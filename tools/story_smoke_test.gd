extends Node
## 剧情模式冒烟测试：覆盖 V 装具、抉择推进、三维目标节点、
## 真相碎片收集、脱水机制、毁灭倒计时、文明轮回、存档读取与真结局。
## 用法：godot --headless --path . res://tools/story_smoke_test.tscn

var frames := 0
var checks: Array[String] = []
var step := 0
var ui_count_before := 0
var progress_before_danger := 0.0

func _ready() -> void:
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	GameState.game_mode = GameState.MODE_STORY
	GameState.player_name = "测试者"
	StoryModeManager.boot_duration = 0.05
	StoryModeManager.cinematic_duration = 0.05
	StoryModeManager.transition_duration = 0.05
	StoryModeManager.destroy_cutscene_duration = 0.05
	StoryModeManager.hot_cutscene_duration = 0.05
	StoryModeManager.cold_cutscene_duration = 0.05
	StoryModeManager.stable_cutscene_duration = 0.05
	StoryModeManager.era_cutscene_duration = 0.05
	# 无头测试关闭导演演出，保持帧时序确定（演出本身在真实运行时启用）
	StoryModeManager.cinematic_enabled = false
	# 冒烟测试驱动固定剧本链，关闭 AI 开放剧情
	StoryModeManager.open_story = false
	# 测试手动驱动节拍，关闭场景自动推进
	StoryModeManager.auto_advance_enabled = false
	# 冒烟测试驱动固定剧本链：固定从第一纪（周文王）开始
	ConfigManager.set_game_setting("story_start_era", "era_wenwang")
	StoryModeManager.start_story($World)
	UIManager.setup()
	PlayerGodController.setup_camera()
	StoryModeManager.after_ui_ready()
	TimeManager.set_time_scale(1.0)

func _process(_delta: float) -> void:
	frames += 1
	match step:
		0:
			if frames < 25:
				return
			_check("剧情模式激活", StoryModeManager.active)
			_check("第一纪开始（周文王）", StoryModeManager.era_index == 0)
			_check("睁眼前玩家未加载", StoryModeManager.player == null)
			_check("历史向导存在（周文王）", StoryModeManager.figure != null \
				and StoryModeManager.figure.character_data.name == "周文王")
			_check("纣王尚未登场（渐进加入）", StoryModeManager.companion == null)
			_check("剧情UI可见", UIManager.story_ui != null and UIManager.story_ui.visible)
			_check("三日天空系统存在", StoryModeManager.sky != null and StoryModeManager.sky._suns.size() == 3)
			_check("生命游戏棋盘已生成", StoryModeManager.sky != null and StoryModeManager.sky._board_cells.size() >= 100)
			_check("目标灯塔已生成（3个）", StoryModeManager.beacons.size() == 3)
			_check("纪元引言幕展示（背景独立）", StoryModeManager._intro_active \
				and StoryModeManager.story_ui.intro_overlay.visible)
			_check("引言后才进入首幕", StoryModeManager.current_beat_id == "camp" \
				and StoryModeManager._pending_intro_beat == "camp")
			StoryModeManager._on_intro_finished()
			step = 1
		1:
			if frames < 45:
				return
			_check("首幕为营地场景", StoryModeManager.current_beat_id == "camp")
			_check("引言后玩家加载并附身", StoryModeManager.player != null \
				and GameState.mode == GameState.Mode.POSSESS \
				and GameState.possessed_character == StoryModeManager.player)
			_check("玩家名字生效", StoryModeManager.player != null \
				and StoryModeManager.player.character_data.name == GameState.player_name)
			StoryModeManager._on_continue()
			step = 2
		2:
			if frames < 60:
				return
			_check("抉择按钮已生成（≥2）", StoryModeManager.story_ui.choices_box.get_child_count() >= 2)
			StoryModeManager._on_choice(0)
			step = 3
		3:
			if frames < 75:
				return
			_check("旅行蒙太奇（journey）", StoryModeManager.current_beat_id == "journey")
			StoryModeManager._on_continue()
			step = 4
		4:
			if frames < 90:
				return
			_check("抵达生命棋盘（gol_board）", StoryModeManager.current_beat_id == "gol_board")
			StoryModeManager._on_continue()
			step = 5
		5:
			if frames < 105:
				return
			_check("推进到脱水抉择", StoryModeManager.current_beat_id == "dehydrate")
			_check("纣王中途加入", StoryModeManager.companion != null \
				and StoryModeManager.companion.character_data.name == "纣王")
			_check("同伴指点手势（纣王）", StoryModeManager.companion != null \
				and StoryModeManager.companion.anim_override == "point")
			StoryModeManager._on_choice(0)
			step = 6
		6:
			if frames < 120:
				return
			_check("结局节点被目标闸门拦截", StoryModeManager.current_beat_id == "east_end" \
				and StoryModeManager.objective_active and not StoryModeManager.objective_complete)
			_check("目标面板已显示", StoryModeManager.story_ui.objective_label.text.begins_with("目标："))
			# 依次抵达三个灯塔
			_teleport_to_objective(0)
			step = 7
		7:
			if frames < 130:
				return
			_check("关键节点1达成", StoryModeManager.objective_index == 1)
			_teleport_to_objective(1)
			step = 8
		8:
			if frames < 140:
				return
			_check("关键节点2达成", StoryModeManager.objective_index == 2)
			_teleport_to_objective(2)
			step = 9
		9:
			if frames < 155:
				return
			_check("关键节点完成，结局节点解锁", StoryModeManager.objective_complete and not StoryModeManager.objective_active)
			StoryModeManager._on_continue()
			step = 10
		10:
			if frames < 170:
				return
			_check("任务完成（文明完成使命覆盖层）", StoryModeManager.task_complete and StoryModeManager.story_ui.overlay.visible)
			_check("真相碎片已收集（1/5）", StoryModeManager.clues.size() == 1 and StoryModeManager.truth == 20.0)
			_check("真相进度条=20", StoryModeManager.story_ui.truth_bar.value == 20.0)
			StoryModeManager._on_overlay()
			step = 11
		11:
			if frames < 190:
				return
			_check("进入文明二（墨子）", StoryModeManager.era_index == 1)
			_check("历史向导为墨子", StoryModeManager.figure != null and StoryModeManager.figure.character_data.name == "墨子")
			_check("文明二无原著外随从", StoryModeManager.companion == null)
			StoryModeManager._on_intro_finished()
			# 跟随验证：把玩家瞬移到远处，向导/随从应留在原地（物理跟随而非吸附）
			StoryModeManager.player.global_position = Vector3(35, 0, 35)
			StoryModeManager.player.velocity = Vector3.ZERO
			step = 111
		111:
			if frames < 200:
				return
			_check("向导不随玩家瞬移（未绑定）", StoryModeManager.figure != null \
				and StoryModeManager.figure.global_position.distance_to(
					StoryModeManager.player.global_position) > 8.0)
			# 送回剧情区域继续后续测试
			StoryModeManager.player.global_position = Vector3(-32, 0, 16)
			StoryModeManager.player.velocity = Vector3.ZERO
			step = 12
		12:
			if frames < 210:
				return
			# 脱水机制：强制进入酷热乱纪元
			progress_before_danger = StoryModeManager.progress
			StoryModeManager._era_wall_time = 0.0  # 视为“正式”翻转，触发脱水抉择
			StoryModeManager._apply_era_kind(StoryModeManager.EraKind.CHAOS_HOT)
			step = 13
		13:
			if frames < 210 or not StoryModeManager.dehydrate_pending:
				if frames > 500:
					_check("酷热触发脱水抉择层", false)
					step = 14
				return
			if not StoryModeManager.story_ui.dehydrate_overlay.visible:
				return
			_check("酷热触发脱水抉择层", StoryModeManager.dehydrate_pending and StoryModeManager.story_ui.dehydrate_overlay.visible)
			StoryModeManager._on_dehydrate_chosen(true)
			step = 14
		14:
			if frames < 225:
				return
			_check("选择脱水后进入沉眠", StoryModeManager.dehydrated and not StoryModeManager.dehydrate_pending)
			# 天灾触发：脱水状态下酷热不削减进度
			StoryModeManager.danger_hours_left = 0.01
			step = 15
		15:
			if frames < 270:
				return
			_check("脱水沉眠免疫酷热天灾", is_equal_approx(StoryModeManager.progress, progress_before_danger))
			StoryModeManager._apply_era_kind(StoryModeManager.EraKind.STABLE)
			step = 16
		16:
			if frames < 285:
				return
			_check("恒纪元浸泡复水", not StoryModeManager.dehydrated)
			# 三日凌空：直接毁灭世界（无倒计时）
			StoryModeManager._destroy_world("三日凌空！三颗飞星同时当空，文明当场毁灭。")
			step = 17
		17:
			if frames < 300 or not StoryModeManager.story_ui.overlay.visible:
				if frames > 600:
					_check("三日凌空直接毁灭世界", false)
					step = 18
				return
			if StoryModeManager.destroyed_count != 1:
				return
			_check("三日凌空直接毁灭世界", StoryModeManager.story_ui.overlay.visible and StoryModeManager.destroyed_count == 1)
			_check("附身已退出", GameState.mode == GameState.Mode.GOD)
			StoryModeManager._on_overlay()
			step = 18
		18:
			if frames < 340:
				return
			_check("毁灭后进入文明三（冯·诺伊曼）", StoryModeManager.era_index == 2)
			if StoryModeManager.player == null:
				if StoryModeManager._intro_active:
					StoryModeManager._on_intro_finished()
				return
			_check("毁灭后重新附身", GameState.mode == GameState.Mode.POSSESS \
				and GameState.possessed_character == StoryModeManager.player)
			step = 19
		19:
			if frames < 360:
				return
			var ok := SaveManager.save_game("user://saves/story_smoke.json")
			_check("剧情存档写入", ok)
			if ok:
				var loaded := SaveManager.load_game("user://saves/story_smoke.json")
				_check("剧情存档读取", loaded)
				_check("读取后恢复剧情状态（文明三）", StoryModeManager.active and StoryModeManager.era_index == 2)
				_check("读取后恢复真相进度", StoryModeManager.truth == 20.0 and StoryModeManager.clues.size() == 1)
				_check("读取后天空重建", StoryModeManager.sky != null)
			# 读取后引言结束 → 玩家重新加载并附身
			if StoryModeManager.player == null:
				if StoryModeManager._intro_active:
					StoryModeManager._on_intro_finished()
				return
			_check("读取后恢复附身", GameState.mode == GameState.Mode.POSSESS)
			step = 20
		20:
			if frames < 400:
				return
			var menu_scene: PackedScene = load("res://scenes/ui/start_menu.tscn")
			_check("开局菜单场景可加载", menu_scene != null)
			if menu_scene != null:
				var menu = menu_scene.instantiate()
				add_child(menu)
				_check("开局菜单已构建", menu != null and menu.start_btn != null and menu.story_btn != null and menu.free_btn != null)
			step = 21
		21:
			if frames < 420:
				return
			# 真结局：集齐真相后跳入最终文明
			StoryModeManager.truth = 100.0
			StoryModeManager.clues = ["clue_sun_chaos", "clue_mechanical_fail", "clue_no_solution", "clue_chaos_theory", "clue_dice"]
			StoryModeManager.era_index = 4
			StoryModeManager.begin_era(StoryModeManager.eras[4])
			step = 22
		22:
			if frames < 440:
				return
			_check("最终文明化身爱因斯坦", StoryModeManager.figure != null and StoryModeManager.figure.character_data.name == "爱因斯坦")
			_check("最终纪元引言幕展示", StoryModeManager._intro_active \
				and StoryModeManager.story_ui.intro_overlay.visible)
			StoryModeManager._on_intro_finished()
			step = 23
		23:
			if frames < 455:
				return
			_check("最终文明化身玩家", GameState.possessed_character == StoryModeManager.player)
			StoryModeManager._on_continue()
			step = 24
		24:
			if frames < 470:
				return
			StoryModeManager._on_choice(0)
			step = 25
		25:
			if frames < 485:
				return
			StoryModeManager._on_continue()
			_check("伽利略在石碑幕登场", StoryModeManager.companion != null \
				and StoryModeManager.companion.character_data.name == "伽利略")
			step = 26
		26:
			if frames < 500:
				return
			StoryModeManager._on_continue()
			_check("最终抉择被墓碑目标拦截", StoryModeManager.current_beat_id == "final_choice" and StoryModeManager.objective_active)
			_teleport_to_objective(0)
			step = 27
		27:
			if frames < 510:
				return
			_teleport_to_objective(1)
			step = 28
		28:
			if frames < 525:
				return
			_check("墓碑刻字完成，最终抉择解锁", StoryModeManager.objective_complete)
			StoryModeManager._on_choice(0)
			step = 29
		29:
			if frames < 540:
				return
			StoryModeManager._on_continue()
			step = 30
		30:
			if frames < 555:
				return
			_check("真结局：通关覆盖层", StoryModeManager.finished and StoryModeManager.story_ui.overlay.visible \
				and StoryModeManager.story_ui.overlay_title.text == "三体游戏 · 通关")
			_check("通关成就解锁", GameState.achievements.has("three_body"))
			# 失败结局分支（飞船）
			StoryModeManager._handle_ending("escape", "测试失败结局")
			_check("失败结局：终局覆盖层", StoryModeManager.story_ui.overlay.visible \
				and StoryModeManager.story_ui.overlay_title.text == "三体游戏 · 终局")
			# 残缺真相的墓碑结局 → 不构成通关，提示重新开始
			StoryModeManager.truth = 0.0
			StoryModeManager._handle_ending("monument", "测试残缺真相")
			_check("残缺真相：不构成通关", StoryModeManager.story_ui.overlay_title.text == "三体游戏 · 终局" \
				and StoryModeManager.story_ui.overlay_btn.text == "文明轮回 · 重新开始")
			StoryModeManager.reset()
			step = 31
		31:
			if frames < 575:
				return
			_check("重置后剧情停止", not StoryModeManager.active)
			ui_count_before = UIManager.ui_layer.get_child_count()
			GameState.game_mode = GameState.MODE_STORY
			StoryModeManager.start_story($World)
			UIManager.setup()
			StoryModeManager.after_ui_ready()
			step = 32
		32:
			if frames < 630:
				return
			_check("重启后真相清零", StoryModeManager.truth == 0.0 and StoryModeManager.clues.is_empty())
			_check("UI层幂等（无重复面板）", UIManager.ui_layer.get_child_count() == ui_count_before)
			# 引言结束 → 玩家重新加载并附身
			if StoryModeManager.player == null:
				if StoryModeManager._intro_active:
					_check("重启后引言幕恢复", StoryModeManager._intro_active \
						and StoryModeManager.story_ui.intro_overlay.visible)
					StoryModeManager._on_intro_finished()
				return
			_check("重启剧情后重新附身", StoryModeManager.active and StoryModeManager.era_index == 0 \
				and GameState.mode == GameState.Mode.POSSESS)
			step = 33
		33:
			if frames < 650:
				return
			_finish()
			return

func _teleport_to_objective(index: int) -> void:
	if StoryModeManager.player == null:
		return
	var pt: Dictionary = StoryModeManager.objective_points[index]
	var pos_arr: Array = pt.get("pos", [0.0, 0.0, 0.0])
	var pos := Vector3(float(pos_arr[0]), 0, float(pos_arr[2]))
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z) + 0.95
	StoryModeManager.player.global_position = pos
	StoryModeManager.player.velocity = Vector3.ZERO

func _check(name: String, ok: bool) -> void:
	var tag := "PASS" if ok else "FAIL"
	checks.append("[%s] %s" % [tag, name])
	print("STORY: [%s] %s" % [tag, name])

func _finish() -> void:
	var failed := 0
	for c in checks:
		if c.begins_with("[FAIL]"):
			failed += 1
	if failed == 0:
		print("STORY: 全部通过（%d 项）✓" % checks.size())
	else:
		print("STORY: %d 项失败" % failed)
	get_tree().quit(failed)
