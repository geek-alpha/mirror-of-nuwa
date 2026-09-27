extends Node
## 世界管理器：地形生成、资源/建筑/生态区管理、坐标工具、序列化。
## 剧情模式下按纪元主题生成地形、道具与装饰，让每张地图都有独特的“古文明 × 先进科技”气质。
var world: Node3D = null
var terrain_gen: TerrainGenerator = null
var resource_nodes: Array = []
var buildings: Array = []
var world_seed: int = 42
var initialized := false
var weather: WeatherSystem = null

var _world_theme: Dictionary = {}

func _ready() -> void:
	world_seed = int(ConfigManager.game_setting("world_seed", 42))

func initialize_world(world_node: Node3D) -> void:
	world = world_node
	weather = world.weather
	generate_terrain()
	_adjust_faction_centers()
	spawn_resources()
	spawn_initial_buildings()
	_spawn_decorations()
	initialized = true
	EventBus.world_regenerated.emit()

func weather_name() -> String:
	return weather.weather_name() if weather != null else "晴朗"

func weather_serialize() -> Dictionary:
	return weather.serialize() if weather != null else {}

func weather_load(data: Dictionary) -> void:
	if weather != null:
		weather.load_from(data)

func _era_theme(era: Dictionary) -> Dictionary:
	## 剧情纪元主题：只传 id，配色与科技浓度由 WorldDecorator 的主题表决定，
	## 地形生成器据此着色，装饰器据此挑选道具组合。
	var theme := WorldDecorator.theme_for_era(str(era.get("id", "")))
	theme["id"] = str(era.get("id", ""))
	return theme

func generate_terrain(theme: Dictionary = {}) -> void:
	if world == null:
		return
	_clear_container("Terrain")
	_world_theme = theme
	terrain_gen = TerrainGenerator.new()
	var terrain_node := terrain_gen.generate(world_seed, theme)
	world.get_node("Terrain").add_child(terrain_node)

func _clear_container(container_name: String) -> void:
	if world == null or not world.has_node(container_name):
		return
	var container := world.get_node(container_name)
	for child in container.get_children():
		# 立即移出场景树再释放：重建世界时若沿用 queue_free，旧对象与同帧新建对象共存一帧，
		# 物理/渲染负载翻倍造成卡顿
		if child.get_parent() != null:
			child.get_parent().remove_child(child)
		child.queue_free()

func _spawn_decorations(theme: Dictionary = {}, objective_points: Array = []) -> void:
	if world == null:
		return
	var container: Node3D = null
	if world.has_node("Decorations"):
		container = world.get_node("Decorations")
	else:
		container = Node3D.new()
		container.name = "Decorations"
		world.add_child(container)
	var decorator := WorldDecorator.new()
	world.add_child(decorator)
	decorator.set_objective_points(objective_points)
	decorator.generate(world_seed, container, theme)
	decorator.queue_free()

func spawn_era_world(era: Dictionary) -> void:
	## 剧情模式按纪元重建世界：资源 + 装饰均按该纪元的主题生成。
	if world == null or terrain_gen == null:
		return
	var theme := _era_theme(era)
	var objective_points: Array = []
	var obj: Dictionary = era.get("objective", {})
	for pt in (obj.get("points", []) as Array):
		var pos_arr: Array = pt.get("pos", [0.0, 0.0, 0.0])
		objective_points.append(Vector3(float(pos_arr[0]), 0, float(pos_arr[2])))
	_clear_container("ResourceNodes")
	resource_nodes.clear()
	_clear_container("Decorations")
	spawn_resources(theme)
	_spawn_decorations(theme, objective_points)

func place_era_landmark(pos: Vector3, kind: String = "monument") -> void:
	## 在剧情坐标放置主题地标（供任务点/关键场景使用）。
	if world == null or not world.has_node("Decorations"):
		return
	var container := world.get_node("Decorations")
	var decorator := WorldDecorator.new()
	world.add_child(decorator)
	decorator.prepare(container, _world_theme)
	decorator.place_landmark(pos, kind)
	decorator.queue_free()

func _adjust_faction_centers() -> void:
	## 在预设落脚点附近寻找平坦、干燥、生态合适的地点作为建村位置
	for fid in CivilizationManager.faction_centers:
		var base: Vector3 = CivilizationManager.faction_centers[fid]
		CivilizationManager.faction_centers[fid] = _find_village_site(base)

func _find_village_site(base: Vector3) -> Vector3:
	var best := clamp_point(base)
	var best_score := INF
	var half := TerrainGenerator.WORLD_SIZE / 2.0 - 5.0
	for i in 140:
		var p := base + Vector3(randf_range(-30.0, 30.0), 0.0, randf_range(-30.0, 30.0))
		p.x = clampf(p.x, -half, half)
		p.z = clampf(p.z, -half, half)
		if terrain_gen == null:
			break
		var h := get_terrain_height(p.x, p.z)
		if h < TerrainGenerator.WATER_LEVEL + 1.0:
			continue
		var slope := terrain_gen.slope_at(p.x, p.z)
		var biome := terrain_gen.biome_at(p.x, p.z)
		var score := slope * 8.0
		score += absf(h - 4.0) * 0.25
		if biome == TerrainGenerator.BIOME_MOUNTAINS or biome == TerrainGenerator.BIOME_WETLANDS:
			score += 12.0
		elif biome == TerrainGenerator.BIOME_SAVANNA or biome == TerrainGenerator.BIOME_FOREST:
			score -= 2.0
		score += Vector2(p.x, p.z).distance_to(Vector2(base.x, base.z)) * 0.04
		if score < best_score:
			best_score = score
			best = Vector3(p.x, h, p.z)
	return best

func clear_world_objects() -> void:
	resource_nodes.clear()
	buildings.clear()
	_clear_container("ResourceNodes")
	_clear_container("Buildings")
	_clear_container("Terrain")
	_clear_container("Characters")
	_clear_container("Decorations")
	terrain_gen = null
	initialized = false

func get_terrain_height(x: float, z: float) -> float:
	if terrain_gen == null:
		return 0.0
	return terrain_gen.height_at(x, z)

func biome_name_at(position: Vector3) -> String:
	if terrain_gen == null:
		return Enums.BIOME_NAMES[0]
	var idx := terrain_gen.biome_at(position.x, position.z)
	return Enums.BIOME_NAMES[clampi(idx, 0, Enums.BIOME_NAMES.size() - 1)]

func clamp_point(p: Vector3, clearance: float = 0.0) -> Vector3:
	var half := TerrainGenerator.WORLD_SIZE / 2.0 - 3.0
	p.x = clampf(p.x, -half, half)
	p.z = clampf(p.z, -half, half)
	p.y = get_terrain_height(p.x, p.z) + clearance
	return p

func random_point_near(position: Vector3, radius: float) -> Vector3:
	return clamp_point(position + Vector3(randf_range(-radius, radius), 0.0, randf_range(-radius, radius)))

func _resource_color(res_type: String) -> Color:
	match res_type:
		"energy_crystal":
			return Color(0.2, 0.8, 1.0)
		"metal":
			return Color(0.7, 0.72, 0.82)
		"data_shard":
			return Color(0.8, 0.3, 1.0)
		"biomass":
			return Color(0.3, 0.9, 0.45)
		"rare_metal":
			return Color(1.0, 0.9, 0.25)
		_:
			return Color(0.8, 0.8, 0.8)

func spawn_resource_node(res_type: String, res_name: String, amount: float, position: Vector3) -> ResourceNode:
	if world == null:
		return null
	var scene := preload("res://scenes/resource_node.tscn")
	var node: ResourceNode = scene.instantiate()
	world.get_node("ResourceNodes").add_child(node)
	node.setup(res_type, res_name, amount, clamp_point(position), _resource_color(res_type))
	resource_nodes.append(node)
	return node

func _resource_weight(era_id: String, res_type: String) -> float:
	## 纪元资源倾向：让每个文明地图的“富矿”不同，增加探索差异。
	match era_id:
		"era_wenwang":
			match res_type:
				"metal": return 1.5
				"energy_crystal": return 0.8
				"data_shard": return 0.7
		"era_mozi":
			match res_type:
				"metal": return 1.6
				"data_shard": return 1.4
				"rare_metal": return 1.3
		"era_qinshihuang":
			match res_type:
				"rare_metal": return 1.6
				"biomass": return 1.5
				"energy_crystal": return 1.2
		"era_newton":
			match res_type:
				"data_shard": return 1.7
				"rare_metal": return 1.4
				"metal": return 1.2
		"era_einstein":
			match res_type:
				"rare_metal": return 1.6
				"data_shard": return 1.5
				"energy_crystal": return 1.2
	return 1.0

func spawn_resources(theme: Dictionary = {}) -> void:
	var era_id := str(theme.get("id", ""))
	var defs := [
		{"type": "energy_crystal", "name": "能量晶体", "count": 30, "amount": 60.0, "biomes": [TerrainGenerator.BIOME_WETLANDS, TerrainGenerator.BIOME_MOUNTAINS, TerrainGenerator.BIOME_PLAINS, TerrainGenerator.BIOME_RELIC]},
		{"type": "metal", "name": "金属矿石", "count": 16, "amount": 40.0, "biomes": [TerrainGenerator.BIOME_MOUNTAINS, TerrainGenerator.BIOME_SAVANNA, TerrainGenerator.BIOME_PLAINS]},
		{"type": "data_shard", "name": "数据碎片", "count": 10, "amount": 25.0, "biomes": [TerrainGenerator.BIOME_MOUNTAINS, TerrainGenerator.BIOME_FOREST, TerrainGenerator.BIOME_SAVANNA, TerrainGenerator.BIOME_RELIC]},
		{"type": "biomass", "name": "生物质", "count": 12, "amount": 35.0, "biomes": [TerrainGenerator.BIOME_PLAINS, TerrainGenerator.BIOME_FOREST, TerrainGenerator.BIOME_WETLANDS]},
		{"type": "rare_metal", "name": "稀有元素", "count": 6, "amount": 10.0, "biomes": [TerrainGenerator.BIOME_MOUNTAINS, TerrainGenerator.BIOME_FOREST, TerrainGenerator.BIOME_RELIC]}
	]
	var all_placed: Array = []
	for def in defs:
		var count := int(float(def["count"]) * _resource_weight(era_id, str(def["type"])))
		var placed_type: Array = []
		for i in count:
			for attempt in 60:
				var pos := Vector3(randf_range(-74, 74), 0.0, randf_range(-74, 74))
				if terrain_gen == null:
					break
				var biome := terrain_gen.biome_at(pos.x, pos.z)
				if not (def["biomes"] as Array).has(biome):
					continue
				if terrain_gen.is_water(pos.x, pos.z):
					continue
				if terrain_gen.slope_at(pos.x, pos.z) > 0.55:
					continue
				# 避免挤在一起：同类型至少 5m，全局至少 2.5m
				if _pos_near(pos, placed_type, 5.0) or _pos_near(pos, all_placed, 2.5):
					continue
				var node := spawn_resource_node(str(def["type"]), str(def["name"]), float(def["amount"]), pos)
				if node != null:
					placed_type.append(pos)
					all_placed.append(pos)
				break

func _pos_near(pos: Vector3, positions: Array, radius: float) -> bool:
	for p in positions:
		if Vector2(pos.x - p.x, pos.z - p.z).length() < radius:
			return true
	return false

func spawn_building(building_id: String, faction_id: String, position: Vector3) -> Building:
	if world == null or not CivilizationManager.building_defs.has(building_id):
		return null
	var def: Dictionary = CivilizationManager.building_defs[building_id]
	var scene := preload("res://scenes/building.tscn")
	var b: Building = scene.instantiate()
	world.get_node("Buildings").add_child(b)
	var color := CivilizationManager.faction_color(faction_id)
	b.setup(def, faction_id, clamp_point(position), color)
	buildings.append(b)
	return b

func spawn_initial_buildings() -> void:
	var centers := CivilizationManager.faction_centers
	var angles := [0.0, PI * 0.7, PI * 1.4]
	for fid in centers:
		var center: Vector3 = centers[fid]
		# 祭台居中，篝火在旁，图腾守门
		spawn_building("building_altar", fid, center + Vector3(0, 0, 0))
		spawn_building("building_bonfire", fid, center + Vector3(2.7, 0, 2.3))
		var house_count := 3 if fid == "faction_crystal_dawn" else 2
		for i in house_count:
			var ang: float = float(angles[i]) + (0.0 if fid == "faction_crystal_dawn" else 0.9)
			var off := Vector3(cos(ang), 0.0, sin(ang)) * 9.0
			spawn_building("building_house", fid, center + off)
		spawn_building("building_workshop", fid, center + Vector3(cos(2.2) * 10.5, 0, sin(2.2) * 10.5))
		spawn_building("building_totem", fid, center + Vector3(-7.6, 0, 0))
		if fid == "faction_crystal_dawn":
			spawn_building("building_temple", fid, center + Vector3(cos(4.1) * 11.5, 0, sin(4.1) * 11.5))
		else:
			spawn_building("building_lab", fid, center + Vector3(cos(4.1) * 11.5, 0, sin(4.1) * 11.5))

func unregister_resource(node: ResourceNode) -> void:
	resource_nodes.erase(node)

func find_resource_by_name(res_name: String) -> ResourceNode:
	for node in resource_nodes:
		if node.resource_name == res_name or node.resource_id == res_name:
			return node
	return null

func nearest_building_of_function(position: Vector3, function: String) -> Building:
	var best: Building = null
	var best_dist := INF
	for b in buildings:
		if b.function != function:
			continue
		var d: float = b.global_position.distance_to(position)
		if d < best_dist:
			best_dist = d
			best = b
	return best

func serialize_resources() -> Array:
	var out: Array = []
	for node in resource_nodes:
		out.append(node.to_save_dict())
	return out

func serialize_buildings() -> Array:
	var out: Array = []
	for b in buildings:
		out.append(b.to_save_dict())
	return out

func load_resources(data: Array) -> void:
	_clear_container("ResourceNodes")
	resource_nodes.clear()
	for item in data:
		var pos: Array = item.get("position", [0.0, 0.0, 0.0])
		spawn_resource_node(
			str(item.get("id", "energy_crystal")),
			str(item.get("name", "能量晶体")),
			float(item.get("amount", 50.0)),
			Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		)

func load_buildings(data: Array) -> void:
	_clear_container("Buildings")
	buildings.clear()
	for item in data:
		var pos: Array = item.get("position", [0.0, 0.0, 0.0])
		var b := spawn_building(str(item.get("id", "building_house")), str(item.get("faction_id", "")), Vector3(float(pos[0]), float(pos[1]), float(pos[2])))
		if b != null:
			b.durability = float(item.get("durability", b.max_durability))
