class_name DayNightCycle
extends Node
## 昼夜循环：根据游戏时间旋转太阳并调整光照强度。

var sun: DirectionalLight3D = null

func _process(_delta: float) -> void:
	if sun == null:
		return
	var hour := TimeManager.get_hour()
	sun.rotation_degrees.x = -90.0 + (hour - 12.0) * 15.0
	var frac := clampf((hour - 6.0) / 12.0, 0.0, 1.0)
	sun.light_energy = 0.08 + 1.5 * sin(frac * PI)
	if hour < 6 or hour > 20:
		sun.light_color = Color(0.35, 0.4, 0.7)
	elif hour < 8 or hour > 17:
		sun.light_color = Color(1.0, 0.65, 0.4)
	else:
		sun.light_color = Color(1.0, 0.95, 0.85)
