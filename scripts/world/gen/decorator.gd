class_name Decorator
extends RefCounted
## Наполнение чанка Обычного мира, как BiomeDecorator и populate в 1.2: руды с жилами 1.2,
## карманы земли и гравия, данжи с сундуками и рассадником, пустынные колодцы, озёра воды и
## лавы, деревья по биомам (пересекают границы чанков), трава, папоротники, цветы, грибы,
## сахарный тростник, кактусы, мёртвые кусты, тыквы, арбузы, кувшинки, лианы, песок/глина/гравий
## на дне, снег и лёд в холодных биомах, животные при генерации.

const SEA := WorldGen.SEA_LEVEL
## Сколько попыток посадки на «кучку» растений (вместо 128 трёхмерных попыток оригинала —
## столько же удачных посадок).
const GRASS_TRIES := 24
const FLOWER_TRIES := 12
## Смещения клеток «шарика» жилы, по возрастанию удалённости: центр, 6 граней, 12 рёбер, 8 углов.
const VEIN_X := [0, 1, -1, 0, 0, 0, 0, 1, 1, -1, -1, 1, 1, -1, -1, 0, 0, 0, 0, 1, 1, 1, 1, -1, -1, -1, -1]
const VEIN_Y := [0, 0, 0, 1, -1, 0, 0, 1, -1, 1, -1, 0, 0, 0, 0, 1, 1, -1, -1, 1, 1, -1, -1, 1, 1, -1, -1]
const VEIN_Z := [0, 0, 0, 0, 0, 1, -1, 0, 0, 0, 0, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1]

## Приёмник блоков дерева, пишущий прямо в чанк (с отсечением по его границам).
class ChunkSink extends TreeGen.Sink:
	var data := PackedByteArray()
	var mt := PackedByteArray()
	## Основание ствола в локальных координатах чанка.
	var bx := 0
	var by := 0
	var bz := 0

	func aim(blocks: PackedByteArray, meta: PackedByteArray, lx: int, y: int, lz: int, reach: int) -> void:
		data = blocks
		mt = meta
		bx = lx
		by = y
		bz = lz
		x0 = maxi(-lx - 1, -reach - 1)
		x1 = mini(16 - lx, reach + 1)
		z0 = maxi(-lz - 1, -reach - 1)
		z1 = mini(16 - lz, reach + 1)

	func put(x: int, y: int, z: int, id: int, meta: int, only_air: bool) -> void:
		var lx := bx + x
		var lz := bz + z
		var py := by + y
		if lx < 0 or lx > 15 or lz < 0 or lz > 15 or py < 1 or py > 255:
			return
		var i := lx + (lz << 4) + (py << 8)
		var cur := data[i]
		if only_air:
			if cur != Blocks.AIR and cur != Blocks.TALLGRASS and cur != Blocks.SNOW_LAYER:
				return
		elif cur != Blocks.AIR and cur != Blocks.LEAVES and cur != Blocks.TALLGRASS and cur != Blocks.VINE \
				and cur != Blocks.SNOW_LAYER and cur != Blocks.DANDELION and cur != Blocks.ROSE:
			return
		data[i] = id
		mt[i] = meta


var gen: WorldGen
var buf: GenChunk
var seed_value := 0
var _sink := ChunkSink.new()
var _rng := RandomNumberGenerator.new()
## Верхний «грунтовый» блок колонки (без листвы и растений) после деревьев и построек.
var _ground := PackedInt32Array()


func _init(p_gen: WorldGen) -> void:
	gen = p_gen
	seed_value = p_gen.seed_value
	_ground.resize(256)


func begin() -> void:
	buf = gen.buf


func _seed(salt: int) -> RandomNumberGenerator:
	_rng.seed = WorldGen.hash3(buf.cx, salt, buf.cz, seed_value) * 1000003 + salt * 7 + buf.cx
	return _rng


static func _ri(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 0:
		return 0
	return int(rng.randi() % n)


# --- Руды ------------------------------------------------------------------

## Руды 1.2 (generateOres): количество жил, размер и высоты — как в оригинале.
## part 0 — земля, гравий и уголь, part 1 — остальные руды (два этапа порционной генерации).
func ores(part: int) -> void:
	var rng := _seed(11 + part)
	if part == 0:
		for i in 20:
			_blob(rng, Blocks.DIRT, 0, 128)
		for i in 10:
			_blob(rng, Blocks.GRAVEL, 0, 128)
		for i in 20:
			_vein(rng, Blocks.COAL_ORE, 16, _ri(rng, 128))
		return
	for i in 20:
		_vein(rng, Blocks.IRON_ORE, 8, _ri(rng, 64))
	for i in 2:
		_vein(rng, Blocks.GOLD_ORE, 8, _ri(rng, 32))
	for i in 8:
		_vein(rng, Blocks.REDSTONE_ORE, 7, _ri(rng, 16))
	_vein(rng, Blocks.DIAMOND_ORE, 7, _ri(rng, 16))
	_vein(rng, Blocks.LAPIS_ORE, 6, _ri(rng, 16) + _ri(rng, 16))


## Жила (WorldGenMinable): цепочка шариков вдоль отрезка; заменяет только камень. Шарики
## округлены до клеток: 1, 7, 19 или 27 клеток вокруг точки в зависимости от радиуса.
func _vein(rng: RandomNumberGenerator, ore: int, n: int, y: int) -> void:
	var data := buf.blocks
	var bx := float(_ri(rng, 16)) + 0.5
	var bz := float(_ri(rng, 16)) + 0.5
	var ang := rng.randf() * PI
	var sx := sin(ang) * n / 8.0
	var sz := cos(ang) * n / 8.0
	var x0 := bx + sx
	var x1 := bx - sx
	var z0 := bz + sz
	var z1 := bz - sz
	var y0 := float(y + _ri(rng, 3) - 2) + 0.5
	var y1 := float(y + _ri(rng, 3) - 2) + 0.5
	for i in n + 1:
		var t := float(i) / n
		var px := floori(x0 + (x1 - x0) * t)
		var py := floori(y0 + (y1 - y0) * t)
		var pz := floori(z0 + (z1 - z0) * t)
		var size := rng.randf() * n / 16.0
		var r := ((sin(i * PI / n) + 1.0) * size + 1.0) * 0.5
		var count := 1
		if r >= 1.42:
			count = 27
		elif r >= 1.15:
			count = 19
		elif r >= 0.8:
			count = 7
		for k in count:
			var xx: int = px + VEIN_X[k]
			var yy: int = py + VEIN_Y[k]
			var zz: int = pz + VEIN_Z[k]
			if xx < 0 or xx > 15 or zz < 0 or zz > 15 or yy < 1 or yy > 250:
				continue
			var idx: int = xx + (zz << 4) + (yy << 8)
			if data[idx] == Blocks.STONE:
				data[idx] = ore


## Карман земли или гравия (жила размера 32 упрощена до одного эллипсоида того же объёма).
func _blob(rng: RandomNumberGenerator, id: int, y_min: int, y_max: int) -> void:
	var data := buf.blocks
	var cx := float(_ri(rng, 16))
	var cy := float(y_min + _ri(rng, y_max - y_min))
	var cz := float(_ri(rng, 16))
	var rx := 1.6 + rng.randf() * 1.6
	var ry := 1.2 + rng.randf() * 1.0
	var rz := 1.6 + rng.randf() * 1.6
	for zz in range(maxi(floori(cz - rz), 0), mini(floori(cz + rz), 15) + 1):
		var dz := (zz + 0.5 - cz) / rz
		for xx in range(maxi(floori(cx - rx), 0), mini(floori(cx + rx), 15) + 1):
			var dx := (xx + 0.5 - cx) / rx
			var hd := 1.0 - dx * dx - dz * dz
			if hd <= 0.0:
				continue
			var span := sqrt(hd) * ry
			for yy in range(maxi(ceili(cy - span - 0.5), 1), mini(floori(cy + span - 0.5), 250) + 1):
				var idx := xx + (zz << 4) + (yy << 8)
				if data[idx] == Blocks.STONE:
					data[idx] = id


# --- Подземелья ------------------------------------------------------------

## Данжи (8 попыток на чанк) и пустынный колодец.
func underground() -> void:
	var rng := _seed(14)
	for i in 8:
		var x := buf.ox + 4 + _ri(rng, 8)
		var y := _ri(rng, 128)
		var z := buf.oz + 4 + _ri(rng, 8)
		_dungeon(rng, x, y, z)
	var b := gen.local_biome(8, 8)
	if Biomes.is_desert(b) and _ri(rng, 1000) == 0:
		_desert_well(buf.ox + 5 + _ri(rng, 6), buf.oz + 5 + _ri(rng, 6))


static func _solid(id: int) -> bool:
	return id > 0 and Blocks.is_solid(id) and not Blocks.is_liquid(id)


## Данж (WorldGenDungeons): комната из булыжника и замшелого булыжника в толще камня с 1–5
## проёмами в пещеры, рассадник зомби/скелета/паука и до двух сундуков.
func _dungeon(rng: RandomNumberGenerator, x: int, y: int, z: int) -> void:
	var rx := _ri(rng, 2) + 2
	var rz := _ri(rng, 2) + 2
	if y < 5 or y > 120:
		return
	var data := buf.blocks
	var lx := x - buf.ox
	var lz := z - buf.oz
	# Сначала проёмы в стенах (чаще всего их нет — данж не ставится), потом пол и потолок.
	var holes := 0
	for dx in range(-rx - 1, rx + 2):
		for dz in range(-rz - 1, rz + 2):
			if dx != -rx - 1 and dx != rx + 1 and dz != -rz - 1 and dz != rz + 1:
				continue
			var i := (lx + dx) + ((lz + dz) << 4) + (y << 8)
			if data[i] == Blocks.AIR and data[i + 256] == Blocks.AIR:
				holes += 1
	if holes < 1 or holes > 5:
		return
	for dx in range(-rx - 1, rx + 2):
		for dz in range(-rz - 1, rz + 2):
			var i := (lx + dx) + ((lz + dz) << 4)
			if not _solid(data[i + ((y - 1) << 8)]) or not _solid(data[i + ((y + 4) << 8)]):
				return
	for dx in range(-rx - 1, rx + 2):
		for dy in range(4, -2, -1):
			for dz in range(-rz - 1, rz + 2):
				var px := x + dx
				var py := y + dy
				var pz := z + dz
				var wall := dx == -rx - 1 or dy == -1 or dz == -rz - 1 or dx == rx + 1 or dy == 4 or dz == rz + 1
				if not wall:
					buf.set_b(px, py, pz, Blocks.AIR)
				elif dy >= 0 and not _solid(buf.get_b(px, py - 1, pz)):
					buf.set_b(px, py, pz, Blocks.AIR)
				elif _solid(buf.get_b(px, py, pz)):
					if dy == -1 and _ri(rng, 4) != 0:
						buf.set_b(px, py, pz, Blocks.MOSSY_COBBLESTONE)
					else:
						buf.set_b(px, py, pz, Blocks.COBBLESTONE)
	for c in 2:
		for attempt in 3:
			var cx := x + _ri(rng, rx * 2 + 1) - rx
			var cz := z + _ri(rng, rz * 2 + 1) - rz
			if buf.get_b(cx, y, cz) != Blocks.AIR:
				continue
			var walls := 0
			var facing := 0
			for d in 4:
				var v: Vector3i = Blocks.DIR_VEC[d]
				if _solid(buf.get_b(cx + v.x, y, cz + v.z)):
					walls += 1
					facing = (d + 2) % 4
			if walls != 1:
				continue
			buf.add_chest(cx, y, cz, facing, Loot.dungeon_chest(rng))
			break
	var mob: int = [51, 54, 54, 52][_ri(rng, 4)]
	buf.add_spawner(x, y, z, mob)


## Пустынный колодец (появился в 1.2): песчаник, вода, плиты и навес на четырёх столбах.
func _desert_well(x: int, z: int) -> void:
	var y := buf.top_y(x, z, 140)
	if buf.get_b(x, y, z) != Blocks.SAND:
		return
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if buf.get_b(x + dx, y - 1, z + dz) == Blocks.AIR and buf.get_b(x + dx, y - 2, z + dz) == Blocks.AIR:
				return
	for dy in range(-1, 1):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				buf.set_b(x + dx, y + dy, z + dz, Blocks.SANDSTONE)
	buf.set_b(x, y, z, Blocks.WATER)
	for d in 4:
		var v: Vector3i = Blocks.DIR_VEC[d]
		buf.set_b(x + v.x, y, z + v.z, Blocks.WATER)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if absi(dx) == 2 or absi(dz) == 2:
				buf.set_b(x + dx, y + 1, z + dz, Blocks.SANDSTONE)
	for d in 4:
		var v: Vector3i = Blocks.DIR_VEC[d]
		buf.set_b(x + v.x * 2, y + 1, z + v.z * 2, Blocks.SLAB, 1)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if dx == 0 and dz == 0:
				buf.set_b(x, y + 4, z, Blocks.SANDSTONE)
			else:
				buf.set_b(x + dx, y + 4, z + dz, Blocks.SLAB, 1)
	for dy in range(1, 4):
		for c: Vector2i in [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]:
			buf.set_b(x + c.x, y + dy, z + c.y, Blocks.SANDSTONE)


# --- Деревья ---------------------------------------------------------------

## Число деревьев на чанк по биому (treesPerChunk 1.2; −1 — нет).
static func trees_per_chunk(b: int) -> int:
	match b:
		Biomes.FOREST, Biomes.FOREST_HILLS, Biomes.TAIGA, Biomes.TAIGA_HILLS:
			return 10
		Biomes.JUNGLE, Biomes.JUNGLE_HILLS:
			return 50
		Biomes.SWAMPLAND:
			return 2
		Biomes.PLAINS, Biomes.DESERT, Biomes.DESERT_HILLS, Biomes.BEACH, Biomes.MUSHROOM_ISLAND, Biomes.MUSHROOM_SHORE:
			return -1
	return 0


## Вид дерева по биому (getRandomWorldGenForTrees 1.2).
static func tree_kind(b: int, rng: RandomNumberGenerator) -> int:
	match b:
		Biomes.FOREST, Biomes.FOREST_HILLS:
			if _ri(rng, 5) == 0:
				return TreeGen.BIRCH
			return TreeGen.BIG_OAK if _ri(rng, 10) == 0 else TreeGen.OAK
		Biomes.TAIGA, Biomes.TAIGA_HILLS, Biomes.ICE_PLAINS, Biomes.ICE_MOUNTAINS:
			return TreeGen.PINE if _ri(rng, 3) == 0 else TreeGen.SPRUCE
		Biomes.SWAMPLAND:
			return TreeGen.SWAMP
		Biomes.JUNGLE, Biomes.JUNGLE_HILLS:
			if _ri(rng, 10) == 0:
				return TreeGen.BIG_OAK
			if _ri(rng, 2) == 0:
				return TreeGen.JUNGLE_BUSH
			if _ri(rng, 3) == 0:
				return TreeGen.HUGE_JUNGLE
			return TreeGen.JUNGLE
	return TreeGen.BIG_OAK if _ri(rng, 10) == 0 else TreeGen.OAK


## Кандидаты деревьев чанка-источника: [x, z, вид, сид]. Зависит только от сида и координат.
func tree_candidates(ocx: int, ocz: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.hash3(ocx, 1414, ocz, seed_value) * 7741 + ocx * 3 + ocz
	var b := gen.biome_at(ocx * 16 + 8, ocz * 16 + 8)
	var n := trees_per_chunk(b)
	if _ri(rng, 10) == 0:
		n += 1
	var out := []
	for i in maxi(n, 0):
		var x := ocx * 16 + _ri(rng, 16)
		var z := ocz * 16 + _ri(rng, 16)
		out.append([x, z, tree_kind(b, rng), int(rng.randi())])
	# Огромные грибы: грибные острова (1 на чанк), изредка — болота и леса.
	var big := 0
	if b == Biomes.MUSHROOM_ISLAND:
		big = 1
	elif (b == Biomes.SWAMPLAND or Biomes.is_forest(b)) and _ri(rng, 40) == 0:
		big = 1
	for i in big:
		var x := ocx * 16 + _ri(rng, 16)
		var z := ocz * 16 + _ri(rng, 16)
		var kind := TreeGen.HUGE_RED_MUSHROOM if _ri(rng, 2) == 0 else TreeGen.HUGE_BROWN_MUSHROOM
		out.append([x, z, kind, int(rng.randi())])
	return out


## Деревья из этого и соседних чанков, дотягивающиеся до этого чанка, — в едином порядке, поэтому
## перекрывающиеся кроны на границах одинаковы с обеих сторон. dz — ряд чанков-источников
## (три этапа порционной генерации).
func trees(dz: int) -> void:
	var rng := RandomNumberGenerator.new()
	for dx in range(-1, 2):
		for c: Array in tree_candidates(buf.cx + dx, buf.cz + dz):
			var x: int = c[0]
			var z: int = c[1]
			var kind: int = c[2]
			var reach: int = TreeGen.REACH[kind]
			if not buf.overlaps(x - reach, z - reach, x + reach + 1, z + reach + 1):
				continue
			var h := gen.get_height(x, z) if not buf.contains(x, z) else gen.heights[(x - buf.ox) + ((z - buf.oz) << 4)]
			if h < SEA or h > 200:
				continue
			var ground := gen.surface_block(x, z, h)
			var mushroom := kind == TreeGen.HUGE_RED_MUSHROOM or kind == TreeGen.HUGE_BROWN_MUSHROOM
			if mushroom:
				if ground != Blocks.MYCELIUM and ground != Blocks.GRASS and ground != Blocks.DIRT:
					continue
			elif ground != Blocks.GRASS and ground != Blocks.DIRT:
				continue
			if gen.structure_blocks_tree(x, z):
				continue
			rng.seed = int(c[3])
			_sink.aim(buf.blocks, buf.meta, x - buf.ox, h + 1, z - buf.oz, reach)
			TreeGen.build(kind, rng, _sink)
			if buf.contains(x, z) and not mushroom:
				buf.set_b(x, h, z, Blocks.DIRT)
				if kind == TreeGen.HUGE_JUNGLE:
					for o: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
						if buf.get_b(x + o.x, h, z + o.y) == Blocks.GRASS:
							buf.set_b(x + o.x, h, z + o.y, Blocks.DIRT)


# --- Поверхность ---------------------------------------------------------------

## Озёра, растения, снег и лёд, животные.
func surface() -> void:
	var rng := _seed(15)
	_lakes(rng)
	_compute_ground()
	var b := gen.local_biome(8, 8)
	_discs(rng, b)
	_plants(rng, b)
	_snow_and_ice()
	_animals(_seed(16), b)


## Верхний грунтовый блок каждой колонки (листва, брёвна наверху, растения и лианы пропускаются).
func _compute_ground() -> void:
	var data := buf.blocks
	var top := buf.top_layer(mini(gen.max_surface + 48, 255))
	for col in 256:
		var y := top
		while y > 0:
			var b := data[col + (y << 8)]
			if b != Blocks.AIR and b != Blocks.LEAVES and b != Blocks.VINE and b != Blocks.TALLGRASS:
				break
			y -= 1
		_ground[col] = y


func _ground_at(lx: int, lz: int) -> int:
	return _ground[lx + (lz << 4)]


func _block(lx: int, y: int, lz: int) -> int:
	return buf.blocks[lx + (lz << 4) + (y << 8)]


func _put(lx: int, y: int, lz: int, id: int, m: int = 0) -> void:
	var i := lx + (lz << 4) + (y << 8)
	buf.blocks[i] = id
	buf.meta[i] = m


## Озёра (WorldGenLakes): вода в 1/4 чанков, лава в 1/8 (над уровнем моря — редко).
## Озеро целиком внутри чанка; не ставится там, где уже стоит дерево.
func _lakes(rng: RandomNumberGenerator) -> void:
	if _ri(rng, 4) == 0:
		_lake(rng, Blocks.WATER, _ri(rng, 128))
	if _ri(rng, 8) == 0:
		var y := _ri(rng, _ri(rng, 120) + 8)
		if y < SEA or _ri(rng, 10) == 0:
			_lake(rng, Blocks.LAVA, y)


func _lake(rng: RandomNumberGenerator, liquid: int, y: int) -> void:
	var data := buf.blocks
	# Спуск до грунта (через воздух и растения).
	while y > 5:
		var b := data[8 + (8 << 4) + (y << 8)]
		if b != Blocks.AIR and b != Blocks.TALLGRASS and b != Blocks.DANDELION and b != Blocks.ROSE:
			break
		y -= 1
	if y <= 4:
		return
	y -= 4
	if y + 8 > 250:
		return
	var mask := PackedByteArray()
	mask.resize(2048)
	var n := _ri(rng, 4) + 4
	# Границы объединения эллипсоидов (+1) — только там нужны проверки берегов.
	var bx0 := 15
	var bx1 := 0
	var bz0 := 15
	var bz1 := 0
	for i in n:
		var sx := rng.randf() * 6.0 + 3.0
		var sy := rng.randf() * 4.0 + 2.0
		var sz := rng.randf() * 6.0 + 3.0
		var cx := rng.randf() * (16.0 - sx - 2.0) + 1.0 + sx / 2.0
		var cy := rng.randf() * (8.0 - sy - 4.0) + 2.0 + sy / 2.0
		var cz := rng.randf() * (16.0 - sz - 2.0) + 1.0 + sz / 2.0
		var ax := maxi(floori(cx - sx / 2.0), 1)
		var ex := mini(ceili(cx + sx / 2.0), 14)
		var az := maxi(floori(cz - sz / 2.0), 1)
		var ez := mini(ceili(cz + sz / 2.0), 14)
		bx0 = mini(bx0, ax)
		bx1 = maxi(bx1, ex)
		bz0 = mini(bz0, az)
		bz1 = maxi(bz1, ez)
		for x in range(ax, ex + 1):
			var dx := (x - cx) / (sx / 2.0)
			for z in range(az, ez + 1):
				var dz := (z - cz) / (sz / 2.0)
				var hd := dx * dx + dz * dz
				if hd >= 1.0:
					continue
				for yy in range(1, 7):
					var dy := (yy - cy) / (sy / 2.0)
					if hd + dy * dy < 1.0:
						mask[(x * 16 + z) * 8 + yy] = 1
	bx0 = maxi(bx0 - 1, 0)
	bz0 = maxi(bz0 - 1, 0)
	bx1 = mini(bx1 + 1, 15)
	bz1 = mini(bz1 + 1, 15)
	for x in range(bx0, bx1 + 1):
		for z in range(bz0, bz1 + 1):
			var base := x + (z << 4) + (y << 8)
			for yy in 8:
				var mi := (x * 16 + z) * 8 + yy
				if mask[mi] != 0:
					if data[base + (yy << 8)] == Blocks.LOG:
						return
					continue
				if not _lake_border(mask, x, z, yy):
					continue
				var b := data[base + (yy << 8)]
				if yy >= 4 and Blocks.is_liquid(b):
					return
				if yy < 4 and not _solid(b) and b != liquid:
					return
	var cold := Biomes.is_snowy(gen.local_biome(8, 8))
	for x in range(bx0, bx1 + 1):
		for z in range(bz0, bz1 + 1):
			for yy in 8:
				if mask[(x * 16 + z) * 8 + yy] == 0:
					continue
				var i := x + (z << 4) + ((y + yy) << 8)
				if data[i] == Blocks.LEAVES:
					continue
				data[i] = Blocks.AIR if yy >= 4 else liquid
				buf.meta[i] = 0
	# Трава (или мицелий) по берегам, где земля открыта небу.
	for x in range(bx0, bx1 + 1):
		for z in range(bz0, bz1 + 1):
			for yy in range(4, 8):
				if mask[(x * 16 + z) * 8 + yy] == 0:
					continue
				var below := x + (z << 4) + ((y + yy - 1) << 8)
				if data[below] == Blocks.DIRT:
					var bm := gen.local_biome(x, z)
					data[below] = Blocks.MYCELIUM if bm == Biomes.MUSHROOM_ISLAND else Blocks.GRASS
	if liquid == Blocks.LAVA:
		for x in range(bx0, bx1 + 1):
			for z in range(bz0, bz1 + 1):
				for yy in 8:
					if mask[(x * 16 + z) * 8 + yy] != 0:
						continue
					if _lake_border(mask, x, z, yy) and (yy < 4 or _ri(rng, 2) != 0):
						var i := x + (z << 4) + ((y + yy) << 8)
						if _solid(data[i]):
							data[i] = Blocks.STONE
	elif cold:
		for x in range(bx0, bx1 + 1):
			for z in range(bz0, bz1 + 1):
				var i := x + (z << 4) + ((y + 4) << 8)
				if data[i - 256] == Blocks.WATER and data[i] == Blocks.AIR:
					data[i - 256] = Blocks.ICE


## Клетка не в озере, но граничит с ним.
static func _lake_border(mask: PackedByteArray, x: int, z: int, yy: int) -> bool:
	var mi := (x * 16 + z) * 8 + yy
	return (x < 15 and mask[mi + 128] != 0) or (x > 0 and mask[mi - 128] != 0) \
		or (z < 15 and mask[mi + 8] != 0) or (z > 0 and mask[mi - 8] != 0) \
		or (yy < 7 and mask[mi + 1] != 0) or (yy > 0 and mask[mi - 1] != 0)


## Песок, глина и гравий на мелководье (WorldGenSand/WorldGenClay).
func _discs(rng: RandomNumberGenerator, b: int) -> void:
	for i in 3:
		_disc(rng, Blocks.SAND, 2 + _ri(rng, 5))
	var clay := 1
	if b == Biomes.SWAMPLAND:
		clay = 2
	for i in clay:
		_disc(rng, Blocks.CLAY, 2 + _ri(rng, 2))
	_disc(rng, Blocks.GRAVEL, 2 + _ri(rng, 4))


## Диск на мелководье: точка должна быть на поверхности воды, меняется земля на ±2 блока по высоте
## (поэтому песок и гравий окаймляют берега, а глубокое дно остаётся землёй, как в 1.2).
func _disc(rng: RandomNumberGenerator, id: int, r: int) -> void:
	var cx := _ri(rng, 16)
	var cz := _ri(rng, 16)
	var y := _ground_at(cx, cz)
	if _block(cx, y, cz) != Blocks.WATER:
		return
	var dy_r := 2 if id != Blocks.CLAY else 1
	for x in range(maxi(cx - r, 0), mini(cx + r, 15) + 1):
		for z in range(maxi(cz - r, 0), mini(cz + r, 15) + 1):
			if (x - cx) * (x - cx) + (z - cz) * (z - cz) > r * r:
				continue
			for yy in range(y - dy_r, y + dy_r + 1):
				if yy < 1:
					continue
				var cur := _block(x, yy, z)
				if cur == Blocks.DIRT or cur == Blocks.GRASS or (id == Blocks.CLAY and cur == Blocks.SAND):
					_put(x, yy, z, id)


## Растения по биому (BiomeDecorator.decorate 1.2).
func _plants(rng: RandomNumberGenerator, b: int) -> void:
	var flowers := 2
	var grass := 1
	var dead := 0
	var mushrooms := 0
	var reeds := 0
	var cacti := 0
	var lilies := 0
	match b:
		Biomes.PLAINS:
			flowers = 4
			grass = 10
		Biomes.FOREST, Biomes.FOREST_HILLS:
			grass = 2
		Biomes.TAIGA, Biomes.TAIGA_HILLS:
			grass = 1
		Biomes.DESERT, Biomes.DESERT_HILLS:
			flowers = 0
			grass = 0
			dead = 2
			reeds = 50
			cacti = 10
		Biomes.SWAMPLAND:
			flowers = 0
			dead = 1
			mushrooms = 8
			reeds = 10
			lilies = 4
		Biomes.JUNGLE, Biomes.JUNGLE_HILLS:
			flowers = 4
			grass = 25
		Biomes.MUSHROOM_ISLAND, Biomes.MUSHROOM_SHORE:
			flowers = 0
			grass = 0
			mushrooms = 1
		Biomes.BEACH:
			flowers = 0
			grass = 0
	for i in flowers:
		_cluster(rng, Blocks.DANDELION, 0, FLOWER_TRIES)
		if _ri(rng, 4) == 0:
			_cluster(rng, Blocks.ROSE, 0, FLOWER_TRIES)
	for i in grass:
		var m := 1
		if Biomes.is_jungle(b) and _ri(rng, 4) == 0:
			m = 2
		elif Biomes.is_taiga(b) and _ri(rng, 3) != 0:
			m = 2
		_cluster(rng, Blocks.TALLGRASS, m, GRASS_TRIES)
	for i in dead:
		_cluster(rng, Blocks.DEADBUSH, 0, 4)
	for i in lilies:
		_lilies(rng)
	for i in mushrooms:
		if _ri(rng, 4) == 0:
			_cluster(rng, Blocks.BROWN_MUSHROOM, 0, 10)
		if _ri(rng, 8) == 0:
			_cluster(rng, Blocks.RED_MUSHROOM, 0, 10)
	if _ri(rng, 4) == 0:
		_cluster(rng, Blocks.BROWN_MUSHROOM, 0, 10)
	if _ri(rng, 8) == 0:
		_cluster(rng, Blocks.RED_MUSHROOM, 0, 10)
	_cave_mushrooms(rng)
	for i in reeds + 10:
		_reeds(rng)
	if _ri(rng, 32) == 0:
		_cluster(rng, Blocks.PUMPKIN, 0, 12)
	for i in cacti:
		_cacti(rng)
	if Biomes.is_jungle(b):
		if _ri(rng, 4) == 0:
			_cluster(rng, Blocks.MELON, 0, 12)
		for i in 30:
			_vines(rng)


## Кучка растений вокруг случайной точки чанка (на траве; мёртвые кусты — на песке).
func _cluster(rng: RandomNumberGenerator, id: int, m: int, tries: int) -> void:
	var cx := _ri(rng, 16)
	var cz := _ri(rng, 16)
	for t in tries:
		var x := cx + _ri(rng, 8) - _ri(rng, 8)
		var z := cz + _ri(rng, 8) - _ri(rng, 8)
		if x < 0 or x > 15 or z < 0 or z > 15:
			continue
		var y := _ground_at(x, z)
		if y < 1 or y > 250 or _block(x, y + 1, z) != Blocks.AIR:
			continue
		var g := _block(x, y, z)
		match id:
			Blocks.DEADBUSH:
				if g != Blocks.SAND:
					continue
			Blocks.BROWN_MUSHROOM, Blocks.RED_MUSHROOM:
				# Грибы — только в тени (под листвой) или на мицелии.
				if g != Blocks.MYCELIUM and not (Blocks.is_opaque(g) and _shaded(x, y, z)):
					continue
			Blocks.PUMPKIN, Blocks.MELON:
				if g != Blocks.GRASS:
					continue
				_put(x, y + 1, z, id, _ri(rng, 4) if id == Blocks.PUMPKIN else 0)
				continue
			_:
				if g != Blocks.GRASS:
					continue
		_put(x, y + 1, z, id, m)


func _shaded(x: int, y: int, z: int) -> bool:
	for yy in range(y + 2, mini(y + 12, 255)):
		if _block(x, yy, z) == Blocks.LEAVES:
			return true
	return false


## Грибы в пещерах (случайная высота).
func _cave_mushrooms(rng: RandomNumberGenerator) -> void:
	for i in 2:
		var x := _ri(rng, 16)
		var z := _ri(rng, 16)
		var top := gen.heights[x + (z << 4)] - 4
		if top < 12:
			continue
		var y := 6 + _ri(rng, top - 6)
		while y > 5 and _block(x, y, z) == Blocks.AIR:
			y -= 1
		if _block(x, y, z) == Blocks.STONE and _block(x, y + 1, z) == Blocks.AIR:
			_put(x, y + 1, z, Blocks.BROWN_MUSHROOM if _ri(rng, 3) != 0 else Blocks.RED_MUSHROOM)


func _lilies(rng: RandomNumberGenerator) -> void:
	var cx := _ri(rng, 16)
	var cz := _ri(rng, 16)
	for t in 10:
		var x := cx + _ri(rng, 8) - _ri(rng, 8)
		var z := cz + _ri(rng, 8) - _ri(rng, 8)
		if x < 0 or x > 15 or z < 0 or z > 15:
			continue
		var y := _ground_at(x, z)
		if _block(x, y, z) == Blocks.WATER and _block(x, y + 1, z) == Blocks.AIR:
			_put(x, y + 1, z, Blocks.WATERLILY)


## Сахарный тростник (WorldGenReed): у воды на траве, земле или песке, 2–4 блока.
func _reeds(rng: RandomNumberGenerator) -> void:
	var cx := _ri(rng, 16)
	var cz := _ri(rng, 16)
	for t in 20:
		var x := cx + _ri(rng, 4) - _ri(rng, 4)
		var z := cz + _ri(rng, 4) - _ri(rng, 4)
		if x < 1 or x > 14 or z < 1 or z > 14:
			continue
		var y := _ground_at(x, z)
		var g := _block(x, y, z)
		if g != Blocks.GRASS and g != Blocks.DIRT and g != Blocks.SAND:
			continue
		if _block(x, y + 1, z) != Blocks.AIR:
			continue
		var wet := false
		for d in 4:
			var v: Vector3i = Blocks.DIR_VEC[d]
			if _block(x + v.x, y, z + v.z) == Blocks.WATER:
				wet = true
		if not wet:
			continue
		var h := 2 + _ri(rng, _ri(rng, 3) + 1)
		for k in h:
			if _block(x, y + 1 + k, z) != Blocks.AIR:
				break
			_put(x, y + 1 + k, z, Blocks.REEDS)


## Кактусы (WorldGenCactus): на песке, без соседних блоков, высота 1–3.
func _cacti(rng: RandomNumberGenerator) -> void:
	var cx := _ri(rng, 16)
	var cz := _ri(rng, 16)
	for t in 10:
		var x := cx + _ri(rng, 8) - _ri(rng, 8)
		var z := cz + _ri(rng, 8) - _ri(rng, 8)
		if x < 1 or x > 14 or z < 1 or z > 14:
			continue
		var y := _ground_at(x, z)
		if _block(x, y, z) != Blocks.SAND:
			continue
		var h := 1 + _ri(rng, _ri(rng, 3) + 1)
		for k in h:
			var yy := y + 1 + k
			if _block(x, yy, z) != Blocks.AIR:
				break
			var free := true
			for d in 4:
				var v: Vector3i = Blocks.DIR_VEC[d]
				if _block(x + v.x, yy, z + v.z) != Blocks.AIR:
					free = false
			if not free:
				break
			_put(x, yy, z, Blocks.CACTUS)


## Лианы джунглей (WorldGenVines): на стенах, стволах и листве над землёй.
func _vines(rng: RandomNumberGenerator) -> void:
	var data := buf.blocks
	var x := 1 + _ri(rng, 14)
	var z := 1 + _ri(rng, 14)
	var col := x + (z << 4)
	var y0 := _ground[col] + 1
	for y in range(y0, mini(y0 + 16, 250)):
		var i := col + (y << 8)
		if data[i] != Blocks.AIR:
			continue
		for d in 4:
			var v: Vector3i = Blocks.DIR_VEC[d]
			var w := data[i - v.x - (v.z << 4)]
			if w == Blocks.LOG or w == Blocks.LEAVES or Blocks.opaque_flags[w] != 0:
				data[i] = Blocks.VINE
				buf.meta[i] = 1 << d
				break


## Снег и лёд в холодных биомах (как в конце populate 1.2).
func _snow_and_ice() -> void:
	var data := buf.blocks
	var top := -1
	for col in 256:
		var b := gen.local_biome(col & 15, col >> 4)
		if not Biomes.is_snowy(b):
			continue
		if top < 0:
			top = buf.top_layer(mini(gen.max_surface + 48, 254))
		var y := top
		while y > 0 and data[col + (y << 8)] == Blocks.AIR:
			y -= 1
		var cur := data[col + (y << 8)]
		if cur == Blocks.WATER:
			data[col + (y << 8)] = Blocks.ICE
		elif Blocks.is_opaque(cur) or cur == Blocks.LEAVES:
			if cur != Blocks.ICE:
				data[col + ((y + 1) << 8)] = Blocks.SNOW_LAYER
				buf.meta[col + ((y + 1) << 8)] = 0


# --- Животные --------------------------------------------------------------

## Животные при генерации чанка (SpawnerAnimals.performWorldGenSpawning): в среднем каждый
## десятый чанк получает стайку из четырёх животных биома.
func _animals(rng: RandomNumberGenerator, b: int) -> void:
	var table := _creatures(b)
	if table.is_empty():
		return
	var total := 0
	for e: Array in table:
		total += int(e[1])
	while rng.randf() < 0.1:
		var r := _ri(rng, total)
		var type := 0
		for e: Array in table:
			r -= int(e[1])
			if r < 0:
				type = e[0]
				break
		var cx := _ri(rng, 16)
		var cz := _ri(rng, 16)
		var group := 4 if type != 98 else 1
		for k in group:
			var x := clampi(cx + _ri(rng, 5) - _ri(rng, 5), 0, 15)
			var z := clampi(cz + _ri(rng, 5) - _ri(rng, 5), 0, 15)
			var y := _ground_at(x, z)
			var g := _block(x, y, z)
			if not Blocks.is_opaque(g) or _block(x, y + 1, z) != Blocks.AIR or _block(x, y + 2, z) != Blocks.AIR:
				continue
			if type == 96 and g != Blocks.MYCELIUM:
				continue
			buf.add_mob(type, buf.ox + x + 0.5, y + 1.0, buf.oz + z + 0.5)


## [тип моба, вес] по биому (spawnableCreatureList 1.2).
static func _creatures(b: int) -> Array:
	match b:
		Biomes.OCEAN, Biomes.FROZEN_OCEAN, Biomes.RIVER, Biomes.FROZEN_RIVER, Biomes.BEACH, Biomes.DESERT, \
				Biomes.DESERT_HILLS, Biomes.MUSHROOM_SHORE:
			return []
		Biomes.MUSHROOM_ISLAND:
			return [[96, 8]]
		Biomes.FOREST, Biomes.FOREST_HILLS, Biomes.TAIGA, Biomes.TAIGA_HILLS:
			return [[91, 12], [90, 10], [93, 10], [92, 8], [95, 5]]
		Biomes.JUNGLE, Biomes.JUNGLE_HILLS:
			return [[91, 12], [90, 10], [93, 10], [92, 8], [98, 2]]
	return [[91, 12], [90, 10], [93, 10], [92, 8]]
