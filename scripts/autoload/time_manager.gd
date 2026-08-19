extends Node
## 时间管理器：游戏时间（小时），可暂停与倍速（1x/10x/100x/1000x）。
## 游戏日历按 24 小时一天、365 天一“年”计算，纪元随天数推进。

var game_time: float = 0.0
var time_scale: float = 1.0
var paused := false
var seconds_per_game_hour: float = 6.0

func _ready() -> void:
	seconds_per_game_hour = float(ConfigManager.game_setting("seconds_per_game_hour", 6.0))

func _process(delta: float) -> void:
	if paused or time_scale <= 0.0:
		return
	var prev_day := get_day()
	game_time += delta * time_scale / seconds_per_game_hour
	if get_day() != prev_day:
		EventBus.day_changed.emit(get_day())

func delta_game_hours(delta: float) -> float:
	if paused or time_scale <= 0.0:
		return 0.0
	return delta * time_scale / seconds_per_game_hour

func set_time_scale(scale: float) -> void:
	time_scale = scale
	paused = scale <= 0.0
	EventBus.time_scale_changed.emit(time_scale)

func get_hour() -> int:
	return int(floor(game_time)) % 24

func get_day() -> int:
	return int(floor(game_time / 24.0))

func get_year() -> int:
	return int(floor(game_time / (24.0 * 365.0)))

func get_era() -> String:
	var days := get_day()
	if days < 30:
		return "创世纪"
	if days < 120:
		return "萌芽纪"
	if days < 400:
		return "兴盛纪"
	if days < 1000:
		return "纷争纪"
	return "奇点纪"

func date_text() -> String:
	var y := get_year() + 1
	var d := get_day() % 365 + 1
	var h := get_hour()
	return "%s 第%d年 %d日 %02d:00" % [get_era(), y, d, h]

func time_of_day_text() -> String:
	var h := get_hour()
	if h < 6:
		return "深夜"
	if h < 10:
		return "清晨"
	if h < 16:
		return "白昼"
	if h < 20:
		return "黄昏"
	return "夜晚"
