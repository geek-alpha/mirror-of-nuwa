class_name WeatherSystem
extends Node
## 天气系统：随机切换晴/雨/风暴/能量风暴/晶体尘暴，影响角色感知，附粒子效果。
## 风暴附带雷电（强光爆闪+雷声），能量风暴附带绿色电弧爆闪，尘暴为横扫沙砾。

enum Weather { CLEAR, RAIN, STORM, ENERGY_STORM, DUST }

var current: int = Weather.CLEAR
var effects_container: Node3D = null
var next_change_hour: float = 0.0
var rain: CPUParticles3D = null
var _strike_timer := 0.0

func _ready() -> void:
	next_change_hour = TimeManager.game_time + 6.0 + randf() * 6.0

func _process(delta: float) -> void:
	if TimeManager.game_time >= next_change_hour:
		_change_weather()
		next_change_hour = TimeManager.game_time + 6.0 + randf() * 8.0
	if current == Weather.STORM or current == Weather.ENERGY_STORM:
		_strike_timer -= delta
		if _strike_timer <= 0.0:
			_strike_timer = randf_range(3.5, 9.0)
			_strike()

func _change_weather() -> void:
	var roll := randf()
	if roll < 0.5:
		current = Weather.CLEAR
	elif roll < 0.7:
		current = Weather.RAIN
	elif roll < 0.85:
		current = Weather.STORM
	elif roll < 0.95:
		current = Weather.ENERGY_STORM
	else:
		current = Weather.DUST
	_strike_timer = randf_range(2.0, 6.0)
	_update_visual()

func _strike() -> void:
	## 风暴雷电 / 能量风暴电弧：高空强光爆闪 + 雷声
	if effects_container == null:
		return
	var energy := current == Weather.ENERGY_STORM
	var l := OmniLight3D.new()
	l.light_color = Color(0.3, 1.0, 0.8) if energy else Color(0.85, 0.9, 1.0)
	l.light_energy = 10.0
	l.omni_range = 60.0
	l.shadow_enabled = false
	l.position = Vector3(randf_range(-30.0, 30.0), 42.0, randf_range(-30.0, 30.0))
	effects_container.add_child(l)
	var t := get_tree().create_timer(0.12)
	t.timeout.connect(func():
		if l != null and is_instance_valid(l):
			l.light_energy = 0.0
	)
	var t2 := get_tree().create_timer(0.24)
	t2.timeout.connect(func():
		if l != null and is_instance_valid(l):
			l.queue_free()
	)
	if AudioManager != null:
		AudioManager.play("discharge", -8.0, randf_range(0.7, 1.1))
		AudioManager.play("whoosh", -10.0, 0.6)

func _update_visual() -> void:
	if rain != null:
		rain.queue_free()
		rain = null
	if effects_container == null:
		return
	match current:
		Weather.RAIN, Weather.STORM, Weather.ENERGY_STORM:
			rain = CPUParticles3D.new()
			rain.name = "Precipitation"
			rain.amount = 600 if current == Weather.RAIN else 1400
			rain.lifetime = 2.0
			rain.one_shot = false
			rain.emitting = true
			rain.direction = Vector3(0.25 if current != Weather.RAIN else 0.0, -1, 0).normalized()
			rain.spread = 12.0
			rain.gravity = Vector3(0, -25, 0)
			rain.initial_velocity_min = 9.0
			rain.initial_velocity_max = 16.0
			rain.scale_amount_min = 0.04
			rain.scale_amount_max = 0.1
			rain.position = Vector3(0, 28, 0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.7, 0.8, 1.0) if current != Weather.ENERGY_STORM else Color(0.3, 1.0, 0.8)
			mat.emission_enabled = true
			mat.emission = mat.albedo_color
			mat.emission_energy_multiplier = 1.2
			rain.material_override = mat
			effects_container.add_child(rain)
		Weather.DUST:
			rain = CPUParticles3D.new()
			rain.name = "DustStorm"
			rain.amount = 1100
			rain.lifetime = 3.2
			rain.one_shot = false
			rain.emitting = true
			rain.direction = Vector3(1.0, 0.12, -0.35).normalized()
			rain.spread = 8.0
			rain.gravity = Vector3(0, -3.5, 0)
			rain.initial_velocity_min = 10.0
			rain.initial_velocity_max = 24.0
			rain.scale_amount_min = 0.06
			rain.scale_amount_max = 0.3
			rain.position = Vector3(-20, 14, 0)
			var dmat := StandardMaterial3D.new()
			dmat.albedo_color = Color(0.82, 0.68, 0.45, 0.85)
			dmat.emission_enabled = true
			dmat.emission = Color(0.5, 0.38, 0.2)
			dmat.emission_energy_multiplier = 0.35
			dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rain.material_override = dmat
			effects_container.add_child(rain)
			if AudioManager != null:
				AudioManager.play("whoosh", -12.0, 0.5)

func weather_name() -> String:
	match current:
		Weather.CLEAR:
			return "晴朗"
		Weather.RAIN:
			return "雨"
		Weather.STORM:
			return "风暴"
		Weather.ENERGY_STORM:
			return "能量风暴"
		Weather.DUST:
			return "晶体尘暴"
	return "晴朗"

func serialize() -> Dictionary:
	return {"current": current}

func load_from(data: Dictionary) -> void:
	current = int(data.get("current", Weather.CLEAR))
	_update_visual()
