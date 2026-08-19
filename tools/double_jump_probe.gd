extends Node
## 二段跳无头探针：验证附身角色一跳离地、空中二段跳生效、
## 三段跳无效、落地后次数重置。
## 用法：godot --headless --path . res://tools/double_jump_probe.tscn

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
	var chars := CharacterManager.all_characters()
	if chars.is_empty():
		get_tree().quit(1)
		return
	var target: AICharacter = chars[0]
	var pos := Vector3(0, WorldManager.get_terrain_height(0, 0) + 0.95, 0)
	target.global_position = pos
	target.velocity = Vector3.ZERO
	PlayerGodController.possess(target)
	PlayerGodController.possession_cam.set_first_person(true)
	for i in 10:
		await get_tree().physics_frame

	var checks: Array[bool] = []
	# 1) 第一次跳：离地
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var v1: float = target.velocity.y
	var airborne := not target.is_on_floor()
	checks.append(v1 > 3.0 and airborne)
	# 2) 空中二段跳：上升途中再按
	for i in 8:
		await get_tree().physics_frame
	var v_before2: float = target.velocity.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	await get_tree().physics_frame
	var v2: float = target.velocity.y
	checks.append(airborne and v2 > v_before2 + 0.5)
	# 3) 三段跳应无效
	for i in 4:
		await get_tree().physics_frame
	var v_before3: float = target.velocity.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	await get_tree().physics_frame
	var v3: float = target.velocity.y
	checks.append(v3 < v_before3 + 1.0)
	# 4) 落地后重置：等待落地再跳，应能再次起跳
	for i in 120:
		await get_tree().physics_frame
		if target.is_on_floor():
			break
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	checks.append(target.velocity.y > 3.0)
	print("DOUBLE_JUMP: v1=%.1f airborne=%s v2=%.1f v3=%.1f" % [v1, airborne, v2, v3])
	var ok := checks.all(func(c): return c)
	print("DOUBLE_JUMP: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
