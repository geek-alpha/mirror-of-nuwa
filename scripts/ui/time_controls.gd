class_name TimeControls
extends Control
## 时间控制条：暂停与倍速切换、时间与天气显示。

var time_label: Label
var weather_label: Label

func _ready() -> void:
	anchor_left = 0.5
	anchor_top = 0.0
	anchor_right = 0.5
	anchor_bottom = 0.0
	offset_left = -320
	offset_top = 10
	offset_right = 320
	offset_bottom = 54
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 44)
	add_child(panel)
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)
	var scales := [0.0, 1.0, 10.0, 100.0, 1000.0]
	var labels := ["⏸", "1x", "10x", "100x", "1000x"]
	for i in scales.size():
		var btn := Button.new()
		btn.text = labels[i]
		btn.custom_minimum_size = Vector2(58, 0)
		var scale_val: float = scales[i]
		btn.pressed.connect(func(): TimeManager.set_time_scale(scale_val))
		hbox.add_child(btn)
	time_label = Label.new()
	time_label.custom_minimum_size = Vector2(240, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(time_label)
	weather_label = Label.new()
	weather_label.custom_minimum_size = Vector2(90, 0)
	hbox.add_child(weather_label)
	refresh()

func refresh() -> void:
	if time_label == null:
		return
	var speed := "暂停" if TimeManager.time_scale <= 0.0 else "%.0fx" % TimeManager.time_scale
	time_label.text = "%s  %s" % [TimeManager.date_text(), speed]
	weather_label.text = WorldManager.weather_name()
