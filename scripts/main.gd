extends Node3D
## 主场景脚本：按开局选择的游戏模式初始化。
## 自由模拟：硅基文明沙盘；剧情模式：三体游戏（自动化身历史人物推动文明）。

func _ready() -> void:
	if GameState.is_story_mode():
		StoryModeManager.start_story($World)
	else:
		CivilizationManager.initialize_factions()
		WorldManager.initialize_world($World)
		CharacterManager.spawn_initial_characters()
		_setup_free_sim_sky()
	UIManager.setup()
	PlayerGodController.setup_camera()
	TimeManager.set_time_scale(float(ConfigManager.game_setting("time_scale_default", 1.0)))
	if GameState.is_story_mode():
		StoryModeManager.after_ui_ready()
	else:
		HistoryManager.log_event("world", "世界诞生", "女娲之镜中，新的硅基文明开始萌动。")
		GameState.unlock_achievement("observer")

## 自由模拟接入三体天空：三颗太阳按真实三体引力运行并驱动天象，
## 不创建导演/巡览相机等任何过场系统；隐藏单一日光并停用旧天气，
## 避免与三日天空的光照、粒子特效相互冲突。
func _setup_free_sim_sky() -> void:
	var sky := ThreeBodySky.new()
	sky.name = "ThreeBodySky"
	$World.add_child(sky)
	sky.setup($World, false)
	sky.auto_era = true
	if $World.has_node("DirectionalLight"):
		$World.get_node("DirectionalLight").visible = false
	if $World.weather != null:
		$World.weather.set_process(false)
