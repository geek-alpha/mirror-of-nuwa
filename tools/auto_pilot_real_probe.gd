extends Node
## 真实配置自动模式验证：过场演出开启（cinematic_enabled=true），
## 验证自动抉择、拒绝脱水、自动跳过引言。
## 用法：godot --headless --path . res://tools/auto_pilot_real_probe.tscn

var frames := 0
var elapsed := 0.0
var intro_seen := false
var choice_seen := false
var choice_resolved := false
var dehydrate_triggered := false
var dehydrate_resolved := false
var doom_before := 0.0
var done := false

func _ready() -> void:
	Engine.max_fps = 60
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	GameState.game_mode = GameState.MODE_STORY
	GameState.player_name = "真实测试者"
	# 过场保持开启（与真实游戏一致），只缩短时长
	StoryModeManager.boot_duration = 0.3
	StoryModeManager.cinematic_duration = 0.8
	StoryModeManager.transition_duration = 0.4
	StoryModeManager.era_cutscene_duration = 0.4
	StoryModeManager.cinematic_enabled = true
	ConfigManager.set_game_setting("story_start_era", "era_wenwang")
	var packed: PackedScene = load("res://scenes/main.tscn")
	add_child(packed.instantiate())
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
	if sm.auto_choice_pending():
		choice_seen = true
	elif choice_seen and not sm._ai_beat_active:
		choice_resolved = true
	if choice_resolved and not dehydrate_triggered:
		dehydrate_triggered = true
		doom_before = sm.doom_progress
		sm.dehydrate_pending = true
	if dehydrate_triggered and not sm.dehydrate_pending:
		dehydrate_resolved = true
	if elapsed > 45.0 or frames > 3600:
		_finish()

func _finish() -> void:
	if done:
		return
	done = true
	var ok: bool = intro_seen and choice_seen and choice_resolved \
		and dehydrate_resolved and not StoryModeManager.dehydrated \
		and StoryModeManager.doom_progress > doom_before + 0.05
	print("AUTO_REAL: %s" % ("PASS" if ok else "FAIL"))
	print("AUTO_REAL: intro=%s choice=%s choice_ok=%s dehydrate=%s doom=%+.2f status=%s" % [
		intro_seen,
		choice_seen,
		choice_resolved,
		dehydrate_resolved,
		StoryModeManager.doom_progress - doom_before,
		AutoPilot.status_text()
	])
	get_tree().quit(0 if ok else 1)

func _fail(reason: String) -> void:
	if done:
		return
	done = true
	print("AUTO_REAL: FAIL - %s" % reason)
	get_tree().quit(1)
