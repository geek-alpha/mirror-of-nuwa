class_name MemoryEntry
extends RefCounted
## 记忆条目：短期（episodic）会衰减，长期（semantic/procedural）保留。

var id: String = ""
var timestamp: int = 0
var location: Vector3 = Vector3.ZERO
var content: String = ""
var importance: float = 0.5
var emotion: String = ""
var tags: Array = []
var associations: Array = []
var type: String = "episodic"
var last_accessed_hour: float = -1.0

func to_dict() -> Dictionary:
	return {
		"id": id,
		"timestamp": timestamp,
		"location": [location.x, location.y, location.z],
		"content": content,
		"importance": importance,
		"emotion": emotion,
		"tags": tags,
		"associations": associations,
		"type": type
	}

static func from_dict(d: Dictionary) -> MemoryEntry:
	var m := MemoryEntry.new()
	m.id = str(d.get("id", ""))
	m.timestamp = int(d.get("timestamp", 0))
	var loc: Array = d.get("location", [0.0, 0.0, 0.0])
	m.location = Vector3(float(loc[0]), float(loc[1]), float(loc[2]))
	m.content = str(d.get("content", ""))
	m.importance = float(d.get("importance", 0.5))
	m.emotion = str(d.get("emotion", ""))
	m.tags = d.get("tags", [])
	m.associations = d.get("associations", [])
	m.type = str(d.get("type", "episodic"))
	return m
