class_name DisasterFX
extends Node3D
## 天灾演出：世界毁灭的炸裂特效与乱纪元的灾难氛围。
## - play_doom()：连环爆闪、地面火海、崩裂飞石、扩张冲击波、叠层音效；
## - lightning()：单次雷击（高空强光爆闪 + 雷声）；
## - strike(kind)：天灾短爆闪（酷热=橙红火光 / 严寒=蓝白寒潮）；
## - ambient(kind)：乱纪元氛围（酷热=远方轰鸣余爆 / 严寒=低鸣风声）。

const FIRE_PITS := 16
const DEBRIS_AMOUNT := 300
const ASH_AMOUNT := 500
const DOOM_SECONDS := 6.5
const AMBIENT_INTERVAL := [7.0, 12.0]

var _center := Vector3.ZERO
var _doom_t := -1.0
var _fire: CPUParticles3D = null
var _debris: CPUParticles3D = null
var _blasts: Array[Dictionary] = []
var _shockwaves: Array[Dictionary] = []
var _bolts: Array[Dictionary] = []
var _ambient_kind := ""
var _ambient_timer := 0.0
var _ambient_pitch := 1.0

func _ready() -> void:
	set_process(false)

func play_doom(center: Vector3) -> void:
	_center = center
	ambient_off()
	_doom_t = 0.0
	_build_fire()
	_build_debris()
	_schedule_blasts()
	_launch_shockwaves()
	if AudioManager != null:
		AudioManager.play("braam", -2.0, 0.85)
		AudioManager.play("discharge", -3.0, 0.9)
		AudioManager.play("whoosh", -4.0, 0.7)
		AudioManager.play("raygun", -7.0, 0.55)
		AudioManager.play("blaster", -8.0, 0.5)
	set_process(true)

## 单次雷击：高空爆闪 + 雷声（可被天气系统与剧情天灾复用）
func lightning(near: Vector3 = Vector3.ZERO) -> void:
	var offset := Vector3(randf_range(-30.0, 30.0), 0.0, randf_range(-30.0, 30.0))
	var top := near + offset + Vector3(0, 55.0, 0)
	var bolt := _make_bolt(top, near + Vector3(offset.x * 0.3, 0.0, offset.z * 0.3))
	add_child(bolt)
	_bolts.append({"mesh": bolt, "t": 0.0})
	var flash := _make_blast_light(top, 14.0, Color(0.85, 0.9, 1.0))
	add_child(flash)
	_blasts.append({"light": flash, "energy": 14.0, "decay": 10.0})
	if AudioManager != null:
		AudioManager.play("discharge", -8.0, randf_range(0.7, 1.1))
		AudioManager.play("whoosh", -10.0, 0.6)
	if not is_processing():
		set_process(true)

## 天灾短爆闪：hot=橙红火光 / cold=蓝白寒潮
func strike(kind: String, near: Vector3 = Vector3.ZERO) -> void:
	var hot := kind == "hot"
	var light := _make_blast_light(
		near + Vector3(randf_range(-8.0, 8.0), randf_range(6.0, 14.0), randf_range(-8.0, 8.0)),
		9.0, Color(1.0, 0.45, 0.15) if hot else Color(0.55, 0.75, 1.0))
	add_child(light)
	_blasts.append({"light": light, "energy": 9.0, "decay": 6.0})
	if AudioManager != null:
		AudioManager.play("discharge", -6.0, 1.1 if hot else 0.65)
		AudioManager.play("whoosh", -7.0, 0.5 if hot else 0.85)
	if not is_processing():
		set_process(true)

## 乱纪元氛围：酷热=远方轰鸣余爆 / 严寒=低鸣风声
func ambient(kind: String) -> void:
	_ambient_kind = kind
	_ambient_timer = randf_range(AMBIENT_INTERVAL[0], AMBIENT_INTERVAL[1])
	_ambient_pitch = randf_range(0.9, 1.1)
	set_process(true)

func ambient_off() -> void:
	_ambient_kind = ""

func stop_all() -> void:
	_doom_t = -1.0
	_ambient_kind = ""
	for b in _blasts:
		var l: OmniLight3D = b["light"]
		if l != null and is_instance_valid(l):
			l.queue_free()
	_blasts.clear()
	for s in _shockwaves:
		var m: MeshInstance3D = s["mesh"]
		if m != null and is_instance_valid(m):
			m.queue_free()
	_shockwaves.clear()
	for b in _bolts:
		var m: MeshInstance3D = b["mesh"]
		if m != null and is_instance_valid(m):
			m.queue_free()
	_bolts.clear()
	if _fire != null and is_instance_valid(_fire):
		_fire.queue_free()
		_fire = null
	if _debris != null and is_instance_valid(_debris):
		_debris.queue_free()
		_debris = null
	set_process(false)

func _process(delta: float) -> void:
	var busy := false
	if _doom_t >= 0.0:
		_doom_t += delta
		busy = true
		if _fire != null and is_instance_valid(_fire):
			_fire.global_position = _center
		if _doom_t >= DOOM_SECONDS and _debris != null and is_instance_valid(_debris):
			_debris.emitting = false
		if _doom_t >= DOOM_SECONDS + 4.0:
			if _fire != null and is_instance_valid(_fire):
				_fire.emitting = false
			_doom_t = -1.0
	busy = _tick_blasts(delta) or busy
	busy = _tick_shockwaves(delta) or busy
	busy = _tick_bolts(delta) or busy
	busy = _tick_ambient(delta) or busy
	if not busy:
		set_process(false)

func _tick_blasts(delta: float) -> bool:
	if _blasts.is_empty():
		return false
	var keep: Array[Dictionary] = []
	for b in _blasts:
		var l: OmniLight3D = b["light"]
		if l == null or not is_instance_valid(l):
			continue
		if b.has("delay"):
			var d: float = b["delay"] - delta
			if d > 0.0:
				b["delay"] = d
				keep.append(b)
				continue
			b.erase("delay")
			var peak: float = b["peak"]
			b["energy"] = peak
			l.light_energy = peak
			if AudioManager != null:
				AudioManager.play("discharge", -9.0, randf_range(0.8, 1.15))
			keep.append(b)
			continue
		var e: float = b["energy"]
		e -= float(b["decay"]) * delta
		l.light_energy = maxf(e, 0.0)
		if e <= 0.05:
			l.queue_free()
		else:
			b["energy"] = e
			keep.append(b)
	_blasts = keep
	return not _blasts.is_empty()

func _tick_shockwaves(delta: float) -> bool:
	if _shockwaves.is_empty():
		return false
	var keep: Array[Dictionary] = []
	for s in _shockwaves:
		var m: MeshInstance3D = s["mesh"]
		if m == null or not is_instance_valid(m):
			continue
		var t: float = s["t"] + delta
		var span: float = s["span"]
		if t >= span:
			m.queue_free()
			continue
		if t < 0.0:
			m.visible = false
			s["t"] = t
			keep.append(s)
			continue
		m.visible = true
		var k := t / span
		var radius: float = lerpf(2.0, 68.0, pow(k, 0.65))
		m.scale = Vector3.ONE * radius
		var mat: StandardMaterial3D = m.get_active_material(0)
		if mat != null:
			mat.albedo_color.a = (1.0 - k) * 0.4
		s["t"] = t
		keep.append(s)
	_shockwaves = keep
	return not _shockwaves.is_empty()

func _tick_bolts(delta: float) -> bool:
	if _bolts.is_empty():
		return false
	var keep: Array[Dictionary] = []
	for b in _bolts:
		var m: MeshInstance3D = b["mesh"]
		if m == null or not is_instance_valid(m):
			continue
		var t: float = b["t"] + delta
		if t >= 0.14:
			m.queue_free()
			continue
		m.visible = fmod(t, 0.07) < 0.045
		b["t"] = t
		keep.append(b)
	_bolts = keep
	return not _bolts.is_empty()

func _tick_ambient(delta: float) -> bool:
	if _ambient_kind == "":
		return false
	_ambient_timer -= delta
	if _ambient_timer <= 0.0:
		_ambient_timer = randf_range(AMBIENT_INTERVAL[0], AMBIENT_INTERVAL[1])
		if _ambient_kind == "hot":
			# 远方轰鸣余爆：低频、微光
			var l := _make_blast_light(
				_center + Vector3(randf_range(-45.0, 45.0), randf_range(8.0, 20.0), randf_range(-45.0, 45.0)),
				4.0, Color(1.0, 0.5, 0.2))
			add_child(l)
			_blasts.append({"light": l, "energy": 4.0, "decay": 1.6})
			if AudioManager != null:
				AudioManager.play("discharge", -14.0, randf_range(0.45, 0.6) * _ambient_pitch)
		else:
			if AudioManager != null:
				AudioManager.play("whoosh", -13.0, randf_range(0.4, 0.55) * _ambient_pitch)
	return true

# ---------- 构建 ----------

func _build_fire() -> void:
	if _fire != null and is_instance_valid(_fire):
		_fire.queue_free()
	_fire = CPUParticles3D.new()
	_fire.name = "DoomFire"
	_fire.amount = FIRE_PITS * 60
	_fire.lifetime = 2.6
	_fire.one_shot = false
	_fire.emitting = true
	_fire.explosiveness = 0.55
	_fire.direction = Vector3(0, 1, 0)
	_fire.spread = 32.0
	_fire.gravity = Vector3(0, 4.5, 0)
	_fire.initial_velocity_min = 3.0
	_fire.initial_velocity_max = 9.0
	_fire.scale_amount_min = 0.25
	_fire.scale_amount_max = 1.1
	_fire.color = Color(1.0, 0.42, 0.1, 0.95)
	_fire.visibility_aabb = AABB(Vector3(-70, -4, -70), Vector3(140, 40, 140))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.12, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.05)
	mat.emission_energy_multiplier = 3.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fire.material_override = mat
	_fire.position = _center
	add_child(_fire)

func _build_debris() -> void:
	if _debris != null and is_instance_valid(_debris):
		_debris.queue_free()
	_debris = CPUParticles3D.new()
	_debris.name = "DoomDebris"
	_debris.amount = DEBRIS_AMOUNT
	_debris.lifetime = 3.4
	_debris.one_shot = false
	_debris.emitting = true
	_debris.explosiveness = 0.92
	_debris.direction = Vector3(0, 1, 0)
	_debris.spread = 80.0
	_debris.gravity = Vector3(0, -14.0, 0)
	_debris.initial_velocity_min = 9.0
	_debris.initial_velocity_max = 22.0
	_debris.angular_velocity_min = -9.0
	_debris.angular_velocity_max = 9.0
	_debris.scale_amount_min = 0.2
	_debris.scale_amount_max = 0.85
	_debris.color = Color(0.35, 0.28, 0.22, 1.0)
	_debris.visibility_aabb = AABB(Vector3(-80, -4, -80), Vector3(160, 60, 160))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.32, 0.26)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.18, 0.05)
	mat.emission_energy_multiplier = 0.7
	_debris.material_override = mat
	_debris.position = _center
	add_child(_debris)

func _schedule_blasts() -> void:
	# 连环爆闪：围绕中心的随机延时/位置，从第 0.2 秒起陆续点燃
	var delays := [0.2, 0.5, 0.9, 1.4, 2.0, 2.7, 3.5, 4.4, 5.4]
	for d in delays:
		var l := _make_blast_light(
			_center + Vector3(randf_range(-40.0, 40.0), randf_range(2.0, 24.0), randf_range(-40.0, 40.0)),
			0.0, Color(1.0, 0.55, 0.2))
		add_child(l)
		_blasts.append({"light": l, "energy": 0.0, "peak": randf_range(7.0, 13.0), "decay": 3.0, "delay": d})

func _launch_shockwaves() -> void:
	# 三道扩张冲击波：错峰从中心炸开
	for i in 3:
		var mesh := MeshInstance3D.new()
		mesh.name = "Shockwave%d" % i
		var sphere := SphereMesh.new()
		sphere.radial_segments = 24
		sphere.rings = 12
		sphere.radius = 1.0
		sphere.height = 2.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.75, 0.45, 0.4)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.6, 0.25)
		mat.emission_energy_multiplier = 2.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sphere.material = mat
		mesh.mesh = sphere
		mesh.scale = Vector3.ONE * 2.0
		mesh.position = _center
		add_child(mesh)
		_shockwaves.append({"mesh": mesh, "t": -0.15 * i, "span": 1.9 - 0.25 * i})

func _make_blast_light(pos: Vector3, energy: float, color: Color) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 55.0
	l.shadow_enabled = false
	l.position = pos
	return l

func _make_bolt(top: Vector3, bottom: Vector3) -> MeshInstance3D:
	var bolt := MeshInstance3D.new()
	bolt.name = "LightningBolt"
	var height := top.distance_to(bottom)
	var box := BoxMesh.new()
	box.size = Vector3(0.35, height, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.95, 1.0, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.75, 0.85, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat
	bolt.mesh = box
	bolt.position = (top + bottom) / 2.0
	bolt.transform = bolt.transform.looking_at(bottom, Vector3.UP)
	bolt.rotate_object_local(Vector3(1, 0, 0), PI / 2.0)
	return bolt
