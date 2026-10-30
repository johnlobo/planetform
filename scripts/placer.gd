extends Node3D
## Modo de colocación: una silueta de lo que se va a construir sigue a la
## mirada del jugador, verde donde se puede y roja donde no. Clic izquierdo
## coloca, R o la rueda del ratón giran y clic derecho o Esc cancelan.
## Las máquinas van sobre el terreno o el suelo de la base, los módulos se
## encajan al lado de otro módulo y las puertas y ventanas van en sus paredes.

const Machine := preload("res://scripts/machine.gd")
const Module := preload("res://scripts/module.gd")
const Player := preload("res://scripts/player.gd")
const Rover := preload("res://scripts/rover.gd")

const REACH := 10.0 # metros desde la cámara
const MAX_SLOPE := 0.7 # con más desnivel entre las esquinas, se excava el suelo
# Lo más que se excava para encajar una construcción, en metros.
const DIG_MAX := 3.0
const ROTATE_STEP := PI / 12.0 # 15 grados por paso de rueda
const SPACING := 0.2 # holgura entre construcciones, en metros
const SNAP_DISTANCE := 3.0 # a menos de esto de un hueco junto a otro módulo, se pega a él

var world: Node3D # el nodo main: da la altura del terreno, el agua y los módulos
var terrain: CollisionObject3D
var player: Player

var _kind := ""
var _mode := "" # "building", "module", "fitting" o "vehicle", como en Game.RECIPES
var _ghost: Node3D
var _rotation := 0.0
var _valid := false
var _reason := ""
var _tinted_valid := false
# Pared elegida para una puerta o ventana.
var _target_module: Module
var _target_side := -1
# Terreno que hay que rebajar al colocar: {"xform", "size", "level"} o {}.
var _dig := {}
# Planta del módulo que se va a colocar (0 en el suelo).
var _level := 0
# Recurso del depósito sobre el que va el extractor.
var _deposit_type := ""
var _green := _ghost_material(Color(0.2, 1.0, 0.35, 0.45))
var _red := _ghost_material(Color(1.0, 0.2, 0.15, 0.45))
var _box := BoxShape3D.new()


func start(kind: String) -> void:
	cancel()
	_kind = kind
	_mode = String(Game.RECIPES[kind]["kind"])
	_rotation = 0.0
	match _mode:
		"building":
			var machine := Machine.new()
			machine.setup(kind)
			machine.make_ghost(_green)
			_ghost = machine
		"vehicle":
			var rover := Rover.new()
			rover.setup(kind)
			rover.make_ghost(_green)
			_ghost = rover
		"module":
			var module := Module.new()
			module.setup({"kind": kind}, true)
			_ghost = module
		"fitting":
			_ghost = Node3D.new()
			var hole := Module.opening_box(kind)
			var mesh := BoxMesh.new()
			mesh.size = hole.size + Vector3(0.1, 0.1, 0.1)
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.position = hole.get_center()
			_ghost.add_child(instance)
	add_child(_ghost)
	_tint(_ghost, _green)
	_tinted_valid = true
	Game.placing = true
	_update_ghost()


func cancel() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_kind = ""
	_target_module = null
	if Game.placing:
		Game.placing = false
		Game.hint = ""


func _input(event: InputEvent) -> void:
	if _ghost == null or Game.ui_open or get_tree().paused:
		return
	var handled := true
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					_confirm()
				else:
					handled = false # el jugador recaptura el ratón
			MOUSE_BUTTON_RIGHT:
				cancel()
			MOUSE_BUTTON_WHEEL_UP:
				_rotation += ROTATE_STEP
			MOUSE_BUTTON_WHEEL_DOWN:
				_rotation -= ROTATE_STEP
			_:
				handled = false
	elif event.is_action_pressed("rotate_building"):
		_rotation += PI / 4.0
	elif event.is_action_pressed("pause"):
		cancel()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if _ghost == null:
		return
	# Abrir el menú o morir cancela la colocación.
	if Game.ui_open or Game.dead:
		cancel()
		return
	_update_ghost()


func _update_ghost() -> void:
	var camera := player.camera
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z
	_dig = {}
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * REACH)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3 = hit["position"] if hit else from + forward * REACH
	match _mode:
		"building", "vehicle":
			_reason = _place_machine(point, hit)
		"module":
			_reason = _place_module(point, hit)
		"fitting":
			_reason = _place_fitting(hit)
	_valid = _reason == ""
	if _valid != _tinted_valid:
		_tint(_ghost, _green if _valid else _red)
		_tinted_valid = _valid
	var recipe_name: String = Game.RECIPES[_kind]["name"]
	if _valid:
		var keys := "clic colocar · clic derecho cancelar" if _mode == "fitting" else "clic colocar · R girar · clic derecho cancelar"
		Game.hint = "%s · %s" % [recipe_name, keys]
	else:
		Game.hint = "%s · %s" % [recipe_name, _reason]


## Coloca la silueta de una máquina y devuelve por qué no cabe, o "".
func _place_machine(point: Vector3, hit: Dictionary) -> String:
	var on_floor: bool = hit and hit["collider"].is_in_group("base_floor")
	if on_floor and _kind == "musgo":
		return "el musgo se planta fuera, en el suelo"
	if on_floor and Game.MACHINES.get(_kind, {}).get("outside", false):
		return "va fuera, al aire libre"
	if on_floor and _mode == "vehicle":
		return "el róver va fuera de la base"
	# En el techo de un módulo va lo de fuera (paneles, turbinas...) salvo las
	# plantas, que necesitan tierra.
	var on_roof: bool = hit and hit["collider"].is_in_group("base_roof") and hit["normal"].y > 0.7
	if on_roof and (Game.MACHINES.get(_kind, {}).get("plant", false) or _mode == "vehicle"):
		return "no se puede poner en el techo"
	var exclude := [terrain.get_rid()]
	# El extractor se encaja encima del depósito que se mira.
	var deposit: Node3D = null
	if Game.MACHINES.get(_kind, {}).get("produces", "") == "deposit":
		if hit and hit["collider"].is_in_group("deposit"):
			deposit = hit["collider"]
			point = deposit.global_position
			exclude.append(deposit.get_rid())
			_deposit_type = String(deposit.get("resource_type"))
	if not on_floor and not on_roof:
		point.y = world.surface_height(point.x, point.z)
	var rot := player.rotation.y + _rotation
	_ghost.global_position = point
	_ghost.rotation.y = rot
	if hit.is_empty():
		return "demasiado lejos"
	if Game.MACHINES.get(_kind, {}).get("inside", false) and not on_floor:
		return "va dentro de la base"
	if Game.MACHINES.get(_kind, {}).get("produces", "") == "deposit" and deposit == null:
		return "apunta a un depósito de recursos"
	var common := _check_area(point)
	if common != "":
		return common
	var size: Vector3 = _ghost.get("footprint")
	var basis := Basis(Vector3.UP, rot)
	if on_floor or on_roof:
		# El suelo y el techo de la base son planos: solo hace falta que no choque.
		exclude.append(hit["collider"].get_rid())
	else:
		var heights := _corner_heights(point, basis, size)
		if heights.y - heights.x > MAX_SLOPE:
			# En cuesta se pone a la altura de la esquina más baja y se excava
			# lo que sobresale.
			if heights.y - heights.x > DIG_MAX:
				return "terreno demasiado inclinado"
			point.y = heights.x
			_ghost.global_position = point
			_dig = {"xform": Transform3D(basis, point), "size": Vector2(size.x, size.z) + Vector2(SPACING, SPACING), "level": point.y - 0.02}
	# Choca con otra construcción, un recurso o el propio jugador.
	_box.size = size + Vector3(SPACING, 0.0, SPACING)
	if _overlaps(Transform3D(basis, point + Vector3(0, size.y / 2.0 + 0.05, 0)), exclude):
		return "no hay sitio"
	return ""


## Coloca la silueta de un módulo. Si queda cerca del lado libre de otro
## módulo, o se está mirando uno, se pega a él como un imán; si no, va
## suelto sobre el terreno.
func _place_module(point: Vector3, hit: Dictionary) -> String:
	var looked: Module = _module_of(hit["collider"]) if hit else null
	# Mirando el techo de un módulo, se pone otro encima.
	if looked and hit["collider"].is_in_group("base_roof"):
		return _place_on_top(looked)
	if looked == null:
		# Suelto queda delante del punto que se mira, no encima del jugador.
		var ahead := -player.global_transform.basis.z
		point += Vector3(ahead.x, 0, ahead.z).normalized() * Module.SIZE / 2.0
	var snap := _snap_cell(point, looked)
	var xform: Transform3D
	var exclude := [terrain.get_rid()]
	if not snap.is_empty():
		xform = snap["xform"]
		_set_ghost_level(int(snap["level"]))
		_ghost.global_transform = xform
		# Las paredes y rampas de los módulos vecinos no cuentan como estorbo.
		for m in world.modules:
			if m.global_position.distance_to(xform.origin) < Module.SIZE + 0.1:
				for child in m.get_children():
					if child is CollisionObject3D:
						exclude.append(child.get_rid())
		var heights := _corner_heights(xform.origin, xform.basis, Vector3(Module.SIZE, 0, Module.SIZE))
		# Lo que sobresale se excava al colocarlo.
		if heights.y > xform.origin.y + DIG_MAX:
			return "el terreno es demasiado alto"
		# Una planta de arriba puede quedar en el aire, como un puente.
		if _level == 0 and heights.x < xform.origin.y - Module.SKIRT:
			return "el terreno es demasiado bajo"
	else:
		_set_ghost_level(0)
		point.y = world.surface_height(point.x, point.z)
		var basis := Basis(Vector3.UP, player.rotation.y + _rotation)
		var heights := _corner_heights(point, basis, Vector3(Module.SIZE, 0, Module.SIZE))
		# El suelo queda a la altura de la esquina más alta y el zócalo tapa el resto.
		point.y = heights.y
		xform = Transform3D(basis, point)
		_ghost.global_transform = xform
		if hit.is_empty():
			return "demasiado lejos"
		if heights.y - heights.x > Module.SKIRT:
			return "terreno demasiado inclinado"
	var common := _check_area(xform.origin)
	if common != "":
		return common
	# Se excava también lo que asome entre las esquinas.
	_dig = {"xform": xform, "size": Vector2(Module.SIZE, Module.SIZE), "level": xform.origin.y - 0.02}
	var inner := Module.SIZE - 0.6
	_box.size = Vector3(inner, Module.HEIGHT, inner)
	var center := xform.origin + Vector3(0, Module.FLOOR + Module.HEIGHT / 2.0 + 0.1, 0)
	if _overlaps(Transform3D(xform.basis, center), exclude):
		return "no hay sitio"
	return ""


## Hueco libre junto a un módulo más cercano al punto: {"xform"} con la
## posición y el giro del módulo vecino, o {} si no hay ninguno a menos de
## SNAP_DISTANCE. Si se mira un módulo (looked), solo vale un hueco junto a
## él, aunque esté más lejos: así se elige planta cuando hay varias.
func _snap_cell(point: Vector3, looked: Module) -> Dictionary:
	var best := {}
	var best_distance := INF
	var always := looked != null
	for m in ([looked] if looked else world.modules):
		for i in 4:
			if m.open[i] != "" or not m.has_port(i):
				continue
			var cell: Vector3 = m.global_transform * (Module.side_direction(i) * Module.SIZE)
			# Puede haber un módulo en diagonal que ocupe ya ese hueco.
			var taken := false
			for other in world.modules:
				if other.global_position.distance_to(cell) < 1.0:
					taken = true
					break
			if taken:
				continue
			var d := Vector2(cell.x - point.x, cell.z - point.z).length()
			if d < best_distance:
				best_distance = d
				best = {"xform": Transform3D(m.global_basis, cell), "towards": m.global_position, "level": m.level}
	if best.is_empty() or (not always and best_distance > SNAP_DISTANCE):
		return {}
	# Se gira en pasos de 90 grados (R) y, si por ese lado no tiene boca, al
	# siguiente giro que sí la tenga.
	var xform: Transform3D = best["xform"]
	var start := roundi(_rotation / (PI / 2.0))
	var ports: Array = Module.PORTS[_kind]
	for k in 4:
		var basis := xform.basis * Basis(Vector3.UP, (start + k) * PI / 2.0)
		var towards: Vector3 = basis.inverse() * (best["towards"] - xform.origin)
		if ports.has(Module.side_of(towards)):
			return {"xform": Transform3D(basis, xform.origin), "level": best["level"]}
	return {}


## Silueta de un módulo encima de otro: mismo giro, una planta más arriba.
func _place_on_top(lower: Module) -> String:
	var xform := Transform3D(lower.global_basis, lower.global_position + Vector3.UP * Module.STOREY)
	_set_ghost_level(lower.level + 1)
	_ghost.global_transform = xform
	_dig = {}
	if _kind != "modulo" or lower.kind != "modulo":
		return "solo se apilan módulos de hábitat"
	if lower.above:
		return "ya tiene otro encima"
	var exclude := [terrain.get_rid()]
	for child in lower.get_children():
		if child is CollisionObject3D:
			exclude.append(child.get_rid())
	var inner := Module.SIZE - 0.6
	_box.size = Vector3(inner, Module.HEIGHT, inner)
	var center := xform.origin + Vector3(0, Module.FLOOR + Module.HEIGHT / 2.0 + 0.1, 0)
	if _overlaps(Transform3D(xform.basis, center), exclude):
		return "no hay sitio"
	return ""


func _set_ghost_level(level: int) -> void:
	_level = level
	var module := _ghost as Module
	if module and module.level != level:
		module.level = level
		module.rebuild()
		_tint(_ghost, _green if _tinted_valid else _red)


## Coloca la silueta de una puerta o ventana en la pared que se mira.
func _place_fitting(hit: Dictionary) -> String:
	_target_module = null
	_target_side = -1
	var collider: Object = hit["collider"] if hit else null
	var module := _module_of(collider)
	if _kind == "escalera":
		return _place_ladder(module)
	if module == null or not collider.has_meta("side"):
		_ghost.visible = false
		return "apunta a una pared de un módulo"
	_ghost.visible = true
	var side: int = collider.get_meta("side")
	# En los pasillos el hueco cambia de tamaño y de sitio.
	var hole := module.opening_for(_kind, side)
	var outline: MeshInstance3D = _ghost.get_child(0)
	(outline.mesh as BoxMesh).size = hole.size + Vector3(0.1, 0.1, 0.1)
	outline.position = hole.get_center()
	_ghost.global_transform = module.global_transform * Transform3D(Basis(Vector3.UP, -side * PI / 2.0), Vector3.ZERO)
	if String(module.sides[side]) != "pared":
		return "esa pared ya tiene %s" % ("puerta" if module.sides[side] == "puerta" else "ventana")

	_target_module = module
	_target_side = side
	return ""


## La escalera va siempre en la misma esquina del módulo que se mira.
func _place_ladder(module: Module) -> String:
	if module == null:
		_ghost.visible = false
		return "apunta a un módulo"
	_ghost.visible = true
	var top := Module.STOREY + Module.LADDER_TOP
	var c := (Module.HATCH_MIN + Module.HATCH_MAX) / 2.0
	var outline: MeshInstance3D = _ghost.get_child(0)
	(outline.mesh as BoxMesh).size = Vector3(Module.HATCH_MAX - Module.HATCH_MIN, top, Module.HATCH_MAX - Module.HATCH_MIN)
	outline.position = Vector3(c, top / 2.0, c)
	_ghost.global_transform = module.global_transform
	if module.is_corridor():
		return "va en un módulo de hábitat, no en un pasillo"
	if module.has_ladder():
		return "ya tiene escalera"
	_target_module = module
	return ""


## Comprobaciones comunes: dentro del mapa y fuera del agua.
func _check_area(point: Vector3) -> String:
	var limit: float = world.WORLD_SIZE * 0.48
	if absf(point.x) > limit or absf(point.z) > limit:
		return "fuera de la zona"
	if world.water.visible and point.y < world.water.position.y + 0.1:
		return "bajo el agua"
	return ""


## Altura del terreno más baja (x) y más alta (y) en las cuatro esquinas.
func _corner_heights(point: Vector3, basis: Basis, size: Vector3) -> Vector2:
	var lowest := INF
	var highest := -INF
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		var p: Vector3 = point + basis * (corner * size * 0.5)
		var h: float = world.surface_height(p.x, p.z)
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	return Vector2(lowest, highest)


func _overlaps(xform: Transform3D, exclude: Array) -> bool:
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = _box
	shape_query.transform = xform
	shape_query.exclude = exclude
	return not get_world_3d().direct_space_state.intersect_shape(shape_query, 1).is_empty()


func _module_of(collider: Object) -> Module:
	if collider and collider.has_meta("module"):
		return collider.get_meta("module") as Module
	return null


func _confirm() -> void:
	if not _valid:
		Sfx.play("alarma", 0.0, -12.0)
		Game.message.emit("Aquí no se puede construir: %s." % _reason)
		return
	var kind := _kind
	if not Game.pay(kind):
		Game.message.emit("Te faltan materiales.")
		cancel()
		return
	if not _dig.is_empty():
		world.land.dig(_dig["xform"], _dig["size"], _dig["level"])
	match _mode:
		"building":
			var pos := _ghost.global_position
			var rot := _ghost.rotation.y
			var data := Game.register_machine(kind, pos, rot)
			if Game.MACHINES[kind].get("produces", "") == "deposit":
				data["resource"] = _deposit_type
			world.spawn_machine(data).sprout()
		"vehicle":
			var pos := _ghost.global_position
			var data := {"kind": kind, "x": pos.x, "y": pos.y + 0.3, "z": pos.z, "rot": _ghost.rotation.y, "battery": Rover.BATTERY_MAX}
			Game.vehicles.append(data)
			world.spawn_vehicle(data).drop()
		"module":
			var pos := _ghost.global_position
			var data := {"kind": kind, "x": pos.x, "y": pos.y, "z": pos.z, "rot": _ghost.rotation.y, "sides": ["pared", "pared", "pared", "pared"]}
			if _level > 0:
				data["level"] = _level
			Game.modules.append(data)
			world.spawn_module(data)
		"fitting":
			if kind == "escalera":
				_target_module.set_ladder(true)
			else:
				_target_module.set_side(_target_side, kind)
	Sfx.play("colocar")
	# Las piezas de la base se suelen poner varias seguidas: se sigue
	# colocando mientras haya materiales.
	if _mode in ["module", "fitting"] and Game.can_craft(kind):
		_update_ghost()
	else:
		cancel()


## Pone el material a todas las mallas de la silueta.
static func _tint(node: Node, material: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.material_override = material
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tint(child, material)


static func _ghost_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_fog = true
	return material
