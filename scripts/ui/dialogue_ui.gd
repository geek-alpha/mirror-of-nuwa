class_name DialogueUI
extends Control
## 对话界面：化身模式下与AI角色聊天。

var log_label: RichTextLabel
var input: LineEdit
var _log_buffer: Array[String] = []

const MAX_LOG_LINES := 120

func _ready() -> void:
	# 锚点定位到右上角：直接用偏移量，避免 set_position 被当作绝对坐标导致面板跑到屏幕外
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -500
	offset_top = 58
	offset_right = -20
	offset_bottom = 288
	custom_minimum_size = Vector2(480, 230)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 230)
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(0, 150)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(log_label)
	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)
	input = LineEdit.new()
	input.placeholder_text = "输入你想说的话… 回车发送，Esc 退出输入"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(func(_t): _submit())
	UIManager.wire_virtual_keyboard(input)
	hbox.add_child(input)
	var send_btn := Button.new()
	send_btn.text = "发送"
	send_btn.pressed.connect(_submit)
	hbox.add_child(send_btn)
	var clear_btn := Button.new()
	clear_btn.text = "清空记录"
	clear_btn.pressed.connect(clear_log)
	hbox.add_child(clear_btn)

func _submit() -> void:
	var text := input.text.strip_edges()
	if text == "":
		return
	var ctx: Dictionary = UIManager.dialogue_context
	var character = ctx.get("player", null)
	var other = ctx.get("other", null)
	if character == null:
		return
	if other == null or not is_instance_valid(other):
		other = _nearest_in_range(character)
		if other == null:
			append_system("附近没有可以交谈的硅灵（距离过远），请靠近后再发送。")
			input.clear()
			return
		ctx["other"] = other
	elif other.global_position.distance_to(character.global_position) > 4.5:
		other = _nearest_in_range(character)
		if other == null:
			append_system("对方已走远，附近没有可以交谈的硅灵，请靠近后再发送。")
			input.clear()
			return
		ctx["other"] = other
		append_system("已切换到更近的%s继续交谈。" % other.character_data.name)
	append_line("你", text)
	PlayerGodController.interaction.send_player_dialogue(character, other, text)
	input.clear()
	if UIManager.is_mobile():
		input.grab_focus()
		UIManager.show_virtual_keyboard(input)
	else:
		input.release_focus()

func open(character, other) -> void:
	var same_pair: bool = UIManager.dialogue_context.get("player") == character \
		and UIManager.dialogue_context.get("other") == other
	UIManager.dialogue_context = {"player": character, "other": other}
	if not same_pair:
		log_label.clear()
		if other != null and is_instance_valid(other) and other.character_data != null:
			append_system("你走近%s，%s停下来看向你。" % [other.character_data.name, other.character_data.name])
			# 双方转身 + NPC 主动问候，避免进入对话过于突兀
			if character != null and is_instance_valid(character):
				character.face_towards(other.global_position)
			other.greet(character)
		else:
			append_system("你开始交谈。输入文字与TA对话，AI角色会记住你说过的话。")
		visible = true
		# 面板淡入，而不是瞬间弹出
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
		_grab_focus_later(0.45)
	else:
		visible = true
		_grab_focus_later(0.1)

func _grab_focus_later(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(self) and visible and input != null and is_instance_valid(input):
		input.grab_focus()
		if UIManager.is_mobile():
			UIManager.show_virtual_keyboard(input)

func append_line(speaker: String, text: String) -> void:
	_push_line("[b]%s：[/b]%s\n" % [speaker, text])

func append_system(text: String) -> void:
	_push_line("[color=#8fd0ff]%s[/color]\n" % text)

func _push_line(bbcode: String) -> void:
	_log_buffer.append(bbcode)
	if _log_buffer.size() > MAX_LOG_LINES:
		_log_buffer.pop_front()
	log_label.clear()
	log_label.append_text("".join(_log_buffer))

func _nearest_in_range(character) -> AICharacter:
	var best: AICharacter = null
	var best_dist := INF
	for c in PerceptionSystem.characters_in_radius(character.global_position, 4.5, [character]):
		var d: float = c.global_position.distance_to(character.global_position)
		if d < best_dist:
			best_dist = d
			best = c
	return best

func clear_log() -> void:
	_log_buffer.clear()
	log_label.clear()
