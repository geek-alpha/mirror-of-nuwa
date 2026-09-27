extends Node
## 地形物理查询基准：193² 网格的三角碰撞体是 97² 的 4 倍三角形，
## 用来确认角色移动/贴地射线（每帧大量 intersect_ray）没有被拖慢。
## 用法：godot --headless --path . res://tools/terrain_raycast_bench.tscn

const QUERIES := 20000
const RNG_SEED := 20260920

var _ran := false

func _ready() -> void:
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	CivilizationManager.initialize_factions()
	WorldManager.world = $World
	var t0 := Time.get_ticks_msec()
	WorldManager.generate_terrain()
	print("地形生成耗时：%d ms" % (Time.get_ticks_msec() - t0))

func _physics_process(_delta: float) -> void:
	# 放在物理帧里：地形刚加入场景树时物理空间尚未更新，_ready 里查询会全部落空
	if _ran:
		return
	_ran = true
	var terrain: TerrainGenerator = WorldManager.terrain_gen
	var world3d := ($World as Node3D).get_world_3d()
	var space := world3d.direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	var half := TerrainGenerator.WORLD_SIZE / 2.0 - 5.0
	var hits := 0
	var t1 := Time.get_ticks_msec()
	for i in QUERIES:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var top := terrain.height_at(x, z) + 6.0
		var from := Vector3(x, top, z)
		var to := Vector3(x, top - 12.0, z)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to)).is_empty():
			hits += 1
	var dt := Time.get_ticks_msec() - t1
	print("射线查询 %d 次｜命中 %d｜总耗时 %d ms｜单次 %.1f μs" % [
		QUERIES, hits, dt, 1000.0 * float(dt) / float(QUERIES)])
	print("网格 %d×%d｜三角碰撞面约 %d" % [
		TerrainGenerator.RESOLUTION, TerrainGenerator.RESOLUTION,
		(TerrainGenerator.RESOLUTION - 1) * (TerrainGenerator.RESOLUTION - 1) * 2])
	print("BENCH_DONE")
	get_tree().quit()
