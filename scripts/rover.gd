extends VehicleBody3D
## Róver de exploración: cuatro ruedas, un maletero pequeño y una batería que
## se gasta al acelerar y se recarga aparcado junto a un punto de recarga.
## Se sube y se baja con E; mientras nadie lo conduce está quieto (congelado),
## así no se cae si el trozo del terreno donde está se borra al alejarse.

const MAX_ENGINE_FORCE := 700.0
const MAX_BRAKE := 40.0
const MAX_STEER := 0.5 # radianes
const STEER_SPEED := 2.5 # radianes por segundo
const MAX_SPEED := 16.0 # metros por segundo
const BATTERY_MAX := 100.0
const BATTERY_DRAIN := 0.8 # por segundo con el acelerador pisado
const CHARGE_RATE := 5.0 # por segundo junto a un punto de recarga con energía
const CHARGE_RANGE := 6.0 # metros
const LOW_BATTERY := 20.0
const TRUNK := 20 # unidades que caben en el maletero
# Al bajar se espera a que se pare antes de congelarlo.
const PARK_SPEED := 0.3
const SEAT := Vector3(0.0, 0.95, 0.3) # donde van los pies del jugador sentado
const EXIT := Vector3(-2.0, 0.2, 0.0) # se baja por la izquierda

var kind := "rover"
## Entrada de Game.vehicles que se guarda con la partida.
var data := {}
## Caja que ocupa en el suelo, para el modo de colocación.
var footprint := Vector3(2.2, 1.6, 3.4)
var driver: Node3D
var _wheels: Array[VehicleWheel3D] = []
var _was_low := false
var _was_empty := false
# Segundos que le quedan sin congelarse aunque esté parado, para que asiente
# las ruedas al colocarlo o al bajarse.
var _settle := 0.0


func setup(vehicle_kind: String) -> void:
	kind = vehicle_kind
	mass = 400.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.2, 0) # bajo, para que no vuelque
	freeze = true
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.9, 0.9, 0.86)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.95, 0.55, 0.15)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.22, 0.25)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.3, 0.55, 0.75, 0.55)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	# Chasis, asiento con respaldo y morro, que va hacia -Z.
	_box(Vector3(1.8, 0.35, 3.0), Vector3(0, 0.75, 0), body_material)
	_box(Vector3(1.9, 0.08, 3.1), Vector3(0, 0.6, 0), accent)
	_box(Vector3(0.7, 0.15, 0.6), Vector3(0, 1.0, 0.3), dark)
	_box(Vector3(0.7, 0.6, 0.12), Vector3(0, 1.3, 0.6), dark)
	_box(Vector3(1.6, 0.35, 0.8), Vector3(0, 1.1, -1.0), body_material)
	_box(Vector3(1.4, 0.4, 0.06), Vector3(0, 1.45, -0.6), glass).rotation_degrees.x = -20.0
	# Maletero detrás del asiento.
	_box(Vector3(1.5, 0.5, 0.8), Vector3(0, 1.2, 1.1), accent)
	_box(Vector3(1.52, 0.05, 0.82), Vector3(0, 1.46, 1.1), dark)
	# Faros y una antena.
	var light := StandardMaterial3D.new()
	light.albedo_color = Color(1.0, 0.95, 0.7)
	light.emission_enabled = true
	light.emission = Color(1.0, 0.9, 0.6)
	for sx in [-0.55, 0.55]:
		_box(Vector3(0.3, 0.15, 0.05), Vector3(sx, 0.95, -1.42), light)
	var antenna := CylinderMesh.new()
	antenna.top_radius = 0.02
	antenna.bottom_radius = 0.03
	antenna.height = 1.2
	antenna.radial_segments = 4
	_mesh(antenna, Vector3(0.65, 2.0, 1.35), dark)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 0.9, 3.0)
	collision.shape = shape
	collision.position.y = 1.0
	add_child(collision)
	# Ruedas: las de delante giran y todas empujan.
	var tire := CylinderMesh.new()
	tire.top_radius = 0.45
	tire.bottom_radius = 0.45
	tire.height = 0.35
	tire.radial_segments = 8
	var hub := CylinderMesh.new()
	hub.top_radius = 0.2
	hub.bottom_radius = 0.2
	hub.height = 0.37
	hub.radial_segments = 6
	for corner in [Vector3(-1.0, 0.55, -1.05), Vector3(1.0, 0.55, -1.05), Vector3(-1.0, 0.55, 1.05), Vector3(1.0, 0.55, 1.05)]:
		var wheel := VehicleWheel3D.new()
		wheel.position = corner
		wheel.use_as_traction = true
		wheel.use_as_steering = corner.z < 0.0
		wheel.wheel_radius = 0.45
		wheel.wheel_rest_length = 0.25
		wheel.suspension_travel = 0.3
		wheel.suspension_stiffness = 40.0
		wheel.suspension_max_force = 12000.0
		wheel.damping_compression = 1.5
		wheel.damping_relaxation = 2.0
		wheel.wheel_friction_slip = 5.0
		wheel.wheel_roll_influence = 0.1
		add_child(wheel)
		var t := _mesh(tire, Vector3.ZERO, dark, wheel)
		t.rotation_degrees.z = 90.0
		var h := _mesh(hub, Vector3.ZERO, accent, wheel)
		h.rotation_degrees.z = 90.0
		# Con el freno echado mientras nadie conduce. Se pone en cada rueda: el
		# freno del vehículo solo llega a las ruedas ya metidas en el árbol.
		wheel.brake = MAX_BRAKE
		_wheels.append(wheel)


func _box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	return _mesh(box, pos, material)


func _mesh(mesh: Mesh, pos: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	part.material_override = material
	(parent if parent else self).add_child(part)
	return part


## Convierte el róver en una silueta sin colisión para el modo de colocación.
func make_ghost(material: Material) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			remove_child(child)
			child.free()
	_tint(self, material)
	set_physics_process(false)


static func _tint(node: Node, material: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.material_override = material
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tint(child, material)


func battery() -> float:
	return float(data.get("battery", BATTERY_MAX))


func is_storage() -> bool:
	return true


## Al maletero se puede meter cualquier cosa.
func accepts_items() -> bool:
	return true


func capacity() -> int:
	return TRUNK


func items() -> Dictionary:
	if not data.has("items"):
		data["items"] = {}
	return data["items"]


func stored_total() -> int:
	var total := 0
	for id in items():
		total += int(items()[id])
	return total


func get_hint() -> String:
	var charging := " · cargando" if _charging() else ""
	return "%s · batería %d %%%s · E subir · clic abrir maletero (%d / %d)" % [
		Game.RECIPES[kind]["name"], roundi(battery()), charging, stored_total(), capacity()]


## Lo que se ve abajo mientras se conduce.
func drive_hint() -> String:
	var speed := linear_velocity.length() * 3.6
	var state := " · sin batería" if battery() <= 0.0 else (" · cargando" if _charging() else "")
	return "Róver · %d km/h · batería %d %%%s · W S acelerar y frenar · A D girar · Espacio freno · E bajar" % [
		roundi(speed), roundi(battery()), state]


## Recién colocado: cae y asienta las ruedas antes de quedarse quieto.
func drop() -> void:
	freeze = false
	_settle = 1.5


func enter(player: Node3D) -> void:
	driver = player
	freeze = false
	sleeping = false
	Game.vehicle = self
	Game.driving_changed.emit(true)
	if battery() <= 0.0:
		Game.message.emit("El róver no tiene batería: déjalo junto a un punto de recarga.")


func exit() -> void:
	driver = null
	engine_force = 0.0
	brake = MAX_BRAKE
	steering = 0.0
	_settle = 1.5
	if Game.vehicle == self:
		Game.vehicle = null
	Game.driving_changed.emit(false)


## Sitio donde el jugador se queda al bajar.
func exit_position() -> Vector3:
	return global_transform * EXIT


func seat_position() -> Vector3:
	return global_transform * SEAT


func _physics_process(delta: float) -> void:
	if data.is_empty():
		return
	_settle -= delta
	var charge := battery()
	if _charging():
		charge = minf(BATTERY_MAX, charge + CHARGE_RATE * Game.energy_ratio() * delta)
	if driver:
		var throttle := 0.0
		var turn := 0.0
		if not Game.ui_open and not Game.dead:
			throttle = Input.get_axis("move_back", "move_forward")
			turn = Input.get_axis("move_right", "move_left")
		# Hacia delante es -Z: la velocidad en ese eje dice si va marcha atrás.
		var forward_speed := -global_basis.z.dot(linear_velocity)
		var braking := Input.is_action_pressed("jump") and not Game.ui_open
		if charge <= 0.0:
			throttle = 0.0
		# Pisar al revés de como se mueve primero frena.
		if throttle != 0.0 and signf(throttle) != signf(forward_speed) and absf(forward_speed) > 1.0:
			brake = MAX_BRAKE
			engine_force = 0.0
		else:
			brake = MAX_BRAKE if braking else 0.0
			var limit := 1.0 if absf(forward_speed) < MAX_SPEED else 0.0
			engine_force = -throttle * MAX_ENGINE_FORCE * limit * (0.5 if throttle < 0.0 else 1.0)
		if throttle != 0.0:
			charge = maxf(0.0, charge - BATTERY_DRAIN * absf(throttle) * delta)
		steering = move_toward(steering, turn * MAX_STEER, STEER_SPEED * delta)
		if throttle == 0.0 and not braking:
			brake = 0.4 # rueda suelta, pero sin quedarse rodando para siempre
	elif not freeze and linear_velocity.length() < PARK_SPEED and _settle <= 0.0:
		# Parado y sin conductor: se congela hasta que alguien se suba.
		freeze = true
	data["battery"] = charge
	_warn_battery(charge)
	if not freeze:
		var p := global_position
		data["x"] = p.x
		data["y"] = p.y
		data["z"] = p.z
		data["rot"] = global_rotation.y
		# Si vuelca, se pone otra vez de pie.
		if driver and global_basis.y.y < 0.2 and linear_velocity.length() < 1.0:
			global_basis = Basis(Vector3.UP, global_rotation.y)
			global_position += Vector3(0, 1.0, 0)


func _warn_battery(charge: float) -> void:
	if driver == null:
		_was_low = charge <= LOW_BATTERY
		_was_empty = charge <= 0.0
		return
	var low := charge <= LOW_BATTERY
	if low and not _was_low:
		Game.message.emit("Batería del róver baja: vuelve a un punto de recarga.")
		Sfx.play("alarma", 0.0, -8.0)
	_was_low = low
	var empty := charge <= 0.0
	if empty and not _was_empty:
		Game.message.emit("El róver se ha quedado sin batería.")
	_was_empty = empty


## Junto a un punto de recarga que tiene energía.
func _charging() -> bool:
	if battery() >= BATTERY_MAX or Game.energy_ratio() <= 0.0:
		return false
	for m in Game.machines:
		if String(m["kind"]) != "cargador":
			continue
		var pos := Vector3(float(m["x"]), float(m["y"]), float(m["z"]))
		if pos.distance_to(global_position) <= CHARGE_RANGE:
			return true
	return false
