extends StaticBody3D
## Construcción colocada por el jugador (panel, generador, calentador,
## taquilla...).

var kind := "panel"
## Entrada de Game.machines que se guarda con la partida. En las taquillas
## lleva también "items": lo que hay guardado.
var data := {}
## Caja que ocupa en el suelo (ancho, alto, fondo), para comprobar dónde cabe.
var footprint := Vector3.ONE
var _spinner: Node3D


func setup(machine_kind: String) -> void:
	kind = machine_kind
	var mesh_instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	var shape := BoxShape3D.new()
	match kind:
		"panel":
			var box := BoxMesh.new()
			box.size = Vector3(2.0, 0.1, 1.4)
			mesh_instance.mesh = box
			mesh_instance.position.y = 0.8
			mesh_instance.rotation_degrees.x = -25.0
			material.albedo_color = Color(0.15, 0.25, 0.6)
			shape.size = Vector3(2.0, 1.2, 1.4)
		"generador":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.5
			cylinder.bottom_radius = 0.7
			cylinder.height = 2.0
			cylinder.radial_segments = 6
			mesh_instance.mesh = cylinder
			mesh_instance.position.y = 1.0
			material.albedo_color = Color(0.85, 0.9, 0.85)
			shape.size = Vector3(1.4, 2.0, 1.4)
		"calentador":
			var heater := BoxMesh.new()
			heater.size = Vector3(1.2, 1.6, 1.2)
			mesh_instance.mesh = heater
			mesh_instance.position.y = 0.8
			material.albedo_color = Color(0.9, 0.45, 0.15)
			material.emission_enabled = true
			material.emission = Color(0.6, 0.2, 0.05)
			shape.size = Vector3(1.2, 1.6, 1.2)
		"turbina":
			var mast := CylinderMesh.new()
			mast.top_radius = 0.12
			mast.bottom_radius = 0.25
			mast.height = 4.0
			mast.radial_segments = 6
			mesh_instance.mesh = mast
			mesh_instance.position.y = 2.0
			material.albedo_color = Color(0.9, 0.9, 0.9)
			shape.size = Vector3(0.8, 4.0, 0.8)
			var blades := MeshInstance3D.new()
			var blade_mesh := BoxMesh.new()
			blade_mesh.size = Vector3(3.0, 0.25, 0.08)
			blades.mesh = blade_mesh
			blades.position = Vector3(0, 4.0, 0.3)
			blades.material_override = material
			add_child(blades)
			_spinner = blades
		"generador_avanzado":
			var big := CylinderMesh.new()
			big.top_radius = 0.7
			big.bottom_radius = 1.0
			big.height = 3.0
			big.radial_segments = 6
			mesh_instance.mesh = big
			mesh_instance.position.y = 1.5
			material.albedo_color = Color(0.3, 0.75, 0.65)
			shape.size = Vector3(2.0, 3.0, 2.0)
		"calentador_avanzado":
			var furnace := BoxMesh.new()
			furnace.size = Vector3(2.0, 2.4, 2.0)
			mesh_instance.mesh = furnace
			mesh_instance.position.y = 1.2
			material.albedo_color = Color(0.85, 0.3, 0.1)
			material.emission_enabled = true
			material.emission = Color(0.8, 0.25, 0.05)
			shape.size = Vector3(2.0, 2.4, 2.0)
		"taquilla":
			var cabinet := BoxMesh.new()
			cabinet.size = Vector3(0.8, 1.9, 0.6)
			mesh_instance.mesh = cabinet
			mesh_instance.position.y = 0.95
			material.albedo_color = Color(0.55, 0.6, 0.66)
			material.metallic = 0.4
			material.roughness = 0.5
			shape.size = Vector3(0.8, 1.9, 0.6)
			_add_locker_details()
	mesh_instance.material_override = material
	add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.size.y / 2.0
	add_child(collision)
	footprint = shape.size


## Puertas, rendijas, tiradores y una franja naranja en el frente (-Z).
func _add_locker_details() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.3, 0.33, 0.37)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.95, 0.55, 0.15)
	var front := -0.3
	# Ranura entre las dos puertas.
	_detail(Vector3(0.02, 1.8, 0.02), Vector3(0, 0.95, front), dark)
	for sx in [-1.0, 1.0]:
		# Tirador junto a la ranura.
		_detail(Vector3(0.03, 0.22, 0.04), Vector3(sx * 0.06, 1.0, front - 0.01), accent)
		# Rendijas de ventilación arriba de cada puerta.
		for k in 3:
			_detail(Vector3(0.24, 0.025, 0.02), Vector3(sx * 0.2, 1.65 - k * 0.07, front), dark)
	_detail(Vector3(0.82, 0.08, 0.62), Vector3(0, 0.12, 0), accent)


func _detail(size: Vector3, pos: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var part := MeshInstance3D.new()
	part.mesh = box
	part.position = pos
	part.material_override = material
	add_child(part)


func is_storage() -> bool:
	return Game.MACHINES[kind].has("storage")


func capacity() -> int:
	return int(Game.MACHINES[kind].get("storage", 0))


## Lo guardado en la taquilla: {recurso: cantidad}.
func items() -> Dictionary:
	if not data.has("items"):
		data["items"] = {}
	return data["items"]


func stored_total() -> int:
	var total := 0
	for id in items():
		total += int(items()[id])
	return total


## Convierte la construcción en una silueta sin colisión que se dibuja con
## el material dado (verde o rojo en el modo de colocación).
func make_ghost(material: Material) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			remove_child(child)
			child.free()
		elif child is MeshInstance3D:
			child.material_override = material
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if _spinner:
		_spinner.rotate_z(delta * 2.0)


func get_hint() -> String:
	var recipe_name: String = Game.RECIPES[kind]["name"]
	if is_storage():
		return "%s · %d / %d · E o clic para abrir" % [recipe_name, stored_total(), capacity()]
	var energy := int(Game.MACHINES[kind]["energy"])
	if energy > 0:
		if Game.MACHINES[kind].get("solar", false) and Game.is_night():
			return "%s · de noche no da energía" % recipe_name
		return "%s · da %d de energía" % [recipe_name, energy]
	if Game.energy_ratio() <= 0.0:
		return "%s · sin energía" % recipe_name
	return "%s · funcionando al %d %%" % [recipe_name, roundi(Game.energy_ratio() * 100.0)]
