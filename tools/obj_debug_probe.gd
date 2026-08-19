extends Node
## 临时调试：按 story_smoke_test 的精确时序（步骤0-7），观察 gate 后 objective（用完即删）
var frames := 0
var step := 0

func _ready() -> void:
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	TTSManager.enabled = false
	GameState.game_mode = GameState.MODE_STORY
	StoryModeManager.boot_duration = 0.05
	StoryModeManager.cinematic_duration = 0.05
	StoryModeManager.transition_duration = 0.05
	StoryModeManager.destroy_cutscene_duration = 0.05
	StoryModeManager.hot_cutscene_duration = 0.05
	StoryModeManager.cold_cutscene_duration = 0.05
	StoryModeManager.stable_cutscene_duration = 0.05
	StoryModeManager.era_cutscene_duration = 0.05
	StoryModeManager.cinematic_enabled = false
	CivilizationManager.initialize_factions()
	WorldManager.initialize_world($World)
	StoryModeManager.open_story = false
	StoryModeManager.auto_advance_enabled = false
	ConfigManager.set_game_setting("story_start_era", "era_wenwang")
	StoryModeManager.start_story($World)
	UIManager.setup()
	PlayerGodController.setup_camera()
	StoryModeManager.after_ui_ready()

func _process(_delta: float) -> void:
	frames += 1
	if frames > 900:
		print("DBG: TIMEOUT at step=%d beat=%s" % [step, StoryModeManager.current_beat_id])
		get_tree().quit(2)
		return
	match step:
		0:
			if frames >= 25 and StoryModeManager._intro_active:
				StoryModeManager._on_intro_finished()
				step = 1
		1:
			if frames >= 45:
				StoryModeManager._on_continue()
				step = 2
		2:
			if frames >= 60:
				StoryModeManager._on_choice(0)
				step = 3
		3:
			if frames >= 75:
				StoryModeManager._on_continue()
				step = 4
		4:
			if frames >= 90:
				StoryModeManager._on_continue()
				step = 5
		5:
			if frames >= 105:
				print("DBG: choice at beat=%s" % StoryModeManager.current_beat_id)
				StoryModeManager._on_choice(0)
				step = 6
		6:
			if frames >= 120:
				print("DBG: gate beat=%s obj_active=%s idx=%d intro=%s wake=%s journey=%s player=%s" % [StoryModeManager.current_beat_id, StoryModeManager.objective_active, StoryModeManager.objective_index, StoryModeManager._intro_active, StoryModeManager._wake_active, StoryModeManager._journey_active, StoryModeManager.player.global_position])
				var pt: Dictionary = StoryModeManager.objective_points[0]
				var pos_arr: Array = pt.get("pos", [0.0, 0.0, 0.0])
				var target := WorldManager.clamp_point(Vector3(float(pos_arr[0]), 0, float(pos_arr[2])), 0.95)
				print("DBG: target=%s dist=%.2f" % [target, StoryModeManager.player.global_position.distance_to(target)])
				StoryModeManager.player.global_position = target
				StoryModeManager.player.velocity = Vector3.ZERO
				step = 7
		7:
			if frames % 2 == 0:
				print("DBG: t%d beat=%s obj_active=%s idx=%d intro=%s wake=%s journey=%s player=%s" % [frames, StoryModeManager.current_beat_id, StoryModeManager.objective_active, StoryModeManager.objective_index, StoryModeManager._intro_active, StoryModeManager._wake_active, StoryModeManager._journey_active, StoryModeManager.player.global_position])
			if frames >= 150:
				get_tree().quit(0)