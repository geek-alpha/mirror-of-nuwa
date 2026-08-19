class_name WorldDecorator
extends Node
## 世界装饰生成器：按生态区生成树木/岩石/草丛/晶体，并在秘境生成古石阵、遗迹与
## “古老文明 × 先进科技”（亚特兰蒂斯式）的地标——石板广场、拱门、方尖碑、古代机械、
## 光柱、能量管道与浮空辉光。支持按剧情纪元切换主题色与科技浓度，所有装饰均由程序化图元构成。
var rng := RandomNumberGenerator.new()
var container: Node3D = null

const VILLAGE_CLEAR_RADIUS := 16.0

var _accent := Color(0.35, 0.8, 1.0)
var _accent2 := Color(1.0, 0.85, 0.3)
var _stone := Color(0.42, 0.4, 0.46)
var _glow := Color(0.45, 0.7, 1.0)
var _tech := 0.35
var _density := 1.0
var _era_id := ""
var _objective_points: Array = []
var _occupied: Array = []

func generate(seed_value: int, root: Node3D, theme: Dictionary = {}) -> void:
	rng.seed = seed_value
	container = root
	_apply_theme(theme)
	_clear()
	_occupied.clear()
	# 主结构优先占地，填充物随后避开，避免穿模与堆叠
	_spawn_pavements()
	_spawn_arches()
	_spawn_obelisks()
	_spawn_menhir_circles(2)
	_spawn_ruins(2)
	_spawn_machines()
	_spawn_terraces()
	_spawn_light_shafts()
	_spawn_energy_conduits()
	_spawn_relic_glows()
	_spawn_wonders()
	_spawn_crystal_mandalas()
	_spawn_grass_and_flowers()
	_spawn_trees()
	_spawn_rocks()
	_spawn_crystals()

func prepare(container_node: Node3D, theme: Dictionary = {}) -> void:
	## 不重建装饰层，直接在当前容器上追加道具（供剧情地标使用）。
	rng.seed = randi()
	container = container_node
	_apply_theme(theme)

func set_objective_points(points: Array) -> void:
	## 任务点锚定：丰碑会优先布置在任务建筑附近，而不是随便扔在荒野。
	_objective_points = points

func _apply_theme(raw: Dictionary) -> void:
	var profile := theme_for_era(str(raw.get("id", "")))
	_era_id = str(raw.get("id", ""))
	_accent = raw.get("accent", profile.get("accent", Color(0.35, 0.8, 1.0)))
	_accent2 = raw.get("accent2", profile.get("accent2", Color(1.0, 0.85, 0.3)))
	_stone = raw.get("stone", profile.get("stone", Color(0.42, 0.4, 0.46)))
	_glow = raw.get("glow", profile.get("glow", Color(0.45, 0.7, 1.0)))
	_tech = float(raw.get("tech", profile.get("tech", 0.35)))
	_density = float(raw.get("density", profile.get("density", 1.0)))

static func theme_for_era(era_id: String) -> Dictionary:
	match era_id:
		"era_wenwang":
			return {
				"accent": Color(1.0, 0.62, 0.25),
				"accent2": Color(0.92, 0.78, 0.42),
				"stone": Color(0.5, 0.4, 0.32),
				"glow": Color(1.0, 0.68, 0.3),
				"tech": 0.15,
				"density": 1.1
			}
		"era_mozi":
			return {
				"accent": Color(0.9, 0.55, 0.25),
				"accent2": Color(0.45, 0.85, 0.7),
				"stone": Color(0.46, 0.38, 0.33),
				"glow": Color(0.5, 0.95, 0.7),
				"tech": 0.6,
				"density": 1.15
			}
		"era_qinshihuang":
			return {
				"accent": Color(0.35, 0.9, 0.6),
				"accent2": Color(0.78, 0.36, 0.2),
				"stone": Color(0.4, 0.38, 0.35),
				"glow": Color(0.42, 1.0, 0.66),
				"tech": 0.4,
				"density": 1.2
			}
		"era_newton":
			return {
				"accent": Color(0.45, 0.7, 1.0),
				"accent2": Color(0.95, 0.8, 0.45),
				"stone": Color(0.42, 0.44, 0.5),
				"glow": Color(0.6, 0.85, 1.0),
				"tech": 0.85,
				"density": 1.05
			}
		"era_einstein":
			return {
				"accent": Color(1.0, 0.85, 0.45),
				"accent2": Color(0.88, 0.95, 1.0),
				"stone": Color(0.48, 0.46, 0.42),
				"glow": Color(1.0, 0.9, 0.55),
				"tech": 0.7,
				"density": 1.1
			}
		_:
			return {
				"accent": Color(0.35, 0.8, 1.0),
				"accent2": Color(1.0, 0.85, 0.3),
				"stone": Color(0.42, 0.4, 0.46),
				"glow": Color(0.45, 0.7, 1.0),
				"tech": 0.35,
				"density": 1.0
			}

func theme_accent() -> Color:
	return _accent

func theme_glow() -> Color:
	return _glow

func occupied_count() -> int:
	return _occupied.size()

func _clear() -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()

# ---------- 通用工具 ----------

func _terrain() -> TerrainGenerator:
	return WorldManager.terrain_gen

func _ground_y(wx: float, wz: float) -> float:
	return _terrain().height_at(wx, wz)

func _ground_normal(wx: float, wz: float) -> Vector3:
	return _terrain().normal_at(wx, wz)

func _suitable(wx: float, wz: float, max_slope: float = 0.45) -> bool:
	var tg := _terrain()
	if tg == null:
		return false
	if tg.is_water(wx, wz):
		return false
	if tg.slope_at(wx, wz) > max_slope:
		return false
	return true

func _near_village(wx: float, wz: float) -> bool:
	if GameState.is_story_mode():
		return false
	for fid in CivilizationManager.faction_centers:
		var c: Vector3 = CivilizationManager.faction_centers[fid]
		if Vector2(wx, wz).distance_to(Vector2(c.x, c.z)) < VILLAGE_CLEAR_RADIUS:
			return true
	return false

func _rand_pos(wx_min: float, wx_max: float, wz_min: float, wz_max: float) -> Vector2:
	return Vector2(rng.randf_range(wx_min, wx_max), rng.randf_range(wz_min, wz_max))

func _mat(color: Color, rough: float = 0.9, metal: float = 0.0, emission: Color = Color.BLACK, em_energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = em_energy
	return m

func _glow_mat(color: Color, energy: float = 1.4) -> StandardMaterial3D:
	return _mat(color.darkened(0.35), 0.3, 0.2, color, energy)

func _beam_mat(color: Color, energy: float = 2.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, 0.16)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

func _add_visual(mesh: Mesh, mat: StandardMaterial3D, pos: Vector3, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	container.add_child(mi)
	return mi

func _add_multimesh(mesh: Mesh, mat: StandardMaterial3D, transforms: Array, shadow: bool = true) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.mesh = mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	container.add_child(mmi)

func _add_static(mesh: Mesh, mat: StandardMaterial3D, pos: Vector3, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE, col_shape: Shape3D = null, col_pos: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot
	body.scale = scale
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	if col_shape != null:
		var cs := CollisionShape3D.new()
		cs.shape = col_shape
		cs.position = col_pos
		body.add_child(cs)
	container.add_child(body)
	return body

func _deco_transform(x: float, y: float, z: float, scale: float) -> Transform3D:
	var b := Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12)))
	return Transform3D(b.scaled(Vector3.ONE * scale), Vector3(x, y, z))

func _ground_transform(wx: float, wz: float, tilt: float = 0.0) -> Transform3D:
	var n := _ground_normal(wx, wz)
	var up := Vector3.UP
	var axis := up.cross(n)
	var angle := up.angle_to(n)
	var b := Basis()
	if axis.length() > 0.001:
		b = Basis(axis.normalized(), angle)
	var spin := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0))
	b = (spin * b).scaled(Vector3.ONE)
	# 额外的随机倾斜
	if tilt > 0.0:
		var tilt_axis := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		b = Basis(tilt_axis, deg_to_rad(rng.randf_range(-tilt, tilt))) * b
	return Transform3D(b, Vector3(wx, _ground_y(wx, wz), wz))

# ---------- 草丛与花卉（MultiMesh 批量实例） ----------

func _spawn_grass_and_flowers() -> void:
	var grass_mesh := CylinderMesh.new()
	grass_mesh.top_radius = 0.0
	grass_mesh.bottom_radius = 0.16
	grass_mesh.height = 0.55
	grass_mesh.radial_segments = 6
	var flower_mesh := SphereMesh.new()
	flower_mesh.radius = 0.07
	flower_mesh.height = 0.14
	flower_mesh.radial_segments = 8
	flower_mesh.rings = 4

	var plans := [
		{"biome": TerrainGenerator.BIOME_PLAINS, "count": int(130 * _density), "color": Color(0.38, 0.62, 0.32), "flower": true},
		{"biome": TerrainGenerator.BIOME_SAVANNA, "count": int(85 * _density), "color": Color(0.78, 0.66, 0.34), "flower": false},
		{"biome": TerrainGenerator.BIOME_WETLANDS, "count": int(75 * _density), "color": Color(0.3, 0.55, 0.48), "flower": true},
		{"biome": TerrainGenerator.BIOME_FOREST, "count": int(65 * _density), "color": Color(0.3, 0.34, 0.48), "flower": true},
		{"biome": TerrainGenerator.BIOME_RELIC, "count": int(50 * _density), "color": _accent.darkened(0.5), "flower": true}
	]
	for plan in plans:
		var grass_transforms: Array = []
		var flower_transforms: Array = []
		var glow_transforms: Array = []
		var placed := 0
		var attempts := 0
		while placed < int(plan["count"]) and attempts < 600:
			attempts += 1
			var p := _rand_pos(-78.0, 78.0, -78.0, 78.0)
			if _terrain().biome_at(p.x, p.y) != int(plan["biome"]):
				continue
			if not _suitable(p.x, p.y, 0.5):
				continue
			if _near_major(p.x, p.y, 2.0):
				continue
			var y := _ground_y(p.x, p.y)
			var s := 0.7 + rng.randf() * 0.9
			grass_transforms.append(_deco_transform(p.x, y, p.y, s))
			if bool(plan["flower"]) and rng.randf() < 0.4:
				flower_transforms.append(_deco_transform(p.x, y + 0.3, p.y, 0.8 + rng.randf() * 0.6))
			if int(plan["biome"]) == TerrainGenerator.BIOME_RELIC and rng.randf() < 0.5:
				glow_transforms.append(_deco_transform(p.x, y + 0.18, p.y, 0.6 + rng.randf() * 0.5))
			placed += 1
		_add_multimesh(grass_mesh, _mat(plan["color"], 1.0), grass_transforms, false)
		if not flower_transforms.is_empty():
			_add_multimesh(flower_mesh, _mat(Color(1.0, 0.8, 0.5), 0.7, 0.0, Color(1.0, 0.75, 0.4), 0.5), flower_transforms, false)
		if not glow_transforms.is_empty():
			var glow_flower := SphereMesh.new()
			glow_flower.radius = 0.05
			glow_flower.height = 0.1
			glow_flower.radial_segments = 6
			glow_flower.rings = 3
			_add_multimesh(glow_flower, _glow_mat(_accent, 1.0), glow_transforms, false)

# ---------- 树木 ----------

func _spawn_trees() -> void:
	var quotas := {
		TerrainGenerator.BIOME_PLAINS: int(38 * _density),
		TerrainGenerator.BIOME_FOREST: int(58 * _density),
		TerrainGenerator.BIOME_WETLANDS: int(22 * _density),
		TerrainGenerator.BIOME_SAVANNA: int(12 * _density),
		TerrainGenerator.BIOME_MOUNTAINS: int(11 * _density),
		TerrainGenerator.BIOME_RELIC: int(8 * _density)
	}
	for biome in quotas:
		var placed := 0
		var attempts := 0
		while placed < int(quotas[biome]) and attempts < 600:
			attempts += 1
			var p := _rand_pos(-78.0, 78.0, -78.0, 78.0)
			if _terrain().biome_at(p.x, p.y) != int(biome):
				continue
			if not _suitable(p.x, p.y, 0.5):
				continue
			if _near_village(p.x, p.y):
				continue
			if _near_major(p.x, p.y, 7.0):
				continue
			_spawn_tree(p.x, p.y, int(biome))
			placed += 1

func _spawn_tree(wx: float, wz: float, biome: int) -> void:
	var y := _ground_y(wx, wz)
	var trunk_h := rng.randf_range(1.5, 2.8)
	if biome == TerrainGenerator.BIOME_FOREST:
		trunk_h = rng.randf_range(2.2, 3.6)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.1 + rng.randf() * 0.08
	trunk.bottom_radius = trunk.top_radius * 1.35
	trunk.height = trunk_h
	trunk.radial_segments = 9
	var wood := _mat(Color(0.42, 0.3, 0.18), 0.95)
	var body := StaticBody3D.new()
	body.position = Vector3(wx, y, wz)
	body.rotation.y = rng.randf() * TAU
	var trunk_mi := MeshInstance3D.new()
	trunk_mi.mesh = trunk
	trunk_mi.material_override = wood
	trunk_mi.position.y = trunk_h / 2.0
	body.add_child(trunk_mi)

	match biome:
		TerrainGenerator.BIOME_FOREST:
			_add_canopy(body, 1, 0.35, trunk_h + 0.5, Color(0.22, 0.3, 0.45), 1.4)
			_add_canopy(body, 0, 0.28, trunk_h + 1.1, Color(0.26, 0.34, 0.5), 1.0)
		TerrainGenerator.BIOME_WETLANDS:
			_add_canopy(body, 0, 0.3, trunk_h + 0.3, Color(0.3, 0.42, 0.38), 0.8)
		TerrainGenerator.BIOME_SAVANNA:
			_add_canopy(body, 0, 0.9, trunk_h + 0.45, Color(0.55, 0.58, 0.3), 1.15, true)
		TerrainGenerator.BIOME_MOUNTAINS:
			_add_pine(body, trunk_h)
		TerrainGenerator.BIOME_RELIC:
			# 遗迹圣所里生长的“晶化古树”：枝干泛着主题色
			_add_canopy(body, 1, 0.3, trunk_h + 0.5, _accent.darkened(0.62), 1.1)
			_add_canopy(body, 0, 0.24, trunk_h + 1.0, _accent.darkened(0.5), 0.8)
		_:
			_add_canopy(body, 1, 0.3, trunk_h + 0.55, Color(0.3, 0.52, 0.3), 1.0)
			_add_canopy(body, 0, 0.25, trunk_h + 1.15, Color(0.36, 0.58, 0.33), 0.72)

	var col := CollisionShape3D.new()
	var cshape := CylinderShape3D.new()
	cshape.radius = 0.24
	cshape.height = trunk_h * 0.9
	col.shape = cshape
	col.position.y = trunk_h * 0.45
	body.add_child(col)
	container.add_child(body)

func _add_canopy(body: StaticBody3D, layer: int, radius: float, height: float, color: Color, s: float, flat := false) -> void:
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	sph.radial_segments = 10
	sph.rings = 5
	var mi := MeshInstance3D.new()
	mi.mesh = sph
	mi.material_override = _mat(color, 1.0)
	var flat_scale := Vector3(1.6, 0.42, 1.6) if flat else Vector3.ONE
	mi.scale = flat_scale * (s * (0.85 + rng.randf() * 0.3))
	mi.position.y = height
	body.add_child(mi)

func _add_pine(body: StaticBody3D, trunk_h: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.9
	cone.height = 2.2
	cone.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.material_override = _mat(Color(0.2, 0.34, 0.3), 1.0)
	mi.position.y = trunk_h + 1.0
	mi.scale = Vector3.ONE * (0.8 + rng.randf() * 0.5)
	body.add_child(mi)

# ---------- 岩石（簇状 MultiMesh） ----------

func _spawn_rocks() -> void:
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.5
	rock_mesh.height = 1.0
	rock_mesh.radial_segments = 9
	rock_mesh.rings = 5
	var stone_mat := _mat(Color(0.45, 0.43, 0.47), 0.95)
	var moss_mat := _mat(Color(0.38, 0.46, 0.42), 0.95)
	var placed := 0
	var attempts := 0
	while placed < int(70 * _density) and attempts < 700:
		attempts += 1
		var p := _rand_pos(-78.0, 78.0, -78.0, 78.0)
		var biome := _terrain().biome_at(p.x, p.y)
		if biome == TerrainGenerator.BIOME_WETLANDS:
			continue
		if not _suitable(p.x, p.y, 0.6):
			continue
		if _near_village(p.x, p.y):
			continue
		if _near_major(p.x, p.y, 6.0):
			continue
		var y := _ground_y(p.x, p.y)
		# 每处 1~3 块岩石成簇，避免单调单石
		var cluster := rng.randi_range(1, 3)
		for c in cluster:
			var off := Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
			var px := p.x + off.x
			var pz := p.y + off.y
			if not _suitable(px, pz, 0.7):
				continue
			var py := _ground_y(px, pz)
			var s := 0.3 + rng.randf() * 0.55
			if biome == TerrainGenerator.BIOME_MOUNTAINS:
				s = 0.7 + rng.randf() * 1.2
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35)))
			var squash := Vector3(1.2, 0.72 + rng.randf() * 0.2, 1.0) * s
			# 每块岩石都是实体：可站立、不可穿透
			var body := StaticBody3D.new()
			body.position = Vector3(px, py + s * 0.1, pz)
			body.basis = b
			var mi := MeshInstance3D.new()
			mi.mesh = rock_mesh
			mi.material_override = moss_mat if (rng.randf() < 0.28 and biome != TerrainGenerator.BIOME_SAVANNA) else stone_mat
			mi.scale = squash
			body.add_child(mi)
			var col := CollisionShape3D.new()
			var cs := SphereShape3D.new()
			cs.radius = 0.58 * s
			col.shape = cs
			body.add_child(col)
			container.add_child(body)
		placed += 1

# ---------- 晶体（簇状 MultiMesh，发光） ----------

func _spawn_crystals() -> void:
	var crystal_mesh := CylinderMesh.new()
	crystal_mesh.top_radius = 0.0
	crystal_mesh.bottom_radius = 0.22
	crystal_mesh.height = 1.5
	crystal_mesh.radial_segments = 6
	var plans := [
		{"biome": TerrainGenerator.BIOME_WETLANDS, "count": int(34 * _density), "color": _accent},
		{"biome": TerrainGenerator.BIOME_SAVANNA, "count": int(26 * _density), "color": _accent2},
		{"biome": TerrainGenerator.BIOME_MOUNTAINS, "count": int(24 * _density), "color": Color(0.7, 0.4, 1.0)},
		{"biome": TerrainGenerator.BIOME_FOREST, "count": int(16 * _density), "color": Color(0.35, 1.0, 0.7)},
		{"biome": TerrainGenerator.BIOME_PLAINS, "count": int(10 * _density), "color": Color(0.3, 0.8, 1.0)},
		{"biome": TerrainGenerator.BIOME_RELIC, "count": int(22 * _density), "color": _glow}
	]
	for plan in plans:
		var transforms: Array = []
		var sites: Array = []
		var placed := 0
		var attempts := 0
		while placed < int(plan["count"]) and attempts < 350:
			attempts += 1
			var p := _rand_pos(-78.0, 78.0, -78.0, 78.0)
			if _terrain().biome_at(p.x, p.y) != int(plan["biome"]):
				continue
			if not _suitable(p.x, p.y, 0.7):
				continue
			if _near_major(p.x, p.y, 5.0):
				continue
			var y := _ground_y(p.x, p.y)
			# 每处 2~4 根晶体成簇，高度错落
			var cluster := rng.randi_range(2, 4)
			for c in cluster:
				var off := Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
				var px := p.x + off.x
				var pz := p.y + off.y
				var py := _ground_y(px, pz)
				var s := 0.45 + rng.randf() * 1.05
				var b := Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15)))
				transforms.append(Transform3D(b.scaled(Vector3.ONE * s), Vector3(px, py + s * 0.62, pz)))
			sites.append(Vector3(p.x, y, p.y))
			placed += 1
		var color: Color = plan["color"]
		var mat := _mat(color.darkened(0.35), 0.4, 0.3, color, 1.4)
		_add_multimesh(crystal_mesh, mat, transforms, false)
		# 晶体簇是实体：每处一个碰撞柱，不可直接穿过
		for site_pos in sites:
			var body := StaticBody3D.new()
			body.position = Vector3(site_pos.x, site_pos.y + 0.75, site_pos.z)
			var col := CollisionShape3D.new()
			var cs := CylinderShape3D.new()
			cs.radius = 0.6
			cs.height = 1.5
			col.shape = cs
			body.add_child(col)
			container.add_child(body)

# ---------- 石板广场（亚特兰蒂斯同心圆广场） ----------

func _spawn_pavements() -> void:
	var count := int(3 * _density)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 90:
		attempts += 1
		var site := _find_open_site([TerrainGenerator.BIOME_RELIC, TerrainGenerator.BIOME_PLAINS], 24.0, 8.0)
		if site == Vector3.INF:
			continue
		_spawn_pavement(site)
		placed += 1

func _spawn_pavement(center: Vector3) -> void:
	var y := _ground_y(center.x, center.z)
	var radius := 4.0 + rng.randf() * 3.0
	var slab_mat := _mat(_stone.lightened(0.12), 0.9)
	# 三层同心石盘，边缘有台阶感
	for i in 3:
		var r := radius * (1.0 - i * 0.28)
		var disc := CylinderMesh.new()
		disc.top_radius = r
		disc.bottom_radius = r * 1.05
		disc.height = 0.34 + i * 0.16
		disc.radial_segments = 28
		var disc_col := CylinderShape3D.new()
		disc_col.radius = r * 1.05
		disc_col.height = 0.34 + i * 0.16
		_add_static(disc, slab_mat, Vector3(center.x, y + 0.17 + i * 0.16, center.z), Vector3.ZERO, Vector3.ONE, disc_col, Vector3.ZERO)
	# 内圈发光沟槽
	var groove := TorusMesh.new()
	groove.inner_radius = radius * 0.4
	groove.outer_radius = radius * 0.42
	groove.rings = 20
	groove.ring_segments = 8
	_add_visual(groove, _glow_mat(_accent, 1.6), Vector3(center.x, y + 0.72, center.z), Vector3(90, 0, 0))
	# 中央祭台与辉光晶体
	var altar := CylinderMesh.new()
	altar.top_radius = 0.9
	altar.bottom_radius = 1.05
	altar.height = 0.9
	altar.radial_segments = 16
	var altar_col := CylinderShape3D.new()
	altar_col.radius = 1.05
	altar_col.height = 0.9
	_add_static(altar, _mat(_stone, 0.85), Vector3(center.x, y + 0.72, center.z), Vector3.ZERO, Vector3.ONE, altar_col, Vector3.ZERO)
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 0.34
	crystal.height = 1.8
	crystal.radial_segments = 6
	_add_visual(crystal, _glow_mat(_glow, 1.8), Vector3(center.x, y + 2.0, center.z))
	_add_spirit_particles(center + Vector3(0, 2.2, 0), _glow)

# ---------- 拱门（古代石门） ----------

func _spawn_arches() -> void:
	var count := int(3 * _density)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 90:
		attempts += 1
		var site := _find_open_site([TerrainGenerator.BIOME_RELIC, TerrainGenerator.BIOME_SAVANNA], 26.0, 7.0)
		if site == Vector3.INF:
			continue
		_spawn_arch(site)
		placed += 1

func _spawn_arch(center: Vector3) -> void:
	var y := _ground_y(center.x, center.z)
	var span := 3.6 + rng.randf() * 1.6
	var h := 2.6 + rng.randf() * 1.2
	var stone_mat := _mat(_stone, 0.9)
	var broken := rng.randf() < 0.4
	for side in [-1.0, 1.0]:
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.28
		pillar.bottom_radius = 0.4
		pillar.height = h
		pillar.radial_segments = 12
		var col := CylinderShape3D.new()
		col.radius = 0.34
		col.height = h
		_add_static(pillar, stone_mat, Vector3(center.x + side * span * 0.5, y + h / 2.0, center.z), Vector3(0, 0, rng.randf_range(-6, 6) if side < 0 else 0), Vector3.ONE, col, Vector3.ZERO)
		# 柱头
		var cap := CylinderMesh.new()
		cap.top_radius = 0.4
		cap.bottom_radius = 0.46
		cap.height = 0.28
		cap.radial_segments = 12
		_add_visual(cap, stone_mat, Vector3(center.x + side * span * 0.5, y + h + 0.12, center.z))
	if not broken:
		# 完整楣梁
		var lintel := BoxMesh.new()
		lintel.size = Vector3(span + 0.7, 0.55, 0.6)
		var lintel_col := BoxShape3D.new()
		lintel_col.size = Vector3(span + 0.7, 0.55, 0.6)
		_add_static(lintel, stone_mat, Vector3(center.x, y + h + 0.45, center.z), Vector3.ZERO, Vector3.ONE, lintel_col, Vector3.ZERO)
		var rune := BoxMesh.new()
		rune.size = Vector3(span * 0.55, 0.14, 0.12)
		_add_visual(rune, _glow_mat(_accent, 1.5), Vector3(center.x, y + h + 0.45, center.z + 0.33))
	else:
		# 断裂的横梁斜插在旁
		var beam := BoxMesh.new()
		beam.size = Vector3(span * 0.55, 0.45, 0.5)
		_add_visual(beam, stone_mat, Vector3(center.x + span * 0.35, y + 0.5, center.z + 0.5), Vector3(0, rng.randf() * 360, 28))

# ---------- 方尖碑（四面棱碑 + 符文带 + 顶端辉光） ----------

func _spawn_obelisks() -> void:
	var count := int(4 * _density)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 120:
		attempts += 1
		var site := _find_open_site([TerrainGenerator.BIOME_RELIC, TerrainGenerator.BIOME_SAVANNA, TerrainGenerator.BIOME_PLAINS], 22.0, 5.0)
		if site == Vector3.INF:
			continue
		_spawn_obelisk(site)
		placed += 1

func _spawn_obelisk(center: Vector3) -> void:
	var y := _ground_y(center.x, center.z)
	var h := 3.2 + rng.randf() * 2.2
	var obelisk := CylinderMesh.new()
	obelisk.top_radius = 0.16
	obelisk.bottom_radius = 0.62
	obelisk.height = h
	obelisk.radial_segments = 4
	var col := CylinderShape3D.new()
	col.radius = 0.45
	col.height = h
	_add_static(obelisk, _mat(_stone.lightened(0.06), 0.88), Vector3(center.x, y + h / 2.0, center.z), Vector3(0, rng.randf() * 90, 0), Vector3.ONE, col, Vector3.ZERO)
	# 金字塔尖
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.18
	tip.height = 0.7
	tip.radial_segments = 4
	_add_visual(tip, _mat(_stone, 0.85), Vector3(center.x, y + h + 0.3, center.z), Vector3(0, rng.randf() * 90, 0))
	# 中部符文环
	var band := BoxMesh.new()
	band.size = Vector3(0.72, 0.22, 0.72)
	_add_visual(band, _glow_mat(_accent, 1.4), Vector3(center.x, y + h * 0.55, center.z))
	# 顶端辉光晶体
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 0.16
	crystal.height = 0.85
	crystal.radial_segments = 5
	_add_visual(crystal, _glow_mat(_glow, 1.7), Vector3(center.x, y + h + 0.75, center.z))
	_add_spirit_particles(center + Vector3(0, h + 1.0, 0), _glow)

# ---------- 古石阵（巨柱阵 + 楣梁 + 中央祭石） ----------

func _spawn_menhir_circles(count: int) -> void:
	for i in count:
		var site := _find_open_site([TerrainGenerator.BIOME_PLAINS, TerrainGenerator.BIOME_FOREST, TerrainGenerator.BIOME_WETLANDS], 34.0, 12.0)
		if site == Vector3.INF:
			continue
		_spawn_menhir_circle(site)

func _spawn_menhir_circle(center: Vector3) -> void:
	var stones := rng.randi_range(7, 9)
	var radius := 6.0 + rng.randf() * 2.0
	var stone_mat := _mat(_stone, 0.9)
	var trilithon_every := rng.randi_range(3, 4)
	for i in stones:
		var ang := TAU / stones * i + rng.randf() * 0.4
		var px := center.x + cos(ang) * radius
		var pz := center.z + sin(ang) * radius
		var py := _ground_y(px, pz)
		var h := rng.randf_range(2.8, 4.6)
		var col := CylinderShape3D.new()
		col.radius = 0.34
		col.height = h
		var st := CylinderMesh.new()
		st.top_radius = 0.3
		st.bottom_radius = 0.44
		st.height = h
		st.radial_segments = 10
		_add_static(st, stone_mat, Vector3(px, py + h / 2.0, pz), Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8)), Vector3.ONE, col, Vector3.ZERO)
		# 每隔几根立柱放一块楣梁，形成三石牌坊
		if i % trilithon_every == 0:
			var next_ang := TAU / stones * ((i + 1) % stones) + rng.randf() * 0.4
			var nx2 := center.x + cos(next_ang) * radius
			var nz2 := center.z + sin(next_ang) * radius
			var mid := Vector2((px + nx2) * 0.5, (pz + nz2) * 0.5)
			var my := _ground_y(mid.x, mid.y)
			var lintel := BoxMesh.new()
			lintel.size = Vector3(2.3, 0.42, 0.55)
			var look := atan2(nz2 - pz, nx2 - px)
			_add_visual(lintel, stone_mat, Vector3(mid.x, my + h * 0.85, mid.y), Vector3(0, rad_to_deg(look), 0))
	# 中央祭石与幽光晶体
	var alt_y := _ground_y(center.x, center.z)
	var slab := CylinderMesh.new()
	slab.top_radius = 1.15
	slab.bottom_radius = 1.3
	slab.height = 0.5
	slab.radial_segments = 16
	var slab_col := CylinderShape3D.new()
	slab_col.radius = 1.3
	slab_col.height = 0.5
	_add_static(slab, _mat(_stone.lightened(0.08), 0.85), Vector3(center.x, alt_y + 0.25, center.z), Vector3.ZERO, Vector3.ONE, slab_col, Vector3.ZERO)
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 0.42
	crystal.height = 2.0
	crystal.radial_segments = 6
	var cmat := _glow_mat(_glow, 1.7)
	_add_visual(crystal, cmat, Vector3(center.x, alt_y + 1.4, center.z))
	_add_spirit_particles(center + Vector3(0, 1.5, 0), _glow)

# ---------- 遗迹 ----------

func _spawn_ruins(count: int) -> void:
	for i in count:
		var site := _find_open_site([TerrainGenerator.BIOME_MOUNTAINS, TerrainGenerator.BIOME_SAVANNA, TerrainGenerator.BIOME_RELIC], 30.0, 10.0)
		if site == Vector3.INF:
			continue
		_spawn_ruin_group(site)

func _spawn_ruin_group(center: Vector3) -> void:
	_add_scorch(center, 4.5 + rng.randf() * 2.0)
	_add_fissures(center, rng.randi_range(2, 4))
	_add_debris(center, rng.randi_range(2, 4), 6.0)
	var stone_mat := _mat(_stone, 0.92)
	var moss_mat := _mat(_stone.darkened(0.15).lerp(Color(0.4, 0.44, 0.42), 0.45), 0.95)
	for i in rng.randi_range(4, 6):
		var off := Vector3(rng.randf_range(-5.0, 5.0), 0, rng.randf_range(-5.0, 5.0))
		var px := center.x + off.x
		var pz := center.z + off.z
		var py := _ground_y(px, pz)
		var h := rng.randf_range(1.1, 3.6)
		var col := CylinderShape3D.new()
		col.radius = 0.42
		col.height = h
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.36
		pillar.bottom_radius = 0.5
		pillar.height = h
		pillar.radial_segments = 12
		var tilt := Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
		_add_static(pillar, stone_mat if rng.randf() < 0.65 else moss_mat, Vector3(px, py + h / 2.0, pz), tilt, Vector3.ONE, col, Vector3.ZERO)
		# 部分柱顶有柱头
		if rng.randf() < 0.45:
			var cap := CylinderMesh.new()
			cap.top_radius = 0.44
			cap.bottom_radius = 0.52
			cap.height = 0.26
			cap.radial_segments = 12
			_add_visual(cap, stone_mat, Vector3(px, py + h + 0.1, pz))
		# 残柱上的幽光符文
		if rng.randf() < 0.42:
			var rune := BoxMesh.new()
			rune.size = Vector3(0.7, 0.16, 0.16)
			var rmat := _glow_mat(_accent, 1.4)
			_add_visual(rune, rmat, Vector3(px, py + h * 0.75, pz + 0.44), Vector3(0, rng.randf_range(-30, 30), 0))
	# 倾倒的石板与碎石
	for i in rng.randi_range(2, 4):
		var sx := center.x + rng.randf_range(-3.5, 3.5)
		var sz := center.z + rng.randf_range(-3.5, 3.5)
		var sy := _ground_y(sx, sz)
		var slab := BoxMesh.new()
		slab.size = Vector3(rng.randf_range(1.6, 3.0), 0.42, rng.randf_range(0.9, 1.4))
		var mat := stone_mat if rng.randf() < 0.6 else moss_mat
		var slab_col := BoxShape3D.new()
		slab_col.size = slab.size
		_add_static(slab, mat, Vector3(sx, sy + 0.25, sz), Vector3(0, rng.randf() * 360, rng.randf_range(65, 95)), Vector3.ONE, slab_col, Vector3.ZERO)
	# 遗迹中心的“能量残骸”
	if rng.randf() < 0.7:
		_spawn_machine_core(center, 0.8 + rng.randf() * 0.5)

# ---------- 古代机械（齿轮/环机构，科技浓度越高越多） ----------

func _spawn_machines() -> void:
	if _tech < 0.2:
		return
	var count := int(3.0 * _density * _tech)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 90:
		attempts += 1
		var site := _find_open_site([TerrainGenerator.BIOME_RELIC, TerrainGenerator.BIOME_SAVANNA, TerrainGenerator.BIOME_PLAINS], 26.0, 7.0)
		if site == Vector3.INF:
			continue
		_spawn_machine_core(site, 0.8 + rng.randf() * 0.7)
		placed += 1

func _spawn_machine_core(center: Vector3, scale: float) -> void:
	var y := _ground_y(center.x, center.z)
	var metal := _mat(_stone.darkened(0.2).lerp(_accent.darkened(0.55), 0.15), 0.5, 0.6)
	# 底座
	var base := CylinderMesh.new()
	base.top_radius = 0.9 * scale
	base.bottom_radius = 1.05 * scale
	base.height = 0.55 * scale
	base.radial_segments = 14
	var base_col := CylinderShape3D.new()
	base_col.radius = 1.05 * scale
	base_col.height = 0.55 * scale
	_add_static(base, metal, Vector3(center.x, y + 0.28 * scale, center.z), Vector3.ZERO, Vector3.ONE, base_col, Vector3.ZERO)
	# 齿轮组（多层）
	for i in 3:
		var gear := CylinderMesh.new()
		gear.top_radius = (0.55 - i * 0.12) * scale
		gear.bottom_radius = (0.55 - i * 0.12) * scale
		gear.height = 0.16 * scale
		gear.radial_segments = 12
		var gy := y + (0.6 + i * 0.3) * scale
		var gx := center.x + cos(i * 2.1) * 0.28 * scale
		var gz := center.z + sin(i * 2.1) * 0.28 * scale
		_add_visual(gear, metal, Vector3(gx, gy, gz), Vector3(0, rng.randf() * 60, 0))
	# 转动的环带（托鲁斯）
	for i in 2:
		var ring := TorusMesh.new()
		ring.inner_radius = (0.75 + i * 0.14) * scale
		ring.outer_radius = (0.78 + i * 0.14) * scale
		ring.rings = 24
		ring.ring_segments = 8
		var holder := Node3D.new()
		holder.position = Vector3(center.x, y + (1.0 + i * 0.28) * scale, center.z)
		holder.rotation_degrees = Vector3(90, 0, rng.randf() * 360)
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = _glow_mat(_accent, 1.3)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		container.add_child(holder)
		var rot := _Rotator.new()
		rot.setup((0.5 + i * 0.3) * (1.0 if i % 2 == 0 else -1.0))
		holder.add_child(rot)
	# 核心辉光晶体与光
	var core := CylinderMesh.new()
	core.top_radius = 0.0
	core.bottom_radius = 0.26 * scale
	core.height = 1.0 * scale
	core.radial_segments = 6
	_add_visual(core, _glow_mat(_glow, 2.0), Vector3(center.x, y + (1.35 + 0.5) * scale, center.z))
	var light := OmniLight3D.new()
	light.light_color = _glow
	light.light_energy = 1.0
	light.omni_range = 7.0 * scale
	light.position = Vector3(center.x, y + 1.6 * scale, center.z)
	light.shadow_enabled = false
	container.add_child(light)
	var pulse := _Pulse.new()
	pulse.setup(light, null)
	light.add_child(pulse)
	_add_spirit_particles(center + Vector3(0, 1.8 * scale, 0), _glow)
	_add_orb(center + Vector3(0, (1.35 + 0.5) * scale, 0), "orbit", 1.2 * scale, 0.8, _glow)

# ---------- 同心阶梯台地（水边亚特兰蒂斯式） ----------

func _spawn_terraces() -> void:
	var count := int(2.5 * _density)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 70:
		attempts += 1
		var p := _rand_pos(-66.0, 66.0, -66.0, 66.0)
		if Vector2(p.x, p.y).length() < 20.0:
			continue
		if not _suitable(p.x, p.y, 0.3):
			continue
		if _near_village(p.x, p.y):
			continue
		_spawn_terrace(p)
		placed += 1

func _spawn_terrace(p: Vector2) -> void:
	var y := _ground_y(p.x, p.y)
	var stone_mat := _mat(_stone.lightened(0.1), 0.9)
	for i in 3:
		var r := 5.0 - i * 1.35
		var disc := CylinderMesh.new()
		disc.top_radius = r
		disc.bottom_radius = r * 1.04
		disc.height = 0.5 + i * 0.22
		disc.radial_segments = 26
		var disc_col := CylinderShape3D.new()
		disc_col.radius = r * 1.04
		disc_col.height = 0.5 + i * 0.22
		_add_static(disc, stone_mat, Vector3(p.x, y + 0.25 + i * 0.22, p.y), Vector3.ZERO, Vector3.ONE, disc_col, Vector3.ZERO)
		var rim := TorusMesh.new()
		rim.inner_radius = r * 0.92
		rim.outer_radius = r * 0.94
		rim.rings = 20
		rim.ring_segments = 8
		_add_visual(rim, _glow_mat(_accent, 1.2), Vector3(p.x, y + 0.5 + i * 0.22, p.y), Vector3(90, 0, 0))
	var center_crystal := CylinderMesh.new()
	center_crystal.top_radius = 0.0
	center_crystal.bottom_radius = 0.3
	center_crystal.height = 1.7
	center_crystal.radial_segments = 6
	_add_visual(center_crystal, _glow_mat(_glow, 1.7), Vector3(p.x, y + 1.9, p.y))

# ---------- 光柱（遗迹圣所的垂直光柱） ----------

func _spawn_light_shafts() -> void:
	var count := int(3.5 * _density)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 100:
		attempts += 1
		var site := _find_open_site([TerrainGenerator.BIOME_RELIC, TerrainGenerator.BIOME_PLAINS], 30.0, 5.0)
		if site == Vector3.INF:
			continue
		_spawn_light_shaft(site)
		placed += 1

func _spawn_light_shaft(center: Vector3) -> void:
	var y := _ground_y(center.x, center.z)
	var h := 8.0 + rng.randf() * 4.0
	var beam := CylinderMesh.new()
	beam.top_radius = 0.5
	beam.bottom_radius = 0.85
	beam.height = h
	beam.radial_segments = 12
	_add_visual(beam, _beam_mat(_glow, 2.4), Vector3(center.x, y + h / 2.0, center.z), Vector3.ZERO, Vector3.ONE, false)
	var halo := TorusMesh.new()
	halo.inner_radius = 1.15
	halo.outer_radius = 1.2
	halo.rings = 24
	halo.ring_segments = 8
	_add_visual(halo, _beam_mat(_glow, 2.0), Vector3(center.x, y + 0.55, center.z), Vector3(90, 0, 0), Vector3.ONE, false)
	_add_spirit_particles(center + Vector3(0, 0.6, 0), _glow)
	var light := OmniLight3D.new()
	light.light_color = _glow
	light.light_energy = 0.8
	light.omni_range = 9.0
	light.position = Vector3(center.x, y + h * 0.6, center.z)
	light.shadow_enabled = false
	container.add_child(light)

# ---------- 能量管道（连接晶体簇的地面辉光线） ----------

func _spawn_energy_conduits() -> void:
	if _tech < 0.3:
		return
	var count := int(2.0 * _density * _tech)
	var anchors: Array = []
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 120:
		attempts += 1
		var a := _find_open_site([TerrainGenerator.BIOME_RELIC, TerrainGenerator.BIOME_WETLANDS, TerrainGenerator.BIOME_PLAINS], 18.0, 4.0)
		if a == Vector3.INF:
			continue
		var b := _find_open_site([TerrainGenerator.BIOME_RELIC, TerrainGenerator.BIOME_WETLANDS, TerrainGenerator.BIOME_PLAINS], 18.0, 4.0)
		if b == Vector3.INF:
			continue
		if Vector2(a.x - b.x, a.z - b.z).length() < 8.0 or Vector2(a.x - b.x, a.z - b.z).length() > 24.0:
			continue
		anchors.append([a, b])
		placed += 1
	for pair in anchors:
		_spawn_conduit(pair[0], pair[1])

func _spawn_conduit(a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5
	var len := Vector2(a.x - b.x, a.z - b.z).length()
	var y := _ground_y(mid.x, mid.z)
	var conduit := BoxMesh.new()
	conduit.size = Vector3(len, 0.09, 0.12)
	var angle := atan2(b.x - a.x, b.z - a.z)
	var conduit_col := BoxShape3D.new()
	conduit_col.size = Vector3(len, 0.09, 0.12)
	_add_static(conduit, _glow_mat(_accent, 1.5), Vector3(mid.x, y + 0.06, mid.z), Vector3(0, rad_to_deg(angle) - 90, 0), Vector3.ONE, conduit_col, Vector3.ZERO)
	# 两端节点
	for p in [a, b]:
		var node := CylinderMesh.new()
		node.top_radius = 0.18
		node.bottom_radius = 0.22
		node.height = 0.34
		node.radial_segments = 10
		var node_col := CylinderShape3D.new()
		node_col.radius = 0.22
		node_col.height = 0.34
		_add_static(node, _glow_mat(_glow, 1.6), Vector3(p.x, _ground_y(p.x, p.z) + 0.18, p.z), Vector3.ZERO, Vector3.ONE, node_col, Vector3.ZERO)

# ---------- 浮空辉光（远古能源环绕的“圣所”节点） ----------

func _spawn_relic_glows() -> void:
	var count := int(2.5 * _density)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 70:
		attempts += 1
		var site := _find_open_site([TerrainGenerator.BIOME_RELIC, TerrainGenerator.BIOME_FOREST], 28.0, 6.0)
		if site == Vector3.INF:
			continue
		_spawn_relic_glow(site)
		placed += 1

func _spawn_relic_glow(center: Vector3) -> void:
	var glow := RelicGlow.new()
	glow.position = center
	glow.setup(_glow, 3, 2.2 + rng.randf() * 1.0, true)
	container.add_child(glow)
	# 环绕晶体环：为圣所节点增加结构感
	for i in 6:
		var ang := TAU / 6.0 * i + rng.randf() * 0.2
		var px := center.x + cos(ang) * 3.2
		var pz := center.z + sin(ang) * 3.2
		var py := _ground_y(px, pz)
		var crystal := CylinderMesh.new()
		crystal.top_radius = 0.0
		crystal.bottom_radius = 0.18
		crystal.height = 0.9 + rng.randf() * 0.5
		crystal.radial_segments = 6
		_add_visual(crystal, _glow_mat(_glow, 1.3), Vector3(px, py + 0.5, pz), Vector3(0, 0, rng.randf_range(-10, 10)))
	# 轨道能量体：圣所的能量缓慢环绕
	_add_orb(center + Vector3(0, 1.5, 0), "orbit", 2.4, 0.7, _glow)

# ---------- 丰碑系统：七大奇迹 × 数学美感 ----------

func _spawn_wonders() -> void:
	## 丰碑优先锚定在任务建筑/聚落附近，其余再随机落在遗迹区。
	var anchors: Array = _objective_points.duplicate()
	var village_anchor := _objective_points.is_empty()
	if anchors.is_empty():
		for fid in CivilizationManager.faction_centers:
			anchors.append(CivilizationManager.faction_centers[fid])
	var count := mini(2, anchors.size())
	var placed := 0
	for i in count:
		var anchor: Vector3 = anchors[i % anchors.size()]
		var site := _find_wonder_site(anchor, village_anchor)
		if site == Vector3.INF:
			continue
		_spawn_wonder(_wonder_kind(placed), site)
		placed += 1

func _wonder_kind(index: int) -> String:
	var kinds: Array
	match _era_id:
		"era_wenwang":
			kinds = ["pyramid", "colonnade"]
		"era_mozi":
			kinds = ["gear_tower", "orrery"]
		"era_qinshihuang":
			kinds = ["pyramid", "obelisks"]
		"era_newton":
			kinds = ["orrery", "pharos"]
		"era_einstein":
			kinds = ["monolith_hall", "mandala"]
		_:
			kinds = ["pyramid", "colonnade"]
	return str(kinds[index % kinds.size()])

func _spawn_wonder(kind: String, center: Vector3) -> void:
	## 丰碑脚下先铺“末日废墟”底子：焦土、裂隙、碎块，再立起文明丰碑。
	_add_scorch(center, 7.0 + rng.randf() * 2.0)
	_add_fissures(center, rng.randi_range(4, 6))
	match kind:
		"pyramid":
			_build_pyramid(center)
		"colonnade":
			_build_colonnade(center)
		"orrery":
			_build_orrery(center)
		"pharos":
			_build_pharos(center)
		"mandala":
			_build_mandala(center)
		"gear_tower":
			_build_gear_tower(center)
		"obelisks":
			_build_obelisk_avenue(center)
		"monolith_hall":
			_build_monolith_hall(center)
	_add_debris(center, rng.randi_range(4, 7), 9.0)
	_add_embers(center, _accent2)

func _build_pyramid(center: Vector3) -> void:
	## 阶梯金字塔：层叠石台 + 金字塔尖 + 顶部光核与轨道能量体
	var y := _ground_y(center.x, center.z)
	var stone_mat := _mat(_stone, 0.9)
	var moss_mat := _mat(_stone.darkened(0.12).lerp(Color(0.4, 0.44, 0.42), 0.4), 0.95)
	var s := 8.0 + rng.randf() * 2.0
	for i in 5:
		var t := float(i) / 4.0
		var layer_w := s * (1.0 - t * 0.78)
		var layer_h := 1.6
		var step_mesh := CylinderMesh.new()
		step_mesh.top_radius = layer_w * 0.9
		step_mesh.bottom_radius = layer_w
		step_mesh.height = layer_h
		step_mesh.radial_segments = 4
		var mat := stone_mat if rng.randf() < 0.7 else moss_mat
		var step_col := CylinderShape3D.new()
		step_col.radius = layer_w
		step_col.height = layer_h
		_add_static(step_mesh, mat, Vector3(center.x, y + layer_h / 2.0 + i * layer_h * 0.92, center.z), Vector3(0, 45.0 * (i % 2), 0), Vector3.ONE, step_col, Vector3.ZERO)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.0
	cap.bottom_radius = s * 0.2
	cap.height = 2.4
	cap.radial_segments = 4
	var cap_col := CylinderShape3D.new()
	cap_col.radius = s * 0.24
	cap_col.height = 2.4
	_add_static(cap, stone_mat, Vector3(center.x, y + 5.0 * 1.6 * 0.92 + 1.2, center.z), Vector3(0, 45.0, 0), Vector3.ONE, cap_col, Vector3.ZERO)
	var core := CylinderMesh.new()
	core.top_radius = 0.0
	core.bottom_radius = 0.4
	core.height = 2.2
	core.radial_segments = 6
	_add_visual(core, _glow_mat(_glow, 2.2), Vector3(center.x, y + 9.4, center.z))
	_add_orb(center + Vector3(0, 10.2, 0), "orbit", 2.2, 0.9, _glow)
	var light := OmniLight3D.new()
	light.light_color = _glow
	light.light_energy = 1.2
	light.omni_range = 14.0
	light.position = Vector3(center.x, y + 9.5, center.z)
	light.shadow_enabled = false
	container.add_child(light)
	_add_spirit_particles(center + Vector3(0, 9.2, 0), _glow)

func _build_colonnade(center: Vector3) -> void:
	## 巨石柱廊：两排多立克式柱 + 楣梁，能量体沿廊道巡逻
	var y := _ground_y(center.x, center.z)
	var stone_mat := _mat(_stone, 0.9)
	var span := 14.0 + rng.randf() * 3.0
	var cols := 7
	var spacing := span / float(cols - 1)
	for r in 2:
		var rz := -3.2 if r == 0 else 3.2
		for c in cols:
			var px := center.x - span / 2.0 + spacing * c
			var pz := center.z + rz
			var broken := rng.randf() < 0.22
			var h := 4.4 - (rng.randf() * 1.2 if broken else 0.0)
			var tilt := Vector3(0, 0, rng.randf_range(-14, 14) if broken else rng.randf_range(-2, 2))
			for seg in 3:
				var drum := CylinderMesh.new()
				drum.top_radius = 0.34
				drum.bottom_radius = 0.38
				drum.height = h / 3.0
				drum.radial_segments = 12
				var drum_col := CylinderShape3D.new()
				drum_col.radius = 0.4
				drum_col.height = h / 3.0
				_add_static(drum, stone_mat, Vector3(px, y + h * (float(seg) + 0.5) / 3.0, pz), tilt, Vector3.ONE, drum_col, Vector3.ZERO)
			if not broken:
				var cap := CylinderMesh.new()
				cap.top_radius = 0.42
				cap.bottom_radius = 0.5
				cap.height = 0.3
				cap.radial_segments = 12
				_add_visual(cap, stone_mat, Vector3(px, y + h + 0.12, pz), Vector3.ZERO)
		var beam := BoxMesh.new()
		beam.size = Vector3(span, 0.5, 0.55)
		var beam_col := BoxShape3D.new()
		beam_col.size = Vector3(span, 0.5, 0.55)
		_add_static(beam, stone_mat, Vector3(center.x, y + 4.7, center.z + rz), Vector3.ZERO, Vector3.ONE, beam_col, Vector3.ZERO)
	var rune := BoxMesh.new()
	rune.size = Vector3(span * 0.7, 0.18, 0.14)
	_add_visual(rune, _glow_mat(_accent, 1.5), Vector3(center.x, y + 4.75, center.z + 3.2))
	var path: Array = []
	for c in cols:
		path.append(Vector3(center.x - span / 2.0 + spacing * c, y + 1.7, center.z))
	var orb := EnergyOrb.new()
	orb.setup(_glow, "patrol", 1.0, 0.8, 0.4)
	orb.set_path(path)
	container.add_child(orb)

func _build_orrery(center: Vector3) -> void:
	## 太阳系仪：倾斜旋转轨道环 + 行星能量体，数学轨道之美
	var y := _ground_y(center.x, center.z)
	var metal := _mat(_stone.darkened(0.2).lerp(_accent.darkened(0.55), 0.2), 0.45, 0.65)
	var base := CylinderMesh.new()
	base.top_radius = 6.0
	base.bottom_radius = 6.5
	base.height = 0.5
	base.radial_segments = 24
	var base_col := CylinderShape3D.new()
	base_col.radius = 6.5
	base_col.height = 0.5
	_add_static(base, metal, Vector3(center.x, y + 0.25, center.z), Vector3.ZERO, Vector3.ONE, base_col, Vector3.ZERO)
	for i in 3:
		var ring := TorusMesh.new()
		var r := 2.4 + i * 1.2
		ring.inner_radius = r
		ring.outer_radius = r + 0.1
		ring.rings = 32
		ring.ring_segments = 8
		var holder := Node3D.new()
		holder.position = Vector3(center.x, y + 1.6, center.z)
		holder.rotation_degrees = Vector3(90 + rng.randf_range(-22, 22), 0, rng.randf_range(-30, 30))
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = _glow_mat(_accent.lerp(_glow, 0.5), 1.4)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		container.add_child(holder)
		var rot := _Rotator.new()
		rot.setup((0.25 + i * 0.15) * (1.0 if i % 2 == 0 else -1.0))
		holder.add_child(rot)
	for i in 3:
		var orb := EnergyOrb.new()
		orb.setup(_accent2 if i == 1 else _glow, "orbit", 2.4 + i * 1.2, 0.6 + i * 0.25, 0.4)
		orb.set_center(center + Vector3(0, y + 1.6, 0))
		container.add_child(orb)
	var core := CylinderMesh.new()
	core.top_radius = 0.0
	core.bottom_radius = 0.5
	core.height = 1.6
	core.radial_segments = 6
	_add_visual(core, _glow_mat(_glow, 2.4), Vector3(center.x, y + 2.4, center.z))
	var light := OmniLight3D.new()
	light.light_color = _glow
	light.light_energy = 1.1
	light.omni_range = 12.0
	light.position = Vector3(center.x, y + 2.4, center.z)
	light.shadow_enabled = false
	container.add_child(light)

func _build_pharos(center: Vector3) -> void:
	## 灯塔巨塔：层叠塔身 + 旋转光束 + 沿塔升降的能量体
	var y := _ground_y(center.x, center.z)
	var stone_mat := _mat(_stone.lightened(0.08), 0.9)
	var h := 9.0 + rng.randf() * 2.0
	var tiers := 3
	for i in tiers:
		var t := float(i) / float(tiers - 1)
		var r := 2.4 - t * 1.1
		var tier_h := h / float(tiers)
		var cyl := CylinderMesh.new()
		cyl.top_radius = r * 0.82
		cyl.bottom_radius = r
		cyl.height = tier_h
		cyl.radial_segments = 10
		var tier_col := CylinderShape3D.new()
		tier_col.radius = r
		tier_col.height = tier_h
		_add_static(cyl, stone_mat, Vector3(center.x, y + tier_h / 2.0 + i * tier_h, center.z), Vector3.ZERO, Vector3.ONE, tier_col, Vector3.ZERO)
		var ledge := CylinderMesh.new()
		ledge.top_radius = r * 1.05
		ledge.bottom_radius = r * 1.12
		ledge.height = 0.24
		ledge.radial_segments = 10
		_add_visual(ledge, stone_mat, Vector3(center.x, y + (i + 1) * tier_h, center.z))
	var lantern := CylinderMesh.new()
	lantern.top_radius = 0.9
	lantern.bottom_radius = 0.9
	lantern.height = 1.2
	lantern.radial_segments = 12
	var lantern_mat := _mat(_stone.darkened(0.15), 0.6, 0.4, _glow, 0.5)
	var lantern_col := CylinderShape3D.new()
	lantern_col.radius = 0.9
	lantern_col.height = 1.2
	_add_static(lantern, lantern_mat, Vector3(center.x, y + h + 0.6, center.z), Vector3.ZERO, Vector3.ONE, lantern_col, Vector3.ZERO)
	var beam_mi := MeshInstance3D.new()
	var beam_cyl := CylinderMesh.new()
	beam_cyl.top_radius = 0.5
	beam_cyl.bottom_radius = 2.4
	beam_cyl.height = 26.0
	beam_cyl.radial_segments = 12
	beam_mi.mesh = beam_cyl
	beam_mi.material_override = _beam_mat(_glow, 1.8)
	beam_mi.position = Vector3(0, 13.0, 0)
	var holder := Node3D.new()
	holder.position = Vector3(center.x, y + h + 0.6, center.z)
	holder.rotation_degrees = Vector3(78, 0, 0)
	holder.add_child(beam_mi)
	container.add_child(holder)
	var rot := _Rotator.new()
	rot.setup(0.35)
	holder.add_child(rot)
	var light := OmniLight3D.new()
	light.light_color = _glow
	light.light_energy = 1.4
	light.omni_range = 18.0
	light.position = Vector3(center.x, y + h + 1.2, center.z)
	light.shadow_enabled = false
	container.add_child(light)
	var path: Array = []
	for i in 5:
		path.append(Vector3(center.x, y + 0.8 + h * float(i) / 4.0, center.z))
	var orb := EnergyOrb.new()
	orb.setup(_accent2, "patrol", 1.0, 0.9, 0.2)
	orb.set_path(path)
	container.add_child(orb)
	_add_spirit_particles(center + Vector3(0, h + 1.2, 0), _glow)

func _build_mandala(center: Vector3) -> void:
	## 数学曼陀罗：12 辐对称 + 三圈界石（12/6/4）+ 斐波那契螺旋发光石
	var y := _ground_y(center.x, center.z)
	var stone_mat := _mat(_stone.lightened(0.1), 0.9)
	var R := 9.0
	var disc := CylinderMesh.new()
	disc.top_radius = 2.0
	disc.bottom_radius = 2.1
	disc.height = 0.4
	disc.radial_segments = 24
	var disc_col := CylinderShape3D.new()
	disc_col.radius = 2.1
	disc_col.height = 0.4
	_add_static(disc, stone_mat, Vector3(center.x, y + 0.2, center.z), Vector3.ZERO, Vector3.ONE, disc_col, Vector3.ZERO)
	for i in 12:
		var ang := TAU / 12.0 * i
		var spoke := BoxMesh.new()
		spoke.size = Vector3(6.4, 0.1, 0.34)
		var si := MeshInstance3D.new()
		si.mesh = spoke
		si.material_override = _mat(_stone, 0.9)
		si.position = Vector3(center.x + cos(ang) * 4.6, y + 0.24, center.z + sin(ang) * 4.6)
		si.rotation_degrees = Vector3(0, rad_to_deg(ang), 0)
		si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		container.add_child(si)
	var ring_defs := [
		{"count": 12, "radius": R, "size": 0.42},
		{"count": 6, "radius": R * 0.62, "size": 0.36},
		{"count": 4, "radius": R * 0.36, "size": 0.3}
	]
	for rd in ring_defs:
		for i in int(rd["count"]):
			var ang := TAU / int(rd["count"]) * i + rng.randf() * 0.05
			var px := center.x + cos(ang) * float(rd["radius"])
			var pz := center.z + sin(ang) * float(rd["radius"])
			var stone := CylinderMesh.new()
			stone.top_radius = float(rd["size"]) * 0.7
			stone.bottom_radius = float(rd["size"])
			stone.height = 0.7
			stone.radial_segments = 8
			var stone_col := CylinderShape3D.new()
			stone_col.radius = float(rd["size"]) * 1.05
			stone_col.height = 0.7
			_add_static(stone, stone_mat, Vector3(px, y + 0.35, pz), Vector3.ZERO, Vector3.ONE, stone_col, Vector3.ZERO)
	for i in 21:
		var radius := R * 0.3 * sqrt(float(i + 1)) / sqrt(21.0)
		var ang := float(i) * 2.399963
		var px := center.x + cos(ang) * radius
		var pz := center.z + sin(ang) * radius
		var stone := CylinderMesh.new()
		stone.top_radius = 0.1
		stone.bottom_radius = 0.14
		stone.height = 0.5
		stone.radial_segments = 6
		_add_visual(stone, _glow_mat(_accent, 1.4), Vector3(px, y + 0.25, pz), Vector3.ZERO, Vector3.ONE, false)
	var orb := EnergyOrb.new()
	orb.setup(_glow, "hover", 0.0, 1.2, 0.9)
	orb.set_center(center + Vector3(0, y + 2.2, 0))
	container.add_child(orb)
	_add_spirit_particles(center + Vector3(0, 2.2, 0), _glow)

func _build_gear_tower(center: Vector3) -> void:
	## 齿轮巨塔：层叠旋转齿轮环的机械丰碑
	var y := _ground_y(center.x, center.z)
	var metal := _mat(_stone.darkened(0.18).lerp(_accent.darkened(0.5), 0.2), 0.45, 0.6)
	var h := 7.0
	var tower := CylinderMesh.new()
	tower.top_radius = 0.55
	tower.bottom_radius = 0.8
	tower.height = h
	tower.radial_segments = 10
	var tower_col := CylinderShape3D.new()
	tower_col.radius = 0.8
	tower_col.height = h
	_add_static(tower, metal, Vector3(center.x, y + h / 2.0, center.z), Vector3.ZERO, Vector3.ONE, tower_col, Vector3.ZERO)
	for i in 6:
		var gear := CylinderMesh.new()
		var r := 1.5 + (i % 3) * 0.35
		gear.top_radius = r
		gear.bottom_radius = r
		gear.height = 0.22
		gear.radial_segments = 14
		var holder := Node3D.new()
		holder.position = Vector3(center.x, y + 1.2 + h * float(i) / 6.0, center.z)
		var mi := MeshInstance3D.new()
		mi.mesh = gear
		mi.material_override = _glow_mat(_accent.lerp(_glow, 0.35), 1.2)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		container.add_child(holder)
		var rot := _Rotator.new()
		rot.setup(0.4 + i * 0.18)
		holder.add_child(rot)
	var orb := EnergyOrb.new()
	orb.setup(_glow, "orbit", 1.8, 1.0, 0.6)
	orb.set_center(center + Vector3(0, y + h + 0.6, 0))
	container.add_child(orb)
	var light := OmniLight3D.new()
	light.light_color = _glow
	light.light_energy = 1.1
	light.omni_range = 12.0
	light.position = Vector3(center.x, y + h, center.z)
	light.shadow_enabled = false
	container.add_child(light)

func _build_obelisk_avenue(center: Vector3) -> void:
	## 方尖碑大道：两排金色分割排列的方尖碑 + 辉光大路 + 尽头巨门
	var y := _ground_y(center.x, center.z)
	var stone_mat := _mat(_stone, 0.9)
	var span := 18.0
	for r in 2:
		var rz := -4.2 if r == 0 else 4.2
		for c in 5:
			var px := center.x - span / 2.0 + span * 0.25 * c
			var broken := rng.randf() < 0.2
			var h := (4.0 + rng.randf() * 1.6) * (0.55 if broken else 1.0)
			var obelisk := CylinderMesh.new()
			obelisk.top_radius = 0.16
			obelisk.bottom_radius = 0.55
			obelisk.height = h
			obelisk.radial_segments = 4
			var ob_col := CylinderShape3D.new()
			ob_col.radius = 0.55
			ob_col.height = h
			_add_static(obelisk, stone_mat, Vector3(px, y + h / 2.0, center.z + rz), Vector3(0, rng.randf() * 90, rng.randf_range(-8, 8) if broken else 0), Vector3.ONE, ob_col, Vector3.ZERO)
			if not broken:
				var crystal := CylinderMesh.new()
				crystal.top_radius = 0.0
				crystal.bottom_radius = 0.14
				crystal.height = 0.7
				crystal.radial_segments = 5
				_add_visual(crystal, _glow_mat(_glow, 1.5), Vector3(px, y + h + 0.35, center.z + rz))
	var strip := BoxMesh.new()
	strip.size = Vector3(span * 0.86, 0.08, 1.4)
	_add_visual(strip, _glow_mat(_accent.darkened(0.25), 1.1), Vector3(center.x, y + 0.06, center.z), Vector3.ZERO, Vector3.ONE, false)
	_spawn_arch(center + Vector3(span * 0.62, 0, 0))
	var path: Array = [
		Vector3(center.x - span * 0.4, y + 1.4, center.z),
		Vector3(center.x + span * 0.4, y + 1.4, center.z)
	]
	var orb := EnergyOrb.new()
	orb.setup(_accent2, "patrol", 1.0, 0.8, 0.5)
	orb.set_path(path)
	container.add_child(orb)

func _build_monolith_hall(center: Vector3) -> void:
	## 巨石神殿：巨石环 + 楣梁 + 中央巨碑与环绕能量体
	var y := _ground_y(center.x, center.z)
	var stone_mat := _mat(_stone, 0.9)
	var R := 7.5
	for i in 12:
		var ang := TAU / 12.0 * i + rng.randf() * 0.05
		var px := center.x + cos(ang) * R
		var pz := center.z + sin(ang) * R
		var h := 4.6 + rng.randf() * 1.4
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.45
		pillar.bottom_radius = 0.62
		pillar.height = h
		pillar.radial_segments = 10
		var pillar_col := CylinderShape3D.new()
		pillar_col.radius = 0.62
		pillar_col.height = h
		_add_static(pillar, stone_mat, Vector3(px, y + h / 2.0, pz), Vector3(0, 0, rng.randf_range(-4, 4)), Vector3.ONE, pillar_col, Vector3.ZERO)
		if i % 3 == 0:
			var next_ang := TAU / 12.0 * ((i + 1) % 12)
			var nx2 := center.x + cos(next_ang) * R
			var nz2 := center.z + sin(next_ang) * R
			var mid := Vector2((px + nx2) * 0.5, (pz + nz2) * 0.5)
			var lintel := BoxMesh.new()
			lintel.size = Vector3(2.6, 0.5, 0.7)
			var look := atan2(nz2 - pz, nx2 - px)
			_add_visual(lintel, stone_mat, Vector3(mid.x, y + h * 0.82, mid.y), Vector3(0, rad_to_deg(look), 0))
	var stele := BoxMesh.new()
	stele.size = Vector3(1.6, 6.2, 0.7)
	var stele_col := BoxShape3D.new()
	stele_col.size = Vector3(1.6, 6.2, 0.7)
	_add_static(stele, stone_mat, Vector3(center.x, y + 3.1, center.z), Vector3(0, rng.randf() * 90, 0), Vector3.ONE, stele_col, Vector3.ZERO)
	var rune := BoxMesh.new()
	rune.size = Vector3(1.0, 3.2, 0.12)
	_add_visual(rune, _glow_mat(_glow, 2.0), Vector3(center.x, y + 3.2, center.z + 0.42), Vector3.ZERO, Vector3.ONE, false)
	for i in 3:
		var orb := EnergyOrb.new()
		orb.setup(_accent2 if i == 1 else _glow, "orbit", 2.0 + i * 0.8, 0.5 + i * 0.2, 0.5)
		orb.set_center(center + Vector3(0, y + 3.5, 0))
		container.add_child(orb)
	_add_spirit_particles(center + Vector3(0, 3.5, 0), _glow)

func _spawn_crystal_mandalas() -> void:
	## 斐波那契螺旋晶体花园：黄金角分布的晶簇，数学美感的结晶
	var count := int(2 * _density)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 80:
		attempts += 1
		var site := _find_open_site([TerrainGenerator.BIOME_RELIC, TerrainGenerator.BIOME_WETLANDS], 30.0, 8.0)
		if site == Vector3.INF:
			continue
		_build_crystal_mandala(site)
		placed += 1

func _build_crystal_mandala(center: Vector3) -> void:
	var y := _ground_y(center.x, center.z)
	var crystal_mesh := CylinderMesh.new()
	crystal_mesh.top_radius = 0.0
	crystal_mesh.bottom_radius = 0.2
	crystal_mesh.height = 1.2
	crystal_mesh.radial_segments = 6
	var transforms: Array = []
	for i in 21:
		var t := float(i) / 21.0
		var radius := 5.5 * sqrt(float(i + 1)) / sqrt(21.0)
		var ang := float(i) * 2.399963
		var px := center.x + cos(ang) * radius
		var pz := center.z + sin(ang) * radius
		var py := _ground_y(px, pz)
		var s := 0.5 + t * 1.1
		var b := Basis.from_euler(Vector3(0, ang + rng.randf() * 0.4, 0))
		transforms.append(Transform3D(b.scaled(Vector3.ONE * s), Vector3(px, py + s * 0.6, pz)))
		if s >= 0.75:
			var body := StaticBody3D.new()
			body.position = Vector3(px, py + s * 0.6, pz)
			var col := CollisionShape3D.new()
			var cs := CylinderShape3D.new()
			cs.radius = 0.22 * s * 1.2
			cs.height = 1.2 * s * 0.95
			col.shape = cs
			body.add_child(col)
			container.add_child(body)
	_add_multimesh(crystal_mesh, _glow_mat(_accent, 1.5), transforms, false)
	var orb := EnergyOrb.new()
	orb.setup(_glow, "hover", 0.0, 1.1, 1.0)
	orb.set_center(center + Vector3(0, y + 2.0, 0))
	container.add_child(orb)
	_add_spirit_particles(center + Vector3(0, 1.8, 0), _glow)

# ---------- 破败与文明共存：焦土 / 裂隙 / 碎块 / 余烬 ----------

func _add_scorch(center: Vector3, radius: float) -> void:
	var y := _ground_y(center.x, center.z)
	var scorch := CylinderMesh.new()
	scorch.top_radius = radius
	scorch.bottom_radius = radius
	scorch.height = 0.08
	scorch.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.07, 0.06, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	_add_visual(scorch, mat, Vector3(center.x, y + 0.045, center.z), Vector3.ZERO, Vector3.ONE, false)

func _add_fissures(center: Vector3, count: int) -> void:
	var y := _ground_y(center.x, center.z)
	for i in count:
		var ang := rng.randf() * TAU
		var len := 2.0 + rng.randf() * 3.5
		var fissure := BoxMesh.new()
		fissure.size = Vector3(len, 0.06, 0.12)
		var mi := MeshInstance3D.new()
		mi.mesh = fissure
		mi.material_override = _glow_mat(_accent, 1.6)
		mi.position = Vector3(center.x + cos(ang) * (1.0 + len * 0.5), y + 0.05, center.z + sin(ang) * (1.0 + len * 0.5))
		mi.rotation_degrees = Vector3(0, rad_to_deg(ang), 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.add_child(mi)

func _add_debris(center: Vector3, count: int, radius: float) -> void:
	var stone_mat := _mat(_stone, 0.92)
	var moss_mat := _mat(_stone.darkened(0.12).lerp(Color(0.4, 0.44, 0.42), 0.4), 0.95)
	for i in count:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(2.0, radius)
		var px := center.x + cos(ang) * dist
		var pz := center.z + sin(ang) * dist
		var py := _ground_y(px, pz)
		var rock := BoxMesh.new()
		var s := rng.randf_range(0.4, 1.2)
		rock.size = Vector3(s, s * 0.7, s * 0.8)
		_add_visual(rock, stone_mat if rng.randf() < 0.6 else moss_mat, Vector3(px, py + s * 0.35, pz), Vector3(rng.randf_range(0, 360), rng.randf_range(0, 360), rng.randf_range(0, 360)), Vector3.ONE, true)

func _add_embers(pos: Vector3, color: Color) -> void:
	var ps := CPUParticles3D.new()
	ps.amount = 18
	ps.lifetime = 2.4
	ps.one_shot = false
	ps.emitting = true
	ps.direction = Vector3(0, 1, 0)
	ps.spread = 30.0
	ps.gravity = Vector3(0, 1.2, 0)
	ps.initial_velocity_min = 0.3
	ps.initial_velocity_max = 0.7
	ps.scale_amount_min = 0.04
	ps.scale_amount_max = 0.1
	ps.position = pos + Vector3(0, 0.4, 0)
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 1.0))
	grad.set_color(0.6, Color(color.r * 0.7, color.g * 0.4, color.b * 0.2, 0.8))
	grad.set_color(1, Color(0.1, 0.05, 0.02, 0.0))
	ps.color_ramp = grad
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.emission_enabled = true
	pm.emission = color
	ps.material_override = pm
	container.add_child(ps)

func _add_orb(center_pos: Vector3, mode: String, radius: float, speed: float, color: Color) -> EnergyOrb:
	var orb := EnergyOrb.new()
	orb.setup(color, mode, radius, speed, 0.5)
	orb.set_center(center_pos)
	container.add_child(orb)
	return orb

# ---------- 剧情地标（任务点纪念碑） ----------

func place_landmark(pos: Vector3, kind: String = "monument") -> void:
	## 由剧情管理器在任务点/剧情坐标放置主题纪念碑，让叙事地点有实体感。
	if container == null or _terrain() == null:
		return
	var y := _ground_y(pos.x, pos.z)
	match kind:
		"obelisk":
			_spawn_obelisk(pos)
		"arch":
			_spawn_arch(pos)
		"machine":
			_spawn_machine_core(pos, 1.0 + rng.randf() * 0.5)
		"pavement":
			_spawn_pavement(pos)
		"shaft":
			_spawn_light_shaft(pos)
		_:
			# 纪念碑：石基 + 石碑 + 辉光，象征“文明刻石”
			var base := CylinderMesh.new()
			base.top_radius = 1.5
			base.bottom_radius = 1.7
			base.height = 0.55
			base.radial_segments = 18
			var base_col := CylinderShape3D.new()
			base_col.radius = 1.7
			base_col.height = 0.55
			_add_static(base, _mat(_stone, 0.88), Vector3(pos.x, y + 0.28, pos.z), Vector3.ZERO, Vector3.ONE, base_col, Vector3.ZERO)
			var stele := BoxMesh.new()
			stele.size = Vector3(1.1, 2.6, 0.45)
			var stele_col := BoxShape3D.new()
			stele_col.size = Vector3(1.1, 2.6, 0.45)
			_add_static(stele, _mat(_stone.lightened(0.08), 0.88), Vector3(pos.x, y + 1.85, pos.z), Vector3(0, rng.randf() * 360, 0), Vector3.ONE, stele_col, Vector3.ZERO)
			var rune := BoxMesh.new()
			rune.size = Vector3(0.7, 1.2, 0.08)
			_add_visual(rune, _glow_mat(_accent, 1.6), Vector3(pos.x, y + 1.9, pos.z + 0.24), Vector3(0, 0, 0), Vector3.ONE, false)
			var crystal := CylinderMesh.new()
			crystal.top_radius = 0.0
			crystal.bottom_radius = 0.24
			crystal.height = 1.0
			crystal.radial_segments = 6
			_add_visual(crystal, _glow_mat(_glow, 1.8), Vector3(pos.x, y + 3.5, pos.z))
			_add_spirit_particles(pos + Vector3(0, 3.6, 0), _glow)

# ---------- 秘境选址与氛围 ----------

func _find_open_site(required_biomes: Array, min_dist: float, claim_radius: float = 0.0) -> Vector3:
	for attempt in 140:
		var p := _rand_pos(-70.0, 70.0, -70.0, 70.0)
		var biome := _terrain().biome_at(p.x, p.y)
		if not required_biomes.has(biome):
			continue
		if not _suitable(p.x, p.y, 0.32):
			continue
		if _near_village(p.x, p.y):
			continue
		if Vector2(p.x, p.y).length() < min_dist:
			continue
		if _pos_blocked(p, claim_radius):
			continue
		if claim_radius > 0.0:
			_claim(p, claim_radius)
		return Vector3(p.x, _ground_y(p.x, p.y), p.y)
	return Vector3.INF

func _claim(pos: Vector2, radius: float) -> void:
	_occupied.append({"pos": pos, "radius": radius})

func _pos_blocked(pos: Vector2, radius: float) -> bool:
	for o in _occupied:
		if (o["pos"] as Vector2).distance_to(pos) < float(o["radius"]) + radius:
			return true
	return false

func _near_major(wx: float, wz: float, margin: float) -> bool:
	## 填充物（树/石/草）是否贴近已占地的丰碑或地标。
	return _pos_blocked(Vector2(wx, wz), margin)

func _find_wonder_site(anchor: Vector3, village_anchor := false) -> Vector3:
	## 在任务点/聚落附近寻找开阔平地，让丰碑“守着”任务建筑。
	## 聚落锚点用更远偏移，避免与村内建筑重叠；任务点锚点贴近布置。
	for attempt in 60:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(22.0, 30.0) if village_anchor else rng.randf_range(11.0, 19.0)
		var p := Vector2(anchor.x + cos(ang) * dist, anchor.z + sin(ang) * dist)
		if _pos_blocked(p, 18.0):
			continue
		if not _suitable(p.x, p.y, 0.35):
			continue
		_claim(p, 18.0)
		return Vector3(p.x, _ground_y(p.x, p.y), p.y)
	return _find_open_site([TerrainGenerator.BIOME_RELIC, TerrainGenerator.BIOME_PLAINS, TerrainGenerator.BIOME_SAVANNA], 40.0, 18.0)

func _add_spirit_particles(pos: Vector3, color: Color) -> void:
	var ps := CPUParticles3D.new()
	ps.amount = 16
	ps.lifetime = 3.2
	ps.one_shot = false
	ps.emitting = true
	ps.direction = Vector3(0, 1, 0)
	ps.spread = 55.0
	ps.gravity = Vector3.ZERO
	ps.initial_velocity_min = 0.15
	ps.initial_velocity_max = 0.45
	ps.scale_amount_min = 0.05
	ps.scale_amount_max = 0.14
	ps.position = pos
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.0))
	grad.set_color(0.5, Color(color.r, color.g, color.b, 0.85))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	ps.color_ramp = grad
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.emission_enabled = true
	pm.emission = color
	ps.material_override = pm
	container.add_child(ps)

# ---------- 内部工具类：辉光脉冲 ----------

class _Pulse:
	extends Node3D
	var _light: OmniLight3D = null
	var _mat: StandardMaterial3D = null
	var _seed := 0.0

	func setup(light: OmniLight3D, mat: StandardMaterial3D) -> void:
		_light = light
		_mat = mat
		_seed = randf() * 100.0

	func _process(delta: float) -> void:
		var t := Time.get_ticks_msec() / 1000.0
		if _light != null:
			var flicker := 0.78 + 0.3 * (sin(t * 2.2 + _seed) * 0.6 + sin(t * 4.7 + _seed * 2.0) * 0.4)
			_light.light_energy = 1.0 * flicker
		if _mat != null:
			_mat.emission_energy_multiplier = 1.3 + 0.5 * sin(t * 2.3 + _seed)

class _Rotator:
	extends Node3D
	var _speed := 1.0

	func setup(speed: float) -> void:
		_speed = speed

	func _process(delta: float) -> void:
		rotation.y += delta * _speed
