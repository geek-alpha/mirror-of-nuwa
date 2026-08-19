extends Node
## 配置管理器：读取根目录 config.json，并合并用户运行时设置（user://llm_settings.json）。
## 支持环境变量覆盖：OPENAI_API_KEY / OLLAMA_HOST。

var config: Dictionary = {}
var llm_settings: Dictionary = {}
var user_settings_path := "user://llm_settings.json"
var tts_settings: Dictionary = {}
var tts_settings_path := "user://tts_settings.json"
var game_settings_path := "user://game_settings.json"
## 剧情排片表（玩家/各纪元角色的形象与声音安排），跨会话保留
var story_casting_path := "user://story_casting.json"
var story_casting_data: Dictionary = {}
var loaded := false

func _ready() -> void:
	load_config()

func load_config() -> void:
	config = _default_config()
	var file := FileAccess.open("res://config.json", FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			for key in parsed:
				config[key] = parsed[key]
		file.close()
	# 合并用户运行时覆盖
	var uf := FileAccess.open(user_settings_path, FileAccess.READ)
	if uf:
		var parsed = JSON.parse_string(uf.get_as_text())
		if parsed is Dictionary:
			llm_settings = parsed
		uf.close()
	# 合并用户语音设置
	var tf := FileAccess.open(tts_settings_path, FileAccess.READ)
	if tf:
		var parsed = JSON.parse_string(tf.get_as_text())
		if parsed is Dictionary:
			tts_settings = parsed
		tf.close()
	# 合并用户全局游戏设置（开局界面写入）
	var gf := FileAccess.open(game_settings_path, FileAccess.READ)
	if gf:
		var parsed = JSON.parse_string(gf.get_as_text())
		if parsed is Dictionary and parsed.has("game"):
			var merged: Dictionary = parsed["game"]
			if not config.has("game"):
				config["game"] = {}
			for key in merged:
				config["game"][key] = merged[key]
		gf.close()
	# 合并剧情排片表（开局界面/剧情菜单写入）
	var cf := FileAccess.open(story_casting_path, FileAccess.READ)
	if cf:
		var parsed = JSON.parse_string(cf.get_as_text())
		if parsed is Dictionary:
			story_casting_data = parsed
		cf.close()
	_update_llm()
	loaded = true

func _default_config() -> Dictionary:
	return {
		"llm": {
			"provider": "openai",
			"api_key": "",
			"base_url": "https://api.siliconflow.cn/v1",
			"model": "Qwen/Qwen3-30B-A3B-Instruct-2507",
			"temperature": 0.8,
			"max_tokens": 500,
			"request_interval_ms": 300,
			"batch_size": 1,
			"cache_ttl_seconds": 60,
			"enabled": true
		},
		"game": {
			"decision_interval_game_hours": 1.0,
			"important_character_decision_interval": 0.25,
			"memory_size": 20,
			"long_term_memory_size": 100,
			"time_scale_default": 1,
			"world_seed": 42,
			"seconds_per_game_hour": 6.0,
			"character_count": 10,
			"autosave_interval_game_days": 1
		}
	}

func _update_llm() -> void:
	if not config.has("llm"):
		config["llm"] = {}
	var llm: Dictionary = config["llm"]
	for key in llm_settings:
		llm[key] = llm_settings[key]
	# 环境变量覆盖（API Key 优先从环境读取，避免明文入库）
	var env_key := OS.get_environment("OPENAI_API_KEY")
	if env_key != "" and str(llm.get("api_key", "")) == "":
		llm["api_key"] = env_key
	var host := OS.get_environment("OLLAMA_HOST")
	if host != "":
		llm["base_url"] = host

func save_llm_settings(settings: Dictionary) -> void:
	llm_settings = settings.duplicate()
	var file := FileAccess.open(user_settings_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(llm_settings, "\t"))
		file.close()
	_update_llm()

## 开局全局配置：写入 user://game_settings.json 并合并进 config["game"]。
func save_game_settings(settings: Dictionary) -> void:
	if not config.has("game"):
		config["game"] = {}
	for key in settings:
		config["game"][key] = settings[key]
	var file := FileAccess.open(game_settings_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"game": config["game"]}, "\t"))
		file.close()

func set_game_setting(key: String, value) -> void:
	if not config.has("game"):
		config["game"] = {}
	config["game"][key] = value

## 剧情排片表：读取用户级排片（形象/声音），新开剧情时作为默认安排。
func story_casting() -> Dictionary:
	return story_casting_data

func save_story_casting(data: Dictionary) -> void:
	story_casting_data = data.duplicate(true)
	var file := FileAccess.open(story_casting_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(story_casting_data, "\t"))
		file.close()

# ---- 语音（TTS）设置 ----
func save_tts_settings(settings: Dictionary) -> void:
	tts_settings = settings.duplicate()
	var file := FileAccess.open(tts_settings_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(tts_settings, "\t"))
		file.close()

func tts_enabled() -> bool:
	return bool(tts_settings.get("enabled", true))

func tts_voice() -> String:
	return str(tts_settings.get("voice", ""))

func tts_provider() -> String:
	## 语音合成提供方：edge（微软 Edge TTS）或 sovits（本机 GPT-SoVITS）
	var p := str(tts_settings.get("provider", "edge"))
	return p if p == "sovits" else "edge"

func tts_voices() -> Array:
	var list = tts_settings.get("voices", [])
	return list if list is Array else []

func tts_server_url() -> String:
	return str(tts_settings.get("server_url", "http://127.0.0.1:17820"))

func tts_rate() -> String:
	return str(tts_settings.get("rate", "+20%"))

func tts_volume() -> String:
	return str(tts_settings.get("volume", "+0%"))

# ---- 便捷访问器 ----
func llm_enabled() -> bool:
	return bool((config.get("llm", {}) as Dictionary).get("enabled", true))

func llm_provider() -> String:
	return str((config.get("llm", {}) as Dictionary).get("provider", "openai"))

func llm_api_key() -> String:
	return str((config.get("llm", {}) as Dictionary).get("api_key", ""))

func llm_base_url() -> String:
	return str((config.get("llm", {}) as Dictionary).get("base_url", "https://api.siliconflow.cn/v1"))

func llm_model() -> String:
	return str((config.get("llm", {}) as Dictionary).get("model", "Qwen/Qwen3-30B-A3B-Instruct-2507"))

func llm_temperature() -> float:
	return float((config.get("llm", {}) as Dictionary).get("temperature", 0.8))

func llm_max_tokens() -> int:
	return int((config.get("llm", {}) as Dictionary).get("max_tokens", 500))

func llm_request_interval_ms() -> int:
	return int((config.get("llm", {}) as Dictionary).get("request_interval_ms", 300))

func llm_cache_ttl() -> float:
	return float((config.get("llm", {}) as Dictionary).get("cache_ttl_seconds", 60))

func game_setting(key: String, default_value = null):
	var game: Dictionary = config.get("game", {})
	return game.get(key, default_value)
