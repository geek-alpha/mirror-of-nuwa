class_name IntroTourCamera
extends Camera3D
## 睁眼前的世界巡览相机：动态漫游，不固定路线。
## 全景飞越与聚焦角色/建筑交替进行，位置、高度、速度、停留时长均随机，
## 覆盖整张地图，充分展示世界全景；不响应任何输入，玩家睁眼前不获得视角控制。
var _focus_points: Array = []
var _last_focus := -1
var _mode := "panorama"
var _target_pos := Vector3.ZERO
var _look_target := Vector3.ZERO
var _leg_time := 0.0
var _leg_duration := 3.0
var _leg_speed := 1.6
var _hold_time := 0.0

const WORLD_HALF := 60.0

func set_focus_points(points: Array) -> void:
	## 传入希望展示的角色/建筑焦点（向导、任务地标、营地等），路线由相机随机生成。
	_focus_points = points
	_last_focus = -1
	_mode = "panorama"
	# 起始机位与首个目标分开：开局立即开始飞行，而不是呆立
	global_position = _surface_lift(_random_panorama_pos())
	_target_pos = _random_panorama_pos()
	_look_target = _random_look_target()
	_look_at_point(_look_target)
	_leg_time = 0.0
	_leg_duration = 4.0 + randf() * 2.0
	_leg_speed = 8.0 + randf() * 5.0
	_hold_time = 0.0

func is_focusing() -> bool:
	return _mode == "focus"

func current_look_target() -> Vector3:
	return _look_target

func _process(delta: float) -> void:
	# 钳制步长：渲染卡顿不产生跳变，运动保持平滑
	var dt := minf(delta, 1.0 / 30.0)
	_leg_time += dt
	if _mode == "focus":
		# 聚焦段：到位（5.2m 内）后停留约 2 秒，避免一直停在远处
		if global_position.distance_to(_look_target) < 5.2:
			_hold_time += dt
			if _hold_time >= 2.0:
				_next_leg()
	else:
		if _leg_time >= _leg_duration:
			_next_leg()
	# 匀速巡航 + 接近减速：速度按段随机（m/s），长距离飞越不会瞬间冲过头
	var to_target := _target_pos - global_position
	var dist := to_target.length()
	var cruise := _leg_speed
	if _mode == "focus" and dist > 10.0:
		cruise = 10.0  # 远处快速接近聚焦目标
	if dist < 8.0:
		cruise = maxf(cruise * dist / 8.0, 0.4)
	var move := minf(cruise * dt, dist)
	if dist > 0.001:
		global_position += to_target.normalized() * move
	# 聚焦角色/重要建筑时，靠近后平滑保持 3~5m 观察距离（远处只巡航，不硬拉）
	if _mode == "focus" and global_position.distance_to(_look_target) < 12.0:
		global_position = _focus_adjust(global_position, _look_target, dt)
	# 始终高于地表与实体：平滑抬升，避免瞬间跳变
	global_position = _surface_lift_smooth(global_position, dt)
	# 视角平滑转向，切换目标时无瞬间甩头
	_look_at_smooth(_look_target, dt)

func _next_leg() -> void:
	_leg_time = 0.0
	_hold_time = 0.0
	# 全景与聚焦交替：广角展示世界后，切近景看角色/建筑，节奏不单调
	if _mode == "panorama" and not _focus_points.is_empty():
		_mode = "focus"
		var idx := _pick_focus_index()
		# 聚焦点按当前地形高度修正：避免山丘高差导致镜头悬在半空
		var fp_raw: Vector3 = _focus_points[idx]
		var fp := fp_raw
		fp.y = WorldManager.get_terrain_height(fp_raw.x, fp_raw.z) + 1.0
		var ang := randf() * TAU
		var radius := 3.3 + randf() * 1.3
		_target_pos = fp + Vector3(cos(ang) * radius, 0.6 + randf() * 0.8, sin(ang) * radius)
		_look_target = fp
		_leg_duration = 1.8 + randf() * 1.0
		_leg_speed = 2.5 + randf() * 1.0
	else:
		_mode = "panorama"
		_target_pos = _random_panorama_pos()
		_look_target = _random_look_target()
		_leg_duration = 4.0 + randf() * 2.0
		_leg_speed = 8.0 + randf() * 5.0

func _pick_focus_index() -> int:
	if _focus_points.size() <= 1:
		return 0
	var idx := randi() % _focus_points.size()
	if idx == _last_focus:
		idx = (idx + 1 + randi() % (_focus_points.size() - 1)) % _focus_points.size()
	_last_focus = idx
	return idx

func _random_panorama_pos() -> Vector3:
	## 全景飞越点：覆盖整张地图，含四角与高处俯瞰
	var p := Vector3(
		randf_range(-WORLD_HALF, WORLD_HALF),
		0,
		randf_range(-WORLD_HALF, WORLD_HALF)
	)
	p.y = WorldManager.get_terrain_height(p.x, p.z) + randf_range(7.0, 17.0)
	return p

func _random_look_target() -> Vector3:
	## 全景时望向地标/角色或远处景色，避免只看脚下
	if randf() < 0.45 and not _focus_points.is_empty():
		return _focus_points[randi() % _focus_points.size()]
	var p := Vector3(
		randf_range(-WORLD_HALF, WORLD_HALF),
		0,
		randf_range(-WORLD_HALF, WORLD_HALF)
	)
	p.y = WorldManager.get_terrain_height(p.x, p.z) + randf_range(0.5, 3.0)
	return p

func _focus_adjust(pos: Vector3, look: Vector3, delta: float) -> Vector3:
	## 把镜头与观察目标（角色/建筑）的直线距离平滑保持在 3~5m 之间。
	var to_look := pos - look
	var dist := to_look.length()
	if dist < 0.01:
		return pos
	var target := clampf(dist, 3.4, 4.6)
	var desired_point := look + to_look.normalized() * target
	# 修正限速 3m/s：靠近过程中不会瞬间拉扯，保持平滑
	return pos + (desired_point - pos).limit_length(3.0 * delta)

func _surface_lift(pos: Vector3) -> Vector3:
	## 保底：至少高于地表 1m，且不低于建筑/岩石/丰碑表面 1m。
	## 返回修正后的位置；移动量交给调用方的平滑插值消化。
	# 1) 地形高度保底：至少高于地表 1m
	var min_y := WorldManager.get_terrain_height(pos.x, pos.z) + 1.1
	# 2) 实体表面保底：向下射线探测建筑/岩石/丰碑等，相机嵌在内部时也抬到表面之上
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 2.0, 0),
		pos + Vector3(0, -60.0, 0)
	)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		min_y = maxf(min_y, float(hit.position.y) + 1.0)
	if pos.y < min_y:
		pos.y = min_y
	return pos

func _surface_lift_smooth(pos: Vector3, delta: float) -> Vector3:
	## 保底：任何时刻都不低于地表 1m，也不低于实体表面 1m。
	## 硬钳制优先于平滑——宁可轻微上抬，绝不冲进地面。
	var min_y := WorldManager.get_terrain_height(pos.x, pos.z) + 1.1
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 2.0, 0),
		pos + Vector3(0, -60.0, 0)
	)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		min_y = maxf(min_y, float(hit.position.y) + 1.0)
	if pos.y < min_y:
		pos.y = min_y
	return pos

func _look_at_point(p: Vector3) -> void:
	var diff := p - global_position
	if diff.length_squared() > 0.0001:
		look_at(p)

func _look_at_smooth(p: Vector3, delta: float) -> void:
	var diff := p - global_position
	if diff.length_squared() < 0.0001:
		return
	var target_basis := global_transform.looking_at(p, Vector3.UP).basis
	var q := global_transform.basis.get_rotation_quaternion() \
		.slerp(target_basis.get_rotation_quaternion(), 1.0 - exp(-3.0 * delta))
	global_transform.basis = Basis(q)
