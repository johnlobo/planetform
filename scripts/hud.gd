extends CanvasLayer
## Interfaz: inventario, estado del planeta, oxígeno del jugador, modo de la
## herramienta, el menú de fabricar y construir y el panel de la taquilla.

const Icons := preload("res://scripts/icons.gd")
const Machine := preload("res://scripts/machine.gd")

const MESSAGE_TIME := 4.0
const ICON_SIZE := 72
# Casilla del menú: con 9 columnas caben las 26 construcciones en 3 filas.
const CELL_SIZE := Vector2(ICON_SIZE + 46, ICON_SIZE + 78)
const MENU_COLUMNS := 9
const TAB_NAMES := {"fabricar": "Fabricar", "construir": "Construir"}
const MODE_COLORS := {
	"recoger": Color(1.0, 0.85, 0.55),
	"construir": Color(0.55, 0.88, 1.0),
	"desmontar": Color(1.0, 0.45, 0.4),
}
const DEATH_FADE_TIME := 3.0

var inventory_label: Label
var planet_label: Label
var oxygen_bar: ProgressBar
var warmth_bar: ProgressBar
var hunger_bar: ProgressBar
var jetpack_title: Label
var jetpack_bar: ProgressBar
var hint_label: Label
var message_label: Label
var menu_panel: PanelContainer
var menu_grid: GridContainer
var menu_scroll: ScrollContainer
var tab_buttons := {}
var locker_panel: PanelContainer
var locker_title: Label
var locker_inventory: VBoxContainer
var locker_contents: VBoxContainer
var crosshair: Label
var mode_labels := {}
var icons: Icons
# Panel abierto ahora (el menú o la taquilla), o null.
var _open_panel: Control
# Pestaña del menú: "fabricar" o "construir". Tab vuelve a la última usada.
var _tab := "fabricar"
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
	inventory_label = _label(Control.PRESET_TOP_LEFT, Vector2(16, 16))

	planet_label = _label(Control.PRESET_TOP_RIGHT, Vector2(-16, 16))
	planet_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	planet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	crosshair = _label(Control.PRESET_CENTER, Vector2(-4, -12))
	crosshair.text = "+"

	hint_label = _label(Control.PRESET_CENTER, Vector2(-160, 16))
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
	help.text = "WASD mover · Espacio saltar · Clic usar herramienta · 1 2 3 o rueda cambiar modo\nTab fabricar y construir · E abrir taquilla o subir al róver · Q usar botella · F comer · R girar · H menú · Esc soltar ratón"

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
	jetpack_title = Label.new()
	jetpack_title.text = "Propulsores"
	oxygen_box.add_child(jetpack_title)
	jetpack_bar = ProgressBar.new()
	jetpack_bar.max_value = Game.JETPACK_FUEL_MAX
	jetpack_bar.custom_minimum_size = Vector2(300, 20)
	jetpack_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oxygen_box.add_child(jetpack_bar)
	add_child(oxygen_box)

	_build_menu_panel()
	_build_locker_panel()
	_build_death_screen()
	icons = Icons.new()
	add_child(icons)
	icons.finished.connect(_on_icons_finished)
	icons.render(Game.RECIPES.keys())

	Game.inventory_changed.connect(_refresh_inventory)
	Game.message.connect(_show_message)
	Game.player_died.connect(_on_player_died)
	Game.tool_changed.connect(_on_tool_changed)
	Game.build_menu_requested.connect(_on_build_menu_requested)
	Game.driving_changed.connect(func(driving: bool) -> void: _driving = driving)
	Game.locker_requested.connect(_on_locker_requested)
	_on_tool_changed(Game.tool_mode)
	_refresh_inventory()


func _input(event: InputEvent) -> void:
	# Se usa _input y no _unhandled_input porque los botones del menú
	# consumen la tecla Tab para mover el foco.
	if Game.dead:
		# Durante la muerte solo cuenta Enter, y solo cuando ya sale el game over.
		if _waiting_respawn and event.is_action_pressed("ui_accept"):
			_respawn()
		get_viewport().set_input_as_handled()
	elif _open_panel:
		var right_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
		if event.is_action_pressed("craft") or event.is_action_pressed("release_mouse") \
				or (event.is_action_pressed("interact") and _open_panel == locker_panel) or right_click:
			_close_panel()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("craft") and not get_tree().paused:
		_show_menu(_tab)
		get_viewport().set_input_as_handled()


## Se llama al abrir el menú: cierra los paneles y oculta la interfaz.
func on_menu_opened() -> void:
	_close_panel()
	visible = false


func on_menu_closed() -> void:
	visible = true


func _process(delta: float) -> void:
	oxygen_bar.max_value = Game.player_o2_max()
	oxygen_bar.value = Game.player_oxygen
	warmth_bar.value = Game.warmth
	hunger_bar.value = Game.hunger
	jetpack_title.visible = Game.has_jetpack
	jetpack_bar.visible = Game.has_jetpack
	jetpack_bar.value = Game.jetpack_fuel
	hint_label.text = "" if Game.ui_open else Game.hint
	if _open_panel == locker_panel and not is_instance_valid(_locker):
		_close_panel()
	elif _open_panel == locker_panel and _locker.stored_total() != _locker_total:
		# La bomba y el bancal siguen produciendo con el panel abierto.
		_refresh_locker()
	planet_label.text = Game.clock_text() + ("  (noche)" if Game.is_night() else "") + ("  (lloviendo)" if Game.is_raining() else "") + "\nEtapa: %s\nOxígeno: %.1f %%\nTemperatura: %.1f %%\nPresión: %.1f %%\nBiomasa: %.1f %%\nÍndice: %.1f %%\nEnergía: %d producida / %d necesaria" % [
		Game.STAGES[Game.stage]["name"], Game.oxygen, Game.temperature, Game.pressure, Game.biomass,
		Game.terraform_index(), Game.energy_supply(), Game.energy_demand()]
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
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	parts[1].add_child(tabs)
	parts[1].move_child(tabs, 0)
	var group := ButtonGroup.new()
	for tab in TAB_NAMES:
		var button := Button.new()
		button.text = TAB_NAMES[tab]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(140, 36)
		button.add_theme_color_override("font_pressed_color", MODE_COLORS["construir"])
		button.add_theme_color_override("font_hover_pressed_color", MODE_COLORS["construir"])
		button.pressed.connect(_select_tab.bind(tab))
		tabs.add_child(button)
		tab_buttons[tab] = button
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	var close_hint := Label.new()
	close_hint.text = "Tab, clic derecho o Esc para cerrar"
	close_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	tabs.add_child(close_hint)
	menu_grid = GridContainer.new()
	menu_grid.columns = MENU_COLUMNS
	menu_grid.add_theme_constant_override("h_separation", 8)
	menu_grid.add_theme_constant_override("v_separation", 8)
	# Las dos pestañas miden lo mismo; si no cabe todo, se desplaza con la rueda.
	menu_scroll = ScrollContainer.new()
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.add_child(menu_grid)
	parts[1].add_child(menu_scroll)


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
	_open_panel.visible = false
	_open_panel = null
	_locker = null
	Game.ui_open = false
	if not Game.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_panel() -> void:
	if _open_panel == menu_panel:
		_refresh_menu_grid()
	elif _open_panel == locker_panel:
		_refresh_locker()


func _refresh_inventory() -> void:
	var lines := PackedStringArray()
	for id in Game.inventory:
		lines.append("%s: %d" % [Game.RESOURCE_NAMES[id], Game.inventory[id]])
	if Game.has_drill:
		lines.append("Taladro mejorado")
	if Game.has_tank:
		lines.append("Tanque de oxígeno")
	if Game.has_jetpack:
		lines.append("Propulsores")
	inventory_label.text = "\n".join(lines)
	if _open_panel:
		_refresh_panel()


func _show_menu(tab: String) -> void:
	_tab = tab
	tab_buttons[tab].button_pressed = true
	var rows := ceili(maxf(_tab_kinds("fabricar").size(), _tab_kinds("construir").size()) / float(MENU_COLUMNS))
	var width := MENU_COLUMNS * (CELL_SIZE.x + 8)
	var height := minf(rows * (CELL_SIZE.y + 8), get_viewport().get_visible_rect().size.y - 140)
	menu_scroll.custom_minimum_size = Vector2(width, height)
	_show_panel(menu_panel)


func _select_tab(tab: String) -> void:
	if tab != _tab:
		Sfx.play("clic")
	_tab = tab
	tab_buttons[tab].button_pressed = true
	menu_scroll.scroll_vertical = 0
	_refresh_menu_grid()


## Lo que sale en una pestaña, en el orden de las recetas.
func _tab_kinds(tab: String) -> Array:
	var kinds := []
	for id in Game.RECIPES:
		if Game.is_placeable(id) == (tab == "construir"):
			kinds.append(id)
	return kinds


func _on_build_menu_requested() -> void:
	if not get_tree().paused and not Game.dead:
		_show_menu("construir")


func _on_icons_finished() -> void:
	if _open_panel == menu_panel:
		_refresh_menu_grid()


## Una casilla por receta de la pestaña: icono, nombre y coste. Las que faltan
## por desbloquear o no se pueden pagar salen apagadas.
func _refresh_menu_grid() -> void:
	for child in menu_grid.get_children():
		child.queue_free()
	for id in _tab_kinds(_tab):
		var recipe: Dictionary = Game.RECIPES[id]
		var unlocked := Game.is_unlocked(id)
		var owned := _owned(id)
		var button := Button.new()
		button.custom_minimum_size = CELL_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = not Game.can_craft(id) or (_driving and _tab == "construir")
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
		if not unlocked:
			icon.modulate = Color(0.2, 0.2, 0.2)
		elif button.disabled and not owned:
			icon.modulate = Color(1, 1, 1, 0.45)
		box.add_child(icon)
		var name_label := _small_label(recipe["name"], 13)
		box.add_child(name_label)
		var cost_text: String = Game.cost_text(recipe["cost"])
		var cost_color := Color(0.75, 0.75, 0.75)
		if not unlocked:
			cost_text = Game.STAGES[int(recipe["stage"])]["name"]
			cost_color = Color(0.9, 0.6, 0.3)
		elif owned:
			cost_text = "Ya lo tienes"
			cost_color = Color(0.55, 0.9, 0.55)
		var cost_label := _small_label(cost_text, 11)
		cost_label.add_theme_color_override("font_color", cost_color)
		box.add_child(cost_label)
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
		menu_grid.add_child(button)


## Las herramientas se fabrican una sola vez.
func _owned(id: String) -> bool:
	match id:
		"taladro":
			return Game.has_drill
		"tanque":
			return Game.has_tank
		"jetpack":
			return Game.has_jetpack
	return false


func _tooltip(id: String) -> String:
	var recipe: Dictionary = Game.RECIPES[id]
	var tip := "%s\n%s" % [recipe["name"], Game.cost_text(recipe["cost"])]
	match id:
		"taladro":
			tip += "\nRecoges el doble"
		"tanque":
			tip += "\nTu reserva de oxígeno sube a %d" % int(Game.TANK_O2_MAX)
		"jetpack":
			tip += "\nMantén Espacio en el aire para volar un poco"
		"botella":
			tip += "\nQ para respirar de ella"
		"semillas":
			tip += "\nSirven para plantar musgo, bancales y árboles"
		"guiso":
			tip += "\nF para comer: llena la barra entera"
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


## Lo fabricado va al inventario y el menú sigue abierto para hacer más;
## lo que se construye cierra el menú y empieza a colocarse.
func _on_item_pressed(id: String) -> void:
	if Game.is_placeable(id):
		_close_panel()
		# Colocar solo funciona en modo construir (al cambiar de modo se cancela).
		Game.set_tool_mode("construir")
	Game.craft(id)


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
	locker_title.text = "%s · %d / %d (E, Tab o Esc para cerrar)" % [locker_name, _locker.stored_total(), _locker.capacity()]
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
			locker_contents.add_child(_locker_row(id, stored, stored, false))


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
		amount = mini(amount, int(items.get(id, 0)))
		items[id] = int(items[id]) - amount
		if int(items[id]) <= 0:
			items.erase(id)
		Game.add_item(id, amount)
	Sfx.play("clic")


func _show_message(text: String) -> void:
	message_label.text = text
	message_timer = MESSAGE_TIME
