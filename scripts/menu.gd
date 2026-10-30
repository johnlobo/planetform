extends CanvasLayer
## Menú principal al arrancar y menú de pausa (Esc) durante la partida.

signal opened
signal closed

var _title: Label
var _subtitle: Label
var _continue_button: Button
var _new_button: Button
var _quit_button: Button
var _box: VBoxContainer
# true en la pantalla de título; false en el menú de pausa.
var _is_title := false
var _has_save := false
# Nueva partida pide un segundo clic si hay progreso que se perdería.
var _confirming_new := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.02, 0.05, 0.6)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.custom_minimum_size.x = 320
	_box.add_theme_constant_override("separation", 12)
	center.add_child(_box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 8)
	_box.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	_box.add_child(_subtitle)

	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	_box.add_child(gap)

	_continue_button = _button(_on_continue_pressed)
	_new_button = _button(_on_new_pressed)
	_quit_button = _button(_on_quit_pressed)
	_quit_button.text = "Salir"
	# En el navegador no se puede cerrar la pestaña desde el juego.
	_quit_button.visible = not OS.has_feature("web")
	visible = false


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or Game.dead or _is_title:
		return
	# Con un panel abierto o colocando algo, Esc solo cierra eso: lo hacen
	# el HUD y el colocador, que reciben el evento después.
	if not visible and (Game.ui_open or Game.placing):
		return
	if visible:
		_close()
	else:
		open_pause()
	get_viewport().set_input_as_handled()


## Pantalla de título; has_save indica si hay una partida guardada que continuar.
func open_title(has_save: bool) -> void:
	_is_title = true
	_has_save = has_save
	_title.text = "PlanetForm"
	_subtitle.text = "Convierte una roca muerta en un planeta habitable"
	_continue_button.text = "Continuar partida" if has_save else "Jugar"
	_new_button.visible = has_save
	_open()


func open_pause() -> void:
	_is_title = false
	_has_save = true
	_title.text = "Pausa"
	_subtitle.text = "Esc para volver a la partida"
	_continue_button.text = "Continuar"
	_new_button.visible = true
	_open()


func _open() -> void:
	_confirming_new = false
	_new_button.text = "Nueva partida"
	visible = true
	get_tree().paused = true
	Game.in_title = _is_title
	# Primero se avisa al HUD: al cerrar su menú vuelve a capturar el ratón.
	opened.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_continue_button.grab_focus()


func _close() -> void:
	visible = false
	_is_title = false
	Game.in_title = false
	get_tree().paused = false
	# En el navegador el ratón solo se captura con un clic dentro del juego.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.has_feature("web") else Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _button(callback: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(320, 48)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(Sfx.play.bind("clic"))
	button.pressed.connect(callback)
	_box.add_child(button)
	return button


func _on_continue_pressed() -> void:
	var was_title := _is_title
	_close()
	if was_title and _has_save:
		Game.message.emit("Partida cargada.")


func _on_new_pressed() -> void:
	if not _confirming_new:
		_confirming_new = true
		_new_button.text = "¿Seguro? Se borra la partida actual"
		return
	Game.new_game()


func _on_quit_pressed() -> void:
	Game.save_game()
	get_tree().quit()
