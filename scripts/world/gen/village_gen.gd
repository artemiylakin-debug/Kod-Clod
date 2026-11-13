class_name VillageGen
extends RefCounted
## Деревни NPC, как MapGenVillage/StructureVillagePieces в 1.2: колодец в центре, гравийные
## дороги (в пустыне — песчаник), вдоль них — домики, хижины, библиотека, мясная лавка,
## кузница с сундуком, церковь с башней, большие и малые поля пшеницы, фонари; жители.
## Деревни бывают в равнинах и пустынях: одна попытка на область 32×32 чанка (смещение до 24).
## План деревни целиком задаётся сидом; высота пола каждого дома — средняя высота рельефа под
## ним (по той же формуле, что и сам рельеф), поэтому части домов в разных чанках совпадают.

enum { WELL, ROAD, HOUSE_SMALL, HUT, LIBRARY, BUTCHER, BLACKSMITH, CHURCH, FARM_SMALL, FARM_LARGE, LAMP, HOUSE_BIG }

const REGION := 32
const SPREAD := 24
## Наибольшее удаление частей от центра (блоки).
const MAX_DIST := 88
## Радиус (в чанках), на котором чанку нужно знать о деревне.
const REACH_CHUNKS := 7
## Вид → [ширина, высота, глубина, x двери, вес, мин, макс] (веса и лимиты — как в 1.2).
static var TYPES := {
	HOUSE_SMALL: [5, 6, 5, 2, 4, 2, 4],
	CHURCH: [5, 13, 9, 2, 20, 0, 1],
	LIBRARY: [9, 8, 6, 1, 20, 0, 2],
	HUT: [4, 6, 5, 1, 3, 2, 5],
	BUTCHER: [9, 7, 11, 4, 15, 0, 2],
	FARM_LARGE: [13, 4, 9, 6, 3, 1, 4],
	FARM_SMALL: [7, 4, 9, 3, 3, 2, 4],
	BLACKSMITH: [10, 6, 7, 2, 15, 0, 1],
	HOUSE_BIG: [9, 8, 7, 4, 8, 0, 3],
}
## Профессии жителей 1.2: 0 фермер, 1 библиотекарь, 2 священник, 3 кузнец, 4 мясник.
static var VILLAGERS := {
	HOUSE_SMALL: [0], HUT: [0], LIBRARY: [1], BUTCHER: [4, 0], BLACKSMITH: [3], CHURCH: [2], HOUSE_BIG: [0, 0],
}

var gen: WorldGen
var seed_value := 0
var _desert := false


func _init(p_gen: WorldGen) -> void:
	gen = p_gen
	seed_value = p_gen.seed_value


static func _ri(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 0:
		return 0
	return int(rng.randi() % n)


## Деревни, которые могут задеть чанк (cx, cz): [{"pieces", "desert", "x", "z"}, …].
func villages_near(cx: int, cz: int) -> Array:
	var out := []
	var rx0 := floori(float(cx - REACH_CHUNKS) / REGION)
	var rx1 := floori(float(cx + REACH_CHUNKS) / REGION)
	var rz0 := floori(float(cz - REACH_CHUNKS) / REGION)
	var rz1 := floori(float(cz + REACH_CHUNKS) / REGION)
	for rz in range(rz0, rz1 + 1):
		for rx in range(rx0, rx1 + 1):
			var v := village_in_region(rx, rz, cx, cz)
			if not v.is_empty():
				out.append(v)
	return out


## Деревня области (rx, rz), если она есть и её центр не дальше REACH_CHUNKS от чанка (cx, cz).
func village_in_region(rx: int, rz: int, cx: int, cz: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.hash3(rx, 10387312, rz, seed_value) * 341873128712 + rx * 132897987541 + rz
	var scx := rx * REGION + _ri(rng, SPREAD)
	var scz := rz * REGION + _ri(rng, SPREAD)
	if absi(scx - cx) > REACH_CHUNKS or absi(scz - cz) > REACH_CHUNKS:
		return {}
	var x := scx * 16 + 8
	var z := scz * 16 + 8
	var b := gen.biome_at(x, z)
	if b != Biomes.PLAINS and b != Biomes.DESERT:
		return {}
	var pieces := _layout(x, z, rng)
	if pieces.is_empty():
		return {}
	return {"pieces": pieces, "desert": b == Biomes.DESERT, "x": x, "z": z}


## Центр деревни области (для поиска, тестов и отладки) или (1<<30, 0), если её нет.
func village_center(rx: int, rz: int) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.hash3(rx, 10387312, rz, seed_value) * 341873128712 + rx * 132897987541 + rz
	var scx := rx * REGION + _ri(rng, SPREAD)
	var scz := rz * REGION + _ri(rng, SPREAD)
	var v := village_in_region(rx, rz, scx, scz)
	if v.is_empty():
		return Vector2i(1 << 30, 0)
	return Vector2i(int(v["x"]), int(v["z"]))


# --- План ------------------------------------------------------------------

func _layout(x: int, z: int, rng: RandomNumberGenerator) -> Array:
	var pieces: Array = []
	var left := {}
	for t: int in TYPES:
		var info: Array = TYPES[t]
		left[t] = int(info[5]) + _ri(rng, int(info[6]) - int(info[5]) + 1)
	var well := GenPiece.make(WELL, 0, x - 3, 0, z - 3, 0, 0, 6, 9, 6)
	well.seed = int(rng.randi())
	pieces.append(well)
	var queue := []
	for side in 4:
		var e := Vector3i.ZERO
		match side:
			0:
				e = well.world(2, 0, 6)
			1:
				e = well.world(-1, 0, 3)
			2:
				e = well.world(3, 0, -1)
			3:
				e = well.world(6, 0, 2)
		queue.append([e.x, e.z, well.dir(side), 0])
	var houses := 0
	var qi := 0
	while qi < queue.size() and qi < 40:
		var q: Array = queue[qi]
		qi += 1
		houses += _road(int(q[0]), int(q[1]), int(q[2]), int(q[3]), x, z, pieces, queue, left, rng)
	if houses < 3:
		return []
	return pieces


func _road(ex: int, ez: int, d: int, depth: int, cx: int, cz: int, pieces: Array, queue: Array, left: Dictionary,
		rng: RandomNumberGenerator) -> int:
	var length := 11 + _ri(rng, 16)
	var road: GenPiece = null
	while length >= 5:
		road = GenPiece.make(ROAD, d, ex, 0, ez, 1, 0, 3, 1, length)
		if not _collides(road, pieces) and _in_range(road, cx, cz):
			break
		road = null
		length -= 3
	if road == null:
		return 0
	road.seed = int(rng.randi())
	pieces.append(road)
	var placed := 0
	for side: int in [1, 3]:
		var t := _ri(rng, 3)
		while t < length - 2:
			var kind := _pick(left, rng)
			if kind < 0:
				break
			var info: Array = TYPES[kind]
			var e := road.world(-1 if side == 1 else 3, 0, t)
			var house := GenPiece.make(kind, road.dir(side), e.x, 0, e.z, int(info[3]), 0, int(info[0]), int(info[1]), int(info[2]))
			if not _collides(house, pieces) and _in_range(house, cx, cz):
				house.seed = int(rng.randi())
				house.data = int(rng.randi() & 0xFFFF)
				pieces.append(house)
				left[kind] = int(left[kind]) - 1
				placed += 1
				t += int(info[0]) + 1 + _ri(rng, 2)
			else:
				t += 2 + _ri(rng, 2)
	# Фонарь у начала дороги.
	if _ri(rng, 2) == 0:
		var e := road.world(-2, 0, 1)
		var lamp := GenPiece.make(LAMP, 0, e.x - 1, 0, e.z - 1, 0, 0, 3, 5, 3)
		if not _collides(lamp, pieces):
			lamp.seed = int(rng.randi())
			pieces.append(lamp)
	# Продолжение и ответвления.
	if depth < 4 and _ri(rng, 3) != 0:
		var e := road.world(1, 0, length)
		queue.append([e.x, e.z, d, depth + 1])
	if depth < 3:
		if _ri(rng, 5) < 2:
			var e := road.world(-1, 0, length - 2)
			queue.append([e.x, e.z, road.dir(1), depth + 1])
		if _ri(rng, 5) < 2:
			var e := road.world(3, 0, length - 2)
			queue.append([e.x, e.z, road.dir(3), depth + 1])
	return placed


func _pick(left: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0
	for t: int in left:
		if int(left[t]) > 0:
			total += int(TYPES[t][4])
	if total == 0:
		return -1
	var r := _ri(rng, total)
	for t: int in left:
		if int(left[t]) > 0:
			r -= int(TYPES[t][4])
			if r < 0:
				return t
	return -1


static func _collides(p: GenPiece, pieces: Array) -> bool:
	for o: GenPiece in pieces:
		if p.overlaps(o):
			return true
	return false


static func _in_range(p: GenPiece, cx: int, cz: int) -> bool:
	var mx := (p.x0 + p.x1) * 0.5 - cx
	var mz := (p.z0 + p.z1) * 0.5 - cz
	return mx * mx + mz * mz <= MAX_DIST * MAX_DIST


## Мешает ли деревня дереву в колонке (x, z).
static func blocks_tree(v: Dictionary, x: int, z: int) -> bool:
	for p: GenPiece in v["pieces"]:
		if p.contains_xz(x, z, 2):
			return true
	return false


# --- Постройка -------------------------------------------------------------

## Рисует части деревни, задевающие чанк.
func draw(v: Dictionary, buf: GenChunk) -> void:
	_desert = v["desert"]
	for p: GenPiece in v["pieces"]:
		if not buf.overlaps(p.x0 - 1, p.z0 - 1, p.x1 + 1, p.z1 + 1):
			continue
		if p.kind == ROAD:
			_draw_road(p, buf)
			continue
		if p.ground < 0:
			p.ground = _ground_level(p)
			var h := p.y1 - p.y0
			p.y0 = p.ground
			p.y1 = p.ground + h
		match p.kind:
			WELL:
				_well(p, buf)
			HOUSE_SMALL:
				_house_small(p, buf)
			HUT:
				_hut(p, buf)
			LIBRARY:
				_library(p, buf)
			BUTCHER:
				_butcher(p, buf)
			BLACKSMITH:
				_blacksmith(p, buf)
			CHURCH:
				_church(p, buf)
			FARM_SMALL:
				_farm(p, buf, false)
			FARM_LARGE:
				_farm(p, buf, true)
			LAMP:
				_lamp(p, buf)
			HOUSE_BIG:
				_house_big(p, buf)
		if VILLAGERS.has(p.kind):
			var profs: Array = VILLAGERS[p.kind]
			for i in profs.size():
				var c := p.world(1 + i, 1, 1 + i % 2)
				if buf.contains(c.x, c.z):
					buf.entities.append({"kind": "mob", "type": 120, "pos": [c.x + 0.5, float(c.y), c.z + 0.5],
						"profession": int(profs[i])})


## Средняя высота земли под частью (вода считается уровнем моря).
func _ground_level(p: GenPiece) -> int:
	var sum := 0
	var pts := [Vector2i(p.x0, p.z0), Vector2i(p.x1, p.z0), Vector2i(p.x0, p.z1), Vector2i(p.x1, p.z1),
		Vector2i((p.x0 + p.x1) >> 1, (p.z0 + p.z1) >> 1)]
	for q: Vector2i in pts:
		sum += maxi(gen.get_height(q.x, q.y), WorldGen.SEA_LEVEL)
	@warning_ignore("integer_division")
	return sum / pts.size()


## Блок с учётом пустыни (как getBiomeSpecificBlock в 1.2).
func _v(id: int) -> int:
	if not _desert:
		return id
	match id:
		Blocks.LOG, Blocks.COBBLESTONE, Blocks.PLANKS, Blocks.GRAVEL:
			return Blocks.SANDSTONE
		Blocks.OAK_STAIRS:
			return Blocks.COBBLESTONE_STAIRS
	return id


func _draw_road(p: GenPiece, buf: GenChunk) -> void:
	var top_id := _v(Blocks.GRAVEL)
	for lz in p.size_z():
		for lx in 3:
			var x := p.wx(lx, lz)
			var z := p.wz(lx, lz)
			if not buf.contains(x, z):
				continue
			var col := (x - buf.ox) + ((z - buf.oz) << 4)
			var y := buf.top_y(x, z, gen.heights[col] + 2)
			var b := buf.get_b(x, y, z)
			if b == Blocks.WATER or b == Blocks.ICE:
				buf.set_b(x, y, z, _v(Blocks.PLANKS))
			elif b != Blocks.AIR:
				buf.set_b(x, y, z, top_id)
			if buf.get_b(x, y + 1, z) == Blocks.SNOW_LAYER:
				buf.set_b(x, y + 1, z, Blocks.AIR)


## Расчистка объёма над полом и фундамент из булыжника под ним.
func _prepare(p: GenPiece, buf: GenChunk, sx: int, sz: int, h: int) -> void:
	p.fill(buf, 0, 1, 0, sx - 1, h, sz - 1, Blocks.AIR)
	for lz in sz:
		for lx in sx:
			p.foundation(buf, lx, -1, lz, _v(Blocks.COBBLESTONE))
			p.clear_above(buf, lx, h + 1, lz, 8)


## Стены из досок с брёвнами по углам, нижний ряд и пол — булыжник.
func _walls(p: GenPiece, buf: GenChunk, sx: int, sz: int, top: int) -> void:
	var c := _v(Blocks.COBBLESTONE)
	var pl := _v(Blocks.PLANKS)
	var lg := _v(Blocks.LOG)
	p.fill(buf, 0, 0, 0, sx - 1, 0, sz - 1, c)
	p.fill(buf, 0, 1, 0, sx - 1, 1, sz - 1, c)
	p.fill(buf, 0, 2, 0, sx - 1, top, sz - 1, pl)
	p.fill(buf, 1, 1, 1, sx - 2, top, sz - 2, Blocks.AIR)
	for q: Vector2i in [Vector2i(0, 0), Vector2i(sx - 1, 0), Vector2i(0, sz - 1), Vector2i(sx - 1, sz - 1)]:
		p.fill(buf, q.x, 1, q.y, q.x, top, q.y, lg)


## Двускатная крыша из ступенек вдоль оси x, фронтоны — доски.
func _roof(p: GenPiece, buf: GenChunk, sx: int, sz: int, y: int) -> void:
	var st := _v(Blocks.OAK_STAIRS)
	var pl := _v(Blocks.PLANKS)
	@warning_ignore("integer_division")
	var rows := (sz + 1) / 2
	for k in rows:
		var yy := y + k
		p.fill(buf, -1, yy, k, sx, yy, k, st, p.dir(0))
		p.fill(buf, -1, yy, sz - 1 - k, sx, yy, sz - 1 - k, st, p.dir(2))
		if sz - 2 - k > k:
			p.fill(buf, 0, yy, k + 1, 0, yy, sz - 2 - k, pl)
			p.fill(buf, sx - 1, yy, k + 1, sx - 1, yy, sz - 2 - k, pl)
	if sz % 2 == 1:
		p.fill(buf, -1, y + rows - 1, rows - 1, sx, y + rows - 1, rows - 1, _v(Blocks.PLANKS))


func _well(p: GenPiece, buf: GenChunk) -> void:
	var c := _v(Blocks.COBBLESTONE)
	p.fill(buf, 0, 1, 0, 5, 6, 5, Blocks.AIR)
	p.fill(buf, 0, 0, 0, 5, 0, 5, _v(Blocks.GRAVEL))
	for lz in 6:
		for lx in 6:
			p.foundation(buf, lx, -1, lz, c)
	p.fill(buf, 1, -4, 1, 4, 1, 4, c)
	p.fill(buf, 2, -3, 2, 3, 1, 3, Blocks.WATER)
	p.fill(buf, 2, 1, 2, 3, 1, 3, Blocks.AIR)
	for q: Vector2i in [Vector2i(1, 1), Vector2i(4, 1), Vector2i(1, 4), Vector2i(4, 4)]:
		p.fill(buf, q.x, 2, q.y, q.x, 3, q.y, Blocks.FENCE)
	p.fill(buf, 1, 4, 1, 4, 4, 4, c)


func _house_small(p: GenPiece, buf: GenChunk) -> void:
	_prepare(p, buf, 5, 5, 5)
	var lg := _v(Blocks.LOG)
	var pl := _v(Blocks.PLANKS)
	p.fill(buf, 0, 0, 0, 4, 0, 4, _v(Blocks.COBBLESTONE))
	p.fill(buf, 0, 1, 0, 4, 3, 4, pl)
	p.fill(buf, 1, 1, 1, 3, 3, 3, Blocks.AIR)
	for q: Vector2i in [Vector2i(0, 0), Vector2i(4, 0), Vector2i(0, 4), Vector2i(4, 4)]:
		p.fill(buf, q.x, 1, q.y, q.x, 3, q.y, lg)
	p.fill(buf, 0, 4, 0, 4, 4, 4, lg)
	p.fill(buf, 1, 4, 1, 3, 4, 3, pl)
	p.put(buf, 0, 2, 2, Blocks.GLASS_PANE)
	p.put(buf, 4, 2, 2, Blocks.GLASS_PANE)
	p.put(buf, 2, 2, 4, Blocks.GLASS_PANE)
	p.door(buf, 2, 1, 0, Blocks.WOODEN_DOOR, 2)
	p.torch(buf, 2, 3, 3, 0)
	if p.data & 1:
		# Плоская крыша с оградой и лестницей.
		p.fill(buf, 0, 5, 0, 4, 5, 4, Blocks.FENCE)
		p.fill(buf, 1, 5, 1, 3, 5, 3, Blocks.AIR)
		p.fill(buf, 3, 1, 3, 3, 4, 3, Blocks.LADDER, p.dir(2))


func _hut(p: GenPiece, buf: GenChunk) -> void:
	var tall := (p.data & 2) != 0
	var top := 4 if tall else 3
	_prepare(p, buf, 4, 5, top + 1)
	var lg := _v(Blocks.LOG)
	p.fill(buf, 0, 0, 0, 3, 0, 4, _v(Blocks.COBBLESTONE))
	p.fill(buf, 1, 0, 1, 2, 0, 3, Blocks.DIRT)
	p.fill(buf, 0, 1, 0, 3, top, 4, _v(Blocks.PLANKS))
	p.fill(buf, 1, 1, 1, 2, top, 3, Blocks.AIR)
	for q: Vector2i in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 4), Vector2i(3, 4)]:
		p.fill(buf, q.x, 1, q.y, q.x, top, q.y, lg)
	p.fill(buf, 0, top + 1, 0, 3, top + 1, 4, lg)
	p.put(buf, 0, 2, 2, Blocks.GLASS_PANE)
	p.put(buf, 3, 2, 2, Blocks.GLASS_PANE)
	p.door(buf, 1, 1, 0, Blocks.WOODEN_DOOR, 2)
	p.put(buf, 2, 1, 3, Blocks.FENCE)
	p.put(buf, 2, 2, 3, Blocks.WOODEN_PLATE)


func _library(p: GenPiece, buf: GenChunk) -> void:
	_prepare(p, buf, 9, 6, 7)
	_walls(p, buf, 9, 6, 3)
	_roof(p, buf, 9, 6, 4)
	for lx: int in [3, 5, 7]:
		p.put(buf, lx, 2, 0, Blocks.GLASS_PANE)
		p.put(buf, lx, 2, 5, Blocks.GLASS_PANE)
	p.put(buf, 0, 2, 2, Blocks.GLASS_PANE)
	p.put(buf, 8, 2, 3, Blocks.GLASS_PANE)
	p.door(buf, 1, 1, 0, Blocks.WOODEN_DOOR, 2)
	p.fill(buf, 1, 1, 4, 7, 2, 4, Blocks.BOOKSHELF)
	p.put(buf, 7, 1, 1, Blocks.CRAFTING_TABLE)
	p.put(buf, 4, 1, 2, Blocks.FENCE)
	p.put(buf, 4, 2, 2, Blocks.WOODEN_PLATE)
	p.put(buf, 3, 1, 2, _v(Blocks.OAK_STAIRS), p.dir(1))
	p.put(buf, 5, 1, 2, _v(Blocks.OAK_STAIRS), p.dir(3))
	p.torch(buf, 4, 3, 1, 2)


func _butcher(p: GenPiece, buf: GenChunk) -> void:
	_prepare(p, buf, 9, 6, 7)
	_walls(p, buf, 9, 6, 3)
	_roof(p, buf, 9, 6, 4)
	# Огороженный двор за домом.
	p.fill(buf, 0, 1, 6, 8, 5, 10, Blocks.AIR)
	for lz in range(6, 11):
		for lx in 9:
			p.foundation(buf, lx, 0, lz, Blocks.DIRT)
			p.put(buf, lx, 0, lz, Blocks.GRASS)
	p.fill(buf, 0, 1, 10, 8, 1, 10, Blocks.FENCE)
	p.fill(buf, 0, 1, 6, 0, 1, 10, Blocks.FENCE)
	p.fill(buf, 8, 1, 6, 8, 1, 10, Blocks.FENCE)
	p.put(buf, 2, 2, 0, Blocks.GLASS_PANE)
	p.put(buf, 6, 2, 0, Blocks.GLASS_PANE)
	p.put(buf, 0, 2, 3, Blocks.GLASS_PANE)
	p.put(buf, 8, 2, 3, Blocks.GLASS_PANE)
	p.door(buf, 4, 1, 0, Blocks.WOODEN_DOOR, 2)
	p.door(buf, 4, 1, 5, Blocks.WOODEN_DOOR, 0)
	p.fill(buf, 1, 1, 4, 3, 1, 4, Blocks.SLAB, 0)
	p.put(buf, 6, 1, 3, Blocks.SLAB, 0)
	p.put(buf, 6, 1, 2, _v(Blocks.OAK_STAIRS), p.dir(0))
	p.torch(buf, 2, 3, 1, 2)


func _blacksmith(p: GenPiece, buf: GenChunk) -> void:
	_prepare(p, buf, 10, 7, 5)
	var c := _v(Blocks.COBBLESTONE)
	p.fill(buf, 0, 0, 0, 9, 0, 6, c)
	p.fill(buf, 0, 1, 6, 9, 3, 6, c)
	p.fill(buf, 9, 1, 0, 9, 3, 6, c)
	p.fill(buf, 0, 1, 3, 0, 3, 6, _v(Blocks.PLANKS))
	p.fill(buf, 0, 1, 3, 3, 3, 3, _v(Blocks.PLANKS))
	p.fill(buf, 1, 1, 4, 3, 3, 5, Blocks.AIR)
	p.door(buf, 2, 1, 3, Blocks.WOODEN_DOOR, 2)
	p.fill(buf, 0, 1, 0, 0, 3, 0, Blocks.FENCE)
	p.fill(buf, 4, 1, 0, 4, 3, 0, Blocks.FENCE)
	p.fill(buf, 0, 4, 0, 9, 4, 6, Blocks.SLAB, 1 if _desert else 0)
	# Горн: лава за железной решёткой, две печи, сундук с добычей.
	p.fill(buf, 7, 1, 5, 8, 1, 5, Blocks.LAVA)
	p.fill(buf, 7, 1, 4, 8, 1, 4, Blocks.IRON_BARS)
	p.fill(buf, 7, 2, 4, 8, 2, 5, c)
	p.put(buf, 6, 1, 5, Blocks.FURNACE, p.dir(2))
	p.put(buf, 5, 1, 5, Blocks.FURNACE, p.dir(2))
	p.fill(buf, 5, 1, 2, 7, 1, 2, Blocks.SLAB, 0)
	var ch := p.world(1, 1, 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed
	buf.add_chest(ch.x, ch.y, ch.z, p.dir(2), Loot.blacksmith(rng))


func _church(p: GenPiece, buf: GenChunk) -> void:
	_prepare(p, buf, 5, 9, 12)
	var c := _v(Blocks.COBBLESTONE)
	p.fill(buf, 0, 0, 0, 4, 0, 8, c)
	p.box(buf, 0, 0, 0, 4, 5, 8, c)
	p.box(buf, 0, 5, 4, 4, 12, 8, c)
	p.fill(buf, 1, 1, 1, 3, 4, 7, Blocks.AIR)
	p.fill(buf, 1, 5, 5, 3, 11, 7, Blocks.AIR)
	p.fill(buf, 1, 8, 5, 3, 8, 7, c)
	p.door(buf, 2, 1, 0, Blocks.WOODEN_DOOR, 2)
	for ly: int in [2, 3]:
		p.put(buf, 0, ly, 2, Blocks.GLASS_PANE)
		p.put(buf, 4, ly, 2, Blocks.GLASS_PANE)
		p.put(buf, 0, ly, 6, Blocks.GLASS_PANE)
		p.put(buf, 4, ly, 6, Blocks.GLASS_PANE)
	for ly: int in [9, 10]:
		p.put(buf, 0, ly, 6, Blocks.GLASS_PANE)
		p.put(buf, 4, ly, 6, Blocks.GLASS_PANE)
		p.put(buf, 2, ly, 4, Blocks.GLASS_PANE)
		p.put(buf, 2, ly, 8, Blocks.GLASS_PANE)
	p.fill(buf, 2, 1, 7, 2, 11, 7, Blocks.LADDER, p.dir(2))
	p.put(buf, 2, 1, 6, Blocks.COBBLESTONE_STAIRS, p.dir(2))
	p.torch(buf, 1, 3, 1, 2)
	p.torch(buf, 3, 3, 1, 2)
	p.torch(buf, 1, 10, 6, 1)
	p.torch(buf, 3, 10, 6, 3)


func _farm(p: GenPiece, buf: GenChunk, large: bool) -> void:
	var sx := 13 if large else 7
	p.fill(buf, 0, 1, 0, sx - 1, 3, 8, Blocks.AIR)
	for lz in 9:
		for lx in sx:
			p.foundation(buf, lx, -1, lz, Blocks.DIRT)
	var lg := _v(Blocks.LOG)
	p.fill(buf, 0, 0, 0, sx - 1, 0, 8, lg)
	var waters := [3, 9] if large else [3]
	for lx in range(1, sx - 1):
		if large and lx == 6:
			continue
		if lx in waters:
			p.fill(buf, lx, 0, 1, lx, 0, 7, Blocks.WATER)
			continue
		for lz in range(1, 8):
			p.put(buf, lx, 0, lz, Blocks.FARMLAND, 7)
			p.put(buf, lx, 1, lz, Blocks.WHEAT, 2 + p.rnd(lx, 1, lz) % 6)


func _lamp(p: GenPiece, buf: GenChunk) -> void:
	p.foundation(buf, 1, 0, 1, _v(Blocks.COBBLESTONE))
	p.fill(buf, 0, 1, 0, 2, 4, 2, Blocks.AIR)
	p.fill(buf, 1, 1, 1, 1, 3, 1, Blocks.FENCE)
	p.put(buf, 1, 4, 1, Blocks.WOOL, 15)
	p.torch(buf, 0, 4, 1, 3)
	p.torch(buf, 2, 4, 1, 1)
	p.torch(buf, 1, 4, 0, 0)
	p.torch(buf, 1, 4, 2, 2)


func _house_big(p: GenPiece, buf: GenChunk) -> void:
	_prepare(p, buf, 9, 7, 8)
	_walls(p, buf, 9, 7, 3)
	_roof(p, buf, 9, 7, 4)
	p.put(buf, 2, 2, 0, Blocks.GLASS_PANE)
	p.put(buf, 6, 2, 0, Blocks.GLASS_PANE)
	p.put(buf, 2, 2, 6, Blocks.GLASS_PANE)
	p.put(buf, 6, 2, 6, Blocks.GLASS_PANE)
	p.put(buf, 0, 2, 3, Blocks.GLASS_PANE)
	p.put(buf, 8, 2, 3, Blocks.GLASS_PANE)
	p.door(buf, 4, 1, 0, Blocks.WOODEN_DOOR, 2)
	p.put(buf, 7, 1, 5, Blocks.CRAFTING_TABLE)
	p.put(buf, 1, 1, 5, Blocks.FENCE)
	p.put(buf, 1, 2, 5, Blocks.WOODEN_PLATE)
	p.torch(buf, 4, 3, 5, 0)
