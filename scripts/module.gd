extends Node3D
## Módulo de hábitat prefabricado: una caja de 4 × 4 m con suelo, techo y
## cuatro paredes. Cada pared puede ser lisa, con puerta o con ventana, y se
## abre sola cuando hay otro módulo pegado a ese lado. Dentro el jugador
## está a cubierto: no pierde oxígeno ni pasa frío.

const SIZE := 4.0
const HEIGHT := 3.0 # altura libre del interior
const WALL := 0.2
const FLOOR := 0.25
const ROOF := 0.25
const SKIRT := 1.5 # zócalo bajo el suelo para que no flote en las cuestas
const DOOR_SIZE := Vector2(1.4, 2.3)
const WINDOW_SIZE := Vector2(3.0, 1.8)
const WINDOW_BOTTOM := 0.7
const FRAME := 0.08 # grosor del marco de puertas y ventanas
const DOOR_RANGE := 2.5 # a esta distancia las hojas se abren solas
const DOOR_SPEED := 2.5 # recorrido por segundo (0 cerrada, 1 abierta)
const RAMP_LENGTH := 1.8
const RAMP_ANGLE := 0.45 # radianes

static var _materials := {}

## Lo que hay en cada lado: "pared", "puerta" o "ventana". Los lados son
## 0 delante (-Z), 1 derecha (+X), 2 detrás (+Z) y 3 izquierda (-X).
var sides: Array = ["pared", "pared", "pared", "pared"]
## Lados pegados a otro módulo: no tienen pared.
var open: Array = [false, false, false, false]
## Entrada de Game.modules que se guarda con la partida.
var data := {}
var _ghost := false
## Puertas correderas: {"center": Node3D, "leaves": [izquierda, derecha], "t": 0..1}.
var _doors: Array = []


func setup(module_data: Dictionary, ghost := false) -> void:
	data = module_data
	_ghost = ghost
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
	var best := 0
	var best_dot := -INF
	for i in 4:
		var d := side_direction(i).dot(local)
		if d > best_dot:
			best_dot = d
			best = i
	return best


## true si el punto global está dentro del módulo.
func contains(point: Vector3) -> bool:
	var local := to_local(point)
	var half := SIZE / 2.0
	return absf(local.x) < half and absf(local.z) < half and local.y > -0.5 and local.y < FLOOR + HEIGHT


func set_side(i: int, kind: String) -> void:
	sides[i] = kind
	data["sides"] = sides.duplicate()
	_build()


func set_open(i: int, value: bool) -> void:
	if open[i] == value:
		return
	open[i] = value
	_build()


## Centro y tamaño del hueco de una puerta o ventana, en coordenadas del lado
## 0 (antes de girarlo hacia su lado).
static func opening_box(kind: String) -> AABB:
	var size := DOOR_SIZE if kind == "puerta" else WINDOW_SIZE
	var bottom := FLOOR if kind == "puerta" else FLOOR + WINDOW_BOTTOM
	return AABB(Vector3(-size.x / 2.0, bottom, -SIZE / 2.0 - 0.05), Vector3(size.x, size.y, WALL + 0.1))


func _process(delta: float) -> void:
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
	var half := SIZE / 2.0
	# Suelo aparte: sobre él se pueden colocar máquinas.
	var floor_body := _body()
	floor_body.add_to_group("base_floor")
	_box(floor_body, Vector3(SIZE, FLOOR, SIZE), Vector3(0, FLOOR / 2.0, 0), "suelo")
	_box(floor_body, Vector3(SIZE - 0.1, SKIRT, SIZE - 0.1), Vector3(0, -SKIRT / 2.0, 0), "zocalo")
	var shell := _body()
	if not _ghost:
		# Sin luz propia el interior se ve casi negro: el techo tapa el sol.
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, FLOOR + HEIGHT - 0.4, 0)
		lamp.omni_range = SIZE * 1.1
		lamp.light_energy = 0.8
		lamp.light_color = Color(1.0, 0.92, 0.8)
		add_child(lamp)
		_box(shell, Vector3(0.8, 0.06, 0.8), Vector3(0, FLOOR + HEIGHT - 0.03, 0), "lampara", false)
	_box(shell, Vector3(SIZE, ROOF, SIZE), Vector3(0, FLOOR + HEIGHT + ROOF / 2.0, 0), "techo")
	for i in 4:
		if open[i]:
			continue
		var wall := _body()
		wall.set_meta("side", i)
		wall.rotation.y = -i * PI / 2.0
		var z := -half + WALL / 2.0
		match String(sides[i]):
			"puerta":
				_wall_with_hole(wall, z, DOOR_SIZE, 0.0)
				if not _ghost:
					_add_sliding_door(wall, z)
				# Rampa para subir al suelo sin saltar.
				var ramp := Basis(Vector3.RIGHT, -RAMP_ANGLE)
				var length := RAMP_LENGTH
				var center := Vector3(0, FLOOR - sin(RAMP_ANGLE) * length / 2.0 - 0.1, -half - cos(RAMP_ANGLE) * length / 2.0)
				_box(wall, Vector3(DOOR_SIZE.x, 0.2, length), center, "suelo", true, ramp)
			"ventana":
				_wall_with_hole(wall, z, WINDOW_SIZE, WINDOW_BOTTOM)
				_box(wall, Vector3(WINDOW_SIZE.x, WINDOW_SIZE.y, 0.05), Vector3(0, FLOOR + WINDOW_BOTTOM + WINDOW_SIZE.y / 2.0, z), "cristal")
			_:
				_box(wall, Vector3(SIZE, HEIGHT, WALL), Vector3(0, FLOOR + HEIGHT / 2.0, z), "pared")


## Pared con un hueco de tamaño hole cuyo borde inferior está a bottom metros
## del suelo. Los lados del hueco llevan el color de acento.
func _wall_with_hole(wall: Node3D, z: float, hole: Vector2, bottom: float) -> void:
	var side_width := (SIZE - hole.x) / 2.0
	var x := hole.x / 2.0 + side_width / 2.0
	_box(wall, Vector3(side_width, HEIGHT, WALL), Vector3(-x, FLOOR + HEIGHT / 2.0, z), "pared")
	_box(wall, Vector3(side_width, HEIGHT, WALL), Vector3(x, FLOOR + HEIGHT / 2.0, z), "pared")
	var top := bottom + hole.y
	_box(wall, Vector3(hole.x, HEIGHT - top, WALL), Vector3(0, FLOOR + (top + HEIGHT) / 2.0, z), "pared")
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
