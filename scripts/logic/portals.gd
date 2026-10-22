class_name Portals
extends RefCounted
## Порталы 1.2: портал в Нижний мир (рамка из обсидиана 4×5, внутри 2×3, зажигается огнём),
## портал в Край (кольцо из 12 рамок с очами Края вокруг площадки 3×3), платформа прибытия в Край.

## Размер внутренней части портала в Нижний мир.
const INNER_W := 2
const INNER_H := 3
## Точка прибытия в Край и обсидиановая платформа под ней (как в оригинале).
const END_SPAWN := Vector3i(100, 49, 0)


## Огонь в клетке p внутри рамки из обсидиана превращает её внутренность в портал. true — портал создан.
static func try_light(world: World, p: Vector3i) -> bool:
	for axis in 2:
		var origin := _find_frame(world, p, axis)
		if origin.y >= 0:
			_fill(world, origin, axis)
			return true
	return false


static func _axis_vec(axis: int) -> Vector3i:
	return Vector3i(1, 0, 0) if axis == 0 else Vector3i(0, 0, 1)


static func _free(id: int) -> bool:
	return id == Blocks.AIR or id == Blocks.FIRE


## Нижний левый угол внутренней части рамки, содержащей p, или (0, -1, 0).
static func _find_frame(world: World, p: Vector3i, axis: int) -> Vector3i:
	if not _free(world.get_block_v(p)):
		return Vector3i(0, -1, 0)
	var a := _axis_vec(axis)
	var bottom := p
	var guard := 0
	while _free(world.get_block_v(bottom + Vector3i(0, -1, 0))) and guard < INNER_H:
		bottom.y -= 1
		guard += 1
	var left := bottom
	guard = 0
	while _free(world.get_block_v(left - a)) and guard < INNER_W:
		left -= a
		guard += 1
	# Проверка: внутренность 2×3 свободна, по краям — обсидиан (углы рамки не обязательны).
	for i in INNER_W:
		for j in INNER_H:
			if not _free(world.get_block_v(left + a * i + Vector3i(0, j, 0))):
				return Vector3i(0, -1, 0)
	for i in INNER_W:
		if world.get_block_v(left + a * i + Vector3i(0, -1, 0)) != Blocks.OBSIDIAN:
			return Vector3i(0, -1, 0)
		if world.get_block_v(left + a * i + Vector3i(0, INNER_H, 0)) != Blocks.OBSIDIAN:
			return Vector3i(0, -1, 0)
	for j in INNER_H:
		if world.get_block_v(left - a + Vector3i(0, j, 0)) != Blocks.OBSIDIAN:
			return Vector3i(0, -1, 0)
		if world.get_block_v(left + a * INNER_W + Vector3i(0, j, 0)) != Blocks.OBSIDIAN:
			return Vector3i(0, -1, 0)
	return left


static func _fill(world: World, origin: Vector3i, axis: int) -> void:
	var a := _axis_vec(axis)
	for i in INNER_W:
		for j in INNER_H:
			var q := origin + a * i + Vector3i(0, j, 0)
			# Тихая установка: соседние блоки портала ещё не готовы и не должны его «ломать».
			world.set_block(q.x, q.y, q.z, Blocks.PORTAL, axis, false)
	world.flush_remesh()


## Держится ли блок портала: соседи в его плоскости — портал или обсидиан.
static func is_intact(world: World, p: Vector3i) -> bool:
	var a := _axis_vec(world.get_meta_v(p) & 1)
	for d: Vector3i in [Vector3i(0, 1, 0), Vector3i(0, -1, 0), a, -a]:
		var id := world.get_block_v(p + d)
		if id != Blocks.PORTAL and id != Blocks.OBSIDIAN:
			return false
	return true


## Портал рассыпается целиком.
static func break_portal(world: World, p: Vector3i) -> void:
	var queue: Array[Vector3i] = [p]
	var seen := {p: true}
	var head := 0
	while head < queue.size() and head < 64:
		var c := queue[head]
		head += 1
		for d in 6:
			var n: Vector3i = c + Blocks.FACE_VEC[d]
			if not seen.has(n) and world.get_block_v(n) == Blocks.PORTAL:
				seen[n] = true
				queue.append(n)
	for c in queue:
		world.set_block(c.x, c.y, c.z, Blocks.AIR, 0, false)
	world.flush_remesh()


## Ближайший блок портала в загруженной области вокруг center (по горизонтали radius).
static func find_portal(world: World, center: Vector3, radius: int) -> Vector3i:
	var best := Vector3i(0, -1, 0)
	var best_d := INF
	var c := Vector3i(floori(center.x), floori(center.y), floori(center.z))
	var top := WorldGen.CHUNK_HEIGHT - 2 if world.dimension != -1 else 126
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := c.x + dx
			var z := c.z + dz
			if not world.has_chunk_at(x, z):
				continue
			for y in range(1, top):
				if world.get_block(x, y, z) == Blocks.PORTAL and world.get_block(x, y - 1, z) != Blocks.PORTAL:
					var d := Vector3(dx, (y - c.y) * 0.5, dz).length()
					if d < best_d:
						best_d = d
						best = Vector3i(x, y, z)
	return best


## Строит новый портал рядом с точкой target и возвращает клетку внутри него (нижнюю).
static func build_portal(world: World, target: Vector3) -> Vector3i:
	var c := Vector3i(floori(target.x), floori(target.y), floori(target.z))
	var low := 34 if world.dimension == -1 else WorldGen.SEA_LEVEL + 1
	var high := 118 if world.dimension == -1 else WorldGen.CHUNK_HEIGHT - 10
	# Ищем место: 4 клетки опоры и пустое пространство 4×5 над ними.
	for r in range(0, 17, 2):
		for dz in range(-r, r + 1, 2):
			for dx in range(-r, r + 1, 2):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				for dy in range(0, 48):
					for sign: int in [1, -1]:
						var y := c.y + dy * sign
						if y < low or y > high:
							continue
						var o := Vector3i(c.x + dx, y, c.z + dz)
						if _site_ok(world, o):
							return _construct(world, o, false)
	# Подходящего места нет — строим в воздухе (или в толще камня) с площадкой.
	var y := clampi(c.y, low, high)
	return _construct(world, Vector3i(c.x, y, c.z), true)


static func _site_ok(world: World, o: Vector3i) -> bool:
	for i in 4:
		var floor_id := world.get_block_v(o + Vector3i(i, -1, 0))
		if not Blocks.is_solid(floor_id) or Blocks.is_liquid(floor_id):
			return false
		for j in 5:
			for k in [-1, 0, 1]:
				if world.get_block_v(o + Vector3i(i, j, k)) != Blocks.AIR:
					return false
	return true


## Рамка вдоль X с левым нижним углом o. platform — подложить обсидиан и расчистить место.
static func _construct(world: World, o: Vector3i, platform: bool) -> Vector3i:
	if platform:
		for i in range(-1, 5):
			for k in range(-1, 2):
				world.set_block(o.x + i, o.y - 1, o.z + k, Blocks.OBSIDIAN, 0, false)
				for j in 5:
					world.set_block(o.x + i, o.y + j, o.z + k, Blocks.AIR, 0, false)
	for i in 4:
		for j in 5:
			var edge := i == 0 or i == 3 or j == 0 or j == 4
			world.set_block(o.x + i, o.y + j, o.z, Blocks.OBSIDIAN if edge else Blocks.PORTAL, 0, false)
	world.flush_remesh()
	return o + Vector3i(1, 1, 0)


# --- Портал в Край -----------------------------------------------------------

## После вставки ока в рамку p: если кольцо из 12 рамок с очами замкнуто — открывается портал.
static func check_end_portal(world: World, p: Vector3i) -> bool:
	for cz in range(p.z - 3, p.z + 4):
		for cx in range(p.x - 3, p.x + 4):
			var c := Vector3i(cx, p.y, cz)
			if _ring_complete(world, c):
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						world.set_block(c.x + dx, c.y, c.z + dz, Blocks.END_PORTAL, 0, false)
				world.flush_remesh()
				return true
	return false


static func _ring_complete(world: World, c: Vector3i) -> bool:
	for k in range(-1, 2):
		for q: Vector3i in [Vector3i(k, 0, -2), Vector3i(k, 0, 2), Vector3i(-2, 0, k), Vector3i(2, 0, k)]:
			var pos := c + q
			if world.get_block_v(pos) != Blocks.END_PORTAL_FRAME or world.get_meta_v(pos) & 4 == 0:
				return false
	return true


## Обсидиановая площадка 5×5 в Краю и пустота над ней.
static func make_end_platform(world: World) -> void:
	var s := END_SPAWN
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			world.set_block(s.x + dx, s.y - 1, s.z + dz, Blocks.OBSIDIAN, 0, false)
			for dy in 3:
				world.set_block(s.x + dx, s.y + dy, s.z + dz, Blocks.AIR, 0, false)
	world.flush_remesh()
