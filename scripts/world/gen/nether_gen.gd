class_name NetherGen
extends RefCounted
## Нижний мир 1.2 (как ChunkProviderHell): высота 128, незерак по трёхмерной плотности — толстые
## пол и потолок, пещеры и колонны между ними; лавовое море до y = 31; песок душ и гравий у уровня
## моря; светокамень гроздьями на потолке, огонь, грибы; крепости из адского кирпича: мосты,
## коридоры, площадка с рассадником ифритов и комната с адским наростом.
## Интерфейс как у WorldGen: generate_chunk / begin_chunk + fill_rows(этапы 0–15) + finish_chunk.

const HEIGHT := 128
const LAVA_LEVEL := 31
const LEVELS := 17
## Крепости: одна на область 28×28 чанков (с вероятностью), в области (0, 0) — всегда.
const REGION := 28 * 16
const DECK_Y := 64
const ARM := 44

var seed_value := 0
var _noise := FastNoiseLite.new()
var _patch := FastNoiseLite.new()
var buf: GenChunk
var _cols: Array[PackedFloat32Array] = []
var _rng := RandomNumberGenerator.new()


func _init(p_seed: int) -> void:
	seed_value = p_seed
	_noise.seed = p_seed + 101
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0 / 46.0
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_patch.seed = p_seed + 102
	_patch.frequency = 1.0 / 24.0


# --- Плотность -----------------------------------------------------------------

## 17 значений плотности колонки сетки (gx, gz) — точка (4·gx, 4·gz), уровни через 8 блоков.
func grid_column(gx: int, gz: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(LEVELS)
	var wx := float(gx * 4)
	var wz := float(gz * 4)
	for k in LEVELS:
		var y := float(k * 8)
		var d := _noise.get_noise_3d(wx, y * 1.6, wz) * 26.0 - 6.0
		# Толстые пол и потолок, пустота между ними.
		if y < 36.0:
			d += (36.0 - y) * 0.9
		if y > 96.0:
			d += (y - 96.0) * 1.1
		out[k] = d
	return out


func _column(wx: int, wz: int) -> PackedFloat32Array:
	var gx := wx >> 2
	var gz := wz >> 2
	var a := grid_column(gx, gz)
	var b := grid_column(gx + 1, gz)
	var c := grid_column(gx, gz + 1)
	var e := grid_column(gx + 1, gz + 1)
	var fx := (wx & 3) * 0.25
	var fz := (wz & 3) * 0.25
	var out := PackedFloat32Array()
	out.resize(LEVELS)
	for k in LEVELS:
		var p := a[k] + (b[k] - a[k]) * fx
		var q := c[k] + (e[k] - c[k]) * fx
		out[k] = p + (q - p) * fz
	return out


static func _solid_at(d: PackedFloat32Array, y: int) -> bool:
	var k := y >> 3
	if k >= LEVELS - 1:
		return d[LEVELS - 1] > 0.0
	return d[k] + (d[k + 1] - d[k]) * ((y & 7) * 0.125) > 0.0


## Высота пола: верхний твёрдый блок под первой пустотой выше лавового моря.
func get_height(wx: int, wz: int) -> int:
	var d := _column(wx, wz)
	for y in range(LAVA_LEVEL + 1, 110):
		if _solid_at(d, y) and not _solid_at(d, y + 1) and not _solid_at(d, y + 2):
			return y
	return LAVA_LEVEL


func biome_at(_wx: int, _wz: int) -> int:
	return Biomes.HELL


func find_spawn_column() -> Vector2i:
	for r in range(0, 200, 8):
		for k in 8:
			var a := TAU * k / 8.0
			var x := int(cos(a) * r)
			var z := int(sin(a) * r)
			if get_height(x, z) > LAVA_LEVEL + 2:
				return Vector2i(x, z)
	return Vector2i.ZERO


# --- Чанк ------------------------------------------------------------------------

func generate_chunk(cx: int, cz: int) -> Dictionary:
	begin_chunk(cx, cz)
	fill_rows(0, 16)
	return finish_chunk()


func begin_chunk(cx: int, cz: int) -> void:
	buf = GenChunk.new()
	buf.setup(cx, cz)
	_cols = []
	_cols.resize(25)
	_rng.seed = WorldGen.hash3(cx, 17, cz, seed_value)


func fill_rows(z0: int, z1: int) -> void:
	for s in range(z0, z1):
		_stage(s)


func _stage(s: int) -> void:
	if s < 4:
		_terrain_rows(s * 4, s * 4 + 4)
		return
	match s:
		4:
			_surface()
		5, 6:
			_glowstone(5)
		7:
			_fire_and_mushrooms()
		8, 9, 10, 11:
			_fortress(s - 8)
		12:
			_lava_springs()


func finish_chunk() -> Dictionary:
	var biomes := PackedByteArray()
	biomes.resize(256)
	biomes.fill(Biomes.HELL)
	var out := {"blocks": buf.blocks, "meta": buf.meta, "biomes": biomes, "block_entities": buf.block_entities,
		"entities": buf.entities, "springs": buf.springs}
	buf = null
	_cols = []
	return out


## Лавопады (WorldGenHellLava в 1.2): 8 попыток на чанк — незерак сверху, четыре незерака среди
## соседей по сторонам и снизу и одна открытая сторона.
func _lava_springs() -> void:
	_rng.seed = WorldGen.hash3(buf.cx, 91, buf.cz, seed_value)
	var data := buf.blocks
	for t in 8:
		var lx := 1 + _rng.randi_range(0, 13)
		var lz := 1 + _rng.randi_range(0, 13)
		var y := 4 + _rng.randi_range(0, 119)
		var i := lx + (lz << 4) + (y << 8)
		if data[i + 256] != Blocks.NETHERRACK:
			continue
		if data[i] != Blocks.AIR and data[i] != Blocks.NETHERRACK:
			continue
		var rack := 0
		var air := 0
		for n: int in [i - 1, i + 1, i - 16, i + 16, i - 256]:
			if data[n] == Blocks.NETHERRACK:
				rack += 1
			elif data[n] == Blocks.AIR:
				air += 1
		if rack == 4 and air == 1:
			data[i] = Blocks.FLOWING_LAVA
			buf.meta[i] = 0
			buf.springs.append(i)


func _terrain_rows(z0: int, z1: int) -> void:
	var data := buf.blocks
	var gx0 := buf.cx * 4
	var gz0 := buf.cz * 4
	var dens := PackedFloat32Array()
	dens.resize(LEVELS)
	for z in range(z0, z1):
		var gj := z >> 2
		for gi in 5:
			for dj in 2:
				var ci := gi + (gj + dj) * 5
				if _cols[ci].is_empty():
					_cols[ci] = grid_column(gx0 + gi, gz0 + gj + dj)
		var fz := (z & 3) * 0.25
		for x in 16:
			var gi := x >> 2
			var fx := (x & 3) * 0.25
			var a := _cols[gi + gj * 5]
			var b := _cols[gi + 1 + gj * 5]
			var c := _cols[gi + (gj + 1) * 5]
			var e := _cols[gi + 1 + (gj + 1) * 5]
			for k in LEVELS:
				var p := a[k] + (b[k] - a[k]) * fx
				var q := c[k] + (e[k] - c[k]) * fx
				dens[k] = p + (q - p) * fz
			var col := x + (z << 4)
			for k in LEVELS - 1:
				var d0 := dens[k]
				var d1 := dens[k + 1]
				var y0 := k * 8
				if d0 > 0.0 and d1 > 0.0:
					for y in range(y0, y0 + 8):
						data[col + (y << 8)] = Blocks.NETHERRACK
					continue
				for j in 8:
					var y := y0 + j
					if d0 + (d1 - d0) * (j * 0.125) > 0.0:
						data[col + (y << 8)] = Blocks.NETHERRACK
					elif y <= LAVA_LEVEL:
						data[col + (y << 8)] = Blocks.LAVA
			# Коренная порода снизу и сверху (y 0 и 127 — всегда, рядом — всё реже).
			var h := WorldGen.hash3(buf.ox + x, 5, buf.oz + z, seed_value)
			data[col] = Blocks.BEDROCK
			data[col + ((HEIGHT - 1) << 8)] = Blocks.BEDROCK
			for k in range(1, 5):
				if ((h >> (k * 3)) & 7) < 5 - k:
					data[col + (k << 8)] = Blocks.BEDROCK
				if ((h >> (k * 3 + 12)) & 7) < 5 - k:
					data[col + ((HEIGHT - 1 - k) << 8)] = Blocks.BEDROCK


## Песок душ и гравий у «уровня моря» (около y = 64), как в 1.2.
func _surface() -> void:
	var data := buf.blocks
	for z in 16:
		for x in 16:
			var wx := buf.ox + x
			var wz := buf.oz + z
			var n := _patch.get_noise_2d(wx, wz)
			var g := _patch.get_noise_2d(wx + 500.0, wz - 300.0)
			if n < 0.25 and g < 0.35:
				continue
			var col := x + (z << 4)
			for y in range(60, 70):
				var i := col + (y << 8)
				if data[i] == Blocks.NETHERRACK and data[i + 256] == Blocks.AIR:
					var id := Blocks.SOUL_SAND if n >= 0.25 else Blocks.GRAVEL
					for k in 3:
						if y - k > 0 and data[i - (k << 8)] == Blocks.NETHERRACK:
							data[i - (k << 8)] = id
					break


## Светокамень: гроздья, свисающие с потолка (WorldGenGlowStone1).
func _glowstone(count: int) -> void:
	for t in count:
		var x := buf.ox + 3 + _rng.randi_range(0, 9)
		var z := buf.oz + 3 + _rng.randi_range(0, 9)
		var y := _rng.randi_range(40, 120)
		# Подходящее место: воздух под незераком.
		var ok := false
		for k in 24:
			if buf.get_b(x, y, z) == Blocks.AIR and buf.get_b(x, y + 1, z) == Blocks.NETHERRACK:
				ok = true
				break
			y -= 1
			if y < 33:
				break
		if not ok:
			continue
		buf.set_b(x, y, z, Blocks.GLOWSTONE)
		for i in 180:
			var px := x + _rng.randi_range(0, 7) - _rng.randi_range(0, 7)
			var py := y - _rng.randi_range(0, 10)
			var pz := z + _rng.randi_range(0, 7) - _rng.randi_range(0, 7)
			if buf.get_b(px, py, pz) != Blocks.AIR:
				continue
			var n := 0
			for d in 6:
				var v: Vector3i = Blocks.FACE_VEC[d]
				if buf.get_b(px + v.x, py + v.y, pz + v.z) == Blocks.GLOWSTONE:
					n += 1
			if n == 1:
				buf.set_b(px, py, pz, Blocks.GLOWSTONE)


## Огонь на незераке и редкие грибы.
func _fire_and_mushrooms() -> void:
	var fires := _rng.randi_range(0, _rng.randi_range(0, 9)) + 1
	for t in fires:
		var cx := buf.ox + _rng.randi_range(0, 15)
		var cz := buf.oz + _rng.randi_range(0, 15)
		var cy := _rng.randi_range(33, 100)
		for k in 48:
			var x := cx + _rng.randi_range(0, 7) - _rng.randi_range(0, 7)
			var y := cy + _rng.randi_range(0, 3) - _rng.randi_range(0, 3)
			var z := cz + _rng.randi_range(0, 7) - _rng.randi_range(0, 7)
			if buf.get_b(x, y, z) == Blocks.AIR and buf.get_b(x, y - 1, z) == Blocks.NETHERRACK:
				buf.set_b(x, y, z, Blocks.FIRE)
	for id: int in [Blocks.BROWN_MUSHROOM, Blocks.RED_MUSHROOM]:
		if _rng.randi_range(0, 1) == 0:
			continue
		var x := buf.ox + _rng.randi_range(0, 15)
		var z := buf.oz + _rng.randi_range(0, 15)
		for y in range(100, 32, -1):
			if buf.get_b(x, y, z) == Blocks.AIR and buf.get_b(x, y - 1, z) == Blocks.NETHERRACK:
				buf.set_b(x, y, z, id)
				break


# --- Крепость --------------------------------------------------------------------

## Центр крепости области (rx, rz) или (1 << 30, 0).
func fortress_center(rx: int, rz: int) -> Vector2i:
	var h := WorldGen.hash3(rx, 33, rz, seed_value)
	if (rx != 0 or rz != 0) and h % 3 == 0:
		return Vector2i(1 << 30, 0)
	var ox := rx * REGION + 96 + ((h >> 4) % (REGION - 192))
	var oz := rz * REGION + 96 + ((h >> 14) % (REGION - 192))
	if rx == 0 and rz == 0:
		ox = 40 + (h >> 4) % 48
		oz = 40 + (h >> 14) % 48
	return Vector2i(ox, oz)


## Ближайшая к точке (x, z) крепость (её центр) среди соседних областей или (1 << 30, 0).
func fortress_near(x: int, z: int) -> Vector2i:
	var best := Vector2i(1 << 30, 0)
	var best_d := INF
	var rx0 := floori(float(x) / REGION)
	var rz0 := floori(float(z) / REGION)
	for rz in range(rz0 - 1, rz0 + 2):
		for rx in range(rx0 - 1, rx0 + 2):
			var c := fortress_center(rx, rz)
			if c.x == 1 << 30:
				continue
			var d := Vector2(c.x - x, c.y - z).length()
			if d < best_d:
				best_d = d
				best = c
	return best


## Этапы крепости: 0 — мосты и опоры, 1 — центральный зал, 2 — коридоры, 3 — площадка ифритов и сад.
func _fortress(part: int) -> void:
	var rx := floori(float(buf.ox) / REGION)
	var rz := floori(float(buf.oz) / REGION)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := fortress_center(rx + dx, rz + dz)
			if c.x == 1 << 30:
				continue
			if not buf.overlaps(c.x - ARM - 12, c.y - ARM - 12, c.x + ARM + 12, c.y + ARM + 12):
				continue
			match part:
				0:
					_bridges(c)
				1:
					_hall(c)
				2:
					_corridors(c)
				3:
					_blaze_platform(c)
					_wart_room(c)


func _bridges(c: Vector2i) -> void:
	var y := DECK_Y
	for axis in 2:
		for s in range(-ARM, ARM + 1):
			var x0 := c.x + s if axis == 0 else c.x - 2
			var x1 := c.x + s if axis == 0 else c.x + 2
			var z0 := c.y - 2 if axis == 0 else c.y + s
			var z1 := c.y + 2 if axis == 0 else c.y + s
			# Настил, пустота над ним, перила по краям.
			buf.fill(x0, y - 1, z0, x1, y, z1, Blocks.NETHER_BRICK)
			buf.fill(x0, y + 1, z0, x1, y + 5, z1, Blocks.AIR)
			if axis == 0:
				buf.set_b(c.x + s, y + 1, c.y - 2, Blocks.NETHER_FENCE)
				buf.set_b(c.x + s, y + 1, c.y + 2, Blocks.NETHER_FENCE)
			else:
				buf.set_b(c.x - 2, y + 1, c.y + s, Blocks.NETHER_FENCE)
				buf.set_b(c.x + 2, y + 1, c.y + s, Blocks.NETHER_FENCE)
			# Опоры до земли (или лавы) через каждые 8 блоков.
			if absi(s) % 8 == 4:
				var px := c.x + s if axis == 0 else c.x
				var pz := c.y if axis == 0 else c.y + s
				var yy := y - 2
				while yy > 8:
					var under := buf.get_b(px, yy, pz)
					if under == Blocks.NETHERRACK or under == Blocks.BEDROCK:
						break
					buf.fill(px - 1, yy, pz - 1, px + 1, yy, pz + 1, Blocks.NETHER_BRICK)
					yy -= 1


## Зал на перекрёстке: стены из адского кирпича с окнами-решётками и крыша.
func _hall(c: Vector2i) -> void:
	var y := DECK_Y
	buf.fill(c.x - 5, y, c.y - 5, c.x + 5, y + 6, c.y + 5, Blocks.NETHER_BRICK)
	buf.fill(c.x - 4, y + 1, c.y - 4, c.x + 4, y + 5, c.y + 4, Blocks.AIR)
	# Проходы на четыре моста и окна.
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var ex := c.x + d.x * 5
		var ez := c.y + d.y * 5
		var side := Vector2i(d.y, d.x)
		buf.fill(ex - side.x, y + 1, ez - side.y, ex + side.x, y + 3, ez + side.y, Blocks.AIR)
		for k: int in [-3, 3]:
			buf.set_b(ex + side.x * k, y + 3, ez + side.y * k, Blocks.NETHER_FENCE)
			buf.set_b(ex + side.x * k, y + 4, ez + side.y * k, Blocks.NETHER_FENCE)


## Крытые коридоры на двух рукавах (−X и +Z), как коридоры крепостей.
func _corridors(c: Vector2i) -> void:
	var y := DECK_Y
	for s in range(8, ARM - 6):
		for arm: Vector2i in [Vector2i(-1, 0), Vector2i(0, 1)]:
			var px := c.x + arm.x * s
			var pz := c.y + arm.y * s
			var side := Vector2i(arm.y, arm.x)
			# Стены по бокам и крыша.
			for k: int in [-2, 2]:
				buf.fill(px + side.x * k, y + 1, pz + side.y * k, px + side.x * k, y + 4, pz + side.y * k, Blocks.NETHER_BRICK)
			buf.fill(px - side.x * 2, y + 5, pz - side.y * 2, px + side.x * 2, y + 5, pz + side.y * 2, Blocks.NETHER_BRICK)
			buf.fill(px - side.x, y + 1, pz - side.y, px + side.x, y + 4, pz + side.y, Blocks.AIR)
			if s % 4 == 2:
				for k: int in [-2, 2]:
					buf.set_b(px + side.x * k, y + 2, pz + side.y * k, Blocks.NETHER_FENCE)
					buf.set_b(px + side.x * k, y + 3, pz + side.y * k, Blocks.NETHER_FENCE)


## Площадка с рассадником ифритов в конце рукава +X.
func _blaze_platform(c: Vector2i) -> void:
	var y := DECK_Y
	var px := c.x + ARM - 4
	var pz := c.y
	buf.fill(px - 4, y - 1, pz - 4, px + 4, y, pz + 4, Blocks.NETHER_BRICK)
	buf.fill(px - 4, y + 1, pz - 4, px + 4, y + 6, pz + 4, Blocks.AIR)
	buf.fill(px - 2, y + 1, pz - 2, px + 2, y + 1, pz + 2, Blocks.NETHER_BRICK)
	for k in range(-4, 5):
		for edge: Vector2i in [Vector2i(k, -4), Vector2i(k, 4), Vector2i(-4, k), Vector2i(4, k)]:
			buf.set_b(px + edge.x, y + 1, pz + edge.y, Blocks.NETHER_FENCE)
	buf.add_spawner(px, y + 2, pz, 61)


## Комната с адским наростом на песке душ в конце рукава −Z.
func _wart_room(c: Vector2i) -> void:
	var y := DECK_Y
	var px := c.x
	var pz := c.y - ARM + 5
	buf.fill(px - 5, y, pz - 5, px + 5, y + 6, pz + 5, Blocks.NETHER_BRICK)
	buf.fill(px - 4, y + 1, pz - 4, px + 4, y + 5, pz + 4, Blocks.AIR)
	buf.fill(px - 1, y + 1, pz + 5, px + 1, y + 3, pz + 5, Blocks.AIR)
	for gx: int in [-3, 3]:
		buf.fill(px + gx - 1, y + 1, pz - 3, px + gx + 1, y + 1, pz + 2, Blocks.NETHER_BRICK)
		buf.fill(px + gx, y + 1, pz - 3, px + gx, y + 1, pz + 2, Blocks.SOUL_SAND)
		for wz in range(pz - 3, pz + 3):
			buf.set_b(px + gx, y + 2, wz, Blocks.NETHER_WART, WorldGen.hash3(px + gx, y, wz, seed_value) & 3)
	# Лестница в центре — ступени из адского кирпича.
	for k in 3:
		buf.set_b(px, y + 1 + k, pz - 3 + k, Blocks.NETHER_BRICK_STAIRS, 0)
