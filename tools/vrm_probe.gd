extends SceneTree
## VRM 模型诊断探针：用与 AICharacter 相同的路径（GLTFDocument 运行时解析 + VRMRigDriver）
## 逐个加载 assets/models/characters 下的 VRM，输出：
##   - 加载结果 / 骨架数量与骨骼数
##   - VRMRigDriver 是否启用（能否解析 hips/head/肢干）
##   - 运行时场景网格包围盒（判断“只剩头”类缩放异常）
##   - head/neck 骨骼 rest 旋转（判断“头部歪了”）
## 用法：godot --headless -s tools/vrm_probe.gd

const VRM_RIG_SCRIPT := preload("res://scripts/characters/vrm_rig_driver.gd")

func _init() -> void:
	var only := ""
	var only_idx := -1
	for arg in OS.get_cmdline_args():
		if arg.begins_with("file="):
			only = arg.substr(5)
		elif arg.begins_with("idx="):
			only_idx = int(arg.substr(4))
	var dirs := ["res://assets/models/characters/male", "res://assets/models/characters/famale"]
	var files: Array[String] = []
	for d in dirs:
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
	for i in files.size():
		var full := files[i]
		if only_idx >= 0:
			if i == only_idx:
				_probe(full)
		elif only == "" or full.get_file().to_lower().contains(only.to_lower()):
			_probe(full)
	quit()

func _probe(path: String) -> void:
	var name := path.get_file()
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(path, state)
	if err != OK:
		print("[%s] LOAD FAIL err=%d" % [name, err])
		return
	var scene := gltf.generate_scene(state)
	if scene == null:
		print("[%s] GENERATE FAIL" % name)
		return
	var skeletons: Array = []
	_find_skeletons(scene, skeletons)
	var skel_count := skeletons.size()
	var bone_count := 0
	var head_rest := ""
	var hips_bone := ""
	var head_bone := ""
	var rig_enabled := false
	if skel_count > 0:
		var skel: Skeleton3D = skeletons[0]
		bone_count = skel.get_bone_count()
		var rig = VRM_RIG_SCRIPT.new()
		rig.setup(skel, path)
		rig_enabled = rig.enabled
		if not rig_enabled:
			var mapping: Dictionary = rig._read_vrm_humanoid_mapping(path)
			print("      mapping hips=%s spine=%s head=%s" % [str(mapping.get("hips","")), str(mapping.get("spine","")), str(mapping.get("head",""))])
			var pelvis_names: Array[String] = []
			for bi in skel.get_bone_count():
				var bn := skel.get_bone_name(bi)
				if bn.to_lower().contains("pelvis") or bn.to_lower().contains("hips"):
					pelvis_names.append(bn)
			print("      runtime bones containing 'pelvis'/'hips': %s" % str(pelvis_names))
			var mapped_found: Array[String] = []
			for key in ["hips", "spine", "head"]:
				var mn := str(mapping.get(key, ""))
				mapped_found.append("%s=%s" % [key, str(skel.find_bone(mn) >= 0)])
			print("      find_bone(mapping): %s" % " ".join(mapped_found))
		if rig.bone_ids.has("hips"):
			hips_bone = skel.get_bone_name(int(rig.bone_ids["hips"]))
		if rig.bone_ids.has("head"):
			head_bone = skel.get_bone_name(int(rig.bone_ids["head"]))
			var rest := skel.get_bone_rest(int(rig.bone_ids["head"]))
			head_rest = "(%s)" % [str(rest.basis.get_rotation_quaternion())]
	var aabb := _scene_aabb(scene)
	if path.get_file().contains("棕发"):
		var mesh_nodes: Array = []
		_find_mesh_nodes(scene, mesh_nodes)
		for mn in mesh_nodes:
			var mi := mn as MeshInstance3D
			var skinned := false
			var surf_info := ""
			if mi.mesh != null:
				for si in mi.mesh.get_surface_count():
					var fmt: int = mi.mesh.surface_get_format(si)
					if fmt & Mesh.ARRAY_FORMAT_BONES or fmt & Mesh.ARRAY_FORMAT_WEIGHTS:
						skinned = true
					surf_info += "S%d(fmt=0x%x) " % [si, fmt]
			print("      mesh node '%s' skin_path='%s' skeleton_node=%s skinned=%s %s" % [
				mi.name, mi.skeleton, str(mi.get_node_or_null(mi.skeleton) if mi.skeleton != NodePath() else null), str(skinned), surf_info
			])
	if path.get_file().contains("棕发") or path.get_file().contains("呆萌"):
		var skel: Skeleton3D = null
		var roots: Array = []
		_find_skeletons(scene, roots)
		if not roots.is_empty():
			skel = roots[0]
			var hip_idx := skel.find_bone("J_Bip_C_Hips")
			var head_idx := skel.find_bone("J_Bip_C_Head")
			print("      skeleton node=%s skeleton_global=%s hips_global_rest=%s head_global_rest=%s" % [
				skel.name, str(skel.global_transform.origin), 
				str(skel.get_bone_global_rest(hip_idx).origin) if hip_idx >= 0 else "?",
				str(skel.get_bone_global_rest(head_idx).origin) if head_idx >= 0 else "?"
			])
	var aabb_text := "NONE"
	if aabb.size.y > 0.001:
		aabb_text = "min=(%.2f, %.2f, %.2f) max=(%.2f, %.2f, %.2f) h=%.2f" % [
			aabb.position.x, aabb.position.y, aabb.position.z,
			aabb.end.x, aabb.end.y, aabb.end.z, aabb.size.y
		]
	print("[%s] skeletons=%d bones(first)=%d rig_enabled=%s hips=%s head=%s head_rest=%s" % [
		name, skel_count, bone_count, str(rig_enabled), hips_bone, head_bone, head_rest
	])
	print("      aabb %s" % aabb_text)
	scene.free()

func _find_mesh_nodes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_find_mesh_nodes(child, out)

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
