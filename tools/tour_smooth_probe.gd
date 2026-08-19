extends Node
## 巡览相机无头探针：动态漫游跑 1800 帧，验证：
## ① 运动平滑（最大单帧位移/转角）；② 覆盖全图（离中心足够远）；
## ③ 聚焦段镜头与目标保持 3~5m；④ 路线不固定（每次生成不同）。
## 用法：godot --headless --path . res://tools/tour_smooth_probe.tscn

func _ready() -> void:
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	_run()

func _run() -> void:
	seed(20260819)
	WorldManager.initialize_world($World)
	var center := Vector3(0, WorldManager.get_terrain_height(0, 0) + 1.0, 0)
	var fp2 := Vector3(20, 0, -15)
	var fp3 := Vector3(-30, 0, 10)
	fp2.y = WorldManager.get_terrain_height(fp2.x, fp2.z) + 1.0
	fp3.y = WorldManager.get_terrain_height(fp3.x, fp3.z) + 1.0
	var cam := IntroTourCamera.new()
	add_child(cam)
	cam.set_focus_points([
		center,
		fp2,
		fp3
	])
	var max_step := 0.0
	var max_horiz := 0.0
	var max_vert := 0.0
	var max_rot := 0.0
	var max_dist := 0.0
	var focus_min := INF
	var focus_max := -INF
	var focus_settled := 0
	var last_pos := cam.global_position
	var last_basis := cam.global_transform.basis
	for i in 6000:
		await get_tree().process_frame
		if i % 1000 == 0:
			print("TOUR_DBG: f=%d mode=%s pos=(%.1f, %.1f, %.1f)" % [
				i, cam._mode, cam.global_position.x, cam.global_position.y, cam.global_position.z
			])
		var step := cam.global_position.distance_to(last_pos)
		max_horiz = maxf(max_horiz, Vector2(cam.global_position.x, cam.global_position.z) \
			.distance_to(Vector2(last_pos.x, last_pos.z)))
		max_vert = maxf(max_vert, absf(cam.global_position.y - last_pos.y))
		var rot_delta := cam.global_transform.basis.get_rotation_quaternion() \
			.angle_to(last_basis.get_rotation_quaternion())
		max_step = maxf(max_step, step)
		max_rot = maxf(max_rot, rot_delta)
		max_dist = maxf(max_dist, Vector2(cam.global_position.x, cam.global_position.z).length())
		if cam.is_focusing():
			var d: float = cam.global_position.distance_to(cam.current_look_target())
			# 只统计“到位后”的聚焦距离（5.5m 内），接近过程不计入
			if d < 5.5:
				focus_min = minf(focus_min, d)
				focus_max = maxf(focus_max, d)
				focus_settled += 1
		last_pos = cam.global_position
		last_basis = cam.global_transform.basis
	print("TOUR_SMOOTH: max_step=%.4f max_rot=%.4f max_dist=%.1f focus=%d dist[%.2f..%.2f]" % [
		max_step, max_rot, max_dist, focus_settled, focus_min, focus_max
	])
	print("TOUR_HV: horiz=%.4f vert=%.4f" % [max_horiz, max_vert])
	var ok := max_horiz < 0.5 and max_vert < 2.0 and max_rot < 0.25 \
		and max_dist > 40.0 \
		and focus_settled >= 30 \
		and focus_min >= 3.0 and focus_max <= 5.5
	print("TOUR_SMOOTH: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
