class_name PossessionController
extends Camera3D
## 化身相机：第三人称环绕（可拉近拉远、上下无死角观察）与第一人称视角切换。
## 按住右键拖动环绕；滚轮缩放；按 V 切换第一人称/第三人称。

var possessed: AICharacter = null
var yaw := 0.0
var pitch := -0.35
var distance := 5.5
var shoulder := 0.55
var dragging := false
var base_fov := 70.0
var first_person := false
var eye_height := 1.5
var fov_zoom := 0.0

const MIN_DISTANCE := 0.8
const MAX_DISTANCE := 16.0
const MIN_PITCH := -1.45
const MAX_PITCH := 1.45
const ORBIT_PIVOT_HEIGHT := 0.95
const ZOOM_STEP := 5.0
const MIN_ZOOM := -40.0
const MAX_ZOOM := 20.0
const MIN_FOV := 30.0
const MAX_FOV := 90.0

func bind(character: AICharacter) -> void:
	possessed = character
	# 默认机位：角色身后 45° 侧后方（与过场收尾机位一致，避免视角跳变）
	yaw = PI / 4.0
	pitch = -0.35
	distance = 5.5
	first_person = false
	fov_zoom = 0.0
	global_position = _orbit_position(character.global_position + Vector3(0, ORBIT_PIVOT_HEIGHT, 0))
	fov = base_fov

func toggle_view_mode() -> void:
	first_person = not first_person
	if possessed == null or not is_instance_valid(possessed):
		return
	if first_person:
		# 进入第一人称时看向角色当前朝向，视线保持水平
		yaw = possessed.rotation.y
		pitch = 0.0
		_set_self_visible(false)
	else:
		# 退出第一人称时恢复到侧后方的环绕视角
		_set_self_visible(true)
		global_position = _orbit_position(possessed.global_position + Vector3(0, ORBIT_PIVOT_HEIGHT, 0))

func set_first_person(enabled: bool) -> void:
	## 强制设置人称（剧情模式默认第一人称）
	if first_person == enabled:
		return
	first_person = enabled
	if first_person:
		if possessed != null and is_instance_valid(possessed):
			yaw = possessed.rotation.y
			global_position = possessed.global_position + Vector3(0, _current_eye_height(), 0)
		pitch = 0.0
		_set_self_visible(false)
	else:
		_set_self_visible(true)

## 视角朝向世界中的某个点（剧情开场“睁眼见向导”等场景使用）：
## 第一人称直接转动视线看向目标；第三人称把机位绕到角色身后，形成经典对话机位。
func face_towards(point: Vector3) -> void:
	if possessed == null or not is_instance_valid(possessed):
		return
	var dir := point - possessed.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	if first_person:
		yaw = target_yaw
		var dy := point.y - (possessed.global_position.y + _current_eye_height())
		pitch = clampf(atan2(dy, maxf(dir.length(), 0.1)), MIN_PITCH, MAX_PITCH)
		rotation = Vector3(pitch, yaw, 0.0)
	else:
		yaw = target_yaw
		global_position = _orbit_position(possessed.global_position + Vector3(0, ORBIT_PIVOT_HEIGHT, 0))

func _set_self_visible(visible: bool) -> void:
	# 第一人称下隐藏角色自身模型与名牌，避免遮挡视线；模型由 Rig 承载
	if possessed == null:
		return
	possessed.rig.visible = visible
	possessed.label.visible = visible and possessed.character_data != null
	# 玩家自己不出头顶气泡：第一人称时即使误触发 speak 也保持隐藏
	if possessed.speech_bubble != null and is_instance_valid(possessed.speech_bubble):
		possessed.speech_bubble.visible = visible

func _exit_tree() -> void:
	# 无论以何种方式结束附身，都恢复角色外观，避免角色一直“隐身”
	if possessed != null and is_instance_valid(possessed):
		possessed.rig.visible = true
		possessed.label.visible = possessed.character_data != null

## 移动端：右侧单指拖动旋转视角
func touch_orbit(relative: Vector2) -> void:
	if GameState.input_locked:
		return
	yaw -= relative.x * 0.004
	pitch = clampf(pitch - relative.y * 0.004, MIN_PITCH, MAX_PITCH)

## 过场收尾衔接：把化身相机朝向对齐到动画相机最后视线（view = (yaw, pitch)）
func snap_view(view: Vector2) -> void:
	yaw = view.x
	pitch = clampf(view.y, MIN_PITCH, MAX_PITCH)
	if first_person and possessed != null and is_instance_valid(possessed):
		global_position = possessed.global_position + Vector3(0, _current_eye_height(), 0)
		rotation = Vector3(pitch, yaw, 0.0)

## 过场自回归交接：立即把机位放到当前视角对应的精确位置（不经过平滑跟随），
## 供导演的回归镜头滑向它；第一人称贴眼部，第三人称落在环绕球面并看向腰际焦点。
func settle_position() -> void:
	if possessed == null or not is_instance_valid(possessed):
		return
	var pivot := possessed.global_position + Vector3(0, ORBIT_PIVOT_HEIGHT, 0)
	if first_person:
		global_position = possessed.global_position + Vector3(0, _current_eye_height(), 0)
		rotation = Vector3(pitch, yaw, 0.0)
	else:
		global_position = _orbit_position(pivot)
		look_at(pivot)

## 移动端：缩放（与滚轮一致：第三人称拉近/拉远，第一人称收放视野）
func zoom_step(dir: int) -> void:
	if GameState.input_locked:
		return
	if first_person:
		fov_zoom = clampf(fov_zoom - float(dir) * ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
	else:
		distance = clampf(distance - float(dir) * 0.6, MIN_DISTANCE, MAX_DISTANCE)

func _input(event: InputEvent) -> void:
	if GameState.input_locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		dragging = event.pressed
		if dragging:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.004
		pitch = clampf(pitch - event.relative.y * 0.004, MIN_PITCH, MAX_PITCH)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if not first_person:
			distance = clampf(distance - 0.6, MIN_DISTANCE, MAX_DISTANCE)
		else:
			# 第一人称：滚轮上滑 = 望远镜拉近（收窄视野）
			fov_zoom = clampf(fov_zoom - ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if first_person:
			# 滚轮下滑 = 望远镜拉远（放宽视野）
			fov_zoom = clampf(fov_zoom + ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
		else:
			distance = clampf(distance + 0.6, MIN_DISTANCE, MAX_DISTANCE)

func _process(delta: float) -> void:
	if GameState.input_locked:
		return
	if possessed == null or not is_instance_valid(possessed):
		return
	if first_person:
		_process_first_person(delta)
	else:
		_process_orbit(delta)

func _process_first_person(delta: float) -> void:
	# 第一人称：相机贴在角色眼部；遇到物体时自动偏移（与第三人称同样的防穿墙逻辑）
	var eye := possessed.global_position + Vector3(0, _current_eye_height(), 0)
	var space := get_world_3d().direct_space_state
	var excludes: Array[RID] = [possessed.get_rid()]
	var desired := eye
	# 1) 相机当前位置 → 眼睛：中间有遮挡时停在遮挡面之前，防止隔着墙看/穿墙
	var ray := PhysicsRayQueryParameters3D.create(global_position, eye)
	ray.exclude = excludes
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		desired = hit.position + hit.normal * 0.12
	# 2) 眼睛附近若仍嵌在几何体内（贴墙、低檐、夹缝），沿视线反方向推开，
	#    推不动时再向上抬，直到获得自由视野
	var clearance := SphereShape3D.new()
	clearance.radius = 0.16
	for i in 8:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = clearance
		q.transform = Transform3D(Basis(), desired)
		q.exclude = excludes
		q.collide_with_bodies = true
		q.collide_with_areas = false
		if space.intersect_shape(q, 1).is_empty():
			break
		var back := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		desired += back * 0.2
		if i >= 4:
			desired.y += 0.12
	# 3) 防止偏移后埋进地面/斜坡：保持在地表之上
	var ground := WorldManager.get_terrain_height(desired.x, desired.z)
	if desired.y < ground + 0.3:
		desired.y = ground + 0.3
	global_position = global_position.lerp(desired, clampf(14.0 * delta, 0.0, 1.0))
	rotation = Vector3(pitch, yaw, 0.0)
	_update_fov(delta)

func _current_eye_height() -> float:
	## 真实眼位：角色原点位于胶囊中心（脚底在本地 -0.95），
	## 模型身高被 _fit_model_to_ground 强制归一化，眼睛取身高的 90%。
	if possessed == null:
		return eye_height
	# 程序化骨骼：直接用头部挂点（含外观 scale）
	if possessed.procedural_rig != null:
		var att := possessed.procedural_rig.get_node_or_null("Skeleton/head") as Node3D
		if att != null:
			return att.position.y - 0.08
	# 模型角色：脚底 + 目标身高 × 90%
	if possessed.character_data != null:
		var scale_value := float(possessed.character_data.appearance.get("scale", 1.0))
		return AICharacter.MODEL_FOOT_Y + AICharacter.MODEL_TARGET_HEIGHT * clampf(scale_value, 0.5, 2.0) * 0.90
	return eye_height

func _process_orbit(delta: float) -> void:
	# 环绕焦点在腰部而非头部，转/拉近拉远都围绕腰部
	var target := possessed.global_position + Vector3(0, ORBIT_PIVOT_HEIGHT, 0)
	var desired := _orbit_position(target)
	# 相机碰撞：从角色头部向期望位置射线，被遮挡时贴到遮挡点（防穿墙/穿地）
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(target, desired)
	var excludes: Array[RID] = [possessed.get_rid()]
	query.exclude = excludes
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		desired = hit.position
	# 平滑跟随
	global_position = global_position.lerp(desired, clampf(10.0 * delta, 0.0, 1.0))
	look_at(target)
	_update_fov(delta)

func _orbit_position(target: Vector3) -> Vector3:
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var offset := (-forward * cos(pitch) + Vector3(0.0, sin(pitch), 0.0)) * distance + right * shoulder
	return target + offset

func _update_fov(delta: float) -> void:
	# 疾跑时 FOV 轻微拉宽，增强速度感
	var sprinting := Input.is_action_pressed("sprint") and not UIManager.text_input_active()
	# 第一人称滚轮缩放（望远镜）只作用于第一人称
	var zoom_offset := fov_zoom if first_person else 0.0
	var target_fov := clampf(base_fov + zoom_offset + (8.0 if sprinting else 0.0), MIN_FOV, MAX_FOV)
	fov = lerpf(fov, target_fov, clampf(8.0 * delta, 0.0, 1.0))
