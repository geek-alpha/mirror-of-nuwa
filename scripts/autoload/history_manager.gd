extends Node
## 历史管理器：记录大事年表、角色传记与文明年鉴。
## 所有事件带游戏时间戳，可按类型过滤，也可导出为文本。

var events: Array = []
var biographies: Dictionary = {}
var max_events := 3000

func log_event(type: String, title: String, details: String, character_id: String = "", faction_id: String = "") -> Dictionary:
	var ev := {
		"id": "evt_%d" % events.size(),
		"hour": TimeManager.game_time,
		"day": TimeManager.get_day(),
		"date_text": TimeManager.date_text(),
		"type": type,
		"title": title,
		"details": details,
		"character_id": character_id,
		"faction_id": faction_id
	}
	events.append(ev)
	if events.size() > max_events:
		events.pop_front()
	if character_id != "":
		if not biographies.has(character_id):
			biographies[character_id] = []
		biographies[character_id].append(ev)
	EventBus.history_updated.emit()
	return ev

func get_events(filter_type: String = "") -> Array:
	if filter_type == "":
		return events
	var out: Array = []
	for ev in events:
		if ev.get("type", "") == filter_type:
			out.append(ev)
	return out

func get_biography(character_id: String) -> Array:
	return biographies.get(character_id, [])

func get_biography_text(character_id: String) -> String:
	var bio: Array = get_biography(character_id)
	if bio.is_empty():
		return "（暂无传记记录）"
	var lines: Array[String] = []
	for ev in bio:
		lines.append("[%s] %s：%s" % [ev.get("date_text", ""), ev.get("title", ""), ev.get("details", "")])
	return "\n".join(lines)

func get_annals_text() -> String:
	var lines: Array[String] = []
	lines.append("===== 文明年鉴（%s）=====" % TimeManager.date_text())
	lines.append("")
	# 统计
	var counts: Dictionary = {}
	for ev in events:
		var t := str(ev.get("type", "other"))
		counts[t] = int(counts.get(t, 0)) + 1
	var type_names := {
		"world": "世界", "birth": "诞生", "death": "陨落", "dialogue": "对话",
		"technology": "科技", "building": "建筑", "religion": "宗教",
		"war": "战争", "intervention": "干预", "disaster": "天灾", "blessing": "赐福"
	}
	for t in counts:
		lines.append("%s：%d 起" % [type_names.get(t, t), counts[t]])
	lines.append("")
	lines.append("----- 最近事件 -----")
	var recent: Array = events.duplicate()
	recent.reverse()
	for ev in recent.slice(0, 40):
		lines.append("[%s] %s" % [ev.get("date_text", ""), ev.get("title", "")])
	return "\n".join(lines)

func event_log_text(filter_type: String = "") -> String:
	var list := get_events(filter_type)
	if list.is_empty():
		return "（暂无事件）"
	var lines: Array[String] = []
	for ev in list:
		lines.append("[%s] %s：%s" % [ev.get("date_text", ""), ev.get("title", ""), ev.get("details", "")])
	return "\n".join(lines)

func clear() -> void:
	events.clear()
	biographies.clear()

func serialize() -> Dictionary:
	return {"events": events, "biographies": biographies}

func load_from(data: Dictionary) -> void:
	events = data.get("events", [])
	biographies = data.get("biographies", {})
	EventBus.history_updated.emit()
