extends Node
## Estado global de la partida: inventario, recetas, métricas del planeta
## y oxígeno del jugador. Se carga como autoload con el nombre "Game".

signal inventory_changed
signal planet_changed
signal stage_changed(stage: int)
signal message(text: String)
signal place_requested(kind: String)
signal player_suffocated

const RESOURCE_NAMES := {
	"hierro": "Hierro",
	"silicio": "Silicio",
	"hielo": "Hielo",
	"botella": "Botella de oxígeno",
}

# "stage" es la etapa mínima de terraformación que desbloquea la receta.
const RECIPES := {
	"taladro": {"name": "Taladro mejorado", "cost": {"hierro": 3, "silicio": 1}, "kind": "tool", "stage": 0},
	"panel": {"name": "Panel solar", "cost": {"hierro": 2, "silicio": 2}, "kind": "building", "stage": 0},
	"generador": {"name": "Generador de oxígeno", "cost": {"hierro": 3, "hielo": 2}, "kind": "building", "stage": 0},
	"calentador": {"name": "Calentador", "cost": {"hierro": 4, "silicio": 1}, "kind": "building", "stage": 1},
	"botella": {"name": "Botella de oxígeno", "cost": {"hielo": 1}, "kind": "consumable", "stage": 0},
}

const STAGES := [
	{"name": "Roca muerta", "threshold": 0.0},
	{"name": "Primera neblina", "threshold": 25.0},
	{"name": "Deshielo", "threshold": 60.0},
	{"name": "Habitable", "threshold": 100.0},
]

# Valores provisionales: se ajustarán al probar el prototipo.
const MACHINE_RATE := 0.05 # puntos de métrica por segundo y máquina activa
const PLAYER_O2_MAX := 100.0
const PLAYER_O2_DRAIN := 0.5 # por segundo, con el planeta sin oxígeno
const BOTTLE_REFILL := 50.0
const SAVE_PATH := "user://partida.json"
const AUTOSAVE_TIME := 30.0

var inventory := {"hierro": 0, "silicio": 0, "hielo": 0, "botella": 0}
var has_drill := false
var panels := 0
var generators := 0
var heaters := 0
var oxygen := 0.0
var temperature := 0.0
var player_oxygen := PLAYER_O2_MAX
var stage := 0
var finished := false
var ui_open := false
var hint := ""
# Construcciones colocadas: [{"kind", "x", "y", "z", "rot"}], para el guardado.
var machines: Array = []
# Posición del jugador leída de la partida guardada, o null si no hay.
var player_position = null
var _autosave_timer := 0.0
var _skip_next_load := false


func _ready() -> void:
	_setup_input()


func _process(delta: float) -> void:
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_TIME:
		_autosave_timer = 0.0
		save_game()
	if finished:
		return
	var ratio := energy_ratio()
	if generators > 0 or heaters > 0:
		oxygen = minf(100.0, oxygen + generators * MACHINE_RATE * ratio * delta)
		temperature = minf(100.0, temperature + heaters * MACHINE_RATE * ratio * delta)
		planet_changed.emit()
		_update_stage()

	player_oxygen -= PLAYER_O2_DRAIN * (1.0 - oxygen / 100.0) * delta
	if player_oxygen <= 0.0:
		player_oxygen = PLAYER_O2_MAX
		player_suffocated.emit()
		message.emit("Te quedaste sin oxígeno. Vuelves a la base.")


func terraform_index() -> float:
	return (oxygen + temperature) / 2.0


func energy_ratio() -> float:
	var demand := generators + heaters
	if demand == 0:
		return 0.0
	return minf(1.0, float(panels) / demand)


func add_item(id: String, amount: int) -> void:
	inventory[id] = int(inventory.get(id, 0)) + amount
	inventory_changed.emit()


func is_unlocked(id: String) -> bool:
	return stage >= int(RECIPES[id]["stage"])


func can_craft(id: String) -> bool:
	if not is_unlocked(id):
		return false
	if id == "taladro" and has_drill:
		return false
	var cost: Dictionary = RECIPES[id]["cost"]
	for res in cost:
		if int(inventory.get(res, 0)) < int(cost[res]):
			return false
	return true


func craft(id: String) -> bool:
	if not can_craft(id):
		return false
	var recipe: Dictionary = RECIPES[id]
	var cost: Dictionary = recipe["cost"]
	for res in cost:
		inventory[res] = int(inventory[res]) - int(cost[res])
	match String(recipe["kind"]):
		"tool":
			has_drill = true
			message.emit("Taladro mejorado: ahora recoges el doble.")
		"consumable":
			inventory[id] = int(inventory.get(id, 0)) + 1
		"building":
			place_requested.emit(id)
	inventory_changed.emit()
	return true


func use_bottle() -> void:
	if int(inventory.get("botella", 0)) <= 0:
		message.emit("No tienes botellas de oxígeno.")
		return
	inventory["botella"] = int(inventory["botella"]) - 1
	player_oxygen = minf(PLAYER_O2_MAX, player_oxygen + BOTTLE_REFILL)
	inventory_changed.emit()


func register_machine(kind: String, pos: Vector3, rot: float) -> void:
	machines.append({"kind": kind, "x": pos.x, "y": pos.y, "z": pos.z, "rot": rot})
	_count_machine(kind)


func _count_machine(kind: String) -> void:
	match kind:
		"panel":
			panels += 1
		"generador":
			generators += 1
		"calentador":
			heaters += 1
	planet_changed.emit()


func _update_stage() -> void:
	var index := terraform_index()
	var new_stage := stage
	for i in STAGES.size():
		if index >= float(STAGES[i]["threshold"]):
			new_stage = i
	if new_stage != stage:
		stage = new_stage
		stage_changed.emit(stage)
		inventory_changed.emit() # refresca recetas desbloqueadas
		save_game()
		if stage == STAGES.size() - 1:
			finished = true
			message.emit("¡El planeta es habitable! Fin del prototipo.")
		else:
			message.emit("Nueva etapa: %s" % STAGES[stage]["name"])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func save_game() -> void:
	var data := {
		"version": 1,
		"inventory": inventory,
		"has_drill": has_drill,
		"oxygen": oxygen,
		"temperature": temperature,
		"player_oxygen": player_oxygen,
		"stage": stage,
		"finished": finished,
		"machines": machines,
	}
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var p := player.global_position
		data["player"] = [p.x, p.y, p.z]
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("No se pudo guardar la partida: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data))


## Carga la partida guardada, si existe. Devuelve true si se ha cargado.
func load_game() -> bool:
	if _skip_next_load:
		_skip_next_load = false
		return false
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("La partida guardada está dañada; se empieza de cero.")
		return false
	_reset_state()
	var saved_inventory: Dictionary = data.get("inventory", {})
	for id in inventory:
		inventory[id] = int(saved_inventory.get(id, 0))
	has_drill = bool(data.get("has_drill", false))
	oxygen = float(data.get("oxygen", 0.0))
	temperature = float(data.get("temperature", 0.0))
	player_oxygen = float(data.get("player_oxygen", PLAYER_O2_MAX))
	stage = int(data.get("stage", 0))
	finished = bool(data.get("finished", false))
	for m in data.get("machines", []):
		if typeof(m) == TYPE_DICTIONARY and RECIPES.has(m.get("kind", "")):
			machines.append(m)
			_count_machine(String(m["kind"]))
	var p = data.get("player")
	if p is Array and p.size() == 3:
		player_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	return true


## Borra la partida guardada y vuelve a empezar desde cero.
func new_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_reset_state()
	# Por si el archivo no se pudo borrar, la escena nueva no debe cargarlo.
	_skip_next_load = true
	get_tree().reload_current_scene()


func _reset_state() -> void:
	for id in inventory:
		inventory[id] = 0
	has_drill = false
	panels = 0
	generators = 0
	heaters = 0
	oxygen = 0.0
	temperature = 0.0
	player_oxygen = PLAYER_O2_MAX
	stage = 0
	finished = false
	ui_open = false
	machines = []
	player_position = null
	_autosave_timer = 0.0


func _setup_input() -> void:
	_add_key("move_forward", [KEY_W, KEY_UP])
	_add_key("move_back", [KEY_S, KEY_DOWN])
	_add_key("move_left", [KEY_A, KEY_LEFT])
	_add_key("move_right", [KEY_D, KEY_RIGHT])
	_add_key("jump", [KEY_SPACE])
	_add_key("craft", [KEY_TAB, KEY_C])
	_add_key("use_bottle", [KEY_Q])
	_add_key("release_mouse", [KEY_ESCAPE])
	_add_key("new_game", [KEY_F9])


func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
