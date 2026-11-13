class_name WorldGen
extends RefCounted
## Генератор Обычного мира в духе Minecraft 1.2 (ChunkProviderGenerate).
## Рельеф — трёхмерная «плотность» на сетке 4×8×4 блока с трилинейной интерполяцией, параметры
## (глубина и разброс высот) смешиваются по биомам 5×5 ячеек, как в оригинале: равнины, горы
## с нависающими скалами, океаны, болота у уровня моря, долины рек. Затем — поверхность биома
## (трава, песок с песчаником, мицелий), коренная порода, пещеры и ущелья, руды, озёра, данжи,
## постройки (деревни, заброшенные шахты, крепости, пустынные колодцы), деревья и растения,
## снег и лёд, животные.
##
## Детерминирован по сиду и координатам чанка и не зависит от порядка генерации: всё, что
## пересекает границы чанков (деревья, пещеры, постройки), рассчитывается из сида, и каждый чанк
## ставит только свою часть. Не трогает дерево сцены — работает в рабочих потоках.
##
## Порционный режим (однопоточная веб-сборка): begin_chunk → fill_rows(z, z + 1) ×16 →
## finish_chunk. fill_rows выполняет «этапы» с номерами z0..z1-1 (0–4 — рельеф по 3–4 ряда,
## дальше — пещеры, ущелья, руды, данжи, постройки, деревья, растения); результат не зависит от
## разбиения на вызовы.

const CHUNK_SIZE := 16
const CHUNK_HEIGHT := 256
const LAYER := CHUNK_SIZE * CHUNK_SIZE
const VOLUME := LAYER * CHUNK_HEIGHT
const SEA_LEVEL := 63
## Высота, выше которой горы обычно голые (используется только для подсказок; снег в 1.2 зависит от биома).
const SNOW_LINE := 115
## Узлы сетки плотности по высоте: y = 0, 8, …, 128.
const GRID_LEVELS := 17
## Амплитуда трёхмерного шума рельефа (в единицах смещения сетки, как noise/512 в 1.2).
const NOISE_AMP := 26.0
## Вертикальное растяжение шума (по вертикали частота вдвое ниже, как в оригинале).
const NOISE_VSCALE := 0.5
const STAGES := 16
## Ряды рельефа по этапам 0–5.
static var TERRAIN_ROWS := [0, 3, 6, 9, 12, 16]
## Вероятность коренной породы на высотах 0–4 (из 16): (5 − y) / 5, как y ≤ rand(5) в 1.2.
static var BEDROCK_CHANCE := [16, 13, 10, 6, 3]

var seed_value := 0
var biome_src: BiomeSource
var _lo := FastNoiseLite.new()
var _hi := FastNoiseLite.new()
var _sel := FastNoiseLite.new()
var _depth := FastNoiseLite.new()
var _soil := FastNoiseLite.new()
var _carvers: Carvers
var _decor: Decorator
var _structures: Structures
## Кэш колонок сетки плотности: ключ → PackedFloat32Array(17).
var _grid_cache: Dictionary = {}

# Состояние порционной генерации.
var buf: GenChunk
var _biomes := PackedByteArray()
## Высота поверхности рельефа по колонкам чанка (до пещер и построек).
var heights := PackedInt32Array()
var _cols: Array[PackedFloat32Array] = []
var min_surface := 0
var max_surface := 0

## Веса смешивания биомов 5×5: 10 / sqrt(dx² + dz² + 0,2).
static var _blend_w := PackedFloat32Array()


static func _static_init() -> void:
	_blend_w.resize(25)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			_blend_w[(dx + 2) + (dz + 2) * 5] = 10.0 / sqrt(dx * dx + dz * dz + 0.2)


func _init(p_seed: int) -> void:
	seed_value = p_seed
	biome_src = BiomeSource.new(p_seed)
	_noise(_lo, p_seed + 1, 1.0 / 210.0, 5)
	_noise(_hi, p_seed + 2, 1.0 / 210.0, 5)
	_noise(_sel, p_seed + 3, 1.0 / 70.0, 3)
	_noise(_depth, p_seed + 4, 1.0 / 260.0, 3)
	_noise(_soil, p_seed + 5, 1.0 / 20.0, 2)


static func _noise(n: FastNoiseLite, s: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves


## Быстрый детерминированный хеш (результат 0..2^31-1), без переполнений int64.
static func hash3(x: int, y: int, z: int, s: int) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (s * 2654435761)
	h = h & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF


# --- Рельеф ----------------------------------------------------------------

## Колонка сетки плотности (gx, gz) — точка (4·gx, 4·gz): 17 значений по высоте.
func grid_column(gx: int, gz: int) -> PackedFloat32Array:
	var key := ((gx + 0x100000) << 22) | (gz + 0x100000)
	var c: Variant = _grid_cache.get(key)
	if c != null:
		return c
	var src := biome_src
	var center_min := Biomes.min_height(src.cell(gx, gz))
	var sum_max := 0.0
	var sum_min := 0.0
	var sum_w := 0.0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var b := src.cell(gx + dx, gz + dz)
			var mn := Biomes.min_height(b)
			var w := _blend_w[(dx + 2) + (dz + 2) * 5] / (mn + 2.0)
			if mn > center_min:
				w *= 0.5
			sum_max += Biomes.max_height(b) * w
			sum_min += mn * w
			sum_w += w
	var wx := float(gx * 4)
	var wz := float(gz * 4)
	var variation := (sum_max / sum_w) * 0.9 + 0.1
	var depth := ((sum_min / sum_w) * 4.0 - 1.0) / 8.0
	# Крупные понижения и поднятия рельефа (depth noise в 1.2): чаще вниз, чем вверх.
	var dn := _depth.get_noise_2d(wx, wz) * 1.6
	if dn < 0.0:
		dn = maxf(dn, -1.0) * 0.35
	else:
		dn = minf(dn, 1.0) * 0.06
	depth += dn
	var base := 8.5 + depth * 17.0 / 16.0 * 4.0 + 0.125
	var out := PackedFloat32Array()
	out.resize(GRID_LEVELS)
	var inv := 12.0 / variation
	for k in GRID_LEVELS:
		var y := float(k * 8) * NOISE_VSCALE
		var off := (float(k) - base) * inv
		if off < 0.0:
			off *= 4.0
		var lo := _lo.get_noise_3d(wx, y, wz)
		var hi := _hi.get_noise_3d(wx, y, wz)
		var s := clampf((_sel.get_noise_3d(wx, y, wz) * 8.0 + 1.0) * 0.5, 0.0, 1.0)
		var d := (lo + (hi - lo) * s) * NOISE_AMP - off
		if k > GRID_LEVELS - 4:
			var t := float(k - (GRID_LEVELS - 4)) / 3.0
			d = d * (1.0 - t) - 10.0 * t
		out[k] = d
	if _grid_cache.size() > 20000:
		_grid_cache.clear()
	_grid_cache[key] = out
	return out


## Плотность колонки (wx, wz) по четырём узлам сетки — общая формула для чанка и get_height.
## Результат — в PackedFloat64Array, чтобы совпадать до бита с get_height (там вычисления в double).
static func _column_dens(a: PackedFloat32Array, b: PackedFloat32Array, c: PackedFloat32Array,
		e: PackedFloat32Array, fx: float, fz: float, out: PackedFloat64Array) -> void:
	for k in GRID_LEVELS:
		var p := a[k] + (b[k] - a[k]) * fx
		var q := c[k] + (e[k] - c[k]) * fx
		out[k] = p + (q - p) * fz


## Верхний y с положительной плотностью (0, если колонка пуста).
static func _top_from_dens(d: PackedFloat64Array) -> int:
	for k in range(GRID_LEVELS - 2, -1, -1):
		var a := d[k]
		var b := d[k + 1]
		if a <= 0.0 and b <= 0.0:
			continue
		for j in range(7, -1, -1):
			if a + (b - a) * (j * 0.125) > 0.0:
				return k * 8 + j
	return 0


## Высота поверхности рельефа (y верхнего твёрдого блока) в мировой колонке — без учёта пещер.
## Значения считаются сверху вниз только до поверхности (та же формула, что и в чанке).
func get_height(wx: int, wz: int) -> int:
	var gx := wx >> 2
	var gz := wz >> 2
	var a := grid_column(gx, gz)
	var b := grid_column(gx + 1, gz)
	var c := grid_column(gx, gz + 1)
	var e := grid_column(gx + 1, gz + 1)
	var fx := (wx & 3) * 0.25
	var fz := (wz & 3) * 0.25
	var k := GRID_LEVELS - 1
	var p := a[k] + (b[k] - a[k]) * fx
	var q := c[k] + (e[k] - c[k]) * fx
	var hi := p + (q - p) * fz
	for kk in range(GRID_LEVELS - 2, -1, -1):
		p = a[kk] + (b[kk] - a[kk]) * fx
		q = c[kk] + (e[kk] - c[kk]) * fx
		var lo := p + (q - p) * fz
		if lo > 0.0 or hi > 0.0:
			for j in range(7, -1, -1):
				if lo + (hi - lo) * (j * 0.125) > 0.0:
					return kk * 8 + j
		hi = lo
	return 0


func biome_at(wx: int, wz: int) -> int:
	return biome_src.biome_at(wx, wz)


## Толщина почвы (как stoneNoise в 1.2): 0 — голый камень, обычно 2–4 блока.
func soil_depth(wx: int, wz: int) -> int:
	var r := float(hash3(wx, 7, wz, seed_value) & 255) / 1024.0
	return clampi(int(_soil.get_noise_2d(wx, wz) * 2.6 + 3.0 + r), 0, 6)


## Блок поверхности колонки по правилам биома (без учёта построек) — для решений соседних чанков.
func surface_block(wx: int, wz: int, h: int) -> int:
	var b := biome_at(wx, wz)
	if soil_depth(wx, wz) <= 0:
		return Blocks.STONE
	if h < SEA_LEVEL:
		return Biomes.filler_block(b)
	return Biomes.top_block(b)


# --- Генерация чанка -------------------------------------------------------

func generate_chunk(cx: int, cz: int) -> Dictionary:
	begin_chunk(cx, cz)
	fill_rows(0, STAGES)
	return finish_chunk()


## Начало: биомы колонок, сетка плотности, толщина почвы.
func begin_chunk(cx: int, cz: int) -> void:
	buf = GenChunk.new()
	buf.setup(cx, cz)
	_biomes = PackedByteArray()
	_biomes.resize(LAYER)
	biome_src.fill_chunk(buf.ox, buf.oz, _biomes)
	# Узлы сетки плотности считаются по мере надобности (в этапах рельефа).
	_cols = []
	_cols.resize(25)
	heights = PackedInt32Array()
	heights.resize(LAYER)
	min_surface = CHUNK_HEIGHT
	max_surface = 0


## Этапы z0..z1-1 (см. описание класса).
func fill_rows(z0: int, z1: int) -> void:
	for s in range(z0, z1):
		_stage(s)


func _stage(s: int) -> void:
	if s < 5:
		_terrain_rows(TERRAIN_ROWS[s], TERRAIN_ROWS[s + 1])
		if s == 4:
			_after_terrain()
		return
	match s:
		5:
			_carvers.caves(-Carvers.CAVE_RANGE, -1)
		6:
			_carvers.caves(0, Carvers.CAVE_RANGE)
		7:
			_carvers.ravines()
		8:
			_decor.ores(0)
		9:
			_decor.ores(1)
			_decor.underground()
		10:
			_structures.generate()
		11:
			_decor.trees(-1, 0, 2)
		12:
			_decor.trees(0, 0, 1)
		13:
			_decor.trees(0, 1, 2)
		14:
			_decor.trees(1, 0, 2)
		15:
			_decor.surface()


func _after_terrain() -> void:
	if _carvers == null:
		_carvers = Carvers.new(seed_value)
		_decor = Decorator.new(self)
		_structures = Structures.new(self)
	_carvers.begin(buf, heights)
	_decor.begin()
	_structures.begin()


## Готовый чанк (снег, лёд и животные — последним шагом).
func finish_chunk() -> Dictionary:
	_decor.finish()
	var out := {"blocks": buf.blocks, "meta": buf.meta, "biomes": _biomes, "block_entities": buf.block_entities,
		"entities": buf.entities}
	buf = null
	_biomes = PackedByteArray()
	_cols = []
	return out


## Мешает ли постройка дереву в колонке (деревья не растут посреди деревень).
func structure_blocks_tree(wx: int, wz: int) -> bool:
	return _structures.blocks_tree(wx, wz)


## Центры трёх крепостей (мировые координаты x, z) — для глаза Края и отладки.
func stronghold_positions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in StrongholdGen.new(seed_value).start_chunks(biome_src):
		out.append(Vector2i(c.x * 16 + 4, c.y * 16 + 4))
	return out


## Центр деревни области 512×512 блоков (rx, rz) или Vector2i(1 << 30, 0), если её там нет.
func village_center(rx: int, rz: int) -> Vector2i:
	return VillageGen.new(self).village_center(rx, rz)


## Биом колонки чанка (локальные координаты).
func local_biome(lx: int, lz: int) -> int:
	return _biomes[lx + lz * 16]


## Рельеф и поверхность рядов z0..z1-1: камень по плотности, вода до уровня моря, верхний слой и
## наполнитель биома (как replaceBlocksForBiome), песчаник под песком, коренная порода.
func _terrain_rows(z0: int, z1: int) -> void:
	var data := buf.blocks
	var dens := PackedFloat64Array()
	dens.resize(GRID_LEVELS)
	var gx0 := buf.cx * 4
	var gz0 := buf.cz * 4
	for z in range(z0, z1):
		var gj := z >> 2
		for gi in 5:
			for dj in 2:
				var ci := gi + (gj + dj) * 5
				if _cols[ci].is_empty():
					_cols[ci] = grid_column(gx0 + gi, gz0 + gj + dj)
		var fz := (z & 3) * 0.25
		for x in CHUNK_SIZE:
			var gi := x >> 2
			_column_dens(_cols[gi + gj * 5], _cols[gi + 1 + gj * 5], _cols[gi + (gj + 1) * 5], _cols[gi + 1 + (gj + 1) * 5],
				(x & 3) * 0.25, fz, dens)
			var col := x + z * 16
			var top := _top_from_dens(dens)
			heights[col] = top
			min_surface = mini(min_surface, top)
			max_surface = maxi(max_surface, top)
			_fill_column(data, col, dens, top, _biomes[col], soil_depth(buf.ox + x, buf.oz + z), buf.ox + x, buf.oz + z)


func _fill_column(data: PackedByteArray, col: int, dens: PackedFloat64Array, top: int, biome: int, soil: int,
		wx: int, wz: int) -> void:
	var top_b := Biomes.top_block(biome)
	var fill_b := Biomes.filler_block(biome)
	var run := -1
	var y := maxi(top, SEA_LEVEL)
	var hs := hash3(wx, 3, wz, seed_value)
	while y > 0:
		var k := y >> 3
		var a := dens[k]
		var b := dens[k + 1]
		if a > 0.0 and b > 0.0 and run == 0:
			# Целиком твёрдая ячейка глубже почвы — сплошной камень.
			var lo := maxi(k * 8, 1)
			while y >= lo:
				data[col + (y << 8)] = Blocks.STONE
				y -= 1
			continue
		var i := col + (y << 8)
		if a + (b - a) * ((y & 7) * 0.125) <= 0.0:
			run = -1
			if y <= SEA_LEVEL:
				data[i] = Blocks.WATER
		elif run == -1:
			if soil <= 0:
				top_b = Blocks.STONE
				fill_b = Blocks.STONE
			elif y >= SEA_LEVEL - 4 and y <= SEA_LEVEL + 1:
				top_b = Biomes.top_block(biome)
				fill_b = Biomes.filler_block(biome)
			run = soil
			data[i] = top_b if y >= SEA_LEVEL else fill_b
		elif run > 0:
			run -= 1
			data[i] = fill_b
			if run == 0 and fill_b == Blocks.SAND:
				run = hs & 3
				hs >>= 2
				fill_b = Blocks.SANDSTONE
		else:
			data[i] = Blocks.STONE
		y -= 1
	# Коренная порода: y = 0 всегда, выше — всё реже (y ≤ rand(5), как в оригинале).
	var hb := hash3(wx, 0, wz, seed_value + 9)
	data[col] = Blocks.BEDROCK
	for yy in range(1, 5):
		if ((hb >> (yy * 4)) & 15) < BEDROCK_CHANCE[yy]:
			data[col + (yy << 8)] = Blocks.BEDROCK


# --- Точка появления ---------------------------------------------------------

## Точка появления: ближайшая к началу координат суша в «тёплом» биоме с травой (как в 1.2 —
## лес, равнины, тайга, джунгли); если такой нет в радиусе 256 блоков — любая суша.
func find_spawn_column() -> Vector2i:
	var fallback := Vector2i(1 << 30, 0)
	for r in range(0, 72):
		for t in maxi(1, r * 8):
			var p := _ring_cell(r, t)
			var x := p.x * 4 + 2
			var z := p.y * 4 + 2
			var b := biome_src.cell(p.x, p.y)
			if Biomes.is_ocean(b) or Biomes.is_river(b):
				continue
			var h := get_height(x, z)
			if h <= SEA_LEVEL or h > 110:
				continue
			if b in Biomes.SPAWN_BIOMES and biome_at(x, z) == b and soil_depth(x, z) > 0:
				return Vector2i(x, z)
			if fallback.x == 1 << 30:
				fallback = Vector2i(x, z)
	return fallback if fallback.x != 1 << 30 else Vector2i.ZERO


## t-я ячейка кольца радиуса r (по периметру квадрата).
static func _ring_cell(r: int, t: int) -> Vector2i:
	if r == 0:
		return Vector2i.ZERO
	@warning_ignore("integer_division")
	var side := t / (2 * r)
	var o := t % (2 * r)
	match side:
		0:
			return Vector2i(-r + o, -r)
		1:
			return Vector2i(r, -r + o)
		2:
			return Vector2i(r - o, r)
	return Vector2i(-r, r - o)
