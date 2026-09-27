extends Node
## 存档管理器：JSON 序列化整个世界状态到 user://saves/，支持手动与自动保存。

const SAVE_DIR := "user://saves"
var autosave_path := "user://saves/autosave.json"
var last_save_path := ""
var autosave_enabled := true
## 自动存档去重：同一帧/同一天多次触发只写一次档（延迟到帧末执行）
var _autosave_queued := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	EventBus.day_changed.connect(_on_day_changed)

func _on_day_changed(_day: int) -> void:
	if autosave_enabled and not _autosave_queued:
		var interval := int(ConfigManager.game_setting("autosave_interval_game_days", 1))
		if TimeManager.get_day() % maxi(interval, 1) == 0:
			_autosave_queued = true
			_flush_autosave.call_deferred()

func _flush_autosave() -> void:
	_autosave_queued = false
	save_game(autosave_path)

func save_game(path: String = "") -> bool:
	if path == "":
		path = "user://saves/save_%d.json" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档：%s" % path)
		return false
	file.store_string(JSON.stringify(build_save_data(), "\t"))
	file.close()
	last_save_path = path
	EventBus.save_completed.emit(path)
	print("已保存到 ", path)
	return true

func build_save_data() -> Dictionary:
	var chars: Array = []
	for c in CharacterManager.all_characters():
		if c.character_data != null:
			var d: CharacterData = c.character_data
			d.location = c.global_position
			chars.append(d.to_save_dict())
	return {
		"version": 1,
		"game_time": TimeManager.game_time,
		"time_scale": TimeManager.time_scale,
		"world_seed": WorldManager.world_seed,
		"resources": WorldManager.serialize_resources(),
		"buildings": WorldManager.serialize_buildings(),
		"characters": chars,
		"civilization": CivilizationManager.serialize(),
		"history": HistoryManager.serialize(),
		"weather": WorldManager.weather_serialize(),
		"story": StoryModeManager.serialize() if GameState.is_story_mode() else {},
		"saved_date": Time.get_date_string_from_system()
	}

func load_game(path: String = "") -> bool:
	if path == "":
		path = last_save_path if last_save_path != "" else autosave_path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("没有找到存档：%s" % path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("存档格式错误：%s" % path)
		return false
	var data: Dictionary = parsed
	# 退出化身模式
	PlayerGodController.exit_possession()
	# 清理当前世界
	WorldManager.clear_world_objects()
	CharacterManager.clear_all()
	HistoryManager.clear()
	GameState.achievements.clear()
	# 恢复基础时间与世界
	TimeManager.game_time = float(data.get("game_time", 0.0))
	TimeManager.set_time_scale(float(data.get("time_scale", 1.0)))
	WorldManager.world_seed = int(data.get("world_seed", 42))
	WorldManager.generate_terrain()
	# 恢复文明（先于建筑，便于取派系颜色）
	CivilizationManager.load_from(data.get("civilization", {}))
	if CivilizationManager.faction_centers.is_empty():
		CivilizationManager.faction_centers = {
			"faction_crystal_dawn": Vector3(-25, 0, -25),
			"faction_abyss_flow": Vector3(30, 0, 20)
		}
	WorldManager.load_resources(data.get("resources", []))
	WorldManager.load_buildings(data.get("buildings", []))
	CharacterManager.load_characters(data.get("characters", []))
	WorldManager.weather_load(data.get("weather", {}))
	HistoryManager.load_from(data.get("history", {}))
	WorldManager.initialized = true
	if GameState.is_story_mode():
		StoryModeManager.load_from(data.get("story", {}))
		StoryModeManager.after_load()
	EventBus.load_completed.emit()
	print("已读取存档：%s" % path)
	return true

func list_saves() -> Array:
	var out: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			out.append(SAVE_DIR + "/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return out
