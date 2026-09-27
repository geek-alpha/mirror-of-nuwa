class_name OrbitRibbons
extends Node3D
## 牛顿纪 · 三体轨道丝带与庞加莱截面：
## 天文台旁立起一台“太阳系仪”——三颗太阳在引力方程里的真实三维轨道，
## 化作三条发光丝带在空气中缓缓生长，恒星如彗星般沿着轨道移动。
## 每当某颗恒星穿过参考半平面，就在头顶的图盘上记下一个点：庞加莱截面。
## 二体问题里这些点落在平滑的曲线上；而这里，它们弥散成混沌的云——
## 牛顿写下了方程，却永远算不出那三个点的下一次相遇。

const PLANE_TILT := 0.72
const SCALE := 24.0
const RIBBON_POINTS := 340
const RIBBON_HALF_W := 0.16
const DISC_RADIUS := 7.0
const DISC_Y := 16.0
const R_NORM_MAX := 2.6
const MAX_DOTS := 420

const SUN_COLORS := [
	Color(1.0, 0.72, 0.35),
	Color(0.55, 0.82, 1.0),
	Color(1.0, 0.42, 0.32),
]

var sky: Node3D = null
var _trails: Array[Array] = [[], [], []]
var _plane_normal := Vector3.UP
var _t := 0.0
var _cross_prev := [-1.0, -1.0, -1.0]
var _dots: Array[Array] = [[], [], []]

var _mesh_ribbon: ImmediateMesh = null
var _mat_ribbon: StandardMaterial3D = null
var _mesh_dots: ImmediateMesh = null
var _mat_dots: StandardMaterial3D = null
var _sun_spheres: Array[MeshInstance3D] = []

func setup(sky_node: Node3D, center: Vector3) -> void:
	sky = sky_node
	var base_y := WorldManager.get_terrain_height(center.x, center.z) + 0.4
	position = Vector3(center.x, base_y, center.z)
	_plane_normal = Vector3(0, -sin(PLANE_TILT), cos(PLANE_TILT)).normalized()
	_build_guides()
	_build_disc()
	_mat_ribbon = _line_mat(Color(0.7, 0.85, 1.0), 1.6)
	_mesh_ribbon = ImmediateMesh.new()
	_add_mesh(_mesh_ribbon, _mat_ribbon)
	_mat_dots = _line_mat(Color(0.8, 0.9, 1.0), 2.2)
	_mesh_dots = ImmediateMesh.new()
	_add_mesh(_mesh_dots, _mat_dots)
	for i in 3:
		var dot := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.55
		sph.height = 1.1
		sph.radial_segments = 10
		sph.rings = 6
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = SUN_COLORS[i]
		m.emission_energy_multiplier = 3.0
		sph.material = m
		dot.mesh = sph
		add_child(dot)
		_sun_spheres.append(dot)
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

func _glow_mat(color: Color, energy := 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

func _add_mesh(mesh: ImmediateMesh, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

## 引导环：倾在真实轨道平面里的两条轨道参考圈
func _build_guides() -> void:
	var guide := Node3D.new()
	var y := _plane_normal
	var x := Vector3(1, 0, 0)
	if absf(x.dot(y)) > 0.99:
		x = Vector3(0, 0, 1)
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	guide.basis = Basis(x, y, z)
	add_child(guide)
	for radius in [0.9 * SCALE, 1.7 * SCALE]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.12
		torus.outer_radius = radius + 0.12
		torus.rings = 6
		torus.ring_segments = 72
		var m := _glow_mat(Color(0.5, 0.65, 0.95), 0.8)
		torus.material = m
		ring.mesh = torus
		ring.rotation_degrees = Vector3(90, 0, 0)
		guide.add_child(ring)

## 庞加莱图盘：水平悬浮的记录盘 + 参考轴线 + 半径刻度
func _build_disc() -> void:
	var plate := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = DISC_RADIUS
	cyl.bottom_radius = DISC_RADIUS
	cyl.height = 0.14
	cyl.radial_segments = 44
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.08, 0.14)
	m.roughness = 0.6
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.7
	cyl.material = m
	plate.mesh = cyl
	plate.position = Vector3(0, DISC_Y, 0)
	add_child(plate)

	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = DISC_RADIUS - 0.1
	torus.outer_radius = DISC_RADIUS + 0.12
	torus.rings = 8
	torus.ring_segments = 64
	torus.material = _glow_mat(Color(0.6, 0.75, 1.0), 1.4)
	rim.mesh = torus
	rim.rotation_degrees = Vector3(90, 0, 0)
	rim.position = Vector3(0, DISC_Y + 0.1, 0)
	add_child(rim)

	# 参考半平面（记录截面时穿过的轴线）与半径刻度
	var deco_mat := _line_mat(Color(0.7, 0.8, 1.0), 1.2)
	var deco := ImmediateMesh.new()
	_add_mesh(deco, deco_mat)
	deco.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, deco_mat)
	deco.surface_set_color(Color(1, 1, 1, 0.8))
	deco.surface_add_vertex(Vector3(0, DISC_Y + 0.05, -DISC_RADIUS))
	deco.surface_add_vertex(Vector3(0, DISC_Y + 0.05, DISC_RADIUS))
	deco.surface_set_color(Color(1, 1, 1, 0.25))
	for r in [DISC_RADIUS * 0.25, DISC_RADIUS * 0.5, DISC_RADIUS * 0.75]:
		for k in 65:
			var a := float(k) / 64.0 * TAU
			deco.surface_add_vertex(Vector3(cos(a) * r, DISC_Y + 0.05, sin(a) * r))
	deco.surface_end()

func _process(delta: float) -> void:
	if sky == null or not is_instance_valid(sky):
		return
	_t += delta
	var orbits: Array[Vector2] = sky.get_orbit_positions()
	for i in 3:
		var world: Vector3 = sky.orbit_to_world(orbits[i], SCALE)
		var local: Vector3 = world - position
		var trail: Array = _trails[i]
		trail.append(local)
		if trail.size() > RIBBON_POINTS:
			trail.pop_front()
		_sun_spheres[i].position = local
		_poincare_step(i, orbits[i])
	_recompute_normal()
	_rebuild_ribbons()
	for list in _dots:
		for d in list:
			d["age"] = float(d["age"]) + 1.0
	_rebuild_dots()

func _poincare_step(i: int, orbit: Vector2) -> void:
	## 轨道每穿过惯性参考半平面（+X 轴）一次，在图盘上记下一个返回点
	var v := orbit.y
	if _cross_prev[i] < 0.0 and v >= 0.0:
		var r := orbit.length()
		var ang := atan2(orbit.y, orbit.x)
		var s := clampf(r / R_NORM_MAX, 0.0, 1.0) * DISC_RADIUS
		var dot := Vector3(cos(ang) * s, DISC_Y + 0.12, sin(ang) * s)
		var list: Array = _dots[i]
		list.append({"pos": dot, "age": 0.0})
		if list.size() > MAX_DOTS:
			list.pop_front()
	_cross_prev[i] = v

## 由最近三个轨迹点反推轨道平面法线（避免与轨道几乎共线的短基线）
func _recompute_normal() -> void:
	var a: Array = _trails[0]
	if a.size() >= 24:
		var p0: Vector3 = a[0]
		var p1: Vector3 = a[a.size() / 2]
		var p2: Vector3 = a[a.size() - 1]
		var n := (p1 - p0).cross(p2 - p0)
		if n.length() > 0.01:
			_plane_normal = n.normalized()

## 把每条轨道重建成一条发光丝带（带宽度 + 头亮尾隐）
func _rebuild_ribbons() -> void:
	_mesh_ribbon.clear_surfaces()
	for i in 3:
		var trail: Array = _trails[i]
		var n := trail.size()
		if n < 2:
			continue
		var normal := _plane_normal
		var side: Vector3 = Vector3.UP
		if n >= 2:
			var dir := (trail[n - 1] as Vector3) - (trail[n - 2] as Vector3)
			if dir.length_squared() > 0.0001:
				side = dir.cross(normal).normalized()
		_mesh_ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat_ribbon)
		for k in n - 1:
			var a0 := float(k) / float(n - 1)
			var a1 := float(k + 1) / float(n - 1)
			var p0: Vector3 = trail[k]
			var p1: Vector3 = trail[k + 1]
			var col0 := Color(1, 1, 1, a0 * 0.5)
			var col1 := Color(1, 1, 1, a1 * 0.55)
			_mesh_ribbon.surface_set_color(col0)
			_mesh_ribbon.surface_add_vertex(p0 + side * RIBBON_HALF_W)
			_mesh_ribbon.surface_set_color(col1)
			_mesh_ribbon.surface_add_vertex(p1 + side * RIBBON_HALF_W)
			_mesh_ribbon.surface_set_color(col0)
			_mesh_ribbon.surface_add_vertex(p0 - side * RIBBON_HALF_W)
			_mesh_ribbon.surface_set_color(col1)
			_mesh_ribbon.surface_add_vertex(p1 - side * RIBBON_HALF_W)
			_mesh_ribbon.surface_set_color(col1)
			_mesh_ribbon.surface_add_vertex(p1 + side * RIBBON_HALF_W)
			_mesh_ribbon.surface_set_color(col0)
			_mesh_ribbon.surface_add_vertex(p0 - side * RIBBON_HALF_W)
		_mesh_ribbon.surface_end()
		# 丝带中心的亮线
		_mesh_ribbon.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat_ribbon)
		for k in n:
			var a := float(k) / float(n - 1)
			_mesh_ribbon.surface_set_color(Color(1, 1, 1, a * 0.9))
			_mesh_ribbon.surface_add_vertex(trail[k])
		_mesh_ribbon.surface_end()

## 把庞加莱返回点渲染成图盘上的光点（按恒星着色，渐次暗淡）
func _rebuild_dots() -> void:
	_mesh_dots.clear_surfaces()
	_mesh_dots.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat_dots)
	var size := 0.22
	for i in 3:
		var hue: Color = SUN_COLORS[i]
		var list: Array = _dots[i]
		for d in list:
			var p: Vector3 = d["pos"]
			var age: float = d["age"]
			var a := 0.9 * pow(0.9975, age)
			if a < 0.03:
				continue
			var col := Color(hue.r, hue.g, hue.b, a)
			var v0 := p + Vector3(-size, 0, -size)
			var v1 := p + Vector3(size, 0, -size)
			var v2 := p + Vector3(size, 0, size)
			var v3 := p + Vector3(-size, 0, size)
			_mesh_dots.surface_set_color(col)
			_mesh_dots.surface_add_vertex(v0)
			_mesh_dots.surface_add_vertex(v1)
			_mesh_dots.surface_add_vertex(v2)
			_mesh_dots.surface_add_vertex(v0)
			_mesh_dots.surface_add_vertex(v2)
			_mesh_dots.surface_add_vertex(v3)
	_mesh_dots.surface_end()
