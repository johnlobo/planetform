extends CanvasLayer
## Contador de rendimiento: F3 lo muestra y lo esconde.

var _label: Label
var _timer := 0.0
var _frame_ms := 16.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_label = Label.new()
	_label.position = Vector2(8, 8)
	_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		_timer = 0.0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.1)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	var land = get_parent().get("land")
	var text := "%d FPS  %.1f ms por fotograma\n" % [Engine.get_frames_per_second(), _frame_ms]
	text += "Llamadas de dibujo: %d  (triángulos: %dk)\n" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000]
	if land:
		text += "Trozos cargados: %d  (último: %.1f ms)" % [land.loaded_chunks, land.last_chunk_ms]
	_label.text = text
