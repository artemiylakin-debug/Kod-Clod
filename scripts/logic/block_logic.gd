class_name BlockLogic
extends Node
## Поведение блоков (20 игровых тиков в секунду, как в оригинале): обновления соседей,
## отложенные тики, текущие вода и лава, падающие песок и гравий, отрыв блоков без опоры,
## случайные тики (рост растений, грядки, трава, огонь), опадание листвы, взрывы.

const TICK := 0.05
const RANDOM_TICK_RADIUS := 6
const WATER_DELAY := 5
const LAVA_DELAY := 30

var world: World
## Игровая сцена: spawn_drop(...), entities (EntityManager) и пр.
var game: Node
var redstone: Redstone
var containers: Containers
var tick := 0
var raining := false
var rng := RandomNumberGenerator.new()

## Отложенные тики: номер тика → массив позиций; позиция → номер тика (без дублей).
var _due: Dictionary = {}
var _pending: Dictionary = {}
var _acc := 0.0
var _random_acc := 0.0
## Позиции, чьи соседи меняются в текущем обновлении (защита от бесконечной рекурсии).
var _depth := 0


func setup(p_world: World, p_game: Node) -> void:
	world = p_world
	game = p_game
	world.logic = self
	redstone = Redstone.new(self)
	containers = Containers.new(self)
	rng.randomize()
	world.chunk_loaded.connect(_on_chunk_loaded)


## Работающие печи и стойки в загруженном чанке продолжают работу.
func _on_chunk_loaded(ch: Chunk) -> void:
	for i: int in ch.block_entities:
		var be: Dictionary = ch.block_entities[i]
		if int(be.get("burn", 0)) > 0 or int(be.get("brew", 0)) > 0:
			var lp := Chunk.local_pos(i)
			containers.mark_active(Vector3i(ch.key.x * 16 + lp.x, lp.y, ch.key.y * 16 + lp.z))


func _process(delta: float) -> void:
	if world == null:
		return
	_acc = minf(_acc + delta, 0.5)
	while _acc >= TICK:
		_acc -= TICK
		game_tick()


func game_tick() -> void:
	tick += 1
	var list: Variant = _due.get(tick)
	if list != null:
		_due.erase(tick)
		for p: Vector3i in list:
			if _pending.get(p) == tick:
				_pending.erase(p)
				_scheduled_tick(p)
	redstone.on_tick()
	containers.tick()
	_random_acc += TICK
	if _random_acc >= 1.0:
		_random_acc = 0.0
		_random_ticks()


## Отложенный тик блока через delay игровых тиков.
func schedule(p: Vector3i, delay: int) -> void:
	var due := tick + maxi(delay, 1)
	var cur: Variant = _pending.get(p)
	if cur != null and int(cur) <= due and int(cur) > tick:
		return
	_pending[p] = due
	if not _due.has(due):
		_due[due] = []
	(_due[due] as Array).append(p)


func is_scheduled(p: Vector3i) -> bool:
	return _pending.has(p)


# --- Изменения блоков ------------------------------------------------------

## Вызывается миром после каждого изменения блока (World.set_block с notify).
func on_block_changed(p: Vector3i, old: int, old_meta: int, id: int, meta: int) -> void:
	_depth += 1
	if _depth > 64:
		_depth -= 1
		return
	if Blocks.is_liquid(id):
		schedule(p, _liquid_delay(id))
	if Blocks.gravity_flags[id] == 1:
		schedule(p, 2)
	if old == Blocks.LOG and id != Blocks.LOG:
		_schedule_leaf_decay(p)
	if Blocks.has_block_entity(old) and old != id and not (old == Blocks.FURNACE and id == Blocks.LIT_FURNACE) \
			and not (old == Blocks.LIT_FURNACE and id == Blocks.FURNACE):
		_spill_container(p, old)
	redstone.on_block_changed(p, old, old_meta, id, meta)
	for d in 6:
		_neighbor_changed(p + Blocks.FACE_VEC[d], p)
	_depth -= 1


func _neighbor_changed(p: Vector3i, from: Vector3i) -> void:
	var id := world.get_block_v(p)
	if id == Blocks.AIR:
		return
	if Blocks.is_liquid(id):
		schedule(p, _liquid_delay(id))
		return
	if Blocks.gravity_flags[id] == 1:
		schedule(p, 2)
	if Blocks.needs_support[id] == 1 and not is_supported(p, id, world.get_meta_v(p)):
		break_naturally(p)
		return
	match id:
		Blocks.FARMLAND, Blocks.GRASS, Blocks.MYCELIUM:
			if from == p + Vector3i(0, 1, 0) and Blocks.is_opaque(world.get_block_v(from)):
				world.set_block(p.x, p.y, p.z, Blocks.DIRT)
				return
		Blocks.CACTUS:
			for d in 4:
				if Blocks.is_solid(world.get_block_v(p + Blocks.DIR_VEC[d])):
					break_naturally(p)
					return
		Blocks.TNT:
			pass
	redstone.on_neighbor_changed(p, from)


func _liquid_delay(id: int) -> int:
	if Blocks.is_water(id):
		return WATER_DELAY
	return 10 if world.dimension == -1 else LAVA_DELAY


## Ломает блок с выпадением предметов (как при отсутствии опоры).
func break_naturally(p: Vector3i, tool := Blocks.TOOL_NONE, tier := -1) -> void:
	var id := world.get_block_v(p)
	if id == Blocks.AIR:
		return
	var meta := world.get_meta_v(p)
	_remove_with_partner(p, id, meta)
	drop_block_items(p, id, meta, tool, tier)


## Двери и кровати состоят из двух блоков: убирается и вторая половина.
func _remove_with_partner(p: Vector3i, id: int, meta: int) -> void:
	world.set_block(p.x, p.y, p.z, Blocks.AIR, 0)
	if Blocks.is_door(id):
		var other := p + (Vector3i(0, -1, 0) if meta & 8 else Vector3i(0, 1, 0))
		if world.get_block_v(other) == id:
			world.set_block(other.x, other.y, other.z, Blocks.AIR, 0)
	elif id == Blocks.BED:
		var dir: Vector3i = Blocks.DIR_VEC[meta & 3]
		var other := p - dir if meta & 8 else p + dir
		if world.get_block_v(other) == Blocks.BED:
			world.set_block(other.x, other.y, other.z, Blocks.AIR, 0)


func drop_block_items(p: Vector3i, id: int, meta: int, tool := Blocks.TOOL_NONE, tier := -1) -> void:
	if game == null:
		return
	for d: Array in Blocks.drops(id, meta, tool, tier, rng):
		if int(d[1]) > 0:
			game.call("spawn_drop", int(d[0]), int(d[1]), int(d[2]), Vector3(p) + Vector3(0.5, 0.3, 0.5))


func _spill_container(p: Vector3i, _old: int) -> void:
	var be := world.remove_block_entity(p)
	var items: Variant = be.get("items", [])
	if game == null or not items is Array:
		return
	for slot: Variant in items:
		if slot is Array and slot.size() >= 3 and int(slot[1]) > 0:
			game.call("spawn_drop", int(slot[0]), int(slot[1]), int(slot[2]), Vector3(p) + Vector3(0.5, 0.5, 0.5))


## Можно ли поставить блок с опорой в p (проверка до установки).
func is_supported_placement(p: Vector3i, id: int, meta: int) -> bool:
	return is_supported(p, id, meta)


## Есть ли у блока опора (факел на стене, растение на земле…).
func is_supported(p: Vector3i, id: int, meta: int) -> bool:
	var below := world.get_block_v(p + Vector3i(0, -1, 0))
	match id:
		Blocks.TORCH, Blocks.REDSTONE_TORCH, Blocks.REDSTONE_TORCH_OFF:
			var att := meta & 7
			var s := world.get_block_v(p + Blocks.attach_offset(att))
			if att == 0:
				return Blocks.is_opaque(s) or Blocks.is_fence_like(s) or s == Blocks.GLASS
			return Blocks.is_opaque(s)
		Blocks.LEVER, Blocks.STONE_BUTTON:
			return Blocks.is_opaque(world.get_block_v(p + Blocks.attach_offset(meta & 7)))
		Blocks.SAPLING, Blocks.DANDELION, Blocks.ROSE, Blocks.TALLGRASS:
			return below == Blocks.GRASS or below == Blocks.DIRT or below == Blocks.FARMLAND
		Blocks.DEADBUSH:
			return below == Blocks.SAND or below == Blocks.GRASS or below == Blocks.DIRT
		Blocks.BROWN_MUSHROOM, Blocks.RED_MUSHROOM:
			return Blocks.is_opaque(below) or below == Blocks.MYCELIUM
		Blocks.WHEAT, Blocks.PUMPKIN_STEM, Blocks.MELON_STEM:
			return below == Blocks.FARMLAND
		Blocks.NETHER_WART:
			return below == Blocks.SOUL_SAND
		Blocks.REEDS:
			if below == Blocks.REEDS:
				return true
			if below != Blocks.GRASS and below != Blocks.DIRT and below != Blocks.SAND:
				return false
			for d in 4:
				if Blocks.is_water(world.get_block_v(p + Vector3i(0, -1, 0) + Blocks.DIR_VEC[d])):
					return true
			return false
		Blocks.CACTUS:
			return below == Blocks.CACTUS or below == Blocks.SAND
		Blocks.WATERLILY:
			return below == Blocks.WATER
		Blocks.SNOW_LAYER:
			return Blocks.is_opaque(below) or below == Blocks.LEAVES
		Blocks.LADDER:
			return Blocks.is_opaque(world.get_block_v(p - Blocks.DIR_VEC[meta & 3]))
		Blocks.WALL_SIGN:
			return Blocks.is_solid(world.get_block_v(p - Blocks.DIR_VEC[meta & 3]))
		Blocks.VINE:
			if Blocks.is_opaque(world.get_block_v(p + Vector3i(0, 1, 0))) or world.get_block_v(p + Vector3i(0, 1, 0)) == Blocks.LEAVES:
				return true
			for d in 4:
				if meta & (1 << d):
					var w := world.get_block_v(p - Blocks.DIR_VEC[d])
					if Blocks.is_opaque(w) or w == Blocks.LEAVES:
						return true
			return world.get_block_v(p + Vector3i(0, 1, 0)) == Blocks.VINE
		Blocks.WOODEN_DOOR, Blocks.IRON_DOOR:
			if meta & 8:
				return world.get_block_v(p + Vector3i(0, -1, 0)) == id
			return Blocks.is_solid(below) and world.get_block_v(p + Vector3i(0, 1, 0)) == id
		Blocks.BED:
			var dir: Vector3i = Blocks.DIR_VEC[meta & 3]
			return world.get_block_v(p - dir if meta & 8 else p + dir) == Blocks.BED
		Blocks.CAKE, Blocks.SIGN_POST, Blocks.REDSTONE_WIRE, Blocks.REPEATER_OFF, Blocks.REPEATER_ON, \
				Blocks.STONE_PLATE, Blocks.WOODEN_PLATE, Blocks.RAIL, Blocks.POWERED_RAIL, Blocks.DETECTOR_RAIL:
			return Blocks.is_solid(below)
	return true


# --- Отложенные тики -------------------------------------------------------

func _scheduled_tick(p: Vector3i) -> void:
	var id := world.get_block_v(p)
	if Blocks.is_liquid(id):
		_liquid_tick(p, id)
	elif Blocks.gravity_flags[id] == 1:
		_fall(p, id)
	elif id == Blocks.LEAVES:
		_check_decay(p)
	elif id == Blocks.LIT_REDSTONE_ORE:
		world.set_block(p.x, p.y, p.z, Blocks.REDSTONE_ORE)
	else:
		redstone.on_scheduled(p, id)


# --- Жидкости --------------------------------------------------------------

func _same_liquid(id: int, water: bool) -> bool:
	return Blocks.is_water(id) if water else Blocks.is_lava(id)


## Уровень жидкости: 0 — источник или падающая, 1–7 — растекающаяся (больше — мельче).
func _level(p: Vector3i, water: bool) -> int:
	var id := world.get_block_v(p)
	if not _same_liquid(id, water):
		return -1
	var m := world.get_meta_v(p)
	return 0 if m >= 8 else m


func _is_source(p: Vector3i, water: bool) -> bool:
	var id := world.get_block_v(p)
	return (id == Blocks.WATER if water else id == Blocks.LAVA) and world.get_meta_v(p) == 0


## Может ли жидкость затечь в клетку (пустота, трава, факелы…).
func _can_flow_into(p: Vector3i, water: bool) -> bool:
	var id := world.get_block_v(p)
	if id == Blocks.AIR:
		return true
	if Blocks.is_liquid(id):
		return not _same_liquid(id, water)
	if id == Blocks.WATERLILY:
		return false
	if Blocks.is_door(id) or Blocks.is_solid(id):
		return false
	return Blocks.is_replaceable(id) or Blocks.needs_support[id] == 1 or id == Blocks.WEB


func _liquid_tick(p: Vector3i, id: int) -> void:
	var water := Blocks.is_water(id)
	var decay := 1 if water or world.dimension == -1 else 2
	var meta := world.get_meta_v(p)
	var flowing_id := Blocks.FLOWING_WATER if water else Blocks.FLOWING_LAVA
	var still_id := Blocks.WATER if water else Blocks.LAVA
	var level := 0 if meta >= 8 else meta
	if not _is_source(p, water):
		# Пересчёт уровня по соседям: без подпитки жидкость отступает.
		# new_meta: 8 — падающая сверху, 1–7 — растекающаяся, 0 — новый источник.
		var new_meta := 8
		if not _same_liquid(world.get_block_v(p + Vector3i(0, 1, 0)), water):
			var new_level := 99
			var sources := 0
			for d in 4:
				var q: Vector3i = p + Blocks.DIR_VEC[d]
				var l := _level(q, water)
				if l < 0:
					continue
				if _is_source(q, water):
					sources += 1
				new_level = mini(new_level, l + decay)
			# Бесконечный источник воды: два источника рядом и опора снизу.
			if water and sources >= 2:
				var below := world.get_block_v(p + Vector3i(0, -1, 0))
				if Blocks.is_solid(below) or _is_source(p + Vector3i(0, -1, 0), true):
					new_level = 0
			if new_level >= 8:
				world.set_block(p.x, p.y, p.z, Blocks.AIR)
				return
			new_meta = new_level
		if new_meta == 0:
			world.set_block(p.x, p.y, p.z, still_id, 0)
			return
		if new_meta != meta:
			world.set_block(p.x, p.y, p.z, flowing_id, new_meta)
			return
		level = 0 if new_meta == 8 else new_meta
	# Встреча лавы с водой.
	if not water and _touches_water(p):
		world.set_block(p.x, p.y, p.z, Blocks.OBSIDIAN if _is_source(p, false) else Blocks.COBBLESTONE)
		return
	# Вниз.
	var down := p + Vector3i(0, -1, 0)
	if down.y >= 0 and _can_flow_into(down, water):
		_flow_to(down, water, 8)
		return
	if _same_liquid(world.get_block_v(down), water) and not _is_source(p, water):
		return
	var next := level + decay
	if next >= 8:
		return
	for d in _flow_dirs(p, water):
		var q: Vector3i = p + Blocks.DIR_VEC[d]
		var l := _level(q, water)
		if l >= 0:
			if not _is_source(q, water) and world.get_meta_v(q) < 8 and l > next:
				world.set_block(q.x, q.y, q.z, flowing_id, next)
			continue
		if _can_flow_into(q, water):
			_flow_to(q, water, next)


func _touches_water(p: Vector3i) -> bool:
	for d in [0, 1, 2, 4, 5]:
		if Blocks.is_water(world.get_block_v(p + Blocks.FACE_VEC[d])):
			return true
	return false


func _flow_to(q: Vector3i, water: bool, level: int) -> void:
	var cur := world.get_block_v(q)
	if Blocks.is_liquid(cur):
		# Вода в лаву: источник → обсидиан, поток → булыжник; лава в воду — камень.
		if water:
			world.set_block(q.x, q.y, q.z, Blocks.OBSIDIAN if world.get_meta_v(q) == 0 and cur == Blocks.LAVA else Blocks.COBBLESTONE)
		else:
			world.set_block(q.x, q.y, q.z, Blocks.STONE)
		return
	if cur != Blocks.AIR:
		if not Blocks.is_replaceable(cur):
			drop_block_items(q, cur, world.get_meta_v(q))
	world.set_block(q.x, q.y, q.z, Blocks.FLOWING_WATER if water else Blocks.FLOWING_LAVA, level)


## Направления растекания: к ближайшему обрыву в пределах 4 блоков (как в оригинале).
func _flow_dirs(p: Vector3i, water: bool) -> Array:
	var best := 1000
	var dirs := []
	for d in 4:
		var q: Vector3i = p + Blocks.DIR_VEC[d]
		if not _can_flow_into(q, water) and _level(q, water) < 0:
			continue
		if _is_source(q, water):
			continue
		var dist := _drop_distance(q, (d + 2) % 4, 1, water)
		if dist < best:
			best = dist
			dirs = [d]
		elif dist == best:
			dirs.append(d)
	return dirs


func _drop_distance(q: Vector3i, from: int, depth: int, water: bool) -> int:
	if _can_flow_into(q + Vector3i(0, -1, 0), water) or _same_liquid(world.get_block_v(q + Vector3i(0, -1, 0)), water):
		return depth
	if depth >= 4:
		return 1000
	var best := 1000
	for d in 4:
		if d == from:
			continue
		var n: Vector3i = q + Blocks.DIR_VEC[d]
		if not _can_flow_into(n, water) and _level(n, water) < 0:
			continue
		best = mini(best, _drop_distance(n, (d + 2) % 4, depth + 1, water))
	return best


# --- Падающие блоки --------------------------------------------------------

func _passable_for_fall(id: int) -> bool:
	return id == Blocks.AIR or Blocks.is_liquid(id) or id == Blocks.FIRE or (Blocks.is_replaceable(id) and not Blocks.is_solid(id))


func _fall(p: Vector3i, id: int) -> void:
	var below := world.get_block_v(p + Vector3i(0, -1, 0))
	if p.y <= 0 or not _passable_for_fall(below):
		return
	var meta := world.get_meta_v(p)
	world.set_block(p.x, p.y, p.z, Blocks.AIR)
	var entities: Variant = game.get("entities") if game != null else null
	if entities != null and entities.has_method("spawn_falling_block"):
		entities.call("spawn_falling_block", id, meta, Vector3(p) + Vector3(0.5, 0.0, 0.5))
		return
	# Без менеджера существ — блок сразу оказывается на опоре.
	var y := p.y - 1
	while y > 0 and _passable_for_fall(world.get_block(p.x, y - 1, p.z)):
		y -= 1
	world.set_block(p.x, y, p.z, id, meta)


## Падающий блок приземлился в клетке p.
func land_falling_block(p: Vector3i, id: int, meta: int) -> void:
	var cur := world.get_block_v(p)
	if cur == Blocks.AIR or Blocks.is_liquid(cur) or Blocks.is_replaceable(cur):
		world.set_block(p.x, p.y, p.z, id, meta)
	else:
		drop_block_items(p, id, meta)


# --- Листва ----------------------------------------------------------------

func _schedule_leaf_decay(p: Vector3i) -> void:
	for dy in range(-4, 5):
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				var q := p + Vector3i(dx, dy, dz)
				if world.get_block_v(q) == Blocks.LEAVES and world.get_meta_v(q) & 4 == 0:
					schedule(q, rng.randi_range(20, 240))


## Листва без бревна в пределах 4 блоков опадает.
func _check_decay(p: Vector3i) -> void:
	if world.get_meta_v(p) & 4:
		return
	var seen := {p: 0}
	var queue: Array[Vector3i] = [p]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var dist: int = seen[c]
		for d in 6:
			var n: Vector3i = c + Blocks.FACE_VEC[d]
			if seen.has(n):
				continue
			var b := world.get_block_v(n)
			if b == Blocks.LOG:
				return
			if b == Blocks.LEAVES and dist < 4:
				seen[n] = dist + 1
				queue.append(n)
	break_naturally(p)


# --- Случайные тики --------------------------------------------------------

func _random_ticks() -> void:
	var focus: Vector3 = game.call("focus_position") if game != null and game.has_method("focus_position") else Vector3.ZERO
	var center := World.key_of(focus)
	for dz in range(-RANDOM_TICK_RADIUS, RANDOM_TICK_RADIUS + 1):
		for dx in range(-RANDOM_TICK_RADIUS, RANDOM_TICK_RADIUS + 1):
			var ch: Chunk = world.chunks.get(center + Vector2i(dx, dz))
			if ch == null or ch.tickers.is_empty():
				continue
			var ox := ch.key.x * 16
			var oz := ch.key.y * 16
			for i: int in ch.tickers.keys():
				var id := ch.blocks[i]
				var lp := Chunk.local_pos(i)
				_random_tick(Vector3i(ox + lp.x, lp.y, oz + lp.z), id, ch.meta[i])


func _light_at(p: Vector3i) -> int:
	var sky := world.get_sky_light(p)
	var daylight := 15
	if game != null and game.has_method("sky_light_level"):
		daylight = int(game.call("sky_light_level"))
	return maxi(mini(sky, daylight), world.get_block_light(p))


func _random_tick(p: Vector3i, id: int, meta: int) -> void:
	match id:
		Blocks.SAPLING:
			if _light_at(p + Vector3i(0, 1, 0)) >= 9 and rng.randi_range(1, 400) == 1:
				grow_tree(p, meta)
		Blocks.WHEAT:
			if meta < 7 and _light_at(p + Vector3i(0, 1, 0)) >= 9:
				var wet := world.get_meta_v(p + Vector3i(0, -1, 0)) > 0
				if rng.randi_range(1, 50 if wet else 110) == 1:
					world.set_meta_at(p.x, p.y, p.z, meta + 1)
		Blocks.PUMPKIN_STEM, Blocks.MELON_STEM:
			if _light_at(p + Vector3i(0, 1, 0)) < 9 or rng.randi_range(1, 50) != 1:
				return
			if meta < 7:
				world.set_meta_at(p.x, p.y, p.z, meta + 1)
				return
			var fruit := Blocks.PUMPKIN if id == Blocks.PUMPKIN_STEM else Blocks.MELON
			for d in 4:
				if world.get_block_v(p + Blocks.DIR_VEC[d]) == fruit:
					return
			var d := rng.randi_range(0, 3)
			var q: Vector3i = p + Blocks.DIR_VEC[d]
			var ground := world.get_block_v(q + Vector3i(0, -1, 0))
			if world.get_block_v(q) == Blocks.AIR and (ground == Blocks.DIRT or ground == Blocks.GRASS or ground == Blocks.FARMLAND):
				world.set_block(q.x, q.y, q.z, fruit, rng.randi_range(0, 3) if fruit == Blocks.PUMPKIN else 0)
		Blocks.NETHER_WART:
			if meta < 3 and rng.randi_range(1, 60) == 1:
				world.set_meta_at(p.x, p.y, p.z, meta + 1)
		Blocks.REEDS, Blocks.CACTUS:
			if world.get_block_v(p + Vector3i(0, 1, 0)) != Blocks.AIR or rng.randi_range(1, 60) != 1:
				return
			var h := 1
			while h < 3 and world.get_block_v(p - Vector3i(0, h, 0)) == id:
				h += 1
			if h < 3:
				world.set_block(p.x, p.y + 1, p.z, id)
		Blocks.FARMLAND:
			var wet := _water_near(p, 4)
			if wet and meta < 7:
				world.set_meta_at(p.x, p.y, p.z, 7)
			elif not wet and rng.randi_range(1, 20) == 1:
				if meta > 0:
					world.set_meta_at(p.x, p.y, p.z, meta - 1)
				elif world.get_block_v(p + Vector3i(0, 1, 0)) == Blocks.AIR:
					world.set_block(p.x, p.y, p.z, Blocks.DIRT)
		Blocks.DIRT:
			# Трава разрастается на освещённую землю рядом.
			if Blocks.is_opaque(world.get_block_v(p + Vector3i(0, 1, 0))):
				return
			for k in 4:
				var q := p + Vector3i(rng.randi_range(-1, 1), rng.randi_range(-1, 1), rng.randi_range(-1, 1))
				var g := world.get_block_v(q)
				if (g == Blocks.GRASS or g == Blocks.MYCELIUM) and rng.randi_range(1, 6) == 1:
					world.set_block(p.x, p.y, p.z, g)
					return
		Blocks.GRASS, Blocks.MYCELIUM:
			if Blocks.is_opaque(world.get_block_v(p + Vector3i(0, 1, 0))):
				world.set_block(p.x, p.y, p.z, Blocks.DIRT)
			else:
				var q := p + Vector3i(rng.randi_range(-1, 1), rng.randi_range(-2, 1), rng.randi_range(-1, 1))
				if world.get_block_v(q) == Blocks.DIRT and not Blocks.is_opaque(world.get_block_v(q + Vector3i(0, 1, 0))) \
						and rng.randi_range(1, 4) == 1:
					world.set_block(q.x, q.y, q.z, id)
		Blocks.ICE, Blocks.SNOW_LAYER:
			if world.get_block_light(p) > 11:
				if id == Blocks.ICE:
					world.set_block(p.x, p.y, p.z, Blocks.WATER)
				else:
					world.set_block(p.x, p.y, p.z, Blocks.AIR)
		Blocks.FIRE:
			_fire_tick(p, meta)
		Blocks.LIT_REDSTONE_ORE:
			if rng.randi_range(1, 5) == 1:
				world.set_block(p.x, p.y, p.z, Blocks.REDSTONE_ORE)
		Blocks.BROWN_MUSHROOM, Blocks.RED_MUSHROOM:
			if rng.randi_range(1, 400) == 1:
				var q := p + Vector3i(rng.randi_range(-2, 2), rng.randi_range(-1, 1), rng.randi_range(-2, 2))
				if world.get_block_v(q) == Blocks.AIR and Blocks.is_opaque(world.get_block_v(q + Vector3i(0, -1, 0))) \
						and _light_at(q) < 13:
					world.set_block(q.x, q.y, q.z, id)


func _water_near(p: Vector3i, r: int) -> bool:
	for dy in range(0, 2):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if Blocks.is_water(world.get_block(p.x + dx, p.y + dy, p.z + dz)):
					return true
	return false


# --- Огонь -----------------------------------------------------------------

func _fire_tick(p: Vector3i, age: int) -> void:
	var below := world.get_block_v(p + Vector3i(0, -1, 0))
	var eternal := below == Blocks.NETHERRACK
	if raining and not eternal and world.get_sky_light(p) >= 15:
		world.set_block(p.x, p.y, p.z, Blocks.AIR)
		return
	if not eternal and not _fire_can_stay(p):
		world.set_block(p.x, p.y, p.z, Blocks.AIR)
		return
	if age < 15:
		world.set_meta_at(p.x, p.y, p.z, mini(age + rng.randi_range(0, 2), 15), false)
	if not eternal and age > 3 and not _has_fuel(p) and rng.randi_range(0, 3) == 0:
		world.set_block(p.x, p.y, p.z, Blocks.AIR)
		return
	if not eternal and age >= 15 and rng.randi_range(0, 3) == 0:
		world.set_block(p.x, p.y, p.z, Blocks.AIR)
		return
	# Горение соседей и распространение.
	for d in 6:
		var q: Vector3i = p + Blocks.FACE_VEC[d]
		var b := world.get_block_v(q)
		var burn := Blocks.fire_burn[b]
		if burn > 0 and rng.randi_range(0, 300) < burn:
			if b == Blocks.TNT:
				ignite_tnt(q)
			elif rng.randi_range(0, age + 9) < 5:
				world.set_block(q.x, q.y, q.z, Blocks.FIRE, mini(age + 1, 15))
			else:
				world.set_block(q.x, q.y, q.z, Blocks.AIR)
	for k in 3:
		var q := p + Vector3i(rng.randi_range(-1, 1), rng.randi_range(-1, 3), rng.randi_range(-1, 1))
		if world.get_block_v(q) != Blocks.AIR:
			continue
		var chance := 0
		for d in 6:
			chance = maxi(chance, Blocks.fire_spread[world.get_block_v(q + Blocks.FACE_VEC[d])])
		if chance > 0 and rng.randi_range(0, 100) < chance:
			world.set_block(q.x, q.y, q.z, Blocks.FIRE, mini(age + 2, 15))


func _has_fuel(p: Vector3i) -> bool:
	for d in 6:
		if Blocks.fire_spread[world.get_block_v(p + Blocks.FACE_VEC[d])] > 0:
			return true
	return false


func _fire_can_stay(p: Vector3i) -> bool:
	return Blocks.is_opaque(world.get_block_v(p + Vector3i(0, -1, 0))) or _has_fuel(p)


## Поджигает клетку p (огниво, огненный шар). false — не получилось.
func place_fire(p: Vector3i) -> bool:
	var cur := world.get_block_v(p)
	if cur != Blocks.AIR and not (Blocks.is_replaceable(cur) and not Blocks.is_liquid(cur)):
		return false
	if not _fire_can_stay(p):
		return false
	if game != null and game.has_method("try_light_portal") and bool(game.call("try_light_portal", p)):
		return true
	world.set_block(p.x, p.y, p.z, Blocks.FIRE)
	return true


# --- Деревья и костная мука ------------------------------------------------

## Вырастить дерево из саженца в p. false — не хватает места.
func grow_tree(p: Vector3i, meta: int) -> bool:
	var kind := TreeGen.kind_for_sapling(meta, rng)
	var base := p
	var big_jungle := false
	if (meta & 3) == 3:
		# Огромное тропическое дерево из четырёх саженцев 2×2.
		for o: Vector3i in [Vector3i(0, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, -1)]:
			var c := p + o
			if _is_jungle_sapling(c) and _is_jungle_sapling(c + Vector3i(1, 0, 0)) and _is_jungle_sapling(c + Vector3i(0, 0, 1)) \
					and _is_jungle_sapling(c + Vector3i(1, 0, 1)):
				base = c
				big_jungle = true
				kind = TreeGen.HUGE_JUNGLE
				break
	var plan := TreeGen.plan(kind, rng)
	# Ствол должен поместиться.
	for e: Array in plan:
		if int(e[1]) != Blocks.LOG:
			continue
		var q: Vector3i = base + e[0]
		var b := world.get_block_v(q)
		if q.y >= WorldGen.CHUNK_HEIGHT or not (b == Blocks.AIR or b == Blocks.SAPLING or b == Blocks.LEAVES or Blocks.is_replaceable(b) and not Blocks.is_liquid(b)):
			return false
	if big_jungle:
		for o: Vector3i in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)]:
			world.set_block_v(base + o, Blocks.AIR, 0, false)
	else:
		world.set_block_v(p, Blocks.AIR, 0, false)
	for e: Array in plan:
		var q: Vector3i = base + e[0]
		var b := world.get_block_v(q)
		var only_air: bool = e[3]
		if only_air and b != Blocks.AIR and not (Blocks.is_replaceable(b) and not Blocks.is_liquid(b)):
			continue
		if not only_air and b != Blocks.AIR and b != Blocks.LEAVES and b != Blocks.SAPLING and not Blocks.is_replaceable(b):
			continue
		world.set_block(q.x, q.y, q.z, int(e[1]), int(e[2]), false)
	var ground := world.get_block_v(base + Vector3i(0, -1, 0))
	if ground == Blocks.GRASS:
		world.set_block(base.x, base.y - 1, base.z, Blocks.DIRT, 0, false)
	return true


func _is_jungle_sapling(p: Vector3i) -> bool:
	return world.get_block_v(p) == Blocks.SAPLING and world.get_meta_v(p) & 3 == 3


## Костная мука: мгновенный рост. true — подействовала.
func apply_bone_meal(p: Vector3i) -> bool:
	var id := world.get_block_v(p)
	var meta := world.get_meta_v(p)
	match id:
		Blocks.SAPLING:
			grow_tree(p, meta)
			return true
		Blocks.WHEAT:
			if meta >= 7:
				return false
			world.set_meta_at(p.x, p.y, p.z, 7)
			return true
		Blocks.PUMPKIN_STEM, Blocks.MELON_STEM:
			if meta >= 7:
				return false
			world.set_meta_at(p.x, p.y, p.z, 7)
			return true
		Blocks.BROWN_MUSHROOM, Blocks.RED_MUSHROOM:
			if rng.randf() < 0.4:
				var kind := TreeGen.HUGE_RED_MUSHROOM if id == Blocks.RED_MUSHROOM else TreeGen.HUGE_BROWN_MUSHROOM
				world.set_block_v(p, Blocks.AIR, 0, false)
				for e: Array in TreeGen.plan(kind, rng):
					var q: Vector3i = p + e[0]
					if world.get_block_v(q) == Blocks.AIR or not bool(e[3]):
						world.set_block(q.x, q.y, q.z, int(e[1]), int(e[2]), false)
			return true
		Blocks.GRASS:
			# Трава и цветы вокруг.
			for k in 64:
				var q := p + Vector3i(rng.randi_range(-3, 3), 1, rng.randi_range(-3, 3))
				if world.get_block_v(q) == Blocks.AIR and world.get_block_v(q + Vector3i(0, -1, 0)) == Blocks.GRASS:
					var r := rng.randi_range(0, 9)
					if r < 7:
						world.set_block(q.x, q.y, q.z, Blocks.TALLGRASS, 1)
					elif r < 9:
						world.set_block(q.x, q.y, q.z, Blocks.DANDELION)
					else:
						world.set_block(q.x, q.y, q.z, Blocks.ROSE)
			return true
	return false


# --- Динамит и взрывы ------------------------------------------------------

func ignite_tnt(p: Vector3i, fuse := 4.0) -> void:
	if world.get_block_v(p) != Blocks.TNT:
		return
	world.set_block(p.x, p.y, p.z, Blocks.AIR)
	var entities: Variant = game.get("entities") if game != null else null
	if entities != null and entities.has_method("spawn_primed_tnt"):
		entities.call("spawn_primed_tnt", Vector3(p) + Vector3(0.5, 0.0, 0.5), fuse)
	else:
		explode(Vector3(p) + Vector3(0.5, 0.5, 0.5), 4.0, false)


func explode(center: Vector3, power: float, fire: bool, source: Node = null) -> void:
	Explosion.explode(self, center, power, fire, source)
