extends CharacterBody3D
## Jugador en primera persona: movimiento, cámara y recolección.

const SPEED := 6.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const REACH := 4.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var camera: Camera3D
var ray: RayCast3D
var spawn_point := Vector3.ZERO


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
	camera.add_child(ray)

	spawn_point = global_position
	Game.player_suffocated.connect(_on_suffocated)


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
	elif event.is_action_pressed("use_bottle"):
		Game.use_bottle()
	elif event.is_action_pressed("new_game"):
		Game.new_game()
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
	if direction != Vector3.ZERO:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	move_and_slide()

	# Red de seguridad por si el jugador atraviesa el terreno.
	if global_position.y < -50.0:
		global_position = spawn_point

	_update_hint()


func _update_hint() -> void:
	Game.hint = ""
	if ray.is_colliding():
		var target = ray.get_collider()
		if target and target.has_method("get_hint"):
			Game.hint = target.get_hint()


func _interact() -> void:
	if not ray.is_colliding():
		return
	var target = ray.get_collider()
	if target and target.has_method("harvest"):
		var amount: int = target.harvest(2 if Game.has_drill else 1)
		if amount > 0:
			Game.add_item(target.resource_type, amount)
			Game.message.emit("+%d %s" % [amount, Game.RESOURCE_NAMES[target.resource_type]])


func _on_suffocated() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
