extends Node
## 临时布局诊断：打印建筑/角色/资源的位置与姿态异常（埋地/倾斜/入水/离聚落过远）。

var frames := 0

func _ready() -> void:
	_run()

func _run() -> void:
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	CivilizationManager.initialize_factions()
	WorldManager.initialize_world($World)
	CharacterManager.spawn_initial_characters()
	UIManager.setup()
	PlayerGodController.setup_camera()
	TimeManager.set_time_scale(10.0)
	for i in 240:
		await get_tree().process_frame
	_dump()
	get_tree().quit(0)

func _dump() -> void:
	var r := TerrainGenerator.PLANET_RADIUS
	print("=== 行星半径 %d 周长 %.0fm ===" % [r, TAU * r])
	for fid in CivilizationManager.faction_centers:
		var c: Vector3 = CivilizationManager.faction_centers[fid]
		var h := WorldManager.surface_height_at(c)
		print("聚落 %s 方向 %s 地表高 %.1f" % [fid, str(c.normalized()), h])
	print("--- 建筑 ---")
	for b in WorldManager.buildings:
		var up := WorldManager.up_at(b.global_position)
		var tilt := rad_to_deg(b.global_basis.y.angle_to(up))
		var srf := r + WorldManager.surface_height_at(b.global_position)
		var depth := srf - b.global_position.length()
		print("%s %-10s r=%.1f 倾斜%.0f° 埋深%.2f" % [b.building_id, b.style, b.global_position.length(), tilt, depth])
	print("--- 角色 ---")
	for c in CharacterManager.all_characters():
		var up := WorldManager.up_at(c.global_position)
		var tilt := rad_to_deg(c.global_basis.y.angle_to(up))
		var srf := r + WorldManager.surface_height_at(c.global_position)
		var depth := srf - c.global_position.length()
		var in_water := WorldManager.surface_height_at(c.global_position) < TerrainGenerator.WATER_LEVEL
		var fid := c.character_data.faction_id
		var home := CivilizationManager.faction_centers.get(fid, Vector3.ZERO)
		var dist := c.global_position.distance_to(home)
		print("%s %s r=%.1f 倾斜%.0f° 离地%.2f 入水:%s 离家%.0fm" % [
			c.character_data.name, c.character_data.faction_id, c.global_position.length(), tilt, depth, in_water, dist
		])
	print("--- 资源 ---")
	var far_res := 0
	for n in WorldManager.resource_nodes:
		var best := INF
		for fid in CivilizationManager.faction_centers:
			best = minf(best, n.global_position.distance_to(CivilizationManager.faction_centers[fid]))
		if best > 3000.0:
			far_res += 1
	print("资源总数 %d，离家>3km 的 %d" % [WorldManager.resource_nodes.size(), far_res])
	print("--- 摇篮密度（聚落±500m 内的装饰数量） ---")
	for fid in CivilizationManager.faction_centers:
		var c: Vector3 = CivilizationManager.faction_centers[fid]
		var near := 0
		if WorldManager.world != null and WorldManager.world.has_node("Decorations"):
			for d in WorldManager.world.get_node("Decorations").get_children():
				var pos := (d as Node3D).global_position
				if pos.distance_to(c) < 500.0:
					near += 1
		print("%s 附近装饰 %d" % [fid, near])
