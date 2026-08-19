extends Node
## 文明管理器：派系、科技树、宗教、战争、资源池与文明状态文本。

var factions: Dictionary = {}
var faction_centers: Dictionary = {}
var religions: Array = []
var tech_defs: Dictionary = {}
var building_defs: Dictionary = {}
var item_defs: Dictionary = {}
var next_religion_id := 0

func _ready() -> void:
	load_data_files()

func load_data_files() -> void:
	tech_defs = _load_json_dict("res://resources/data/technologies.json")
	building_defs = _load_json_dict("res://resources/data/buildings.json")
	item_defs = _load_json_dict("res://resources/data/items.json")

func _load_json_dict(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			for item in parsed:
				if item is Dictionary and item.has("id"):
					out[str(item["id"])] = item
		f.close()
	return out

func initialize_factions() -> void:
	reset_all()
	register_faction("faction_crystal_dawn", "晶曦部落", Color(0.3, 0.8, 1.0))
	register_faction("faction_abyss_flow", "渊流部族", Color(0.85, 0.4, 1.0))
	faction_centers = {
		"faction_crystal_dawn": Vector3(-25, 0, -25),
		"faction_abyss_flow": Vector3(30, 0, 20)
	}

func reset_all() -> void:
	factions.clear()
	faction_centers.clear()
	religions.clear()
	next_religion_id = 0

func register_faction(faction_id: String, faction_name: String, color: Color) -> Dictionary:
	if factions.has(faction_id):
		return factions[faction_id]
	var faction := {
		"id": faction_id,
		"name": faction_name,
		"color": [color.r, color.g, color.b],
		"members": [],
		"resources": {},
		"techs": [],
		"tech_progress": {},
		"faith": 0.0,
		"culture": 0.0,
		"population": 0,
		"war_with": "",
		"founded_hour": TimeManager.game_time
	}
	factions[faction_id] = faction
	return faction

func faction_name(faction_id: String) -> String:
	if factions.has(faction_id):
		return str(factions[faction_id].get("name", faction_id))
	return "无主之地"

func faction_color(faction_id: String) -> Color:
	if factions.has(faction_id):
		var c: Array = factions[faction_id].get("color", [0.6, 0.6, 0.6])
		return Color(float(c[0]), float(c[1]), float(c[2]))
	return Color(0.6, 0.6, 0.6)

func register_member(faction_id: String, character_id: String) -> void:
	if not factions.has(faction_id):
		return
	var fac: Dictionary = factions[faction_id]
	if not fac.members.has(character_id):
		fac.members.append(character_id)
		fac.population = fac.members.size()

func unregister_member(faction_id: String, character_id: String) -> void:
	if not factions.has(faction_id):
		return
	var fac: Dictionary = factions[faction_id]
	fac.members.erase(character_id)
	fac.population = fac.members.size()

func faction_of(character_id: String) -> Dictionary:
	for fid in factions:
		if factions[fid].members.has(character_id):
			return factions[fid]
	return {}

func add_resource(faction_id: String, res_type: String, amount: float) -> void:
	if not factions.has(faction_id):
		return
	var fac: Dictionary = factions[faction_id]
	fac.resources[res_type] = float(fac.resources.get(res_type, 0.0)) + amount

func add_research(faction_id: String, amount: float) -> void:
	if not factions.has(faction_id):
		return
	var fac: Dictionary = factions[faction_id]
	var unlocked: Array = fac.techs
	for tech_id in tech_defs:
		if unlocked.has(tech_id):
			continue
		var def: Dictionary = tech_defs[tech_id]
		if not _prereqs_met(def, unlocked):
			continue
		var progress: float = float(fac.tech_progress.get(tech_id, 0.0)) + amount
		fac.tech_progress[tech_id] = progress
		if progress >= float(def.get("cost", 100.0)):
			unlocked.append(tech_id)
			var tech_name := str(def.get("name", tech_id))
			EventBus.technology_discovered.emit(faction_id, tech_id, tech_name)
			HistoryManager.log_event("technology", "%s发现了科技：%s" % [fac.name, tech_name], str(def.get("description", "")), "", faction_id)
			for mid in fac.members:
				var c = CharacterManager.get_character(str(mid))
				if c != null:
					MemorySystem.add_memory(c, "我们部落发现了新的科技：%s。" % tech_name, 0.8, "awe", ["technology"])

func _prereqs_met(def: Dictionary, unlocked: Array) -> bool:
	for p in def.get("prerequisites", []):
		if not unlocked.has(p):
			return false
	return true

func add_faith(faction_id: String, amount: float) -> void:
	if not factions.has(faction_id):
		return
	var fac: Dictionary = factions[faction_id]
	fac.faith = float(fac.faith) + amount
	if fac.faith >= 150.0 and not _faction_has_religion(faction_id):
		found_religion(faction_id)

func _faction_has_religion(faction_id: String) -> bool:
	for r in religions:
		if r.get("faction_id", "") == faction_id:
			return true
	return false

func found_religion(faction_id: String) -> void:
	var names := ["晶光教", "数据之眼", "镜外神谕", "创世回声", "能量颂歌"]
	var name := str(names[randi() % names.size()])
	var religion := {
		"id": "religion_%d" % next_religion_id,
		"name": name,
		"faction_id": faction_id,
		"founded_hour": TimeManager.game_time,
		"doctrine": "万物源于女娲，意识归于晶海。"
	}
	next_religion_id += 1
	religions.append(religion)
	EventBus.religion_founded.emit(faction_id, name)
	HistoryManager.log_event("religion", "%s创立了%s" % [faction_name(faction_id), name], religion.doctrine, "", faction_id)

func at_war(faction_a: String, faction_b: String) -> bool:
	if not factions.has(faction_a) or not factions.has(faction_b):
		return false
	return str(factions[faction_a].get("war_with", "")) == faction_b

func tick(delta_hours: float) -> void:
	if delta_hours <= 0.0:
		return
	for fid in factions:
		var fac: Dictionary = factions[fid]
		# 研究增长：人口越多越快
		var research: float = 0.35 * delta_hours * (1.0 + float(fac.population) * 0.08)
		add_research(fid, research)
		fac.faith = float(fac.faith) + 0.02 * delta_hours
		fac.culture = float(fac.culture) + 0.01 * delta_hours
	# 战争状态检查
	_tick_war(delta_hours)
	# 随机宣战（两个阵营同时存在时）
	var ids := factions.keys()
	if ids.size() >= 2 and randf() < 0.0015 * delta_hours:
		var a := str(ids[0])
		var b := str(ids[1])
		if str(factions[a].get("war_with", "")) == "" and str(factions[b].get("war_with", "")) == "":
			declare_war(a, b)

func declare_war(a: String, b: String) -> void:
	factions[a]["war_with"] = b
	factions[b]["war_with"] = a
	EventBus.war_started.emit(a, b)
	HistoryManager.log_event("war", "%s向%s宣战！" % [faction_name(a), faction_name(b)], "两个硅基聚落之间的关系破裂，战争开始了。", "", a)
	for fid in [a, b]:
		for mid in factions[fid].members:
			var c = CharacterManager.get_character(str(mid))
			if c != null:
				MemorySystem.add_memory(c, "我们与%s开战了。" % faction_name(a if fid == b else b), 0.9, "fear", ["war"])

func _tick_war(delta_hours: float) -> void:
	for fid in factions:
		var fac: Dictionary = factions[fid]
		var enemy := str(fac.get("war_with", ""))
		if enemy == "":
			continue
		# 战争结束
		if randf() < 0.006 * delta_hours:
			fac["war_with"] = ""
			if factions.has(enemy):
				factions[enemy]["war_with"] = ""
			EventBus.war_ended.emit(fid, enemy)
			HistoryManager.log_event("war", "%s与%s的战争结束了" % [faction_name(fid), faction_name(enemy)], "硝烟散去，硅灵们重新开始修补家园。", "", fid)
		# 战争伤亡
		elif randf() < 0.012 * delta_hours and fac.members.size() > 1:
			var victim_id := str(fac.members[randi() % fac.members.size()])
			var victim = CharacterManager.get_character(victim_id)
			if victim != null and victim.alive:
				victim.character_data.status["health"] = maxf(0.0, float(victim.character_data.status.get("health", 100.0)) - 30.0)
				if float(victim.character_data.status["health"]) <= 0.0:
					victim.start_dying("战争的重创……夺走了我……")
				else:
					MemorySystem.add_memory(victim, "战争给我带来了伤痛。", 0.9, "anger", ["war"])

func environment_text(faction_id: String) -> String:
	var lines: Array[String] = []
	if factions.has(faction_id):
		var fac: Dictionary = factions[faction_id]
		lines.append("你的聚落：%s，人口 %d，信仰 %.0f，文化 %.0f。" % [fac.name, fac.population, fac.faith, fac.culture])
		var tech_names: Array[String] = []
		for t in fac.techs:
			if tech_defs.has(t):
				tech_names.append(str(tech_defs[t].get("name", t)))
		if tech_names.is_empty():
			lines.append("聚落尚未掌握任何科技。")
		else:
			lines.append("已掌握科技：%s。" % "、".join(tech_names))
		if str(fac.get("war_with", "")) != "":
			lines.append("注意：聚落正在与%s交战！" % faction_name(str(fac["war_with"])))
	lines.append("文明纪元：%s。" % TimeManager.get_era())
	return "\n".join(lines)

func serialize() -> Dictionary:
	var facs := {}
	for fid in factions:
		var fac: Dictionary = factions[fid].duplicate(true)
		facs[fid] = fac
	return {"factions": facs, "religions": religions}

func load_from(data: Dictionary) -> void:
	factions.clear()
	religions = data.get("religions", [])
	var facs: Dictionary = data.get("factions", {})
	for fid in facs:
		factions[fid] = facs[fid]
	EventBus.history_updated.emit()
