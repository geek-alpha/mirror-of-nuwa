extends Node
## 角色管理器：创建/查询/销毁 AI 角色，负责初始角色生成与名称/外观生成。

var characters: Dictionary = {}
var templates: Array = []
var vrm_models: Array = []
## 按性别分类的 VRM 模型池：male / female / any（顶层未分类模型归 any）
var vrm_models_by_sex: Dictionary = {"male": [], "female": [], "any": []}
## 模型路径 -> 性别（"male" / "female" / "" 表示未分类）
var vrm_model_sex: Dictionary = {}
var counter := 0

## 已知在 Godot 运行时 GLTF 加载下渲染异常的模型：
## - 棕发学长：身体网格坍缩，只剩头部可渲染；
## - 马头零：整模型渲染为空。
## 随机分配时跳过，避免角色显示异常；用户仍可在排片面板中手动指定。
const BROKEN_VRM_MODELS := [
	"res://assets/models/characters/male/棕发学长.vrm",
	"res://assets/models/characters/male/马头零.vrm"
]

const NAME_A := ["晶", "璃", "霜", "岚", "烬", "砾", "渊", "穹", "曦", "暮", "萤", "焰", "汐", "栎", "珩", "琤"]
const NAME_B := ["辉", "澈", "曜", "冽", "漪", "吟", "洄", "淼", "玦", "聆", "朔", "隍", "沁", "陌", "瑶", "珩"]

func _ready() -> void:
	_load_templates()
	_scan_vrm_models()

func _scan_vrm_models() -> void:
	## 递归扫描资产目录下的 VRM 模型：male/famale(female) 子目录按性别分类，
	## 顶层及其他子目录归入 any，供按性别随机绑定使用。
	vrm_models.clear()
	vrm_models_by_sex = {"male": [], "female": [], "any": []}
	vrm_model_sex.clear()
	_scan_vrm_dir("res://assets/models/characters", "")
	vrm_models.sort()
	for key in vrm_models_by_sex:
		vrm_models_by_sex[key].sort()
	if vrm_models.is_empty():
		push_warning("未找到 VRM 模型，角色将回退到模板模型/程序化骨骼")

func _scan_vrm_dir(dir_path: String, sex: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("无法打开角色模型目录 %s" % dir_path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = dir.get_next()
			continue
		var full_path := dir_path.path_join(fname)
		if dir.current_is_dir():
			var sub_sex := ""
			match fname.to_lower():
				"male":
					sub_sex = "male"
				"famale", "female":
					sub_sex = "female"
				_:
					sub_sex = ""
			_scan_vrm_dir(full_path, sub_sex)
		elif fname.to_lower().ends_with(".vrm"):
			vrm_models.append(full_path)
			vrm_model_sex[full_path] = sex
			var pool_sex := sex if sex != "" else "any"
			vrm_models_by_sex[pool_sex].append(full_path)
		fname = dir.get_next()
	dir.list_dir_end()

func random_vrm_model(sex: String = "") -> String:
	## 按性别从 VRM 模型池随机取一个；性别池为空时依次回退 any 池/全量列表。
	var pool: Array = []
	if sex == "male":
		pool = vrm_models_by_sex.get("male", [])
	elif sex == "female":
		pool = vrm_models_by_sex.get("female", [])
	else:
		pool = vrm_models_by_sex.get("any", [])
	if pool.is_empty():
		pool = vrm_models_by_sex.get("any", [])
	if pool.is_empty():
		pool = vrm_models
	if pool.is_empty():
		return ""
	# 多次重试避开已知渲染异常的模型
	for attempt in 8:
		var cand := str(pool[randi() % pool.size()])
		if not BROKEN_VRM_MODELS.has(cand):
			return cand
	return str(pool[randi() % pool.size()])

func _load_templates() -> void:
	var f := FileAccess.open("res://resources/data/character_templates.json", FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			templates = parsed
		f.close()
	if templates.is_empty():
		push_warning("character_templates.json 为空，使用内置模板")
		templates = [{"id": "template_explorer", "role": "explorer", "personality": {}, "motivations": ["探索"], "speech_style": "好奇", "forms": ["humanoid"]}]

func spawn_initial_characters(count: int = -1) -> void:
	clear_all()
	HistoryManager.begin_batch()
	if count < 0:
		count = int(ConfigManager.game_setting("character_count", 10))
	var centers := CivilizationManager.faction_centers
	if centers.is_empty():
		CivilizationManager.initialize_factions()
	var tribe1_count := ceili(float(count) * 0.6)
	for i in count:
		var fid := "faction_crystal_dawn" if i < tribe1_count else "faction_abyss_flow"
		var center: Vector3 = CivilizationManager.faction_centers.get(fid, Vector3.ZERO)
		var pos := center + Vector3(randf_range(-8, 8), 0.0, randf_range(-8, 8))
		_create_random_character(pos, fid)
	HistoryManager.end_batch()

func create_character(data: CharacterData) -> AICharacter:
	if WorldManager.world == null:
		push_error("WorldManager.world 未初始化")
		return null
	var scene := preload("res://scenes/character.tscn")
	var char: AICharacter = scene.instantiate()
	char.name = data.id
	WorldManager.world.get_node("Characters").add_child(char)
	char.setup(data)
	characters[data.id] = char
	if data.faction_id != "":
		CivilizationManager.register_member(data.faction_id, data.id)
	EventBus.character_born.emit(char)
	return char

func _create_random_character(position: Vector3, faction_id: String) -> AICharacter:
	var template: Dictionary = templates[randi() % templates.size()]
	var data := CharacterData.new()
	data.id = "char_%d" % counter
	counter += 1
	data.name = _generate_name()
	data.form = str(template.get("forms", ["humanoid"])[randi() % int(template.get("forms", ["humanoid"]).size())])
	var model_path := str(template.get("model", ""))
	data.role = str(template.get("role", "explorer"))
	data.personality = Personality.from_dict(template.get("personality", {}))
	if not template.get("motivations", []).is_empty():
		data.personality.motivations = template["motivations"]
	data.speech_style = str(template.get("speech_style", "自然"))
	data.faction_id = faction_id
	data.sex = ["male", "female", "nonbinary"][randi() % 3]
	data.age = randf_range(1.0, 12.0)
	var color := CivilizationManager.faction_color(faction_id)
	var jitter := 0.25
	data.appearance = {
		"color": [clampf(color.r + randf_range(-jitter, jitter), 0.0, 1.0), clampf(color.g + randf_range(-jitter, jitter), 0.0, 1.0), clampf(color.b + randf_range(-jitter, jitter), 0.0, 1.0)],
		"scale": randf_range(0.8, 1.25)
	}
	# 随机绑定资产中的 VRM 模型，不再使用程序化/胶囊建模；
	# 未找到 VRM 时，人形模板仍回退到模板模型
	var random_model := random_vrm_model(data.sex)
	if random_model != "":
		model_path = random_model
		data.appearance["model_path"] = model_path
	elif data.form == Enums.FORM_HUMANOID and model_path != "":
		data.appearance["model_path"] = model_path
	# 0.95 让胶囊体底部恰好贴地（角色中心高度）
	data.location = WorldManager.clamp_point(position, 0.95)
	var home := WorldManager.nearest_building_of_function(data.location, "housing")
	data.home_id = home.building_id if home != null else ""
	_initial_goals(data)
	var char := create_character(data)
	HistoryManager.log_event("birth", "%s诞生了" % data.name, "一名%s在%s中苏醒。" % [Enums.ROLE_NAMES.get(data.role, data.role), CivilizationManager.faction_name(faction_id)], data.id, faction_id)
	return char

func spawn_random_character(position: Vector3, faction_id: String = "") -> AICharacter:
	## 创造模式入口：在指定位置生成一名随机硅灵角色。
	if faction_id == "":
		var ids := CivilizationManager.factions.keys()
		faction_id = str(ids[randi() % ids.size()]) if not ids.is_empty() else "faction_crystal_dawn"
	var char := _create_random_character(position, faction_id)
	HistoryManager.log_event("intervention", "神创造了%s" % char.character_data.name, "镜外之神以神力捏合晶体，一名新的硅灵诞生了。", char.character_data.id, faction_id)
	return char

func _initial_goals(data: CharacterData) -> void:
	match data.role:
		"gatherer":
			data.add_goal("收集能量晶体", "维持部落的能源储备", 0.8)
		"builder":
			data.add_goal("扩建聚落", "让族人拥有更多居所", 0.7)
		"scholar":
			data.add_goal("解读前代遗迹", "追寻失落的知识", 0.9)
		"priest":
			data.add_goal("聆听女娲的启示", "传播信仰", 0.8)
		"guard":
			data.add_goal("保卫聚落", "抵御任何威胁", 0.9)
		_:
			data.add_goal("探索未知世界", "发现新的区域与秘密", 0.6)

func _generate_name() -> String:
	var a: String = str(NAME_A[randi() % NAME_A.size()])
	var b: String = str(NAME_B[randi() % NAME_B.size()])
	return a + b

func get_character(character_id: String) -> AICharacter:
	return characters.get(character_id, null)

func all_characters() -> Array:
	var out: Array = []
	for cid in characters:
		out.append(characters[cid])
	return out

func kill_character(character: AICharacter, cause := "") -> void:
	if character == null or not character.alive:
		return
	character.alive = false
	character.character_data.status["health"] = 0.0
	CivilizationManager.unregister_member(character.character_data.faction_id, character.character_data.id)
	if GameState.possessed_character == character:
		PlayerGodController.exit_possession()
	var death_desc := "一名%s结束了它的生命循环。" % [Enums.ROLE_NAMES.get(character.character_data.role, character.character_data.role)]
	if cause != "":
		death_desc = "%s%s" % [cause, death_desc]
	HistoryManager.log_event("death", "%s陨落了" % character.character_data.name, death_desc, character.character_data.id, character.character_data.faction_id)
	MemorySystem.add_memory(character, "我感到了终结，意识归于晶海。", 1.0, "sadness", ["death"])
	EventBus.character_died.emit(character)
	characters.erase(character.character_data.id)
	character.queue_free()

func clear_all() -> void:
	for cid in characters:
		var c = characters[cid]
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			# 立即移出场景树，避免与同帧重建叠加（queue_free 只在帧末释放，会与新增角色共存一帧）
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	characters.clear()

func load_characters(data: Array) -> void:
	clear_all()
	HistoryManager.begin_batch()
	for item in data:
		var cd := CharacterData.from_save_dict(item)
		# 旧存档升级：无模型或仍指向旧示例模型的角色，随机绑定 VRM
		var saved_model := str(cd.appearance.get("model_path", ""))
		if (saved_model == "" or saved_model == "res://assets/models/characters/silicat_humanoid.gltf") \
				and not vrm_models.is_empty():
			var upgrade_model := random_vrm_model(cd.sex)
			if upgrade_model != "":
				cd.appearance["model_path"] = upgrade_model
		var char := create_character(cd)
		if char != null:
			char.moving = false
			char.current_action = {}
			MemorySystem.add_memory(char, "我从沉睡中醒来，世界已经变化。", 0.5, "curiosity", ["awakening"])
	HistoryManager.end_batch()
