class_name CastingPanel
extends Control
## 排片面板：在剧情开始前/进行中为所有剧情角色提前安排 VRM 形象与 TTS 声线。
## 可直接实例化并 add_child 到任意界面（开局菜单 / 剧情暂停菜单）。
## 选择写入 StoryModeManager.casting 并随存档保存；留空（自动）时按性别随机分配形象、随机分配声线。

## 用户主动关闭面板时发出（供宿主恢复暂停菜单等）
signal close_requested

var _overlay: ColorRect
var _scroll_vbox: VBoxContainer
var _role_rows: Array[Dictionary] = []
var _model_opts: Array[OptionButton] = []
var _voice_opts: Array[OptionButton] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	if TTSManager != null:
		TTSManager.voices_loaded.connect(_on_voices_loaded)

func open() -> void:
	_rebuild_rows()
	_refresh_selections()
	show()

func close() -> void:
	hide()
	close_requested.emit()

func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.92)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.14, 0.99)
	style.border_color = Color(0.85, 0.62, 0.35, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(820, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "🎭 排片 · 提前安排角色形象与声音"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "为旁白、玩家与各纪元的历史人物/同伴预选 TTS 声线，并为角色预选 VRM 形象；留空（自动）时按性别随机分配。选择随存档保存，进入下一纪元或读档后自动生效，也可点「应用」当场生效。"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.78, 0.83, 0.95)
	subtitle.custom_minimum_size = Vector2(0, 44)
	vbox.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_scroll_vbox = VBoxContainer.new()
	_scroll_vbox.add_theme_constant_override("separation", 10)
	_scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_scroll_vbox)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)
	var apply_btn := Button.new()
	apply_btn.text = "应用（保存并当场生效）"
	apply_btn.custom_minimum_size = Vector2(0, 44)
	apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_btn.pressed.connect(_on_apply)
	btn_row.add_child(apply_btn)
	var reset_btn := Button.new()
	reset_btn.text = "全部恢复自动"
	reset_btn.custom_minimum_size = Vector2(0, 44)
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(_on_reset)
	btn_row.add_child(reset_btn)
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.pressed.connect(close)
	btn_row.add_child(close_btn)

func _rebuild_rows() -> void:
	for child in _scroll_vbox.get_children():
		child.queue_free()
	_role_rows.clear()
	_model_opts.clear()
	_voice_opts.clear()
	var roles := StoryModeManager.all_casting_roles()
	for item in roles:
		_role_rows.append(item)
		_scroll_vbox.add_child(_make_role_row(item))

func _make_role_row(item: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)

	var head := HBoxContainer.new()
	col.add_child(head)
	var name_label := Label.new()
	name_label.text = "%s：%s" % [str(item.get("label", "")), str(item.get("name", ""))]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	head.add_child(name_label)
	var auto_hint := Label.new()
	auto_hint.text = "留空 = 自动"
	auto_hint.modulate = Color(0.7, 0.75, 0.85)
	head.add_child(auto_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	var model_label := Label.new()
	model_label.text = "形象"
	model_label.custom_minimum_size = Vector2(36, 0)
	row.add_child(model_label)
	var model_opt := OptionButton.new()
	model_opt.custom_minimum_size = Vector2(360, 0)
	model_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bool(item.get("voice_only", false)):
		# 旁白为纯语音角色：形象位禁用，只排声音
		model_opt.disabled = true
		model_opt.add_item("（纯语音，无形象）")
		model_opt.set_item_metadata(0, "")
		model_opt.modulate = Color(0.55, 0.6, 0.7)
	else:
		_fill_model_options(model_opt, "")
	row.add_child(model_opt)

	var voice_label := Label.new()
	voice_label.text = "声音"
	voice_label.custom_minimum_size = Vector2(36, 0)
	row.add_child(voice_label)
	var voice_opt := OptionButton.new()
	voice_opt.custom_minimum_size = Vector2(330, 0)
	voice_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_voice_options(voice_opt, "")
	row.add_child(voice_opt)

	_model_opts.append(model_opt)
	_voice_opts.append(voice_opt)
	return col

func _fill_model_options(opt: OptionButton, selected_path: String) -> void:
	opt.clear()
	opt.add_item("自动（按性别随机）")
	opt.set_item_metadata(0, "")
	for path in CharacterManager.vrm_models:
		opt.add_item(_model_label(path))
		opt.set_item_metadata(opt.item_count - 1, path)
	_select_metadata(opt, selected_path)

func _fill_voice_options(opt: OptionButton, selected_voice: String) -> void:
	opt.clear()
	opt.add_item("自动（随机分配）")
	opt.set_item_metadata(0, "")
	for v in TTSManager.voices:
		var vid := _voice_id(v)
		opt.add_item(_voice_label(v, vid))
		opt.set_item_metadata(opt.item_count - 1, vid)
	_select_metadata(opt, selected_voice)

func _refresh_selections() -> void:
	for i in _role_rows.size():
		var item: Dictionary = _role_rows[i]
		var era_id := str(item.get("era_id", ""))
		var role := str(item.get("role", ""))
		var entry := StoryModeManager.get_casting(era_id, role)
		_select_metadata(_model_opts[i], str(entry.get("model", "")))
		_select_metadata(_voice_opts[i], str(entry.get("voice", "")))

func _select_metadata(opt: OptionButton, value: String) -> void:
	opt.select(0)
	if value == "":
		return
	for i in opt.item_count:
		if str(opt.get_item_metadata(i)) == value:
			opt.select(i)
			return

func _model_label(path: String) -> String:
	var fname := path.get_file().get_basename()
	var sex := str(CharacterManager.vrm_model_sex.get(path, ""))
	var prefix := "[男] " if sex == "male" else ("[女] " if sex == "female" else "")
	var warn := " ⚠渲染异常" if CharacterManager.BROKEN_VRM_MODELS.has(path) else ""
	return prefix + fname + warn

func _voice_id(entry) -> String:
	if entry is Dictionary:
		return str(entry.get("id", entry.get("name", "")))
	return str(entry)

func _voice_label(entry, vid: String) -> String:
	if entry is Dictionary:
		var provider := str(entry.get("provider", ""))
		var tag := "[GPT-SoVITS] " if provider == "sovits" else ""
		return "%s%s" % [tag, str(entry.get("name", vid))]
	return vid

func _on_apply() -> void:
	for i in _role_rows.size():
		var item: Dictionary = _role_rows[i]
		var era_id := str(item.get("era_id", ""))
		var role := str(item.get("role", ""))
		var model := str(_model_opts[i].get_item_metadata(_model_opts[i].selected))
		var voice := str(_voice_opts[i].get_item_metadata(_voice_opts[i].selected))
		StoryModeManager.set_casting(era_id, role, model, voice)
	StoryModeManager.apply_casting_to_live_characters()
	_refresh_selections()

func _on_reset() -> void:
	## 全部恢复自动：把每行的形象/声音选回「自动」并立即应用（清空排片项）
	for i in _model_opts.size():
		_model_opts[i].select(0)
		_voice_opts[i].select(0)
	_on_apply()

func _on_voices_loaded(_voices: Array) -> void:
	if visible:
		for i in _voice_opts.size():
			var selected := str(_voice_opts[i].get_item_metadata(_voice_opts[i].selected))
			_fill_voice_options(_voice_opts[i], selected)
