extends Node3D
## Mano con la herramienta en primera persona. Va pegada a la cámara y cambia
## de cabezal según el modo: taladro para recoger, emisor azul para construir
## y pinzas rojas para desmontar. Al usarla da un golpe hacia atrás y lanza
## un rayo corto hasta el punto al que se apunta.

const REST := Vector3(0.16, -0.12, -0.38) # posición en reposo, delante y a la derecha
const LOWERED := Vector3(0.16, -0.4, -0.34) # escondida mientras cambia de cabezal
const SWITCH_TIME := 0.12
const BEAM_TIME := 0.12
const BOB_SPEED := 9.0
const BOB_AMOUNT := 0.008
const SCALE := 0.65 # tamaño de la mano y la herramienta
const HEAD_SCALE := 1.5 # los cabezales, más grandes para que se distingan
const COLORS := {
	"recoger": Color(1.0, 0.7, 0.2),
	"construir": Color(0.3, 0.8, 1.0),
	"desmontar": Color(1.0, 0.25, 0.2),
}

var player: CharacterBody3D
var _heads := {}
var _screen_material := StandardMaterial3D.new()
var _glow_material := StandardMaterial3D.new()
var _light: OmniLight3D
var _tip: Node3D
var _drill: Node3D
var _hologram: Node3D
var _beam: MeshInstance3D
var _beam_material := StandardMaterial3D.new()
var _beam_timer := 0.0
var _spin := 0.0 # velocidad de giro del taladro, se frena sola
var _bob := 0.0
var _kick := 0.0 # retroceso al usarla, de 1 a 0
var _switch: Tween


func _ready() -> void:
	position = REST
	# Algo girada hacia el centro y con la punta levantada para que se vea el cabezal.
	rotation_degrees = Vector3(12.0, 14.0, 0.0)
	scale = Vector3.ONE * SCALE
	_build()
	_apply_mode(Game.tool_mode)
	Game.tool_changed.connect(_on_tool_changed)
	Game.tool_used.connect(use)


func _process(delta: float) -> void:
	var speed := 0.0
	if player:
		speed = Vector2(player.velocity.x, player.velocity.z).length()
		if not player.is_on_floor():
			speed = 0.0
	_bob += delta * BOB_SPEED * clampf(speed / 6.0, 0.0, 1.0)
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	if _switch == null or not _switch.is_running():
		var sway := Vector3(cos(_bob * 0.5) * BOB_AMOUNT, absf(sin(_bob)) * BOB_AMOUNT, 0.0)
		position = REST + sway + Vector3(0, 0, _kick * 0.05)
	_spin = move_toward(_spin, 4.0, delta * 30.0)
	_drill.rotate_z(_spin * delta)
	_hologram.rotate_y(delta * 1.5)
	_hologram.position.y = 0.02 + sin(Time.get_ticks_msec() * 0.003) * 0.006
	if _beam_timer > 0.0:
		_beam_timer -= delta
		_beam.visible = _beam_timer > 0.0
		_beam_material.albedo_color.a = clampf(_beam_timer / BEAM_TIME, 0.0, 1.0)


## Golpe de retroceso y rayo hasta point (en coordenadas globales).
func use(point: Vector3) -> void:
	_kick = 1.0
	if Game.tool_mode == "recoger":
		_spin = 40.0
	var from := _tip.global_position
	var length := from.distance_to(point)
	if length < 0.05:
		return
	var mesh := _beam.mesh as CylinderMesh
	mesh.height = length
	_beam.global_transform = Transform3D(Basis.looking_at(point - from), (from + point) / 2.0) \
			* Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
	_beam_timer = BEAM_TIME
	_beam.visible = true


func _on_tool_changed(mode: String) -> void:
	if _switch:
		_switch.kill()
	# Baja la mano, cambia el cabezal y la vuelve a subir.
	_switch = create_tween()
	_switch.tween_property(self, "position", LOWERED, SWITCH_TIME)
	_switch.tween_callback(_apply_mode.bind(mode))
	_switch.tween_property(self, "position", REST, SWITCH_TIME)


func _apply_mode(mode: String) -> void:
	for id in _heads:
		_heads[id].visible = id == mode
	var color: Color = COLORS[mode]
	_screen_material.albedo_color = color
	_screen_material.emission = color
	_glow_material.albedo_color = Color(color, 0.6)
	_glow_material.emission = color
	_beam_material.albedo_color = Color(color, 1.0)
	_light.light_color = color


func _build() -> void:
	var casing := _material(Color(0.36, 0.39, 0.44))
	var cover := _material(Color(0.95, 0.55, 0.15))
	var metal := _material(Color(0.7, 0.72, 0.75), 0.7)
	var glove := _material(Color(0.2, 0.22, 0.26))
	var suit := _material(Color(0.88, 0.88, 0.85))
	for m in [_screen_material, _glow_material, _beam_material]:
		m.emission_enabled = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Cuerpo de la herramienta, apuntando hacia -Z.
	_part(self, _box(Vector3(0.06, 0.07, 0.22)), Vector3.ZERO, casing)
	_part(self, _box(Vector3(0.066, 0.02, 0.15)), Vector3(0, 0.04, 0.02), cover)
	_part(self, _box(Vector3(0.04, 0.004, 0.05)), Vector3(0, 0.051, 0.05), _screen_material)
	_part(self, _box(Vector3(0.07, 0.05, 0.02)), Vector3(0, 0, -0.1), metal)
	var grip := _part(self, _box(Vector3(0.042, 0.12, 0.05)), Vector3(0, -0.085, 0.065), casing)
	grip.rotation_degrees.x = 18.0

	# Puño cerrado alrededor de la empuñadura y antebrazo del traje.
	_part(self, _box(Vector3(0.075, 0.075, 0.07)), Vector3(0.005, -0.09, 0.07), glove)
	_part(self, _box(Vector3(0.02, 0.025, 0.06)), Vector3(-0.034, -0.055, 0.04), glove) # pulgar
	_part(self, _box(Vector3(0.08, 0.04, 0.03)), Vector3(0.005, -0.075, 0.025), glove) # dedos
	var arm := Node3D.new()
	arm.position = Vector3(0.02, -0.14, 0.11)
	arm.rotation_degrees = Vector3(-60.0, 0.0, 20.0)
	add_child(arm)
	_part(arm, _cylinder(0.045, 0.05, 0.04), Vector3(0, 0.0, 0), cover) # puño del traje
	_part(arm, _cylinder(0.05, 0.065, 0.35), Vector3(0, -0.19, 0), suit)

	_tip = Node3D.new()
	_tip.position = Vector3(0, 0, -0.26)
	add_child(_tip)
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.02, -0.18)
	_light.omni_range = 0.6
	_light.light_energy = 0.6
	add_child(_light)

	# Recoger: taladro que gira.
	var drill_head := _head("recoger")
	_part(drill_head, _cylinder(0.028, 0.028, 0.04, Vector3.FORWARD), Vector3(0, 0, -0.13), metal)
	_drill = Node3D.new()
	_drill.position = Vector3(0, 0, -0.15)
	drill_head.add_child(_drill)
	_part(_drill, _cylinder(0.0, 0.022, 0.08, Vector3.FORWARD, 5), Vector3(0, 0, -0.04), cover)

	# Construir: anillo emisor con un cubo holográfico delante.
	var builder := _head("construir")
	var ring := TorusMesh.new()
	ring.inner_radius = 0.022
	ring.outer_radius = 0.034
	ring.rings = 8
	ring.ring_segments = 6
	var ring_part := _part(builder, ring, Vector3(0, 0, -0.12), _glow_material)
	ring_part.rotation_degrees.x = 90.0
	var holder := Node3D.new()
	holder.position = Vector3(0, 0, -0.17)
	builder.add_child(holder)
	_hologram = _part(holder, _box(Vector3(0.03, 0.03, 0.03)), Vector3(0, 0.02, 0), _glow_material)
	_hologram.rotation_degrees = Vector3(35.0, 45.0, 0.0)

	# Desmontar: dos pinzas con un cristal rojo entre ellas.
	var cutter := _head("desmontar")
	for sx in [-1.0, 1.0]:
		var prong := _part(cutter, _box(Vector3(0.012, 0.016, 0.08)), Vector3(sx * 0.022, 0, -0.14), metal)
		prong.rotation_degrees.y = sx * 12.0
	_part(cutter, _box(Vector3(0.016, 0.016, 0.03)), Vector3(0, 0, -0.125), _glow_material)

	_beam = MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.004
	beam_mesh.bottom_radius = 0.004
	beam_mesh.radial_segments = 4
	beam_mesh.rings = 1
	_beam.mesh = beam_mesh
	_beam.material_override = _beam_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)


func _head(mode: String) -> Node3D:
	var head := Node3D.new()
	# Se agranda desde la boca de la herramienta (z = -0.11), que no se mueve.
	head.scale = Vector3.ONE * HEAD_SCALE
	head.position.z = 0.11 * (HEAD_SCALE - 1.0)
	add_child(head)
	_heads[mode] = head
	return head


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	part.material_override = material
	# La mano no debe ensombrecer el mundo que se ve detrás.
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


## Cilindro de pocas caras. Con axis = FORWARD se tumba a lo largo de -Z.
func _cylinder(top: float, bottom: float, height: float, axis := Vector3.UP, segments := 6) -> Mesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	cylinder.radial_segments = segments
	cylinder.rings = 1
	if axis == Vector3.UP:
		return cylinder
	# La punta (top) queda hacia -Z.
	var st := SurfaceTool.new()
	st.append_from(cylinder, 0, Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3.ZERO))
	return st.commit()


func _material(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.6
	return material
