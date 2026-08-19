extends Node
## LLM服务：全局请求队列、缓存、重试与Provider管理。
## 设计意图：避免API过载；按角色重要性排序（当前FIFO+间隔）；离线时自动降级。

signal response_received(character_id: String, result: Dictionary)
signal request_failed(character_id: String, error: String)

var provider: LLMProvider = null
var request_queue: Array = []
var processing := false
var cache: Dictionary = {}
var http_pool: Array = []
var status_text := "离线规则AI"
var _provider_backoff_until := 0
var last_error := ""
var ever_connected := false

const REQUEST_TIMEOUT := 30.0
const TEST_TIMEOUT := 10.0
const DIALOGUE_TIMEOUT := 8.0

func _ready() -> void:
	reload_provider()

func reload_provider() -> void:
	var provider_name := ConfigManager.llm_provider()
	var settings := {
		"base_url": ConfigManager.llm_base_url(),
		"api_key": ConfigManager.llm_api_key(),
		"model": ConfigManager.llm_model(),
		"temperature": ConfigManager.llm_temperature(),
		"max_tokens": ConfigManager.llm_max_tokens()
	}
	match provider_name:
		"openai":
			provider = OpenAIProvider.new(settings)
		"ollama":
			provider = OllamaProvider.new(settings)
		_:
			provider = LLMProvider.new(settings)
	var available := is_available()
	last_error = ""
	ever_connected = false
	if available:
		status_text = "%s | %s | 已配置（等待首次连接）" % [provider_name, settings.model]
	else:
		status_text = "%s | %s | 未启用或未配置" % [provider_name, settings.model]
	EventBus.llm_status_changed.emit(available, provider_name, str(settings.model))

func is_available() -> bool:
	if Time.get_ticks_msec() < _provider_backoff_until:
		return false
	return ConfigManager.llm_enabled() and provider != null and provider.is_available()

func request_decision(character_id: String, prompt_data: Dictionary, callback: Callable = Callable()) -> void:
	_enqueue_request({
		"character_id": character_id,
		"prompt": str(prompt_data.get("prompt", "")),
		"kind": "decision",
		"callback": callback
	}, false)

func request_dialogue(character_id: String, prompt: String, callback: Callable = Callable()) -> void:
	# 对话是玩家交互，优先于角色决策，避免被队列里的决策请求拖慢
	_enqueue_request({
		"character_id": character_id,
		"prompt": prompt,
		"kind": "dialogue",
		"callback": callback
	}, true)

func request_oracle(character_id: String, prompt: String, callback: Callable = Callable()) -> void:
	_enqueue_request({
		"character_id": character_id,
		"prompt": prompt,
		"kind": "oracle",
		"callback": callback
	}, true)

func request_reflection(character_id: String, prompt: String, callback: Callable = Callable()) -> void:
	_enqueue_request({
		"character_id": character_id,
		"prompt": prompt,
		"kind": "reflection",
		"callback": callback
	}, false)

func _enqueue_request(req: Dictionary, priority: bool) -> void:
	req["timeout"] = DIALOGUE_TIMEOUT if priority else REQUEST_TIMEOUT
	if priority:
		request_queue.push_front(req)
	else:
		request_queue.append(req)
	_pump()

func _pump() -> void:
	if processing:
		return
	processing = true
	_process_queue()

func _process_queue() -> void:
	while request_queue.size() > 0:
		if not is_available():
			# 离线降级：清空队列并通知回调（空结果=使用规则AI）
			for req in request_queue:
				var cb: Callable = req.get("callback", Callable())
				if cb.is_valid():
					cb.call({})
			request_queue.clear()
			break
		var req: Dictionary = request_queue.pop_front()
		var character_id := str(req.get("character_id", ""))
		var prompt := str(req.get("prompt", ""))
		var cache_key := "%s|%d" % [character_id, prompt.hash()]
		if cache.has(cache_key) and Time.get_ticks_msec() / 1000.0 - float(cache[cache_key].get("time", 0.0)) < ConfigManager.llm_cache_ttl():
			_handle_result(req, cache[cache_key].result)
			continue
		var result: Dictionary = await _send_request(prompt, float(req.get("timeout", REQUEST_TIMEOUT)))
		if result.has("content"):
			ever_connected = true
			last_error = ""
			status_text = _status_text(true)
			cache[cache_key] = {"time": Time.get_ticks_msec() / 1000.0, "result": result}
			_handle_result(req, result)
		else:
			# 连续失败时冷却 Provider，避免对不可达服务反复请求
			_provider_backoff_until = Time.get_ticks_msec() + 5000
			last_error = str(result.get("error", "未知错误"))
			status_text = _status_text(false)
			request_failed.emit(character_id, last_error)
			var cb: Callable = req.get("callback", Callable())
			if cb.is_valid():
				cb.call({})
		await get_tree().create_timer(float(ConfigManager.llm_request_interval_ms()) / 1000.0).timeout
	processing = false

func _status_text(online: bool) -> String:
	var provider_name := ConfigManager.llm_provider()
	var model := ConfigManager.llm_model()
	if online:
		return "%s | %s | 在线" % [provider_name, model]
	if last_error != "":
		return "%s | %s | 连接失败：%s" % [provider_name, model, last_error]
	return "%s | %s | 离线/未配置" % [provider_name, model]

func test_connection() -> Dictionary:
	## 向配置的 API 发送一条最小请求，验证连通性与模型可用性。
	if provider == null:
		return {"ok": false, "message": "Provider 未初始化"}
	if not ConfigManager.llm_enabled():
		return {"ok": false, "message": "LLM 未启用：请先在设置中勾选“启用 LLM 驱动角色”"}
	if ConfigManager.llm_model() == "":
		return {"ok": false, "message": "模型名为空，请填写模型名"}
	var result: Dictionary = await _send_request("请只回复两个字：成功。", TEST_TIMEOUT)
	if result.has("content"):
		ever_connected = true
		last_error = ""
		status_text = _status_text(true)
		return {"ok": true, "message": "连接成功：%s" % str(result.get("content", "")).left(60)}
	var err_msg := str(result.get("error", "连接失败"))
	last_error = err_msg
	status_text = _status_text(false)
	return {"ok": false, "message": err_msg}

func _handle_result(req: Dictionary, raw_result: Dictionary) -> void:
	var character_id := str(req.get("character_id", ""))
	var content := str(raw_result.get("content", ""))
	var parsed := LLMJsonParser.parse(content)
	if parsed.is_empty():
		var kind := str(req.get("kind", ""))
		if content.strip_edges() != "" and (kind == "dialogue" or kind == "oracle"):
			# 对话/神谕类请求：模型输出自然语言而非JSON时，直接把原文当作回复，
			# 避免答非所问或把有效的回应丢弃。
			parsed = {"dialogue": content.strip_edges()}
		else:
			request_failed.emit(character_id, "JSON解析失败，降级为规则AI")
			var cb: Callable = req.get("callback", Callable())
			if cb.is_valid():
				cb.call({})
			return
	response_received.emit(character_id, parsed)
	var cb: Callable = req.get("callback", Callable())
	if cb.is_valid():
		cb.call(parsed)

func _send_request(prompt: String, timeout_sec: float = REQUEST_TIMEOUT) -> Dictionary:
	if provider == null:
		return {"error": "Provider 未初始化"}
	var http := _get_http()
	http.timeout = timeout_sec
	var err := http.request(
		provider.build_chat_url(),
		_build_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify(provider.build_payload(prompt))
	)
	if err != OK:
		_release_http(http)
		return {"error": "HTTP 请求启动失败（%s）" % error_string(err)}
	var result: Array = await http.request_completed
	_release_http(http)
	if result.is_empty():
		return {"error": "请求无响应"}
	var res: int = result[0]
	var code: int = result[1]
	var body: PackedByteArray = result[3]
	if res != HTTPRequest.RESULT_SUCCESS:
		return {"error": "请求失败（%s）" % _http_result_text(res)}
	if code < 200 or code >= 300:
		var detail := body.get_string_from_utf8().left(200)
		push_warning("LLM HTTP %d: %s" % [code, detail])
		return {"error": "HTTP %d %s" % [code, detail]}
	var content := provider.parse_response(body.get_string_from_utf8())
	if content.strip_edges() == "":
		return {"error": "响应解析为空（格式可能不兼容）"}
	return {"content": content}

func _http_result_text(res: int) -> String:
	if res >= 13:
		return "连接中断或超时（%d）" % res
	match res:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "无法连接到服务器（请检查 Base URL 与本地服务是否启动）"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "无法解析域名（请检查 Base URL）"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "连接中断或超时"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "服务器无响应（超时）"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS/SSL 握手失败（https 证书问题）"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "请求失败（服务器无响应或超时）"
	return "请求错误（%d）" % res

func _build_headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if provider is OpenAIProvider and provider.api_key != "":
		headers.append("Authorization: Bearer %s" % provider.api_key)
	return headers

func _get_http() -> HTTPRequest:
	if http_pool.size() > 0:
		return http_pool.pop_back()
	var http := HTTPRequest.new()
	add_child(http)
	return http

func _release_http(http: HTTPRequest) -> void:
	http_pool.append(http)

func clear_cache() -> void:
	cache.clear()
