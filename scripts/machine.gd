extends StaticBody3D
## Construcción colocada por el jugador (panel, generador, calentador,
## taquilla, musgo, bomba de agua, pantallas...).

var kind := "panel"
## Entrada de Game.machines que se guarda con la partida. En las taquillas
## lleva también "items": lo que hay guardado.
var data := {}
## Caja que ocupa en el suelo (ancho, alto, fondo), para comprobar dónde cabe.
var footprint := Vector3.ONE
var _spinner: Node3D
# Pieza que gira sobre el eje vertical (broca de la perforadora, ventilador
# del compresor).
var _rotor: Node3D
# La bomba de agua: cabezal que sube y baja.
var _piston: Node3D
# Segundos acumulados de producción (agua de la bomba, verduras del bancal).
var _produce_time := 0.0
# Frutos del bancal: se ve uno por cada verdura lista para recoger.
var _fruits: Array[Node3D] = []
# El musgo nace pequeño y crece hasta su tamaño en GROW_TIME segundos.
var _growth := 1.0
const GROW_TIME := 40.0
# Pantallas: barras que se rellenan, [{"metric", "fill", "left", "width"}]
# (con "value", el texto con la cifra), y textos que cambian.
var _bars: Array = []
var _screen_title: Label3D
var _screen_value: Label3D
var _screen_rate: Label3D
var _screen_time := 0.0
const SCREEN_REFRESH := 0.25 # segundos entre actualizaciones de la pantalla
const METRIC_COLORS := {
	"index": Color(1.0, 0.85, 0.4),
	"oxygen": Color(0.4, 0.85, 1.0),
	"temperature": Color(1.0, 0.55, 0.2),
	"pressure": Color(0.75, 0.6, 1.0),
	"biomass": Color(0.45, 0.9, 0.35),
}


func setup(machine_kind: String) -> void:
	kind = machine_kind
	var mesh_instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	var shape := BoxShape3D.new()
	match kind:
		"panel":
			var box := BoxMesh.new()
			box.size = Vector3(2.0, 0.1, 1.4)
			mesh_instance.mesh = box
			mesh_instance.position.y = 0.8
			mesh_instance.rotation_degrees.x = -25.0
			material.albedo_color = Color(0.15, 0.25, 0.6)
			shape.size = Vector3(2.0, 1.2, 1.4)
		"generador":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.5
			cylinder.bottom_radius = 0.7
			cylinder.height = 2.0
			cylinder.radial_segments = 6
			mesh_instance.mesh = cylinder
			mesh_instance.position.y = 1.0
			material.albedo_color = Color(0.85, 0.9, 0.85)
			shape.size = Vector3(1.4, 2.0, 1.4)
		"calentador":
			var heater := BoxMesh.new()
			heater.size = Vector3(1.2, 1.6, 1.2)
			mesh_instance.mesh = heater
			mesh_instance.position.y = 0.8
			material.albedo_color = Color(0.9, 0.45, 0.15)
			material.emission_enabled = true
			material.emission = Color(0.6, 0.2, 0.05)
			shape.size = Vector3(1.2, 1.6, 1.2)
		"turbina":
			var mast := CylinderMesh.new()
			mast.top_radius = 0.12
			mast.bottom_radius = 0.25
			mast.height = 4.0
			mast.radial_segments = 6
			mesh_instance.mesh = mast
			mesh_instance.position.y = 2.0
			material.albedo_color = Color(0.9, 0.9, 0.9)
			shape.size = Vector3(0.8, 4.0, 0.8)
			var blades := MeshInstance3D.new()
			var blade_mesh := BoxMesh.new()
			blade_mesh.size = Vector3(3.0, 0.25, 0.08)
			blades.mesh = blade_mesh
			blades.position = Vector3(0, 4.0, 0.3)
			blades.material_override = material
			add_child(blades)
			_spinner = blades
		"generador_avanzado":
			var big := CylinderMesh.new()
			big.top_radius = 0.7
			big.bottom_radius = 1.0
			big.height = 3.0
			big.radial_segments = 6
			mesh_instance.mesh = big
			mesh_instance.position.y = 1.5
			material.albedo_color = Color(0.3, 0.75, 0.65)
			shape.size = Vector3(2.0, 3.0, 2.0)
		"calentador_avanzado":
			var furnace := BoxMesh.new()
			furnace.size = Vector3(2.0, 2.4, 2.0)
			mesh_instance.mesh = furnace
			mesh_instance.position.y = 1.2
			material.albedo_color = Color(0.85, 0.3, 0.1)
			material.emission_enabled = true
			material.emission = Color(0.8, 0.25, 0.05)
			shape.size = Vector3(2.0, 2.4, 2.0)
		"perforadora":
			# Torre de perforación con la broca girando y un respiradero de gas.
			var base := BoxMesh.new()
			base.size = Vector3(1.6, 0.3, 1.6)
			mesh_instance.mesh = base
			mesh_instance.position.y = 0.15
			material.albedo_color = Color(0.45, 0.47, 0.5)
			shape.size = Vector3(1.6, 3.0, 1.6)
			var frame := StandardMaterial3D.new()
			frame.albedo_color = Color(0.95, 0.7, 0.15)
			for corner in [Vector3(-0.6, 0, -0.6), Vector3(0.6, 0, -0.6), Vector3(-0.6, 0, 0.6), Vector3(0.6, 0, 0.6)]:
				var leg := BoxMesh.new()
				leg.size = Vector3(0.1, 2.7, 0.1)
				var part := _mesh(leg, Vector3(corner.x * 0.67, 1.6, corner.z * 0.67), frame)
				# Patas inclinadas hacia el centro: torre en forma de pirámide.
				part.rotation = Vector3(-corner.z * 0.25, 0, corner.x * 0.25)
			_detail(Vector3(0.5, 0.15, 0.5), Vector3(0, 2.95, 0), frame)
			_rotor = Node3D.new()
			_rotor.position.y = 0.3
			add_child(_rotor)
			var bit := CylinderMesh.new()
			bit.top_radius = 0.12
			bit.bottom_radius = 0.03
			bit.height = 2.4
			bit.radial_segments = 5
			var steel := StandardMaterial3D.new()
			steel.albedo_color = Color(0.7, 0.72, 0.75)
			steel.metallic = 0.6
			_mesh(bit, Vector3(0, 1.1, 0), steel, _rotor)
			var arm := BoxMesh.new()
			arm.size = Vector3(0.5, 0.06, 0.06)
			_mesh(arm, Vector3(0, 2.2, 0), frame, _rotor)
			var gas := StandardMaterial3D.new()
			gas.albedo_color = Color(0.75, 0.6, 1.0)
			gas.emission_enabled = true
			gas.emission = Color(0.45, 0.3, 0.8)
			var vent := CylinderMesh.new()
			vent.top_radius = 0.12
			vent.bottom_radius = 0.16
			vent.height = 0.8
			vent.radial_segments = 6
			_mesh(vent, Vector3(0.6, 0.7, 0.6), material)
			var glow := CylinderMesh.new()
			glow.top_radius = 0.1
			glow.bottom_radius = 0.1
			glow.height = 0.05
			glow.radial_segments = 6
			_mesh(glow, Vector3(0.6, 1.11, 0.6), gas)
		"compresor":
			# Dos tanques tumbados y un ventilador grande encima.
			var plinth := BoxMesh.new()
			plinth.size = Vector3(2.2, 0.4, 1.8)
			mesh_instance.mesh = plinth
			mesh_instance.position.y = 0.2
			material.albedo_color = Color(0.4, 0.42, 0.48)
			shape.size = Vector3(2.2, 2.4, 1.8)
			var tank_material := StandardMaterial3D.new()
			tank_material.albedo_color = Color(0.6, 0.5, 0.85)
			tank_material.metallic = 0.4
			tank_material.roughness = 0.45
			for sz in [-0.45, 0.45]:
				var tank := CapsuleMesh.new()
				tank.radius = 0.38
				tank.height = 2.0
				tank.radial_segments = 8
				tank.rings = 2
				var part := _mesh(tank, Vector3(0, 0.8, sz), tank_material)
				part.rotation_degrees.z = 90.0
			var housing := CylinderMesh.new()
			housing.top_radius = 0.65
			housing.bottom_radius = 0.65
			housing.height = 0.5
			housing.radial_segments = 8
			_mesh(housing, Vector3(0, 1.6, 0), material)
			_rotor = Node3D.new()
			_rotor.position.y = 1.9
			add_child(_rotor)
			var light_metal := StandardMaterial3D.new()
			light_metal.albedo_color = Color(0.85, 0.87, 0.9)
			for i in 3:
				var blade := BoxMesh.new()
				blade.size = Vector3(1.1, 0.04, 0.22)
				var part := _mesh(blade, Vector3.ZERO, light_metal, _rotor)
				part.rotation_degrees = Vector3(12.0, i * 60.0, 0)
			var gas := StandardMaterial3D.new()
			gas.albedo_color = Color(0.75, 0.6, 1.0)
			gas.emission_enabled = true
			gas.emission = Color(0.45, 0.3, 0.8)
			_detail(Vector3(0.5, 0.12, 0.04), Vector3(0, 0.25, -0.91), gas)
		"pantalla":
			mesh_instance.mesh = _build_screen(Vector2(1.8, 1.2), 1.7, material)
			mesh_instance.position.y = mesh_instance.mesh.size.y / 2.0
			shape.size = Vector3(1.9, 2.4, 0.4)
			_screen_title = _screen_label("", Vector2(0, 0.48), 34, HORIZONTAL_ALIGNMENT_CENTER)
			_screen_value = _screen_label("", Vector2(-0.82, 0.3), 30, HORIZONTAL_ALIGNMENT_LEFT)
			_add_bar("index", Vector2(-0.82, 0.16), 1.64, 0.1)
			for i in Game.METRICS.size():
				var metric: String = Game.METRICS[i]
				var y := -0.03 - i * 0.15
				_screen_label(Game.METRIC_NAMES[metric], Vector2(-0.82, y), 24, HORIZONTAL_ALIGNMENT_LEFT, METRIC_COLORS[metric])
				_add_bar(metric, Vector2(-0.3, y), 0.82, 0.07)
				_bars[-1]["value"] = _screen_label("", Vector2(0.82, y), 24, HORIZONTAL_ALIGNMENT_RIGHT, METRIC_COLORS[metric])
		"monitor_oxigeno", "monitor_calor", "monitor_presion", "monitor_biomasa":
			mesh_instance.mesh = _build_screen(Vector2(1.0, 0.75), 1.45, material)
			mesh_instance.position.y = mesh_instance.mesh.size.y / 2.0
			shape.size = Vector3(1.1, 1.9, 0.4)
			var metric := String(Game.MACHINES[kind]["display"])
			var color: Color = METRIC_COLORS[metric]
			_screen_title = _screen_label(String(Game.METRIC_NAMES[metric]).to_upper(), Vector2(0, 0.26), 30, HORIZONTAL_ALIGNMENT_CENTER, color)
			_screen_value = _screen_label("", Vector2(0, 0.07), 64, HORIZONTAL_ALIGNMENT_CENTER, color)
			_add_bar(metric, Vector2(-0.4, -0.13), 0.8, 0.08)
			_screen_rate = _screen_label("", Vector2(0, -0.27), 22, HORIZONTAL_ALIGNMENT_CENTER)
		"taquilla":
			var cabinet := BoxMesh.new()
			cabinet.size = Vector3(0.8, 1.9, 0.6)
			mesh_instance.mesh = cabinet
			mesh_instance.position.y = 0.95
			material.albedo_color = Color(0.55, 0.6, 0.66)
			material.metallic = 0.4
			material.roughness = 0.5
			shape.size = Vector3(0.8, 1.9, 0.6)
			_add_locker_details()
		"musgo":
			mesh_instance.mesh = _moss_mesh()
			material.albedo_color = Color(0.3, 0.55, 0.22)
			material.vertex_color_use_as_albedo = true
			material.roughness = 1.0
			shape.size = Vector3(1.4, 0.3, 1.4)
			# En otra capa para que el jugador lo pise sin tropezar; el rayo de
			# la herramienta sí lo ve.
			collision_layer = 2
		"bomba":
			# Base de hormigón, cilindro con el agua y cabezal que bombea.
			var base := BoxMesh.new()
			base.size = Vector3(1.4, 0.3, 1.4)
			mesh_instance.mesh = base
			mesh_instance.position.y = 0.15
			material.albedo_color = Color(0.5, 0.52, 0.55)
			shape.size = Vector3(1.4, 2.2, 1.4)
			var metal := StandardMaterial3D.new()
			metal.albedo_color = Color(0.85, 0.55, 0.2)
			metal.metallic = 0.5
			var tank := CylinderMesh.new()
			tank.top_radius = 0.45
			tank.bottom_radius = 0.45
			tank.height = 1.2
			tank.radial_segments = 8
			_mesh(tank, Vector3(0, 0.9, 0), metal)
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.25, 0.55, 0.9, 0.7)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.emission_enabled = true
			glass.emission = Color(0.05, 0.2, 0.4)
			var window := BoxMesh.new()
			window.size = Vector3(0.3, 0.8, 0.1)
			_mesh(window, Vector3(0, 0.9, -0.43), glass)
			_piston = Node3D.new()
			_piston.position.y = 1.5
			add_child(_piston)
			var rod := CylinderMesh.new()
			rod.top_radius = 0.08
			rod.bottom_radius = 0.08
			rod.height = 0.6
			rod.radial_segments = 6
			_mesh(rod, Vector3(0, 0.3, 0), material, _piston)
			var cap := BoxMesh.new()
			cap.size = Vector3(0.6, 0.12, 0.25)
			_mesh(cap, Vector3(0, 0.62, 0), metal, _piston)
		"cultivo":
			# Jardinera de madera con tierra y brotes verdes.
			var planter := BoxMesh.new()
			planter.size = Vector3(1.8, 0.45, 0.9)
			mesh_instance.mesh = planter
			mesh_instance.position.y = 0.225
			material.albedo_color = Color(0.5, 0.35, 0.2)
			shape.size = Vector3(1.8, 0.8, 0.9)
			var soil := StandardMaterial3D.new()
			soil.albedo_color = Color(0.22, 0.15, 0.1)
			var dirt := BoxMesh.new()
			dirt.size = Vector3(1.65, 0.05, 0.75)
			_mesh(dirt, Vector3(0, 0.46, 0), soil)
			var light := StandardMaterial3D.new()
			light.albedo_color = Color(0.85, 0.5, 1.0)
			light.emission_enabled = true
			light.emission = Color(0.7, 0.3, 0.9)
			var lamp := BoxMesh.new()
			lamp.size = Vector3(1.6, 0.06, 0.2)
			_mesh(lamp, Vector3(0, 1.3, 0), light)
			for sx in [-0.85, 0.85]:
				var post := BoxMesh.new()
				post.size = Vector3(0.06, 0.9, 0.06)
				_mesh(post, Vector3(sx, 0.85, 0), material)
			var sprout := CylinderMesh.new()
			sprout.top_radius = 0.0
			sprout.bottom_radius = 0.09
			sprout.height = 0.3
			sprout.radial_segments = 4
			var green := StandardMaterial3D.new()
			green.albedo_color = Color(0.3, 0.7, 0.25)
			var fruit := SphereMesh.new()
			fruit.radius = 0.08
			fruit.height = 0.15
			fruit.radial_segments = 6
			fruit.rings = 3
			var red := StandardMaterial3D.new()
			red.albedo_color = Color(0.9, 0.25, 0.12)
			red.roughness = 0.6
			for i in 6:
				for j in 2:
					var spot := Vector3(-0.65 + i * 0.26, 0.62, -0.18 + j * 0.36)
					_mesh(sprout, spot, green)
					var ripe := _mesh(fruit, spot + Vector3(0, 0.14, 0), red)
					ripe.visible = false
					_fruits.append(ripe)
	mesh_instance.material_override = material
	add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.size.y / 2.0
	add_child(collision)
	footprint = shape.size
	if Game.MACHINES[kind].has("display"):
		update_screen()


## Puertas, rendijas, tiradores y una franja naranja en el frente (-Z).
func _add_locker_details() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.3, 0.33, 0.37)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.95, 0.55, 0.15)
	var front := -0.3
	# Ranura entre las dos puertas.
	_detail(Vector3(0.02, 1.8, 0.02), Vector3(0, 0.95, front), dark)
	for sx in [-1.0, 1.0]:
		# Tirador junto a la ranura.
		_detail(Vector3(0.03, 0.22, 0.04), Vector3(sx * 0.06, 1.0, front - 0.01), accent)
		# Rendijas de ventilación arriba de cada puerta.
		for k in 3:
			_detail(Vector3(0.24, 0.025, 0.02), Vector3(sx * 0.2, 1.65 - k * 0.07, front), dark)
	_detail(Vector3(0.82, 0.08, 0.62), Vector3(0, 0.12, 0), accent)


func _detail(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	return _mesh(box, pos, material)


# Altura del centro de la pantalla que se está construyendo, para colocar
# textos y barras relativos a él.
var _screen_center := 0.0


## Marco, cristal oscuro y peana de una pantalla de tamaño "size" con el
## centro a la altura "center". La cara que se mira es la delantera (-Z).
## Devuelve el poste, que es la malla principal con el material dado.
func _build_screen(size: Vector2, center: float, material: StandardMaterial3D) -> BoxMesh:
	_screen_center = center
	material.albedo_color = Color(0.35, 0.38, 0.42)
	material.metallic = 0.3
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.22, 0.24, 0.27)
	_detail(Vector3(size.x + 0.1, size.y + 0.1, 0.12), Vector3(0, center, 0), frame)
	var foot := StandardMaterial3D.new()
	foot.albedo_color = Color(0.3, 0.32, 0.36)
	_detail(Vector3(0.6, 0.06, 0.4), Vector3(0, 0.03, 0), foot)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.03, 0.06, 0.09)
	glass.emission_enabled = true
	glass.emission = Color(0.02, 0.05, 0.08)
	glass.roughness = 0.2
	_detail(Vector3(size.x, size.y, 0.01), Vector3(0, center, -0.065), glass)
	var post := BoxMesh.new()
	post.size = Vector3(0.12, center - size.y / 2.0, 0.12)
	return post


## Texto en la cara de la pantalla. "pos" va relativa al centro de la pantalla.
func _screen_label(text: String, pos: Vector2, size: int, align: HorizontalAlignment,
		color := Color(0.85, 0.92, 1.0)) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.0025
	label.outline_size = 0
	label.modulate = color
	label.horizontal_alignment = align
	label.double_sided = false
	# Label3D mira hacia +Z; se gira para que se lea desde delante (-Z).
	label.rotation_degrees.y = 180.0
	# "pos" es como se ve de frente: con el giro, su x va al revés en el modelo.
	label.position = Vector3(-pos.x, _screen_center + pos.y, -0.075)
	add_child(label)
	return label


## Barra horizontal que empieza en "pos" (borde izquierdo, visto de frente).
func _add_bar(metric: String, pos: Vector2, width: float, height: float) -> void:
	var back := StandardMaterial3D.new()
	back.albedo_color = Color(0.12, 0.15, 0.2)
	back.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Vista de frente la x crece hacia la izquierda del modelo: se invierte.
	var left := -pos.x
	_detail(Vector3(width, height, 0.01), Vector3(left - width / 2.0, _screen_center + pos.y, -0.072), back)
	var color: Color = METRIC_COLORS[metric]
	var bright := StandardMaterial3D.new()
	bright.albedo_color = color
	bright.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var fill := _detail(Vector3(width, height, 0.01), Vector3(left, _screen_center + pos.y, -0.078), bright)
	_bars.append({"metric": metric, "fill": fill, "left": left, "width": width})


## Pone al día textos y barras. "sample" (0 a 1) rellena todo a ese valor,
## para los iconos del menú.
func update_screen(sample := -1.0) -> void:
	for bar in _bars:
		var metric := String(bar["metric"])
		var value := sample * 100.0 if sample >= 0.0 else _metric_value(metric)
		var part := clampf(value / 100.0, 0.0, 1.0)
		var fill: MeshInstance3D = bar["fill"]
		fill.visible = part > 0.0
		fill.scale.x = maxf(part, 0.001)
		fill.position.x = float(bar["left"]) - float(bar["width"]) * part / 2.0
		if bar.has("value"):
			bar["value"].text = "%d %%" % floori(value)
	var display := String(Game.MACHINES[kind]["display"])
	var value := sample * 100.0 if sample >= 0.0 else _metric_value(display)
	if display == "index":
		var stage: int = Game.stage
		_screen_title.text = "TERRAFORMACIÓN · %s" % Game.STAGES[stage]["name"]
		if stage + 1 < Game.STAGES.size():
			_screen_value.text = "Índice %.1f %%  ·  %s al %d %%" % [value, Game.STAGES[stage + 1]["name"], int(Game.STAGES[stage + 1]["threshold"])]
		else:
			_screen_value.text = "Índice %.1f %%  ·  planeta habitable" % value
	else:
		_screen_value.text = "%.1f %%" % value
		var rate := 1.5 if sample >= 0.0 else Game.metric_rate(display) * 60.0
		_screen_rate.text = "+%.1f %% por minuto" % rate if rate > 0.0 else "sin máquinas en marcha"


func _metric_value(metric: String) -> float:
	return Game.terraform_index() if metric == "index" else float(Game.get(metric))


func _mesh(mesh: Mesh, pos: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	part.material_override = material
	(parent if parent else self).add_child(part)
	return part


## Mancha de musgo: un disco bajo y abultado de caras planas con tonos de
## verde distintos.
static func _moss_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	const SIDES := 9
	var center := Vector3(0, 0.22, 0)
	var ring := []
	for i in SIDES:
		var angle := TAU * i / SIDES
		var radius := rng.randf_range(0.55, 0.75)
		ring.append(Vector3(cos(angle) * radius, rng.randf_range(0.06, 0.14), sin(angle) * radius))
	for i in SIDES:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % SIDES]
		var shade := rng.randf_range(0.75, 1.15)
		st.set_color(Color(shade, shade, shade))
		# Cara de arriba y borde hasta el suelo.
		for v in [center, a, b, a, Vector3(b.x, 0, b.z), b, a, Vector3(a.x, 0, a.z), Vector3(b.x, 0, b.z)]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## El musgo recién plantado empieza pequeño y crece.
func sprout() -> void:
	if kind == "musgo":
		_growth = 0.0
		scale = Vector3.ONE * 0.3


func is_storage() -> bool:
	return Game.MACHINES[kind].has("storage")


func capacity() -> int:
	return int(Game.MACHINES[kind].get("storage", 0))


## Lo guardado en la taquilla: {recurso: cantidad}.
func items() -> Dictionary:
	if not data.has("items"):
		data["items"] = {}
	return data["items"]


func stored_total() -> int:
	var total := 0
	for id in items():
		total += int(items()[id])
	return total


## Convierte la construcción en una silueta sin colisión que se dibuja con
## el material dado (verde o rojo en el modo de colocación).
func make_ghost(material: Material) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			remove_child(child)
			child.free()
		elif child is MeshInstance3D:
			child.material_override = material
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif child is Label3D:
			child.visible = false
	_bars.clear()


func _process(delta: float) -> void:
	if _spinner:
		_spinner.rotate_z(delta * 2.0)
	if _rotor and Game.energy_ratio() > 0.0:
		_rotor.rotate_y(delta * 4.0 * Game.energy_ratio())
	if _bars.size() > 0:
		_screen_time -= delta
		if _screen_time <= 0.0:
			_screen_time = SCREEN_REFRESH
			update_screen()
	if _growth < 1.0:
		_growth = minf(1.0, _growth + delta / GROW_TIME)
		scale = Vector3.ONE * lerpf(0.3, 1.0, _growth)
	if Game.MACHINES[kind].has("produces"):
		_produce(delta)


## La bomba y el bancal sacan una unidad cada "produce_time" segundos, más
## despacio si les falta energía, hasta llenarse.
func _produce(delta: float) -> void:
	var ratio := Game.energy_ratio()
	var total := stored_total()
	var full := total >= capacity()
	if _piston:
		_piston.position.y = 1.5 + (0.0 if full or ratio <= 0.0 else sin(Time.get_ticks_msec() * 0.006) * 0.12)
	for i in _fruits.size():
		_fruits[i].visible = i < total
	if full or ratio <= 0.0 or data.is_empty():
		return
	_produce_time += delta * ratio
	var period := float(Game.MACHINES[kind]["produce_time"])
	if _produce_time >= period:
		_produce_time -= period
		var resource := String(Game.MACHINES[kind]["produces"])
		items()[resource] = int(items().get(resource, 0)) + 1


func get_hint() -> String:
	var recipe_name: String = Game.RECIPES[kind]["name"]
	if is_storage():
		var state := ""
		if Game.MACHINES[kind].has("produces") and Game.energy_ratio() <= 0.0:
			state = " · sin energía"
		return "%s · %d / %d%s · E o clic para abrir" % [recipe_name, stored_total(), capacity(), state]
	var display := String(Game.MACHINES[kind].get("display", ""))
	if display == "index":
		return "%s · índice %.1f %%" % [recipe_name, Game.terraform_index()]
	if display != "":
		return "%s · %.1f %%" % [recipe_name, float(Game.get(display))]
	var energy := int(Game.MACHINES[kind]["energy"])
	if energy == 0:
		return "%s · creciendo" % recipe_name if _growth < 1.0 else recipe_name
	if energy > 0:
		if Game.MACHINES[kind].get("solar", false) and Game.is_night():
			return "%s · de noche no da energía" % recipe_name
		return "%s · da %d de energía" % [recipe_name, energy]
	if Game.energy_ratio() <= 0.0:
		return "%s · sin energía" % recipe_name
	return "%s · funcionando al %d %%" % [recipe_name, roundi(Game.energy_ratio() * 100.0)]
