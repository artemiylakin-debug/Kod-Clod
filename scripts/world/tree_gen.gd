class_name TreeGen
extends RefCounted
## Деревья 1.2: дуб (и большой дуб), берёза, ель (сосна), тропическое (малое и огромное 2×2 с лианами),
## болотный дуб с лианами, огромные грибы. Возвращает список блоков [смещение, id, meta] относительно
## основания ствола — его используют и генератор мира, и выросший саженец.

enum { OAK, BIG_OAK, BIRCH, SPRUCE, PINE, JUNGLE, HUGE_JUNGLE, SWAMP, HUGE_BROWN_MUSHROOM, HUGE_RED_MUSHROOM }


## rng — генератор для формы. Результат: [[Vector3i, id, meta, только_в_пустоту], …].
static func plan(kind: int, rng: RandomNumberGenerator) -> Array:
	match kind:
		BIG_OAK:
			return _big_oak(rng)
		BIRCH:
			return _oak(rng, 2, 5 + rng.randi_range(0, 2))
		SPRUCE:
			return _spruce(rng)
		PINE:
			return _pine(rng)
		JUNGLE:
			return _small_jungle(rng)
		HUGE_JUNGLE:
			return _huge_jungle(rng)
		SWAMP:
			return _swamp(rng)
		HUGE_BROWN_MUSHROOM, HUGE_RED_MUSHROOM:
			return _huge_mushroom(rng, kind == HUGE_RED_MUSHROOM)
	return _oak(rng, 0, 4 + rng.randi_range(0, 2))


static func _leaf(out: Array, p: Vector3i, wood: int) -> void:
	out.append([p, Blocks.LEAVES, wood, true])


static func _log(out: Array, p: Vector3i, wood: int) -> void:
	out.append([p, Blocks.LOG, wood, false])


static func _oak(rng: RandomNumberGenerator, wood: int, trunk: int) -> Array:
	var out := []
	var top := trunk
	for dy in range(-3, 1):
		var y := top + dy
		var r := 2 if dy < -1 else 1
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r and (dy == 0 or rng.randi_range(0, 1) == 0):
					continue
				_leaf(out, Vector3i(dx, y, dz), wood)
	for y in range(0, top):
		_log(out, Vector3i(0, y, 0), wood)
	return out


static func _big_oak(rng: RandomNumberGenerator) -> Array:
	var out := []
	var h := 8 + rng.randi_range(0, 4)
	for y in h:
		_log(out, Vector3i(0, y, 0), 0)
	# Несколько ветвей с шарами листвы.
	for b in 3 + rng.randi_range(0, 2):
		var by := h - 2 - rng.randi_range(0, 4)
		var ang := rng.randf() * TAU
		var len := 2 + rng.randi_range(0, 2)
		var end := Vector3i(roundi(cos(ang) * len), by + 1, roundi(sin(ang) * len))
		for k in range(1, len + 1):
			_log(out, Vector3i(roundi(cos(ang) * k), by + (1 if k == len else 0), roundi(sin(ang) * k)), 0)
		_blob(out, end, 2, 0)
	_blob(out, Vector3i(0, h, 0), 2, 0)
	return out


static func _blob(out: Array, c: Vector3i, r: int, wood: int) -> void:
	for dy in range(-1, 2):
		var rr := r if dy == 0 else r - 1
		for dz in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if dx * dx + dz * dz <= rr * rr + 1:
					_leaf(out, c + Vector3i(dx, dy, dz), wood)


static func _spruce(rng: RandomNumberGenerator) -> Array:
	var out := []
	var h := 6 + rng.randi_range(0, 3)
	var bare := 1 + rng.randi_range(0, 1)
	var r := 0
	var y := h
	var max_r := 2 + rng.randi_range(0, 1)
	while y >= bare:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r and r > 0:
					continue
				_leaf(out, Vector3i(dx, y, dz), 1)
		r += 1
		if r > max_r:
			r = 1
		y -= 1
	_leaf(out, Vector3i(0, h + 1, 0), 1)
	for yy in range(0, h):
		_log(out, Vector3i(0, yy, 0), 1)
	return out


static func _pine(rng: RandomNumberGenerator) -> Array:
	var out := []
	var h := 7 + rng.randi_range(0, 4)
	var cap := h - 3 - rng.randi_range(0, 1)
	for y in range(cap, h + 1):
		var r := 1 if y < h - 1 else 0
		if y == cap or y == cap + 1:
			r = 2 if y == cap + 1 else 1
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) + absi(dz) <= r + 1:
					_leaf(out, Vector3i(dx, y, dz), 1)
	for y in range(0, h):
		_log(out, Vector3i(0, y, 0), 1)
	return out


static func _small_jungle(rng: RandomNumberGenerator) -> Array:
	var out := _oak(rng, 3, 4 + rng.randi_range(0, 7))
	# Лианы по краям кроны и какао (в 1.2 — без какао).
	var vines := []
	for e: Array in out:
		if int(e[1]) == Blocks.LEAVES and rng.randi_range(0, 3) == 0:
			var p: Vector3i = e[0]
			var d := rng.randi_range(0, 3)
			var n: Vector3i = Blocks.DIR_VEC[d]
			vines.append([p + n, Blocks.VINE, 1 << d, true])
	out.append_array(vines)
	return out


static func _huge_jungle(rng: RandomNumberGenerator) -> Array:
	var out := []
	var h := 12 + rng.randi_range(0, 18)
	for y in h:
		for c: Vector3i in [Vector3i(0, y, 0), Vector3i(1, y, 0), Vector3i(0, y, 1), Vector3i(1, y, 1)]:
			_log(out, c, 3)
	# Лианы по стволу.
	for y in range(0, h - 2):
		for side in 4:
			if rng.randi_range(0, 2) != 0:
				continue
			var d := side
			var n: Vector3i = Blocks.DIR_VEC[d]
			var base := Vector3i(0 if n.x <= 0 else 1, y, 0 if n.z <= 0 else 1)
			var cell := base + n
			if n.x != 0:
				cell.z = rng.randi_range(0, 1)
			else:
				cell.x = rng.randi_range(0, 1)
			out.append([cell, Blocks.VINE, 1 << d, true])
	# Крона и несколько веток с листвой.
	_canopy(out, Vector3i(0, h, 0), 4 + rng.randi_range(0, 1))
	for b in rng.randi_range(2, 4):
		var by := h - 4 - rng.randi_range(0, h / 2)
		var ang := rng.randf() * TAU
		var tip := Vector3i(roundi(cos(ang) * 4), by + 2, roundi(sin(ang) * 4))
		for k in range(1, 5):
			_log(out, Vector3i(roundi(cos(ang) * k), by + k / 2, roundi(sin(ang) * k)), 3)
		_canopy(out, tip, 2)
	return out


static func _canopy(out: Array, c: Vector3i, r: int) -> void:
	for dy in range(-1, 2):
		var rr := r - (1 if dy == 1 else 0)
		for dz in range(-rr, rr + 2):
			for dx in range(-rr, rr + 2):
				var fx := dx - 0.5
				var fz := dz - 0.5
				if fx * fx + fz * fz <= rr * rr + 1:
					_leaf(out, c + Vector3i(dx, dy, dz), 3)


static func _swamp(rng: RandomNumberGenerator) -> Array:
	var out := []
	var h := 5 + rng.randi_range(0, 3)
	for dy in range(-3, 1):
		var y := h + dy
		var r := 3 if dy < -1 else 2
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r and rng.randi_range(0, 1) == 0:
					continue
				_leaf(out, Vector3i(dx, y, dz), 0)
	for y in range(0, h):
		_log(out, Vector3i(0, y, 0), 0)
	# Свисающие лианы.
	for k in 10:
		var dx := rng.randi_range(-3, 3)
		var dz := rng.randi_range(-3, 3)
		var d := rng.randi_range(0, 3)
		for y in range(h - 3, h - 3 - rng.randi_range(1, 4), -1):
			out.append([Vector3i(dx, y, dz), Blocks.VINE, 1 << d, true])
	return out


static func _huge_mushroom(rng: RandomNumberGenerator, red: bool) -> Array:
	var out := []
	var id := Blocks.RED_MUSHROOM_BLOCK if red else Blocks.BROWN_MUSHROOM_BLOCK
	var h := 4 + rng.randi_range(0, 2)
	for y in h:
		out.append([Vector3i(0, y, 0), id, 10, false])
	if red:
		for y in range(h - 3, h + 1):
			var r := 2 if y < h else 1
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var edge := absi(dx) == r or absi(dz) == r
					if y < h and not edge:
						continue
					if absi(dx) == r and absi(dz) == r and y < h:
						continue
					out.append([Vector3i(dx, y, dz), id, _cap_meta(dx, dz, r), true])
	else:
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				if absi(dx) == 3 and absi(dz) == 3:
					continue
				out.append([Vector3i(dx, h, dz), id, _cap_meta(dx, dz, 3), true])
	return out


## Данные шляпки огромного гриба по положению в квадрате (1–9, как в оригинале).
static func _cap_meta(dx: int, dz: int, r: int) -> int:
	var col := 0 if dx == -r else (2 if dx == r else 1)
	var row := 0 if dz == -r else (2 if dz == r else 1)
	return 1 + col + row * 3


## Вид дерева для саженца данных meta (0 дуб, 1 ель, 2 берёза, 3 тропическое).
static func kind_for_sapling(meta: int, rng: RandomNumberGenerator) -> int:
	match meta & 3:
		1:
			return SPRUCE
		2:
			return BIRCH
		3:
			return JUNGLE
	return BIG_OAK if rng.randi_range(0, 9) == 0 else OAK
