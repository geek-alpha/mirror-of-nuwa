class_name AICharacter
extends CharacterBody3D
## AI角色主体：位于场景中的硅灵。处理移动、状态消耗、动作计时、对话气泡与外观。
## 外观支持两种方式：
##   ① 导入的 .glb/.gltf 骨骼模型（含 Skeleton3D 骨骼与 AnimationPlayer 动画）；
##   ② 程序化骨骼角色（Skeleton3D + BoneAttachment3D 部件绑定，逐帧骨骼动画）。
## 决策由子节点 AIController 驱动；执行由 ActionExecutor 完成。

signal spoke(character: AICharacter, text: String)
signal action_completed(character: AICharacter)
signal died(character: AICharacter)

var character_data: CharacterData = null
var alive := true
var is_possessed := false
var voice_name := ""

var action_target: Vector3 = Vector3.ZERO
var current_action: Dictionary = {}
var action_on_arrive: Dictionary = {}
var action_remaining_hours: float = 0.0
var moving := false
var llm_busy := false
## 剧情演出期间由 StoryModeManager 指定的姿态（talk/point/...），覆盖自动动画
var anim_override := ""
## 头顶漂浮对话气泡（按需创建）
var speech_bubble = null
## 气泡是否带语音；无语音时的兜底显示时长（秒）
var bubble_voice := false
var bubble_remaining := 0.0
var _bubble_hiding := false
var dying := false
var _death_cause := ""
var _dying_time := 0.0
var _low_energy_warn_cd := 0.0

var procedural_rig: ProceduralRig = null
var vrm_rig = null  # VRMRigDriver（经 VRM_RIG_SCRIPT 创建）
var model_anim_player: AnimationPlayer = null
var current_anim := ""
var has_model := false
var model_root: Node3D = null
var model_foot_local_y := 0.0

const ANIM_ALIASES := {
	"walk": "Walk", "run": "Run", "idle": "Idle", "jump": "Jump",
	"attack": "Attack", "pray": "Pray", "rest": "Rest", "gather": "Gather",
	"talk": "Talk", "point": "Point"
}

const VRM_RIG_SCRIPT := preload("res://scripts/characters/vrm_rig_driver.gd")

const NPC_GRAVITY := 22.0
const NPC_ACCEL := 12.0
const NPC_DECEL := 18.0
const NPC_SPEED := 3.2
const DYING_SEQUENCE_TIME := 1.6
const LOW_ENERGY_WARNING := 25.0

@onready var mesh: MeshInstance3D = $Mesh
@onready var label: Label3D = $Label
@onready var rig: Node3D = $Rig
var stuck_time := 0.0

func setup(data: CharacterData) -> void:
	character_data = data
	# 物理移动：支持坡面行走，NPC 与玩家使用同一套地面判定
	# 65° 覆盖程序化地形的最大坡度，避免角色在陡坡上滑落/腾空
	floor_max_angle = deg_to_rad(65.0)
	floor_snap_length = 0.35
	global_position = data.location
	_update_appearance()
	# 初始记忆：诞生
	if data.memories.is_empty():
		var fac_name := CivilizationManager.faction_name(data.faction_id)
		MemorySystem.add_memory(self, "我在%s苏醒，我的意识开始了。" % fac_name, 0.8, "curiosity", ["birth"])
	label.text = data.name
	label.modulate = Color(0.9, 0.95, 1.0)

func _ready() -> void:
	set_physics_process(true)
	set_process(true)

func _physics_process(delta: float) -> void:
	if not alive or is_possessed:
		return
	if dying:
		velocity.x = move_toward(velocity.x, 0.0, NPC_DECEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, NPC_DECEL * delta)
		velocity.y -= NPC_GRAVITY * delta
		velocity.y = maxf(velocity.y, -25.0)
		move_and_slide()
		return
	if moving:
		var dir := action_target - global_position
		dir.y = 0.0
		if dir.length() < 1.0:
			moving = false
			velocity.x = move_toward(velocity.x, 0.0, NPC_DECEL * delta)
			velocity.z = move_toward(velocity.z, 0.0, NPC_DECEL * delta)
			velocity.y -= NPC_GRAVITY * delta
			move_and_slide()
			ActionExecutor.on_character_arrived(self)
		else:
			var speed := float(character_data.status.get("speed", NPC_SPEED))
			var target_vel := dir.normalized() * speed
			# 平滑加减速 + 重力，NPC 可沿地形坡面自由行走
			velocity.x = move_toward(velocity.x, target_vel.x, NPC_ACCEL * delta)
			velocity.z = move_toward(velocity.z, target_vel.z, NPC_ACCEL * delta)
			velocity.y -= NPC_GRAVITY * delta
			velocity.y = maxf(velocity.y, -25.0)  # 限制下落速度，避免高速穿透薄碰撞体
			move_and_slide()
			var target_yaw := atan2(-dir.normalized().x, -dir.normalized().z)
			rotation.y = lerp_angle(rotation.y, target_yaw, clampf(10.0 * delta, 0.0, 1.0))
			_check_stuck(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, NPC_DECEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, NPC_DECEL * delta)
		velocity.y -= NPC_GRAVITY * delta
		velocity.y = maxf(velocity.y, -25.0)
		move_and_slide()

func _check_stuck(delta: float) -> void:
	# 被地形/建筑/同伴卡住时，重新选择附近目标，避免原地卡死
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed < 0.7:
		stuck_time += delta
		if stuck_time > 1.5:
			stuck_time = 0.0
			action_target = WorldManager.random_point_near(global_position, 12.0)
	else:
		stuck_time = 0.0

func _process(delta: float) -> void:
	if not alive:
		return
	_tick_bubble(delta)
	if dying:
		_update_dying(delta)
		_anchor_model_to_ground()
		return
	# 安全网：万一穿透地形，送回地面重新站立
	if global_position.y < -5.0:
		global_position = WorldManager.clamp_point(global_position, 0.95)
		velocity = Vector3.ZERO
	# 附身期间角色完全由玩家接管：不消耗状态、不推进旧行动、不产生自主行为
	if is_possessed:
		_anchor_model_to_ground()
		return
	# 低能量提示：颜色变红 + 周期性开口示警，让死亡前有预兆
	var energy_now := float(character_data.status.get("energy", 100.0))
	var warn_color := Color(1.0, 0.45, 0.45) if energy_now <= LOW_ENERGY_WARNING else Color(0.9, 0.95, 1.0)
	label.modulate = label.modulate.lerp(warn_color, clampf(delta * 3.0, 0.0, 1.0))
	if energy_now <= LOW_ENERGY_WARNING and bubble_remaining <= 0.5 and _low_energy_warn_cd <= 0.0:
		_low_energy_warn_cd = 12.0
		speak("我的能量快耗尽了……")
	_low_energy_warn_cd = maxf(0.0, _low_energy_warn_cd - delta)
	var dh := TimeManager.delta_game_hours(delta)
	if dh > 0.0:
		_tick_status(dh)
	if current_action.size() > 0 and action_remaining_hours > 0.0:
		action_remaining_hours -= dh
		if action_remaining_hours <= 0.0:
			action_remaining_hours = 0.0
			ActionExecutor.on_character_action_finished(self)
	_update_npc_animation()
	_anchor_model_to_ground()

func _tick_bubble(delta: float) -> void:
	## 气泡与语音同步：语音还在播就保持，播完给 0.6s 余量再收起；
	## 无语音（离线/未启用）时按文本长度兜底显示
	if speech_bubble == null or not is_instance_valid(speech_bubble) or not speech_bubble.visible:
		return
	if bubble_voice and TTSManager != null and TTSManager.is_speaking_for(self):
		bubble_remaining = 0.6
		return
	bubble_remaining -= delta
	if bubble_remaining <= 0.0 and not _bubble_hiding:
		_bubble_hiding = true
		_hide_bubble()

func _tick_status(dh: float) -> void:
	var st: Dictionary = character_data.status
	st["energy"] = maxf(0.0, float(st.get("energy", 100.0)) - 0.35 * dh)
	if moving:
		st["energy"] = maxf(0.0, float(st.get("energy", 100.0)) - 0.9 * dh)
	st["fatigue"] = minf(100.0, float(st.get("fatigue", 0.0)) + 0.25 * dh)
	st["health"] = minf(100.0, float(st.get("health", 100.0)) + 0.2 * dh)
	if float(st.get("energy", 100.0)) <= 0.0:
		start_dying("我的能量耗尽了……")

# ---------- 外观：导入模型 / 程序化骨骼 ----------

func set_appearance_model(path: String) -> void:
	## 排片/运行时换装：替换 VRM 形象并立即重建模型。
	if path == "" or character_data == null:
		return
	character_data.appearance["model_path"] = path
	_update_appearance()

func set_voice(voice: String) -> void:
	## 排片/运行时换声线：设置 TTS 声线，空值恢复自动分配。
	voice_name = voice

func _update_appearance() -> void:
	if not character_data:
		return
	mesh.visible = false  # 骨骼角色接管外观，回退网格隐藏
	_clear_rig()
	var color := _appearance_color()
	var model_path := str(character_data.appearance.get("model_path", ""))
	if model_path != "":
		has_model = _load_model(model_path)
		if not has_model:
			push_warning("模型加载失败，使用程序化骨骼角色：%s" % model_path)
	if not has_model:
		procedural_rig = ProceduralRig.new()
		procedural_rig.name = "ProceduralRig"
		rig.add_child(procedural_rig)
		procedural_rig.build(color, character_data.form, float(character_data.appearance.get("scale", 1.0)))

func _appearance_color() -> Color:
	var color: Color = Color(0.3, 0.7, 0.9)
	if character_data.appearance.has("color"):
		var c: Array = character_data.appearance["color"]
		if c.size() >= 3:
			color = Color(float(c[0]), float(c[1]), float(c[2]))
	return color

func _clear_rig() -> void:
	procedural_rig = null
	vrm_rig = null
	model_anim_player = null
	current_anim = ""
	has_model = false
	model_root = null
	model_foot_local_y = 0.0
	for child in rig.get_children():
		child.queue_free()

func _load_model(path: String) -> bool:
	## 优先加载编辑器导入的资源；否则用 GLTFDocument 在运行时解析 .glb/.gltf。
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = ResourceLoader.load(path) as PackedScene
	var model_root: Node = null
	if scene == null:
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		if gltf.append_from_file(path, state) != OK:
			return false
		model_root = gltf.generate_scene(state)
		if model_root == null:
			return false
	else:
		model_root = scene.instantiate()
	rig.add_child(model_root)
	_fit_model_to_ground(model_root, float(character_data.appearance.get("scale", 1.0)))
	_find_anim_player(model_root)
	if model_anim_player == null:
		var skeleton := _find_skeleton(model_root)
		if skeleton != null:
			vrm_rig = VRM_RIG_SCRIPT.new()
			vrm_rig.name = "VRMRig"
			rig.add_child(vrm_rig)
			vrm_rig.setup(skeleton, path)
			if not vrm_rig.enabled:
				push_warning("VRM 骨骼映射失败，模型将保持静态：%s" % path)
	return true

## 将模型按包围盒对齐：脚底落在本地 y=-0.95（胶囊底），并按外观 scale 归一化身高。
const MODEL_FOOT_Y := -0.95
const MODEL_TARGET_HEIGHT := 1.75

func _fit_model_to_ground(model_root: Node, scale_value: float) -> void:
	if model_root is Node3D:
		var aabb := _model_aabb(model_root)
		if aabb.size.y <= 0.001:
			return
		var height_scale := (MODEL_TARGET_HEIGHT * clampf(scale_value, 0.5, 2.0)) / aabb.size.y
		var root3d := model_root as Node3D
		root3d.scale = Vector3.ONE * height_scale
		var min_y := aabb.position.y * height_scale
		root3d.position.y = MODEL_FOOT_Y - min_y
		self.model_root = root3d
		model_foot_local_y = min_y

## 每帧把模型脚底锚定到地面（射线检测地形/建筑，空中或未命中时保持原状），
## 避免坡地、胶囊起伏导致的穿模与忽高忽低。
func _anchor_model_to_ground() -> void:
	if model_root == null:
		return
	# 附身跳跃/腾空时模型跟随身体；NPC 无跳跃，始终锚定（避免陡坡滑落时下沉）
	if is_possessed and not is_on_floor():
		return
	var ground_y := WorldManager.get_terrain_height(global_position.x, global_position.z)
	if is_on_floor():
		# 优先用射线命中实际网格面（地形/建筑），不可靠时回退地形高度函数
		var space := get_world_3d().direct_space_state
		var from := global_position + Vector3(0, 0.6, 0)
		var to := global_position + Vector3(0, -3.2, 0)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and hit.collider is StaticBody3D \
				and not hit.collider.has_method("collect") \
				and from.y - float(hit.position.y) < 3.0:
			ground_y = float(hit.position.y)
	model_root.position.y = ground_y - global_position.y - model_foot_local_y

func _model_aabb(root: Node) -> AABB:
	var boxes: Array = []
	_collect_aabb(root, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var result: AABB = boxes[0]
	for i in range(1, boxes.size()):
		result = result.merge(boxes[i])
	return result

func _collect_aabb(node: Node, acc: Transform3D, boxes: Array) -> void:
	if node is Node3D:
		var node3d: Node3D = node
		var acc_local := acc * node3d.transform
		if node3d is MeshInstance3D and node3d.mesh != null:
			boxes.append(acc_local * node3d.mesh.get_aabb())
		for child in node3d.get_children():
			_collect_aabb(child, acc_local, boxes)

func _find_anim_player(node: Node) -> void:
	if node is AnimationPlayer:
		model_anim_player = node
		return
	for child in node.get_children():
		_find_anim_player(child)
		if model_anim_player != null:
			return

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var s := _find_skeleton(child)
		if s != null:
			return s
	return null

func set_animation_state(state: String) -> void:
	## 动画状态机：idle/walk/run/jump/attack/pray/rest/gather。
	## 导入模型缺少对应动画名时尝试常见别名，仍缺失则保持当前动画。
	if state == current_anim:
		return
	current_anim = state
	if procedural_rig != null:
		procedural_rig.set_anim_state(state)
		return
	if vrm_rig != null:
		vrm_rig.set_anim_state(state)
		return
	if model_anim_player == null:
		return
	if model_anim_player.has_animation(state):
		model_anim_player.play(state, 0.15)
		return
	var alias := str(ANIM_ALIASES.get(state, ""))
	if alias != "" and model_anim_player.has_animation(alias):
		model_anim_player.play(alias, 0.15)

func set_move_speed(speed: float) -> void:
	if procedural_rig != null:
		procedural_rig.move_speed = speed
	if vrm_rig != null:
		vrm_rig.move_speed = speed

func _update_npc_animation() -> void:
	if is_possessed or not alive:
		return
	if moving:
		set_animation_state("walk")
		set_move_speed(float(character_data.status.get("speed", 4.0)))
		return
	set_move_speed(0.0)
	if anim_override != "":
		set_animation_state(anim_override)
		return
	var action_type := str(character_data.current_action)
	var state := "idle"
	match action_type:
		Enums.ACTION_ATTACK:
			state = "attack"
		Enums.ACTION_PRAY:
			state = "pray"
		Enums.ACTION_REST, Enums.ACTION_EAT, Enums.ACTION_MEDITATE:
			state = "rest"
	set_animation_state(state)

func speak(text: String, voiced := false, priority := false) -> void:
	if not alive:
		return
	_show_bubble(text)
	bubble_voice = voiced
	bubble_remaining = maxf(4.0, text.length() / 4.5)
	spoke.emit(self, text)
	# 对话日志：玩家范围内的所有台词进入右上角对话框
	if UIManager != null:
		UIManager.on_character_spoke(self, text)
	# 语音：仅对话（voiced=true）通过本地 Edge TTS 发声；
	# 每个角色随机分配一个声音，且只在玩家 10 米内才生成/播报。
	if voiced and TTSManager != null:
		if voice_name == "":
			voice_name = TTSManager.random_voice()
		TTSManager.speak(text, voice_name, self, priority)

func _show_bubble(text: String) -> void:
	if speech_bubble == null or not is_instance_valid(speech_bubble):
		speech_bubble = SpeechBubble.new()
		speech_bubble.name = "SpeechBubble"
		speech_bubble.position = Vector3(0, 1.8, 0)
		add_child(speech_bubble)
	_bubble_hiding = false
	# 气泡文字大小与头顶名牌一致（随名牌设置变化）
	if label != null:
		speech_bubble.set_target_text_scale(float(label.font_size) * label.pixel_size)
	speech_bubble.show_text(text)

func _hide_bubble() -> void:
	if speech_bubble != null and is_instance_valid(speech_bubble):
		speech_bubble.hide_bubble()

func face_towards(point: Vector3) -> void:
	## 让角色面向某个位置（只转 yaw），用于对话开始时双方转身。
	var dir := point - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	rotation.y = atan2(-dir.x, -dir.z)

func greet(visitor) -> void:
	## 对话开始时的反应：转向来访者并开口问候。
	if not alive or dying:
		return
	if visitor != null and is_instance_valid(visitor):
		face_towards(visitor.global_position)
	var guest_name := "旅人"
	if visitor != null and visitor.character_data != null:
		guest_name = str(visitor.character_data.name)
	var pools: Array[String] = []
	if GameState.is_story_mode():
		# 剧情模式·三体游戏：历史人物/同伴的问候只属于三体世界观
		pools = [
			"%s，是你。看这天色，乱纪元怕是又要来了。" % guest_name,
			"你来了，%s。太阳的事，有消息吗？" % guest_name,
			"%s，还好你赶在恒纪元里。活着，就还有机会。" % guest_name
		]
		speak(str(pools[randi() % pools.size()]), true, true)
		return
	match character_data.role:
		"priest":
			pools = ["愿晶海之光指引你，%s。" % guest_name, "啊，%s，你来了。晶海正注视着我们。" % guest_name]
		"guard":
			pools = ["站住——啊，是你，%s。最近小心些。" % guest_name, "%s，你来了。营地这边一切安好。" % guest_name]
		"scholar":
			pools = ["%s，你来得正好，我刚破译了一枚符文。" % guest_name, "哦，%s，想听听我的新发现吗？" % guest_name]
		"gatherer":
			pools = ["%s，你也要去采集吗？东边的晶簇长得很好。" % guest_name, "嗨，%s，这里的能量很充沛。" % guest_name]
		"builder":
			pools = ["%s，你来啦，看看这座新修的屋子。" % guest_name, "%s，欢迎回来。" % guest_name]
		"explorer":
			pools = ["嗨，%s！我刚从北边回来，那边有新发现。" % guest_name, "%s，正好，跟我讲讲你的见闻吧。" % guest_name]
		_:
			pools = ["你好，%s。" % guest_name, "%s，又见面了。" % guest_name]
	speak(str(pools[randi() % pools.size()]), true, true)

func start_dying(cause := "") -> void:
	## 进入死亡演出：停止行动、说遗言、缓缓倒下，随后由 CharacterManager 移除。
	if not alive or dying:
		return
	dying = true
	_death_cause = cause
	_dying_time = 0.0
	_low_energy_warn_cd = 0.0
	_hide_bubble()
	moving = false
	current_action = {}
	action_on_arrive = {}
	action_remaining_hours = 0.0
	if is_possessed and GameState.possessed_character == self:
		PlayerGodController.exit_possession()
	if cause != "":
		speak(cause, true, true)
	else:
		speak("我……感觉意识正在消散……", true, true)

func _update_dying(delta: float) -> void:
	_dying_time += delta
	set_animation_state("rest")
	var fall := -deg_to_rad(78.0)
	if model_root != null:
		model_root.rotation.x = lerpf(model_root.rotation.x, fall, clampf(delta * 4.5, 0.0, 1.0))
	elif rig != null:
		rig.rotation.x = lerpf(rig.rotation.x, fall, clampf(delta * 4.5, 0.0, 1.0))
	if _dying_time >= DYING_SEQUENCE_TIME:
		CharacterManager.kill_character(self, _death_cause)

func rule_based_decision() -> Dictionary:
	## 离线规则AI：基于需求与角色职业的效用决策，保证无LLM时游戏可玩。
	var st: Dictionary = character_data.status
	var energy := float(st.get("energy", 100.0))
	var fatigue := float(st.get("fatigue", 0.0))
	var health := float(st.get("health", 100.0))
	if health <= 20.0:
		return {"action": Enums.ACTION_REST, "duration_hours": 3.0, "intent": "rest"}
	if fatigue >= 70.0:
		return {"action": Enums.ACTION_REST, "duration_hours": 2.0, "intent": "rest"}
	if energy <= 35.0:
		var node = PerceptionSystem.nearest_resource(self, "energy_crystal")
		if node != null:
			return {"action": Enums.ACTION_GATHER, "target_node": node, "intent": "gather"}
		return {"action": Enums.ACTION_EAT, "duration_hours": 0.5, "intent": "eat"}
	# 社交：定期与附近角色交谈
	if randf() < 0.2:
		var other = PerceptionSystem.nearest_character(self)
		if other != null:
			return {"action": Enums.ACTION_TALK_TO, "target_character": other, "intent": "socialize"}
	# 职业行为
	match character_data.role:
		"gatherer":
			var types := ["energy_crystal", "metal", "data_shard", "biomass"]
			var rnode = PerceptionSystem.nearest_resource(self, types[randi() % types.size()])
			if rnode != null:
				return {"action": Enums.ACTION_GATHER, "target_node": rnode, "intent": "gather"}
		"builder":
			if randf() < 0.6:
				return {"action": Enums.ACTION_BUILD, "intent": "build"}
			var mnode = PerceptionSystem.nearest_resource(self, "metal")
			if mnode != null:
				return {"action": Enums.ACTION_GATHER, "target_node": mnode, "intent": "gather_metal"}
		"scholar":
			if randf() < 0.45:
				return {"action": Enums.ACTION_MEDITATE, "duration_hours": 1.5, "intent": "research"}
			if randf() < 0.5:
				var dnode = PerceptionSystem.nearest_resource(self, "data_shard")
				if dnode != null:
					return {"action": Enums.ACTION_GATHER, "target_node": dnode, "intent": "study_ruins"}
		"priest":
			if randf() < 0.7:
				return {"action": Enums.ACTION_PRAY, "duration_hours": 1.0, "intent": "pray"}
		"guard":
			if randf() < 0.3:
				var hostile = PerceptionSystem.nearest_hostile(self)
				if hostile != null:
					return {"action": Enums.ACTION_ATTACK, "target_character": hostile, "intent": "defend"}
			return {"action": Enums.ACTION_MOVE_TO, "position": WorldManager.random_point_near(global_position, 18.0), "intent": "patrol"}
		"explorer":
			return {"action": Enums.ACTION_MOVE_TO, "position": WorldManager.random_point_near(global_position, 45.0), "intent": "explore"}
	return {"action": Enums.ACTION_MOVE_TO, "position": WorldManager.random_point_near(global_position, 15.0), "intent": "wander"}

func get_status_text() -> String:
	var st: Dictionary = character_data.status
	return "能量 %d%% | 健康 %d%% | 疲劳 %d%%" % [
		int(st.get("energy", 0.0)), int(st.get("health", 0.0)), int(st.get("fatigue", 0.0))
	]
