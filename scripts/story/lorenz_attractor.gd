class_name LorenzAttractor
extends Node3D
## 洛伦茨混沌蝴蝶（三日世界的混沌本质）：
## Lorenz 系统 σ=10、ρ=28、β=8/3（经典“奇异吸引子”参数）以 RK4 积分，
## 在天空中画出一条永恒流动的发光丝带——轨迹永不闭合、永不自交、永远盘旋在同一片云里。
## 三日体问题正是这样：确定性的方程，无法预测的未来。
##
## 乱纪元/毁灭时 boost() 会加快蝶翼扇动并增强辉光，仿佛混沌正在逼近。

const SIGMA := 10.0
const RHO := 28.0
const BETA := 8.0 / 3.0

const TRAIL := 460
const RK4_STEP := 0.006
const COLOR_TAIL := 0.0
const COLOR_HEAD := 0.92

var _mat: StandardMaterial3D = null
var _mesh: ImmediateMesh = null
var _trail: Array[Vector3] = []
var _state := Vector3(1.0, 1.0, 1.0)
var _acc := 0.0
var _t := 0.0
var _scale := 1.0
var _base_speed := 1.0
var _boost := 0.0
var _spin := 0.0

func setup(origin: Vector3, scale := 1.0, color := Color(0.95, 0.9, 1.0), speed := 1.0) -> void:
	position = origin
	_scale = scale
	_base_speed = speed
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.vertex_color_use_as_albedo = true
	_mat.emission_enabled = true
	_mat.emission = color
	_mat.emission_energy_multiplier = 1.6
	_mesh = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	add_child(mi)
	set_process(true)

## 混沌增强：乱纪元/毁灭时提高蝶翼扇动速度与辉光
func boost(amount: float) -> void:
	_boost = clampf(amount, 0.0, 1.0)

func _process(delta: float) -> void:
	_t += delta
	# 混沌状态推进：基准速度之上，乱纪元加速扇动
	_acc += delta * _base_speed * (1.0 + _boost * 2.6)
	var guard := 0
	while _acc >= RK4_STEP and guard < 24:
		_state = _rk4(_state, RK4_STEP)
		_acc -= RK4_STEP
		guard += 1
	# Lorenz 坐标域（x≈[-20,20] y≈[0,50] z≈[-25,25]）缩放到本地球半径内
	var n := (_state - Vector3(0, 25, 0)) / 40.0
	var p := Vector3(n.x, n.y * 0.85, n.z * 0.72) * _scale
	_trail.append(p)
	if _trail.size() > TRAIL:
		_trail.pop_front()
	# 缓慢盘旋：混沌蝴蝶如星座般在天空中自转
	_spin += delta * 0.055 * (1.0 + _boost)
	rotation.y = _spin
	_rebuild()
	# 呼吸辉光
	_mat.emission_energy_multiplier = 1.6 + _boost * 1.8 + sin(_t * 1.3) * 0.15

func _accel(v: Vector3) -> Vector3:
	return Vector3(
		SIGMA * (v.y - v.x),
		v.x * (RHO - v.z) - v.y,
		v.x * v.y - BETA * v.z
	)

## 经典四阶龙格-库塔：比欧拉更稳，长时间演化也不发散
func _rk4(v: Vector3, dt: float) -> Vector3:
	var k1 := _accel(v)
	var k2 := _accel(v + k1 * (dt * 0.5))
	var k3 := _accel(v + k2 * (dt * 0.5))
	var k4 := _accel(v + k3 * dt)
	return v + (k1 + 2.0 * k2 + 2.0 * k3 + k4) * (dt / 6.0)

## 把整条丝带重建为一条带亮度渐变的折线（头亮尾隐，仿佛光在流动）
func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _trail.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat)
	var n := _trail.size()
	for i in n:
		var k := float(i) / float(n - 1)
		var alpha := COLOR_TAIL + (COLOR_HEAD - COLOR_TAIL) * k
		_mesh.surface_set_color(Color(1, 1, 1, alpha))
		_mesh.surface_add_vertex(_trail[i])
	_mesh.surface_end()
