class_name CinematicDirector
extends Node3D
## 剧情过场导演：在过场/节拍演出期间接管相机与角色。
## - 支持多段镜头序列：每段独立定义 起止位移、视线移动、FOV 与缓动，段间无缝衔接；
## - 「shoulder」肩后机位：结束段以角色（走位终点 + 朝向）为基准，
##   落在其身后 45° 侧后方，保证收尾机位稳定、沉浸；
## - 自回归收尾：正片结束后自动追加一段回归镜头，把相机平滑滑回
##   玩家转场前的机位（位置与视角都还原），再无缝交还控制权，
##   避免“过场停在别处、交棒瞬间跳视角”引发的晕眩；
## - 角色：figure/companion 慢速走位（可指定 speed，结束后恢复原速），到达后面向指定点；
## - 演出期间锁定玩家输入（GameState.input_locked），结束后恢复附身/上帝视角。

signal cutscene_finished()

const EASE_LINEAR := 0
const EASE_QUAD := 1
const EASE_CUBE := 2
const EASE_SINE := 3

const EASE_IN := 0
const EASE_OUT := 1
const EASE_IN_OUT := 2

## 走位距离上限：超过则只做镜头，不强行走位，避免长距离锁死玩家
const MAX_WALK_DISTANCE := 9.0
const DEFAULT_WALK_SPEED := 3.2

## 自回归段时长：按距离自适应，近处快回、远处稍缓
const RETURN_GLIDE := 1.1
const RETURN_GLIDE_MIN := 0.45

var active := false
var camera: Camera3D = null
var _focus_light: OmniLight3D = null

var _segments: Array = []
var _seg_index := 0
var _seg_t := 0.0
var _key_pos: Array = []
var _key_look: Array = []
var _key_fov: Array = []
var _key_s: Array = []
var _total_duration := 0.001
var _elapsed := 0.0
var _walkers: Array = []
var _done: Callable = Callable()
var _restore_possession := true
var _was_possessed := false
var _cleaned := false
var _suppress_done := false
var _returning := false
var _control_prepared := false
var _pre_view := Vector2.ZERO
var _prepared_cam: Camera3D = null

func _ready() -> void:
	set_process(false)

func _exit_tree() -> void:
	# 无论以何种方式被移除（换场景/重置），都确保输入解锁
	active = false
	GameState.input_locked = false
	UIManager.set_cutscene_ui_active(false)
	if _focus_light != null and is_instance_valid(_focus_light):
		_focus_light.light_energy = 0.0

func is_active() -> bool:
	return active

## 是否正处于自回归段（正片已完，正在滑回转场前机位）
func is_returning() -> bool:
	return active and _returning

## 过场：接管相机与角色，结束后恢复控制（不回调）。
## shots 可以是单个镜头 Dictionary，也可以是镜头序列 Array。
func play_cutscene(shots, walks: Array = [], restore_possession := true) -> void:
	_begin(shots, walks, restore_possession, Callable())

## 节拍演出：结束后调用 done 继续展示剧情内容。
func play_beat_shot(shots, walks: Array, done: Callable) -> void:
	_begin(shots, walks, true, done)

## 跳过/提前结束：立即恢复控制并回调（用于“跳过”按钮等）。
func cancel() -> void:
	if not active or _cleaned:
		return
	_cleaned = true
	active = false
	GameState.input_locked = false
	UIManager.set_cutscene_ui_active(false)
	if _focus_light != null and is_instance_valid(_focus_light):
		_focus_light.light_energy = 0.0
	_cleanup_walkers(false)
	_restore_control()
	set_process(false)
	var done := _done
	_done = Callable()
	if not done.is_null() and not _suppress_done:
		done.call()
	_suppress_done = false
	cutscene_finished.emit()

func _begin(shots, walks: Array, restore_possession: bool, done: Callable) -> void:
	if active:
		_suppress_done = true
		cancel()
	_cleaned = false
	active = true
	_done = done
	_restore_possession = restore_possession
	_was_possessed = GameState.mode == GameState.Mode.POSSESS
	_returning = false
	_control_prepared = false
	_prepared_cam = null
	_record_pre_view()
	GameState.input_locked = true
	UIManager.set_cutscene_ui_active(true)
	if _was_possessed:
		PlayerGodController.exit_possession(true)
	_ensure_camera()
	camera.make_current()
	GameState.camera = camera
	_walkers.clear()
	for w in walks:
		_add_walker(w)
	_parse_shots(shots)
	_seg_index = 0
	_seg_t = 0.0
	_elapsed = 0.0
	_apply_segment_start()
	set_process(true)

func _ensure_camera() -> void:
	if camera != null and is_instance_valid(camera):
		return
	camera = Camera3D.new()
	camera.name = "DirectorCamera"
	add_child(camera)
	camera.fov = 70.0
	camera.far = 1200.0

func _parse_shots(shots) -> void:
	_segments.clear()
	var raw_shots: Array = shots if shots is Array else [shots]
	var prev_to := camera.global_position
	for raw in raw_shots:
		if not (raw is Dictionary):
			continue
		var shot: Dictionary = raw
		var seg := _parse_segment(shot, prev_to)
		if shot.has("shoulder"):
			_apply_shoulder(seg, shot["shoulder"])
		_segments.append(seg)
		prev_to = seg["to"]
	if _segments.is_empty():
		_segments.append(_default_segment(camera.global_position))
	_build_path()

func _parse_segment(shot: Dictionary, default_from: Vector3) -> Dictionary:
	var from := _vec3(shot.get("from", []), default_from)
	var to := _vec3(shot.get("to", []), from + Vector3(0, 0, 4.0))
	var look := _vec3(shot.get("look_at", []), from + Vector3(0, 0, -20.0))
	return {
		"from": from,
		"to": to,
		"look_from": _vec3(shot.get("look_from", []), look),
		"look_to": _vec3(shot.get("look_to", []), look),
		"look_static": not shot.has("look_from") and not shot.has("look_to"),
		"fov_from": float(shot.get("fov_from", 70.0)),
		"fov_to": float(shot.get("fov_to", 70.0)),
		"duration": maxf(float(shot.get("duration", 1.0)), 0.1),
		"trans": _parse_trans(str(shot.get("trans", "quad"))),
		"ease": _parse_ease(str(shot.get("ease", "in_out"))),
		"shake": float(shot.get("shake", 0.0))
	}

## 肩后机位：以角色走位终点 + 朝向为基准，落在身后 45° 侧后方
func _apply_shoulder(seg: Dictionary, shoulder) -> void:
	var who := "figure"
	var side := 1.0
	var dist := 4.6
	var height := 2.0
	if shoulder is Dictionary:
		who = str(shoulder.get("who", "figure"))
		side = float(shoulder.get("side", 1.0))
		dist = float(shoulder.get("distance", 4.6))
		height = float(shoulder.get("height", 2.0))
	# 聚焦角色时保持 3~5m 观察距离，避免贴脸
	dist = clampf(dist, 3.2, 4.8)
	var anchor := Vector3.ZERO
	var yaw := 0.0
	var walker := _find_walker(who)
	if not walker.is_empty():
		anchor = walker["target"]
		if walker.get("has_face", false):
			var face: Vector3 = walker["face"]
			var dir := face - anchor
			dir.y = 0.0
			if dir.length_squared() > 0.0001:
				yaw = atan2(-dir.x, -dir.z)
		else:
			var ch: AICharacter = walker.get("character", null)
			if ch != null and is_instance_valid(ch):
				yaw = ch.rotation.y
	elif who == "player" and StoryModeManager.player != null and is_instance_valid(StoryModeManager.player):
		anchor = StoryModeManager.player.global_position
		yaw = StoryModeManager.player.rotation.y
	elif who == "figure" and StoryModeManager.figure != null and is_instance_valid(StoryModeManager.figure):
		anchor = StoryModeManager.figure.global_position
		yaw = StoryModeManager.figure.rotation.y
	elif who == "companion" and StoryModeManager.companion != null and is_instance_valid(StoryModeManager.companion):
		anchor = StoryModeManager.companion.global_position
		yaw = StoryModeManager.companion.rotation.y
	else:
		anchor = camera.global_position
	seg["to"] = _over_shoulder_pos(anchor, yaw, dist, height, side)
	seg["has_shoulder"] = true
	seg["anchor"] = anchor
	if seg["look_static"]:
		# 未显式指定视线时，收尾默认对准角色
		seg["look_from"] = anchor + Vector3(0, 1.3, 0)
		seg["look_to"] = anchor + Vector3(0, 1.3, 0)

func _over_shoulder_pos(anchor: Vector3, yaw: float, distance: float, height: float, side: float) -> Vector3:
	var back := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dir := (back + right * side).normalized()
	return anchor + Vector3(dir.x * distance, height, dir.z * distance)

func _default_segment(from: Vector3) -> Dictionary:
	return {
		"from": from,
		"to": from,
		"look_from": from + Vector3(0, 0, -10.0),
		"look_to": from + Vector3(0, 0, -10.0),
		"look_static": true,
		"fov_from": 70.0,
		"fov_to": 70.0,
		"duration": 0.5,
		"trans": EASE_LINEAR,
		"ease": EASE_IN_OUT
	}

func _add_walker(w: Dictionary) -> void:
	var who := str(w.get("who", ""))
	var ch: AICharacter = null
	if who == "player":
		ch = StoryModeManager.player
	elif who == "figure":
		ch = StoryModeManager.figure
	elif who == "companion":
		ch = StoryModeManager.companion
	if ch == null or not is_instance_valid(ch) or not ch.alive:
		return
	var to := _vec3(w.get("to", []), ch.global_position)
	to = WorldManager.clamp_point(to, 0.95)
	# 先清空角色既有移动/动作状态，确保完全由导演驱动
	ch.moving = false
	ch.current_action = {}
	ch.action_on_arrive = {}
	ch.velocity = Vector3.ZERO
	var dist := Vector2(ch.global_position.x - to.x, ch.global_position.z - to.z).length()
	if dist > MAX_WALK_DISTANCE:
		return  # 太远：只做镜头，不强行走位
	var entry := {"who": who, "character": ch, "target": to, "arrived": false, "has_face": false}
	if w.has("face"):
		entry["face"] = _vec3(w["face"], to)
		entry["has_face"] = true
	var speed := float(w.get("speed", 0.0))
	if speed > 0.0:
		entry["speed"] = speed
		entry["old_speed"] = float(ch.character_data.status.get("speed", DEFAULT_WALK_SPEED))
		ch.character_data.status["speed"] = speed
	_walkers.append(entry)

func _process(delta: float) -> void:
	if not active:
		return
	_elapsed += delta
	var t := clampf(_elapsed / _total_duration, 0.0, 1.0)
	# 全局缓动：整条路径一次性的起收（smoothstep），段与段之间零顿挫
	var e := _global_ease(t)
	var s := e * _total_duration
	var seg := _segment_at(s)
	# 沿 Catmull-Rom 样条连续滑过所有关键点 —— 行云流水的运镜
	var pos := _sample_path(_key_pos, _key_s, s)
	# 地表钳制：任何时刻都不低于地表 1.2m，杜绝镜头冲进地里
	pos.y = maxf(pos.y, WorldManager.get_terrain_height(pos.x, pos.z) + 1.2)
	var shake := float(seg.get("shake", 0.0)) * (1.0 - e * 0.6)
	if shake > 0.0:
		pos += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 0.25
		# 抖动后再次钳制，避免震落进山体
		pos.y = maxf(pos.y, WorldManager.get_terrain_height(pos.x, pos.z) + 1.2)
	# 实体表面保底：向下射线探测建筑/岩石/丰碑等，避免镜头钻穿场景物体
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 2.0, 0),
		pos + Vector3(0, -60.0, 0)
	)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		pos.y = maxf(pos.y, float(hit.position.y) + 1.0)
	camera.global_position = pos
	var look := _sample_path(_key_look, _key_s, s)
	if camera.global_position.distance_to(look) > 0.01:
		camera.look_at(look, Vector3.UP)
	# 轻微滚转：让镜头带一点“活”的气息
	camera.rotation.z += sin(_elapsed * 0.55) * 0.006
	# FOV：沿路径缓推 + 轻微呼吸
	camera.fov = lerpf(_key_fov[0], _key_fov[_key_fov.size() - 1], e) + sin(_elapsed * 1.8) * 0.4
	_tick_focus_light(delta, seg)
	_tick_walkers()
	if t >= 1.0:
		_finish()

func _global_ease(t: float) -> float:
	## smoothstep：起收舒缓、中段匀速顺滑
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _build_path() -> void:
	_key_pos.clear()
	_key_look.clear()
	_key_fov.clear()
	_key_s.clear()
	if _segments.is_empty():
		return
	var acc := 0.0
	_key_s.append(0.0)
	var first: Dictionary = _segments[0]
	_key_pos.append(first["from"])
	_key_look.append(first["look_from"])
	_key_fov.append(float(first["fov_from"]))
	for seg in _segments:
		_key_pos.append(seg["to"])
		_key_look.append(seg["look_to"])
		_key_fov.append(float(seg["fov_to"]))
		acc += float(seg["duration"])
		_key_s.append(acc)
	_total_duration = maxf(acc, 0.001)

func _segment_at(s: float) -> Dictionary:
	if _segments.is_empty():
		return {}
	var idx := _segments.size() - 1
	for i in _segments.size():
		if s <= float(_key_s[i + 1]):
			idx = i
			break
	return _segments[clampi(idx, 0, _segments.size() - 1)]

## 非均匀 Catmull-Rom 样条采样：镜头与视线都走同一条连续曲线
func _sample_path(points: Array, knots: Array, s: float) -> Vector3:
	var n := points.size()
	if n == 0:
		return Vector3.ZERO
	if n == 1:
		return points[0]
	var k := 0
	for i in n - 1:
		if s > float(knots[i + 1]):
			k = i
		else:
			break
	k = clampi(k, 0, n - 2)
	var p0: Vector3 = points[maxi(k - 1, 0)]
	var p1: Vector3 = points[k]
	var p2: Vector3 = points[k + 1]
	var p3: Vector3 = points[mini(k + 2, n - 1)]
	var t0: float = knots[maxi(k - 1, 0)]
	var t1: float = knots[k]
	var t2: float = knots[k + 1]
	var t3: float = knots[mini(k + 2, n - 1)]
	var u := (s - t1) / maxf(t2 - t1, 0.0001)
	var m1 := (p2 - p0) / maxf(t2 - t0, 0.0001) * (t2 - t1)
	var m2 := (p3 - p1) / maxf(t3 - t1, 0.0001) * (t2 - t1)
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * p1 \
		+ (u3 - 2.0 * u2 + u) * m1 \
		+ (-2.0 * u3 + 3.0 * u2) * p2 \
		+ (u3 - u2) * m2

func _tick_walkers() -> void:
	for w in _walkers:
		var ch: AICharacter = w.get("character", null)
		if ch == null or not is_instance_valid(ch) or not ch.alive:
			continue
		var target: Vector3 = w["target"]
		var dir := target - ch.global_position
		dir.y = 0.0
		if dir.length() <= 1.0:
			if not w.get("arrived", false):
				w["arrived"] = true
				ch.moving = false
				ch.velocity = Vector3.ZERO
				if w.get("has_face", false):
					ch.face_towards(w["face"])
		elif not ch.moving:
			ch.moving = true
			ch.current_action = {}
			ch.action_target = target
			ch.velocity = Vector3.ZERO

func _stop_walker(w: Dictionary, snap_face := false) -> void:
	var ch: AICharacter = w.get("character", null)
	if ch == null or not is_instance_valid(ch):
		return
	ch.moving = false
	ch.velocity = Vector3.ZERO
	if w.has("speed"):
		ch.character_data.status["speed"] = w["old_speed"]
	if snap_face and w.get("has_face", false):
		ch.face_towards(w["face"])

func _cleanup_walkers(snap_face: bool) -> void:
	for w in _walkers:
		_stop_walker(w, snap_face)

func _find_walker(who: String) -> Dictionary:
	for w in _walkers:
		if str(w.get("who", "")) == who:
			return w
	return {}

func _apply_segment_start() -> void:
	if _segments.is_empty():
		return
	var seg: Dictionary = _segments[0]
	camera.global_position = seg["from"]
	camera.fov = float(seg["fov_from"])

func _ensure_focus_light() -> void:
	if _focus_light == null or not is_instance_valid(_focus_light):
		_focus_light = OmniLight3D.new()
		_focus_light.name = "DirectorFocusLight"
		_focus_light.light_color = Color(1.0, 0.9, 0.7)
		_focus_light.light_energy = 0.0
		_focus_light.omni_range = 15.0
		_focus_light.shadow_enabled = false
		add_child(_focus_light)

func _tick_focus_light(delta: float, seg: Dictionary) -> void:
	## 肩后聚焦段落：在人物头顶打一束暖光，增强登场/收尾的仪式感
	if not seg.get("has_shoulder", false):
		if _focus_light != null and is_instance_valid(_focus_light):
			_focus_light.light_energy = maxf(0.0, _focus_light.light_energy - delta * 3.0)
		return
	_ensure_focus_light()
	var anchor: Vector3 = seg.get("anchor", camera.global_position)
	_focus_light.global_position = anchor + Vector3(0, 4.2, 0)
	_focus_light.light_energy = lerpf(_focus_light.light_energy, 3.6, clampf(delta * 2.5, 0.0, 1.0))

func _finish() -> void:
	if _cleaned:
		return
	if not _returning and _begin_return_segment():
		return
	_complete_finish()

func _complete_finish() -> void:
	_cleaned = true
	active = false
	GameState.input_locked = false
	UIManager.set_cutscene_ui_active(false)
	if _focus_light != null and is_instance_valid(_focus_light):
		_focus_light.light_energy = 0.0
	_cleanup_walkers(true)
	_restore_control()
	set_process(false)
	var done := _done
	_done = Callable()
	if not done.is_null():
		done.call()
	cutscene_finished.emit()

func _record_pre_view() -> void:
	## 记录转场前玩家相机的视角（yaw, pitch）：自回归与跳过恢复都以它为准
	var cam: Camera3D = PlayerGodController.possession_cam if _was_possessed else PlayerGodController.god_camera
	if cam != null and is_instance_valid(cam):
		_pre_view = Vector2(cam.rotation.y, cam.rotation.x)

func _begin_return_segment() -> bool:
	## 自回归段：从动画相机当前机位平滑滑回玩家转场前的机位；失败返回 false（立即收尾）
	if camera == null or not is_instance_valid(camera):
		return false
	var handoff := _prepare_handoff()
	if handoff.is_empty():
		return false
	var from_pos := camera.global_position
	var from_look := from_pos - camera.global_transform.basis.z * 8.0
	var dist := from_pos.distance_to(handoff["pos"])
	var duration := clampf(RETURN_GLIDE * dist / 28.0, RETURN_GLIDE_MIN, RETURN_GLIDE)
	_segments.clear()
	_segments.append({
		"from": from_pos,
		"to": handoff["pos"],
		"look_from": from_look,
		"look_to": handoff["look"],
		"look_static": false,
		"fov_from": camera.fov,
		"fov_to": 70.0,
		"duration": duration,
		"trans": EASE_QUAD,
		"ease": EASE_IN_OUT,
		"shake": 0.0
	})
	_build_path()
	_seg_index = 0
	_seg_t = 0.0
	_elapsed = 0.0
	_returning = true
	return true

func _prepare_handoff() -> Dictionary:
	## 预先恢复玩家模式与机位（视角/位置对齐转场前），并返回回归段的目标机位。
	## 玩家相机就位后仍保持非当前，动画相机继续演出，交棒时零跳变。
	var cam: Camera3D = null
	if _restore_possession and _was_possessed:
		var player: AICharacter = StoryModeManager.player
		if player != null and is_instance_valid(player) and player.alive:
			PlayerGodController.possess(player, true)
			var pcam = PlayerGodController.possession_cam
			if pcam != null and is_instance_valid(pcam):
				pcam.snap_view(_pre_view)
				pcam.settle_position()
				cam = pcam
	if cam == null:
		PlayerGodController.exit_possession(true)
		var gcam = PlayerGodController.god_camera
		if gcam != null and is_instance_valid(gcam):
			gcam.snap_view(_pre_view)
			cam = gcam
	if cam == null:
		return {}
	cam.current = false
	camera.make_current()
	GameState.camera = camera
	_control_prepared = true
	_prepared_cam = cam
	return {"pos": cam.global_position, "look": cam.global_position - cam.global_transform.basis.z * 8.0}

func _restore_control() -> void:
	## 交还控制权。回归段已把玩家相机按转场前机位就位，直接切回即可；
	## 跳过/中断路径则立即按转场前视角恢复（位置对玩家相机本就保持原位）。
	if _control_prepared:
		if _prepared_cam != null and is_instance_valid(_prepared_cam):
			_prepared_cam.make_current()
			GameState.camera = _prepared_cam
		return
	if _restore_possession and _was_possessed:
		PlayerGodController.possess(StoryModeManager.player, true)
		var pcam = PlayerGodController.possession_cam
		if pcam != null and is_instance_valid(pcam):
			pcam.snap_view(_pre_view)
			pcam.settle_position()
	else:
		PlayerGodController.exit_possession(true)
		var gcam = PlayerGodController.god_camera
		if gcam != null and is_instance_valid(gcam):
			gcam.snap_view(_pre_view)

func _eased(t: float, trans: int, ease: int) -> float:
	var x := clampf(t, 0.0, 1.0)
	match trans:
		EASE_LINEAR:
			return x
		EASE_QUAD:
			return _quad(x, ease)
		EASE_CUBE:
			return _cube(x, ease)
		EASE_SINE:
			return _sine(x, ease)
		_:
			return x

func _quad(x: float, ease: int) -> float:
	match ease:
		EASE_IN:
			return x * x
		EASE_OUT:
			return 1.0 - (1.0 - x) * (1.0 - x)
		_:
			if x < 0.5:
				return 2.0 * x * x
			return 1.0 - pow(-2.0 * x + 2.0, 2.0) / 2.0

func _cube(x: float, ease: int) -> float:
	match ease:
		EASE_IN:
			return x * x * x
		EASE_OUT:
			return 1.0 - pow(1.0 - x, 3.0)
		_:
			if x < 0.5:
				return 4.0 * x * x * x
			return 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0

func _sine(x: float, ease: int) -> float:
	match ease:
		EASE_IN:
			return 1.0 - cos(x * PI / 2.0)
		EASE_OUT:
			return sin(x * PI / 2.0)
		_:
			return -(cos(PI * x) - 1.0) / 2.0

func _parse_trans(s: String) -> int:
	match s:
		"linear":
			return EASE_LINEAR
		"cube":
			return EASE_CUBE
		"sine":
			return EASE_SINE
		_:
			return EASE_QUAD

func _parse_ease(s: String) -> int:
	match s:
		"in":
			return EASE_IN
		"out":
			return EASE_OUT
		_:
			return EASE_IN_OUT

func _vec3(data, fallback: Vector3) -> Vector3:
	if data is Vector3:
		return data
	if data is Array and (data as Array).size() >= 3:
		return Vector3(float(data[0]), float(data[1]), float(data[2]))
	return fallback
