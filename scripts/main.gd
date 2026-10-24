extends Node3D
## Construye el mundo del prototipo: terreno low poly, recursos, jugador,
## interfaz y los cambios visuales del planeta según la terraformación.

const ResourceNode := preload("res://scripts/resource_node.gd")
const Machine := preload("res://scripts/machine.gd")
const Player := preload("res://scripts/player.gd")
const Hud := preload("res://scripts/hud.gd")
const Menu := preload("res://scripts/menu.gd")

const WORLD_SIZE := 160.0
const GRID := 64 # cuadros por lado del terreno
const HEIGHT := 6.0
const RESOURCE_COUNTS := {"hierro": 40, "silicio": 25, "hielo": 25, "cobre": 20}
const PLANT_COUNT := 80

var noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var environment: Environment
var sun: DirectionalLight3D
var ground_material: StandardMaterial3D
var water: MeshInstance3D
var plants: Node3D
var player: CharacterBody3D

var sky_colors := Gradient.new()
var ground_colors := Gradient.new()


func _ready() -> void:
	noise.seed = 7
	noise.frequency = 0.02
	rng.seed = 42
	var loaded := Game.load_game()
	_setup_gradients()
	_build_environment()
	_build_terrain()
	_build_water()
	_spawn_resources()
	for m in Game.machines:
		_spawn_machine(String(m["kind"]), Vector3(float(m["x"]), float(m["y"]), float(m["z"])), float(m["rot"]))
	_spawn_player()
	var hud := Hud.new()
	add_child(hud)
	var menu := Menu.new()
	add_child(menu)
	menu.opened.connect(hud.on_menu_opened)
	menu.closed.connect(hud.on_menu_closed)
	Game.place_requested.connect(_on_place_requested)
	Game.stage_changed.connect(_on_stage_changed)
	if loaded:
		_on_stage_changed(Game.stage)
	# Tras pulsar "Nueva partida" se entra directamente a jugar.
	if Game.skip_title:
		Game.skip_title = false
	else:
		menu.open_title(loaded)


func _process(_delta: float) -> void:
	var t := Game.terraform_index() / 100.0
	# 1 de día, 0 de noche, con una transición suave alrededor del horizonte.
	var daylight := clampf(Game.sun_height() * 3.0 + 0.5, 0.0, 1.0)
	var sky := sky_colors.sample(t)
	environment.background_color = sky.darkened(0.85 * (1.0 - daylight))
	environment.ambient_light_color = sky.lightened(0.3).darkened(0.7 * (1.0 - daylight))
	ground_material.albedo_color = ground_colors.sample(t)
	sun.light_energy = lerpf(0.6, 1.2, t) * daylight
	sun.rotation_degrees.x = -10.0 - 70.0 * maxf(Game.sun_height(), 0.0)
	sun.rotation_degrees.y = 30.0 + Game.time_of_day * 360.0
	if water.visible:
		# El agua sube entre el 60 % y el 100 % del índice.
		var w := clampf((Game.terraform_index() - 60.0) / 40.0, 0.0, 1.0)
		water.position.y = lerpf(-HEIGHT, -HEIGHT * 0.2, w)


func height_at(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * HEIGHT


func _setup_gradients() -> void:
	sky_colors.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	sky_colors.colors = PackedColorArray([
		Color(0.04, 0.03, 0.06), Color(0.12, 0.16, 0.32),
		Color(0.3, 0.45, 0.7), Color(0.5, 0.75, 0.95)])
	ground_colors.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ground_colors.colors = PackedColorArray([
		Color(0.45, 0.42, 0.4), Color(0.5, 0.4, 0.3), Color(0.35, 0.45, 0.25)])


func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # normales planas: aspecto low poly
	var step := WORLD_SIZE / GRID
	var half := WORLD_SIZE / 2.0
	for i in GRID:
		for j in GRID:
			var x0 := -half + i * step
			var z0 := -half + j * step
			var a := Vector3(x0, height_at(x0, z0), z0)
			var b := Vector3(x0 + step, height_at(x0 + step, z0), z0)
			var c := Vector3(x0, height_at(x0, z0 + step), z0 + step)
			var d := Vector3(x0 + step, height_at(x0 + step, z0 + step), z0 + step)
			for v in [a, b, c, b, d, c]:
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()

	ground_material = StandardMaterial3D.new()
	ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground_material.roughness = 1.0

	var body := StaticBody3D.new()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = ground_material
	body.add_child(mesh_instance)
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _build_water() -> void:
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_SIZE, WORLD_SIZE)
	water.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.45, 0.75, 0.75)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = material
	water.position.y = -HEIGHT
	water.visible = false
	add_child(water)

	plants = Node3D.new()
	plants.visible = false
	add_child(plants)


func _spawn_resources() -> void:
	var defs := {
		"hierro": _resource_def(_low_poly_rock(), Color(0.55, 0.35, 0.25), _sphere_shape(0.8), Vector3(0, 0.4, 0)),
		"silicio": _resource_def(_crystal(), Color(0.55, 0.85, 0.95), _box_shape(Vector3(0.6, 1.6, 0.6)), Vector3(0, 0.8, 0)),
		"hielo": _resource_def(_ice_slab(), Color(0.85, 0.95, 1.0), _box_shape(Vector3(1.6, 0.4, 1.6)), Vector3(0, 0.2, 0)),
		"cobre": _resource_def(_low_poly_rock(), Color(0.3, 0.65, 0.5), _sphere_shape(0.8), Vector3(0, 0.4, 0)),
	}
	for type in RESOURCE_COUNTS:
		var def: Dictionary = defs[type]
		for n in int(RESOURCE_COUNTS[type]):
			var pos := _random_point(8.0)
			var node := ResourceNode.new()
			node.setup(type, def["mesh"], def["material"], def["shape"], def["offset"])
			node.position = pos
			node.rotation.y = rng.randf_range(0.0, TAU)
			add_child(node)


func _spawn_player() -> void:
	var base := Vector3(0.0, height_at(0.0, 0.0) + 1.0, 0.0)
	player = Player.new()
	player.position = base
	if Game.player_position != null:
		player.position = Game.player_position
	add_child(player)
	player.spawn_point = base # si se ahoga, vuelve a la base y no al punto guardado
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_place_requested(kind: String) -> void:
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	var pos := player.global_position + forward.normalized() * 4.0
	pos.y = height_at(pos.x, pos.z)
	_spawn_machine(kind, pos, player.rotation.y)
	Game.register_machine(kind, pos, player.rotation.y)


func _spawn_machine(kind: String, pos: Vector3, rot: float) -> void:
	var machine := Machine.new()
	machine.setup(kind)
	machine.position = pos
	machine.rotation.y = rot
	add_child(machine)


func _on_stage_changed(stage: int) -> void:
	if stage >= 2:
		water.visible = true
	if stage >= 3 and plants.get_child_count() == 0:
		_spawn_plants()
		plants.visible = true


func _spawn_plants() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.6
	cone.height = 1.8
	cone.radial_segments = 5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.6, 0.25)
	for n in PLANT_COUNT:
		var pos := _random_point(4.0)
		if pos.y < water.position.y + 0.3:
			continue
		var plant := MeshInstance3D.new()
		plant.mesh = cone
		plant.material_override = material
		plant.position = pos + Vector3(0, 0.9, 0)
		plants.add_child(plant)


func _random_point(min_distance: float) -> Vector3:
	var limit := WORLD_SIZE * 0.45
	var x := 0.0
	var z := 0.0
	while Vector2(x, z).length() < min_distance:
		x = rng.randf_range(-limit, limit)
		z = rng.randf_range(-limit, limit)
	return Vector3(x, height_at(x, z), z)


func _resource_def(mesh: Mesh, color: Color, shape: Shape3D, offset: Vector3) -> Dictionary:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return {"mesh": mesh, "material": material, "shape": shape, "offset": offset}


func _low_poly_rock() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.2
	sphere.radial_segments = 6
	sphere.rings = 3
	return sphere


func _crystal() -> Mesh:
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 0.35
	crystal.height = 1.6
	crystal.radial_segments = 4
	return crystal


func _ice_slab() -> Mesh:
	var slab := BoxMesh.new()
	slab.size = Vector3(1.6, 0.4, 1.6)
	return slab


func _sphere_shape(radius: float) -> Shape3D:
	var shape := SphereShape3D.new()
	shape.radius = radius
	return shape


func _box_shape(size: Vector3) -> Shape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape
