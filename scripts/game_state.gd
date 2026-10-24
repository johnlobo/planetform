extends Node
## Estado global de la partida: inventario, recetas, métricas del planeta
## y oxígeno del jugador. Se carga como autoload con el nombre "Game".

signal inventory_changed
signal planet_changed
signal stage_changed(stage: int)
signal message(text: String)
signal place_requested(kind: String)
signal player_died(cause: String)
signal player_respawned

const RESOURCE_NAMES := {
	"hierro": "Hierro",
	"silicio": "Silicio",
	"hielo": "Hielo",
	"cobre": "Cobre",
	"botella": "Botella de oxígeno",
}

# "stage" es la etapa mínima de terraformación que desbloquea la receta.
const RECIPES := {
	"taladro": {"name": "Taladro mejorado", "cost": {"hierro": 3, "silicio": 1}, "kind": "tool", "stage": 0},
	"panel": {"name": "Panel solar", "cost": {"hierro": 2, "silicio": 2}, "kind": "building", "stage": 0},
	"generador": {"name": "Generador de oxígeno", "cost": {"hierro": 3, "hielo": 2}, "kind": "building", "stage": 0},
	"calentador": {"name": "Calentador", "cost": {"hierro": 4, "silicio": 1}, "kind": "building", "stage": 1},
	"botella": {"name": "Botella de oxígeno", "cost": {"hielo": 1}, "kind": "consumable", "stage": 0},
	# Deshielo
	"tanque": {"name": "Tanque de oxígeno", "cost": {"hierro": 2, "cobre": 2}, "kind": "tool", "stage": 2},
	"turbina": {"name": "Turbina eólica", "cost": {"hierro": 3, "cobre": 2}, "kind": "building", "stage": 2},
	"generador_avanzado": {"name": "Generador avanzado", "cost": {"hierro": 4, "cobre": 3, "hielo": 3}, "kind": "building", "stage": 2},
	"calentador_avanzado": {"name": "Calentador avanzado", "cost": {"hierro": 4, "cobre": 3, "silicio": 2}, "kind": "building", "stage": 2},
}

# Efecto de cada construcción: energía que da (+) o gasta (-) y cuánto sube
# cada métrica del planeta, en múltiplos de MACHINE_RATE. "solar" = no da
# energía de noche.
const MACHINES := {
	"panel": {"energy": 1, "oxygen": 0, "temperature": 0, "solar": true},
	"turbina": {"energy": 3, "oxygen": 0, "temperature": 0},
	"generador": {"energy": -1, "oxygen": 1, "temperature": 0},
	"calentador": {"energy": -1, "oxygen": 0, "temperature": 1},
	"generador_avanzado": {"energy": -2, "oxygen": 3, "temperature": 0},
	"calentador_avanzado": {"energy": -2, "oxygen": 0, "temperature": 3},
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
const TANK_O2_MAX := 200.0
const PLAYER_O2_DRAIN := 0.5 # por segundo, con el planeta sin oxígeno
const BOTTLE_REFILL := 50.0
# Día y noche
const DAY_LENGTH := 240.0 # segundos por día completo
const START_TIME := 0.3 # 0 = medianoche, 0.5 = mediodía
const WARMTH_MAX := 100.0
const WARMTH_DRAIN := 2.0 # por segundo de noche, con el planeta a 0 % de temperatura
const WARMTH_REGEN := 5.0 # por segundo de día o junto a un calentador
const HEATER_RANGE := 8.0 # metros
const COLD_WARNING := 25.0 # por debajo de este calor se avisa al jugador
const COLD_O2_FACTOR := 3.0 # multiplica el gasto de oxígeno cuando el calor llega a 0
const SAVE_PATH := "user://partida.json"
const AUTOSAVE_TIME := 15.0

var inventory := {"hierro": 0, "silicio": 0, "hielo": 0, "cobre": 0, "botella": 0}
var has_drill := false
var has_tank := false
# Número de construcciones colocadas de cada tipo.
var machine_counts := {}
var oxygen := 0.0
var temperature := 0.0
var player_oxygen := PLAYER_O2_MAX
var stage := 0
var finished := false
var time_of_day := START_TIME
var day := 1
var warmth := WARMTH_MAX
var _was_night := false
var _was_cold := false
var _was_frozen := false
# true desde que el jugador muere hasta que vuelve a la base.
var dead := false
var ui_open := false
var hint := ""
# Construcciones colocadas: [{"kind", "x", "y", "z", "rot"}], para el guardado.
var machines: Array = []
# Posición del jugador leída de la partida guardada, o null si no hay.
var player_position = null
var _autosave_timer := 0.0
var _skip_next_load := false
# En el navegador el cierre de la pestaña no avisa al juego; se guarda al ocultarla.
var _js_visibility_callback


func _ready() -> void:
	_setup_input()
	if OS.has_feature("web"):
		_js_visibility_callback = JavaScriptBridge.create_callback(_on_web_visibility_change)
		var document = JavaScriptBridge.get_interface("document")
		document.addEventListener("visibilitychange", _js_visibility_callback)


func _process(delta: float) -> void:
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_TIME:
		_autosave_timer = 0.0
		save_game()
	if finished or dead:
		return
	var ratio := energy_ratio()
	if energy_demand() > 0:
		oxygen = minf(100.0, oxygen + _total("oxygen") * MACHINE_RATE * ratio * delta)
		temperature = minf(100.0, temperature + _total("temperature") * MACHINE_RATE * ratio * delta)
		planet_changed.emit()
		_update_stage()

	_update_day_and_cold(delta)
	var drain := PLAYER_O2_DRAIN * (1.0 - oxygen / 100.0)
	if warmth <= 0.0:
		drain *= COLD_O2_FACTOR
	player_oxygen -= drain * delta
	if player_oxygen <= 0.0:
		_die("Te quedaste sin oxígeno." if warmth > 0.0 else "Te quedaste sin oxígeno por el frío.")


func _die(cause: String) -> void:
	dead = true
	player_died.emit(cause)


## Devuelve al jugador a la base con el oxígeno y el calor al máximo.
func respawn() -> void:
	dead = false
	player_oxygen = player_o2_max()
	warmth = WARMTH_MAX
	_was_cold = false
	_was_frozen = false
	player_respawned.emit()
	message.emit("Vuelves a la base.")


## 1 a mediodía, -1 a medianoche.
func sun_height() -> float:
	return sin((time_of_day - 0.25) * TAU)


func is_night() -> bool:
	return sun_height() < 0.0


func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "Día %d · %02d:%02d" % [day, minutes / 60, minutes % 60]


func _update_day_and_cold(delta: float) -> void:
	time_of_day += delta / DAY_LENGTH
	if time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1

	var night := is_night()
	if night and not _was_night:
		message.emit("Cae la noche: hace frío, quédate cerca de un calentador.")
	elif not night and _was_night:
		message.emit("Amanece.")
	_was_night = night

	if night and not _near_heater():
		# Cuanto más caliente está el planeta, menos frío hace de noche.
		warmth -= WARMTH_DRAIN * (1.0 - temperature / 100.0) * delta
	else:
		warmth += WARMTH_REGEN * delta
	warmth = clampf(warmth, 0.0, WARMTH_MAX)

	var cold := warmth <= COLD_WARNING
	if cold and not _was_cold:
		message.emit("Te estás congelando: busca un calentador con energía.")
	_was_cold = cold

	var frozen := warmth <= 0.0
	if frozen and not _was_frozen:
		message.emit("Estás helado: gastas oxígeno el triple de rápido.")
	_was_frozen = frozen


func _near_heater() -> bool:
	# Un calentador sin energía no calienta, igual que no sube la temperatura.
	if energy_ratio() <= 0.0:
		return false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	for m in machines:
		var kind := String(m["kind"])
		if int(MACHINES[kind]["temperature"]) <= 0:
			continue
		var pos := Vector3(float(m["x"]), float(m["y"]), float(m["z"]))
		if pos.distance_to(player.global_position) <= HEATER_RANGE:
			return true
	return false


func terraform_index() -> float:
	return (oxygen + temperature) / 2.0


func player_o2_max() -> float:
	return TANK_O2_MAX if has_tank else PLAYER_O2_MAX


func energy_supply() -> int:
	var supply := 0
	var night := is_night()
	for kind in machine_counts:
		if night and MACHINES[kind].get("solar", false):
			continue
		supply += maxi(0, int(MACHINES[kind]["energy"])) * int(machine_counts[kind])
	return supply


func energy_demand() -> int:
	var demand := 0
	for kind in machine_counts:
		demand += maxi(0, -int(MACHINES[kind]["energy"])) * int(machine_counts[kind])
	return demand


func energy_ratio() -> float:
	var demand := energy_demand()
	if demand == 0:
		return 0.0
	return minf(1.0, float(energy_supply()) / demand)


func _total(metric: String) -> int:
	var total := 0
	for kind in machine_counts:
		total += int(MACHINES[kind][metric]) * int(machine_counts[kind])
	return total


func add_item(id: String, amount: int) -> void:
	inventory[id] = int(inventory.get(id, 0)) + amount
	inventory_changed.emit()


func is_unlocked(id: String) -> bool:
	return stage >= int(RECIPES[id]["stage"])


func can_craft(id: String) -> bool:
	if not is_unlocked(id):
		return false
	if (id == "taladro" and has_drill) or (id == "tanque" and has_tank):
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
			if id == "tanque":
				has_tank = true
				message.emit("Tanque de oxígeno: tu reserva sube a %d." % int(TANK_O2_MAX))
			else:
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
	player_oxygen = minf(player_o2_max(), player_oxygen + BOTTLE_REFILL)
	inventory_changed.emit()


func register_machine(kind: String, pos: Vector3, rot: float) -> void:
	machines.append({"kind": kind, "x": pos.x, "y": pos.y, "z": pos.z, "rot": rot})
	_count_machine(kind)


func _count_machine(kind: String) -> void:
	machine_counts[kind] = int(machine_counts.get(kind, 0)) + 1
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
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()


func _on_web_visibility_change(_args: Array) -> void:
	var document = JavaScriptBridge.get_interface("document")
	if document.hidden:
		save_game()


func save_game() -> void:
	# Guardar al morir dejaría una partida que vuelve a matar al cargarla.
	# Fuera del árbol (al cerrar la aplicación) ya no hay jugador que guardar.
	if dead or not is_inside_tree():
		return
	var data := {
		"version": 1,
		"inventory": inventory,
		"has_drill": has_drill,
		"has_tank": has_tank,
		"oxygen": oxygen,
		"temperature": temperature,
		"player_oxygen": player_oxygen,
		"stage": stage,
		"time_of_day": time_of_day,
		"day": day,
		"warmth": warmth,
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
	has_tank = bool(data.get("has_tank", false))
	oxygen = float(data.get("oxygen", 0.0))
	temperature = float(data.get("temperature", 0.0))
	player_oxygen = float(data.get("player_oxygen", PLAYER_O2_MAX))
	stage = int(data.get("stage", 0))
	time_of_day = float(data.get("time_of_day", START_TIME))
	day = int(data.get("day", 1))
	warmth = float(data.get("warmth", WARMTH_MAX))
	_was_night = is_night()
	finished = bool(data.get("finished", false))
	for m in data.get("machines", []):
		if typeof(m) == TYPE_DICTIONARY and MACHINES.has(m.get("kind", "")):
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
	has_tank = false
	machine_counts = {}
	oxygen = 0.0
	temperature = 0.0
	player_oxygen = PLAYER_O2_MAX
	stage = 0
	finished = false
	time_of_day = START_TIME
	day = 1
	warmth = WARMTH_MAX
	_was_night = false
	_was_cold = false
	_was_frozen = false
	dead = false
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
	_add_key("pause", [KEY_H])


func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
