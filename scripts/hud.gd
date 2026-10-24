extends CanvasLayer
## Interfaz: inventario, estado del planeta, oxígeno del jugador y menú de crafteo.

const MESSAGE_TIME := 4.0
const DEATH_FADE_TIME := 3.0

var inventory_label: Label
var planet_label: Label
var oxygen_bar: ProgressBar
var warmth_bar: ProgressBar
var hint_label: Label
var message_label: Label
var craft_panel: PanelContainer
var craft_list: VBoxContainer
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

	var crosshair := _label(Control.PRESET_CENTER, Vector2(-4, -12))
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
	help.text = "WASD mover · Espacio saltar · Clic recoger · Tab craftear · Q usar botella\nH menú · Esc soltar ratón"

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
	add_child(oxygen_box)

	_build_craft_panel()
	_build_death_screen()

	Game.inventory_changed.connect(_refresh_inventory)
	Game.message.connect(_show_message)
	Game.player_died.connect(_on_player_died)
	_refresh_inventory()


func _input(event: InputEvent) -> void:
	# Se usa _input y no _unhandled_input porque los botones del menú
	# consumen la tecla Tab para mover el foco.
	if Game.dead:
		# Durante la muerte solo cuenta Enter, y solo cuando ya sale el game over.
		if _waiting_respawn and event.is_action_pressed("ui_accept"):
			_respawn()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("craft") and not get_tree().paused:
		_toggle_craft()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("release_mouse") and craft_panel.visible:
		_toggle_craft()
		get_viewport().set_input_as_handled()


## Se llama al abrir el menú: cierra el crafteo y oculta la interfaz.
func on_menu_opened() -> void:
	if craft_panel.visible:
		_toggle_craft()
	visible = false


func on_menu_closed() -> void:
	visible = true


func _process(delta: float) -> void:
	oxygen_bar.max_value = Game.player_o2_max()
	oxygen_bar.value = Game.player_oxygen
	warmth_bar.value = Game.warmth
	hint_label.text = Game.hint
	planet_label.text = Game.clock_text() + ("  (noche)" if Game.is_night() else "") + "\nEtapa: %s\nOxígeno: %.1f %%\nTemperatura: %.1f %%\nÍndice: %.1f %%\nEnergía: %d producida / %d necesaria" % [
		Game.STAGES[Game.stage]["name"], Game.oxygen, Game.temperature,
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


func _build_craft_panel() -> void:
	craft_panel = PanelContainer.new()
	craft_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	craft_panel.custom_minimum_size = Vector2(460, 0)
	craft_panel.position += Vector2(-230, -160)
	craft_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	craft_panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var title := Label.new()
	title.text = "Crafteo (Tab o Esc para cerrar)"
	box.add_child(title)
	craft_list = VBoxContainer.new()
	box.add_child(craft_list)
	add_child(craft_panel)


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
	if craft_panel.visible:
		_toggle_craft()
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


func _toggle_craft() -> void:
	craft_panel.visible = not craft_panel.visible
	Game.ui_open = craft_panel.visible
	if craft_panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh_craft_list()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_inventory() -> void:
	var lines := PackedStringArray()
	for id in Game.inventory:
		lines.append("%s: %d" % [Game.RESOURCE_NAMES[id], Game.inventory[id]])
	if Game.has_drill:
		lines.append("Taladro mejorado")
	if Game.has_tank:
		lines.append("Tanque de oxígeno")
	inventory_label.text = "\n".join(lines)
	if craft_panel and craft_panel.visible:
		_refresh_craft_list()


func _refresh_craft_list() -> void:
	for child in craft_list.get_children():
		child.queue_free()
	for id in Game.RECIPES:
		var recipe: Dictionary = Game.RECIPES[id]
		var cost: Dictionary = recipe["cost"]
		var parts := PackedStringArray()
		for res in cost:
			parts.append("%d %s" % [cost[res], String(Game.RESOURCE_NAMES[res]).to_lower()])
		var text := "%s · %s" % [recipe["name"], " + ".join(parts)]
		if recipe["kind"] == "building" and int(Game.MACHINES[id]["energy"]) < 0:
			text += " + energía"
		if not Game.is_unlocked(id):
			text = "%s (se desbloquea en %s)" % [recipe["name"], Game.STAGES[int(recipe["stage"])]["name"]]
		var button := Button.new()
		button.text = text
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not Game.can_craft(id)
		button.pressed.connect(_on_craft_pressed.bind(id))
		craft_list.add_child(button)


func _on_craft_pressed(id: String) -> void:
	if not Game.craft(id):
		return
	if Game.RECIPES[id]["kind"] == "building":
		# Se cierra el menú para que el jugador vea la construcción colocada.
		_toggle_craft()


func _show_message(text: String) -> void:
	message_label.text = text
	message_timer = MESSAGE_TIME
