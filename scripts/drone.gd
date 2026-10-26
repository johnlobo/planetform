extends Node3D
## Dron recolector de una estación: vuela solo al depósito más cercano que
## nadie está recogiendo, se queda encima un rato, se lleva CARGO unidades y
## vuelve a dejarlas en la estación. Sin energía se queda en su plataforma.

const ResourceNode := preload("res://scripts/resource_node.gd")

const SPEED := 6.0 # metros por segundo
const CRUISE := 6.0 # metros por encima del camino recto, a mitad de viaje
const CLEARANCE := 2.0 # nunca más bajo que esto sobre el terreno
const RANGE := 70.0 # metros desde la estación hasta los depósitos que busca
const GATHER_TIME := 5.0
const CARGO := 1
const REST_TIME := 3.0 # segundos en la plataforma entre viaje y viaje
const SEARCH_TIME := 3.0 # si no hay depósitos, cada cuánto se vuelve a mirar

var station: Node3D # la Machine de la estación
var dock := Vector3.ZERO # posición de la plataforma, relativa a la estación
var _state := "docked" # docked, out, gathering, back
var _target: ResourceNode
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _travel := 0.0 # metros recorridos del viaje actual
var _timer := 0.0
var _carrying := {}
var _rotors: Array[Node3D] = []
var _light: MeshInstance3D


func _ready() -> void:
	top_level = true
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.85, 0.87, 0.9)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.22, 0.25)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.4, 1.0, 0.6)
	glow.emission_enabled = true
	glow.emission = Color(0.2, 0.9, 0.4)
	_box(Vector3(0.5, 0.18, 0.5), Vector3.ZERO, body_material, self)
	_light = _box(Vector3(0.2, 0.06, 0.2), Vector3(0, -0.12, 0), glow, self)
	for corner in [Vector3(-0.4, 0, -0.4), Vector3(0.4, 0, -0.4), Vector3(-0.4, 0, 0.4), Vector3(0.4, 0, 0.4)]:
		var arm := _box(Vector3(0.5, 0.05, 0.06), corner / 2.0, dark, self)
		arm.rotation.y = atan2(corner.x, corner.z) + PI / 2.0
		var rotor := Node3D.new()
		rotor.position = corner + Vector3(0, 0.08, 0)
		add_child(rotor)
		_box(Vector3(0.45, 0.02, 0.06), Vector3.ZERO, dark, rotor)
		_rotors.append(rotor)
	global_position = _dock_position()


func _box(size: Vector3, pos: Vector3, material: Material, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


func _dock_position() -> Vector3:
	return station.global_transform * dock


func _exit_tree() -> void:
	_release()


func _process(delta: float) -> void:
	var powered: bool = Game.energy_ratio() > 0.0
	var flying := _state != "docked"
	for rotor in _rotors:
		if flying or powered:
			rotor.rotate_y(delta * (40.0 if flying else 8.0))
	match _state:
		"docked":
			global_position = _dock_position()
			_timer -= delta
			if _timer <= 0.0 and powered:
				_launch()
		"out":
			if not _valid_target():
				_head_home()
			elif _fly(delta * Game.energy_ratio()):
				_state = "gathering"
				_timer = GATHER_TIME
		"gathering":
			if not _valid_target():
				_head_home()
				return
			# Se balancea un poco sobre el depósito mientras recoge.
			global_position = _to + Vector3(0, sin(Time.get_ticks_msec() * 0.004) * 0.1, 0)
			_timer -= delta * Game.energy_ratio()
			if _timer <= 0.0:
				var taken := _target.take(CARGO)
				if taken > 0:
					_carrying[_target.resource_type] = int(_carrying.get(_target.resource_type, 0)) + taken
				_head_home()
		"back":
			# Vuelve aunque falte energía, más despacio, para no quedarse perdido.
			_to = _dock_position()
			if _fly(delta * maxf(0.3, Game.energy_ratio())):
				_unload()


## Busca el depósito libre más cercano y sale hacia él.
func _launch() -> void:
	_target = _nearest_deposit()
	if _target == null:
		_timer = SEARCH_TIME
		return
	_target.set_meta("drone_claim", self)
	_from = global_position
	_to = _target.global_position + Vector3(0, 1.6, 0)
	_travel = 0.0
	_state = "out"


func _head_home() -> void:
	_release()
	_from = global_position
	_to = _dock_position()
	_travel = 0.0
	_state = "back"


## Deja la carga en la estación; lo que no cabe se pierde.
func _unload() -> void:
	global_position = _dock_position()
	_state = "docked"
	_timer = REST_TIME
	if _carrying.is_empty() or not is_instance_valid(station):
		return
	var items: Dictionary = station.items()
	for id in _carrying:
		var room: int = station.capacity() - station.stored_total()
		var amount := mini(int(_carrying[id]), room)
		if amount > 0:
			items[id] = int(items.get(id, 0)) + amount
	_carrying = {}


func _release() -> void:
	if is_instance_valid(_target) and _target.get_meta("drone_claim", null) == self:
		_target.remove_meta("drone_claim")
	_target = null


func _valid_target() -> bool:
	return is_instance_valid(_target) and _target.is_inside_tree() and _target.amount > 0


## Avanza por el arco entre _from y _to. Devuelve true al llegar.
func _fly(delta: float) -> bool:
	var flat := Vector2(_to.x - _from.x, _to.z - _from.z).length()
	var length := maxf(flat, absf(_to.y - _from.y))
	_travel = minf(length, _travel + SPEED * delta)
	var t := 1.0 if length <= 0.01 else _travel / length
	var pos := _from.lerp(_to, t)
	pos.y += sin(t * PI) * minf(CRUISE, length * 0.3)
	var world := station.get_parent()
	if world and world.has_method("surface_height") and t > 0.05 and t < 0.95:
		pos.y = maxf(pos.y, world.surface_height(pos.x, pos.z) + CLEARANCE)
	var heading := Vector2(_to.x - global_position.x, _to.z - global_position.z)
	if heading.length() > 0.05:
		rotation.y = atan2(-heading.x, -heading.y)
	global_position = pos
	return t >= 1.0


func _nearest_deposit() -> ResourceNode:
	var home := station.global_position
	var world := station.get_parent()
	var best: ResourceNode
	var best_distance := RANGE
	for node in get_tree().get_nodes_in_group("deposit"):
		var deposit := node as ResourceNode
		if deposit == null or deposit.amount <= 0 or deposit.has_meta("drone_claim"):
			continue
		var d := deposit.global_position.distance_to(home)
		if d >= best_distance:
			continue
		# Bajo el agua no se ve el depósito.
		if world and world.has_method("water_depth") and world.water_depth(deposit.global_position) > 0.3:
			continue
		best = deposit
		best_distance = d
	return best


func status_text() -> String:
	match _state:
		"out":
			return "va a por %s" % String(Game.RESOURCE_NAMES[_target.resource_type]).to_lower() if _valid_target() else "vuelve"
		"gathering":
			return "recogiendo"
		"back":
			return "vuelve con carga" if not _carrying.is_empty() else "vuelve"
	return "en la plataforma"
