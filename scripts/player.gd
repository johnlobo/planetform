extends CharacterBody3D
## Jugador en primera persona: movimiento, cámara y la herramienta de mano
## con sus tres modos (recoger, construir y desmontar), los propulsores y la
## conducción del róver.

const Tool := preload("res://scripts/tool.gd")
const Machine := preload("res://scripts/machine.gd")
const Rover := preload("res://scripts/rover.gd")

const SPEED := 6.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const REACH := 4.0
const WADE_FACTOR := 0.55
const STEP_DISTANCE := 2.2 # metros entre pisadas
const LANDING_MIN_AIR_TIME := 0.25 # segundos en el aire para que suene el aterrizaje
# Propulsores: con Espacio pulsado en el aire empujan hacia arriba hasta
# JET_MAX_RISE m/s y dejan ir más rápido en horizontal.
const JET_ACCEL := 20.0 # m/s², algo más del doble de la gravedad
const JET_MAX_RISE := 6.0
const JET_SPEED_FACTOR := 1.6
const JET_DRAIN := 33.0 # combustible por segundo: el depósito dura 3 s
const JET_REFILL := 20.0 # por segundo con los pies en el suelo
# Escaleras: W o Espacio suben, S baja; dentro del hueco se va hacia el centro.
const CLIMB_SPEED := 2.5
const CLIMB_PULL := 4.0

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
# Conduciendo: el róver y hacia dónde se mira respecto a su morro.
var rover: Rover
var _drive_yaw := 0.0
var _jetting := false
# Minando: se pulsó el ratón sobre un depósito y aún no se ha soltado. La
# barra avanza mientras se siga apuntando al mismo.
var _mining := false
var _mine_target: Object
# true una vez avisado de que la mochila está llena, hasta soltar el ratón.
var _full_warned := false
# Linterna en el casco: se ve solo con Game.flashlight_on.
var _flashlight: SpotLight3D


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
	camera.far = 700.0
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

	_flashlight = SpotLight3D.new()
	_flashlight.spot_range = 28.0
	_flashlight.spot_angle = 28.0
	_flashlight.light_energy = 2.5
	_flashlight.light_color = Color(1.0, 0.95, 0.85)
	_flashlight.position = Vector3(0.15, 0.05, 0.0)
	_flashlight.visible = false
	camera.add_child(_flashlight)

	spawn_point = global_position
	Game.player_respawned.connect(_on_respawned)


func _unhandled_input(event: InputEvent) -> void:
	if Game.ui_open:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		if rover:
			_drive_yaw = clampf(_drive_yaw - event.relative.x * MOUSE_SENSITIVITY, -2.2, 2.2)
		else:
			rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(camera.rotation.x, -1.4, 1.4)
	elif rover:
		# Conduciendo solo se puede bajar (el inventario lo abre el HUD con I).
		if event.is_action_pressed("interact"):
			get_out()
		elif event is InputEventMouseButton and event.pressed and not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
		if target is Rover:
			get_in(target)
		elif target is Machine and target.is_storage():
			Game.locker_requested.emit(target)
		elif target is Machine and target.is_usable():
			target.use()
		elif target and target.has_method("open_crate"):
			target.open_crate()
	elif event.is_action_pressed("flashlight"):
		Game.toggle_flashlight()


func _physics_process(delta: float) -> void:
	_flashlight.visible = Game.flashlight_on and Game.has_flashlight
	if rover:
		_ride()
		return
	var ladder: Node3D = world.ladder_at(global_position + Vector3(0, 0.3, 0))
	if ladder:
		_climb(ladder)
		_update_hint()
		return
	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Vector2.ZERO
	if not Game.ui_open:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	_update_jetpack(delta)

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# Con el agua por encima de las rodillas se anda más despacio.
	var speed := SPEED * (WADE_FACTOR if world.water_depth(global_position) > Game.WADE_DEPTH else 1.0)
	if _jetting:
		speed *= JET_SPEED_FACTOR
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

	_update_mining(delta)
	_update_hint()


## En la escalera no hay gravedad: se sube y se baja con W/Espacio y S, y
## dentro del hueco se va hacia el centro para pasar por la trampilla.
func _climb(ladder: Node3D) -> void:
	var input_dir := Vector2.ZERO
	var up := false
	if not Game.ui_open:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		up = Input.is_action_pressed("jump")
	var climb := -input_dir.y
	if up:
		climb = 1.0
	velocity.y = climb * CLIMB_SPEED
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * SPEED * 0.5
	velocity.z = direction.z * SPEED * 0.5
	var local := ladder.to_local(global_position)
	if local.y < ladder.STOREY:
		var to_center: Vector3 = ladder.hatch_center() - global_position
		velocity.x += to_center.x * CLIMB_PULL
		velocity.z += to_center.z * CLIMB_PULL
	move_and_slide()


## Con el ratón pulsado sobre un depósito se llena la barra; al llenarse se
## recoge entero. Cuánto tarda y cuánto da depende del taladro.
func _update_mining(delta: float) -> void:
	var target := _target()
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Game.ui_open or Game.placing \
			or Game.tool_mode != "recoger" or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_mining = false
	if not _mining or target == null or not target.has_method("harvest"):
		_mine_target = null
		_full_warned = false
		Game.mine_progress = -1.0
		return
	if target != _mine_target:
		_mine_target = target
		Game.mine_progress = 0.0
		if Game.drill_level < target.required_drill():
			Game.message.emit("Para el %s necesitas el %s." % [
				String(Game.RESOURCE_NAMES[target.resource_type]).to_lower(),
				String(Game.DRILLS[target.required_drill()]["name"]).to_lower()])
	if Game.drill_level < target.required_drill():
		Game.mine_progress = -1.0
		return
	# Con la mochila llena la barra no avanza.
	if Game.room_for(target.resource_type) <= 0:
		if not _full_warned:
			_full_warned = true
			Game.message.emit(Game.FULL_MESSAGE)
		Game.mine_progress = 0.0
		return
	_full_warned = false
	var drill := Game.drill()
	Game.mine_progress += delta / float(drill["time"])
	if Game.mine_progress < 1.0:
		return
	Game.mine_progress = 0.0
	# Lo que no cabe se queda en el depósito.
	var amount: int = target.harvest(int(drill["yield"]), Game.room_for(target.resource_type))
	if amount > 0:
		Sfx.play("recoger", 0.05)
		Game.tool_used.emit(ray.get_collision_point())
		Game.add_item(target.resource_type, amount)
		Game.message.emit("+%d %s (%d / %d casillas)" % [amount, Game.RESOURCE_NAMES[target.resource_type], Game.slots_used(), Game.slots_max()])


## Los propulsores empujan mientras se mantiene Espacio en el aire y se
## rellenan solos al pisar el suelo.
func _update_jetpack(delta: float) -> void:
	_jetting = false
	if not Game.has_jetpack:
		return
	if is_on_floor():
		Game.jetpack_fuel = minf(Game.JETPACK_FUEL_MAX, Game.jetpack_fuel + JET_REFILL * delta)
		return
	if Game.ui_open or not Input.is_action_pressed("jump") or Game.jetpack_fuel <= 0.0:
		return
	_jetting = true
	velocity.y = minf(JET_MAX_RISE, velocity.y + JET_ACCEL * delta)
	Game.jetpack_fuel = maxf(0.0, Game.jetpack_fuel - JET_DRAIN * delta)


## Sentado en el róver: el jugador va donde el asiento y mira hacia su morro
## más lo que se gire con el ratón.
func _ride() -> void:
	if not is_instance_valid(rover):
		rover = null
		return
	global_position = rover.seat_position()
	rotation.y = rover.global_rotation.y + _drive_yaw
	velocity = Vector3.ZERO
	Game.hint = rover.drive_hint()


func get_in(target: Rover) -> void:
	rover = target
	_drive_yaw = 0.0
	# Sentado, el jugador y el róver no chocan entre sí.
	add_collision_exception_with(target)
	ray.add_exception(target)
	tool.visible = false
	Game.set_tool_mode("recoger")
	rover.enter(self)
	Sfx.play("clic")


func get_out() -> void:
	if rover == null:
		return
	var out := rover.exit_position()
	# Que no quede enterrado si se baja en una cuesta.
	out.y = maxf(out.y, world.surface_height(out.x, out.z) + 0.1)
	ray.remove_exception(rover)
	rover.exit()
	var left := rover
	rover = null
	global_position = out
	velocity = Vector3.ZERO
	# Vuelven a chocar cuando la física ya tiene al jugador fuera; si no, el
	# róver saldría disparado.
	get_tree().create_timer(0.3, false, true).timeout.connect(func():
		if is_instance_valid(left) and left != rover:
			remove_collision_exception_with(left))
	tool.visible = true
	Game.hint = ""
	Sfx.play("clic")


## Lleva al jugador a otro sitio del mapa (telepuerto) y prepara ya el
## terreno de allí para que no caiga a través del suelo.
func teleport_to(pos: Vector3) -> void:
	get_out()
	global_position = pos
	velocity = Vector3.ZERO
	world.land.load_around(pos)


## Donde se guarda al jugador: si conduce, junto al róver.
func saved_position() -> Vector3:
	return rover.exit_position() if rover else global_position


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
			if (target is Machine or target is Rover) and target.is_storage():
				Game.locker_requested.emit(target)
			elif target is Machine and target.is_usable():
				target.use()
			elif target and target.has_method("open_crate"):
				target.open_crate()
			elif target and target.has_method("harvest"):
				_mining = true # sigue en _update_mining mientras no se suelte


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
	get_out()
	var bed = Game.spawn_bed()
	# Junto a la cama donde se durmió por última vez, o en la base.
	global_position = bed + Vector3(0, 0.8, 0) if bed != null else spawn_point
	velocity = Vector3.ZERO
