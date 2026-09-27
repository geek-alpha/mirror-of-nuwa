class_name VRMRigDriver
extends Node
## 程序化驱动 VRM 骨骼的程序化动画。
## VRM 模型通常不携带动画，本驱动通过 VRM 扩展中的 humanoid 骨骼映射精确定位骨骼，
## 逐帧摆出行走/奔跑/待机/跳跃/攻击/祈祷/休息等姿态，与 ProceduralRig 共用同一套动画状态机。

var skeleton: Skeleton3D
var bone_ids: Dictionary = {}
var state := "idle"
var move_speed := 0.0
var anim_time := 0.0
var enabled := true
var _arm_drop_q: Dictionary = {}
var _elbow_axes: Dictionary = {}
var hips_rest_pos := Vector3.ZERO
## 需要“扶正”的骨骼（MMD 模型 rest 姿势常烘焙大角度旋转，如头骨 ~180°）
var _rest_compensation: Dictionary = {}

const ELBOW_BEND := 0.35
const IDLE_ELBOW_BEND := 0.18
const ARM_ABDUCT_DEG := 15.0

## 语义角色 -> VRM humanoid 骨骼键
const HUMAN_BONE_KEYS := {
	"hips": "hips",
	"spine": "spine",
	"chest": "chest",
	"head": "head",
	"arm_l": "leftUpperArm",
	"arm_r": "rightUpperArm",
	"forearm_l": "leftLowerArm",
	"forearm_r": "rightLowerArm",
	"leg_l": "leftUpperLeg",
	"leg_r": "rightUpperLeg",
	"shin_l": "leftLowerLeg",
	"shin_r": "rightLowerLeg",
	"foot_l": "leftFoot",
	"foot_r": "rightFoot"
}

## 兜底候选名（兼容 VRoid / Mixamo / Blender / 程序化骨骼等不同命名习惯）
const ROLE_CANDIDATES := {
	"hips": ["hips", "J_Bip_C_Hips", "Hips"],
	"spine": ["spine", "J_Bip_C_Spine", "Spine"],
	"chest": ["chest", "J_Bip_C_Chest", "Chest"],
	"head": ["head", "J_Bip_C_Head", "Head"],
	"arm_l": ["leftUpperArm", "J_Bip_L_UpperArm", "LeftArm", "UpperArm_L", "Upper_arm.L", "upper_arm.L", "arm_l"],
	"arm_r": ["rightUpperArm", "J_Bip_R_UpperArm", "RightArm", "UpperArm_R", "Upper_arm.R", "upper_arm.R", "arm_r"],
	"forearm_l": ["leftLowerArm", "J_Bip_L_LowerArm", "LeftForeArm", "LowerArm_L", "Lower_arm.L", "lower_arm.L"],
	"forearm_r": ["rightLowerArm", "J_Bip_R_LowerArm", "RightForeArm", "LowerArm_R", "Lower_arm.R", "lower_arm.R"],
	"leg_l": ["leftUpperLeg", "J_Bip_L_UpperLeg", "LeftUpLeg", "UpperLeg_L", "Upper_leg.L", "upper_leg.L", "leg_l"],
	"leg_r": ["rightUpperLeg", "J_Bip_R_UpperLeg", "RightUpLeg", "UpperLeg_R", "Upper_leg.R", "upper_leg.R", "leg_r"],
	"shin_l": ["leftLowerLeg", "J_Bip_L_LowerLeg", "LeftLeg", "LowerLeg_L", "Lower_leg.L", "lower_leg.L"],
	"shin_r": ["rightLowerLeg", "J_Bip_R_LowerLeg", "RightLeg", "LowerLeg_R", "Lower_leg.R", "lower_leg.R"],
	"foot_l": ["leftFoot", "J_Bip_L_Foot", "LeftFoot", "Foot_L", "Foot.L", "foot.L"],
	"foot_r": ["rightFoot", "J_Bip_R_Foot", "RightFoot", "Foot_R", "Foot.R", "foot.R"]
}

func setup(skel: Skeleton3D, model_path: String) -> void:
	skeleton = skel
	var mapping := _read_vrm_humanoid_mapping(model_path)
	var names := _resolve_bone_names(mapping)
	for role in names:
		var idx := skeleton.find_bone(names[role])
		if idx >= 0:
			bone_ids[role] = idx
	# 至少需要 髋/头 以及任一肢干，否则保持静态并关闭驱动
	if not bone_ids.has("hips") or not bone_ids.has("head"):
		enabled = false
		return
	if not (bone_ids.has("leg_l") or bone_ids.has("leg_r") or bone_ids.has("arm_l") or bone_ids.has("arm_r")):
		enabled = false
		return
	_prepare_arm_rig()
	if bone_ids.has("hips"):
		# set_bone_pose_position 是绝对位置，摆动必须以髋骨 rest 位置为基准
		hips_rest_pos = skeleton.get_bone_rest(int(bone_ids["hips"])).origin
	# MMD 导出常把 head 语义映射到 neck 类骨骼（如 BN_Neck / Bip001 Neck.002），
	# 若骨架里存在真正的 Head 骨骼则优先换用，避免程序化动画驱动错误的骨骼
	if bone_ids.has("head"):
		var head_name := skeleton.get_bone_name(int(bone_ids["head"]))
		if head_name.to_lower().contains("neck"):
			for i in skeleton.get_bone_count():
				var bn := skeleton.get_bone_name(i)
				if bn.to_lower().contains("head") and not bn.to_lower().ends_with("_end"):
					bone_ids["head"] = i
					break
	# MMD 模型常在 rest 姿势里烘焙大角度旋转（绣春/逍遥头骨 ~180°），
	# 程序化动画在此基础上叠加会导致头部始终歪斜；记录补偿量，摆姿时先“扶正”
	_rest_compensation.clear()
	for role in ["neck", "head"]:
		if not bone_ids.has(role):
			continue
		var rest_q := skeleton.get_bone_rest(int(bone_ids[role])).basis.get_rotation_quaternion()
		if rest_q.get_angle() > deg_to_rad(10.0):
			_rest_compensation[role] = rest_q.inverse()
	anim_time = randf() * 10.0

## VRM 标准休息姿势是 T-pose（手臂水平），直接绕 X 摆动等于绕手臂自身长轴转，手不会动。
## 这里先测量肩->肘方向，绕局部 Z 把手臂“放下”，再绕局部 X 前后摆动；
## 肘部用“放下后对应全局侧向轴”的局部旋转给出自然前弯。
func _prepare_arm_rig() -> void:
	for arm_role in ["arm_l", "arm_r"]:
		var forearm_role := "forearm_l" if arm_role == "arm_l" else "forearm_r"
		if not bone_ids.has(arm_role) or not bone_ids.has(forearm_role):
			continue
		var arm_idx: int = bone_ids[arm_role]
		var forearm_idx: int = bone_ids[forearm_role]
		var arm_rest := skeleton.get_bone_global_rest(arm_idx)
		var forearm_rest := skeleton.get_bone_global_rest(forearm_idx)
		var arm_dir := forearm_rest.origin - arm_rest.origin
		var arm_len := arm_dir.length()
		if arm_len < 0.001:
			continue
		# 绕全局 Z（骨架空间）把上臂放到垂直向下的旋转角
		var theta := -PI / 2.0 - atan2(arm_dir.y / arm_len, arm_dir.x / arm_len)
		theta = wrapf(theta, -PI, PI)
		# 手臂向身体左右张开约 30°，避免完全垂直时手部穿模裙摆/身体
		var abduct := deg_to_rad(ARM_ABDUCT_DEG)
		theta -= abduct if arm_role == "arm_l" else -abduct
		if absf(theta) > 0.12:
			_arm_drop_q[arm_role] = Quaternion((arm_rest.basis.inverse() * Vector3.BACK).normalized(), theta)
		# 前臂弯曲轴：在休息坐标系中，对应“放下后全局侧向轴”的方向
		var drop_global := Quaternion(Vector3.BACK, theta)
		# 骨骼 rest 带 1.01 级缩放，Basis 直接转 Quaternion 会报 “must be normalized”
		_elbow_axes[forearm_role] = ((drop_global * Quaternion(forearm_rest.basis.get_rotation_quaternion())).inverse() * Vector3.RIGHT).normalized()

func _arm_pose(arm_role: String, swing: float) -> Quaternion:
	if not bone_ids.has(arm_role):
		return Quaternion.IDENTITY
	var rest := skeleton.get_bone_global_rest(int(bone_ids[arm_role]))
	# rest.basis 可能带缩放（VRM 骨骼常带 1.01 级别缩放），逆变换后轴长 ≠ 1，
	# 不归一化会让 Quaternion() 每帧报 “axis must be normalized” 并算错旋转
	var swing_q := Quaternion((rest.basis.inverse() * Vector3.RIGHT).normalized(), swing)
	var drop_q: Quaternion = _arm_drop_q.get(arm_role, Quaternion.IDENTITY)
	return swing_q * drop_q

func _elbow_pose(forearm_role: String, bend: float) -> Quaternion:
	if not _elbow_axes.has(forearm_role):
		return Quaternion.IDENTITY
	return Quaternion(_elbow_axes[forearm_role], bend)

func set_anim_state(new_state: String) -> void:
	state = new_state

func _process(delta: float) -> void:
	if skeleton == null or not enabled:
		return
	# 步频随速度，但设上限：异常速度（冲刺/击飞）不会让摆动抽筋
	anim_time += delta * clampf(move_speed / 4.0, 0.25, 2.5)
	var rot: Dictionary = {}
	var pos: Dictionary = {}
	match state:
		"walk":
			_swing_pose(rot, 5.5, 0.7, 0.5, ELBOW_BEND)
			rot["spine"] = Quaternion(Vector3.FORWARD, sin(anim_time * 11.0) * 0.04)
			pos["hips"] = hips_rest_pos + Vector3(0, absf(sin(anim_time * 5.5)) * 0.015, 0)
		"run":
			_swing_pose(rot, 8.0, 1.0, 0.75, ELBOW_BEND + 0.25)
			rot["spine"] = Quaternion(Vector3.FORWARD, sin(anim_time * 16.0) * 0.05)
			rot["chest"] = Quaternion(Vector3.RIGHT, -0.12)
			pos["hips"] = hips_rest_pos + Vector3(0, absf(sin(anim_time * 8.0)) * 0.02, 0)
		"idle":
			rot["spine"] = Quaternion(Vector3.FORWARD, sin(anim_time * 1.8) * 0.025)
			rot["chest"] = Quaternion(Vector3.FORWARD, sin(anim_time * 1.8) * 0.02)
			rot["head"] = Quaternion(Vector3.RIGHT, sin(anim_time * 1.5) * 0.06)
			# 站立时手臂自然下垂：无前倾，仅轻微呼吸摆动与很小的肘部弯曲
			rot["arm_l"] = _arm_pose("arm_l", sin(anim_time * 1.8) * 0.02)
			rot["arm_r"] = _arm_pose("arm_r", sin(anim_time * 1.8) * 0.02)
			rot["forearm_l"] = _elbow_pose("forearm_l", IDLE_ELBOW_BEND)
			rot["forearm_r"] = _elbow_pose("forearm_r", IDLE_ELBOW_BEND)
			pos["hips"] = hips_rest_pos + Vector3(0, sin(anim_time * 1.8) * 0.008, 0)
		"talk":
			# 说话姿态：轻微点头、手臂小幅抬起、躯干随语气轻晃
			var t := anim_time * 6.0
			rot["head"] = Quaternion(Vector3.RIGHT, sin(t) * 0.10)
			rot["spine"] = Quaternion(Vector3.FORWARD, sin(anim_time * 2.4) * 0.03)
			rot["chest"] = Quaternion(Vector3.FORWARD, sin(anim_time * 2.4) * 0.025)
			rot["arm_l"] = _arm_pose("arm_l", 0.12 + sin(t * 0.7) * 0.08)
			rot["arm_r"] = _arm_pose("arm_r", 0.22 + sin(t) * 0.12)
			rot["forearm_l"] = _elbow_pose("forearm_l", IDLE_ELBOW_BEND)
			rot["forearm_r"] = _elbow_pose("forearm_r", ELBOW_BEND * 1.4)
			pos["hips"] = hips_rest_pos + Vector3(0, sin(anim_time * 2.4) * 0.008, 0)
		"point":
			# 指点姿态：一手前伸，另一手自然下垂，目光随指点方向
			rot["arm_r"] = _arm_pose("arm_r", -1.2)
			rot["forearm_r"] = _elbow_pose("forearm_r", 0.8)
			rot["arm_l"] = _arm_pose("arm_l", 0.12)
			rot["forearm_l"] = _elbow_pose("forearm_l", IDLE_ELBOW_BEND)
			rot["head"] = Quaternion(Vector3.RIGHT, 0.08)
			rot["spine"] = Quaternion(Vector3.FORWARD, sin(anim_time * 2.0) * 0.025)
			pos["hips"] = hips_rest_pos + Vector3(0, sin(anim_time * 2.0) * 0.006, 0)
		"jump":
			rot["leg_l"] = Quaternion(Vector3.RIGHT, 0.5)
			rot["leg_r"] = Quaternion(Vector3.RIGHT, 0.5)
			rot["shin_l"] = Quaternion(Vector3.RIGHT, -0.7)
			rot["shin_r"] = Quaternion(Vector3.RIGHT, -0.7)
			rot["arm_l"] = _arm_pose("arm_l", 1.25)
			rot["arm_r"] = _arm_pose("arm_r", 1.25)
			rot["forearm_l"] = _elbow_pose("forearm_l", 1.0)
			rot["forearm_r"] = _elbow_pose("forearm_r", 1.0)
		"attack":
			var swing := sin(anim_time * 10.0) * 1.4
			rot["arm_r"] = _arm_pose("arm_r", -swing)
			rot["forearm_r"] = _elbow_pose("forearm_r", 0.9 + absf(swing) * 0.25)
			rot["spine"] = Quaternion(Vector3.FORWARD, 0.08)
		"pray":
			rot["arm_l"] = _arm_pose("arm_l", 0.65)
			rot["arm_r"] = _arm_pose("arm_r", 0.65)
			rot["forearm_l"] = _elbow_pose("forearm_l", 1.25)
			rot["forearm_r"] = _elbow_pose("forearm_r", 1.25)
			rot["head"] = Quaternion(Vector3.RIGHT, 0.12)
		"rest":
			rot["spine"] = Quaternion(Vector3.RIGHT, -0.35)
			rot["head"] = Quaternion(Vector3.RIGHT, -0.2)
			rot["arm_l"] = _arm_pose("arm_l", 0.2)
			rot["arm_r"] = _arm_pose("arm_r", 0.2)
			rot["forearm_l"] = _elbow_pose("forearm_l", ELBOW_BEND + 0.15)
			rot["forearm_r"] = _elbow_pose("forearm_r", ELBOW_BEND + 0.15)
		_:
			pass
	_apply_pose(rot, pos, delta)

func _swing_pose(rot: Dictionary, freq: float, amp_leg: float, amp_arm: float, elbow: float) -> void:
	var s := sin(anim_time * freq)
	rot["leg_l"] = Quaternion(Vector3.RIGHT, s * amp_leg)
	rot["leg_r"] = Quaternion(Vector3.RIGHT, -s * amp_leg)
	rot["shin_l"] = Quaternion(Vector3.RIGHT, -s * amp_leg * 0.6)
	rot["shin_r"] = Quaternion(Vector3.RIGHT, s * amp_leg * 0.6)
	# 手臂与同侧腿反向摆动（对侧协调），略微前倾
	rot["arm_l"] = _arm_pose("arm_l", 0.1 - s * amp_arm)
	rot["arm_r"] = _arm_pose("arm_r", 0.1 + s * amp_arm)
	rot["forearm_l"] = _elbow_pose("forearm_l", elbow)
	rot["forearm_r"] = _elbow_pose("forearm_r", elbow)

func _apply_pose(rot: Dictionary, pos: Dictionary, delta: float) -> void:
	# 指数收敛（时间常数 0.1s）：状态切换不再瞬间跳变，且与帧率无关——
	# clampf(10*delta) 写法在掉帧（delta≥0.1）时会饱和成瞬跳
	var k := 1.0 - exp(-10.0 * delta)
	for role in bone_ids:
		var idx: int = bone_ids[role]
		var rest: Transform3D = skeleton.get_bone_rest(idx)
		var target_q: Quaternion = rest.basis.get_rotation_quaternion()
		if rot.has(role):
			var q: Quaternion = rot[role]
			if _rest_compensation.has(role):
				q = _rest_compensation[role] * q
			target_q = q
		skeleton.set_bone_pose_rotation(idx, skeleton.get_bone_pose_rotation(idx).slerp(target_q, k))
		var target_p: Vector3 = rest.origin
		if pos.has(role):
			target_p = pos[role]
		skeleton.set_bone_pose_position(idx, skeleton.get_bone_pose_position(idx).lerp(target_p, k))

## 从 GLB 容器的 JSON 块读取 VRM humanoid 骨骼映射（bone 语义 -> 节点名）。
## 同一路径只读一次文件，结果由 ModelLoader 缓存，供多个角色复用。
func _read_vrm_humanoid_mapping(path: String) -> Dictionary:
	return ModelLoader.vrm_mapping(path)

## 综合 VRM 映射与候选命名，为每个语义角色解析实际骨骼名。
func _resolve_bone_names(mapping: Dictionary) -> Dictionary:
	var out := {}
	for role in ROLE_CANDIDATES:
		var name := ""
		var hkey := str(HUMAN_BONE_KEYS.get(role, ""))
		if hkey != "" and mapping.has(hkey):
			name = _find_bone_name(str(mapping[hkey]))
		if name == "":
			var candidates: Array = ROLE_CANDIDATES[role]
			name = _fuzzy_find_bone(candidates)
		if name != "":
			out[role] = name
	return out

func _find_bone_name(mapping_name: String) -> String:
	## Godot 导入 glTF 时会对重复骨骼重命名（如 Bip001 Pelvis -> Bip001 Pelvis_2），
	## 按映射名精确查找失败时，依次尝试去数字后缀 / 前缀匹配。
	if mapping_name == "":
		return ""
	if skeleton.find_bone(mapping_name) >= 0:
		return mapping_name
	var base := _strip_bone_suffix(mapping_name)
	if base != "" and base != mapping_name and skeleton.find_bone(base) >= 0:
		return base
	if base.length() >= 4:
		for i in skeleton.get_bone_count():
			var bn := skeleton.get_bone_name(i)
			if bn.begins_with(base):
				return bn
	return ""

func _strip_bone_suffix(name: String) -> String:
	## 去掉 Godot/导出器追加的数字后缀：Bip001 Pelvis.002 -> Bip001 Pelvis
	var n := name
	var changed := true
	while changed and n != "":
		changed = false
		var last_dot := n.rfind(".")
		if last_dot > 0:
			if n.substr(last_dot + 1).is_valid_int():
				n = n.substr(0, last_dot)
				changed = true
				continue
		var last_us := n.rfind("_")
		if last_us > 0:
			if n.substr(last_us + 1).is_valid_int():
				n = n.substr(0, last_us)
				changed = true
	return n

func _fuzzy_find_bone(candidates: Array) -> String:
	# 精确匹配优先，其次前缀，最后包含（避免 Headset/headhudie 等误配）
	for cand in candidates:
		var cand_name := str(cand)
		if skeleton.find_bone(cand_name) >= 0:
			return cand_name
	for cand in candidates:
		var low: String = str(cand).to_lower()
		for i in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(i)
			if name.length() >= low.length() and name.substr(0, low.length()).to_lower() == low:
				return name
	for cand in candidates:
		var low: String = str(cand).to_lower()
		for i in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(i)
			if name.to_lower().contains(low):
				return name
	return ""
