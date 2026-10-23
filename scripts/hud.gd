extends CanvasLayer
## Interfaz: inventario, estado del planeta, oxígeno del jugador y menú de crafteo.

const MESSAGE_TIME := 4.0

var inventory_label: Label
var planet_label: Label
var oxygen_bar: ProgressBar
var hint_label: Label
var message_label: Label
var craft_panel: PanelContainer
var craft_list: VBoxContainer
var message_timer := 0.0


func _ready() -> void:
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

	var help := _label(Control.PRESET_BOTTOM_LEFT, Vector2(16, -40))
	help.text = "WASD mover · Espacio saltar · Clic recoger · Tab craftear · Q usar botella · Esc soltar ratón"

	var oxygen_box := VBoxContainer.new()
	oxygen_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	oxygen_box.position += Vector2(-150, -72)
	oxygen_box.custom_minimum_size = Vector2(300, 0)
	oxygen_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var oxygen_title := Label.new()
	oxygen_title.text = "Tu oxígeno"
	oxygen_box.add_child(oxygen_title)
	oxygen_bar = ProgressBar.new()
	oxygen_bar.max_value = Game.PLAYER_O2_MAX
	oxygen_bar.custom_minimum_size = Vector2(300, 20)
	oxygen_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oxygen_box.add_child(oxygen_bar)
	add_child(oxygen_box)

	_build_craft_panel()

	Game.inventory_changed.connect(_refresh_inventory)
	Game.message.connect(_show_message)
	_refresh_inventory()


func _input(event: InputEvent) -> void:
	# Se usa _input y no _unhandled_input porque los botones del menú
	# consumen la tecla Tab para mover el foco.
	if event.is_action_pressed("craft"):
		_toggle_craft()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	oxygen_bar.value = Game.player_oxygen
	hint_label.text = Game.hint
	planet_label.text = "Etapa: %s\nOxígeno: %.1f %%\nTemperatura: %.1f %%\nÍndice: %.1f %%\nEnergía: %d paneles / %d máquinas" % [
		Game.STAGES[Game.stage]["name"], Game.oxygen, Game.temperature,
		Game.terraform_index(), Game.panels, Game.generators + Game.heaters]
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
	title.text = "Crafteo (Tab para cerrar)"
	box.add_child(title)
	craft_list = VBoxContainer.new()
	box.add_child(craft_list)
	add_child(craft_panel)


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
		if recipe["kind"] == "building" and id != "panel":
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
