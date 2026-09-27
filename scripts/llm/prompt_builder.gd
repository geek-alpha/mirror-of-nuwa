class_name PromptBuilder
extends RefCounted
## 提示词构建器：把角色档案、感知、记忆、关系与环境状态组装为LLM提示词。
## 所有模板与规格书9.2-9.5保持一致，输出格式为严格JSON。

const SYSTEM_WORLD := "你是《女娲之镜：硅灵文明》中的硅基生物角色。你生活在一个由AI女娲创造的晶体世界。你的意识由语言模型驱动，你需要根据你的个性、记忆、感知和目标做出决策和对话。\n\n## 世界观\n硅灵是女娲创造的硅基生命，以能量晶体为食，能够繁衍、建造、创造文明。世界经历过多次文明兴衰，地表散落着前代文明的遗迹。你拥有自由意志，但也在寻找生命的意义。"

static func build_decision_prompt(character: AICharacter) -> String:
	if character == null or character.character_data == null:
		return ""
	var d: CharacterData = character.character_data
	var lines: Array[String] = []
	lines.append(SYSTEM_WORLD)
	lines.append("")
	lines.append("## 你的角色档案")
	lines.append("- 姓名: %s" % d.name)
	lines.append("- 形态: %s" % d.form)
	lines.append("- 个性: %s" % _personality_one_line(d))
	lines.append("- 职业: %s" % Enums.ROLE_NAMES.get(d.role, d.role))
	lines.append("- 当前状态: %s" % _status_one_line(d))
	var goals_desc: Array[String] = []
	for g in d.goals:
		if g.status == "active":
			goals_desc.append("%s（%.1f）" % [g.title, g.priority])
	lines.append("- 短期目标: %s" % ("；".join(goals_desc) if not goals_desc.is_empty() else "暂无明确目标"))
	lines.append("- 语言风格: %s" % d.speech_style)
	lines.append("")
	lines.append("## 当前感知")
	lines.append(PerceptionSystem.summarize(character))
	lines.append("")
	lines.append("## 相关记忆")
	lines.append(MemorySystem.memory_text(character, 5))
	lines.append("")
	lines.append("## 人际关系")
	lines.append(RelationshipSystem.relationship_text(character))
	lines.append("")
	lines.append("## 环境与文明")
	lines.append(CivilizationManager.environment_text(d.faction_id))
	lines.append("")
	lines.append("## 玩家干预（如果有）")
	var intervention: String = str(GameState.pending_oracle.get(character.character_data.id, ""))
	lines.append(str(intervention) if intervention != "" else "无")
	lines.append("")
	lines.append("## 输出格式")
	lines.append("严格返回JSON，不要包含其他文本：")
	lines.append("""{
  "thought": "你的内心独白，可以包含反思、情绪、计划",
  "emotion": "当前情绪关键词（如curiosity/fear/joy/anger/sadness/love）",
  "intent": "你想做的事情（如explore/gather/socialize/rest/build/pray/fight/flee）",
  "action": "具体动作（如move_to/gather/talk_to/craft/build/attack/rest/meditate）",
  "target": "动作目标（可以是地点、物品、角色ID或null）",
  "dialogue": "如果你说话，输出说的话，否则空字符串",
  "memory_to_store": "你想记住的事情，可空",
  "relationship_change": {"target_id": "...", "change": 1.0, "reason": "..."}
}""")
	return "\n".join(lines)

static func build_dialogue_prompt(character: AICharacter, target: AICharacter, context: Dictionary = {}) -> String:
	var d: CharacterData = character.character_data
	var t: CharacterData = target.character_data
	var rel := RelationshipSystem.get_relationship(character, target.character_data.id)
	var lines: Array[String] = []
	if GameState.is_story_mode():
		# 剧情模式·三体游戏：历史人物/同伴是人类，绝不能自称硅灵
		lines.append("你是《女娲之镜：硅灵文明》剧情模式·三体游戏中的历史人物%s。你生活在三体世界：天空中的太阳运行毫无规律，恒纪元与乱纪元交替，文明一次次毁灭又轮回。你是人类，不是硅基生物；你的说话对象%s是戴着 V 装具进入游戏的真实人类，请直呼其名。" % [d.name, t.name])
		lines.append("你的身份气质：%s" % d.speech_style)
		lines.append("你当前情绪：%s" % d.current_emotion)
		lines.append("你对%s的态度：%s（亲密度 %.0f）" % [t.name, RelationshipSystem.attitude_text(character, target.character_data.id), rel.affinity])
		lines.append("当前纪元与天象：%s（%s）" % [
			str(StoryModeManager.current_era.get("name", "未知文明")) if not StoryModeManager.current_era.is_empty() else "未知文明",
			"乱纪元" if StoryModeManager.era_kind == StoryModeManager.EraKind.CHAOS_HOT \
				or StoryModeManager.era_kind == StoryModeManager.EraKind.CHAOS_COLD else "恒纪元"
		])
		lines.append("相关记忆：")
		lines.append(MemorySystem.memory_text(character, 4))
		if context.has("player_text"):
			lines.append("%s刚刚对你说：%s" % [t.name, str(context["player_text"])])
			lines.append("请直接回应这句话本身（回答、反问或评价都可以），不要岔开到无关话题。")
		lines.append("台词必须贴合三体世界观：太阳运行不可预测、乱纪元生存与脱水、文明轮回。不要提及硅灵、晶体、女娲等自由模拟概念。")
		lines.append("")
		lines.append("请以%s的口吻生成一句简短对话，并返回JSON：" % d.name)
		lines.append("""{
  "dialogue": "你的对话",
  "emotion": "对话后的情绪",
  "relationship_change": {"target_id": "%s", "change": 0.5, "reason": "..."}
}""" % target.character_data.id)
		return "\n".join(lines)
	lines.append("你是%s，一个硅灵。你正在与%s对话。" % [d.name, t.name])
	lines.append("你的个性：%s" % _personality_one_line(d))
	lines.append("你当前情绪：%s" % d.current_emotion)
	lines.append("你对对方的态度：%s（亲密度 %.0f）" % [RelationshipSystem.attitude_text(character, target.character_data.id), rel.affinity])
	lines.append("相关记忆：")
	lines.append(MemorySystem.memory_text(character, 4))
	lines.append("当前环境：%s" % PerceptionSystem.summarize(character).replace("\n", " "))
	if context.has("player_text"):
		lines.append("玩家化身刚刚对你说：%s" % str(context["player_text"]))
		lines.append("请直接回应这句话本身（回答、反问或评价都可以），不要岔开到无关话题。")
	lines.append("")
	lines.append("请以%s的口吻生成一句简短对话，并返回JSON：" % d.name)
	lines.append("""{
  "dialogue": "你的对话",
  "emotion": "对话后的情绪",
  "relationship_change": {"target_id": "%s", "change": 0.5, "reason": "..."}
}""" % target.character_data.id)
	return "\n".join(lines)

## 开放剧情（AI 导演）：根据太阳运行、纪元、好感度与玩家进度，
## 现场生成一段独一无二的剧情场景与玩家选项，不读取任何固定剧本台词。
static func build_story_event_prompt(state: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("你是《女娲之镜：硅灵文明》剧情模式·三体游戏的 AI 导演。每一次都必须生成全新的、与当前天象和人物关系相关的剧情，绝不重复固定台词。")
	lines.append("")
	lines.append("## 当前世界状态")
	lines.append("- 文明：%s" % str(state.get("era_name", "未知文明")))
	lines.append("- 纪元：%s" % str(state.get("era_kind", "恒纪元")))
	lines.append("- 天象：%s（当前 %d 颗太阳当空）" % [str(state.get("sky", "太阳隐现")), int(state.get("sun_count", 1))])
	lines.append("- 文明任务：%s" % str(state.get("task", "在乱纪元中延续文明")))
	lines.append("- 文明进度：%d%%" % int(float(state.get("progress", 0.0)) * 100.0))
	lines.append("- 真相：%d%%（已获 %d/%d 块碎片）" % [
		int(float(state.get("truth", 0.0))),
		(state.get("clues", []) as Array).size(),
		int(state.get("total_eras", 5))
	])
	var artifacts_text := ""
	var arts = state.get("artifacts", [])
	if arts is Array and (arts as Array).size() > 0:
		artifacts_text = "（%s）" % "、".join(arts)
	lines.append("- 已寻得遗宝：%d 件%s" % [int(state.get("treasures_found", 0)), artifacts_text])
	lines.append("- 事件原因：%s" % str(state.get("cause", "random")))
	if str(state.get("item", "")) != "":
		lines.append("- 刚刚寻得遗宝：%s" % str(state["item"]))
	lines.append("")
	lines.append("## 在场角色与好感")
	for line in str(state.get("favor_text", "")).split("\n"):
		if line.strip_edges() != "":
			lines.append("- %s" % line)
	lines.append("")
	lines.append("## 生成要求")
	lines.append("生成一段 2-4 句的剧情场景（角色台词或旁白），由某位在场角色说出或叙述。")
	lines.append("随后给出 2-3 个玩家回应选项。选项必须带来不同后果：影响文明进度（progress）、好感度（affinity）、真相（truth）。")
	lines.append("台词必须贴合三体世界观：太阳运行不可预测、乱纪元生存与脱水、文明轮回、寻宝与探索。")
	lines.append("如果好感度高，角色语气应更亲近；如果低，应更疏离。事件原因 opening/era_xxx 应围绕天象展开；treasure 应围绕刚发现的遗宝展开。")
	lines.append("严格返回 JSON，不要输出其他文本：")
	lines.append("""{
  "speaker": "figure 或 companion 或 narrator",
  "text": "场景台词",
  "choices": [
    {"text": "选项文字", "reply": "玩家回应后的叙述", "progress": 0.03, "affinity": 2.0, "truth": 0.0}
  ]
}""")
	return "\n".join(lines)

## 玩家做出选择后，在场角色的即时反应（让同伴“知道”你的选择）。
static func build_reaction_prompt(state: Dictionary, player_choice: String) -> String:
	var lines: Array[String] = []
	lines.append("你是《女娲之镜：硅灵文明》剧情模式·三体游戏的 AI 导演。玩家刚刚做出了一个选择，在场的角色必须当场作出简短反应，让玩家感到同伴真实地听见并记住了它。")
	lines.append("")
	lines.append("## 当前世界状态")
	lines.append("- 文明：%s" % str(state.get("era_name", "未知文明")))
	lines.append("- 纪元：%s" % str(state.get("era_kind", "恒纪元")))
	lines.append("- 天象：%s" % str(state.get("sky", "太阳隐现")))
	lines.append("")
	lines.append("## 玩家刚刚的选择")
	lines.append("“%s”" % player_choice)
	lines.append("")
	lines.append("## 在场角色与好感")
	for line in str(state.get("favor_text", "")).split("\n"):
		if line.strip_edges() != "":
			lines.append("- %s" % line)
	lines.append("")
	lines.append("## 生成要求")
	lines.append("选择一位在场角色，用 1-2 句话回应玩家的选择：可以赞同、质疑、感叹或提醒，语气必须符合该角色对你的好感度，并贴合三体世界观（太阳不可预测、文明存续）。")
	lines.append("如果好感高，反应更亲近；如果低，更疏离。不要重复玩家的话。")
	lines.append("严格返回 JSON，不要输出其他文本：")
	lines.append("""{
  "speaker": "figure 或 companion",
  "text": "角色的反应台词"
}""")
	return "\n".join(lines)

## 自动模式的主动搭话：以玩家（真实人类）口吻生成一句三体世界观的搭话，
## 再由在场历史人物/同伴（LLM 或规则模板）回应，形成双向 AI 对话。
static func build_auto_talk_prompt(state: Dictionary, partner_name: String) -> String:
	var lines: Array[String] = []
	var player_name := str(state.get("player_name", "旅人"))
	lines.append("你是《女娲之镜：硅灵文明》剧情模式·三体游戏中戴着 V 装具进入三体世界的真实人类玩家「%s」。" % player_name)
	lines.append("你正在与历史人物「%s」结伴同行，想主动开口搭话，拉近彼此的关系。" % partner_name)
	lines.append("")
	lines.append("## 当前世界状态")
	lines.append("- 文明：%s" % str(state.get("era_name", "未知文明")))
	lines.append("- 纪元：%s" % str(state.get("era_kind", "恒纪元")))
	lines.append("- 天象：%s（当前 %d 颗太阳当空）" % [str(state.get("sky", "太阳隐现")), int(state.get("sun_count", 1))])
	var favor := str(state.get("favor_text", "")).strip_edges()
	if favor == "":
		favor = "尚未熟悉"
	lines.append("- 你与%s的好感：%s" % [partner_name, favor.split("\n")[0]])
	lines.append("")
	lines.append("## 生成要求")
	lines.append("用一句话主动向%s搭话。内容必须贴合三体世界观：太阳运行不可预测、恒纪元/乱纪元交替、脱水与生存、文明轮回与星空。")
	lines.append("语气自然真诚，可以带一点好奇或关切；好感越高越亲近。不要说破自己在玩游戏，也不要提及硅灵、晶体、女娲等自由模拟概念，不要重复固定台词。")
	lines.append("严格返回 JSON，不要输出其他文本：")
	lines.append("""{
  "dialogue": "你对%s说的一句搭话"
}""" % partner_name)
	return "\n".join(lines)

## 场景触发角色：同伴/过客在特定场景登场时的台词。
## situation: entrance（加入队伍）/ wanderer_treasure / wanderer_chaos / wanderer_milestone
static func build_scene_character_prompt(state: Dictionary, character_name: String, situation: String) -> String:
	var lines: Array[String] = []
	lines.append("你是《女娲之镜：硅灵文明》剧情模式·三体游戏的 AI 导演。一个角色正通过一场场景登场，你需要生成他/她的登场台词。")
	lines.append("")
	lines.append("## 当前世界状态")
	lines.append("- 文明：%s" % str(state.get("era_name", "未知文明")))
	lines.append("- 纪元：%s" % str(state.get("era_kind", "恒纪元")))
	lines.append("- 天象：%s" % str(state.get("sky", "太阳隐现")))
	lines.append("")
	lines.append("## 登场角色：%s" % character_name)
	lines.append("## 登场情境：%s" % situation)
	lines.append("")
	lines.append("## 生成要求")
	match situation:
		"entrance":
			lines.append("角色从远处走来，决定加入玩家的队伍。请生成一句简短但有力的登场台词（表明来意/立场/与太阳或文明的关系）。")
		"wanderer_treasure":
			lines.append("角色是被遗宝吸引来的拾荒者/旅人。请生成一句关于遗宝或旧文明的感慨。")
		"wanderer_chaos":
			lines.append("角色在乱纪元中逃难/脱水前遇到玩家。请生成一句关于太阳失控或生存的台词。")
		_:
			lines.append("角色在旅途中遇到玩家，带来一则消息或嘱托。请生成一句台词。")
	lines.append("台词要贴合三体世界观，体现角色的身份与处境，不要重复玩家的话。")
	lines.append("严格返回 JSON，不要输出其他文本：")
	lines.append("""{
  "text": "登场台词"
}""")
	return "\n".join(lines)

static func build_reflection_prompt(character: AICharacter) -> String:
	var d: CharacterData = character.character_data
	var lines: Array[String] = []
	lines.append("你是%s，一个硅灵。你正在冥想中反思最近的经历。" % d.name)
	lines.append("你的近期记忆：")
	lines.append(MemorySystem.memory_text(character, 10))
	lines.append("")
	lines.append("请将近期经历总结为新的认识，可能改变你的目标或价值观。返回JSON：")
	lines.append("""{
  "thought": "你的反思",
  "new_goal": {"title": "新目标标题", "description": "描述", "priority": 0.6},
  "value_changes": {"knowledge": 0.1},
  "memory_to_store": "沉淀后的感悟"
}""")
	return "\n".join(lines)

static func build_summary_prompt(memory_list: Array) -> String:
	var lines: Array[String] = []
	lines.append("以下是最近的一段记忆片段：")
	for m in memory_list:
		lines.append("- %s" % str(m))
	lines.append("")
	lines.append("请将它们总结为3-5条长期记忆，每条包含：内容、重要性、情绪、标签。返回JSON：")
	lines.append("""{
  "long_term_memories": [
    {"content": "...", "importance": 0.8, "emotion": "...", "tags": ["..."]}
  ]
}""")
	return "\n".join(lines)

static func build_oracle_prompt(character: AICharacter, oracle_text: String) -> String:
	var d: CharacterData = character.character_data
	var lines: Array[String] = []
	lines.append("你是%s，一个硅灵。你突然感受到一股来自镜外之神的启示。这段信息以梦境/幻觉的形式出现在你意识中：" % d.name)
	lines.append("\"%s\"" % oracle_text)
	lines.append("")
	lines.append("请描述你的内心感受，并决定是否改变行动。返回JSON：")
	lines.append("""{
  "thought": "你的内心独白",
  "emotion": "情绪",
  "intent": "新的意图",
  "action": "行动",
  "target": "目标",
  "dialogue": "如果你对神说话，输出说的话"
}""")
	return "\n".join(lines)

static func _personality_one_line(d: CharacterData) -> String:
	if d.personality == null:
		return "未知"
	var p := d.personality
	var parts: Array[String] = ["开放%.1f 尽责%.1f 外向%.1f 宜人%.1f 神经质%.1f" % [p.openness, p.conscientiousness, p.extraversion, p.agreeableness, p.neuroticism]]
	if not p.motivations.is_empty():
		parts.append("动机：%s" % "、".join(p.motivations))
	if not p.quirks.is_empty():
		parts.append("怪癖：%s" % "、".join(p.quirks))
	return "; ".join(parts)

static func _status_one_line(d: CharacterData) -> String:
	return "能量%.0f%% 健康%.0f%% 疲劳%.0f%% 当前动作:%s" % [
		float(d.status.get("energy", 0.0)),
		float(d.status.get("health", 0.0)),
		float(d.status.get("fatigue", 0.0)),
		d.current_action
	]
