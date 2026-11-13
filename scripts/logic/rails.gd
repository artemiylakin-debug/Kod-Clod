class_name Rails
extends RefCounted
## Рельсы 1.2: форма в данных блока (0 — север-юг, 1 — запад-восток, 2–5 — подъём на восток, запад,
## север, юг; 6–9 — повороты юг-восток, юг-запад, север-запад, север-восток). Ускоряющие и нажимные
## рельсы не поворачивают (у них бит 8 — «включено»). При установке рельсы сами соединяются с
## соседними: прямо, поворотом или подъёмом, а соседи со свободным концом подстраиваются.

const N := Vector3i(0, 0, -1)
const S := Vector3i(0, 0, 1)
const E := Vector3i(1, 0, 0)
const W := Vector3i(-1, 0, 0)
const UP := Vector3i(0, 1, 0)


static func is_rail(id: int) -> bool:
	return id == Blocks.RAIL or id == Blocks.POWERED_RAIL or id == Blocks.DETECTOR_RAIL


static func shape_of(id: int, meta: int) -> int:
	return meta & 15 if id == Blocks.RAIL else meta & 7


## Два конца рельса: [направление, подъём (0 или 1)].
static func ends(shape: int) -> Array:
	match shape:
		0:
			return [[N, 0], [S, 0]]
		1:
			return [[W, 0], [E, 0]]
		2:
			return [[W, 0], [E, 1]]
		3:
			return [[E, 0], [W, 1]]
		4:
			return [[S, 0], [N, 1]]
		5:
			return [[N, 0], [S, 1]]
		6:
			return [[S, 0], [E, 0]]
		7:
			return [[S, 0], [W, 0]]
		8:
			return [[N, 0], [W, 0]]
		9:
			return [[N, 0], [E, 0]]
	return [[N, 0], [S, 0]]


## Клетка, куда ведёт конец рельса (с учётом подъёма).
static func end_cell(p: Vector3i, e: Array) -> Vector3i:
	return p + (e[0] as Vector3i) + UP * int(e[1])


## Рельс в клетке q (или на блок ниже — для спуска).
static func _rail_at(world: World, q: Vector3i) -> Vector3i:
	for dy in [0, 1, -1]:
		var c: Vector3i = q + UP * dy
		if is_rail(world.get_block_v(c)):
			return c
	return Vector3i(0, -999, 0)


## Соединён ли рельс в r концом с клеткой p. Ровный конец соединяется с рельсом на том же уровне
## или на блок ниже (тот поднимается к нам); поднимающийся конец — с рельсом на блок выше.
static func _connects_to(world: World, r: Vector3i, p: Vector3i) -> bool:
	var shape := shape_of(world.get_block_v(r), world.get_meta_v(r))
	for e: Array in ends(shape):
		var c := end_cell(r, e)
		if c.x == p.x and c.z == p.z and (p.y == c.y or p.y == c.y - 1):
			return true
	return false


## Сколько концов рельса r уже упираются в другие рельсы, соединённые с ним (кроме клетки ignore).
static func _used_ends(world: World, r: Vector3i, ignore: Vector3i) -> int:
	var shape := shape_of(world.get_block_v(r), world.get_meta_v(r))
	var n := 0
	for e: Array in ends(shape):
		var other := _rail_at(world, end_cell(r, e))
		if other.y > -999 and other != ignore and _connects_to(world, other, r):
			n += 1
	return n


## Форма для рельса в p по соседям (curves — можно ли поворачивать).
static func choose_shape(world: World, p: Vector3i, curves: bool, fallback: int) -> int:
	var dirs: Array[Vector3i] = []
	var up: Array[bool] = []
	for d: Vector3i in [N, S, E, W]:
		var r := _rail_at(world, p + d)
		if r.y <= -999:
			continue
		# Сосед подходит, если уже соединён с нами или у него есть свободный конец
		# (сам рельс p при подсчёте не учитываем — его форма ещё выбирается).
		if not _connects_to(world, r, p) and _used_ends(world, r, p) >= 2:
			continue
		dirs.append(d)
		up.append(r.y > p.y)
	if dirs.is_empty():
		return fallback
	var pick: Array[int] = [0]
	# Пара: сначала прямая (противоположные стороны), затем поворот.
	for a in dirs.size():
		for b in range(a + 1, dirs.size()):
			if dirs[a] == -dirs[b]:
				pick = [a, b]
	if pick.size() == 1 and dirs.size() >= 2 and curves:
		pick = [0, 1]
	if pick.size() == 2:
		var da := dirs[pick[0]]
		var db := dirs[pick[1]]
		if da == -db:
			for k in 2:
				if up[pick[k]]:
					return _slope_toward(dirs[pick[k]])
			return 0 if da.x == 0 else 1
		var has := func(d: Vector3i) -> bool: return da == d or db == d
		if has.call(S) and has.call(E):
			return 6
		if has.call(S) and has.call(W):
			return 7
		if has.call(N) and has.call(W):
			return 8
		return 9
	var d := dirs[pick[0]]
	if up[pick[0]]:
		return _slope_toward(d)
	return 0 if d.x == 0 else 1


static func _slope_toward(d: Vector3i) -> int:
	if d == E:
		return 2
	if d == W:
		return 3
	if d == N:
		return 4
	return 5


## Рельс только что поставлен в p: выбрать ему форму и подстроить соседей.
static func on_placed(world: World, p: Vector3i, fallback: int) -> void:
	var id := world.get_block_v(p)
	if not is_rail(id):
		return
	var curves := id == Blocks.RAIL
	var shape := choose_shape(world, p, curves, fallback)
	var keep := world.get_meta_v(p) & 8 if id != Blocks.RAIL else 0
	world.set_block(p.x, p.y, p.z, id, shape | keep)
	# Соседи со свободным концом поворачиваются к новому рельсу.
	for e: Array in ends(shape):
		var r := _rail_at(world, end_cell(p, e))
		if r.y <= -999 or _connects_to(world, r, p):
			continue
		var rid := world.get_block_v(r)
		var ns := choose_shape(world, r, rid == Blocks.RAIL, shape_of(rid, world.get_meta_v(r)))
		var rkeep := world.get_meta_v(r) & 8 if rid != Blocks.RAIL else 0
		world.set_block(r.x, r.y, r.z, rid, ns | rkeep)


## Отрезок пути рельса в мировых координатах: [точка A, точка B] (на высоте колёс).
static func segment(p: Vector3i, shape: int) -> Array:
	var center := Vector3(p) + Vector3(0.5, 0.0625, 0.5)
	var out := []
	for e: Array in ends(shape):
		out.append(center + Vector3(e[0] as Vector3i) * 0.5 + Vector3(0, float(e[1]), 0))
	return out
