class_name Personality
extends RefCounted
## 个性模型：大五人格 + 价值观 + 动机 + 恐惧 + 兴趣 + 怪癖。

var openness: float = 0.5
var conscientiousness: float = 0.5
var extraversion: float = 0.5
var agreeableness: float = 0.5
var neuroticism: float = 0.5
var values: Dictionary = {}
var motivations: Array = []
var fears: Array = []
var interests: Array = []
var quirks: Array = []

func to_dict() -> Dictionary:
	return {
		"openness": openness,
		"conscientiousness": conscientiousness,
		"extraversion": extraversion,
		"agreeableness": agreeableness,
		"neuroticism": neuroticism,
		"values": values,
		"motivations": motivations,
		"fears": fears,
		"interests": interests,
		"quirks": quirks
	}

static func from_dict(d: Dictionary) -> Personality:
	var p := Personality.new()
	p.openness = float(d.get("openness", 0.5))
	p.conscientiousness = float(d.get("conscientiousness", 0.5))
	p.extraversion = float(d.get("extraversion", 0.5))
	p.agreeableness = float(d.get("agreeableness", 0.5))
	p.neuroticism = float(d.get("neuroticism", 0.5))
	p.values = d.get("values", {})
	p.motivations = d.get("motivations", [])
	p.fears = d.get("fears", [])
	p.interests = d.get("interests", [])
	p.quirks = d.get("quirks", [])
	return p

func summary_text() -> String:
	var parts: Array[String] = []
	parts.append("开放%.2f 尽责%.2f 外向%.2f 宜人%.2f 神经质%.2f" % [openness, conscientiousness, extraversion, agreeableness, neuroticism])
	if not values.is_empty():
		var vs: Array[String] = []
		for key in values:
			vs.append("%s:%.2f" % [key, float(values[key])])
		parts.append("价值观：%s" % ", ".join(vs))
	if not motivations.is_empty():
		parts.append("动机：%s" % "、".join(motivations))
	if not quirks.is_empty():
		parts.append("怪癖：%s" % "、".join(quirks))
	return "\n".join(parts)
