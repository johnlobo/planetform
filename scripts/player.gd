extends CharacterBody3D
## Jugador en primera persona: movimiento, cámara y la herramienta de mano
## con sus tres modos (recoger, construir y desmontar).

const Tool := preload("res://scripts/tool.gd")
const Machine := preload("res://scripts/machine.gd")

const SPEED := 6.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const REACH := 4.0
const WADE_DEPTH := 0.4 # metros de agua a partir de los que se anda más despacio
const WADE_FACTOR := 0.55
const STEP_DISTANCE := 2.2 # metros entre pisadas
const LANDING_MIN_AIR_TIME := 0.25 # segundos en el aire para que suene el aterrizaje

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var camera: Camera3D
var ray: RayCast3D
var spawn_point := Vector3.ZERO
var world: Node3D # el nodo main: sabe desmontar lo construido
var tool: Node3D
# Lo que se ilumina en rojo al apuntarlo en modo desmontar.
var _highlighted: Node3D
var _highlight := _highlight_material()
var _step_travel := 0.0
var _air_time := 0.0


func _ready() -> void:
	add_to_group("player")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	shape.shape = capsule
	shape.position.y = 0.8
	add_child(shape)

	camera = Camera3D.new()
	camera.position.y = 1.35
	camera.far = 300.0
	add_child(camera)
	camera.make_current()

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.add_exception(self)
	# También ve el musgo (capa 2) y la superficie del agua (un Area3D).
	ray.collision_mask = 1 | 2
	ray.collide_with_areas = true
	camera.add_child(ray)

	camera.near = 0.02 # la herramienta va muy cerca de la cámara
	tool = Tool.new()
	tool.player = self
	camera.add_child(tool)

	spawn_point = global_position
	Game.player_respawned.connect(_on_respawned)


func _unhandled_input(event: InputEvent) -> void:
	if Game.ui_open:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(camera.rotation.x, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if captured:
			_interact()
		else:
			# En el navegador el ratón solo se puede capturar tras un clic.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and captured \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# Con la rueda se pasa de un modo al siguiente (al colocar, gira la pieza).
		var step := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		var i := Game.TOOL_MODES.find(Game.tool_mode)
		_set_mode(Game.TOOL_MODES[posmod(i + step, Game.TOOL_MODES.size())], false)
	elif event.is_action_pressed("tool_recoger"):
		_set_mode("recoger", false)
	elif event.is_action_pressed("tool_construir"):
		_set_mode("construir", true)
	elif event.is_action_pressed("tool_desmontar"):
		_set_mode("desmontar", false)
	elif event.is_action_pressed("interact"):
		var target = ray.get_collider() if ray.is_colliding() else null
		if target is Machine and target.is_storage():
			Game.locker_requested.emit(target)
	elif event.is_action_pressed("use_bottle"):
		Game.use_bottle()
	elif event.is_action_pressed("eat"):
		Game.eat()
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Vector2.ZERO
	if not Game.ui_open:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# Con el agua por encima de las rodillas se anda más despacio.
	var speed := SPEED * (WADE_FACTOR if world.water_depth(global_position) > WADE_DEPTH else 1.0)
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	var was_on_floor := is_on_floor()
	move_and_slide()
	_update_steps(delta, was_on_floor)

	# Red de seguridad por si el jugador atraviesa el terreno.
	if global_position.y < -50.0:
		global_position = spawn_point

	_update_hint()


func _update_steps(delta: float, was_on_floor: bool) -> void:
	if not is_on_floor():
		_air_time += delta
		return
	if not was_on_floor:
		# Al aparecer o reaparecer el jugador toca el suelo enseguida: eso no
		# es un aterrizaje y no debe sonar.
		if _air_time >= LANDING_MIN_AIR_TIME:
			Sfx.play("paso", 0.1, 3.0) # aterrizaje
		_air_time = 0.0
		_step_travel = 0.0
		return
	_step_travel += Vector2(velocity.x, velocity.z).length() * delta
	if _step_travel >= STEP_DISTANCE:
		_step_travel = 0.0
		Sfx.play("paso", 0.15)


## Cambia el modo de la herramienta. Con open_menu, al pasar a construir se
## abre directamente el menú de construcción.
func _set_mode(mode: String, open_menu: bool) -> void:
	if mode != Game.tool_mode:
		Sfx.play("clic")
	Game.set_tool_mode(mode)
	if mode == "construir" and open_menu and not Game.placing:
		Game.build_menu_requested.emit()


func _target() -> Object:
	return ray.get_collider() if ray.is_colliding() else null


func _update_hint() -> void:
	var target := _target()
	var info := {}
	if Game.tool_mode == "desmontar" and not Game.placing and target:
		info = world.dismantle_info(target)
	_set_highlight(info.get("node"))
	if Game.placing:
		return # el modo de colocación escribe su propia ayuda
	Game.hint = ""
	match Game.tool_mode:
		"recoger":
			if target and target.has_method("get_hint"):
				Game.hint = target.get_hint()
		"construir":
			Game.hint = "Clic para elegir qué construir"
		"desmontar":
			if info.is_empty():
				return
			if info.has("reason"):
				Game.hint = "%s · %s" % [info["name"], info["reason"]]
			else:
				Game.hint = "Desmontar %s · clic · devuelve %s" % [info["name"], Game.cost_text(info["refund"])]


func _interact() -> void:
	var target := _target()
	match Game.tool_mode:
		"construir":
			Game.build_menu_requested.emit()
		"desmontar":
			if target == null:
				return
			var point := ray.get_collision_point()
			if world.dismantle(target):
				_highlighted = null
				Game.tool_used.emit(point)
		"recoger":
			if target is Machine and target.is_storage():
				Game.locker_requested.emit(target)
			elif target and target.has_method("harvest"):
				var amount: int = target.harvest(2 if Game.has_drill else 1)
				if amount > 0:
					Sfx.play("recoger", 0.05)
					Game.tool_used.emit(ray.get_collision_point())
					Game.add_item(target.resource_type, amount)
					Game.message.emit("+%d %s" % [amount, Game.RESOURCE_NAMES[target.resource_type]])


## Tiñe de rojo lo que se va a desmontar.
func _set_highlight(node: Node3D) -> void:
	if node == _highlighted:
		return
	if is_instance_valid(_highlighted):
		_overlay(_highlighted, null)
	_highlighted = node
	if node:
		_overlay(node, _highlight)


static func _overlay(node: Node, material: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.material_overlay = material
		_overlay(child, material)


static func _highlight_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.15, 0.1, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _on_respawned() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
