extends Node3D
## Modo de colocación: una silueta de la construcción sigue a la mirada del
## jugador, verde donde se puede construir y roja donde no. Clic izquierdo
## la coloca, R o la rueda del ratón la giran y clic derecho o Esc cancelan.

const Machine := preload("res://scripts/machine.gd")
const Player := preload("res://scripts/player.gd")

const REACH := 10.0 # metros desde la cámara
const MAX_SLOPE := 0.7 # diferencia de altura máxima entre las esquinas, en metros
const ROTATE_STEP := PI / 12.0 # 15 grados por paso de rueda
const SPACING := 0.2 # holgura entre construcciones, en metros

var world: Node3D # el nodo main: da la altura del terreno y el nivel del agua
var terrain: CollisionObject3D
var player: Player

var _kind := ""
var _ghost: Machine
var _rotation := 0.0
var _valid := false
var _reason := ""
var _green := _ghost_material(Color(0.2, 1.0, 0.35, 0.45))
var _red := _ghost_material(Color(1.0, 0.2, 0.15, 0.45))
var _box := BoxShape3D.new()


func start(kind: String) -> void:
	cancel()
	_kind = kind
	_rotation = 0.0
	_ghost = Machine.new()
	_ghost.setup(kind)
	_ghost.make_ghost(_green)
	add_child(_ghost)
	Game.placing = true
	_update_ghost()


func cancel() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_kind = ""
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
	elif event.is_action_pressed("release_mouse"):
		cancel()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if _ghost == null:
		return
	# Abrir el crafteo o morir cancela la colocación.
	if Game.ui_open or Game.dead:
		cancel()
		return
	_update_ghost()


func _update_ghost() -> void:
	var camera := player.camera
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * REACH)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3 = hit["position"] if hit else from + forward * REACH
	point.y = world.surface_height(point.x, point.z)
	var rot := player.rotation.y + _rotation
	_ghost.global_position = point
	_ghost.rotation.y = rot
	_reason = _check(point, rot, not hit.is_empty())
	_valid = _reason == ""
	_ghost.make_ghost(_green if _valid else _red)
	var recipe_name: String = Game.RECIPES[_kind]["name"]
	if _valid:
		Game.hint = "%s · clic colocar · R girar · clic derecho cancelar" % recipe_name
	else:
		Game.hint = "%s · %s" % [recipe_name, _reason]


## Devuelve por qué no se puede construir en ese punto, o "" si se puede.
func _check(point: Vector3, rot: float, in_reach: bool) -> String:
	if not in_reach:
		return "demasiado lejos"
	var limit: float = world.WORLD_SIZE * 0.48
	if absf(point.x) > limit or absf(point.z) > limit:
		return "fuera de la zona"
	if world.water.visible and point.y < world.water.position.y + 0.1:
		return "bajo el agua"
	var size: Vector3 = _ghost.footprint
	var basis := Basis(Vector3.UP, rot)
	var lowest := INF
	var highest := -INF
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		var p: Vector3 = point + basis * (corner * size * 0.5)
		var h: float = world.surface_height(p.x, p.z)
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	if highest - lowest > MAX_SLOPE:
		return "terreno demasiado inclinado"
	# Choca con otra construcción, un recurso o el propio jugador.
	_box.size = size + Vector3(SPACING, 0.0, SPACING)
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = _box
	shape_query.transform = Transform3D(basis, point + Vector3(0, size.y / 2.0 + 0.05, 0))
	shape_query.exclude = [terrain.get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(shape_query, 1).is_empty():
		return "no hay sitio"
	return ""


func _confirm() -> void:
	if not _valid:
		Sfx.play("alarma", 0.0, -12.0)
		Game.message.emit("Aquí no se puede construir: %s." % _reason)
		return
	var kind := _kind
	var pos := _ghost.global_position
	var rot := _ghost.rotation.y
	if not Game.build(kind, pos, rot):
		Game.message.emit("Te faltan materiales.")
		cancel()
		return
	world.spawn_machine(kind, pos, rot)
	Sfx.play("colocar")
	cancel()


static func _ghost_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_fog = true
	return material
