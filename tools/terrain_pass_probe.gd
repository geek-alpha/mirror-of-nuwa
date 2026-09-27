extends Node
## 地形可通行性探针：并行放出若干胶囊探针，从随机起点朝随机方向匀速行走固定时长，
## 统计「被地形卡住」（水平位移远低于理论位移）的比例，并给出卡住点的坡度剖面，
## 用于区分「陡壁合理阻挡」与「缓坡/平地上的异常卡死」。固定随机种子，改地形前后可直接对比。
## 用法：godot --headless --path . res://tools/terrain_pass_probe.tscn

const PROBE_COUNT := 48
const SPEED := 4.0
const WALK_SECONDS := 6.0
const STUCK_DISTANCE := 3.0
const RNG_SEED := 20260919
const PROFILE_STEP := 0.5
const PROFILE_LENGTH := 6.0

var elapsed := 0.0
var terrain: TerrainGenerator = null
var probes: Array = []
var assisted_flags: Array = []
var starts: Array = []
var dirs: Array = []
## B 组专用方向：卡住时会沿墙切向改向绕行，不能与 A 组共用
var dirs_b: Array = []
var done := false

func _ready() -> void:
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	CivilizationManager.initialize_factions()
	WorldManager.world = $World
	var t0 := Time.get_ticks_msec()
	WorldManager.generate_terrain()
	var gen_ms := Time.get_ticks_msec() - t0
	terrain = WorldManager.terrain_gen
	print("地形生成耗时：%d ms" % gen_ms)
	_report_terrain_stats()
	_report_reachability()
	_spawn_probes()

func _spawn_probes() -> void:
	## 起点与方向完全由固定种子决定，且不按地形高度筛选：一旦筛选，地形微调就会
	## 换掉一批起点，跨版本比出来的卡住率是两组不同起点的差异，没有可比性。
	## 每个起点各造两个胶囊：A 纯地形行走，B 额外带角色的台阶爬升——用来量化
	## 「地形平缓度」与「角色灵活性」各自贡献了多少。
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	var half := TerrainGenerator.WORLD_SIZE / 2.0 - 10.0
	for i in PROBE_COUNT:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var angle := rng.randf_range(0.0, TAU)
		var h: float = terrain.height_at(x, z)
		starts.append(Vector3(x, h, z))
		var heading := Vector3(cos(angle), 0.0, sin(angle))
		dirs.append(heading)
		dirs_b.append(heading)
		for assisted in [false, true]:
			var body := CharacterBody3D.new()
			var cs := CollisionShape3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = 0.4
			cap.height = 1.9
			cs.shape = cap
			body.add_child(cs)
			body.floor_max_angle = deg_to_rad(65.0)
			body.floor_snap_length = 0.45
			# 探针不参与被碰撞（避免互相阻挡），只检测世界
			body.collision_layer = 0
			body.collision_mask = 1
			$World.add_child(body)
			body.global_position = Vector3(x, h + 0.6, z)
			probes.append(body)
			assisted_flags.append(assisted)

func _physics_process(delta: float) -> void:
	if done or probes.is_empty():
		return
	elapsed += delta
	for i in probes.size():
		var b: CharacterBody3D = probes[i]
		var slot := i / 2
		var assisted: bool = assisted_flags[i]
		var d: Vector3 = dirs_b[slot] if assisted else dirs[slot]
		b.velocity.x = d.x * SPEED
		b.velocity.z = d.z * SPEED
		if b.is_on_floor():
			b.velocity.y = -0.5
		else:
			b.velocity.y = maxf(b.velocity.y - 22.0 * delta, -25.0)
		var before := b.global_position
		b.move_and_slide()
		if not assisted:
			continue
		ClimbAssist.try_step_up(b, before, delta)
		# 几乎没挪动 = 撞上了墙：沿墙切向改向绕行（角色的脱困行为）
		var moved := Vector2(b.global_position.x - before.x, b.global_position.z - before.z).length()
		if moved < SPEED * delta * 0.25:
			var tangent := ClimbAssist.wall_sidestep_dir(b, d)
			if tangent != Vector3.ZERO:
				dirs_b[slot] = tangent
	if elapsed >= WALK_SECONDS:
		done = true
		_report_walk()

func _report_terrain_stats() -> void:
	var res := TerrainGenerator.RESOLUTION
	var cell := TerrainGenerator.CELL_SIZE
	var slopes_sorted := Array(terrain.slopes)
	slopes_sorted.sort()
	var n := slopes_sorted.size()
	var step_h := 2.1
	var steps_over := 0
	var edges := 0
	var max_diff := 0.0
	var diffs: Array = []
	for z in res:
		for x in res - 1:
			var d: float = absf(terrain.heights[z * res + x + 1] - terrain.heights[z * res + x])
			diffs.append(d)
			max_diff = maxf(max_diff, d)
			edges += 1
			if d > cell * 1.5:
				steps_over += 1
	diffs.sort()
	print("=== 地形统计 ===")
	print("网格 %d×%d 格距 %.2fm｜坡度 p50=%.2f p90=%.2f p99=%.2f max=%.2f（tan65°=2.14）" % [
		res, res, cell,
		slopes_sorted[n / 2], slopes_sorted[int(n * 0.9)], slopes_sorted[int(n * 0.99)], slopes_sorted[n - 1]])
	print("相邻格高差 p50=%.2f p90=%.2f p99=%.2f max=%.2f｜超 %.2fm 的边 %d/%d（%.1f%%）" % [
		diffs[diffs.size() / 2], diffs[int(diffs.size() * 0.9)], diffs[int(diffs.size() * 0.99)], max_diff,
		cell * 1.5, steps_over, edges, 100.0 * float(steps_over) / float(maxi(edges, 1))])

func _report_reachability() -> void:
	## 8 邻域 BFS：从地图中心出生点出发，按「每单位水平距离可攀升的最大高差」判可通行，
	## 看地形是否被陡壁切成孤岛——可达率低就说明绕路也到不了，不只是局部撞墙。
	var res := TerrainGenerator.RESOLUTION
	var cell := TerrainGenerator.CELL_SIZE
	var diag := cell * sqrt(2.0)
	var water := TerrainGenerator.WATER_LEVEL
	var land_total := 0
	for i in res * res:
		if terrain.heights[i] >= water:
			land_total += 1
	print("=== 可达性（8 邻域 BFS，起点=地图中心）===")
	for ratio: float in [1.0, 2.14]:
		var visited := PackedByteArray()
		visited.resize(res * res)
		var queue := PackedInt32Array()
		var start := (res / 2) * res + res / 2
		visited[start] = 1
		queue.append(start)
		var head := 0
		var reached := 1
		var land_reached := 1 if terrain.heights[start] >= water else 0
		while head < queue.size():
			var idx := queue[head]
			head += 1
			var x := idx % res
			var z := idx / res
			var h := terrain.heights[idx]
			for dz: int in [-1, 0, 1]:
				for dx: int in [-1, 0, 1]:
					if dx == 0 and dz == 0:
						continue
					var nx: int = x + dx
					var nz: int = z + dz
					if nx < 0 or nz < 0 or nx >= res or nz >= res:
						continue
					var nidx: int = nz * res + nx
					if visited[nidx] == 1:
						continue
					var dist: float = diag if (dx != 0 and dz != 0) else cell
					if absf(terrain.heights[nidx] - h) > ratio * dist:
						continue
					visited[nidx] = 1
					queue.append(nidx)
					reached += 1
					if terrain.heights[nidx] >= water:
						land_reached += 1
		var total := res * res
		print("可上坡 %.0f°（每格高差上限 %.2fm）：全图可达 %d/%d（%.0f%%）｜陆地可达 %d/%d（%.0f%%）" % [
			rad_to_deg(atan(ratio)), ratio * cell, reached, total,
			100.0 * float(reached) / float(total), land_reached, land_total,
			100.0 * float(land_reached) / float(maxi(land_total, 1))])

func _profile_max_slope(from: Vector3, dir: Vector3) -> float:
	## 起点沿行走方向的地表坡度剖面最大值（Δh/Δ水平距离）
	var prev_h := terrain.height_at(from.x, from.z)
	var worst := 0.0
	var d := PROFILE_STEP
	while d <= PROFILE_LENGTH:
		var h := terrain.height_at(from.x + dir.x * d, from.z + dir.z * d)
		worst = maxf(worst, absf(h - prev_h) / PROFILE_STEP)
		prev_h = h
		d += PROFILE_STEP
	return worst

func _report_walk() -> void:
	print("=== 行走探针 ===")
	print("每组 %d 个起点｜行走 %.1fs @%.1fm/s（理论位移 %.1fm，卡住阈值 %.1fm）" % [
		PROBE_COUNT, WALK_SECONDS, SPEED, WALK_SECONDS * SPEED, STUCK_DISTANCE])
	_report_group(false, "A 纯地形（无爬升）")
	_report_group(true, "B 带台阶爬升（角色实际体验）")

func _report_group(assisted: bool, label: String) -> void:
	var stuck := 0
	var stuck_low_slope := 0
	var total_dist := 0.0
	var count := 0
	var lines: Array[String] = []
	for i in probes.size():
		if assisted_flags[i] != assisted:
			continue
		count += 1
		var b: CharacterBody3D = probes[i]
		var s: Vector3 = starts[i / 2]
		var flat := Vector2(b.global_position.x - s.x, b.global_position.z - s.z).length()
		total_dist += flat
		if flat >= STUCK_DISTANCE:
			continue
		stuck += 1
		var front := _profile_max_slope(s, dirs_b[i / 2] if assisted else dirs[i / 2])
		# 前方 6m 内最大坡度低于 45°（tan≈1.0）却走不动 = 缓坡/平地卡死，属异常
		if front < 1.0:
			stuck_low_slope += 1
		var wall_info := "否"
		if b.is_on_wall():
			wall_info = "是(%.0f°)" % rad_to_deg(b.get_wall_normal().angle_to(Vector3.UP))
		lines.append("  [%d] 起点(%.1f,%.1f) h=%.1f 位移=%.2fm 起点坡=%.2f 前方最大坡=%.2f 触墙=%s" % [
			i / 2, s.x, s.z, s.y, flat, terrain.slope_at(s.x, s.z), front, wall_info])
	print("%s：卡住 %d/%d（%.0f%%）｜平均位移 %.2fm｜前方坡度<45°的异常卡死 %d 个" % [
		label, stuck, count, 100.0 * float(stuck) / float(maxi(count, 1)),
		total_dist / float(maxi(count, 1)), stuck_low_slope])
	for l in lines:
		print(l)
	print("PROBE_DONE")
	get_tree().quit()
