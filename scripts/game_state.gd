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


func _ready() -> void:
	_setup_input()


func _process(delta: float) -> void:
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


func register_machine(kind: String) -> void:
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
		if stage == STAGES.size() - 1:
			finished = true
			message.emit("¡El planeta es habitable! Fin del prototipo.")
		else:
			message.emit("Nueva etapa: %s" % STAGES[stage]["name"])


func _setup_input() -> void:
	_add_key("move_forward", [KEY_W, KEY_UP])
	_add_key("move_back", [KEY_S, KEY_DOWN])
	_add_key("move_left", [KEY_A, KEY_LEFT])
	_add_key("move_right", [KEY_D, KEY_RIGHT])
	_add_key("jump", [KEY_SPACE])
	_add_key("craft", [KEY_TAB, KEY_C])
	_add_key("use_bottle", [KEY_Q])
	_add_key("release_mouse", [KEY_ESCAPE])


func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
