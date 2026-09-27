extends Node
## 感知系统：计算角色视野内的角色/资源/建筑，生成自然语言感知摘要。
## 设计意图：把世界状态翻译成LLM可理解的中文段落，同时兼顾性能（仅查询附近）。

const PERCEPTION_RADIUS := 20.0
const RESOURCE_RADIUS := 14.0

func nearest_character(character) -> AICharacter:
	if character == null:
		return null
	var best: AICharacter = null
	var best_dist := INF
	for c in CharacterManager.all_characters():
		if c == character or not c.alive or c.dying:
			continue
		var d: float = c.global_position.distance_to(character.global_position)
		if d < best_dist:
			best_dist = d
			best = c
	return best

func nearest_resource(character, res_type: String = "") -> ResourceNode:
	if character == null:
		return null
	var best: ResourceNode = null
	var best_dist := INF
	for node in WorldManager.resource_nodes:
		if res_type != "" and node.resource_id != res_type:
			continue
		var d: float = node.global_position.distance_to(character.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best

func nearest_hostile(character) -> AICharacter:
	if character == null:
		return null
	var best: AICharacter = null
	var best_dist := INF
	var my_faction: String = str(character.character_data.faction_id)
	for c in CharacterManager.all_characters():
		if c == character or not c.alive or c.dying:
			continue
		var d: float = c.global_position.distance_to(character.global_position)
		if d > 28.0:
			continue
		var hostile := false
		if my_faction != c.character_data.faction_id and CivilizationManager.at_war(my_faction, c.character_data.faction_id):
			hostile = true
		elif RelationshipSystem.get_relationship(character, c.character_data.id).affinity < -30.0:
			hostile = true
		if hostile and d < best_dist:
			best_dist = d
			best = c
	return best

func characters_in_radius(position: Vector3, radius: float, exclude: Array = []) -> Array:
	var out: Array = []
	var skip: Dictionary = {}
	for e in exclude:
		skip[e] = true
	var radius_sq := radius * radius
	for c in CharacterManager.all_characters():
		if skip.has(c) or not c.alive or c.dying:
			continue
		if c.global_position.distance_squared_to(position) <= radius_sq:
			out.append(c)
	return out

func summarize(character) -> String:
	if character == null or character.character_data == null:
		return ""
	var d: CharacterData = character.character_data
	var lines: Array[String] = []
	lines.append("你位于%s。" % WorldManager.biome_name_at(character.global_position))
	var nearby := characters_in_radius(character.global_position, PERCEPTION_RADIUS, [character])
	if nearby.is_empty():
		lines.append("附近没有其他硅灵。")
	else:
		var desc: Array[String] = []
		for c in nearby:
			desc.append("%s（%s）" % [c.character_data.name, c.character_data.current_action])
		lines.append("附近有%d个硅灵：%s。" % [nearby.size(), "、".join(desc)])
	var res_desc: Array[String] = []
	for node in WorldManager.resource_nodes:
		if node.global_position.distance_to(character.global_position) <= RESOURCE_RADIUS:
			res_desc.append("%s×%d" % [node.resource_name, int(node.amount)])
	if not res_desc.is_empty():
		lines.append("你注意到附近的资源：%s。" % "、".join(res_desc))
	lines.append("天气%s，时间是%s。" % [WorldManager.weather_name(), TimeManager.time_of_day_text()])
	var energy := float(d.status.get("energy", 100.0))
	var fatigue := float(d.status.get("fatigue", 0.0))
	if energy < 35.0:
		lines.append("你感到能量不足（%d%%）。" % int(energy))
	if fatigue > 60.0:
		lines.append("你非常疲惫。")
	if GameState.selected_character == character:
		lines.append("你感到镜外之神的视线正落在你身上。")
	return "\n".join(lines)
