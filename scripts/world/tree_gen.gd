class_name TreeGen
extends RefCounted
## Деревья 1.2: дуб (и большой дуб), берёза, ель и сосна тайги, тропическое (малое с лианами и
## огромное 2×2), тропический куст, болотный дуб с лианами, огромные грибы.
## plan() возвращает список блоков [смещение, id, meta, только_в_пустоту] относительно основания
## ствола — его использует выросший саженец. Генератор мира вызывает build() с приёмником,
## который пишет блоки прямо в чанк: случайность отдельных блоков (углы кроны, лианы) берётся из
## хеша позиции, а не из последовательности rng, поэтому дерево, обрезанное по чанку, совпадает
## с целым — части кроны в соседних чанках стыкуются.

enum { OAK, BIG_OAK, BIRCH, SPRUCE, PINE, JUNGLE, HUGE_JUNGLE, SWAMP, HUGE_BROWN_MUSHROOM, HUGE_RED_MUSHROOM,
	JUNGLE_BUSH }

## Наибольшее горизонтальное удаление блоков дерева от ствола (для отсечения по чанкам).
const REACH := [2, 6, 2, 3, 2, 3, 9, 4, 3, 2, 2]


## Приёмник блоков дерева. x0..x1, z0..z1 — смещения, которые имеет смысл строить (циклы кроны
## обрезаются по ним; блоки вне — просто отбрасываются приёмником).
class Sink extends RefCounted:
	var out := []
	var x0 := -1000
	var x1 := 1000
	var z0 := -1000
	var z1 := 1000

	func put(x: int, y: int, z: int, id: int, meta: int, only_air: bool) -> void:
		out.append([Vector3i(x, y, z), id, meta, only_air])

	## Задевает ли приёмник прямоугольник смещений [ax..bx]×[az..bz] (для пропуска ствола).
	func touches(ax: int, az: int, bx: int, bz: int) -> bool:
		return bx >= x0 and ax <= x1 and bz >= z0 and az <= z1


## rng — генератор для формы. Результат: [[Vector3i, id, meta, только_в_пустоту], …].
static func plan(kind: int, rng: RandomNumberGenerator) -> Array:
	var s := Sink.new()
	build(kind, rng, s)
	return s.out


static func build(kind: int, rng: RandomNumberGenerator, s: Sink) -> void:
	match kind:
		BIG_OAK:
			_big_oak(rng, s)
		BIRCH:
			_oak(rng, s, 2, 5 + rng.randi_range(0, 2), false)
		SPRUCE:
			_spruce(rng, s)
		PINE:
			_pine(rng, s)
		JUNGLE:
			_oak(rng, s, 3, 4 + rng.randi_range(0, 6), true)
		HUGE_JUNGLE:
			_huge_jungle(rng, s)
		SWAMP:
			_swamp(rng, s)
		HUGE_BROWN_MUSHROOM, HUGE_RED_MUSHROOM:
			_huge_mushroom(rng, s, kind == HUGE_RED_MUSHROOM)
		JUNGLE_BUSH:
			_jungle_bush(rng, s)
		_:
			_oak(rng, s, 0, 4 + rng.randi_range(0, 2), false)


## Детерминированный «случайный» байт для блока кроны.
static func _h(hs: int, x: int, y: int, z: int) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ hs
	h = h & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0xFFFF


static func _seed(rng: RandomNumberGenerator) -> int:
	return int(rng.randi()) & 0x7FFFFFFF


## Дуб/берёза/малое тропическое (WorldGenTrees): крона 5×5 и 3×3, у тропического — лианы.
static func _oak(rng: RandomNumberGenerator, s: Sink, wood: int, trunk: int, vines: bool) -> void:
	var hs := _seed(rng)
	for dy in range(-3, 1):
		var y := trunk + dy
		var r := 2 if dy < -1 else 1
		for dz in range(maxi(-r, s.z0), mini(r, s.z1) + 1):
			for dx in range(maxi(-r, s.x0), mini(r, s.x1) + 1):
				if absi(dx) == r and absi(dz) == r and (dy == 0 or _h(hs, dx, y, dz) & 1 == 0):
					continue
				s.put(dx, y, dz, Blocks.LEAVES, wood, true)
				if vines and r == 2:
					_leaf_vines(s, hs, dx, y, dz, r)
	if not s.touches(-1, -1, 1, 1):
		return
	for y in trunk:
		s.put(0, y, 0, Blocks.LOG, wood, false)
		if vines and y > 0:
			_trunk_vines(s, hs, 0, y, 0, 3)


## Лианы, свисающие с края кроны (до 4 блоков вниз), как growVines в 1.2.
static func _leaf_vines(s: Sink, hs: int, dx: int, y: int, dz: int, r: int) -> void:
	for d in 4:
		var v: Vector3i = Blocks.DIR_VEC[d]
		# Только наружу от кроны.
		if (v.x != 0 and dx * v.x < r) or (v.z != 0 and dz * v.z < r):
			continue
		var h := _h(hs, dx * 4 + d, y, dz)
		if h & 3 != 0:
			continue
		var length := 1 + ((h >> 2) & 3)
		for k in length:
			s.put(dx + v.x, y - k, dz + v.z, Blocks.VINE, 1 << d, true)


## Лианы по стволу (с вероятностью 2/3 на каждую сторону).
static func _trunk_vines(s: Sink, hs: int, x: int, y: int, z: int, salt: int) -> void:
	for d in 4:
		if _h(hs + salt, x * 4 + d, y, z) % 3 == 0:
			continue
		var v: Vector3i = Blocks.DIR_VEC[d]
		s.put(x + v.x, y, z + v.z, Blocks.VINE, 1 << d, true)


static func _big_oak(rng: RandomNumberGenerator, s: Sink) -> void:
	var h := 8 + rng.randi_range(0, 4)
	var branches := []
	for b in 3 + rng.randi_range(0, 2):
		var by := h - 2 - rng.randi_range(0, 4)
		var ang := rng.randf() * TAU
		var length := 2 + rng.randi_range(0, 2)
		branches.append([by, ang, length])
	# Шары листвы на концах ветвей и на макушке, затем ветви и ствол.
	for br: Array in branches:
		var by: int = br[0]
		var ang: float = br[1]
		var length: int = br[2]
		_blob(s, Vector3i(roundi(cos(ang) * length), by + 1, roundi(sin(ang) * length)), 2, 0)
	_blob(s, Vector3i(0, h, 0), 2, 0)
	for br: Array in branches:
		var by: int = br[0]
		var ang: float = br[1]
		var length: int = br[2]
		for k in range(1, length + 1):
			s.put(roundi(cos(ang) * k), by + (1 if k == length else 0), roundi(sin(ang) * k), Blocks.LOG, 0, false)
	for y in h:
		s.put(0, y, 0, Blocks.LOG, 0, false)


static func _blob(s: Sink, c: Vector3i, r: int, wood: int) -> void:
	for dy in range(-1, 2):
		var rr := r if dy == 0 else r - 1
		for dz in range(maxi(-rr, s.z0 - c.z), mini(rr, s.z1 - c.z) + 1):
			for dx in range(maxi(-rr, s.x0 - c.x), mini(rr, s.x1 - c.x) + 1):
				if dx * dx + dz * dz <= rr * rr + 1:
					s.put(c.x + dx, c.y + dy, c.z + dz, Blocks.LEAVES, wood, true)


## Ель тайги (WorldGenTaiga2): ярусы кроны, расширяющиеся вниз.
static func _spruce(rng: RandomNumberGenerator, s: Sink) -> void:
	var h := 6 + rng.randi_range(0, 3)
	var bare := 1 + rng.randi_range(0, 1)
	var max_r := 2 + rng.randi_range(0, 1)
	var r := rng.randi_range(0, 1)
	var cur_max := 1
	var min_r := 0
	var trunk := h - rng.randi_range(0, 2)
	for dy in range(0, h - bare + 1):
		var y := h - dy
		for dz in range(maxi(-r, s.z0), mini(r, s.z1) + 1):
			for dx in range(maxi(-r, s.x0), mini(r, s.x1) + 1):
				if absi(dx) == r and absi(dz) == r and r > 0:
					continue
				s.put(dx, y, dz, Blocks.LEAVES, 1, true)
		if r >= cur_max:
			r = min_r
			min_r = 1
			cur_max = mini(cur_max + 1, max_r)
		else:
			r += 1
	for y in trunk:
		s.put(0, y, 0, Blocks.LOG, 1, false)


## Сосна тайги (WorldGenTaiga1): высокий голый ствол и узкая шапка.
static func _pine(rng: RandomNumberGenerator, s: Sink) -> void:
	var h := 7 + rng.randi_range(0, 4)
	var bare := h - rng.randi_range(0, 1) - 3
	var max_r := 1 + rng.randi_range(0, h - bare)
	max_r = mini(max_r, 2)
	var r := 0
	for y in range(h, bare - 1, -1):
		for dz in range(maxi(-r, s.z0), mini(r, s.z1) + 1):
			for dx in range(maxi(-r, s.x0), mini(r, s.x1) + 1):
				if absi(dx) == r and absi(dz) == r and r > 0:
					continue
				s.put(dx, y, dz, Blocks.LEAVES, 1, true)
		if r >= 1 and y == bare + 1:
			r -= 1
		elif r < max_r:
			r += 1
	for y in h:
		s.put(0, y, 0, Blocks.LOG, 1, false)


## Огромное тропическое дерево (WorldGenHugeTrees): ствол 2×2, лианы, шапка и боковые ветви.
static func _huge_jungle(rng: RandomNumberGenerator, s: Sink) -> void:
	var hs := _seed(rng)
	var h := 10 + rng.randi_range(0, 19)
	var branches := []
	var by := h - 2 - rng.randi_range(0, 3)
	@warning_ignore("integer_division")
	var half := h / 2
	while by > half:
		branches.append([by, rng.randf() * TAU])
		by -= 2 + rng.randi_range(0, 3)
	_canopy(s, hs, 0, h, 0, 2)
	for br: Array in branches:
		var y: int = br[0]
		var ang: float = br[1]
		_canopy(s, hs, int(0.5 + cos(ang) * 4.0), y, int(0.5 + sin(ang) * 4.0), 0)
		for k in 5:
			@warning_ignore("integer_division")
			var ky := y - 3 + k / 2
			s.put(int(1.5 + cos(ang) * k), ky, int(1.5 + sin(ang) * k), Blocks.LOG, 3, false)
	if not s.touches(-1, -1, 2, 2):
		return
	for y in h:
		for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			s.put(c.x, y, c.y, Blocks.LOG, 3, false)
		if y > 0:
			# Лианы по стволу: по одной на каждую внешнюю грань.
			for d in 4:
				if _h(hs + 7, d, y, 0) % 3 == 0:
					continue
				var v: Vector3i = Blocks.DIR_VEC[d]
				var side := _h(hs + 9, d, y, 0) & 1
				var vx := side
				var vz := side
				if v.x < 0:
					vx = -1
				elif v.x > 0:
					vx = 2
				if v.z < 0:
					vz = -1
				elif v.z > 0:
					vz = 2
				s.put(vx, y, vz, Blocks.VINE, 1 << d, true)


## Шапка листвы огромного дерева (growLeaves 1.2): три слоя, нижний шире, рваный край.
static func _canopy(s: Sink, hs: int, cx: int, cy: int, cz: int, r: int) -> void:
	for yy in range(cy - 2, cy + 1):
		var rr := r + 1 - (yy - cy)
		var r0 := rr * rr
		var r1 := (rr + 1) * (rr + 1)
		var rm := (rr - 1) * (rr - 1)
		for dz in range(maxi(-rr, s.z0 - cz), mini(rr + 1, s.z1 - cz) + 1):
			for dx in range(maxi(-rr, s.x0 - cx), mini(rr + 1, s.x1 - cx) + 1):
				var d2 := dx * dx + dz * dz
				if not (dx >= 0 or dz >= 0 or d2 <= r0):
					continue
				if not ((dx <= 0 and dz <= 0) or d2 <= r1):
					continue
				if _h(hs, cx + dx, yy, cz + dz) & 3 == 0 and d2 > rm:
					continue
				s.put(cx + dx, yy, cz + dz, Blocks.LEAVES, 3, true)


## Болотный дуб (WorldGenSwamp): широкая плоская крона и свисающие лианы.
static func _swamp(rng: RandomNumberGenerator, s: Sink) -> void:
	var hs := _seed(rng)
	var h := 5 + rng.randi_range(0, 3)
	for dy in range(-3, 1):
		var y := h + dy
		var r := 3 if dy < -1 else 2
		for dz in range(maxi(-r, s.z0), mini(r, s.z1) + 1):
			for dx in range(maxi(-r, s.x0), mini(r, s.x1) + 1):
				if absi(dx) == r and absi(dz) == r and (dy == 0 or _h(hs, dx, y, dz) & 1 == 0):
					continue
				s.put(dx, y, dz, Blocks.LEAVES, 0, true)
				if absi(dx) == r or absi(dz) == r:
					_leaf_vines(s, hs, dx, y, dz, r)
	for y in h:
		s.put(0, y, 0, Blocks.LOG, 0, false)


static func _huge_mushroom(rng: RandomNumberGenerator, s: Sink, red: bool) -> void:
	var id := Blocks.RED_MUSHROOM_BLOCK if red else Blocks.BROWN_MUSHROOM_BLOCK
	var h := 4 + rng.randi_range(0, 2)
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
					s.put(dx, y, dz, id, _cap_meta(dx, dz, r), true)
	else:
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				if absi(dx) == 3 and absi(dz) == 3:
					continue
				s.put(dx, h, dz, id, _cap_meta(dx, dz, 3), true)
	for y in h:
		s.put(0, y, 0, id, 10, false)


## Данные шляпки огромного гриба по положению в квадрате (1–9, как в оригинале).
static func _cap_meta(dx: int, dz: int, r: int) -> int:
	var col := 0 if dx == -r else (2 if dx == r else 1)
	var row := 0 if dz == -r else (2 if dz == r else 1)
	return 1 + col + row * 3


## Тропический куст (WorldGenShrub): одно бревно и «шапка» листвы дуба.
static func _jungle_bush(rng: RandomNumberGenerator, s: Sink) -> void:
	var hs := _seed(rng)
	for dy in 3:
		var r := 2 - dy
		for dz in range(maxi(-r, s.z0), mini(r, s.z1) + 1):
			for dx in range(maxi(-r, s.x0), mini(r, s.x1) + 1):
				if absi(dx) == r and absi(dz) == r and r > 0 and _h(hs, dx, dy, dz) & 1 == 0:
					continue
				s.put(dx, dy, dz, Blocks.LEAVES, 0, true)
	s.put(0, 0, 0, Blocks.LOG, 3, false)


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
