class_name StrongholdGen
extends RefCounted
## Крепости (MapGenStronghold/StructureStrongholdPieces 1.2): три на мир, на расстоянии
## 640–1152 блоков от начала координат, через 120°. Винтовая лестница вниз, коридоры с дверями
## (проём, деревянная, решётка, железная), повороты, залы-перекрёстки (колонна, фонтан, балкон
## с сундуком), прямые лестницы, тюрьма с камерами, коридоры с сундуком, библиотеки и комната
## с порталом: рамка из 12 блоков портала Края над лавой, лестница и рассадник чешуйниц.
## Стены — каменные кирпичи (обычные, замшелые, треснувшие) с камнями-чешуйницами.

enum { START, CORRIDOR, CHEST_CORRIDOR, TURN_LEFT, TURN_RIGHT, CROSSING, STAIRS, SPIRAL, PRISON, LIBRARY, PORTAL }

const COUNT := 3
## Радиус (в чанках), на котором крепость может задеть чанк.
const REACH_CHUNKS := 8
const MAX_DIST := 112
const MAX_PIECES := 60
## Вид → [ширина, высота, глубина, x проёма входа, y проёма входа, вес, предел, мин. глубина].
const TYPES := {
	CORRIDOR: [5, 5, 7, 1, 1, 40, 0, 0],
	CHEST_CORRIDOR: [5, 5, 7, 1, 1, 5, 4, 0],
	TURN_LEFT: [5, 5, 5, 1, 1, 20, 0, 0],
	TURN_RIGHT: [5, 5, 5, 1, 1, 20, 0, 0],
	CROSSING: [11, 7, 11, 4, 1, 10, 6, 0],
	STAIRS: [5, 11, 8, 1, 7, 5, 5, 0],
	SPIRAL: [5, 11, 5, 1, 7, 5, 5, 0],
	PRISON: [9, 5, 11, 1, 1, 5, 5, 0],
	LIBRARY: [14, 11, 15, 4, 1, 10, 2, 5],
	PORTAL: [11, 8, 16, 4, 1, 20, 1, 6],
}

var seed_value := 0
var _positions: Array[Vector2i] = []


func _init(p_seed: int) -> void:
	seed_value = p_seed


static func _ri(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 0:
		return 0
	return int(rng.randi() % n)


## Чанки начала трёх крепостей (как canSpawnStructureAtCoords 1.2).
func start_chunks(biomes: BiomeSource) -> Array[Vector2i]:
	if not _positions.is_empty():
		return _positions
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 2003
	var angle := rng.randf() * TAU
	for i in COUNT:
		var dist := (1.25 + rng.randf()) * 32.0
		var cx := roundi(cos(angle) * dist)
		var cz := roundi(sin(angle) * dist)
		# Крепость не ставится под океаном: ищем сушу в радиусе 112 блоков (findBiomePosition).
		var best := Vector2i(cx, cz)
		if Biomes.is_ocean(biomes.biome_at(cx * 16 + 8, cz * 16 + 8)):
			var found := false
			for r in range(1, 8):
				for t in r * 8:
					var p := WorldGen._ring_cell(r, t)
					var q := Vector2i(cx + p.x, cz + p.y)
					if not Biomes.is_ocean(biomes.biome_at(q.x * 16 + 8, q.y * 16 + 8)):
						best = q
						found = true
						break
				if found:
					break
		_positions.append(best)
		angle += TAU / COUNT
	return _positions


# --- План ------------------------------------------------------------------

func layout(scx: int, scz: int) -> Array:
	var best: Array = []
	for attempt in 12:
		var rng := RandomNumberGenerator.new()
		rng.seed = WorldGen.hash3(scx, 7717 + attempt, scz, seed_value) * 1009 + attempt
		var pieces := _try_layout(scx * 16 + 2, scz * 16 + 2, rng)
		var has_portal := false
		for p: GenPiece in pieces:
			if p.kind == PORTAL:
				has_portal = true
		if has_portal:
			return pieces
		if pieces.size() > best.size():
			best = pieces
	return best


func _try_layout(x: int, z: int, rng: RandomNumberGenerator) -> Array:
	var y := 22 + _ri(rng, 16)
	var start := GenPiece.make(START, _ri(rng, 4), x, y, z, 0, 0, 5, 11, 5)
	start.seed = int(rng.randi())
	var pieces: Array = [start]
	var used := {}
	var queue := []
	queue.append(_exit(start, 1, 1, 5, true, 0, 1))
	while not queue.is_empty() and pieces.size() < MAX_PIECES:
		var e: Array = queue.pop_at(_ri(rng, queue.size()))
		_attach(e, x, z, pieces, used, queue, rng)
	return pieces


## Выход части: [мировая клетка-вход для следующей части, направление, глубина].
## Проём — три клетки от (lx, ly, lz) вдоль локальной x (along_x) или z.
func _exit(p: GenPiece, lx: int, ly: int, lz: int, along_x: bool, ld: int, depth: int) -> Array:
	var f := p.dir(ld)
	var c0 := p.world(lx, ly, lz)
	var c2 := p.world(lx + 2, ly, lz) if along_x else p.world(lx, ly, lz + 2)
	var w := Vector3i(1, 0, 0) if (f == 0 or f == 2) else Vector3i(0, 0, 1)
	var e := c0 if c2 - c0 == w * 2 else c2
	return [e, f, depth]


func _attach(e: Array, sx: int, sz: int, pieces: Array, used: Dictionary, queue: Array, rng: RandomNumberGenerator) -> void:
	var cell: Vector3i = e[0]
	var facing: int = e[1]
	var depth: int = e[2]
	if depth > 30:
		return
	for attempt in 5:
		var kind := _pick(depth, used, rng)
		if kind < 0:
			return
		var info: Array = TYPES[kind]
		var p := GenPiece.make(kind, facing, cell.x, cell.y, cell.z, int(info[3]), int(info[4]), int(info[0]), int(info[1]), int(info[2]))
		if p.y0 < 5:
			continue
		var mx := (p.x0 + p.x1) * 0.5 - sx
		var mz := (p.z0 + p.z1) * 0.5 - sz
		if mx * mx + mz * mz > MAX_DIST * MAX_DIST:
			continue
		var clash := false
		for o: GenPiece in pieces:
			if p.overlaps(o) and p.y1 >= o.y0 and p.y0 <= o.y1:
				clash = true
				break
		if clash:
			continue
		p.seed = int(rng.randi())
		p.data = int(rng.randi() & 0xFFFF)
		p.depth = depth
		pieces.append(p)
		used[kind] = int(used.get(kind, 0)) + 1
		_add_exits(p, depth + 1, queue, rng)
		return


func _pick(depth: int, used: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0
	var ok := []
	for t: int in TYPES:
		var info: Array = TYPES[t]
		if int(info[6]) > 0 and int(used.get(t, 0)) >= int(info[6]):
			continue
		if depth < int(info[7]):
			continue
		ok.append(t)
		total += int(info[5])
	if total == 0:
		return -1
	var r := _ri(rng, total)
	for t: int in ok:
		r -= int(TYPES[t][5])
		if r < 0:
			return t
	return -1


func _add_exits(p: GenPiece, depth: int, queue: Array, rng: RandomNumberGenerator) -> void:
	match p.kind:
		CORRIDOR, CHEST_CORRIDOR:
			queue.append(_exit(p, 1, 1, 7, true, 0, depth))
			if p.kind == CORRIDOR:
				if p.data & 1:
					queue.append(_exit(p, -1, 1, 2, false, 1, depth))
				if p.data & 2:
					queue.append(_exit(p, 5, 1, 2, false, 3, depth))
		TURN_LEFT:
			queue.append(_exit(p, -1, 1, 1, false, 1, depth))
		TURN_RIGHT:
			queue.append(_exit(p, 5, 1, 1, false, 3, depth))
		CROSSING:
			queue.append(_exit(p, 4, 1, 11, true, 0, depth))
			queue.append(_exit(p, -1, 1, 4, false, 1, depth))
			queue.append(_exit(p, 11, 1, 4, false, 3, depth))
		STAIRS:
			queue.append(_exit(p, 1, 1, 8, true, 0, depth))
		SPIRAL, START:
			queue.append(_exit(p, 1, 1, 5, true, 0, depth))
		PRISON:
			queue.append(_exit(p, 1, 1, 11, true, 0, depth))


## Чанк на расстоянии не больше REACH_CHUNKS от начала крепости?
static func near(scx: int, scz: int, cx: int, cz: int) -> bool:
	return absi(scx - cx) <= REACH_CHUNKS and absi(scz - cz) <= REACH_CHUNKS


# --- Постройка -------------------------------------------------------------

func draw(pieces: Array, buf: GenChunk) -> void:
	for p: GenPiece in pieces:
		if not buf.overlaps(p.x0 - 1, p.z0 - 1, p.x1 + 1, p.z1 + 1):
			continue
		var info: Array = TYPES.get(p.kind, [5, 11, 5, 1, 7, 0, 0, 0])
		var sx := p.size_x()
		var sz := p.size_z()
		var sy := p.y1 - p.y0 + 1
		_stone_box(p, buf, 0, 0, 0, sx - 1, sy - 1, sz - 1)
		match p.kind:
			START, SPIRAL:
				_spiral(p, buf)
			CORRIDOR, CHEST_CORRIDOR:
				_corridor(p, buf)
			TURN_LEFT, TURN_RIGHT:
				_turn(p, buf)
			CROSSING:
				_crossing(p, buf)
			STAIRS:
				_stairs(p, buf)
			PRISON:
				_prison(p, buf)
			LIBRARY:
				_library(p, buf)
			PORTAL:
				_portal(p, buf)
		if p.kind != START:
			_door(p, buf, int(info[3]), int(info[4]))


## Случайный каменный кирпич (StrongholdStones): треснувший, замшелый, камень-чешуйница, обычный.
static func _stone_id(h: int) -> Vector2i:
	var r := h % 100
	if r < 20:
		return Vector2i(Blocks.STONE_BRICKS, 2)
	if r < 50:
		return Vector2i(Blocks.STONE_BRICKS, 1)
	if r < 55:
		return Vector2i(Blocks.MONSTER_EGG, 2)
	return Vector2i(Blocks.STONE_BRICKS, 0)


## Оболочка из случайных кирпичей, внутри — воздух.
func _stone_box(p: GenPiece, buf: GenChunk, ax: int, ay: int, az: int, bx: int, by: int, bz: int) -> void:
	p.fill(buf, ax + 1, ay + 1, az + 1, bx - 1, by - 1, bz - 1, Blocks.AIR)
	for lz in range(az, bz + 1):
		for lx in range(ax, bx + 1):
			var x := p.wx(lx, lz)
			var z := p.wz(lx, lz)
			if not buf.contains(x, z):
				continue
			var edge := lx == ax or lx == bx or lz == az or lz == bz
			for ly in range(ay, by + 1):
				if not edge and ly != ay and ly != by:
					continue
				var s := _stone_id(WorldGen.hash3(x, p.y0 + ly, z, p.seed))
				buf.set_b(x, p.y0 + ly, z, s.x, s.y)


func _stones(p: GenPiece, buf: GenChunk, ax: int, ay: int, az: int, bx: int, by: int, bz: int) -> void:
	for lz in range(az, bz + 1):
		for lx in range(ax, bx + 1):
			var x := p.wx(lx, lz)
			var z := p.wz(lx, lz)
			if not buf.contains(x, z):
				continue
			for ly in range(ay, by + 1):
				var s := _stone_id(WorldGen.hash3(x, p.y0 + ly, z, p.seed + 1))
				buf.set_b(x, p.y0 + ly, z, s.x, s.y)


## Проём входа 3×3 (lx..lx+2, ly..ly+2, z = 0) с дверью случайного типа.
func _door(p: GenPiece, buf: GenChunk, lx: int, ly: int) -> void:
	p.fill(buf, lx, ly, 0, lx + 2, ly + 2, 0, Blocks.AIR)
	match (p.data >> 4) % 5:
		2:
			p.fill(buf, lx, ly, 0, lx + 2, ly + 2, 0, Blocks.STONE_BRICKS)
			p.door(buf, lx + 1, ly, 0, Blocks.WOODEN_DOOR, 2)
		3:
			p.fill(buf, lx, ly, 0, lx + 2, ly + 2, 0, Blocks.IRON_BARS)
			p.fill(buf, lx + 1, ly, 0, lx + 1, ly + 1, 0, Blocks.AIR)
		4:
			p.fill(buf, lx, ly, 0, lx + 2, ly + 2, 0, Blocks.STONE_BRICKS)
			p.door(buf, lx + 1, ly, 0, Blocks.IRON_DOOR, 2)
			p.put(buf, lx + 2, ly + 1, -1, Blocks.STONE_BUTTON, GenPiece.torch_meta(p.dir(0)))
			p.put(buf, lx + 2, ly + 1, 1, Blocks.STONE_BUTTON, GenPiece.torch_meta(p.dir(2)))


func _spiral(p: GenPiece, buf: GenChunk) -> void:
	p.fill(buf, 2, 1, 2, 2, 9, 2, Blocks.STONE_BRICKS)
	var ring := [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(2, 3),
		Vector2i(1, 3), Vector2i(1, 2)]
	for k in 7:
		var c: Vector2i = ring[(k + 2) % 8]
		p.put(buf, c.x, 6 - k, c.y, Blocks.SLAB, 5)
		if 6 - k - 1 >= 1:
			p.fill(buf, c.x, 1, c.y, c.x, 5 - k, c.y, Blocks.STONE_BRICKS)
	# Выход внизу (z = 4).
	p.fill(buf, 1, 1, 4, 3, 3, 4, Blocks.AIR)
	p.torch(buf, 1, 3, 2, 1)


func _corridor(p: GenPiece, buf: GenChunk) -> void:
	p.fill(buf, 1, 1, 6, 3, 3, 6, Blocks.AIR)
	if p.kind == CORRIDOR:
		if p.data & 1:
			p.fill(buf, 0, 1, 2, 0, 3, 4, Blocks.AIR)
		if p.data & 2:
			p.fill(buf, 4, 1, 2, 4, 3, 4, Blocks.AIR)
		for q: Vector3i in [Vector3i(1, 2, 1), Vector3i(3, 2, 5)]:
			if p.rnd(q.x, q.y, q.z, 3) % 10 == 0:
				p.torch(buf, q.x, q.y, q.z, 1 if q.x == 1 else 3)
	else:
		p.fill(buf, 3, 1, 2, 3, 1, 4, Blocks.STONE_BRICKS)
		p.put(buf, 3, 2, 2, Blocks.SLAB, 5)
		p.put(buf, 3, 2, 4, Blocks.SLAB, 5)
		var c := p.world(3, 2, 3)
		var rng := RandomNumberGenerator.new()
		rng.seed = p.seed
		buf.add_chest(c.x, c.y, c.z, p.dir(1), Loot.stronghold_corridor(rng))


func _turn(p: GenPiece, buf: GenChunk) -> void:
	if p.kind == TURN_LEFT:
		p.fill(buf, 0, 1, 1, 0, 3, 3, Blocks.AIR)
	else:
		p.fill(buf, 4, 1, 1, 4, 3, 3, Blocks.AIR)


func _crossing(p: GenPiece, buf: GenChunk) -> void:
	p.fill(buf, 4, 1, 10, 6, 3, 10, Blocks.AIR)
	p.fill(buf, 0, 1, 4, 0, 3, 6, Blocks.AIR)
	p.fill(buf, 10, 1, 4, 10, 3, 6, Blocks.AIR)
	match p.data % 4:
		0:
			p.fill(buf, 5, 1, 5, 5, 5, 5, Blocks.STONE_BRICKS)
			p.torch(buf, 4, 3, 5, 3)
			p.torch(buf, 6, 3, 5, 1)
			p.torch(buf, 5, 3, 4, 0)
			p.torch(buf, 5, 3, 6, 2)
		1:
			p.fill(buf, 4, 1, 4, 6, 1, 6, Blocks.SLAB, 0)
			p.put(buf, 5, 1, 5, Blocks.STONE_BRICKS)
			p.put(buf, 5, 2, 5, Blocks.WATER)
			p.torch(buf, 1, 3, 1, 1)
			p.torch(buf, 9, 3, 9, 3)
		2:
			# Балкон из досок с лестницей и сундуком.
			p.fill(buf, 1, 3, 1, 3, 3, 9, Blocks.PLANKS)
			p.fill(buf, 4, 4, 1, 4, 4, 9, Blocks.FENCE)
			p.fill(buf, 1, 3, 4, 3, 3, 6, Blocks.AIR)
			p.fill(buf, 1, 1, 9, 1, 3, 9, Blocks.LADDER, p.dir(3))
			var c := p.world(1, 4, 1)
			var rng := RandomNumberGenerator.new()
			rng.seed = p.seed
			buf.add_chest(c.x, c.y, c.z, p.dir(3), Loot.stronghold_crossing(rng))
			p.torch(buf, 9, 3, 5, 3)
		_:
			p.torch(buf, 1, 3, 5, 1)
			p.torch(buf, 9, 3, 5, 3)


func _stairs(p: GenPiece, buf: GenChunk) -> void:
	p.fill(buf, 1, 1, 7, 3, 3, 7, Blocks.AIR)
	for lz in range(1, 7):
		var top := 6 - lz
		if top > 0:
			_stones(p, buf, 1, 1, lz, 3, top - 1 + 1, lz)
		p.fill(buf, 1, top, lz, 3, top, lz, Blocks.STONE_BRICK_STAIRS, p.dir(2))
	_stones(p, buf, 1, 1, 0, 3, 6, 0)


func _prison(p: GenPiece, buf: GenChunk) -> void:
	p.fill(buf, 1, 1, 10, 3, 3, 10, Blocks.AIR)
	p.fill(buf, 4, 1, 1, 4, 3, 9, Blocks.IRON_BARS)
	p.fill(buf, 5, 1, 5, 7, 3, 5, Blocks.IRON_BARS)
	for lz: int in [3, 7]:
		p.fill(buf, 4, 1, lz, 4, 2, lz, Blocks.AIR)
		p.door(buf, 4, 1, lz, Blocks.IRON_DOOR, 1)


func _library(p: GenPiece, buf: GenChunk) -> void:
	var tall := (p.data & 1) != 0
	var top := 9 if tall else 4
	if not tall:
		_stone_box(p, buf, 0, 0, 0, 13, 5, 14)
		p.fill(buf, 0, 6, 0, 13, 10, 14, Blocks.STONE)
	for lz in range(1, 14):
		var shelf := Blocks.BOOKSHELF if lz % 4 != 0 else Blocks.PLANKS
		p.fill(buf, 1, 1, lz, 1, top, lz, shelf)
		p.fill(buf, 12, 1, lz, 12, top, lz, shelf)
	p.fill(buf, 2, 1, 13, 11, top, 13, Blocks.BOOKSHELF)
	for lz: int in [5, 9]:
		p.fill(buf, 4, 1, lz, 9, 3, lz, Blocks.BOOKSHELF)
		p.fill(buf, 4, 1, lz, 4, 3, lz, Blocks.PLANKS)
	for lz in range(1, 14):
		for lx in range(2, 12):
			if p.rnd(lx, top, lz, 9) % 100 < 7:
				p.put(buf, lx, top, lz, Blocks.WEB)
	if tall:
		p.fill(buf, 2, 5, 1, 3, 5, 12, Blocks.PLANKS)
		p.fill(buf, 10, 5, 1, 11, 5, 12, Blocks.PLANKS)
		p.fill(buf, 4, 5, 12, 9, 5, 12, Blocks.PLANKS)
		p.fill(buf, 4, 6, 1, 4, 6, 11, Blocks.FENCE)
		p.fill(buf, 9, 6, 1, 9, 6, 11, Blocks.FENCE)
		p.fill(buf, 2, 1, 2, 2, 5, 2, Blocks.LADDER, p.dir(3))
		p.fill(buf, 7, 7, 7, 7, 9, 7, Blocks.FENCE)
	p.torch(buf, 2, 3, 7, 1)
	p.torch(buf, 11, 3, 7, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed
	var c := p.world(3, 1, 5)
	buf.add_chest(c.x, c.y, c.z, p.dir(3), Loot.stronghold_library(rng))
	if tall:
		var c2 := p.world(11, 6, 8)
		buf.add_chest(c2.x, c2.y, c2.z, p.dir(1), Loot.stronghold_library(rng))


func _portal(p: GenPiece, buf: GenChunk) -> void:
	# Карниз под потолком, лавовые канавки у входа, бассейн лавы под рамкой.
	_stones(p, buf, 1, 6, 1, 1, 6, 14)
	_stones(p, buf, 9, 6, 1, 9, 6, 14)
	_stones(p, buf, 2, 6, 1, 8, 6, 2)
	_stones(p, buf, 2, 6, 14, 8, 6, 14)
	_stones(p, buf, 1, 1, 1, 2, 1, 4)
	_stones(p, buf, 8, 1, 1, 9, 1, 4)
	p.fill(buf, 1, 1, 1, 1, 1, 3, Blocks.LAVA)
	p.fill(buf, 9, 1, 1, 9, 1, 3, Blocks.LAVA)
	_stones(p, buf, 3, 1, 8, 7, 2, 12)
	p.fill(buf, 4, 1, 9, 6, 2, 11, Blocks.LAVA)
	p.fill(buf, 4, 2, 9, 6, 2, 11, Blocks.AIR)
	for lz in range(3, 14, 2):
		p.fill(buf, 0, 3, lz, 0, 4, lz, Blocks.IRON_BARS)
		p.fill(buf, 10, 3, lz, 10, 4, lz, Blocks.IRON_BARS)
	for lx in range(2, 9, 2):
		p.fill(buf, lx, 3, 15, lx, 4, 15, Blocks.IRON_BARS)
	# Лестница к рамке.
	_stones(p, buf, 4, 1, 5, 6, 1, 7)
	_stones(p, buf, 4, 2, 6, 6, 2, 7)
	_stones(p, buf, 4, 3, 7, 6, 3, 7)
	var st := p.dir(0)
	p.fill(buf, 4, 1, 4, 6, 1, 4, Blocks.STONE_BRICK_STAIRS, st)
	p.fill(buf, 4, 2, 5, 6, 2, 5, Blocks.STONE_BRICK_STAIRS, st)
	p.fill(buf, 4, 3, 6, 6, 3, 6, Blocks.STONE_BRICK_STAIRS, st)
	# Рамка портала: 3 блока с каждой стороны, «смотрят» к центру; глаза не вставлены.
	for lx in range(4, 7):
		p.put(buf, lx, 3, 8, Blocks.END_PORTAL_FRAME, p.dir(0))
		p.put(buf, lx, 3, 12, Blocks.END_PORTAL_FRAME, p.dir(2))
	for lz in range(9, 12):
		p.put(buf, 3, 3, lz, Blocks.END_PORTAL_FRAME, p.dir(3))
		p.put(buf, 7, 3, lz, Blocks.END_PORTAL_FRAME, p.dir(1))
	var sp := p.world(5, 3, 6)
	buf.add_spawner(sp.x, sp.y, sp.z, 60)
	p.torch(buf, 1, 5, 7, 1)
	p.torch(buf, 9, 5, 7, 3)
