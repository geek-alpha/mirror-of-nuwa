class_name TerrainGenerator
extends Node
## 程序化地形生成器：多层次高度场（山脊/山陵/平原/湖泊）+ 生态区划分 + 坡度/高度着色 + 水面。
## 生态区：0 翠风平原 / 1 金沙荒原 / 2 幽蓝湿地 / 3 紫雾密林 / 4 墨玉山脉 / 5 辉晶遗迹。
## 纪元主题：每个剧情纪元可携带 accent 主色与地形性格，让每张地图都有
## “古老文明 × 先进科技”（亚特兰蒂斯式）的神秘地貌——阶梯台地、同心环水道、辉光遗迹带。

const WORLD_SIZE := 160.0
const RESOLUTION := 97
const WATER_LEVEL := 1.4
const CELL_SIZE := WORLD_SIZE / float(RESOLUTION - 1)

const BIOME_PLAINS := 0
const BIOME_SAVANNA := 1
const BIOME_WETLANDS := 2
const BIOME_FOREST := 3
const BIOME_MOUNTAINS := 4
const BIOME_RELIC := 5

var heights: PackedFloat32Array = PackedFloat32Array()
var slopes: PackedFloat32Array = PackedFloat32Array()
var biome_grid: Array = []
var relic_grid: PackedFloat32Array = PackedFloat32Array()

var theme: Dictionary = {}
var accent := Color(0.35, 0.8, 1.0)
var era_id := ""
var _seed := 0

var _color_noise := FastNoiseLite.new()
var _vein_noise := FastNoiseLite.new()

func generate(seed_value: int, theme: Dictionary = {}) -> Node3D:
	self.theme = theme
	accent = theme.get("accent", Color(0.35, 0.8, 1.0))
	era_id = str(theme.get("id", ""))
	# 用纪元 id 派生独立种子，保证不同地图即使种子相近也地形迥异
	_seed = seed_value + (abs(hash(era_id)) % 65536)

	var container := Node3D.new()
	container.name = "TerrainMesh"

	var warp_noise := FastNoiseLite.new()
	warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	warp_noise.seed = _seed + 3
	warp_noise.frequency = 0.024
	warp_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	warp_noise.fractal_octaves = 3

	var height_noise := FastNoiseLite.new()
	height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	height_noise.seed = _seed
	height_noise.frequency = 0.015
	height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	height_noise.fractal_octaves = 4

	var hill_noise := FastNoiseLite.new()
	hill_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	hill_noise.seed = _seed + 7
	hill_noise.frequency = 0.055
	hill_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	hill_noise.fractal_octaves = 3

	var peak_noise := FastNoiseLite.new()
	peak_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	peak_noise.seed = _seed + 11
	peak_noise.frequency = 0.024
	peak_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	peak_noise.fractal_octaves = 4

	var mountain_region := FastNoiseLite.new()
	mountain_region.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mountain_region.seed = _seed + 29
	mountain_region.frequency = 0.017
	mountain_region.fractal_type = FastNoiseLite.FRACTAL_FBM
	mountain_region.fractal_octaves = 3

	var detail_noise := FastNoiseLite.new()
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.seed = _seed + 19
	detail_noise.frequency = 0.09

	var micro_noise := FastNoiseLite.new()
	micro_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	micro_noise.seed = _seed + 41
	micro_noise.frequency = 0.21

	var temp_noise := FastNoiseLite.new()
	temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	temp_noise.seed = _seed + 13
	temp_noise.frequency = 0.013

	var moist_noise := FastNoiseLite.new()
	moist_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moist_noise.seed = _seed + 17
	moist_noise.frequency = 0.016

	var lake_noise := FastNoiseLite.new()
	lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	lake_noise.seed = _seed + 23
	lake_noise.frequency = 0.027
	lake_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	lake_noise.fractal_octaves = 3

	_color_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_color_noise.seed = _seed + 31
	_color_noise.frequency = 0.11

	_vein_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_vein_noise.seed = _seed + 37
	_vein_noise.frequency = 0.035
	_vein_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_vein_noise.fractal_octaves = 2

	# 古代台地：大块削平的高原，浮现阶梯状层次
	var terrace_noise := FastNoiseLite.new()
	terrace_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	terrace_noise.seed = _seed + 43
	terrace_noise.frequency = 0.02
	terrace_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrace_noise.fractal_octaves = 3

	var plateau_noise := FastNoiseLite.new()
	plateau_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	plateau_noise.seed = _seed + 47
	plateau_noise.frequency = 0.013
	plateau_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	plateau_noise.fractal_octaves = 2

	# 亚特兰蒂斯式同心环：以地图中心向外一圈圈扩散的环状水道/台地
	var ring_zone_noise := FastNoiseLite.new()
	ring_zone_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ring_zone_noise.seed = _seed + 53
	ring_zone_noise.frequency = 0.03
	ring_zone_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	ring_zone_noise.fractal_octaves = 2

	# 辉光遗迹带：地形轻微抬升并着色的“圣所”区域
	var relic_noise := FastNoiseLite.new()
	relic_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	relic_noise.seed = _seed + 59
	relic_noise.frequency = 0.021
	relic_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	relic_noise.fractal_octaves = 3

	# 山体深切峡谷
	var ridge_noise := FastNoiseLite.new()
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge_noise.seed = _seed + 61
	ridge_noise.frequency = 0.03
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge_noise.fractal_octaves = 3

	heights.resize(RESOLUTION * RESOLUTION)
	slopes.resize(RESOLUTION * RESOLUTION)
	relic_grid.resize(RESOLUTION * RESOLUTION)
	biome_grid.clear()

	for z in RESOLUTION:
		for x in RESOLUTION:
			var idx := z * RESOLUTION + x
			var nx := _world_x(x)
			var nz := _world_z(z)
			var wx := warp_noise.get_noise_2d(nx, nz) * 4.0
			var wz := warp_noise.get_noise_2d(nx + 57.3, nz + 91.7) * 4.0

			# 山脊：山脊噪声 + 大尺度高度场共同抬高
			var peak := maxf(0.0, peak_noise.get_noise_2d(nx + wx, nz + wz))
			var mregion := smoothstep(0.18, 0.58, mountain_region.get_noise_2d(nx + wx, nz + wz))
			var h := 3.2 + height_noise.get_noise_2d(nx + wx, nz + wz) * 5.5
			h += hill_noise.get_noise_2d(nx, nz) * 2.4
			h += mregion * (5.0 + peak * 26.0)
			h += detail_noise.get_noise_2d(nx, nz) * 0.7
			h += micro_noise.get_noise_2d(nx, nz) * 0.35

			# 古代高原：大片削平的台地，被抬到稳定高度
			var plateau_mask := smoothstep(0.1, 0.55, plateau_noise.get_noise_2d(nx, nz))
			if plateau_mask > 0.0:
				var plateau_h := 9.0 + plateau_mask * 9.0
				h = lerpf(h, plateau_h, plateau_mask * 0.72)

			# 阶梯台地：在台地区域把高度量化为台阶，形成古文明层叠感
			var terrace_region := smoothstep(0.22, 0.62, terrace_noise.get_noise_2d(nx + wx * 0.5, nz + wz * 0.5))
			if terrace_region > 0.0:
				var step_h := 2.1
				var stepped: float = floor(h / step_h) * step_h + step_h * 0.55
				var terrace_mask := terrace_region * (1.0 - mregion * 0.55) * plateau_mask
				h = lerpf(h, stepped, terrace_mask * 0.72)

			# 亚特兰蒂斯同心环：中心向外一圈圈环形沟槽，形成环水台地
			var dist := Vector2(nx, nz).length()
			var ring_zone := smoothstep(0.32, 0.68, ring_zone_noise.get_noise_2d(nx, nz))
			if ring_zone > 0.05 and dist > 16.0 and dist < 74.0:
				var ring_wave := 0.5 + 0.5 * cos(dist * 0.42)
				var channel := smoothstep(0.66, 0.94, ring_wave)
				h -= channel * ring_zone * 2.6 * (1.0 - mregion * 0.7)

			# 山脉深切峡谷：让山体拥有锐利岩壁，而不是圆丘
			var ridge := maxf(0.0, ridge_noise.get_noise_2d(nx, nz))
			h -= ridge * 3.0 * mregion

			# 辉光遗迹带：遗迹圣所区域微抬升，便于摆放古建筑
			var relic := smoothstep(0.46, 0.76, relic_noise.get_noise_2d(nx, nz))
			h += relic * 1.5 * (1.0 - mregion * 0.55)
			relic_grid[idx] = relic

			# 湖泊：低洼盆地挖低，湖心最深
			var lake_mask := smoothstep(0.46, 0.64, lake_noise.get_noise_2d(nx, nz))
			var spawn_keep := smoothstep(16.0, 30.0, dist)
			h = lerpf(h, WATER_LEVEL - 0.65 - lake_mask * 0.35, lake_mask * spawn_keep)

			# 出生点附近压平，方便开局观察与聚落展开
			var flatten := 1.0 - smoothstep(13.0, 28.0, dist)
			h = lerpf(h, 3.4, flatten)

			h = clampf(h, 0.0, 36.0)
			heights[idx] = h

			# 生态区：温度 + 湿度 + 海拔 + 遗迹带
			var t := temp_noise.get_noise_2d(nx, nz)
			var w := moist_noise.get_noise_2d(nx, nz)
			var biome := BIOME_PLAINS
			if h > 12.5:
				biome = BIOME_MOUNTAINS
			elif relic > 0.52:
				biome = BIOME_RELIC
			elif w > 0.3 and h < 7.5:
				biome = BIOME_WETLANDS
			elif t > 0.12 and w < 0.02:
				biome = BIOME_SAVANNA
			elif w > 0.12 and t < -0.08:
				biome = BIOME_FOREST
			biome_grid.append(biome)

	# 坡度：用高度网格差分近似（用于岩石/雪线着色）
	for z in RESOLUTION:
		for x in RESOLUTION:
			var hx := heights[z * RESOLUTION + mini(x + 1, RESOLUTION - 1)] - heights[z * RESOLUTION + maxi(x - 1, 0)]
			var hz := heights[mini(z + 1, RESOLUTION - 1) * RESOLUTION + x] - heights[maxi(z - 1, 0) * RESOLUTION + x]
			slopes[z * RESOLUTION + x] = Vector2(hx, hz).length() / (2.0 * CELL_SIZE)

	# 构建地形网格（带顶点颜色）
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in RESOLUTION - 1:
		for x in RESOLUTION - 1:
			var i00 := z * RESOLUTION + x
			var i10 := i00 + 1
			var i01 := i00 + RESOLUTION
			var i11 := i01 + 1
			var p00 := _vertex(x, z)
			var p10 := _vertex(x + 1, z)
			var p01 := _vertex(x, z + 1)
			var p11 := _vertex(x + 1, z + 1)
			var c00 := _vertex_color(x, z)
			var c10 := _vertex_color(x + 1, z)
			var c01 := _vertex_color(x, z + 1)
			var c11 := _vertex_color(x + 1, z + 1)
			st.set_color(c00)
			st.add_vertex(p00)
			st.set_color(c10)
			st.add_vertex(p10)
			st.set_color(c01)
			st.add_vertex(p01)
			st.set_color(c10)
			st.add_vertex(p10)
			st.set_color(c11)
			st.add_vertex(p11)
			st.set_color(c01)
			st.add_vertex(p01)
	st.generate_normals()
	var mesh := st.commit()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic = 0.02
	mesh.surface_set_material(0, mat)

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Visual"
	mesh_node.mesh = mesh
	container.add_child(mesh_node)

	# 水面：仅覆盖低洼/湖泊区域，稍低于地形表面
	var water := _build_water_mesh()
	if water != null:
		var water_node := MeshInstance3D.new()
		water_node.name = "Water"
		water_node.mesh = water
		container.add_child(water_node)

	# 碰撞：从地形网格生成三角形网格碰撞体（与视觉精确一致）
	var body := StaticBody3D.new()
	body.name = "Collision"
	var col := CollisionShape3D.new()
	var trimesh := mesh.create_trimesh_shape() as ConcavePolygonShape3D
	trimesh.backface_collision = true
	col.shape = trimesh
	body.add_child(col)
	container.add_child(body)
	return container

func _build_water_mesh() -> ArrayMesh:
	## 只在水面以下的网格单元生成水面，避免平面穿透山体。
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var made := false
	for z in RESOLUTION - 1:
		for x in RESOLUTION - 1:
			var h00 := heights[z * RESOLUTION + x]
			var h10 := heights[z * RESOLUTION + x + 1]
			var h01 := heights[(z + 1) * RESOLUTION + x]
			var h11 := heights[(z + 1) * RESOLUTION + x + 1]
			var underwater := h00 < WATER_LEVEL and h10 < WATER_LEVEL and h01 < WATER_LEVEL and h11 < WATER_LEVEL
			if not underwater:
				continue
			made = true
			var p00 := Vector3(_world_x(x), WATER_LEVEL, _world_z(z))
			var p10 := Vector3(_world_x(x + 1), WATER_LEVEL, _world_z(z))
			var p01 := Vector3(_world_x(x), WATER_LEVEL, _world_z(z + 1))
			var p11 := Vector3(_world_x(x + 1), WATER_LEVEL, _world_z(z + 1))
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p01)
			st.add_vertex(p10)
			st.add_vertex(p11)
			st.add_vertex(p01)
	if not made:
		return null
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	var water_tint := Color(0.12, 0.35, 0.5).lerp(accent, 0.22)
	mat.albedo_color = Color(water_tint.r, water_tint.g, water_tint.b, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.15
	mat.emission_enabled = true
	mat.emission = accent.darkened(0.45)
	mat.emission_energy_multiplier = 0.5
	mesh.surface_set_material(0, mat)
	return mesh

func _world_x(x: int) -> float:
	return float(x) / float(RESOLUTION - 1) * WORLD_SIZE - WORLD_SIZE / 2.0

func _world_z(z: int) -> float:
	return float(z) / float(RESOLUTION - 1) * WORLD_SIZE - WORLD_SIZE / 2.0

func _vertex(x: int, z: int) -> Vector3:
	return Vector3(_world_x(x), heights[z * RESOLUTION + x], _world_z(z))

func _vertex_color(x: int, z: int) -> Color:
	var idx := z * RESOLUTION + x
	var biome := int(biome_grid[idx])
	var h := heights[idx]
	var slope := slopes[idx]
	var relic := relic_grid[idx]
	var wx := _world_x(x)
	var wz := _world_z(z)
	var n := _color_noise.get_noise_2d(wx, wz)
	var vein := _vein_noise.get_noise_2d(wx, wz)
	var c: Color = _biome_palette(biome)

	# 海拔染色：低处湿润变深，高处露出岩石
	var rock := Color(0.42, 0.4, 0.45)
	if h > 13.0:
		c = c.lerp(rock, clampf((h - 13.0) / 10.0, 0.0, 0.9))
	# 雪线：高山顶覆雪
	if biome == BIOME_MOUNTAINS and h > 24.0:
		c = c.lerp(Color(0.92, 0.94, 0.98), clampf((h - 24.0) / 8.0, 0.0, 1.0))
	# 陡坡露出岩土
	if slope > 0.5:
		c = c.lerp(Color(0.48, 0.43, 0.36), clampf((slope - 0.5) / 0.6, 0.0, 0.85))
	# 遗迹带：地面被远古能源染成主题色，边缘微亮
	if relic > 0.18:
		var relic_tint := accent.darkened(0.42)
		c = c.lerp(relic_tint, clampf((relic - 0.18) / 0.62, 0.0, 0.42))
	# 辉光矿脉：沿着遗迹带蜿蜒的主题色亮纹
	if relic > 0.3 and vein > 0.48:
		var vein_strength := clampf((vein - 0.48) / 0.42, 0.0, 1.0) * clampf((relic - 0.3) / 0.5, 0.0, 1.0)
		c = c.lerp(accent.lightened(0.5), vein_strength * 0.5)
	# 湿度微调：湿地更暗沉
	if biome == BIOME_WETLANDS:
		c = c.darkened(0.12)
	# 亮度抖动：让地表有细微斑驳，而非纯色
	var brightness := 1.0 + n * 0.12
	return Color(c.r * brightness, c.g * brightness, c.b * brightness)

func _biome_palette(biome: int) -> Color:
	match biome:
		BIOME_PLAINS:
			return Color(0.32, 0.55, 0.28)
		BIOME_SAVANNA:
			return Color(0.78, 0.6, 0.3)
		BIOME_WETLANDS:
			return Color(0.25, 0.48, 0.46)
		BIOME_FOREST:
			return Color(0.27, 0.28, 0.44)
		BIOME_MOUNTAINS:
			return Color(0.38, 0.37, 0.42)
		BIOME_RELIC:
			return Color(0.3, 0.42, 0.52).lerp(accent.darkened(0.3), 0.45)
		_:
			return Color(0.4, 0.5, 0.4)

func height_at(world_x: float, world_z: float) -> float:
	if heights.is_empty():
		return 0.0
	var fx := clampf((world_x + WORLD_SIZE / 2.0) / WORLD_SIZE * float(RESOLUTION - 1), 0.0, float(RESOLUTION - 1))
	var fz := clampf((world_z + WORLD_SIZE / 2.0) / WORLD_SIZE * float(RESOLUTION - 1), 0.0, float(RESOLUTION - 1))
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var x1 := mini(x0 + 1, RESOLUTION - 1)
	var z1 := mini(z0 + 1, RESOLUTION - 1)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var h00 := heights[z0 * RESOLUTION + x0]
	var h10 := heights[z0 * RESOLUTION + x1]
	var h01 := heights[z1 * RESOLUTION + x0]
	var h11 := heights[z1 * RESOLUTION + x1]
	var h0 := lerpf(h00, h10, tx)
	var h1 := lerpf(h01, h11, tx)
	return lerpf(h0, h1, tz)

func normal_at(world_x: float, world_z: float) -> Vector3:
	## 地表法线，供装饰物贴地摆放。
	var e := 0.8
	var hx1 := height_at(world_x + e, world_z)
	var hx0 := height_at(world_x - e, world_z)
	var hz1 := height_at(world_x, world_z + e)
	var hz0 := height_at(world_x, world_z - e)
	return Vector3(hx0 - hx1, 2.0 * e, hz0 - hz1).normalized()

func biome_at(world_x: float, world_z: float) -> int:
	if biome_grid.is_empty():
		return BIOME_PLAINS
	var fx := clampi(int((world_x + WORLD_SIZE / 2.0) / WORLD_SIZE * float(RESOLUTION - 1)), 0, RESOLUTION - 1)
	var fz := clampi(int((world_z + WORLD_SIZE / 2.0) / WORLD_SIZE * float(RESOLUTION - 1)), 0, RESOLUTION - 1)
	return int(biome_grid[fz * RESOLUTION + fx])

func relic_at(world_x: float, world_z: float) -> float:
	if relic_grid.is_empty():
		return 0.0
	var fx := clampi(int((world_x + WORLD_SIZE / 2.0) / WORLD_SIZE * float(RESOLUTION - 1)), 0, RESOLUTION - 1)
	var fz := clampi(int((world_z + WORLD_SIZE / 2.0) / WORLD_SIZE * float(RESOLUTION - 1)), 0, RESOLUTION - 1)
	return relic_grid[fz * RESOLUTION + fx]

func is_water(world_x: float, world_z: float) -> bool:
	return height_at(world_x, world_z) < WATER_LEVEL

func slope_at(world_x: float, world_z: float) -> float:
	if slopes.is_empty():
		return 0.0
	var fx := clampi(int((world_x + WORLD_SIZE / 2.0) / WORLD_SIZE * float(RESOLUTION - 1)), 0, RESOLUTION - 1)
	var fz := clampi(int((world_z + WORLD_SIZE / 2.0) / WORLD_SIZE * float(RESOLUTION - 1)), 0, RESOLUTION - 1)
	return slopes[fz * RESOLUTION + fx]
