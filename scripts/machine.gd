extends StaticBody3D
## Construcción colocada por el jugador (panel, generador o calentador).

var kind := "panel"


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
	mesh_instance.material_override = material
	add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.size.y / 2.0
	add_child(collision)


func get_hint() -> String:
	var recipe_name: String = Game.RECIPES[kind]["name"]
	if kind == "panel":
		return recipe_name
	if Game.energy_ratio() <= 0.0:
		return "%s · sin energía" % recipe_name
	return "%s · funcionando al %d %%" % [recipe_name, roundi(Game.energy_ratio() * 100.0)]
