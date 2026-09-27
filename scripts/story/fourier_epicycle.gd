class_name FourierEpicycle
extends Node3D
## 墨子纪 · 傅里叶本轮齿轮仪：
## 嵌套的一组齿轮（本轮）——每个齿轮的转轴搭在上一枚齿轮的边缘，
## 笔尖是它们向量叠加的末端。任何曲线都能写成旋转圆之和（傅里叶级数），
## 而这里齿轮转出的是一朵玫瑰：转速取整数比 1:-3:5:-7，轨迹优雅地闭环，永不紊乱。
## 这正是墨子“宇宙是一台精密的机器”的器物化——机器用旋转画出了世界的形状。

const TRAIL := 660
const ANG_SPEED := 0.9
const TRAIL_STEP := 0.045

const RADII := [2.4, 1.5, 0.9, 0.5]
const SPEEDS := [1.0, -3.0, 5.0, -7.0]
const PHASES := [0.0, 0.4, 1.1, 2.2]
const GOLD := Color(1.0, 0.8, 0.4)
const COPPER := Color(0.9, 0.62, 0.3)

var _ring_nodes: Array[MeshInstance3D] = []
var _ring_dots: Array[MeshInstance3D] = []
var _ring_mats: Array[StandardMaterial3D] = []
var _trail: Array[Vector2] = []
var _trail_timer := 0.0
var _t := 0.0
var _pen := Vector2.ZERO
var _dot_positions: Array[Vector2] = []

var _mesh_pen: ImmediateMesh = null
var _mat_pen: StandardMaterial3D = null
var _pen_dot: MeshInstance3D = null

func setup(center: Vector3) -> void:
	var base_y := WorldManager.get_terrain_height(center.x, center.z) + 0.06
	position = Vector3(center.x, base_y, center.z)
	_build_pedestal()
	_build_rings()
	_mat_pen = _line_mat(GOLD, 1.5)
	_mesh_pen = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_pen
	add_child(mi)
	_pen_dot = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.2
	sph.height = 0.4
	sph.radial_segments = 8
	sph.rings = 5
	sph.material = _glow_mat(Color(1.0, 0.95, 0.7), 3.0)
	_pen_dot.mesh = sph
	add_child(_pen_dot)
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

func _glow_mat(color: Color, energy := 1.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

func _build_pedestal() -> void:
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 5.6
	cyl.bottom_radius = 6.2
	cyl.height = 0.4
	cyl.radial_segments = 36
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.28, 0.14)
	mat.roughness = 0.9
	cyl.material = mat
	base.mesh = cyl
	base.position = Vector3(0, 0.18, 0)
	add_child(base)

## 铸造齿轮环：每个齿轮一根发光轮辋 + 一枚转点
func _build_rings() -> void:
	for k in RADII.size():
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = RADII[k] - 0.12
		torus.outer_radius = RADII[k] + 0.12
		torus.rings = 10
		torus.ring_segments = 48
		var rmat := _glow_mat(GOLD if k % 2 == 0 else COPPER, 1.1)
		torus.material = rmat
		ring.mesh = torus
		ring.rotation_degrees = Vector3(90, 0, 0)
		ring.position = Vector3(0, 0.16 + k * 0.012, 0)
		add_child(ring)
		_ring_nodes.append(ring)
		var dot := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.16
		sph.height = 0.32
		sph.radial_segments = 8
		sph.rings = 5
		sph.material = _glow_mat(Color(1.0, 0.95, 0.7), 2.4)
		dot.mesh = sph
		dot.position = Vector3(0, 0.34, 0)
		add_child(dot)
		_ring_dots.append(dot)

func _compute_parts() -> void:
	_dot_positions.clear()
	_dot_positions.append(Vector2.ZERO)
	var acc := Vector2.ZERO
	for k in RADII.size():
		var a: float = _t * ANG_SPEED * float(SPEEDS[k]) + float(PHASES[k])
		var v: Vector2 = Vector2(cos(a), sin(a)) * float(RADII[k])
		acc += v
		_dot_positions.append(acc)
	_pen = acc

func _process(delta: float) -> void:
	_t += delta
	_compute_parts()
	# 更新齿轮环与转点位置
	for k in RADII.size():
		_ring_nodes[k].position = Vector3(_dot_positions[k].x, 0.16 + k * 0.012, _dot_positions[k].y)
		_ring_dots[k].position = Vector3(_dot_positions[k + 1].x, 0.34, _dot_positions[k + 1].y)
	_pen_dot.position = Vector3(_pen.x, 0.5, _pen.y)
	# 笔尖轨迹
	_trail_timer -= delta
	while _trail_timer <= 0.0:
		_trail_timer += TRAIL_STEP
		_trail.append(_pen)
		if _trail.size() > TRAIL:
			_trail.pop_front()
	_rebuild_pen()

func _rebuild_pen() -> void:
	_mesh_pen.clear_surfaces()
	# 齿轮链的传动臂（从轴到本轮转点）
	if _dot_positions.size() >= 2:
		_mesh_pen.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat_pen)
		for k in _dot_positions.size():
			var a := float(k) / float(_dot_positions.size() - 1)
			_mesh_pen.surface_set_color(Color(1, 1, 1, 0.45 + a * 0.35))
			_mesh_pen.surface_add_vertex(Vector3(_dot_positions[k].x, 0.24, _dot_positions[k].y))
		_mesh_pen.surface_end()
	# 玫瑰轨迹：头亮尾隐的流动光迹
	if _trail.size() >= 2:
		_mesh_pen.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat_pen)
		var n := _trail.size()
		for i in n:
			var a := float(i) / float(n - 1)
			_mesh_pen.surface_set_color(Color(1, 1, 1, a * 0.9))
			_mesh_pen.surface_add_vertex(Vector3(_trail[i].x, 0.42, _trail[i].y))
		_mesh_pen.surface_end()
