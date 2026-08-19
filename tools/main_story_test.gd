extends Node
## 验证 main.tscn 在剧情模式下的完整接线：
## start_story → UIManager.setup → setup_camera → after_ui_ready。
## 用法：godot --headless --path . res://tools/main_story_test.tscn

var frames := 0
var done := false

func _ready() -> void:
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	StoryModeManager.boot_duration = 0.05
	StoryModeManager.cinematic_duration = 0.05
	StoryModeManager.transition_duration = 0.05
	StoryModeManager.era_cutscene_duration = 0.05
	# 无头测试关闭导演演出，保证帧时序确定（演出本身在真实运行时启用）
	StoryModeManager.cinematic_enabled = false
	GameState.game_mode = GameState.MODE_STORY
	GameState.player_name = "测试者"
	# 固定从第一纪（周文王）开始，避免用户配置的起始文明影响断言
	ConfigManager.set_game_setting("story_start_era", "era_wenwang")
	var packed: PackedScene = load("res://scenes/main.tscn")
	add_child(packed.instantiate())

func _process(_delta: float) -> void:
	frames += 1
	if frames < 80 or done:
		return
	# 引言幕出现后手动结束引言（无过场模式），触发玩家加载
	if StoryModeManager._intro_active:
		if frames > 300:
			StoryModeManager._on_intro_finished()
		return
	if StoryModeManager.player == null:
		if frames > 600:
			push_error("玩家未在引言后加载")
			get_tree().quit(1)
		return
	done = true
	var ok: bool = StoryModeManager.active \
		and StoryModeManager.era_index == 0 \
		and GameState.mode == GameState.Mode.POSSESS \
		and StoryModeManager.figure != null \
		and StoryModeManager.figure.character_data.name == "周文王" \
		and StoryModeManager.player != null \
		and StoryModeManager.player.character_data.name == GameState.player_name \
		and GameState.possessed_character == StoryModeManager.player \
		and UIManager.story_ui != null and UIManager.story_ui.visible
	print("MAIN_STORY: %s" % ("PASS" if ok else "FAIL"))
	print("MAIN_STORY: active=%s era=%d mode=%d figure=%s ui_visible=%s" % [
		StoryModeManager.active, StoryModeManager.era_index, GameState.mode,
		StoryModeManager.figure.character_data.name if StoryModeManager.figure != null else "null",
		UIManager.story_ui != null and UIManager.story_ui.visible
	])
	get_tree().quit(0 if ok else 1)
