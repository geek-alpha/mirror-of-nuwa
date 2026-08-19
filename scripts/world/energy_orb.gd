class_name EnergyOrb
extends Node3D
## 运动的能量体：围绕中心做轨道/悬浮/巡逻/线性流动运动，携带辉光、光晕与光尘。
## 用于丰碑、遗迹与机械核心，让“古老文明 × 先进科技”的世界真正“活”起来。
var _color := Color(0.4, 0.9, 1.0)
var _mode := "orbit"
var _center := Vector3.ZERO
var _radius := 3.0
var _speed := 1.0
var _height_amp := 0.6
var _phase := 0.0
var _t := 0.0
var _path: Array = []

var _mesh: MeshInstance3D = null
var _halo: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _light: OmniLight3D = null
var _particles: CPUParticles3D = null
var _pulse_seed := 0.0

func setup(color: Color, mode := "orbit", radius := 3.0, speed := 1.0, height_amp := 0.6) -> void:
	_color = color
	_mode = mode
	_radius = radius
	_speed = speed
	_height_amp = height_amp
	_phase = randf() * TAU
	_pulse_seed = randf() * 100.0
	_build()

func set_center(c: Vector3) -> void:
	_center = c

func set_path(points: Array) -> void:
	_path = points
	if not _path.is_empty():
		_center = _path[0]
	_mode = "patrol"

func _build() -> void:
	var sph := SphereMesh.new()
	sph.radius = 0.26
	sph.height = 0.52
	sph.radial_segments = 12
	sph.rings = 6
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = _color.lightened(0.35)
	_mat.emission_enabled = true
	_mat.emission = _color
	_mat.emission_energy_multiplier = 2.6
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sph
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	var halo_sph := SphereMesh.new()
	halo_sph.radius = 0.42
	halo_sph.height = 0.84
	halo_sph.radial_segments = 10
	halo_sph.rings = 5
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_mat.albedo_color = Color(_color.r, _color.g, _color.b, 0.12)
	halo_mat.emission_enabled = true
	halo_mat.emission = _color
	halo_mat.emission_energy_multiplier = 1.2
	_halo = MeshInstance3D.new()
	_halo.mesh = halo_sph
	_halo.material_override = halo_mat
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)

	_light = OmniLight3D.new()
	_light.light_color = _color
	_light.light_energy = 0.85
	_light.omni_range = 6.5
	_light.shadow_enabled = false
	add_child(_light)

	_particles = CPUParticles3D.new()
	_particles.amount = 8
	_particles.lifetime = 1.8
	_particles.one_shot = false
	_particles.emitting = true
	_particles.direction = Vector3(0, 1, 0)
	_particles.spread = 60.0
	_particles.gravity = Vector3.ZERO
	_particles.initial_velocity_min = 0.12
	_particles.initial_velocity_max = 0.4
	_particles.scale_amount_min = 0.04
	_particles.scale_amount_max = 0.1
	var grad := Gradient.new()
	grad.set_color(0, Color(_color.r, _color.g, _color.b, 0.0))
	grad.set_color(0.5, Color(_color.r, _color.g, _color.b, 0.8))
	grad.set_color(1, Color(_color.r, _color.g, _color.b, 0.0))
	_particles.color_ramp = grad
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.emission_enabled = true
	pm.emission = _color
	_particles.material_override = pm
	add_child(_particles)

func _process(delta: float) -> void:
	_t += delta * _speed
	match _mode:
		"orbit":
			var ang := _t + _phase
			position = _center + Vector3(
				cos(ang) * _radius,
				sin(_t * 1.35 + _phase) * _height_amp,
				sin(ang) * _radius
			)
		"hover":
			position = _center + Vector3(
				sin(_t * 0.7 + _phase) * _radius * 0.25,
				sin(_t * 2.0 + _phase) * _height_amp,
				cos(_t * 0.8 + _phase) * _radius * 0.25
			)
		"stream":
			position = _center + Vector3(
				sin(_t + _phase) * _radius,
				sin(_t * 2.0 + _phase) * _height_amp * 0.3,
				0
			)
		"patrol":
			_tick_patrol()
	if _mat != null:
		_mat.emission_energy_multiplier = 2.2 + 0.9 * sin(_t * 2.6 + _pulse_seed)
	if _light != null:
		_light.light_energy = 0.7 + 0.3 * (sin(_t * 2.4 + _pulse_seed) * 0.6 + sin(_t * 5.1 + _pulse_seed * 2.0) * 0.4)
	if _halo != null:
		_halo.scale = Vector3.ONE * (1.0 + 0.08 * sin(_t * 2.0 + _pulse_seed))

func _tick_patrol() -> void:
	if _path.size() < 2:
		return
	var total := float(_path.size() - 1)
	var f := fposmod(_t, total * 2.0)
	var seg: int
	var tt: float
	if f <= total:
		seg = int(floor(f))
		tt = f - float(seg)
	else:
		var rev := total * 2.0 - f
		seg = int(floor(rev))
		tt = rev - float(seg)
	seg = clampi(seg, 0, _path.size() - 2)
	position = (_path[seg] as Vector3).lerp(_path[seg + 1] as Vector3, tt)
