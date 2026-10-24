extends Node
## Iconos del menú de construcción. Cada pieza se dibuja una vez en un
## SubViewport con su propio mundo, luz y cámara, y la imagen se guarda como
## textura. Así no hacen falta archivos de imagen.

signal finished

const Machine := preload("res://scripts/machine.gd")
const Module := preload("res://scripts/module.gd")
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
	var machine := Machine.new()
	machine.setup(kind)
	machine.set_process(false)
	if Game.MACHINES[kind].has("display"):
		# Barras a medias para que se vea que es una pantalla.
		machine.update_screen(0.6)
	# Sin colisión: en este mundo aparte no tiene nada con lo que chocar.
	machine.collision_layer = 0
	return machine


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
