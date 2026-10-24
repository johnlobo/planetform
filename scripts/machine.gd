extends StaticBody3D
## Construcción colocada por el jugador (panel, generador, calentador,
## taquilla, musgo, bomba de agua...).

var kind := "panel"
## Entrada de Game.machines que se guarda con la partida. En las taquillas
## lleva también "items": lo que hay guardado.
var data := {}
## Caja que ocupa en el suelo (ancho, alto, fondo), para comprobar dónde cabe.
var footprint := Vector3.ONE
var _spinner: Node3D
# La bomba de agua: cabezal que sube y baja, y segundos acumulados de bombeo.
var _piston: Node3D
var _pump_time := 0.0
# El musgo nace pequeño y crece hasta su tamaño en GROW_TIME segundos.
var _growth := 1.0
const GROW_TIME := 40.0


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
			for i in 6:
				for j in 2:
					_mesh(sprout, Vector3(-0.65 + i * 0.26, 0.62, -0.18 + j * 0.36), green)
	mesh_instance.material_override = material
	add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.size.y / 2.0
	add_child(collision)
	footprint = shape.size


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


func _detail(size: Vector3, pos: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh(box, pos, material)


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


func _process(delta: float) -> void:
	if _spinner:
		_spinner.rotate_z(delta * 2.0)
	if _growth < 1.0:
		_growth = minf(1.0, _growth + delta / GROW_TIME)
		scale = Vector3.ONE * lerpf(0.3, 1.0, _growth)
	if Game.MACHINES[kind].has("produces"):
		_pump(delta)


## La bomba saca una unidad cada PUMP_TIME segundos, más despacio si le
## falta energía, hasta llenarse.
func _pump(delta: float) -> void:
	var ratio := Game.energy_ratio()
	var full := stored_total() >= capacity()
	if _piston:
		_piston.position.y = 1.5 + (0.0 if full or ratio <= 0.0 else sin(Time.get_ticks_msec() * 0.006) * 0.12)
	if full or ratio <= 0.0 or data.is_empty():
		return
	_pump_time += delta * ratio
	if _pump_time >= Game.PUMP_TIME:
		_pump_time -= Game.PUMP_TIME
		var resource := String(Game.MACHINES[kind]["produces"])
		items()[resource] = int(items().get(resource, 0)) + 1


func get_hint() -> String:
	var recipe_name: String = Game.RECIPES[kind]["name"]
	if is_storage():
		var state := ""
		if Game.MACHINES[kind].has("produces") and Game.energy_ratio() <= 0.0:
			state = " · sin energía"
		return "%s · %d / %d%s · E o clic para abrir" % [recipe_name, stored_total(), capacity(), state]
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
