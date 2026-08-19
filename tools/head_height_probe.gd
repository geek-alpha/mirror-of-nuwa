extends Node
## 头部高度测量探针：打印每个角色的原点高度、地形高度与真实头部本地 Y，
## 用于校准第一人称相机眼高。
## 用法：godot --headless --path . res://tools/head_height_probe.tscn

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
	for i in 45:
		await get_tree().process_frame
	var chars := CharacterManager.all_characters()
	print("CHAR_COUNT: %d" % chars.size())
	for c in chars:
		var head_local := _head_local_y(c)
		var aabb_top := _model_top_local_y(c)
		var terrain := WorldManager.get_terrain_height(c.global_position.x, c.global_position.z)
		print("CHAR: %-12s model=%s origin_y=%.2f terrain=%.2f bone_head=%.2f aabb_top=%.2f eye_est=%.2f" % [
			c.character_data.name, c.has_model, c.global_position.y, terrain, head_local, aabb_top,
			c.global_position.y + head_local - terrain
		])
	print("HEAD_PROBE_DONE")
	get_tree().quit(0)

func _head_local_y(c: AICharacter) -> float:
	if c.procedural_rig != null:
		var att := c.procedural_rig.get_node_or_null("Skeleton/head") as Node3D
		if att != null:
			return att.global_position.y - c.global_position.y
	# 模型角色：用模型包围盒顶部估算头部中心
	if c.vrm_rig != null and c.vrm_rig.skeleton != null:
		var sk: Skeleton3D = c.vrm_rig.skeleton
		var head_idx := sk.find_bone("head")
		if head_idx >= 0:
			var head_world := sk.to_global(sk.get_bone_global_pose(head_idx).origin)
			return head_world.y - c.global_position.y
	return 1.5

func _model_top_local_y(c: AICharacter) -> float:
	## 与 _fit_model_to_ground 一致：脚底本地 -0.95，身高按外观 scale 归一化
	var scale_value := 1.0
	if c.character_data != null:
		scale_value = float(c.character_data.appearance.get("scale", 1.0))
	return AICharacter.MODEL_FOOT_Y + AICharacter.MODEL_TARGET_HEIGHT * clampf(scale_value, 0.5, 2.0)
