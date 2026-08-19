class_name RelicGlow
extends Node3D
## 上古遗物氛围节点：围绕中心缓慢绕行的发光晶簇 + 脉动光源 + 升腾光尘。
## 用于秘境/沉没之城等"古老文明 × 先进科技"地标的动态点缀。

var _shards: Array[MeshInstance3D] = []
var _light: OmniLight3D = null
var _particles: CPUParticles3D = null
var _t := 0.0
var orbit_radius := 2.2
var orbit_speed := 0.5
var _pulse_seed := 0.0

func setup(color: Color, shard_count := 3, radius := 2.2, with_light := true) -> void:
	orbit_radius = radius
	orbit_speed = 0.35 + randf() * 0.4
	_pulse_seed = randf() * 100.0
	for i in shard_count:
		var shard := MeshInstance3D.new()
		var crystal := CylinderMesh.new()
		crystal.top_radius = 0.0
		crystal.bottom_radius = 0.16 + randf() * 0.1
		crystal.height = 0.7 + randf() * 0.6
		crystal.radial_segments = 5
		shard.mesh = crystal
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = color.darkened(0.4)
		cmat.roughness = 0.25
		cmat.metallic = 0.3
		cmat.emission_enabled = true
		cmat.emission = color
		cmat.emission_energy_multiplier = 1.8
		shard.material_override = cmat
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := TAU / shard_count * i + randf() * 0.5
		shard.position = Vector3(cos(ang) * radius, 1.4, sin(ang) * radius)
		shard.rotation_degrees = Vector3(randf_range(0, 360), randf_range(0, 360), randf_range(0, 360))
		shard.scale = Vector3.ONE * randf_range(0.7, 1.3)
		add_child(shard)
		_shards.append(shard)
	if with_light:
		_light = OmniLight3D.new()
		_light.light_color = color
		_light.light_energy = 0.9
		_light.omni_range = 8.5
		_light.shadow_enabled = false
		_light.position = Vector3(0, 1.8, 0)
		add_child(_light)
	# 升腾光尘
	_particles = CPUParticles3D.new()
	_particles.amount = 10
	_particles.lifetime = 2.8
	_particles.one_shot = false
	_particles.emitting = true
	_particles.direction = Vector3(0, 1, 0)
	_particles.spread = 40.0
	_particles.gravity = Vector3.ZERO
	_particles.initial_velocity_min = 0.15
	_particles.initial_velocity_max = 0.4
	_particles.scale_amount_min = 0.04
	_particles.scale_amount_max = 0.1
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.0))
	grad.set_color(0.5, Color(color.r, color.g, color.b, 0.8))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	_particles.color_ramp = grad
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.emission_enabled = true
	pm.emission = color
	_particles.material_override = pm
	add_child(_particles)

func _process(delta: float) -> void:
	_t += delta
	var t := _t
	for i in _shards.size():
		var shard := _shards[i]
		var ang := t * orbit_speed + TAU / maxi(_shards.size(), 1) * i
		var radius := orbit_radius * (0.92 + sin(t * 0.7 + i * 2.3) * 0.08)
		shard.position = Vector3(
			cos(ang) * radius,
			1.35 + sin(t * 1.1 + i * 2.1) * 0.4,
			sin(ang) * radius
		)
		shard.rotation.y += delta * 1.2
		shard.rotation.x += delta * 0.6
	if _light != null:
		var flicker := 0.75 + 0.35 * (sin(t * 2.2 + _pulse_seed) * 0.6 + sin(t * 4.6 + _pulse_seed * 2.0) * 0.4)
		_light.light_energy = 0.9 * flicker