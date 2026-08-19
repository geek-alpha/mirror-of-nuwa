class_name CharacterSheet
extends Control
## 角色详情面板：查看选中角色的状态、个性、记忆、关系，并提供附身入口。

var name_label: Label
var info_label: Label
var status_label: Label
var personality_label: Label
var goals_label: Label
var memories_label: RichTextLabel
var relations_label: RichTextLabel
var current_character = null

func _ready() -> void:
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -330
	offset_top = 60
	offset_right = -10
	offset_bottom = 560
	custom_minimum_size = Vector2(320, 0)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(name_label)
	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info_label)
	status_label = Label.new()
	vbox.add_child(status_label)
	personality_label = Label.new()
	personality_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	personality_label.custom_minimum_size = Vector2(0, 60)
	vbox.add_child(personality_label)
	goals_label = Label.new()
	goals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(goals_label)
	memories_label = RichTextLabel.new()
	memories_label.bbcode_enabled = true
	memories_label.custom_minimum_size = Vector2(0, 100)
	memories_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(memories_label)
	relations_label = RichTextLabel.new()
	relations_label.bbcode_enabled = true
	relations_label.custom_minimum_size = Vector2(0, 90)
	relations_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(relations_label)
	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)
	var possess_btn := Button.new()
	possess_btn.text = "附身"
	possess_btn.pressed.connect(_on_possess)
	hbox.add_child(possess_btn)
	var bio_btn := Button.new()
	bio_btn.text = "传记"
	bio_btn.pressed.connect(_on_biography)
	hbox.add_child(bio_btn)
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(func(): hide())
	hbox.add_child(close_btn)

func refresh() -> void:
	if name_label == null:
		return
	current_character = GameState.selected_character
	if current_character == null or not is_instance_valid(current_character) or current_character.character_data == null:
		name_label.text = "未选中角色"
		info_label.text = "点击世界中的硅灵查看详情"
		status_label.text = ""
		personality_label.text = ""
		goals_label.text = ""
		memories_label.text = ""
		relations_label.text = ""
		return
	var d: CharacterData = current_character.character_data
	name_label.text = "%s（%s）" % [d.name, CivilizationManager.faction_name(d.faction_id)]
	info_label.text = "形态：%s | 职业：%s | 情绪：%s\n当前动作：%s" % [
		d.form,
		Enums.ROLE_NAMES.get(d.role, d.role),
		d.current_emotion,
		d.current_action
	]
	status_label.text = current_character.get_status_text()
	personality_label.text = "个性：\n%s" % d.personality.summary_text() if d.personality else ""
	var goals_desc: Array[String] = []
	for g in d.goals:
		if g.status == "active":
			goals_desc.append("• %s（%.1f）" % [g.title, g.priority])
	goals_label.text = "目标：\n" + ("\n".join(goals_desc) if not goals_desc.is_empty() else "暂无")
	memories_label.text = "最近记忆：\n" + MemorySystem.memory_text(current_character, 4)
	relations_label.text = "关系：\n" + RelationshipSystem.relationship_text(current_character, 4)

func _on_possess() -> void:
	if current_character != null and is_instance_valid(current_character):
		PlayerGodController.possess(current_character)

func _on_biography() -> void:
	if current_character != null:
		UIManager.show_history(current_character.character_data.id)
