class_name BiomeSource
extends RefCounted
## Карта биомов в духе слоёв GenLayer из 1.1/1.2: материки и океаны, холодные зоны (ледяные
## равнины и горы), крупные области биомов (~250 блоков: пустыня, лес, горы, болото, равнины,
## тайга, джунгли), холмы внутри областей, пляжи, предгорья на краях гор, извилистые реки и
## редкие грибные острова посреди океана.
## Карта считается по ячейкам 4×4 блока (как biomesForGeneration в 1.2) — по ним смешиваются
## параметры рельефа; биом отдельного блока берётся из ячейки со случайным сдвигом на ±1 блок,
## поэтому границы «рваные», как после зума Вороного. Всё зависит только от сида и координат.

const CELL := 4
## Порог «суша/океан» по шуму материков (доля океана ~35 %).
const OCEAN_LEVEL := -0.08
## Порог холодной зоны (ледяные равнины, замёрзшие океаны и реки).
const COLD_LEVEL := -0.3
## Полуширина русла реки в значениях шума.
const RIVER_WIDTH := 0.042
## Доля ячеек холмов внутри биома.
const HILLS_LEVEL := 0.36
## Радиус вокруг начала координат, где суша гарантирована (точка появления).
const ORIGIN_LAND := 600.0
## Размер области, в которой может быть один грибной остров.
const MUSHROOM_REGION := 768

## Биомы обычной (не холодной) суши — равновероятны, как allowedBiomes в GenLayerBiome 1.2.
static var LAND_BIOMES := [Biomes.DESERT, Biomes.FOREST, Biomes.EXTREME_HILLS, Biomes.SWAMPLAND, Biomes.PLAINS,
	Biomes.TAIGA, Biomes.JUNGLE]

var seed_value := 0
var _warp_a := FastNoiseLite.new()
var _warp_b := FastNoiseLite.new()
var _land := FastNoiseLite.new()
var _temp := FastNoiseLite.new()
var _cells := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _river := FastNoiseLite.new()
var _shape := FastNoiseLite.new()
## Кэш ячеек: ключ → биом (сырой — до пляжей/холмов/рек, итоговый — после).
var _raw: Dictionary = {}
var _final: Dictionary = {}


func _init(p_seed: int) -> void:
	seed_value = p_seed
	_simplex(_warp_a, p_seed + 101, 1.0 / 90.0, 2)
	_simplex(_warp_b, p_seed + 102, 1.0 / 90.0, 2)
	_simplex(_land, p_seed + 103, 1.0 / 1100.0, 4)
	_simplex(_temp, p_seed + 104, 1.0 / 1700.0, 2)
	_simplex(_river, p_seed + 105, 1.0 / 460.0, 3)
	_simplex(_shape, p_seed + 106, 1.0 / 40.0, 2)
	_cells.seed = p_seed + 107
	_cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	_cells.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	_cells.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	_cells.frequency = 1.0 / 250.0
	_cells.fractal_type = FastNoiseLite.FRACTAL_NONE
	_hills.seed = p_seed + 108
	_hills.noise_type = FastNoiseLite.TYPE_CELLULAR
	_hills.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	_hills.frequency = 1.0 / 80.0
	_hills.fractal_type = FastNoiseLite.FRACTAL_NONE


static func _simplex(n: FastNoiseLite, s: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves


static func _key(i: int, j: int) -> int:
	return ((i + 0x100000) << 22) | (j + 0x100000)


## Биом блока (ячейка со сдвигом на ±1 блок — «рваные» границы).
func biome_at(wx: int, wz: int) -> int:
	var h := WorldGen.hash3(wx, 91, wz, seed_value)
	var jx := (h & 3) - 1
	var jz := ((h >> 2) & 3) - 1
	if jx > 1:
		jx = 0
	if jz > 1:
		jz = 0
	return cell((wx + jx) >> 2, (wz + jz) >> 2)


## Биомы колонок чанка (16×16, индекс x + z * 16) — то же, что biome_at, но быстрее.
func fill_chunk(ox: int, oz: int, out: PackedByteArray) -> void:
	var i0 := (ox >> 2) - 1
	var j0 := (oz >> 2) - 1
	var cells := PackedByteArray()
	cells.resize(36)
	for j in 6:
		for i in 6:
			cells[i + j * 6] = cell(i0 + i, j0 + j)
	for z in 16:
		for x in 16:
			var h := WorldGen.hash3(ox + x, 91, oz + z, seed_value)
			var jx := (h & 3) - 1
			var jz := ((h >> 2) & 3) - 1
			if jx > 1:
				jx = 0
			if jz > 1:
				jz = 0
			out[x + z * 16] = cells[((ox + x + jx) >> 2) - i0 + (((oz + z + jz) >> 2) - j0) * 6]


## Итоговый биом ячейки 4×4 (i, j) — с пляжами, предгорьями, холмами и реками.
func cell(i: int, j: int) -> int:
	var k := _key(i, j)
	var c: Variant = _final.get(k)
	if c != null:
		return c
	var b := _compute_cell(i, j)
	if _final.size() > 60000:
		_final.clear()
	_final[k] = b
	return b


func _compute_cell(i: int, j: int) -> int:
	var b := raw_cell(i, j)
	var n0 := raw_cell(i, j - 2)
	var n1 := raw_cell(i + 2, j)
	var n2 := raw_cell(i, j + 2)
	var n3 := raw_cell(i - 2, j)
	var near_ocean := _is_sea(n0) or _is_sea(n1) or _is_sea(n2) or _is_sea(n3)
	if b == Biomes.MUSHROOM_ISLAND:
		if near_ocean:
			b = Biomes.MUSHROOM_SHORE
	elif Biomes.is_ocean(b):
		pass
	elif b == Biomes.EXTREME_HILLS:
		# Горы у моря обрываются утёсами, на границе с другой сушей — предгорья.
		if not near_ocean and (n0 != b or n1 != b or n2 != b or n3 != b):
			b = Biomes.EXTREME_HILLS_EDGE
	elif near_ocean:
		if b != Biomes.SWAMPLAND:
			b = Biomes.BEACH
	elif n0 == b and n1 == b and n2 == b and n3 == b:
		var x := i * CELL + 2
		var z := j * CELL + 2
		if _hills.get_noise_2d(x + 7.0, z - 11.0) > 1.0 - 2.0 * HILLS_LEVEL:
			b = _hills_variant(b)
	# Реки пересекают всё, кроме океанов (RiverMix).
	if not Biomes.is_ocean(b):
		var x := float(i * CELL + 2)
		var z := float(j * CELL + 2)
		var rx := x + _warp_b.get_noise_2d(z, x) * 22.0
		var rz := z + _warp_a.get_noise_2d(z, x) * 22.0
		var r := _river.get_noise_2d(rx, rz)
		if absf(r) < RIVER_WIDTH:
			if b == Biomes.ICE_PLAINS or b == Biomes.ICE_MOUNTAINS:
				b = Biomes.FROZEN_RIVER
			elif Biomes.is_mushroom(b):
				b = Biomes.MUSHROOM_SHORE
			else:
				b = Biomes.RIVER
	return b


static func _is_sea(b: int) -> bool:
	return b == Biomes.OCEAN or b == Biomes.FROZEN_OCEAN


static func _hills_variant(b: int) -> int:
	match b:
		Biomes.DESERT:
			return Biomes.DESERT_HILLS
		Biomes.FOREST:
			return Biomes.FOREST_HILLS
		Biomes.TAIGA:
			return Biomes.TAIGA_HILLS
		Biomes.PLAINS:
			return Biomes.FOREST
		Biomes.ICE_PLAINS:
			return Biomes.ICE_MOUNTAINS
		Biomes.JUNGLE:
			return Biomes.JUNGLE_HILLS
	return b


## Ячейка до пляжей, холмов и рек: океан/суша, холодные зоны, область биома, грибные острова.
func raw_cell(i: int, j: int) -> int:
	var k := _key(i, j)
	var c: Variant = _raw.get(k)
	if c != null:
		return c
	var x := float(i * CELL + 2)
	var z := float(j * CELL + 2)
	var wx := x + _warp_a.get_noise_2d(x, z) * 40.0
	var wz := z + _warp_b.get_noise_2d(x, z) * 40.0
	var land := _land.get_noise_2d(wx, wz)
	# Как в GenLayerIsland: окрестности начала координат — всегда суша.
	var d0 := sqrt(x * x + z * z)
	if d0 < ORIGIN_LAND:
		land += (1.0 - d0 / ORIGIN_LAND) * 0.4
	var cold := _temp.get_noise_2d(wx, wz) < COLD_LEVEL
	var b := 0
	if land < OCEAN_LEVEL:
		b = Biomes.FROZEN_OCEAN if cold else Biomes.OCEAN
		if land < OCEAN_LEVEL - 0.12 and _mushroom_island(i * CELL + 2, j * CELL + 2):
			b = Biomes.MUSHROOM_ISLAND
	elif cold:
		b = Biomes.ICE_PLAINS
	else:
		var v := _cells.get_noise_2d(wx, wz)
		b = LAND_BIOMES[clampi(int((v + 1.0) * 0.5 * LAND_BIOMES.size()), 0, LAND_BIOMES.size() - 1)]
	if _raw.size() > 60000:
		_raw.clear()
	_raw[k] = b
	return b


## Грибной остров: не больше одного на область MUSHROOM_REGION, только вдали от суши.
func _mushroom_island(x: int, z: int) -> bool:
	var rx := floori(float(x) / MUSHROOM_REGION)
	var rz := floori(float(z) / MUSHROOM_REGION)
	var h := WorldGen.hash3(rx, 1414, rz, seed_value)
	if h % 3 != 0:
		return false
	var span := MUSHROOM_REGION - 260
	var cx := rx * MUSHROOM_REGION + 130 + (h >> 3) % span
	var cz := rz * MUSHROOM_REGION + 130 + (h >> 13) % span
	var radius := 34.0 + float((h >> 23) % 30)
	var dx := float(x - cx)
	var dz := float(z - cz)
	var d := sqrt(dx * dx + dz * dz)
	if d > radius * 1.5:
		return false
	# Центр острова тоже должен быть в открытом океане.
	if _land.get_noise_2d(cx, cz) > OCEAN_LEVEL - 0.15:
		return false
	return d < radius * (1.0 + 0.35 * _shape.get_noise_2d(x, z))


## Холодная зона (для ледяных биомов и замёрзших океанов).
func is_cold_at(wx: int, wz: int) -> bool:
	var x := float(wx)
	var z := float(wz)
	var px := x + _warp_a.get_noise_2d(x, z) * 40.0
	var pz := z + _warp_b.get_noise_2d(x, z) * 40.0
	return _temp.get_noise_2d(px, pz) < COLD_LEVEL
