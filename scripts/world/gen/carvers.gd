class_name Carvers
extends RefCounted
## Пещеры и ущелья, как MapGenCaves/MapGenRavine в 1.2: «черви»-туннели с ответвлениями и
## залами, стартующие в соседних чанках. Каждый чанк заново проходит все туннели, которые могут
## до него дотянуться (их путь задаётся сидом чанка-источника), и вырезает только свою часть —
## поэтому пещеры непрерывны на границах и не зависят от порядка генерации.
## Радиус и длина туннелей меньше оригинала (5 чанков вместо 8, туннели 48–64 шага вместо 84–112),
## а пещеры чуть чаще (1/12 чанков вместо 1/15), чтобы уложиться в бюджет времени.

const CAVE_RANGE := 5
## Наибольшая «ширина» туннеля (в оригинале изредка до 12 — огромные дорогие полости).
const MAX_WIDTH := 6.0
const RAVINE_RANGE := 8
## Ниже этой высоты пещеры заливаются лавой.
const LAVA_LEVEL := 10

var seed_value := 0
var _buf: GenChunk
## Центр текущего чанка (для отсечения туннелей, которые до него не дотянутся).
var _ccx := 0.0
var _ccz := 0.0
## Минимальная высота поверхности в чанке: глубже воды быть не может.
var _min_surface := 0
var _rng := RandomNumberGenerator.new()
## Множители ширины ущелья по высоте (рваные стены).
var _ravine_rs := PackedFloat32Array()


func _init(p_seed: int) -> void:
	seed_value = p_seed
	_ravine_rs.resize(128)


func begin(buf: GenChunk, min_surface: int) -> void:
	_buf = buf
	_ccx = buf.ox + 8.0
	_ccz = buf.oz + 8.0
	_min_surface = min_surface


static func _ri(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 0:
		return 0
	return int(rng.randi() % n)


## Пещеры от чанков-источников с dz из [dz0, dz1] (работу можно разбить на части).
func caves(dz0: int, dz1: int) -> void:
	var rng := _rng
	for dz in range(dz0, dz1 + 1):
		for dx in range(-CAVE_RANGE, CAVE_RANGE + 1):
			var ocx := _buf.cx + dx
			var ocz := _buf.cz + dz
			rng.seed = WorldGen.hash3(ocx, 4401, ocz, seed_value) * 7919 + ocx * 31 + ocz
			var n := _ri(rng, _ri(rng, _ri(rng, 40) + 1) + 1)
			if _ri(rng, 12) != 0:
				continue
			for i in n:
				var x := float(ocx * 16 + _ri(rng, 16))
				var y := float(_ri(rng, _ri(rng, 120) + 8))
				var z := float(ocz * 16 + _ri(rng, 16))
				var tunnels := 1
				if _ri(rng, 4) == 0:
					_tunnel(int(rng.randi()), x, y, z, 1.0 + rng.randf() * 6.0, 0.0, 0.0, -1, -1, 0.5)
					tunnels += _ri(rng, 4)
				for j in tunnels:
					var yaw := rng.randf() * TAU
					var pitch := (rng.randf() - 0.5) * 2.0 / 8.0
					var width := rng.randf() * 2.0 + rng.randf()
					if _ri(rng, 10) == 0:
						width = minf(width * (rng.randf() * rng.randf() * 3.0 + 1.0), MAX_WIDTH)
					_tunnel(int(rng.randi()), x, y, z, width, yaw, pitch, 0, 0, 1.0)


func _tunnel(s: int, x: float, y: float, z: float, width: float, yaw: float, pitch: float,
		step: int, length: int, vscale: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var dyaw := 0.0
	var dpitch := 0.0
	if length <= 0:
		var mx := CAVE_RANGE * 16 - 16
		@warning_ignore("integer_division")
		length = mx - _ri(rng, mx / 4)
	var room := false
	if step == -1:
		@warning_ignore("integer_division")
		step = length / 2
		room = true
	@warning_ignore("integer_division")
	var branch_at := _ri(rng, length / 2) + length / 4
	var steep := _ri(rng, 6) == 0
	# Туннель (со всеми ответвлениями) не может отойти дальше оставшейся длины.
	var sdx := x - _ccx
	var sdz := z - _ccz
	var reach := float(length - step) + width + 2.0 + 16.0 + 1.5
	if sdx * sdx + sdz * sdz > reach * reach:
		return
	while step < length:
		var rh := 1.5 + sin(step * PI / length) * width
		var rv := rh * vscale
		var cp := cos(pitch)
		x += cos(yaw) * cp
		y += sin(pitch)
		z += sin(yaw) * cp
		pitch *= 0.92 if steep else 0.7
		pitch += dpitch * 0.1
		yaw += dyaw * 0.1
		dpitch *= 0.9
		dyaw *= 0.75
		dpitch += (rng.randf() - rng.randf()) * rng.randf() * 2.0
		dyaw += (rng.randf() - rng.randf()) * rng.randf() * 4.0
		if not room and step == branch_at and width > 1.0:
			_tunnel(int(rng.randi()), x, y, z, rng.randf() * 0.5 + 0.5, yaw - PI * 0.5, pitch / 3.0, step, length, 1.0)
			_tunnel(int(rng.randi()), x, y, z, rng.randf() * 0.5 + 0.5, yaw + PI * 0.5, pitch / 3.0, step, length, 1.0)
			return
		if room or _ri(rng, 4) != 0:
			var ddx := x - _ccx
			var ddz := z - _ccz
			var rem := float(length - step)
			var maxr := width + 2.0 + 16.0
			if ddx * ddx + ddz * ddz - rem * rem > maxr * maxr:
				return
			if x >= _ccx - 16.0 - rh * 2.0 and z >= _ccz - 16.0 - rh * 2.0 and x <= _ccx + 16.0 + rh * 2.0 and z <= _ccz + 16.0 + rh * 2.0:
				_carve(x, y, z, rh, rv, -0.7, false)
				if room:
					return
		step += 1


## Вырезает эллипсоид (центр — мировые координаты). floor_cut — нижняя граница по нормированной
## высоте (у пещер −0,7: плоский пол). Не трогает воду: если она рядом, шаг пропускается.
## Для каждой колонки диапазон высот считается сразу, без проверки каждого блока.
func _carve(x: float, y: float, z: float, rh: float, rv: float, floor_cut: float, ravine: bool) -> void:
	var ox := _buf.ox
	var oz := _buf.oz
	var x0 := maxi(floori(x - rh) - ox - 1, 0)
	var x1 := mini(floori(x + rh) - ox + 1, 16)
	var y0 := maxi(floori(y - rv) - 1, 1)
	var y1 := mini(floori(y + rv) + 1, 120)
	var z0 := maxi(floori(z - rh) - oz - 1, 0)
	var z1 := mini(floori(z + rh) - oz + 1, 16)
	if x0 >= x1 or z0 >= z1 or y0 >= y1:
		return
	var data := _buf.blocks
	# Вода (океан, реки) может быть только выше самой низкой поверхности чанка.
	if y1 + 1 >= _min_surface:
		for yy in range(maxi(y0 - 1, _min_surface - 2), mini(y1 + 1, 255)):
			for zz in range(z0, z1):
				var row := (zz << 4) + (yy << 8)
				for xx in range(x0, x1):
					var b := data[row + xx]
					if b == Blocks.WATER or b == Blocks.FLOWING_WATER:
						return
	for zz in range(z0, z1):
		var nz := (zz + oz + 0.5 - z) / rh
		for xx in range(x0, x1):
			var nx := (xx + ox + 0.5 - x) / rh
			var hd := nx * nx + nz * nz
			if hd >= 1.0:
				continue
			# Диапазон высот колонки: |ny| < sqrt(1 − hd) (у ущелий — с запасом, дальше точная проверка).
			var span := sqrt((1.0 - hd) * (6.0 if ravine else 1.0)) * rv
			var lo := y - span - 0.5
			if not ravine:
				lo = maxf(lo, y + floor_cut * rv - 0.5)
			var ya := maxi(ceili(lo), y0)
			var yb := mini(floori(y + span - 0.5), y1 - 1)
			if ya > yb:
				continue
			var col := xx + (zz << 4)
			var grass := false
			for yy in range(yb, ya - 1, -1):
				if ravine:
					var ny := (yy + 0.5 - y) / rv
					if hd * _ravine_rs[yy] + ny * ny / 6.0 >= 1.0:
						continue
				var i := col + (yy << 8)
				var b := data[i]
				if b == Blocks.GRASS:
					grass = true
				if b == Blocks.STONE or b == Blocks.DIRT or b == Blocks.GRASS or b == Blocks.SANDSTONE:
					if yy < LAVA_LEVEL:
						data[i] = Blocks.LAVA
					else:
						data[i] = Blocks.AIR
						if grass and data[i - 256] == Blocks.DIRT:
							data[i - 256] = Blocks.GRASS


## Ущелья (1 на ~50 чанков), длинные и глубокие.
func ravines() -> void:
	var rng := _rng
	for dz in range(-RAVINE_RANGE, RAVINE_RANGE + 1):
		for dx in range(-RAVINE_RANGE, RAVINE_RANGE + 1):
			var ocx := _buf.cx + dx
			var ocz := _buf.cz + dz
			rng.seed = WorldGen.hash3(ocx, 4402, ocz, seed_value) * 6007 + ocx * 17 + ocz
			if _ri(rng, 50) != 0:
				continue
			var x := float(ocx * 16 + _ri(rng, 16))
			var y := float(_ri(rng, _ri(rng, 40) + 8) + 20)
			var z := float(ocz * 16 + _ri(rng, 16))
			var yaw := rng.randf() * TAU
			var pitch := (rng.randf() - 0.5) * 2.0 / 8.0
			var width := (rng.randf() * 2.0 + rng.randf()) * 2.0
			_ravine(int(rng.randi()), x, y, z, width, yaw, pitch, 3.0)


func _ravine(s: int, x: float, y: float, z: float, width: float, yaw: float, pitch: float, vscale: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var dyaw := 0.0
	var dpitch := 0.0
	var mx := RAVINE_RANGE * 16 - 16
	@warning_ignore("integer_division")
	var length := mx - _ri(rng, mx / 4)
	var f := 1.0
	for i in 128:
		if i == 0 or _ri(rng, 3) == 0:
			f = 1.0 + rng.randf() * rng.randf()
		_ravine_rs[i] = f * f
	for step in length:
		var rh := 1.5 + sin(step * PI / length) * width
		var rv := rh * vscale
		rh *= rng.randf() * 0.25 + 0.75
		rv *= rng.randf() * 0.25 + 0.75
		var cp := cos(pitch)
		x += cos(yaw) * cp
		y += sin(pitch)
		z += sin(yaw) * cp
		pitch *= 0.7
		pitch += dpitch * 0.05
		yaw += dyaw * 0.05
		dpitch *= 0.8
		dyaw *= 0.5
		dpitch += (rng.randf() - rng.randf()) * rng.randf() * 2.0
		dyaw += (rng.randf() - rng.randf()) * rng.randf() * 4.0
		if _ri(rng, 4) == 0:
			continue
		var ddx := x - _ccx
		var ddz := z - _ccz
		var rem := float(length - step)
		var maxr := width + 2.0 + 16.0
		if ddx * ddx + ddz * ddz - rem * rem > maxr * maxr:
			return
		if x >= _ccx - 16.0 - rh * 2.0 and z >= _ccz - 16.0 - rh * 2.0 and x <= _ccx + 16.0 + rh * 2.0 and z <= _ccz + 16.0 + rh * 2.0:
			_carve(x, y, z, rh, rv, -1.0, true)
