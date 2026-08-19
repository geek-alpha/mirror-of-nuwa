class_name Building
extends StaticBody3D
## 建筑：由角色建造或初始生成，具有功能、耐久度。
## 外观按样式（style）程序化搭建：茅屋/长屋/圣殿/工坊/围栏/农田/祭台/图腾/篝火等。

const WOOD := Color(0.44, 0.31, 0.18)
const THATCH := Color(0.63, 0.5, 0.27)
const STONE := Color(0.48, 0.46, 0.5)
const DARK_STONE := Color(0.31, 0.29, 0.34)

var building_id: String = "building_house"
var building_name: String = "部落小屋"
var function: String = "housing"
var durability: float = 100.0
var max_durability: float = 100.0
var faction_id: String = ""
var style: String = "hut"
var residents: Array = []

var _part_count := 0
var _fire_light: OmniLight3D = null
var _fire_particles: CPUParticles3D = null
var _glow_mat: StandardMaterial3D = null
var _pulse_seed := 0.0

@onready var mesh: MeshInstance3D = $Mesh
@onready var collision: CollisionShape3D = $Collision

func setup(data: Dictionary, faction: String, position: Vector3, color: Color) -> void:
	building_id = str(data.get("id", building_id))
	building_name = str(data.get("name", building_name))
	function = str(data.get("function", "housing"))
	durability = float(data.get("durability", 100.0))
	max_durability = durability
	faction_id = faction
	global_position = position
	style = str(data.get("style", "hut"))
	_pulse_seed = randf() * 100.0
	_clear_extra_parts()
	_part_count = 0
	_build_visual(data, color)
	_build_collision(data)
	if style == "altar" or style == "bonfire":
		_setup_fire(Vector3(0.9, 0.0, 0.7) if style == "altar" else Vector3.ZERO)

func _clear_extra_parts() -> void:
	for child in get_children():
		if child.name != "Mesh" and child.name != "Collision":
			child.queue_free()

func _build_collision(data: Dictionary) -> void:
	var size: Array = data.get("size", [4, 3, 4])
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(float(size[0]), float(size[1]), float(size[2]))
	collision.shape = col_shape
	collision.position.y = float(size[1]) / 2.0

func _mat(color: Color, rough: float = 0.85, metal: float = 0.0, emission: Color = Color.BLACK, em: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = em
	return m

func _part(part_mesh: Mesh, mat: StandardMaterial3D, pos: Vector3, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi: MeshInstance3D
	if _part_count == 0:
		mi = mesh
	else:
		mi = MeshInstance3D.new()
		add_child(mi)
	_part_count += 1
	mi.mesh = part_mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scale
	return mi

func _build_visual(data: Dictionary, color: Color) -> void:
	match style:
		"longhouse":
			_style_longhouse(color)
		"temple":
			_style_temple(color)
		"workshop":
			_style_workshop(color)
		"palisade":
			_style_palisade(data, color)
		"farm":
			_style_farm(data)
		"lab":
			_style_lab(color)
		"altar":
			_style_altar(color)
		"totem":
			_style_totem(color)
		"bonfire":
			_style_bonfire(color)
		_:
			_style_hut(color)

# ---------- 样式 ----------

func _style_hut(color: Color) -> void:
	## 圆形茅屋：木墙 + 茅草/部族布顶
	var wall := CylinderMesh.new()
	wall.top_radius = 1.25
	wall.bottom_radius = 1.4
	wall.height = 1.7
	wall.radial_segments = 8
	_part(wall, _mat(WOOD, 0.95), Vector3(0, 0.85, 0))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = 1.6
	roof.height = 1.4
	roof.radial_segments = 8
	var roof_color := THATCH.lerp(color, 0.35).darkened(0.1)
	_part(roof, _mat(roof_color, 0.9), Vector3(0, 1.7 + 0.7, 0))
	var door := BoxMesh.new()
	door.size = Vector3(0.62, 1.05, 0.12)
	_part(door, _mat(WOOD.darkened(0.35), 0.95), Vector3(0, 0.55, 1.35))

func _style_longhouse(color: Color) -> void:
	## 长屋：木架 + 双坡布顶
	var base := BoxMesh.new()
	base.size = Vector3(5.2, 2.0, 3.6)
	_part(base, _mat(WOOD, 0.95), Vector3(0, 1.0, 0))
	var roof_l := BoxMesh.new()
	roof_l.size = Vector3(3.0, 0.28, 3.8)
	_part(roof_l, _mat(color.darkened(0.25), 0.9), Vector3(-1.05, 2.75, 0), Vector3(0, 0, 38))
	var roof_r := BoxMesh.new()
	roof_r.size = Vector3(3.0, 0.28, 3.8)
	_part(roof_r, _mat(color.darkened(0.25), 0.9), Vector3(1.05, 2.75, 0), Vector3(0, 0, -38))
	var door := BoxMesh.new()
	door.size = Vector3(0.7, 1.2, 0.14)
	_part(door, _mat(WOOD.darkened(0.4), 0.95), Vector3(0, 0.6, 1.8))

func _style_temple(color: Color) -> void:
	## 圣殿：阶梯金字塔 + 顶部晶辉
	var step1 := BoxMesh.new()
	step1.size = Vector3(5.6, 1.3, 5.6)
	_part(step1, _mat(STONE, 0.9), Vector3(0, 0.65, 0))
	var step2 := BoxMesh.new()
	step2.size = Vector3(4.0, 1.1, 4.0)
	_part(step2, _mat(STONE.darkened(0.08), 0.9), Vector3(0, 1.85, 0))
	var step3 := BoxMesh.new()
	step3.size = Vector3(2.6, 1.0, 2.6)
	_part(step3, _mat(STONE.darkened(0.16), 0.9), Vector3(0, 2.9, 0))
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 0.42
	crystal.height = 1.6
	crystal.radial_segments = 5
	_glow_mat = _mat(color, 0.3, 0.2, color, 1.5)
	_part(crystal, _glow_mat, Vector3(0, 4.2, 0))
	var entrance := BoxMesh.new()
	entrance.size = Vector3(1.4, 2.0, 0.3)
	_part(entrance, _mat(DARK_STONE, 0.9), Vector3(0, 1.0, 2.85))

func _style_workshop(color: Color) -> void:
	## 工坊：立柱 + 棚顶 + 工作台
	var roof := BoxMesh.new()
	roof.size = Vector3(4.8, 0.26, 4.8)
	_part(roof, _mat(THATCH, 0.9), Vector3(0, 2.35, 0))
	for i in 4:
		var px := -1.8 if i % 2 == 0 else 1.8
		var pz := -1.8 if i < 2 else 1.8
		var post := CylinderMesh.new()
		post.top_radius = 0.11
		post.bottom_radius = 0.14
		post.height = 2.2
		post.radial_segments = 6
		_part(post, _mat(WOOD, 0.95), Vector3(px, 1.1, pz))
	var table := BoxMesh.new()
	table.size = Vector3(1.7, 0.75, 0.9)
	_part(table, _mat(WOOD.darkened(0.15), 0.95), Vector3(0.4, 0.55, 0.3))
	var tool_rack := BoxMesh.new()
	tool_rack.size = Vector3(1.6, 0.12, 0.3)
	_part(tool_rack, _mat(color.darkened(0.3), 0.9), Vector3(-0.5, 1.9, 1.4))

func _style_palisade(data: Dictionary, color: Color) -> void:
	## 原木围栏：一排尖头木桩
	var size: Array = data.get("size", [8, 3, 1])
	var length := float(size[0])
	var log_h := float(size[1])
	var count := clampi(int(length / 0.75), 3, 14)
	for i in count:
		var t := float(i) / float(maxi(count - 1, 1))
		var px := -length / 2.0 + length * t
		var log_mesh := CylinderMesh.new()
		log_mesh.top_radius = 0.18
		log_mesh.bottom_radius = 0.22
		log_mesh.height = log_h
		log_mesh.radial_segments = 7
		_part(log_mesh, _mat(WOOD, 0.95), Vector3(px, log_h / 2.0, 0))
		var tip := CylinderMesh.new()
		tip.top_radius = 0.0
		tip.bottom_radius = 0.18
		tip.height = 0.5
		tip.radial_segments = 7
		_part(tip, _mat(WOOD.darkened(0.1), 0.95), Vector3(px, log_h + 0.25, 0))

func _style_farm(data: Dictionary) -> void:
	## 农田：黑土 + 成排晶苗
	var size: Array = data.get("size", [6, 1, 6])
	var w := float(size[0])
	var d := float(size[2])
	var soil := BoxMesh.new()
	soil.size = Vector3(w, 0.35, d)
	_part(soil, _mat(Color(0.32, 0.22, 0.14), 1.0), Vector3(0, 0.12, 0))
	var rows := 4
	var cols := 4
	for r in rows:
		for c in cols:
			var px := -w * 0.34 + w * 0.68 * (float(c) / float(maxi(cols - 1, 1)))
			var pz := -d * 0.34 + d * 0.68 * (float(r) / float(maxi(rows - 1, 1)))
			var crop := CylinderMesh.new()
			crop.top_radius = 0.0
			crop.bottom_radius = 0.16
			crop.height = 0.55
			crop.radial_segments = 5
			_part(crop, _mat(Color(0.34, 0.62, 0.32), 1.0), Vector3(px, 0.45, pz))

func _style_lab(color: Color) -> void:
	## 遗迹研究室：残柱 + 石板顶 + 发光符文
	var roof := BoxMesh.new()
	roof.size = Vector3(5.0, 0.32, 3.2)
	_part(roof, _mat(STONE.darkened(0.12), 0.9), Vector3(0, 2.6, 0))
	for i in 2:
		var px := -2.0 if i == 0 else 2.0
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.32
		pillar.bottom_radius = 0.4
		pillar.height = 2.5
		pillar.radial_segments = 8
		_part(pillar, _mat(STONE, 0.9), Vector3(px, 1.25, 0))
	var rune := BoxMesh.new()
	rune.size = Vector3(1.1, 0.2, 0.14)
	_glow_mat = _mat(color, 0.4, 0.2, color, 1.4)
	_part(rune, _glow_mat, Vector3(0, 2.85, 1.6))

func _style_altar(color: Color) -> void:
	## 祭台：石台 + 环立圣石 + 中央晶辉 + 祭火
	var platform := CylinderMesh.new()
	platform.top_radius = 2.0
	platform.bottom_radius = 2.15
	platform.height = 0.42
	platform.radial_segments = 12
	_part(platform, _mat(STONE, 0.85), Vector3(0, 0.21, 0))
	var ring := TorusMesh.new()
	ring.inner_radius = 1.28
	ring.outer_radius = 1.36
	ring.rings = 16
	ring.ring_segments = 6
	var ring_mat := _mat(color, 0.4, 0.2, color, 1.2)
	_part(ring, ring_mat, Vector3(0, 0.45, 0), Vector3(90, 0, 0))
	for i in 5:
		var ang := TAU / 5.0 * i
		var px := cos(ang) * 1.75
		var pz := sin(ang) * 1.75
		var stone := CylinderMesh.new()
		stone.top_radius = 0.26
		stone.bottom_radius = 0.36
		stone.height = 2.2
		stone.radial_segments = 7
		_part(stone, _mat(DARK_STONE, 0.9), Vector3(px, 1.1, pz), Vector3(-sin(ang) * 10, 0, cos(ang) * 10))
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 0.48
	crystal.height = 2.2
	crystal.radial_segments = 5
	_glow_mat = _mat(color, 0.3, 0.2, color, 1.6)
	_part(crystal, _glow_mat, Vector3(0, 2.6, 0))
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.55
	bowl.bottom_radius = 0.62
	bowl.height = 0.36
	bowl.radial_segments = 8
	_part(bowl, _mat(DARK_STONE, 0.9), Vector3(0.9, 0.32, 0.7))

func _style_totem(color: Color) -> void:
	## 图腾柱：木柱 + 叠层兽首 + 顶部晶辉
	var pole := CylinderMesh.new()
	pole.top_radius = 0.14
	pole.bottom_radius = 0.2
	pole.height = 3.4
	pole.radial_segments = 8
	_part(pole, _mat(WOOD, 0.95), Vector3(0, 1.7, 0))
	var head_sizes := [0.42, 0.32, 0.24]
	var head_y := 3.3
	for i in 3:
		var head := SphereMesh.new()
		head.radius = head_sizes[i]
		head.height = head_sizes[i] * 2.0
		head.radial_segments = 8
		head.rings = 4
		_part(head, _mat(color.lerp(WOOD, 0.25), 0.9), Vector3(0, head_y, 0))
		head_y += 0.55
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 0.16
	crystal.height = 0.7
	crystal.radial_segments = 5
	_glow_mat = _mat(color, 0.3, 0.2, color, 1.5)
	_part(crystal, _glow_mat, Vector3(0, head_y + 0.2, 0))

func _style_bonfire(color: Color) -> void:
	## 篝火：石圈 + 柴堆 + 火焰与光源
	var stone_mat := _mat(DARK_STONE, 0.9)
	for i in 6:
		var ang := TAU / 6.0 * i
		var stone := SphereMesh.new()
		stone.radius = 0.2
		stone.height = 0.4
		stone.radial_segments = 6
		_part(stone, stone_mat, Vector3(cos(ang) * 0.85, 0.15, sin(ang) * 0.85))
	for i in 4:
		var ang := TAU / 4.0 * i + 0.4
		var log := CylinderMesh.new()
		log.top_radius = 0.12
		log.bottom_radius = 0.12
		log.height = 1.1
		log.radial_segments = 6
		_part(log, _mat(WOOD.darkened(0.15), 0.95), Vector3(0, 0.12, 0), Vector3(0, rad_to_deg(ang), 90))

func _setup_fire(offset: Vector3) -> void:
	_fire_light = OmniLight3D.new()
	_fire_light.position = offset + Vector3(0, 1.05, 0)
	_fire_light.light_color = Color(1.0, 0.55, 0.18)
	_fire_light.light_energy = 1.15
	_fire_light.omni_range = 7.5
	_fire_light.shadow_enabled = false
	add_child(_fire_light)

	_fire_particles = CPUParticles3D.new()
	_fire_particles.position = offset + Vector3(0, 0.35, 0)
	_fire_particles.amount = 26
	_fire_particles.lifetime = 1.15
	_fire_particles.one_shot = false
	_fire_particles.emitting = true
	_fire_particles.direction = Vector3(0, 1, 0)
	_fire_particles.spread = 24.0
	_fire_particles.gravity = Vector3(0, -0.9, 0)
	_fire_particles.initial_velocity_min = 0.7
	_fire_particles.initial_velocity_max = 1.3
	_fire_particles.scale_amount_min = 0.28
	_fire_particles.scale_amount_max = 0.62
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	grad.set_color(0.55, Color(1.0, 0.45, 0.08, 0.95))
	grad.set_color(1, Color(0.35, 0.05, 0.0, 0.0))
	_fire_particles.color_ramp = grad
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.emission_enabled = true
	pm.emission = Color(1.0, 0.5, 0.15)
	_fire_particles.material_override = pm
	add_child(_fire_particles)

func _process(_delta: float) -> void:
	if _fire_light == null and _glow_mat == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	if _fire_light != null:
		var flicker := 0.8 + 0.25 * (sin(t * 9.0 + _pulse_seed) * 0.6 + sin(t * 14.0 + _pulse_seed * 2.0) * 0.4)
		_fire_light.light_energy = 1.15 * flicker
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 1.2 + 0.45 * sin(t * 2.3 + _pulse_seed)

func to_save_dict() -> Dictionary:
	return {
		"id": building_id,
		"name": building_name,
		"function": function,
		"durability": durability,
		"faction_id": faction_id,
		"position": [global_position.x, global_position.y, global_position.z]
	}
