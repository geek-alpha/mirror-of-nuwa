class_name LLMProvider
extends RefCounted
## LLM Provider 抽象基类：所有Provider实现统一的聊天接口。
## 子类只需实现 build_chat_url / build_payload / parse_response。

var base_url: String = ""
var api_key: String = ""
var model: String = ""
var temperature: float = 0.8
var max_tokens: int = 500

func _init(settings: Dictionary = {}) -> void:
	base_url = str(settings.get("base_url", ""))
	api_key = str(settings.get("api_key", ""))
	model = str(settings.get("model", ""))
	temperature = float(settings.get("temperature", 0.8))
	max_tokens = int(settings.get("max_tokens", 500))

func is_available() -> bool:
	return false

func build_chat_url() -> String:
	return ""

func build_payload(_prompt: String) -> Dictionary:
	return {}

func parse_response(_body: String) -> String:
	return ""
