class_name MineshaftGen
extends RefCounted
## Заброшенные шахты (StructureMineshaftPieces 1.2): зал с земляным полом, от него — коридоры 3×3
## с деревянными крепями (заборы и доски), рельсы, паутина, редкие факелы и сундуки, «паучьи»
## коридоры с рассадником пещерных пауков, перекрёстки (иногда двухэтажные) и спуски.
## Шанс шахты в чанке — 1/100 при условии rand(80) < max(|x|, |z|) (как в 1.2: у начала мира их нет).
## План целиком задаётся сидом чанка-начала; каждый чанк рисует свою часть.

enum { ROOM, CORRIDOR, CROSSING, STAIRS }

## Радиус (в чанках), на котором шахта может задеть чанк.
const REACH_CHUNKS := 6
const MAX_DEPTH := 8
const MAX_DIST := 80

var seed_value := 0


func _init(p_seed: int) -> void:
	seed_value = p_seed


static func _ri(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 0:
		return 0
	return int(rng.randi() % n)


## Есть ли шахта с началом в чанке (scx, scz).
func has_start(scx: int, scz: int) -> bool:
	var h := WorldGen.hash3(scx, 66091, scz, seed_value)
	if h % 100 != 0:
		return false
	return (h >> 8) % 80 < maxi(absi(scx), absi(scz))


## Шахты, которые могут задеть чанк: список планов (массивов частей).
func near(cx: int, cz: int) -> Array:
	var out := []
	for dz in range(-REACH_CHUNKS, REACH_CHUNKS + 1):
		for dx in range(-REACH_CHUNKS, REACH_CHUNKS + 1):
			if has_start(cx + dx, cz + dz):
				out.append(layout(cx + dx, cz + dz))
	return out


func layout(scx: int, scz: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.hash3(scx, 66092, scz, seed_value) * 9871 + scx
	var x := scx * 16 + 2
	var z := scz * 16 + 2
	var sx := 7 + _ri(rng, 6)
	var sy := 4 + _ri(rng, 6)
	var sz := 7 + _ri(rng, 6)
	var room := GenPiece.make(ROOM, 0, x, 50, z, 0, 0, sx, sy, sz)
	room.seed = int(rng.randi())
	var pieces: Array = [room]
	# Коридоры из стен зала.
	var exits := []
	for side in 4:
		var wall_len := sx if side == 0 or side == 2 else sz
		var t := 0
		while t < wall_len:
			t += _ri(rng, wall_len)
			if t + 3 > wall_len:
				break
			var y := _ri(rng, maxi(sy - 2, 1))
			match side:
				0:
					exits.append([room.world(t, y, sz), room.dir(0)])
				1:
					exits.append([room.world(-1, y, t), room.dir(1)])
				2:
					exits.append([room.world(t, y, -1), room.dir(2)])
				3:
					exits.append([room.world(sx, y, t), room.dir(3)])
			t += 4
	var queue := []
	for e: Array in exits:
		queue.append([e[0], e[1], 1])
	var qi := 0
	while qi < queue.size() and pieces.size() < 64:
		var q: Array = queue[qi]
		qi += 1
		_next(q[0], int(q[1]), int(q[2]), x, z, pieces, queue, rng)
	# Вся шахта — ниже уровня моря − 10 (markAvailableHeight).
	var lo := 255
	var hi := 0
	for p: GenPiece in pieces:
		lo = mini(lo, p.y0)
		hi = maxi(hi, p.y1)
	var height := hi - lo + 1
	var limit := WorldGen.SEA_LEVEL - 10
	var top := height + 1
	if top < limit:
		top += _ri(rng, limit - top)
	var shift := top - hi
	for p: GenPiece in pieces:
		p.y0 += shift
		p.y1 += shift
	return pieces


func _next(e: Vector3i, d: int, depth: int, sx: int, sz: int, pieces: Array, queue: Array, rng: RandomNumberGenerator) -> void:
	if depth > MAX_DEPTH:
		return
	var r := _ri(rng, 100)
	var p: GenPiece
	if r >= 80:
		var tall := _ri(rng, 4) == 0
		p = GenPiece.make(CROSSING, d, e.x, e.y, e.z, 2, 0, 5, 7 if tall else 3, 5)
		p.data = 1 if tall else 0
	elif r >= 70:
		p = GenPiece.make(STAIRS, d, e.x, e.y, e.z, 1, 5, 3, 8, 9)
	else:
		var sections := 2 + _ri(rng, 3)
		p = GenPiece.make(CORRIDOR, d, e.x, e.y, e.z, 1, 0, 3, 3, sections * 5)
		p.data = sections
		if _ri(rng, 3) == 0:
			p.data |= 16
		elif _ri(rng, 23) == 0:
			p.data |= 32
	var mx := (p.x0 + p.x1) * 0.5 - sx
	var mz := (p.z0 + p.z1) * 0.5 - sz
	if mx * mx + mz * mz > MAX_DIST * MAX_DIST:
		return
	for o: GenPiece in pieces:
		if p.overlaps(o) and p.y1 >= o.y0 and p.y0 <= o.y1:
			return
	p.seed = int(rng.randi())
	p.depth = depth
	pieces.append(p)
	match p.kind:
		CORRIDOR:
			var length := p.size_z()
			queue.append([p.world(1, 0, length), p.dir(0), depth + 1])
			if _ri(rng, 4) == 0:
				var t := 1 + _ri(rng, length - 3)
				queue.append([p.world(-1, 0, t), p.dir(1), depth + 1])
			if _ri(rng, 4) == 0:
				var t := 1 + _ri(rng, length - 3)
				queue.append([p.world(3, 0, t), p.dir(3), depth + 1])
		CROSSING:
			queue.append([p.world(2, 0, 5), p.dir(0), depth + 1])
			queue.append([p.world(-1, 0, 2), p.dir(1), depth + 1])
			queue.append([p.world(5, 0, 2), p.dir(3), depth + 1])
			if p.data == 1:
				queue.append([p.world(2, 4, 5), p.dir(0), depth + 1])
				queue.append([p.world(-1, 4, 2), p.dir(1), depth + 1])
				queue.append([p.world(5, 4, 2), p.dir(3), depth + 1])
		STAIRS:
			queue.append([p.world(1, 0, 9), p.dir(0), depth + 1])


## Мешает ли шахта… (деревьям — нет, она под землёй).
func draw(pieces: Array, buf: GenChunk) -> void:
	for p: GenPiece in pieces:
		if not buf.overlaps(p.x0 - 1, p.z0 - 1, p.x1 + 1, p.z1 + 1):
			continue
		match p.kind:
			ROOM:
				_room(p, buf)
			CORRIDOR:
				_corridor(p, buf)
			CROSSING:
				_crossing(p, buf)
			STAIRS:
				_stairs(p, buf)


func _room(p: GenPiece, buf: GenChunk) -> void:
	var sx := p.size_x()
	var sz := p.size_z()
	var sy := p.y1 - p.y0 + 1
	p.fill(buf, 0, 0, 0, sx - 1, 0, sz - 1, Blocks.DIRT)
	p.fill(buf, 0, 1, 0, sx - 1, mini(sy - 1, 3), sz - 1, Blocks.AIR)
	# Купол: чем выше, тем уже.
	for ly in range(4, sy):
		var k := ly - 3
		if sx - 1 - k <= k or sz - 1 - k <= k:
			break
		p.fill(buf, k, ly, k, sx - 1 - k, ly, sz - 1 - k, Blocks.AIR)


## Доски под полом там, где внизу пустота (мостики над пещерами).
func _bridge(p: GenPiece, buf: GenChunk, lx: int, lz: int) -> void:
	var b := p.get_b(buf, lx, -1, lz)
	if b == Blocks.AIR or b == Blocks.WATER or b == Blocks.LAVA:
		p.put(buf, lx, -1, lz, Blocks.PLANKS)


func _corridor(p: GenPiece, buf: GenChunk) -> void:
	var length := p.size_z()
	var rails := (p.data & 16) != 0
	var spiders := (p.data & 32) != 0
	p.fill(buf, 0, 0, 0, 2, 2, length - 1, Blocks.AIR)
	for lz in length:
		for lx in 3:
			_bridge(p, buf, lx, lz)
		# Паутина под потолком (в «паучьих» коридорах — гуще).
		for lx in 3:
			for ly in range(1, 3):
				var h := p.rnd(lx, ly, lz, 5) % 100
				if (spiders and h < 30) or (not spiders and ly == 2 and h < 6):
					p.put(buf, lx, ly, lz, Blocks.WEB)
		if rails and p.rnd(1, 0, lz, 7) % 10 < 7:
			p.put(buf, 1, 0, lz, Blocks.RAIL, 0 if p.dir(0) % 2 == 0 else 1)
	for k in p.data & 15:
		var lz := 2 + k * 5
		p.fill(buf, 0, 0, lz, 0, 1, lz, Blocks.FENCE)
		p.fill(buf, 2, 0, lz, 2, 1, lz, Blocks.FENCE)
		p.fill(buf, 0, 2, lz, 2, 2, lz, Blocks.PLANKS)
		# Редкий факел на балке крепи (опора — доска с локальной стороны +z).
		if p.rnd(1, 1, lz, 9) % 20 == 0:
			p.put(buf, 1, 2, lz - 1, Blocks.TORCH, GenPiece.torch_meta(p.dir(0)))
		if p.rnd(0, 0, lz, 11) % 100 < 1:
			var c := p.world(2, 0, lz - 1)
			var rng := RandomNumberGenerator.new()
			rng.seed = p.seed + k
			buf.add_chest(c.x, c.y, c.z, p.dir(1), Loot.mineshaft(rng))
	if spiders:
		var c := p.world(1, 0, 2 + (p.seed % (p.data & 15)) * 5 + 2)
		buf.add_spawner(c.x, c.y, c.z, 59)


func _crossing(p: GenPiece, buf: GenChunk) -> void:
	var tall := p.data == 1
	var top := 6 if tall else 2
	p.fill(buf, 1, 0, 0, 3, top, 4, Blocks.AIR)
	p.fill(buf, 0, 0, 1, 4, top, 3, Blocks.AIR)
	if tall:
		p.fill(buf, 1, 4, 1, 3, 4, 3, Blocks.PLANKS)
		p.fill(buf, 1, 5, 1, 3, 6, 3, Blocks.AIR)
	for q: Vector2i in [Vector2i(1, 1), Vector2i(3, 1), Vector2i(1, 3), Vector2i(3, 3)]:
		p.fill(buf, q.x, 0, q.y, q.x, top, q.y, Blocks.PLANKS)
	for lz in 5:
		for lx in 5:
			_bridge(p, buf, lx, lz)


func _stairs(p: GenPiece, buf: GenChunk) -> void:
	# Вход сверху (y 5–7), спуск на 5 блоков, выход внизу (y 0–2).
	p.fill(buf, 0, 5, 0, 2, 7, 1, Blocks.AIR)
	p.fill(buf, 0, 0, 7, 2, 2, 8, Blocks.AIR)
	for k in 5:
		p.fill(buf, 0, 5 - k - 1, 2 + k, 2, 7 - k, 2 + k, Blocks.AIR)
