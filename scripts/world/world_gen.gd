class_name WorldGen
extends RefCounted
## Детерминированная генерация ландшафта по сиду.
## Не трогает дерево сцены, поэтому экземпляр можно создавать в рабочем потоке.

const CHUNK_SIZE := 16
const CHUNK_HEIGHT := 128
const LAYER := CHUNK_SIZE * CHUNK_SIZE
const VOLUME := LAYER * CHUNK_HEIGHT
const SEA_LEVEL := 40
const SNOW_LINE := 92
const TREE_CELL := 6

var seed_value := 0
var _continent := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _mountain := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _cave_a := FastNoiseLite.new()
var _cave_b := FastNoiseLite.new()


func _init(p_seed: int) -> void:
	seed_value = p_seed
	_setup(_continent, p_seed, 0.0021, 3, FastNoiseLite.FRACTAL_FBM)
	_setup(_detail, p_seed + 11, 0.012, 4, FastNoiseLite.FRACTAL_FBM)
	_setup(_mountain, p_seed + 23, 0.0055, 4, FastNoiseLite.FRACTAL_RIDGED)
	_setup(_forest, p_seed + 37, 0.009, 2, FastNoiseLite.FRACTAL_FBM)
	_setup(_cave_a, p_seed + 51, 0.034, 1, FastNoiseLite.FRACTAL_NONE)
	_setup(_cave_b, p_seed + 67, 0.034, 1, FastNoiseLite.FRACTAL_NONE)


static func _setup(n: FastNoiseLite, s: int, freq: float, octaves: int, fractal: FastNoiseLite.FractalType) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves


## Быстрый детерминированный хеш (результат 0..2^31-1), без переполнений int64.
static func hash3(x: int, y: int, z: int, s: int) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (s * 2654435761)
	h = h & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF


## Высота поверхности (y верхнего твёрдого блока) в мировой колонке.
func get_height(wx: int, wz: int) -> int:
	var c := _continent.get_noise_2d(wx, wz)
	var d := _detail.get_noise_2d(wx, wz)
	var h := SEA_LEVEL + 4.0 + c * 30.0 + d * 7.0
	# Горы появляются только вглубь материка.
	var inland := clampf((c + 0.02) * 4.0, 0.0, 1.0)
	var ridge := (_mountain.get_noise_2d(wx, wz) + 1.0) * 0.5
	h += pow(ridge, 3.0) * 46.0 * inland
	return clampi(int(h), 4, CHUNK_HEIGHT - 16)


func generate_chunk(cx: int, cz: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(VOLUME)
	var ox := cx * CHUNK_SIZE
	var oz := cz * CHUNK_SIZE

	var heights := PackedInt32Array()
	heights.resize(LAYER)
	var max_h := 0
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var h := get_height(ox + x, oz + z)
			heights[x + z * CHUNK_SIZE] = h
			max_h = maxi(max_h, h)

	# Шум пещер считается целиком на стороне движка: image[z].pixel(x, y) = noise(x, y, z).
	var cave_h := maxi(max_h - 4, 1)
	_cave_a.offset = Vector3(ox, 0, oz)
	_cave_b.offset = Vector3(ox, 0, oz)
	var imgs_a := _cave_a.get_image_3d(CHUNK_SIZE, cave_h, CHUNK_SIZE, false, false)
	var imgs_b := _cave_b.get_image_3d(CHUNK_SIZE, cave_h, CHUNK_SIZE, false, false)

	for z in CHUNK_SIZE:
		var cave_a: PackedByteArray = imgs_a[z].get_data()
		var cave_b: PackedByteArray = imgs_b[z].get_data()
		for x in CHUNK_SIZE:
			var col := x + z * CHUNK_SIZE
			var h := heights[col]
			var wx := ox + x
			var wz := oz + z
			var top_block := Blocks.GRASS
			var filler := Blocks.DIRT
			if h <= SEA_LEVEL + 1:
				top_block = Blocks.SAND
				filler = Blocks.SAND
				if h < SEA_LEVEL - 7:
					top_block = Blocks.GRAVEL
			elif h >= SNOW_LINE:
				top_block = Blocks.SNOW
				filler = Blocks.STONE
			for y in range(0, h + 1):
				var b := Blocks.STONE
				if y == 0:
					b = Blocks.BEDROCK
				elif y < 4 and hash3(wx, y, wz, seed_value) % 3 == 0:
					b = Blocks.BEDROCK
				elif y == h:
					b = top_block
				elif y > h - 4:
					b = filler
				else:
					var r := hash3(wx, y, wz, seed_value + 5) % 1000
					if r < 11 and y < 96:
						b = Blocks.COAL_ORE
					elif r < 18 and y < 52:
						b = Blocks.IRON_ORE
					# Пещеры-«спагетти»: пересечение двух тонких изоповерхностей шума.
					if y > 4 and y < h - 4:
						var ci := x + y * CHUNK_SIZE
						var va := cave_a[ci]
						var vb := cave_b[ci]
						if va > 113 and va < 142 and vb > 113 and vb < 142:
							b = Blocks.AIR
				data[col + y * LAYER] = b
			for y in range(h + 1, SEA_LEVEL + 1):
				data[col + y * LAYER] = Blocks.WATER

	_place_trees(data, ox, oz)
	return data


## Деревья ставятся по сетке со случайным смещением; каждый чанк проверяет и соседние ячейки,
## поэтому кроны на границах чанков совпадают без обмена данными между чанками.
func _place_trees(data: PackedByteArray, ox: int, oz: int) -> void:
	var gx0 := floori((ox - 3) / float(TREE_CELL))
	var gx1 := floori((ox + CHUNK_SIZE + 2) / float(TREE_CELL))
	var gz0 := floori((oz - 3) / float(TREE_CELL))
	var gz1 := floori((oz + CHUNK_SIZE + 2) / float(TREE_CELL))
	for gz in range(gz0, gz1 + 1):
		for gx in range(gx0, gx1 + 1):
			var hs := hash3(gx, 7, gz, seed_value)
			var forest := _forest.get_noise_2d(gx * TREE_CELL, gz * TREE_CELL)
			var chance := clampf(0.1 + forest * 1.2, 0.02, 0.8)
			if float(hs % 1000) / 1000.0 >= chance:
				continue
			var tx := gx * TREE_CELL + 1 + (hs >> 10) % 4
			var tz := gz * TREE_CELL + 1 + (hs >> 13) % 4
			if tx < ox - 2 or tx > ox + CHUNK_SIZE + 1 or tz < oz - 2 or tz > oz + CHUNK_SIZE + 1:
				continue
			var ground := get_height(tx, tz)
			if ground <= SEA_LEVEL + 1 or ground >= SNOW_LINE - 6:
				continue
			var trunk := 4 + (hs >> 17) % 3
			_place_tree(data, ox, oz, tx, ground, tz, trunk, hs)


func _place_tree(data: PackedByteArray, ox: int, oz: int, tx: int, ground: int, tz: int, trunk: int, hs: int) -> void:
	var top := ground + trunk
	for dy in range(-2, 2):
		var y := top + dy
		var r := 2 if dy < 0 else 1
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r:
					if dy == 1:
						continue
					if hash3(tx + dx, y, tz + dz, hs) % 2 == 0:
						continue
				_set_local(data, ox, oz, tx + dx, y, tz + dz, Blocks.LEAVES, true)
	for y in range(ground + 1, top + 1):
		_set_local(data, ox, oz, tx, y, tz, Blocks.LOG, false)
	# Под стволом трава превращается в землю.
	var lx := tx - ox
	var lz := tz - oz
	if lx >= 0 and lx < CHUNK_SIZE and lz >= 0 and lz < CHUNK_SIZE:
		data[lx + lz * CHUNK_SIZE + ground * LAYER] = Blocks.DIRT


func _set_local(data: PackedByteArray, ox: int, oz: int, wx: int, y: int, wz: int, b: int, only_air: bool) -> void:
	var lx := wx - ox
	var lz := wz - oz
	if lx < 0 or lx >= CHUNK_SIZE or lz < 0 or lz >= CHUNK_SIZE or y < 0 or y >= CHUNK_HEIGHT:
		return
	var i := lx + lz * CHUNK_SIZE + y * LAYER
	var cur := data[i]
	if only_air:
		if cur != Blocks.AIR:
			return
	elif cur != Blocks.AIR and cur != Blocks.LEAVES:
		return
	data[i] = b


## Поиск точки появления на суше рядом с началом координат.
func find_spawn_column() -> Vector2i:
	for radius in range(0, 400, 8):
		for i in 16:
			var a := TAU * i / 16.0
			var x := int(cos(a) * radius)
			var z := int(sin(a) * radius)
			var h := get_height(x, z)
			if h > SEA_LEVEL + 2 and h < SNOW_LINE - 10:
				return Vector2i(x, z)
			if radius == 0:
				break
	return Vector2i.ZERO
