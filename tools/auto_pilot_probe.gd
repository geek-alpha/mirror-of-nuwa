extends Node
## 自动模式验证：剧情模式 + AutoPilot 的自动探索与自动抉择。
## 用法：godot --headless --path . res://tools/auto_pilot_probe.tscn

var frames := 0
var elapsed := 0.0
var intro_seen := false
var intro_done := false
var player_start := Vector3.ZERO
var player_moved := false
var saw_choice := false
var choice_resolved := false
var talk_delivered := false
var talk_affinity_gained := false
var focus_ok := false
## 边走边聊期间的实际累计位移（验证踱步真的在动，而非只切换了状态）
var pace_distance := 0.0
var prev_pace_pos := Vector3.ZERO
## 踱步期间贴着对话对象（<1.5m）超过 1 秒视为被卡住
var pace_stuck_time := 0.0
var pace_bad_close := false
var pace_forced := false
var done := false

func _ready() -> void:
	Engine.max_fps = 60
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	GameState.game_mode = GameState.MODE_STORY
	GameState.player_name = "自动测试者"
	StoryModeManager.boot_duration = 0.05
	StoryModeManager.cinematic_duration = 0.05
	StoryModeManager.transition_duration = 0.05
	StoryModeManager.era_cutscene_duration = 0.05
	StoryModeManager.cinematic_enabled = false
	StoryModeManager.story_pace = 8.0
	ConfigManager.set_game_setting("story_start_era", "era_wenwang")
	var packed: PackedScene = load("res://scenes/main.tscn")
	add_child(packed.instantiate())
	# main.tscn 接线完成后开启自动模式（静默，不弹系统消息）
	AutoPilot.set_enabled(true, true)

func _process(delta: float) -> void:
	frames += 1
	elapsed += delta
	if done:
		return
	var sm := StoryModeManager
	if not sm.active:
		if frames > 300:
			_fail("剧情未激活")
		return
	if sm._intro_active:
		intro_seen = true
		return
	if intro_seen and not intro_done:
		# 自动模式应在旁白结束后自动跳过引言
		intro_done = true
		return
	if sm.player == null:
		return
	# 自动搭话投递：直接触发一次，确认好感增长且不报错
	if not talk_delivered and sm.figure != null and is_instance_valid(sm.figure) \
			and frames > 500:
		talk_delivered = true
		AutoPilot._deliver_auto_talk(sm.player, sm.figure, "你见过最长的恒纪元有多久？")
		var aff := RelationshipSystem.get_relationship(
			sm.figure, sm.player.character_data.id
		).affinity
		talk_affinity_gained = aff > 0.0
	# 探索：玩家从出生点移动超过 1.5 米
	if player_start == Vector3.ZERO:
		player_start = sm.player.global_position
	if player_start != Vector3.ZERO \
			and sm.player.global_position.distance_to(player_start) > 1.5:
		player_moved = true
	# 边走边聊：累计踱步期间的实际移动距离
	if AutoPilot.pacing_active() and sm.player != null and is_instance_valid(sm.player):
		if prev_pace_pos != Vector3.ZERO:
			pace_distance += sm.player.global_position.distance_to(prev_pace_pos)
		prev_pace_pos = sm.player.global_position
		var p_partner = AutoPilot._pace_partner
		if p_partner != null and is_instance_valid(p_partner):
			var hp := Vector2(sm.player.velocity.x, sm.player.velocity.z).length()
			var dist_p: float = sm.player.global_position.distance_to(p_partner.global_position)
			# 剧情节拍切换时全局锁定输入，角色本来就不能动，不计入卡死
			if not GameState.input_locked and dist_p < 1.5 and hp < 0.5:
				pace_stuck_time += delta
				if pace_stuck_time > 0.8:
					pace_bad_close = true
			else:
				pace_stuck_time = maxf(0.0, pace_stuck_time - delta)
	else:
		prev_pace_pos = Vector3.ZERO
	# 确定性触发一次边走边聊：把玩家放到角色附近再开启踱步，
	# 让“是否真的在动”的实测不依赖随机路径是否恰好路过角色
	if elapsed > 8.0 and elapsed < 12.0 and not sm.auto_busy() \
			and not sm.auto_choice_pending() and not sm.auto_dehydrate_pending() \
			and sm.figure != null and is_instance_valid(sm.figure) \
			and sm.player != null and is_instance_valid(sm.player) \
			and (not pace_forced or (pace_distance < 3.0 and not AutoPilot.pacing_active())):
		pace_forced = true
		var to_fig: Vector3 = sm.player.global_position - sm.figure.global_position
		to_fig.y = 0.0
		if to_fig.length() < 0.5:
			to_fig = Vector3(3.6, 0, 0)
		sm.player.global_position = sm.figure.global_position + to_fig.normalized() * 3.6
		AutoPilot._start_pacing(sm.figure)
		AutoPilot._pace_until = Time.get_ticks_msec() + 8000
	# 抉择：出现选项后被自动模式选中并结算
	if sm.auto_choice_pending():
		saw_choice = true
		if sm.auto_focus_character() != null:
			focus_ok = true
	elif saw_choice and not sm._ai_beat_active:
		choice_resolved = true
	if elapsed > 14.0 or frames > 1800:
		_finish()

func _finish() -> void:
	if done:
		return
	done = true
	# 自动搭话提示词应符合三体世界观并输出 JSON
	var talk_prompt := PromptBuilder.build_auto_talk_prompt({
		"era_name": "文明一 · 周文王",
		"era_kind": "恒纪元",
		"sky": "一轮太阳悬在稳定的轨道上",
		"sun_count": 1,
		"favor_text": "周文王 对你的态度：友好（亲密度 12）",
		"player_name": "测试者"
	}, "周文王")
	var prompt_ok: bool = talk_prompt.find("三体") != -1 \
		and talk_prompt.find("dialogue") != -1 \
		and talk_prompt.find("周文王") != -1
	# 人性化接口：跳跃请求、绕路点、冲刺节奏、拒绝脱水的阈值
	var api_ok := true
	if StoryModeManager.player != null and is_instance_valid(StoryModeManager.player):
		var p = StoryModeManager.player
		# API 检查是确定性单元级验证：先解除输入锁，避免剧情节拍锁定导致的合法零值误报
		GameState.input_locked = false
		# 人性化接口检查针对“正常赶路”模式：先退出可能的边走边聊踱步
		AutoPilot._stop_pacing()
		# 收尾时若有未处理的剧情抉择，先标记已处理，
		# 避免卡住/连跳模拟被 auto_choice_pending() 的守卫跳过
		if StoryModeManager != null:
			StoryModeManager._auto_picked = true
			if StoryModeManager.auto_dehydrate_pending():
				StoryModeManager.auto_choose_dehydrate(false)
		AutoPilot._set_target(p.global_position + Vector3(20, 0, 0), "测试")
		api_ok = api_ok and AutoPilot.wants_sprint(p) is bool
		AutoPilot._jump_request = 0.4
		# 首次起跳后应自动武装二段跳（空中补第二跳逃离）
		AutoPilot.consume_jump()
		# consume_jump 只负责武装；计时由 _tick_double_jump 在滞空时推进，
		# 这里只断言武装契约，避免依赖测试收尾时玩家是否恰好滞空
		api_ok = api_ok and AutoPilot._double_jump_armed
		AutoPilot._double_jump_armed = false
		AutoPilot._double_jump_timer = 0.0
		# 到达关键节点：停步环顾四周（视线缓慢转动）
		AutoPilot._start_look_around()
		api_ok = api_ok and AutoPilot._look_around_time > 0.0
		var yaw_before := 0.0
		var cam = PlayerGodController.possession_cam
		if cam != null and is_instance_valid(cam):
			yaw_before = cam.yaw
		AutoPilot._tick_look_around(0.2)
		if cam != null and is_instance_valid(cam):
			api_ok = api_ok and not is_equal_approx(cam.yaw, yaw_before)
		AutoPilot._look_around_time = 0.0
		var climbable := AutoPilot._can_climb_ahead(p)
		api_ok = api_ok and (climbable is bool)
		var dp := AutoPilot._detour_point(p, p.global_position + Vector3(30, 0, 0))
		api_ok = api_ok and dp != Vector3.ZERO
		# 灵动连跳/卡住绕路依赖剧情状态（抉择/脱水时会合法地不执行）：
		# 仅当剧情处于可模拟的普通状态时断言，避免探针时序性失败
		var story_sim_ok: bool = StoryModeManager != null \
				and StoryModeManager.is_story_active() and not StoryModeManager.dehydrated \
				and not StoryModeManager.auto_choice_pending() \
				and not StoryModeManager.auto_dehydrate_pending() \
				and p.is_on_floor()
		if story_sim_ok:
			# 灵动连跳：落地时连跳应立刻接下一跳；空中则等待落地
			AutoPilot._hop_chain = 1
			AutoPilot._jump_request = 0.0
			AutoPilot._hop_cooldown = 0.0
			var on_floor: bool = p.is_on_floor()
			AutoPilot._tick_agility(0.1)
			if p.is_on_wall():
				api_ok = api_ok and AutoPilot._hop_chain == 0  # 撞墙合理结束连跳
			elif on_floor:
				api_ok = api_ok and AutoPilot._jump_request > 0.0 and AutoPilot._hop_chain == 0
			else:
				api_ok = api_ok and AutoPilot._hop_chain == 1
			AutoPilot._hop_chain = 0
			AutoPilot._jump_request = 0.0
			AutoPilot._jump_request = 0.4
			api_ok = api_ok and AutoPilot.wants_jump()
			AutoPilot.consume_jump()
			api_ok = api_ok and not AutoPilot.wants_jump()
			# 卡住逻辑：模拟原地卡住 4 秒，最多试跳 2 次，随后转入绕路
			p.velocity = Vector3.ZERO
			AutoPilot._target = p.global_position + Vector3(20, 0, 0)
			AutoPilot._target_reason = "测试"
			AutoPilot._detour = Vector3.ZERO
			AutoPilot._jump_attempts = 0
			AutoPilot._stuck_time = 0.0
			var jump_triggers := 0
			var prev_jump := false
			for i in 40:
				AutoPilot._tick_stuck(0.1)
				var j := AutoPilot.wants_jump()
				if j and not prev_jump:
					jump_triggers += 1
				prev_jump = j
				AutoPilot._jump_request = 0.0
			api_ok = api_ok and jump_triggers <= 2 and AutoPilot._detour != Vector3.ZERO
			AutoPilot._detour = Vector3.ZERO
			AutoPilot._jump_request = 0.0
			AutoPilot._stuck_time = 0.0
		AutoPilot._detour = Vector3.ZERO
		AutoPilot._jump_request = 0.0
		AutoPilot._stuck_time = 0.0
		# 边走边聊：搭话后绕对方踱步，不站桩；偶尔回望
		var figure = StoryModeManager.figure
		if figure != null and is_instance_valid(figure):
			AutoPilot._start_pacing(figure)
			api_ok = api_ok and AutoPilot.pacing_active()
			api_ok = api_ok and not AutoPilot.wants_sprint(p)
			# 先把玩家放到距对方 3.6m 处，保证踱步方向非零、断言确定
			var to_fig: Vector3 = p.global_position - figure.global_position
			to_fig.y = 0.0
			if to_fig.length() < 2.0 or to_fig.length() > 6.0:
				p.global_position = figure.global_position + Vector3(3.6, 0, 0)
			api_ok = api_ok and AutoPilot.pace_direction(p) != Vector3.ZERO
			# 偶发回望：踱步期间会周期性给出回望点
			AutoPilot._glance_target = figure
			AutoPilot._glance_until = Time.get_ticks_msec() + 1000
			api_ok = api_ok and AutoPilot.glance_point() != Vector3.ZERO
			AutoPilot._glance_until = 0
			api_ok = api_ok and AutoPilot.glance_point() == Vector3.ZERO
			# 踱步窗口结束或对象失效后停止
			AutoPilot._pace_until = 0
			AutoPilot._tick_pacing(0.1)
			api_ok = api_ok and not AutoPilot.pacing_active()
			AutoPilot._stop_pacing()
	api_ok = api_ok and 0.1 < AutoPilot.REFUSE_DEHYDRATE_MAX_DOOM
	var ok: bool = AutoPilot.enabled and intro_done and player_moved \
		and saw_choice and choice_resolved and prompt_ok and talk_affinity_gained \
		and focus_ok and api_ok and pace_distance > 3.0 and not pace_bad_close
	print("AUTO_PILOT: %s" % ("PASS" if ok else "FAIL"))
	print("AUTO_PILOT: enabled=%s intro=%s moved=%s saw_choice=%s choice_resolved=%s prompt=%s talk=%s focus=%s api=%s pace_dist=%.2f stuck=%s target=%s status=%s" % [
		AutoPilot.enabled,
		intro_done,
		player_moved,
		saw_choice,
		choice_resolved,
		prompt_ok,
		talk_affinity_gained,
		focus_ok,
		api_ok,
		pace_distance,
		pace_bad_close,
		AutoPilot._target_reason,
		AutoPilot.status_text()
	])
	get_tree().quit(0 if ok else 1)

func _fail(reason: String) -> void:
	if done:
		return
	done = true
	print("AUTO_PILOT: FAIL - %s" % reason)
	get_tree().quit(1)
