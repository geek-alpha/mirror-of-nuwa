class_name SpacetimeGrid
extends Node3D
## 爱因斯坦纪 · 时空曲率织锦：
## 一块 3D 网格被中心质量压成引力井——网格光沿弯曲的时空滑落。
## 这就是引力透镜：光并不是被“拉弯”，它走的本来就是弯曲时空里的“直线”。
## 井底悬着一颗致密天体，光子在它周围被引力囚禁成一道光环，
## 坠井的星尘沿测地线盘旋——质能告诉时空如何弯曲，时空告诉质能如何运动。

const GRID_N := 12
const GRID_Y := 10.0
const SPAN := 52.0
const SAMPLE_N := 36
const WELL_DEPTH := 7.2
const WELL_R := 9.0
const ORB_R := 1.5

var _t := 0.0
var _mesh: ImmediateMesh = null
var _mat: StandardMaterial3D = null
var _rings: Array[Node3D] = []
var _photon_dots: Array[MeshInstance3D] = []

func setup(center: Vector3) -> void:
	var base_y := WorldManager.get_terrain_height(center.x, center.z) + 0.1
	position = Vector3(center.x, base_y, center.z)
	_build_well()
	_build_photon_ring()
	_build_tilted_rings()
	_mat = _line_mat(Color(0.62, 0.78, 1.0), 1.35)
	_mesh = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	add_child(mi)
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

## 井底致密天体 + 落向地面的光之滑道
func _build_well() -> void:
	var orb := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = ORB_R
	sph.height = ORB_R * 2.0
	sph.radial_segments = 16
	sph.rings = 10
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = Color(0.03, 0.04, 0.1)
	m.emission_energy_multiplier = 1.0
	sph.material = m
	orb.mesh = sph
	orb.position = Vector3(0, GRID_Y - WELL_DEPTH, 0)
	add_child(orb)
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.8
	cyl.height = GRID_Y - WELL_DEPTH + 0.4
	cyl.radial_segments = 12
	var sm := _glow_mat(Color(0.5, 0.7, 1.0), 0.8)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.albedo_color = Color(1, 1, 1, 0.12)
	cyl.material = sm
	shaft.mesh = cyl
	shaft.position = Vector3(0, (GRID_Y - WELL_DEPTH) * 0.5, 0)
	add_child(shaft)

## 光子环：光子被引力囚禁在井口，形成一圈永恒的光
func _build_photon_ring() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = ORB_R * 1.35
	torus.outer_radius = ORB_R * 1.55
	torus.rings = 10
	torus.ring_segments = 64
	var m := _glow_mat(Color(1.0, 0.95, 0.8), 2.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1, 1, 1, 0.9)
	torus.material = m
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = Vector3(0, GRID_Y - WELL_DEPTH, 0)
	add_child(ring)

## 倾斜的吸积盘环与绕行的光子
func _build_tilted_rings() -> void:
	for k in 2:
		var g := Node3D.new()
		g.position = Vector3(0, GRID_Y - WELL_DEPTH, 0)
		g.rotation_degrees = Vector3(22 + k * 34, 0, 12 + k * 21)
		add_child(g)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = ORB_R * (1.9 + k * 0.55)
		torus.outer_radius = torus.inner_radius + 0.14
		torus.rings = 6
		torus.ring_segments = 48
		var m := _glow_mat(Color(0.7, 0.55, 0.95) if k == 0 else Color(0.4, 0.6, 0.9), 1.1)
		torus.material = m
		ring.mesh = torus
		ring.rotation_degrees = Vector3(90, 0, 0)
		g.add_child(ring)
		_rings.append(g)
	for k in 3:
		var dot := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.18
		sph.height = 0.36
		sph.radial_segments = 6
		sph.rings = 4
		sph.material = _glow_mat(Color(1.0, 0.95, 0.8), 2.8)
		dot.mesh = sph
		dot.position = Vector3(0, GRID_Y - WELL_DEPTH, 0)
		add_child(dot)
		_photon_dots.append(dot)

## 弯曲时空的高度场：引力井 + 呼吸 + 行波，并带轻微的径向内卷（透镜）
func _warp(x: float, z: float) -> Vector3:
	var r := sqrt(x * x + z * z)
	var breathing := 1.0 + 0.05 * sin(_t * 0.9)
	var sag := -WELL_DEPTH * breathing / (1.0 + (r / WELL_R) * (r / WELL_R))
	var ripple := 0.4 * sin(_t * 1.7 - r * 0.14) * exp(-r / 18.0)
	var infall := 1.0 - 0.1 / (1.0 + (r / 7.0) * (r / 7.0))
	return Vector3(x * infall, GRID_Y + sag + ripple, z * infall)

func _process(delta: float) -> void:
	_t += delta
	# 吸积盘缓缓旋转，光子绕井而行
	for k in _rings.size():
		_rings[k].rotate_y(delta * (0.25 + k * 0.14) * (1.0 if k % 2 == 0 else -1.0))
	for k in _photon_dots.size():
		var a := _t * 0.9 + k * TAU / 3.0
		_photon_dots[k].position = Vector3(cos(a) * ORB_R * 1.1, GRID_Y - WELL_DEPTH, sin(a) * ORB_R * 1.1)
	_rebuild_grid()

func _rebuild_grid() -> void:
	_mesh.clear_surfaces()
	var step := SPAN * 2.0 / float(GRID_N)
	for i in GRID_N + 1:
		var coord := -SPAN + step * i
		_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat)
		for k in SAMPLE_N + 1:
			var x := -SPAN + SPAN * 2.0 / float(SAMPLE_N) * k
			var p := _warp(x, coord)
			var d := clampf(1.0 - p.distance_to(Vector3(0, GRID_Y, 0)) / 55.0, 0.15, 1.0)
			_mesh.surface_set_color(Color(1, 1, 1, d * 0.5))
			_mesh.surface_add_vertex(p)
		_mesh.surface_end()
		_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat)
		for k in SAMPLE_N + 1:
			var z := -SPAN + SPAN * 2.0 / float(SAMPLE_N) * k
			var p := _warp(coord, z)
			var d := clampf(1.0 - p.distance_to(Vector3(0, GRID_Y, 0)) / 55.0, 0.15, 1.0)
			_mesh.surface_set_color(Color(1, 1, 1, d * 0.5))
			_mesh.surface_add_vertex(p)
		_mesh.surface_end()
