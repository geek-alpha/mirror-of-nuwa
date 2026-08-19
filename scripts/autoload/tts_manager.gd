extends Node
## 语音管理器：连接本地语音服务（Edge TTS / GPT-SoVITS），维护可用声音池与语音播放队列。
## 职责：
##   - 自动启动/探测 tools/tts_server.py（需要 Python + edge-tts / gradio-client）；
##   - 拉取声音池（/voices：Edge 中文声音 + GPT-SoVITS 角色）供用户选择；
##   - 请求 /tts 合成语音，按文本缓存，排队无间隙播放。

signal voices_loaded(voices: Array)

const DEFAULT_SERVER_URL := "http://127.0.0.1:17820"
const DEFAULT_VOICE := "zh-CN-YunxiNeural"
const PROVIDER_EDGE := "edge"
const PROVIDER_SOVITS := "sovits"
const SERVER_VERSION := 2
const MAX_PENDING := 16
const MAX_QUEUE := 48
const LISTEN_RADIUS := 10.0
## 语音合成的最小分句长度：低于该长度的碎片（如“你好。”或孤立的引号）
## 会与后续内容合并成自然长度的整句，避免语音与字幕被切得太碎。
const MIN_SENTENCE_LEN := 14

var enabled := true
var server_url := DEFAULT_SERVER_URL
var voices: Array = []
var enabled_voices: Array = []
var current_voice := DEFAULT_VOICE
var provider := PROVIDER_EDGE
var rate := "+20%"
var volume := "+0%"
var pace := 1.0
var status_text := "语音：未连接"
var server_online := false

var _audio_cache: Dictionary = {}
var _play_queue: Array = []
var _speaker_pending: Dictionary = {}
var _current_speaker = null
var _pending := 0
var _playing := false
var _player: AudioStreamPlayer = null
var _starting := false

func _ready() -> void:
	enabled = ConfigManager.tts_enabled()
	server_url = ConfigManager.tts_server_url()
	provider = ConfigManager.tts_provider()
	rate = ConfigManager.tts_rate()
	volume = ConfigManager.tts_volume()
	enabled_voices = ConfigManager.tts_voices()
	var saved_voice := ConfigManager.tts_voice()
	if saved_voice != "":
		current_voice = saved_voice
	_player = AudioStreamPlayer.new()
	_player.name = "TTSSpeaker"
	add_child(_player)
	if enabled:
		_start_later()

func _exit_tree() -> void:
	# 退出前停止播放，避免播放线程阻塞进程退出
	if _player != null:
		_player.stop()
	_play_queue.clear()
	_audio_cache.clear()

func _start_later() -> void:
	# 等主循环就绪后再探测/启动服务（autoload _ready 阶段 HTTPRequest 尚未运转）
	await get_tree().create_timer(0.5).timeout
	if enabled:
		_start_server_if_needed()

func speak(text: String, voice: String = "", speaker: Node3D = null, priority := false, force := false) -> void:
	## 生成并播放语音：长文本按句拆分流式生成（一小句一小句，边合成边播）。
	## 相同文本会命中缓存，立即播放。
	## 默认仅当说话角色位于玩家（附身角色/上帝相机）10 米内时才生成与播报；
	## force=true 时跳过距离限制（用于剧情旁白/画外音，始终可闻）。
	if not enabled or not server_online or text.strip_edges() == "":
		return
	if not force and (speaker == null or not is_near_player(speaker)):
		return
	var sentences := split_sentences(text)
	if sentences.size() <= 1:
		_speak_sentence(text, voice, priority, speaker)
		return
	_speak_streamed(sentences, voice, priority, speaker)

func set_pace(p: float) -> void:
	## 综合速度：同步影响语音合成速率（配合逐字文字节奏）
	pace = clampf(p, 0.5, 2.0)
	rate = "+%d%%" % int(round(20.0 + (pace - 1.0) * 25.0))

func prefetch(text: String, voice: String = "") -> void:
	## 预取：提前合成下一句并入缓存（不播放），当前句播完即可无缝衔接
	if not enabled or not server_online or text.strip_edges() == "":
		return
	var v := voice if voice != "" else current_voice
	var key := _cache_key(v, text)
	if _audio_cache.has(key):
		return
	if _pending >= MAX_PENDING:
		return
	_pending += 1
	_request_tts(key, text, v, _provider_for(v), false, Callable(), Callable(), null, true)

func split_sentences(text: String) -> PackedStringArray:
	## 按句拆分流式合成：在句号/问号/叹号/分号处切开，但过短的碎片
	## 会与后续内容合并成自然长度的整句；段落（换行）之间不跨行合并。
	var out := PackedStringArray()
	for paragraph in text.split("\n", false):
		var acc := ""
		for s in _split_at_enders(paragraph):
			acc += s
			if acc.length() >= MIN_SENTENCE_LEN:
				out.append(acc.strip_edges())
				acc = ""
		acc = acc.strip_edges()
		if acc != "":
			out.append(acc)
	return out

## 仅按句末标点切分，不做长度合并（供 split_sentences 内部使用）
func _split_at_enders(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var buf := ""
	for ch in text:
		buf += ch
		if ch in "。！？!?；;":
			var s := buf.strip_edges()
			if s != "":
				out.append(s)
			buf = ""
	var rest := buf.strip_edges()
	if rest != "":
		out.append(rest)
	return out

func _speak_sentence(text: String, voice: String, priority: bool, speaker = null) -> void:
	_await_slot()
	var v := voice if voice != "" else current_voice
	var key := _cache_key(v, text)
	if _audio_cache.has(key):
		_enqueue(_audio_cache[key], priority, speaker)
		return
	_pending += 1
	_request_tts(key, text, v, _provider_for(v), priority, Callable(), Callable(), speaker)

func _await_slot() -> void:
	## 等待一个可用的并发/队列位，避免语音被静默丢弃
	while _pending >= MAX_PENDING or _play_queue.size() >= MAX_QUEUE:
		await get_tree().create_timer(0.15).timeout
		if not enabled or not server_online:
			return

var _stream_seq := 0
var _stream_buffers: Dictionary = {}

## 按句流式：同时发起多句合成请求，按语序缓冲后依次播放
func _speak_streamed(sentences: PackedStringArray, voice: String, priority: bool, speaker = null) -> void:
	var v := voice if voice != "" else current_voice
	var call_id := _stream_seq
	_stream_seq += 1
	_stream_buffers[call_id] = {"next": 0, "count": sentences.size(), "buf": {}}
	for i in sentences.size():
		var key := _cache_key(v, sentences[i])
		if _audio_cache.has(key):
			_enqueue_streamed(call_id, i, _audio_cache[key], priority, speaker)
			continue
		_await_slot()
		if not enabled or not server_online:
			return
		_pending += 1
		_request_tts(
			key, sentences[i], v, _provider_for(v), priority,
			func(stream: AudioStream) -> void:
				_enqueue_streamed(call_id, i, stream, priority, speaker),
			func() -> void:
				# 单句合成失败：占位跳过，不让整段卡死
				_enqueue_streamed(call_id, i, null, priority, speaker)
		)

func _enqueue_streamed(call_id: int, index: int, stream, priority: bool, speaker = null) -> void:
	var entry: Dictionary = _stream_buffers.get(call_id, {})
	if entry.is_empty():
		return
	var buf: Dictionary = entry["buf"]
	buf[index] = stream
	while buf.has(entry["next"]):
		var st = buf[entry["next"]]
		buf.erase(entry["next"])
		entry["next"] = int(entry["next"]) + 1
		if st != null:
			# 流式分句严格按语序追加，保证整句顺序
			_enqueue(st, false, speaker)
	if int(entry["next"]) >= int(entry["count"]) and buf.is_empty():
		_stream_buffers.erase(call_id)

func random_voice() -> String:
	## 从玩家启用的声音池随机分配；池子为空时回退到当前提供方的第一个声音。
	var pool := _active_voice_pool()
	if not pool.is_empty():
		return _voice_id(pool[randi() % pool.size()])
	var provider_pool := _provider_pool()
	if not provider_pool.is_empty():
		return _voice_id(provider_pool[0])
	return current_voice

func set_enabled_voices(list: Array) -> void:
	enabled_voices = list.duplicate()
	var settings := _config_settings()
	settings["voices"] = enabled_voices
	ConfigManager.save_tts_settings(settings)

func is_voice_enabled(voice: String) -> bool:
	return enabled_voices.is_empty() or enabled_voices.has(voice)

func active_voice_count() -> int:
	return _provider_pool().size()

func provider_voices() -> Array:
	## 当前全局提供方下的声音条目（供 UI 展示；完整列表见 voices）
	return _provider_pool()

func _active_voice_pool() -> Array:
	var pool := _provider_pool()
	if enabled_voices.is_empty():
		return pool
	var out: Array = []
	for v in pool:
		if enabled_voices.has(_voice_id(v)):
			out.append(v)
	return out

func _provider_pool() -> Array:
	## 当前全局提供方下的声音条目（用于随机分配与界面展示）
	var out: Array = []
	for v in voices:
		if v is Dictionary:
			if str(v.get("provider", PROVIDER_EDGE)) == provider:
				out.append(v)
		elif provider == PROVIDER_EDGE:
			out.append(v)
	return out

func _voice_id(entry) -> String:
	## 声音条目统一取 id：兼容新版 {id,name,provider} 与旧版纯字符串
	if entry is Dictionary:
		return str(entry.get("id", entry.get("name", "")))
	return str(entry)

func _provider_for(voice_id: String) -> String:
	## 解析声音所属的合成提供方；纯字符串（旧保存值）按当前全局 provider 处理
	for v in voices:
		if _voice_id(v) == voice_id:
			if v is Dictionary and str(v.get("provider", "")) == PROVIDER_SOVITS:
				return PROVIDER_SOVITS
			return PROVIDER_EDGE
	return provider

func _cache_key(voice_id: String, text: String) -> String:
	return "%s|%s|%s|%s" % [_provider_for(voice_id), voice_id, rate, text]

func is_near_player(node: Node3D) -> bool:
	## 判断节点是否在玩家（附身角色/上帝相机）10 米范围内。
	var listener: Node3D = null
	if GameState.mode == GameState.Mode.POSSESS:
		listener = GameState.possessed_character
	else:
		listener = PlayerGodController.god_camera
	if listener == null or not is_instance_valid(listener) or not is_instance_valid(node):
		return false
	return node.global_position.distance_to(listener.global_position) <= LISTEN_RADIUS

func refresh_voices() -> void:
	if not server_online:
		status_text = "语音：服务未连接，无法获取声音列表"
		return
	status_text = "语音：正在获取声音列表…"
	_request_voices()

func refresh_voices_with_upgrade() -> void:
	## 刷新声音：检测到旧版服务时明确提示，引导手动重启
	if not server_online:
		# 服务可能已由外部启动，重新探测/拉起一次
		status_text = "语音：服务未连接，正在重新连接…"
		await _start_server_if_needed()
		if not server_online:
			status_text = "语音：服务未连接，无法获取声音列表"
			return
	if not await _server_version_ok():
		status_text = "语音：检测到旧版服务（无 GPT-SoVITS），请重启服务：python tools/tts_server.py 或运行 restart_tts_server.bat"
		return
	_request_voices()

func set_enabled(on: bool) -> void:
	enabled = on
	var settings := _config_settings()
	settings["enabled"] = on
	ConfigManager.save_tts_settings(settings)
	if on and not server_online:
		_start_server_if_needed()

func set_voice(name: String) -> void:
	if name == "" or not _voice_known(name):
		return
	current_voice = name
	var settings := _config_settings()
	settings["voice"] = name
	ConfigManager.save_tts_settings(settings)

func set_provider(p: String) -> void:
	## 切换全局语音提供方（edge / sovits），刷新声音池并持久化
	if p != PROVIDER_EDGE and p != PROVIDER_SOVITS:
		return
	if provider == p:
		return
	provider = p
	var settings := _config_settings()
	settings["provider"] = provider
	ConfigManager.save_tts_settings(settings)
	clear_cache()
	# 旧提供方下分配的角色声线不再适用，重置后下次说话按新提供方重新分配
	enabled_voices.clear()
	current_voice = ""
	EventBus.tts_provider_changed.emit(provider)
	if server_online:
		refresh_voices()
	else:
		status_text = "语音：服务未连接，无法获取声音列表"
	_reset_character_voices()

func _reset_character_voices() -> void:
	## 让所有角色/旁白声线跟随新的全局提供方（AI 角色惰性重分配）
	if CharacterManager == null:
		return
	for c in CharacterManager.all_characters():
		if c != null and is_instance_valid(c) and "voice_name" in c:
			c.set("voice_name", "")

func set_server_url(url: String) -> void:
	if url.strip_edges() == "":
		return
	server_url = url.strip_edges()
	var settings := _config_settings()
	settings["server_url"] = server_url
	ConfigManager.save_tts_settings(settings)
	server_online = false
	status_text = "语音：已切换服务地址，重新连接中…"
	_start_server_if_needed()

func clear_cache() -> void:
	_audio_cache.clear()

func _config_settings() -> Dictionary:
	return {
		"enabled": enabled,
		"voice": current_voice,
		"provider": provider,
		"server_url": server_url,
		"rate": rate,
		"volume": volume,
		"voices": enabled_voices
	}

# ---------- 服务探测与启动 ----------

func _start_server_if_needed() -> void:
	if _starting:
		return
	_starting = true
	if await _ping(5.0):
		_on_server_online()
		_starting = false
		return
	var script_path := ProjectSettings.globalize_path("res://tools/tts_server.py")
	if not FileAccess.file_exists(script_path):
		status_text = "语音：未找到 tools/tts_server.py"
		_starting = false
		return
	var launched := false
	for py in _find_python_candidates():
		var err := OS.create_process(py, [script_path, "--port", "17820"])
		if err == OK:
			launched = true
			break
	if not launched:
		status_text = "语音：无法启动服务（请安装 Python 与 edge-tts，或手动运行 python tools/tts_server.py）"
		_starting = false
		return
	status_text = "语音：正在启动服务…"
	for i in 20:
		await get_tree().create_timer(0.5).timeout
		if await _ping(5.0):
			_on_server_online()
			_starting = false
			return
	status_text = "语音：服务启动超时（可手动运行 python tools/tts_server.py）"
	_starting = false

func _server_version_ok() -> bool:
	## 新版服务提供 /version；旧版会 404，视为需要升级
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 5.0
	var err := http.request(server_url + "/version")
	if err != OK:
		http.queue_free()
		return false
	var res: Array = await http.request_completed
	http.queue_free()
	if res.size() < 4 or res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return false
	var parsed = JSON.parse_string(res[3].get_string_from_utf8())
	return parsed is Dictionary and int(parsed.get("version", 0)) >= SERVER_VERSION

func _find_python_candidates() -> Array:
	## Windows 上 OS.create_process 不搜索 PATH，需返回候选的绝对路径。
	var out: Array = []
	if OS.get_name() != "Windows":
		return ["python3", "python"]
	var path_env := OS.get_environment("PATH")
	for dir_path in path_env.split(";"):
		var dir_clean := dir_path.strip_edges()
		if dir_clean == "":
			continue
		var exe := dir_clean.trim_suffix("\\") + "\\python.exe"
		if FileAccess.file_exists(exe) and not out.has(exe):
			out.append(exe)
	out.append("python")
	out.append("py")
	return out

func _on_server_online() -> void:
	server_online = true
	status_text = "语音：服务在线"
	refresh_voices()

func _ping(timeout: float) -> bool:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = timeout
	var err := http.request(server_url + "/health")
	if err != OK:
		http.queue_free()
		return false
	var res: Array = await http.request_completed
	http.queue_free()
	return res.size() >= 2 and res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200

# ---------- HTTP 请求 ----------

func _request_voices() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 10.0
	var err := http.request(server_url + "/voices")
	if err != OK:
		http.queue_free()
		status_text = "语音：获取声音列表失败"
		return
	var res: Array = await http.request_completed
	http.queue_free()
	if res.size() < 4 or res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		status_text = "语音：获取声音列表失败（%s）" % _http_error_text(res)
		return
	var parsed = JSON.parse_string(res[3].get_string_from_utf8())
	if parsed is Dictionary and parsed.get("voices") is Array:
		voices = _normalize_voices(parsed["voices"])
		if current_voice == "" or not _voice_known(current_voice):
			var first := _first_active_voice()
			if first != "":
				current_voice = first
			var settings := _config_settings()
			settings["voice"] = current_voice
			ConfigManager.save_tts_settings(settings)
		var provider_count := _provider_pool().size()
		status_text = "语音：服务在线（%s，启用 %d/%d 个声音）" % [_provider_label(provider), active_voice_count(), provider_count]
		voices_loaded.emit(voices)
	else:
		status_text = "语音：声音列表格式异常"

func _normalize_voices(raw: Array) -> Array:
	## 统一声音条目为 {id, name, provider}；旧服务器返回纯字符串时视为 Edge 声音
	var out: Array = []
	for entry in raw:
		if entry is Dictionary:
			var v_id := str(entry.get("id", entry.get("name", "")))
			if v_id == "":
				continue
			out.append({
				"id": v_id,
				"name": str(entry.get("name", v_id)),
				"provider": str(entry.get("provider", PROVIDER_EDGE))
			})
		else:
			var v_id2 := str(entry)
			if v_id2 != "":
				out.append({"id": v_id2, "name": v_id2, "provider": PROVIDER_EDGE})
	return out

func _voice_known(voice_id: String) -> bool:
	for v in voices:
		if _voice_id(v) == voice_id:
			return true
	return false

func _first_active_voice() -> String:
	## 默认声线只从当前提供方的声音池取，避免切到 GPT-SoVITS 后仍拿到旧 Edge 声音
	for v in _provider_pool():
		if _voice_id(v) != "":
			return _voice_id(v)
	return ""

func _provider_label(p: String) -> String:
	return "GPT-SoVITS" if p == PROVIDER_SOVITS else "Edge TTS"

func _request_tts(key: String, text: String, voice: String, voice_provider: String, priority := false, on_ready := Callable(), on_fail := Callable(), speaker = null, cache_only := false) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 30.0
	var body: String = JSON.stringify({
		"text": text,
		"voice": voice,
		"provider": voice_provider,
		"rate": rate,
		"volume": volume
	})
	var err := http.request(
		server_url + "/tts",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		http.queue_free()
		_pending -= 1
		status_text = "语音：请求发送失败"
		if not on_fail.is_null():
			on_fail.call()
		return
	var res: Array = await http.request_completed
	http.queue_free()
	_pending -= 1
	if res.size() < 4 or res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		status_text = "语音：合成失败（%s）" % _http_error_text(res)
		if not on_fail.is_null():
			on_fail.call()
		return
	var content_type := _response_content_type(res)
	var stream: AudioStream = null
	if "x-pcm" in content_type or "wav" in content_type:
		# GPT-SoVITS：手动解析 WAV 头 -> 裸 PCM，构造 AudioStreamWAV
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		var parsed := _parse_wav(res[3])
		if parsed.is_empty():
			status_text = "语音：WAV 解析失败（%s）" % _http_error_text(res)
			if not on_fail.is_null():
				on_fail.call()
			return
		wav.mix_rate = int(parsed["sample_rate"])
		wav.data = parsed["pcm"]
		stream = wav
	else:
		var mp3 := AudioStreamMP3.new()
		mp3.data = res[3]
		stream = mp3
	_audio_cache[key] = stream
	if on_ready.is_null():
		if not cache_only:
			_enqueue(stream, priority, speaker)
	else:
		on_ready.call(stream)

func _response_content_type(res: Array) -> String:
	## Godot 4.x 响应数组为 [result, response_code, headers, body]，防御式读取 Content-Type
	var headers = res[2] if res.size() > 2 else null
	if headers is Dictionary:
		return str(headers.get("Content-Type", headers.get("content-type", ""))).to_lower()
	if headers is Array:
		for h in headers:
			if str(h).to_lower().begins_with("content-type:"):
				return str(h).split(":", false, 1)[1].strip_edges().to_lower()
	return ""

func _response_header(res: Array, name: String, default_value: String) -> String:
	## 从响应头读取指定字段（兼容 PackedStringArray / Array / Dictionary）
	var headers = res[2] if res.size() > 2 else null
	var lower_name := name.to_lower()
	if headers is Dictionary:
		var v = headers.get(name, headers.get(lower_name, ""))
		if v != null and str(v) != "":
			return str(v)
	if headers is Array:
		for h in headers:
			var hs := str(h)
			if hs.to_lower().begins_with(lower_name + ":"):
				return hs.split(":", false, 1)[1].strip_edges()
	return default_value

func _parse_wav(bytes: PackedByteArray) -> Dictionary:
	## 手动解析 WAV 文件头，返回 {sample_rate, channels, pcm}；失败返回空字典。
	## 兼容服务端返回的两种格式：完整 WAV（RIFF 头）或裸 PCM（无头）。
	if bytes.size() < 44:
		return {}
	# Godot slice 是闭区间：[begin, end]，前 4 字节为 0..3
	var is_riff := bytes.slice(0, 3) == "RIFF".to_ascii_buffer()
	if not is_riff:
		# 裸 PCM：无法得知采样率，按 GPT-SoVITS 默认 24000Hz 单声道处理
		return {"sample_rate": 24000, "channels": 1, "pcm": bytes}
	var riff_type := bytes.slice(8, 11)
	if riff_type != "WAVE".to_ascii_buffer():
		return {}
	var fmt_chunk: Dictionary = {}
	var data_chunk: Dictionary = {}
	var pos := 12
	while pos + 8 <= bytes.size():
		var chunk_id := bytes.slice(pos, pos + 3)
		var chunk_size := bytes.decode_u32(pos + 4)
		var chunk_id_str := String(chunk_id.get_string_from_ascii())
		if chunk_id_str == "fmt ":
			fmt_chunk = {"pos": pos + 8, "size": chunk_size}
		elif chunk_id_str == "data":
			data_chunk = {"pos": pos + 8, "size": chunk_size}
			break
		pos += 8 + chunk_size + (chunk_size & 1)
	if fmt_chunk.is_empty() or data_chunk.is_empty():
		return {}
	var fpos := int(fmt_chunk["pos"])
	var audio_format := bytes.decode_u16(fpos)
	var channels := int(bytes.decode_u16(fpos + 2))
	var sample_rate := int(bytes.decode_u32(fpos + 4))
	var bits := int(bytes.decode_u16(fpos + 14))
	if audio_format != 1:  # 只支持 PCM
		return {}
	var pcm := bytes.slice(int(data_chunk["pos"]), int(data_chunk["pos"]) + int(data_chunk["size"]))
	if bits == 8:
		# 8-bit WAV 是无符号 PCM，AudioStreamWAV 需要有符号 8-bit
		var signed := PackedByteArray()
		signed.resize(pcm.size())
		for i in pcm.size():
			signed[i] = pcm[i] - 128
		pcm = signed
	return {"sample_rate": sample_rate, "channels": channels, "pcm": pcm}

func _http_error_text(res: Array) -> String:
	if res.is_empty():
		return "无响应"
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return "连接失败（%d）" % res[0]
	if res.size() >= 4:
		var body: String = res[3].get_string_from_utf8().left(120)
		return "HTTP %d %s" % [res[1], body]
	return "HTTP %d" % res[1]

# ---------- 播放队列 ----------

func _enqueue(stream: AudioStream, priority := false, speaker = null) -> void:
	var item := {"stream": stream, "speaker": speaker}
	if priority:
		_play_queue.push_front(item)
	else:
		_play_queue.append(item)
	if _play_queue.size() > MAX_QUEUE:
		if priority:
			_drop_item(_play_queue.pop_back())
		else:
			_drop_item(_play_queue.pop_front())
	if speaker != null and is_instance_valid(speaker):
		var sid: int = speaker.get_instance_id()
		_speaker_pending[sid] = int(_speaker_pending.get(sid, 0)) + 1
	_pump()

func _drop_item(item: Dictionary) -> void:
	## 队列溢出被丢弃的语音也要释放“正在发声”计数，避免气泡卡住
	var sp = item.get("speaker", null)
	if sp != null and is_instance_valid(sp):
		var sid: int = sp.get_instance_id()
		var left := int(_speaker_pending.get(sid, 0)) - 1
		if left <= 0:
			_speaker_pending.erase(sid)
		else:
			_speaker_pending[sid] = left

func _pump() -> void:
	if _playing or _play_queue.is_empty() or _player == null:
		return
	var item: Dictionary = _play_queue.pop_front()
	var stream: AudioStream = item["stream"]
	_current_speaker = item.get("speaker", null)
	_player.stream = stream
	_player.play()
	_playing = true
	_player.finished.connect(_on_finished.bind(_player), CONNECT_ONE_SHOT)

func _on_finished(_p: AudioStreamPlayer) -> void:
	if _current_speaker != null and is_instance_valid(_current_speaker):
		var sid: int = _current_speaker.get_instance_id()
		var left := int(_speaker_pending.get(sid, 0)) - 1
		if left <= 0:
			_speaker_pending.erase(sid)
		else:
			_speaker_pending[sid] = left
	_current_speaker = null
	_playing = false
	_pump()

func is_speaking_for(character: Node) -> bool:
	## 该角色是否仍有语音在排队/播放（气泡据此保持显示）
	if character == null or not is_instance_valid(character):
		return false
	return int(_speaker_pending.get(character.get_instance_id(), 0)) > 0

func is_voice_busy() -> bool:
	## 是否仍有语音在合成、排队或播放（剧情推进据此等待，避免语音与剧情重叠）
	return _pending > 0 or not _play_queue.is_empty() or _playing
