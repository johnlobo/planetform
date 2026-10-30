extends Node3D
## Módulo de hábitat prefabricado: una caja de 4 × 4 m con suelo, techo y
## cuatro paredes. Cada pared puede ser lisa, con puerta o con ventana, y se
## abre sola cuando hay otro módulo pegado a ese lado. Dentro el jugador
## está a cubierto: no pierde oxígeno ni pasa frío.
## Los pasillos ocupan la misma casilla de 4 × 4 m pero son un tubo estrecho
## que solo sale por algunos lados (sus "bocas"): recto, en L o en T.
## Encima del techo de un módulo se puede poner otro (una planta más) y, con
## una escalera, se sube por una trampilla al techo o a la planta de arriba.

const SIZE := 4.0
const HEIGHT := 3.0 # altura libre del interior
const WALL := 0.2
const FLOOR := 0.25
const ROOF := 0.25
const SKIRT := 3.5 # zócalo bajo el suelo para que no flote en las cuestas
const DOOR_SIZE := Vector2(1.4, 2.3)
const WINDOW_SIZE := Vector2(3.0, 1.8)
const WINDOW_BOTTOM := 0.7
const FRAME := 0.08 # grosor del marco de puertas y ventanas
const DOOR_RANGE := 2.5 # a esta distancia las hojas se abren solas
const DOOR_SPEED := 2.5 # recorrido por segundo (0 cerrada, 1 abierta)
const RAMP_LENGTH := 1.8
const RAMP_ANGLE := 0.45 # radianes
# Pasillos: ancho por fuera y altura libre. Por dentro caben las puertas.
const CORRIDOR_WIDTH := 2.5
const CORRIDOR_HEIGHT := 2.5
const CORRIDOR_WINDOW := Vector2(1.6, 1.2) # ventana de pasillo, más pequeña
const STOREY := FLOOR + HEIGHT + ROOF # altura de una planta
# Trampilla de la escalera, en una esquina: de HATCH_MIN a HATCH_MAX en x y z.
const HATCH_MIN := 0.75
const HATCH_MAX := SIZE / 2.0 - WALL
const LADDER_TOP := 1.1 # lo que asoma la escalera sobre el techo
## Lados por los que se puede pasar a otro módulo, según la receta.
const PORTS := {"modulo": [0, 1, 2, 3], "pasillo": [0, 2], "pasillo_l": [0, 1], "pasillo_t": [0, 1, 3]}

static var _materials := {}

## Lo que hay en cada lado: "pared", "puerta" o "ventana". Los lados son
## 0 delante (-Z), 1 derecha (+X), 2 detrás (+Z) y 3 izquierda (-X).
var sides: Array = ["pared", "pared", "pared", "pared"]
## Lados unidos a otro módulo: "" cerrado, "full" sin pared (dos módulos)
## o "narrow" con un hueco del ancho de un pasillo.
var open: Array = ["", "", "", ""]
## Receta: "modulo" o uno de los pasillos.
var kind := "modulo"
## Planta: 0 en el suelo, 1 encima de otro módulo...
var level := 0
## Módulos justo encima y debajo, o null.
var above: Node3D
var below: Node3D
## Entrada de Game.modules que se guarda con la partida.
var data := {}
var _ghost := false
## Puertas correderas: {"center": Node3D, "leaves": [izquierda, derecha], "t": 0..1}.
var _doors: Array = []
## Luces del techo: solo se encienden si hay energía.
var _lamps: Array[OmniLight3D] = []


func setup(module_data: Dictionary, ghost := false) -> void:
	data = module_data
	_ghost = ghost
	kind = String(data.get("kind", "modulo"))
	level = int(data.get("level", 0))
	var saved: Array = data.get("sides", [])
	for i in mini(saved.size(), 4):
		sides[i] = String(saved[i])
	_build()


## Dirección hacia fuera del lado i, en coordenadas del módulo.
static func side_direction(i: int) -> Vector3:
	return Vector3(0, 0, -1).rotated(Vector3.UP, -i * PI / 2.0)


## Lado del módulo que mira hacia el punto dado (en coordenadas globales).
func side_towards(point: Vector3) -> int:
	var local := to_local(point)
	local.y = 0.0
	return side_of(local)


func is_corridor() -> bool:
	return kind != "modulo"


func has_ladder() -> bool:
	return data.get("ladder", false)


func set_ladder(value: bool) -> void:
	if value:
		data["ladder"] = true
	else:
		data.erase("ladder")
	_build()
	if above:
		above.rebuild()


func rebuild() -> void:
	_build()


## true si el punto global está en el hueco de la escalera, donde se trepa.
func on_ladder(point: Vector3) -> bool:
	if not has_ladder():
		return false
	var local := to_local(point)
	var top := STOREY + (FLOOR + 0.3 if above else LADDER_TOP)
	return local.x > HATCH_MIN - 0.1 and local.x < HATCH_MAX and local.z > HATCH_MIN - 0.1 and local.z < HATCH_MAX \
			and local.y > -0.2 and local.y < top


## Centro del hueco de la trampilla, en coordenadas globales.
func hatch_center() -> Vector3:
	var c := (HATCH_MIN + HATCH_MAX) / 2.0
	return to_global(Vector3(c, 0, c))


func has_port(i: int) -> bool:
	return PORTS.get(kind, PORTS["modulo"]).has(i)


## Lado de este tipo de módulo que mira en la dirección dada (local).
static func side_of(direction: Vector3) -> int:
	var best := 0
	var best_dot := -INF
	for i in 4:
		var d := side_direction(i).dot(direction)
		if d > best_dot:
			best_dot = d
			best = i
	return best


## true si el punto global está dentro del módulo.
func contains(point: Vector3) -> bool:
	var local := to_local(point)
	var half := SIZE / 2.0
	if not is_corridor():
		return absf(local.x) < half and absf(local.z) < half and local.y > -0.5 and local.y < FLOOR + HEIGHT
	if local.y < -0.5 or local.y > FLOOR + CORRIDOR_HEIGHT:
		return false
	var w := CORRIDOR_WIDTH / 2.0
	if absf(local.x) < w and absf(local.z) < w:
		return true
	# En uno de sus brazos: se gira el punto al lado 0 del brazo.
	for i in 4:
		if has_port(i):
			var p := local.rotated(Vector3.UP, i * PI / 2.0)
			if absf(p.x) < w and p.z < 0.0 and p.z > -half:
				return true
	return false


func set_side(i: int, kind: String) -> void:
	sides[i] = kind
	data["sides"] = sides.duplicate()
	_build()


func set_open(i: int, value: String) -> void:
	if open[i] == value:
		return
	open[i] = value
	_build()


## Centro y tamaño del hueco de una puerta o ventana, en coordenadas del lado
## 0 (antes de girarlo hacia su lado).
## En un pasillo, "corridor"; si además el lado no es una boca, la pared está
## más adentro, en el borde del cuadrado del centro.
static func opening_box(kind: String, corridor := false, inner := false) -> AABB:
	var size := DOOR_SIZE if kind == "puerta" else (CORRIDOR_WINDOW if corridor else WINDOW_SIZE)
	var bottom := FLOOR if kind == "puerta" else FLOOR + WINDOW_BOTTOM
	var face := -CORRIDOR_WIDTH / 2.0 if inner else -SIZE / 2.0
	return AABB(Vector3(-size.x / 2.0, bottom, face - 0.05), Vector3(size.x, size.y, WALL + 0.1))


## Hueco de una puerta o ventana en el lado i de este módulo.
func opening_for(kind: String, i: int) -> AABB:
	return opening_box(kind, is_corridor(), is_corridor() and not has_port(i))


## Con energía (o batería cargada) se encienden las luces del techo.
static func has_power() -> bool:
	return Game.generated_energy() > 0 or Game.battery_charge > 0.0


func _process(delta: float) -> void:
	if not _lamps.is_empty():
		var lit := has_power()
		if lit != _lamps[0].visible:
			for lamp in _lamps:
				lamp.visible = lit
		# El material de la lámpara es el mismo para todos los módulos.
		var glow := 1.0 if lit else 0.0
		var material := _material("lampara")
		if material.emission_energy_multiplier != glow:
			material.emission_energy_multiplier = glow
			material.albedo_color = Color(1.0, 0.95, 0.85) if lit else Color(0.55, 0.55, 0.52)
	if _doors.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for door in _doors:
		var near := player != null and player.global_position.distance_to(door["center"].global_position) < DOOR_RANGE
		var t: float = move_toward(door["t"], 1.0 if near else 0.0, DOOR_SPEED * delta)
		if t == door["t"]:
			continue
		door["t"] = t
		# Cada hoja se mete en la pared de su lado.
		var width := (DOOR_SIZE.x - 2.0 * FRAME) / 2.0
		var eased := smoothstep(0.0, 1.0, t)
		for k in 2:
			var leaf: Node3D = door["leaves"][k]
			var sx := -1.0 if k == 0 else 1.0
			leaf.position.x = sx * (width / 2.0 + eased * width)


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_doors.clear()
	_lamps.clear()
	if is_corridor():
		_build_corridor()
		return
	var half := SIZE / 2.0
	# Suelo aparte: sobre él se pueden colocar máquinas.
	var floor_body := _body()
	floor_body.add_to_group("base_floor")
	if below and below.has_ladder():
		_plate_with_hatch(floor_body, FLOOR / 2.0, FLOOR, "suelo")
	else:
		_box(floor_body, Vector3(SIZE, FLOOR, SIZE), Vector3(0, FLOOR / 2.0, 0), "suelo")
	if level == 0:
		_box(floor_body, Vector3(SIZE - 0.1, SKIRT, SIZE - 0.1), Vector3(0, -SKIRT / 2.0, 0), "zocalo")
	var shell := _body()
	if not _ghost:
		# Sin luz propia el interior se ve casi negro: el techo tapa el sol.
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, FLOOR + HEIGHT - 0.4, 0)
		lamp.omni_range = SIZE * 1.1
		lamp.light_energy = 0.8
		lamp.light_color = Color(1.0, 0.92, 0.8)
		lamp.visible = has_power()
		add_child(lamp)
		_lamps.append(lamp)
		_box(shell, Vector3(0.8, 0.06, 0.8), Vector3(0, FLOOR + HEIGHT - 0.03, 0), "lampara", false)
	# Techo aparte: encima se pueden colocar máquinas (paneles) u otro módulo.
	var roof := _body()
	roof.add_to_group("base_roof")
	if has_ladder():
		_plate_with_hatch(roof, FLOOR + HEIGHT + ROOF / 2.0, ROOF, "techo")
		_add_ladder()
	else:
		_box(roof, Vector3(SIZE, ROOF, SIZE), Vector3(0, FLOOR + HEIGHT + ROOF / 2.0, 0), "techo")
	for i in 4:
		if open[i] == "full":
			continue
		var wall := _body()
		wall.rotation.y = -i * PI / 2.0
		var z := -half + WALL / 2.0
		if open[i] == "narrow":
			# Unido a un pasillo: pared con un hueco de su ancho.
			_wall_with_hole(wall, z, Vector2(CORRIDOR_WIDTH - 2.0 * WALL, CORRIDOR_HEIGHT), 0.0)
			continue
		wall.set_meta("side", i)
		match String(sides[i]):
			"puerta":
				_wall_with_hole(wall, z, DOOR_SIZE, 0.0)
				_add_door(wall, z)
			"ventana":
				_wall_with_hole(wall, z, WINDOW_SIZE, WINDOW_BOTTOM)
				_box(wall, Vector3(WINDOW_SIZE.x, WINDOW_SIZE.y, 0.05), Vector3(0, FLOOR + WINDOW_BOTTOM + WINDOW_SIZE.y / 2.0, z), "cristal")
			_:
				_box(wall, Vector3(SIZE, HEIGHT, WALL), Vector3(0, FLOOR + HEIGHT / 2.0, z), "pared")


## Puerta corredera y rampa delante de ella, en una pared cuya cara está en z.
func _add_door(wall: Node3D, z: float) -> void:
	if not _ghost:
		_add_sliding_door(wall, z)
	# Rampa para subir al suelo sin saltar.
	var ramp := Basis(Vector3.RIGHT, -RAMP_ANGLE)
	var length := RAMP_LENGTH
	var center := Vector3(0, FLOOR - sin(RAMP_ANGLE) * length / 2.0 - 0.1, z - WALL / 2.0 - cos(RAMP_ANGLE) * length / 2.0)
	_box(wall, Vector3(DOOR_SIZE.x, 0.2, length), center, "suelo", true, ramp)


## Pasillo: un cuadrado en el centro y un brazo hasta el borde por cada boca.
## Las bocas sin nada al lado se cierran con una pared que admite puerta.
func _build_corridor() -> void:
	var half := SIZE / 2.0
	var w := CORRIDOR_WIDTH
	var arm := half - w / 2.0
	var floor_body := _body()
	floor_body.add_to_group("base_floor")
	var shell := _body()
	_box(floor_body, Vector3(w, FLOOR, w), Vector3(0, FLOOR / 2.0, 0), "suelo")
	if level == 0:
		_box(floor_body, Vector3(w - 0.1, SKIRT, w - 0.1), Vector3(0, -SKIRT / 2.0, 0), "zocalo")
	_box(shell, Vector3(w, ROOF, w), Vector3(0, FLOOR + CORRIDOR_HEIGHT + ROOF / 2.0, 0), "techo")
	if not _ghost:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, FLOOR + CORRIDOR_HEIGHT - 0.3, 0)
		lamp.omni_range = SIZE * 0.9
		lamp.light_energy = 0.7
		lamp.light_color = Color(1.0, 0.92, 0.8)
		lamp.visible = has_power()
		add_child(lamp)
		_lamps.append(lamp)
		_box(shell, Vector3(0.5, 0.05, 0.5), Vector3(0, FLOOR + CORRIDOR_HEIGHT - 0.025, 0), "lampara", false)
	for i in 4:
		var turn := Basis(Vector3.UP, -i * PI / 2.0)
		if not has_port(i):
			# Pared que cierra el cuadrado del centro por ese lado.
			_corridor_wall(i, -w / 2.0 + WALL / 2.0)
			continue
		# Brazo: suelo, zócalo, techo y dos paredes que entran un poco en el
		# centro para que no quede rendija en las esquinas.
		var mid := -(w / 2.0 + arm / 2.0)
		_box(floor_body, Vector3(w, FLOOR, arm), turn * Vector3(0, FLOOR / 2.0, mid), "suelo", true, turn)
		if level == 0:
			_box(floor_body, Vector3(w - 0.1, SKIRT, arm), turn * Vector3(0, -SKIRT / 2.0, mid), "zocalo", true, turn)
		_box(shell, Vector3(w, ROOF, arm), turn * Vector3(0, FLOOR + CORRIDOR_HEIGHT + ROOF / 2.0, mid), "techo", true, turn)
		var length := arm + WALL
		for sx in [-1.0, 1.0]:
			var pos := Vector3(sx * (w / 2.0 - WALL / 2.0), FLOOR + CORRIDOR_HEIGHT / 2.0, -half + length / 2.0)
			_box(shell, Vector3(WALL, CORRIDOR_HEIGHT, length), turn * pos, "pared", true, turn)
		if open[i] == "":
			_corridor_wall(i, -half + WALL / 2.0)


## Placa de SIZE × SIZE (suelo o techo) con el hueco de la trampilla en la
## esquina, con su centro a la altura y.
func _plate_with_hatch(body: Node3D, y: float, thickness: float, material: String) -> void:
	var half := SIZE / 2.0
	var a := HATCH_MIN
	var b := HATCH_MAX
	# Lo que queda alrededor del hueco: una franja ancha y tres pequeñas.
	_box(body, Vector3(a + half, thickness, SIZE), Vector3((a - half) / 2.0, y, 0), material)
	_box(body, Vector3(half - a, thickness, a + half), Vector3((a + half) / 2.0, y, (a - half) / 2.0), material)
	_box(body, Vector3(half - b, thickness, half - a), Vector3((b + half) / 2.0, y, (a + half) / 2.0), material)
	_box(body, Vector3(b - a, thickness, half - b), Vector3((a + b) / 2.0, y, (b + half) / 2.0), material)
	_box(body, Vector3(b - a + 0.04, 0.04, 0.04), Vector3((a + b) / 2.0, y + thickness / 2.0, a), "acento", false)


## Escalera de mano pegada a la pared derecha (+X), en el hueco de la
## trampilla: sube hasta la planta de arriba o asoma por el techo.
func _add_ladder() -> void:
	var body := _body()
	body.set_meta("ladder", true)
	# En la capa 2, como el musgo: el rayo de la herramienta la ve pero el
	# jugador no choca con ella al trepar.
	if body is CollisionObject3D:
		body.collision_layer = 2
	var top := STOREY + (FLOOR if above else LADDER_TOP)
	var x := HATCH_MAX - 0.08
	var z := (HATCH_MIN + HATCH_MAX) / 2.0
	var width := 0.6
	for sz in [-1.0, 1.0]:
		_box(body, Vector3(0.06, top, 0.06), Vector3(x, top / 2.0, z + sz * width / 2.0), "acento", false)
	var rungs := int(top / 0.35)
	for k in rungs:
		_box(body, Vector3(0.04, 0.04, width), Vector3(x, 0.3 + k * 0.35, z), "hoja", false)
	# Una caja invisible para poder apuntarla y desmontarla.
	if body is CollisionObject3D:
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.1, top, width)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(x, top / 2.0, z)
		body.add_child(collision)


## Pared de pasillo del ancho del tubo en el lado i, con su cara en z; puede
## llevar puerta o ventana.
func _corridor_wall(i: int, z: float) -> void:
	var w := CORRIDOR_WIDTH
	var wall := _body()
	wall.set_meta("side", i)
	wall.rotation.y = -i * PI / 2.0
	match String(sides[i]):
		"puerta":
			_wall_with_hole(wall, z, DOOR_SIZE, 0.0, w, CORRIDOR_HEIGHT)
			_add_door(wall, z)
		"ventana":
			_wall_with_hole(wall, z, CORRIDOR_WINDOW, WINDOW_BOTTOM, w, CORRIDOR_HEIGHT)
			_box(wall, Vector3(CORRIDOR_WINDOW.x, CORRIDOR_WINDOW.y, 0.05), Vector3(0, FLOOR + WINDOW_BOTTOM + CORRIDOR_WINDOW.y / 2.0, z), "cristal")
		_:
			_box(wall, Vector3(w, CORRIDOR_HEIGHT, WALL), Vector3(0, FLOOR + CORRIDOR_HEIGHT / 2.0, z), "pared")


## Pared de ancho width y alto height con un hueco de tamaño hole cuyo borde
## inferior está a bottom metros del suelo. Los lados del hueco llevan el
## color de acento.
func _wall_with_hole(wall: Node3D, z: float, hole: Vector2, bottom: float, width := SIZE, height := HEIGHT) -> void:
	var side_width := (width - hole.x) / 2.0
	var x := hole.x / 2.0 + side_width / 2.0
	_box(wall, Vector3(side_width, height, WALL), Vector3(-x, FLOOR + height / 2.0, z), "pared")
	_box(wall, Vector3(side_width, height, WALL), Vector3(x, FLOOR + height / 2.0, z), "pared")
	var top := bottom + hole.y
	if height - top > 0.01:
		_box(wall, Vector3(hole.x, height - top, WALL), Vector3(0, FLOOR + (top + height) / 2.0, z), "pared")
	if bottom > 0.0:
		_box(wall, Vector3(hole.x, bottom, WALL), Vector3(0, FLOOR + bottom / 2.0, z), "pared")
	# Marco por dentro del hueco. Si se solapa con la pared, sus caras coinciden
	# con las del hueco y parpadean (z-fighting).
	var frame := FRAME
	for sx in [-1, 1]:
		_box(wall, Vector3(frame, hole.y, WALL + 0.04), Vector3(sx * (hole.x / 2.0 - frame / 2.0), FLOOR + bottom + hole.y / 2.0, z), "acento", false)
	_box(wall, Vector3(hole.x, frame, WALL + 0.04), Vector3(0, FLOOR + top - frame / 2.0, z), "acento", false)
	if bottom > 0.0:
		_box(wall, Vector3(hole.x, frame, WALL + 0.04), Vector3(0, FLOOR + bottom + frame / 2.0, z), "acento", false)


## Dos hojas finas que se deslizan dentro del grosor de la pared.
func _add_sliding_door(wall: Node3D, z: float) -> void:
	var width := (DOOR_SIZE.x - 2.0 * FRAME) / 2.0
	var height := DOOR_SIZE.y - FRAME
	var center := Node3D.new()
	center.position = Vector3(0, FLOOR + height / 2.0, z)
	wall.add_child(center)
	var leaves := []
	for sx in [-1.0, 1.0]:
		var leaf := AnimatableBody3D.new()
		leaf.sync_to_physics = false
		leaf.set_meta("module", self)
		leaf.set_meta("side", wall.get_meta("side"))
		leaf.position.x = sx * width / 2.0
		center.add_child(leaf)
		_box(leaf, Vector3(width, height, 0.06), Vector3.ZERO, "hoja")
		# Tirador vertical junto al borde que se junta con la otra hoja.
		_box(leaf, Vector3(0.04, 0.5, 0.1), Vector3(-sx * (width / 2.0 - 0.08), 0, 0), "acento", false)
		leaves.append(leaf)
	_doors.append({"center": center, "leaves": leaves, "t": 0.0})


func _body() -> Node3D:
	var body: Node3D = Node3D.new() if _ghost else StaticBody3D.new()
	body.set_meta("module", self)
	add_child(body)
	return body


func _box(parent: Node3D, size: Vector3, pos: Vector3, material: String, collide := true, basis := Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.transform = Transform3D(basis, pos)
	instance.material_override = _material(material)
	parent.add_child(instance)
	if collide and not _ghost:
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = Transform3D(basis, pos)
		parent.add_child(collision)


static func _material(name: String) -> StandardMaterial3D:
	if _materials.has(name):
		return _materials[name]
	var material := StandardMaterial3D.new()
	match name:
		"pared":
			material.albedo_color = Color(0.82, 0.83, 0.8)
		"suelo":
			material.albedo_color = Color(0.45, 0.47, 0.5)
		"zocalo":
			material.albedo_color = Color(0.3, 0.3, 0.32)
		"techo":
			material.albedo_color = Color(0.7, 0.72, 0.7)
		"lampara":
			material.albedo_color = Color(1.0, 0.95, 0.85)
			material.emission_enabled = true
			material.emission = Color(1.0, 0.9, 0.7)
		"acento":
			material.albedo_color = Color(0.95, 0.55, 0.15)
		"hoja":
			material.albedo_color = Color(0.6, 0.63, 0.66)
			material.metallic = 0.5
			material.roughness = 0.4
		"cristal":
			material.albedo_color = Color(0.5, 0.8, 1.0, 0.3)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.roughness = 0.05
	_materials[name] = material
	return material
