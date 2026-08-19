extends Node
## UI管理器：实例化各UI场景，协调显示与刷新，提供全局UI查询辅助。

var ui_layer: CanvasLayer = null
var god_panel: GodPanel = null
var character_sheet: CharacterSheet = null
var dialogue_ui: DialogueUI = null
var history_ui: HistoryUI = null
var time_controls: TimeControls = null
var touch_controls: TouchControls = null
var story_ui: StoryUI = null
var _mobile_controls := false
var dialogue_context: Dictionary = {}
var _touch_controls_saved_visible := false

func _ready() -> void:
	EventBus.time_scale_changed.connect(func(_s): if time_controls: time_controls.refresh())
	EventBus.character_selected.connect(func(_c): if character_sheet: character_sheet.refresh())
	EventBus.history_updated.connect(func(): if history_ui: history_ui.refresh())
	EventBus.character_died.connect(func(_c): if character_sheet: character_sheet.refresh())
	EventBus.world_regenerated.connect(func(): if time_controls: time_controls.refresh())
	EventBus.game_mode_changed.connect(func(_m): if character_sheet: character_sheet.refresh())
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)

func _process(_delta: float) -> void:
	if character_sheet != null and character_sheet.visible:
		character_sheet.refresh()
	if god_panel != null:
		god_panel.refresh()
	if time_controls != null:
		time_controls.refresh()

func setup() -> void:
	# 开局菜单与主场景之间会来回切换，UI 层挂在全局单例上，
	# 已有 UI 层时直接复用，避免重复实例化面板。
	if ui_layer != null and is_instance_valid(ui_layer):
		_apply_mode_ui_visibility()
		return
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 10
	add_child(ui_layer)
	god_panel = preload("res://scenes/ui/god_panel.tscn").instantiate() as GodPanel
	ui_layer.add_child(god_panel)
	character_sheet = preload("res://scenes/ui/character_sheet.tscn").instantiate() as CharacterSheet
	ui_layer.add_child(character_sheet)
	character_sheet.hide()
	dialogue_ui = preload("res://scenes/ui/dialogue_ui.tscn").instantiate() as DialogueUI
	ui_layer.add_child(dialogue_ui)
	# 对话框常驻：开局即显示，全程保留聊天记录
	dialogue_ui.visible = true
	history_ui = preload("res://scenes/ui/history_ui.tscn").instantiate() as HistoryUI
	ui_layer.add_child(history_ui)
	history_ui.hide()
	time_controls = preload("res://scenes/ui/time_controls.tscn").instantiate() as TimeControls
	ui_layer.add_child(time_controls)
	touch_controls = preload("res://scenes/ui/touch_controls.tscn").instantiate() as TouchControls
	touch_controls.name = "TouchControls"
	add_child(touch_controls)
	# 剧情模式：三体游戏界面（置于最上层）
	if GameState.is_story_mode():
		story_ui = preload("res://scenes/ui/story_ui.tscn").instantiate() as StoryUI
		ui_layer.add_child(story_ui)
	_apply_mode_ui_visibility()
	_mobile_controls = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") \
		or bool(ProjectSettings.get_setting("application/config/force_mobile_controls", false))
	touch_controls.visible = _mobile_controls
	refresh_all()

func _apply_mode_ui_visibility() -> void:
	## 按游戏模式切换通用 UI：剧情模式隐藏上帝面板/对话窗，避免与剧情 HUD 堆叠。
	if GameState.is_story_mode():
		if god_panel:
			god_panel.hide()
		if character_sheet:
			character_sheet.hide()
		if dialogue_ui:
			dialogue_ui.hide()
		if history_ui:
			history_ui.hide()
		if time_controls:
			time_controls.hide()
	else:
		if god_panel:
			god_panel.show()
		if dialogue_ui:
			dialogue_ui.show()
		if time_controls:
			time_controls.show()

func is_mobile() -> bool:
	return _mobile_controls

## 过场/引言演出期间隐藏触摸摇杆，保证屏幕干净；结束后恢复
func set_cutscene_ui_active(active: bool) -> void:
	if touch_controls == null:
		return
	if active:
		_touch_controls_saved_visible = touch_controls.visible
		touch_controls.visible = false
	else:
		touch_controls.visible = _touch_controls_saved_visible

func force_mobile_controls(on: bool) -> void:
	_mobile_controls = on
	if touch_controls != null:
		touch_controls.visible = on

func _on_gui_focus_changed(control: Control) -> void:
	## 移动端：任意输入框获得焦点时显式弹出系统键盘，
	## 规避 Android 上软键盘隐藏后再次点击不弹出的平台问题。
	if is_mobile() and (control is LineEdit or control is TextEdit):
		DisplayServer.virtual_keyboard_show(str(control.text))

func wire_virtual_keyboard(edit: Control) -> void:
	## 移动端：输入框被点击（包括已聚焦后再次点击）时确保弹出键盘。
	if edit == null:
		return
	edit.gui_input.connect(func(event: InputEvent) -> void:
		var pressed := false
		if event is InputEventScreenTouch:
			pressed = event.pressed
		elif event is InputEventMouseButton:
			pressed = event.pressed
		if pressed:
			show_virtual_keyboard(edit)
	)

func show_virtual_keyboard(edit: Control) -> void:
	if not is_mobile():
		return
	if edit is LineEdit or edit is TextEdit:
		if not edit.has_focus():
			edit.grab_focus()
		DisplayServer.virtual_keyboard_show(str(edit.text))

func refresh_all() -> void:
	if god_panel:
		god_panel.refresh()
	if character_sheet:
		character_sheet.refresh()
	if time_controls:
		time_controls.refresh()
	if history_ui:
		history_ui.refresh()

func on_possession_started(character) -> void:
	dialogue_context = {"player": character, "other": null}
	if GameState.is_story_mode():
		# 剧情模式下系统提示进入左侧“最近事件”，不再弹出右上角对话窗
		if dialogue_ui:
			dialogue_ui.hide()
		append_system_message("你已化身%s。查看左上「下一步」指引行动。" % character.character_data.name)
		return
	if dialogue_ui:
		dialogue_ui.visible = true
		if is_mobile():
			dialogue_ui.append_system(
				"你已化身%s。左侧摇杆移动，右侧滑动转视角，双指缩放，点按世界可结束输入。"
				% character.character_data.name
			)
			dialogue_ui.append_system("点击【交谈】对话、【跳跃】跳跃、【疾跑】加速、【视角】切换人称、【神模式】返回上帝视角。")
		else:
			dialogue_ui.append_system(
				"你已化身%s。WASD移动 / Shift疾跑 / 空格跳跃；按住右键环绕视角，滚轮拉近拉远；"
				% character.character_data.name
			)
			dialogue_ui.append_system("按 V 切换第一人称；按 F 交谈；回车发送、Esc 退出输入；按 G 回到神模式。")

func on_possession_ended(message := "对话结束") -> void:
	dialogue_context = {}
	if GameState.is_story_mode():
		if dialogue_ui:
			dialogue_ui.hide()
		append_system_message(message)
		return
	if dialogue_ui:
		dialogue_ui.visible = true
		dialogue_ui.append_system(message)

func on_character_spoke(character, text: String) -> void:
	## 玩家范围内的所有台词进入对话框日志。
	if dialogue_ui == null or text.strip_edges() == "":
		return
	if character == null or not is_instance_valid(character) or not TTSManager.is_near_player(character):
		return
	var speaker_name := str(character.character_data.name) if character.character_data != null else str(character.name)
	dialogue_ui.append_line(speaker_name, text)

func open_dialogue(character, other) -> void:
	if dialogue_ui:
		dialogue_ui.open(character, other)

func append_dialogue(speaker: String, text: String) -> void:
	if dialogue_ui:
		dialogue_ui.append_line(speaker, text)

func append_system_message(text: String) -> void:
	## 显示系统提示（若对话面板未打开则打开它），用于交互反馈。
	## 剧情模式下重定向到剧情 HUD 的“最近事件”流。
	if GameState.is_story_mode() and story_ui != null and is_instance_valid(story_ui):
		story_ui.push_event(text)
		return
	if dialogue_ui:
		dialogue_ui.visible = true
		dialogue_ui.append_system(text)

func dialogue_visible() -> bool:
	return dialogue_ui != null and dialogue_ui.visible

func toggle_history(character_id: String = "") -> void:
	if history_ui == null:
		return
	if history_ui.visible:
		history_ui.hide()
	else:
		history_ui.show_for(character_id)

func show_history(character_id: String) -> void:
	if history_ui:
		history_ui.show_for(character_id)

func text_input_active() -> bool:
	if ui_layer == null or not is_instance_valid(ui_layer):
		return false
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit

func is_pointer_over_ui() -> bool:
	if ui_layer == null:
		return false
	return get_viewport().gui_get_hovered_control() != null
