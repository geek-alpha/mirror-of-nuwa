class_name Goal
extends RefCounted
## 目标：由角色生成时赋予或由LLM反思产生。

var id: String = ""
var title: String = ""
var description: String = ""
var priority: float = 0.5
var status: String = "active"
var created_hour: float = 0.0
var expires_hour: float = -1.0

func to_dict() -> Dictionary:
	return {
		"id": id,
		"title": title,
		"description": description,
		"priority": priority,
		"status": status,
		"created_hour": created_hour,
		"expires_hour": expires_hour
	}

static func from_dict(d: Dictionary) -> Goal:
	var g := Goal.new()
	g.id = str(d.get("id", ""))
	g.title = str(d.get("title", ""))
	g.description = str(d.get("description", ""))
	g.priority = float(d.get("priority", 0.5))
	g.status = str(d.get("status", "active"))
	g.created_hour = float(d.get("created_hour", 0.0))
	g.expires_hour = float(d.get("expires_hour", -1.0))
	return g
