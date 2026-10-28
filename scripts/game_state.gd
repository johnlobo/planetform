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
signal tool_changed(mode: String)
signal tool_used(point: Vector3)
signal build_menu_requested
signal locker_requested(locker: Node3D)
signal driving_changed(driving: bool)

const RESOURCE_NAMES := {
	"hierro": "Hierro",
	"silicio": "Silicio",
	"hielo": "Hielo",
	"cobre": "Cobre",
	"agua": "Agua",
	"semillas": "Semillas de musgo",
	"botella": "Botella de oxígeno",
	"racion": "Ración de emergencia",
	"verdura": "Verduras",
	"guiso": "Guiso",
}

# "stage" es la etapa mínima de terraformación que desbloquea la receta.
const RECIPES := {
	# Taladros: cada uno sustituye al anterior y hace falta tener el anterior.
	"taladro": {"name": "Taladro mejorado", "cost": {"hierro": 3, "silicio": 1}, "kind": "tool", "stage": 0},
	"taladro_termico": {"name": "Taladro térmico", "cost": {"hierro": 4, "cobre": 3, "silicio": 2}, "kind": "tool", "stage": 2},
	"taladro_plasma": {"name": "Taladro de plasma", "cost": {"hierro": 5, "cobre": 4, "silicio": 3, "agua": 2}, "kind": "tool", "stage": 3},
	"panel": {"name": "Panel solar", "cost": {"hierro": 2, "silicio": 2}, "kind": "building", "stage": 0},
	"generador": {"name": "Generador de oxígeno", "cost": {"hierro": 3, "hielo": 2}, "kind": "building", "stage": 0},
	"calentador": {"name": "Calentador", "cost": {"hierro": 4, "silicio": 1}, "kind": "building", "stage": 1},
	"perforadora": {"name": "Perforadora de gases", "cost": {"hierro": 3, "silicio": 1, "hielo": 1}, "kind": "building", "stage": 0},
	# Primera neblina: para salir a explorar lejos de la base.
	"jetpack": {"name": "Propulsores", "cost": {"hierro": 4, "silicio": 2, "hielo": 2}, "kind": "tool", "stage": 1},
	"rover": {"name": "Róver de exploración", "cost": {"hierro": 10, "silicio": 4}, "kind": "vehicle", "stage": 1},
	"cargador": {"name": "Punto de recarga", "cost": {"hierro": 3, "silicio": 2}, "kind": "building", "stage": 1},
	"botella": {"name": "Botella de oxígeno", "cost": {"hielo": 1}, "kind": "consumable", "stage": 0},
	# Deshielo
	"tanque": {"name": "Tanque de oxígeno", "cost": {"hierro": 2, "cobre": 2}, "kind": "tool", "stage": 2},
	"turbina": {"name": "Turbina eólica", "cost": {"hierro": 3, "cobre": 2}, "kind": "building", "stage": 2},
	"generador_avanzado": {"name": "Generador avanzado", "cost": {"hierro": 4, "cobre": 3, "hielo": 3}, "kind": "building", "stage": 2},
	"calentador_avanzado": {"name": "Calentador avanzado", "cost": {"hierro": 4, "cobre": 3, "silicio": 2}, "kind": "building", "stage": 2},
	"compresor": {"name": "Compresor atmosférico", "cost": {"hierro": 4, "cobre": 3, "silicio": 2}, "kind": "building", "stage": 2},
	"semillas": {"name": "Semillas de musgo", "cost": {"agua": 1, "silicio": 1}, "kind": "consumable", "stage": 2},
	"guiso": {"name": "Guiso", "cost": {"verdura": 3, "agua": 1}, "kind": "consumable", "stage": 2},
	"musgo": {"name": "Musgo", "cost": {"semillas": 1}, "kind": "building", "stage": 2},
	"bomba": {"name": "Bomba de agua", "cost": {"hierro": 3, "cobre": 2}, "kind": "building", "stage": 2},
	"cultivo": {"name": "Bancal de cultivo", "cost": {"hierro": 2, "agua": 3, "semillas": 2}, "kind": "building", "stage": 2},
	"drones": {"name": "Estación de drones", "cost": {"hierro": 6, "cobre": 4, "silicio": 3}, "kind": "building", "stage": 2},
	# Lluvias
	"colector": {"name": "Colector de lluvia", "cost": {"hierro": 2, "silicio": 2}, "kind": "building", "stage": 3},
	"arbol": {"name": "Plantón de árbol", "cost": {"semillas": 2, "agua": 2}, "kind": "building", "stage": 3},
	"insectos": {"name": "Criadero de insectos", "cost": {"hierro": 3, "cobre": 2, "verdura": 2}, "kind": "building", "stage": 3},
	# Base: módulos que encajan entre sí y piezas para sus paredes.
	"modulo": {"name": "Módulo de hábitat", "cost": {"hierro": 6, "silicio": 2}, "kind": "module", "stage": 0},
	"puerta": {"name": "Puerta", "cost": {"hierro": 2}, "kind": "fitting", "stage": 0},
	"ventana": {"name": "Ventana", "cost": {"hierro": 1, "silicio": 2}, "kind": "fitting", "stage": 0},
	"taquilla": {"name": "Taquilla", "cost": {"hierro": 3}, "kind": "building", "stage": 0},
	# Pantallas que muestran cómo va el planeta.
	"pantalla": {"name": "Pantalla de terraformación", "cost": {"hierro": 2, "silicio": 2}, "kind": "building", "stage": 0},
	"monitor_oxigeno": {"name": "Monitor de oxígeno", "cost": {"hierro": 1, "silicio": 1}, "kind": "building", "stage": 0},
	"monitor_calor": {"name": "Monitor de calor", "cost": {"hierro": 1, "silicio": 1}, "kind": "building", "stage": 0},
	"monitor_presion": {"name": "Monitor de presión", "cost": {"hierro": 1, "silicio": 1}, "kind": "building", "stage": 0},
	"monitor_biomasa": {"name": "Monitor de biomasa", "cost": {"hierro": 1, "silicio": 1}, "kind": "building", "stage": 0},
}

# Recetas que se colocan en el mundo en vez de ir al inventario.
const PLACEABLE_KINDS := ["building", "module", "fitting", "vehicle"]

# Efecto de cada construcción: energía que da (+) o gasta (-) y cuánto sube
# cada métrica del planeta, en múltiplos de MACHINE_RATE (la que no se pone
# es 0). "solar" = no da energía de noche. Lo que no gasta energía (el musgo)
# funciona siempre.
const MACHINES := {
	"panel": {"energy": 1, "oxygen": 0, "temperature": 0, "biomass": 0, "solar": true},
	"turbina": {"energy": 3, "oxygen": 0, "temperature": 0, "biomass": 0},
	"generador": {"energy": -1, "oxygen": 1, "temperature": 0, "biomass": 0},
	"calentador": {"energy": -1, "oxygen": 0, "temperature": 1, "biomass": 0},
	"generador_avanzado": {"energy": -2, "oxygen": 3, "temperature": 0, "biomass": 0},
	"calentador_avanzado": {"energy": -2, "oxygen": 0, "temperature": 3, "biomass": 0},
	# Presión: la perforadora saca gases del subsuelo; el compresor, el triple.
	"perforadora": {"energy": -1, "oxygen": 0, "temperature": 0, "biomass": 0, "pressure": 1},
	"compresor": {"energy": -2, "oxygen": 0, "temperature": 0, "biomass": 0, "pressure": 3},
	# Guarda recursos: "storage" es cuántas unidades caben.
	"taquilla": {"energy": 0, "oxygen": 0, "temperature": 0, "biomass": 0, "storage": 50},
	# Deshielo: el musgo crece solo; el bancal, más rápido pero con energía.
	# "plant" = con lluvia sube la biomasa RAIN_PLANT_FACTOR veces más rápido.
	# "outside" = solo se coloca fuera de la base. "grow_time" = segundos que
	# tarda en crecer desde que se planta.
	"musgo": {"energy": 0, "oxygen": 0, "temperature": 0, "biomass": 1, "plant": true, "outside": true, "grow_time": 40.0},
	# Saca agua del subsuelo y la guarda: una unidad de "produces" cada
	# "produce_time" segundos con toda la energía, hasta llenar "storage".
	"bomba": {"energy": -1, "oxygen": 0, "temperature": 0, "biomass": 0, "storage": 20, "produces": "agua", "produce_time": 6.0},
	# El bancal, además de subir la biomasa, da verduras para comer.
	"cultivo": {"energy": -1, "oxygen": 0, "temperature": 0, "biomass": 3, "storage": 12, "produces": "verdura", "produce_time": 20.0},
	# Pantallas: no gastan energía. "display" es lo que enseñan: una métrica
	# o "index" para el índice con todas las métricas.
	"pantalla": {"energy": 0, "oxygen": 0, "temperature": 0, "biomass": 0, "display": "index"},
	"monitor_oxigeno": {"energy": 0, "oxygen": 0, "temperature": 0, "biomass": 0, "display": "oxygen"},
	"monitor_calor": {"energy": 0, "oxygen": 0, "temperature": 0, "biomass": 0, "display": "temperature"},
	"monitor_presion": {"energy": 0, "oxygen": 0, "temperature": 0, "biomass": 0, "display": "pressure"},
	"monitor_biomasa": {"energy": 0, "oxygen": 0, "temperature": 0, "biomass": 0, "display": "biomass"},
	# Carga la batería de los róveres que se aparcan al lado.
	"cargador": {"energy": -1, "oxygen": 0, "temperature": 0, "biomass": 0},
	# Sus drones traen lo que recogen de los depósitos cercanos y lo guardan.
	"drones": {"energy": -2, "oxygen": 0, "temperature": 0, "biomass": 0, "storage": 30, "gathers": true},
	# Lluvias. El colector no gasta energía: solo recoge mientras llueve ("rain").
	"colector": {"energy": 0, "oxygen": 0, "temperature": 0, "biomass": 0, "storage": 20, "produces": "agua", "produce_time": 5.0, "rain": true, "outside": true},
	"arbol": {"energy": 0, "oxygen": 1, "temperature": 0, "biomass": 2, "plant": true, "outside": true, "grow_time": 90.0},
	# Sus insectos polinizan los bancales a menos de POLLEN_RANGE metros.
	"insectos": {"energy": -1, "oxygen": 0, "temperature": 0, "biomass": 2, "pollinates": true},
}

# Métricas del planeta, en el orden en que salen en la interfaz.
const METRICS := ["oxygen", "temperature", "pressure", "biomass"]
const METRIC_NAMES := {"oxygen": "Oxígeno", "temperature": "Temperatura", "pressure": "Presión", "biomass": "Biomasa"}

# Comida: cuánto quita el hambre cada cosa. Al comer (F) se toma la primera
# de esta lista que haya en la mochila.
const FOODS := {"verdura": 20.0, "racion": 40.0, "guiso": 100.0}

# Modos de la herramienta de mano, en el orden de las teclas 1, 2 y 3.
const TOOL_MODES := ["recoger", "construir", "desmontar"]
const TOOL_NAMES := {"recoger": "Recoger", "construir": "Construir", "desmontar": "Desmontar"}

# Niveles del taladro de la herramienta. "time" son los segundos que hay que
# mantener pulsado el ratón para sacar una unidad del depósito, y "yield"
# cuántas unidades da cada una. El nivel 0 es el que se tiene al empezar.
const DRILLS := [
	{"id": "", "name": "Taladro básico", "time": 1.0, "yield": 1, "color": Color(0.95, 0.55, 0.15)},
	{"id": "taladro", "name": "Taladro mejorado", "time": 0.6, "yield": 2, "color": Color(0.75, 0.78, 0.82)},
	{"id": "taladro_termico", "name": "Taladro térmico", "time": 0.35, "yield": 2, "color": Color(0.95, 0.3, 0.15)},
	{"id": "taladro_plasma", "name": "Taladro de plasma", "time": 0.2, "yield": 3, "color": Color(0.55, 0.4, 1.0)},
]

const STAGES := [
	{"name": "Roca muerta", "threshold": 0.0},
	{"name": "Primera neblina", "threshold": 20.0},
	{"name": "Deshielo", "threshold": 50.0},
	{"name": "Lluvias", "threshold": 75.0},
	{"name": "Habitable", "threshold": 100.0},
]

# Valores provisionales: se ajustarán al probar el prototipo.
const MACHINE_RATE := 0.05 # puntos de métrica por segundo y máquina activa
const PLAYER_O2_MAX := 100.0
const TANK_O2_MAX := 200.0
const JETPACK_FUEL_MAX := 100.0
const PLAYER_O2_DRAIN := 0.5 # por segundo, con el planeta sin oxígeno
const BOTTLE_REFILL := 50.0
# Hambre: la barra de comida se vacía en HUNGER_MAX / HUNGER_DRAIN segundos
# (12 minutos, tres días). Vacía, hay STARVE_TIME segundos para comer algo.
const HUNGER_MAX := 100.0
const HUNGER_DRAIN := 100.0 / 720.0
const HUNGER_WARNING := 25.0
const STARVE_TIME := 60.0
# Raciones con las que se empieza, para aguantar hasta tener bancales.
const START_RATIONS := 5
# Peso de cada métrica en el índice de terraformación. Sin biomasa se llega
# como mucho al 80 %: para que el planeta sea habitable hacen falta plantas.
const INDEX_WEIGHTS := {"oxygen": 0.3, "temperature": 0.3, "pressure": 0.2, "biomass": 0.2}
# Día y noche
const DAY_LENGTH := 240.0 # segundos por día completo
const START_TIME := 0.3 # 0 = medianoche, 0.5 = mediodía
const WARMTH_MAX := 100.0
const WARMTH_DRAIN := 2.0 # por segundo de noche, con el planeta a 0 % de temperatura
const WARMTH_REGEN := 5.0 # por segundo de día o junto a un calentador
const HEATER_RANGE := 8.0 # metros
const SHELTER_O2_REFILL := 20.0 # oxígeno por segundo dentro de un módulo
const LOW_O2_WARNING := 0.2 # fracción de la reserva a la que se avisa
const COLD_WARNING := 25.0 # por debajo de este calor se avisa al jugador
const COLD_O2_FACTOR := 3.0 # multiplica el gasto de oxígeno cuando el calor llega a 0
# Lluvias: desde la etapa RAIN_STAGE cae un chubasco cada RAIN_CYCLE días
# que dura RAIN_PART de ese tiempo (unos 50 s cada 3 minutos).
const RAIN_STAGE := 3
const RAIN_CYCLE := 0.75
const RAIN_PART := 0.3
const RAIN_PLANT_FACTOR := 2.0
# Los insectos hacen que los bancales cercanos den verduras más rápido.
const POLLEN_RANGE := 10.0
const POLLEN_FACTOR := 1.5
# Versión del guardado. La 2 añadió las Lluvias entre el Deshielo y Habitable.
const SAVE_VERSION := 2
const SAVE_PATH := "user://partida.json"
const AUTOSAVE_TIME := 15.0

var inventory := {"hierro": 0, "silicio": 0, "hielo": 0, "cobre": 0, "agua": 0, "semillas": 0, "botella": 0,
		"racion": START_RATIONS, "verdura": 0, "guiso": 0}
var drill_level := 0 # índice en DRILLS
var has_tank := false
var has_jetpack := false
# Combustible de los propulsores, de 0 a JETPACK_FUEL_MAX.
var jetpack_fuel := 100.0
# Número de construcciones colocadas de cada tipo.
var machine_counts := {}
var oxygen := 0.0
var temperature := 0.0
var biomass := 0.0
var pressure := 0.0
var player_oxygen := PLAYER_O2_MAX
var stage := 0
var finished := false
var time_of_day := START_TIME
var day := 1
var warmth := WARMTH_MAX
var hunger := HUNGER_MAX
# Segundos que lleva el jugador con la barra de comida vacía.
var _starve_time := 0.0
var _was_hungry := false
var _was_night := false
var _was_cold := false
var _was_frozen := false
var _was_low_oxygen := false
var _was_raining := false
# true desde que el jugador muere hasta que vuelve a la base.
var dead := false
# true mientras se muestra la pantalla de título: aún no se ha empezado a jugar.
var in_title := false
var ui_open := false
# true mientras el jugador elige dónde colocar una construcción.
var placing := false
var hint := ""
# De 0 a 1 mientras se mantiene pulsado el ratón sobre un depósito; -1 si no.
var mine_progress := -1.0
var tool_mode := "recoger"
# Construcciones colocadas: [{"kind", "x", "y", "z", "rot"}], para el guardado.
var machines: Array = []
# Módulos de la base: [{"x", "y", "z", "rot", "sides"}].
var modules: Array = []
# Vehículos: [{"kind", "x", "y", "z", "rot", "battery", "items"}].
var vehicles: Array = []
# El vehículo que conduce el jugador, o null.
var vehicle: Node3D
# true mientras el jugador está dentro de un módulo de la base.
var sheltered := false
# Posición del jugador leída de la partida guardada, o null si no hay.
var player_position = null
var _autosave_timer := 0.0
var _skip_next_load := false
# true tras empezar una nueva partida, para no volver a la pantalla de título.
var skip_title := false
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
	if not machine_counts.is_empty():
		for metric in METRICS:
			set(metric, minf(100.0, float(get(metric)) + metric_rate(metric) * delta))
		planet_changed.emit()
		_update_stage()

	_update_day_and_cold(delta)
	_update_rain()
	_update_hunger(delta)
	if dead:
		return
	if sheltered:
		# Dentro de la base hay aire: la reserva se rellena.
		player_oxygen = minf(player_o2_max(), player_oxygen + SHELTER_O2_REFILL * delta)
	else:
		var drain := PLAYER_O2_DRAIN * (1.0 - oxygen / 100.0)
		if warmth <= 0.0:
			drain *= COLD_O2_FACTOR
		player_oxygen -= drain * delta
	var low_oxygen := player_oxygen <= player_o2_max() * LOW_O2_WARNING
	if low_oxygen and not _was_low_oxygen:
		message.emit("Oxígeno bajo: usa una botella (Q).")
		Sfx.play("alarma")
	_was_low_oxygen = low_oxygen
	if player_oxygen <= 0.0:
		_die("Te quedaste sin oxígeno." if warmth > 0.0 else "Te quedaste sin oxígeno por el frío.")


func _die(cause: String) -> void:
	dead = true
	Sfx.play("muerte")
	player_died.emit(cause)


## Devuelve al jugador a la base con el oxígeno y el calor al máximo.
func respawn() -> void:
	dead = false
	player_oxygen = player_o2_max()
	warmth = WARMTH_MAX
	hunger = HUNGER_MAX
	_starve_time = 0.0
	_was_hungry = false
	_was_cold = false
	_was_frozen = false
	_was_low_oxygen = false
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

	if night and not sheltered and not _near_heater():
		# Cuanto más caliente está el planeta, menos frío hace de noche.
		warmth -= WARMTH_DRAIN * (1.0 - temperature / 100.0) * delta
	else:
		warmth += WARMTH_REGEN * delta
	warmth = clampf(warmth, 0.0, WARMTH_MAX)

	var cold := warmth <= COLD_WARNING
	if cold and not _was_cold:
		message.emit("Te estás congelando: busca un calentador con energía.")
		Sfx.play("alarma")
	_was_cold = cold

	var frozen := warmth <= 0.0
	if frozen and not _was_frozen:
		message.emit("Estás helado: gastas oxígeno el triple de rápido.")
	_was_frozen = frozen


## Intensidad de la lluvia, de 0 (no llueve) a 1. Va por la hora del juego,
## así que no hace falta guardarla.
func rain() -> float:
	if stage < RAIN_STAGE:
		return 0.0
	var phase := fposmod((day - 1 + time_of_day) / RAIN_CYCLE, 1.0)
	if phase >= RAIN_PART:
		return 0.0
	# Empieza y acaba poco a poco.
	return clampf(sin(PI * phase / RAIN_PART) * 3.0, 0.0, 1.0)


func is_raining() -> bool:
	return rain() > 0.2


func _update_rain() -> void:
	var raining := is_raining()
	if raining and not _was_raining:
		message.emit("Empieza a llover: el musgo y los árboles crecen el doble.")
	elif not raining and _was_raining:
		message.emit("Deja de llover.")
	_was_raining = raining


## Ritmo al que produce una construcción (0 parada, 1 normal): los colectores
## con la lluvia, lo que gasta energía con la energía que recibe y los
## bancales, más rápido si hay insectos cerca.
func production_ratio(kind: String, pos: Vector3) -> float:
	if MACHINES[kind].get("rain", false):
		return rain()
	var ratio := 1.0
	if int(MACHINES[kind]["energy"]) < 0:
		ratio = energy_ratio()
	if kind == "cultivo" and ratio > 0.0 and is_pollinated(pos):
		ratio *= POLLEN_FACTOR
	return ratio


## true si hay un criadero de insectos con energía cerca del punto.
func is_pollinated(pos: Vector3) -> bool:
	if not machine_counts.has("insectos") or energy_ratio() <= 0.0:
		return false
	for m in machines:
		if MACHINES[String(m["kind"])].get("pollinates", false):
			if Vector3(float(m["x"]), float(m["y"]), float(m["z"])).distance_to(pos) <= POLLEN_RANGE:
				return true
	return false


func _update_hunger(delta: float) -> void:
	hunger = maxf(0.0, hunger - HUNGER_DRAIN * delta)
	var hungry := hunger <= HUNGER_WARNING
	if hungry and not _was_hungry:
		message.emit("Tienes hambre: come algo (F).")
		Sfx.play("alarma")
	_was_hungry = hungry
	if hunger > 0.0:
		_starve_time = 0.0
		return
	if _starve_time == 0.0:
		message.emit("Te mueres de hambre: come algo antes de %d segundos (F)." % int(STARVE_TIME))
		Sfx.play("alarma")
	_starve_time += delta
	if _starve_time >= STARVE_TIME:
		_die("Te desmayaste de hambre.")


## Come lo primero de FOODS que haya en la mochila.
func eat() -> void:
	if hunger >= HUNGER_MAX - 1.0:
		message.emit("No tienes hambre.")
		return
	for id in FOODS:
		if int(inventory.get(id, 0)) > 0:
			inventory[id] = int(inventory[id]) - 1
			hunger = minf(HUNGER_MAX, hunger + float(FOODS[id]))
			Sfx.play("recoger")
			message.emit("Comes: %s." % String(RESOURCE_NAMES[id]).to_lower())
			inventory_changed.emit()
			return
	message.emit("No tienes comida: cultívala en un bancal.")


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
	var index := 0.0
	for metric in METRICS:
		index += float(get(metric)) * INDEX_WEIGHTS[metric]
	return index


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


## Puntos por segundo que suben la métrica. Las máquinas que gastan energía
## van al ritmo de la energía que reciben; las que no la gastan, siempre.
func metric_rate(metric: String) -> float:
	var ratio := energy_ratio()
	var plant_factor := lerpf(1.0, RAIN_PLANT_FACTOR, rain())
	var total := 0.0
	for kind in machine_counts:
		var amount := float(MACHINES[kind].get(metric, 0)) * int(machine_counts[kind])
		if int(MACHINES[kind]["energy"]) < 0:
			amount *= ratio
		if metric == "biomass" and MACHINES[kind].get("plant", false):
			amount *= plant_factor
		total += amount
	return total * MACHINE_RATE


func add_item(id: String, amount: int) -> void:
	inventory[id] = int(inventory.get(id, 0)) + amount
	inventory_changed.emit()


func is_unlocked(id: String) -> bool:
	return stage >= int(RECIPES[id]["stage"])


func can_craft(id: String) -> bool:
	if not is_unlocked(id):
		return false
	var drill := drill_index(id)
	if drill > 0 and drill_level != drill - 1:
		return false # ya lo tiene, o le falta el taladro anterior
	if (id == "tanque" and has_tank) or (id == "jetpack" and has_jetpack):
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
	# Las construcciones se pagan al colocarlas, así cancelar no cuesta nada.
	if is_placeable(id):
		place_requested.emit(id)
		return true
	var cost: Dictionary = recipe["cost"]
	for res in cost:
		inventory[res] = int(inventory[res]) - int(cost[res])
	Sfx.play("craftear")
	match String(recipe["kind"]):
		"tool":
			if id == "tanque":
				has_tank = true
				message.emit("Tanque de oxígeno: tu reserva sube a %d." % int(TANK_O2_MAX))
			elif id == "jetpack":
				has_jetpack = true
				jetpack_fuel = JETPACK_FUEL_MAX
				message.emit("Propulsores: mantén Espacio en el aire para volar un poco.")
			elif drill_index(id) > 0:
				drill_level = drill_index(id)
				var drill: Dictionary = DRILLS[drill_level]
				message.emit("%s: recoges x%d y %.1f veces más rápido." % [drill["name"], drill["yield"], float(DRILLS[0]["time"]) / float(drill["time"])])
		"consumable":
			inventory[id] = int(inventory.get(id, 0)) + 1
	inventory_changed.emit()
	return true


## Nivel de taladro que da la receta id, o 0 si no es un taladro.
func drill_index(id: String) -> int:
	for i in range(1, DRILLS.size()):
		if DRILLS[i]["id"] == id:
			return i
	return 0


func drill() -> Dictionary:
	return DRILLS[drill_level]


func is_placeable(id: String) -> bool:
	return String(RECIPES[id]["kind"]) in PLACEABLE_KINDS


## Descuenta el coste de algo que se acaba de colocar. Devuelve false si ya
## no hay materiales.
func pay(id: String) -> bool:
	if not can_craft(id):
		return false
	var cost: Dictionary = RECIPES[id]["cost"]
	for res in cost:
		inventory[res] = int(inventory[res]) - int(cost[res])
	inventory_changed.emit()
	return true


func use_bottle() -> void:
	if int(inventory.get("botella", 0)) <= 0:
		message.emit("No tienes botellas de oxígeno.")
		return
	inventory["botella"] = int(inventory["botella"]) - 1
	player_oxygen = minf(player_o2_max(), player_oxygen + BOTTLE_REFILL)
	inventory_changed.emit()


## Apunta una construcción para el guardado y devuelve su entrada.
func register_machine(kind: String, pos: Vector3, rot: float) -> Dictionary:
	var data := {"kind": kind, "x": pos.x, "y": pos.y, "z": pos.z, "rot": rot}
	machines.append(data)
	_count_machine(kind)
	return data


## Quita una construcción desmontada. Se busca la entrada misma y no una
## igual, por si hubiera dos con los mismos datos.
func unregister_machine(data: Dictionary) -> void:
	for i in machines.size():
		if is_same(machines[i], data):
			machines.remove_at(i)
			break
	var kind := String(data["kind"])
	machine_counts[kind] = maxi(0, int(machine_counts.get(kind, 0)) - 1)
	if machine_counts[kind] == 0:
		machine_counts.erase(kind)
	planet_changed.emit()


## Devuelve al inventario los materiales de lo que se desmonta.
func refund(cost: Dictionary) -> void:
	for res in cost:
		inventory[res] = int(inventory.get(res, 0)) + int(cost[res])
	inventory_changed.emit()


## "2 hierro + 1 silicio"
func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for res in cost:
		parts.append("%d %s" % [cost[res], String(RESOURCE_NAMES[res]).to_lower()])
	return " + ".join(parts)


func set_tool_mode(mode: String) -> void:
	if mode == tool_mode:
		return
	tool_mode = mode
	tool_changed.emit(mode)


func _count_machine(kind: String) -> void:
	machine_counts[kind] = int(machine_counts.get(kind, 0)) + 1
	planet_changed.emit()


func _update_stage() -> void:
	var index := terraform_index()
	# Nunca se vuelve atrás: una partida antigua puede tener menos índice
	# ahora que cuenta la biomasa.
	var new_stage := stage
	for i in range(stage + 1, STAGES.size()):
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
		Sfx.play("etapa")


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
	# En el título no se guarda: crearía una partida vacía sin haber jugado.
	if dead or in_title or not is_inside_tree():
		return
	var data := {
		"version": SAVE_VERSION,
		"inventory": inventory,
		"drill_level": drill_level,
		"has_tank": has_tank,
		"has_jetpack": has_jetpack,
		"oxygen": oxygen,
		"temperature": temperature,
		"biomass": biomass,
		"pressure": pressure,
		"player_oxygen": player_oxygen,
		"stage": stage,
		"time_of_day": time_of_day,
		"day": day,
		"warmth": warmth,
		"hunger": hunger,
		"finished": finished,
		"machines": machines,
		"modules": modules,
		"vehicles": vehicles,
	}
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		# Conduciendo se guarda el sitio donde se baja, junto al róver.
		var p: Vector3 = player.saved_position() if player.has_method("saved_position") else player.global_position
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
	# Las partidas de antes de los niveles solo guardaban si había taladro mejorado.
	drill_level = clampi(int(data.get("drill_level", 1 if data.get("has_drill", false) else 0)), 0, DRILLS.size() - 1)
	has_tank = bool(data.get("has_tank", false))
	has_jetpack = bool(data.get("has_jetpack", false))
	oxygen = float(data.get("oxygen", 0.0))
	temperature = float(data.get("temperature", 0.0))
	biomass = float(data.get("biomass", 0.0))
	# Una partida de antes de la presión empieza con la que deja el índice
	# igual que antes (pesaban 40 % el oxígeno y la temperatura).
	pressure = float(data.get("pressure", minf(100.0, (oxygen + temperature) / 2.0)))
	player_oxygen = float(data.get("player_oxygen", PLAYER_O2_MAX))
	stage = int(data.get("stage", 0))
	# Antes de las Lluvias, la etapa 3 era Habitable: sigue siéndolo.
	if int(data.get("version", 1)) < 2 and stage >= RAIN_STAGE:
		stage += 1
	stage = mini(stage, STAGES.size() - 1)
	time_of_day = float(data.get("time_of_day", START_TIME))
	day = int(data.get("day", 1))
	warmth = float(data.get("warmth", WARMTH_MAX))
	hunger = float(data.get("hunger", HUNGER_MAX))
	_was_hungry = hunger <= HUNGER_WARNING
	if not data.has("hunger"):
		# Partida de antes del hambre: se le dan las raciones del principio.
		inventory["racion"] = START_RATIONS
	_was_night = is_night()
	_was_raining = is_raining()
	finished = bool(data.get("finished", false))
	for m in data.get("machines", []):
		if typeof(m) == TYPE_DICTIONARY and MACHINES.has(m.get("kind", "")):
			machines.append(m)
			_count_machine(String(m["kind"]))
	for m in data.get("modules", []):
		if typeof(m) == TYPE_DICTIONARY:
			modules.append(m)
	for v in data.get("vehicles", []):
		if typeof(v) == TYPE_DICTIONARY and RECIPES.has(v.get("kind", "")):
			vehicles.append(v)
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
	skip_title = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func _reset_state() -> void:
	for id in inventory:
		inventory[id] = 0
	inventory["racion"] = START_RATIONS
	drill_level = 0
	has_tank = false
	has_jetpack = false
	jetpack_fuel = JETPACK_FUEL_MAX
	machine_counts = {}
	oxygen = 0.0
	temperature = 0.0
	biomass = 0.0
	pressure = 0.0
	player_oxygen = PLAYER_O2_MAX
	stage = 0
	finished = false
	time_of_day = START_TIME
	day = 1
	warmth = WARMTH_MAX
	hunger = HUNGER_MAX
	_starve_time = 0.0
	_was_hungry = false
	_was_night = false
	_was_cold = false
	_was_frozen = false
	_was_low_oxygen = false
	_was_raining = false
	dead = false
	in_title = false
	ui_open = false
	placing = false
	machines = []
	modules = []
	vehicles = []
	vehicle = null
	tool_mode = "recoger"
	sheltered = false
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
	_add_key("eat", [KEY_F])
	_add_key("release_mouse", [KEY_ESCAPE])
	_add_key("pause", [KEY_H])
	_add_key("rotate_building", [KEY_R])
	_add_key("interact", [KEY_E])
	_add_key("tool_recoger", [KEY_1])
	_add_key("tool_construir", [KEY_2])
	_add_key("tool_desmontar", [KEY_3])


func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
