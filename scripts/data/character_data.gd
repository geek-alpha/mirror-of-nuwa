class_name CharacterData
extends RefCounted
## 角色数据结构：承载AI角色的全部状态，可序列化到JSON。

var id: String = ""
var name: String = ""
var age: float = 1.0
var sex: String = "none"
var race: String = "silicreature"
var form: String = Enums.FORM_HUMANOID
var location: Vector3 = Vector3.ZERO
var home_id: String = ""
var faction_id: String = ""
var role: String = "explorer"
var status: Dictionary = {"energy": 100.0, "health": 100.0, "fatigue": 0.0, "spirit": 100.0}
var inventory: Dictionary = {}
var personality: Personality = null
var memories: Array = []
var relationships: Dictionary = {}
var goals: Array = []
var beliefs: Array = []
var current_emotion: String = "curiosity"
var current_action: String = "idle"
var speech_style: String = "自然"
var appearance: Dictionary = {}

func add_goal(title: String, description: String = "", priority: float = 0.5) -> Goal:
	var goal := Goal.new()
	goal.id = "goal_%d" % goals.size()
	goal.title = title
	goal.description = description
	goal.priority = priority
	goal.created_hour = TimeManager.game_time
	goals.append(goal)
	return goal

func to_save_dict() -> Dictionary:
	var mems: Array = []
	for m in memories:
		mems.append(m.to_dict())
	var rels := {}
	for rid in relationships:
		rels[rid] = relationships[rid].to_dict()
	var goals_out: Array = []
	for g in goals:
		goals_out.append(g.to_dict())
	return {
		"id": id,
		"name": name,
		"age": age,
		"sex": sex,
		"race": race,
		"form": form,
		"location": [location.x, location.y, location.z],
		"home_id": home_id,
		"faction_id": faction_id,
		"role": role,
		"status": status,
		"inventory": inventory,
		"personality": personality.to_dict() if personality != null else {},
		"memories": mems,
		"relationships": rels,
		"goals": goals_out,
		"beliefs": beliefs,
		"current_emotion": current_emotion,
		"current_action": current_action,
		"speech_style": speech_style,
		"appearance": appearance
	}

static func from_save_dict(d: Dictionary) -> CharacterData:
	var data := CharacterData.new()
	data.id = str(d.get("id", ""))
	data.name = str(d.get("name", "无名硅灵"))
	data.age = float(d.get("age", 1.0))
	data.sex = str(d.get("sex", "none"))
	data.race = str(d.get("race", "silicreature"))
	data.form = str(d.get("form", Enums.FORM_HUMANOID))
	var loc: Array = d.get("location", [0.0, 0.0, 0.0])
	data.location = Vector3(float(loc[0]), float(loc[1]), float(loc[2]))
	data.home_id = str(d.get("home_id", ""))
	data.faction_id = str(d.get("faction_id", ""))
	data.role = str(d.get("role", "explorer"))
	data.status = d.get("status", {})
	data.inventory = d.get("inventory", {})
	data.personality = Personality.from_dict(d.get("personality", {}))
	for md in d.get("memories", []):
		data.memories.append(MemoryEntry.from_dict(md))
	for rid in d.get("relationships", {}):
		data.relationships[rid] = RelationshipEntry.from_dict(d["relationships"][rid])
	for gd in d.get("goals", []):
		data.goals.append(Goal.from_dict(gd))
	data.beliefs = d.get("beliefs", [])
	data.current_emotion = str(d.get("current_emotion", "curiosity"))
	data.current_action = str(d.get("current_action", "idle"))
	data.speech_style = str(d.get("speech_style", "自然"))
	data.appearance = d.get("appearance", {})
	return data
