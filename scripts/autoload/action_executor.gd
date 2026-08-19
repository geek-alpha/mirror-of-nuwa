extends Node
## 行为执行器：将LLM或规则AI输出的动作字典映射为具体游戏行为。
## 支持移动、采集、对话、建造、休息、进食、冥想、祈祷、攻击、逃跑等。

func execute(character: AICharacter, action: Dictionary) -> bool:
	if character == null or not character.alive:
		return false
	var action_type := str(action.get("action", "idle"))
	character.character_data.current_action = action_type
	character.current_action = action
	match action_type:
		Enums.ACTION_MOVE_TO:
			_begin_move(character, _resolve_position(character, action), {})
		Enums.ACTION_GATHER:
			var node = _resolve_node(character, action)
			if node == null:
				_fail(character, "附近没有可采集的资源")
				return false
			action["_node"] = node
			_begin_move(character, node.global_position, {"on_arrive": "gather"})
		Enums.ACTION_TALK_TO:
			var target = _resolve_character(character, action)
			if target == null:
				_fail(character, "附近没有可交谈的对象")
				return false
			action["_target"] = target
			_begin_move(character, target.global_position, {"on_arrive": "talk_to"})
		Enums.ACTION_BUILD:
			var site := WorldManager.random_point_near(character.global_position, 8.0)
			action["_site"] = site
			_begin_move(character, site, {"on_arrive": "build"})
		Enums.ACTION_ATTACK:
			var target = _resolve_character(character, action)
			if target == null:
				_fail(character, "没有可攻击的目标")
				return false
			action["_target"] = target
			_begin_move(character, target.global_position, {"on_arrive": "attack"})
		Enums.ACTION_FLEE:
			var away := character.global_position + Vector3(randf_range(-25.0, 25.0), 0.0, randf_range(-25.0, 25.0))
			_begin_move(character, WorldManager.clamp_point(away), {})
		Enums.ACTION_REST:
			_begin_timed(character, action, float(action.get("duration_hours", 2.0)))
		Enums.ACTION_EAT:
			_begin_timed(character, action, float(action.get("duration_hours", 0.5)))
		Enums.ACTION_MEDITATE:
			_begin_timed(character, action, float(action.get("duration_hours", 1.5)))
		Enums.ACTION_PRAY:
			_begin_timed(character, action, float(action.get("duration_hours", 1.0)))
		Enums.ACTION_USE_ITEM:
			_begin_timed(character, action, float(action.get("duration_hours", 0.5)))
		_:
			# idle 或未知动作：短暂停留后重新决策
			_begin_timed(character, action, 0.25)
	return true

func _begin_move(character: AICharacter, target: Vector3, on_arrive: Dictionary) -> void:
	character.moving = true
	character.action_on_arrive = on_arrive
	character.action_remaining_hours = 0.0
	character.action_target = WorldManager.clamp_point(target)

func _begin_timed(character: AICharacter, _action: Dictionary, hours: float) -> void:
	character.moving = false
	character.action_remaining_hours = maxf(hours, 0.05)
	character.action_on_arrive = {}

func on_character_arrived(character: AICharacter) -> void:
	if character == null or not character.alive:
		return
	var on_arrive: Dictionary = character.action_on_arrive
	var kind := str(on_arrive.get("on_arrive", ""))
	match kind:
		"gather":
			_do_gather(character)
		"talk_to":
			_do_talk(character, character.current_action.get("_target", null))
		"build":
			_do_build(character)
		"attack":
			_do_attack(character, character.current_action.get("_target", null))
		_:
			_complete(character)

func on_character_action_finished(character: AICharacter) -> void:
	if character == null or not character.alive:
		return
	var action_type := str(character.character_data.current_action)
	match action_type:
		Enums.ACTION_REST:
			var st: Dictionary = character.character_data.status
			st["fatigue"] = maxf(0.0, float(st.get("fatigue", 0.0)) - 40.0)
			st["energy"] = minf(100.0, float(st.get("energy", 100.0)) + 20.0)
			MemorySystem.add_memory(character, "我休息了一段时间，恢复了一些能量。", 0.3, "peace", ["rest"])
		Enums.ACTION_EAT:
			var inv: Dictionary = character.character_data.inventory
			var st2: Dictionary = character.character_data.status
			if float(inv.get("energy_crystal", 0.0)) > 0.0:
				inv["energy_crystal"] = float(inv["energy_crystal"]) - 1.0
				st2["energy"] = minf(100.0, float(st2.get("energy", 100.0)) + 35.0)
			else:
				st2["energy"] = minf(100.0, float(st2.get("energy", 100.0)) + 8.0)
		Enums.ACTION_MEDITATE:
			var st3: Dictionary = character.character_data.status
			st3["spirit"] = minf(100.0, float(st3.get("spirit", 100.0)) + 30.0)
			st3["fatigue"] = maxf(0.0, float(st3.get("fatigue", 0.0)) - 15.0)
			MemorySystem.add_memory(character, "我在冥想中看见了关于存在本质的碎片。", 0.6, "awe", ["meditation", "reflection"])
		Enums.ACTION_PRAY:
			CivilizationManager.add_faith(character.character_data.faction_id, 2.0)
			MemorySystem.add_memory(character, "我向女娲祈祷，晶海回应了我的低语。", 0.7, "peace", ["pray", "religion"])
			HistoryManager.log_event("religion", "%s在祈祷" % character.character_data.name, "祭司的祈祷声回荡在聚落中。", character.character_data.id, character.character_data.faction_id)
		_:
			pass
	_complete(character)

func _do_gather(character: AICharacter) -> void:
	var node = character.current_action.get("_node", null)
	if node == null or not is_instance_valid(node):
		_complete(character)
		return
	var taken: float = node.collect(10.0)
	if taken <= 0.0:
		_complete(character)
		return
	var res_type: String = str(node.resource_id)
	var inv: Dictionary = character.character_data.inventory
	inv[res_type] = float(inv.get(res_type, 0.0)) + taken
	CivilizationManager.add_resource(character.character_data.faction_id, res_type, taken)
	character.speak("采集了%s×%d" % [node.resource_name, int(taken)])
	MemorySystem.add_memory(character, "我采集了%s。" % node.resource_name, 0.4, "curiosity", ["gather", res_type])
	_complete(character)

func _do_talk(character: AICharacter, target) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		_complete(character)
		return
	RelationshipSystem.update_relationship(character, target.character_data.id, 1.2, "交谈")
	if ConfigManager.llm_enabled() and LLMService.is_available():
		character.llm_busy = true
		var prompt := PromptBuilder.build_dialogue_prompt(character, target)
		LLMService.request_dialogue(character.character_data.id, prompt, func(result):
			if character != null and is_instance_valid(character):
				character.llm_busy = false
			if character == null or not is_instance_valid(character) or target == null or not is_instance_valid(target):
				return
			var text := str(result.get("dialogue", ""))
			if text.strip_edges() == "":
				text = _template_dialogue(character, target)
			_finish_talk(character, target, text)
		)
	else:
		var text := _template_dialogue(character, target)
		_finish_talk(character, target, text)

func _finish_talk(character: AICharacter, target, text: String) -> void:
	if text.strip_edges() != "":
		character.speak(text, true)
		MemorySystem.add_memory(character, "与%s交谈：%s" % [target.character_data.name, text], 0.5, "curiosity", ["social", "dialogue"])
		MemorySystem.add_memory(target, "与%s交谈：%s" % [character.character_data.name, text], 0.5, "curiosity", ["social", "dialogue"])
		EventBus.dialogue_occurred.emit(character.character_data.id, target.character_data.id, text)
		HistoryManager.log_event("dialogue", "%s与%s交谈" % [character.character_data.name, target.character_data.name], text, character.character_data.id, character.character_data.faction_id)
	_complete(character)

func _do_build(character: AICharacter) -> void:
	var d: CharacterData = character.character_data
	var preferred := {
		"builder": "building_house",
		"priest": "building_temple",
		"scholar": "building_lab"
	}
	var building_id := str(preferred.get(d.role, "building_house"))
	if not CivilizationManager.building_defs.has(building_id):
		building_id = "building_house"
	var def: Dictionary = CivilizationManager.building_defs[building_id]
	var cost: Dictionary = def.get("cost", {})
	var inv: Dictionary = d.inventory
	var affordable := true
	for res_type in cost:
		if float(inv.get(res_type, 0.0)) < float(cost[res_type]):
			affordable = false
			break
	if affordable:
		for res_type in cost:
			inv[res_type] = float(inv.get(res_type, 0.0)) - float(cost[res_type])
		var site: Vector3 = character.current_action.get("_site", WorldManager.random_point_near(character.global_position, 8.0))
		var building := WorldManager.spawn_building(building_id, d.faction_id, site)
		if building != null:
			EventBus.building_built.emit(building)
			MemorySystem.add_memory(character, "我建造了一座%s。" % def.get("name", building_id), 0.8, "joy", ["build"])
			HistoryManager.log_event("building", "%s建造了%s" % [d.name, def.get("name", building_id)], str(def.get("description", "")), d.id, d.faction_id)
			character.speak("建造完成：%s" % def.get("name", ""))
	else:
		character.speak("缺少建造材料")
		MemorySystem.add_memory(character, "我想建造%s，但材料不足。" % def.get("name", ""), 0.5, "frustration", ["build"])
	_complete(character)

func _do_attack(character: AICharacter, target) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		_complete(character)
		return
	RelationshipSystem.update_relationship(character, target.character_data.id, -10.0, "攻击")
	var hp := float(target.character_data.status.get("health", 100.0)) - 18.0
	target.character_data.status["health"] = hp
	character.speak("受死吧！")
	MemorySystem.add_memory(character, "我攻击了%s。" % target.character_data.name, 0.8, "anger", ["combat"])
	if hp <= 0.0:
		target.start_dying("我……被%s击败了……" % character.character_data.name)
		HistoryManager.log_event("war", "%s击杀了%s" % [character.character_data.name, target.character_data.name], "战斗结束，一名硅灵陨落。", character.character_data.id, character.character_data.faction_id)
	else:
		MemorySystem.add_memory(target, "%s攻击了我！" % character.character_data.name, 0.9, "anger", ["combat"])
		target.speak("可恶……")
	_complete(character)

func _complete(character: AICharacter) -> void:
	if character == null or not is_instance_valid(character):
		return
	character.current_action = {}
	character.action_on_arrive = {}
	character.action_remaining_hours = 0.0
	character.moving = false
	if character.character_data != null:
		character.character_data.current_action = "idle"
	character.action_completed.emit(character)

func _fail(character: AICharacter, reason: String) -> void:
	if character != null and is_instance_valid(character):
		character.speak(reason)
	_complete(character)

func _resolve_position(character: AICharacter, action: Dictionary) -> Vector3:
	if action.has("position") and action["position"] is Vector3:
		return action["position"]
	if action.has("target_node") and is_instance_valid(action["target_node"]):
		return action["target_node"].global_position
	if action.has("target_character") and is_instance_valid(action["target_character"]):
		return action["target_character"].global_position
	var target = action.get("target", null)
	if target is Vector3:
		return target
	if target is Node3D:
		return target.global_position
	if target is String:
		var c = CharacterManager.get_character(str(target))
		if c != null:
			return c.global_position
		var node = WorldManager.find_resource_by_name(str(target))
		if node != null:
			return node.global_position
	return WorldManager.random_point_near(character.global_position, 15.0)

func _resolve_node(character: AICharacter, action: Dictionary) -> ResourceNode:
	if action.has("target_node") and is_instance_valid(action["target_node"]):
		return action["target_node"]
	var target = action.get("target", null)
	if target is Node3D and target is ResourceNode:
		return target
	if target is String:
		var node = WorldManager.find_resource_by_name(str(target))
		if node != null:
			return node
	return PerceptionSystem.nearest_resource(character)

func _resolve_character(character: AICharacter, action: Dictionary) -> AICharacter:
	if action.has("target_character") and is_instance_valid(action["target_character"]):
		return action["target_character"]
	var target = action.get("target", null)
	if target is Node3D and target is AICharacter:
		return target
	if target is String:
		return CharacterManager.get_character(str(target))
	return PerceptionSystem.nearest_character(character)

func _template_dialogue(character: AICharacter, target) -> String:
	## 离线对话模板：按关系与个性生成简短台词。
	var affinity := RelationshipSystem.get_relationship(character, target.character_data.id).affinity
	var pools: Array = []
	if affinity > 20.0:
		pools = [
			"愿你晶核明亮，%s。" % target.character_data.name,
			"看到你真好，最近能量还够用吗？",
			"我想我们应当一起建点什么。",
			"晶海的低语说，我们是一体的。"
		]
	elif affinity < -30.0:
		pools = [
			"哼，%s，别挡我的路。" % target.character_data.name,
			"你的出现让这片晶域变得浑浊。",
			"记住，我不信任你。"
		]
	else:
		pools = [
			"你好，%s。今天也在寻找什么吗？" % target.character_data.name,
			"你听说了吗？北边的遗迹又发出了信号。",
			"女娲留下的世界，真是奇妙。",
			"能量晶体在呼唤我们。"
		]
	if character.character_data.role == "priest":
		pools.append("愿镜外之神注视着你，%s。" % target.character_data.name)
	if character.character_data.role == "scholar":
		pools.append("我昨夜梦见了一串古老的符号，也许与数据碎片有关。")
	return str(pools[randi() % pools.size()])
