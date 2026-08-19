extends Node
## 关系系统：角色间亲密度/信任度随互动变化，输出关系摘要文本。

func get_relationship(character, target_id: String) -> RelationshipEntry:
	if character == null or character.character_data == null:
		return RelationshipEntry.new()
	var rels: Dictionary = character.character_data.relationships
	if not rels.has(target_id):
		var rel := RelationshipEntry.new()
		rel.target_id = target_id
		rels[target_id] = rel
	return rels[target_id]

func update_relationship(character, target_id: String, change: float, reason: String = "") -> void:
	if character == null or character.character_data == null or target_id == "" or target_id == character.character_data.id:
		return
	var rel := get_relationship(character, target_id)
	rel.affinity = clampf(rel.affinity + change, -100.0, 100.0)
	rel.trust = clampf(rel.trust + change * 0.5, -100.0, 100.0)
	rel.last_interaction_hour = TimeManager.game_time
	if reason != "":
		rel.history.append("%s（第%d天）" % [reason, TimeManager.get_day()])
	# 双向影响：对方对你的态度变化略弱
	var other = CharacterManager.get_character(target_id)
	if other != null and other.alive and other.character_data != null:
		var rel2 := get_relationship(other, character.character_data.id)
		rel2.affinity = clampf(rel2.affinity + change * 0.7, -100.0, 100.0)
		rel2.trust = clampf(rel2.trust + change * 0.35, -100.0, 100.0)
		rel2.last_interaction_hour = TimeManager.game_time

func attitude_text(character, target_id: String) -> String:
	var affinity := get_relationship(character, target_id).affinity
	if affinity > 50.0:
		return "挚友"
	if affinity > 20.0:
		return "友好"
	if affinity > -20.0:
		return "中立"
	if affinity > -60.0:
		return "冷淡"
	return "敌视"

func relationship_text(character, max_count: int = 6) -> String:
	if character == null or character.character_data == null:
		return "（无）"
	var rels: Dictionary = character.character_data.relationships
	if rels.is_empty():
		return "（尚未建立深刻关系）"
	var entries: Array = []
	for target_id in rels:
		var rel: RelationshipEntry = rels[target_id]
		var other = CharacterManager.get_character(str(target_id))
		var name := str(target_id)
		if other != null and other.character_data != null:
			name = other.character_data.name
		entries.append({"id": target_id, "name": name, "affinity": rel.affinity})
	entries.sort_custom(func(a, b): return absf(a.affinity) > absf(b.affinity))
	var lines: Array[String] = []
	for i in mini(max_count, entries.size()):
		var e: Dictionary = entries[i]
		lines.append("%s：%s（%.0f）" % [e.name, attitude_text(character, e.id), e.affinity])
	return "\n".join(lines)
