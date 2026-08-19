class_name InteractionSystem
extends Node
## 交互系统：化身模式下与AI角色的对话入口与LLM/模板回复。

func try_talk_nearest(character: AICharacter) -> void:
	if character == null:
		return
	var other = PerceptionSystem.nearest_character(character)
	if other == null:
		UIManager.append_system_message("附近没有可以交谈的人。" if GameState.is_story_mode() else "附近没有可以交谈的硅灵。")
		return
	var d: float = other.global_position.distance_to(character.global_position)
	if d > 4.5:
		UIManager.append_system_message("距离太远（%.1f米），靠近一点再按F交谈。" % d)
		return
	UIManager.open_dialogue(character, other)

func send_player_dialogue(character: AICharacter, other: AICharacter, text: String) -> void:
	if character == null or other == null or text.strip_edges() == "":
		return
	var pname := str(character.character_data.name)
	MemorySystem.add_memory(other, "%s对我说：%s" % [pname, text], 0.8, "curiosity", ["player", "dialogue"])
	MemorySystem.add_memory(character, "我对%s说：%s" % [other.character_data.name, text], 0.6, "", ["player", "dialogue"])
	RelationshipSystem.update_relationship(other, character.character_data.id, 2.0, "与%s交谈" % pname)
	EventBus.dialogue_occurred.emit(character.character_data.id, other.character_data.id, text)
	EventBus.player_intervention.emit(other.character_data.id, "dialogue", text)
	if ConfigManager.llm_enabled() and LLMService.is_available():
		UIManager.append_system_message("（%s正在思考…）" % other.character_data.name)
		var prompt := PromptBuilder.build_dialogue_prompt(other, character, {"player_text": text})
		LLMService.request_dialogue(other.character_data.id, prompt, func(result):
			if character == null or not is_instance_valid(character) or other == null or not is_instance_valid(other):
				return
			var reply := str(result.get("dialogue", ""))
			if reply.strip_edges() == "":
				reply = _template_reply(other, text)
			_deliver_reply(character, other, reply)
		)
	else:
		_deliver_reply(character, other, _template_reply(other, text))

func _deliver_reply(character: AICharacter, other: AICharacter, reply: String) -> void:
	# 回复会通过 other.speak → UIManager.on_character_spoke 自动进入对话框日志
	var pname := str(character.character_data.name)
	other.speak(reply, true, true)
	MemorySystem.add_memory(character, "%s回应我：%s" % [other.character_data.name, reply], 0.6, "", ["player", "dialogue"])
	MemorySystem.add_memory(other, "我回应了%s：%s" % [pname, reply], 0.5, other.character_data.current_emotion, ["player", "dialogue"])

func _template_reply(other: AICharacter, player_text: String) -> String:
	## 离线对话模板：按关键词回应玩家，并尽量引用玩家的话，避免答非所问。
	if GameState.is_story_mode():
		return _story_template_reply(other, player_text)
	var text := player_text.strip_edges().to_lower()
	var role := str(other.character_data.role)
	var matched: Array[String] = []
	if _contains_any(text, ["你好", "嗨", "哈啰", "hello", "hi"]):
		matched.append("你好，%s。晶海之畔见到你，是我的荣幸。" % other.character_data.name)
	if _contains_any(text, ["名字", "你是谁", "叫什么", "大名"]):
		matched.append("我是%s，一名%s。你呢，镜外的访客？" % [other.character_data.name, Enums.ROLE_NAMES.get(role, role)])
	if _contains_any(text, ["女娲", "神", "神谕", "启示", "信仰"]):
		matched.append("女娲的意志像晶海的潮汐一样涌动，我能感觉到她正注视着这片土地。")
	if _contains_any(text, ["世界", "文明", "历史", "遗迹", "以前"]):
		matched.append("这片世界已经历过多次兴衰，地表之下还沉睡着前代文明的遗迹。")
	if _contains_any(text, ["能量", "晶体", "食物", "饿", "资源"]):
		matched.append("能量晶体是我们的食粮。最近%s一带的晶体越来越少，大家都在发愁。" % WorldManager.biome_name_at(other.global_position))
	if _contains_any(text, ["建造", "房子", "建筑", "聚落", "家"]):
		matched.append("聚落还在不断扩建。如果你愿意，可以帮我们寻找建材。")
	if _contains_any(text, ["战争", "敌人", "攻击", "危险", "打"]):
		matched.append("晶海的另一边并不平静……我们必须时刻保持警惕。")
	if _contains_any(text, ["帮助", "帮忙", "任务", "需要", "请求"]):
		matched.append("如果你愿意伸出援手，我会把你的善意记在心里。")
	if _contains_any(text, ["怎么样", "还好", "最近", "如何"]):
		matched.append("我最近一直在%s，能量还算充沛，只是有些疲惫。" % WorldManager.biome_name_at(other.global_position))
	if _contains_any(text, ["谢谢", "感谢"]):
		matched.append("不必道谢。晶海会记得每一个善意。")
	if not matched.is_empty():
		return str(matched[randi() % matched.size()])
	# 无关键词命中：按职业回应 + 兜底引用玩家的话，保证与问题有关联
	var pools: Array[String] = []
	match role:
		"priest":
			pools.append("关于「%s」，我常在祈祷中听见晶海深处的低语，也许那就是答案。" % _clip(player_text, 12))
		"guard":
			pools.append("「%s」……这值得警惕。我的职责是守护聚落，我会留意这件事。" % _clip(player_text, 12))
		"scholar":
			pools.append("你提到「%s」，这与我正在研究的遗迹符号或许有关联。" % _clip(player_text, 12))
		"builder":
			pools.append("「%s」是个好想法，扩建聚落正需要这样的主意。" % _clip(player_text, 12))
		"gatherer":
			pools.append("关于「%s」，这片地区的能量晶体分布我比谁都清楚。" % _clip(player_text, 12))
		"explorer":
			pools.append("「%s」——地平线之外确实还有未知的领域，我总想去看一看。" % _clip(player_text, 12))
	pools.append("你刚才说「%s」……我记住了。" % _clip(player_text, 18))
	pools.append("（%s若有所思地点点头）你说的这件事，我会好好想想。" % other.character_data.name)
	return str(pools[randi() % pools.size()])

func _story_template_reply(other: AICharacter, player_text: String) -> String:
	## 剧情模式·三体游戏的离线对话模板：只使用三体世界观（太阳/纪元/脱水/文明轮回），
	## 绝不出现硅灵、晶体、女娲等自由模拟概念。
	var pname := GameState.player_name if GameState.player_name.strip_edges() != "" else "旅人"
	var text := player_text.strip_edges().to_lower()
	var era_name := "这一纪文明"
	if not StoryModeManager.current_era.is_empty():
		era_name = str(StoryModeManager.current_era.get("name", era_name))
	var matched: Array[String] = []
	if _contains_any(text, ["你好", "嗨", "哈啰", "hello", "hi"]):
		matched.append("是你啊，%s。这世道还能遇见活人，是运气。" % pname)
	if _contains_any(text, ["名字", "你是谁", "叫什么", "大名"]):
		matched.append("我是%s。%s里的人，多少听过我的名字。" % [other.character_data.name, era_name])
	if _contains_any(text, ["太阳", "天", "日", "星辰", "星空"]):
		matched.append("太阳的运行毫无规律——连最古老的历法都算不准它。谁参透它，谁就拯救了文明。")
	if _contains_any(text, ["乱纪元", "恒纪元", "纪元", "季节", "寒冷", "炎热"]):
		matched.append("恒纪元是文明生长的间隙，乱纪元是它的刑罚。我们只能祈祷，或脱水。")
	if _contains_any(text, ["脱水", "浸泡", "干燥", "休眠"]):
		matched.append("乱纪元来了就脱水保存，恒纪元来了再浸泡复活——这是文明的生存之道。")
	if _contains_any(text, ["文明", "历史", "轮回", "毁灭", "以前", "遗迹"]):
		matched.append("%s之前，文明已经毁灭过许多次。石碑上刻着的，都是没能活下去的聪明人。" % era_name)
	if _contains_any(text, ["金字塔", "联合国", "王国", "皇帝", "城市"]):
		matched.append("金字塔下聚集着这纪文明最清醒的头脑。我们都在等一个答案。")
	if _contains_any(text, ["三体", "三颗太阳", "三星", "飞星"]):
		matched.append("三颗太阳的引力互相撕扯，没有谁能算出它们的轨道——至今没有。")
	if _contains_any(text, ["帮助", "帮忙", "任务", "需要", "请求"]):
		matched.append("愿意帮忙就好。文明的存续，需要每一个清醒的人。")
	if _contains_any(text, ["谢谢", "感谢"]):
		matched.append("不必谢我。若这纪文明能延续下去，我们都会被记住。")
	if not matched.is_empty():
		return str(matched[randi() % matched.size()])
	var pools: Array[String] = [
		"「%s」……你说得对，太阳的事，谁也不敢妄言。" % _clip(player_text, 12),
		"你提到「%s」。也许这纪文明的命运，就藏在这句话里。" % _clip(player_text, 12),
		"（%s望了一眼天空）关于「%s」，我会记住的。活下去，再谈其他。" % [other.character_data.name, _clip(player_text, 10)]
	]
	return str(pools[randi() % pools.size()])

func _contains_any(text: String, keywords: Array) -> bool:
	for k in keywords:
		if text.find(str(k)) != -1:
			return true
	return false

func _clip(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.substr(0, max_len) + "…"
