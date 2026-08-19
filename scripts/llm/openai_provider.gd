class_name OpenAIProvider
extends LLMProvider
## OpenAI 兼容 Provider：适用于 OpenAI、DeepSeek、Kimi 等任何
## 提供 /chat/completions 接口的服务。

func is_available() -> bool:
	return base_url != "" and api_key != "" and model != ""

func build_chat_url() -> String:
	return base_url.trim_suffix("/") + "/chat/completions"

func build_payload(prompt: String) -> Dictionary:
	return {
		"model": model,
		"messages": [
			{"role": "system", "content": "你是《女娲之镜：硅灵文明》游戏引擎中的AI角色大脑。你必须严格按照要求的JSON格式输出，不要输出任何其他文本。"},
			{"role": "user", "content": prompt}
		],
		"temperature": temperature,
		"max_tokens": max_tokens
	}

func parse_response(body: String) -> String:
	var parsed = JSON.parse_string(body)
	if parsed is Dictionary:
		var choices = parsed.get("choices", [])
		if choices is Array and choices.size() > 0:
			var msg = choices[0].get("message", {})
			return str(msg.get("content", ""))
	return ""
