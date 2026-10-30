extends RefCounted
## Sitios recónditos del mapa, lejos de la base: cuevas con titanio y cuarzo,
## restos de naves con cajas de suministros y cráteres con un meteorito de
## iridio. El terreno es una sola superficie de alturas y no puede tener
## huecos, así que las cuevas son una bóveda de roca metida en la ladera de
## una montaña: el terreno excava su suelo y la boca (Terrain._carve).

const LootCrate := preload("res://scripts/loot_crate.gd")

const CAVE_RADIUS := 11.0
const CAVE_HEIGHT := 7.0
const CAVE_SEGMENTS := 16
const CAVE_RINGS := 6
# Anillos de abajo que se quitan en la boca y ángulo de la boca a cada lado.
const MOUTH_RINGS := 3
const MOUTH_ANGLE := 0.35
const CRATER_RADIUS := 11.0
const CRATER_DEPTH := 6.0 # metros que se hunde el centro
const CRATER_RIM := 1.5 # y lo que se levanta el borde
# Media anchura de la boca y del pasillo excavado delante.
const MOUTH_HALF := 4.5
# Radio que ocupa cada sitio: dentro no se ponen rocas, árboles ni depósitos.
const RADIUS := {"cueva": CAVE_RADIUS + 16.0, "nave": 8.0, "crater": CRATER_RADIUS + 8.0}


## Cueva en "pos" (coordenadas del mundo) con la boca hacia "rot". Devuelve
## el nodo para añadir al trozo, ya colocado respecto a "center".
static func cave(world: Node3D, pos: Vector3, rot: float, center: Vector3, id: String, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = pos - center
	root.rotation.y = rot
	var basis := Basis(Vector3.UP, rot)
	var faces := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Bóveda de anillos desde algo por debajo del suelo hasta arriba, con los
	# vértices movidos al azar para que parezca roca.
	var points := []
	for i in CAVE_RINGS + 1:
		var ring := []
		var phi := lerpf(-0.25, 1.0, float(i) / CAVE_RINGS) * PI / 2.0
		for j in CAVE_SEGMENTS:
			var theta := j * TAU / CAVE_SEGMENTS
			# Los dos anillos de abajo, sin mover: rodean justo el suelo excavado.
			var jitter := 1.0 if i <= 1 or i == CAVE_RINGS else rng.randf_range(0.85, 1.12)
			ring.append(Vector3(sin(theta) * cos(phi) * CAVE_RADIUS * jitter, sin(phi) * CAVE_HEIGHT * jitter, cos(theta) * cos(phi) * CAVE_RADIUS * jitter))
		points.append(ring)
	for i in CAVE_RINGS:
		for j in CAVE_SEGMENTS:
			var mid := (j + 0.5) * TAU / CAVE_SEGMENTS
			var off := minf(mid, TAU - mid)
			if i < MOUTH_RINGS and off < MOUTH_ANGLE:
				continue # la boca, mirando hacia +Z
			var k := (j + 1) % CAVE_SEGMENTS
			var a: Vector3 = points[i][j]
			var b: Vector3 = points[i][k]
			var c: Vector3 = points[i + 1][j]
			var d: Vector3 = points[i + 1][k]
			for tri in [[a, c, b], [b, c, d]]:
				var normal: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				var shade := rng.randf_range(0.85, 1.1)
				for v in tri:
					st.set_normal(normal)
					st.set_color(Color(0.34 * shade, 0.31 * shade, 0.3 * shade))
					st.add_vertex(v)
					faces.append(v)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shell := MeshInstance3D.new()
	shell.mesh = st.commit()
	shell.material_override = material
	root.add_child(shell)
	var body := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)

	# Titanio en las paredes y cristales de cuarzo al fondo, que dan algo de luz.
	var veins := rng.randi_range(3, 4)
	for n in veins:
		var theta := lerpf(1.0, TAU - 1.0, (n + 0.5) / veins) + rng.randf_range(-0.2, 0.2)
		_deposit(world, root, "titanio", Vector3(sin(theta), 0, cos(theta)) * CAVE_RADIUS * 0.7, pos, basis, rng)
	for n in 2:
		var theta := PI + (n - 0.5) * 0.7
		_deposit(world, root, "cuarzo", Vector3(sin(theta), 0, cos(theta)) * CAVE_RADIUS * 0.62, pos, basis, rng)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.95, 0.5, 0.9)
	glow.light_energy = 0.8
	glow.omni_range = 7.0
	glow.position = Vector3(0, 1.5, -CAVE_RADIUS * 0.55)
	root.add_child(glow)
	# En la mitad de las cuevas hay una caja al fondo.
	if rng.randf() < 0.5:
		_crate(world, root, id, Vector3(rng.randf_range(-2.0, 2.0), 0, -CAVE_RADIUS * 0.3), pos, basis)
	return root


## Restos de una nave estrellada, medio enterrados, con una caja al lado.
static func wreck(world: Node3D, pos: Vector3, rot: float, center: Vector3, id: String, rng: RandomNumberGenerator) -> Node3D:
	var root := StaticBody3D.new()
	root.position = pos - center
	root.rotation.y = rot
	var hull := _material(Color(0.72, 0.74, 0.77), 0.4)
	var burnt := _material(Color(0.18, 0.18, 0.2), 0.2)
	var stripe := _material(Color(0.95, 0.55, 0.15), 0.1)
	var tilt := rng.randf_range(8.0, 16.0)
	# El casco, tumbado a lo largo de X y algo inclinado, con el morro enterrado.
	var body := Node3D.new()
	body.rotation_degrees = Vector3(0, 0, -tilt)
	body.position.y = 0.6
	root.add_child(body)
	var tube := CylinderMesh.new()
	tube.top_radius = 1.4
	tube.bottom_radius = 1.5
	tube.height = 8.0
	tube.radial_segments = 8
	tube.rings = 1
	_part(body, tube, Vector3.ZERO, hull, Vector3(0, 0, 90))
	var nose := CylinderMesh.new()
	nose.top_radius = 0.2
	nose.bottom_radius = 1.4
	nose.height = 2.5
	nose.radial_segments = 8
	_part(body, nose, Vector3(-5.2, 0, 0), burnt, Vector3(0, 0, 90))
	var band := CylinderMesh.new()
	band.top_radius = 1.52
	band.bottom_radius = 1.52
	band.height = 0.5
	band.radial_segments = 8
	_part(body, band, Vector3(1.5, 0, 0), stripe, Vector3(0, 0, 90))
	# Ala rota y aleta trasera.
	var wing := BoxMesh.new()
	wing.size = Vector3(2.6, 0.15, 4.5)
	_part(body, wing, Vector3(1.0, -0.4, 2.6), hull, Vector3(0, 12, -8))
	var fin := BoxMesh.new()
	fin.size = Vector3(1.8, 1.8, 0.15)
	_part(body, fin, Vector3(3.4, 1.6, 0), burnt, Vector3(0, 0, 20))
	for n in 4:
		var scrap := BoxMesh.new()
		scrap.size = Vector3(rng.randf_range(0.4, 1.2), 0.1, rng.randf_range(0.3, 0.9))
		var spot := Vector3(rng.randf_range(-4.0, 4.0), 0, rng.randf_range(-4.5, -2.0))
		var y: float = world.surface_height(pos.x + spot.rotated(Vector3.UP, rot).x, pos.z + spot.rotated(Vector3.UP, rot).z) - pos.y
		_part(root, scrap, spot + Vector3(0, y + 0.05, 0), hull if n % 2 == 0 else burnt, Vector3(rng.randf_range(-10, 10), rng.randf_range(0, 180), 0))
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 2.8, 2.8)
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position = body.position
	collision.rotation = body.rotation
	root.add_child(collision)
	_crate(world, root, id, Vector3(0.5, 0, 2.8), pos, Basis(Vector3.UP, rot))
	return root


## Cráter: el terreno se hunde en medio (Terrain._carve) con un anillo de
## rocas en el borde y un meteorito de iridio en el fondo.
static func crater(world: Node3D, pos: Vector3, rot: float, center: Vector3, boulder: Mesh, rng: RandomNumberGenerator) -> Node3D:
	var root := StaticBody3D.new()
	root.position = pos - center
	root.rotation.y = rot
	var basis := Basis(Vector3.UP, rot)
	var rock := StandardMaterial3D.new()
	rock.vertex_color_use_as_albedo = true
	rock.albedo_color = Color(1.0, 0.85, 0.75)
	rock.roughness = 1.0
	var count := 9
	for n in count:
		var theta := n * TAU / count + rng.randf_range(-0.1, 0.1)
		var local := Vector3(sin(theta), 0, cos(theta)) * CRATER_RADIUS * rng.randf_range(1.1, 1.25)
		var global := pos + basis * local
		var size := rng.randf_range(0.6, 1.1)
		local.y = world.surface_height(global.x, global.z) - pos.y - 0.3 * size
		var instance := MeshInstance3D.new()
		instance.mesh = boulder
		instance.material_override = rock
		instance.position = local
		instance.scale = Vector3(rng.randf_range(1.2, 1.8), rng.randf_range(0.4, 0.7), rng.randf_range(0.8, 1.2)) * size
		instance.rotation.y = theta
		root.add_child(instance)
		var sphere := SphereShape3D.new()
		sphere.radius = 0.75 * size
		var collision := CollisionShape3D.new()
		collision.shape = sphere
		collision.position = local + Vector3(0, 0.3 * size, 0)
		root.add_child(collision)
	var meteor: Node3D = world.make_resource("iridio")
	meteor.scale *= 2.0
	root.add_child(meteor)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.6, 0.35, 1.0)
	glow.light_energy = 1.2
	glow.omni_range = 6.0
	glow.position = Vector3(0, 1.2, 0)
	root.add_child(glow)
	return root


static func _deposit(world: Node3D, root: Node3D, type: String, local: Vector3, pos: Vector3, basis: Basis, rng: RandomNumberGenerator) -> void:
	var global := pos + basis * local
	var node: Node3D = world.make_resource(type)
	node.position = Vector3(local.x, world.surface_height(global.x, global.z) - pos.y, local.z)
	node.rotation.y = rng.randf_range(0.0, TAU)
	root.add_child(node)


static func _crate(world: Node3D, root: Node3D, id: String, local: Vector3, pos: Vector3, basis: Basis) -> void:
	var global := pos + basis * local
	var crate := LootCrate.new()
	crate.id = id
	crate.position = Vector3(local.x, world.surface_height(global.x, global.z) - pos.y, local.z)
	crate.rotation.y = 0.3
	root.add_child(crate)


static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material, degrees := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	part.rotation_degrees = degrees
	parent.add_child(part)
	return part


static func _material(color: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.6
	return material
