class_name OllamaProvider
extends LLMProvider
## Ollama 本地 Provider：无需API Key，连接本地 /api/chat。

func is_available() -> bool:
	return base_url != ""

func build_chat_url() -> String:
	return base_url.trim_suffix("/") + "/api/chat"

func build_payload(prompt: String) -> Dictionary:
	return {
		"model": model,
		"messages": [{"role": "user", "content": prompt}],
		"stream": false,
		"options": {
			"temperature": temperature,
			"num_predict": max_tokens
		}
	}

func parse_response(body: String) -> String:
	var parsed = JSON.parse_string(body)
	if parsed is Dictionary:
		var msg = parsed.get("message", {})
		return str(msg.get("content", ""))
	return ""
