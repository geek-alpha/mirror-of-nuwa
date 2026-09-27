extends Node
## 导演系统冒烟测试：启用 cinematic_enabled 验证入场过场（相机接管/输入锁定/恢复附身）
## 与剧情节拍演出（镜头+走位结束后剧情继续）。
## 用法：godot --headless --path . res://tools/director_smoke_test.tscn

var frames := 0
var phase := 0
var checks: Array[String] = []
var destroyed_before := 0
var tour_sample_ok := true
var tour_sample_count := 0
var tour_min_gap := INF
var tour_focus_min := INF
var tour_focus_max := -INF
var tour_focus_samples := 0
var tour_max_step := 0.0
var tour_last_pos := Vector3.INF
var director_under := false
var director_samples := 0

func _ready() -> void:
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	GameState.game_mode = GameState.MODE_STORY
	GameState.player_name = "测试者"
	StoryModeManager.boot_duration = 0.05
	StoryModeManager.cinematic_duration = 0.6
	StoryModeManager.transition_duration = 0.4
	StoryModeManager.arrival_duration = 0.1
	StoryModeManager.wake_duration = 0.3
	StoryModeManager.journey_leg_duration = 0.05
	# 天象/毁灭过场时长按类型取下限（destroy 9s 等），无头测试全部压缩
	StoryModeManager.destroy_cutscene_duration = 0.6
	StoryModeManager.hot_cutscene_duration = 0.6
	StoryModeManager.cold_cutscene_duration = 0.6
	StoryModeManager.stable_cutscene_duration = 0.6
	StoryModeManager.era_cutscene_duration = 0.6
	StoryModeManager.cinematic_enabled = true
	# 测试手动驱动节拍，关闭场景自动推进
	StoryModeManager.auto_advance_enabled = false
	# 测试驱动固定剧本链（camp→journey→gol_board→dehydrate），关闭 AI 开放剧情
	StoryModeManager.open_story = false
	# 固定从第一纪（周文王）开始，保证断言确定性
	ConfigManager.set_game_setting("story_start_era", "era_wenwang")
	# 固定默认第一人称，保证「睁眼附身即第一人称」断言不受用户配置影响
	ConfigManager.set_game_setting("view_mode_story", "first")
	StoryModeManager.start_story($World)
	UIManager.setup()
	PlayerGodController.setup_camera()
	StoryModeManager.after_ui_ready()
	TimeManager.set_time_scale(1.0)

func _process(_delta: float) -> void:
	frames += 1
	match phase:
		0:
			var d = StoryModeManager.cinematic_director
			# 入场过场播放中逐帧采样：导演相机必须始终高于地表，不冲进地里
			if d != null and is_instance_valid(d) and d.active and d.camera != null:
				var dc: Camera3D = d.camera
				var h := WorldManager.get_terrain_height(dc.global_position.x, dc.global_position.z)
				if dc.global_position.y < h + 1.0:
					director_under = true
				director_samples += 1
			if frames == 22:
				_check("过场期间导演激活", d != null and is_instance_valid(d) and d.active)
				_check("过场期间输入锁定", GameState.input_locked)
				_check("过场期间相机被导演接管", GameState.camera != null and GameState.camera.name == "DirectorCamera")
				# 收尾机位：必须在过场播放中检查——回归段会替换 _segments，结束后肩后段数据已丢失
				var pw := {}
				for w in d._walkers:
					if str(w.get("who", "")) == "figure":
						pw = w
						break
				var last_seg: Dictionary = d._segments[d._segments.size() - 1] if not d._segments.is_empty() else {}
				if not pw.is_empty() and last_seg.get("has_shoulder", false):
					var anchor: Vector3 = pw["target"]
					var face: Vector3 = pw["face"]
					var dirv := face - anchor
					dirv.y = 0.0
					var yaw := atan2(-dirv.x, -dirv.z)
					var back := Vector3(-sin(yaw), 0.0, -cos(yaw))
					var cam_dir: Vector3 = last_seg["to"] - anchor
					cam_dir.y = 0.0
					var angle_deg := rad_to_deg(back.angle_to(cam_dir.normalized()))
					_check("收尾机位 45° 侧后", angle_deg > 40.0 and angle_deg < 50.0)
				else:
					_check("收尾机位 45° 侧后", false)
			if frames < 80:
				return
			_check("过场相机始终高于地表", director_samples >= 20 and not director_under)
			print("DIRECTOR: director samples=%d under=%s" % [director_samples, director_under])
			phase = 1
		1:
			# 逐帧采样巡览相机：必须始终高于地表，避免镜头钻进山体穿帮
			if StoryModeManager._tour_cam != null and is_instance_valid(StoryModeManager._tour_cam):
				var tc: Camera3D = StoryModeManager._tour_cam
				var h := WorldManager.get_terrain_height(tc.global_position.x, tc.global_position.z)
				tour_min_gap = minf(tour_min_gap, tc.global_position.y - h)
				if tc.global_position.y < h + 1.0:
					tour_sample_ok = false
				tour_sample_count += 1
				if tc.is_focusing():
					var d: float = tc.global_position.distance_to(tc.current_look_target())
					tour_focus_min = minf(tour_focus_min, d)
					tour_focus_max = maxf(tour_focus_max, d)
					tour_focus_samples += 1
				if tour_last_pos != Vector3.INF:
					tour_max_step = maxf(tour_max_step, tc.global_position.distance_to(tour_last_pos))
				tour_last_pos = tc.global_position
			# 等入场过场（含相机回归段）真正结束：引言幕出现才算就位，避免固定帧窗口误判
			if frames < 90:
				return
			if not StoryModeManager._intro_active and frames < 900:
				return
			# 过场结束后：玩家睁眼前不加载，巡览相机接管，输入保持锁定
			_check("睁眼前玩家未加载", StoryModeManager.player == null)
			_check("巡览相机接管", GameState.camera != null \
				and GameState.camera.name == "IntroTourCamera")
			_check("巡览相机始终高于地表", tour_sample_count >= 10 and tour_sample_ok)
			print("DIRECTOR: tour samples=%d min_gap=%.2f" % [tour_sample_count, tour_min_gap])
			_check("聚焦角色距离3~5m", tour_focus_samples == 0 \
				or (tour_focus_min >= 3.0 and tour_focus_max <= 5.5))
			print("DIRECTOR: focus dist min=%.2f max=%.2f samples=%d" % [
				tour_focus_min, tour_focus_max, tour_focus_samples
			])
			_check("巡览相机运动平滑", tour_sample_count >= 10 and tour_max_step < 1.0)
			print("DIRECTOR: max_step=%.3f" % tour_max_step)
			_check("引言期间输入锁定", GameState.input_locked)
			_check("先讲背景（引言幕）", StoryModeManager._intro_active \
				and StoryModeManager.story_ui.intro_overlay.visible)
			phase = 2
		2:
			if not StoryModeManager._intro_active and frames < 1500:
				return
			StoryModeManager._on_intro_finished()
			phase = 3
		3:
			if not StoryModeManager._wake_active and frames < 2000:
				return
			_check("外部音后苏醒（睁眼见向导）", StoryModeManager._wake_active)
			_check("睁眼时玩家登场并附身", StoryModeManager.player != null \
				and GameState.mode == GameState.Mode.POSSESS \
				and PlayerGodController.possession_cam != null \
				and PlayerGodController.possession_cam.first_person)
			phase = 4
		4:
			if StoryModeManager._wake_active and frames < 2600:
				return
			# 营地节拍可能仍有演出占用：等演出结束再继续，避免 _on_continue 被守卫丢弃
			if StoryModeManager._choreography_active and frames < 3600:
				return
			_check("引言结束后输入解锁", not GameState.input_locked)
			# 营地场景 → 继续 → 登场抉择 → 旅行蒙太奇（带镜头演出的 scene beat）
			print("DBG: phase4 continue前节拍=%s wake=%s choreo=%s 输入锁=%s pending_next=%s beat_type=%s auto=%s" % [StoryModeManager.current_beat_id, StoryModeManager._wake_active, StoryModeManager._choreography_active, GameState.input_locked, StoryModeManager._pending_next_id, StoryModeManager._current_beat_type, StoryModeManager.auto_advance_enabled])
			StoryModeManager._on_continue()
			await get_tree().process_frame
			print("DBG: phase4 continue后节拍=%s pending_next=%s" % [StoryModeManager.current_beat_id, StoryModeManager._pending_next_id])
			phase = 5
		5:
			if frames < 2650:
				return
			# 抉择生效的前提是演出已结束（_on_choice 在演出期间会被丢弃）
			if StoryModeManager._choreography_active and frames < 3600:
				return
			StoryModeManager._on_choice(0)
			print("DBG: choice后即时节拍=%s choice已就绪=%s" % [StoryModeManager.current_beat_id, StoryModeManager.story_ui.choices_box.get_child_count() > 0])
			phase = 6
		6:
			if not StoryModeManager._choreography_active and frames < 3000:
				return
			if frames > 3600:
				print("DBG: choice后节拍=%s choreo=%s" % [StoryModeManager.current_beat_id, StoryModeManager._choreography_active])
				_check("节拍演出激活（journey）", false)
				phase = 7
				return
			_check("节拍演出激活（journey）", StoryModeManager._choreography_active)
			phase = 7
		7:
			if StoryModeManager._choreography_active and frames < 4000:
				return
			print("DBG: phase7 frame=%d 节拍=%s choreo=%s" % [frames, StoryModeManager.current_beat_id, StoryModeManager._choreography_active])
			# 演出结束、剧情继续
			_check("节拍演出结束", not StoryModeManager._choreography_active)
			_check("演出后剧情继续（journey）", StoryModeManager.current_beat_id == "journey")
			StoryModeManager._on_continue()
			phase = 8
		8:
			if StoryModeManager._choreography_active and frames < 5000:
				return
			print("DBG: phase8 frame=%d 节拍=%s choreo=%s" % [frames, StoryModeManager.current_beat_id, StoryModeManager._choreography_active])
			_check("抵达生命棋盘（gol_board）", StoryModeManager.current_beat_id == "gol_board")
			StoryModeManager._on_continue()
			phase = 9
		9:
			if StoryModeManager._choreography_active and frames < 6000:
				return
			print("DBG: phase9 frame=%d 节拍=%s choreo=%s" % [frames, StoryModeManager.current_beat_id, StoryModeManager._choreography_active])
			_check("继续后到达脱水抉择", StoryModeManager.current_beat_id == "dehydrate")
			_check("纣王登场聚焦", StoryModeManager.companion != null \
				and StoryModeManager.companion.character_data.name == "纣王")
			_check("同伴指点手势（纣王）", StoryModeManager.companion != null \
				and StoryModeManager.companion.anim_override == "point")
			# 等待期间随机天象（三日凌空）可能已提前毁灭过世界：以相对计数断言
			destroyed_before = StoryModeManager.destroyed_count
			# 触发乱纪元切换过场（酷热）
			StoryModeManager._apply_era_kind(StoryModeManager.EraKind.CHAOS_HOT)
			phase = 10
			return
		10:
			if not StoryModeManager.dehydrate_pending and frames < 6600:
				return
			var cd = StoryModeManager.cinematic_director
			# 过场自回归段可能仍在收尾：等导演完全交还控制权再断言
			if cd != null and is_instance_valid(cd) and cd.active and frames < 7000:
				return
			_check("酷热切换过场后恢复附身", GameState.mode == GameState.Mode.POSSESS)
			_check("酷热后弹出脱水抉择", StoryModeManager.dehydrate_pending)
			StoryModeManager._on_dehydrate_chosen(true)
			phase = 11
		11:
			if frames < 6700:
				return
			# 三日凌空：直接触发世界毁灭过场
			StoryModeManager._destroy_world("三日凌空！三颗飞星同时当空，文明当场毁灭。")
			phase = 12
		12:
			if not StoryModeManager.story_ui.overlay.visible and frames < 9000:
				return
			_check("毁灭过场后进入毁灭覆盖层", StoryModeManager.story_ui.overlay.visible \
				and StoryModeManager.destroyed_count > destroyed_before)
			_check("毁灭过场后保持上帝视角", GameState.mode == GameState.Mode.GOD)
			_check("覆盖层期间输入锁定", GameState.input_locked)
			_finish()
			return

func _check(name: String, ok: bool) -> void:
	var tag := "PASS" if ok else "FAIL"
	checks.append("[%s] %s" % [tag, name])
	print("DIRECTOR: [%s] %s" % [tag, name])

func _finish() -> void:
	var failed := 0
	for c in checks:
		if c.begins_with("[FAIL]"):
			failed += 1
	print("DIRECTOR: 完成，失败 %d 项" % failed)
	get_tree().quit(failed)
