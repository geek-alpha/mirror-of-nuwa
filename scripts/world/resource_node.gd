class_name ResourceNode
extends StaticBody3D
## 资源节点：可被硅灵采集，耗尽后消失。

var resource_id: String = "energy_crystal"
var resource_name: String = "能量晶体"
var amount: float = 50.0
var max_amount: float = 50.0

@onready var mesh: MeshInstance3D = $Mesh

func setup(res_type: String, res_name: String, initial: float, position: Vector3, color: Color) -> void:
	resource_id = res_type
	resource_name = res_name
	amount = initial
	max_amount = initial
	global_position = position
	mesh.rotation_degrees = Vector3(randf_range(0, 360), randf_range(0, 360), randf_range(0, 360))
	mesh.scale = Vector3.ONE * randf_range(0.5, 1.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.7
	mat.roughness = 0.3
	mat.metallic = 0.4
	mesh.material_override = mat

func collect(amount_to_take: float) -> float:
	var taken := minf(amount, amount_to_take)
	amount -= taken
	var scale := 0.5 + amount / max_amount * 0.7
	mesh.scale = Vector3.ONE * maxf(scale, 0.15)
	if amount <= 0.0:
		EventBus.resource_depleted.emit(resource_id)
		WorldManager.unregister_resource(self)
		queue_free()
	return taken

func to_save_dict() -> Dictionary:
	return {
		"id": resource_id,
		"name": resource_name,
		"amount": amount,
		"position": [global_position.x, global_position.y, global_position.z]
	}
