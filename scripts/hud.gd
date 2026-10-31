extends CanvasLayer
## Interfaz: estado del planeta, barras del jugador, modo de la herramienta,
## el menú de fabricar y construir, el inventario y el panel de la taquilla.

const Icons := preload("res://scripts/icons.gd")
const Machine := preload("res://scripts/machine.gd")
const Terrain := preload("res://scripts/terrain.gd")

const MESSAGE_TIME := 4.0
const ICON_SIZE := 56
# Casilla del menú: pequeña para que quepan todas las secciones de una vez.
const CELL_SIZE := Vector2(ICON_SIZE + 50, ICON_SIZE + 66)
const MENU_COLUMNS := 11
const SECTION_NAMES := {"fabricar": "Fabricar", "construccion": "Construcción", "tecnologia": "Tecnología", "terraformacion": "Terraformación"}
# El menú de construir (herramienta de construcción) y el panel del fabricador
# comparten la rejilla; cada uno enseña sus secciones.
const BUILD_SECTIONS := ["construccion", "tecnologia", "terraformacion"]
const FAB_SECTIONS := ["fabricar"]
const EQUIP_SIZE := Vector2(310, 400)
const EQUIP_SLOT := 64.0
const INVENTORY_COLUMNS := 6
const SLOT_SIZE := Vector2(76, 76)
const MODE_COLORS := {
	"recoger": Color(1.0, 0.85, 0.55),
	"construir": Color(0.55, 0.88, 1.0),
	"desmontar": Color(1.0, 0.45, 0.4),
}
const DEATH_FADE_TIME := 3.0
const MAP_PIXELS := 200 # resolución del mapa por satélite
const MAP_SIZE := 520.0 # lado del mapa en pantalla
const SITE_MARKS := {"cueva": Color(1.0, 0.6, 0.15), "nave": Color(0.3, 0.95, 1.0), "crater": Color(1.0, 1.0, 1.0)}
const SITE_NAMES := {"cueva": "Cueva", "nave": "Resto de nave", "crater": "Cráter"}

var planet_label: Label
var oxygen_bar: ProgressBar
var warmth_bar: ProgressBar
var hunger_bar: ProgressBar
var wet_title: Label
var wet_bar: ProgressBar
var cold_label: Label
var jetpack_title: Label
var jetpack_bar: ProgressBar
var hint_label: Label
var message_label: Label
var menu_panel: PanelContainer
var menu_sections: VBoxContainer
var menu_scroll: ScrollContainer
# Título de cada sección del menú, para desplazarse hasta ella.
var _section_headers := {}
var menu_heading: Label
var menu_close_hint: Label
var fab_box: VBoxContainer
var fab_label: Label
var fab_bar: ProgressBar
var fab_icon: TextureRect
var _menu_mode := "build"
var _fab_time := 0.0
# true cuando ya se ha dado el primer aviso de la cápsula.
var _intro_shown := false
var inventory_panel: PanelContainer
var inventory_title: Label
var inventory_bar: ProgressBar
var inventory_grid: GridContainer
var inventory_detail: VBoxContainer
var equip_frame: Control
var equip_body: Control
# Posición de cada casilla del equipo en equip_frame, y a qué parte del
# astronauta apunta su línea.
var _equip_slots := []
# Objeto elegido en el inventario, el que pidió tirar todo (a la espera de
# confirmar) y si se ordena por nombre en vez de por tipo.
var _inv_selected := ""
var _inv_confirm := ""
var _inv_sort_by_name := false
var locker_panel: PanelContainer
var locker_title: Label
var locker_inventory: VBoxContainer
var locker_contents: VBoxContainer
var research_panel: PanelContainer
var research_list: VBoxContainer
var map_panel: PanelContainer
var map_marks: Control
var map_info: RichTextLabel
var _map_texture: ImageTexture
var crosshair: Label
var mine_bar: ProgressBar
var mode_labels := {}
var icons: Icons
# Panel abierto ahora (el menú o la taquilla), o null.
var _open_panel: Control
var _driving := false
# La taquilla, máquina o maletero abierto: una Machine o un róver.
var _locker: Node3D
var _locker_total := 0
var death_overlay: ColorRect
var death_label: Label
var message_timer := 0.0
# true cuando la pantalla de game over espera a que el jugador pulse Enter.
var _waiting_respawn := false


func _ready() -> void:
	# El HUD sigue activo con el juego en pausa para la pantalla de game over.
	process_mode = Node.PROCESS_MODE_ALWAYS
	planet_label = _label(Control.PRESET_TOP_RIGHT, Vector2(-16, 16))
	planet_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	planet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	crosshair = _label(Control.PRESET_CENTER, Vector2(-4, -12))
	crosshair.text = "+"

	# Barra de minar, justo debajo de la mira.
	mine_bar = ProgressBar.new()
	mine_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mine_bar.offset_left = -40
	mine_bar.offset_right = 40
	mine_bar.offset_top = 14
	mine_bar.offset_bottom = 22
	mine_bar.max_value = 1.0
	mine_bar.show_percentage = false
	mine_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = MODE_COLORS["recoger"]
	mine_bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.5)
	mine_bar.add_theme_stylebox_override("background", back)
	add_child(mine_bar)

	hint_label = _label(Control.PRESET_CENTER, Vector2(-160, 28))
	hint_label.custom_minimum_size.x = 320
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	message_label = _label(Control.PRESET_CENTER_TOP, Vector2(-240, 16))
	message_label.custom_minimum_size.x = 480
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Dos líneas, abajo a la izquierda, para no llegar a las barras de la derecha.
	var help := _label(Control.PRESET_BOTTOM_LEFT, Vector2.ZERO)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_left = 16
	help.offset_bottom = -16
	help.text = "WASD mover · Espacio saltar · Clic usar herramienta (mantén para minar) · 1 2 3 o rueda cambiar modo\nE usar (fabricador, almacén, cama…) o subir al róver · I inventario · L linterna · R girar · Esc cerrar o pausa"

	_build_mode_bar()

	# Barras abajo a la derecha; el contenedor crece hacia arriba y a la izquierda.
	var oxygen_box := VBoxContainer.new()
	oxygen_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	oxygen_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	oxygen_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	oxygen_box.offset_right = -16
	oxygen_box.offset_bottom = -16
	oxygen_box.custom_minimum_size = Vector2(300, 0)
	oxygen_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var oxygen_title := Label.new()
	oxygen_title.text = "Tu oxígeno"
	oxygen_box.add_child(oxygen_title)
	oxygen_bar = ProgressBar.new()
	oxygen_bar.custom_minimum_size = Vector2(300, 20)
	oxygen_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oxygen_box.add_child(oxygen_bar)
	var warmth_title := Label.new()
	warmth_title.text = "Tu calor"
	oxygen_box.add_child(warmth_title)
	warmth_bar = ProgressBar.new()
	warmth_bar.max_value = Game.WARMTH_MAX
	warmth_bar.custom_minimum_size = Vector2(300, 20)
	warmth_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oxygen_box.add_child(warmth_bar)
	var hunger_title := Label.new()
	hunger_title.text = "Tu comida"
	oxygen_box.add_child(hunger_title)
	hunger_bar = ProgressBar.new()
	hunger_bar.max_value = Game.HUNGER_MAX
	hunger_bar.custom_minimum_size = Vector2(300, 20)
	hunger_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oxygen_box.add_child(hunger_bar)
	wet_title = Label.new()
	wet_title.text = "Tu humedad"
	oxygen_box.add_child(wet_title)
	wet_bar = ProgressBar.new()
	wet_bar.max_value = Game.WET_MAX
	wet_bar.show_percentage = false
	wet_bar.custom_minimum_size = Vector2(300, 12)
	wet_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wet_fill := StyleBoxFlat.new()
	wet_fill.bg_color = Color(0.3, 0.6, 1.0)
	wet_bar.add_theme_stylebox_override("fill", wet_fill)
	oxygen_box.add_child(wet_bar)
	jetpack_title = Label.new()
	jetpack_title.text = "Propulsores"
	oxygen_box.add_child(jetpack_title)
	jetpack_bar = ProgressBar.new()
	jetpack_bar.max_value = Game.JETPACK_FUEL_MAX
	jetpack_bar.custom_minimum_size = Vector2(300, 20)
	jetpack_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oxygen_box.add_child(jetpack_bar)
	# Una línea de estado cuando aplica: cueva, mojado o secándose.
	cold_label = Label.new()
	cold_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	oxygen_box.add_child(cold_label)
	add_child(oxygen_box)

	_build_menu_panel()
	_build_inventory_panel()
	_build_locker_panel()
	_build_research_panel()
	_build_map_panel()
	_build_death_screen()
	icons = Icons.new()
	add_child(icons)
	icons.finished.connect(_on_icons_finished)
	icons.render(Game.RECIPES.keys() + Icons.EXTRA)

	Game.inventory_changed.connect(_on_inventory_changed)
	Game.message.connect(_show_message)
	Game.player_died.connect(_on_player_died)
	Game.tool_changed.connect(_on_tool_changed)
	Game.build_menu_requested.connect(_on_build_menu_requested)
	Game.fabricator_requested.connect(_on_fabricator_requested)
	Game.fabrication_changed.connect(_on_fabrication_changed)
	Game.driving_changed.connect(func(driving: bool) -> void: _driving = driving)
	Game.locker_requested.connect(_on_locker_requested)
	Game.research_requested.connect(_on_research_requested)
	_on_tool_changed(Game.tool_mode)
	if Game.pending_notice != "":
		_show_message(Game.pending_notice)
		Game.pending_notice = ""
	# Sin pantalla de título (tras "Nueva partida") el aviso sale ya; si no,
	# al cerrarse el menú.
	if Game.skip_title:
		_show_intro()


func _input(event: InputEvent) -> void:
	# Se usa _input y no _unhandled_input para cerrar los paneles aunque un
	# botón tenga el foco.
	if Game.dead:
		# Durante la muerte solo cuenta Enter, y solo cuando ya sale el game over.
		if _waiting_respawn and event.is_action_pressed("ui_accept"):
			_respawn()
		get_viewport().set_input_as_handled()
	elif _open_panel:
		var right_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
		var is_fabricator := _open_panel == menu_panel and _menu_mode == "fabricate"
		if event.is_action_pressed("pause") \
				or (event.is_action_pressed("map") and _open_panel == map_panel) \
				or (event.is_action_pressed("inventory") and _open_panel == inventory_panel) \
				or (event.is_action_pressed("interact") and (_open_panel in [locker_panel, research_panel] or is_fabricator)) or right_click:
			_close_panel()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") and not get_tree().paused and not Game.placing:
		_show_panel(inventory_panel)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and not get_tree().paused and not Game.placing:
		_on_map_requested()
		get_viewport().set_input_as_handled()


## Se llama al abrir el menú: cierra los paneles y oculta la interfaz.
func on_menu_opened() -> void:
	_close_panel()
	visible = false


func on_menu_closed() -> void:
	visible = true
	_show_intro()


## Primer aviso de la partida: el almacén de pared de la cápsula.
func _show_intro() -> void:
	if _intro_shown or Game.tutorial != 1:
		return
	_intro_shown = true
	_show_message("Has aterrizado. Abre el almacén de pared (E) para coger tus provisiones.")


func _process(delta: float) -> void:
	oxygen_bar.max_value = Game.player_o2_max()
	oxygen_bar.value = Game.player_oxygen
	warmth_bar.value = Game.warmth
	hunger_bar.value = Game.hunger
	wet_title.visible = Game.wetness > 0.0
	wet_bar.visible = wet_title.visible
	wet_bar.value = Game.wetness
	cold_label.text = Game.cold_status()
	cold_label.visible = cold_label.text != ""
	jetpack_title.visible = Game.has_jetpack
	jetpack_bar.visible = Game.has_jetpack
	jetpack_bar.value = Game.jetpack_fuel
	hint_label.text = "" if Game.ui_open else Game.hint
	mine_bar.visible = Game.mine_progress >= 0.0 and not Game.ui_open
	mine_bar.value = maxf(Game.mine_progress, 0.0)
	if _open_panel == menu_panel and _menu_mode == "fabricate":
		_update_fabrication_bar(delta)
	if _open_panel == locker_panel and not is_instance_valid(_locker):
		_close_panel()
	elif _open_panel == locker_panel and _locker.stored_total() != _locker_total:
		# La bomba y el bancal siguen produciendo con el panel abierto.
		_refresh_locker()
	planet_label.text = Game.clock_text() + ("  (noche)" if Game.is_night() else "") + ("  (lloviendo)" if Game.is_raining() else "") + "\nEtapa: %s\nOxígeno: %.1f %%\nTemperatura: %.1f %%\nPresión: %.1f %%\nBiomasa: %.1f %%\nÍndice: %.1f %%\nEnergía: %d producida / %d necesaria" % [
		Game.STAGES[Game.stage]["name"], Game.oxygen, Game.temperature, Game.pressure, Game.biomass,
		Game.terraform_index(), Game.energy_supply(), Game.energy_demand()]
	if Game.battery_capacity() > 0.0:
		planet_label.text += "\nBaterías: %d %%" % roundi(Game.battery_percent())
	# Planos a medias: solo los que ya tienen algún fragmento.
	for id in Game.fragments:
		if not id in Game.unlocked:
			planet_label.text += "\nPlano de %s: %d / %d" % [String(Game.RECIPES[id]["name"]).to_lower(), Game.fragments[id], Game.RECIPES[id]["unlock"]["fragments"]]
	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0 and not Game.finished:
			message_label.text = ""


func _label(preset: int, offset: Vector2) -> Label:
	var label := Label.new()
	# Ninguna etiqueta debe quedarse con los clics destinados al juego.
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(preset)
	label.position += offset
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label


## Un solo menú con dos pestañas: Fabricar (herramientas, botellas y comida,
## que van al inventario) y Construir (lo que se coloca en el mundo).
func _build_menu_panel() -> void:
	var parts := _panel("")
	menu_panel = parts[0]
	var title: Label = parts[2]
	title.visible = false
	var header := HBoxContainer.new()
	parts[1].add_child(header)
	parts[1].move_child(header, 0)
	menu_heading = Label.new()
	menu_heading.add_theme_font_size_override("font_size", 18)
	menu_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(menu_heading)
	menu_close_hint = Label.new()
	menu_close_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	header.add_child(menu_close_hint)
	menu_sections = VBoxContainer.new()
	menu_sections.add_theme_constant_override("separation", 6)
	# Si no cabe todo en la pantalla, se desplaza con la rueda.
	menu_scroll = ScrollContainer.new()
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.add_child(menu_sections)
	parts[1].add_child(menu_scroll)
	# Solo en el fabricador: qué se está haciendo y cuánto falta.
	fab_box = VBoxContainer.new()
	fab_box.add_theme_constant_override("separation", 6)
	fab_box.add_child(HSeparator.new())
	var fab_row := HBoxContainer.new()
	fab_row.add_theme_constant_override("separation", 14)
	fab_box.add_child(fab_row)
	var icon_slot := Control.new()
	icon_slot.custom_minimum_size = Vector2(76, 76)
	fab_row.add_child(icon_slot)
	fab_icon = TextureRect.new()
	fab_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fab_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fab_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fab_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_slot.add_child(fab_icon)
	var fab_text := VBoxContainer.new()
	fab_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fab_text.alignment = BoxContainer.ALIGNMENT_CENTER
	fab_row.add_child(fab_text)
	fab_label = Label.new()
	fab_label.add_theme_font_size_override("font_size", 16)
	fab_text.add_child(fab_label)
	fab_bar = ProgressBar.new()
	fab_bar.custom_minimum_size = Vector2(0, 18)
	fab_bar.max_value = 1.0
	fab_bar.show_percentage = false
	fab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fab_fill := StyleBoxFlat.new()
	fab_fill.bg_color = MODE_COLORS["construir"]
	fab_bar.add_theme_stylebox_override("fill", fab_fill)
	fab_text.add_child(fab_bar)
	fab_box.visible = false
	parts[1].add_child(fab_box)


## Los tres modos de la herramienta abajo en el centro; el activo resalta.
func _build_mode_bar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -64 # por encima de la ayuda de abajo a la izquierda
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 18)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in Game.TOOL_MODES.size():
		var mode: String = Game.TOOL_MODES[i]
		var label := Label.new()
		label.text = "%d %s" % [i + 1, Game.TOOL_NAMES[mode]]
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		bar.add_child(label)
		mode_labels[mode] = label
	add_child(bar)


func _on_tool_changed(mode: String) -> void:
	crosshair.add_theme_color_override("font_color", MODE_COLORS[mode])
	for id in mode_labels:
		var label: Label = mode_labels[id]
		# Solo salen los modos de las herramientas que se tienen.
		label.visible = Game.has_mode(id)
		var active: bool = id == mode
		label.add_theme_font_size_override("font_size", 22 if active else 16)
		label.add_theme_color_override("font_color", MODE_COLORS[id] if active else Color(0.75, 0.75, 0.75, 0.7))


## Panel centrado con título; devuelve el contenedor donde va su contenido.
func _panel(title_text: String) -> Array:
	var panel := PanelContainer.new()
	panel.visible = false
	# Fondo casi opaco para que no se lea el HUD de detrás.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.14, 0.95)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	add_child(center)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = title_text
	box.add_child(title)
	return [panel, box, title]


## Inventario: la rejilla de casillas de la mochila, la ficha del objeto
## elegido (usar y tirar) y el equipo que se lleva puesto.
func _build_inventory_panel() -> void:
	var parts := _panel("")
	inventory_panel = parts[0]
	inventory_title = parts[2]
	inventory_title.add_theme_font_size_override("font_size", 18)
	inventory_bar = ProgressBar.new()
	inventory_bar.custom_minimum_size = Vector2(0, 14)
	inventory_bar.show_percentage = false
	inventory_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parts[1].add_child(inventory_bar)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	parts[1].add_child(columns)
	inventory_grid = GridContainer.new()
	inventory_grid.columns = INVENTORY_COLUMNS
	inventory_grid.add_theme_constant_override("h_separation", 6)
	inventory_grid.add_theme_constant_override("v_separation", 6)
	columns.add_child(inventory_grid)
	inventory_detail = VBoxContainer.new()
	inventory_detail.custom_minimum_size.x = 260
	inventory_detail.add_theme_constant_override("separation", 8)
	columns.add_child(inventory_detail)
	# A la derecha, el equipo montado sobre la silueta de un astronauta.
	columns.add_child(VSeparator.new())
	var equip_column := VBoxContainer.new()
	equip_column.add_child(_small_heading("Equipo"))
	equip_frame = Control.new()
	equip_frame.custom_minimum_size = EQUIP_SIZE
	equip_body = Control.new()
	equip_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	equip_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equip_body.draw.connect(_draw_astronaut)
	equip_frame.add_child(equip_body)
	equip_column.add_child(equip_frame)
	columns.add_child(equip_column)


func _refresh_inventory_panel() -> void:
	var used := Game.slots_used()
	var total := Game.slots_max()
	var free := total - used
	inventory_title.text = "Mochila: %d / %d casillas · I, clic derecho o Esc para cerrar" % [used, total]
	inventory_bar.max_value = total
	inventory_bar.value = mini(used, total)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.9, 0.25, 0.2) if free <= 0 else (Color(1.0, 0.65, 0.2) if free == 1 else Color(0.55, 0.88, 1.0))
	inventory_bar.add_theme_stylebox_override("fill", fill)
	var ids := []
	for id in Game.inventory:
		if int(Game.inventory[id]) > 0:
			ids.append(id)
	if _inv_sort_by_name:
		ids.sort_custom(func(a: String, b: String) -> bool: return String(Game.RESOURCE_NAMES[a]) < String(Game.RESOURCE_NAMES[b]))
	if not _inv_selected in ids:
		_inv_selected = ids[0] if not ids.is_empty() else ""
	# Una casilla por cada SLOT_SIZE unidades de cada objeto.
	var slots := []
	for id in ids:
		var left := int(Game.inventory[id])
		while left > 0:
			slots.append([id, mini(left, Game.SLOT_SIZE)])
			left -= Game.SLOT_SIZE
	for child in inventory_grid.get_children():
		inventory_grid.remove_child(child)
		child.queue_free()
	for i in maxi(total, slots.size()):
		inventory_grid.add_child(_inventory_slot(slots[i] if i < slots.size() else []))
	_refresh_inventory_detail()
	_refresh_equipment()


func _inventory_slot(slot: Array) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	if slot.is_empty():
		button.disabled = true
		return button
	var id: String = slot[0]
	button.toggle_mode = true
	button.button_pressed = id == _inv_selected
	button.tooltip_text = Game.RESOURCE_NAMES[id]
	button.pressed.connect(_select_item.bind(id))
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			_use_item(id))
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 6
	icon.offset_top = 6
	icon.offset_right = -6
	icon.offset_bottom = -6
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = icons.textures.get(id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var count := Label.new()
	count.text = str(slot[1])
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	count.offset_right = -5
	count.offset_bottom = -2
	count.add_theme_font_size_override("font_size", 15)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 4)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(count)
	return button


func _select_item(id: String) -> void:
	_inv_selected = id
	_inv_confirm = ""
	_refresh_inventory_panel()


## Ficha del objeto elegido: nombre, para qué sirve y qué se puede hacer.
func _refresh_inventory_detail() -> void:
	for child in inventory_detail.get_children():
		inventory_detail.remove_child(child)
		child.queue_free()
	var id := _inv_selected
	if id == "":
		var empty := Label.new()
		empty.text = "La mochila está vacía."
		empty.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		inventory_detail.add_child(empty)
	else:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = icons.textures.get(id)
		head.add_child(icon)
		var name_label := Label.new()
		name_label.text = "%s\nLlevas %d" % [Game.RESOURCE_NAMES[id], Game.inventory[id]]
		name_label.add_theme_font_size_override("font_size", 16)
		head.add_child(name_label)
		inventory_detail.add_child(head)
		var info := Label.new()
		info.text = _item_info(id)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = 250
		info.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		inventory_detail.add_child(info)
		var buttons := HBoxContainer.new()
		if Game.is_usable(id):
			buttons.add_child(_inventory_button("Usar", _use_item.bind(id)))
		buttons.add_child(_inventory_button("Tirar 1", _throw_item.bind(id, 1)))
		buttons.add_child(_inventory_button(
				"¿Seguro? Otra vez" if _inv_confirm == id else "Tirar todo", _throw_item.bind(id, -1)))
		inventory_detail.add_child(buttons)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_detail.add_child(spacer)
	inventory_detail.add_child(_inventory_button(
			"Orden: por nombre" if _inv_sort_by_name else "Orden: por tipo", _toggle_sort))


func _inventory_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


func _toggle_sort() -> void:
	_inv_sort_by_name = not _inv_sort_by_name
	_refresh_inventory_panel()


func _use_item(id: String) -> void:
	_inv_confirm = ""
	if Game.is_usable(id):
		Game.use_item(id)
	_refresh_inventory_panel()


## Tirar destruye el objeto. Con amount -1 se tira todo, y hay que pulsar dos veces.
func _throw_item(id: String, amount: int) -> void:
	var have := int(Game.inventory.get(id, 0))
	if amount < 0:
		if _inv_confirm != id:
			_inv_confirm = id
			_refresh_inventory_panel()
			return
		amount = have
	_inv_confirm = ""
	if have <= 0:
		return
	Game.add_item(id, -mini(amount, have))
	Sfx.play("clic")
	_refresh_inventory_panel()


func _item_info(id: String) -> String:
	match id:
		"botella":
			return "Usar: +%d de oxígeno." % int(Game.BOTTLE_REFILL)
		"racion", "verdura", "guiso":
			var text := "Usar: quita %d de hambre." % int(Game.FOODS[id])
			return text + (" También sirve para el guiso." if id == "verdura" else "")
		"semillas":
			return "Material: plantar musgo, bancales y árboles."
		"chip":
			return "Se gasta en un terminal de investigación."
		"titanio", "cuarzo", "iridio":
			return "Material avanzado de cuevas y cráteres."
		"placa", "circuito":
			return "Componente de las tecnologías avanzadas."
	return "Material de construcción y fabricación."


## Casillas del equipo: id, nombre corto, posición en el marco y a qué
## parte del astronauta apunta su línea.
func _equipment_slots() -> Array:
	var drill := Game.drill()
	var pack: Dictionary = Game.BACKPACKS[Game.backpack_level]
	var left := 8.0
	var right := EQUIP_SIZE.x - EQUIP_SLOT - 8.0
	return [
		{"icon": "linterna", "name": "Linterna", "owned": Game.has_flashlight, "pos": Vector2(right, 14),
				"to": Vector2(172, 62), "effect": "L para encenderla o apagarla; en las cuevas no se ve sin ella",
				"caption": ("Encendida" if Game.flashlight_on else "Apagada") if Game.has_flashlight else "Linterna", "toggle": true},
		{"icon": String(drill["id"]) if drill["id"] != "" else "taladro", "name": "Recolector", "owned": true,
				"pos": Vector2(right, 100), "to": Vector2(212, 150),
				"effect": "%s: vacía un depósito en %.2f s y recoges x%d" % [drill["name"], drill["time"], drill["yield"]],
				"caption": drill["name"]},
		{"icon": "herramienta_construccion", "name": "Construcción", "owned": Game.has_build_tool, "pos": Vector2(right, 186),
				"to": Vector2(110, 262), "effect": "Modo Construir (2)", "caption": "Construcción"},
		{"icon": "herramienta_desmontaje", "name": "Desmontaje", "owned": Game.has_dismantle_tool, "pos": Vector2(right, 272),
				"to": Vector2(200, 262), "effect": "Modo Desmontar (3)", "caption": "Desmontaje"},
		{"icon": String(pack["id"]) if pack["id"] != "" else "bolsa", "name": pack["name"], "owned": true,
				"pos": Vector2(left, 100), "to": Vector2(118, 150), "effect": "%d casillas" % pack["slots"], "caption": pack["name"]},
		{"icon": "tanque", "name": "Tanque de oxígeno", "owned": Game.has_tank, "pos": Vector2(left, 186),
				"to": Vector2(118, 185), "effect": "Reserva de oxígeno de %d" % int(Game.TANK_O2_MAX), "caption": "Tanque"},
		{"icon": "jetpack", "name": "Propulsores", "owned": Game.has_jetpack, "pos": Vector2(left, 272),
				"to": Vector2(118, 215), "effect": "Espacio en el aire para volar un poco", "caption": "Propulsores"},
	]


## Silueta del astronauta con una línea hasta cada casilla del equipo.
func _draw_astronaut() -> void:
	var suit := Color(0.2, 0.23, 0.29)
	var edge := Color(0.55, 0.62, 0.72)
	var visor := Color(0.3, 0.55, 0.8)
	var line := Color(0.55, 0.62, 0.72, 0.45)
	for slot in _equipment_slots():
		var from: Vector2 = slot["pos"] + Vector2(EQUIP_SLOT / 2.0, EQUIP_SLOT / 2.0)
		equip_body.draw_line(from, slot["to"], line, 1.5)
	var parts := [
		PackedVector2Array([Vector2(128, 250), Vector2(152, 250), Vector2(150, 372), Vector2(124, 372)]), # pierna izquierda
		PackedVector2Array([Vector2(158, 250), Vector2(182, 250), Vector2(186, 372), Vector2(160, 372)]), # pierna derecha
		PackedVector2Array([Vector2(112, 112), Vector2(198, 112), Vector2(192, 255), Vector2(118, 255)]), # torso
		PackedVector2Array([Vector2(112, 114), Vector2(96, 120), Vector2(82, 230), Vector2(102, 236), Vector2(114, 170)]), # brazo izquierdo
		PackedVector2Array([Vector2(198, 114), Vector2(214, 120), Vector2(228, 230), Vector2(208, 236), Vector2(196, 170)]), # brazo derecho
	]
	for part in parts:
		equip_body.draw_colored_polygon(part, suit)
		equip_body.draw_polyline(part + PackedVector2Array([part[0]]), edge, 2.0)
	for boot_x in [124.0, 160.0]:
		equip_body.draw_rect(Rect2(boot_x, 366, 28, 18), edge.darkened(0.3))
	equip_body.draw_circle(Vector2(155, 66), 40.0, suit)
	equip_body.draw_arc(Vector2(155, 66), 40.0, 0.0, TAU, 32, edge, 2.0)
	equip_body.draw_rect(Rect2(129, 54, 52, 26), visor)
	equip_body.draw_rect(Rect2(138, 150, 34, 10), edge.darkened(0.3)) # panel del pecho
	equip_body.draw_rect(Rect2(118, 244, 74, 8), edge.darkened(0.3)) # cinturón


## Lo que se lleva puesto, que no ocupa casillas: una casilla por pieza, vacía
## y apagada si no se tiene, y la linterna se enciende desde ahí.
func _refresh_equipment() -> void:
	for child in equip_frame.get_children():
		if child != equip_body:
			equip_frame.remove_child(child)
			child.queue_free()
	equip_body.queue_redraw()
	for slot in _equipment_slots():
		_equipment_slot(slot)


func _equipment_slot(slot: Dictionary) -> void:
	var owned: bool = slot["owned"]
	var button := Button.new()
	button.position = slot["pos"]
	button.custom_minimum_size = Vector2(EQUIP_SLOT, EQUIP_SLOT)
	button.size = Vector2(EQUIP_SLOT, EQUIP_SLOT)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not owned
	button.tooltip_text = "%s\n%s" % [slot["name"], slot["effect"]] if owned else "%s\nTodavía no la tienes: fabrícala en el fabricador" % slot["name"]
	if owned and slot.get("toggle", false):
		button.pressed.connect(func() -> void:
			Game.toggle_flashlight()
			_refresh_equipment())
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 6
	icon.offset_top = 6
	icon.offset_right = -6
	icon.offset_bottom = -6
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = icons.textures.get(slot["icon"])
	icon.modulate = Color(1, 1, 1, 1) if owned else Color(0.6, 0.65, 0.75, 0.22)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	equip_frame.add_child(button)
	var caption := Label.new()
	caption.text = slot["caption"]
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85) if owned else Color(0.55, 0.55, 0.55))
	caption.position = Vector2(slot["pos"].x - 8.0, slot["pos"].y + EQUIP_SLOT + 1.0)
	caption.custom_minimum_size.x = EQUIP_SLOT + 16.0
	caption.size.x = EQUIP_SLOT + 16.0
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equip_frame.add_child(caption)


func _build_locker_panel() -> void:
	var parts := _panel("")
	locker_panel = parts[0]
	locker_title = parts[2]
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	parts[1].add_child(columns)
	locker_inventory = VBoxContainer.new()
	locker_inventory.custom_minimum_size.x = 260
	columns.add_child(locker_inventory)
	locker_contents = VBoxContainer.new()
	locker_contents.custom_minimum_size.x = 260
	columns.add_child(locker_contents)


func _build_death_screen() -> void:
	death_overlay = ColorRect.new()
	death_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay.color = Color(0, 0, 0, 0)
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.visible = false
	add_child(death_overlay)
	death_label = Label.new()
	death_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_label.add_theme_font_size_override("font_size", 32)
	death_label.visible = false
	death_overlay.add_child(death_label)


## Fundido a negro de DEATH_FADE_TIME segundos y, después, el game over.
func _on_player_died(cause: String) -> void:
	_close_panel()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	death_label.text = "GAME OVER\n\n%s\n\nPulsa Enter para volver a la base" % cause
	death_overlay.color.a = 0.0
	death_overlay.visible = true
	var tween := create_tween()
	tween.tween_property(death_overlay, "color:a", 1.0, DEATH_FADE_TIME)
	tween.tween_callback(_show_game_over)


func _show_game_over() -> void:
	death_label.visible = true
	_waiting_respawn = true


func _respawn() -> void:
	_waiting_respawn = false
	death_label.visible = false
	death_overlay.visible = false
	get_tree().paused = false
	Game.respawn()


func _show_panel(panel: Control) -> void:
	_close_panel()
	_open_panel = panel
	panel.visible = true
	Game.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_panel()


func _close_panel() -> void:
	if _open_panel == null:
		return
	if _open_panel == menu_panel and Game.fabricating != "":
		Game.cancel_fabrication()
		_show_message("Fabricación cancelada: te devuelve los materiales.")
	if _open_panel == locker_panel and is_instance_valid(_locker) and Game.tutorial == 1 \
			and _locker.is_fixed():
		Game.tutorial = 2
		_show_message("Fabrica la herramienta de construcción en el fabricador (E).")
	_open_panel.visible = false
	_open_panel = null
	_locker = null
	Game.ui_open = false
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_panel() -> void:
	if _open_panel == menu_panel:
		_refresh_menu_grid()
	elif _open_panel == inventory_panel:
		_refresh_inventory_panel()
	elif _open_panel == locker_panel:
		_refresh_locker()
	elif _open_panel == research_panel:
		_refresh_research()
	elif _open_panel == map_panel:
		_refresh_map()


func _on_inventory_changed() -> void:
	# Una herramienta nueva trae su modo a la barra.
	_on_tool_changed(Game.tool_mode)
	if _open_panel:
		_refresh_panel()


## Secciones que enseña el menú abierto ahora.
func _menu_sections() -> Array:
	return FAB_SECTIONS if _menu_mode == "fabricate" else BUILD_SECTIONS


## Abre el menú de "mode": "build" (construcciones, con la herramienta de
## construcción) o "fabricate" (el panel del fabricador).
func _show_menu(mode: String, section := "") -> void:
	_menu_mode = mode
	var fabricate := mode == "fabricate"
	menu_heading.text = "Fabricador" if fabricate else "Construir"
	menu_close_hint.text = "E, clic derecho o Esc para cerrar" if fabricate else "Clic derecho o Esc para cerrar"
	fab_box.visible = fabricate
	_fab_time = 0.0
	var height := 0.0
	for name in _menu_sections():
		var count := _section_kinds(name).size()
		if count > 0:
			height += (0.0 if fabricate else 44.0) + ceili(count / float(MENU_COLUMNS)) * (CELL_SIZE.y + 6)
	var width := MENU_COLUMNS * (CELL_SIZE.x + 6)
	height = minf(height, get_viewport().get_visible_rect().size.y - 110 - (110.0 if fabricate else 0.0))
	menu_scroll.custom_minimum_size = Vector2(width, height)
	_show_panel(menu_panel)
	menu_scroll.scroll_vertical = 0
	if section != "" and _section_headers.has(section):
		# Hay que esperar a que se coloquen las casillas para saber dónde queda.
		await get_tree().process_frame
		if _section_headers.has(section) and is_instance_valid(_section_headers[section]):
			menu_scroll.scroll_vertical = int(_section_headers[section].position.y)


## Lo que sale en una sección, en el orden de las recetas: solo lo
## desbloqueado.
func _section_kinds(tab: String) -> Array:
	var kinds := []
	for id in Game.RECIPES:
		if not Game.is_unlocked(id):
			continue
		if tab == "fabricar" and not Game.is_placeable(id):
			kinds.append(id)
		elif tab != "fabricar" and String(Game.RECIPES[id].get("tab", "")) == tab:
			kinds.append(id)
	return kinds


## Con la herramienta de construcción: clic o elegir el modo.
func _on_build_menu_requested() -> void:
	if not get_tree().paused and not Game.dead:
		_show_menu("build")


## E sobre un fabricador.
func _on_fabricator_requested() -> void:
	if not get_tree().paused and not Game.dead:
		_show_menu("fabricate")


func _on_fabrication_changed() -> void:
	if _open_panel == menu_panel and _menu_mode == "fabricate":
		_refresh_menu_grid()
		_update_fabrication_bar(0.0)


## Barra y animación de lo que se fabrica: el icono se mece y late.
func _update_fabrication_bar(delta: float) -> void:
	if Game.fabricating == "":
		fab_label.text = "Elige qué fabricar"
		fab_bar.value = 0.0
		fab_icon.modulate = Color(1, 1, 1, 0)
		return
	_fab_time += delta
	fab_label.text = "Fabricando: %s" % Game.RECIPES[Game.fabricating]["name"]
	fab_bar.value = 1.0 - Game.fabricate_left / maxf(Game.fabricate_total, 0.01)
	fab_icon.texture = icons.textures.get(Game.fabricating)
	fab_icon.modulate = Color(1, 1, 1, 1)
	fab_icon.pivot_offset = fab_icon.size / 2.0
	fab_icon.scale = Vector2.ONE * (1.0 + 0.1 * sin(_fab_time * 10.0))
	fab_icon.rotation = sin(_fab_time * 6.0) * 0.2


func _on_icons_finished() -> void:
	if _open_panel:
		_refresh_panel()


## Todas las secciones seguidas, cada una con su título y una casilla por
## receta desbloqueada: icono, nombre y coste. Las que no se pueden pagar
## salen apagadas. Las secciones sin nada desbloqueado no salen.
func _refresh_menu_grid() -> void:
	for child in menu_sections.get_children():
		menu_sections.remove_child(child)
		child.queue_free()
	_section_headers.clear()
	for section in _menu_sections():
		var kinds := _section_kinds(section)
		if kinds.is_empty():
			continue
		# El fabricador es una sola lista y no necesita título.
		if _menu_mode == "build":
			var header := Label.new()
			header.text = SECTION_NAMES[section]
			header.add_theme_font_size_override("font_size", 16)
			header.add_theme_color_override("font_color", MODE_COLORS["construir"])
			menu_sections.add_child(header)
			_section_headers[section] = header
			menu_sections.add_child(HSeparator.new())
		var grid := GridContainer.new()
		grid.columns = MENU_COLUMNS
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		menu_sections.add_child(grid)
		for id in kinds:
			grid.add_child(_menu_cell(id, section))


func _menu_cell(id: String, section: String) -> Button:
	var recipe: Dictionary = Game.RECIPES[id]
	var owned := _owned(id)
	var button := Button.new()
	button.custom_minimum_size = CELL_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not Game.can_craft(id) or _driving or (_menu_mode == "fabricate" and Game.fabricating != "")
	button.pressed.connect(_on_item_pressed.bind(id))
	button.tooltip_text = _tooltip(id)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	button.add_child(box)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.texture = icons.textures.get(id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Lo que no se puede hacer sale difuminado y los componentes que faltan,
	# en rojo.
	var blurred: bool = button.disabled and not owned
	if blurred:
		icon.modulate = Color(1, 1, 1, 0.3)
	box.add_child(icon)
	var name_label := _small_label(recipe["name"], 12)
	if blurred:
		name_label.modulate = Color(1, 1, 1, 0.5)
	box.add_child(name_label)
	if owned:
		var owned_label := _small_label("Ya lo tienes", 11)
		owned_label.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
		box.add_child(owned_label)
	else:
		box.add_child(_cost_label(recipe["cost"], blurred))
	var count := int(Game.inventory.get(id, 0))
	if recipe["kind"] == "consumable" and count > 0:
		# Cuántas lleva ya, en la esquina de arriba a la derecha.
		var count_label := Label.new()
		count_label.text = "x%d" % count
		count_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		count_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count_label.offset_right = -6
		count_label.offset_top = 2
		count_label.add_theme_font_size_override("font_size", 13)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(count_label)
	return button


## Coste de una receta: cada componente en su color, en rojo los que faltan.
func _cost_label(cost: Dictionary, blurred: bool) -> RichTextLabel:
	var parts := PackedStringArray()
	for res in cost:
		var text := "%d %s" % [cost[res], String(Game.RESOURCE_NAMES[res]).to_lower()]
		if int(Game.inventory.get(res, 0)) < int(cost[res]):
			text = "[color=#ff5a50]%s[/color]" % text
		parts.append(text)
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CELL_SIZE.x - 8
	label.add_theme_font_size_override("normal_font_size", 11)
	label.add_theme_color_override("default_color", Color(0.75, 0.75, 0.75))
	label.text = "[center]%s[/center]" % " + ".join(parts)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if blurred:
		# Los que faltan siguen viéndose bien; solo se apaga el resto.
		label.modulate = Color(1, 1, 1, 0.85)
	return label


## Las herramientas se fabrican una sola vez.
func _owned(id: String) -> bool:
	match id:
		"taladro", "taladro_termico", "taladro_plasma":
			return Game.drill_level >= Game.drill_index(id)
		"mochila", "mochila_reforzada", "mochila_aleacion":
			return Game.backpack_level >= Game.backpack_index(id)
		"tanque":
			return Game.has_tank
		"jetpack":
			return Game.has_jetpack
		"linterna":
			return Game.has_flashlight
		"herramienta_construccion":
			return Game.has_build_tool
		"herramienta_desmontaje":
			return Game.has_dismantle_tool
	return false


func _tooltip(id: String) -> String:
	var recipe: Dictionary = Game.RECIPES[id]
	var tip := "%s\n%s" % [recipe["name"], Game.cost_text(recipe["cost"])]
	match id:
		"taladro", "taladro_termico", "taladro_plasma":
			var drill: Dictionary = Game.DRILLS[Game.drill_index(id)]
			tip += "\nVacía un depósito en %.2f s (ahora %.2f s) y recoges x%d" % [drill["time"], Game.drill()["time"], drill["yield"]]
			var before := Game.drill_index(id) - 1
			if Game.drill_level < before:
				tip += "\nAntes necesitas el %s" % Game.DRILLS[before]["name"]
		"tanque":
			tip += "\nTu reserva de oxígeno sube a %d" % int(Game.TANK_O2_MAX)
		"jetpack":
			tip += "\nMantén Espacio en el aire para volar un poco"
		"botella":
			tip += "\nSe usa desde el inventario (I) para respirar de ella"
		"semillas":
			tip += "\nSirven para plantar musgo, bancales y árboles"
		"guiso":
			tip += "\nSe come desde el inventario (I): llena la barra entera"
		"mochila", "mochila_reforzada", "mochila_aleacion":
			var pack: Dictionary = Game.BACKPACKS[Game.backpack_index(id)]
			tip += "\n%d casillas de %d unidades (ahora %d)" % [pack["slots"], Game.SLOT_SIZE, Game.slots_max()]
			var previous := Game.backpack_index(id) - 1
			if Game.backpack_level < previous:
				tip += "\nAntes necesitas la %s" % String(Game.BACKPACKS[previous]["name"]).to_lower()
		"linterna":
			tip += "\nL para encenderla o apagarla; dentro de las cuevas no se ve nada sin ella"
		"herramienta_construccion":
			tip += "\nModo Construir (2): coloca bases, máquinas y todo lo demás"
		"herramienta_desmontaje":
			tip += "\nModo Desmontar (3): quita lo construido y te devuelve los materiales"
		"fabricador":
			tip += "\nPara fabricar lejos de la cápsula; no gasta energía. Va dentro de la base"
		"placa", "circuito":
			tip += "\nComponente de las tecnologías avanzadas"
	if recipe["kind"] == "consumable" and Game.room_for(id) < 1:
		tip += "\nMochila llena: tira o guarda algo (I)"
	if _driving and Game.is_placeable(id):
		tip += "\nBájate del róver para construir"
	if recipe["kind"] == "vehicle":
		tip += "\nMaletero pequeño y batería\nSe carga en un punto de recarga"
	if Game.MACHINES.get(id, {}).get("gathers", false):
		tip += "\nSus drones recogen de los depósitos cercanos"
	if Game.MACHINES.get(id, {}).get("rain", false):
		tip += "\nRecoge agua cuando llueve, sin energía"
	if Game.MACHINES.get(id, {}).get("pollinates", false):
		tip += "\nLos bancales cercanos dan verduras más rápido"
	if Game.MACHINES.get(id, {}).get("research", false):
		tip += "\nE para gastar chips de datos en tecnologías nuevas"
	if Game.MACHINES.get(id, {}).get("satellite", false):
		tip += "\nDa conexión con satélites: abre el mapa con M"
	if Game.MACHINES.get(id, {}).get("teleport", false):
		tip += "\nE para viajar al siguiente telepuerto (hacen falta dos)"
	if Game.MACHINES.get(id, {}).has("deposits"):
		var names := PackedStringArray()
		for res in Game.MACHINES[id]["deposits"]:
			names.append(String(Game.RESOURCE_NAMES[res]).to_lower())
		tip += "\nSe pone sobre un depósito de %s" % ", ".join(names)
	if Game.MACHINES.get(id, {}).get("plant", false):
		tip += "\nCon lluvia crece el doble de rápido"
	if recipe["kind"] == "building":
		var energy := int(Game.MACHINES[id]["energy"])
		if energy > 0:
			tip += "\nDa %d de energía" % energy
		elif energy < 0:
			tip += "\nGasta %d de energía" % -energy
		for metric in Game.METRICS:
			if float(Game.MACHINES[id].get(metric, 0)) > 0.0:
				tip += "\nSube: %s" % String(Game.METRIC_NAMES[metric]).to_lower()
		if Game.MACHINES[id].has("display"):
			tip += "\nMuestra cómo va el planeta"
	return tip


func _small_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CELL_SIZE.x - 8
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## En el fabricador empieza a fabricar (va a la mochila al acabar); en el
## menú de construir cierra el menú y empieza a colocarse.
func _on_item_pressed(id: String) -> void:
	if _menu_mode == "fabricate":
		Game.start_fabrication(id)
		return
	if Game.is_placeable(id):
		_close_panel()
		# Colocar solo funciona en modo construir (al cambiar de modo se cancela).
		Game.set_tool_mode("construir")
	Game.craft(id)


## Panel del terminal: lo que se puede investigar con chips de datos.
func _build_research_panel() -> void:
	var parts := _panel("Terminal de investigación (E o Esc para cerrar)")
	research_panel = parts[0]
	research_list = VBoxContainer.new()
	research_list.custom_minimum_size.x = 520
	research_list.add_theme_constant_override("separation", 8)
	parts[1].add_child(research_list)


func _on_research_requested() -> void:
	if not get_tree().paused and not Game.dead:
		_show_panel(research_panel)


func _refresh_research() -> void:
	for child in research_list.get_children():
		child.queue_free()
	var chips := int(Game.inventory.get("chip", 0))
	research_list.add_child(_small_heading("Chips de datos: %d" % chips))
	var list := Game.researchable()
	if list.is_empty():
		var note := Label.new()
		note.text = "No hay nada que investigar por ahora."
		note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		research_list.add_child(note)
	for id in list:
		var recipe: Dictionary = Game.RECIPES[id]
		var need := int(recipe["unlock"]["chips"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = icons.textures.get(id)
		row.add_child(icon)
		var label := Label.new()
		label.text = "%s\n%s" % [recipe["name"], Game.cost_text(recipe["cost"])]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.text = "Investigar (%d chips)" % need
		button.disabled = chips < need
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: Game.research(id))
		row.add_child(button)
		research_list.add_child(row)
	var hint := Label.new()
	hint.text = "Los chips y los fragmentos de plano están en las cajas de los restos de naves y de las cuevas."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 520
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	research_list.add_child(hint)


## Mapa por satélite: los biomas del planeta, dónde estás y lo que has
## visitado. Hace falta un enlace satelital construido.
func _build_map_panel() -> void:
	var parts := _panel("Mapa por satélite (M o Esc para cerrar)")
	map_panel = parts[0]
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	var image := TextureRect.new()
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(image)
	map_marks = Control.new()
	map_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_marks.draw.connect(_draw_map_marks)
	frame.add_child(map_marks)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(frame)
	map_info = RichTextLabel.new()
	map_info.bbcode_enabled = true
	map_info.custom_minimum_size = Vector2(230, MAP_SIZE)
	row.add_child(map_info)
	parts[1].add_child(row)
	map_panel.set_meta("image", image)


func _on_map_requested() -> void:
	if Game.dead:
		return
	if not Game.has_satellite():
		_show_message("Sin conexión con satélites: construye un enlace satelital (Tecnología).")
		return
	_show_panel(map_panel)


func _refresh_map() -> void:
	if _map_texture == null:
		var land = get_parent().land
		_map_texture = ImageTexture.create_from_image(land.biome_map(MAP_PIXELS))
		(map_panel.get_meta("image") as TextureRect).texture = _map_texture
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var pos := player.global_position
	var text := "Estás en: %s\nPosición: %d, %d\n\nBiomas\n" % [Terrain.BIOME_NAMES[Game.biome], roundi(pos.x), roundi(pos.z)]
	for id in Terrain.BIOME_NAMES:
		text += "[color=#%s]■[/color] %s\n" % [Terrain.BIOME_MAP_COLORS[id].to_html(false), Terrain.BIOME_NAMES[id]]
	text += "\nSitios visitados: %d\n● cueva  ■ nave  ○ cráter\n▲ tú  ▪ base" % Game.visited_sites.size()
	map_info.text = text
	map_marks.queue_redraw()


## Convierte una posición del mundo en un punto del mapa.
func _map_point(x: float, z: float) -> Vector2:
	var world := Terrain.WORLD_SIZE
	return Vector2((x + world / 2.0) / world, (z + world / 2.0) / world) * MAP_SIZE


func _draw_map_marks() -> void:
	var land = get_parent().land
	var outline := Color(0, 0, 0, 0.85)
	map_marks.draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)), Color(1, 1, 1, 0.5), false, 2.0)
	for site in land.sites():
		if not String(site["id"]) in Game.visited_sites:
			continue
		var at := _map_point(site["pos"].x, site["pos"].z)
		var color: Color = SITE_MARKS[site["type"]]
		match String(site["type"]):
			"cueva":
				map_marks.draw_circle(at, 5.0, outline)
				map_marks.draw_circle(at, 3.5, color)
			"nave":
				map_marks.draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), outline)
				map_marks.draw_rect(Rect2(at - Vector2(3.5, 3.5), Vector2(7, 7)), color)
			_:
				map_marks.draw_arc(at, 4.5, 0.0, TAU, 16, outline, 4.0)
				map_marks.draw_arc(at, 4.5, 0.0, TAU, 16, color, 2.0)
	# La base: un cuadrado por módulo (o por máquina, si no hay módulos).
	var base := Game.modules if not Game.modules.is_empty() else Game.machines
	for part in base:
		var at := _map_point(float(part.get("x", 0.0)), float(part.get("z", 0.0)))
		map_marks.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.85, 0.2))
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var at := _map_point(player.global_position.x, player.global_position.z)
		var facing: Vector3 = player.global_transform.basis * Vector3.FORWARD
		var dir := Vector2(facing.x, facing.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		var tip := at + dir * 10.0
		var points := PackedVector2Array([tip, at - dir * 6.0 + side * 6.0, at - dir * 3.0, at - dir * 6.0 - side * 6.0])
		map_marks.draw_colored_polygon(points, Color(1, 1, 1))
		map_marks.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), outline, 1.5)


func _on_locker_requested(locker: Node3D) -> void:
	if not get_tree().paused and not Game.dead:
		_show_panel(locker_panel)
		_locker = locker
		_refresh_locker()


## Dos columnas: la mochila (guardar) y la taquilla (sacar).
func _refresh_locker() -> void:
	if not is_instance_valid(_locker):
		return
	_locker_total = _locker.stored_total()
	var locker_name: String = Game.RECIPES[_locker.kind]["name"]
	locker_title.text = "%s · %d / %d (E o Esc para cerrar)" % [locker_name, _locker.stored_total(), _locker.capacity()]
	# En la bomba, el bancal y la estación de drones solo se saca lo que traen.
	var accepts: bool = _locker.accepts_items()
	for column in [locker_inventory, locker_contents]:
		for child in column.get_children():
			child.queue_free()
	locker_inventory.add_child(_small_heading("Mochila"))
	if not accepts:
		var note := Label.new()
		note.text = "Aquí solo se saca lo que trae." if Game.MACHINES[_locker.kind].get("gathers", false) else "Aquí solo se saca lo que produce."
		note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		locker_inventory.add_child(note)
	locker_contents.add_child(_small_heading(locker_name))
	var free: int = _locker.capacity() - _locker.stored_total()
	var items: Dictionary = _locker.items()
	for id in Game.inventory:
		var have := int(Game.inventory[id])
		if have > 0 and accepts:
			locker_inventory.add_child(_locker_row(id, have, mini(have, free), true))
	for id in items:
		var stored := int(items[id])
		if stored > 0:
			locker_contents.add_child(_locker_row(id, stored, mini(stored, Game.room_for(id)), false))


func _small_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	return label


## Fila con el recurso, cuántos hay y botones para mover 1 o todos.
func _locker_row(id: String, count: int, movable: int, storing: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s: %d" % [Game.RESOURCE_NAMES[id], count]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	for amount in [1, movable]:
		var button := Button.new()
		button.text = "1" if amount == 1 else "Todo"
		button.disabled = movable <= 0
		button.pressed.connect(_move_items.bind(id, amount, storing))
		row.add_child(button)
	return row


func _move_items(id: String, amount: int, storing: bool) -> void:
	if not is_instance_valid(_locker) or amount <= 0:
		return
	var items: Dictionary = _locker.items()
	if storing:
		amount = mini(amount, mini(int(Game.inventory.get(id, 0)), _locker.capacity() - _locker.stored_total()))
		items[id] = int(items.get(id, 0)) + amount
		Game.add_item(id, -amount)
	else:
		# Solo lo que quepa en la mochila.
		amount = mini(amount, mini(int(items.get(id, 0)), Game.room_for(id)))
		if amount <= 0:
			_show_message(Game.FULL_MESSAGE)
			return
		items[id] = int(items[id]) - amount
		if int(items[id]) <= 0:
			items.erase(id)
		Game.add_item(id, amount)
	Sfx.play("clic")


func _show_message(text: String) -> void:
	message_label.text = text
	message_timer = MESSAGE_TIME
