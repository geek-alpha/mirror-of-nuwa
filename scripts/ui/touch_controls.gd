class_name TouchControls
extends CanvasLayer
## 移动端触摸控制层：
## - 左下虚拟摇杆：移动（神模式=相机移动，附身模式=角色移动）
## - 右侧区域单指拖动：旋转视角
## - 右侧区域双指捏合：缩放（神模式=调整移动速度，附身模式=拉近/拉远）
## - 右侧区域快速点按：神模式=选中角色/建筑/资源；附身模式=结束文本输入
## - 屏幕边缘快捷按钮：附身/升降/疾跑/缩放/跳跃/交谈/视角/返回神模式
## 仅在触摸设备（或手动开启）时显示；桌面端键鼠控制保持不变。

const JOYSTICK_RADIUS := 52.0
const DEADZONE := 0.15
const TAP_SLOP := 14.0
const PINCH_STEP := 8.0
const JOY_SIZE := 170.0
const JOY_MARGIN := 26.0
const JOY_BOTTOM := 30.0
const BTN_SIZE := Vector2(72, 72)
const BTN_GAP := 8.0
const BTN_RIGHT_MARGIN := 16.0

var _joy_touch := -1
var _joy_origin := Vector2.ZERO
var _joy_vector := Vector2.ZERO
var _look_points: Dictionary = {}  # 触摸 index -> 当前坐标
var _look_starts: Dictionary = {}  # 触摸 index -> 起始坐标
var _pinch_dist := 0.0

var _joystick_ctl: Control = null
var _knob: Panel = null
var _hint_label: Label = null
var _god_buttons: Array[Button] = []
var _possess_buttons: Array[Button] = []

func _ready() -> void:
	layer = 100
	_build_ui()
	_refresh_mode()
	if EventBus != null:
		EventBus.game_mode_changed.connect(func(_m): _refresh_mode())
	_show_hint()

func _build_ui() -> void:
	var root := Control.new()
	root.name = "TouchRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 虚拟摇杆
	_joystick_ctl = Control.new()
	_joystick_ctl.name = "JoystickBase"
	_joystick_ctl.anchor_left = 0.0
	_joystick_ctl.anchor_top = 1.0
	_joystick_ctl.anchor_right = 0.0
	_joystick_ctl.anchor_bottom = 1.0
	_joystick_ctl.offset_left = JOY_MARGIN
	_joystick_ctl.offset_top = -JOY_BOTTOM - JOY_SIZE
	_joystick_ctl.offset_right = JOY_MARGIN + JOY_SIZE
	_joystick_ctl.offset_bottom = -JOY_BOTTOM
	_joystick_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_joystick_ctl)

	var base_style := StyleBoxFlat.new()
	base_style.bg_color = Color(1, 1, 1, 0.12)
	base_style.set_corner_radius_all(int(JOY_SIZE / 2.0))
	var base_panel := Panel.new()
	base_panel.name = "JoystickBasePanel"
	base_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	base_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_panel.add_theme_stylebox_override("panel", base_style)
	_joystick_ctl.add_child(base_panel)

	_knob = Panel.new()
	_knob.name = "JoystickKnob"
	_knob.custom_minimum_size = Vector2(64, 64)
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var knob_style := StyleBoxFlat.new()
	knob_style.bg_color = Color(1, 1, 1, 0.35)
	knob_style.set_corner_radius_all(32)
	_knob.add_theme_stylebox_override("panel", knob_style)
	_joystick_ctl.add_child(_knob)
	_knob.position = Vector2((JOY_SIZE - 64.0) / 2.0, (JOY_SIZE - 64.0) / 2.0)

	# 提示文字
	_hint_label = Label.new()
	_hint_label.name = "ControlHint"
	_hint_label.anchor_left = 0.5
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_right = 0.5
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_left = -360
	_hint_label.offset_top = -152
	_hint_label.offset_right = 360
	_hint_label.offset_bottom = -118
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.modulate = Color(1, 1, 1, 0.9)
	root.add_child(_hint_label)

	# 快捷按钮（自下而上堆叠，贴右下角）
	var god_specs := [
		["附身", func(): PlayerGodController.touch_possess(), ""],
		["升", Callable(), "fly_up"],
		["降", Callable(), "fly_down"],
		["疾跑", Callable(), "sprint"],
	]
	var possess_specs := [
		["跳跃", func(): PlayerGodController.touch_jump(), ""],
		["交谈", func(): PlayerGodController.touch_interact(), ""],
		["疾跑", Callable(), "sprint"],
		["视角", func(): PlayerGodController.touch_toggle_view(), ""],
		["神模式", func(): PlayerGodController.touch_exit_possession(), ""],
	]
	var y := BTN_RIGHT_MARGIN
	for spec in god_specs:
		var b := _make_button(spec[0], spec[1], spec[2])
		_place_button(b, y)
		root.add_child(b)
		_god_buttons.append(b)
		y += BTN_SIZE.y + BTN_GAP
	y = BTN_RIGHT_MARGIN
	for spec in possess_specs:
		var b := _make_button(spec[0], spec[1], spec[2])
		_place_button(b, y)
		root.add_child(b)
		_possess_buttons.append(b)
		y += BTN_SIZE.y + BTN_GAP

func _make_button(text: String, on_press: Callable, hold_action: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BTN_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	if hold_action != "":
		b.button_down.connect(func(): Input.action_press(hold_action))
		b.button_up.connect(func(): Input.action_release(hold_action))
	elif on_press.is_valid():
		b.pressed.connect(on_press)
	return b

func _place_button(b: Button, bottom_gap: float) -> void:
	b.anchor_left = 1.0
	b.anchor_top = 1.0
	b.anchor_right = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = -BTN_RIGHT_MARGIN - BTN_SIZE.x
	b.offset_top = -bottom_gap - BTN_SIZE.y
	b.offset_right = -BTN_RIGHT_MARGIN
	b.offset_bottom = -bottom_gap

func _refresh_mode() -> void:
	if GameState == null:
		return
	var possess: bool = GameState.mode == GameState.Mode.POSSESS
	for b in _god_buttons:
		b.visible = not possess
	for b in _possess_buttons:
		b.visible = possess
	if _hint_label != null:
		_hint_label.text = _hint_text(possess)

func _hint_text(possess: bool) -> String:
	if possess:
		return "左摇杆移动 · 右侧滑动转视角 · 双指缩放 · 点按世界结束输入"
	return "左摇杆移动 · 右侧滑动转视角 · 双指缩放 · 点按世界选中"

func _show_hint() -> void:
	if _hint_label == null:
		return
	_hint_label.modulate.a = 0.9
	_hint_label.visible = true
	var tw := create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(_hint_label, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): _hint_label.visible = false)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_on_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)

func _on_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _joystick_rect().has_point(pos):
			if _joy_touch == -1:
				_joy_touch = idx
				_joy_origin = pos
				_set_joystick(Vector2.ZERO)
			return
		if _is_over_ui(pos):
			return
		if not _look_points.has(idx):
			_look_points[idx] = pos
			_look_starts[idx] = pos
			if _look_points.size() == 2:
				var pts: Array = _look_points.values()
				_pinch_dist = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
		return
	if idx == _joy_touch:
		_joy_touch = -1
		_set_joystick(Vector2.ZERO)
		return
	if _look_points.has(idx):
		var start: Vector2 = _look_starts[idx]
		var moved := pos.distance_to(start)
		_look_points.erase(idx)
		_look_starts.erase(idx)
		_pinch_dist = 0.0
		if moved < TAP_SLOP and _look_points.is_empty():
			_on_tap(start)

func _on_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if idx == _joy_touch:
		var offset := pos - _joy_origin
		var vec := offset / JOYSTICK_RADIUS
		if vec.length() > 1.0:
			vec = vec.normalized()
		_set_joystick(vec)
		return
	if not _look_points.has(idx):
		return
	if _look_points.size() >= 2:
		var before := _pinch_dist
		_look_points[idx] = pos
		if _look_points.size() == 2:
			var pts: Array = _look_points.values()
			var now_dist: float = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			if before > 0.0:
				var delta := now_dist - before
				if absf(delta) >= PINCH_STEP:
					PlayerGodController.touch_zoom(1 if delta > 0.0 else -1)
					_pinch_dist = now_dist
			else:
				_pinch_dist = now_dist
	else:
		_look_points[idx] = pos
		PlayerGodController.touch_look(rel)

func _on_tap(pos: Vector2) -> void:
	if _is_over_ui(pos):
		return
	if GameState.mode == GameState.Mode.GOD:
		PlayerGodController.select_at_screen(pos)
	else:
		get_viewport().gui_release_focus()

func _is_over_ui(pos: Vector2) -> bool:
	# 触摸控件自身的按钮
	for b in _god_buttons:
		if b.visible and b.get_global_rect().has_point(pos):
			return true
	for b in _possess_buttons:
		if b.visible and b.get_global_rect().has_point(pos):
			return true
	# 其他 UI 面板（神面板 / 角色详情 / 对话 / 历史 / 时间控制）
	if UIManager != null and UIManager.ui_layer != null:
		for c in UIManager.ui_layer.get_children():
			if c is Control and c.visible and c.get_global_rect().has_point(pos):
				return true
	return false

func _joystick_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	return Rect2(JOY_MARGIN, vp.y - JOY_BOTTOM - JOY_SIZE, JOY_SIZE, JOY_SIZE)

func _set_joystick(vec: Vector2) -> void:
	_joy_vector = vec
	if _knob != null and _joystick_ctl != null:
		var center := Vector2(JOY_SIZE / 2.0, JOY_SIZE / 2.0)
		_knob.position = center + vec * JOYSTICK_RADIUS - Vector2(32, 32)
	_apply_joystick_actions()

func _apply_joystick_actions() -> void:
	_set_action("move_right", _joy_vector.x > DEADZONE)
	_set_action("move_left", _joy_vector.x < -DEADZONE)
	_set_action("move_forward", _joy_vector.y < -DEADZONE)
	_set_action("move_back", _joy_vector.y > DEADZONE)

func _set_action(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)

## 测试用：直接设置摇杆向量（等价于模拟拖动）
func set_joystick_vector(vec: Vector2) -> void:
	_set_joystick(vec)

func reset_joystick() -> void:
	_set_joystick(Vector2.ZERO)
