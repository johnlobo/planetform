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

var noise := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _ranges := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
# Por trozo (Vector2i): {"center", "far", "detail", "shape", "trees", "ice"}.
var _chunks := {}
var _tree_meshes: Array[Mesh] = []
var _boulder_mesh: Mesh
var _deco_material := StandardMaterial3D.new()
var _check_time := 0.0


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


## Prepara el mapa con el jugador en "around": todas las mallas lejanas y las
## detalladas que ya se ven.
func build(around: Vector3) -> void:
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
	for i in count:
		for j in count:
			var key := Vector2i(i, j)
			var center := Vector3(-WORLD_SIZE / 2.0 + (i + 0.5) * CHUNK, 0.0, -WORLD_SIZE / 2.0 + (j + 0.5) * CHUNK)
			var far := MeshInstance3D.new()
			far.mesh = _chunk_mesh(center, FAR_STEP)[0]
			far.material_override = material
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			far.position = center
			add_child(far)
			_chunks[key] = {"center": center, "far": far, "detail": null, "shape": null, "trees": null, "ice": []}
	for key in _chunks:
		if _distance(_chunks[key], around) < NEAR_RANGE:
			_load(key)
	_update(around, INF)


## Altura del terreno en un vértice de la malla: la del ruido, salvo donde se
## ha excavado para construir (Game.digs).
func height_at(x: float, z: float) -> float:
	var h := _noise_height(x, z)
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
	chunk["far"].mesh = _chunk_mesh(center, FAR_STEP)[0]
	if chunk["detail"] == null:
		return
	var built := _chunk_mesh(center, STEP)
	(chunk["detail"].get_child(0) as MeshInstance3D).mesh = built[0]
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(built[1])
	chunk["shape"].shape = shape


func _noise_height(x: float, z: float) -> float:
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
		_update(pos, BUILD_BUDGET_MS)


## Muestra en cada trozo la malla que toca, borra lo que queda lejos y prepara
## los trozos que se van a necesitar, los más cercanos primero, sin pasar de
## budget_ms milisegundos.
func _update(pos: Vector3, budget_ms: float) -> void:
	var pending := []
	for key in _chunks:
		var chunk: Dictionary = _chunks[key]
		var d := _distance(chunk, pos)
		if chunk["detail"] == null and d < LOAD_RANGE:
			pending.append([d, key])
		elif chunk["detail"] != null and d > UNLOAD_RANGE:
			_unload(key)
		var near: bool = chunk["detail"] != null and d < NEAR_RANGE
		chunk["far"].visible = not near
		if chunk["detail"] != null:
			chunk["detail"].visible = near
	pending.sort_custom(func(a, b): return a[0] < b[0])
	var start := Time.get_ticks_usec()
	for p in pending:
		if (Time.get_ticks_usec() - start) / 1000.0 > budget_ms:
			# Lo que falte se hace en la siguiente comprobación.
			_check_time = 0.0
			break
		_load(p[1])
		var chunk: Dictionary = _chunks[p[1]]
		var near: bool = p[0] < NEAR_RANGE
		chunk["far"].visible = not near
		chunk["detail"].visible = near


## Distancia en horizontal del punto al borde del trozo (0 si está dentro).
func _distance(chunk: Dictionary, pos: Vector3) -> float:
	var c: Vector3 = chunk["center"]
	var dx := maxf(0.0, absf(pos.x - c.x) - CHUNK / 2.0)
	var dz := maxf(0.0, absf(pos.z - c.z) - CHUNK / 2.0)
	return Vector2(dx, dz).length()


func _load(key: Vector2i) -> void:
	var chunk: Dictionary = _chunks[key]
	var center: Vector3 = chunk["center"]
	var built := _chunk_mesh(center, STEP)
	var detail := Node3D.new()
	detail.position = center
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = built[0]
	mesh_instance.material_override = material
	detail.add_child(mesh_instance)
	add_child(detail)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(built[1])
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
	chunk["detail"] = detail
	chunk["shape"] = collision
	# La misma semilla para cada trozo: al volver, todo está en el mismo sitio.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var start := absf(center.x) < START_AREA / 2.0 + CHUNK / 2.0 and absf(center.z) < START_AREA / 2.0 + CHUNK / 2.0
	chunk["trees"] = _plant_trees(detail, center, rng)
	if not start:
		_place_boulders(detail, center, rng)
		_place_resources(chunk, detail, center, rng)


func _unload(key: Vector2i) -> void:
	var chunk: Dictionary = _chunks[key]
	for node in chunk["ice"]:
		world.remove_ice(node)
	chunk["ice"] = []
	chunk["detail"].queue_free()
	chunk["shape"].queue_free()
	chunk["detail"] = null
	chunk["shape"] = null
	chunk["trees"] = null


## Malla de un trozo con vértices cada "step" metros, en coordenadas
## relativas a su centro. Devuelve [malla, triángulos para la colisión].
func _chunk_mesh(center: Vector3, step: float) -> Array:
	var cells := int(CHUNK / step)
	var x0 := center.x - CHUNK / 2.0
	var z0 := center.z - CHUNK / 2.0
	var heights := PackedFloat32Array()
	heights.resize((cells + 1) * (cells + 1))
	for i in cells + 1:
		for j in cells + 1:
			heights[i * (cells + 1) + j] = height_at(x0 + i * step, z0 + j * step)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var count := cells * cells * 6
	# Sitio para los triángulos y el faldón de una vez: es más rápido que ir añadiendo.
	verts.resize(count + cells * 24)
	normals.resize(verts.size())
	colors.resize(verts.size())
	var offset := Vector3(center.x, 0.0, center.z)
	var n := 0
	for i in cells:
		for j in cells:
			var lx := -CHUNK / 2.0 + i * step
			var lz := -CHUNK / 2.0 + j * step
			var a := Vector3(lx, heights[i * (cells + 1) + j], lz)
			var b := Vector3(lx + step, heights[(i + 1) * (cells + 1) + j], lz)
			var c := Vector3(lx, heights[i * (cells + 1) + j + 1], lz + step)
			var d := Vector3(lx + step, heights[(i + 1) * (cells + 1) + j + 1], lz + step)
			# Cada cuadro se parte en (a, b, c) y (b, d, c), como en surface_height.
			n = _triangle(verts, normals, colors, n, a, b, c, offset)
			n = _triangle(verts, normals, colors, n, b, d, c, offset)
	var faces := verts.slice(0, count)
	# Faldón: una tira vertical bajo cada borde que tapa el hueco con el trozo
	# vecino cuando este tiene otro nivel de detalle.
	for side in 4:
		for k in cells:
			var p: Vector3
			var q: Vector3
			var out: Vector3
			match side:
				0:
					p = Vector3(-CHUNK / 2.0, heights[k], -CHUNK / 2.0 + k * step)
					q = Vector3(-CHUNK / 2.0, heights[k + 1], -CHUNK / 2.0 + (k + 1) * step)
					out = Vector3.LEFT
				1:
					p = Vector3(CHUNK / 2.0, heights[cells * (cells + 1) + k], -CHUNK / 2.0 + k * step)
					q = Vector3(CHUNK / 2.0, heights[cells * (cells + 1) + k + 1], -CHUNK / 2.0 + (k + 1) * step)
					out = Vector3.RIGHT
				2:
					p = Vector3(-CHUNK / 2.0 + k * step, heights[k * (cells + 1)], -CHUNK / 2.0)
					q = Vector3(-CHUNK / 2.0 + (k + 1) * step, heights[(k + 1) * (cells + 1)], -CHUNK / 2.0)
					out = Vector3.FORWARD
				_:
					p = Vector3(-CHUNK / 2.0 + k * step, heights[k * (cells + 1) + cells], CHUNK / 2.0)
					q = Vector3(-CHUNK / 2.0 + (k + 1) * step, heights[(k + 1) * (cells + 1) + cells], CHUNK / 2.0)
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
func _triangle(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, n: int, a: Vector3, b: Vector3, c: Vector3, offset: Vector3) -> int:
	var normal := (c - a).cross(b - a).normalized()
	var color := _shade(a + offset, b + offset, c + offset, normal)
	verts[n] = a
	verts[n + 1] = b
	verts[n + 2] = c
	for k in 3:
		normals[n + k] = normal
		colors[n + k] = color
	return n + 3


## Color de un triángulo. Suelo (alfa 1): gris más oscuro en pendiente y en los
## valles, que se tiñe según la etapa. Roca y nieve (alfa 0): color propio.
func _shade(a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> Color:
	var mid := (a + b + c) / 3.0
	var flat := absf(normal.y)
	var jitter := _hash(mid.x, mid.z) * 0.1 - 0.05
	if mid.y > SNOW_HEIGHT and flat > 0.6:
		var s := 0.9 + jitter
		return Color(s, s + 0.02, s + 0.06, 0.0)
	if flat < ROCK_SLOPE or mid.y > ROCK_HEIGHT:
		var r := 0.22 + 0.12 * flat + jitter
		return Color(r, r * 0.97, r * 1.02, 0.0)
	var height := clampf((mid.y + HEIGHT) / (2.0 * HEIGHT), 0.0, 1.0)
	var v := 0.7 + 0.2 * flat + 0.15 * height + jitter
	return Color(v, v, v, 1.0)


## Número entre 0 y 1 que depende solo del punto.
func _hash(x: float, z: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)


## Normal del terreno en un punto (para saber si hay mucha pendiente).
func _slope(x: float, z: float) -> float:
	var dx := height_at(x + 1.0, z) - height_at(x - 1.0, z)
	var dz := height_at(x, z + 1.0) - height_at(x, z - 1.0)
	return Vector3(-dx, 2.0, -dz).normalized().y


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
		var kind := rng.randi() % _tree_meshes.size()
		var size := rng.randf_range(0.8, 1.8)
		var turn := rng.randf_range(0.0, TAU)
		var shade := Color.from_hsv(rng.randf_range(0.22, 0.36), rng.randf_range(0.0, 0.25), rng.randf_range(0.85, 1.1))
		if rng.randf() > chance:
			continue
		var y: float = world.surface_height(x, z)
		if y < DRY_LEVEL or y > TREE_LINE or _slope(x, z) < 0.85:
			continue
		var xform := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * size), Vector3(x, y - 0.1, z) - center)
		lists[kind].append([xform, shade])
	var trees := Node3D.new()
	trees.visible = plants_visible
	for k in lists.size():
		if not lists[k].is_empty():
			trees.add_child(_multimesh(_tree_meshes[k], lists[k]))
	detail.add_child(trees)
	return trees


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
		var y: float = world.surface_height(x, z)
		var rocky := y > ROCK_HEIGHT or _slope(x, z) < ROCK_SLOPE
		if not rocky and rng.randf() > 0.3:
			continue
		var basis := Basis(Vector3.UP, turn).scaled(stretch * size)
		list.append([Transform3D(basis, Vector3(x, y - 0.3 * size, z) - center), Color(shade, shade, shade)])
		var sphere := SphereShape3D.new()
		sphere.radius = 0.75 * size * minf(stretch.x, stretch.z)
		var collision := CollisionShape3D.new()
		collision.shape = sphere
		collision.position = Vector3(x, y, z) - center
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
		if _slope(x, z) < 0.7:
			continue
		var type := ""
		if y > ROCK_HEIGHT:
			type = "hielo" if roll < 0.4 else ("hierro" if roll < 0.7 else "cobre")
		else:
			type = "silicio" if roll < 0.35 else ("hierro" if roll < 0.65 else ("cobre" if roll < 0.85 else "hielo"))
		var node: ResourceNode = world.make_resource(type)
		node.position = Vector3(x, y, z) - center
		node.rotation.y = turn
		detail.add_child(node)
		if type == "hielo":
			chunk["ice"].append(node)
			# Funde antes el más bajo; el de las cumbres no se funde nunca.
			var start := INF
			if y < ICE_SUMMIT:
				start = (1.0 - world.MELT_TIME) * clampf(inverse_lerp(-HEIGHT, ICE_SUMMIT, y), 0.0, 1.0)
			world.add_ice(node, start)


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
