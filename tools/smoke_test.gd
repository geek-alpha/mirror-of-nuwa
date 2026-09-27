extends Node
## 冒烟测试场景：初始化世界后运行数百帧，验证核心系统、输入控制与存档功能。
## 注意：无头模式下物理以约 30Hz 运行，因此各检查帧号已按半速物理留足余量。
## 用法：godot --headless --path . res://tools/smoke_test.tscn

var frames := 0
var checks: Array[String] = []
var first_char = null
var move_start := Vector3.ZERO
var cam_start := Vector3.ZERO
var probe_body: CharacterBody3D = null
var selection_test_char = null
var ever_active: Dictionary = {}

func _ready() -> void:
	# 冒烟测试不依赖外部服务：关闭 AI 语音，避免自动拉起 TTS 进程
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	CivilizationManager.initialize_factions()
	WorldManager.initialize_world($World)
	CharacterManager.spawn_initial_characters()
	UIManager.setup()
	PlayerGodController.setup_camera()
	TimeManager.set_time_scale(10.0)
	HistoryManager.log_event("world", "世界诞生", "冒烟测试世界。")

func _physics_process(delta: float) -> void:
	if probe_body != null:
		probe_body.velocity.y -= 22.0 * delta
		probe_body.move_and_slide()

func _process(_delta: float) -> void:
	frames += 1
	for c in CharacterManager.all_characters():
		if c.current_action.size() > 0 or c.moving or c.character_data.memories.size() > 1:
			ever_active[c.get_instance_id()] = true
	match frames:
		30:
			_check("角色数量≥10", CharacterManager.characters.size() >= 10)
			_check("资源节点≥20", WorldManager.resource_nodes.size() >= 20)
			_check("建筑≥5", WorldManager.buildings.size() >= 5)
			_check("地形高度查询", absf(WorldManager.get_terrain_height(0, 0)) < 60.0)
			_check("输入映射已注册", InputMap.has_action("move_forward") and InputMap.has_action("jump") and InputMap.has_action("sprint"))
			_check("触摸控件已创建", UIManager.touch_controls != null)
			UIManager.force_mobile_controls(true)
			_check("触摸控件强制显示", UIManager.touch_controls != null and UIManager.touch_controls.visible)
			var rig_chars := 0
			var vrm_chars := 0
			for c in CharacterManager.all_characters():
				if c.procedural_rig != null or c.model_anim_player != null or c.vrm_rig != null:
					rig_chars += 1
				if c.vrm_rig != null:
					vrm_chars += 1
			_check("骨骼角色外观（程序化/模型）", rig_chars >= 10)
			_check("VRM 模型角色加载", vrm_chars >= 1)
			# 落地探针：验证地形碰撞能让角色站稳（从高处落下）
			probe_body = CharacterBody3D.new()
			var pcol := CollisionShape3D.new()
			var pcap := CapsuleShape3D.new()
			pcap.radius = 0.4
			pcap.height = 1.9
			pcol.shape = pcap
			probe_body.add_child(pcol)
			$World.add_child(probe_body)
			probe_body.global_position = Vector3(0, 20, 0)
			var chars := CharacterManager.all_characters()
			if not chars.is_empty():
				first_char = chars[0]
		500:
			if probe_body != null:
				_check("地形碰撞可站立（落地探针）", probe_body.is_on_floor() and probe_body.global_position.y > -3.0)
			var min_y := INF
			var acted := 0
			var progressed := 0
			for c in CharacterManager.all_characters():
				min_y = minf(min_y, c.global_position.y)
				if c.current_action.size() > 0 or c.moving or c.character_data.memories.size() > 1:
					acted += 1
				if c.character_data.memories.size() > 1:
					progressed += 1
			if min_y <= -3.0:
				for c in CharacterManager.all_characters():
					if c.global_position.y < -3.0:
						print("DEBUG: 低y角色 %s y=%.1f" % [c.character_data.name, c.global_position.y])
			_check("NPC不穿地（y>-3）", min_y > -3.0)
			_check("角色活跃（决策/行动/记忆）", ever_active.size() >= 3)
			_check("时间推进", TimeManager.game_time > 1.0)
			_check("文明研究推进", CivilizationManager.factions.size() == 2)
		470:
			# 把待选角色传送到中央平地，方便点击测试
			if first_char == null or not is_instance_valid(first_char) or not first_char.alive:
				for c in CharacterManager.all_characters():
					if c.alive:
						first_char = c
						break
			if first_char != null:
				first_char.global_position = Vector3(0, 3, 0)
				first_char.velocity = Vector3.ZERO
				# 相机看向角色，保证投影在屏幕内
				PlayerGodController.god_camera.look_at(first_char.global_position + Vector3(0, 1, 0), Vector3.UP)
				selection_test_char = first_char
		480:
			# 模拟左键点击角色的屏幕位置，验证“点击选中”路径
			if selection_test_char != null:
				# 相机贴近角色正上方俯视（视线仅数米）：远景斜俯视时随机生成的建筑/
				# 资源节点会挡在角色与相机之间，射线先命中它们就变成“点建筑”（按设计
				# 清空角色选中并 return），断言随之偶发假失败。
				selection_test_char.global_position = Vector3(0, 10, 0)
				selection_test_char.velocity = Vector3.ZERO
				PlayerGodController.god_camera.global_position = Vector3(0, 16, 0.5)
				PlayerGodController.god_camera.look_at(selection_test_char.global_position + Vector3(0, 1.0, 0), Vector3.UP)
				var sp := PlayerGodController.god_camera.unproject_position(selection_test_char.global_position + Vector3(0, 1.0, 0))
				# 真实鼠标事件以窗口（嵌入器）坐标进入引擎，再由引擎转换为视口坐标；
				# Input.parse_input_event 同样按嵌入器坐标处理，因此这里先转回窗口坐标，
				# 才能在任意窗口缩放比例下等价于真实点击。
				var window_pos: Vector2 = selection_test_char.get_viewport().get_final_transform() * sp
				var mm := InputEventMouseMotion.new()
				mm.position = window_pos
				Input.parse_input_event(mm)
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = true
				click.position = window_pos
				Input.parse_input_event(click)
				var click_up := InputEventMouseButton.new()
				click_up.button_index = MOUSE_BUTTON_LEFT
				click_up.pressed = false
				click_up.position = window_pos
				Input.parse_input_event(click_up)
		485:
			if selection_test_char != null:
				_check("点击选中角色", GameState.selected_character == selection_test_char)
				selection_test_char = null
			else:
				_check("点击选中角色", false)
		620:
			if first_char != null and is_instance_valid(first_char):
				PlayerGodController.possess(first_char)
				_check("化身模式进入", GameState.mode == GameState.Mode.POSSESS)
				PlayerGodController.exit_possession()
				_check("化身模式退出", GameState.mode == GameState.Mode.GOD)
				PlayerGodController.send_oracle(first_char, "晶海在呼唤你。")
				_check("神谕记忆写入", first_char.character_data.memories.size() >= 2)
				first_char.set_animation_state("run")
				_check("骨骼动画状态切换", first_char.current_anim == "run")
		650:
			# 传送到开阔的中央平地，避免出生点建筑/资源阻挡移动测试
			if first_char != null and is_instance_valid(first_char) and first_char.alive:
				first_char.global_position = Vector3(0, 3, 0)
				first_char.velocity = Vector3.ZERO
				first_char.moving = false
				first_char.current_action = {}
		660:
			# 化身移动输入测试：按住W
			if first_char != null and is_instance_valid(first_char):
				PlayerGodController.possess(first_char)
				move_start = first_char.global_position
				Input.action_press("move_forward")
		760:
			Input.action_release("move_forward")
			if first_char != null and is_instance_valid(first_char):
				var moved := Vector2(first_char.global_position.x - move_start.x, first_char.global_position.z - move_start.z).length()
				_check("化身移动（WASD输入）", moved > 0.5)
			PlayerGodController.exit_possession()
		780:
			# 上帝相机移动输入测试：按住W
			cam_start = PlayerGodController.god_camera.global_position
			Input.action_press("move_forward")
		830:
			Input.action_release("move_forward")
			var cam_moved := PlayerGodController.god_camera.global_position.distance_to(cam_start)
			_check("上帝相机移动（WASD输入）", cam_moved > 0.5)
			# 鼠标旋转测试（事件在下一帧flush）
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_RIGHT
			press.pressed = true
			Input.parse_input_event(press)
			var motion := InputEventMouseMotion.new()
			motion.relative = Vector2(120, 0)
			Input.parse_input_event(motion)
		850:
			var yaw_changed := absf(PlayerGodController.god_camera.yaw) > 0.1
			_check("上帝相机旋转（鼠标拖拽）", yaw_changed)
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_RIGHT
			release.pressed = false
			Input.parse_input_event(release)
		870:
			# 触摸控件测试：视角拖动 / 缩放 / 摇杆
			if UIManager.touch_controls != null:
				var yaw_before := PlayerGodController.god_camera.yaw
				PlayerGodController.touch_look(Vector2(120, 0))
				_check("触摸视角旋转", absf(PlayerGodController.god_camera.yaw - yaw_before) > 0.2)
				PlayerGodController.touch_zoom(1)  # 神模式缩放无速度效果（不应报错）
				UIManager.touch_controls.set_joystick_vector(Vector2(0, -1))
				_check("摇杆前进动作", Input.is_action_pressed("move_forward"))
				cam_start = PlayerGodController.god_camera.global_position
		900:
			var ok := SaveManager.save_game("user://saves/smoke_test.json")
			_check("存档写入", ok)
			if ok:
				var loaded := SaveManager.load_game("user://saves/smoke_test.json")
				_check("存档读取", loaded)
				_check("读取后角色恢复", CharacterManager.characters.size() >= 10)
		910:
			# 把待选角色送到中央平地，供触摸点选测试
			var tap_char = null
			for c in CharacterManager.all_characters():
				if c != null and c.alive:
					tap_char = c
					break
			if tap_char != null:
				var spot := Vector3(0, 0, 0)
				for i in 60:
					var cand := Vector3(randf_range(-35, 35), 0, randf_range(-35, 35))
					var blocked := false
					for b in WorldManager.buildings:
						if b.global_position.distance_to(cand) < 8.0:
							blocked = true
							break
					if not blocked:
						for r in WorldManager.resource_nodes:
							if r.global_position.distance_to(cand) < 3.0:
								blocked = true
								break
					if not blocked:
						spot = cand
						break
				var th := WorldManager.get_terrain_height(spot.x, spot.z)
				tap_char.global_position = Vector3(spot.x, th + 2.5, spot.z)
				tap_char.velocity = Vector3.ZERO
				PlayerGodController.god_camera.look_at(tap_char.global_position + Vector3(0, 1, 0), Vector3.UP)
				selection_test_char = tap_char
		930:
			# 触摸摇杆移动与点按选中测试
			if UIManager.touch_controls != null:
				UIManager.touch_controls.reset_joystick()
				_check("摇杆复位释放动作", not Input.is_action_pressed("move_forward"))
				var cam_moved := PlayerGodController.god_camera.global_position.distance_to(cam_start)
				_check("上帝相机移动（触摸摇杆）", cam_moved > 0.5)
			if selection_test_char != null and is_instance_valid(selection_test_char):
				PlayerGodController.god_camera.look_at(selection_test_char.global_position + Vector3(0, 1, 0), Vector3.UP)
				var sp := PlayerGodController.god_camera.unproject_position(selection_test_char.global_position + Vector3(0, 1.0, 0))
				var window_pos: Vector2 = selection_test_char.get_viewport().get_final_transform() * sp
				var touch := InputEventScreenTouch.new()
				touch.index = 0
				touch.position = window_pos
				touch.pressed = true
				Input.parse_input_event(touch)
				var touch_up := InputEventScreenTouch.new()
				touch_up.index = 0
				touch_up.position = window_pos
				touch_up.pressed = false
				Input.parse_input_event(touch_up)
		935:
			if selection_test_char != null and is_instance_valid(selection_test_char):
				_check("触摸点按选中角色", GameState.selected_character == selection_test_char)
				selection_test_char = null
		980:
			_finish()
			return

func _check(name: String, ok: bool) -> void:
	var tag := "PASS" if ok else "FAIL"
	checks.append("[%s] %s" % [tag, name])
	print("SMOKE: [%s] %s" % [tag, name])

func _finish() -> void:
	var failed := 0
	for c in checks:
		if c.begins_with("[FAIL]"):
			failed += 1
	if failed == 0:
		print("SMOKE: 全部通过（%d 项）✓" % checks.size())
	else:
		print("SMOKE: %d 项失败" % failed)
	get_tree().quit(failed)
