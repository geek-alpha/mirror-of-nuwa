extends Node
## 自动模式（AutoPilot）：三体游戏自动探索 + 攻略 + 得分最大化。
##
## 开启后自动执行：
##   - 探索：优先前往当前目标灯塔；最后一个灯塔前先寻遗宝把文明进度刷到 75%，
##     确保拿到该纪元的真相碎片；顺路与过客相遇；无事可做时自由探索世界；
##     途中实时局部寻路：以射线探测前方障碍并选择可通行的方向绕行，避免被
##     建筑/岩壁困住；跳跃+二段跳翻越可攀障碍，二段跳在最高点触发并向目标
##     方向持续冲刺位移，开阔平地偶尔连续跳跃；
##   - 攻略：主动靠近历史人物/同伴并定期交谈，提升好感（亲密度/信任）；
##     交谈时边走边聊：绕对方缓步踱步、偶尔回望，不站桩；
##   - 抉择：剧情选项按「进度×100 + 真相×5 + 好感×2 - 危险惩罚」自动选择最优，
##     并像真人一样略作停顿再选；
##   - 生存：酷热乱纪元默认拒绝脱水、顶着酷热赶路尽快通关；
##     仅当毁灭进度逼近临界时才脱水避险；结局/毁灭覆盖层自动继续轮回；
##   - 得分：以「进度 + 真相 + 好感」为自动得分，在 HUD 上实时显示。
##
## 仅在剧情模式（三体游戏）下生效；自由模拟中会自动关闭。

const FARM_TARGET_PROGRESS := 0.75
const FARM_TRUTH_TARGET := 60.0
const MAX_FARM_PER_ERA := 6
const TALK_COOLDOWN := 18.0
const CHOICE_DELAY := 1.5
const OVERLAY_DELAY := 4.0
const RETARGET_INTERVAL := 0.35
const TALK_RADIUS := 4.5
const REFUSE_DEHYDRATE_MAX_DOOM := 0.6
## 边走边聊：搭话/对话期间绕对话对象缓步踱步，不站桩
## 踱步半径：绕对方走动时保持的可交谈距离
const PACE_RADIUS := 3.8
const PACE_MIN_SECONDS := 6.0
const PACE_MAX_SECONDS := 11.0
## 换点步距：每走到一个踱步点，绕对方转过的弧度范围。
## 步距上限受限于安全距离：两点间的直线路径不得穿过对方（弦中点 ≥ 贴身安全距离）
const PACE_STEP_MIN_ANGLE := 1.2
const PACE_STEP_MAX_ANGLE := 1.8
## 贴身安全距离：低于此距离直接向外撤出，避免顶着对方碰撞体打转
const PACE_SAFE_MIN_DIST := 2.2
const PACE_FLIP_MIN_SECONDS := 4.0
const PACE_FLIP_MAX_SECONDS := 8.0
## 偶发回望：踱步途中每隔几秒短暂看一眼对话对象，模拟真人边走边聊
const GLANCE_FIRST_MIN := 1.2
const GLANCE_FIRST_MAX := 2.5
const GLANCE_EVERY_MIN := 2.0
const GLANCE_EVERY_MAX := 4.0
const GLANCE_DURATION_MS := 700
## 实时局部寻路：候选方向采样数、近/远探测距离、可跨越的坎高
const PATH_SAMPLE_COUNT := 16
const PATH_PROBE_NEAR := 1.5
const PATH_PROBE_FAR := 3.0
const PATH_PROBE_LONG := 5.0
## 直行视距：直线方向上更远的实体障碍也会触发绕行
const PATH_LOOKAHEAD := 6.0
## 视为“不可通行高坎”的地面落差：超过该值（约 40°+ 陡坡）才绕行，
## 普通坡面直接用 move_and_slide 走上去，避免把缓坡误判成墙
const PATH_MAX_STEP := 2.5
## 贴墙绕行时朝目标方向的混合权重（越小越贴墙，越大越趋向目标）
const CONTOUR_BLEND := 0.35
## 避障方向重新采样的间隔（秒）
const STEER_UPDATE_INTERVAL := 0.15
## 二段跳：首次起跳后至少等待的最短滞空时间（避免刚离地就误触）、
## 以及超过该滞空时间仍未到最高点时的兜底触发
const DOUBLE_JUMP_MIN_AIRTIME := 0.16
const DOUBLE_JUMP_MAX_AIRTIME := 0.9

var enabled := false

var _target := Vector3.ZERO
var _target_reason := ""
var _retarget_timer := 0.0
var _choice_seen := false
var _choice_seen_time := 0.0
var _choice_delay_target := CHOICE_DELAY
var _choice_text_len := 0.0
var _dehydrate_seen := false
var _dehydrate_seen_time := 0.0
var _dehydrate_delay := 1.5
var _intro_elapsed := 0.0
var _intro_pending_until := 0.0
var _overlay_delay := 0.0
var _talk_cooldown := 0.0
var _talk_requesting := false
var _jump_request := 0.0
var _jump_attempts := 0
var _double_jump_timer := 0.0
var _double_jump_armed := false
## 二段跳触发时朝目标方向的水平冲量方向（角色控制器读取一次后清除）
var _air_dash_dir := Vector3.ZERO
## 实时避障后的实际移动方向（每 STEER_UPDATE_INTERVAL 重新采样）
var _steer_dir := Vector3.ZERO
var _steer_timer := 0.0
## 贴墙绕行方向：0=直线畅通；1=沿墙左侧；-1=沿墙右侧
var _contour_side := 0
var _hop_chain := 0
var _hop_cooldown := 0.0
var _stuck_time := 0.0
var _moving_time := 0.0
var _detour := Vector3.ZERO
var _detour_side := 1.0
var _look_around_time := 0.0
var _look_around_pan_speed := 0.0
var _talk_focus_target = null
var _talk_focus_until := 0
## 边走边聊：踱步对象、方向与偶发回望调度
var _pace_active := false
var _pace_partner = null
var _pace_angle := 0.0
var _pace_waypoint := Vector3.ZERO
var _pace_sign := 1.0
var _pace_flip_until := 0
var _pace_until := 0
## 撤离卡住检测：对方站在台阶/坡上时，先跳一下越过坎再走开
var _escape_since := 0
var _escape_jumped := false
var _glance_target = null
var _glance_until := 0
var _glance_next := 0
var _speed_phase_until := 0.0
var _sprint_phase := true
var _last_era_index := -999
var _era_farmed := 0
var _last_treasure_count := -1

const SLOW_TICK_INTERVAL := 0.2
var _slow_tick_accum := 0.0

func _process(delta: float) -> void:
	_talk_cooldown = maxf(0.0, _talk_cooldown - delta)
	if not enabled:
		return
	if GameState == null or not GameState.is_story_mode():
		# 自由模拟没有“三体游戏”的探索/攻略目标，自动模式自动退出
		set_enabled(false)
		return
	var sm := StoryModeManager
	if sm == null or not sm.is_story_active():
		_clear_target()
		return
	# 决策/UI 类降到 5Hz（传累积 delta，计时精度不变）；移动/跳跃类保持每帧保手感
	_slow_tick_accum += delta
	if _slow_tick_accum >= SLOW_TICK_INTERVAL:
		_tick_choices(_slow_tick_accum)
		_tick_dehydrate(_slow_tick_accum)
		_tick_intro(_slow_tick_accum)
		_tick_overlay(_slow_tick_accum)
		_tick_talk()
		_slow_tick_accum = 0.0
	_tick_pacing(delta)
	_tick_double_jump(delta)
	_tick_stuck(delta)
	_tick_agility(delta)
	_tick_pathfind(delta)
	_tick_speed_phase(delta)
	if _look_around_time > 0.0:
		# 到达关键节点：停步环顾四周；期间出现抉择/脱水则立刻打断
		if sm.auto_choice_pending() or sm.auto_dehydrate_pending():
			_look_around_time = 0.0
		else:
			_tick_look_around(delta)
			_clear_target()
			return
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		_update_target()

func set_enabled(on: bool, silent := false) -> void:
	if enabled == on:
		if not silent:
			_sync_ui()
		return
	enabled = on
	# 游戏内开关与开局设置保持一致，结局返回主菜单后重开仍保持该模式
	if ConfigManager != null:
		ConfigManager.save_game_settings({"auto_pilot_enabled": on})
	if enabled:
		_stop_pacing()
		_clear_target()
		_last_era_index = StoryModeManager.era_index if StoryModeManager != null else -999
		_era_farmed = 0
		_last_treasure_count = -1
		_detour = Vector3.ZERO
		_stuck_time = 0.0
		_jump_attempts = 0
		_moving_time = 0.0
		_detour_side = 1.0
		_jump_request = 0.0
		_double_jump_timer = 0.0
		_double_jump_armed = false
		_air_dash_dir = Vector3.ZERO
		_steer_dir = Vector3.ZERO
		_steer_timer = 0.0
		_contour_side = 0
		_hop_chain = 0
		_hop_cooldown = 0.0
		_look_around_time = 0.0
		_talk_focus_target = null
		if not silent and UIManager != null:
			UIManager.append_system_message("⚡ 自动模式开启：自动探索、攻略角色、最优抉择；酷热时默认拒绝脱水加速通关。")
	else:
		_stop_pacing()
		_clear_target()
		_jump_request = 0.0
		_double_jump_timer = 0.0
		_double_jump_armed = false
		_air_dash_dir = Vector3.ZERO
		_steer_dir = Vector3.ZERO
		_steer_timer = 0.0
		_contour_side = 0
		_look_around_time = 0.0
		_hop_chain = 0
		_talk_focus_target = null
		if not silent and UIManager != null:
			UIManager.append_system_message("⚡ 自动模式关闭，操控已交还。")
	_sync_ui()

## 供角色控制器读取：返回当前应移动的水平方向（已做实时避障），
## 无目标/被锁定时返回零向量
func move_direction(character) -> Vector3:
	if not enabled or _target_reason == "":
		return Vector3.ZERO
	if character == null or not is_instance_valid(character):
		return Vector3.ZERO
	if GameState != null and GameState.input_locked:
		return Vector3.ZERO
	var sm := StoryModeManager
	if sm == null or sm.dehydrated:
		return Vector3.ZERO
	var to: Vector3 = _target - character.global_position
	to.y = 0.0
	if to.length_squared() < 0.64:
		return Vector3.ZERO
	# 实时寻路：优先走避开障碍的采样方向；尚未采样时退化为直指目标
	if _steer_dir.length_squared() > 0.01:
		return _steer_dir.normalized()
	return to.normalized()

## 是否请求跳跃（被障碍物卡住时由角色控制器触发）
func wants_jump() -> bool:
	return enabled and _jump_request > 0.0

## 跳跃已触发：清除请求；首次起跳后武装二段跳，由 _tick_double_jump
## 在上升最高点附近触发第二跳（并带出水平冲刺）
func consume_jump() -> void:
	_jump_request = 0.0
	if not _double_jump_armed:
		_double_jump_armed = true
		_double_jump_timer = 0.0

## 二段跳的水平冲量方向：角色控制器触发二段跳时读取一次并清除
func air_dash_direction() -> Vector3:
	var d := _air_dash_dir
	_air_dash_dir = Vector3.ZERO
	return d

## 是否冲刺：目标远时冲刺、近时步行；中途会随机切换走路/跑步，更接近真人
func wants_sprint(player) -> bool:
	if not enabled or _target_reason == "" or _pace_active:
		return false
	if player == null or not is_instance_valid(player):
		return false
	var d := Vector2(
		_target.x - player.global_position.x,
		_target.z - player.global_position.z
	).length()
	if d > 20.0:
		return true
	if d < 5.0:
		return false
	return _sprint_phase

## 对话时的视线焦点：剧情选项看说话者，自动搭话期间看搭话对象
func focus_point() -> Vector3:
	if not enabled:
		return Vector3.ZERO
	var sm := StoryModeManager
	if sm == null:
		return Vector3.ZERO
	var speaker = sm.auto_focus_character()
	if speaker != null and is_instance_valid(speaker):
		return speaker.global_position + Vector3(0, 1.4, 0)
	if _talk_focus_target != null and is_instance_valid(_talk_focus_target) \
			and Time.get_ticks_msec() < _talk_focus_until:
		return _talk_focus_target.global_position + Vector3(0, 1.4, 0)
	return Vector3.ZERO

## 当前是否处于「边走边聊」踱步状态
func pacing_active() -> bool:
	return _pace_active

## 踱步时是否处于“太近需撤出”状态（此时应全速撤离而非缓步）
func pacing_escape(character) -> bool:
	if not _pace_active or _pace_partner == null or not is_instance_valid(_pace_partner) \
			or character == null or not is_instance_valid(character):
		return false
	var to_partner: Vector3 = _pace_partner.global_position - character.global_position
	to_partner.y = 0.0
	return to_partner.length() < PACE_SAFE_MIN_DIST

## 边走边聊的移动方向：走向绕对话对象的踱步点（3.8m 半径），
## 走到后换下一个点继续绕行；太近时直接向外撤出，避免贴脸打转
func pace_direction(character) -> Vector3:
	if not _pace_active or _pace_partner == null or not is_instance_valid(_pace_partner) \
			or character == null or not is_instance_valid(character) \
			or (GameState != null and GameState.input_locked):
		return Vector3.ZERO
	var to_partner: Vector3 = _pace_partner.global_position - character.global_position
	to_partner.y = 0.0
	var dist := to_partner.length()
	# 太近：先直接向外撤出（不混入切向），保证能脱离对方碰撞体
	if dist < PACE_SAFE_MIN_DIST:
		if _escape_since == 0:
			_escape_since = Time.get_ticks_msec()
		elif not _escape_jumped and Time.get_ticks_msec() - _escape_since > 450 \
				and character.is_on_floor():
			# 撤离约半秒仍被台阶/地形挡住：小跳越坎（配合二段跳可翻越）
			_jump_request = 0.4
			_escape_jumped = true
		if dist < 0.3:
			return Vector3.ZERO
		return -to_partner.normalized()
	_escape_since = 0
	_escape_jumped = false
	var to_wp: Vector3 = _pace_waypoint - character.global_position
	to_wp.y = 0.0
	var dist_wp := to_wp.length()
	if dist_wp < 0.9:
		# 到达踱步点：换下一个点，保持连续移动
		_pick_next_waypoint()
		to_wp = _pace_waypoint - character.global_position
		to_wp.y = 0.0
		dist_wp = to_wp.length()
	if dist_wp < 0.3:
		return Vector3.ZERO
	return to_wp.normalized()

## 换下一个踱步点：绕对方转一段弧线，偶尔反向
func _pick_next_waypoint() -> void:
	var now := Time.get_ticks_msec()
	if now >= _pace_flip_until:
		_pace_sign = -_pace_sign
		_pace_flip_until = now + int(randf_range(PACE_FLIP_MIN_SECONDS, PACE_FLIP_MAX_SECONDS) * 1000.0)
	_pace_angle += _pace_sign * randf_range(PACE_STEP_MIN_ANGLE, PACE_STEP_MAX_ANGLE)
	_update_pace_waypoint()

func _update_pace_waypoint() -> void:
	if _pace_partner == null or not is_instance_valid(_pace_partner):
		return
	# 踱步点与对方保持同一高度（绕行平面），避免布点落在高坡/悬崖上导致走不过去
	var pos: Vector3 = _pace_partner.global_position + Vector3(cos(_pace_angle), 0.0, sin(_pace_angle)) * PACE_RADIUS
	_pace_waypoint = WorldManager.clamp_point(pos, 0.0)
	_pace_waypoint.y = _pace_partner.global_position.y

## 边走边聊期间的偶发回望：返回对话对象位置（零向量表示当前不需要回望）
func glance_point() -> Vector3:
	if not enabled or not _pace_active:
		return Vector3.ZERO
	if _glance_target != null and is_instance_valid(_glance_target) \
			and Time.get_ticks_msec() < _glance_until:
		return _glance_target.global_position + Vector3(0, 1.4, 0)
	return Vector3.ZERO

## 搭话开始：绕对话对象踱步一段时间，并调度偶发回望
func _start_pacing(partner) -> void:
	_pace_active = true
	_pace_partner = partner
	_pace_sign = 1.0 if randi() % 2 == 0 else -1.0
	# 从玩家当前绕对方的方位开始沿圆周布点，路径不穿过对方
	_pace_angle = _angle_around(partner)
	_pace_flip_until = Time.get_ticks_msec() + int(randf_range(PACE_FLIP_MIN_SECONDS, PACE_FLIP_MAX_SECONDS) * 1000.0)
	_pace_until = Time.get_ticks_msec() + int(randf_range(PACE_MIN_SECONDS, PACE_MAX_SECONDS) * 1000.0)
	_glance_next = Time.get_ticks_msec() + int(randf_range(GLANCE_FIRST_MIN, GLANCE_FIRST_MAX) * 1000.0)
	_glance_until = 0
	_glance_target = partner
	if partner != null and is_instance_valid(partner):
		_update_pace_waypoint()
		_set_target(partner.global_position, "边走边聊")

## 玩家当前绕对话对象的方位角（弧度）：从该角度向前布点，
## 玩家沿圆周弧线移动，不会穿过对话对象所在的位置
func _angle_around(partner) -> float:
	var player = StoryModeManager.player
	if player != null and is_instance_valid(player):
		var off: Vector3 = player.global_position - partner.global_position
		off.y = 0.0
		if off.length_squared() > 0.01:
			return atan2(off.z, off.x)
	return randf_range(0.0, TAU)

## 边走边聊状态机：对话结束/被打断时停止踱步；按节奏调度偶发回望
func _tick_pacing(_delta: float) -> void:
	if not _pace_active:
		return
	var sm := StoryModeManager
	if _pace_partner == null or not is_instance_valid(_pace_partner) \
			or sm == null or sm.auto_busy() or sm.auto_choice_pending() \
			or sm.auto_dehydrate_pending() or sm.dehydrated \
			or Time.get_ticks_msec() >= _pace_until:
		_stop_pacing()
		return
	var now := Time.get_ticks_msec()
	if now >= _glance_next:
		_glance_until = now + GLANCE_DURATION_MS
		_glance_target = _pace_partner
		_glance_next = now + int(randf_range(GLANCE_EVERY_MIN, GLANCE_EVERY_MAX) * 1000.0)

func _stop_pacing() -> void:
	_pace_active = false
	_pace_partner = null
	_pace_waypoint = Vector3.ZERO
	_escape_since = 0
	_escape_jumped = false
	_glance_target = null
	_glance_until = 0
	_glance_next = 0
	_talk_focus_target = null
	_talk_focus_until = 0
	_clear_target()

## 到达关键节点：停步并环顾四周（缓慢转动视线，像真人打量环境）
func _start_look_around() -> void:
	_look_around_time = randf_range(1.6, 2.8)
	var total_deg := randf_range(90.0, 170.0) * (1.0 if randi() % 2 == 0 else -1.0)
	_look_around_pan_speed = deg_to_rad(total_deg) / _look_around_time

func _tick_look_around(delta: float) -> void:
	_look_around_time -= delta
	if _look_around_time <= 0.0:
		_look_around_time = 0.0
		return
	var cam = PlayerGodController.possession_cam
	if cam != null and is_instance_valid(cam):
		cam.yaw += _look_around_pan_speed * delta

## HUD 状态文字：当前在做什么 + 自动得分
func status_text() -> String:
	if not enabled:
		return ""
	var parts := score_parts()
	var score := int(parts["progress"] * 100.0 + parts["truth"] + parts["affinity"])
	var reason := _target_reason if _target_reason != "" else "待机"
	var sm := StoryModeManager
	if sm != null:
		if sm.dehydrated:
			reason = "脱水沉眠，等待恒纪元复水"
		elif sm.auto_dehydrate_pending():
			reason = "酷热袭来，抉择脱水…"
		elif sm.auto_choice_pending():
			reason = "正在听对方把话说完…" if not _dialogue_finished() else "正在权衡最优抉择…"
		elif sm.auto_overlay_pending():
			reason = "等待结算…"
		elif _talk_requesting:
			reason = "正在构思搭话…"
	return "⚡ 自动 · %s · 得分 %d（进度%d 真相%d 好感%d）" % [
		reason,
		score,
		int(parts["progress"] * 100.0),
		int(parts["truth"]),
		int(parts["affinity"])
	]

## 自动得分构成：文明进度（0~100）+ 真相（0~100）+ 在场角色好感总和（0~200）
func score_parts() -> Dictionary:
	var parts := {"progress": 0.0, "truth": 0.0, "affinity": 0.0}
	var sm := StoryModeManager
	if sm == null:
		return parts
	parts["progress"] = sm.progress
	parts["truth"] = sm.truth
	if sm.player != null and is_instance_valid(sm.player) and sm.player.character_data != null:
		for ch in [sm.figure, sm.companion]:
			if ch != null and is_instance_valid(ch) and ch.character_data != null:
				parts["affinity"] += RelationshipSystem.get_relationship(
					ch, sm.player.character_data.id
				).affinity
	return parts

## 抉择：出现选项后稍等（让台词说完一小段）再按得分公式选最优
func _tick_choices(delta: float) -> void:
	var sm := StoryModeManager
	if not sm.auto_choice_pending():
		_choice_seen = false
		_choice_seen_time = 0.0
		_choice_text_len = 0.0
		return
	if not _choice_seen:
		_choice_seen = true
		_choice_seen_time = 0.0
		# 先听/读完对白再选：按文字长度估算阅读时长 + 像真人一样略作停顿
		_choice_text_len = float(sm.auto_current_choice_text().length())
		var chars_per_sec := maxf(4.5 * sm.story_pace, 1.0)
		var read_time := maxf(0.0, _choice_text_len / chars_per_sec)
		_choice_delay_target = read_time + randf_range(0.8, 1.8)
	_choice_seen_time += delta
	# 对话还没说完（语音在合成/排队/播放）就一直等，绝不打断台词
	if not _dialogue_finished():
		return
	if _choice_seen_time >= _choice_delay_target:
		_choice_seen = false
		_choice_text_len = 0.0
		sm.auto_choose_best()

## 当前对白是否已播完：TTS 未启用/离线时按阅读时长估算，启用时以语音队列为准
func _dialogue_finished() -> bool:
	if TTSManager == null or not TTSManager.enabled:
		return true
	return not TTSManager.is_voice_busy()

## 酷热乱纪元脱水抉择：默认拒绝脱水、顶着酷热赶路（尽快通关）；
## 仅当毁灭进度逼近临界时才脱水避险，避免前功尽弃
func _tick_dehydrate(delta: float) -> void:
	var sm := StoryModeManager
	if not sm.auto_dehydrate_pending():
		_dehydrate_seen = false
		_dehydrate_seen_time = 0.0
		return
	if not _dehydrate_seen:
		_dehydrate_seen = true
		_dehydrate_seen_time = 0.0
		_dehydrate_delay = randf_range(1.2, 2.2)
	_dehydrate_seen_time += delta
	if _dehydrate_seen_time >= _dehydrate_delay:
		_dehydrate_seen = false
		var refuse: bool = sm.doom_progress < REFUSE_DEHYDRATE_MAX_DOOM
		# auto_choose_dehydrate 的参数是「是否脱水」：拒绝脱水时传 false
		sm.auto_choose_dehydrate(not refuse)
		if UIManager != null:
			if refuse:
				UIManager.append_system_message("🔥 自动模式拒绝脱水：顶着酷热赶路，尽快完成文明任务。")
			else:
				UIManager.append_system_message("💧 毁灭进度逼近临界，自动模式脱水避险保文明。")

## 二段跳：首次起跳后记录滞空时间，在垂直速度归零（上升最高点）附近补第二跳，
## 并记录朝目标方向的水平冲量，让二段跳同时完成“爬高 + 向指定方向持续位移”。
## 若长时间未到最高点（异常滞空）则兜底触发，避免永远不跳。
func _tick_double_jump(delta: float) -> void:
	var sm := StoryModeManager
	var player = sm.player if sm != null else null
	if player == null or not is_instance_valid(player):
		_double_jump_armed = false
		_double_jump_timer = 0.0
		return
	if player.is_on_floor():
		# 落地即解除武装，下一次起跳重新计数
		_double_jump_armed = false
		_double_jump_timer = 0.0
		return
	if not _double_jump_armed or _jump_request > 0.0:
		return
	_double_jump_timer += delta
	var vy: float = player.velocity.y
	# 垂直速度由升转降/接近零即为最高点；加最短滞空门槛避免刚离地就误触
	var at_apex: bool = vy <= 0.5
	if (_double_jump_timer >= DOUBLE_JUMP_MIN_AIRTIME and at_apex) \
			or _double_jump_timer >= DOUBLE_JUMP_MAX_AIRTIME:
		_double_jump_armed = false
		_air_dash_dir = _dash_direction(player)
		_jump_request = 0.35

## 二段跳的水平冲刺方向：优先用实时避障算出的移动方向，否则直指目标
func _dash_direction(player) -> Vector3:
	if _target_reason == "" or player == null or not is_instance_valid(player):
		return Vector3.ZERO
	if _steer_dir.length_squared() > 0.01:
		return _steer_dir.normalized()
	var to: Vector3 = _target - player.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return Vector3.ZERO
	return to.normalized()

## 实时局部寻路：周期性重新采样前进方向，避开前方障碍（建筑/岩壁/水面/高坎），
## 被困时沿可通行方向绕行而不是原地撞墙
func _tick_pathfind(delta: float) -> void:
	var sm := StoryModeManager
	var player = sm.player if sm != null else null
	if player == null or not is_instance_valid(player) or _target_reason == "" \
			or sm == null or sm.dehydrated:
		return
	_steer_timer -= delta
	if _steer_timer > 0.0:
		return
	_steer_timer = STEER_UPDATE_INTERVAL
	_steer_dir = _plan_direction(player)

func _plan_direction(player) -> Vector3:
	var to_target: Vector3 = _target - player.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.64:
		_contour_side = 0
		return Vector3.ZERO
	var base := to_target.normalized()
	var terrain_rid := _find_terrain_rid()
	# 直线在视距内畅通：正常直行并退出绕行状态
	if not _ray_blocked(player, base, PATH_LOOKAHEAD, terrain_rid) \
			and not _probe_blocked(player, base, PATH_PROBE_FAR, terrain_rid):
		_contour_side = 0
		return base
	# 直线被挡：进入/保持贴墙绕行，选择更空旷的一侧沿墙走
	if _contour_side == 0:
		_contour_side = _pick_contour_side(player, base, terrain_rid)
	var tangent: Vector3 = Vector3(-base.z, 0.0, base.x) * _contour_side
	# 沿墙方向很快被挡说明撞到墙角：换另一侧
	if _ray_blocked(player, tangent.normalized(), PATH_PROBE_NEAR, terrain_rid):
		_contour_side = -_contour_side
		tangent = -tangent
	# 两侧都走不通（口袋/死角）：退回全向采样找逃生方向
	if _ray_blocked(player, tangent.normalized(), PATH_PROBE_NEAR, terrain_rid):
		return _plan_direction_sampled(player, base, terrain_rid)
	# 贴墙走 + 轻微偏向目标，避免越绕越远
	return (tangent.normalized() + base * CONTOUR_BLEND).normalized()

## 首次遇阻时选择更空旷的一侧绕行（两侧都通则随机，避免对称摇摆）
func _pick_contour_side(player, base: Vector3, terrain_rid: RID) -> int:
	var left: Vector3 = Vector3(-base.z, 0.0, base.x)
	var right: Vector3 = -left
	var left_clear := not _ray_blocked(player, left.normalized(), PATH_PROBE_FAR, terrain_rid)
	var right_clear := not _ray_blocked(player, right.normalized(), PATH_PROBE_FAR, terrain_rid)
	if left_clear and not right_clear:
		return 1
	if right_clear and not left_clear:
		return -1
	return 1 if randi() % 2 == 0 else -1

## 全向采样兜底：直线与贴墙方向都走不通时，找所有方向上得分最高的逃生方向
func _plan_direction_sampled(player, base: Vector3, terrain_rid: RID) -> Vector3:
	var heading := Vector2(player.velocity.x, player.velocity.z)
	var best_dir := base
	var best_score := -INF
	for i in PATH_SAMPLE_COUNT:
		var ang := float(i) / float(PATH_SAMPLE_COUNT) * TAU
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var progress: float = dir.dot(base)
		var near_blocked := _probe_blocked(player, dir, PATH_PROBE_NEAR, terrain_rid)
		var far_blocked := _probe_blocked(player, dir, PATH_PROBE_FAR, terrain_rid)
		# 长距离探测只查实体障碍（建筑/岩壁），不查地形高差，提前绕开远处的墙
		var long_blocked := _ray_blocked(player, dir, PATH_PROBE_LONG, terrain_rid)
		var walkable := not near_blocked and not far_blocked and not long_blocked
		var score := progress * 3.0
		if walkable:
			score += 1.0
			# 与当前速度方向一致更顺滑，转弯不僵硬
			if heading.length_squared() > 0.25:
				score += maxf(0.0, heading.normalized().dot(Vector2(dir.x, dir.z))) * 0.4
		else:
			# 近处被挡扣重分（立即要撞上），远处被挡扣轻分
			score -= 1.8 if near_blocked else (0.9 if far_blocked else 0.45)
		# 轻微随机抖动：避免两侧对称时来回摇摆
		score += randf_range(-0.12, 0.12)
		if score > best_score:
			best_score = score
			best_dir = dir
	return best_dir

## 探测某个方向上 dist 米内是否被障碍挡住：腰线与胸口两档水平射线
## （排除角色自身与地形碰撞体，陡坡交由高度差判断，避免坡面误报）+ 地形高度/水域检查
func _probe_blocked(player, dir: Vector3, dist: float, terrain_rid: RID) -> bool:
	if _ray_blocked(player, dir, dist, terrain_rid):
		return true
	if WorldManager == null or WorldManager.terrain_gen == null:
		return false
	var base: Vector3 = player.global_position - Vector3(0, 1.0, 0)
	var ground: float = WorldManager.get_terrain_height(base.x, base.z)
	var ahead: float = WorldManager.get_terrain_height(
		base.x + dir.x * dist,
		base.z + dir.z * dist
	)
	# 前方地面比脚下高太多（悬崖/高墙）视为不可走；水域不可走
	if ahead - ground > PATH_MAX_STEP:
		return true
	if WorldManager.terrain_gen.is_water(base.x + dir.x * dist, base.z + dir.z * dist):
		return true
	return false

## 仅实体射线探测（不含地形高差/水域），用于更远距离的提前避障
func _ray_blocked(player, dir: Vector3, dist: float, terrain_rid: RID) -> bool:
	if player == null or not is_instance_valid(player):
		return true
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	# 角色原点在胶囊中心（约离地 0.95m），先降到脚底附近再起测
	var base: Vector3 = player.global_position - Vector3(0, 1.0, 0)
	for height in [0.6, 1.5]:
		var from: Vector3 = base + Vector3(0, height, 0)
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * dist)
		query.exclude = [player.get_rid()]
		if terrain_rid.is_valid():
			query.exclude.append(terrain_rid)
		if not space.intersect_ray(query).is_empty():
			return true
	return false

## 查找地形碰撞体（StaticBody3D）的 RID，供探测射线排除，避免坡面误报
func _find_terrain_rid() -> RID:
	if WorldManager == null or WorldManager.world == null \
			or not WorldManager.world.has_node("Terrain"):
		return RID()
	var stack: Array = [WorldManager.world.get_node("Terrain")]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is StaticBody3D:
			return n.get_rid()
		for c in n.get_children():
			stack.append(c)
	return RID()

## 卡住检测：障碍物前跳一下；仍卡住则绕路，像真人一样翻越/迂回
func _tick_stuck(delta: float) -> void:
	if _jump_request > 0.0:
		_jump_request -= delta
	var sm := StoryModeManager
	var player = sm.player if sm != null else null
	if sm == null or not sm.is_story_active() or sm.dehydrated:
		_stuck_time = 0.0
		_moving_time = 0.0
		return
	if player == null or not is_instance_valid(player) or _target_reason == "":
		_stuck_time = 0.0
		_moving_time = 0.0
		return
	if sm.auto_choice_pending() or sm.auto_dehydrate_pending():
		# 抉择/脱水期间不移动、不跳跃、不环顾
		_stuck_time = 0.0
		_moving_time = 0.0
		return
	if _pace_active:
		# 边走边聊：不判断卡住、不跳跃，踱步方向由踱步逻辑保证
		_stuck_time = 0.0
		_moving_time = 0.0
		return
	if _hop_chain > 0:
		# 连跳进行中：卡住检测让位给连跳逻辑
		_stuck_time = 0.0
		_moving_time = 0.0
		return
	# 落地后解除二段跳武装，等下次卡住再重新武装
	if player.is_on_floor():
		_double_jump_armed = false
		_double_jump_timer = 0.0
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	var d := Vector2(
		_target.x - player.global_position.x,
		_target.z - player.global_position.z
	).length()
	if d < 1.2:
		# 到达关键节点：停步环顾四周（人性化），随后继续
		if hspeed < 0.8 and _look_around_time <= 0.0 and _target_reason != "绕开障碍":
			_start_look_around()
		_stuck_time = 0.0
		_moving_time = 0.0
		return
	# 只在落地时做“卡住”判断：起跳后的上升阶段水平速度还没起来，
	# 若误判为卡住会提前抢跳，打乱二段跳在最高点触发的时机
	if hspeed < 0.7 and player.is_on_floor():
		_stuck_time += delta
		_moving_time = 0.0
		# 可爬高的障碍（低墙/台阶）用跳+二段跳翻越；明显爬不过的高墙直接绕路
		if _stuck_time > 0.45 and _jump_request <= 0.0 \
				and _jump_attempts < 2 and _can_climb_ahead(player):
			_jump_request = 0.4
			_jump_attempts += 1
		if _stuck_time > 2.0 and _detour == Vector3.ZERO:
			_detour = _detour_point(player, _target)
			_detour_side *= -1.0
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0
		_jump_attempts = 0
		_moving_time += delta
		# 已经恢复移动（比如跳过了障碍）：放弃旧绕路点，回归正常目标
		if _moving_time > 1.0 and _detour != Vector3.ZERO:
			_detour = Vector3.ZERO

## 前方障碍是否可以跳+二段跳爬越：从约 2.25m 高度向前射线探测，
## 胸口以上仍有阻挡说明高于二段跳能力（约 3.2m），直接绕路而不是白跳
func _can_climb_ahead(player) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	# 沿实时避障选出的移动方向探测（尚未采样时直指目标）
	var dir := _steer_dir
	if dir.length_squared() < 0.01:
		var to: Vector3 = _target - player.global_position
		to.y = 0.0
		if to.length_squared() < 0.01:
			return false
		dir = to.normalized()
	dir = dir.normalized()
	var eye: Vector3 = player.global_position + Vector3(0, 2.25, 0)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, eye + dir * 2.2)
	query.exclude = [player.get_rid()]
	return space.intersect_ray(query).is_empty()

## 绕路点：朝目标斜前方偏移，避开挡路的障碍
func _detour_point(player, target: Vector3) -> Vector3:
	var to: Vector3 = target - player.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		to = Vector3(1, 0, 0)
	var dir := to.normalized()
	var perp := Vector3(-dir.z, 0.0, dir.x) * _detour_side
	return WorldManager.clamp_point(
		player.global_position + dir * 5.0 + perp * 7.0,
		0.95
	)

## 灵动连跳：开阔平地上偶尔来一串「跳+二段跳」连续跳跃，落地即接下一跳；
## 遇到前方有墙或临近目标/抉择时不跳，保证只在合适的时候跳
func _tick_agility(delta: float) -> void:
	_hop_cooldown = maxf(0.0, _hop_cooldown - delta)
	var sm := StoryModeManager
	if sm == null or not sm.is_story_active():
		_hop_chain = 0
		return
	var player = sm.player
	if player == null or not is_instance_valid(player) or sm.dehydrated \
			or _target_reason == "" or sm.auto_choice_pending() or sm.auto_dehydrate_pending():
		_hop_chain = 0
		return
	if _pace_active:
		# 边走边聊：不连跳，保持平稳踱步
		_hop_chain = 0
		return
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	var d := Vector2(
		_target.x - player.global_position.x,
		_target.z - player.global_position.z
	).length()
	if player.is_on_floor():
		# 落地即解除二段跳武装，下一跳起跳时重新武装
		_double_jump_armed = false
		_double_jump_timer = 0.0
	if _hop_chain > 0:
		if d < 4.0 or player.is_on_wall():
			# 快到目标或撞墙：结束连跳
			_hop_chain = 0
			_hop_cooldown = randf_range(4.0, 9.0)
			return
		if player.is_on_floor() and _jump_request <= 0.0:
			# 落地瞬间接下一跳，保持连跳节奏
			_jump_request = 0.35
			_hop_chain -= 1
			if _hop_chain <= 0:
				_hop_cooldown = randf_range(4.0, 9.0)
		return
	if _hop_cooldown <= 0.0:
		if hspeed >= 2.5 and d > 10.0 and player.is_on_floor() \
				and not player.is_on_wall() and _can_climb_ahead(player) \
				and randf() < 0.45:
			_hop_chain = randi_range(2, 4)
			_hop_cooldown = 99999.0
			_jump_request = 0.35
			_hop_chain -= 1
		else:
			_hop_cooldown = randf_range(3.0, 7.0)

## 步伐节奏：几秒一换，目标远/危机时偏冲刺，其余时候随机走路/跑步
func _tick_speed_phase(delta: float) -> void:
	if _speed_phase_until <= 0.0:
		var sm := StoryModeManager
		var urgent := sm != null and (sm.doom_progress >= 0.4 or sm.progress < 0.75)
		_sprint_phase = urgent or randf() < 0.6
		_speed_phase_until = randf_range(2.5, 6.0)
	else:
		_speed_phase_until -= delta

## 纪元引言：等旁白把背景念完（按文本长度估算），再自动点「开始剧情」
func _tick_intro(delta: float) -> void:
	var sm := StoryModeManager
	if not sm.auto_intro_pending():
		_intro_pending_until = 0.0
		_intro_elapsed = 0.0
		return
	if _intro_pending_until <= 0.0:
		var text_len := 0.0
		if sm.story_ui != null and sm.story_ui.intro_text != null:
			text_len = float(str(sm.story_ui.intro_text.text).length())
		var chars_per_sec := maxf(4.5 * sm.story_pace, 1.0)
		_intro_pending_until = maxf(3.0, text_len / chars_per_sec) + 0.8
		_intro_elapsed = 0.0
	_intro_elapsed += delta
	if _intro_elapsed >= _intro_pending_until:
		_intro_pending_until = 0.0
		sm.auto_skip_intro()

## 文明完成/世界毁灭/结局覆盖层：稍等片刻自动继续（轮回或进入下一纪）
func _tick_overlay(delta: float) -> void:
	var sm := StoryModeManager
	if not sm.auto_overlay_pending():
		_overlay_delay = 0.0
		return
	_overlay_delay += delta
	if _overlay_delay >= OVERLAY_DELAY:
		_overlay_delay = 0.0
		sm.auto_continue_overlay()

## 攻略：在场角色距离够近且好感未满时，定期搭话刷好感
func _tick_talk() -> void:
	if _talk_cooldown > 0.0 or _talk_requesting:
		return
	var sm := StoryModeManager
	var player = sm.player
	if player == null or not is_instance_valid(player) or player.character_data == null:
		return
	if sm.auto_choice_pending() or sm.auto_dehydrate_pending() or sm.dehydrated:
		return
	var partner = sm.auto_favor_partner(player, TALK_RADIUS)
	if partner == null:
		return
	_talk_cooldown = TALK_COOLDOWN
	# 边走边聊：搭话后绕对方缓步踱步，不站桩
	_start_pacing(partner)
	# 搭话期间视线跟随对方
	_talk_focus_target = partner
	_talk_focus_until = Time.get_ticks_msec() + 4500
	# 搭话内容也由 AI 生成：系统提示词贴合三体世界观，离线时用三体风兜底台词
	if ConfigManager != null and ConfigManager.llm_enabled() and LLMService != null \
			and LLMService.is_available():
		_talk_requesting = true
		var state := sm.auto_event_state({"cause": "auto_talk"})
		state["player_name"] = GameState.player_name if GameState.player_name.strip_edges() != "" else "旅人"
		var prompt := PromptBuilder.build_auto_talk_prompt(state, partner.character_data.name)
		LLMService.request_dialogue("auto_talk", prompt, func(result: Dictionary) -> void:
			_talk_requesting = false
			if player == null or not is_instance_valid(player) or partner == null \
					or not is_instance_valid(partner):
				return
			var line := str(result.get("dialogue", ""))
			if line.strip_edges() == "":
				line = _canned_line(partner)
			_deliver_auto_talk(player, partner, line)
		)
	else:
		_deliver_auto_talk(player, partner, _canned_line(partner))

func _deliver_auto_talk(player, partner, line: String) -> void:
	if player == null or not is_instance_valid(player) or partner == null \
			or not is_instance_valid(partner):
		return
	if PlayerGodController != null and PlayerGodController.interaction != null:
		PlayerGodController.interaction.send_player_dialogue(player, partner, line)
	if UIManager != null:
		UIManager.append_system_message("💬 自动搭话：%s" % line)

func _canned_line(partner) -> String:
	var pool := [
		"你见过最长的恒纪元有多久？我总觉得太阳的秘密就藏在那里。",
		"如果乱纪元再来，你会先脱水，还是先听我把话说完？",
		"我在想，文明刻进石碑之前，也许该先刻进彼此的眼睛里。",
		"太阳虽然疯狂，但和你说话的时候，世界好像稳定了一瞬。",
		"等这一纪结束，我想和你一起看看真正的星空。",
		"脱水并不可怕——可怕的是醒来时，忘记了你这样的人。"
	]
	var affinity := 0.0
	var sm := StoryModeManager
	if partner != null and partner.character_data != null and sm.player != null \
			and is_instance_valid(sm.player) and sm.player.character_data != null:
		affinity = RelationshipSystem.get_relationship(
			partner, sm.player.character_data.id
		).affinity
	if affinity > 50.0:
		pool = [
			"有你在这条路上，恒纪元似乎真的长了一些。",
			"文明也许终会毁灭，但我会先记住你。",
			"等太阳安定下来，我要带你去看我算出的那颗星。"
		]
	return str(pool[randi() % pool.size()])

func _update_target() -> void:
	var sm := StoryModeManager
	if sm == null or not sm.is_story_active() or sm.finished or sm.task_complete:
		_clear_target()
		return
	# 纪元切换：重置本纪寻宝计数
	if sm.era_index != _last_era_index:
		_last_era_index = sm.era_index
		_era_farmed = 0
		_last_treasure_count = -1
		_detour = Vector3.ZERO
		_stuck_time = 0.0
		_jump_request = 0.0
		_double_jump_timer = 0.0
		_double_jump_armed = false
		_air_dash_dir = Vector3.ZERO
		_steer_dir = Vector3.ZERO
		_steer_timer = 0.0
		_contour_side = 0
		_hop_chain = 0
		_hop_cooldown = 0.0
	var player = sm.player
	if player == null or not is_instance_valid(player) or sm.dehydrated:
		_clear_target()
		return
	if _pace_active:
		# 边走边聊期间目标始终是踱步：绕对话对象保持距离
		if _pace_partner != null and is_instance_valid(_pace_partner):
			_set_target(_pace_partner.global_position, "边走边聊")
		return
	if sm.auto_busy() or sm.auto_choice_pending() or sm.auto_dehydrate_pending() \
			or sm.auto_overlay_pending():
		_clear_target()
		return
	# 卡住绕路优先：走到绕路点后再回到正常目标
	if _detour != Vector3.ZERO:
		var dd := Vector2(
			_detour.x - player.global_position.x,
			_detour.z - player.global_position.z
		).length()
		if dd < 2.0:
			_detour = Vector3.ZERO
		else:
			_set_target(_detour, "绕开障碍")
			return
	# 记录本纪寻得的遗宝数（遗宝被拾取后场上数量减少）
	var tcount := sm.auto_treasure_count()
	if _last_treasure_count >= 0 and tcount < _last_treasure_count:
		_era_farmed += 1
	_last_treasure_count = tcount
	# 1) 当前目标灯塔：最后一个灯塔前先把进度刷到 75%，确保真相碎片到手
	if sm.auto_objective_active():
		if sm.auto_is_last_objective() and _should_farm(sm) and sm.doom_progress < 0.55:
			var t := sm.auto_best_treasure_pos(player)
			if t != Vector3.ZERO:
				_set_target(t, "寻遗宝提升进度至75%（当前%d%%）" % int(sm.progress * 100.0))
				return
		var pos := sm.auto_objective_position()
		if pos != Vector3.ZERO:
			_set_target(pos, "前往目标：%s" % sm.auto_objective_label())
			return
	# 2) 场上遗宝（探索 + 进度/真相/好感）
	var treasure := sm.auto_best_treasure_pos(player)
	if treasure != Vector3.ZERO:
		_set_target(treasure, "探索遗宝（场上%d件）" % sm.auto_treasure_count())
		return
	# 3) 过客：相遇有进度/真相奖励
	var wpos := sm.auto_wanderer_position()
	if wpos != Vector3.ZERO:
		_set_target(wpos, "与过客相遇")
		return
	# 4) 接近历史人物/同伴刷好感
	var fpos := sm.auto_favor_target_pos(player)
	if fpos != Vector3.ZERO:
		_set_target(fpos, "接近%s增进好感" % sm.auto_favor_target_name(player))
		return
	# 5) 无事可做：自由探索世界
	var explore := WorldManager.random_point_near(player.global_position, 36.0)
	_set_target(explore, "自由探索世界")

func _should_farm(sm) -> bool:
	var need_progress: bool = sm.progress < FARM_TARGET_PROGRESS
	var want_truth: bool = sm.truth < FARM_TRUTH_TARGET and _era_farmed < MAX_FARM_PER_ERA
	return need_progress or want_truth

func _set_target(pos: Vector3, reason: String) -> void:
	_target = pos
	_target_reason = reason

func _clear_target() -> void:
	_target_reason = ""
	_steer_dir = Vector3.ZERO
	_steer_timer = 0.0
	_air_dash_dir = Vector3.ZERO
	_contour_side = 0

func _sync_ui() -> void:
	if StoryModeManager != null and StoryModeManager.story_ui != null \
			and is_instance_valid(StoryModeManager.story_ui):
		StoryModeManager.story_ui.refresh_auto_ui()
