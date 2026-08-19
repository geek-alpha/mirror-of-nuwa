class_name RelationshipEntry
extends RefCounted
## 关系条目：亲密度、信任度、互动历史。

var target_id: String = ""
var affinity: float = 0.0
var trust: float = 0.0
var history: Array = []
var last_interaction_hour: float = -1.0

func to_dict() -> Dictionary:
	return {
		"target_id": target_id,
		"affinity": affinity,
		"trust": trust,
		"history": history,
		"last_interaction_hour": last_interaction_hour
	}

static func from_dict(d: Dictionary) -> RelationshipEntry:
	var r := RelationshipEntry.new()
	r.target_id = str(d.get("target_id", ""))
	r.affinity = float(d.get("affinity", 0.0))
	r.trust = float(d.get("trust", 0.0))
	r.history = d.get("history", [])
	r.last_interaction_hour = float(d.get("last_interaction_hour", -1.0))
	return r
