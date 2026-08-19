extends SceneTree
## 一次性工具：把游戏输入映射写入 project.godot，便于在编辑器中查看与修改。
## 与 GameState._setup_input_map() 的运行时注册保持一致（物理键位）。
## 用法：godot --headless --path . -s res://tools/setup_input_map.gd

const KEY_ACTIONS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"fly_up": KEY_E,
	"fly_down": KEY_Q,
	"sprint": KEY_SHIFT,
	"interact": KEY_F,
	"jump": KEY_SPACE,
	"toggle_god_mode": KEY_G,
	"toggle_view_mode": KEY_V,
	"save_game": KEY_K,
	"load_game": KEY_L,
}

const MOUSE_ACTIONS := {
	"look": MOUSE_BUTTON_RIGHT,
	"click": MOUSE_BUTTON_LEFT,
}

func _initialize() -> void:
	for action in KEY_ACTIONS:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_ACTIONS[action]
		_set_action(action, [ev])
	for action in MOUSE_ACTIONS:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_ACTIONS[action]
		_set_action(action, [ev])
	ProjectSettings.save()
	print("Input map saved to project.godot")
	quit(0)

func _set_action(action: String, events: Array) -> void:
	ProjectSettings.set_setting("input/" + action, {
		"deadzone": 0.5,
		"events": events,
	})
