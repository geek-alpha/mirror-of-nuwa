class_name LLMJsonParser
extends RefCounted
## LLM JSON 解析器：从模型输出中提取严格的JSON对象，容忍markdown围栏与多余文本。

static func parse(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {}
	var cleaned := text.strip_edges()
	# 去除 markdown 代码块围栏
	if cleaned.begins_with("```"):
		var lines := cleaned.split("\n")
		lines.remove_at(0)
		if lines.size() > 0 and lines[lines.size() - 1].strip_edges().begins_with("```"):
			lines.remove_at(lines.size() - 1)
		cleaned = "\n".join(lines)
	var start := cleaned.find("{")
	var end := cleaned.rfind("}")
	if start == -1 or end == -1 or end < start:
		return {}
	cleaned = cleaned.substr(start, end - start + 1)
	var parsed = JSON.parse_string(cleaned)
	if parsed is Dictionary:
		return parsed
	return {}
