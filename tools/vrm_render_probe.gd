extends SceneTree
## VRM 渲染探针：按游戏同款加载/缩放逻辑把每个模型摆到地面，渲染一张侧视截图，
## 用于直观确认“只剩头/头部歪/静态”等异常。输出到 user://vrm_shots/。

const MODEL_TARGET_HEIGHT := 1.75
const MODEL_FOOT_Y := -0.95
const VRM_RIG_SCRIPT := preload("res://scripts/characters/vrm_rig_driver.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://vrm_shots")
	var only := OS.get_environment("VRM_ONLY")
	var mesh_mode := OS.get_environment("VRM_MESH")  # ""=整模型, solo=逐网格, lod0=只留LOD0
	var drive_rig := OS.get_environment("VRM_RIG") == "1"
	var files: Array[String] = []
	for d in ["res://assets/models/characters/male", "res://assets/models/characters/famale"]:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.to_lower().ends_with(".vrm"):
				files.append(d.path_join(fname))
			fname = dir.get_next()
		dir.list_dir_end()
	files.sort()
	for full in files:
		if only == "" or full.get_file().to_lower().contains(only.to_lower()):
			await _render_one(full, mesh_mode, drive_rig)
	quit()

func _render_one(path: String, mesh_mode: String, drive_rig: bool) -> void:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	if gltf.append_from_file(path, state) != OK:
		print("LOAD FAIL %s" % path)
		return
	var model := gltf.generate_scene(state)
	if model == null:
		print("GEN FAIL %s" % path)
		return
	if mesh_mode == "lod0":
		_remove_lod_duplicates(model)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(420, 640)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true
	root.add_child(viewport)
	viewport.add_child(model)
	var rig = null
	if drive_rig:
		var skels: Array = []
		_find_skeletons(model, skels)
		if not skels.is_empty():
			rig = VRM_RIG_SCRIPT.new()
			rig.setup(skels[0], path)
			rig.set_anim_state("idle")
			skels[0].add_child(rig)
	# 与 AICharacter._fit_model_to_ground 相同的归一化（加入场景后再缩放）
	var aabb := _scene_aabb(model)
	if aabb.size.y > 0.001 and mesh_mode != "raw":
		var height_scale := MODEL_TARGET_HEIGHT / aabb.size.y
		(model as Node3D).scale = Vector3.ONE * height_scale
		var min_y := aabb.position.y * height_scale
		(model as Node3D).position.y = MODEL_FOOT_Y - min_y

	var cam := _make_cam(viewport)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.6, -0.7, 0)
	light.light_energy = 1.4
	viewport.add_child(light)

	if mesh_mode == "solo":
		var mesh_nodes: Array = []
		_find_mesh_nodes(model, mesh_nodes)
		for mi in mesh_nodes.size():
			for mn in mesh_nodes:
				mn.visible = false
			mesh_nodes[mi].visible = true
			await _snap(viewport, "%s_m%d" % [path.get_file().get_basename(), mi])
		mesh_nodes[0].visible = true
	else:
		await _snap(viewport, path.get_file().get_basename())
	viewport.queue_free()

func _make_cam(viewport: SubViewport) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.position = Vector3(2.6, 1.15, -2.6)
	viewport.add_child(cam)
	cam.look_at(Vector3(0, 0.85, 0), Vector3.UP)
	cam.make_current()
	return cam

func _snap(viewport: SubViewport, tag: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	var out := "user://vrm_shots/%s.png" % tag
	if img != null:
		img.save_png(out)
	else:
		out = "NO IMAGE"
	print("SHOT %s -> %s" % [tag, out])

func _find_mesh_nodes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_find_mesh_nodes(child, out)

func _remove_lod_duplicates(root: Node) -> void:
	var to_remove: Array = []
	_find_lod_dups(root, to_remove)
	for n in to_remove:
		n.queue_free()

func _find_lod_dups(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var nm := str(node.name).to_lower()
		if nm.contains("lod1") or nm.contains("lod2"):
			out.append(node)
	for child in node.get_children():
		_find_lod_dups(child, out)

func _find_skeletons(node: Node, out: Array) -> void:
	if node is Skeleton3D:
		out.append(node)
	for child in node.get_children():
		_find_skeletons(child, out)

func _scene_aabb(root: Node) -> AABB:
	var boxes: Array = []
	_collect_aabb(root, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var result: AABB = boxes[0]
	for i in range(1, boxes.size()):
		result = result.merge(boxes[i])
	return result

func _collect_aabb(node: Node, acc: Transform3D, boxes: Array) -> void:
	if node is Node3D:
		var node3d: Node3D = node
		var acc_local := acc * node3d.transform
		if node3d is MeshInstance3D and node3d.mesh != null:
			boxes.append(acc_local * node3d.mesh.get_aabb())
		for child in node3d.get_children():
			_collect_aabb(child, acc_local, boxes)
