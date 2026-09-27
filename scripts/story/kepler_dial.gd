class_name KeplerDial
extends Node3D
## 周文王纪 · 开普勒等面积日晷：
## 以行星为原点，把三颗太阳的真实轨道实时画成极坐标图 r(θ)——天文观测的雏形。
## 每隔固定时间记下一道“扫掠扇区”：在二体世界里，等时间扫过等面积（开普勒第二定律）；
## 而在三日世界，第三体把这份对称扯碎——面积不再相等，观测者将在这面盘上第一次看见混沌。
## 环周环绕八卦爻纹：古老占星与精密天体力学的对望。

const RADIUS := 8.0
const TRAIL := 520
const SECTOR_TIME := 5.0
const MAX_SECTORS := 40
const NORM_MAX := 3.0

const TRIGRAMS := [
	[1, 1, 1],  # 乾
	[1, 1, 0],  # 兑
	[1, 0, 1],  # 离
	[1, 0, 0],  # 震
	[0, 1, 1],  # 巽
	[0, 1, 0],  # 坎
	[0, 0, 1],  # 艮
	[0, 0, 0],  # 坤
]
const SUN_COLORS := [
	Color(1.0, 0.75, 0.35),
	Color(0.55, 0.8, 1.0),
	Color(1.0, 0.45, 0.35),
]
const AMBER := Color(1.0, 0.78, 0.42)

var sky: Node3D = null
var _trails: Array[Array] = [[], [], []]
var _sectors: Array = []
var _sector_timer := 0.0
var _t := 0.0
var _mesh_trail: ImmediateMesh = null
var _mat_trail: StandardMaterial3D = null
var _mesh_sector: ImmediateMesh = null
var _mat_sector: StandardMaterial3D = null
var _mesh_static: ImmediateMesh = null
var _mat_static: StandardMaterial3D = null
var _base_y := 0.0

func setup(sky_node: Node3D, center: Vector3) -> void:
	sky = sky_node
	_base_y = WorldManager.get_terrain_height(center.x, center.z) + 0.06
	position = Vector3(center.x, _base_y, center.z)
	_build_static()
	_mat_trail = _line_mat(AMBER, 1.5)
	_mesh_trail = ImmediateMesh.new()
	_add_mesh(_mesh_trail, _mat_trail)
	_mat_sector = _line_mat(AMBER, 1.2)
	_mesh_sector = ImmediateMesh.new()
	_add_mesh(_mesh_sector, _mat_sector)
	set_process(true)

func _line_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

func _add_mesh(mesh: ImmediateMesh, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

## 盘面静态几何：石板 + 半径刻度环 + 环周八卦爻纹
func _build_static() -> void:
	_mat_static = _line_mat(AMBER, 1.3)
	var plate := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIUS
	cyl.bottom_radius = RADIUS
	cyl.height = 0.16
	cyl.radial_segments = 40
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.24, 0.15, 0.07)
	pmat.roughness = 0.9
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.albedo_color.a = 0.55
	cyl.material = pmat
	plate.mesh = cyl
	plate.position = Vector3(0, 0.02, 0)
	add_child(plate)

	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.1
	torus.outer_radius = RADIUS + 0.12
	torus.rings = 12
	torus.ring_segments = 64
	torus.material = _beacon_glow(AMBER)
	rim.mesh = torus
	rim.rotation_degrees = Vector3(90, 0, 0)
	rim.position = Vector3(0, 0.14, 0)
	add_child(rim)

	_mesh_static = ImmediateMesh.new()
	_add_mesh(_mesh_static, _mat_static)
	_mesh_static.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat_static)
	_mesh_static.surface_set_color(Color(1, 1, 1, 0.4))
	for r in [RADIUS * 0.333, RADIUS * 0.667, RADIUS * 0.93]:
		for i in 65:
			var a := float(i) / 64.0 * TAU
			_mesh_static.surface_add_vertex(Vector3(cos(a) * r, 0.12, sin(a) * r))
	_mesh_static.surface_end()
	_draw_trigrams()

func _beacon_glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.6
	return m

## 八卦爻纹：每卦三爻，按“阳爻连、阴爻断”的爻画刻在环周
func _draw_trigrams() -> void:
	_mesh_static.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat_static)
	for k in 8:
		var a := float(k) / 8.0 * TAU
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		for line_i in 3:
			var radial := RADIUS + 0.5 + line_i * 0.62
			var bar := 0.42
			var bit: int = TRIGRAMS[k][2 - line_i]  # 从外圈看自上而下 = 卦象自上而下
			var cx := dir * radial
			if bit == 1:
				_mesh_static.surface_add_vertex(Vector3(cx.x + perp.x * bar, 0.16, cx.y + perp.y * bar))
				_mesh_static.surface_add_vertex(Vector3(cx.x - perp.x * bar, 0.16, cx.y - perp.y * bar))
			else:
				var half := 0.16
				_mesh_static.surface_add_vertex(Vector3(cx.x + perp.x * bar, 0.16, cx.y + perp.y * bar))
				_mesh_static.surface_add_vertex(Vector3(cx.x + perp.x * half, 0.16, cx.y + perp.y * half))
				_mesh_static.surface_add_vertex(Vector3(cx.x - perp.x * half, 0.16, cx.y - perp.y * half))
				_mesh_static.surface_add_vertex(Vector3(cx.x - perp.x * bar, 0.16, cx.y - perp.y * bar))
	_mesh_static.surface_end()

func _process(delta: float) -> void:
	if sky == null or not is_instance_valid(sky):
		return
	_t += delta
	var orbits: Array[Vector2] = sky.get_orbit_positions()
	var idx: int = sky.get_nearest_sun_index()
	var nearest_pt := Vector3.ZERO
	for i in 3:
		var world: Vector3 = sky.orbit_to_world(orbits[i], 1.0)
		var local: Vector3 = world - position
		var angle := atan2(local.z, local.x)
		var r_abs := Vector2(local.x, local.z).length()
		var norm := clampf(r_abs / NORM_MAX, 0.0, 1.0)
		var p := Vector3(cos(angle) * norm * RADIUS, 0.06, sin(angle) * norm * RADIUS)
		var trail: Array = _trails[i]
		trail.append(p)
		if trail.size() > TRAIL:
			trail.pop_front()
		if i == idx:
			nearest_pt = p
	# 等时间扫掠扇区：记录当前最危险恒星的极径端点，逐扇区填充
	_sector_timer -= delta
	if _sector_timer <= 0.0:
		_sector_timer = SECTOR_TIME
		_sectors.append({"pt": nearest_pt, "age": 0.0})
		if _sectors.size() > MAX_SECTORS:
			_sectors.pop_front()
	for s in _sectors:
		s["age"] = float(s["age"]) + delta
	_rebuild_trails()
	_rebuild_sectors(nearest_pt)

func _rebuild_trails() -> void:
	_mesh_trail.clear_surfaces()
	for i in 3:
		var trail: Array = _trails[i]
		if trail.size() < 2:
			continue
		var hue: Color = SUN_COLORS[i]
		_mesh_trail.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat_trail)
		var n := trail.size()
		for k in n:
			var a := float(k) / float(n - 1)
			_mesh_trail.surface_set_color(Color(hue.r, hue.g, hue.b, a * 0.95))
			_mesh_trail.surface_add_vertex(trail[k])
		_mesh_trail.surface_end()

## 扫掠扇区：相邻两次记录点与盘心围成的三角形。等时间 → 面积相等才叫开普勒定律；
## 三体世界里，你会看见这片扇形忽宽忽窄——定律在这里断了。
func _rebuild_sectors(nearest_pt: Vector3) -> void:
	_mesh_sector.clear_surfaces()
	if _sectors.size() < 2:
		return
	_mesh_sector.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat_sector)
	for k in _sectors.size() - 1:
		var a: Dictionary = _sectors[k]
		var b: Dictionary = _sectors[k + 1]
		var age_a: float = a.get("age", 0.0)
		var age_b: float = b.get("age", 0.0)
		var alpha := 0.5 * maxf(0.0, 1.0 - (age_a + age_b) / 120.0)
		if alpha <= 0.01:
			continue
		var col := Color(1, 1, 1, alpha)
		_mesh_sector.surface_set_color(col)
		_mesh_sector.surface_add_vertex(Vector3.ZERO)
		_mesh_sector.surface_set_color(col)
		_mesh_sector.surface_add_vertex(a["pt"])
		_mesh_sector.surface_set_color(col)
		_mesh_sector.surface_add_vertex(b["pt"])
	_mesh_sector.surface_end()
	# 当前指针：从盘心指向此刻最危险的恒星
	if nearest_pt.length_squared() > 0.0001:
		_mesh_sector.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat_trail)
		_mesh_sector.surface_set_color(Color(1, 1, 1, 0.9))
		_mesh_sector.surface_add_vertex(Vector3.ZERO)
		_mesh_sector.surface_set_color(Color(1, 1, 1, 0.15))
		_mesh_sector.surface_add_vertex(nearest_pt)
		_mesh_sector.surface_end()
