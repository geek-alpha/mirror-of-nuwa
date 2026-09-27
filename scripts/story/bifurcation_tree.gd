class_name BifurcationTree
extends Node3D
## 冯·诺伊曼纪 · 分岔之树：
## 一行迭代 x_{n+1} = r·x_n·(1-x_n)，从 r=2.8 走到 4.0——
## 周期一分为二、再分为四、八……最终混沌铺满整段区间。
## 这棵“树”就是混沌的谱系：无限复杂藏在最简单的规则里。
## 人列计算机在算的就是这样一棵树；一道光扫过树干，把每一根枝杈逐一照亮。

const R_MIN := 2.8
const R_MAX := 4.0
const R_STEPS := 420
const ITER_SETTLE := 200
const ATTRACT_PTS := 16
const WIDTH := 52.0
const HEIGHT := 28.0
const POINT_SIZE := 0.13
const SWEEP_TIME := 26.0

var _t := 0.0
var _sweep := 0.0
var _tree_mesh: ArrayMesh = null
var _tree_mat: StandardMaterial3D = null
var _sweep_mesh: ImmediateMesh = null
var _sweep_mat: StandardMaterial3D = null

func setup(center: Vector3, facing := Vector3(0, 0, -1)) -> void:
	var base_y := WorldManager.get_terrain_height(center.x, center.z)
	position = Vector3(center.x, base_y, center.z)
	if facing.dot(Vector3(0, 0, -1)) < 0.0:
		rotation.y = PI
	_build_pedestal()
	_build_tree()
	_sweep_mat = StandardMaterial3D.new()
	_sweep_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sweep_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sweep_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_sweep_mat.vertex_color_use_as_albedo = true
	_sweep_mat.emission_enabled = true
	_sweep_mat.emission = Color(1.0, 0.85, 0.45)
	_sweep_mat.emission_energy_multiplier = 2.0
	_sweep_mesh = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _sweep_mesh
	add_child(mi)
	set_process(true)

func _glow_mat(color: Color, energy := 1.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

func _build_pedestal() -> void:
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH + 3.0, 0.6, 2.4)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.12, 0.18)
	m.roughness = 0.9
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.85
	box.material = m
	slab.mesh = box
	slab.position = Vector3(0, 0.3, 0)
	add_child(slab)
	for k in 2:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.22
		cyl.bottom_radius = 0.3
		cyl.height = HEIGHT
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.13, 0.1, 0.16)
		pm.roughness = 0.9
		cyl.material = pm
		post.mesh = cyl
		post.position = Vector3((WIDTH + 1.6) * (0.5 if k == 0 else -0.5) * 0.92, HEIGHT * 0.5, 0)
		add_child(post)

## 计算并铸成整棵分岔树：每根 r 迭代出稳定的吸引子点集，画成发光碎点
func _build_tree() -> void:
	_tree_mat = StandardMaterial3D.new()
	_tree_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tree_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tree_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tree_mat.vertex_color_use_as_albedo = true
	_tree_mat.emission_enabled = true
	_tree_mat.emission = Color(1.0, 0.72, 0.35)
	_tree_mat.emission_energy_multiplier = 1.5

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var s := POINT_SIZE * 0.5
	var x_step := (R_MAX - R_MIN) / float(R_STEPS - 1)
	for k in R_STEPS:
		var r := R_MIN + x_step * k
		var x := 0.5
		for _i in ITER_SETTLE:
			x = r * x * (1.0 - x)
		var wx := (r - R_MIN) / (R_MAX - R_MIN) * WIDTH - WIDTH * 0.5
		for _j in ATTRACT_PTS:
			x = r * x * (1.0 - x)
			var wy := 0.4 + x * (HEIGHT - 0.8)
			var hue := Color(
				1.0,
				0.55 + x * 0.35,
				0.25 + x * 0.25,
				0.85
			)
			var base := verts.size()
			verts.append(Vector3(wx - s, wy - s, 0.0))
			verts.append(Vector3(wx + s, wy - s, 0.0))
			verts.append(Vector3(wx + s, wy + s, 0.0))
			verts.append(Vector3(wx - s, wy + s, 0.0))
			for _c in 4:
				colors.append(hue)
			indices.append(base)
			indices.append(base + 1)
			indices.append(base + 2)
			indices.append(base)
			indices.append(base + 2)
			indices.append(base + 3)
	_tree_mesh = ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3(0, 0, 1))
	arrays[Mesh.ARRAY_NORMAL] = normals
	_tree_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = _tree_mesh
	mi.material_override = _tree_mat
	add_child(mi)

func _process(delta: float) -> void:
	_t += delta
	_sweep = fmod(_sweep + delta / SWEEP_TIME, 1.0)
	_tree_mat.emission_energy_multiplier = 1.4 + sin(_t * 1.1) * 0.18
	var r := lerpf(R_MIN, R_MAX, _sweep)
	var wx := (r - R_MIN) / (R_MAX - R_MIN) * WIDTH - WIDTH * 0.5
	_rebuild_sweep(wx)

## 扫过树干的光：主刃 + 两侧余晖
func _rebuild_sweep(wx: float) -> void:
	_sweep_mesh.clear_surfaces()
	_sweep_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _sweep_mat)
	var y0 := -1.0
	var y1 := HEIGHT + 1.0
	_add_quad(_sweep_mesh, wx, y0, wx, y1, 0.10, Color(1, 1, 1, 0.95))
	_add_quad(_sweep_mesh, wx, y0, wx, y1, 0.55, Color(1, 1, 1, 0.22))
	_sweep_mesh.surface_end()

func _add_quad(mesh: ImmediateMesh, x0: float, y0: float, x1: float, y1: float, half_w: float, col: Color) -> void:
	mesh.surface_set_color(col)
	mesh.surface_add_vertex(Vector3(x0 - half_w, y0, 0))
	mesh.surface_set_color(col)
	mesh.surface_add_vertex(Vector3(x0 + half_w, y0, 0))
	mesh.surface_set_color(col)
	mesh.surface_add_vertex(Vector3(x0 + half_w, y1, 0))
	mesh.surface_set_color(col)
	mesh.surface_add_vertex(Vector3(x0 - half_w, y0, 0))
	mesh.surface_set_color(col)
	mesh.surface_add_vertex(Vector3(x0 + half_w, y1, 0))
	mesh.surface_set_color(col)
	mesh.surface_add_vertex(Vector3(x0 - half_w, y1, 0))
