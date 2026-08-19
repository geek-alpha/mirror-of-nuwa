extends Node
## 纪元世界生成无头探针：遍历剧情纪元，独立生成地形/装饰，并经由 WorldManager
## 重建真实世界（资源 + 装饰），打印每张地图的随机性与密度统计。
## 用法：godot --headless --path . res://tools/era_world_probe.tscn

func _ready() -> void:
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	_run()

func _run() -> void:
	var text := FileAccess.get_file_as_string("res://resources/data/three_body_story.json")
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("剧情数据解析失败")
		get_tree().quit(1)
		return
	var eras: Array = parsed.get("eras", [])
	print("ERAS: %d" % eras.size())
	for era in eras:
		var era_id := str(era.get("id", ""))
		var seed := int(era.get("seed", 7))
		var theme := WorldDecorator.theme_for_era(era_id)
		print("=== %s seed=%d accent=%s tech=%.2f density=%.2f ===" % [
			era_id, seed, str(theme["accent"]), float(theme["tech"]), float(theme["density"])
		])

		# 独立地形 + 装饰统计
		var tg := TerrainGenerator.new()
		var troot := tg.generate(seed, theme)
		add_child(troot)
		WorldManager.terrain_gen = tg
		var deco_container := Node3D.new()
		add_child(deco_container)
		var deco := WorldDecorator.new()
		add_child(deco)
		var objective_points: Array = []
		var obj: Dictionary = era.get("objective", {})
		for pt in (obj.get("points", []) as Array):
			var pos_arr: Array = pt.get("pos", [0.0, 0.0, 0.0])
			objective_points.append(Vector3(float(pos_arr[0]), 0, float(pos_arr[2])))
		deco.set_objective_points(objective_points)
		deco.generate(seed, deco_container, theme)
		var relic_count := 0
		for v in tg.relic_grid:
			if v > 0.4:
				relic_count += 1
		var h_min := INF
		var h_max := -INF
		for h in tg.heights:
			h_min = minf(h_min, h)
			h_max = maxf(h_max, h)
		var biome_counts := {}
		for b in tg.biome_grid:
			var key := str(b)
			biome_counts[key] = int(biome_counts.get(key, 0)) + 1
		var orb_count := 0
		var static_count := 0
		for child in deco_container.get_children():
			if child is EnergyOrb:
				orb_count += 1
			elif child is StaticBody3D:
				static_count += 1
		print("TERRAIN: hmin=%.1f hmax=%.1f relic_cells=%d biomes=%s" % [h_min, h_max, relic_count, str(biome_counts)])
		var anchor_dists := ""
		for pt in objective_points:
			var d := INF
			for child in deco_container.get_children():
				if child is Node3D:
					d = minf(d, (child as Node3D).global_position.distance_to(pt))
			anchor_dists += "%.1f " % d
		print("DECOR: children=%d orbs=%d statics=%d occupied=%d anchors=[%s]" % [
			deco_container.get_child_count(), orb_count, static_count, deco.occupied_count(), anchor_dists
		])

		# 经 WorldManager 重建真实世界
		WorldManager.world = $World
		WorldManager.weather = $World.weather
		WorldManager.world_seed = seed
		WorldManager.generate_terrain(theme)
		WorldManager.spawn_era_world(era)
		var deco_children := 0
		if $World.has_node("Decorations"):
			deco_children = $World.get_node("Decorations").get_child_count()
		print("WORLD: resources=%d decorations=%d" % [
			WorldManager.resource_nodes.size(), deco_children
		])
		WorldManager.clear_world_objects()
		troot.queue_free()
		deco_container.queue_free()
		deco.queue_free()
		await get_tree().process_frame
	print("PROBE_DONE")
	get_tree().quit(0)
