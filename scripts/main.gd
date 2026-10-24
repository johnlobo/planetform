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
const STAR_COUNT := 400
const ROCK_VARIANTS := 4 # formas distintas de cada tipo de roca

var noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
# Aparte de rng para que los detalles visuales no muevan los recursos de sitio.
var deco_rng := RandomNumberGenerator.new()
var environment: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var stars: MeshInstance3D
var star_material: StandardMaterial3D
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
	deco_rng.seed = 99
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
	var night := 1.0 - daylight
	var sky := sky_colors.sample(t)
	var horizon := sky.lightened(0.35).lerp(Color(0.9, 0.6, 0.4), _dusk() * 0.6)
	var night_sky := Color(0.02, 0.025, 0.06)
	sky_material.sky_top_color = sky.lerp(night_sky, night * 0.95)
	sky_material.sky_horizon_color = horizon.lerp(night_sky.lightened(0.08), night * 0.9)
	sky_material.ground_horizon_color = sky_material.sky_horizon_color
	sky_material.ground_bottom_color = sky_material.sky_horizon_color.darkened(0.5)
	environment.fog_light_color = sky_material.sky_horizon_color
	# Con atmósfera la niebla es más densa: el aire se ve.
	environment.fog_density = lerpf(0.004, 0.009, t)
	# De noche queda algo de luz azulada para que se vea el terreno.
	environment.ambient_light_color = sky.lightened(0.3).lerp(Color(0.25, 0.3, 0.5), night * 0.8)
	environment.ambient_light_energy = lerpf(0.6, 0.35, night)
	ground_material.albedo_color = ground_colors.sample(t)
	sun.light_energy = lerpf(0.6, 1.2, t) * daylight
	sun.light_color = Color.WHITE.lerp(Color(1.0, 0.7, 0.45), _dusk())
	moon.light_energy = 0.25 * night
	# Las estrellas se apagan a medida que la atmósfera se espesa.
	star_material.albedo_color.a = night * lerpf(1.0, 0.5, t)
	stars.visible = night > 0.01
	stars.global_position = player.global_position
	sun.rotation_degrees.x = -10.0 - 70.0 * maxf(Game.sun_height(), 0.0)
	sun.rotation_degrees.y = 30.0 + Game.time_of_day * 360.0
	if water.visible:
		# El agua sube entre el 60 % y el 100 % del índice.
		var w := clampf((Game.terraform_index() - 60.0) / 40.0, 0.0, 1.0)
		water.position.y = lerpf(-HEIGHT, -HEIGHT * 0.2, w)


## 1 cuando el sol está en el horizonte (amanecer y atardecer), 0 lejos de él.
func _dusk() -> float:
	return clampf(1.0 - absf(Game.sun_height()) * 4.0, 0.0, 1.0)


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
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.6
	environment.fog_enabled = true
	environment.fog_sky_affect = 0.1
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-60.0, -120.0, 0.0)
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.0
	add_child(moon)

	_build_stars()


## Puntos blancos en una cúpula que sigue al jugador.
func _build_stars() -> void:
	var points := PackedVector3Array()
	for n in STAR_COUNT:
		var dir := Vector3(deco_rng.randf_range(-1, 1), deco_rng.randf_range(0.05, 1), deco_rng.randf_range(-1, 1)).normalized()
		points.append(dir * 250.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	star_material = StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_material.use_point_size = true
	star_material.point_size = 2.0
	star_material.disable_fog = true
	star_material.albedo_color = Color(1, 1, 1, 0)
	stars = MeshInstance3D.new()
	stars.mesh = mesh
	stars.material_override = star_material
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)


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
			for tri in [[a, b, c], [b, d, c]]:
				st.set_color(_ground_shade(tri[0], tri[1], tri[2]))
				for v in tri:
					st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()

	ground_material = StandardMaterial3D.new()
	ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground_material.roughness = 1.0
	# Los colores por triángulo se multiplican por el color de la etapa.
	ground_material.vertex_color_use_as_albedo = true

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


## Tono de gris de un triángulo: más oscuro en pendiente y en los valles,
## con algo de ruido para que se distingan las caras.
func _ground_shade(a: Vector3, b: Vector3, c: Vector3) -> Color:
	var normal := (b - a).cross(c - a).normalized()
	var flat := absf(normal.y)
	var height := ((a.y + b.y + c.y) / 3.0 + HEIGHT) / (2.0 * HEIGHT)
	var v := 0.7 + 0.2 * flat + 0.15 * height + deco_rng.randf_range(-0.05, 0.05)
	return Color(v, v, v)


func _build_water() -> void:
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_SIZE, WORLD_SIZE)
	water.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.4, 0.7, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.1
	material.metallic_specular = 1.0
	water.material_override = material
	water.position.y = -HEIGHT
	water.visible = false
	add_child(water)

	plants = Node3D.new()
	plants.visible = false
	add_child(plants)


func _spawn_resources() -> void:
	var defs := {
		"hierro": _resource_def(_variants(_low_poly_rock), Color(0.55, 0.35, 0.25), _sphere_shape(0.8), Vector3(0, 0.4, 0)),
		"silicio": _resource_def(_variants(_crystal), Color(0.55, 0.85, 0.95), _box_shape(Vector3(0.9, 1.6, 0.9)), Vector3(0, 0.8, 0)),
		"hielo": _resource_def(_variants(_ice_slab), Color(0.85, 0.95, 1.0), _box_shape(Vector3(1.6, 0.4, 1.6)), Vector3(0, 0.2, 0)),
		"cobre": _resource_def(_variants(_low_poly_rock), Color(0.3, 0.65, 0.5), _sphere_shape(0.8), Vector3(0, 0.4, 0)),
	}
	defs["silicio"]["material"].emission_enabled = true
	defs["silicio"]["material"].emission = Color(0.1, 0.25, 0.3)
	defs["silicio"]["material"].roughness = 0.2
	defs["hielo"]["material"].roughness = 0.15
	for type in RESOURCE_COUNTS:
		var def: Dictionary = defs[type]
		var meshes: Array = def["meshes"]
		for n in int(RESOURCE_COUNTS[type]):
			var pos := _random_point(8.0)
			var node := ResourceNode.new()
			var mesh: Mesh = meshes[deco_rng.randi() % meshes.size()]
			node.setup(type, mesh, def["material"], def["shape"], def["offset"])
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
	Sfx.play("colocar")
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
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.08
	trunk.bottom_radius = 0.12
	trunk.height = 0.8
	trunk.radial_segments = 5
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 0.7
	crown.height = 1.4
	crown.radial_segments = 5
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.4, 0.28, 0.18)
	var greens: Array[StandardMaterial3D] = []
	for color in [Color(0.25, 0.6, 0.25), Color(0.35, 0.65, 0.2), Color(0.2, 0.5, 0.3)]:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		greens.append(material)
	var bush_meshes := _variants(_bush)
	for n in PLANT_COUNT:
		var pos := _random_point(4.0)
		if pos.y < water.position.y + 0.3:
			continue
		var plant := Node3D.new()
		plant.position = pos
		plant.rotation.y = deco_rng.randf_range(0.0, TAU)
		plant.scale = Vector3.ONE * deco_rng.randf_range(0.7, 1.4)
		var green: StandardMaterial3D = greens[deco_rng.randi() % greens.size()]
		if deco_rng.randf() < 0.65:
			# Árbol: tronco y dos o tres conos apilados.
			_add_part(plant, trunk, trunk_material, 0.4)
			var layers := deco_rng.randi_range(2, 3)
			for k in layers:
				var part := _add_part(plant, crown, green, 1.1 + k * 0.55)
				part.scale = Vector3.ONE * (1.0 - k * 0.22)
		else:
			_add_part(plant, bush_meshes[deco_rng.randi() % bush_meshes.size()], green, 0.25)
		plants.add_child(plant)


func _add_part(parent: Node3D, mesh: Mesh, material: Material, y: float) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position.y = y
	parent.add_child(part)
	return part


func _random_point(min_distance: float) -> Vector3:
	var limit := WORLD_SIZE * 0.45
	var x := 0.0
	var z := 0.0
	while Vector2(x, z).length() < min_distance:
		x = rng.randf_range(-limit, limit)
		z = rng.randf_range(-limit, limit)
	return Vector3(x, height_at(x, z), z)


func _resource_def(meshes: Array, color: Color, shape: Shape3D, offset: Vector3) -> Dictionary:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return {"meshes": meshes, "material": material, "shape": shape, "offset": offset}


## ROCK_VARIANTS mallas distintas hechas con la misma función.
func _variants(make: Callable) -> Array:
	var meshes := []
	for n in ROCK_VARIANTS:
		meshes.append(make.call())
	return meshes


## Esfera de pocas caras con los vértices movidos al azar y normales planas.
func _jagged(sphere: SphereMesh, amount: float) -> Mesh:
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Los vértices repetidos en la costura se mueven igual para no abrir huecos.
	var offsets := {}
	for i in vertices.size():
		var key := vertices[i].snapped(Vector3.ONE * 0.001)
		if not offsets.has(key):
			offsets[key] = 1.0 + deco_rng.randf_range(-amount, amount)
		vertices[i] *= offsets[key]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for index in indices:
		st.add_vertex(vertices[index])
	st.generate_normals()
	return st.commit()


func _low_poly_rock() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.2
	sphere.radial_segments = 7
	sphere.rings = 4
	return _jagged(sphere, 0.25)


func _bush() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 0.9
	sphere.radial_segments = 6
	sphere.rings = 3
	return _jagged(sphere, 0.2)


## Grupo de tres a cinco prismas inclinados.
func _crystal() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var count := deco_rng.randi_range(3, 5)
	for n in count:
		var prism := CylinderMesh.new()
		prism.top_radius = 0.0
		prism.bottom_radius = deco_rng.randf_range(0.15, 0.3)
		prism.height = deco_rng.randf_range(0.8, 1.7) if n > 0 else 1.7
		prism.radial_segments = 4
		var basis := Basis.from_euler(Vector3(deco_rng.randf_range(-0.4, 0.4), deco_rng.randf_range(0.0, TAU), deco_rng.randf_range(-0.4, 0.4)))
		if n == 0:
			basis = Basis.IDENTITY
		var base := Vector3(deco_rng.randf_range(-0.25, 0.25), 0.0, deco_rng.randf_range(-0.25, 0.25)) if n > 0 else Vector3.ZERO
		# El cilindro está centrado: se sube media altura para apoyarlo en el suelo
		# y se baja 0.8 porque el nodo ya lo sube esa distancia.
		var xform := Transform3D(basis, base + Vector3(0, -0.8, 0)) * Transform3D(Basis.IDENTITY, Vector3(0, prism.height / 2.0, 0))
		st.append_from(prism, 0, xform)
	st.generate_normals()
	return st.commit()


func _ice_slab() -> Mesh:
	var slab := BoxMesh.new()
	slab.size = Vector3(deco_rng.randf_range(1.3, 1.7), deco_rng.randf_range(0.3, 0.45), deco_rng.randf_range(1.3, 1.7))
	return slab


func _sphere_shape(radius: float) -> Shape3D:
	var shape := SphereShape3D.new()
	shape.radius = radius
	return shape


func _box_shape(size: Vector3) -> Shape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape
