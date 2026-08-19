class_name GodCamera
extends Camera3D
## 上帝相机：自由飞行、右键观察、左键由玩家控制器做选中射线。
## 按住方向键线性加速移动，松手后平滑减速至静止。

const MAX_SPEED := 12.0
const SPRINT_MULT := 2.5
const MOVE_ACCEL := 16.0
const MOVE_DECEL := 24.0
var yaw := 0.0
var pitch := -0.55
var dragging := false
var velocity := Vector3.ZERO

func _ready() -> void:
	fov = 70.0
	global_position = Vector3(0, 45, 45)
	_apply_rotation()

func _input(event: InputEvent) -> void:
	# 过场演出期间相机完全由导演接管
	if GameState.input_locked:
		return
	# 附身模式下上帝相机不响应输入，避免相机在附身期间漂移
	if GameState.mode != GameState.Mode.GOD:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		dragging = event.pressed
		if dragging:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch - event.relative.y * 0.005, -1.45, 1.45)
		_apply_rotation()

func _apply_rotation() -> void:
	rotation = Vector3(pitch, yaw, 0.0)

## 移动端：右侧单指拖动旋转视角
func touch_orbit(relative: Vector2) -> void:
	if GameState.input_locked:
		return
	if GameState.mode != GameState.Mode.GOD:
		return
	yaw -= relative.x * 0.005
	pitch = clampf(pitch - relative.y * 0.005, -1.45, 1.45)
	_apply_rotation()

## 过场收尾衔接：把上帝相机朝向对齐到动画相机最后视线（view = (yaw, pitch)）
func snap_view(view: Vector2) -> void:
	yaw = view.x
	pitch = clampf(view.y, -1.45, 1.45)
	_apply_rotation()

func _process(delta: float) -> void:
	if GameState.input_locked:
		return
	if GameState.mode != GameState.Mode.GOD or UIManager.text_input_active():
		return
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir -= transform.basis.z
	if Input.is_action_pressed("move_back"):
		dir += transform.basis.z
	if Input.is_action_pressed("move_left"):
		dir -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		dir += transform.basis.x
	if Input.is_action_pressed("fly_up"):
		dir += Vector3.UP
	if Input.is_action_pressed("fly_down"):
		dir += Vector3.DOWN
	if dir.length_squared() > 0.01:
		# 持续按住方向线性加速，直到达到上限
		var max_speed := MAX_SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
		var target_vel := dir.normalized() * max_speed
		velocity = velocity.move_toward(target_vel, MOVE_ACCEL * delta)
	else:
		# 松手后线性减速，恢复静止
		velocity = velocity.move_toward(Vector3.ZERO, MOVE_DECEL * delta)
	if velocity.length() > 0.01:
		global_position += velocity * delta
		global_position.y = clampf(global_position.y, 2.0, 120.0)
