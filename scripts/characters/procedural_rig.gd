class_name ProceduralRig
extends Node3D
## 程序化骨骼角色：Skeleton3D 骨骼层次 + BoneAttachment3D 绑定部件网格。
## 逐帧设置骨骼姿态，实现行走/奔跑/跳跃/攻击/祈祷/休息等骨骼动画。
## 玩家导入 .glb/.gltf 模型后，此回退角色会被模型角色替换。

var skeleton: Skeleton3D
var bone_ids: Dictionary = {}
var state := "idle"
var move_speed := 0.0
var anim_time := 0.0
var body_color := Color(0.3, 0.7, 0.9)

func build(color: Color, form: String, scale_value: float) -> void:
	body_color = color
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	_add_bone("root", -1)
	var spine := _add_bone("spine", 0)
	_add_bone("head", spine)
	_add_bone("arm_l", spine)
	_add_bone("arm_r", spine)
	_add_bone("leg_l", 0)
	_add_bone("leg_r", 0)
	skeleton.set_bone_rest(0, Transform3D(Basis(), Vector3(0, 0.95, 0)))
	skeleton.set_bone_rest(1, Transform3D(Basis(), Vector3(0, 0.25, 0)))
	skeleton.set_bone_rest(2, Transform3D(Basis(), Vector3(0, 0.30, 0)))
	skeleton.set_bone_rest(3, Transform3D(Basis(), Vector3(-0.40, 0.18, 0)))
	skeleton.set_bone_rest(4, Transform3D(Basis(), Vector3(0.40, 0.18, 0)))
	skeleton.set_bone_rest(5, Transform3D(Basis(), Vector3(-0.16, -0.08, 0)))
	skeleton.set_bone_rest(6, Transform3D(Basis(), Vector3(0.16, -0.08, 0)))
	var head_size := 0.24
	var torso_scale := Vector3.ONE
	var limb_scale := Vector3.ONE
	match form:
		Enums.FORM_GEOMETRIC:
			head_size = 0.26
			torso_scale = Vector3(1.15, 0.9, 1.15)
		Enums.FORM_BESTIAL:
			head_size = 0.30
			torso_scale = Vector3(1.35, 0.95, 1.35)
			limb_scale = Vector3(1.2, 1.0, 1.2)
		Enums.FORM_FLUID:
			head_size = 0.28
			limb_scale = Vector3(0.7, 1.0, 0.7)
	# 部件网格绑定到骨骼：骨骼动画会带动部件运动
	_attach("head", "head", _head_mesh(form, head_size), Vector3(0, 0.24, 0))
	_attach("torso", "spine", _box_mesh(Vector3(0.55 * torso_scale.x, 0.5 * torso_scale.y, 0.45 * torso_scale.z)), Vector3(0, -0.08, 0))
	_attach("arm_l", "arm_l", _box_mesh(Vector3(0.14 * limb_scale.x, 0.5, 0.14 * limb_scale.z)), Vector3(0, -0.28, 0))
	_attach("arm_r", "arm_r", _box_mesh(Vector3(0.14 * limb_scale.x, 0.5, 0.14 * limb_scale.z)), Vector3(0, -0.28, 0))
	_attach("leg_l", "leg_l", _box_mesh(Vector3(0.17 * limb_scale.x, 0.62, 0.17 * limb_scale.z)), Vector3(0, -0.33, 0))
	_attach("leg_r", "leg_r", _box_mesh(Vector3(0.17 * limb_scale.x, 0.62, 0.17 * limb_scale.z)), Vector3(0, -0.33, 0))
	scale = Vector3.ONE * scale_value
	anim_time = randf() * 10.0

func _add_bone(bone_name: String, parent: int) -> int:
	var idx := skeleton.get_bone_count()
	skeleton.add_bone(bone_name)
	if parent >= 0:
		skeleton.set_bone_parent(idx, parent)
	bone_ids[bone_name] = idx
	return idx

func _head_mesh(form: String, radius: float) -> Mesh:
	if form == Enums.FORM_GEOMETRIC:
		var box := BoxMesh.new()
		box.size = Vector3.ONE * radius * 1.7
		box.material = _material()
		return box
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.material = _material()
	return sphere

func _box_mesh(size: Vector3) -> Mesh:
	var box := BoxMesh.new()
	box.size = size
	box.material = _material()
	return box

func _material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.emission_enabled = true
	mat.emission = body_color
	mat.emission_energy_multiplier = 0.6
	mat.roughness = 0.4
	mat.metallic = 0.5
	return mat

func _attach(att_name: String, bone_name: String, mesh: Mesh, offset: Vector3) -> void:
	var att := BoneAttachment3D.new()
	att.name = att_name
	att.bone_name = bone_name
	att.position = offset
	skeleton.add_child(att)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	att.add_child(mi)

func set_anim_state(new_state: String) -> void:
	state = new_state

func _process(delta: float) -> void:
	if skeleton == null:
		return
	anim_time += delta * maxf(move_speed / 4.0, 0.25)
	var rot: Dictionary = {}
	var pos: Dictionary = {}
	var freq := 5.0
	var amp_leg := 0.75
	var amp_arm := 0.5
	match state:
		"walk":
			freq = 5.5
			amp_leg = 0.75
			amp_arm = 0.5
			rot["leg_l"] = Quaternion(Vector3.RIGHT, sin(anim_time * freq) * amp_leg)
			rot["leg_r"] = Quaternion(Vector3.RIGHT, -sin(anim_time * freq) * amp_leg)
			rot["arm_l"] = Quaternion(Vector3.RIGHT, -sin(anim_time * freq) * amp_arm)
			rot["arm_r"] = Quaternion(Vector3.RIGHT, sin(anim_time * freq) * amp_arm)
			rot["spine"] = Quaternion(Vector3.FORWARD, sin(anim_time * freq * 2.0) * 0.04)
			pos["root"] = Vector3(0, 0.95 + absf(sin(anim_time * freq)) * 0.05, 0)
		"run":
			freq = 8.0
			amp_leg = 1.05
			amp_arm = 0.8
			rot["leg_l"] = Quaternion(Vector3.RIGHT, sin(anim_time * freq) * amp_leg)
			rot["leg_r"] = Quaternion(Vector3.RIGHT, -sin(anim_time * freq) * amp_leg)
			rot["arm_l"] = Quaternion(Vector3.RIGHT, -sin(anim_time * freq) * amp_arm)
			rot["arm_r"] = Quaternion(Vector3.RIGHT, sin(anim_time * freq) * amp_arm)
			rot["spine"] = Quaternion(Vector3.FORWARD, sin(anim_time * freq * 2.0) * 0.06)
			pos["root"] = Vector3(0, 0.95 + absf(sin(anim_time * freq)) * 0.07, 0)
		"idle":
			rot["spine"] = Quaternion(Vector3.FORWARD, sin(anim_time * 1.8) * 0.03)
			rot["head"] = Quaternion(Vector3.RIGHT, sin(anim_time * 1.5) * 0.08)
			pos["root"] = Vector3(0, 0.95 + sin(anim_time * 1.8) * 0.01, 0)
		"talk":
			# 说话姿态：轻微点头、手臂小幅抬起、躯干随语气轻晃
			var t := anim_time * 6.0
			rot["head"] = Quaternion(Vector3.RIGHT, sin(t) * 0.10)
			rot["spine"] = Quaternion(Vector3.FORWARD, sin(anim_time * 2.4) * 0.04)
			rot["arm_r"] = Quaternion(Vector3.RIGHT, 0.28 + sin(t) * 0.12)
			rot["arm_l"] = Quaternion(Vector3.RIGHT, 0.18 + sin(t * 0.7) * 0.08)
			pos["root"] = Vector3(0, 0.95 + sin(anim_time * 2.4) * 0.008, 0)
		"point":
			# 指点姿态：一手前伸，另一手自然下垂，目光随指点方向
			rot["arm_r"] = Quaternion(Vector3.RIGHT, -1.15)
			rot["arm_l"] = Quaternion(Vector3.RIGHT, 0.15)
			rot["head"] = Quaternion(Vector3.RIGHT, 0.05)
			rot["spine"] = Quaternion(Vector3.FORWARD, sin(anim_time * 2.0) * 0.03)
			pos["root"] = Vector3(0, 0.95 + sin(anim_time * 2.0) * 0.008, 0)
		"jump":
			rot["leg_l"] = Quaternion(Vector3.RIGHT, 0.5)
			rot["leg_r"] = Quaternion(Vector3.RIGHT, -0.45)
			rot["arm_l"] = Quaternion(Vector3.RIGHT, -1.3)
			rot["arm_r"] = Quaternion(Vector3.RIGHT, -1.3)
		"attack":
			rot["arm_r"] = Quaternion(Vector3.RIGHT, -sin(anim_time * 10.0) * 1.5)
			rot["spine"] = Quaternion(Vector3.FORWARD, 0.1)
		"pray":
			rot["arm_l"] = Quaternion(Vector3.RIGHT, 0.35)
			rot["arm_r"] = Quaternion(Vector3.RIGHT, 0.35)
			rot["head"] = Quaternion(Vector3.RIGHT, 0.12)
		"rest":
			rot["spine"] = Quaternion(Vector3.RIGHT, 0.55)
			rot["head"] = Quaternion(Vector3.RIGHT, 0.15)
		_:
			pass
	_apply_pose(rot, pos)

func _apply_pose(rot: Dictionary, pos: Dictionary) -> void:
	skeleton.reset_bone_poses()
	for bone_name in bone_ids:
		var idx: int = bone_ids[bone_name]
		if rot.has(bone_name):
			skeleton.set_bone_pose_rotation(idx, rot[bone_name])
		if pos.has(bone_name):
			skeleton.set_bone_pose_position(idx, pos[bone_name])
