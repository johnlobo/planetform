extends Node3D
## Cápsula de aterrizaje: donde empieza la partida. Octogonal, de unos 5 m de
## ancho, con una puerta (con rampa), una ventana, una luz que siempre
## funciona (batería de emergencia propia), el fabricador y el almacén de
## pared. Es un refugio (oxígeno y sin frío) y no se puede desmontar.
## El nodo está en el centro del mapa, con su origen en el suelo de dentro.

const Machine := preload("res://scripts/machine.gd")

const RADIUS := 3.0 # del centro a una esquina del octógono
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.2
const DOOR_WIDTH := 1.4
const DOOR_HEIGHT := 2.2
const DOOR_WALL := 2 # número de pared: 0 es +X y de ahí de 45 en 45° hacia +Z
const RAMP_LENGTH := 2.2
const STORAGE_WALL := 5
const FABRICATOR_WALL := 7
const WINDOW_WALL := 6

var world: Node3D
## Altura del suelo de dentro.
var floor_y := 0.0
var fabricator: Machine
var storage: Machine
var _hull: StaticBody3D
var _hull_material := StandardMaterial3D.new()
var _dark_material := StandardMaterial3D.new()
var _floor_material := StandardMaterial3D.new()
var _glass_material := StandardMaterial3D.new()
var _lamp_material := StandardMaterial3D.new()


## Distancia del centro a la mitad de una pared (lo que mide por dentro).
static func apothem() -> float:
	return RADIUS * cos(deg_to_rad(22.5))


func setup(world_node: Node3D) -> void:
	world = world_node
	add_to_group("capsule")
	_hull_material.albedo_color = Color(0.82, 0.82, 0.78)
	_hull_material.metallic = 0.3
	_hull_material.roughness = 0.55
	_dark_material.albedo_color = Color(0.16, 0.15, 0.15)
	_dark_material.roughness = 0.9
	_floor_material.albedo_color = Color(0.36, 0.38, 0.42)
	_floor_material.roughness = 0.7
	_glass_material.albedo_color = Color(0.25, 0.5, 0.75)
	_glass_material.emission_enabled = true
	_glass_material.emission = Color(0.1, 0.3, 0.5)
	_lamp_material.albedo_color = Color(1.0, 0.95, 0.8)
	_lamp_material.emission_enabled = true
	_lamp_material.emission = Color(1.0, 0.9, 0.6)

	# El suelo queda a la altura del terreno más alto bajo la cápsula.
	var low := INF
	var high := -INF
	for i in 16:
		var angle := TAU * i / 16.0
		for r in [0.0, RADIUS * 0.6, RADIUS + 0.4]:
			var h: float = world.surface_height(cos(angle) * r, sin(angle) * r)
			low = minf(low, h)
			high = maxf(high, h)
	floor_y = high + 0.12
	position = Vector3(0, floor_y, 0)

	_hull = StaticBody3D.new()
	_hull.set_meta("capsule", true)
	add_child(_hull)
	_build_floor(low - floor_y - 0.5)
	for k in 8:
		if k == DOOR_WALL:
			_build_door_wall(k)
		else:
			_wall(k)
	_build_roof()
	_build_ramp()
	_build_details()
	_build_inside()


## true si el punto está dentro de la cápsula, bajo su techo.
func contains(point: Vector3) -> bool:
	var local := point - global_position
	if local.y < -0.2 or local.y > WALL_HEIGHT:
		return false
	for k in 8:
		if local.x * cos(deg_to_rad(45.0 * k)) + local.z * sin(deg_to_rad(45.0 * k)) > apothem() - 0.05:
			return false
	return true


## Donde aparece el jugador: en el centro, de pie sobre el suelo.
func spawn_position() -> Vector3:
	return global_position + Vector3(0, 0.1, 0)


## Los ocho puntos de un anillo octogonal con las esquinas a 22,5° + 45°·k,
## de modo que las paredes (k·45°) quedan centradas en los ejes.
static func _ring(radius: float, y: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for k in 8:
		var angle := deg_to_rad(22.5 + 45.0 * k)
		points.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
	return points


## Tronco de pirámide octogonal entre dos anillos, con tapa arriba y abajo.
func _frustum(r0: float, y0: float, r1: float, y1: float, material: Material, top_material: Material = null) -> MeshInstance3D:
	var bottom := _ring(r0, y0)
	var top := _ring(r1, y1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for k in 8:
		var n := (k + 1) % 8
		for v in [top[n], top[k], bottom[k], top[n], bottom[k], bottom[n]]:
			st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	add_child(part)
	# Tapas: la de arriba mira hacia arriba y la de abajo, hacia abajo.
	for cap in [[top, Vector3(0, y1, 0), true], [bottom, Vector3(0, y0, 0), false]]:
		var cap_st := SurfaceTool.new()
		cap_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		cap_st.set_smooth_group(-1)
		var ring: PackedVector3Array = cap[0]
		for k in 8:
			var n := (k + 1) % 8
			var order := [cap[1], ring[k], ring[n]] if cap[2] else [cap[1], ring[n], ring[k]]
			for v in order:
				cap_st.add_vertex(v)
		cap_st.generate_normals()
		var cap_part := MeshInstance3D.new()
		cap_part.mesh = cap_st.commit()
		cap_part.material_override = top_material if (cap[2] and top_material) else material
		add_child(cap_part)
	return part


func _convex(points: PackedVector3Array) -> void:
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	shape.shape = convex
	_hull.add_child(shape)


func _build_floor(skirt: float) -> void:
	# Plataforma que llega hasta el terreno más bajo y tapa el que sobresale.
	_frustum(RADIUS + 0.35, skirt, RADIUS + 0.35, 0.0, _hull_material, _floor_material)
	var points := PackedVector3Array()
	points.append_array(_ring(RADIUS + 0.35, skirt))
	points.append_array(_ring(RADIUS + 0.35, 0.0))
	_convex(points)


func _build_roof() -> void:
	# Techo en cono truncado; por dentro se ve su cara de abajo, plana.
	_frustum(RADIUS + 0.15, WALL_HEIGHT, 1.3, WALL_HEIGHT + 0.9, _hull_material)
	var points := PackedVector3Array()
	points.append_array(_ring(RADIUS + 0.15, WALL_HEIGHT))
	points.append_array(_ring(1.3, WALL_HEIGHT + 0.9))
	_convex(points)
	# Antena y luz del techo.
	var mast := _box(Vector3(0.08, 0.9, 0.08), Vector3(0.4, WALL_HEIGHT + 1.35, 0.0), _dark_material)
	mast.rotation_degrees.z = -12.0
	var lamp := _box(Vector3(0.7, 0.04, 0.7), Vector3(0, WALL_HEIGHT - 0.03, 0), _lamp_material)
	lamp.rotation_degrees.y = 22.5
	var light := OmniLight3D.new()
	light.position = Vector3(0, WALL_HEIGHT - 0.4, 0)
	light.omni_range = 7.0
	light.light_energy = 1.3
	light.light_color = Color(1.0, 0.93, 0.8)
	add_child(light)


## Posición del centro de la pared k, a "radius" del eje, y su giro: el eje Z
## local de lo que se ponga ahí mira hacia fuera.
static func _wall_spot(k: int, radius: float) -> Transform3D:
	var phi := deg_to_rad(45.0 * k)
	return Transform3D(Basis(Vector3.UP, PI / 2.0 - phi), Vector3(cos(phi) * radius, 0, sin(phi) * radius))


func _wall_box(spot: Transform3D, size: Vector3, local_pos: Vector3, material: Material) -> void:
	var xform := spot * Transform3D(Basis.IDENTITY, local_pos)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.transform = xform
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.transform = xform
	_hull.add_child(shape)


func _wall(k: int) -> void:
	var spot := _wall_spot(k, apothem() + WALL_THICKNESS / 2.0)
	_wall_box(spot, Vector3(2.6, WALL_HEIGHT, WALL_THICKNESS), Vector3(0, WALL_HEIGHT / 2.0, 0), _hull_material)


func _build_door_wall(k: int) -> void:
	var spot := _wall_spot(k, apothem() + WALL_THICKNESS / 2.0)
	var side := (2.6 - DOOR_WIDTH) / 2.0
	for sx in [-1.0, 1.0]:
		_wall_box(spot, Vector3(side, WALL_HEIGHT, WALL_THICKNESS), Vector3(sx * (DOOR_WIDTH + side) / 2.0, WALL_HEIGHT / 2.0, 0), _hull_material)
	_wall_box(spot, Vector3(DOOR_WIDTH, WALL_HEIGHT - DOOR_HEIGHT, WALL_THICKNESS), Vector3(0, (WALL_HEIGHT + DOOR_HEIGHT) / 2.0, 0), _hull_material)
	# Marco naranja alrededor del hueco.
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.95, 0.55, 0.15)
	for sx in [-1.0, 1.0]:
		_visual(spot, Vector3(0.08, DOOR_HEIGHT, WALL_THICKNESS + 0.06), Vector3(sx * (DOOR_WIDTH / 2.0 + 0.04), DOOR_HEIGHT / 2.0, 0), accent)
	_visual(spot, Vector3(DOOR_WIDTH + 0.16, 0.08, WALL_THICKNESS + 0.06), Vector3(0, DOOR_HEIGHT + 0.04, 0), accent)


## Pieza que solo se ve, sin colisión.
func _visual(spot: Transform3D, size: Vector3, local_pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.transform = spot * Transform3D(Basis.IDENTITY, local_pos)
	add_child(mesh)
	return mesh


func _box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	return _visual(Transform3D.IDENTITY, size, pos, material)


## Rampa de la puerta hasta el terreno de fuera.
func _build_ramp() -> void:
	var spot := _wall_spot(DOOR_WALL, apothem() + WALL_THICKNESS)
	var start: Vector3 = spot.origin
	var out := spot.basis * Vector3(0, 0, RAMP_LENGTH)
	var end := start + out
	var ground: float = world.surface_height(end.x, end.z) - floor_y
	var drop := -ground
	if drop < 0.03:
		return
	var from := start
	var to := Vector3(end.x, -drop, end.z)
	var basis := Basis.looking_at(to - from, Vector3.UP)
	var length := from.distance_to(to)
	var xform := Transform3D(basis, (from + to) / 2.0 - basis.y * 0.1)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(DOOR_WIDTH + 0.2, 0.2, length)
	mesh.mesh = box
	mesh.material_override = _floor_material
	mesh.transform = xform
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	shape.transform = xform
	_hull.add_child(shape)


## Patas de aterrizaje, marcas de quemado y ojo de buey.
func _build_details() -> void:
	for k in 4:
		var angle := deg_to_rad(22.5 + 45.0 + 90.0 * k)
		var top := Vector3(cos(angle) * (apothem() + 0.1), 1.3, sin(angle) * (apothem() + 0.1))
		var ground_x := cos(angle) * (RADIUS + 1.3)
		var ground_z := sin(angle) * (RADIUS + 1.3)
		var ground: float = world.surface_height(ground_x + global_position.x, ground_z + global_position.z) - floor_y
		var bottom := Vector3(ground_x, ground + 0.05, ground_z)
		_strut(top, bottom, 0.16, _dark_material)
		_box(Vector3(0.9, 0.1, 0.9), bottom + Vector3(0, 0.0, 0), _hull_material).rotation.y = angle
	# Marcas de quemado en el casco, más abajo que arriba.
	for k in 8:
		if k == DOOR_WALL or k == WINDOW_WALL:
			continue
		var spot := _wall_spot(k, apothem() + WALL_THICKNESS + 0.01)
		_visual(spot, Vector3(1.2, 0.6, 0.02), Vector3(0.3 * (1 if k % 2 == 0 else -1), 0.45, 0), _dark_material)
	# Ojo de buey en la pared del fondo: un disco que atraviesa el grosor.
	var window_spot := _wall_spot(WINDOW_WALL, apothem() + WALL_THICKNESS / 2.0)
	var window := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.42
	disc.height = WALL_THICKNESS + 0.06
	disc.radial_segments = 8
	disc.rings = 1
	window.mesh = disc
	window.material_override = _glass_material
	window.transform = window_spot * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 1.9, 0))
	add_child(window)


## Barra entre dos puntos.
func _strut(a: Vector3, b: Vector3, thickness: float, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(thickness, thickness, a.distance_to(b))
	mesh.mesh = box
	mesh.material_override = material
	mesh.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) / 2.0)
	add_child(mesh)


## El fabricador y el almacén de pared, pegados a sus paredes y de cara al centro.
func _build_inside() -> void:
	fabricator = _machine("fabricador", FABRICATOR_WALL, 0.45, {"kind": "fabricador", "fixed": true})
	storage = _machine("almacen", STORAGE_WALL, 0.25, Game.capsule)


func _machine(kind: String, wall: int, depth_from_wall: float, data: Dictionary) -> Machine:
	var machine := Machine.new()
	machine.data = data
	machine.setup(kind)
	var spot := _wall_spot(wall, apothem() - depth_from_wall)
	machine.transform = spot
	add_child(machine)
	return machine
