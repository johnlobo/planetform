extends Node
## Efectos de sonido y ambiente generados por código al arrancar, sin
## archivos de audio. Se carga como autoload con el nombre "Sfx".

const MIX_RATE := 22050
const PLAYERS := 8
const WIND_LENGTH := 6.0 # segundos del bucle de viento
# Volumen en lo más fuerte de una ráfaga.
const WIND_DB_DAY := -28.0
const WIND_DB_NIGHT := -22.0
# Ráfagas largas y suaves separadas por pausas muy largas de silencio.
const GUST_MIN := 8.0
const GUST_MAX := 16.0
const GUST_PAUSE_MIN := 25.0
const GUST_PAUSE_MAX := 60.0
const RAIN_LENGTH := 4.0 # segundos del bucle de lluvia
const RAIN_DB := -18.0 # volumen con la lluvia más fuerte, al aire libre
const RAIN_SHELTER_DB := -8.0 # cuánto baja dentro de la base

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _wind: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _gust_time := 0.0
var _gust_length := 0.0
var _gust_pause := 0.0
var _wind_level := 0.0 # volumen lineal actual del viento
var _rain: AudioStreamPlayer


func _ready() -> void:
	# Los sonidos de la interfaz deben oírse también con el juego en pausa.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	_sounds = {
		"paso": _step(),
		"recoger": _tones([660.0, 990.0], 0.07, 0.35),
		"craftear": _tones([523.0, 659.0, 784.0], 0.08, 0.3),
		"colocar": _thud(),
		"desmontar": _sweep(700.0, 220.0, 0.25, 0.3),
		"clic": _tones([880.0], 0.03, 0.2),
		"alarma": _tones([440.0, 0.0, 440.0], 0.12, 0.3),
		"muerte": _sweep(440.0, 110.0, 1.2, 0.4),
		"etapa": _tones([392.0, 523.0, 659.0, 784.0], 0.15, 0.3),
	}
	for i in PLAYERS:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_wind = AudioStreamPlayer.new()
	_wind.stream = _wind_loop()
	_wind.volume_db = linear_to_db(0.0001)
	# La primera ráfaga llega antes que las siguientes.
	_gust_pause = _rng.randf_range(5.0, 15.0)
	add_child(_wind)
	_wind.play()
	_rain = AudioStreamPlayer.new()
	_rain.stream = _rain_loop()
	_rain.volume_db = linear_to_db(0.0001)
	add_child(_rain)
	_rain.play()


func _process(delta: float) -> void:
	# El viento va a ráfagas de duración y separación al azar para que no
	# suene regular; de noche sopla más fuerte y con el juego en pausa se apaga.
	var target := 0.0
	if not get_tree().paused:
		if _gust_pause > 0.0:
			_gust_pause -= delta
			if _gust_pause <= 0.0:
				_gust_time = 0.0
				_gust_length = _rng.randf_range(GUST_MIN, GUST_MAX)
		else:
			_gust_time += delta
			if _gust_time >= _gust_length:
				_gust_pause = _rng.randf_range(GUST_PAUSE_MIN, GUST_PAUSE_MAX)
			else:
				var peak := db_to_linear(WIND_DB_NIGHT if Game.is_night() else WIND_DB_DAY)
				# Sube y baja despacio a lo largo de toda la ráfaga.
				target = peak * pow(sin(PI * _gust_time / _gust_length), 2.0)
	_wind_level = move_toward(_wind_level, target, 0.05 * delta)
	_wind.volume_db = linear_to_db(maxf(_wind_level, 0.0001))
	var rain := 0.0 if get_tree().paused else Game.rain()
	var rain_db := RAIN_DB + (RAIN_SHELTER_DB if Game.sheltered else 0.0)
	_rain.volume_db = linear_to_db(maxf(rain * db_to_linear(rain_db), 0.0001))


func _exit_tree() -> void:
	# Si el viento sigue sonando al cerrar, Godot avisa de recursos sin liberar.
	_wind.stop()
	_rain.stop()


## Reproduce un efecto por nombre; pitch_jitter varía el tono para que no canse.
func play(sound_name: String, pitch_jitter := 0.0, volume_db := 0.0) -> void:
	if not _sounds.has(sound_name):
		push_warning("Sonido desconocido: %s" % sound_name)
		return
	var player := _players[_next]
	_next = (_next + 1) % PLAYERS
	player.stream = _sounds[sound_name]
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = volume_db
	player.play()


func _make_stream(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size()
	return stream


## Notas seguidas de onda triangular; frecuencia 0 = silencio.
func _tones(freqs: Array, note_length: float, volume: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var n := int(note_length * MIX_RATE)
	for freq in freqs:
		if float(freq) == 0.0:
			# La onda triangular con frecuencia 0 vale 1 fijo: daría un golpe, no silencio.
			for i in n:
				samples.append(0.0)
			continue
		for i in n:
			var t := float(i) / MIX_RATE
			# Ataque corto y caída lineal para que no haga clic.
			var env := minf(1.0, i / 200.0) * (1.0 - float(i) / n)
			var phase := fmod(t * float(freq), 1.0)
			var tri := 4.0 * absf(phase - 0.5) - 1.0
			samples.append(tri * env * volume)
	return _make_stream(samples)


## Pisada sobre grava: ruido filtrado que se apaga rápido.
func _step() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var n := int(0.09 * MIX_RATE)
	var low := 0.0
	for i in n:
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.25)
		var env := pow(1.0 - float(i) / n, 3.0)
		samples.append(low * env * 0.18)
	return _make_stream(samples)


## Golpe grave al colocar una construcción.
func _thud() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var n := int(0.35 * MIX_RATE)
	var low := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := pow(1.0 - float(i) / n, 2.0)
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.1)
		samples.append((sin(TAU * 70.0 * t) * 0.6 + low * 0.5) * env * 0.6)
	return _make_stream(samples)


## Tono que baja de una frecuencia a otra.
func _sweep(from_hz: float, to_hz: float, length: float, volume: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var n := int(length * MIX_RATE)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += lerpf(from_hz, to_hz, k) / MIX_RATE
		samples.append(sin(TAU * phase) * (1.0 - k) * volume)
	return _make_stream(samples)


## Viento: ruido marrón con ráfagas lentas. El final se mezcla con el
## principio para que el bucle no se note.
func _wind_loop() -> AudioStreamWAV:
	var n := int(WIND_LENGTH * MIX_RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	# Ruido blanco suavizado: un siseo de aire. El ruido marrón de antes,
	# más grave, recordaba al oleaje.
	var hiss := 0.0
	for i in n:
		hiss = lerpf(hiss, _rng.randf_range(-1.0, 1.0), 0.15)
		raw[i] = hiss * 2.0
	var fade := int(0.5 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n - fade)
	for i in n - fade:
		samples[i] = raw[i]
		if i < fade:
			var k := float(i) / fade
			samples[i] = raw[i] * k + raw[n - fade + i] * (1.0 - k)
	return _make_stream(samples, true)


## Lluvia: siseo agudo continuo con gotas sueltas que golpean. El final se
## mezcla con el principio para que el bucle no se note.
func _rain_loop() -> AudioStreamWAV:
	var n := int(RAIN_LENGTH * MIX_RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var last := 0.0
	var drop := 0.0
	for i in n:
		# Ruido blanco menos su versión suavizada: solo quedan los agudos.
		var white := _rng.randf_range(-1.0, 1.0)
		last = lerpf(last, white, 0.3)
		if _rng.randf() < 0.002:
			drop = _rng.randf_range(0.4, 1.0)
		drop *= 0.995
		raw[i] = (white - last) * 0.5 + white * drop * 0.6
	var fade := int(0.5 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n - fade)
	for i in n - fade:
		samples[i] = raw[i]
		if i < fade:
			var k := float(i) / fade
			samples[i] = raw[i] * k + raw[n - fade + i] * (1.0 - k)
	return _make_stream(samples, true)
