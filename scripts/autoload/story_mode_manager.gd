extends Node
## 剧情模式管理器：三体游戏（深度还原小说设定与底层通关逻辑）。
##
## 通关逻辑：
##   - 每个文明纪元的“任务”不是终点——关键在于收集【真相碎片】。
##   - 玩家自动化身历史人物（周文王/墨子/冯·诺伊曼/牛顿/爱因斯坦），
##     通过对话抉择 + 三维目标节点（抵达灯塔）推进纪元任务；
##   - 纪元任务完成且文明进度达标，才能获得该纪元的真相碎片；
##   - 五个碎片集齐（真相 100%），最终“墓碑”抉择才会揭示真结局：
##     三日凌空之后，石碑坐标指向真实的三体世界——舰队启航。
##   - 失败与代价：天灾、拒绝脱水、持续的高温与严寒都会累积「文明毁灭进度」，
##     恒纪元里它逐日消退；进度满格、或三日凌空当场降临，则世界毁灭
##     并丢失该纪元真相碎片，真相不足时无法通关。
##
## 沉浸机制：
##   - V 装具载入（纪元切换的神经同步画面）；
##   - 恒纪元/乱纪元（酷热/严寒）轮转，酷热时触发【脱水抉择】；
##   - 脱水后酷热天灾失效，恒纪元浸泡复水；
##   - 三日天空、天灾闪光、目标灯塔与逐字叙事。

enum EraKind { STABLE, CHAOS_HOT, CHAOS_COLD, DESTROYED }

const ERA_KIND_NAMES := {
	EraKind.STABLE: "恒纪元",
	EraKind.CHAOS_HOT: "乱纪元 · 酷热",
	EraKind.CHAOS_COLD: "乱纪元 · 严寒",
	EraKind.DESTROYED: "毁灭纪元"
}

const STORY_DATA_PATH := "res://resources/data/three_body_story.json"

const TRUTH_PER_CLUE := 20.0
const TRUE_ENDING_MIN_TRUTH := 80.0
const NORMAL_ENDING_MIN_TRUTH := 40.0
const OBJECTIVE_REACH_DISTANCE := 3.5
const OBJECTIVE_PROGRESS_GAIN := 0.08
const COMPANION_KEEP_DISTANCE := 3.2
const COMPANION_FOLLOW_DISTANCE := 5.5
## 天象驱动纪元：某势态累计出现这么久（秒，短暂打断不清零）就翻转
const SKY_FLIP_ACCUM := 8.0
## 每个纪元至少持续这么久（秒）才允许被天象打断，避免刚开场就翻来覆去
const MIN_ERA_WALL_TIME := 20.0
## 开放剧情（AI 导演）参数
const TREASURE_REACH_DISTANCE := 3.2
const TREASURE_COUNT := 3
const TREASURE_RESPAWN_TIME := 40.0
const TREASURE_PROGRESS_GAIN := 0.06
const TREASURE_TRUTH_GAIN := 2.0
const TREASURE_AFFINITY_GAIN := 5.0
const AI_EVENT_MIN_INTERVAL := 50.0
const AI_EVENT_MAX_INTERVAL := 110.0
const TREASURE_ARTIFACTS := ["青铜日晷", "机械星盘", "脱水陶罐", "甲骨历法", "青铜齿轮", "星象刻石", "永恒火种", "浑天仪残片"]
## 场景触发角色：同伴由场景条件（靠近地标/寻宝/经历事件/天象骤变）触发登场
const COMPANION_ENTRANCE_DISTANCE := 22.0
const COMPANION_JOIN_DISTANCE := 3.5
const COMPANION_ENTRANCE_EVENTS := 3
const COMPANION_ENTRANCE_TIMEOUT := 14.0
## 临时“过客”角色：寻宝/乱纪元/里程碑时的随机遭遇
const WANDERER_COOLDOWN := 75.0

const ENDING_MONUMENT_TRUE := "三日凌空吞没了世界。但你在石碑的最后一划里，看到了宇宙的另一端：真实的坐标、真实的恒星，还有一支正在启航的舰队。\n\n你摘下 V 装具——三体游戏通关了。你明白：那支舰队，正驶向地球。"
const ENDING_MONUMENT_NORMAL := "石碑立起，文明的知识得以留存。但真相依然朦胧——你看见了混沌，却还没有看透混沌背后的世界。\n\n三体游戏未完。也许下一轮轮回，你能走得更远。"
const ENDING_MONUMENT_PARTIAL := "石碑立起，却刻得仓促凌乱。文明消逝了，而你没有真正理解它。\n\n三体游戏失败——重来一次，去收集每一段真相吧。"
const ENDING_ESCAPE := "引力深井比想象中更深。飞船坠入熔岩，文明没有留下任何知识。\n\n你摘下 V 装具，重新戴好——再来一次？"
const ENDING_COLLAPSE := "文明在执念中化为灰烬。没有石碑，没有知识，只有太阳的余晖。\n\n你摘下 V 装具，重新戴好——再来一次？"

var active := false
var finished := false
var story_data: Dictionary = {}
var eras: Array = []
var current_era: Dictionary = {}
var era_index := -1
var current_beat_id := ""
var progress := 0.5
var task_complete := false
var era_kind := EraKind.STABLE
var era_hours_left := 0.0
var danger_hours_left := 0.0
var destroyed_count := 0

var truth := 0.0
var clues: Array[String] = []
var objective_active := false
var objective_complete := false
var objective_index := 0
var objective_points: Array = []
var beacons: Array = []
var dehydrated := false
var dehydrate_pending := false
var booting := false
var boot_duration := 2.0
var cinematic_duration := 4.6
var transition_duration := 3.6
## 各类过场的最短时长：毁灭/酷热/严寒/恒纪元/文明入场各有差异
var destroy_cutscene_duration := 9.0
var hot_cutscene_duration := 7.0
var cold_cutscene_duration := 7.0
var stable_cutscene_duration := 5.5
var era_cutscene_duration := 5.0
var wake_duration := 2.6
var journey_leg_duration := 1.6
var arrival_duration := 2.4
## 剧情综合速度（逐字文字 + 语音流式速率）
var story_pace := 1.0
## 场景/结局旁白自动推进（普通对白不再依赖“继续”按钮）
var auto_advance_enabled := true
## 过场演出总开关：测试（headless 冒烟）可关闭，保证帧时序确定
var cinematic_enabled := true

var player = null
var figure = null
var companion = null
var sky = null
var story_ui = null
var cinematic_director = null
var disaster_fx: DisasterFX = null
var narrator_voice := ""
var _story_voices: Array[String] = []
## 排片表：提前为剧情角色安排形象（VRM 模型）与声音（TTS 声线）。
## 键："player" 表示玩家化身；"{纪元id}/figure" 与 "{纪元id}/companion" 表示该纪元的历史人物/同伴。
## 值：{"model": "res://...vrm", "voice": "声线id"}，留空表示自动分配。
var casting: Dictionary = {}

const CASTING_ROLE_PLAYER := "player"
const CASTING_ROLE_FIGURE := "figure"
const CASTING_ROLE_COMPANION := "companion"
const CASTING_ROLE_NARRATOR := "narrator"

const CASTING_ROLE_NAMES := {
	CASTING_ROLE_PLAYER: "玩家化身",
	CASTING_ROLE_FIGURE: "历史人物",
	CASTING_ROLE_COMPANION: "同伴",
	CASTING_ROLE_NARRATOR: "旁白"
}

var _world: Node3D = null
var _story_root: Node3D = null
var _tour_cam: Camera3D = null
var _player_spawn_pos := Vector3.ZERO
var _pending_next_id := ""
var _pending_end_beat: Dictionary = {}
var _pending_action := ""
var _ui_wired := false
var _needs_begin := false
var _current_beat_type := ""
var _cinematic_kind := ""
var _dehydrate_waiting := false
var _pending_destroy_reason := ""
var _pending_destroy_overlay := false
var _choreography_active := false
var _intro_active := false
var _wake_active := false
var _journey_active := false
var _pending_intro_beat := ""
var _intro_played := false
var _last_conjunction := ""
var _last_conj_warn_ms := 0
var _hot_accum := 0.0
var _cold_accum := 0.0
var _stable_accum := 0.0
var _era_wall_time := 0.0
## 文明毁灭进度（0~1）：天灾/拒绝脱水/持续的高温与严寒都会累积，
## 恒纪元里逐日消退；满格即文明倾覆。速率逐日随机，叠加「灾难日/喘息日」，不可预测。
var doom_progress := 0.0
var _doom_day_accum := 0.0
var _chaos_days_total := 0
var _doom_hot_days := 0
var _doom_cold_days := 0
## 已播报过的毁灭阶段（50%/75%/90%），避免重复警告
var _doom_warned_stage := 0
## 开放剧情：完全由 AI 生成台词与随机事件，辅以寻宝奖励与好感度
var open_story := true
var _ai_beat_active := false
var _ai_request_pending := false
var _ai_beat: Dictionary = {}
var _ai_event_then: Callable = Callable()
var _ai_event_cooldown := 99999.0
var _reaction_playing := false
var _treasures: Array[Dictionary] = []
var _treasures_found := 0
var _artifacts: Array[String] = []
var _treasure_respawn_timer := 0.0
var _last_favor_text := ""
var _companion_entrance_pending := false
var _companion_walking_in := false
var _companion_entrance_timer := 0.0
var _resolved_ai_events := 0
var _wanderer = null
var _wanderer_phase := ""
var _wanderer_reason := ""
var _wanderer_timer := 0.0
var _wanderer_cooldown := 0.0
var _pending_wanderer_reason := ""
var _auto_generation := 0
var _sentence_generation := 0

func _ready() -> void:
	_load_story_data()
	# 读入用户级排片表，作为本局默认安排（存档内的排片在 load_from 时覆盖）
	casting = ConfigManager.story_casting() if ConfigManager != null else {}
	if EventBus != null:
		EventBus.tts_provider_changed.connect(_on_tts_provider_changed)

func _on_tts_provider_changed(_provider: String) -> void:
	## 切换语音提供方后，清空已分配的旁白/剧情角色声线，下次按新提供方重新分配
	narrator_voice = ""
	_story_voices.clear()
	for c in CharacterManager.all_characters():
		if c != null and is_instance_valid(c) and "voice_name" in c:
			c.set("voice_name", "")
	# 排片中的声线随提供方切换而失效：保留形象排片，声音恢复自动分配
	for key in casting:
		if casting[key] is Dictionary:
			casting[key]["voice"] = ""
	_persist_casting()

func _load_story_data() -> void:
	var file := FileAccess.open(STORY_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取三体游戏数据：%s" % STORY_DATA_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and parsed.get("eras") is Array:
		story_data = parsed
		eras = story_data.get("eras", [])
	else:
		push_error("三体游戏数据格式错误")

func is_story_active() -> bool:
	return active

# ---------- 启动与接入 ----------

func _entry_era_index() -> int:
	## 起始文明：按设置中指定的纪元 id 进入；未指定或“random”时随机进入。
	if eras.is_empty():
		return 0
	var want := str(ConfigManager.game_setting("story_start_era", "random"))
	if want != "random" and want != "":
		for i in eras.size():
			if str(eras[i].get("id", "")) == want:
				return i
	return randi() % eras.size()

func start_story(world_node: Node3D) -> void:
	active = true
	finished = false
	_world = world_node
	_intro_played = false
	CivilizationManager.initialize_factions()
	WorldManager.world = world_node
	WorldManager.weather = world_node.weather
	# begin_next_era() 会先自增，这里预置为起始纪元的前一位
	era_index = _entry_era_index() - 1
	var first_era: Dictionary = eras[era_index + 1] if not eras.is_empty() else {}
	WorldManager.world_seed = int(first_era.get("seed", int(ConfigManager.game_setting("story_world_seed", 7))))
	WorldManager.generate_terrain()
	WorldManager.spawn_era_world(first_era)
	_place_era_landmarks(first_era)
	WorldManager.initialized = true
	if world_node.has_node("DirectionalLight"):
		world_node.get_node("DirectionalLight").visible = false
	if WorldManager.weather != null:
		WorldManager.weather.set_process(false)
	_spawn_story_world(first_era)
	_needs_begin = true

func after_ui_ready() -> void:
	if not active:
		return
	story_ui = UIManager.story_ui
	_wire_ui()
	if _needs_begin:
		_needs_begin = false
		begin_next_era()

func _wire_ui() -> void:
	if _ui_wired or story_ui == null:
		return
	_ui_wired = true
	story_ui.choice_pressed.connect(_on_choice)
	story_ui.continue_pressed.connect(_on_continue)
	story_ui.overlay_pressed.connect(_on_overlay)
	story_ui.boot_finished.connect(_on_boot_finished)
	story_ui.cinematic_finished.connect(_on_cinematic_finished)
	story_ui.dehydrate_chosen.connect(_on_dehydrate_chosen)
	story_ui.intro_finished.connect(_on_intro_finished)
	story_ui.wake_finished.connect(_on_wake_finished)

# ---------- 纪元生命周期 ----------

func begin_next_era() -> void:
	era_index += 1
	if era_index >= eras.size():
		_finish_failure("文明再无来者。三体游戏终止。")
		return
	begin_era(eras[era_index])

func begin_era(era: Dictionary) -> void:
	current_era = era
	era_kind = EraKind.STABLE
	doom_progress = 0.0
	_doom_day_accum = 0.0
	_chaos_days_total = 0
	_doom_hot_days = 0
	_doom_cold_days = 0
	_doom_warned_stage = 0
	_intro_active = false
	_pending_intro_beat = ""
	_wake_active = false
	_journey_active = false
	_last_conjunction = ""
	_hot_accum = 0.0
	_cold_accum = 0.0
	_stable_accum = 0.0
	_era_wall_time = 0.0
	_ai_beat_active = false
	_ai_request_pending = false
	_ai_beat = {}
	_ai_event_then = Callable()
	_ai_event_cooldown = 99999.0
	_companion_entrance_pending = false
	_companion_walking_in = false
	_companion_entrance_timer = 0.0
	_resolved_ai_events = 0
	_wanderer = null
	_wanderer_phase = ""
	_wanderer_reason = ""
	_wanderer_timer = 0.0
	_wanderer_cooldown = 0.0
	_treasures.clear()
	_treasure_respawn_timer = TREASURE_RESPAWN_TIME
	_last_favor_text = ""
	progress = clampf(float(era.get("start_progress", 0.5)), 0.0, 1.0)
	task_complete = false
	current_beat_id = str(era.get("start_beat", ""))
	era_hours_left = 24.0 * randf_range(0.5, 1.5)
	danger_hours_left = float(era.get("danger_interval_hours", 8.0))
	dehydrated = false
	dehydrate_pending = false
	PlayerGodController.set_movement_lock(false)
	objective_active = false
	objective_complete = false
	objective_index = 0
	objective_points = (era.get("objective", {}) as Dictionary).get("points", [])
	_spawn_era_characters()
	_spawn_objective_beacons(0)
	if sky != null:
		sky.apply_era("stable")
		sky.apply_era_style(str(era.get("id", "")), era.get("palette", {}))
	if story_ui != null:
		story_ui.setup_era(era, destroyed_count, truth, clues)
		story_ui.set_progress(progress)
		story_ui.set_truth(truth, clues)
		story_ui.set_doom_progress(doom_progress)
		story_ui.apply_era_theme(_era_accent_color())
	_apply_era_audio()
	PlayerGodController.exit_possession()
	_log_era_start()
	_pending_intro_beat = current_beat_id
	_start_boot()

func _era_accent_color() -> Color:
	## 纪元主题色：取调色板地平线色作为 HUD/过场强调色（古文明 × 科技）
	var palette: Dictionary = current_era.get("palette", {})
	var arr = palette.get("horizon", [])
	if arr is Array and (arr as Array).size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return Color(0.9, 0.62, 0.3)

func _apply_era_audio() -> void:
	## 每纪氛围音：神秘走廊无人机打底，机械纪元叠加专属机械声
	if AudioManager == null:
		return
	AudioManager.stop_all_loops()
	AudioManager.start_loop("drone", -26.0)
	match str(current_era.get("id", "")):
		"era_mozi":
			AudioManager.start_loop("tick", -20.0)
		"era_newton":
			AudioManager.start_loop("hover", -22.0)
		"era_qinshihuang":
			AudioManager.start_loop("tank", -24.0)

func _log_era_start() -> void:
	var figure_id := str(player.character_data.id) if player != null else ""
	var setting := _with_player_name(str(current_era.get("setting", "")))
	HistoryManager.log_event(
		"story",
		"%s开始" % str(current_era.get("name", "")),
		setting,
		figure_id
	)

## 纪元引言：背景介绍独立成幕，讲完（点「开始剧情」）再正式进入角色剧情
func _show_era_intro() -> void:
	if story_ui == null:
		_on_intro_finished()
		return
	_intro_active = true
	GameState.input_locked = true
	# 睁眼前：巡览相机周游世界与场景中的非玩家角色，玩家不可移动视线
	_start_intro_tour()
	if story_ui != null:
		story_ui.set_hud_visible(false)
	UIManager.set_cutscene_ui_active(true)
	var title := str(current_era.get("name", ""))
	var text := ""
	if not _intro_played:
		# 本轮首次进入的文明（含随机/指定起始）播放 V 装具开场引言
		_intro_played = true
		text = _with_player_name(str(story_data.get("intro", ""))) + "\n\n"
	text += _with_player_name(str(current_era.get("setting", "")))
	story_ui.show_era_intro(title, "")
	# 引言正文逐句显示 + 逐句语音，音画同步
	_play_voiced_sentences(text, func(s: String) -> void:
		if story_ui != null:
			story_ui.set_intro_sentence(s)
	, Callable())

## 睁眼苏醒：第一人称从黑场淡入，睁眼即见与剧情相应的向导
func _show_wake() -> void:
	if story_ui == null:
		_start_first_beat()
		return
	_wake_active = true
	GameState.input_locked = true
	# 睁开眼：此刻才加载玩家化身并接管视角，巡览相机让位
	if player == null or not is_instance_valid(player):
		_spawn_player_for_wake()
	_stop_intro_tour()
	if story_ui != null:
		story_ui.set_hud_visible(false)
		story_ui.set_trance(0.85)
	UIManager.set_cutscene_ui_active(true)
	_position_guide_for_wake()
	story_ui.show_wake()
	var wake_line := _with_player_name(str(current_era.get("wake_line", "你醒了，{player}。这个世界在等你。")))
	if figure != null and is_instance_valid(figure):
		figure.speak(wake_line, true, true)

func _on_wake_finished() -> void:
	if not _wake_active:
		return
	_wake_active = false
	GameState.input_locked = false
	if story_ui != null:
		story_ui.hide_wake()
		story_ui.set_hud_visible(true)
		story_ui.set_trance(0.0)
	UIManager.set_cutscene_ui_active(false)
	# 苏醒语说完再进入引言，语音不重叠
	await _wait_for_voice_clear()
	if not active:
		return
	_start_first_beat()

## 外部系统音：背景讲完后、苏醒前，以穿越网文式口吻宣告降临
func _play_arrival_line() -> void:
	if story_ui == null:
		_show_wake()
		return
	if AudioManager != null:
		AudioManager.play("teleporter", -8.0)
	var line := _with_player_name(str(current_era.get("arrival_line", "意识接入完成。现在，睁开眼吧。")))
	if line != "":
		story_ui.show_external_voice(line)
		_speak_narration(line)
	story_ui.set_trance(0.5)
	GameState.input_locked = true
	if story_ui != null:
		story_ui.set_hud_visible(false)
	UIManager.set_cutscene_ui_active(true)
	await get_tree().create_timer(maxf(arrival_duration, 0.1)).timeout
	if not active:
		return
	# 外部系统音说完再苏醒，语音不重叠
	await _wait_for_voice_clear()
	if not active:
		return
	if story_ui != null:
		story_ui.hide_external_voice()
	_show_wake()

func _start_first_beat() -> void:
	var beat_id := _pending_intro_beat
	_pending_intro_beat = ""
	if open_story:
		# 开放剧情：不再进入固定剧本，改由 AI 导演随机生成事件
		_start_open_story()
		return
	if beat_id != "":
		_show_beat(beat_id)

## 苏醒时把向导放到玩家正前方：第一人称睁眼正对剧情相关人物
func _position_guide_for_wake() -> void:
	if player == null or not is_instance_valid(player) or figure == null or not is_instance_valid(figure):
		return
	var yaw: float = player.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var spot := WorldManager.clamp_point(player.global_position + fwd * 2.4, 0.95)
	figure.global_position = spot
	figure.moving = false
	figure.velocity = Vector3.ZERO
	figure.current_action = {}
	figure.face_towards(player.global_position)
	player.face_towards(figure.global_position)
	# 化身相机拥有独立的 yaw，只转角色身体不会带动视线；这里把镜头也转向向导，
	# 保证第一人称睁眼时画面正对剧情人物。
	var cam := PlayerGodController.possession_cam
	if cam != null and is_instance_valid(cam):
		cam.face_towards(figure.global_position)

func _spawn_player_for_wake() -> void:
	## 睁眼瞬间才加载玩家化身：不出现在开场巡览动画中，附身后由黑场淡入接管视角。
	player = _spawn_story_character("story_player", {}, _player_spawn_pos, true)
	if player != null and is_instance_valid(player):
		PlayerGodController.possess(player)
		PlayerGodController.possession_cam.set_first_person(true)
		PlayerGodController.possession_cam.make_current()

func _start_intro_tour() -> void:
	## 睁眼前的巡览动画：动态漫游全图，随机聚焦角色/建筑，玩家不可控。
	if _story_root == null or not is_instance_valid(_story_root):
		return
	if _tour_cam == null or not is_instance_valid(_tour_cam):
		_tour_cam = IntroTourCamera.new()
		_tour_cam.name = "IntroTourCamera"
		_story_root.add_child(_tour_cam)
	_tour_cam.set_focus_points(_build_intro_focus_points())
	_tour_cam.make_current()
	GameState.camera = _tour_cam

func _stop_intro_tour() -> void:
	if _tour_cam != null and is_instance_valid(_tour_cam):
		_tour_cam.queue_free()
	_tour_cam = null

func _build_intro_focus_points() -> Array:
	## 巡览要展示的焦点：向导、任务地标、营地；聚焦时镜头保持 3~5m。
	var pts: Array = []
	if figure != null and is_instance_valid(figure):
		pts.append(figure.global_position + Vector3(0, 1.0, 0))
	var obj_pts: Array = ((current_era.get("objective", {}) as Dictionary).get("points", []) as Array)
	for i in mini(3, obj_pts.size()):
		var pos_arr: Array = obj_pts[i].get("pos", [0.0, 0.0, 0.0])
		var p := Vector3(float(pos_arr[0]), 0, float(pos_arr[2]))
		pts.append(p + Vector3(0, 1.2, 0))
	pts.append(_player_spawn_pos)
	return pts

func _on_intro_finished() -> void:
	if not _intro_active:
		return
	_sentence_generation += 1
	_intro_active = false
	if story_ui != null:
		story_ui.hide_era_intro()
		story_ui.set_hud_visible(true)
	UIManager.set_cutscene_ui_active(false)
	if cinematic_enabled:
		# 背景旁白说完再播放外部系统音，语音不重叠
		await _wait_for_voice_clear()
		_play_arrival_line()
	else:
		# 关闭过场时同样保证玩家在开场后可用：立即加载化身并移交控制
		if player == null or not is_instance_valid(player):
			_spawn_player_for_wake()
		_stop_intro_tour()
		GameState.input_locked = false
		_start_first_beat()

func _start_boot() -> void:
	## 进入文明：电影式过场（象征图形 + 标题 + 引子）
	_start_cinematic(
		"era",
		str(current_era.get("name", "")),
		str(current_era.get("cinematic", "")),
		cinematic_duration
	)

func _on_boot_finished() -> void:
	booting = false

func _ensure_disaster_fx() -> void:
	if disaster_fx != null and is_instance_valid(disaster_fx):
		return
	if _story_root == null or not is_instance_valid(_story_root):
		return
	disaster_fx = DisasterFX.new()
	disaster_fx.name = "DisasterFX"
	_story_root.add_child(disaster_fx)

func _doom_center() -> Vector3:
	## 毁灭演出中心：玩家化身位置（镜头拉远时玩家在画面中，冲击最直接）
	if player != null and is_instance_valid(player):
		return player.global_position
	return Vector3.ZERO

func _start_cinematic(kind: String, title: String, subtitle: String, duration: float) -> void:
	if story_ui == null:
		return
	# 每种天象过场独立时长，让玩家有足够时间感知天地异象
	var eff_duration := maxf(duration, _cinematic_duration_for(kind))
	if AudioManager != null:
		if kind == "destroyed":
			AudioManager.play("discharge", -4.0)
		elif kind == "hot" or kind == "cold":
			AudioManager.play("whoosh", -6.0)
		elif kind == "era":
			AudioManager.play("braam", -6.0)
		else:
			AudioManager.play("whoosh", -8.0)
	if story_ui != null:
		if kind == "era":
			story_ui.set_trance(0.9)
		elif kind == "destroyed":
			story_ui.set_trance(0.45)
		elif kind == "hot" or kind == "cold":
			story_ui.set_trance(0.28)
		else:
			# 恒纪元是复苏与秩序，不做白光扭曲
			story_ui.set_trance(0.0)
	_cinematic_kind = kind
	booting = true
	story_ui.show_cinematic(kind, title, subtitle, eff_duration)
	if subtitle.strip_edges() != "":
		_speak_narration(subtitle)
	# 过场期间太阳光辉涌动，让天象与镜头同步；恒纪元只做温和晨曦
	if sky != null and is_instance_valid(sky) and kind != "era":
		sky.pulse_suns(0.4 if kind == "stable" else 1.3, eff_duration)
	if kind == "destroyed":
		_ensure_disaster_fx()
		if disaster_fx != null and is_instance_valid(disaster_fx):
			disaster_fx.play_doom(_doom_center())
	if not cinematic_enabled:
		return
	_ensure_director()
	if cinematic_director == null or not is_instance_valid(cinematic_director):
		return
	var choreo := _cutscene_choreography(kind, eff_duration)
	cinematic_director.play_cutscene(
		choreo.get("shots", []),
		choreo.get("walks", []),
		kind != "destroyed"
	)

func _cinematic_duration_for(kind: String) -> float:
	match kind:
		"destroyed":
			return destroy_cutscene_duration
		"hot":
			return hot_cutscene_duration
		"cold":
			return cold_cutscene_duration
		"stable":
			return stable_cutscene_duration
		"era":
			return era_cutscene_duration
		_:
			return 4.5

func _on_cinematic_finished() -> void:
	booting = false
	if story_ui != null:
		story_ui.set_trance(0.0)
	if cinematic_director != null and is_instance_valid(cinematic_director) and cinematic_director.active:
		if cinematic_director.is_returning():
			# 正片已完：等自回归镜头滑回转场前机位（最长约1.2秒）再继续剧情
			await _await_director_return(cinematic_director)
		else:
			# 玩家点了“跳过”：导演同步收尾，恢复控制权
			cinematic_director.cancel()
	if _cinematic_kind == "era" and _pending_intro_beat != "":
		# V装具过场结束 → 先讲背景（引言幕）→ 外部系统音 → 苏醒 → 睁眼见向导
		_show_era_intro()
		return
	if _dehydrate_waiting and era_kind == EraKind.CHAOS_HOT and not dehydrated and not task_complete:
		_dehydrate_waiting = false
		dehydrate_pending = true
		if AudioManager != null:
			AudioManager.play("raygun", -7.0)
		story_ui.show_dehydrate_choice()
	if _pending_destroy_overlay:
		_pending_destroy_overlay = false
		story_ui.show_world_destroyed(_pending_destroy_reason, "文明轮回")
		GameState.input_locked = true

func _await_director_return(director: CinematicDirector) -> void:
	## 等待导演完成自回归；若导演异常被移除（未发信号），限时兜底放行，避免剧情卡死
	var done_flag := [false]
	director.cutscene_finished.connect(func(): done_flag[0] = true, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not done_flag[0] and waited < 2.5:
		if director == null or not is_instance_valid(director) or director.is_queued_for_deletion():
			break
		await get_tree().process_frame
		waited += get_process_delta_time()

func _spawn_era_characters() -> void:
	CharacterManager.clear_all()
	_story_voices.clear()
	narrator_voice = ""
	player = null
	figure = null
	companion = null
	# 开局营地：远离各纪的标志性地标，随剧情慢慢接近
	var camp := _story_vec3(current_era.get("start_pos", []), _story_pos())
	_player_spawn_pos = camp
	# 玩家化身睁眼后才加载：避免出现在开场巡览动画里，破坏“由外入内”的沉浸感
	var fig_def: Dictionary = current_era.get("figure", {})
	figure = _spawn_story_character("story_figure", fig_def, camp + Vector3(3.4, 0, 1.0))
	# 同伴不在开局出现：由剧情节拍（beat["join"]）在旅途中加入

func _spawn_story_character(character_id: String, def: Dictionary, pos: Vector3, is_player := false):
	var data := CharacterData.new()
	data.id = character_id
	var era_id := str(current_era.get("id", "")) if not current_era.is_empty() else ""
	var cast_role := CASTING_ROLE_PLAYER if is_player else \
		(CASTING_ROLE_FIGURE if character_id == "story_figure" else CASTING_ROLE_COMPANION)
	if is_player:
		var pname := GameState.player_name
		if pname.strip_edges() == "":
			pname = "旅人"
		data.name = pname
		data.role = "visitor"
		data.speech_style = "自然"
		data.current_emotion = "awe"
		data.sex = "any"
	else:
		data.name = str(def.get("name", "无名历史人物"))
		data.role = str(def.get("role", "scholar"))
		data.speech_style = str(def.get("speech_style", "沉稳"))
		data.current_emotion = str(def.get("emotion", "awe"))
		# 三体游戏中的历史人物/同伴均为男性，优先匹配 male 模型池
		data.sex = "male"
	data.personality = Personality.from_dict({
		"openness": 0.9, "conscientiousness": 0.8, "extraversion": 0.5,
		"agreeableness": 0.6, "neuroticism": 0.3
	})
	data.personality.motivations = ["揭开三体运动的真相", "让文明延续"]
	data.faction_id = ""
	data.form = Enums.FORM_HUMANOID
	data.age = 45.0
	data.status = {"energy": 200.0, "health": 100.0, "fatigue": 0.0, "spirit": 100.0}
	# 排片优先：取排片表中该角色的形象；未安排则按性别从 VRM 池随机
	var model_path := casted_model(era_id, cast_role, data.sex)
	if model_path == "":
		model_path = "res://assets/models/characters/silicat_humanoid.gltf"
	data.appearance = {
		"model_path": model_path,
		"color": [0.35, 0.82, 0.92] if is_player else [0.72, 0.58, 0.4],
		"scale": 1.0 if is_player else 1.05
	}
	data.location = WorldManager.clamp_point(pos, 0.95)
	var char = CharacterManager.create_character(data)
	char.voice_name = casted_voice(era_id, cast_role)
	char.llm_busy = true
	char.moving = false
	char.current_action = {}
	char.character_data.status["energy"] = 200.0
	return char

func _story_voice() -> String:
	## 为历史人物/旁白分配互不重复的中文声线（服务离线时回退默认声线）
	var v := TTSManager.random_voice()
	for i in 8:
		if not _story_voices.has(v):
			break
		v = TTSManager.random_voice()
	_story_voices.append(v)
	return v

# ---------- 排片表：形象与声音的提前安排 ----------

func get_casting(era_id: String, role: String) -> Dictionary:
	## 读取某纪元某角色的排片项；未按纪元安排时回退到全局同名角色项。
	if role == CASTING_ROLE_PLAYER:
		return casting.get(CASTING_ROLE_PLAYER, {})
	var key := "%s/%s" % [era_id, role] if era_id != "" else role
	var entry = casting.get(key, casting.get(role, {}))
	return entry if entry is Dictionary else {}

func set_casting(era_id: String, role: String, model_path: String, voice: String) -> void:
	## 写入排片项；两者都为空时清除该排片项（恢复自动分配）。
	var entry := {"model": model_path, "voice": voice}
	var key := ""
	if role == CASTING_ROLE_PLAYER:
		key = CASTING_ROLE_PLAYER
	elif era_id != "":
		key = "%s/%s" % [era_id, role]
	else:
		key = role
	if model_path == "" and voice == "":
		casting.erase(key)
	else:
		casting[key] = entry
	_persist_casting()

func reset_casting(era_id: String = "", role: String = "") -> void:
	## 清空排片：不传参清空全部；传纪元清空该纪元；再传角色只清空该角色。
	if era_id == "" and role == "":
		casting.clear()
		_persist_casting()
		return
	if role != "":
		if role == CASTING_ROLE_PLAYER:
			casting.erase(CASTING_ROLE_PLAYER)
		elif era_id != "":
			casting.erase("%s/%s" % [era_id, role])
		else:
			casting.erase(role)
		_persist_casting()
		return
	for key in casting.keys():
		if str(key).begins_with(era_id + "/"):
			casting.erase(key)
	_persist_casting()

func _persist_casting() -> void:
	## 把排片表写入用户设置，保证下次开局仍保留（存档内排片以存档为准）
	if ConfigManager != null:
		ConfigManager.save_story_casting(casting)

func casted_model(era_id: String, role: String, sex: String) -> String:
	## 排片形象：已安排返回模型路径；未安排按性别随机从 VRM 池取。
	var entry := get_casting(era_id, role)
	var path := str(entry.get("model", ""))
	if path == "":
		path = CharacterManager.random_vrm_model(sex)
	return path

func casted_voice(era_id: String, role: String) -> String:
	## 排片声音：已安排返回声线；未安排随机分配互不重复的声线。
	var entry := get_casting(era_id, role)
	var v := str(entry.get("voice", ""))
	if v != "":
		if not _story_voices.has(v):
			_story_voices.append(v)
		return v
	return _story_voice()

func apply_casting_to_live_characters() -> void:
	## 把排片立即应用到当前在场的玩家/历史人物/同伴（形象与声音即时生效）。
	if not active or current_era.is_empty():
		return
	var era_id := str(current_era.get("id", ""))
	var live_roles := [
		[CASTING_ROLE_PLAYER, player],
		[CASTING_ROLE_FIGURE, figure],
		[CASTING_ROLE_COMPANION, companion]
	]
	for pair in live_roles:
		var role := str(pair[0])
		var ch = pair[1]
		if ch == null or not is_instance_valid(ch):
			continue
		var entry := get_casting(era_id, role)
		var model := str(entry.get("model", ""))
		if model != "":
			ch.set_appearance_model(model)
		var voice := str(entry.get("voice", ""))
		if voice != "":
			ch.set_voice(voice)
	# 旁白：已排片则立即切换叙事声线（未排片保持自动，下一句旁白随机分配）
	var narrator_entry := get_casting("", CASTING_ROLE_NARRATOR)
	var narrator_v := str(narrator_entry.get("voice", ""))
	if narrator_v != "":
		narrator_voice = narrator_v

func all_casting_roles() -> Array[Dictionary]:
	## 供排片面板使用：返回所有可排片条目（旁白 + 玩家 + 每纪元的历史人物/同伴）。
	var out: Array[Dictionary] = []
	out.append({
		"era_id": "",
		"role": CASTING_ROLE_NARRATOR,
		"label": CASTING_ROLE_NAMES[CASTING_ROLE_NARRATOR],
		"name": "系统旁白（纯语音，无形象）",
		"voice_only": true
	})
	out.append({
		"era_id": "",
		"role": CASTING_ROLE_PLAYER,
		"label": CASTING_ROLE_NAMES[CASTING_ROLE_PLAYER],
		"name": GameState.player_name
	})
	for era in eras:
		var eid := str(era.get("id", ""))
		var figure_def: Dictionary = era.get("figure", {})
		out.append({
			"era_id": eid,
			"role": CASTING_ROLE_FIGURE,
			"label": "%s · %s" % [str(era.get("name", "")), CASTING_ROLE_NAMES[CASTING_ROLE_FIGURE]],
			"name": str(figure_def.get("name", ""))
		})
		var companion_def: Dictionary = era.get("companion", {})
		if str(companion_def.get("name", "")) != "":
			out.append({
				"era_id": eid,
				"role": CASTING_ROLE_COMPANION,
				"label": "%s · %s" % [str(era.get("name", "")), CASTING_ROLE_NAMES[CASTING_ROLE_COMPANION]],
				"name": str(companion_def.get("name", ""))
			})
	return out

func set_story_pace(p: float) -> void:
	story_pace = clampf(p, 0.5, 2.0)
	if TTSManager != null:
		TTSManager.set_pace(story_pace)

func _story_pos() -> Vector3:
	return Vector3(-6, 0, 6)

# ---------- 目标节点（三维灯塔） ----------

func _spawn_objective_beacons(from_index := 0) -> void:
	beacons.clear()
	if sky == null:
		return
	var beacon_color := _era_beacon_color()
	for i in range(from_index, objective_points.size()):
		var pt: Dictionary = objective_points[i]
		var pos_arr: Array = pt.get("pos", [0.0, 0.0, 0.0])
		var beacon = sky.spawn_beacon(
			Vector3(float(pos_arr[0]), 0, float(pos_arr[2])),
			str(pt.get("label", "目标")),
			beacon_color
		)
		beacons.append(beacon)

## 每纪专属灯塔色：避免跨纪元复用同一视觉
func _era_beacon_color() -> Color:
	match str(current_era.get("id", "")):
		"era_wenwang":
			return Color(1.0, 0.72, 0.35)
		"era_mozi":
			return Color(0.9, 0.62, 0.25)
		"era_qinshihuang":
			return Color(1.0, 0.3, 0.22)
		"era_newton":
			return Color(0.45, 0.75, 1.0)
		"era_einstein":
			return Color(1.0, 0.85, 0.42)
		_:
			return Color(0.3, 0.9, 1.0)

func _tick_objective() -> void:
	if not active or finished or not objective_active or objective_complete:
		return
	if player == null or not is_instance_valid(player) or objective_index >= objective_points.size():
		return
	var pt: Dictionary = objective_points[objective_index]
	var pos_arr: Array = pt.get("pos", [0.0, 0.0, 0.0])
	var target := Vector3(float(pos_arr[0]), 0, float(pos_arr[2]))
	var dist: float = Vector2(
		player.global_position.x - target.x,
		player.global_position.z - target.z
	).length()
	story_ui.update_objective_distance(dist)
	story_ui.set_next_step("前往目标：%s（距离 %dm）" % [str(pt.get("label", "目标")), int(dist)], "action")
	if dist >= OBJECTIVE_REACH_DISTANCE:
		return
	# 抵达关键节点
	var label := str(pt.get("label", "目标"))
	var line := str(pt.get("line", "文明的线索又清晰一分。"))
	objective_index += 1
	progress = clampf(progress + OBJECTIVE_PROGRESS_GAIN, 0.0, 1.0)
	story_ui.set_progress(progress)
	story_ui.show_milestone("◆ 关键节点 · %s" % label, line, Color(0.55, 0.95, 1.0))
	if AudioManager != null:
		AudioManager.play("tick", -10.0)
	UIManager.append_system_message("◆ 关键节点：抵达%s（%d/%d）" % [label, objective_index, objective_points.size()])
	HistoryManager.log_event(
		"story",
		"关键节点：%s" % label,
		"你抵达了%s，文明的线索又清晰一分。" % label,
		str(player.character_data.id) if player != null else ""
	)
	# 关键地标往往有人守望：触发“过客”相遇
	_spawn_wanderer("milestone")
	if not beacons.is_empty():
		var beacon = beacons.pop_front()
		if is_instance_valid(beacon):
			beacon.queue_free()
	if objective_index >= objective_points.size():
		objective_complete = true
		objective_active = false
		story_ui.objective_done()
		if AudioManager != null:
			AudioManager.play("scifi", -7.0)
		var obj_title := str((current_era.get("objective", {}) as Dictionary).get("title", "目标完成"))
		UIManager.append_system_message("★ 关键节点完成：%s" % obj_title)
		GameState.unlock_achievement("three_body_witness")
		var gate_beat := str(current_era.get("objective_beat", ""))
		if gate_beat != "" and current_beat_id == gate_beat:
			_show_beat(gate_beat)

# ---------- 剧情推进 ----------

func _show_beat(beat_id: String) -> void:
	_sentence_generation += 1
	current_beat_id = beat_id
	_pending_end_beat = {}
	_pending_next_id = ""
	_current_beat_type = ""
	var beats: Dictionary = current_era.get("beats", {})
	var beat: Dictionary = beats.get(beat_id, {})
	if beat.is_empty():
		_complete_task(beat)
		return
	# 渐进式加入：同伴在剧情推进中登场
	if beat.has("join"):
		_handle_beat_join(beat)
	# 旅途跋涉：分程推进（每程字幕 + 队伍移动），把“怎么走过去的”讲清楚
	if beat.has("travel") and cinematic_enabled:
		_play_travel_sequence(beat, func() -> void: _show_beat_continue(beat_id, beat))
		return
	if beat.has("travel"):
		_apply_travel_final(beat)
	# 旧版单点旅行兼容
	if beat.has("travel_to"):
		_travel_party(_story_vec3(beat["travel_to"], _story_pos()))
	_show_beat_continue(beat_id, beat)

func _show_beat_continue(beat_id: String, beat: Dictionary) -> void:
	# 目标节点闸门：该节点需要先完成三维目标
	var gate := str(current_era.get("objective_beat", ""))
	if gate != "" and beat_id == gate and not objective_complete:
		var obj: Dictionary = current_era.get("objective", {})
		objective_active = true
		_current_beat_type = "objective"
		story_ui.show_objective(str(obj.get("title", "完成目标")), str(obj.get("hint", "跟随发光的灯塔前进。")))
		return
	# 节拍演出：先播镜头与角色走位，再展示剧情内容（登场聚焦也属于演出）
	if cinematic_enabled and (beat.has("shot") or beat.has("move") or beat.has("join")):
		_play_beat_choreography(beat, func() -> void: _show_beat_content(beat_id, beat))
		return
	_show_beat_content(beat_id, beat)

func _show_beat_content(beat_id: String, beat: Dictionary) -> void:
	_stage_beat(beat)
	match str(beat.get("type", "choice")):
		"scene":
			_current_beat_type = "scene"
			var narration := _with_player_name(str(beat.get("narration", "")))
			# 逐句显示 + 逐句语音同步，底部一次只显示一句
			_play_voiced_sentences(narration, func(s: String) -> void:
				if story_ui != null:
					story_ui.set_bottom_sentence(s)
			, func() -> void:
				_schedule_auto_advance(0)
			)
			_pending_next_id = str(beat.get("next", ""))
		"end":
			_current_beat_type = "end"
			var text := _with_player_name(str(beat.get("text", "")))
			var end_narration := _with_player_name(str(beat.get("narration", "")))
			if text != "" or end_narration != "":
				if text != "":
					_speak_beat(beat)
				if end_narration != "":
					_run_end_narration(end_narration)
				_pending_end_beat = beat
			else:
				_complete_task(beat)
		_:
			_current_beat_type = "choice"
			var speaker := str(beat.get("speaker", "旁白"))
			var choices: Array = beat.get("choices", [])
			var choice_texts: Array[String] = []
			for ch in choices:
				var ctext := _with_player_name(str(ch.get("text", "")))
				if bool(ch.get("risk", false)):
					ctext = "⚠ %s" % ctext
				choice_texts.append(ctext)
			story_ui.show_beat(speaker, _with_player_name(str(beat.get("text", ""))), choice_texts)
			_speak_beat(beat)

func _run_end_narration(narration: String) -> void:
	## 结局旁白：等说话者说完，再逐句显示 + 逐句语音
	await _wait_for_voice_clear()
	if not active or finished:
		return
	_play_voiced_sentences(narration, func(s: String) -> void:
		if story_ui != null:
			story_ui.set_bottom_sentence(s)
	, func() -> void:
		_schedule_auto_advance(0)
	)

## 普通台词/结局旁白：逐字显示 + 语音播完后自动推进，不依赖剧情栏按钮
func _schedule_auto_advance(text_length: int) -> void:
	if not auto_advance_enabled:
		return
	_auto_generation += 1
	var gen := _auto_generation
	var cps := maxf(4.5 * story_pace, 1.0)
	var min_wait := float(text_length) / cps + 0.8
	_run_auto_advance(gen, min_wait)

func _run_auto_advance(gen: int, min_wait: float) -> void:
	## 场景/结局自动推进：文字播完 + 语音播完才进入下一节拍，避免重叠与突兀
	var waited := 0.0
	while waited < min_wait:
		await get_tree().create_timer(0.2).timeout
		if gen != _auto_generation or not active or finished:
			return
		waited += 0.2
	await _wait_for_voice_clear()
	if gen != _auto_generation or not active or finished:
		return
	_on_continue()

func _wait_for_voice_clear(max_wait := 60.0) -> void:
	## 等待所有语音（合成/排队/播放）结束，保证语音与剧情严格同步
	if TTSManager == null or not TTSManager.enabled:
		return
	var guard := 0.0
	while TTSManager.is_voice_busy() and guard < max_wait:
		await get_tree().create_timer(0.2).timeout
		guard += 0.2

func _with_player_name(text: String) -> String:
	if text.find("{player}") == -1:
		return text
	var pname := GameState.player_name
	if pname.strip_edges() == "":
		pname = "旅人"
	return text.replace("{player}", pname)

## 节拍排布：让角色“活”起来——说话者做手势、其他角色转身面对，姿态随剧情切换
func _stage_beat(beat: Dictionary) -> void:
	_clear_beat_pose()
	var speaker := str(beat.get("speaker", ""))
	var player_speaks: bool = player != null and is_instance_valid(player) and player.character_data != null \
		and speaker == player.character_data.name
	var figure_speaks: bool = figure != null and is_instance_valid(figure) and figure.character_data != null \
		and speaker == figure.character_data.name
	var companion_speaks: bool = companion != null and is_instance_valid(companion) and companion.character_data != null \
		and speaker == companion.character_data.name
	var has_choreography := beat.has("shot") or beat.has("move")
	var anim := str(beat.get("anim", ""))
	var anim_target = companion if companion != null and is_instance_valid(companion) else figure
	for npc in [figure, companion]:
		if npc == null or not is_instance_valid(npc):
			continue
		npc.moving = false
		npc.current_action = {}
		npc.velocity = Vector3.ZERO
		var npc_speaks: bool = (npc == figure and figure_speaks) or (npc == companion and companion_speaks)
		if npc_speaks or not has_choreography:
			# 说话时面对玩家；无走位编排的普通对话也自然面向玩家
			if player != null and is_instance_valid(player):
				npc.face_towards(player.global_position)
		if anim != "" and npc == anim_target:
			npc.anim_override = anim
		elif npc_speaks:
			npc.anim_override = "talk"
		else:
			npc.anim_override = "idle"
	if player_speaks and figure != null and is_instance_valid(figure):
		figure.face_towards(player.global_position)
	if player_speaks and companion != null and is_instance_valid(companion):
		companion.face_towards(player.global_position)

func _clear_beat_pose() -> void:
	if player != null and is_instance_valid(player):
		player.anim_override = ""
	if companion != null and is_instance_valid(companion):
		companion.anim_override = ""
	if figure != null and is_instance_valid(figure):
		figure.anim_override = ""

func _play_beat_choreography(beat: Dictionary, then: Callable) -> void:
	var shot: Dictionary = beat.get("shot", {})
	var moves: Array = beat.get("move", [])
	var shots: Array = []
	if not shot.is_empty():
		shots.append(shot)
	# 重要人物登场聚焦：先给新加入的同伴一个特写镜头
	if beat.has("join") and companion != null and is_instance_valid(companion):
		shots.insert(0, {
			"from": companion.global_position + Vector3(0, 2.0, 4.5),
			"duration": 1.6,
			"fov_from": 70.0,
			"fov_to": 62.0,
			"trans": "sine",
			"ease": "in_out",
			"shake": 0.12,
			"shoulder": {"who": "companion", "side": 1.0, "distance": 3.8, "height": 1.7}
		})
	if shots.is_empty() and moves.is_empty():
		then.call()
		return
	_ensure_director()
	if cinematic_director == null or not is_instance_valid(cinematic_director):
		then.call()
		return
	var walks: Array = []
	for m in moves:
		var who := str(m.get("who", ""))
		if who != "figure" and who != "companion":
			continue
		var entry := {"who": who, "to": m.get("to", [0.0, 0.0, 0.0])}
		if m.has("face"):
			entry["face"] = m["face"]
		walks.append(entry)
	_choreography_active = true
	if story_ui != null:
		story_ui.set_hud_visible(false)
	UIManager.set_cutscene_ui_active(true)
	cinematic_director.play_beat_shot(shots, walks, _on_beat_choreography_done.bind(then))

func _handle_beat_join(beat: Dictionary) -> void:
	var join := str(beat.get("join", ""))
	if join != "companion" or (companion != null and is_instance_valid(companion)):
		return
	var comp_def: Dictionary = current_era.get("companion", {})
	if comp_def.is_empty():
		return
	var pos := _story_vec3(beat.get("join_pos", []), _story_pos() + Vector3(6.8, 0, 0.2))
	companion = _spawn_story_character("story_companion", comp_def, pos)
	if player != null and is_instance_valid(player):
		companion.face_towards(player.global_position)
	if story_ui != null:
		story_ui.show_character_entrance(str(comp_def.get("name", "同伴")))
	if AudioManager != null:
		AudioManager.play_3d("landing", companion.global_position, -4.0)
	UIManager.append_system_message("◈ %s 从远处走来，加入了你们的旅途。" % str(comp_def.get("name", "同伴")))

func _play_travel_sequence(beat: Dictionary, then: Callable) -> void:
	## 跋涉分程：每程队伍移动 + 顶部字幕，讲清楚旅途经过
	var travel: Array = beat.get("travel", [])
	if travel.is_empty():
		then.call()
		return
	_journey_active = true
	GameState.input_locked = true
	if story_ui != null:
		story_ui.set_hud_visible(false)
	UIManager.set_cutscene_ui_active(true)
	for leg in travel:
		if not active:
			return
		if not (leg is Dictionary):
			continue
		if AudioManager != null:
			AudioManager.play("teleport", -8.0)
		_travel_party(_story_vec3((leg as Dictionary).get("to", []), _story_pos()))
		var label := str((leg as Dictionary).get("label", ""))
		if label != "" and story_ui != null:
			story_ui.show_journey_step(label)
		await get_tree().create_timer(maxf(journey_leg_duration, 0.05)).timeout
	if not active:
		return
	_journey_active = false
	GameState.input_locked = false
	if story_ui != null:
		story_ui.set_hud_visible(true)
	UIManager.set_cutscene_ui_active(false)
	then.call()

func _apply_travel_final(beat: Dictionary) -> void:
	## 无演出模式（测试/高倍速）：直接跳到最后一程目的地
	var travel: Array = beat.get("travel", [])
	if travel.is_empty():
		return
	var last: Dictionary = travel[travel.size() - 1]
	_travel_party(_story_vec3(last.get("to", []), _story_pos()))

func _travel_party(pos: Vector3) -> void:
	## 旅行蒙太奇：整支队伍瞬移到远方（配合镜头完成“从旧地望向新地”的披露）
	if player == null or not is_instance_valid(player):
		return
	var clamped := WorldManager.clamp_point(pos, 0.95)
	var delta = clamped - player.global_position
	for c in [player, figure, companion]:
		if c == null or not is_instance_valid(c):
			continue
		c.global_position += delta
		c.velocity = Vector3.ZERO
		c.moving = false
		c.current_action = {}

func _story_vec3(data, fallback: Vector3) -> Vector3:
	if data is Vector3:
		return data
	if data is Array and (data as Array).size() >= 3:
		return Vector3(float(data[0]), float(data[1]), float(data[2]))
	return fallback

func _on_beat_choreography_done(then: Callable) -> void:
	_choreography_active = false
	if story_ui != null:
		story_ui.set_hud_visible(true)
	UIManager.set_cutscene_ui_active(false)
	then.call()

func _speak_beat(beat: Dictionary) -> void:
	var speaker := str(beat.get("speaker", ""))
	var text := _with_player_name(str(beat.get("text", "")))
	if text.strip_edges() == "":
		return
	if player != null and is_instance_valid(player) and player.character_data != null \
			and speaker == player.character_data.name:
		# 玩家自己不配音、不出气泡：台词以字幕呈现，避免“玩家像 AI”的观感
		if story_ui != null:
			story_ui.set_bottom_sentence(text)
		return
	if companion != null and is_instance_valid(companion) and companion.character_data != null \
			and speaker == companion.character_data.name:
		companion.speak(text, true, true)
		companion.bubble_remaining = maxf(companion.bubble_remaining, 8.0)
		return
	if figure != null and is_instance_valid(figure) and figure.character_data != null \
			and speaker == figure.character_data.name:
		figure.speak(text, true, true)
		figure.bubble_remaining = maxf(figure.bubble_remaining, 8.0)
		return
	_speak_narration(text)

func _speak_narration(text: String) -> void:
	## 旁白/画外音：使用独立叙事声线，强制可闻（V装具叙事感）
	text = _with_player_name(text)
	if text.strip_edges() == "":
		return
	if narrator_voice == "":
		narrator_voice = casted_voice("", CASTING_ROLE_NARRATOR)
	var anchor = figure if figure != null and is_instance_valid(figure) else null
	TTSManager.speak(text, narrator_voice, anchor, true, true)

## 逐句演出：整句显示 + 该句语音播完再进下一句，保证音画同步
func _play_voiced_sentences(text: String, setter: Callable, on_done: Callable) -> void:
	if text.strip_edges() == "":
		on_done.call()
		return
	var gen := _sentence_generation
	var sentences := TTSManager.split_sentences(text) if TTSManager != null else PackedStringArray([text])
	for i in sentences.size():
		if gen != _sentence_generation or not active or finished:
			return
		# 预取下一句：当前句播放时即开始合成下一句，语音连贯无停顿
		if i + 1 < sentences.size():
			_prefetch_sentence(sentences[i + 1])
		var s: String = sentences[i]
		setter.call(s)
		await _speak_sentence_synced(s)
		if gen != _sentence_generation or not active or finished:
			return
	on_done.call()

func _prefetch_sentence(text: String) -> void:
	if narrator_voice == "":
		narrator_voice = casted_voice("", CASTING_ROLE_NARRATOR)
	if TTSManager != null:
		TTSManager.prefetch(text, narrator_voice)

func _speak_sentence_synced(text: String) -> void:
	## 播一句并等待：语音注册后等它播完；离线时按阅读时长停留
	if narrator_voice == "":
		narrator_voice = casted_voice("", CASTING_ROLE_NARRATOR)
	var read_time := maxf(1.0, text.length() / maxf(4.5 * story_pace, 1.0))
	var anchor = figure if figure != null and is_instance_valid(figure) else player
	if TTSManager == null or not TTSManager.enabled or not TTSManager.server_online:
		await get_tree().create_timer(read_time).timeout
		return
	TTSManager.speak(text, narrator_voice, anchor, true, true)
	var guard := 0.0
	var max_wait := clampf(read_time + 3.0, 12.0, 20.0)
	while guard < max_wait:
		await get_tree().create_timer(0.1).timeout
		guard += 0.1
		if TTSManager.is_speaking_for(anchor):
			# 语音已开始播放：等它完整播完
			while TTSManager.is_speaking_for(anchor) and guard < max_wait:
				await get_tree().create_timer(0.1).timeout
				guard += 0.1
			return

func _on_choice(index: int) -> void:
	if not active or finished or _intro_active or _choreography_active:
		return
	if open_story and _ai_beat_active:
		_apply_ai_choice(index)
		return
	var beats: Dictionary = current_era.get("beats", {})
	var beat: Dictionary = beats.get(current_beat_id, {})
	var choices: Array = beat.get("choices", [])
	if index < 0 or index >= choices.size():
		return
	var choice: Dictionary = choices[index]
	progress = clampf(progress + float(choice.get("progress", 0.0)), 0.0, 1.0)
	story_ui.set_progress(progress)
	var reply := _with_player_name(str(choice.get("reply", "")))
	if str(choice.get("danger", "")) != "":
		_apply_danger_event(str(choice["danger"]))
	_sentence_generation += 1
	# 语音同步：等当前说话者说完 → 再播你的回应 → 说完才推进下一节拍
	await _wait_for_voice_clear()
	if not active or finished:
		return
	if reply != "" and player != null and is_instance_valid(player):
		# 玩家的回应以字幕呈现，不出气泡、不合成语音
		if story_ui != null:
			story_ui.set_bottom_sentence(reply)
	await _wait_for_voice_clear()
	if not active or finished:
		return
	var next_id := str(choice.get("next", ""))
	if next_id == "":
		_complete_task(beat)
	else:
		_show_beat(next_id)

func _on_continue() -> void:
	if not active or finished or _intro_active or _choreography_active:
		return
	_sentence_generation += 1
	await _wait_for_voice_clear()
	if not active or finished or _intro_active or _choreography_active:
		return
	if not _pending_end_beat.is_empty():
		var beat: Dictionary = _pending_end_beat
		_pending_end_beat = {}
		_complete_task(beat)
		return
	if _pending_next_id == "":
		var beats: Dictionary = current_era.get("beats", {})
		_complete_task(beats.get(current_beat_id, {}))
	else:
		_show_beat(_pending_next_id)

func _complete_task(beat: Dictionary) -> void:
	_clear_beat_pose()
	task_complete = true
	var task: Dictionary = current_era.get("task", {})
	HistoryManager.log_event(
		"story",
		"任务完成：%s" % str(task.get("title", "")),
		str(beat.get("narration", "")),
		str(player.character_data.id) if player != null else ""
	)
	GameState.unlock_achievement("three_body_witness")
	_try_collect_clue()
	var ending := str(beat.get("ending", ""))
	if ending != "":
		_handle_ending(ending, str(beat.get("narration", "")))
		return
	var completion := _open_completion_text() if open_story \
		else str(current_era.get("completion_text", "文明完成了它的使命。"))
	story_ui.show_era_complete(completion, "进入下一文明")
	_pending_action = "advance"
	GameState.input_locked = true

func _try_collect_clue() -> void:
	var clue: Dictionary = current_era.get("clue", {})
	var clue_id := str(clue.get("id", ""))
	if clue_id == "" or clues.has(clue_id):
		return
	if progress < float(current_era.get("min_clue_progress", 0.5)):
		UIManager.append_system_message("真相碎片未能收集：文明进度不足（%.0f%%），真相沉入灰烬。" % (progress * 100.0))
		return
	clues.append(clue_id)
	truth = clampf(truth + TRUTH_PER_CLUE, 0.0, 100.0)
	story_ui.set_truth(truth, clues)
	if AudioManager != null:
		AudioManager.play("powerup", -6.0)
	GameState.unlock_achievement("truth_seeker")
	story_ui.show_milestone(
		"✦ 真相碎片 +%d（%d/%d）" % [int(TRUTH_PER_CLUE), clues.size(), eras.size()],
		str(clue.get("text", "")),
		Color(0.45, 0.95, 1.0)
	)
	UIManager.append_system_message(
		"✦ 真相碎片 +%d（%d/%d）：%s" % [int(TRUTH_PER_CLUE), clues.size(), eras.size(), str(clue.get("text", ""))]
	)

func _handle_ending(ending: String, narration: String) -> void:
	_clear_beat_pose()
	finished = true
	if AudioManager != null:
		AudioManager.play("braam", -5.0)
	if story_ui != null:
		story_ui.set_trance(0.35)
	PlayerGodController.exit_possession()
	GameState.input_locked = true
	match ending:
		"monument":
			_handle_monument_ending(narration)
		"escape":
			story_ui.show_ending(false, "%s\n\n%s" % [narration, ENDING_ESCAPE], "文明轮回 · 重新开始")
			_pending_action = "rebuild"
		"collapse":
			story_ui.show_ending(false, "%s\n\n%s" % [narration, ENDING_COLLAPSE], "文明轮回 · 重新开始")
			_pending_action = "rebuild"
		_:
			story_ui.show_ending(true, narration, "返回主菜单")
			_pending_action = "menu"
	HistoryManager.log_event("story", "三体游戏结局", "%s（%s）" % [ending, narration])

func _handle_monument_ending(narration: String) -> void:
	if truth >= TRUE_ENDING_MIN_TRUTH:
		GameState.unlock_achievement("three_body")
		story_ui.show_ending(true, "%s\n\n%s" % [narration, ENDING_MONUMENT_TRUE], "返回主菜单")
		_pending_action = "menu"
	elif truth >= NORMAL_ENDING_MIN_TRUTH:
		story_ui.show_ending(false, "%s\n\n%s" % [narration, ENDING_MONUMENT_NORMAL], "返回主菜单")
		_pending_action = "menu"
	else:
		story_ui.show_ending(false, "%s\n\n%s" % [narration, ENDING_MONUMENT_PARTIAL], "文明轮回 · 重新开始")
		_pending_action = "rebuild"

func _on_overlay() -> void:
	if not active:
		return
	GameState.input_locked = false
	match _pending_action:
		"advance":
			_advance_civilization(false)
		"destroyed":
			_advance_civilization(true)
		"rebuild":
			_rebuild_world()
		"menu":
			return_to_menu()
		_:
			_advance_civilization(false)

# ---------- 文明毁灭 / 轮回 / 结局 ----------
# 灭亡规则（明确界定）：
# 1) 慢性灭亡：文明毁灭进度（红色进度条）逐日累积——天灾、拒绝脱水、持续的高温与
#    严寒都在加压（速率逐日随机，偶有「灾难日/喘息日」）；恒纪元里逐日消退。
#    进度满格，文明当场倾覆，判词会写明「乱纪元持续了多少天」。
# 2) 即时灭亡：三日凌空（三颗飞星同时当空）宣判文明死刑，当场执行——没有倒计时，
#    玩家无法预知，也无法躲避。
# 3) 完成任务：目标全部抵达并收官 → 文明延续，进入下一纪，不触发毁灭。

func _destroy_world(reason: String) -> void:
	_clear_beat_pose()
	destroyed_count += 1
	era_kind = EraKind.DESTROYED
	dehydrate_pending = false
	_dehydrate_waiting = false
	dehydrated = false
	PlayerGodController.set_movement_lock(false)
	if sky != null:
		sky.apply_era("destroyed")
	if story_ui != null:
		story_ui.hide_dehydrate_choice()
		story_ui.flash(Color(1.0, 0.95, 0.85), 0.7)
	PlayerGodController.exit_possession()
	HistoryManager.log_event("story", "世界毁灭 · 第%d次轮回" % destroyed_count, reason)
	_pending_action = "destroyed"
	_pending_destroy_reason = reason
	_pending_destroy_overlay = true
	# 先播放“三日凌空”过场，结束后再弹出毁灭覆盖层
	_start_cinematic("destroyed", "世界毁灭 · 第%d次轮回" % destroyed_count, reason, transition_duration)

func _advance_civilization(from_destruction: bool) -> void:
	var next_era: Dictionary = eras[era_index + 1] if era_index + 1 < eras.size() else {}
	story_ui.hide_overlay()
	PlayerGodController.exit_possession()
	_clear_story_world()
	WorldManager.world_seed = int(next_era.get("seed", randi()))
	WorldManager.generate_terrain()
	WorldManager.spawn_era_world(next_era)
	_place_era_landmarks(next_era)
	_spawn_story_world(next_era)
	if era_index + 1 < eras.size():
		begin_next_era()
	elif from_destruction:
		_finish_failure("最后一纪文明也未能幸免。三体游戏终止。")
	else:
		_finish_failure("文明再无来者。三体游戏终止。")

func _rebuild_world() -> void:
	## 失败结局后重开：文明轮回按设置重新选择起始文明（随机/指定），真相清零。
	story_ui.hide_overlay()
	finished = false
	era_index = _entry_era_index() - 1
	_intro_played = false
	destroyed_count = 0
	truth = 0.0
	clues.clear()
	PlayerGodController.exit_possession()
	_clear_story_world()
	var entry_era: Dictionary = eras[era_index + 1] if not eras.is_empty() else {}
	WorldManager.world_seed = int(entry_era.get("seed", randi())) if not eras.is_empty() else randi()
	WorldManager.generate_terrain()
	WorldManager.spawn_era_world(entry_era)
	_place_era_landmarks(entry_era)
	_spawn_story_world(entry_era)
	begin_next_era()

func _finish_failure(text: String) -> void:
	finished = true
	PlayerGodController.exit_possession()
	story_ui.show_ending(false, text, "文明轮回 · 重新开始")
	_pending_action = "rebuild"
	GameState.input_locked = true

func _clear_story_world() -> void:
	if AudioManager != null:
		AudioManager.stop_all_loops()
	if cinematic_director != null and is_instance_valid(cinematic_director):
		cinematic_director.queue_free()
	cinematic_director = null
	if _story_root != null and is_instance_valid(_story_root):
		_story_root.queue_free()
	_story_root = null
	sky = null
	_tour_cam = null
	disaster_fx = null
	player = null
	figure = null
	companion = null
	beacons.clear()

func _ensure_director() -> void:
	if cinematic_director != null and is_instance_valid(cinematic_director):
		return
	if _world == null:
		return
	cinematic_director = CinematicDirector.new()
	cinematic_director.name = "CinematicDirector"
	_world.add_child(cinematic_director)

## 按过场类型编排“镜头序列 + 角色走位”，让每场过场都有贴合叙事的运动：
## 节奏舒缓（sine/quad 缓动）、跟随剧情同步（镜头追着角色走位）、
## 收尾统一落在角色身后 45° 侧后机位（shoulder）。
## 差异设计：毁灭=三颗飞星同现的长镜头；酷热=缓慢抬升凝视双日；严寒=冻土升空望长夜；
## 恒纪元=柔和环绕；文明入场=高空缓降。每场都有独立的“天地异象”凝视时间。
func _cutscene_choreography(kind: String, duration: float) -> Dictionary:
	var pc: AICharacter = player
	var pos := pc.global_position if pc != null and is_instance_valid(pc) else Vector3(-6, 0, 6)
	var d := clampf(duration, 0.5, 12.0)
	var shots: Array = []
	var walks: Array = []
	match kind:
		"era":
			# 文明入场：从高空缓缓降入，周游世界与向导（玩家睁眼前不登场）
			var fig: AICharacter = figure
			var anchor_pos: Vector3 = fig.global_position if fig != null and is_instance_valid(fig) else pos
			var dest := anchor_pos + Vector3(1.2, 0, 0.5)
			shots = [
				{
					"from": anchor_pos + Vector3(0, 22.0, 40.0),
					"to": anchor_pos + Vector3(0, 14.0, 22.0),
					"look_from": anchor_pos + Vector3(0, 1.8, 0),
					"look_to": dest + Vector3(0, 1.6, 0),
					"duration": d * 0.55,
					"fov_from": 56.0,
					"fov_to": 62.0,
					"trans": "sine",
					"ease": "in_out"
				},
				{
					"duration": d * 0.45,
					"fov_from": 62.0,
					"fov_to": 64.0,
					"trans": "sine",
					"ease": "in_out",
					"shoulder": {"who": "figure", "side": 1.0, "distance": 4.8, "height": 2.0}
				}
			]
			walks = [
				{"who": "figure", "to": dest, "face": anchor_pos + Vector3(6.0, 0, 1.5), "speed": 1.4},
			]
		"stable":
			# 恒纪元：柔和的阳光，缓慢环绕半圈，强调“秩序与喘息”
			shots = [
				{
					"from": pos + Vector3(-1.5, 4.2, 8.5),
					"to": pos + Vector3(3.0, 5.0, -2.0),
					"look_from": pos + Vector3(0, 1.3, 0),
					"look_to": pos + Vector3(4.0, 1.5, -2.0),
					"duration": d * 0.55,
					"fov_from": 58.0,
					"fov_to": 62.0,
					"trans": "sine",
					"ease": "in_out"
				},
				{
					"duration": d * 0.45,
					"fov_from": 62.0,
					"fov_to": 66.0,
					"trans": "sine",
					"ease": "in_out",
					"shoulder": {"who": "player", "side": 1.0, "distance": 4.6, "height": 1.9}
				}
			]
		"hot":
			# 双日凌空/酷热：缓慢抬升凝视两颗飞星（热浪扭曲），再缓缓落回肩后
			var sun := _nearest_sun_pos()
			shots = [
				{
					"from": pos + Vector3(0, 1.8, 4.8),
					"to": pos + Vector3(0, 11.0, -1.0),
					"look_from": pos + Vector3(0, 1.2, 0),
					"look_to": sun,
					"duration": d * 0.38,
					"fov_from": 68.0,
					"fov_to": 58.0,
					"trans": "quad",
					"ease": "out",
					"shake": 0.10
				},
				{
					"from": pos + Vector3(0, 11.0, -1.0),
					"to": pos + Vector3(0, 15.0, -4.0),
					"look_from": sun,
					"look_to": sun + Vector3(30.0, 8.0, -20.0),
					"duration": d * 0.32,
					"fov_from": 58.0,
					"fov_to": 54.0,
					"trans": "sine",
					"ease": "in_out",
					"shake": 0.16
				},
				{
					"duration": d * 0.30,
					"fov_from": 62.0,
					"fov_to": 66.0,
					"trans": "sine",
					"ease": "in_out",
					"shoulder": {"who": "player", "side": 1.0, "distance": 4.4, "height": 1.8}
				}
			]
		"cold":
			# 严寒：从冻土缓缓升空，飞雪漫天、长夜漆黑，再缓缓落回肩后
			var sun := _nearest_sun_pos()
			shots = [
				{
					"from": pos + Vector3(-2.5, 0.6, 4.0),
					"to": pos + Vector3(1.0, 9.0, 1.0),
					"look_from": pos + Vector3(-2.0, 0.2, 3.0),
					"look_to": sun,
					"duration": d * 0.40,
					"fov_from": 66.0,
					"fov_to": 58.0,
					"trans": "quad",
					"ease": "in_out"
				},
				{
					"from": pos + Vector3(1.0, 9.0, 1.0),
					"to": pos + Vector3(-3.0, 12.0, -5.0),
					"look_from": sun,
					"look_to": sun + Vector3(-20.0, 10.0, 30.0),
					"duration": d * 0.30,
					"fov_from": 58.0,
					"fov_to": 56.0,
					"trans": "sine",
					"ease": "in_out"
				},
				{
					"duration": d * 0.30,
					"fov_from": 62.0,
					"fov_to": 66.0,
					"trans": "sine",
					"ease": "in_out",
					"shoulder": {"who": "player", "side": -1.0, "distance": 4.5, "height": 1.8}
				}
			]
		"destroyed":
			# 三日凌空/毁灭：缓慢拉远揭示三颗飞星同现，白热强光，最终坠落。
			# 配合 DisasterFX 的火海/飞石/连环爆闪/冲击波，镜头震动层层加码。
			var sun := _nearest_sun_pos()
			shots = [
				{
					"from": pos + Vector3(0, 2.2, 5.2),
					"to": pos + Vector3(0, 26.0, 18.0),
					"look_from": pos + Vector3(0, 1.3, 0),
					"look_to": sun,
					"duration": d * 0.36,
					"fov_from": 66.0,
					"fov_to": 54.0,
					"trans": "quad",
					"ease": "out",
					"shake": 0.35
				},
				{
					"from": pos + Vector3(0, 26.0, 18.0),
					"to": pos + Vector3(pos.x * 0.2, 40.0, pos.z + 30.0),
					"look_from": sun,
					"look_to": Vector3(0, 60.0, 0),
					"duration": d * 0.36,
					"fov_from": 54.0,
					"fov_to": 50.0,
					"trans": "sine",
					"ease": "in",
					"shake": 1.0
				},
				{
					"from": pos + Vector3(pos.x * 0.2, 40.0, pos.z + 30.0),
					"to": pos + Vector3(pos.x * 0.2, 2.0, pos.z + 34.0),
					"look_from": Vector3(0, 60.0, 0),
					"look_to": Vector3(0, 60.0, 0),
					"duration": d * 0.28,
					"fov_from": 50.0,
					"fov_to": 46.0,
					"trans": "quad",
					"ease": "in",
					"shake": 2.0
				}
			]
	return {"shots": shots, "walks": walks}

func _nearest_sun_pos() -> Vector3:
	if sky != null and is_instance_valid(sky):
		return sky.nearest_sun_position()
	return Vector3(0, 80, 0)

func _spawn_story_world(era: Dictionary = {}) -> void:
	_story_root = Node3D.new()
	_story_root.name = "ThreeBodyLayer"
	_world.add_child(_story_root)
	sky = ThreeBodySky.new()
	sky.name = "ThreeBodySky"
	_story_root.add_child(sky)
	sky.setup(_world)
	if not era.is_empty():
		sky.apply_era_style(str(era.get("id", "")), era.get("palette", {}))

func _place_era_landmarks(era: Dictionary) -> void:
	## 在任务点/剧情坐标放置主题地标，让叙事地点有实体感。
	if WorldManager.terrain_gen == null:
		return
	var pts: Array = ((era.get("objective", {}) as Dictionary).get("points", []) as Array)
	var kinds := ["monument", "obelisk", "arch", "pavement", "machine", "shaft"]
	for i in pts.size():
		var pt: Dictionary = pts[i]
		var pos_arr: Array = pt.get("pos", [0.0, 0.0, 0.0])
		var pos := Vector3(float(pos_arr[0]), 0, float(pos_arr[2]))
		var kind := str(pt.get("landmark", kinds[i % kinds.size()]))
		WorldManager.place_era_landmark(pos, kind)

func return_to_menu() -> void:
	_clear_beat_pose()
	if AudioManager != null:
		AudioManager.stop_all_loops()
	active = false
	finished = false
	era_index = -1
	destroyed_count = 0
	current_era = {}
	player = null
	disaster_fx = null
	_intro_active = false
	_wake_active = false
	_journey_active = false
	_pending_intro_beat = ""
	_choreography_active = false
	_treasures.clear()
	_treasures_found = 0
	_artifacts.clear()
	_pending_wanderer_reason = ""
	_despawn_wanderer()
	_ai_beat_active = false
	_ai_request_pending = false
	_ai_beat = {}
	_ai_event_then = Callable()
	_ai_event_cooldown = 99999.0
	GameState.input_locked = false
	PlayerGodController.exit_possession()
	if story_ui != null:
		story_ui.hide_all()
	get_tree().change_scene_to_file("res://scenes/ui/start_menu.tscn")

func reset() -> void:
	_clear_beat_pose()
	active = false
	finished = false
	era_index = -1
	destroyed_count = 0
	current_era = {}
	truth = 0.0
	clues.clear()
	_needs_begin = false
	_dehydrate_waiting = false
	_pending_destroy_overlay = false
	_pending_destroy_reason = ""
	booting = false
	_choreography_active = false
	_intro_active = false
	_wake_active = false
	_journey_active = false
	_pending_intro_beat = ""
	_treasures.clear()
	_treasures_found = 0
	_artifacts.clear()
	_pending_wanderer_reason = ""
	_despawn_wanderer()
	_ai_beat_active = false
	_ai_request_pending = false
	_ai_beat = {}
	_ai_event_then = Callable()
	_ai_event_cooldown = 99999.0
	GameState.input_locked = false
	_clear_story_world()
	PlayerGodController.exit_possession()
	if story_ui != null:
		story_ui.hide_all()

# ---------- 纪元轮转、天灾与脱水 ----------

func _process(delta: float) -> void:
	if not active or finished or current_era.is_empty():
		return
	if _intro_active or _wake_active or _journey_active:
		return  # 引言/苏醒/跋涉幕：暂停纪元计时与跟随
	_tick_era(delta)
	_tick_conjunction()
	_tick_objective()
	var directoring: bool = cinematic_director != null \
		and is_instance_valid(cinematic_director) \
		and cinematic_director.active
	if not directoring:
		# 演出期间角色由导演驱动，暂停跟随，避免互相争夺移动
		_tick_followers(delta)
	_refresh_step()
	_tick_treasures(delta)
	_tick_ai_events(delta)
	_tick_companion_entrance(delta)
	_tick_wanderer(delta)
	# 过场期间排队等待的过客：演出结束、恢复游玩后再放行登场
	if _pending_wanderer_reason != "" and not _presentation_busy():
		var pending_reason := _pending_wanderer_reason
		_pending_wanderer_reason = ""
		_spawn_wanderer(pending_reason)
	_update_favor_ui()

func _tick_era(delta: float) -> void:
	if era_kind == EraKind.DESTROYED or booting or dehydrate_pending:
		return
	var hours := TimeManager.delta_game_hours(delta)
	if hours <= 0.0:
		return
	_era_wall_time += delta
	era_hours_left -= hours
	if era_hours_left <= 0.0:
		_flip_era()
		return
	if task_complete:
		return
	# 文明毁灭进度以「天」为节拍：乱纪元逐日叠加，恒纪元逐日消退
	_doom_day_accum += hours
	while _doom_day_accum >= 24.0:
		_doom_day_accum -= 24.0
		_tick_doom_day()
		if era_kind == EraKind.DESTROYED:
			return
	# 天象驱动：纪元跟随太阳走——统计近期势态的累计时长，
	# 某势态累计够久（短暂打断不清零）就翻转纪元
	if not _choreography_active and sky != null and is_instance_valid(sky) \
			and era_kind != EraKind.DESTROYED:
		var tendency: String = sky.era_tendency()
		if sky.current_conjunction() == "triple":
			tendency = "hot"  # 三日凌空：日轨彻底失控，按酷热处理
		match tendency:
			"hot", "destroy":
				_hot_accum += delta
				_cold_accum = 0.0
				_stable_accum = 0.0
			"cold":
				_cold_accum += delta
				_hot_accum = 0.0
				_stable_accum = 0.0
			"stable":
				# 恒纪元单日不打断热/寒累计：双日凌空窗口内的短暂单日不算干扰
				_stable_accum += delta
			_:
				pass  # 普通夜晚：中性，不累积也不清零
		if _era_wall_time >= MIN_ERA_WALL_TIME:
			var desired := _era_kind_for_tendency(tendency)
			if desired == EraKind.CHAOS_HOT and era_kind != EraKind.CHAOS_HOT \
					and _hot_accum >= SKY_FLIP_ACCUM:
				_flip_era()
				return
			if desired == EraKind.CHAOS_COLD and era_kind != EraKind.CHAOS_COLD \
					and _cold_accum >= SKY_FLIP_ACCUM:
				_flip_era()
				return
			if desired == EraKind.STABLE and era_kind != EraKind.STABLE \
					and _stable_accum >= SKY_FLIP_ACCUM:
				_flip_era()
				return
	# 乱纪元周期性天灾：酷热/严寒按间隔持续加压（文案 + 毁灭进度）
	if era_kind == EraKind.CHAOS_HOT or era_kind == EraKind.CHAOS_COLD:
		danger_hours_left -= hours
		if danger_hours_left <= 0.0:
			_apply_danger()

func _tick_conjunction() -> void:
	## 天地异象铺垫：依据三体模拟的真实日位检测双日/三日凌空，给出预警与光辉脉冲
	if sky == null or not is_instance_valid(sky) or booting or era_kind == EraKind.DESTROYED:
		return
	var conj: String = sky.current_conjunction()
	if conj == _last_conjunction:
		return
	_last_conjunction = conj
	if story_ui == null:
		return
	# 混沌轨道下天象变换频繁，同类预警至少间隔 60 秒，避免刷屏；
	# 三日凌空例外：死刑宣判永远即时执行，不受节流拦截
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_conj_warn_ms < 60000 and conj != "triple":
		return
	_last_conj_warn_ms = now_ms
	if conj == "triple":
		# 三日凌空：三颗飞星同时当空——文明的死刑当场执行，没有倒计时，
		# 玩家无法预知，也无法躲避（原著：三日凌空瞬间毁灭文明）。
		sky.pulse_suns(2.2, 2.0)
		if AudioManager != null:
			AudioManager.play("braam", -5.0)
		story_ui.show_warning("三日凌空！三颗飞星同时升上天空——世界在烈焰中崩解！")
		UIManager.append_system_message("☀ 三日凌空：三颗飞星同时出现，世界当场毁灭。")
		# 宣判瞬间天雷示警：强化“天象失控”的临场感
		_ensure_disaster_fx()
		if disaster_fx != null and is_instance_valid(disaster_fx):
			disaster_fx.lightning(_doom_center())
		_destroy_world("三日凌空！三颗飞星同时当空，大地在灼热中熔化——文明当场毁灭，无人能预料，也无人能幸免。")
	elif conj == "binary":
		sky.pulse_suns(1.3, 1.4)
		if AudioManager != null:
			AudioManager.play("beam", -10.0)
		story_ui.show_warning("双日凌空：两颗飞星并肩升起，热浪正在聚集。")
		UIManager.append_system_message("☀ 双日凌空：热浪正在聚集。")
		# 双日凌空本身也是毁灭性天灾：热浪灼烧大地，累积毁灭进度（已脱水则免疫）
		if open_story and not dehydrated and not task_complete:
			story_ui.flash(Color(1.0, 0.3, 0.1), 0.18)
			UIManager.append_system_message("☀ 双日凌空：热浪灼烧大地，毁灭进度上升！")
			_add_doom(randf_range(0.018, 0.032))

func _tick_doom_day() -> void:
	## 毁灭进度的「日结」：乱纪元逐日加压（速率随机 + 灾难日/喘息日），
	## 恒纪元逐日消退；拒绝脱水与三日凌空会进一步加速。
	if era_kind == EraKind.DESTROYED or task_complete:
		return
	if era_kind == EraKind.STABLE:
		# 恒纪元：文明喘息复苏，毁灭进度逐日消退
		var heal := randf_range(0.03, 0.055)
		_add_doom(-heal)
		if doom_progress <= 0.0 and _chaos_days_total > 0:
			_chaos_days_total = 0
			_doom_hot_days = 0
			_doom_cold_days = 0
			_doom_warned_stage = 0
			UIManager.append_system_message("恒纪元的暖意抚平大地——毁灭的阴霾散尽，文明重获新生。")
		return
	_chaos_days_total += 1
	if era_kind == EraKind.CHAOS_HOT:
		_doom_hot_days += 1
	else:
		_doom_cold_days += 1
	# 不可预测性：每天随机出现「灾难日」（加压×2）或「喘息日」（不加深）
	var surge := randf() < 0.12
	var mercy := (not surge) and randf() < 0.08
	var rate := randf_range(0.026, 0.05)
	if surge:
		rate *= 2.0
	if mercy:
		rate = 0.0
	if era_kind == EraKind.CHAOS_HOT:
		if dehydrated:
			rate *= 0.35  # 脱水沉眠：文明转入干壳状态，酷热的损耗大幅降低
		else:
			rate += 0.015  # 拒绝脱水硬撑：族人伤亡，生命在流逝
	if surge:
		if story_ui != null:
			story_ui.show_warning("天象骤变！这一天的灾变格外残酷——毁灭进程陡然加速！")
	elif mercy:
		UIManager.append_system_message("难得的平静一日，大地的伤痕没有继续加深。")
	_add_doom(rate)

func _add_doom(amount: float) -> void:
	## 统一入口：增减毁灭进度、刷新 UI、跨越 50%/75%/90% 阶段时警告、满格触发毁灭
	var before := doom_progress
	doom_progress = clampf(doom_progress + amount, 0.0, 1.0)
	if story_ui != null:
		story_ui.set_doom_progress(doom_progress)
	if amount <= 0.0 or is_equal_approx(before, doom_progress):
		return
	if doom_progress >= 1.0:
		_destroy_world(_doom_reason_text())
		return
	var stage := 0
	if doom_progress >= 0.9:
		stage = 3
	elif doom_progress >= 0.75:
		stage = 2
	elif doom_progress >= 0.5:
		stage = 1
	if stage > _doom_warned_stage:
		_doom_warned_stage = stage
		if story_ui != null:
			match stage:
				1:
					story_ui.show_warning("警示：乱纪元已重创文明——毁灭风险过半！")
				2:
					story_ui.show_warning("危急：文明濒临倾覆！恒纪元的喘息是唯一的生机。")
				3:
					story_ui.show_warning("终局临近：文明的火苗只剩一线，随时可能熄灭！")
			story_ui.flash(Color(1.0, 0.2, 0.15), 0.3)

func _doom_reason_text() -> String:
	## 原著式毁灭判词：以乱纪元累计天数与主导灾变（酷热/严寒）描述文明之死
	var days := maxi(_chaos_days_total, 1)
	if _doom_hot_days > _doom_cold_days:
		return "乱纪元持续了 %d 天——文明在酷热中化为焦土，连脱水者也未能幸免。" % days
	if _doom_cold_days > _doom_hot_days:
		return "乱纪元持续了 %d 天——文明在严寒中冻灭，长夜再未迎来黎明。" % days
	return "乱纪元持续了 %d 天——文明在反复的酷热与严寒中耗尽了最后一线生机。" % days

func _flip_era() -> void:
	# 纪元走向完全由太阳决定：逼近=酷热，远去=严寒，适中=恒纪元
	var tendency := "stable"
	if sky != null and is_instance_valid(sky):
		tendency = sky.era_tendency()
		if sky.current_conjunction() == "triple":
			tendency = "hot"  # 三日凌空：日轨彻底失控，直接坠入酷热乱纪元
	if tendency == "night":
		# 普通夜晚不是纪元信号：计时器归零时延续当前纪元
		tendency = "stable" if era_kind == EraKind.STABLE \
			else ("hot" if era_kind == EraKind.CHAOS_HOT else "cold")
	var kind := _era_kind_for_tendency(tendency)
	match kind:
		EraKind.CHAOS_HOT:
			era_hours_left = randf_range(6.0, 30.0)
		EraKind.CHAOS_COLD:
			era_hours_left = randf_range(8.0, 36.0)
		_:
			era_hours_left = randf_range(30.0, 120.0)
	_apply_era_kind(kind)

func _era_kind_for_tendency(tendency: String) -> int:
	match tendency:
		"hot", "destroy":
			return EraKind.CHAOS_HOT
		"cold":
			return EraKind.CHAOS_COLD
		_:
			return EraKind.STABLE

func _apply_era_kind(kind: int) -> void:
	# 判断这次翻转是否“有意义”：刚开局（wall≈0）或上一纪元持续够久才播过场，
	# 快速反复的天象翻转只做状态与视觉切换，避免过场刷屏。
	var prev_wall := _era_wall_time
	era_kind = kind
	_hot_accum = 0.0
	_cold_accum = 0.0
	_stable_accum = 0.0
	_era_wall_time = 0.0
	danger_hours_left = float(current_era.get("danger_interval_hours", 8.0))
	if sky != null:
		sky.apply_era(_era_state_name())
	# 乱纪元常驻灾难氛围：远方轰鸣/风声随机袭来；恒纪元归于宁静
	if kind == EraKind.CHAOS_HOT or kind == EraKind.CHAOS_COLD:
		_ensure_disaster_fx()
		if disaster_fx != null and is_instance_valid(disaster_fx):
			disaster_fx.ambient("hot" if kind == EraKind.CHAOS_HOT else "cold")
	elif disaster_fx != null and is_instance_valid(disaster_fx):
		disaster_fx.ambient_off()
	_notify_era_change()
	var title := ""
	var line := ""
	var cine_kind := "stable"
	match kind:
		EraKind.STABLE:
			title = "恒纪元"
			line = "太阳归于秩序，文明得以喘息。"
		EraKind.CHAOS_HOT:
			title = "乱纪元 · 酷热"
			line = "双日凌空，飞星逼近，万物脱水，天地在燃烧。"
			cine_kind = "hot"
		EraKind.CHAOS_COLD:
			title = "乱纪元 · 严寒"
			line = "飞星尽没，长夜笼罩，寒流冻结星辰与大地。"
			cine_kind = "cold"
	# 高倍速时跳过切换过场，避免频繁打断节奏（文明入场过场始终保留）
	var use_cinematic: bool = TimeManager.time_scale <= 10.0
	var significant := prev_wall <= 0.5 or prev_wall >= MIN_ERA_WALL_TIME
	if use_cinematic and significant:
		_start_cinematic(cine_kind, title, line, transition_duration)
	else:
		# 无过场时，叙事氛围由在场角色亲口道出，而不是走系统播报
		match kind:
			EraKind.STABLE:
				if not dehydrated:
					_speak_or_system("太阳归于秩序，万物复苏。")
			EraKind.CHAOS_HOT:
				_speak_or_system("热浪灼烧大地，族人们纷纷脱水……")
			EraKind.CHAOS_COLD:
				_speak_or_system("长夜笼罩大地，寒流冻结万物……")
	if kind == EraKind.CHAOS_HOT and not dehydrated and not task_complete and significant:
		if use_cinematic:
			# 先播完酷热过场，再弹出脱水抉择
			_dehydrate_waiting = true
		else:
			dehydrate_pending = true
			story_ui.show_dehydrate_choice()
	# 开放剧情：纪元随太阳翻转时，让 AI 导演即兴生成一段天象事件
	if open_story:
		_ai_event_cooldown = minf(_ai_event_cooldown, 6.0)
		_trigger_ai_event({"cause": "era_%s" % _era_state_name()})
		if kind == EraKind.CHAOS_HOT or kind == EraKind.CHAOS_COLD:
			# 乱纪元：有“过客”从风沙中逃难而来
			_spawn_wanderer("chaos")

func _notify_era_change() -> void:
	match era_kind:
		EraKind.STABLE:
			if dehydrated:
				dehydrated = false
				PlayerGodController.set_movement_lock(false)
				UIManager.append_system_message("☀ 恒纪元降临！族人们将你浸泡复水，你从干枯中醒来，重获行动。")
			else:
				UIManager.append_system_message("☀ 恒纪元降临！太阳归于秩序。")
		EraKind.CHAOS_HOT:
			UIManager.append_system_message("☀ 乱纪元·酷热降临！双日凌空，飞星逼近。")
		EraKind.CHAOS_COLD:
			UIManager.append_system_message("❄ 乱纪元·严寒降临！飞星尽没，长夜笼罩。")

func _on_dehydrate_chosen(do_dehydrate: bool) -> void:
	dehydrate_pending = false
	story_ui.hide_dehydrate_choice()
	if do_dehydrate:
		dehydrated = true
		PlayerGodController.set_movement_lock(true)
		story_ui.flash(Color(0.95, 0.6, 0.25), 0.3)
		UIManager.append_system_message("你脱水了——蜷成干枯的皮囊沉入滚烫的沙中。脱水期间无法移动，酷热将无法伤害你。")
	else:
		dehydrated = false
		story_ui.flash(Color(1.0, 0.15, 0.1), 0.35)
		UIManager.append_system_message("你拒绝脱水，在酷热中强撑——族人心生动摇，毁灭进度骤增！")
		_add_doom(randf_range(0.10, 0.15))

func _speak_or_system(msg: String) -> void:
	## 叙事文本优先由在场角色亲口说出（气泡+对话日志+TTS），
	## 系统「最近事件」只保留给机械信息；无角色在场时才回退系统播报。
	for ch in [figure, companion]:
		if ch != null and is_instance_valid(ch) and ch.alive:
			ch.speak(msg, true)
			return
	UIManager.append_system_message(msg)

func _apply_danger() -> void:
	var hot := era_kind == EraKind.CHAOS_HOT
	if hot and dehydrated:
		UIManager.append_system_message("你在脱水沉眠中，酷热与你无关。")
		danger_hours_left = float(current_era.get("danger_interval_hours", 8.0))
		return
	var texts: Array = current_era.get("hot_texts" if hot else "cold_texts", [])
	var msg := str(texts[randi() % texts.size()]) if not texts.is_empty() \
		else ("酷热继续吞噬大地。" if hot else "严寒继续冻结万物。")
	_speak_or_system(msg)
	story_ui.flash(Color(1.0, 0.3, 0.1) if hot else Color(0.4, 0.6, 1.0), 0.18)
	_ensure_disaster_fx()
	if disaster_fx != null and is_instance_valid(disaster_fx):
		disaster_fx.strike("hot" if hot else "cold", _doom_center())
	# 天灾持续加压：毁灭进度上升（幅度随机，酷热略猛于严寒）
	_add_doom(randf_range(0.035, 0.06) if hot else randf_range(0.028, 0.05))
	if era_kind == EraKind.DESTROYED:
		return
	danger_hours_left = float(current_era.get("danger_interval_hours", 8.0))

func _apply_danger_event(kind: String) -> void:
	if AudioManager != null:
		AudioManager.play("blaster", -8.0)
	match kind:
		"hot":
			UIManager.append_system_message("☀ 天灾：太阳逼近，热浪吞噬一切！")
		"cold":
			UIManager.append_system_message("❄ 天灾：太阳远去，严寒冻结一切！")
	_ensure_disaster_fx()
	if disaster_fx != null and is_instance_valid(disaster_fx):
		disaster_fx.strike(kind, _doom_center())
	# 突发天灾重击：毁灭进度显著上升
	_add_doom(randf_range(0.05, 0.08) if kind == "hot" else randf_range(0.04, 0.07))

func _tick_followers(delta: float) -> void:
	## 历史向导与同伴跟随玩家化身（分列左右，保持可交谈距离）
	for follower in [figure, companion]:
		if follower == null or not is_instance_valid(follower) or player == null or not is_instance_valid(player):
			continue
		if follower.anim_override != "":
			continue  # 对话演出中保持姿态，由剧情排布管理
		if follower.character_data != null:
			follower.character_data.status["energy"] = 200.0
			follower.character_data.status["health"] = 100.0
		follower.llm_busy = true
		var to_player: Vector3 = player.global_position - follower.global_position
		to_player.y = 0.0
		var dist := to_player.length()
		if dist <= COMPANION_KEEP_DISTANCE:
			# 距离合适：待机，只面向玩家，不再吸附位置
			follower.moving = false
			follower.velocity = Vector3.ZERO
			follower.current_action = {}
			follower.face_towards(player.global_position)
			follower.set_animation_state("idle")
			continue
		if dist > COMPANION_FOLLOW_DISTANCE:
			# 太远：用自身的物理移动自然跟随（move_and_slide 有碰撞，不会重叠）
			var yaw: float = player.rotation.y
			var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var right := Vector3(cos(yaw), 0.0, -sin(yaw))
			var side := 1.4 if follower == figure else -1.4
			var desired: Vector3 = player.global_position + forward * 2.2 + right * side
			desired.y = WorldManager.get_terrain_height(desired.x, desired.z) + 0.95
			follower.action_target = desired
			follower.moving = true
			follower.current_action = {}
			continue
		# 中等距离（3.2~5.5m）：允许缓慢靠近，避免一直贴脸
		follower.moving = false
		follower.velocity = Vector3.ZERO
		follower.current_action = {}
		follower.face_towards(player.global_position)
		follower.set_animation_state("idle")

func _refresh_step() -> void:
	## 持续性“下一步”指引：让玩家始终清楚当前该做什么。
	if story_ui == null or not story_ui.visible:
		return
	if booting:
		story_ui.set_next_step(
			"天象骤变，世界正在变换……" if _cinematic_kind != "era" else "V装具同步中……",
			"auto"
		)
		return
	if _choreography_active:
		story_ui.set_next_step("剧情演出中……", "auto")
		return
	if dehydrate_pending:
		story_ui.set_next_step("⚠ 脱水抉择：决定你的命运！", "danger")
		return
	if dehydrated:
		story_ui.set_next_step("你正脱水沉眠——无法移动，等待恒纪元复水", "auto")
		return
	if doom_progress >= 0.75 and (era_kind == EraKind.CHAOS_HOT or era_kind == EraKind.CHAOS_COLD):
		story_ui.set_next_step("⚠ 毁灭进度 %d%%：乱纪元已煎熬 %d 天，亟待转机！" % [int(doom_progress * 100.0), maxi(_chaos_days_total, 1)], "danger")
		return
	if objective_active and not objective_complete:
		return  # 目标距离由 _tick_objective 实时更新
	if task_complete:
		story_ui.set_next_step("任务完成，准备进入下一文明", "idle")
		return
	match _current_beat_type:
		"choice":
			story_ui.set_next_step("剧情对话：选择你的回应", "action")
		"scene", "end":
			story_ui.set_next_step("剧情旁白播放中……", "auto")
		"objective":
			story_ui.set_next_step("前往发光灯塔，触发关键节点", "action")
		_:
			story_ui.set_next_step("等待自动事件…（纪元会自动轮转）", "auto")

# ---------- 开放剧情：AI 生成、寻宝奖励与好感度 ----------

## 开放剧情开场：目标灯塔先行，遗宝散布荒野，AI 事件随即触发
func _start_open_story() -> void:
	# 同伴不在一开场就在场：由场景条件触发登场（靠近地标/寻宝/经历事件/天象骤变）
	_companion_entrance_pending = not (current_era.get("companion", {}) as Dictionary).is_empty()
	objective_active = true
	_spawn_objective_beacons(objective_index)
	_spawn_treasures()
	_ai_event_cooldown = 3.0
	_trigger_ai_event({"cause": "opening"})

## 随机触发循环：AI 事件按随机间隔自动发生；天象与纪元切换也会即时触发
func _tick_ai_events(delta: float) -> void:
	if not open_story or not active or finished or task_complete:
		return
	if booting or _intro_active or _wake_active or _journey_active or _choreography_active or dehydrate_pending:
		return
	if _ai_beat_active or _ai_request_pending or _reaction_playing:
		return
	# 任务收束：目标节点全部抵达即进入收官；
	# 真相碎片仍要求进度达标（鼓励继续对话与寻宝，而不是冲刺跑图）
	if objective_complete:
		_complete_open_era()
		return
	_ai_event_cooldown -= delta
	if _ai_event_cooldown <= 0.0:
		_ai_event_cooldown = randf_range(AI_EVENT_MIN_INTERVAL, AI_EVENT_MAX_INTERVAL)
		_trigger_ai_event({"cause": "random"})

## 纪元收官：AI 导演再演一段，然后结算文明
func _complete_open_era() -> void:
	if task_complete:
		return
	_ai_event_cooldown = 99999.0
	_trigger_ai_event({"cause": "ending"}, _finish_open_era)

func _finish_open_era() -> void:
	if task_complete:
		return
	var beat := {"narration": _procedural_narration("completion")}
	if era_index >= eras.size() - 1:
		# 最后一纪：按真相决定石碑结局（真结局/普通/残缺）
		beat["ending"] = "monument"
	_complete_task(beat)

func _trigger_ai_event(cause: Dictionary, then: Callable = Callable()) -> void:
	if not active or finished or _ai_beat_active or _ai_request_pending or _reaction_playing:
		return
	if booting or _choreography_active:
		_ai_event_cooldown = minf(_ai_event_cooldown, 8.0)
		return
	# 随机性增强：部分随机事件会演化为吉兆/凶兆/沙暴等特殊事件
	if str(cause.get("cause", "")) == "random" and randf() < 0.4:
		var special := ["omen", "fortune", "storm"]
		cause = {"cause": special[randi() % special.size()]}
	_ai_event_then = then
	if _ai_llm_ready():
		_ai_request_pending = true
		var prompt := PromptBuilder.build_story_event_prompt(_ai_event_state(cause))
		LLMService.request_dialogue("story_event", prompt, func(result: Dictionary) -> void:
			_ai_request_pending = false
			if not active or finished:
				return
			if result.is_empty() or not result.has("text"):
				_fallback_ai_event(cause)
				return
			_show_ai_beat(result, cause)
		)
	else:
		_fallback_ai_event(cause)

func _fallback_ai_event(cause: Dictionary) -> void:
	## LLM 离线时的程序化兜底：根据天象拼装事件，不读取固定剧本
	var event := {
		"speaker": "figure",
		"text": _procedural_narration(str(cause.get("cause", "event"))),
		"choices": _fallback_choices(cause)
	}
	_show_ai_beat(event, cause)

func _show_ai_beat(event: Dictionary, cause: Dictionary) -> void:
	var speaker_id := str(event.get("speaker", "figure"))
	if speaker_id != "companion" and speaker_id != "narrator":
		speaker_id = "figure"
	var text := str(event.get("text", _procedural_narration("event")))
	var choices: Array = event.get("choices", [])
	if not choices is Array or choices.is_empty():
		choices = _fallback_choices(cause)
	var sanitized: Array = []
	for ch in choices:
		if ch is Dictionary:
			sanitized.append({
				"text": str(ch.get("text", "继续")),
				"reply": str(ch.get("reply", "")),
				"progress": float(ch.get("progress", 0.04)),
				"affinity": float(ch.get("affinity", 0.0)),
				"truth": float(ch.get("truth", 0.0))
			})
	if sanitized.is_empty():
		sanitized = _fallback_choices(cause)
	_ai_beat = {"speaker": speaker_id, "choices": sanitized, "text": text, "cause": cause}
	if _ai_event_then.is_valid():
		_ai_beat["then"] = _ai_event_then
		_ai_event_then = Callable()
	_ai_beat_active = true
	_current_beat_type = "choice"
	var choice_texts: Array[String] = []
	for ch in sanitized:
		choice_texts.append(str(ch.get("text", "继续")))
	if story_ui != null:
		story_ui.show_beat(_speaker_name(speaker_id), text, choice_texts)
	_speak_ai_text(speaker_id, text)

func _apply_ai_choice(index: int) -> void:
	if not _ai_beat_active:
		return
	var choices: Array = _ai_beat.get("choices", [])
	if index < 0 or index >= choices.size():
		return
	_ai_beat_active = false
	_current_beat_type = ""
	var choice: Dictionary = choices[index]
	var then: Callable = _ai_beat.get("then", Callable())
	var speaker_id := str(_ai_beat.get("speaker", "figure"))
	progress = clampf(progress + float(choice.get("progress", 0.04)), 0.0, 1.0)
	if story_ui != null:
		story_ui.set_progress(progress)
	var affinity := float(choice.get("affinity", 0.0))
	if affinity != 0.0:
		_apply_favor(affinity, "回应%s的谈话" % _speaker_name(speaker_id))
	var truth_gain := float(choice.get("truth", 0.0))
	if truth_gain > 0.0:
		truth = clampf(truth + truth_gain, 0.0, 100.0)
		if story_ui != null:
			story_ui.set_truth(truth, clues)
	var reply := str(choice.get("reply", ""))
	_sentence_generation += 1
	if reply != "" and player != null and is_instance_valid(player):
		# 玩家的回应以字幕呈现，不出气泡、不合成语音
		if story_ui != null:
			story_ui.set_bottom_sentence(reply)
	# 让旁边的人知道并记住这次选择
	_remember_player_choice(str(choice.get("text", "")), reply)
	_resolved_ai_events += 1
	if then.is_valid():
		then.call()
		return
	# 目标已达成时，事件一结束就立刻进入收官，不等随机间隔
	if objective_complete and not task_complete:
		_ai_event_cooldown = 2.0
	else:
		_ai_event_cooldown = randf_range(AI_EVENT_MIN_INTERVAL, AI_EVENT_MAX_INTERVAL)
	# 玩家回应后，在场角色当场反应（AI 生成或程序化兜底）
	await _play_companion_reaction({"text": str(choice.get("text", "")), "reply": reply})

func _ai_llm_ready() -> bool:
	return LLMService != null and LLMService.is_available()

func _ai_event_state(cause: Dictionary) -> Dictionary:
	var favor_parts: Array[String] = []
	var player_id := str(player.character_data.id) \
		if player != null and is_instance_valid(player) and player.character_data != null else ""
	for ch in [figure, companion]:
		if ch == null or not is_instance_valid(ch) or ch.character_data == null or player_id == "":
			continue
		var rel := RelationshipSystem.get_relationship(ch, player_id)
		favor_parts.append("%s 对你的态度：%s（亲密度 %.0f）" % [
			ch.character_data.name, RelationshipSystem.attitude_text(ch, player_id), rel.affinity
		])
	return {
		"era_name": str(current_era.get("name", "")),
		"era_kind": era_kind_text(),
		"sky": _sky_description(),
		"sun_count": sky.visible_sun_count() if sky != null and is_instance_valid(sky) else 1,
		"task": str((current_era.get("task", {}) as Dictionary).get("title", "文明的任务")),
		"progress": progress,
		"truth": truth,
		"clues": clues,
		"total_eras": eras.size(),
		"cause": str(cause.get("cause", "random")),
		"item": str(cause.get("item", "")),
		"favor_text": "\n".join(favor_parts),
		"treasures_found": _treasures_found,
		"artifacts": _artifacts
	}

func _speaker_name(speaker_id: String) -> String:
	match speaker_id:
		"companion":
			return str(companion.character_data.name) \
				if companion != null and is_instance_valid(companion) and companion.character_data != null else "同伴"
		"narrator":
			return "旁白"
		_:
			return str(figure.character_data.name) \
				if figure != null and is_instance_valid(figure) and figure.character_data != null else "向导"

func _speak_ai_text(speaker_id: String, text: String) -> void:
	if text.strip_edges() == "":
		return
	if speaker_id == "narrator":
		if narrator_voice == "":
			narrator_voice = casted_voice("", CASTING_ROLE_NARRATOR)
		var anchor = figure if figure != null and is_instance_valid(figure) else player
		if TTSManager != null:
			TTSManager.speak(text, narrator_voice, anchor, true, true)
		return
	var anchor = companion if speaker_id == "companion" else figure
	if anchor != null and is_instance_valid(anchor):
		anchor.speak(text, true, true)

func _procedural_narration(kind: String) -> String:
	var sky_desc := _sky_description()
	var name := _speaker_name("figure")
	var task := str((current_era.get("task", {}) as Dictionary).get("title", "文明的任务"))
	match kind:
		"completion":
			return "「%s」达成。太阳依旧不可预测，但这一纪的路，已经被写进石头与记忆里。" % task
		"omen":
			return "天空掠过一道不祥的弧光，%s。%s望着你，眼底有不安。" % [sky_desc, name]
		"fortune":
			return "太阳短暂温顺，风里传来吉兆的低语，%s。%s觉得该做点什么。" % [sky_desc, name]
		"storm":
			return "地平线腾起沙暴，%s。%s压低声音，等你的决定。" % [sky_desc, name]
		_:
			return "风沙漫过地平线，%s。%s望着你，等这一程的方向。" % [sky_desc, name]

func _sky_description() -> String:
	if sky == null or not is_instance_valid(sky):
		return "三颗飞星在云层后隐现"
	match sky.era_tendency():
		"destroy":
			return "三日凌空！三颗飞星同时升上天空，天象彻底失控"
		"hot":
			return "双日凌空，两颗飞星并肩悬在空中，热浪翻涌" \
				if sky.visible_sun_count() >= 2 else "一颗飞星逼近大地，空气在灼热中颤抖"
		"cold":
			return "飞星尽没，天幕漆黑，长夜笼罩大地" \
				if sky.visible_sun_count() == 0 else "飞星远去，白昼微弱，寒气从荒原深处漫上来"
		"night":
			return "飞星尽没，夜穹深黑，星辰低垂"
		_:
			return "一轮太阳悬在稳定的轨道上，日升日落"

func _fallback_choices(cause := {}) -> Array:
	var kind := str(cause.get("cause", "random"))
	match kind:
		"omen":
			return [
				{"text": "在灰烬中寻找预兆的痕迹", "reply": "你读懂了一半——这可能是毁灭前的低语。", "progress": -0.02, "affinity": 0.0, "truth": 2.0},
				{"text": "召集队伍立刻转移", "reply": "你们撤离了不祥之地，风沙随即吞没了原地。", "progress": 0.04, "affinity": 2.0, "truth": 0.0}
			]
		"fortune":
			return [
				{"text": "顺着吉兆继续前行", "reply": "太阳短暂放晴，前路似乎格外平坦。", "progress": 0.08, "affinity": 2.0, "truth": 1.0},
				{"text": "停下感谢命运", "reply": "你们驻足片刻，仿佛听见文明在低语。", "progress": 0.03, "affinity": 3.0, "truth": 1.0}
			]
		"storm":
			return [
				{"text": "就地扎营躲避沙暴", "reply": "沙暴过境，队伍损失了些许时间。", "progress": -0.03, "affinity": 0.0, "truth": 0.0},
				{"text": "顶着风暴赶路", "reply": "你们在风沙中硬闯，反而发现了一条捷径。", "progress": 0.07, "affinity": -1.0, "truth": 0.0}
			]
		_:
			return [
				{"text": "继续探索，寻找文明遗迹", "reply": "你带着队伍继续前行，风沙在身后合拢。", "progress": 0.06, "affinity": 2.0, "truth": 0.0},
				{"text": "停下观察太阳的轨迹", "reply": "你在烈日下记录日位，隐约捕捉到一丝规律。", "progress": 0.04, "affinity": 1.0, "truth": 1.0},
				{"text": "与%s长谈这一纪的见闻" % _speaker_name("figure"), "reply": "你们在营火旁交换了对这个世界的理解。", "progress": 0.02, "affinity": 4.0, "truth": 0.0}
			]

func _apply_favor(change: float, reason: String) -> void:
	if player == null or not is_instance_valid(player) or player.character_data == null:
		return
	for ch in [figure, companion]:
		if ch != null and is_instance_valid(ch) and ch.character_data != null:
			RelationshipSystem.update_relationship(ch, player.character_data.id, change, reason)

## 把玩家的选择写进所有在场角色的记忆：之后 AI 对话会引用它
func _remember_player_choice(choice_text: String, reply: String) -> void:
	if choice_text == "" and reply == "":
		return
	var summary := "玩家选择了：“%s”%s" % [
		choice_text,
		("（回应：%s）" % reply) if reply != "" else ""
	]
	for ch in [figure, companion]:
		if ch != null and is_instance_valid(ch) and ch.character_data != null:
			MemorySystem.add_memory(ch, summary.left(140), 0.65, "neutral", ["story", "player", "choice"])
	if story_ui != null:
		story_ui.push_event("众人听见了你的选择。")

## 让在场角色对玩家的选择作出即时反应
func _play_companion_reaction(choice: Dictionary) -> void:
	await _wait_for_voice_clear()
	if not active or finished:
		return
	var speaker = _reaction_speaker()
	if speaker == null:
		return
	_reaction_playing = true
	var choice_text := str(choice.get("text", ""))
	if _ai_llm_ready():
		var prompt := PromptBuilder.build_reaction_prompt(
			_ai_event_state({"cause": "reaction"}),
			choice_text
		)
		LLMService.request_dialogue("story_reaction", prompt, func(result: Dictionary) -> void:
			_finish_reaction(speaker, str(result.get("text", "")), choice_text)
		)
	else:
		_finish_reaction(speaker, "", choice_text)

func _finish_reaction(speaker, ai_text: String, choice_text: String) -> void:
	if not active or finished:
		_reaction_playing = false
		return
	var text := ai_text.strip_edges()
	if text == "":
		text = _fallback_reaction(speaker, choice_text)
	_speak_ai_text(_speaker_id_of(speaker), text)
	# 给足观感：等台词读完再让随机事件接管
	var hold := maxf(1.4, float(text.length()) / 4.5)
	await get_tree().create_timer(hold).timeout
	if active and not finished:
		_reaction_playing = false

## 选一个刚才没开口的在场角色来反应
func _reaction_speaker():
	var beat_speaker := str(_ai_beat.get("speaker", ""))
	var candidates: Array = []
	for ch in [companion, figure]:
		if ch != null and is_instance_valid(ch) and ch.character_data != null:
			if _speaker_id_of(ch) != beat_speaker:
				candidates.append(ch)
	if candidates.is_empty():
		for ch in [figure, companion]:
			if ch != null and is_instance_valid(ch) and ch.character_data != null:
				candidates.append(ch)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]

func _speaker_id_of(ch) -> String:
	if ch == companion:
		return "companion"
	return "figure"

## 程序化兜底反应：按好感度给出不同口吻
func _fallback_reaction(speaker, choice_text: String) -> String:
	var player_name := GameState.player_name
	var pools := {
		"挚友": ["“这条路，我陪你走到底。”", "“你开口的那一刻，我就知道了。”"],
		"友好": ["“好，{player}，按你说的办。”", "“我听见了——太阳会记住你的话。”"],
		"中立": ["“你做了选择，族人都看在眼里。”", "“风会带走很多，但这个决定会留下。”"],
		"冷淡": ["“随你。”", "“我记住了。”"],
		"敌视": ["“你最好知道自己在做什么。”", "“哼，记住你今天的话。”"]
	}
	var attitude := "中立"
	if player != null and is_instance_valid(player) and player.character_data != null \
			and speaker != null and is_instance_valid(speaker) and speaker.character_data != null:
		attitude = RelationshipSystem.attitude_text(speaker, player.character_data.id)
	var pool: Array = pools.get(attitude, pools["中立"])
	return str(pool[randi() % pool.size()]).replace("{player}", player_name)

func _update_favor_ui() -> void:
	if story_ui == null:
		return
	var player_id := str(player.character_data.id) \
		if player != null and is_instance_valid(player) and player.character_data != null else ""
	var parts: Array[String] = []
	if player_id != "":
		for ch in [figure, companion]:
			if ch == null or not is_instance_valid(ch) or ch.character_data == null:
				continue
			var rel := RelationshipSystem.get_relationship(ch, player_id)
			parts.append("%s %s(%d)" % [
				ch.character_data.name, RelationshipSystem.attitude_text(ch, player_id), int(rel.affinity)
			])
	var text := "好感 " + ("  ".join(parts) if not parts.is_empty() else "—")
	if text != _last_favor_text:
		_last_favor_text = text
		story_ui.set_favorability(text)
	story_ui.set_treasure_count(_treasures_found)

func _open_completion_text() -> String:
	var task := str((current_era.get("task", {}) as Dictionary).get("title", "文明的任务"))
	return "「%s」完成。这一纪共寻得 %d 件遗宝、获得 %.0f%% 的真相——太阳依然不可预测，但文明记住了这段路。" % [
		task, _treasures_found, truth
	]

# ---------- 寻宝系统 ----------

func _spawn_treasures() -> void:
	for i in TREASURE_COUNT:
		_spawn_treasure()

func _spawn_treasure() -> void:
	if sky == null or not is_instance_valid(sky):
		return
	var pos := _random_treasure_pos()
	var styles := ["pillar", "crystal", "orb", "rune"]
	var style: String = styles[randi() % styles.size()]
	var node = sky.spawn_beacon(pos, "遗宝", _era_beacon_color(), style)
	_treasures.append({"node": node, "pos": pos})

func _random_treasure_pos() -> Vector3:
	var center: Vector3 = player.global_position if player != null and is_instance_valid(player) else _story_pos()
	for attempt in 26:
		var ang := randf() * TAU
		var dist := randf_range(22.0, 52.0)
		var pos := center + Vector3(cos(ang), 0, sin(ang)) * dist
		# 遗迹带更容易出现遗宝：三成概率向辉光区域偏移
		if randf() < 0.3 and WorldManager.terrain_gen != null:
			var relic_dir := Vector3(cos(ang + PI * 0.5), 0, sin(ang + PI * 0.5))
			pos += relic_dir * randf_range(4.0, 14.0)
		if WorldManager.terrain_gen != null:
			if WorldManager.terrain_gen.is_water(pos.x, pos.z):
				continue
			if WorldManager.terrain_gen.slope_at(pos.x, pos.z) > 0.5:
				continue
		pos = WorldManager.clamp_point(pos, 0.9)
		if _pos_near_any(pos, _treasure_positions(), 9.0):
			continue
		if _pos_near_any(pos, _beacon_positions(), 12.0):
			continue
		return pos
	return WorldManager.clamp_point(center + Vector3(36, 0, 0), 0.9)

func _treasure_positions() -> Array:
	var out: Array = []
	for t in _treasures:
		out.append(t.get("pos", Vector3.ZERO))
	return out

func _beacon_positions() -> Array:
	var out: Array = []
	for b in beacons:
		if b != null and is_instance_valid(b):
			out.append(b.global_position)
	return out

func _pos_near_any(pos: Vector3, positions: Array, radius: float) -> bool:
	for p in positions:
		if Vector2(pos.x - p.x, pos.z - p.z).length() < radius:
			return true
	return false

func _tick_treasures(delta: float) -> void:
	if not open_story or not active or finished or player == null or not is_instance_valid(player):
		return
	_treasure_respawn_timer -= delta
	for i in range(_treasures.size() - 1, -1, -1):
		var t: Dictionary = _treasures[i]
		var pos: Vector3 = t.get("pos", Vector3.ZERO)
		var dist := Vector2(player.global_position.x - pos.x, player.global_position.z - pos.z).length()
		if dist < TREASURE_REACH_DISTANCE:
			_claim_treasure(i)
			return
	if _treasure_respawn_timer <= 0.0 and _treasures.size() < TREASURE_COUNT:
		_spawn_treasure()
		_treasure_respawn_timer = TREASURE_RESPAWN_TIME

func _claim_treasure(index: int) -> void:
	if index < 0 or index >= _treasures.size():
		return
	var t: Dictionary = _treasures[index]
	_treasures.remove_at(index)
	var node = t.get("node", null)
	if is_instance_valid(node):
		node.queue_free()
	_treasures_found += 1
	var artifact := _next_artifact()
	_artifacts.append(artifact)
	progress = clampf(progress + TREASURE_PROGRESS_GAIN, 0.0, 1.0)
	truth = clampf(truth + TREASURE_TRUTH_GAIN, 0.0, 100.0)
	if story_ui != null:
		story_ui.set_progress(progress)
		story_ui.set_truth(truth, clues)
	_apply_favor(TREASURE_AFFINITY_GAIN, "寻得遗宝·%s" % artifact)
	if AudioManager != null:
		AudioManager.play("powerup", -6.0)
	if story_ui != null:
		story_ui.show_milestone(
			"✦ 寻得遗宝 · %s" % artifact,
			"沙土之下，埋着前一个文明的余温。",
			Color(1.0, 0.85, 0.3)
		)
	UIManager.append_system_message(
		"✦ 寻得遗宝「%s」：进度+%d%%，真相+%d，好感+%d（累计 %d 件）" % [
			artifact, int(TREASURE_PROGRESS_GAIN * 100.0), int(TREASURE_TRUTH_GAIN),
			int(TREASURE_AFFINITY_GAIN), _treasures_found
		]
	)
	HistoryManager.log_event("story", "寻得遗宝·%s" % artifact, "你在废土中掘出了前代文明的遗物。")
	if _treasures_found >= 3:
		GameState.unlock_achievement("treasure_hunter")
	_ai_event_cooldown = minf(_ai_event_cooldown, 4.0)
	_trigger_ai_event({"cause": "treasure", "item": artifact})
	# 遗宝的动静引来“过客”
	_spawn_wanderer("treasure")

func _next_artifact() -> String:
	var pool: Array[String] = []
	for name in _era_artifact_pool():
		if not _artifacts.has(name):
			pool.append(name)
	for name in TREASURE_ARTIFACTS:
		if not _artifacts.has(name):
			pool.append(name)
	if pool.is_empty():
		return "无名遗物 %d" % (_treasures_found + 1)
	return pool[randi() % pool.size()]

func _era_artifact_pool() -> Array[String]:
	## 每纪专属遗宝：把时代印记织进道具命名，增加收集新鲜感。
	match str(current_era.get("id", "")):
		"era_wenwang":
			return ["卜骨星图", "青铜日晷残片", "观星蓍草"]
		"era_mozi":
			return ["铜齿轮芯", "浑仪刻度环", "墨守机括"]
		"era_qinshihuang":
			return ["玉琮权杖", "陶俑兵符", "方士丹炉"]
		"era_newton":
			return ["黄铜摆钟芯", "万有引力砝码", "天文台镜片"]
		"era_einstein":
			return ["统一场棱镜", "光速标尺", "时空曲率环"]
		_:
			return []

# ---------- 场景触发角色：同伴登场与过客相遇 ----------

## 演出进行中：过场动画 / 节拍演出 / 引言 / 苏醒 / 跋涉期间，
## 场景触发的角色登场与走位一律暂停，等演出结束再继续
func _presentation_busy() -> bool:
	return booting or _choreography_active or _intro_active or _wake_active or _journey_active

## 同伴登场检测：由场景条件触发，从远处走来入队
func _tick_companion_entrance(delta: float) -> void:
	if not open_story or not active or finished or task_complete:
		return
	if _presentation_busy():
		# 演出期间暂停入场走位，避免角色在过场镜头里提前入队
		return
	# 同伴已在场：若仍处于“入场中”，检查是否已走近并正式入队
	if companion != null and is_instance_valid(companion):
		if _companion_walking_in and player != null and is_instance_valid(player):
			_tick_companion_walk_in(delta)
		return
	if not _companion_entrance_pending:
		return
	if _ai_beat_active or _reaction_playing:
		return
	# 场景触发条件：靠近首个地标 / 寻得遗宝 / 经历三场剧情 / 天象骤变
	if _near_first_beacon() or _treasures_found >= 1 \
			or _resolved_ai_events >= COMPANION_ENTRANCE_EVENTS or _era_is_chaos():
		_start_companion_entrance()

## 入场走位：持续走向玩家身边，走近后停下、面向玩家、说登场台词
func _tick_companion_walk_in(delta: float) -> void:
	_companion_entrance_timer += delta
	var dist := Vector2(
		companion.global_position.x - player.global_position.x,
		companion.global_position.z - player.global_position.z
	).length()
	if dist <= COMPANION_JOIN_DISTANCE:
		_finish_companion_entrance()
		return
	if _companion_entrance_timer >= COMPANION_ENTRANCE_TIMEOUT:
		# 兜底：地形/建筑卡住走不过来时，直接安置到玩家身边再入队
		companion.global_position = WorldManager.clamp_point(
			player.global_position + Vector3(2.4, 0, 0.6), 0.95
		)
		companion.velocity = Vector3.ZERO
		_finish_companion_entrance()
		return
	companion.moving = true
	companion.action_target = player.global_position + Vector3(2.4, 0, 0.6)

func _finish_companion_entrance() -> void:
	companion.anim_override = ""
	companion.moving = false
	companion.velocity = Vector3.ZERO
	companion.current_action = {}
	companion.face_towards(player.global_position)
	companion.llm_busy = true
	_companion_walking_in = false
	_companion_entrance_pending = false
	_speak_companion_entrance_line()

func _near_first_beacon() -> bool:
	if player == null or not is_instance_valid(player) or objective_points.is_empty():
		return false
	var pt: Dictionary = objective_points[0]
	var pos_arr: Array = pt.get("pos", [0.0, 0.0, 0.0])
	var target := Vector3(float(pos_arr[0]), 0, float(pos_arr[2]))
	return Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < COMPANION_ENTRANCE_DISTANCE

func _era_is_chaos() -> bool:
	return era_kind == EraKind.CHAOS_HOT or era_kind == EraKind.CHAOS_COLD

## 同伴登场：从玩家身后远处走来，走近后入队
func _start_companion_entrance() -> void:
	var comp_def: Dictionary = current_era.get("companion", {})
	if comp_def.is_empty() or player == null or not is_instance_valid(player):
		_companion_entrance_pending = false
		return
	var yaw: float = player.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var spawn := WorldManager.clamp_point(
		player.global_position - fwd * 15.0 + Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0)),
		0.95
	)
	companion = _spawn_story_character("story_companion", comp_def, spawn)
	companion.face_towards(player.global_position)
	# 历史人物不做自主 LLM 决策（决策提示词属于自由模拟·硅灵世界观），入场期间同样保持静默
	companion.llm_busy = true
	# 入场期间用姿态覆盖让跟随逻辑跳过，由入场逻辑独立走到玩家身边
	companion.anim_override = "walk"
	companion.moving = true
	companion.action_target = player.global_position + Vector3(2.4, 0, 0.6)
	companion.current_action = {}
	_companion_walking_in = true
	_companion_entrance_pending = false
	if story_ui != null:
		story_ui.show_character_entrance(str(comp_def.get("name", "同伴")))
	if AudioManager != null:
		AudioManager.play_3d("landing", companion.global_position, -4.0)
	UIManager.append_system_message("◈ 远处走来一个人影——%s 正朝你靠近。" % str(comp_def.get("name", "同伴")))

func _speak_companion_entrance_line() -> void:
	if companion == null or not is_instance_valid(companion):
		return
	var comp_name := str(companion.character_data.name) if companion.character_data != null else "同伴"
	if _ai_llm_ready():
		var prompt := PromptBuilder.build_scene_character_prompt(
			_ai_event_state({"cause": "entrance"}), comp_name, "entrance"
		)
		LLMService.request_dialogue("story_entrance", prompt, func(result: Dictionary) -> void:
			if companion == null or not is_instance_valid(companion):
				return
			var text := str(result.get("text", ""))
			if text.strip_edges() == "":
				text = _fallback_entrance_line()
			companion.speak(text, true, true)
		)
	else:
		companion.speak(_fallback_entrance_line(), true, true)

func _fallback_entrance_line() -> String:
	var player_name := GameState.player_name
	return "风沙里走出一条路。%s，我跟你走这一程——太阳的事，我想亲眼看看。" % player_name

# ---------- 过客相遇：寻宝/乱纪元/地标时的临时角色 ----------

func _spawn_wanderer(reason: String) -> void:
	if not open_story or not active or finished:
		return
	if _presentation_busy():
		# 过场/引言等演出期间不生成过客，等演出结束再登场
		_pending_wanderer_reason = reason
		return
	if _wanderer != null and is_instance_valid(_wanderer):
		return
	if Time.get_ticks_msec() / 1000.0 < _wanderer_cooldown:
		return
	if player == null or not is_instance_valid(player):
		return
	var def := _wanderer_def(reason)
	var yaw: float = player.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var spawn := WorldManager.clamp_point(
		player.global_position - fwd * 13.0 + Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0)),
		0.95
	)
	_wanderer = _spawn_story_character("story_wanderer", def, spawn)
	_wanderer.face_towards(player.global_position)
	_wanderer.moving = true
	_wanderer.action_target = player.global_position + Vector3(3.0, 0, 0.5)
	_wanderer.current_action = {}
	_wanderer_phase = "in"
	_wanderer_reason = reason
	_wanderer_timer = 0.0
	_wanderer_cooldown = Time.get_ticks_msec() / 1000.0 + WANDERER_COOLDOWN
	if story_ui != null:
		story_ui.show_character_entrance(str(def.get("name", "旅人")))

func _wanderer_def(reason: String) -> Dictionary:
	var archetypes: Array[Dictionary] = []
	match reason:
		"treasure":
			archetypes = [
				{"name": "拾荒者", "role": "scavenger", "speech_style": "粗粝", "emotion": "curiosity"},
				{"name": "掘墓人", "role": "digger", "speech_style": "沉默", "emotion": "calm"}
			]
		"chaos":
			archetypes = [
				{"name": "脱水者", "role": "survivor", "speech_style": "虚弱", "emotion": "fear"},
				{"name": "流浪星象师", "role": "astrologer", "speech_style": "呓语", "emotion": "awe"}
			]
		_:
			archetypes = [
				{"name": "传令使", "role": "messenger", "speech_style": "急促", "emotion": "hope"},
				{"name": "长老", "role": "elder", "speech_style": "沉稳", "emotion": "calm"}
			]
	return archetypes[randi() % archetypes.size()]

func _tick_wanderer(delta: float) -> void:
	if _wanderer == null or not is_instance_valid(_wanderer):
		_wanderer_phase = ""
		return
	if _presentation_busy():
		# 过场期间过客原地等待，不走近也不说话
		return
	if player == null or not is_instance_valid(player):
		return
	match _wanderer_phase:
		"in":
			var dist := Vector2(
				_wanderer.global_position.x - player.global_position.x,
				_wanderer.global_position.z - player.global_position.z
			).length()
			if dist < 3.5:
				_wanderer.moving = false
				_wanderer.velocity = Vector3.ZERO
				_wanderer.current_action = {}
				_wanderer.face_towards(player.global_position)
				_wanderer_phase = "speak"
				_wanderer_timer = 0.0
				_speak_wanderer()
		"speak":
			_wanderer_timer += delta
			if _wanderer_timer > 7.0:
				_wanderer.moving = true
				var away: Vector3 = _wanderer.global_position - player.global_position
				away.y = 0.0
				if away.length_squared() < 0.01:
					away = Vector3(1, 0, 0)
				away = away.normalized() * 18.0
				_wanderer.action_target = WorldManager.clamp_point(_wanderer.global_position + away, 0.95)
				_wanderer_phase = "out"
				_wanderer_timer = 0.0
		"out":
			_wanderer_timer += delta
			var d: float = _wanderer.global_position.distance_to(_wanderer.action_target)
			if d < 1.0 or _wanderer_timer > 15.0:
				_despawn_wanderer()

func _speak_wanderer() -> void:
	if _wanderer == null or not is_instance_valid(_wanderer):
		return
	var w_name := str(_wanderer.character_data.name) if _wanderer.character_data != null else "旅人"
	if _ai_llm_ready():
		var prompt := PromptBuilder.build_scene_character_prompt(
			_ai_event_state({"cause": "wanderer"}), w_name, "wanderer_%s" % _wanderer_reason
		)
		LLMService.request_dialogue("story_wanderer", prompt, func(result: Dictionary) -> void:
			if _wanderer == null or not is_instance_valid(_wanderer):
				return
			var text := str(result.get("text", ""))
			if text.strip_edges() == "":
				text = _fallback_wanderer_line()
			_wanderer.speak(text, true, true)
			_reward_wanderer_meeting()
		)
	else:
		_wanderer.speak(_fallback_wanderer_line(), true, true)
		_reward_wanderer_meeting()

func _fallback_wanderer_line() -> String:
	match _wanderer_reason:
		"treasure":
			return "这里埋着旧世界的东西——你比我更懂它该去哪。"
		"chaos":
			return "太阳疯了……脱水之前，让我把这句话带给你：别停。"
		_:
			return "沿着光走，别回头——这是前人留下的话。"

func _reward_wanderer_meeting() -> void:
	progress = clampf(progress + 0.02, 0.0, 1.0)
	truth = clampf(truth + 1.0, 0.0, 100.0)
	if story_ui != null:
		story_ui.set_progress(progress)
		story_ui.set_truth(truth, clues)
	var w_name := str(_wanderer.character_data.name) if _wanderer != null and _wanderer.character_data != null else "旅人"
	UIManager.append_system_message("◈ 与%s短暂交谈：文明进度+2%%，真相+1" % w_name)
	HistoryManager.log_event("story", "与过客相遇", "你在旅途中与一位过客交换了见闻。")

func _despawn_wanderer() -> void:
	if _wanderer != null and is_instance_valid(_wanderer):
		# 同步清理角色表，避免残留“已释放节点”的引用
		if CharacterManager != null and _wanderer.character_data != null:
			CharacterManager.characters.erase(_wanderer.character_data.id)
		_wanderer.queue_free()
	_wanderer = null
	_wanderer_phase = ""
	_wanderer_reason = ""

func era_kind_text() -> String:
	return str(ERA_KIND_NAMES.get(era_kind, "恒纪元"))

# ---------- 存档 ----------

func serialize() -> Dictionary:
	return {
		"active": active,
		"finished": finished,
		"era_index": era_index,
		"current_beat_id": current_beat_id,
		"progress": progress,
		"task_complete": task_complete,
		"era_kind": era_kind,
		"era_hours_left": era_hours_left,
		"danger_hours_left": danger_hours_left,
		"doom_progress": doom_progress,
		"doom_day_accum": _doom_day_accum,
		"chaos_days_total": _chaos_days_total,
		"doom_hot_days": _doom_hot_days,
		"doom_cold_days": _doom_cold_days,
		"doom_warned_stage": _doom_warned_stage,
		"destroyed_count": destroyed_count,
		"truth": truth,
		"clues": clues,
		"objective_complete": objective_complete,
		"objective_index": objective_index,
		"dehydrated": dehydrated,
		"dehydrate_pending": dehydrate_pending,
		"open_story": open_story,
		"treasures_found": _treasures_found,
		"artifacts": _artifacts,
		"player_name": GameState.player_name,
		"world_seed": WorldManager.world_seed,
		"casting": casting
	}

func load_from(data: Dictionary) -> void:
	if data.is_empty() or eras.is_empty():
		return
	active = bool(data.get("active", true))
	finished = bool(data.get("finished", false))
	era_index = int(data.get("era_index", 0))
	_intro_played = true
	current_beat_id = str(data.get("current_beat_id", ""))
	progress = float(data.get("progress", 0.5))
	task_complete = bool(data.get("task_complete", false))
	era_kind = int(data.get("era_kind", EraKind.STABLE))
	era_hours_left = float(data.get("era_hours_left", 0.0))
	danger_hours_left = float(data.get("danger_hours_left", 0.0))
	doom_progress = float(data.get("doom_progress", 0.0))
	_doom_day_accum = float(data.get("doom_day_accum", 0.0))
	_chaos_days_total = int(data.get("chaos_days_total", 0))
	_doom_hot_days = int(data.get("doom_hot_days", 0))
	_doom_cold_days = int(data.get("doom_cold_days", 0))
	_doom_warned_stage = int(data.get("doom_warned_stage", 0))
	destroyed_count = int(data.get("destroyed_count", 0))
	truth = float(data.get("truth", 0.0))
	var saved_clues = data.get("clues", [])
	clues.clear()
	for c in saved_clues:
		clues.append(str(c))
	objective_complete = bool(data.get("objective_complete", false))
	objective_index = int(data.get("objective_index", 0))
	dehydrated = bool(data.get("dehydrated", false))
	dehydrate_pending = bool(data.get("dehydrate_pending", false))
	PlayerGodController.set_movement_lock(dehydrated)
	open_story = bool(data.get("open_story", true))
	_treasures_found = int(data.get("treasures_found", 0))
	var saved_artifacts = data.get("artifacts", [])
	_artifacts.clear()
	for a in saved_artifacts:
		_artifacts.append(str(a))
	var saved_name := str(data.get("player_name", ""))
	if saved_name != "":
		GameState.player_name = saved_name
	WorldManager.world_seed = int(data.get("world_seed", 7))
	var saved_casting = data.get("casting", {})
	casting = saved_casting if saved_casting is Dictionary else {}

func after_load() -> void:
	if not active or finished or era_index < 0 or era_index >= eras.size():
		return
	_intro_active = false
	_pending_intro_beat = ""
	_hot_accum = 0.0
	_cold_accum = 0.0
	_stable_accum = 0.0
	_era_wall_time = 0.0
	_ai_beat_active = false
	_ai_request_pending = false
	_ai_beat = {}
	_ai_event_then = Callable()
	_ai_event_cooldown = 8.0
	_last_favor_text = ""
	current_era = eras[era_index]
	if story_ui != null:
		story_ui.hide_era_intro()
	objective_points = (current_era.get("objective", {}) as Dictionary).get("points", [])
	_spawn_story_world(current_era)
	if sky != null:
		sky.apply_era(_era_state_name())
		sky.apply_era_style(str(current_era.get("id", "")), current_era.get("palette", {}))
	_spawn_objective_beacons(objective_index)
	figure = CharacterManager.get_character("story_figure")
	companion = CharacterManager.get_character("story_companion")
	player = CharacterManager.get_character("story_player")
	# 旧存档兼容：无玩家化身时补建
	if player == null or not is_instance_valid(player):
		player = _spawn_story_character("story_player", {}, _story_pos(), true)
	if figure != null and is_instance_valid(figure):
		figure.llm_busy = true
		figure.current_action = {}
		figure.moving = false
	if companion != null and is_instance_valid(companion):
		companion.llm_busy = true
		companion.current_action = {}
		companion.moving = false
	if player != null and is_instance_valid(player):
		PlayerGodController.possess(player)
	# 读档后把排片表应用到在场角色（形象/声音即时生效）
	apply_casting_to_live_characters()
	if story_ui != null:
		story_ui.setup_era(current_era, destroyed_count, truth, clues)
		story_ui.set_progress(progress)
		story_ui.set_truth(truth, clues)
		story_ui.set_doom_progress(doom_progress)
		story_ui.apply_era_theme(_era_accent_color())
	_apply_era_audio()
	if open_story:
		_start_open_story()
	elif current_beat_id != "" and (current_era.get("beats", {}) as Dictionary).has(current_beat_id):
		_show_beat(current_beat_id)

func _era_state_name() -> String:
	match era_kind:
		EraKind.CHAOS_HOT:
			return "hot"
		EraKind.CHAOS_COLD:
			return "cold"
		EraKind.DESTROYED:
			return "destroyed"
		_:
			return "stable"
