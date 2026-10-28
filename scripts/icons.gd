extends Node
## Iconos del menú de fabricar y construir. Cada pieza se dibuja una vez en un
## SubViewport con su propio mundo, luz y cámara, y la imagen se guarda como
## textura. Así no hacen falta archivos de imagen.

signal finished

const Machine := preload("res://scripts/machine.gd")
const Module := preload("res://scripts/module.gd")
const Rover := preload("res://scripts/rover.gd")
const SIZE := 128

## {pieza: ImageTexture}; vacío hasta que se emite finished.
var textures := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Dibuja todas las piezas a la vez y espera a que la tarjeta gráfica las pinte.
func render(kinds: Array) -> void:
	var viewports := {}
	for kind in kinds:
		viewports[kind] = _scene(kind)
	# Un fotograma para preparar la escena y otro para tenerla ya dibujada.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for kind in viewports:
		var viewport: SubViewport = viewports[kind]
		textures[kind] = ImageTexture.create_from_image(viewport.get_texture().get_image())
		viewport.queue_free()
	finished.emit()


func _scene(kind: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	environment.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	viewport.add_child(world_env)
	var light := DirectionalLight3D.new()
	# Luz desde el lado de la cámara, que mira desde delante a la derecha.
	light.rotation_degrees = Vector3(-45.0, 150.0, 0.0)
	light.light_energy = 1.1
	viewport.add_child(light)

	var model := _model(kind)
	viewport.add_child(model)
	var box := _bounds(model, Transform3D.IDENTITY)
	var center := box.get_center()
	var radius := box.size.length() / 2.0

	var camera := Camera3D.new()
	camera.fov = 30.0
	viewport.add_child(camera)
	# Vista de tres cuartos desde delante (-Z) y algo de arriba; las puertas y
	# ventanas se miran más de frente para que se vea el hueco.
	var direction := Vector3(0.55, 0.45, -1.0) if Game.RECIPES[kind]["kind"] == "fitting" else Vector3(0.8, 0.7, -1.0)
	var distance := radius / sin(deg_to_rad(camera.fov / 2.0)) * 1.05
	camera.look_at_from_position(center + direction.normalized() * distance, center)
	return viewport


func _model(kind: String) -> Node3D:
	match String(Game.RECIPES[kind]["kind"]):
		"tool", "consumable":
			return _item(kind)
		"module":
			var module := Module.new()
			module.setup({}, true)
			return module
		"fitting":
			# Solo la pared delantera de un módulo con la pieza puesta.
			var module := Module.new()
			module.setup({"sides": [kind, "pared", "pared", "pared"]}, true)
			for child in module.get_children():
				if not (child.has_meta("side") and int(child.get_meta("side")) == 0):
					child.visible = false
			return module
		"vehicle":
			var rover := Rover.new()
			rover.setup(kind)
			rover.set_physics_process(false)
			rover.collision_layer = 0
			return rover
	var machine := Machine.new()
	machine.setup(kind)
	machine.set_process(false)
	if Game.MACHINES[kind].has("display"):
		# Barras a medias para que se vea que es una pantalla.
		machine.update_screen(0.6)
	# Sin colisión: en este mundo aparte no tiene nada con lo que chocar.
	machine.collision_layer = 0
	return machine


## Herramientas y consumibles: no existen en el mundo, así que su modelo
## solo se usa aquí, hecho con unas pocas piezas de pocos lados.
func _item(kind: String) -> Node3D:
	var root := Node3D.new()
	var metal := _material(Color(0.62, 0.65, 0.7), 0.6)
	var dark := _material(Color(0.22, 0.24, 0.27), 0.3)
	match kind:
		"taladro":
			var body := _part(root, _cylinder(0.22, 0.22, 0.9, 6), _material(Color(0.95, 0.55, 0.15), 0.1), Vector3(0, 0.3, 0))
			body.rotation_degrees.z = 90.0
			var bit := _part(root, _cylinder(0.12, 0.0, 0.7, 5), metal, Vector3(-0.8, 0.3, 0))
			bit.rotation_degrees.z = 90.0
			var grip := _part(root, _box(Vector3(0.22, 0.6, 0.24)), dark, Vector3(0.25, -0.1, 0))
			grip.rotation_degrees.z = -12.0
		"jetpack":
			_part(root, _box(Vector3(0.9, 1.0, 0.18)), dark, Vector3(0, 0.1, 0.2))
			var tank := _material(Color(0.85, 0.85, 0.88), 0.4)
			var flame := _material(Color(1.0, 0.6, 0.2), 0.0)
			flame.emission_enabled = true
			flame.emission = Color(1.0, 0.45, 0.1)
			for x in [-0.24, 0.24]:
				_part(root, _cylinder(0.2, 0.2, 1.0, 7), tank, Vector3(x, 0.15, 0))
				_part(root, _cylinder(0.0, 0.2, 0.18, 7), tank, Vector3(x, 0.74, 0))
				_part(root, _cylinder(0.1, 0.16, 0.2, 7), dark, Vector3(x, -0.45, 0))
				_part(root, _cylinder(0.1, 0.0, 0.3, 6), flame, Vector3(x, -0.7, 0))
		"botella":
			var glass := _material(Color(0.45, 0.75, 1.0), 0.2)
			_part(root, _cylinder(0.25, 0.25, 0.8, 7), glass, Vector3.ZERO)
			_part(root, _cylinder(0.12, 0.25, 0.2, 7), glass, Vector3(0, 0.5, 0))
			_part(root, _cylinder(0.13, 0.13, 0.14, 7), dark, Vector3(0, 0.67, 0))
			_part(root, _cylinder(0.26, 0.26, 0.16, 7), _material(Color(1, 1, 1), 0.0), Vector3(0, 0.05, 0))
		"tanque":
			var green := _material(Color(0.35, 0.7, 0.45), 0.4)
			var body := _part(root, _cylinder(0.35, 0.35, 1.1, 8), green, Vector3.ZERO)
			body.rotation_degrees.z = 90.0
			for x in [-0.55, 0.55]:
				var cap := _part(root, _sphere(0.35, 8), green, Vector3(x, 0, 0))
				cap.scale = Vector3(0.45, 1, 1)
			_part(root, _cylinder(0.07, 0.07, 0.3, 6), metal, Vector3(0, 0.45, 0))
			_part(root, _box(Vector3(0.3, 0.06, 0.06)), dark, Vector3(0, 0.6, 0))
		"semillas":
			var sack := _part(root, _sphere(0.5, 7), _material(Color(0.7, 0.55, 0.35), 0.0), Vector3.ZERO)
			sack.scale = Vector3(1, 0.9, 1)
			_part(root, _cylinder(0.14, 0.22, 0.3, 6), _material(Color(0.6, 0.45, 0.28), 0.0), Vector3(0, 0.55, 0))
			var sprout := _material(Color(0.35, 0.8, 0.3), 0.0)
			for i in 3:
				var leaf := _part(root, _sphere(0.1, 5), sprout, Vector3(-0.1 + 0.1 * i, 0.75 + 0.04 * (i % 2), 0))
				leaf.scale = Vector3(0.6, 1.3, 0.6)
		"guiso":
			_part(root, _cylinder(0.6, 0.35, 0.4, 9), _material(Color(0.85, 0.4, 0.25), 0.1), Vector3.ZERO)
			_part(root, _cylinder(0.55, 0.55, 0.06, 9), _material(Color(0.6, 0.38, 0.18), 0.0), Vector3(0, 0.17, 0))
			var veg := _material(Color(0.4, 0.75, 0.3), 0.0)
			var carrot := _material(Color(1.0, 0.6, 0.15), 0.0)
			for i in 4:
				var angle := i * TAU / 4.0 + 0.4
				_part(root, _sphere(0.1, 5), veg if i % 2 == 0 else carrot, Vector3(cos(angle) * 0.28, 0.22, sin(angle) * 0.28))
		_:
			_part(root, _box(Vector3.ONE * 0.6), metal, Vector3.ZERO)
	return root


func _part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	parent.add_child(part)
	return part


func _material(color: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.6
	return material


func _cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _sphere(radius: float, sides: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = sides
	mesh.rings = maxi(sides / 2, 3)
	return mesh


## Caja que envuelve las mallas visibles, en coordenadas del modelo.
func _bounds(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.get_children():
		if child is Node3D and not child.visible:
			continue
		var child_xform: Transform3D = xform * child.transform if child is Node3D else xform
		var box := AABB()
		var has_box := false
		if child is MeshInstance3D and child.mesh:
			box = child_xform * child.mesh.get_aabb()
			has_box = true
		var inner := _bounds(child, child_xform)
		if inner.size != Vector3.ZERO:
			box = box.merge(inner) if has_box else inner
			has_box = true
		if has_box:
			result = box if first else result.merge(box)
			first = false
	return result
