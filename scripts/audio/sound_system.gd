class_name SoundSystem
extends Node
## Звуки и музыка без файлов: всё синтезируется при первом обращении и кэшируется.
## play(name, pos) — звук в мире (3D), play_ui(name) — без положения. Материалы блоков (шаги,
## добыча, установка) — по Blocks.sound_table. Нотный блок — 5 инструментов, как в оригинале.
## Фоновая музыка — спокойные фортепианные фразы раз в несколько минут, пластинки — свои мелодии.

const RATE := 22050
const POOL := 16

static var _cache: Dictionary = {}

var listener_pos := Vector3.ZERO
var volume := 1.0
var music_volume := 0.6
var _players: Array[AudioStreamPlayer3D] = []
var _ui: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()
var _music: AudioStreamPlayer
var _music_wait := 60.0
var _loops: Dictionary = {}
var _record: AudioStreamPlayer3D


func _ready() -> void:
	_rng.randomize()
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 48.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_players.append(p)
	for i in 4:
		var u := AudioStreamPlayer.new()
		add_child(u)
		_ui.append(u)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_record = AudioStreamPlayer3D.new()
	_record.unit_size = 12.0
	_record.max_distance = 64.0
	add_child(_record)


## Звук в точке мира. pitch — множитель высоты (1 — как есть).
func play(sound: String, pos: Vector3, vol := 1.0, pitch := 1.0) -> void:
	if volume <= 0.001 or pos.distance_to(listener_pos) > 48.0:
		return
	var stream := get_stream(sound)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = stream
	p.global_position = pos
	p.volume_db = linear_to_db(maxf(vol * volume, 0.0001))
	p.pitch_scale = pitch * _rng.randf_range(0.92, 1.08)
	p.play()


## Звук интерфейса (без положения).
func play_ui(sound: String, vol := 1.0, pitch := 1.0) -> void:
	if volume <= 0.001:
		return
	var stream := get_stream(sound)
	if stream == null:
		return
	for u in _ui:
		if not u.playing:
			u.stream = stream
			u.volume_db = linear_to_db(maxf(vol * volume, 0.0001))
			u.pitch_scale = pitch
			u.play()
			return


## Звук материала блока: kind — "step", "dig", "break", "place".
func play_block(kind: String, block_id: int, pos: Vector3) -> void:
	if block_id <= 0 or block_id >= Blocks.COUNT:
		return
	var mat := Blocks.sound_table[block_id]
	if mat == Blocks.SND_NONE:
		return
	var names := ["stone", "wood", "gravel", "grass", "sand", "glass", "cloth", "metal", "snow"]
	var m: String = names[mat] if mat < names.size() else "stone"
	if kind == "break" and m == "glass":
		play("glass_break", pos)
		return
	if m == "glass" or m == "metal":
		m = "stone"
	match kind:
		"step":
			play("step_" + m, pos, 0.35, 1.0)
		"dig":
			play("dig_" + m, pos, 0.45, 0.8)
		_:
			play("dig_" + m, pos, 0.9, 0.85 if kind == "break" else 0.95)


## Нотный блок: инструмент по блоку под ним, нота 0–24 (F♯3…F♯5).
func play_note(pos: Vector3, note: int, below_id: int) -> void:
	var inst := "harp"
	if below_id >= 0:
		var mat := Blocks.sound_table[below_id] if below_id < Blocks.COUNT else Blocks.SND_STONE
		match mat:
			Blocks.SND_STONE:
				inst = "bassdrum"
			Blocks.SND_SAND, Blocks.SND_GRAVEL:
				inst = "snare"
			Blocks.SND_GLASS:
				inst = "hat"
			Blocks.SND_WOOD:
				inst = "bass"
	play("note_" + inst, pos, 1.0, pow(2.0, (note - 12) / 12.0))


## Зацикленный звук (дождь, портал, огонь) с громкостью 0..1; 0 — остановить.
func set_loop(sound: String, vol: float, pos := Vector3.INF) -> void:
	var p: Node = _loops.get(sound)
	if vol <= 0.01:
		if p != null:
			p.call("stop")
		return
	if p == null:
		if pos == Vector3.INF:
			p = AudioStreamPlayer.new()
		else:
			var p3 := AudioStreamPlayer3D.new()
			p3.unit_size = 4.0
			p3.max_distance = 24.0
			p = p3
		add_child(p)
		_loops[sound] = p
		p.set("stream", get_stream(sound))
	if pos != Vector3.INF:
		(p as Node3D).global_position = pos
	p.set("volume_db", linear_to_db(maxf(vol * volume, 0.0001)))
	if not bool(p.get("playing")):
		p.call("play")


## Пластинка в проигрывателе: id предмета или 0 — остановить.
func play_record(record_id: int, pos: Vector3) -> void:
	if record_id <= 0:
		_record.stop()
		return
	_record.stream = _melody(record_id, 24.0, true)
	_record.global_position = pos
	_record.volume_db = linear_to_db(maxf(music_volume * 1.2, 0.0001))
	_record.play()


## Фоновая музыка: короткая фортепианная пьеса раз в 3–8 минут.
func update_music(delta: float) -> void:
	if music_volume <= 0.001 or _music.playing:
		return
	_music_wait -= delta
	if _music_wait > 0.0:
		return
	_music_wait = _rng.randf_range(180.0, 480.0)
	_music.stream = _melody(_rng.randi(), 40.0, false)
	_music.volume_db = linear_to_db(music_volume * 0.7)
	_music.play()


func stop_all() -> void:
	for p in _players:
		p.stop()
	for k: String in _loops:
		(_loops[k] as Node).call("stop")
	_music.stop()
	_record.stop()


# --- Синтез ----------------------------------------------------------------------

static func get_stream(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var data := _synth(sound)
	if data.is_empty():
		_cache[sound] = null
		return null
	var s := _to_stream(data, sound in ["rain", "portal_hum", "fire", "water_flow", "lava"])
	_cache[sound] = s
	return s


static func _to_stream(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


static func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * RATE))
	return b


## Шум, пропущенный через фильтр нижних частот (cut 0..1), с огибающей attack/decay.
static func _noise(sec: float, cut: float, attack: float, decay: float, gain := 0.8, sd := 1) -> PackedFloat32Array:
	var b := _buf(sec)
	var r := RandomNumberGenerator.new()
	r.seed = sd
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t / maxf(attack, 0.0001), 1.0) * exp(-t / maxf(decay, 0.0001))
		lp += (r.randf_range(-1.0, 1.0) - lp) * cut
		lp2 += (lp - lp2) * cut
		b[i] = lp2 * env * gain * (1.0 + (1.0 - cut) * 2.0)
	return b


static func _tone(sec: float, f0: float, f1: float, decay: float, gain := 0.6, harmonics := [1.0], attack := 0.005) -> PackedFloat32Array:
	var b := _buf(sec)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / sec)
		phase += TAU * f / RATE
		var v := 0.0
		for k in harmonics.size():
			v += sin(phase * (k + 1)) * float(harmonics[k])
		var env := minf(t / attack, 1.0) * exp(-t / decay)
		b[i] = v * env * gain
	return b


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset := 0, gain := 1.0) -> PackedFloat32Array:
	var out := a.duplicate()
	if out.size() < offset + b.size():
		out.resize(offset + b.size())
	for i in b.size():
		out[offset + i] += b[i] * gain
	return out


## Серия коротких щелчков-хрустов (шаги по гравию, еда).
static func _crunch(sec: float, hits: int, cut: float, sd: int, gain := 0.7) -> PackedFloat32Array:
	var out := _buf(sec)
	var r := RandomNumberGenerator.new()
	r.seed = sd
	for h in hits:
		var at := int(r.randf_range(0.0, sec * 0.7) * RATE)
		out = _mix(out, _noise(0.05, cut, 0.001, 0.012, gain, sd + h), at)
	return out


static func _synth(sound: String) -> PackedFloat32Array:
	match sound:
		"step_stone":
			return _noise(0.09, 0.55, 0.001, 0.025, 0.7, 3)
		"dig_stone":
			return _mix(_noise(0.16, 0.6, 0.001, 0.04, 0.8, 4), _tone(0.1, 900.0, 700.0, 0.02, 0.15))
		"step_wood":
			return _mix(_noise(0.1, 0.25, 0.001, 0.03, 0.6, 5), _tone(0.1, 210.0, 160.0, 0.035, 0.35, [1.0, 0.4]))
		"dig_wood":
			return _mix(_noise(0.18, 0.3, 0.001, 0.05, 0.7, 6), _tone(0.16, 180.0, 130.0, 0.05, 0.45, [1.0, 0.5, 0.2]))
		"step_gravel", "dig_gravel":
			return _crunch(0.2 if sound == "dig_gravel" else 0.12, 5, 0.45, 7)
		"step_grass", "dig_grass":
			return _noise(0.18 if sound == "dig_grass" else 0.12, 0.2, 0.01, 0.05, 0.6, 8)
		"step_sand", "dig_sand":
			return _noise(0.2, 0.7, 0.02, 0.05, 0.35, 9)
		"step_cloth", "dig_cloth":
			return _noise(0.12, 0.08, 0.01, 0.04, 0.6, 10)
		"step_snow", "dig_snow":
			return _crunch(0.15, 4, 0.25, 11, 0.5)
		"glass_break":
			var g := _noise(0.4, 0.8, 0.001, 0.08, 0.5, 12)
			var r := RandomNumberGenerator.new()
			r.seed = 13
			for k in 6:
				g = _mix(g, _tone(0.25, r.randf_range(2200.0, 4200.0), r.randf_range(2000.0, 4000.0), 0.06, 0.2), int(r.randf_range(0.0, 0.12) * RATE))
			return g
		"hurt":
			return _tone(0.28, 260.0, 150.0, 0.12, 0.55, [1.0, 0.6, 0.35, 0.2], 0.01)
		"mob_hurt":
			return _tone(0.22, 330.0, 200.0, 0.09, 0.45, [1.0, 0.5, 0.3], 0.01)
		"mob_death":
			return _mix(_tone(0.5, 280.0, 90.0, 0.25, 0.45, [1.0, 0.5, 0.3]), _noise(0.4, 0.2, 0.01, 0.15, 0.3, 14))
		"explode":
			return _mix(_noise(1.6, 0.06, 0.002, 0.45, 1.2, 15), _noise(0.5, 0.5, 0.001, 0.08, 0.6, 16))
		"thunder":
			return _mix(_noise(3.0, 0.03, 0.05, 1.0, 1.4, 17), _noise(0.4, 0.4, 0.001, 0.1, 0.7, 18))
		"pop":
			return _tone(0.08, 500.0, 1100.0, 0.04, 0.4)
		"orb":
			return _tone(0.25, 1700.0, 1900.0, 0.1, 0.25, [1.0, 0.3])
		"levelup":
			var l := _buf(0.9)
			var notes := [523.25, 659.25, 783.99, 1046.5]
			for k in notes.size():
				l = _mix(l, _tone(0.5, float(notes[k]), float(notes[k]), 0.2, 0.3, [1.0, 0.4, 0.2]), int(k * 0.09 * RATE))
			return l
		"click":
			return _mix(_noise(0.05, 0.9, 0.0005, 0.006, 0.6, 19), _tone(0.04, 1500.0, 1200.0, 0.008, 0.3))
		"door_open", "door_close":
			var creak := _tone(0.35, 160.0 if sound == "door_open" else 220.0, 240.0 if sound == "door_open" else 140.0, 0.12, 0.25, [1.0, 0.7, 0.5, 0.4, 0.3])
			return _mix(creak, _noise(0.15, 0.3, 0.001, 0.03, 0.6, 20), int((0.0 if sound == "door_open" else 0.22) * RATE))
		"chest_open", "chest_close":
			return _mix(_tone(0.3, 140.0, 110.0, 0.1, 0.35, [1.0, 0.6, 0.3]), _noise(0.2, 0.25, 0.001, 0.05, 0.5, 21))
		"eat":
			return _crunch(0.6, 9, 0.5, 22, 0.6)
		"burp":
			return _tone(0.35, 110.0, 90.0, 0.15, 0.5, [1.0, 0.8, 0.5, 0.3], 0.03)
		"drink":
			var d := _buf(0.6)
			for k in 4:
				d = _mix(d, _tone(0.1, 300.0, 600.0, 0.03, 0.35), int(k * 0.14 * RATE))
			return d
		"bow":
			return _mix(_tone(0.3, 330.0, 280.0, 0.07, 0.35, [1.0, 0.6, 0.4]), _noise(0.2, 0.5, 0.001, 0.03, 0.4, 23))
		"arrow_hit":
			return _noise(0.08, 0.5, 0.001, 0.015, 0.6, 24)
		"splash":
			return _noise(0.6, 0.45, 0.01, 0.15, 0.6, 25)
		"swim":
			return _noise(0.3, 0.3, 0.05, 0.08, 0.35, 26)
		"fuse", "creeper_fuse":
			return _noise(1.5, 0.85, 0.05, 1.5, 0.3, 27)
		"fizz":
			return _noise(0.5, 0.8, 0.005, 0.15, 0.4, 28)
		"fire", "lava":
			var f := _buf(2.0)
			var r := RandomNumberGenerator.new()
			r.seed = 29
			for k in 30:
				f = _mix(f, _noise(0.04, r.randf_range(0.3, 0.9), 0.001, 0.008, 0.5, 30 + k), int(r.randf_range(0.0, 1.95) * RATE))
			if sound == "lava":
				f = _mix(f, _noise(2.0, 0.04, 0.3, 4.0, 0.4, 61))
			return f
		"rain":
			return _noise(2.0, 0.35, 0.0, 100.0, 0.25, 31)
		"water_flow":
			return _noise(2.0, 0.12, 0.0, 100.0, 0.25, 32)
		"portal_hum":
			var b := _buf(2.0)
			for i in b.size():
				var t := float(i) / RATE
				b[i] = (sin(TAU * 55.0 * t) * 0.3 + sin(TAU * 82.5 * t + sin(TAU * 0.5 * t) * 3.0) * 0.2) * 0.6
			return b
		"portal_travel":
			return _mix(_tone(2.5, 80.0, 400.0, 1.5, 0.4, [1.0, 0.5, 0.3], 0.5), _noise(2.5, 0.2, 0.5, 1.2, 0.3, 33))
		"shear":
			return _mix(_noise(0.12, 0.9, 0.001, 0.02, 0.5, 34), _tone(0.1, 2500.0, 2000.0, 0.02, 0.15))
		"milk":
			return _noise(0.5, 0.3, 0.05, 0.2, 0.4, 35)
		"plop":
			return _tone(0.12, 400.0, 200.0, 0.04, 0.5)
		"note_harp":
			return _tone(1.2, 370.0, 370.0, 0.35, 0.5, [1.0, 0.35, 0.15, 0.08])
		"note_bass":
			return _tone(1.0, 92.5, 92.5, 0.3, 0.7, [1.0, 0.6, 0.3])
		"note_bassdrum":
			return _tone(0.4, 120.0, 45.0, 0.1, 0.9, [1.0, 0.3])
		"note_snare":
			return _noise(0.25, 0.7, 0.001, 0.06, 0.7, 36)
		"note_hat":
			return _noise(0.12, 0.95, 0.0005, 0.02, 0.5, 37)
		# Голоса существ — условные, но узнаваемые по характеру.
		"zombie":
			return _tone(0.9, 110.0, 85.0, 0.4, 0.45, [1.0, 0.8, 0.6, 0.4, 0.3], 0.1)
		"skeleton":
			return _crunch(0.4, 6, 0.8, 38, 0.5)
		"spider":
			return _noise(0.5, 0.6, 0.05, 0.15, 0.4, 39)
		"enderman":
			return _tone(1.0, 70.0, 60.0, 0.5, 0.5, [1.0, 0.0, 0.5, 0.0, 0.3], 0.05)
		"enderman_teleport":
			return _tone(0.5, 600.0, 120.0, 0.2, 0.4, [1.0, 0.5])
		"slime":
			return _tone(0.2, 220.0, 120.0, 0.06, 0.5, [1.0, 0.2])
		"ghast":
			return _tone(1.5, 600.0, 350.0, 0.7, 0.35, [1.0, 0.4, 0.2], 0.2)
		"ghast_shoot":
			return _mix(_noise(0.6, 0.2, 0.01, 0.2, 0.6, 40), _tone(0.4, 500.0, 200.0, 0.15, 0.3))
		"blaze":
			return _noise(1.0, 0.15, 0.2, 0.4, 0.5, 41)
		"pigman":
			return _tone(0.7, 150.0, 120.0, 0.3, 0.45, [1.0, 0.7, 0.5, 0.4], 0.05)
		"silverfish":
			return _noise(0.3, 0.9, 0.01, 0.08, 0.3, 42)
		"pig":
			return _mix(_tone(0.25, 260.0, 200.0, 0.08, 0.4, [1.0, 0.8, 0.6, 0.5]), _noise(0.25, 0.3, 0.01, 0.07, 0.3, 43))
		"cow":
			return _tone(1.1, 150.0, 120.0, 0.6, 0.5, [1.0, 0.7, 0.5, 0.3, 0.2], 0.08)
		"sheep":
			var sb := _tone(0.7, 330.0, 300.0, 0.35, 0.4, [1.0, 0.6, 0.4], 0.05)
			for i in sb.size():
				sb[i] *= 0.7 + 0.3 * sin(TAU * 18.0 * float(i) / RATE)
			return sb
		"chicken":
			var cb := _buf(0.5)
			for k in 3:
				cb = _mix(cb, _tone(0.09, 900.0, 1400.0, 0.03, 0.35, [1.0, 0.4]), int(k * 0.13 * RATE))
			return cb
		"wolf":
			return _mix(_tone(0.2, 450.0, 300.0, 0.06, 0.5, [1.0, 0.6, 0.3]), _noise(0.2, 0.4, 0.002, 0.05, 0.4, 44))
		"wolf_growl":
			return _tone(0.8, 90.0, 80.0, 0.4, 0.4, [1.0, 0.9, 0.7, 0.5], 0.05)
		"cat":
			return _tone(0.5, 500.0, 800.0, 0.2, 0.35, [1.0, 0.5, 0.3], 0.03)
		"villager":
			return _tone(0.4, 180.0, 160.0, 0.18, 0.4, [1.0, 0.8, 0.5, 0.3], 0.03)
		"golem":
			return _mix(_noise(0.3, 0.2, 0.001, 0.08, 0.7, 45), _tone(0.3, 80.0, 60.0, 0.1, 0.5, [1.0, 0.5]))
		"snow_golem":
			return _crunch(0.3, 5, 0.25, 46, 0.5)
		"dragon":
			return _mix(_tone(2.0, 70.0, 50.0, 0.9, 0.6, [1.0, 0.8, 0.6, 0.5, 0.4], 0.2), _noise(2.0, 0.08, 0.3, 0.8, 0.5, 47))
		"dragon_wings":
			return _noise(0.6, 0.06, 0.1, 0.2, 0.8, 48)
	return PackedFloat32Array()


## Мелодия: пентатоника, «фортепиано» с затуханием. seed определяет пьесу.
static func _melody(sd: int, sec: float, lively: bool) -> AudioStreamWAV:
	var key := "melody_%d_%d" % [sd, int(lively)]
	if _cache.has(key):
		return _cache[key]
	var r := RandomNumberGenerator.new()
	r.seed = sd
	var steps := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]
	var base := 220.0 * pow(2.0, r.randi_range(-3, 3) / 12.0)
	var out := _buf(sec)
	var t := 0.5
	var beat := r.randf_range(0.28, 0.4) if lively else r.randf_range(0.6, 1.1)
	var idx := r.randi_range(2, 6)
	while t < sec - 2.0:
		idx = clampi(idx + r.randi_range(-2, 2), 0, steps.size() - 1)
		var f := base * pow(2.0, int(steps[idx]) / 12.0)
		out = _mix(out, _tone(1.8, f, f, 0.6, 0.18, [1.0, 0.4, 0.15, 0.05], 0.004), int(t * RATE))
		if r.randf() < 0.35:
			var f2 := f * pow(2.0, -12.0 / 12.0)
			out = _mix(out, _tone(2.0, f2, f2, 0.8, 0.12, [1.0, 0.3]), int(t * RATE))
		t += beat * (2.0 if r.randf() < 0.2 else 1.0)
	var s := _to_stream(out, false)
	_cache[key] = s
	return s
