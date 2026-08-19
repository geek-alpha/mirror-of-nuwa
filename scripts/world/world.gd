extends Node3D
## 世界场景脚本：组织地形/资源/建筑/角色容器，并挂载昼夜与天气系统。

var terrain_container: Node3D
var resource_container: Node3D
var building_container: Node3D
var character_container: Node3D
var effects_container: Node3D
var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var weather: WeatherSystem

func _ready() -> void:
	terrain_container = $Terrain
	resource_container = $ResourceNodes
	building_container = $Buildings
	character_container = $Characters
	effects_container = $Effects
	sun = $DirectionalLight
	world_environment = $WorldEnvironment
	var day_night := DayNightCycle.new()
	day_night.sun = sun
	add_child(day_night)
	var weather := WeatherSystem.new()
	add_child(weather)
	weather.effects_container = effects_container
	self.weather = weather
