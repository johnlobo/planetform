extends StaticBody3D
## Depósito de recurso que se agota al recogerlo y reaparece pasado un tiempo.

const RESPAWN_TIME := 60.0
const MAX_AMOUNT := 3

var resource_type := "hierro"
var amount := MAX_AMOUNT
# true cuando el hielo se ha fundido del todo: ya no vuelve a aparecer.
var melted := false
var _shape: CollisionShape3D
var _base_scale := Vector3.ZERO


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


## Encoge el bloque según lo fundido (0 entero, 1 desaparecido).
func set_melt(fraction: float) -> void:
	if _base_scale == Vector3.ZERO:
		_base_scale = scale
	scale = _base_scale * lerpf(1.0, 0.25, fraction)
	if fraction >= 1.0 and not melted:
		melted = true
		amount = 0
		visible = false
		_shape.set_deferred("disabled", true)


func _deplete() -> void:
	visible = false
	_shape.set_deferred("disabled", true)
	# Con connect y no await: si el trozo del terreno se borra antes, no pasa nada.
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(_respawn)


func _respawn() -> void:
	if melted:
		return
	amount = MAX_AMOUNT
	visible = true
	_shape.set_deferred("disabled", false)
