class_name ThreeBodySky
extends Node3D
## 三体游戏的世界氛围层：
## 三颗太阳（酷热/严寒/恒纪元三态）、纪元色调天空、巨石遗迹，
## 以及周文王的“生命游戏”棋盘（康威生命游戏，忠实还原小说设定）。

enum State { STABLE, HOT, COLD, DESTROYED }

const SUN_BASE_RADIUS := 13.0
const SKY_RADIUS := 190.0

# ---- 三体引力模拟（真实三体运动，恒星位置由引力方程决定） ----
const GRAV_G := 1.0
const SOFTENING := 0.03
## 软性约束半径：混沌解偶尔会把恒星甩远，超出后缓慢拉回，避免恒星永久逃逸
const CONTAIN_RADIUS := 2.6
const CONTAIN_STRENGTH := 3.0
## 行星守护半径：恒星过于贴近行星时（视角天球上方向会剧烈翻转/瞬跳），
## 用平滑斥力把它推开，保持轨迹连续——行星不是恒星掠过时该经过的地方
const PLANET_GUARD_RADIUS := 0.22
const PLANET_GUARD_STRENGTH := 20.0
## 模拟速度：抽象时间单位/秒（放慢后势态窗口更长，纪元切换节奏更合理）
const SIM_SPEED := 0.015
const SIM_DT := 0.004
## 天象势态阈值（以最近显著飞星的距离衡量）：逼近 = 酷热，远去 = 严寒，中间 = 恒纪元
const THERMAL_HOT_R := 0.34
const THERMAL_COLD_R := 0.8
## 显著飞星半径：只有同时“在地平线上”且“离行星足够近”的恒星才算当空飞星。
## 远去的恒星隐入星空（飞星尽没），不参与天象判定，也不在天空显示。
const PROMINENT_RADIUS := 1.3
const PROMINENT_BAND := 0.15
## 轨道平面相对地平线的倾角（恒星在天空中升起/落下）
const PLANE_TILT := 0.72
## 行星自转：太阳缓慢划过天空，形成昼夜
const WORLD_SPIN := 0.021
## 地平线判定迟滞带：恒星在带内保持原状态，避免在交界处闪烁
const HORIZON_BAND := 16.0
## 太阳可见性过渡速度：升起/落下时平滑淡入淡出，不再瞬间闪现/消失
const SUN_FADE_SPEED := 1.8
## 太阳尾迹保留点数（约 8 秒），勾勒出连续流动的轨道弧线
const TRAIL_POINTS := 480

var world: Node3D = null
var env: Environment = null
var sky_material: ProceduralSkyMaterial = null
var state := State.STABLE
## 自由模拟接入：true 时仍生成剧情专用的地面几何（黄金螺线/斐波那契环）与纪元道具
var story_props_enabled := true
## 自由模拟接入：true 时由天象趋势自行驱动纪元状态（无剧情、无过场）
var auto_era := false

var _suns: Array[MeshInstance3D] = []
var _sun_lights: Array[DirectionalLight3D] = []
var _sun_mats: Array[StandardMaterial3D] = []
var _sun_targets: Array[Dictionary] = []
var _state_sun_targets: Array[Dictionary] = []
var _sky_target: Dictionary = {}
var _state_sky_target: Dictionary = {}
var _triple_override_active := false

var _board_cells: Array[MeshInstance3D] = []
var _board_mats: Array[StandardMaterial3D] = []
var _board_state: Array = []
var _board_size := 13
var _board_timer := 0.0

var _base_sky: Dictionary = {}
var _t := 0.0
var _props_spawned := false
var _pulse := 0.0
var _pulse_duration := 1.0
var _trail_meshes: Array[MeshInstance3D] = []
var _trail_points: Array = [[], [], []]
var _trail_material: StandardMaterial3D = null
const AUTO_ERA_HOLD := 6.0
var _auto_tendency := ""
var _auto_accum := 0.0

# ---- 三体模拟状态（抽象单位，原点即行星所在） ----
var _pos2: Array[Vector2] = []
var _vel2: Array[Vector2] = []
var _world_rot := 0.0
var _tilt_cos := cos(PLANE_TILT)
var _tilt_sin := sin(PLANE_TILT)
var _above := [false, false, false]
var _near := [true, true, true]
var _sun_fade: Array[float] = [0.0, 0.0, 0.0]
var _up_indices: Array[int] = []
## 每颗恒星上一帧的天球方向：恒星掠过行星正上方时沿用，保证轨迹连续不瞬跳
var _last_dir: Array[Vector3] = [Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 1, 0)]
var _masses := [1.0, 1.0, 1.0]
var _kick_timer := 0.0
var _heat_particles: CPUParticles3D = null
var _snow_particles: CPUParticles3D = null
var _ash_particles: CPUParticles3D = null
var _revival_particles: CPUParticles3D = null
var _lorenz: LorenzAttractor = null

func setup(world_node: Node3D, story_props := true) -> void:
	story_props_enabled = story_props
	world = world_node
	if world.has_node("WorldEnvironment"):
		env = world.get_node("WorldEnvironment").environment
	if env != null and env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		sky_material = env.sky.sky_material
	_capture_base()
	_init_three_body()
	for i in 3:
		var sun := MeshInstance3D.new()
		sun.name = "Sun%02d" % i
		var mesh := SphereMesh.new()
		mesh.radius = SUN_BASE_RADIUS
		mesh.height = SUN_BASE_RADIUS * 2.0
		mesh.radial_segments = 24
		mesh.rings = 12
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.42, 0.12)
		mat.emission_energy_multiplier = 4.0
		mesh.material = mat
		sun.mesh = mesh
		add_child(sun)
		_suns.append(sun)
		_sun_mats.append(mat)
		var light := DirectionalLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.3)
		light.light_energy = 1.0
		add_child(light)
		_sun_lights.append(light)
	_trail_material = StandardMaterial3D.new()
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.albedo_color = Color(1.0, 0.85, 0.55, 0.35)
	_trail_material.emission_enabled = true
	_trail_material.emission = Color(1.0, 0.85, 0.55)
	_trail_material.emission_energy_multiplier = 1.4
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = "SunTrail%02d" % i
		mi.mesh = ImmediateMesh.new()
		add_child(mi)
		_trail_meshes.append(mi)
	if story_props_enabled:
		_build_ground_geometry()
	_build_weather_particles()
	_spawn_lorenz()
	set_state(State.STABLE)

## 混沌蝴蝶：天空中的洛伦茨吸引子丝带——三日世界混沌本质的化身。
## 它永远盘旋、永不自交、永不重复，仿佛三体问题本身。
func _spawn_lorenz() -> void:
	_lorenz = LorenzAttractor.new()
	_lorenz.name = "LorenzButterfly"
	_lorenz.setup(Vector3(150, 118, 70), 26.0, Color(0.95, 0.9, 1.0), 1.0)
	_lorenz.rotation_degrees = Vector3(-16, 0, 0)
	add_child(_lorenz)

## 纪元大气特效：酷热的热浪火星、严寒的飞雪、毁灭的灰烬
func _build_weather_particles() -> void:
	_heat_particles = CPUParticles3D.new()
	_heat_particles.name = "HeatEmbers"
	_heat_particles.amount = 340
	_heat_particles.lifetime = 2.2
	_heat_particles.one_shot = false
	_heat_particles.emitting = false
	_heat_particles.direction = Vector3(0, 1, 0)
	_heat_particles.spread = 28.0
	_heat_particles.gravity = Vector3(0, 1.1, 0)
	_heat_particles.initial_velocity_min = 0.5
	_heat_particles.initial_velocity_max = 1.5
	_heat_particles.scale_amount_min = 0.035
	_heat_particles.scale_amount_max = 0.12
	_heat_particles.color = Color(1.0, 0.45, 0.15, 0.95)
	_heat_particles.visibility_aabb = AABB(Vector3(-80, -4, -80), Vector3(160, 60, 160))
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ember_mat.albedo_color = Color(1.0, 0.45, 0.15, 0.9)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.42, 0.12)
	ember_mat.emission_energy_multiplier = 2.4
	_heat_particles.material_override = ember_mat
	add_child(_heat_particles)

	_snow_particles = CPUParticles3D.new()
	_snow_particles.name = "SnowFall"
	_snow_particles.amount = 1300
	_snow_particles.lifetime = 5.0
	_snow_particles.one_shot = false
	_snow_particles.emitting = false
	_snow_particles.direction = Vector3(0, -1, 0)
	_snow_particles.spread = 16.0
	_snow_particles.gravity = Vector3(0, -2.2, 0)
	_snow_particles.initial_velocity_min = 0.5
	_snow_particles.initial_velocity_max = 1.6
	_snow_particles.scale_amount_min = 0.05
	_snow_particles.scale_amount_max = 0.2
	_snow_particles.color = Color(0.9, 0.95, 1.0, 0.95)
	_snow_particles.visibility_aabb = AABB(Vector3(-90, -4, -90), Vector3(180, 90, 180))
	var snow_mat := StandardMaterial3D.new()
	snow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	snow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	snow_mat.albedo_color = Color(0.92, 0.96, 1.0, 0.95)
	snow_mat.emission_enabled = true
	snow_mat.emission = Color(0.6, 0.75, 1.0)
	snow_mat.emission_energy_multiplier = 1.2
	_snow_particles.material_override = snow_mat
	add_child(_snow_particles)

	_ash_particles = CPUParticles3D.new()
	_ash_particles.name = "DestroyAsh"
	_ash_particles.amount = 950
	_ash_particles.lifetime = 4.0
	_ash_particles.one_shot = false
	_ash_particles.emitting = false
	_ash_particles.direction = Vector3(0, -1, 0)
	_ash_particles.spread = 20.0
	_ash_particles.gravity = Vector3(0, -1.5, 0)
	_ash_particles.initial_velocity_min = 0.3
	_ash_particles.initial_velocity_max = 1.2
	_ash_particles.scale_amount_min = 0.06
	_ash_particles.scale_amount_max = 0.24
	_ash_particles.color = Color(0.75, 0.7, 0.62, 0.9)
	_ash_particles.visibility_aabb = AABB(Vector3(-90, -4, -90), Vector3(180, 90, 180))
	var ash_mat := StandardMaterial3D.new()
	ash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ash_mat.albedo_color = Color(0.75, 0.7, 0.62, 0.9)
	ash_mat.emission_enabled = true
	ash_mat.emission = Color(0.6, 0.55, 0.45)
	ash_mat.emission_energy_multiplier = 0.8
	_ash_particles.material_override = ash_mat
	add_child(_ash_particles)

	# 恒纪元复苏光尘：温暖的金色尘埃缓缓上浮，万物欣欣向荣
	_revival_particles = CPUParticles3D.new()
	_revival_particles.name = "RevivalMotes"
	_revival_particles.amount = 150
	_revival_particles.lifetime = 6.0
	_revival_particles.one_shot = false
	_revival_particles.emitting = false
	_revival_particles.direction = Vector3(0, 1, 0)
	_revival_particles.spread = 45.0
	_revival_particles.gravity = Vector3(0, 0.6, 0)
	_revival_particles.initial_velocity_min = 0.2
	_revival_particles.initial_velocity_max = 0.7
	_revival_particles.scale_amount_min = 0.05
	_revival_particles.scale_amount_max = 0.16
	_revival_particles.color = Color(1.0, 0.86, 0.55, 0.85)
	_revival_particles.visibility_aabb = AABB(Vector3(-90, -4, -90), Vector3(180, 90, 180))
	var revival_mat := StandardMaterial3D.new()
	revival_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	revival_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	revival_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	revival_mat.albedo_color = Color(1.0, 0.86, 0.55, 0.8)
	revival_mat.emission_enabled = true
	revival_mat.emission = Color(1.0, 0.82, 0.5)
	revival_mat.emission_energy_multiplier = 1.6
	_revival_particles.material_override = revival_mat
	add_child(_revival_particles)

## 大气特效跟随玩家/镜头：保证火气与风雪始终在身边，而不是生成在世界原点远处
func _follow_particle_anchor() -> void:
	var anchor := Vector3.ZERO
	if StoryModeManager != null and StoryModeManager.player != null \
			and is_instance_valid(StoryModeManager.player):
		anchor = StoryModeManager.player.global_position
	elif GameState.camera != null and is_instance_valid(GameState.camera):
		anchor = GameState.camera.global_position
	if _heat_particles != null:
		_heat_particles.global_position = anchor + Vector3(0, 3.0, 0)
	if _snow_particles != null:
		_snow_particles.global_position = anchor + Vector3(0, 22.0, 0)
	if _ash_particles != null:
		_ash_particles.global_position = anchor + Vector3(0, 20.0, 0)
	if _revival_particles != null:
		_revival_particles.global_position = anchor + Vector3(0, 4.0, 0)

## 按纪元状态开合大气特效（平滑地由粒子寿命自然淡出）
func _tick_weather_particles() -> void:
	var heat := 0.0
	var snow := 0.0
	var ash := 0.0
	match state:
		State.HOT:
			heat = 1.0
		State.COLD:
			snow = 1.0
		State.DESTROYED:
			ash = 1.0
			heat = 0.7
	if _triple_override_active:
		# 三日凌空窗口：飞星逼近，空气也在燃烧
		heat = maxf(heat, 0.8)
		ash = maxf(ash, 0.5)
	if _heat_particles != null:
		_heat_particles.emitting = heat > 0.05
	if _snow_particles != null:
		_snow_particles.emitting = snow > 0.05
	if _ash_particles != null:
		_ash_particles.emitting = ash > 0.05
	# 恒纪元：温暖的金色复苏光尘，欣欣向荣
	if _revival_particles != null:
		_revival_particles.emitting = state == State.STABLE

## 真实三体初始条件：等边三角形（拉格朗日构型）加随机微扰，
## 每纪随机掷出轨道尺度、微扰强度与恒星质量，让每轮轮回的动力学都不同。
func _init_three_body() -> void:
	_pos2.clear()
	_vel2.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var side := rng.randf_range(0.62, 0.85)
	var pert := rng.randf_range(0.02, 0.06)
	var radius := side / sqrt(3.0)
	for k in 3:
		var ang := float(k) * TAU / 3.0
		_pos2.append(Vector2(cos(ang), sin(ang)) * radius)
		var speed := 1.0 / sqrt(side)
		speed *= 1.0 + rng.randf_range(-pert, pert)
		_vel2.append(Vector2(-sin(ang), cos(ang)) * speed)
	_masses = [
		rng.randf_range(0.85, 1.15),
		rng.randf_range(0.85, 1.15),
		rng.randf_range(0.85, 1.15)
	]
	_kick_timer = rng.randf_range(60.0, 180.0)

## 数学之美：棋盘旁的黄金螺线 + 斐波那契同心圆（古老占星与精密几何）
func _build_ground_geometry() -> void:
	var center := Vector3(-8, 0, 6)
	var base_y := WorldManager.get_terrain_height(center.x, center.z) + 0.06
	var spiral := PackedVector3Array()
	var phi := (1.0 + sqrt(5.0)) / 2.0
	var b := log(phi) / (PI / 2.0)
	var a := 0.0
	while a <= 2.6 * TAU:
		var r := 0.8 * exp(b * a)
		if r > 13.0:
			break
		spiral.append(Vector3(center.x + cos(a) * r, base_y, center.z + sin(a) * r))
		a += 0.1
	_spawn_line_ring(spiral, Color(1.0, 0.8, 0.5, 0.55))
	for r in [2.0, 3.0, 5.0, 8.0, 13.0]:
		var ring := PackedVector3Array()
		for i in 65:
			var ang := float(i) / 64.0 * TAU
			ring.append(Vector3(center.x + cos(ang) * r, base_y, center.z + sin(ang) * r))
		_spawn_line_ring(ring, Color(1.0, 0.75, 0.4, 0.15))

func _spawn_line_ring(points: PackedVector3Array, color: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 1.3
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for p in points:
		mesh.surface_add_vertex(p)
	if points.size() > 1 and points[0] != points[points.size() - 1]:
		mesh.surface_add_vertex(points[0])
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	return mi

func _capture_base() -> void:
	_base_sky = {}
	if sky_material == null:
		return
	_base_sky["top"] = sky_material.sky_top_color
	_base_sky["horizon"] = sky_material.sky_horizon_color
	_base_sky["ground"] = sky_material.ground_bottom_color
	_base_sky["ground_horizon"] = sky_material.ground_horizon_color
	if env != null:
		_base_sky["fog"] = env.fog_light_color
		_base_sky["fog_density"] = env.fog_density
		_base_sky["ambient"] = env.ambient_light_energy

func set_state(new_state: int) -> void:
	state = new_state
	var sun_scale := 1.0
	var sun_energy := 1.0
	var sun_color := Color(1.0, 0.72, 0.42)
	var top := Color(0.32, 0.15, 0.08)
	var horizon := Color(0.82, 0.5, 0.26)
	var ground := Color(0.22, 0.12, 0.06)
	var ground_horizon := Color(0.5, 0.3, 0.16)
	var fog := Color(0.85, 0.55, 0.3)
	var fog_density := 0.004
	var ambient := 0.55
	match new_state:
		State.HOT:
			sun_scale = 2.35
			sun_energy = 2.2
			sun_color = Color(1.0, 0.26, 0.08)
			top = Color(0.55, 0.08, 0.02)
			horizon = Color(1.0, 0.36, 0.08)
			ground = Color(0.28, 0.06, 0.03)
			ground_horizon = Color(0.7, 0.18, 0.06)
			fog = Color(1.0, 0.3, 0.1)
			fog_density = 0.006
			ambient = 0.8
		State.COLD:
			sun_scale = 0.5
			sun_energy = 0.35
			sun_color = Color(0.62, 0.78, 1.0)
			top = Color(0.03, 0.05, 0.17)
			horizon = Color(0.3, 0.4, 0.62)
			ground = Color(0.06, 0.08, 0.16)
			ground_horizon = Color(0.18, 0.24, 0.4)
			fog = Color(0.42, 0.52, 0.72)
			fog_density = 0.008
			ambient = 0.4
		State.DESTROYED:
			sun_scale = 3.2
			sun_energy = 4.0
			sun_color = Color(1.0, 0.95, 0.85)
			top = Color(0.95, 0.88, 0.8)
			horizon = Color(1.0, 0.92, 0.8)
			ground = Color(0.75, 0.6, 0.45)
			ground_horizon = Color(0.9, 0.75, 0.55)
			fog = Color(1.0, 0.9, 0.75)
			fog_density = 0.012
			ambient = 1.2
	_triple_override_active = false
	_state_sun_targets.clear()
	for i in 3:
		_state_sun_targets.append({"scale": sun_scale, "energy": sun_energy, "color": sun_color})
	_state_sky_target = {
		"top": top, "horizon": horizon, "ground": ground, "ground_horizon": ground_horizon,
		"fog": fog, "fog_density": fog_density, "ambient": ambient
	}
	_sky_target = _state_sky_target.duplicate()
	_restore_state_targets()
	# 立刻应用一次，切换纪元时视觉瞬间到位（随后 _process 平滑过渡）
	_apply_targets(1.0)

## 恢复当前纪元状态的目标值（三日凌空短暂接管后还原）
func _restore_state_targets() -> void:
	# 只还原恒星目标；天空色调可能被文明专属调色板覆盖，保持不动
	_sun_targets.clear()
	for t in _state_sun_targets:
		_sun_targets.append(t.duplicate())

func apply_era(era_name: String) -> void:
	match era_name:
		"hot":
			set_state(State.HOT)
		"cold":
			set_state(State.COLD)
		"destroyed":
			set_state(State.DESTROYED)
		_:
			set_state(State.STABLE)

## 应用每个文明的专属色调（在纪元状态之上打底），并生成该文明的场景道具
func apply_era_style(era_id: String, palette: Dictionary) -> void:
	_apply_palette(palette)
	spawn_era_props(era_id)

func _apply_palette(palette: Dictionary) -> void:
	if palette.is_empty():
		return
	_sky_target = {
		"top": _palette_color(palette, "top", Color(0.32, 0.15, 0.08)),
		"horizon": _palette_color(palette, "horizon", Color(0.82, 0.5, 0.26)),
		"ground": _palette_color(palette, "ground", Color(0.22, 0.12, 0.06)),
		"ground_horizon": _palette_color(palette, "ground_horizon", Color(0.5, 0.3, 0.16)),
		"fog": _palette_color(palette, "fog", Color(0.85, 0.55, 0.3)),
		"fog_density": float(palette.get("fog_density", 0.005)),
		"ambient": float(palette.get("ambient", 0.55))
	}
	_apply_targets(1.0)

func _palette_color(palette: Dictionary, key: String, fallback: Color) -> Color:
	var arr = palette.get(key, [])
	if arr is Array and (arr as Array).size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return fallback

## 每个文明生成贴合时代氛围的低模场景道具（沿剧情路径/目标节点分布）
func spawn_era_props(era_id: String) -> void:
	if _props_spawned:
		return
	_props_spawned = true
	var glow := Color(1.0, 0.7, 0.35)
	var center := Vector3(-6, 0, 6)
	match era_id:
		"era_wenwang":
			# 周文王纪：荒漠遗迹 + 生命游戏棋盘（宇宙之算）+ 东行木杆路标
			glow = Color(1.0, 0.7, 0.35)
			center = Vector3(-8, 0, 6)
			_spawn_pyramid(Vector3(46, 0, -38), 9.0, 7.0)
			_spawn_pyramid(Vector3(58, 0, -30), 6.0, 4.5)
			spawn_game_board(Vector3(-8, 0, 6), 13)
			_spawn_wood_pole(Vector3(14, 0, -18), 3.4)
			_spawn_wood_pole(Vector3(24, 0, -32), 3.4)
			_spawn_light_pillar(Vector3(14, 0, -18), glow)
		"era_mozi":
			# 墨子纪：青铜齿轮塔 + 中央浑天宇宙仪
			glow = Color(0.95, 0.65, 0.25)
			center = Vector3(0, 0, 10)
			_spawn_gear_tower(Vector3(0, 0, 10))
			_spawn_gear_tower(Vector3(-12, 0, 14))
			_spawn_gear_tower(Vector3(6, 0, 18))
			_spawn_armillary(Vector3(0, 0, 10))
			_spawn_light_pillar(Vector3(-12, 0, 14), glow)
		"era_qinshihuang":
			# 秦始皇纪：黑甲旗帜阵列 + 指挥塔
			glow = Color(1.0, 0.3, 0.2)
			center = Vector3(16, 0, -10)
			_spawn_banner(Vector3(10, 0, -6), Color(0.14, 0.11, 0.16))
			_spawn_banner(Vector3(16, 0, -10), Color(0.14, 0.11, 0.16))
			_spawn_banner(Vector3(22, 0, -4), Color(0.14, 0.11, 0.16))
			_spawn_banner(Vector3(18, 0, -16), Color(0.55, 0.08, 0.06))
			_spawn_command_tower(Vector3(10, 0, -6))
			_spawn_command_tower(Vector3(22, 0, -4))
			_spawn_light_pillar(Vector3(18, 0, -16), glow)
		"era_newton":
			# 牛顿纪：天文台穹顶 + 机械钟楼 + 轨道环模型
			glow = Color(0.45, 0.8, 1.0)
			center = Vector3(-14, 0, -14)
			_spawn_observatory(Vector3(-6, 0, -10))
			_spawn_clock_tower(Vector3(-14, 0, -14))
			_spawn_clock_tower(Vector3(-20, 0, -4))
			_spawn_orbit_rings(Vector3(-6, 0, -10))
			_spawn_light_pillar(Vector3(-20, 0, -4), glow)
		"era_einstein":
			# 爱因斯坦纪：墓碑双碑（正面/背面）+ 石碑之林
			glow = Color(1.0, 0.85, 0.45)
			center = Vector3(-44, 0, 36)
			_spawn_tablet(Vector3(-44, 0, 36), "文明在此轮回\n知识刻于石上")
			_spawn_tablet(Vector3(-40, 0, 40), "三日凌空\n文明终将重来")
			_spawn_obelisk(Vector3(-50, 0, 30))
			_spawn_obelisk(Vector3(-38, 0, 44))
			_spawn_obelisk(Vector3(-46, 0, 42))
			_spawn_light_pillar(Vector3(-44, 0, 36), glow)
	spawn_ambient_motes(center, glow)
	_spawn_math_visuals(era_id)
	spawn_starfield()

## 高等数学 × 物理学之美：每个文明专属的科学奇观（五纪五物，互不复用）
func _spawn_math_visuals(era_id: String) -> void:
	match era_id:
		"era_wenwang":
			_spawn_kepler_dial()
		"era_mozi":
			_spawn_fourier_epicycle()
		"era_qinshihuang":
			_spawn_bifurcation_tree()
		"era_newton":
			_spawn_orbit_ribbons()
		"era_einstein":
			_spawn_spacetime_grid()

## 周文王纪：开普勒等面积日晷——以行星为原点实时记录三太阳的极坐标轨道
func _spawn_kepler_dial() -> void:
	var dial := KeplerDial.new()
	dial.name = "KeplerDial"
	dial.setup(self, Vector3(24, 0, 2))
	add_child(dial)

## 墨子纪：傅里叶本轮齿轮仪——嵌套齿轮用旋转叠加画出玫瑰
func _spawn_fourier_epicycle() -> void:
	var epi := FourierEpicycle.new()
	epi.name = "FourierEpicycle"
	epi.setup(Vector3(14, 0, 4))
	add_child(epi)

## 冯·诺伊曼纪：Logistic 分岔之树——周期加倍通向混沌的谱系
func _spawn_bifurcation_tree() -> void:
	var tree := BifurcationTree.new()
	tree.name = "BifurcationTree"
	tree.setup(Vector3(4, 0, 10), Vector3(0, 0, -1))
	add_child(tree)

## 牛顿纪：三体轨道丝带 + 庞加莱截面——把真实轨道搬进太阳系仪
func _spawn_orbit_ribbons() -> void:
	var orbit := OrbitRibbons.new()
	orbit.name = "OrbitRibbons"
	orbit.setup(self, Vector3(-2, 0, -16))
	add_child(orbit)

## 爱因斯坦纪：时空曲率织锦——引力井把光弯成围绕质量的光环
func _spawn_spacetime_grid() -> void:
	var grid := SpacetimeGrid.new()
	grid.name = "SpacetimeGrid"
	grid.setup(Vector3(-38, 0, 30))
	add_child(grid)

## 古老文明 × 科技：石柱 + 发光符文带 + 冲天光柱
func _spawn_light_pillar(pos: Vector3, glow: Color) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.68
	cyl.height = 4.5
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.45, 0.42, 0.38)
	cmat.roughness = 0.9
	cyl.material = cmat
	col.mesh = cyl
	col.position = Vector3(0, 2.25, 0)
	root.add_child(col)
	var band := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.5
	bcyl.bottom_radius = 0.72
	bcyl.height = 0.5
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.emission_enabled = true
	bmat.emission = glow
	bmat.emission_energy_multiplier = 2.4
	bcyl.material = bmat
	band.mesh = bcyl
	band.position = Vector3(0, 2.0, 0)
	root.add_child(band)
	var beam := MeshInstance3D.new()
	var bmesh := CylinderMesh.new()
	bmesh.top_radius = 0.16
	bmesh.bottom_radius = 0.5
	bmesh.height = 9.0
	var bmat2 := StandardMaterial3D.new()
	bmat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat2.albedo_color = Color(glow.r, glow.g, glow.b, 0.16)
	bmat2.emission_enabled = true
	bmat2.emission = glow
	bmat2.emission_energy_multiplier = 1.4
	bmesh.material = bmat2
	beam.mesh = bmesh
	beam.position = Vector3(0, 7.2, 0)
	root.add_child(beam)

## 氛围光尘：随纪元配色的漂浮粒子（古老又带着全息感）
func spawn_ambient_motes(center: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.position = center + Vector3(0, 4.0, 0)
	p.emitting = true
	p.amount = 70
	p.lifetime = 7.0
	p.spread = 60.0
	p.gravity = Vector3(0, -0.12, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.0
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.15
	p.color = Color(color.r, color.g, color.b, 0.75)
	p.visibility_aabb = AABB(Vector3(-40, -8, -40), Vector3(80, 40, 80))
	add_child(p)

## 玄奥背景：高处的星尘/微光粒子场
func spawn_starfield() -> void:
	var p := CPUParticles3D.new()
	p.position = Vector3(0, 55, 0)
	p.emitting = true
	p.amount = 240
	p.lifetime = 14.0
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 1.4
	p.scale_amount_min = 0.35
	p.scale_amount_max = 1.5
	p.color = Color(0.92, 0.96, 1.0, 0.7)
	p.visibility_aabb = AABB(Vector3(-320, -140, -320), Vector3(640, 280, 640))
	add_child(p)

func _spawn_wood_pole(pos: Vector3, h: float) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.22
	cyl.height = h
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.32, 0.2)
	mat.roughness = 0.95
	cyl.material = mat
	m.mesh = cyl
	m.position = pos + Vector3(0, h / 2.0, 0)
	add_child(m)

func _spawn_gear_tower(pos: Vector3) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 1.0
	cyl.height = 4.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.38, 0.18)
	mat.roughness = 0.9
	cyl.material = mat
	pillar.mesh = cyl
	pillar.position = Vector3(0, 2.0, 0)
	root.add_child(pillar)
	for i in 2:
		var gear := MeshInstance3D.new()
		var gcyl := CylinderMesh.new()
		gcyl.top_radius = 1.3
		gcyl.bottom_radius = 1.3
		gcyl.height = 0.28
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(0.75, 0.55, 0.22)
		gmat.roughness = 0.6
		gcyl.material = gmat
		gear.mesh = gcyl
		gear.position = Vector3(0, 3.1 + i * 0.5, 0)
		root.add_child(gear)

func _spawn_banner(pos: Vector3, cloth_color: Color) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.1
	cyl.height = 5.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.16, 0.2)
	cyl.material = mat
	pole.mesh = cyl
	pole.position = Vector3(0, 2.5, 0)
	root.add_child(pole)
	var cloth := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 1.4, 0.8)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = cloth_color
	box.material = cmat
	cloth.mesh = box
	cloth.position = Vector3(0, 4.2, 0.45)
	root.add_child(cloth)

func _spawn_observatory(pos: Vector3) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var base := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 1.6
	bcyl.bottom_radius = 1.9
	bcyl.height = 2.2
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.72, 0.74, 0.82)
	bcyl.material = bmat
	base.mesh = bcyl
	base.position = Vector3(0, 1.1, 0)
	root.add_child(base)
	var dome := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.5
	sph.height = 1.5
	sph.is_hemisphere = true
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.55, 0.6, 0.72)
	dome.mesh = sph
	dome.position = Vector3(0, 2.5, 0)
	root.add_child(dome)

func _spawn_clock_tower(pos: Vector3) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 5.2, 1.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.55, 0.66)
	body.mesh = box
	body.position = Vector3(0, 2.6, 0)
	root.add_child(body)
	var face := MeshInstance3D.new()
	var fcyl := CylinderMesh.new()
	fcyl.top_radius = 0.42
	fcyl.bottom_radius = 0.42
	fcyl.height = 0.12
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.emission_enabled = true
	fmat.emission = Color(0.9, 0.85, 0.6)
	fmat.emission_energy_multiplier = 1.5
	fcyl.material = fmat
	face.mesh = fcyl
	face.position = Vector3(0, 4.4, 0.56)
	root.add_child(face)

## 墨子纪：青铜浑天宇宙仪（球体 + 双环）
func _spawn_armillary(pos: Vector3) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var base := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 1.5
	bcyl.bottom_radius = 1.8
	bcyl.height = 0.8
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.5, 0.36, 0.16)
	bcyl.material = bmat
	base.mesh = bcyl
	base.position = Vector3(0, 0.4, 0)
	root.add_child(base)
	var sphere := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.15
	sph.height = 2.3
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.78, 0.58, 0.22)
	smat.roughness = 0.5
	sph.material = smat
	sphere.mesh = sph
	sphere.position = Vector3(0, 1.9, 0)
	root.add_child(sphere)
	for i in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.55
		torus.outer_radius = 1.75
		torus.rings = 3
		torus.ring_segments = 48
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.85, 0.68, 0.3)
		rmat.roughness = 0.45
		torus.material = rmat
		ring.mesh = torus
		ring.position = Vector3(0, 1.9, 0)
		ring.rotation = Vector3(0, 0, i * PI / 2.0) if i == 0 else Vector3(PI / 2.2, 0.5, 0)
		root.add_child(ring)

## 秦始皇纪：黑甲指挥塔（立柱 + 顶台 + 红光）
func _spawn_command_tower(pos: Vector3) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var column := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.7
	cyl.height = 6.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.11, 0.16)
	mat.roughness = 0.85
	cyl.material = mat
	column.mesh = cyl
	column.position = Vector3(0, 3.0, 0)
	root.add_child(column)
	var top := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 0.3, 1.8)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.2, 0.16, 0.22)
	box.material = tmat
	top.mesh = box
	top.position = Vector3(0, 6.1, 0)
	root.add_child(top)
	var glow := MeshInstance3D.new()
	var gcyl := CylinderMesh.new()
	gcyl.top_radius = 0.18
	gcyl.bottom_radius = 0.18
	gcyl.height = 0.5
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.emission_enabled = true
	gmat.emission = Color(1.0, 0.22, 0.16)
	gmat.emission_energy_multiplier = 2.5
	gcyl.material = gmat
	glow.mesh = gcyl
	glow.position = Vector3(0, 6.35, 0)
	root.add_child(glow)

## 牛顿纪：轨道环模型（三体轨道示意）
func _spawn_orbit_rings(pos: Vector3) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var root := Node3D.new()
	root.position = pos + Vector3(0, 0.2, 0)
	add_child(root)
	for i in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.4 + i * 0.45
		torus.outer_radius = torus.inner_radius + 0.12
		torus.rings = 3
		torus.ring_segments = 48
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.55, 0.72, 0.95)
		rmat.emission_enabled = true
		rmat.emission = Color(0.3, 0.5, 0.85)
		rmat.emission_energy_multiplier = 0.8
		torus.material = rmat
		ring.mesh = torus
		ring.rotation = Vector3(
			PI / 2.0 + i * 0.35,
			i * 0.9,
			0.15 + i * 0.25
		)
		root.add_child(ring)

func nearest_sun_position() -> Vector3:
	## 返回最接近天顶（视觉上“当头/逼近”）的太阳位置，供过场镜头指向天空
	var best := Vector3(0, 80, 0)
	var best_elev := -INF
	for sun in _suns:
		if sun == null or not is_instance_valid(sun):
			continue
		var elev := sun.global_position.y
		if elev > best_elev:
			best_elev = elev
			best = sun.global_position
	return best

# ---------- 轨道读取 API（供各纪元的数学/物理可视化节点取用） ----------

## 当前三颗恒星的抽象轨道坐标（原点即行星），只读拷贝
func get_orbit_positions() -> Array[Vector2]:
	return _pos2.duplicate()

func get_world_rot() -> float:
	return _world_rot

func get_masses() -> Array:
	return _masses.duplicate()

## 最近（对行星威胁最大）的恒星下标
func get_nearest_sun_index() -> int:
	var best := -1
	var best_r := INF
	for i in 3:
		var r := _pos2[i].length()
		if r < best_r:
			best_r = r
			best = i
	return best

## 把抽象轨道坐标映射到世界空间：与天空方向的旋转/倾斜完全一致（同一套天球变换），
## 但保留径向距离并按 scale 缩放——供“太阳系仪”把真实轨道搬进地面模型。
func orbit_to_world(p: Vector2, scale: float) -> Vector3:
	var d := Vector3(p.x, p.y * _tilt_cos, p.y * _tilt_sin)
	var c := cos(_world_rot)
	var s := sin(_world_rot)
	return Vector3(d.x * c + d.z * s, d.y, -d.x * s + d.z * c) * scale

## 依据三体模拟的真实日位判定天象：
## 三颗太阳同时当空 = 三日凌空（毁灭），两颗 = 双日凌空（乱纪元前兆）。
func current_conjunction() -> String:
	if _up_indices.size() >= 3:
		return "triple"
	if _up_indices.size() == 2:
		return "binary"
	return ""

## 当前同时当空的太阳数量（供 AI 剧情生成读取天象）
func visible_sun_count() -> int:
	return _up_indices.size()

## 天象势态：严格由“当空飞星”的数量与距离决定，还原原著——
## 三日凌空（三颗当空）= 毁灭；双日凌空（两颗当空）= 酷热；
## 飞星尽没且全部远去 = 严寒；单日（一颗当空）再按距离分恒纪元/逼近；
## 0 颗当空但飞星仍在近处 = 普通夜晚（night，不构成纪元信号）。
func era_tendency() -> String:
	var count := _up_indices.size()
	if count >= 3:
		return "destroy"  # 三日凌空
	if count == 2:
		return "hot"  # 双日凌空
	if count == 1:
		var near := _pos2[_up_indices[0]].length()
		if near < THERMAL_HOT_R:
			return "hot"  # 单日逼近
		return "stable"  # 恒纪元
	# 0 颗当空：全部飞星都远去 → 严寒；否则只是普通夜晚
	var near_any := INF
	for i in 3:
		near_any = minf(near_any, _pos2[i].length())
	return "cold" if near_any > THERMAL_COLD_R else "night"

## 天地异象铺垫：短暂增强太阳光辉，提示“太阳们正在聚拢”
func pulse_suns(strength := 1.4, duration := 1.5) -> void:
	_pulse = maxf(_pulse, strength)
	_pulse_duration = maxf(duration, 0.2)

func _process(delta: float) -> void:
	_t += delta
	_world_rot = fmod(_world_rot + WORLD_SPIN * delta, TAU)
	_advance_sim(SIM_SPEED * delta)
	_kick_timer -= delta
	if _kick_timer <= 0.0:
		_apply_random_kick()
		_kick_timer = randf_range(120.0, 300.0)
	_update_visibility()
	var triple_window := _up_indices.size() >= 3
	_apply_triple_override(triple_window)
	for i in 3:
		var pos := _sky_direction(i) * SKY_RADIUS
		_suns[i].global_position = pos
		_sun_lights[i].global_position = pos
		if pos.length_squared() > 0.01:
			_sun_lights[i].look_at(Vector3.ZERO, Vector3.UP)
		# 太阳尾迹：保留近期轨迹，构成流动的轨道弧线
		var trail: Array = _trail_points[i]
		trail.append(pos)
		if trail.size() > TRAIL_POINTS:
			trail.pop_front()
		_update_trail_mesh(i, trail)
		# 可见性完全由物理位置决定：地平线之上才显示，升起/落下时平滑淡入淡出；
		# 远近只影响大小与亮度，不再按纪元状态硬性裁剪，轨道轨迹连续不跳变
		var want: bool = _above[i]
		_sun_fade[i] = move_toward(_sun_fade[i], 1.0 if want else 0.0, SUN_FADE_SPEED * delta)
		_suns[i].visible = _sun_fade[i] > 0.01
		_trail_meshes[i].visible = _suns[i].visible
	_apply_targets(clampf(delta * 2.5, 0.0, 1.0))
	_tick_weather_particles()
	_follow_particle_anchor()
	if _lorenz != null:
		var chaos := 0.0
		match state:
			State.HOT:
				chaos = 0.55
			State.COLD:
				chaos = 0.35
			State.DESTROYED:
				chaos = 1.0
		if _triple_override_active:
			chaos = maxf(chaos, 0.8)
		_lorenz.boost(chaos)
	if auto_era:
		_tick_auto_era(delta)
	if _pulse > 0.0:
		for i in 3:
			_sun_lights[i].light_energy += _pulse * 1.5
			_sun_mats[i].emission_energy_multiplier += _pulse * 1.5
		_pulse = maxf(0.0, _pulse - delta / maxf(_pulse_duration, 0.1))
		_tick_board_timer(delta)

## 自由模拟：天象趋势持续达到阈值后切换纪元状态——只改光影与粒子，不播放任何过场
func _tick_auto_era(delta: float) -> void:
	var tendency := era_tendency()
	if tendency != _auto_tendency:
		_auto_tendency = tendency
		_auto_accum = 0.0
	else:
		_auto_accum += delta
	if _auto_accum < AUTO_ERA_HOLD:
		return
	_auto_accum = 0.0
	match tendency:
		"hot":
			apply_era("hot")
		"cold":
			apply_era("cold")
		"destroy":
			apply_era("destroyed")
		"stable":
			apply_era("stable")
		_:
			pass  # night：普通夜晚，保持当前纪元

## 随机“天外扰动”：不定期给某颗恒星一个随机速度脉冲，
## 让三体轨道长期运行也不会落入可预测的固定周期。
func _apply_random_kick() -> void:
	var i := randi() % 3
	var ang := randf() * TAU
	var power := randf_range(0.04, 0.14)
	_vel2[i] += Vector2(cos(ang), sin(ang)) * power

## 三日凌空接管：三颗太阳同时当空时短暂呈现毁灭态（白热、巨大），
## 窗口结束后还原当前纪元的视觉目标。
func _apply_triple_override(active: bool) -> void:
	var want := active and state != State.DESTROYED
	if want == _triple_override_active:
		return
	_triple_override_active = want
	if want:
		_sun_targets = [
			{"scale": 2.6, "energy": 3.2, "color": Color(1.0, 0.95, 0.85)},
			{"scale": 2.6, "energy": 3.2, "color": Color(1.0, 0.95, 0.85)},
			{"scale": 2.6, "energy": 3.2, "color": Color(1.0, 0.95, 0.85)}
		]
	else:
		_restore_state_targets()

# ---------- 三体引力模拟 ----------

func _advance_sim(time: float) -> void:
	var remaining := time
	while remaining > 0.0:
		var dt := minf(SIM_DT, remaining)
		_verlet_step(dt)
		remaining -= dt

## Velocity-Verlet：近辛积分，长时间运行能量漂移可忽略
func _verlet_step(dt: float) -> void:
	var a0 := _accelerations()
	for i in 3:
		_pos2[i] = _pos2[i] + _vel2[i] * dt + 0.5 * a0[i] * dt * dt
	var a1 := _accelerations()
	for i in 3:
		_vel2[i] = _vel2[i] + 0.5 * (a0[i] + a1[i]) * dt

func _accelerations() -> Array[Vector2]:
	var accs: Array[Vector2] = []
	for i in 3:
		var a := Vector2.ZERO
		for j in 3:
			if j == i:
				continue
			var d: Vector2 = _pos2[j] - _pos2[i]
			var r2 := d.length_squared() + SOFTENING * SOFTENING
			a += d * (GRAV_G * _masses[j] / (r2 * sqrt(r2)))
		# 软性约束：防止混沌解把恒星永久甩出视野范围
		var r := _pos2[i].length()
		if r > CONTAIN_RADIUS:
			a -= _pos2[i] / r * (CONTAIN_STRENGTH * (r - CONTAIN_RADIUS))
		elif r < PLANET_GUARD_RADIUS:
			# 行星守护：越贴近行星推力越强，柔和地把掠过的恒星推开
			a += _pos2[i] / r * (PLANET_GUARD_STRENGTH * (PLANET_GUARD_RADIUS - r))
		accs.append(a)
	return accs

# ---------- 天空映射与可见性 ----------

## 恒星在天球上的方向：三体轨道平面倾斜 + 行星自转，产生升起/落下
func _sky_direction(i: int) -> Vector3:
	var p: Vector2 = _pos2[i]
	if p.length_squared() < 0.0001:
		# 恒星恰好掠过行星正上方：沿用上一帧方向，避免天球上的瞬跳
		return _last_dir[i]
	var d := Vector3(p.x, p.y * _tilt_cos, p.y * _tilt_sin).normalized()
	var c := cos(_world_rot)
	var s := sin(_world_rot)
	var dir := Vector3(d.x * c + d.z * s, d.y, -d.x * s + d.z * c)
	_last_dir[i] = dir
	return dir

func _elevation(i: int) -> float:
	return _sky_direction(i).y * SKY_RADIUS

## 更新每颗恒星是否当空（带迟滞），并按高度排序
func _update_visibility() -> void:
	_up_indices.clear()
	for i in 3:
		var elev := _elevation(i)
		if elev > HORIZON_BAND:
			_above[i] = true
		elif elev < -HORIZON_BAND:
			_above[i] = false
		var r := _pos2[i].length()
		if r < PROMINENT_RADIUS:
			_near[i] = true
		elif r > PROMINENT_RADIUS + PROMINENT_BAND:
			_near[i] = false
		# 当空飞星 = 地平线之上 且 离行星足够近（远去的恒星隐入星空）
		if _above[i] and _near[i]:
			_up_indices.append(i)
	_up_indices.sort_custom(func(a: int, b: int) -> bool: return _elevation(a) > _elevation(b))

## 恒星距离因子：离行星越近看起来越大越亮（酷热），越远越小越暗（严寒）
func _distance_factor(i: int) -> float:
	var r := _pos2[i].length()
	return clampf(0.9 / maxf(r, 0.3), 0.35, 2.0)

func _update_trail_mesh(index: int, points: Array) -> void:
	if _trail_meshes.size() <= index:
		return
	var mesh: ImmediateMesh = _trail_meshes[index].mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _trail_material)
	for p in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()

func _apply_targets(rate: float) -> void:
	if _sun_targets.is_empty() or _sky_target.is_empty():
		return
	for i in _sun_targets.size():
		var target: Dictionary = _sun_targets[i]
		var mat: StandardMaterial3D = _sun_mats[i]
		var show: bool = _suns[i].visible
		var fade: float = _sun_fade[i] if i < _sun_fade.size() else 1.0
		var df := _distance_factor(i)
		var target_scale: float = (float(target.get("scale", 1.0)) * df * fade) if show else 0.01
		var cur_scale := _suns[i].scale.x
		_suns[i].scale = Vector3.ONE * lerpf(cur_scale, target_scale, rate)
		# 光感变动：乱纪元光线缓慢“呼吸”，毁灭时剧烈闪烁
		var breathe := 1.0
		if state == State.HOT or state == State.COLD:
			breathe = 1.0 + sin(_t * 2.2) * 0.08
		elif state == State.DESTROYED:
			breathe = 1.0 + (randf() - 0.5) * 0.4
		var target_energy: float = (float(target.get("energy", 1.0)) * df * breathe * fade) if show else 0.0
		mat.emission_energy_multiplier = lerpf(mat.emission_energy_multiplier, target_energy, rate)
		mat.emission = mat.emission.lerp(target.get("color", Color(1, 0.7, 0.4)), rate)
		mat.albedo_color.a = lerpf(mat.albedo_color.a, clampf(fade, 0.0, 1.0), rate)
		_sun_lights[i].light_energy = lerpf(_sun_lights[i].light_energy, target_energy, rate)
		_sun_lights[i].light_color = _sun_lights[i].light_color.lerp(target.get("color", Color.WHITE), rate)
	if sky_material != null:
		sky_material.sky_top_color = sky_material.sky_top_color.lerp(_sky_target.get("top", Color.BLACK), rate)
		sky_material.sky_horizon_color = sky_material.sky_horizon_color.lerp(_sky_target.get("horizon", Color.BLACK), rate)
		sky_material.ground_bottom_color = sky_material.ground_bottom_color.lerp(_sky_target.get("ground", Color.BLACK), rate)
		sky_material.ground_horizon_color = sky_material.ground_horizon_color.lerp(_sky_target.get("ground_horizon", Color.BLACK), rate)
	if env != null:
		env.fog_light_color = env.fog_light_color.lerp(_sky_target.get("fog", Color.WHITE), rate)
		env.fog_density = lerpf(env.fog_density, float(_sky_target.get("fog_density", 0.005)), rate)
		env.ambient_light_energy = lerpf(env.ambient_light_energy, float(_sky_target.get("ambient", 0.55)), rate)

# ---------- 遗迹：巨石碑与金字塔（各纪元专属，见 spawn_era_props） ----------

func _spawn_pyramid(pos: Vector3, base: float, height: float) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var layers := 5
	for i in layers:
		var shrink := 1.0 - float(i) * 0.17
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(base * shrink, height / float(layers), base * shrink)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.58, 0.38).darkened(float(i) * 0.07)
		mat.roughness = 0.95
		box.material = mat
		m.mesh = box
		m.position = Vector3(0, float(i) * (height / float(layers)) + height / float(layers) / 2.0, 0)
		root.add_child(m)

func _spawn_tablet(pos: Vector3, text: String) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.6, 4.2, 0.8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.42)
	mat.roughness = 0.9
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.1, 0.06)
	mat.emission_energy_multiplier = 0.4
	box.material = mat
	m.mesh = box
	m.position = pos + Vector3(0, 2.1, 0)
	add_child(m)
	var label := Label3D.new()
	label.text = text
	label.font_size = 90
	label.outline_size = 12
	label.modulate = Color(1.0, 0.9, 0.72)
	label.position = pos + Vector3(0, 2.1, 0.48)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.0045
	add_child(label)

func _spawn_obelisk(pos: Vector3) -> void:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 5.5, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.4, 0.33)
	mat.roughness = 0.95
	box.material = mat
	m.mesh = box
	m.position = pos + Vector3(0, 2.75, 0)
	add_child(m)

# ---------- 生命游戏棋盘（周文王的“宇宙之算”） ----------

func spawn_game_board(center: Vector3, size := 13) -> void:
	_board_size = size
	_board_cells.clear()
	_board_mats.clear()
	_board_state.clear()
	var root := Node3D.new()
	root.name = "LifeBoard"
	add_child(root)
	var base_y := WorldManager.get_terrain_height(center.x, center.z) + 0.12
	for y in size:
		for x in size:
			var cell := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.4, 0.1, 0.4)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.emission_enabled = true
			mat.albedo_color = Color(0.08, 0.09, 0.12)
			mat.emission = Color(0.04, 0.06, 0.09)
			mat.emission_energy_multiplier = 0.5
			box.material = mat
			cell.mesh = box
			var px := center.x + (float(x) - float(size - 1) / 2.0) * 0.55
			var pz := center.z + (float(y) - float(size - 1) / 2.0) * 0.55
			cell.position = Vector3(px, base_y + sin(float(x) * 1.7 + float(y) * 2.3) * 0.015, pz)
			root.add_child(cell)
			_board_cells.append(cell)
			_board_mats.append(mat)
			_board_state.append(randf() < 0.34)
	_apply_board()

# ---------- 目标灯塔：关键节点的三维指引 ----------

func spawn_beacon(pos: Vector3, label_text: String, beacon_color := Color(0.3, 0.9, 1.0), style := "pillar") -> Node3D:
	pos.y = WorldManager.get_terrain_height(pos.x, pos.z)
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	match style:
		"crystal":
			_build_crystal_beacon(root, beacon_color)
		"orb":
			_build_orb_beacon(root, beacon_color)
		"rune":
			_build_rune_beacon(root, beacon_color)
		_:
			_build_pillar_beacon(root, beacon_color)
	var label := Label3D.new()
	label.text = label_text
	label.font_size = 90
	label.outline_size = 12
	label.modulate = beacon_color.lightened(0.35)
	label.position = Vector3(0, 8.4, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	root.add_child(label)
	return root

func _beacon_glow_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.2
	return m

func _beacon_beam_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, 0.14)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	return m

func _beacon_base_disc(root: Node3D, color: Color) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.25
	cyl.height = 0.28
	cyl.radial_segments = 18
	disc.mesh = cyl
	disc.position = Vector3(0, 0.12, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.22, 0.26)
	mat.roughness = 0.85
	disc.material_override = mat
	root.add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.95
	torus.outer_radius = 0.98
	torus.rings = 20
	torus.ring_segments = 8
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = Vector3(0, 0.3, 0)
	ring.material_override = _beacon_glow_mat(color)
	root.add_child(ring)

func _build_pillar_beacon(root: Node3D, color: Color) -> void:
	_beacon_base_disc(root, color)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.42
	cyl.height = 7.0
	cyl.radial_segments = 12
	beam.mesh = cyl
	beam.position = Vector3(0, 3.5, 0)
	beam.material_override = _beacon_beam_mat(color)
	root.add_child(beam)
	var core := MeshInstance3D.new()
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 0.3
	crystal.height = 1.4
	crystal.radial_segments = 6
	core.mesh = crystal
	core.position = Vector3(0, 1.0, 0)
	core.material_override = _beacon_glow_mat(color)
	root.add_child(core)

func _build_crystal_beacon(root: Node3D, color: Color) -> void:
	_beacon_base_disc(root, color)
	for i in 3:
		var shard := MeshInstance3D.new()
		var crystal := CylinderMesh.new()
		crystal.top_radius = 0.0
		crystal.bottom_radius = 0.3
		crystal.height = 2.0 + (i % 2) * 0.9
		crystal.radial_segments = 5
		shard.mesh = crystal
		var ang := TAU / 3.0 * i
		shard.position = Vector3(cos(ang) * 0.5, 1.1 + (i % 2) * 0.35, sin(ang) * 0.5)
		shard.rotation_degrees = Vector3(randf_range(-8, 8), randf() * 360, randf_range(-8, 8))
		shard.material_override = _beacon_glow_mat(color)
		root.add_child(shard)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.3
	cyl.height = 5.0
	cyl.radial_segments = 10
	beam.mesh = cyl
	beam.position = Vector3(0, 2.6, 0)
	beam.material_override = _beacon_beam_mat(color)
	root.add_child(beam)

func _build_orb_beacon(root: Node3D, color: Color) -> void:
	_beacon_base_disc(root, color)
	var orb := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.42
	sph.height = 0.84
	sph.radial_segments = 12
	sph.rings = 7
	orb.mesh = sph
	orb.position = Vector3(0, 2.8, 0)
	orb.material_override = _beacon_glow_mat(color)
	root.add_child(orb)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.3
	cyl.height = 5.4
	cyl.radial_segments = 10
	beam.mesh = cyl
	beam.position = Vector3(0, 2.7, 0)
	beam.material_override = _beacon_beam_mat(color)
	root.add_child(beam)
	for i in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.85
		torus.outer_radius = 0.88
		torus.rings = 20
		torus.ring_segments = 8
		ring.mesh = torus
		ring.position = Vector3(0, 2.8, 0)
		ring.rotation_degrees = Vector3(90, 0, 60.0 * i)
		ring.material_override = _beacon_beam_mat(color)
		root.add_child(ring)
	_add_beacon_particles(root, color)

func _build_rune_beacon(root: Node3D, color: Color) -> void:
	_beacon_base_disc(root, color)
	var stele := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 3.0, 0.5)
	stele.mesh = box
	stele.position = Vector3(0, 1.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.35)
	mat.roughness = 0.85
	stele.material_override = mat
	root.add_child(stele)
	var rune := MeshInstance3D.new()
	var rune_box := BoxMesh.new()
	rune_box.size = Vector3(0.6, 1.4, 0.1)
	rune.mesh = rune_box
	rune.position = Vector3(0, 1.7, 0.28)
	rune.material_override = _beacon_glow_mat(color)
	root.add_child(rune)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.3
	cyl.height = 6.0
	cyl.radial_segments = 10
	beam.mesh = cyl
	beam.position = Vector3(0, 3.2, 0)
	beam.material_override = _beacon_beam_mat(color)
	root.add_child(beam)
	_add_beacon_particles(root, color)

func _add_beacon_particles(root: Node3D, color: Color) -> void:
	var ps := CPUParticles3D.new()
	ps.amount = 12
	ps.lifetime = 2.6
	ps.one_shot = false
	ps.emitting = true
	ps.direction = Vector3(0, 1, 0)
	ps.spread = 45.0
	ps.gravity = Vector3.ZERO
	ps.initial_velocity_min = 0.2
	ps.initial_velocity_max = 0.5
	ps.scale_amount_min = 0.05
	ps.scale_amount_max = 0.12
	ps.position = Vector3(0, 1.2, 0)
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.0))
	grad.set_color(0.5, Color(color.r, color.g, color.b, 0.85))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	ps.color_ramp = grad
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.emission_enabled = true
	pm.emission = color
	ps.material_override = pm
	root.add_child(ps)

func _tick_board_timer(delta: float) -> void:
	if _board_cells.is_empty():
		return
	_board_timer -= delta
	if _board_timer <= 0.0:
		_board_timer = 1.1
		_step_life()
		_apply_board()

func _step_life() -> void:
	var n := _board_size
	var next: Array = []
	next.resize(n * n)
	for y in n:
		for x in n:
			var idx := y * n + x
			var live := _count_life_neighbors(x, y)
			var alive: bool = _board_state[idx]
			next[idx] = (alive and (live == 2 or live == 3)) or (not alive and live == 3)
	_board_state = next

func _count_life_neighbors(x: int, y: int) -> int:
	var count := 0
	for dy in 3:
		for dx in 3:
			if dx == 1 and dy == 1:
				continue
			var nx := wrapi(x + dx - 1, 0, _board_size)
			var ny := wrapi(y + dy - 1, 0, _board_size)
			if _board_state[ny * _board_size + nx]:
				count += 1
	return count

func _apply_board() -> void:
	for i in _board_cells.size():
		var alive: bool = _board_state[i]
		var mat: StandardMaterial3D = _board_mats[i]
		if alive:
			mat.albedo_color = Color(0.8, 1.0, 0.92)
			mat.emission = Color(0.35, 0.9, 0.7)
			mat.emission_energy_multiplier = 2.2
		else:
			mat.albedo_color = Color(0.08, 0.09, 0.12)
			mat.emission = Color(0.04, 0.06, 0.09)
			mat.emission_energy_multiplier = 0.5

func _exit_tree() -> void:
	# 离开剧情世界时还原天空，避免影响后续场景
	if sky_material == null or _base_sky.is_empty():
		return
	sky_material.sky_top_color = _base_sky.get("top", Color.BLACK)
	sky_material.sky_horizon_color = _base_sky.get("horizon", Color.BLACK)
	sky_material.ground_bottom_color = _base_sky.get("ground", Color.BLACK)
	sky_material.ground_horizon_color = _base_sky.get("ground_horizon", Color.BLACK)
	if env != null:
		env.fog_light_color = _base_sky.get("fog", Color.WHITE)
		env.fog_density = float(_base_sky.get("fog_density", 0.005))
		env.ambient_light_energy = float(_base_sky.get("ambient", 0.55))
