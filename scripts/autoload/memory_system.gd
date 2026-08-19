extends Node
## 记忆系统：短期记忆添加/衰减/遗忘，按重要度与时效检索，生成记忆摘要文本。
## 设计意图：模拟认知——只有与当前情境相关且重要的记忆才会进入LLM上下文。

var memory_counter := 0

func add_memory(character, content: String, importance: float = 0.5, emotion: String = "", tags: Array = [], type: String = "episodic") -> void:
	if character == null or not is_instance_valid(character) or character.character_data == null:
		return
	if content.strip_edges() == "":
		return
	var mem := MemoryEntry.new()
	mem.id = "mem_%d" % memory_counter
	memory_counter += 1
	mem.timestamp = int(TimeManager.game_time)
	mem.location = character.global_position
	mem.content = content
	mem.importance = clampf(importance, 0.0, 1.0)
	mem.emotion = emotion
	mem.tags = tags
	mem.type = type
	character.character_data.memories.append(mem)
	_trim(character)

func _trim(character) -> void:
	var max_short := int(ConfigManager.game_setting("memory_size", 20))
	var mems: Array = character.character_data.memories
	if mems.size() <= max_short + 10:
		return
	mems.sort_custom(func(a, b): return a.importance > b.importance)
	while mems.size() > max_short:
		mems.pop_back()

func retrieve_top(character, context_tags: Array = [], count: int = 5) -> Array:
	if character == null or character.character_data == null:
		return []
	var scored: Array = []
	for mem in character.character_data.memories:
		var score: float = float(mem.importance) * 0.6 + _recency_score(mem) * 0.35
		for tag in context_tags:
			if mem.tags.has(tag):
				score += 0.1
		scored.append({"mem": mem, "score": score})
	scored.sort_custom(func(a, b): return a.score > b.score)
	var out: Array = []
	for i in mini(count, scored.size()):
		out.append(scored[i].mem)
	return out

func _recency_score(mem: MemoryEntry) -> float:
	var age := maxf(1.0, float(TimeManager.game_time - mem.timestamp))
	return clampf(1.0 / age, 0.0, 1.0)

func memory_text(character, count: int = 5) -> String:
	var mems := retrieve_top(character, [], count)
	var lines: Array[String] = []
	for m in mems:
		lines.append("- [%s] %s" % [m.type, m.content])
	if lines.is_empty():
		return "（暂无深刻记忆）"
	return "\n".join(lines)

func decay(character, delta_hours: float) -> void:
	if character == null or character.character_data == null:
		return
	var mems: Array = character.character_data.memories
	for mem in mems:
		if mem.type == "episodic":
			mem.importance = maxf(0.0, mem.importance - 0.004 * delta_hours)
	# 遗忘：极低重要度的短期记忆
	var kept: Array = []
	for mem in mems:
		if mem.type != "episodic" or mem.importance >= 0.02:
			kept.append(mem)
	character.character_data.memories = kept
