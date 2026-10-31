extends Node3D
## Terreno del planeta: un cuadrado de WORLD_SIZE metros partido en trozos de
## CHUNK metros. Cada trozo tiene siempre una malla lejana con poco detalle; al
## acercarse el jugador se le hace la malla detallada con su colisión, rocas
## grandes, árboles y recursos, y al alejarse se borra. Así solo cuesta lo que
## hay cerca y el mapa puede crecer sin que el juego vaya más lento.
##
## La zona del principio (START_AREA) es igual que el mapa original de 160 m:
## las montañas empiezan más lejos para que las bases guardadas no cambien.

const ResourceNode := preload("res://scripts/resource_node.gd")
const Sites := preload("res://scripts/sites.gd")

const WORLD_SIZE := 2000.0
const CHUNK := 100.0
const STEP := 2.5 # metros entre vértices de la malla detallada
const FAR_STEP := 10.0 # y de la lejana
# Distancias desde el jugador hasta el borde del trozo.
const NEAR_RANGE := 120.0 # hasta aquí se ve la malla detallada
const LOAD_RANGE := 150.0 # se prepara un poco antes de que haga falta
const UNLOAD_RANGE := 260.0
const SKIRT := 12.0 # faldón bajo el borde de cada malla para tapar rendijas
const BUILD_BUDGET_MS := 6.0 # tiempo por fotograma para preparar trozos
# Las mallas lejanas se dibujan en bloques de BLOCK x BLOCK trozos (25 en vez de
# 400). Cerca del jugador un bloque se cambia por las mallas de sus trozos, para
# poder esconder solo los que tienen malla detallada encima.
const BLOCK := 4
const EXPAND_RANGE := 200.0
const COLLAPSE_RANGE := 260.0
# Pasos en que se prepara un trozo (ver _load_step).
const LOAD_STEPS := 12
const HEIGHT := 6.0
const START_AREA := 160.0
# Montañas: empiezan a MOUNTAIN_START metros del centro y crecen hasta MOUNTAIN_FULL.
const MOUNTAIN_START := 150.0
const MOUNTAIN_FULL := 450.0
const MOUNTAIN_HEIGHT := 80.0
const HILL_HEIGHT := 10.0
const EDGE_WALL := 120.0 # franja junto al borde donde las montañas cierran el mapa
const EDGE_HEIGHT := 70.0
# Qué es roca y qué nieve: por pendiente (normal.y) y altura.
const ROCK_SLOPE := 0.8
const ROCK_HEIGHT := 22.0
const SNOW_HEIGHT := 55.0
const TREE_LINE := 18.0 # no hay árboles por encima
const DRY_LEVEL := -0.7 # ni por debajo: el agua sube hasta -1 m
const TREE_TRIES := 100 # sitios que se prueban por trozo
const BOULDER_TRIES := 14
const RESOURCES_PER_CHUNK := 6
const ICE_SUMMIT := 12.0 # el hielo por encima no se funde
# Sitios recónditos (scripts/sites.gd): como mucho uno por trozo y solo a
# partir de SITE_MIN metros del centro. Probabilidad de cada uno por trozo;
# las cuevas solo salen donde hay una ladera y los cráteres, solo lejos.
const SITE_MIN := 250.0
const WRECK_MIN := 300.0
const CRATER_MIN := 600.0
const CAVE_CHANCE := 0.15
const WRECK_CHANCE := 0.1
const CRATER_CHANCE := 0.25
const SITE_TRIES := 24
# La montaña sube detrás de la cueva entre CAVE_RISE y CAVE_MAX_RISE metros.
const CAVE_RISE := 4.0
# La loma que tapa la bóveda por fuera llega a su altura a este tanto de su radio.
const MOUND_SCALE := 1.5
# Rampa de la entrada: metros de largo desde la boca y pendiente (unos 30 grados).
const RAMP_LENGTH := 22.0
const RAMP_SLOPE := 0.6
const CAVE_MAX_RISE := 45.0
const SITE_FLAT := {"nave": 3.0, "crater": 4.0}
# Biomas: grandes zonas por ruido de baja frecuencia. Desde BIOME_START metros
# del centro empiezan a mezclarse con la llanura de polvo (el bioma inicial,
# igual que antes) y a BIOME_FULL ya mandan. BIOME_BLEND es lo ancha que es la
# franja de mezcla entre dos biomas, en unidades del ruido.
const BIOME_START := 180.0
const BIOME_FULL := 260.0
const BIOME_BLEND := 0.12
# Orden de los pesos de _biome_weights.
const BIOME_IDS := ["polvo", "oxido", "hielo", "basalto"]
const BIOME_NAMES := {
	"polvo": "Llanura de polvo", "oxido": "Desierto de óxido", "hielo": "Campo de hielo",
	"basalto": "Mesetas de basalto", "montana": "Montañas nevadas",
}
# Color del mapa de cada bioma.
const BIOME_MAP_COLORS := {
	"polvo": Color(0.62, 0.58, 0.52), "oxido": Color(0.78, 0.38, 0.22), "hielo": Color(0.72, 0.88, 0.96),
	"basalto": Color(0.24, 0.25, 0.3), "montana": Color(0.93, 0.95, 1.0),
}
# Por bioma [polvo, óxido, hielo, basalto]: multiplica el color del suelo, el de
# las rocas y la cantidad de árboles. El suelo conserva TINT_KEPT del color de
# la etapa (el verde de la terraformación) donde no manda la llanura.
const GROUND_TINT := [Color(1, 1, 1), Color(1.1, 0.55, 0.36), Color(0.88, 0.98, 1.1), Color(0.5, 0.5, 0.56)]
const ROCK_TINT := [Color(1, 1, 1), Color(1.4, 0.8, 0.62), Color(0.95, 1.05, 1.2), Color(0.6, 0.6, 0.66)]
const TREE_FACTOR := [1.0, 0.35, 0.15, 0.1]
const TINT_KEPT := 0.4
# Qué sale en el suelo llano de cada bioma: probabilidad de [silicio, hierro,
# cobre, hielo]. La llanura es la de siempre.
const RESOURCE_MIX := [[0.35, 0.30, 0.20, 0.15], [0.15, 0.55, 0.20, 0.10], [0.20, 0.15, 0.10, 0.55], [0.35, 0.20, 0.35, 0.10]]
const MIX_TYPES := ["silicio", "hierro", "cobre", "hielo"]
# Mesetas de basalto: cuánto suben y entre qué valores del ruido pasan de llano a alto.
const PLATEAU_HEIGHT := 7.0
const PLATEAU_FROM := -0.1
const PLATEAU_TO := 0.3
# Por encima de esta altura el mapa pone "montaña".
const MOUNTAIN_BIOME_HEIGHT := 28.0

## El nodo main: crea los recursos y lleva el deshielo.
var world: Node3D
## Un solo cuerpo para todo el suelo; cada trozo cercano le añade su forma.
var body := StaticBody3D.new()
var material := ShaderMaterial.new()
var plants_visible := false:
	set(value):
		plants_visible = value
		for chunk in _chunks.values():
			if chunk["trees"]:
				chunk["trees"].visible = value
				_set_trees_solid(chunk["trees"], value)

var noise := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _ranges := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _biome_a := FastNoiseLite.new()
var _biome_b := FastNoiseLite.new()
var _plateau := FastNoiseLite.new()
## Semilla de la partida (Game.world_seed): 0 es el mapa de siempre.
var world_seed := 0
# Por trozo (Vector2i): {"center", "far", "detail", "shape", "trees", "ice",
# "site", "stage", "work", "load_ms"}. "site" es el sitio recóndito del trozo
# ({} si no tiene). "far" solo existe con el bloque abierto. "stage" es el paso
# de preparación por el que va (LOAD_STEPS = listo) y "work" lo que lleva hecho.
var _chunks := {}
# Por bloque (Vector2i): {"center", "mesh", "expanded", "ready", "dirty"}.
var _blocks := {}
# Trabajo pendiente, lo más urgente primero: ["expand", bloque] o ["load", trozo].
var _queue := []
## Para el contador F3: ms que costó preparar el último trozo y trozos listos.
var last_chunk_ms := 0.0
var loaded_chunks := 0
var _tree_meshes: Array[Mesh] = []
var _boulder_mesh: Mesh
# Vértices de la malla de las rocas grandes, para darles la misma forma al chocar.
var _boulder_hull := PackedVector3Array()
var _deco_material := StandardMaterial3D.new()
var _check_time := 0.0
var _last_pos := Vector3.ZERO
# Sitio recóndito del trozo que se está preparando.
var _avoid := {}
# Sitios recónditos por trozo (Vector2i), para excavar el terreno.
var _sites := {}


func _init() -> void:
	noise.seed = 7
	noise.frequency = 0.02
	_hills.seed = 11
	_hills.frequency = 0.006
	_ridges.seed = 3
	_ridges.frequency = 0.004
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 4
	_ranges.seed = 5
	_ranges.frequency = 0.0015
	_forest.seed = 13
	_forest.frequency = 0.01
	_biome_a.seed = 14
	_biome_a.frequency = 0.0009
	_biome_b.seed = 9
	_biome_b.frequency = 0.0009
	_plateau.seed = 41
	_plateau.frequency = 0.012
	_apply_seed()


## Cambia las semillas de todos los ruidos según world_seed. Con 0 quedan las
## de siempre, así que las partidas viejas tienen el mismo mapa.
func _apply_seed() -> void:
	var bases := {noise: 7, _hills: 11, _ridges: 3, _ranges: 5, _forest: 13, _biome_a: 14, _biome_b: 9, _plateau: 41}
	for n in bases:
		n.seed = int(bases[n]) + world_seed * 101


## Prepara el mapa con el jugador en "around": todas las mallas lejanas y las
## detalladas que ya se ven.
func build(around: Vector3) -> void:
	_apply_seed()
	var shader := Shader.new()
	# El color de cada triángulo va en el vértice; el alfa dice si es suelo, que
	# se tiñe con el color de la etapa, o roca y nieve, que no cambian.
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	ALBEDO = COLOR.rgb * mix(vec3(1.0), tint.rgb, COLOR.a);
	ROUGHNESS = 1.0;
}
"""
	material.shader = shader
	_deco_material.vertex_color_use_as_albedo = true
	_deco_material.roughness = 1.0
	_build_deco_meshes()
	add_child(body)
	var count := int(WORLD_SIZE / CHUNK)
	# Primero los sitios recónditos: cambian la altura del terreno.
	for i in count:
		for j in count:
			var key := Vector2i(i, j)
			var site := site_of(key, Vector3(-WORLD_SIZE / 2.0 + (i + 0.5) * CHUNK, 0.0, -WORLD_SIZE / 2.0 + (j + 0.5) * CHUNK))
			if not site.is_empty():
				_sites[key] = site
	for i in count:
		for j in count:
			var key := Vector2i(i, j)
			var center := Vector3(-WORLD_SIZE / 2.0 + (i + 0.5) * CHUNK, 0.0, -WORLD_SIZE / 2.0 + (j + 0.5) * CHUNK)
			_chunks[key] = {"center": center, "far": null, "detail": null, "shape": null, "trees": null, "ice": [],
				"site": _sites.get(key, {}), "stage": 0, "work": {}, "load_ms": 0.0}
	var blocks := ceili(float(count) / BLOCK)
	for i in blocks:
		for j in blocks:
			var size := BLOCK * CHUNK
			var center := Vector3(-WORLD_SIZE / 2.0 + (i + 0.5) * size, 0.0, -WORLD_SIZE / 2.0 + (j + 0.5) * size)
			var mesh := MeshInstance3D.new()
			mesh.mesh = _chunk_mesh(center, FAR_STEP, size)[0]
			mesh.material_override = material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.position = center
			add_child(mesh)
			_blocks[Vector2i(i, j)] = {"center": center, "mesh": mesh, "expanded": false, "ready": false, "dirty": false}
	_update(around, INF)


## Altura del terreno en un vértice de la malla: la del ruido, salvo donde se
## ha excavado para construir (Game.digs).
func height_at(x: float, z: float, weights: Variant = null) -> float:
	var h := _carve(x, z, _noise_height(x, z, weights))
	if not Game.digs.is_empty():
		var key := _vertex(x, z)
		# Solo en los vértices: entre ellos manda el ruido (pendientes).
		var on_grid := absf(-WORLD_SIZE / 2.0 + key.x * STEP - x) < 0.01 and absf(-WORLD_SIZE / 2.0 + key.y * STEP - z) < 0.01
		if on_grid and Game.digs.has(key):
			h = minf(h, float(Game.digs[key]))
	return h


## Vértice de la malla detallada más cercano al punto.
static func _vertex(x: float, z: float) -> Vector2i:
	return Vector2i(roundi((x + WORLD_SIZE / 2.0) / STEP), roundi((z + WORLD_SIZE / 2.0) / STEP))


## Rebaja hasta la altura "level" el terreno bajo un rectángulo de tamaño
## "size" (ancho, fondo) con el centro y el giro de xform, y rehace los trozos
## que cambian. Se bajan también los vértices a menos de STEP del borde para
## que ningún triángulo asome dentro.
func dig(xform: Transform3D, size: Vector2, level: float) -> void:
	var half := size / 2.0 + Vector2(STEP, STEP)
	var reach := half.length()
	var c := xform.origin
	var first := _vertex(c.x - reach, c.z - reach)
	var last := _vertex(c.x + reach, c.z + reach)
	var changed := {}
	for i in range(first.x, last.x + 1):
		for j in range(first.y, last.y + 1):
			var x := -WORLD_SIZE / 2.0 + i * STEP
			var z := -WORLD_SIZE / 2.0 + j * STEP
			var local := xform.basis.inverse() * Vector3(x - c.x, 0.0, z - c.z)
			if absf(local.x) > half.x or absf(local.z) > half.y:
				continue
			var key := Vector2i(i, j)
			if height_at(x, z) <= level:
				continue
			Game.digs[key] = level
			# Un vértice del borde de un trozo es de los dos (o cuatro) trozos.
			for dx in [-0.01, 0.01]:
				for dz in [-0.01, 0.01]:
					changed[_chunk_key(x + dx, z + dz)] = true
	for key in changed:
		if _chunks.has(key):
			_rebuild_ground(key)


func _chunk_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x + WORLD_SIZE / 2.0) / CHUNK), floori((z + WORLD_SIZE / 2.0) / CHUNK))


## Rehace las mallas y la colisión de un trozo sin tocar lo que tiene encima.
func _rebuild_ground(key: Vector2i) -> void:
	var chunk: Dictionary = _chunks[key]
	var center: Vector3 = chunk["center"]
	if chunk["far"] != null:
		chunk["far"].mesh = _chunk_mesh(center, FAR_STEP)[0]
	var block: Dictionary = _blocks[_block_key(key)]
	if block["expanded"] and block["ready"]:
		# El bloque no se ve: se rehace cuando vuelva a hacer falta.
		block["dirty"] = true
	else:
		_rebuild_block(block)
	if chunk["stage"] < 6:
		# Si la malla detallada va a medias, lleva las alturas de antes: se empieza de nuevo.
		chunk["stage"] = 0
		chunk["work"] = {}
		return
	var built := _chunk_mesh(center, STEP)
	(chunk["detail"].get_child(0) as MeshInstance3D).mesh = built[0]
	if chunk["stage"] >= 7:
		chunk["shape"].shape = _concave(built[1])
	else:
		chunk["work"]["faces"] = built[1]


func _concave(faces: PackedVector3Array) -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	return shape


static func _block_key(key: Vector2i) -> Vector2i:
	return Vector2i(key.x / BLOCK, key.y / BLOCK)


func _rebuild_block(block: Dictionary) -> void:
	block["mesh"].mesh = _chunk_mesh(block["center"], FAR_STEP, BLOCK * CHUNK)[0]
	block["dirty"] = false


func _noise_height(x: float, z: float, weights: Variant = null) -> float:
	var h := _base_height(x, z)
	if Vector2(x, z).length() < BIOME_START:
		return h
	var basalt: float = (weights if weights != null else _biome_weights(x, z))[3]
	if basalt > 0.0:
		h += basalt * PLATEAU_HEIGHT * smoothstep(PLATEAU_FROM, PLATEAU_TO, _plateau.get_noise_2d(x, z))
	return h


## Pesos de los biomas en un punto, [polvo, óxido, hielo, basalto], que suman 1.
## Cerca del centro todo es llanura de polvo.
func _biome_weights(x: float, z: float) -> Array:
	var far := smoothstep(BIOME_START, BIOME_FULL, Vector2(x, z).length())
	if far <= 0.0:
		return [1.0, 0.0, 0.0, 0.0]
	var a := smoothstep(-BIOME_BLEND, BIOME_BLEND, _biome_a.get_noise_2d(x, z))
	var b := smoothstep(-BIOME_BLEND, BIOME_BLEND, _biome_b.get_noise_2d(x, z))
	var rust := a * b * far
	var basalt := a * (1.0 - b) * far
	var ice := (1.0 - a) * b * far
	return [1.0 - rust - basalt - ice, rust, ice, basalt]


## Bioma que manda en un punto: una de las BIOME_NAMES. Las zonas altas son
## montañas, sea cual sea el bioma de debajo.
func biome_at(x: float, z: float) -> String:
	if _noise_height(x, z) > MOUNTAIN_BIOME_HEIGHT:
		return "montana"
	return BIOME_IDS[_dominant(_biome_weights(x, z))]


func _dominant(weights: Array) -> int:
	var best := 0
	for k in weights.size():
		if weights[k] > weights[best]:
			best = k
	return best


## Mezcla de los colores de la lista según los pesos.
func _blend(list: Array, weights: Array) -> Color:
	var c := Color(0, 0, 0)
	for k in weights.size():
		c += list[k] * float(weights[k])
	return c


## Imagen del mapa de "size" x "size" píxeles con el color de cada bioma,
## sombreado por la altura. Norte (-Z) arriba.
func biome_map(size: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for j in size:
		for i in size:
			var x := -WORLD_SIZE / 2.0 + (i + 0.5) * WORLD_SIZE / size
			var z := -WORLD_SIZE / 2.0 + (j + 0.5) * WORLD_SIZE / size
			var h := _noise_height(x, z)
			var id: String = "montana" if h > MOUNTAIN_BIOME_HEIGHT else BIOME_IDS[_dominant(_biome_weights(x, z))]
			var shade := 0.82 + 0.18 * clampf(h / 40.0, -0.5, 1.0)
			var c: Color = BIOME_MAP_COLORS[id] * shade
			image.set_pixel(i, j, Color(c.r, c.g, c.b))
	return image


func _base_height(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * HEIGHT
	var wild := smoothstep(MOUNTAIN_START, MOUNTAIN_FULL, Vector2(x, z).length())
	if wild <= 0.0:
		return h
	var hills := (_hills.get_noise_2d(x, z) * 0.5 + 0.5) * HILL_HEIGHT
	# Las cordilleras aparecen solo donde el ruido de escala grande lo dice; junto
	# al borde siempre hay montañas, que hacen de muro.
	var edge := smoothstep(WORLD_SIZE / 2.0 - EDGE_WALL, WORLD_SIZE / 2.0 - 10.0, maxf(absf(x), absf(z)))
	var ranges := maxf(smoothstep(-0.1, 0.35, _ranges.get_noise_2d(x, z)), edge)
	var ridge := clampf((_ridges.get_noise_2d(x, z) + 0.8) / 1.8, 0.0, 1.0)
	return h + wild * (hills + MOUNTAIN_HEIGHT * ranges * pow(ridge, 2.5)) + edge * EDGE_HEIGHT


func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	var pos: Vector3 = world.player.global_position
	_check_time -= delta
	if _check_time <= 0.0:
		_check_time = 0.25
		_scan(pos)
	_pump(BUILD_BUDGET_MS)


## Pone al día lo que se ve de cada bloque y cada trozo, borra lo que queda
## lejos y apunta en la cola lo que hay que preparar, lo más cercano primero.
func _update(pos: Vector3, budget_ms: float) -> void:
	_scan(pos)
	_pump(budget_ms)


func _scan(pos: Vector3) -> void:
	var work := []
	for key in _blocks:
		var block: Dictionary = _blocks[key]
		var d := _rect_distance(block["center"], BLOCK * CHUNK / 2.0, pos)
		if not block["expanded"] and d < EXPAND_RANGE:
			block["expanded"] = true
			block["ready"] = false
		elif block["expanded"] and d > COLLAPSE_RANGE and _collapse(block, key):
			continue
		if block["expanded"] and not block["ready"]:
			work.append([d - 1000.0, ["expand", key]])
	for key in _chunks:
		var chunk: Dictionary = _chunks[key]
		var d := _rect_distance(chunk["center"], CHUNK / 2.0, pos)
		if chunk["stage"] < LOAD_STEPS and d < LOAD_RANGE and _blocks[_block_key(key)]["expanded"]:
			work.append([d, ["load", key]])
		elif chunk["detail"] != null and d > UNLOAD_RANGE:
			_unload(key)
		_show(key, d)
	work.sort_custom(func(a, b): return a[0] < b[0])
	_queue.clear()
	for entry in work:
		_queue.append(entry[1])
	_last_pos = pos


## Qué malla se ve en un trozo: la detallada si está lista y cerca; si no, la
## lejana (la del bloque mientras este no esté abierto).
func _show(key: Vector2i, d: float) -> void:
	var chunk: Dictionary = _chunks[key]
	var block: Dictionary = _blocks[_block_key(key)]
	var open: bool = block["expanded"] and block["ready"]
	var near: bool = open and chunk["stage"] >= LOAD_STEPS and d < NEAR_RANGE
	if chunk["far"] != null:
		chunk["far"].visible = not near
	if chunk["detail"] != null:
		chunk["detail"].visible = near and chunk["stage"] >= LOAD_STEPS


## Cierra un bloque abierto y vuelve a dibujarlo entero. false si algún trozo
## suyo sigue con la malla detallada.
func _collapse(block: Dictionary, key: Vector2i) -> bool:
	for i in BLOCK:
		for j in BLOCK:
			var chunk_key := key * BLOCK + Vector2i(i, j)
			if _chunks.has(chunk_key) and _chunks[chunk_key]["detail"] != null:
				return false
	if block["dirty"]:
		_rebuild_block(block)
	block["mesh"].visible = true
	block["expanded"] = false
	block["ready"] = false
	for i in BLOCK:
		for j in BLOCK:
			var chunk: Dictionary = _chunks.get(key * BLOCK + Vector2i(i, j), {})
			if chunk.is_empty():
				continue
			chunk["stage"] = 0
			chunk["work"] = {}
			if chunk["far"] != null:
				chunk["far"].queue_free()
				chunk["far"] = null
	return true


## Hace trabajo de la cola sin pasar de budget_ms milisegundos (un paso
## empezado siempre se acaba). Con INF vacía la cola entera.
func _pump(budget_ms: float) -> void:
	var start := Time.get_ticks_usec()
	while not _queue.is_empty():
		if (Time.get_ticks_usec() - start) / 1000.0 > budget_ms:
			return
		var task: Array = _queue[0]
		if task[0] == "expand":
			_expand_step(task[1])
			if _blocks[task[1]]["ready"]:
				_queue.pop_front()
		else:
			_load_step(task[1])
			if _chunks[task[1]]["stage"] >= LOAD_STEPS:
				_queue.pop_front()


## Hace la malla lejana de un trozo del bloque que falte; con todas hechas el
## bloque se esconde.
func _expand_step(key: Vector2i) -> void:
	var block: Dictionary = _blocks[key]
	for i in BLOCK:
		for j in BLOCK:
			var chunk_key := key * BLOCK + Vector2i(i, j)
			if not _chunks.has(chunk_key) or _chunks[chunk_key]["far"] != null:
				continue
			var chunk: Dictionary = _chunks[chunk_key]
			var far := MeshInstance3D.new()
			far.mesh = _chunk_mesh(chunk["center"], FAR_STEP)[0]
			far.material_override = material
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			far.position = chunk["center"]
			add_child(far)
			chunk["far"] = far
			return
	block["ready"] = true
	block["mesh"].visible = false
	if block["dirty"]:
		_rebuild_block(block)


## Distancia en horizontal del punto al borde de un cuadrado (0 si está dentro).
func _rect_distance(c: Vector3, half: float, pos: Vector3) -> float:
	var dx := maxf(0.0, absf(pos.x - c.x) - half)
	var dz := maxf(0.0, absf(pos.z - c.z) - half)
	return Vector2(dx, dz).length()


## Prepara un trozo de golpe (al empezar y al teletransportarse).
func _load(key: Vector2i) -> void:
	while _chunks[key]["stage"] < LOAD_STEPS:
		_load_step(key)


## Un paso de la preparación de un trozo. Cada uno es corto para repartir el
## trabajo en varios fotogramas; entre pasos el trozo no se ve.
func _load_step(key: Vector2i) -> void:
	var chunk: Dictionary = _chunks[key]
	var center: Vector3 = chunk["center"]
	var work: Dictionary = chunk["work"]
	var t := Time.get_ticks_usec()
	var cells := int(CHUNK / STEP)
	match int(chunk["stage"]):
		0:
			work["mesh"] = _mesh_start(center, STEP, CHUNK)
			chunk["load_ms"] = 0.0
			_mesh_heights(work["mesh"], cells / 2)
		1:
			_mesh_heights(work["mesh"], cells + 1)
		2:
			_mesh_rows(work["mesh"], cells / 3)
		3:
			_mesh_rows(work["mesh"], cells * 2 / 3)
		4:
			_mesh_rows(work["mesh"], cells)
		5:
			var built := _mesh_finish(work["mesh"])
			work.erase("mesh")
			work["faces"] = built[1]
			var detail := Node3D.new()
			detail.position = center
			detail.visible = false
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.mesh = built[0]
			mesh_instance.material_override = material
			# El suelo no proyecta sombra: las sombras son para lo que hay encima.
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			detail.add_child(mesh_instance)
			add_child(detail)
			chunk["detail"] = detail
		6:
			var collision := CollisionShape3D.new()
			collision.shape = _concave(work["faces"])
			collision.position = center
			body.add_child(collision)
			chunk["shape"] = collision
			work.erase("faces")
			# La misma semilla para cada trozo: al volver, todo está en el mismo sitio.
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(key) + world_seed * 7919
			work["rng"] = rng
		7:
			# Lo demás no se pone dentro del sitio recóndito, pero se sortea igual
			# para que no cambie de sitio respecto a antes.
			_avoid = chunk["site"]
			chunk["trees"] = _plant_trees(chunk["detail"], center, work["rng"])
			_avoid = {}
		8:
			if not _is_start(center):
				_avoid = chunk["site"]
				_place_boulders(chunk["detail"], center, work["rng"])
				_avoid = {}
		9:
			if not _is_start(center):
				_avoid = chunk["site"]
				_place_resources(chunk, chunk["detail"], center, work["rng"])
				_avoid = {}
		10:
			_build_site(chunk, chunk["detail"], key)
		11:
			work.clear()
	chunk["stage"] += 1
	chunk["load_ms"] += (Time.get_ticks_usec() - t) / 1000.0
	if chunk["stage"] >= LOAD_STEPS:
		loaded_chunks += 1
		last_chunk_ms = chunk["load_ms"]
		_show(key, _rect_distance(center, CHUNK / 2.0, _last_pos))


func _is_start(center: Vector3) -> bool:
	return absf(center.x) < START_AREA / 2.0 + CHUNK / 2.0 and absf(center.z) < START_AREA / 2.0 + CHUNK / 2.0


## El sitio recóndito de un trozo: {"type", "pos", "rot"} o {} si no hay.
## Depende solo del trozo, así que siempre sale igual. Se mira con la altura
## del ruido, antes de excavar.
func site_of(key: Vector2i, center: Vector3) -> Dictionary:
	var distance := Vector2(center.x, center.z).length()
	if distance < SITE_MIN:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([key.x, key.y, "sitio"]) + world_seed * 104729
	var roll := rng.randf()
	var type := ""
	if roll < CAVE_CHANCE:
		type = "cueva"
	elif roll < CAVE_CHANCE + WRECK_CHANCE and distance >= WRECK_MIN:
		type = "nave"
	elif roll < CAVE_CHANCE + WRECK_CHANCE + CRATER_CHANCE and distance >= CRATER_MIN:
		type = "crater"
	if type == "":
		return {}
	var margin: float = Sites.RADIUS[type] + 2.0
	for n in SITE_TRIES:
		var x := center.x + rng.randf_range(-CHUNK / 2.0 + margin, CHUNK / 2.0 - margin)
		var z := center.z + rng.randf_range(-CHUNK / 2.0 + margin, CHUNK / 2.0 - margin)
		var rot := rng.randf_range(0.0, TAU)
		var site := {}
		match type:
			"cueva":
				site = _cave_site(x, z)
			"nave":
				if _flat(x, z, Sites.RADIUS[type], SITE_FLAT[type]):
					site = {"pos": Vector3(x, _noise_height(x, z), z), "rot": rot}
			"crater":
				# El fondo del cráter tiene que quedar por encima del agua.
				if _flat(x, z, Sites.RADIUS[type], SITE_FLAT[type]) and _noise_height(x, z) - Sites.CRATER_DEPTH > DRY_LEVEL + 0.5:
					site = {"pos": Vector3(x, _noise_height(x, z) - Sites.CRATER_DEPTH, z), "rot": rot}
		if not site.is_empty():
			site["type"] = type
			return site
	return {}


## Cueva metida en la ladera de una montaña: la boca mira cuesta abajo y
## detrás el terreno sube al menos CAVE_RISE metros, así que la bóveda queda
## dentro de la montaña. {} si en (x, z) no hay ladera que sirva.
func _cave_site(x: float, z: float) -> Dictionary:
	var dx := _noise_height(x + 2.0, z) - _noise_height(x - 2.0, z)
	var dz := _noise_height(x, z + 2.0) - _noise_height(x, z - 2.0)
	var downhill := -Vector2(dx, dz)
	if downhill.length() < 0.01:
		return {}
	var rot := atan2(downhill.x, downhill.y)
	var basis := Basis(Vector3.UP, rot)
	var r := Sites.CAVE_RADIUS
	var at := func(local: Vector3) -> float:
		var p := Vector3(x, 0, z) + basis * local
		return _noise_height(p.x, p.z)
	var floor_y: float = at.call(Vector3(0, 0, r * 0.9))
	var back: float = at.call(Vector3(0, 0, -r))
	if floor_y < DRY_LEVEL + 0.5 or back - floor_y < CAVE_RISE or back - floor_y > CAVE_MAX_RISE:
		return {}
	# A los lados el suelo no puede quedar por debajo del borde de la bóveda.
	for side in [-1.0, 1.0]:
		if at.call(Vector3(side * r, 0, 0)) < floor_y - 2.0:
			return {}
	# Y al final de la rampa de la entrada tiene que llegar al suelo.
	if at.call(Vector3(0, 0, r + RAMP_LENGTH)) < floor_y - RAMP_LENGTH * RAMP_SLOPE:
		return {}
	return {"pos": Vector3(x, floor_y - 0.2, z), "rot": rot}


## true si la diferencia de altura en un círculo de radio "radius" no pasa de "flat".
func _flat(x: float, z: float, radius: float, flat: float) -> bool:
	var low := INF
	var high := -INF
	for k in 9:
		var p := Vector2(x, z) if k == 8 else Vector2(x, z) + Vector2.from_angle(k * TAU / 8.0) * radius
		var h := _noise_height(p.x, p.y)
		low = minf(low, h)
		high = maxf(high, h)
	return high - low <= flat and low >= DRY_LEVEL + 0.5


## Altura del terreno con lo que cambia el sitio recóndito del trozo: la
## cueva excava su suelo y un pasillo hasta la boca; el cráter hunde el
## centro y levanta un borde.
func _carve(x: float, z: float, h: float) -> float:
	var site: Dictionary = _sites.get(_chunk_key(x, z), {})
	if site.is_empty():
		return h
	var pos: Vector3 = site["pos"]
	match String(site["type"]):
		"cueva":
			var local := Basis(Vector3.UP, -float(site["rot"])) * Vector3(x - pos.x, 0.0, z - pos.z)
			var r := Sites.CAVE_RADIUS
			var d := Vector2(local.x, local.z).length()
			# Delante de la boca no hay montaña: queda un pasillo hasta fuera.
			var front := 0.0
			if local.z > 0.0:
				front = 1.0 - smoothstep(Sites.MOUTH_HALF, Sites.MOUTH_HALF + 3.0, absf(local.x))
			# Alrededor, una loma tan alta como la bóveda la tapa por fuera
			# aunque la ladera sea suave; luego baja hasta el terreno.
			# Sube poco a poco desde la bóveda para no meterse en ella.
			var mound := pos.y + (Sites.CAVE_HEIGHT * 1.15 + 0.5) * smoothstep(r * 1.1, r * MOUND_SCALE, d)
			mound = lerpf(mound, h, smoothstep(r * MOUND_SCALE, r * MOUND_SCALE + 10.0, d))
			h = maxf(h, lerpf(mound, h, front))
			# Dentro, el suelo se excava hasta el de la cueva. Se excava algo
			# más allá de la bóveda para que la pared de tierra no asome por dentro.
			if d < r * 1.1:
				return minf(h, pos.y)
			# Delante, una rampa hasta la boca: se excava lo que sobra y se
			# rellena lo que falta para que se pueda subir andando.
			# La rampa va en línea recta desde la boca hasta la altura que tiene
			# el terreno al final, así no tiene escalones.
			if local.z > 0.0:
				var end := Vector3(pos.x, 0.0, pos.z) + Basis(Vector3.UP, float(site["rot"])) * Vector3(0, 0, r + RAMP_LENGTH)
				var end_y := clampf(_noise_height(end.x, end.z), pos.y - RAMP_LENGTH * RAMP_SLOPE, pos.y)
				var ramp := lerpf(pos.y, end_y, clampf((local.z - r) / RAMP_LENGTH, 0.0, 1.0))
				var weight := front * (1.0 - smoothstep(r + RAMP_LENGTH - 3.0, r + RAMP_LENGTH + 2.0, local.z))
				return lerpf(h, ramp, weight)
			return h
		"crater":
			var d := Vector2(x - pos.x, z - pos.z).length()
			var rc := Sites.CRATER_RADIUS
			if d > rc + 8.0:
				return h
			# Perfil de coseno: la pendiente no pasa de unos 40 grados y se
			# puede salir andando.
			var bowl := Sites.CRATER_DEPTH * (0.5 + 0.5 * cos(PI * d / rc)) if d < rc else 0.0
			var rim := Sites.CRATER_RIM * exp(-pow((d - rc - 1.0) / 3.0, 2.0))
			return h - bowl + rim
	return h


func _build_site(chunk: Dictionary, detail: Node3D, key: Vector2i) -> void:
	var site: Dictionary = chunk["site"]
	if site.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([key.x, key.y, "contenido"]) + world_seed * 1299709
	var id := "%s_%d_%d" % [site["type"], key.x, key.y]
	var node: Node3D
	match String(site["type"]):
		"cueva":
			node = Sites.cave(world, site["pos"], site["rot"], chunk["center"], id, rng)
		"nave":
			node = Sites.wreck(world, site["pos"], site["rot"], chunk["center"], id, rng)
		"crater":
			node = Sites.crater(world, site["pos"], site["rot"], chunk["center"], _boulder_mesh, rng)
	detail.add_child(node)


## Prepara ya los trozos que se ven desde pos, sin repartirlo en fotogramas.
func load_around(pos: Vector3) -> void:
	_update(pos, INF)


## true si el punto está dentro de una cueva.
func cave_at(pos: Vector3) -> bool:
	var key := _chunk_key(pos.x, pos.z)
	if not _chunks.has(key):
		return false
	var site: Dictionary = _chunks[key]["site"]
	if site.is_empty() or site["type"] != "cueva":
		return false
	var offset: Vector3 = pos - site["pos"]
	if Vector2(offset.x, offset.z).length() < Sites.CAVE_RADIUS * 0.8 and offset.y < Sites.CAVE_HEIGHT:
		return true
	# En el túnel de la entrada también, salvo en los últimos metros.
	var local := Basis(Vector3.UP, -float(site["rot"])) * offset
	return absf(local.x) < 4.0 and local.z > 0.0 and local.z < Sites.TUNNEL_END - 2.0 and local.y < 5.0


## Todos los sitios recónditos del mapa: [{"type", "pos", "rot"}].
func sites() -> Array:
	var list := []
	for key in _sites:
		var site: Dictionary = _sites[key].duplicate()
		site["id"] = "%s_%d_%d" % [site["type"], key.x, key.y]
		list.append(site)
	return list


## true si el punto cae dentro del sitio que se está evitando.
func _in_site(x: float, z: float) -> bool:
	if _avoid.is_empty():
		return false
	var pos: Vector3 = _avoid["pos"]
	return Vector2(x - pos.x, z - pos.z).length() < float(Sites.RADIUS[_avoid["type"]])


func _unload(key: Vector2i) -> void:
	var chunk: Dictionary = _chunks[key]
	for node in chunk["ice"]:
		world.remove_ice(node)
	chunk["ice"] = []
	if chunk["stage"] >= LOAD_STEPS:
		loaded_chunks -= 1
	if chunk["detail"] != null:
		chunk["detail"].queue_free()
	if chunk["shape"] != null:
		chunk["shape"].queue_free()
	chunk["detail"] = null
	chunk["shape"] = null
	chunk["trees"] = null
	chunk["stage"] = 0
	chunk["work"] = {}


## Malla de un cuadrado de "size" metros con vértices cada "step" metros, en
## coordenadas relativas a su centro. Devuelve [malla, triángulos para la colisión].
func _chunk_mesh(center: Vector3, step: float, size := CHUNK) -> Array:
	var mesh_state := _mesh_start(center, step, size)
	_mesh_heights(mesh_state, mesh_state["cells"] + 1)
	_mesh_rows(mesh_state, mesh_state["cells"])
	return _mesh_finish(mesh_state)


## Prepara la malla. Después hay que llamar a _mesh_heights, _mesh_rows y
## _mesh_finish, que se pueden repartir en varios fotogramas.
func _mesh_start(center: Vector3, step: float, size: float) -> Dictionary:
	var cells := int(size / step)
	var x0 := center.x - size / 2.0
	var z0 := center.z - size / 2.0
	var width := cells + 1
	var heights := PackedFloat32Array()
	heights.resize(width * width)
	var weights := PackedFloat32Array()
	weights.resize(width * width * 4)
	var count := cells * cells * 6
	# Sitio para los triángulos y el faldón de una vez: es más rápido que ir añadiendo.
	var verts := PackedVector3Array()
	verts.resize(count + cells * 24)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var colors := PackedColorArray()
	colors.resize(verts.size())
	return {"center": center, "step": step, "size": size, "cells": cells, "heights": heights, "weights": weights,
		"verts": verts, "normals": normals, "colors": colors, "n": 0, "row": 0, "hrow": 0}


## Calcula las alturas y los pesos de bioma de las filas de vértices que faltan
## hasta "until" (sin incluirla; hay cells + 1 filas).
func _mesh_heights(st: Dictionary, until: int) -> void:
	var cells: int = st["cells"]
	var step: float = st["step"]
	var center: Vector3 = st["center"]
	var x0: float = center.x - float(st["size"]) / 2.0
	var z0: float = center.z - float(st["size"]) / 2.0
	var width := cells + 1
	var heights: PackedFloat32Array = st["heights"]
	var weights: PackedFloat32Array = st["weights"]
	for i in range(st["hrow"], until):
		for j in width:
			var x: float = x0 + i * step
			var z: float = z0 + j * step
			# Los pesos se calculan una vez por vértice y sirven para la altura y el color.
			var w := _biome_weights(x, z)
			var at := i * width + j
			heights[at] = height_at(x, z, w)
			for k in 4:
				weights[at * 4 + k] = w[k]
	st["hrow"] = until


## Hace los triángulos de las filas que faltan hasta la fila "until" (sin incluirla).
func _mesh_rows(st: Dictionary, until: int) -> void:
	var cells: int = st["cells"]
	var step: float = st["step"]
	var half: float = st["size"] / 2.0
	var heights: PackedFloat32Array = st["heights"]
	var weights: PackedFloat32Array = st["weights"]
	var verts: PackedVector3Array = st["verts"]
	var normals: PackedVector3Array = st["normals"]
	var colors: PackedColorArray = st["colors"]
	var center: Vector3 = st["center"]
	var offset := Vector3(center.x, 0.0, center.z)
	var width := cells + 1
	var n: int = st["n"]
	for i in range(st["row"], until):
		for j in cells:
			var lx := -half + i * step
			var lz := -half + j * step
			var ia := i * width + j
			var ib := ia + width
			var a := Vector3(lx, heights[ia], lz)
			var b := Vector3(lx + step, heights[ib], lz)
			var c := Vector3(lx, heights[ia + 1], lz + step)
			var d := Vector3(lx + step, heights[ib + 1], lz + step)
			# Cada cuadro se parte en (a, b, c) y (b, d, c), como en surface_height.
			n = _triangle(verts, normals, colors, n, a, b, c, offset, weights, ia, ib, ia + 1)
			n = _triangle(verts, normals, colors, n, b, d, c, offset, weights, ib, ib + 1, ia + 1)
	st["n"] = n
	st["row"] = until


## Cierra la malla: faldón y superficie. Devuelve [malla, triángulos para la colisión].
func _mesh_finish(st: Dictionary) -> Array:
	var cells: int = st["cells"]
	var step: float = st["step"]
	var half: float = st["size"] / 2.0
	var heights: PackedFloat32Array = st["heights"]
	var verts: PackedVector3Array = st["verts"]
	var normals: PackedVector3Array = st["normals"]
	var colors: PackedColorArray = st["colors"]
	var n: int = st["n"]
	var faces := verts.slice(0, cells * cells * 6)
	# Faldón: una tira vertical bajo cada borde que tapa el hueco con el trozo
	# vecino cuando este tiene otro nivel de detalle.
	for side in 4:
		for k in cells:
			var p: Vector3
			var q: Vector3
			var out: Vector3
			match side:
				0:
					p = Vector3(-half, heights[k], -half + k * step)
					q = Vector3(-half, heights[k + 1], -half + (k + 1) * step)
					out = Vector3.LEFT
				1:
					p = Vector3(half, heights[cells * (cells + 1) + k], -half + k * step)
					q = Vector3(half, heights[cells * (cells + 1) + k + 1], -half + (k + 1) * step)
					out = Vector3.RIGHT
				2:
					p = Vector3(-half + k * step, heights[k * (cells + 1)], -half)
					q = Vector3(-half + (k + 1) * step, heights[(k + 1) * (cells + 1)], -half)
					out = Vector3.FORWARD
				_:
					p = Vector3(-half + k * step, heights[k * (cells + 1) + cells], half)
					q = Vector3(-half + (k + 1) * step, heights[(k + 1) * (cells + 1) + cells], half)
					out = Vector3.BACK
			var pd := p + Vector3.DOWN * SKIRT
			var qd := q + Vector3.DOWN * SKIRT
			for v in [p, q, pd, q, qd, pd]:
				verts[n] = v
				normals[n] = out
				colors[n] = Color(0.45, 0.42, 0.4, 0.0)
				n += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return [mesh, faces]


## Escribe el triángulo en la posición n de las listas y devuelve la siguiente.
## ia, ib e ic son los índices de sus vértices en "weights" (pesos de bioma).
func _triangle(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, n: int, a: Vector3, b: Vector3, c: Vector3, offset: Vector3, weights: PackedFloat32Array, ia: int, ib: int, ic: int) -> int:
	var normal := (c - a).cross(b - a).normalized()
	var mid := weights_mean(weights, ia, ib, ic)
	var color := _shade(a + offset, b + offset, c + offset, normal, mid)
	verts[n] = a
	verts[n + 1] = b
	verts[n + 2] = c
	for k in 3:
		normals[n + k] = normal
		colors[n + k] = color
	return n + 3


## Media de los pesos de bioma de tres vértices.
static func weights_mean(weights: PackedFloat32Array, ia: int, ib: int, ic: int) -> Array:
	var out := []
	for k in 4:
		out.append((weights[ia * 4 + k] + weights[ib * 4 + k] + weights[ic * 4 + k]) / 3.0)
	return out


## Color de un triángulo. Suelo (alfa 1): gris más oscuro en pendiente y en los
## valles, que se tiñe según la etapa. Roca y nieve (alfa 0): color propio.
func _shade(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, weights: Array) -> Color:
	var mid := (a + b + c) / 3.0
	var flat := absf(normal.y)
	var jitter := _hash(mid.x, mid.z) * 0.1 - 0.05
	if mid.y > SNOW_HEIGHT and flat > 0.6:
		var s := 0.9 + jitter
		return Color(s, s + 0.02, s + 0.06, 0.0)
	if flat < ROCK_SLOPE or mid.y > ROCK_HEIGHT:
		var r := 0.22 + 0.12 * flat + jitter
		var rock := _blend(ROCK_TINT, weights)
		return Color(r * rock.r, r * 0.97 * rock.g, r * 1.02 * rock.b, 0.0)
	var height := clampf((mid.y + HEIGHT) / (2.0 * HEIGHT), 0.0, 1.0)
	var v := 0.7 + 0.2 * flat + 0.15 * height + jitter
	var ground := _blend(GROUND_TINT, weights)
	# Donde no manda la llanura, el color de la etapa pesa menos.
	return Color(v * ground.r, v * ground.g, v * ground.b, 1.0 - (1.0 - TINT_KEPT) * (1.0 - float(weights[0])))


## Valor de la lista mezclado según los pesos de los biomas.
func _blend_number(list: Array, weights: Array) -> float:
	var total := 0.0
	for k in weights.size():
		total += float(list[k]) * float(weights[k])
	return total


## Número entre 0 y 1 que depende solo del punto.
func _hash(x: float, z: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)


## Normal del terreno en un punto (para saber si hay mucha pendiente).
func _slope(x: float, z: float) -> float:
	var dx := height_at(x + 1.0, z) - height_at(x - 1.0, z)
	var dz := height_at(x, z + 1.0) - height_at(x, z - 1.0)
	return Vector3(-dx, 2.0, -dz).normalized().y


## Los árboles solo chocan mientras se ven: con ellos ocultos se pasa de largo.
func _set_trees_solid(trees: Node3D, solid: bool) -> void:
	var collider := trees.get_node_or_null("Collision") as StaticBody3D
	if collider:
		collider.collision_layer = 1 if solid else 0


## Árboles y arbustos del trozo, juntos en bosques. Están ocultos hasta que la
## biomasa los hace crecer (plants_visible).
func _plant_trees(detail: Node3D, center: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var lists := []
	for m in _tree_meshes:
		lists.append([])
	for n in TREE_TRIES:
		var x := center.x + rng.randf_range(-CHUNK / 2.0, CHUNK / 2.0)
		var z := center.z + rng.randf_range(-CHUNK / 2.0, CHUNK / 2.0)
		var chance := smoothstep(0.0, 0.5, _forest.get_noise_2d(x, z)) * 0.8 + 0.05
		chance *= _blend_number(TREE_FACTOR, _biome_weights(x, z))
		var kind := rng.randi() % _tree_meshes.size()
		var size := rng.randf_range(0.8, 1.8)
		var turn := rng.randf_range(0.0, TAU)
		var shade := Color.from_hsv(rng.randf_range(0.22, 0.36), rng.randf_range(0.0, 0.25), rng.randf_range(0.85, 1.1))
		if rng.randf() > chance or _in_site(x, z):
			continue
		var y: float = world.surface_height(x, z)
		if y < DRY_LEVEL or y > TREE_LINE or _slope(x, z) < 0.85:
			continue
		var xform := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * size), Vector3(x, y - 0.1, z) - center)
		lists[kind].append([xform, shade])
	var trees := Node3D.new()
	trees.visible = plants_visible
	var collider := StaticBody3D.new()
	collider.name = "Collision"
	for k in lists.size():
		if lists[k].is_empty():
			continue
		trees.add_child(_multimesh(_tree_meshes[k], lists[k]))
		for entry in lists[k]:
			collider.add_child(_tree_collision(k, entry[0]))
	trees.add_child(collider)
	_set_trees_solid(trees, plants_visible)
	detail.add_child(trees)
	return trees


## Forma con la que se choca con un árbol: el tronco (un cilindro) o, en el
## arbusto, la mata entera. Crece con el tamaño del árbol.
func _tree_collision(kind: int, xform: Transform3D) -> CollisionShape3D:
	var size := xform.basis.get_scale().x
	var shape := CylinderShape3D.new()
	var height := 3.0 * size
	if kind == _tree_meshes.size() - 1:
		shape.radius = 0.6 * size
		height = 0.8 * size
	else:
		shape.radius = 0.22 * size
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = xform.origin + Vector3(0, height / 2.0, 0)
	return collision


## Rocas grandes que no se recogen; más en las montañas.
func _place_boulders(detail: Node3D, center: Vector3, rng: RandomNumberGenerator) -> void:
	var list := []
	var rocks := StaticBody3D.new()
	for n in BOULDER_TRIES:
		var x := center.x + rng.randf_range(-CHUNK / 2.0, CHUNK / 2.0)
		var z := center.z + rng.randf_range(-CHUNK / 2.0, CHUNK / 2.0)
		var size := rng.randf_range(1.2, 4.5)
		var stretch := Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.6, 1.1), rng.randf_range(0.8, 1.4))
		var turn := rng.randf_range(0.0, TAU)
		var shade := rng.randf_range(0.8, 1.15)
		var rock := _blend(ROCK_TINT, _biome_weights(x, z))
		var y: float = world.surface_height(x, z)
		var rocky := y > ROCK_HEIGHT or _slope(x, z) < ROCK_SLOPE
		if (not rocky and rng.randf() > 0.3) or _in_site(x, z):
			continue
		var basis := Basis(Vector3.UP, turn).scaled(stretch * size)
		list.append([Transform3D(basis, Vector3(x, y - 0.3 * size, z) - center), Color(shade * rock.r, shade * rock.g, shade * rock.b)])
		# Misma forma que la malla (sin la parte hundida en el suelo no se nota).
		var xform := list[list.size() - 1][0] as Transform3D
		var points := PackedVector3Array()
		for point in _boulder_hull:
			points.append(xform * point)
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var collision := CollisionShape3D.new()
		collision.shape = shape
		rocks.add_child(collision)
	if list.is_empty():
		rocks.free()
		return
	detail.add_child(_multimesh(_boulder_mesh, list))
	detail.add_child(rocks)


## Depósitos de recursos: en la roca sobre todo hierro y cobre, hielo en lo
## alto y silicio en el llano.
func _place_resources(chunk: Dictionary, detail: Node3D, center: Vector3, rng: RandomNumberGenerator) -> void:
	for n in RESOURCES_PER_CHUNK:
		var x := center.x + rng.randf_range(-CHUNK / 2.0, CHUNK / 2.0)
		var z := center.z + rng.randf_range(-CHUNK / 2.0, CHUNK / 2.0)
		var roll := rng.randf()
		var turn := rng.randf_range(0.0, TAU)
		var y: float = world.surface_height(x, z)
		if _slope(x, z) < 0.7 or _in_site(x, z):
			continue
		var weights := _biome_weights(x, z)
		var type := ""
		if y > ROCK_HEIGHT:
			type = "hielo" if roll < 0.4 else ("hierro" if roll < 0.7 else "cobre")
		else:
			type = _flat_resource(roll, weights)
		var node: ResourceNode = world.make_resource(type)
		node.position = Vector3(x, y, z) - center
		node.rotation.y = turn
		detail.add_child(node)
		if type == "hielo":
			chunk["ice"].append(node)
			# Funde antes el más bajo; el de las cumbres no se funde nunca.
			var start := INF
			# El hielo del campo de hielo es permanente y no se funde.
			if y < ICE_SUMMIT and float(weights[2]) < 0.5:
				start = (1.0 - world.MELT_TIME) * clampf(inverse_lerp(-HEIGHT, ICE_SUMMIT, y), 0.0, 1.0)
			world.add_ice(node, start)


## Recurso del suelo llano para una tirada de 0 a 1 según los biomas.
func _flat_resource(roll: float, weights: Array) -> String:
	var total := 0.0
	for k in MIX_TYPES.size():
		for b in weights.size():
			total += float(RESOURCE_MIX[b][k]) * float(weights[b])
		if roll < total:
			return MIX_TYPES[k]
	return MIX_TYPES[MIX_TYPES.size() - 1]


func _multimesh(mesh: Mesh, list: Array) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = list.size()
	for k in list.size():
		multimesh.set_instance_transform(k, list[k][0])
		multimesh.set_instance_color(k, list[k][1])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _deco_material
	return instance


## Mallas de los árboles (pino, frondoso y arbusto) y de las rocas grandes,
## con el color en los vértices para dibujarlas en una sola pasada.
func _build_deco_meshes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var bark := Color(0.4, 0.28, 0.18)
	var green := Color(0.28, 0.58, 0.25)
	# Pino: tronco y tres conos apilados.
	var parts := []
	parts.append([_cylinder(0.12, 0.18, 1.2), Vector3(0, 0.6, 0), bark, 0.0])
	for k in 3:
		parts.append([_cylinder(0.0, 1.1 - k * 0.25, 1.8), Vector3(0, 1.7 + k * 0.8, 0), green, 0.0])
	_tree_meshes.append(_combine(parts, rng))
	# Frondoso: tronco alto y copa redonda.
	parts = []
	parts.append([_cylinder(0.12, 0.2, 2.0), Vector3(0, 1.0, 0), bark, 0.0])
	parts.append([_sphere(1.3, 1.6, 7, 4), Vector3(0, 2.7, 0), green.lightened(0.1), 0.2])
	_tree_meshes.append(_combine(parts, rng))
	# Arbusto.
	parts = [[_sphere(0.7, 1.0, 6, 3), Vector3(0, 0.35, 0), green.darkened(0.1), 0.2]]
	_tree_meshes.append(_combine(parts, rng))
	_boulder_mesh = _combine([[_sphere(1.0, 1.6, 8, 5), Vector3(0, 0.5, 0), Color(0.42, 0.39, 0.37), 0.25]], rng)
	_boulder_hull = (_boulder_mesh.create_convex_shape(true, false) as ConvexPolygonShape3D).points


func _cylinder(top: float, bottom: float, height: float) -> PrimitiveMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 1
	return mesh


func _sphere(radius: float, height: float, segments: int, rings: int) -> PrimitiveMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


## Junta piezas [malla, posición, color, irregularidad] en una malla de caras
## planas. La irregularidad mueve los vértices al azar (sin abrir huecos).
func _combine(parts: Array, rng: RandomNumberGenerator) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for part in parts:
		var arrays: Array = part[0].get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var offsets := {}
		st.set_color(part[2])
		for index in arrays[Mesh.ARRAY_INDEX]:
			var v: Vector3 = vertices[index]
			var key := v.snapped(Vector3.ONE * 0.001)
			if not offsets.has(key):
				offsets[key] = 1.0 + rng.randf_range(-part[3], part[3])
			st.add_vertex(v * offsets[key] + part[1])
	st.generate_normals()
	return st.commit()
