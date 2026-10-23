extends StaticBody3D
## Depósito de recurso que se agota al recogerlo y reaparece pasado un tiempo.

const RESPAWN_TIME := 60.0
const MAX_AMOUNT := 3

var resource_type := "hierro"
var amount := MAX_AMOUNT
var _shape: CollisionShape3D


func setup(type: String, mesh: Mesh, material: Material, shape: Shape3D, shape_offset: Vector3) -> void:
	resource_type = type
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = shape_offset
	add_child(mesh_instance)
	_shape = CollisionShape3D.new()
	_shape.shape = shape
	_shape.position = shape_offset
	add_child(_shape)


func get_hint() -> String:
	return "%s (%d) · clic para recoger" % [Game.RESOURCE_NAMES[resource_type], amount]


# Un clic recoge el depósito entero; el taladro mejorado multiplica lo recogido.
func harvest(multiplier: int) -> int:
	if amount <= 0:
		return 0
	var taken := amount * multiplier
	amount = 0
	_deplete()
	return taken


func _deplete() -> void:
	visible = false
	_shape.set_deferred("disabled", true)
	await get_tree().create_timer(RESPAWN_TIME).timeout
	amount = MAX_AMOUNT
	visible = true
	_shape.set_deferred("disabled", false)
