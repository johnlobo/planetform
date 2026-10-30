extends StaticBody3D
## Caja de suministros de una nave estrellada o del fondo de una cueva. Se
## abre una sola vez (E o clic) y da un chip de datos o un fragmento de plano.

## Identificador para el guardado: dónde está, que no cambia entre partidas.
var id := ""
var _lid: Node3D


func _ready() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.3, 0.33, 0.37)
	shell.metallic = 0.3
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.95, 0.55, 0.15)
	var light := StandardMaterial3D.new()
	light.albedo_color = Color(0.4, 0.9, 1.0)
	light.emission_enabled = true
	light.emission = Color(0.2, 0.7, 0.9)
	_box(self, Vector3(1.0, 0.55, 0.65), Vector3(0, 0.275, 0), shell)
	_box(self, Vector3(1.02, 0.08, 0.67), Vector3(0, 0.12, 0), accent)
	# La tapa gira sobre el borde de atrás (+Z).
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.55, 0.325)
	add_child(_lid)
	_box(_lid, Vector3(1.02, 0.1, 0.67), Vector3(0, 0.05, -0.335), shell)
	_box(_lid, Vector3(0.3, 0.02, 0.1), Vector3(0, 0.11, -0.5), light)
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.65, 0.65)
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position.y = 0.325
	add_child(collision)
	_update_lid()


func get_hint() -> String:
	if is_opened():
		return "Caja de suministros · vacía"
	return "Caja de suministros · E o clic para abrir"


func is_opened() -> bool:
	return id in Game.opened_crates


func open_crate() -> void:
	if is_opened():
		return
	Game.open_crate(id)
	_update_lid()


func _update_lid() -> void:
	_lid.rotation_degrees.x = -110.0 if is_opened() else 0.0


func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	parent.add_child(part)
