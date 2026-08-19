extends Node
## 示例骨骼模型生成器：输出一个 glTF 2.0（text）格式的双足硅灵，
## 包含骨骼节点层次、部件网格与 idle/walk/run 骨骼动画。
## 运行：godot --headless --path . res://tools/generate_sample_model.tscn
## 输出：res://assets/models/characters/silicat_humanoid.gltf

var _bytes := PackedByteArray()
var _views: Array = []
var _accessors: Array = []

func _ready() -> void:
	_generate()
	get_tree().quit()

func _generate() -> void:
	var dir := DirAccess.open("res://assets/models/characters")
	if dir == null:
		DirAccess.make_dir_recursive_absolute("res://assets/models/characters")
	var head := _sphere_arrays(0.24, 10, 6)
	var arm := _box_arrays(Vector3(-0.07, -0.5, -0.07), Vector3(0.07, 0.0, 0.07))
	var leg := _box_arrays(Vector3(-0.085, -0.62, -0.085), Vector3(0.085, 0.0, 0.085))
	var torso := _box_arrays(Vector3(-0.275, -0.25, -0.225), Vector3(0.275, 0.25, 0.225))
	var mesh_indices: Array = []
	for geo in [head, arm, leg, torso]:
		mesh_indices.append(_add_mesh(geo))
	var doc := {
		"asset": {"version": "2.0", "generator": "NuwaMirrorTool"},
		"scene": 0,
		"scenes": [{"nodes": [0]}],
		"nodes": [
			{"name": "Root", "children": [1]},
			{"name": "Hips", "translation": [0.0, 0.95, 0.0], "children": [2, 6, 7]},
			{"name": "Spine", "translation": [0.0, 0.25, 0.0], "children": [3, 4, 5, 8]},
			{"name": "Head", "translation": [0.0, 0.30, 0.0], "mesh": mesh_indices[0]},
			{"name": "ArmL", "translation": [-0.40, 0.18, 0.0], "mesh": mesh_indices[1]},
			{"name": "ArmR", "translation": [0.40, 0.18, 0.0], "mesh": mesh_indices[1]},
			{"name": "LegL", "translation": [-0.16, -0.08, 0.0], "mesh": mesh_indices[2]},
			{"name": "LegR", "translation": [0.16, -0.08, 0.0], "mesh": mesh_indices[2]},
			{"name": "Torso", "translation": [0.0, -0.08, 0.0], "mesh": mesh_indices[3]}
		],
		"meshes": _meshes,
		"materials": [
			{
				"name": "Crystal",
				"pbrMetallicRoughness": {
					"baseColorFactor": [0.3, 0.75, 0.95, 1.0],
					"metallicFactor": 0.5,
					"roughnessFactor": 0.4
				},
				"emissiveFactor": [0.08, 0.2, 0.28]
			}
		],
		"animations": [
			_build_animation("idle", [
				{"node": 1, "path": "translation", "times": [0.0, 0.5, 1.0], "values": [[0.0, 0.95, 0.0], [0.0, 0.96, 0.0], [0.0, 0.95, 0.0]]},
				{"node": 2, "path": "rotation", "times": [0.0, 0.5, 1.0], "values": [_qz(0.04), _qz(-0.04), _qz(0.04)]},
				{"node": 3, "path": "rotation", "times": [0.0, 0.5, 1.0], "values": [_qx(0.05), _qx(0.10), _qx(0.05)]}
			]),
			_build_animation("walk", _walk_channels(0.7, 0.5, 0.95, [0.0, 0.25, 0.5, 0.75, 1.0], 1.0)),
			_build_animation("run", _walk_channels(1.05, 0.8, 1.03, [0.0, 0.15, 0.3, 0.45, 0.6], 0.6))
		],
		"accessors": _accessors,
		"bufferViews": _views,
		"buffers": [
			{
				"byteLength": _bytes.size(),
				"uri": "data:application/octet-stream;base64,%s" % Marshalls.raw_to_base64(_bytes)
			}
		]
	}
	var file := FileAccess.open("res://assets/models/characters/silicat_humanoid.gltf", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(doc, "\t"))
		file.close()
		print("已生成示例模型：res://assets/models/characters/silicat_humanoid.gltf（%d 字节）" % _bytes.size())
	else:
		push_error("无法写入示例模型文件")

var _meshes: Array = []

func _add_mesh(geo: Dictionary) -> int:
	var pos_view := _append_view(_pack_floats(geo.pos))
	var nrm_view := _append_view(_pack_floats(geo.nrm))
	var idx_view := _append_view(_pack_u16(geo.idx))
	var pos_acc := _add_accessor(pos_view, geo.pos.size() / 3, 5126, "VEC3", _min_max(geo.pos))
	var nrm_acc := _add_accessor(nrm_view, geo.nrm.size() / 3, 5126, "VEC3", {})
	var idx_acc := _add_accessor(idx_view, geo.idx.size(), 5123, "SCALAR", {})
	var mesh := {"name": "Part", "primitives": [{"attributes": {"POSITION": pos_acc, "NORMAL": nrm_acc}, "indices": idx_acc, "material": 0}]}
	_meshes.append(mesh)
	return _meshes.size() - 1

func _append_view(data: PackedByteArray) -> int:
	while _bytes.size() % 4 != 0:
		_bytes.append(0)
	var view := {"buffer": 0, "byteOffset": _bytes.size(), "byteLength": data.size()}
	_views.append(view)
	_bytes.append_array(data)
	return _views.size() - 1

func _add_accessor(view_idx: int, count: int, component_type: int, acc_type: String, minmax: Dictionary) -> int:
	var acc := {
		"bufferView": view_idx,
		"byteOffset": 0,
		"componentType": component_type,
		"count": count,
		"type": acc_type
	}
	if not minmax.is_empty():
		acc["min"] = minmax.get("min", [])
		acc["max"] = minmax.get("max", [])
	_accessors.append(acc)
	return _accessors.size() - 1

func _build_animation(name: String, channels: Array) -> Dictionary:
	var anim := {"name": name, "channels": [], "samplers": []}
	for ch in channels:
		var time_view := _append_view(_pack_floats(ch.times))
		var time_acc := _add_accessor(time_view, ch.times.size(), 5126, "SCALAR", {})
		var out_values: Array = ch.values
		var vec_type := "VEC3" if ch.path == "translation" else "VEC4"
		var out_view := _append_view(_pack_floats(_flatten(out_values)))
		var out_acc := _add_accessor(out_view, out_values.size(), 5126, vec_type, {})
		var sampler_idx: int = anim.samplers.size()
		anim.samplers.append({"input": time_acc, "output": out_acc, "interpolation": "LINEAR"})
		anim.channels.append({"sampler": sampler_idx, "target": {"node": int(ch.node), "path": str(ch.path)}})
	return anim

func _walk_channels(leg_amp: float, arm_amp: float, bob_y: float, times: Array, _cycle: float) -> Array:
	return [
		{"node": 6, "path": "rotation", "times": times, "values": [_qx(0.0), _qx(-leg_amp), _qx(0.0), _qx(leg_amp), _qx(0.0)]},
		{"node": 7, "path": "rotation", "times": times, "values": [_qx(0.0), _qx(leg_amp), _qx(0.0), _qx(-leg_amp), _qx(0.0)]},
		{"node": 4, "path": "rotation", "times": times, "values": [_qx(0.0), _qx(arm_amp), _qx(0.0), _qx(-arm_amp), _qx(0.0)]},
		{"node": 5, "path": "rotation", "times": times, "values": [_qx(0.0), _qx(-arm_amp), _qx(0.0), _qx(arm_amp), _qx(0.0)]},
		{"node": 1, "path": "translation", "times": [times[0], times[int(times.size() / 2)], times[times.size() - 1]], "values": [[0.0, 0.95, 0.0], [0.0, bob_y, 0.0], [0.0, 0.95, 0.0]]}
	]

func _qx(angle: float) -> Array:
	return _quat(Vector3.RIGHT, angle)

func _qz(angle: float) -> Array:
	return _quat(Vector3.FORWARD, angle)

func _quat(axis: Vector3, angle: float) -> Array:
	var half := angle / 2.0
	var s := sin(half)
	return [axis.x * s, axis.y * s, axis.z * s, cos(half)]

func _flatten(values: Array) -> Array:
	var out: Array = []
	for v in values:
		for component in v:
			out.append(float(component))
	return out

func _min_max(values: Array) -> Dictionary:
	var min_v := [INF, INF, INF]
	var max_v := [-INF, -INF, -INF]
	for i in range(0, values.size(), 3):
		for j in 3:
			min_v[j] = minf(min_v[j], float(values[i + j]))
			max_v[j] = maxf(max_v[j], float(values[i + j]))
	return {"min": min_v, "max": max_v}

func _pack_floats(values: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for v in values:
		var start := out.size()
		out.resize(start + 4)
		out.encode_float(start, float(v))
	return out

func _pack_u16(values: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for v in values:
		var start := out.size()
		out.resize(start + 2)
		out.encode_u16(start, int(v))
	return out

func _sphere_arrays(radius: float, seg: int, rings: int) -> Dictionary:
	var pos: Array = []
	var nrm: Array = []
	var idx: Array = []
	for ring in rings + 1:
		var phi := PI * float(ring) / float(rings)
		for s in seg:
			var theta := TAU * float(s) / float(seg)
			var x := radius * sin(phi) * cos(theta)
			var y := radius * cos(phi)
			var z := radius * sin(phi) * sin(theta)
			var n := Vector3(x, y, z).normalized()
			pos.append_array([x, y, z])
			nrm.append_array([n.x, n.y, n.z])
	for ring in rings:
		for s in seg:
			var v00 := ring * seg + s
			var v01 := ring * seg + ((s + 1) % seg)
			var v10 := (ring + 1) * seg + s
			var v11 := (ring + 1) * seg + ((s + 1) % seg)
			idx.append_array([v00, v10, v11, v00, v11, v01])
	return {"pos": pos, "nrm": nrm, "idx": idx}

func _box_arrays(minv: Vector3, maxv: Vector3) -> Dictionary:
	var pos: Array = []
	var nrm: Array = []
	var idx: Array = []
	var faces := [
		{"n": Vector3(1, 0, 0), "pts": [Vector3(maxv.x, minv.y, minv.z), Vector3(maxv.x, maxv.y, minv.z), Vector3(maxv.x, maxv.y, maxv.z), Vector3(maxv.x, minv.y, maxv.z)]},
		{"n": Vector3(-1, 0, 0), "pts": [Vector3(minv.x, minv.y, maxv.z), Vector3(minv.x, maxv.y, maxv.z), Vector3(minv.x, maxv.y, minv.z), Vector3(minv.x, minv.y, minv.z)]},
		{"n": Vector3(0, 1, 0), "pts": [Vector3(minv.x, maxv.y, minv.z), Vector3(maxv.x, maxv.y, minv.z), Vector3(maxv.x, maxv.y, maxv.z), Vector3(minv.x, maxv.y, maxv.z)]},
		{"n": Vector3(0, -1, 0), "pts": [Vector3(minv.x, minv.y, maxv.z), Vector3(maxv.x, minv.y, maxv.z), Vector3(maxv.x, minv.y, minv.z), Vector3(minv.x, minv.y, minv.z)]},
		{"n": Vector3(0, 0, 1), "pts": [Vector3(minv.x, minv.y, maxv.z), Vector3(maxv.x, minv.y, maxv.z), Vector3(maxv.x, maxv.y, maxv.z), Vector3(minv.x, maxv.y, maxv.z)]},
		{"n": Vector3(0, 0, -1), "pts": [Vector3(maxv.x, minv.y, minv.z), Vector3(minv.x, minv.y, minv.z), Vector3(minv.x, maxv.y, minv.z), Vector3(maxv.x, maxv.y, minv.z)]}
	]
	var base := 0
	for f in faces:
		for p in f.pts:
			pos.append_array([p.x, p.y, p.z])
			nrm.append_array([f.n.x, f.n.y, f.n.z])
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		base += 4
	return {"pos": pos, "nrm": nrm, "idx": idx}
