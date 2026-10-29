extends Node3D
## Construye el mundo del prototipo: terreno low poly, recursos, jugador,
## interfaz y los cambios visuales del planeta según la terraformación.

const ResourceNode := preload("res://scripts/resource_node.gd")
const Machine := preload("res://scripts/machine.gd")
const Player := preload("res://scripts/player.gd")
const Hud := preload("res://scripts/hud.gd")
const Menu := preload("res://scripts/menu.gd")
const Placer := preload("res://scripts/placer.gd")
const Module := preload("res://scripts/module.gd")
const WaterBody := preload("res://scripts/water_body.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Rover := preload("res://scripts/rover.gd")

const WORLD_SIZE := Terrain.WORLD_SIZE
# Depósitos de la zona del principio; el resto del mapa tiene los suyos por trozos.
const RESOURCE_COUNTS := {"hierro": 40, "silicio": 25, "hielo": 25, "cobre": 20}
const RESOURCE_SCALE := 0.55 # tamaño de los recursos recogibles (malla y colisión)
const STAR_COUNT := 400
const ROCK_VARIANTS := 4 # formas distintas de cada tipo de roca
# Deshielo: los lagos suben de WATER_LOW a WATER_HIGH metros entre el índice
# del Deshielo y el 100 %, sin pasar de WATER_SPEED metros por segundo.
const WATER_LOW := -3.4
const WATER_HIGH := -1.0
const WATER_SPEED := 0.05
# El hielo se derrite del todo entre el inicio del Deshielo y este índice.
const MELT_END := 80.0
const MELT_TIME := 0.25 # parte del Deshielo que tarda en derretirse cada bloque
const ICE_KEPT := 0.25 # parte del hielo, la de los sitios más altos, que no se derrite
# Lluvias: nubes que pasan sobre el jugador y gotas a su alrededor.
const CLOUD_COUNT := 45
const CLOUD_SPREAD := 350.0 # metros a cada lado del jugador
const CLOUD_HEIGHT := Vector2(110.0, 150.0)
const CLOUD_WIND := Vector3(3.0, 0.0, 1.2) # metros por segundo
const RAIN_GRAY := Color(0.42, 0.45, 0.5)

var rng := RandomNumberGenerator.new()
# Aparte de rng para que los detalles visuales no muevan los recursos de sitio.
var deco_rng := RandomNumberGenerator.new()
var environment: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var stars: MeshInstance3D
var star_material: StandardMaterial3D
var water: MeshInstance3D
var water_area: Area3D
# Bloques de hielo y, para cada uno, en qué punto del deshielo empieza a fundirse.
var ice_nodes: Array[ResourceNode] = []
var _melt_start := {}
var _water_level := WATER_LOW
var _deshielo_explained := false
var clouds: Node3D
var cloud_material: StandardMaterial3D
var _cloud_drift := Vector3.ZERO
var rain_drops: CPUParticles3D
var player: CharacterBody3D
var land: Terrain
var terrain: StaticBody3D # el cuerpo de todo el suelo
# Malla, material, forma y altura de cada tipo de depósito.
var resource_defs := {}
var placer: Node3D
var modules: Array[Module] = []
var _shelter_explained := false

var sky_colors := Gradient.new()
var ground_colors := Gradient.new()


func _ready() -> void:
	rng.seed = 42
	deco_rng.seed = 99
	var loaded := Game.load_game()
	_setup_gradients()
	_build_environment()
	_build_water()
	_build_clouds()
	_build_rain()
	land = Terrain.new()
	land.world = self
	# Primero los depósitos: los trozos del terreno también los usan.
	_spawn_resources()
	_build_terrain()
	for m in Game.machines:
		spawn_machine(m)
	for m in Game.modules:
		spawn_module(m)
	for v in Game.vehicles:
		spawn_vehicle(v)
	_spawn_player()
	placer = Placer.new()
	placer.world = self
	placer.terrain = terrain
	placer.player = player
	add_child(placer)
	var hud := Hud.new()
	add_child(hud)
	var menu := Menu.new()
	add_child(menu)
	menu.opened.connect(hud.on_menu_opened)
	menu.closed.connect(hud.on_menu_closed)
	Game.place_requested.connect(_on_place_requested)
	Game.tool_changed.connect(_on_tool_changed)
	Game.stage_changed.connect(_on_stage_changed)
	Game.stage_changed.connect(_on_stage_reached)
	if loaded:
		_on_stage_changed(Game.stage)
	# Tras pulsar "Nueva partida" se entra directamente a jugar.
	if Game.skip_title:
		Game.skip_title = false
	else:
		menu.open_title(loaded)


func _process(delta: float) -> void:
	_update_shelter()
	var t := Game.terraform_index() / 100.0
	# 1 de día, 0 de noche, con una transición suave alrededor del horizonte.
	var daylight := clampf(Game.sun_height() * 3.0 + 0.5, 0.0, 1.0)
	var night := 1.0 - daylight
	var rain := Game.rain()
	# Con lluvia el cielo se pone gris y se ve menos.
	var sky := sky_colors.sample(t).lerp(RAIN_GRAY, rain * 0.7)
	var horizon := sky.lightened(0.35).lerp(Color(0.9, 0.6, 0.4), _dusk() * 0.6)
	var night_sky := Color(0.02, 0.025, 0.06)
	sky_material.sky_top_color = sky.lerp(night_sky, night * 0.95)
	sky_material.sky_horizon_color = horizon.lerp(night_sky.lightened(0.08), night * 0.9)
	sky_material.ground_horizon_color = sky_material.sky_horizon_color
	sky_material.ground_bottom_color = sky_material.sky_horizon_color.darkened(0.5)
	environment.fog_light_color = sky_material.sky_horizon_color
	# Con más presión la atmósfera es más densa: el aire se ve.
	environment.fog_density = lerpf(0.004, 0.009, Game.pressure / 100.0) + rain * 0.01
	# De noche queda algo de luz azulada para que se vea el terreno.
	environment.ambient_light_color = sky.lightened(0.3).lerp(Color(0.25, 0.3, 0.5), night * 0.8)
	environment.ambient_light_energy = lerpf(0.6, 0.35, night)
	land.material.set_shader_parameter("tint", ground_colors.sample(t))
	sun.light_energy = lerpf(0.6, 1.2, t) * daylight * (1.0 - rain * 0.6)
	sun.light_color = Color.WHITE.lerp(Color(1.0, 0.7, 0.45), _dusk())
	moon.light_energy = 0.25 * night
	# Las estrellas se apagan a medida que la atmósfera se espesa.
	star_material.albedo_color.a = night * lerpf(1.0, 0.5, t)
	stars.visible = night > 0.01
	stars.global_position = player.global_position
	# El borde del mapa es un muro de montañas; esto es por si se trepa.
	var limit := WORLD_SIZE / 2.0 - 5.0
	player.global_position.x = clampf(player.global_position.x, -limit, limit)
	player.global_position.z = clampf(player.global_position.z, -limit, limit)
	sun.rotation_degrees.x = -10.0 - 70.0 * maxf(Game.sun_height(), 0.0)
	sun.rotation_degrees.y = 30.0 + Game.time_of_day * 360.0
	if clouds.visible:
		_update_clouds(delta, daylight, rain)
	rain_drops.global_position = player.global_position + Vector3(0, 14, 0)
	# Bajo techo no llueve; las gotas no saben de techos y se esconden.
	rain_drops.emitting = rain > 0.2
	rain_drops.visible = not Game.sheltered
	if water.visible:
		_water_level = move_toward(_water_level, _target_water_level(), WATER_SPEED * delta)
		water.position.y = _water_level
		_update_melting()


## Progreso del Deshielo según el índice: 0 al empezar, 1 en el índice dado.
func _thaw(end: float) -> float:
	var start := float(Game.STAGES[2]["threshold"])
	return clampf((Game.terraform_index() - start) / (end - start), 0.0, 1.0)


func _target_water_level() -> float:
	return lerpf(WATER_LOW, WATER_HIGH, _thaw(100.0))


## Metros de agua sobre el punto, o 0 si no hay agua encima.
func water_depth(pos: Vector3) -> float:
	if not water.visible:
		return 0.0
	return maxf(0.0, water.position.y - pos.y)


## Encoge los bloques de hielo según avanza el Deshielo; los que quedan bajo
## el agua o terminan de fundirse desaparecen.
func _update_melting() -> void:
	var melt := _thaw(MELT_END)
	for node in ice_nodes:
		if not node.is_inside_tree():
			continue
		var f := clampf((melt - float(_melt_start[node])) / MELT_TIME, 0.0, 1.0)
		if node.position.y < water.position.y - 0.1:
			f = 1.0
		node.set_melt(f)


## 1 cuando el sol está en el horizonte (amanecer y atardecer), 0 lejos de él.
func _dusk() -> float:
	return clampf(1.0 - absf(Game.sun_height()) * 4.0, 0.0, 1.0)


func height_at(x: float, z: float) -> float:
	return land.height_at(x, z)


## Altura del terreno tal como se dibuja: el triángulo de la malla que
## contiene el punto. height_at da la del ruido, que en las lomas queda
## hasta medio metro por encima y deja los objetos flotando.
func surface_height(x: float, z: float) -> float:
	var step := Terrain.STEP
	var half := WORLD_SIZE / 2.0
	var x0 := -half + floorf((x + half) / step) * step
	var z0 := -half + floorf((z + half) / step) * step
	var u := (x - x0) / step
	var v := (z - z0) / step
	var ha := height_at(x0, z0)
	var hb := height_at(x0 + step, z0)
	var hc := height_at(x0, z0 + step)
	var hd := height_at(x0 + step, z0 + step)
	# Cada cuadro se parte en los triángulos (a, b, c) y (b, d, c).
	if u + v <= 1.0:
		return ha + (hb - ha) * u + (hc - ha) * v
	return hd + (hc - hd) * (1.0 - u) + (hb - hd) * (1.0 - v)


func _setup_gradients() -> void:
	# Desde las Lluvias (75 %) el cielo ya es azul de verdad.
	sky_colors.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 0.75, 1.0])
	sky_colors.colors = PackedColorArray([
		Color(0.04, 0.03, 0.06), Color(0.12, 0.16, 0.32),
		Color(0.3, 0.45, 0.7), Color(0.3, 0.55, 0.9), Color(0.38, 0.65, 0.97)])
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


## Nubes low poly: varias esferas aplastadas juntas. Siguen al jugador
## y dan la vuelta al salir de la zona, así siempre hay cielo cubierto.
func _build_clouds() -> void:
	clouds = Node3D.new()
	clouds.visible = false
	add_child(clouds)
	cloud_material = StandardMaterial3D.new()
	cloud_material.albedo_color = Color.WHITE
	cloud_material.roughness = 1.0
	# Con la niebla se volverían del color del horizonte a esta distancia.
	cloud_material.disable_fog = true
	# Algo de luz propia para que la cara de abajo no se vea como una roca.
	cloud_material.emission_enabled = true
	for n in CLOUD_COUNT:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		var puffs := deco_rng.randi_range(3, 6)
		for k in puffs:
			var puff := SphereMesh.new()
			puff.radius = deco_rng.randf_range(9.0, 16.0)
			puff.height = puff.radius * deco_rng.randf_range(0.8, 1.1)
			puff.radial_segments = 7
			puff.rings = 3
			var offset := Vector3(deco_rng.randf_range(-20, 20), deco_rng.randf_range(-1.5, 2.5), deco_rng.randf_range(-10, 10))
			st.append_from(puff, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(1.4, 0.45, 1.0)), offset))
		st.generate_normals()
		var cloud := MeshInstance3D.new()
		cloud.mesh = st.commit()
		cloud.material_override = cloud_material
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.rotation.y = deco_rng.randf_range(0.0, TAU)
		cloud.set_meta("base", Vector3(deco_rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD),
				deco_rng.randf_range(CLOUD_HEIGHT.x, CLOUD_HEIGHT.y), deco_rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD)))
		clouds.add_child(cloud)


func _update_clouds(delta: float, daylight: float, rain: float) -> void:
	_cloud_drift += CLOUD_WIND * delta
	var center := player.global_position
	var size := CLOUD_SPREAD * 2.0
	for cloud in clouds.get_children():
		var p: Vector3 = cloud.get_meta("base") + _cloud_drift
		# Posición relativa al jugador, dentro de la zona de nubes.
		var x := fposmod(p.x - center.x + CLOUD_SPREAD, size) - CLOUD_SPREAD
		var z := fposmod(p.z - center.z + CLOUD_SPREAD, size) - CLOUD_SPREAD
		cloud.global_position = Vector3(center.x + x, p.y, center.z + z)
	var color := Color.WHITE.lerp(Color(0.5, 0.52, 0.56), rain).lerp(Color(1.0, 0.75, 0.6), _dusk() * 0.5)
	color = color.lerp(Color(0.08, 0.09, 0.13), 1.0 - daylight)
	cloud_material.albedo_color = color
	cloud_material.emission = color * 0.55


## Gotas de lluvia: rayitas que caen en una caja sobre el jugador.
func _build_rain() -> void:
	rain_drops = CPUParticles3D.new()
	rain_drops.amount = 900
	rain_drops.lifetime = 1.6
	rain_drops.local_coords = false
	rain_drops.emitting = false
	rain_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain_drops.emission_box_extents = Vector3(22, 2, 22)
	rain_drops.direction = Vector3(0.1, -1, 0.05)
	rain_drops.spread = 2.0
	rain_drops.gravity = Vector3.ZERO
	rain_drops.initial_velocity_min = 15.0
	rain_drops.initial_velocity_max = 18.0
	var drop := BoxMesh.new()
	drop.size = Vector3(0.02, 0.55, 0.02)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.75, 0.82, 0.95, 0.45)
	drop.material = material
	rain_drops.mesh = drop
	rain_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Se mueve con el jugador: la caja de visibilidad debe cubrir la caída.
	rain_drops.visibility_aabb = AABB(Vector3(-30, -40, -30), Vector3(60, 50, 60))
	add_child(rain_drops)


func _build_terrain() -> void:
	add_child(land)
	var around := Vector3.ZERO
	if Game.player_position != null:
		around = Game.player_position
	land.build(around)
	terrain = land.body


func _build_water() -> void:
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_SIZE, WORLD_SIZE)
	water.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.32, 0.6, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.1
	material.metallic_specular = 1.0
	water.material_override = material
	water.position.y = WATER_LOW
	water.visible = false
	add_child(water)
	# Volumen bajo la superficie: lo que el rayo de la herramienta toca para
	# recoger agua. Es un Area3D, así que no frena al jugador.
	water_area = WaterBody.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WORLD_SIZE, 10.0, WORLD_SIZE)
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position.y = -5.0
	water_area.add_child(collision)
	water_area.monitoring = false
	water.add_child(water_area)


func _spawn_resources() -> void:
	resource_defs = {
		"hierro": _resource_def(_variants(_low_poly_rock), Color(0.55, 0.35, 0.25), _sphere_shape(0.8), Vector3(0, 0.4, 0)),
		"silicio": _resource_def(_variants(_crystal), Color(0.55, 0.85, 0.95), _box_shape(Vector3(0.9, 1.6, 0.9)), Vector3(0, 0.8, 0)),
		"hielo": _resource_def(_variants(_ice_slab), Color(0.85, 0.95, 1.0), _box_shape(Vector3(1.6, 0.4, 1.6)), Vector3(0, 0.2, 0)),
		"cobre": _resource_def(_variants(_low_poly_rock), Color(0.3, 0.65, 0.5), _sphere_shape(0.8), Vector3(0, 0.4, 0)),
	}
	resource_defs["silicio"]["material"].emission_enabled = true
	resource_defs["silicio"]["material"].emission = Color(0.1, 0.25, 0.3)
	resource_defs["silicio"]["material"].roughness = 0.2
	resource_defs["hielo"]["material"].roughness = 0.15
	for type in RESOURCE_COUNTS:
		for n in int(RESOURCE_COUNTS[type]):
			var pos := _random_point(8.0)
			var node := make_resource(type)
			node.position = pos
			node.rotation.y = rng.randf_range(0.0, TAU)
			add_child(node)
			if type == "hielo":
				ice_nodes.append(node)
	_assign_melt_order()


## Depósito nuevo del tipo dado, aún sin colocar.
func make_resource(type: String) -> ResourceNode:
	var def: Dictionary = resource_defs[type]
	var meshes: Array = def["meshes"]
	var node := ResourceNode.new()
	node.setup(type, meshes[deco_rng.randi() % meshes.size()], def["material"], def["shape"], def["offset"])
	node.scale = Vector3.ONE * RESOURCE_SCALE
	return node


## Bloque de hielo de un trozo del terreno que empieza a fundirse en "start"
## (de 0 a 1 del deshielo; INF si no se funde).
func add_ice(node: ResourceNode, start: float) -> void:
	ice_nodes.append(node)
	_melt_start[node] = start


func remove_ice(node: ResourceNode) -> void:
	ice_nodes.erase(node)
	_melt_start.erase(node)


## Los bloques más bajos se funden antes; la parte más alta no se funde nunca
## para que siga habiendo hielo en las cumbres.
func _assign_melt_order() -> void:
	var sorted := ice_nodes.duplicate()
	sorted.sort_custom(func(a, b): return a.position.y < b.position.y)
	var melting := int(sorted.size() * (1.0 - ICE_KEPT))
	for i in sorted.size():
		var start := INF
		if i < melting:
			start = (1.0 - MELT_TIME) * i / maxf(1.0, melting - 1)
		_melt_start[sorted[i]] = start


func _spawn_player() -> void:
	var base := Vector3(0.0, surface_height(0.0, 0.0) + 1.0, 0.0)
	player = Player.new()
	player.world = self
	player.position = base
	if Game.player_position != null:
		player.position = Game.player_position
	add_child(player)
	player.spawn_point = base # si se ahoga, vuelve a la base y no al punto guardado
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_place_requested(kind: String) -> void:
	placer.start(kind)


func _on_tool_changed(mode: String) -> void:
	if mode != "construir":
		placer.cancel()


## Crea una construcción a partir de su entrada de Game.machines.
func spawn_machine(data: Dictionary) -> Machine:
	var machine := Machine.new()
	machine.data = data
	machine.setup(String(data["kind"]))
	machine.position = Vector3(float(data["x"]), float(data["y"]), float(data["z"]))
	machine.rotation.y = float(data["rot"])
	add_child(machine)
	return machine


## Crea un vehículo a partir de su entrada de Game.vehicles. Aparece quieto
## (congelado) hasta que alguien se sube.
func spawn_vehicle(data: Dictionary) -> Rover:
	var rover := Rover.new()
	rover.data = data
	rover.setup(String(data["kind"]))
	rover.position = Vector3(float(data["x"]), float(data["y"]), float(data["z"]))
	rover.rotation.y = float(data["rot"])
	add_child(rover)
	return rover


func spawn_module(data: Dictionary) -> void:
	var module := Module.new()
	module.setup(data)
	module.position = Vector3(float(data["x"]), float(data["y"]), float(data["z"]))
	module.rotation.y = float(data["rot"])
	add_child(module)
	# Los lados pegados a otro módulo se abren en los dos para unirlos, si
	# los dos tienen boca por ese lado. Con un pasillo el hueco es estrecho.
	for other in modules:
		if _adjacent(module, other):
			var side := module.side_towards(other.global_position)
			var other_side := other.side_towards(module.global_position)
			if module.has_port(side) and other.has_port(other_side):
				var join := "narrow" if module.is_corridor() or other.is_corridor() else "full"
				module.set_open(side, join)
				other.set_open(other_side, join)
	modules.append(module)


func _adjacent(a: Module, b: Module) -> bool:
	var offset := b.global_position - a.global_position
	if absf(offset.y) > 0.05:
		return false
	# Uno justo al lado del otro, no en diagonal.
	var local := a.global_basis.inverse() * offset
	var side_by_side := (absf(absf(local.x) - Module.SIZE) < 0.05 and absf(local.z) < 0.05) \
			or (absf(absf(local.z) - Module.SIZE) < 0.05 and absf(local.x) < 0.05)
	if not side_by_side:
		return false
	# Tienen que estar alineados: girados lo mismo o un múltiplo de 90 grados.
	var turn := fposmod(a.rotation.y - b.rotation.y, PI / 2.0)
	return minf(turn, PI / 2.0 - turn) < 0.02


## Qué pasaría al desmontar lo que se apunta: {"name", "node" (lo que se
## ilumina), "refund"} o, si no se puede, {"name", "node", "reason"}.
## Vacío si no es algo construido.
func dismantle_info(target: Object) -> Dictionary:
	if target is Machine:
		var machine := target as Machine
		return {"name": Game.RECIPES[machine.kind]["name"], "node": machine, "refund": Game.RECIPES[machine.kind]["cost"]}
	if target is Rover:
		var rover := target as Rover
		return {"name": Game.RECIPES[rover.kind]["name"], "node": rover, "refund": Game.RECIPES[rover.kind]["cost"]}
	if not (target is Node and target.has_meta("module")):
		return {}
	var module: Module = target.get_meta("module")
	if target.has_meta("side"):
		var side: int = target.get_meta("side")
		var fitting := String(module.sides[side])
		if fitting != "pared" and module.open[side] == "":
			# La pared con la puerta o ventana: se quita solo esa pieza.
			var wall: Node3D = target
			while wall.get_parent() != module:
				wall = wall.get_parent()
			return {"name": Game.RECIPES[fitting]["name"], "node": wall, "refund": Game.RECIPES[fitting]["cost"]}
	var info := {"name": Game.RECIPES[module.kind]["name"], "node": module}
	for child in get_children():
		if child is Machine and module.contains(child.global_position + Vector3(0, 0.3, 0)):
			info["reason"] = "saca antes lo que hay dentro"
			return info
	# Se devuelven también las puertas y ventanas que tenga.
	var refund: Dictionary = Game.RECIPES[module.kind]["cost"].duplicate()
	for fitting in module.sides:
		if fitting != "pared":
			var cost: Dictionary = Game.RECIPES[fitting]["cost"]
			for res in cost:
				refund[res] = int(refund.get(res, 0)) + int(cost[res])
	info["refund"] = refund
	return info


## Desmonta lo que se apunta y devuelve sus materiales. Devuelve true si se ha
## desmontado algo.
func dismantle(target: Object) -> bool:
	var info := dismantle_info(target)
	if info.is_empty():
		return false
	if info.has("reason"):
		Sfx.play("alarma", 0.0, -12.0)
		Game.message.emit("No se puede desmontar: %s." % info["reason"])
		return false
	var node: Node3D = info["node"]
	if node is Machine:
		var machine := node as Machine
		if machine.is_storage():
			# Lo guardado en la taquilla vuelve a la mochila.
			Game.refund(machine.items())
		Game.unregister_machine(machine.data)
		machine.queue_free()
	elif node is Rover:
		var rover := node as Rover
		# Lo del maletero vuelve a la mochila.
		Game.refund(rover.items())
		Game.vehicles.erase(rover.data)
		rover.queue_free()
	elif node is Module:
		_remove_module(node as Module)
	else:
		var module: Module = target.get_meta("module")
		module.set_side(int(target.get_meta("side")), "pared")
	Game.refund(info["refund"])
	Sfx.play("desmontar")
	Game.message.emit("+%s" % Game.cost_text(info["refund"]))
	return true


func _remove_module(module: Module) -> void:
	modules.erase(module)
	for i in Game.modules.size():
		if is_same(Game.modules[i], module.data):
			Game.modules.remove_at(i)
			break
	# Los vecinos vuelven a tener pared en el lado que compartían.
	for other in modules:
		if _adjacent(module, other):
			other.set_open(other.side_towards(module.global_position), "")
	module.queue_free()


func _update_shelter() -> void:
	var inside := false
	for module in modules:
		if module.contains(player.global_position + Vector3(0, 0.5, 0)):
			inside = true
			break
	if inside and not Game.sheltered and not _shelter_explained:
		_shelter_explained = true
		Game.message.emit("Estás a cubierto: aquí recuperas oxígeno y no pasas frío.")
	Game.sheltered = inside


func _on_stage_changed(stage: int) -> void:
	if stage >= 2:
		if not water.visible:
			# Al cargar una partida el agua ya está a su nivel.
			_water_level = _target_water_level()
			water.position.y = _water_level
			water.visible = true
			_update_melting()
		if not _deshielo_explained and Game.biomass <= 0.0:
			_deshielo_explained = true
			_explain_deshielo()
	if stage >= Game.RAIN_STAGE:
		# Con las lluvias crecen los bosques y aparecen las nubes.
		land.plants_visible = true
		clouds.visible = true


## Solo al llegar a una etapa jugando, no al cargar la partida.
func _on_stage_reached(stage: int) -> void:
	if stage == Game.RAIN_STAGE:
		for text in [
				"Se forman nubes y empiezan a crecer bosques. Pronto lloverá.",
				"Con lluvia, el musgo y los árboles suben la biomasa el doble de rápido.",
				"Nuevas construcciones: colector de lluvia, plantón de árbol y criadero de insectos."]:
			await get_tree().create_timer(Hud.MESSAGE_TIME + 0.5).timeout
			Game.message.emit(text)


## Mensajes seguidos al llegar al Deshielo, para que se entienda qué cambia.
func _explain_deshielo() -> void:
	for text in [
			"El hielo empieza a derretirse y se forman lagos en los valles.",
			"Recoge agua en la orilla y fabrica semillas de musgo (Tab).",
			"Planta musgo fuera y monta bancales en la base: la biomasa sube el índice."]:
		await get_tree().create_timer(Hud.MESSAGE_TIME + 0.5).timeout
		Game.message.emit(text)


func _random_point(min_distance: float) -> Vector3:
	var limit := Terrain.START_AREA * 0.45
	var x := 0.0
	var z := 0.0
	while Vector2(x, z).length() < min_distance:
		x = rng.randf_range(-limit, limit)
		z = rng.randf_range(-limit, limit)
	return Vector3(x, surface_height(x, z), z)


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
