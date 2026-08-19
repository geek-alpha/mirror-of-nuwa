extends Node
## 游戏状态：当前模式（上帝/化身）、选中对象、成就。运行时注册输入映射。

enum Mode { GOD, POSSESS }

## 开局选择的游戏模式
const MODE_FREE_SIM := "free_sim"
const MODE_STORY := "story"

var mode: int = Mode.GOD
var game_mode: String = MODE_FREE_SIM
## 剧情模式玩家化身名字（开局界面可自选，角色会以此称呼玩家）
var player_name := "旅人"
var selected_character = null
var selected_object = null
var possessed_character = null
var camera: Camera3D = null
## 过场/演出期间锁定玩家输入（由 CinematicDirector 接管/释放）
var input_locked := false
var achievements: Dictionary = {}
var pending_oracle: Dictionary = {}

func _ready() -> void:
	_setup_input_map()
	# 成就挂钩
	EventBus.player_intervention.connect(func(_cid, _kind, _detail): unlock_achievement("intervention"))
	EventBus.technology_discovered.connect(func(_f, _t, _n): unlock_achievement("witness"))
	EventBus.character_born.connect(_on_character_born)

func set_mode(new_mode: int) -> void:
	mode = new_mode
	EventBus.game_mode_changed.emit("god" if mode == Mode.GOD else "possess")

func is_story_mode() -> bool:
	return game_mode == MODE_STORY

func unlock_achievement(id: String) -> void:
	if achievements.has(id):
		return
	achievements[id] = true
	EventBus.achievement_unlocked.emit(id)

func _on_character_born(_character) -> void:
	if CharacterManager and CharacterManager.characters.size() >= 15:
		unlock_achievement("creator")

func _setup_input_map() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("fly_up", KEY_E)
	_add_key_action("fly_down", KEY_Q)
	_add_key_action("sprint", KEY_SHIFT)
	_add_key_action("interact", KEY_F)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("toggle_god_mode", KEY_G)
	_add_key_action("toggle_view_mode", KEY_V)
	_add_key_action("save_game", KEY_K)
	_add_key_action("load_game", KEY_L)
	_add_mouse_action("look", MOUSE_BUTTON_RIGHT)
	_add_mouse_action("click", MOUSE_BUTTON_LEFT)

func _add_key_action(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func _add_mouse_action(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
