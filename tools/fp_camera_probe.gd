extends Node
## 第一人称相机防穿墙无头探针：在角色眼部放一面大墙，跑若干帧后
## 验证相机已自动偏移出墙体，且不再与任何几何体重叠。
## 用法：godot --headless --path . res://tools/fp_camera_probe.tscn

func _ready() -> void:
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	_run()

func _run() -> void:
	CivilizationManager.initialize_factions()
	WorldManager.initialize_world($World)
	CharacterManager.spawn_initial_characters()
	UIManager.setup()
	PlayerGodController.setup_camera()
	TimeManager.set_time_scale(10.0)
	var chars := CharacterManager.all_characters()
	if chars.is_empty():
		push_error("无角色")
		get_tree().quit(1)
		return
	var target: AICharacter = chars[0]
	PlayerGodController.possess(target)
	PlayerGodController.possession_cam.set_first_person(true)
	await get_tree().process_frame
	var cam: Camera3D = PlayerGodController.possession_cam

	# 在角色眼部放一面大墙：墙心对准眼睛，模拟头部嵌进墙体
	var wall := StaticBody3D.new()
	var wall_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 3.0, 0.5)
	wall_mesh.mesh = box
	wall.add_child(wall_mesh)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(3.0, 3.0, 0.5)
	col.shape = cs
	wall.add_child(col)
	$World.add_child(wall)
	var head := cam.global_position
	wall.global_position = head

	for i in 90:
		await get_tree().process_frame

	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	q.shape = sph
	q.transform = Transform3D(Basis(), cam.global_position)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = [target.get_rid(), wall.get_rid()]
	var overlaps := space.intersect_shape(q, 3)
	var inside_wall := absf(cam.global_position.x - wall.global_position.x) < 1.6 \
		and absf(cam.global_position.y - wall.global_position.y) < 1.6 \
		and absf(cam.global_position.z - wall.global_position.z) < 0.35
	var pushed_out := cam.global_position.distance_to(wall.global_position) > 0.55
	print("FP_CAM: cam=%s head=%s overlaps=%d inside_wall=%s pushed_out=%s" % [
		cam.global_position, head, overlaps.size(), inside_wall, pushed_out
	])
	if overlaps.is_empty() and not inside_wall and pushed_out:
		print("FP_PROBE_PASS")
	else:
		print("FP_PROBE_FAIL")
	get_tree().quit(0 if overlaps.is_empty() and not inside_wall and pushed_out else 1)
