extends Node
## 模型加载器：VRM/GLB 场景缓存 + 分帧预算加载，消除批量生成/换装时的同步卡顿。
##
## 痛点：角色外观此前在生成帧内同步调用 GLTFDocument 解析整个模型（文件 I/O + 结构解析 +
## 网格实例化），批量生成（世界开局/读档/纪元切换）会单帧阻塞数百毫秒。
##
## 方案：
##   ① 同一路径只解析一次，结果以 PackedScene 缓存，后续生成/换装直接实例化；
##   ② 未缓存模型进入分帧队列：每帧「解析一个 / 生成一个」交替进行，单帧只承担一半工作量；
##   ③ VRM 骨骼映射与模型包围盒按路径缓存，避免每次加载重复读文件/遍历整棵树；
##   ④ 剧情开场/纪元切换时先 preload_scenes 预热形象，过场播完模型已就绪。

## 每帧最多生成一个已解析模型（解析帧与生成帧交替，单模型平均两帧完成）
const MODELS_PER_FRAME := 1

## path -> PackedScene；失败路径缓存 null 避免反复尝试
var _scene_cache: Dictionary = {}
## path -> AABB（模型本地空间包围盒，与实例无关）
var _aabb_cache: Dictionary = {}
## path -> Dictionary（VRM humanoid 骨骼映射，读一次文件即可）
var _vrm_mapping_cache: Dictionary = {}
## 待解析的模型路径（已去重）
var _parse_pending: Array = []
## 已解析待生成：{"path": String, "gltf": GLTFDocument, "state": GLTFState}
var _generate_pending: Array = []
## path -> Array[Callable]，模型就绪后回调
var _callbacks: Dictionary = {}

func _ready() -> void:
	set_process(false)

## 同步取场景：命中缓存或已导入资源时立即可用；未缓存返回 null（应走 load_scene_async）。
func get_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path] as PackedScene
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = ResourceLoader.load(path) as PackedScene
	if scene != null:
		_scene_cache[path] = scene
	return scene

## 异步取场景：未缓存时入队分帧加载，就绪后回调（scene 为 null 表示加载失败）。
func load_scene_async(path: String, done: Callable = Callable()) -> void:
	if _scene_cache.has(path):
		if done.is_valid():
			done.call(path, _scene_cache[path])
		return
	if not _is_queued(path):
		_parse_pending.append(path)
		set_process(true)
	if done.is_valid():
		if not _callbacks.has(path):
			_callbacks[path] = []
		_callbacks[path].append(done)

## 批量预热：把未缓存的模型全部入队，按帧预算后台加载（用于过场/加载期间）。
func preload_scenes(paths: Array) -> void:
	var queued := false
	for p in paths:
		var path := str(p)
		if path == "":
			continue
		if _scene_cache.has(path):
			continue
		if _is_queued(path):
			continue
		_parse_pending.append(path)
		queued = true
	if queued:
		set_process(true)

func is_ready(path: String) -> bool:
	return _scene_cache.has(path) and _scene_cache[path] != null

## 模型本地空间包围盒（按路径缓存，避免每次换装遍历整棵节点树）。
func scene_aabb(path: String, root: Node) -> AABB:
	if _aabb_cache.has(path):
		return _aabb_cache[path]
	var boxes: Array = []
	_collect_aabb(root, Transform3D.IDENTITY, boxes)
	var result := AABB()
	if not boxes.is_empty():
		result = boxes[0]
		for i in range(1, boxes.size()):
			result = result.merge(boxes[i])
	_aabb_cache[path] = result
	return result

## VRM humanoid 骨骼映射（读一次文件并缓存，避免每个角色重复 I/O）。
func vrm_mapping(path: String) -> Dictionary:
	if _vrm_mapping_cache.has(path):
		return _vrm_mapping_cache[path]
	var mapping := _read_vrm_mapping(path)
	_vrm_mapping_cache[path] = mapping
	return mapping

func _process(_delta: float) -> void:
	# 交替执行：先消化已解析模型（生成帧），再解析下一个（解析帧），单帧负担减半
	if not _generate_pending.is_empty():
		_generate_next()
	elif not _parse_pending.is_empty():
		_parse_next()
	else:
		set_process(false)

func _parse_next() -> void:
	var path: String = _parse_pending.pop_front()
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	if gltf.append_from_file(path, state) == OK:
		_generate_pending.append({"path": path, "gltf": gltf, "state": state})
	else:
		_scene_cache[path] = null
		_notify(path, null)

func _generate_next() -> void:
	var job: Dictionary = _generate_pending.pop_front()
	var scene: PackedScene = null
	var root: Node = job["gltf"].generate_scene(job["state"])
	if root != null:
		var ps := PackedScene.new()
		if ps.pack(root) == OK:
			scene = ps
	_scene_cache[job["path"]] = scene
	_notify(job["path"], scene)

func _notify(path: String, scene) -> void:
	var cbs: Array = _callbacks.get(path, [])
	_callbacks.erase(path)
	for cb in cbs:
		if cb.is_valid():
			cb.call(path, scene)

func _is_queued(path: String) -> bool:
	if _parse_pending.has(path):
		return true
	for job in _generate_pending:
		if job["path"] == path:
			return true
	return false

## 从 GLB 容器的 JSON 块读取 VRM humanoid 骨骼映射（bone 语义 -> 节点名）。
func _read_vrm_mapping(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	if f.get_length() < 28:
		f.close()
		return {}
	f.seek(12)
	var chunk_len := f.get_32()
	var type_bytes := f.get_buffer(4)
	if type_bytes.get_string_from_ascii() != "JSON":
		f.close()
		return {}
	var json_bytes := f.get_buffer(chunk_len)
	f.close()
	var data = JSON.parse_string(json_bytes.get_string_from_utf8())
	if not (data is Dictionary):
		return {}
	var nodes: Array = data.get("nodes", [])
	var ext: Dictionary = data.get("extensions", {})
	var out := {}
	var ext_obj: Variant = null
	if ext.has("VRM"):
		ext_obj = ext["VRM"]
	elif ext.has("VRMC_vrm"):
		ext_obj = ext["VRMC_vrm"]
	if not (ext_obj is Dictionary):
		return out
	var humanoid: Variant = (ext_obj as Dictionary).get("humanoid", {})
	var hb: Variant = {}
	if humanoid is Dictionary:
		hb = (humanoid as Dictionary).get("humanBones", {})
	if hb is Array:
		# 列表格式：[{"bone": "hips", "node": 14}, ...]（VRM 0.x 常见导出）
		for entry in hb:
			if entry is Dictionary and (entry as Dictionary).has("bone") and (entry as Dictionary).has("node"):
				var idx := int((entry as Dictionary)["node"])
				if idx >= 0 and idx < nodes.size():
					out[str((entry as Dictionary)["bone"])] = str(nodes[idx].get("name", ""))
	elif hb is Dictionary:
		# 对象格式：{"hips": {"node": 14}, ...}（VRM 1.0）
		for key in hb:
			var entry = hb[key]
			if entry is Dictionary and entry.has("node"):
				var idx := int(entry["node"])
				if idx >= 0 and idx < nodes.size():
					out[key] = str(nodes[idx].get("name", ""))
	return out

func _collect_aabb(node: Node, acc: Transform3D, boxes: Array) -> void:
	if node is Node3D:
		var node3d: Node3D = node
		var acc_local := acc * node3d.transform
		if node3d is MeshInstance3D and node3d.mesh != null:
			boxes.append(acc_local * node3d.mesh.get_aabb())
		for child in node3d.get_children():
			_collect_aabb(child, acc_local, boxes)