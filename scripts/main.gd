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

const WORLD_SIZE := 160.0
const GRID := 64 # cuadros por lado del terreno
const HEIGHT := 6.0
const RESOURCE_COUNTS := {"hierro": 40, "silicio": 25, "hielo": 25, "cobre": 20}
const PLANT_COUNT := 80
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
var water_area: Area3D
# Bloques de hielo y, para cada uno, en qué punto del deshielo empieza a fundirse.
var ice_nodes: Array[ResourceNode] = []
var _melt_start := {}
var _water_level := WATER_LOW
var _deshielo_explained := false
var player: CharacterBody3D
var terrain: StaticBody3D
var placer: Node3D
var modules: Array[Module] = []
var _shelter_explained := false

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
		spawn_machine(m)
	for m in Game.modules:
		spawn_module(m)
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
	var sky := sky_colors.sample(t)
	var horizon := sky.lightened(0.35).lerp(Color(0.9, 0.6, 0.4), _dusk() * 0.6)
	var night_sky := Color(0.02, 0.025, 0.06)
	sky_material.sky_top_color = sky.lerp(night_sky, night * 0.95)
	sky_material.sky_horizon_color = horizon.lerp(night_sky.lightened(0.08), night * 0.9)
	sky_material.ground_horizon_color = sky_material.sky_horizon_color
	sky_material.ground_bottom_color = sky_material.sky_horizon_color.darkened(0.5)
	environment.fog_light_color = sky_material.sky_horizon_color
	# Con más presión la atmósfera es más densa: el aire se ve.
	environment.fog_density = lerpf(0.004, 0.009, Game.pressure / 100.0)
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
		var f := clampf((melt - float(_melt_start[node])) / MELT_TIME, 0.0, 1.0)
		if node.position.y < water.position.y - 0.1:
			f = 1.0
		node.set_melt(f)


## 1 cuando el sol está en el horizonte (amanecer y atardecer), 0 lejos de él.
func _dusk() -> float:
	return clampf(1.0 - absf(Game.sun_height()) * 4.0, 0.0, 1.0)


func height_at(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * HEIGHT


## Altura del terreno tal como se dibuja: el triángulo de la malla que
## contiene el punto. height_at da la del ruido, que en las lomas queda
## hasta medio metro por encima y deja los objetos flotando.
func surface_height(x: float, z: float) -> float:
	var step := WORLD_SIZE / GRID
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
	terrain = body


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
			node.scale = Vector3.ONE * RESOURCE_SCALE
			add_child(node)
			if type == "hielo":
				ice_nodes.append(node)
	_assign_melt_order()


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


func spawn_module(data: Dictionary) -> void:
	var module := Module.new()
	module.setup(data)
	module.position = Vector3(float(data["x"]), float(data["y"]), float(data["z"]))
	module.rotation.y = float(data["rot"])
	add_child(module)
	# Los lados pegados a otro módulo se abren en los dos para unirlos.
	for other in modules:
		if _adjacent(module, other):
			module.set_open(module.side_towards(other.global_position), true)
			other.set_open(other.side_towards(module.global_position), true)
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
	if not (target is Node and target.has_meta("module")):
		return {}
	var module: Module = target.get_meta("module")
	if target.has_meta("side"):
		var side: int = target.get_meta("side")
		var fitting := String(module.sides[side])
		if fitting != "pared" and not module.open[side]:
			# La pared con la puerta o ventana: se quita solo esa pieza.
			var wall: Node3D = target
			while wall.get_parent() != module:
				wall = wall.get_parent()
			return {"name": Game.RECIPES[fitting]["name"], "node": wall, "refund": Game.RECIPES[fitting]["cost"]}
	var info := {"name": Game.RECIPES["modulo"]["name"], "node": module}
	for child in get_children():
		if child is Machine and module.contains(child.global_position + Vector3(0, 0.3, 0)):
			info["reason"] = "saca antes lo que hay dentro"
			return info
	# Se devuelven también las puertas y ventanas que tenga.
	var refund: Dictionary = Game.RECIPES["modulo"]["cost"].duplicate()
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
			other.set_open(other.side_towards(module.global_position), false)
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
	if stage >= 3 and plants.get_child_count() == 0:
		_spawn_plants()
		plants.visible = true


## Mensajes seguidos al llegar al Deshielo, para que se entienda qué cambia.
func _explain_deshielo() -> void:
	for text in [
			"El hielo empieza a derretirse y se forman lagos en los valles.",
			"Recoge agua en la orilla y craftea semillas de musgo (Tab).",
			"Planta musgo fuera y monta bancales en la base: la biomasa sube el índice."]:
		await get_tree().create_timer(Hud.MESSAGE_TIME + 0.5).timeout
		Game.message.emit(text)


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
