class_name ClimbAssist
extends RefCounted
## 台阶爬升：被地形折角挡住时抬腿跨过去。
## 角色与可通行性探针共用同一份实现——探针必须跑真实角色的爬升逻辑，
## 否则测出来的卡住率不代表玩家/NPC 的实际体验。

const STEP_UP_HEIGHT := 0.75
const STEP_UP_PROBE := 0.65
## 判定「被挡住」的位移比例：实际位移低于本帧期望位移的这个比例就算撞上了。
const BLOCKED_RATIO := 0.6

## 尝试抬腿跨坎，返回是否抬升成功。before 为 move_and_slide 之前的位置。
static func try_step_up(body: CharacterBody3D, before: Vector3, delta: float) -> bool:
	var vel := body.velocity
	var wanted := Vector2(vel.x, vel.z).length() * delta
	if wanted < 0.005:
		return false
	var moved := Vector2(body.global_position.x - before.x, body.global_position.z - before.z).length()
	if moved > wanted * BLOCKED_RATIO:
		return false
	var space := body.get_world_3d().direct_space_state
	# 不用 is_on_floor 判定贴地：在略超 floor_max_angle 的陡面上引擎判为离地，
	# 角色其实仍贴着坡面（只是打滑），那样会漏掉坎前的抬腿机会。改用脚下短射线。
	var down_from := body.global_position + Vector3(0.0, 0.35, 0.0)
	var down_query := PhysicsRayQueryParameters3D.create(down_from, down_from + Vector3(0.0, -1.0, 0.0))
	down_query.exclude = [body.get_rid()]
	if space.intersect_ray(down_query).is_empty():
		return false
	var fwd := Vector3(vel.x, 0.0, vel.z).normalized()
	var from := body.global_position + fwd * STEP_UP_PROBE + Vector3(0.0, STEP_UP_HEIGHT, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -STEP_UP_HEIGHT * 2.2, 0.0))
	query.exclude = [body.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	var rise := float(hit.position.y) - body.global_position.y
	if rise <= 0.02 or rise > STEP_UP_HEIGHT:
		return false
	body.global_position.y += rise + 0.03
	return true

## 沿碰撞面切向的绕行方向（朝目标那一侧），没有可绕的墙时返回零向量。
## 角色顶着墙推时用它在墙的尽头绕出去，而不是原地磨。
static func wall_sidestep_dir(body: CharacterBody3D, to_target: Vector3) -> Vector3:
	var normal := Vector3.ZERO
	for i in body.get_slide_collision_count():
		normal += body.get_slide_collision(i).get_normal()
	normal.y = 0.0
	if normal.length_squared() < 0.01:
		return Vector3.ZERO
	normal = normal.normalized()
	var tangent := Vector3(-normal.z, 0.0, normal.x)
	to_target.y = 0.0
	if tangent.dot(to_target) < 0.0:
		tangent = -tangent
	return tangent
