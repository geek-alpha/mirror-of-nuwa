extends Node
## 纪元观测探针：在真实游戏流程里观察天象势态与纪元切换是否正常。
## 用法：godot --headless --path . res://tools/era_watch_probe.tscn

var frames := 0
var last_kind := -1

func _ready() -> void:
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	GameState.game_mode = GameState.MODE_STORY
	GameState.player_name = "探针"
	StoryModeManager.boot_duration = 0.05
	StoryModeManager.cinematic_duration = 0.05
	StoryModeManager.transition_duration = 0.05
	StoryModeManager.arrival_duration = 0.1
	StoryModeManager.wake_duration = 0.1
	StoryModeManager.cinematic_enabled = false
	StoryModeManager.auto_advance_enabled = false
	StoryModeManager.open_story = true
	StoryModeManager.start_story($World)
	UIManager.setup()
	PlayerGodController.setup_camera()
	StoryModeManager.after_ui_ready()
	TimeManager.set_time_scale(1.0)

func _process(_delta: float) -> void:
	frames += 1
	# 自动结束引言/苏醒流程，进入开放剧情
	if frames == 20 and StoryModeManager._intro_active:
		StoryModeManager._on_intro_finished()
	# 自动结算出现的 AI 事件，保持流程干净
	if frames % 180 == 0 and StoryModeManager._ai_beat_active:
		StoryModeManager._on_choice(0)
	# 自动处理脱水抉择（真实游玩由玩家选择）
	if StoryModeManager.dehydrate_pending:
		StoryModeManager._on_dehydrate_chosen(true)
	if frames < 120:
		return
	if frames % 120 == 0:
		var sky = StoryModeManager.sky
		var tend := "无"
		var suns := 0
		if sky != null:
			tend = sky.era_tendency()
			suns = sky.visible_sun_count()
		var kind := StoryModeManager.era_kind
		var kind_names := ["恒纪元", "酷热", "严寒", "毁灭"]
		var kind_name: String = kind_names[kind] if kind >= 0 and kind <= 3 else str(kind)
		var changed := "（切换）" if kind != last_kind and last_kind != -1 else ""
		last_kind = kind
		print("WATCH: 帧=%d 纪元=%s 势态=%s 当空=%d 计时器=%.0fh dwell=%.1f wall=%.1f%s" % [
			frames, kind_name, tend, suns,
			StoryModeManager.era_hours_left,
			StoryModeManager._hot_accum,
			StoryModeManager._era_wall_time,
			changed
		])
	if frames > 60 * 60 * 4:
		print("WATCH: 观测结束")
		get_tree().quit()
