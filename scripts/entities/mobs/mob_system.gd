class_name MobSystem
extends Node3D
## Мобы Minecraft 1.2: создание, обновление, естественное появление (монстры в темноте, животные
## на траве, спруты в воде; Нижний мир и Край — свои списки), рассадники, деревенские големы,
## дракон Края, исчезновение вдали от игрока, урон от снарядов и взрывов, прицел игрока,
## сохранение вместе с чанками. Подключается к EntityManager автоматически (setup(manager)).

## Пределы одновременно живых существ (снижены для однопоточной веб-сборки).
const HOSTILE_CAP := 24
const PASSIVE_CAP := 12
const WATER_CAP := 5
## Естественное появление прекращается при таком числе существ.
const MAX_NATURAL := 44
## Жёсткий предел (яйца призыва, рассадники).
const MAX_TOTAL := 150
const SPAWN_MIN_DIST := 24.0
const DESPAWN_FAR := 128.0
const DESPAWN_RANDOM := 32.0
const SPAWNER_RANGE := 16.0

var manager: EntityManager
var world: World
var mobs: Array[Mob] = []
var rng := RandomNumberGenerator.new()
## Сколько поисков пути разрешено в этом кадре (общий бюджет на всех существ).
var path_budget := 2
## Рассадники в загруженных чанках: ключ чанка → [позиции].
var spawners: Dictionary = {}
## Время последнего обновления (мкс) — для отладки производительности.
var last_update_usec := 0
## Отладка и сценарии скриншотов: выключить ИИ (существа только анимируются) и естественное появление.
var ai_enabled := true
var natural_spawning := true

var _spawn_timer := 0.0
var _passive_timer := 0.0
var _spawner_timer := 0.0
var _dragon_timer := 0.0
var _village_timer := 0.0
var _despawn_timer := 0.0


func setup(m: EntityManager) -> void:
	manager = m
	world = m.world
	name = "Mobs"
	rng.randomize()
	if world != null:
		world.chunk_loaded.connect(_on_chunk_loaded)
		for ch: Chunk in world.chunks.values():
			_scan_spawners(ch)


func difficulty() -> int:
	if manager == null or manager.game == null:
		return 2
	var d: Variant = manager.game.get("difficulty")
	return int(d) if d != null else 2


func player() -> Player:
	return manager.player if manager != null else null


# --- Кадр ----------------------------------------------------------------------

func update(delta: float) -> void:
	if world == null:
		return
	var t0 := Time.get_ticks_usec()
	path_budget = 2
	delta = minf(delta, 0.25)
	for m: Mob in mobs.duplicate():
		if not is_instance_valid(m) or m.removed:
			continue
		# В незагруженных чанках существа замирают.
		if not world.has_chunk_at(m.position.x, m.position.z):
			continue
		m.update_frame(delta)
	_cleanup()
	var p := player()
	if p != null:
		_spawn_timer += delta
		if _spawn_timer >= 1.0:
			_spawn_timer = 0.0
			if natural_spawning:
				_natural_spawn(p)
		_despawn_timer += delta
		if _despawn_timer >= 1.0:
			_despawn_timer = 0.0
			_despawn(p)
		_spawner_timer += delta
		if _spawner_timer >= 0.25:
			_tick_spawners(p, _spawner_timer)
			_spawner_timer = 0.0
		_dragon_timer += delta
		if _dragon_timer >= 2.0:
			_dragon_timer = 0.0
			_check_dragon(p)
		_village_timer += delta
		if _village_timer >= 10.0:
			_village_timer = 0.0
			_village_golems()
	last_update_usec = Time.get_ticks_usec() - t0


func _cleanup() -> void:
	var alive: Array[Mob] = []
	for m in mobs:
		if is_instance_valid(m) and not m.removed and not m.is_queued_for_deletion():
			alive.append(m)
	mobs = alive


# --- Создание --------------------------------------------------------------------

static func create_mob(type: int) -> Mob:
	match type:
		MobDefs.ZOMBIE:
			return HostileMobs.Zombie.new()
		MobDefs.GIANT:
			return HostileMobs.Giant.new()
		MobDefs.PIG_ZOMBIE:
			return HostileMobs.PigZombie.new()
		MobDefs.SKELETON:
			return HostileMobs.Skeleton.new()
		MobDefs.CREEPER:
			return HostileMobs.Creeper.new()
		MobDefs.SPIDER, MobDefs.CAVE_SPIDER:
			return HostileMobs.Spider.new()
		MobDefs.ENDERMAN:
			return HostileMobs.Enderman.new()
		MobDefs.SLIME, MobDefs.MAGMA_CUBE:
			return HostileMobs.Slime.new()
		MobDefs.SILVERFISH:
			return HostileMobs.Silverfish.new()
		MobDefs.GHAST:
			return HostileMobs.Ghast.new()
		MobDefs.BLAZE:
			return HostileMobs.Blaze.new()
		MobDefs.ENDER_DRAGON:
			return EnderDragon.new()
		MobDefs.END_CRYSTAL:
			return EnderDragon.EndCrystal.new()
		MobDefs.PIG:
			return PassiveMobs.Pig.new()
		MobDefs.SHEEP:
			return PassiveMobs.Sheep.new()
		MobDefs.COW:
			return PassiveMobs.Cow.new()
		MobDefs.MOOSHROOM:
			return PassiveMobs.Mooshroom.new()
		MobDefs.CHICKEN:
			return PassiveMobs.Chicken.new()
		MobDefs.SQUID:
			return PassiveMobs.Squid.new()
		MobDefs.WOLF:
			return PassiveMobs.Wolf.new()
		MobDefs.OCELOT:
			return PassiveMobs.Ocelot.new()
		MobDefs.VILLAGER:
			return PassiveMobs.Villager.new()
		MobDefs.IRON_GOLEM:
			return PassiveMobs.IronGolem.new()
		MobDefs.SNOW_GOLEM:
			return PassiveMobs.SnowGolem.new()
	return null


## Создать существо (яйцо призыва, раздатчик, голем из блоков, курица из яйца, чешуйница из камня).
func spawn(type: int, pos: Vector3, baby := false) -> Node3D:
	var m := _spawn(type, pos, baby)
	if m is PassiveMobs.IronGolem:
		# Голем, построенный игроком, никогда не нападает на игрока.
		(m as PassiveMobs.IronGolem).player_made = true
	return m


func _spawn(type: int, pos: Vector3, baby := false) -> Mob:
	if not MobDefs.exists(type) or mobs.size() >= MAX_TOTAL or world == null:
		return null
	var m := create_mob(type)
	if m == null:
		return null
	m.init_type(type, self, baby)
	m.position = pos
	add_child(m)
	mobs.append(m)
	return m


func remove_mob(m: Mob) -> void:
	if m == null or not is_instance_valid(m):
		return
	m.removed = true
	mobs.erase(m)
	m.queue_free()


# --- Запросы ---------------------------------------------------------------------

func mobs_near(pos: Vector3, r: float) -> Array[Mob]:
	var out: Array[Mob] = []
	var r2 := r * r
	for m in mobs:
		if is_instance_valid(m) and not m.is_dead() and m.position.distance_squared_to(pos) <= r2:
			out.append(m)
	return out


## Ближайшее живое существо одного из видов types (кроме exclude). adult_only — только взрослые.
func nearest_mob(pos: Vector3, r: float, types: Array, exclude: Node3D = null, adult_only := false) -> Mob:
	var best: Mob = null
	var bd := r * r
	for m in mobs:
		if m == exclude or not is_instance_valid(m) or m.is_dead() or not m.type in types:
			continue
		if adult_only and m.baby:
			continue
		var d := m.position.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = m
	return best


## Ближайший монстр (для големов).
func nearest_monster(pos: Vector3, r: float, exclude: Node3D = null) -> Mob:
	var best: Mob = null
	var bd := r * r
	for m in mobs:
		if m == exclude or not is_instance_valid(m) or m.is_dead():
			continue
		if MobDefs.category(m.type) != MobDefs.CAT_MONSTER:
			continue
		if m is HostileMobs.PigZombie and (m as HostileMobs.PigZombie).anger <= 0.0:
			continue
		var d := m.position.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = m
	return best


func in_radius(center: Vector3, r: float) -> Array:
	var out := []
	for m in mobs:
		if is_instance_valid(m) and not m.is_dead() and m.center().distance_to(center) <= r + m.half_w:
			out.append(m)
	return out


## Есть ли монстры рядом (проверка перед сном): 8 блоков по горизонтали, 5 по высоте.
func monsters_near(pos: Vector3, r: float) -> bool:
	for m in mobs:
		if not is_instance_valid(m) or m.is_dead() or not m.has_flag(MobDefs.F_MOB):
			continue
		var d := m.position - pos
		if absf(d.x) <= r and absf(d.z) <= r and absf(d.y) <= 5.0:
			return true
	return false


func count_category(cat: int) -> int:
	var n := 0
	for m in mobs:
		if is_instance_valid(m) and not m.is_dead() and MobDefs.category(m.type) == cat:
			n += 1
	return n


# --- Бой -----------------------------------------------------------------------------

## Снаряд на отрезке a→b: ближайшее существо (кроме стрелявшего) или null.
func segment_hit(a: Vector3, b: Vector3, shooter: Variant) -> Variant:
	var seg := b - a
	var len := seg.length()
	if len < 1e-6:
		return null
	var dir := seg / len
	var best: Mob = null
	var bt := INF
	var best_head := false
	for m in mobs:
		if not is_instance_valid(m) or m.is_dead() or m == shooter:
			continue
		if m.position.distance_to(a) > len + 12.0:
			continue
		var boxes := m.hit_boxes()
		for i in boxes.size():
			var r := World._ray_aabb(a, dir, boxes[i].grow(0.1))
			if r.size() == 2 and float(r[0]) <= len and float(r[0]) < bt:
				bt = float(r[0])
				best = m
				best_head = i == 1
	if best is EnderDragon:
		best.set("_hit_head", best_head)
	return best


## Урон от снаряда (стрела, снежок, огненный шар) или иного источника.
func damage(mob: Variant, amount: int, source: String, attacker: Variant, vel: Vector3) -> void:
	if not mob is Mob:
		return
	var m := mob as Mob
	var att := attacker as Node3D if attacker is Node3D else null
	var flat := Vector3(vel.x, 0, vel.z)
	var kb := Vector3.ZERO
	if flat.length_squared() > 0.01:
		kb = flat.normalized() * (4.0 if amount > 0 else 2.5)
	m.hurt(amount, source, att, kb)
	if source == "fire" and not m.has_flag(MobDefs.F_FIRE_IMMUNE):
		m.fire_time = maxf(m.fire_time, 5.0)
	if att != null and att == player():
		_owner_attacked(m)


## Существо или огненный шар под прицелом игрока.
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	if dir.length_squared() < 1e-8:
		return {}
	dir = dir.normalized()
	var best: Node3D = null
	var bt := max_dist
	var head := false
	for m in mobs:
		if not is_instance_valid(m) or m.is_dead():
			continue
		if m.position.distance_to(origin) > max_dist + 12.0:
			continue
		var boxes := m.hit_boxes()
		for i in boxes.size():
			var r := World._ray_aabb(origin, dir, boxes[i])
			if r.size() == 2 and float(r[0]) <= bt:
				bt = float(r[0])
				best = m
				head = i == 1
	# Огненные шары гастов можно отбить ударом.
	if manager != null:
		for n in manager.get_children():
			var pr := n as SimpleEntities.Projectile
			if pr == null or pr.is_queued_for_deletion() or not pr.type.ends_with("fireball"):
				continue
			var r := World._ray_aabb(origin, dir, AABB(pr.position - Vector3(0.6, 0.6, 0.6), Vector3(1.2, 1.2, 1.2)))
			if r.size() == 2 and float(r[0]) <= bt:
				bt = float(r[0])
				best = pr
	if best == null:
		return {}
	if best is EnderDragon:
		best.set("_hit_head", head)
	return {"entity": best, "dist": bt}


## Удар игрока (урон уже с учётом оружия и крита): отбрасывание от игрока, при беге — сильнее.
func player_attack(entity: Variant, dmg: int) -> void:
	var p := player()
	if entity is SimpleEntities.Projectile:
		_reflect(entity as SimpleEntities.Projectile)
		return
	if not entity is Mob or p == null:
		return
	var m := entity as Mob
	var dir := m.position - p.position
	dir.y = 0.0
	var kb := Vector3.ZERO
	if dir.length_squared() > 1e-4:
		kb = dir.normalized() * (6.0 + (4.0 if p.sprinting else 0.0))
	if not p.on_ground and p.velocity.y < 0.0:
		effect("crit", m.center())
	m.hurt(dmg, "player", p, kb)
	_owner_attacked(m)


func _reflect(pr: SimpleEntities.Projectile) -> void:
	var p := player()
	if p == null:
		return
	pr.velocity = p.look_dir() * maxf(pr.velocity.length(), 16.0)
	pr.shooter = p
	pr.from_player = true


## Правая кнопка по существу.
func interact(mob: Variant, p: Variant) -> bool:
	if not mob is Mob or not p is Player:
		return false
	var m := mob as Mob
	if m.is_dead():
		return false
	return m.interact(p as Player)


## Урон и отбрасывание от взрыва (формула как у игрока в EntityManager.explosion_damage).
func explosion(center: Vector3, power: float, source: Variant) -> void:
	var radius := power * 2.0
	var src := source as Node3D if source is Node3D else null
	for m: Mob in mobs.duplicate():
		if not is_instance_valid(m) or m.is_dead() or m == src:
			continue
		var c := m.center()
		var dist := c.distance_to(center)
		if dist >= radius + m.half_w:
			continue
		var impact := clampf(1.0 - dist / radius, 0.0, 1.0)
		var dmg := int((impact * impact + impact) / 2.0 * 8.0 * power + 1.0)
		var dir := (c - center).normalized() if dist > 0.01 else Vector3.UP
		m.hurt(dmg, "explosion", src, dir * impact * 12.0)
		if m.has_flag(MobDefs.F_FLYING):
			continue
		m.velocity.y += impact * 6.0


## Удар молнии: свинья → свинозомби, крипер → заряженный, остальным 5 урона и огонь.
func lightning(pos: Vector3) -> void:
	for m: Mob in mobs_near(pos, 3.0):
		if m is PassiveMobs.Pig:
			var z := _spawn(MobDefs.PIG_ZOMBIE, m.position)
			if z != null:
				z.yaw = m.yaw
			remove_mob(m)
		elif m is HostileMobs.Creeper:
			(m as HostileMobs.Creeper).set_charged(true)
		else:
			m.hurt(5, "lightning", null, Vector3.ZERO)
			if not m.has_flag(MobDefs.F_FIRE_IMMUNE):
				m.fire_time = maxf(m.fire_time, 8.0)


# --- Сигналы между существами ------------------------------------------------------

## Игрок ударил существо: прирученные волки нападают на него.
func _owner_attacked(victim: Mob) -> void:
	var p := player()
	if p == null or victim.is_dead():
		return
	for m in mobs_near(p.position, 16.0):
		if m is PassiveMobs.Wolf and m != victim:
			(m as PassiveMobs.Wolf).defend_owner(victim)


## Существо ранило игрока: прирученные волки защищают хозяина.
func player_attacked_by(attacker: Node3D) -> void:
	var p := player()
	if p == null or not attacker is Mob:
		return
	for m in mobs_near(p.position, 16.0):
		if m is PassiveMobs.Wolf:
			(m as PassiveMobs.Wolf).defend_owner(attacker)


## Удар по свинозомби злит всех свинозомби в радиусе 32 блоков.
func alert_pigmen(pos: Vector3, attacker: Node3D) -> void:
	for m in mobs_near(pos, 32.0):
		if m is HostileMobs.PigZombie:
			(m as HostileMobs.PigZombie).become_angry(attacker)


## Удар по дикому волку злит стаю.
func alert_wolves(pos: Vector3, attacker: Node3D) -> void:
	for m in mobs_near(pos, 16.0):
		var w := m as PassiveMobs.Wolf
		if w != null and not w.tamed:
			w.angry = rng.randf_range(20.0, 40.0)
			w.target = attacker


## Игрок напал на жителя: деревенские железные големы вступаются.
func village_alarm(pos: Vector3, attacker: Node3D) -> void:
	for m in mobs_near(pos, 24.0):
		var g := m as PassiveMobs.IronGolem
		if g != null and not g.player_made:
			g.angry_at_player = 60.0
			g.target = attacker


func crystal_destroyed(c: Mob) -> void:
	for m in mobs:
		if m is EnderDragon and is_instance_valid(m):
			(m as EnderDragon).crystal_destroyed(c)


func dragon_killed() -> void:
	var g := manager.game if manager != null else null
	if g == null:
		return
	g.set("dragon_killed", true)
	var meta: Variant = g.get("meta")
	if meta is Dictionary:
		(meta as Dictionary)["dragon_killed"] = true
	if g.has_method("show_toast"):
		g.call("show_toast", "Дракон Края повержен!", 4.0)


func _dragon_is_killed() -> bool:
	var g := manager.game if manager != null else null
	if g == null:
		return false
	if g.get("dragon_killed") == true:
		return true
	var meta: Variant = g.get("meta")
	return meta is Dictionary and bool((meta as Dictionary).get("dragon_killed", false))


# --- Звуки и частицы (необязательные обработчики игровой сцены) ---------------------

func sound(sound_name: String, pos: Vector3) -> void:
	if sound_name == "" or manager == null or manager.game == null:
		return
	if manager.game.has_method("play_sound"):
		manager.game.call("play_sound", sound_name, pos)


func effect(effect_kind: String, pos: Vector3, data := 0) -> void:
	if manager == null or manager.game == null:
		return
	if manager.game.has_method("effect"):
		manager.game.call("effect", effect_kind, pos, data)


# --- Естественное появление и исчезновение ----------------------------------------

func _natural_spawn(p: Player) -> void:
	if mobs.size() >= MAX_NATURAL or p.dead:
		return
	var diff := difficulty()
	if diff > 0:
		for i in 3:
			var room := HOSTILE_CAP - count_category(MobDefs.CAT_MONSTER)
			if room <= 0:
				break
			_try_spawn_pack(p, MobDefs.CAT_MONSTER, room)
	# Животные — раз в 20 секунд (как каждые 400 тиков в 1.2).
	_passive_timer += 1.0
	if _passive_timer >= 20.0:
		_passive_timer = 0.0
		for i in 4:
			var room := PASSIVE_CAP - count_category(MobDefs.CAT_CREATURE)
			if room <= 0:
				break
			_try_spawn_pack(p, MobDefs.CAT_CREATURE, room)
	var water_room := WATER_CAP - count_category(MobDefs.CAT_WATER)
	if water_room > 0:
		_try_spawn_pack(p, MobDefs.CAT_WATER, water_room)


func _try_spawn_pack(p: Player, cat: int, room := 4) -> int:
	var ang := rng.randf() * TAU
	var far := maxf(SPAWN_MIN_DIST + 8.0, float(world.render_distance * WorldGen.CHUNK_SIZE) - 8.0)
	var dist := rng.randf_range(SPAWN_MIN_DIST, far)
	var x := floori(p.position.x + cos(ang) * dist)
	var z := floori(p.position.z + sin(ang) * dist)
	if not world.has_chunk_at(x, z):
		return 0
	var top := world.height_at(x, z)
	var y := 0
	match cat:
		MobDefs.CAT_WATER:
			y = rng.randi_range(46, 62)
		MobDefs.CAT_CREATURE:
			y = top + 1
		_:
			y = rng.randi_range(1, maxi(top + 1, 2))
	var type := _pick_type(cat, x, y, z)
	if type < 0:
		return 0
	var group := 4
	match type:
		MobDefs.OCELOT:
			group = 2
		MobDefs.ENDERMAN, MobDefs.GHAST:
			group = 1 if world.dimension == 0 or type == MobDefs.GHAST else 4
		MobDefs.WOLF:
			group = 4
	var n := mini(rng.randi_range(1, group), room)
	var spawned := 0
	var c := Vector3i(x, y, z)
	for i in n * 3:
		if spawned >= n:
			break
		var q := c + Vector3i(rng.randi_range(-5, 5), 0, rng.randi_range(-5, 5))
		if cat != MobDefs.CAT_WATER:
			q = _settle(q)
		if q.y < 0 or not _can_spawn_at(type, q, p):
			continue
		var m := _spawn(type, Vector3(q.x + 0.5, q.y, q.z + 0.5))
		if m != null:
			m.yaw = rng.randf_range(-PI, PI)
			spawned += 1
	return spawned


## Опустить точку на опору (не дальше 6 блоков) — для группы существ на неровной земле.
func _settle(q: Vector3i) -> Vector3i:
	if Blocks.is_solid(world.get_block_v(q)):
		for k in 3:
			q.y += 1
			if not Blocks.is_solid(world.get_block_v(q)):
				return q
		return Vector3i(0, -1, 0)
	for k in 6:
		if Blocks.is_solid(world.get_block_v(q + Vector3i(0, -1, 0))):
			return q
		q.y -= 1
	return Vector3i(0, -1, 0)


func _pick_type(cat: int, x: int, y: int, z: int) -> int:
	var dim := world.dimension
	var biome := world.biome_at(x, z)
	var list: Array = []
	if dim == -1:
		if cat == MobDefs.CAT_MONSTER:
			list = [[MobDefs.GHAST, 10], [MobDefs.PIG_ZOMBIE, 10], [MobDefs.MAGMA_CUBE, 1]]
	elif dim == 1:
		if cat == MobDefs.CAT_MONSTER:
			list = [[MobDefs.ENDERMAN, 10]]
	else:
		var mushroom := biome == Biomes.MUSHROOM_ISLAND or biome == Biomes.MUSHROOM_SHORE
		match cat:
			MobDefs.CAT_MONSTER:
				if not mushroom:
					list = [[MobDefs.SPIDER, 10], [MobDefs.ZOMBIE, 10], [MobDefs.SKELETON, 10], [MobDefs.CREEPER, 10],
						[MobDefs.SLIME, 10], [MobDefs.ENDERMAN, 1]]
			MobDefs.CAT_CREATURE:
				if mushroom:
					list = [[MobDefs.MOOSHROOM, 8]]
				elif not biome in [Biomes.DESERT, Biomes.DESERT_HILLS, Biomes.OCEAN, Biomes.FROZEN_OCEAN, Biomes.BEACH,
						Biomes.RIVER, Biomes.FROZEN_RIVER, Biomes.HELL, Biomes.SKY]:
					list = [[MobDefs.SHEEP, 12], [MobDefs.PIG, 10], [MobDefs.CHICKEN, 10], [MobDefs.COW, 8]]
					if biome == Biomes.FOREST or biome == Biomes.FOREST_HILLS:
						list.append([MobDefs.WOLF, 5])
					elif biome == Biomes.TAIGA or biome == Biomes.TAIGA_HILLS:
						list.append([MobDefs.WOLF, 8])
					elif biome == Biomes.JUNGLE or biome == Biomes.JUNGLE_HILLS:
						list.append([MobDefs.OCELOT, 2])
			MobDefs.CAT_WATER:
				list = [[MobDefs.SQUID, 10]]
	if list.is_empty():
		return -1
	var total := 0
	for e: Array in list:
		total += int(e[1])
	var r := rng.randi_range(0, total - 1)
	for e: Array in list:
		r -= int(e[1])
		if r < 0:
			return int(e[0])
	return -1


## Можно ли существу появиться в клетке c (правила 1.2, упрощённо).
func _can_spawn_at(type: int, c: Vector3i, p: Player) -> bool:
	if not world.is_loaded(c) or c.y < 1 or c.y > 250:
		return false
	var pos := Vector3(c.x + 0.5, c.y, c.z + 0.5)
	if pos.distance_to(p.position) < SPAWN_MIN_DIST:
		return false
	var info := MobDefs.info(type)
	var hw: float = info[2]
	var h: float = info[3]
	var here := world.get_block_v(c)
	var below := world.get_block_v(c + Vector3i(0, -1, 0))
	match MobDefs.category(type):
		MobDefs.CAT_WATER:
			if not Blocks.is_water(here) or Blocks.is_opaque(world.get_block_v(c + Vector3i(0, 1, 0))):
				return false
			return c.y > 45 and c.y < 63
		MobDefs.CAT_CREATURE:
			var ground := Blocks.MYCELIUM if type == MobDefs.MOOSHROOM else Blocks.GRASS
			if type == MobDefs.OCELOT:
				if not (below == Blocks.GRASS or below == Blocks.LEAVES) or c.y < 63 or rng.randi_range(0, 2) == 0:
					return false
			elif below != ground:
				return false
			if maxi(world.get_sky_light(c), world.get_block_light(c)) <= 8:
				return false
		_:
			if not Blocks.is_opaque(below) or below == Blocks.BEDROCK:
				return false
			if Blocks.is_liquid(here):
				return false
			if not _monster_rules(type, c):
				return false
	if Blocks.is_liquid(here) and MobDefs.category(type) != MobDefs.CAT_WATER:
		return false
	return not BodyPhysics.collides(world, pos, hw, h)


func _monster_rules(type: int, c: Vector3i) -> bool:
	match type:
		MobDefs.PIG_ZOMBIE, MobDefs.MAGMA_CUBE:
			return true
		MobDefs.GHAST:
			return rng.randi_range(0, 19) == 0
		MobDefs.SLIME:
			if c.y < 40 and is_slime_chunk(c.x >> 4, c.z >> 4):
				return true
			# Болото (упрощение): ночью в темноте.
			var biome := world.biome_at(c.x, c.z)
			return biome == Biomes.SWAMPLAND and c.y > 50 and c.y < 70 and _monster_light_ok(c)
	return _monster_light_ok(c)


## Освещённость для монстров (1.2): небо ярче случайного 0–31 — нельзя; итоговый свет ≤ случайного 0–7.
func _monster_light_ok(c: Vector3i) -> bool:
	var sky := world.get_sky_light(c)
	if sky > rng.randi_range(0, 31):
		return false
	var level := 15
	if manager != null and manager.game != null and manager.game.has_method("sky_light_level"):
		level = int(manager.game.call("sky_light_level"))
	var sky_now := maxi(0, sky - (15 - level))
	var l := maxi(sky_now, world.get_block_light(c))
	return l <= rng.randi_range(0, 7)


## «Чанк слизней» — каждый десятый, по зерну мира.
func is_slime_chunk(cx: int, cz: int) -> bool:
	var r := RandomNumberGenerator.new()
	r.seed = hash([world.seed_value, cx * cx * 4987142 + cx * 5947611, cz * cz * 4392871 + cz * 389711, 987234911])
	return r.randi_range(0, 9) == 0


func _despawn(p: Player) -> void:
	var peaceful := difficulty() == 0
	for m: Mob in mobs.duplicate():
		if not is_instance_valid(m) or m.is_dead():
			continue
		var cat := MobDefs.category(m.type)
		if peaceful and cat == MobDefs.CAT_MONSTER and m.type != MobDefs.ENDER_DRAGON:
			remove_mob(m)
			continue
		if not can_despawn(m):
			continue
		var d := m.position.distance_to(p.position)
		if d > DESPAWN_FAR:
			remove_mob(m)
		elif d > DESPAWN_RANDOM and m.age > 30.0 and rng.randi_range(0, 39) == 0:
			remove_mob(m)


## Исчезают монстры, спруты и злые дикие волки (животные, жители, големы, питомцы — нет).
func can_despawn(m: Mob) -> bool:
	if m.persistent and not (m is PassiveMobs.Wolf and (m as PassiveMobs.Wolf).angry > 0.0 and not (m as PassiveMobs.Wolf).tamed):
		return false
	var cat := MobDefs.category(m.type)
	return cat == MobDefs.CAT_MONSTER or cat == MobDefs.CAT_WATER or m is PassiveMobs.Wolf


# --- Рассадники ------------------------------------------------------------------------

func _on_chunk_loaded(ch: Chunk) -> void:
	_scan_spawners(ch)


func _scan_spawners(ch: Chunk) -> void:
	var list: Array[Vector3i] = []
	for i: int in ch.block_entities:
		var be: Variant = ch.block_entities[i]
		if not be is Dictionary or not (be as Dictionary).has("mob"):
			continue
		if ch.blocks.is_empty() or ch.blocks[i] != Blocks.SPAWNER:
			continue
		var lp := Chunk.local_pos(i)
		list.append(Vector3i(ch.key.x * WorldGen.CHUNK_SIZE + lp.x, lp.y, ch.key.y * WorldGen.CHUNK_SIZE + lp.z))
	if list.is_empty():
		spawners.erase(ch.key)
	else:
		spawners[ch.key] = list


## Рассадник: игрок ближе 16 блоков — каждые 10–40 с до 4 существ рядом, не больше 6 вокруг.
func _tick_spawners(p: Player, dt: float) -> void:
	var pk := World.key_of(p.position)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var key := pk + Vector2i(dx, dz)
			var ch: Chunk = world.chunks.get(key)
			if ch == null:
				continue
			# Новые рассадники (поставленные в творческом режиме, сгенерированные позже) — пересканировать изредка.
			if rng.randi_range(0, 79) == 0:
				_scan_spawners(ch)
			if not spawners.has(key):
				continue
			for pos: Vector3i in spawners[key]:
				if Vector3(pos).distance_to(p.position) > SPAWNER_RANGE:
					continue
				if world.get_block_v(pos) != Blocks.SPAWNER:
					continue
				var be := world.get_block_entity(pos, false)
				if be.is_empty() or not be.has("mob"):
					continue
				var delay := float(be.get("delay", 1.0))
				delay -= dt
				if delay <= 0.0:
					# Неудачная попытка (нет места или светло) — повтор вскоре, как в оригинале.
					if _spawner_spawn(pos, int(be["mob"]), p) > 0:
						delay = rng.randf_range(10.0, 40.0)
					else:
						delay = 0.5
					world.mark_dirty(pos)
				be["delay"] = delay


func _spawner_spawn(pos: Vector3i, type: int, p: Player) -> int:
	if not MobDefs.exists(type) or type == MobDefs.ENDER_DRAGON:
		return 0
	if MobDefs.category(type) == MobDefs.CAT_MONSTER and difficulty() == 0:
		return 0
	var center := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	var made := 0
	for i in 4:
		if _count_near(type, center) >= 6:
			break
		var q := Vector3(pos.x + 0.5 + (rng.randf() - rng.randf()) * 4.0, pos.y + rng.randi_range(-1, 1),
			pos.z + 0.5 + (rng.randf() - rng.randf()) * 4.0)
		var info := MobDefs.info(type)
		if BodyPhysics.collides(world, q, float(info[2]), float(info[3])):
			continue
		var cell := Vector3i(floori(q.x), floori(q.y), floori(q.z))
		if Blocks.is_liquid(world.get_block_v(cell)):
			continue
		if MobDefs.category(type) == MobDefs.CAT_MONSTER and type != MobDefs.BLAZE and type != MobDefs.PIG_ZOMBIE \
				and type != MobDefs.MAGMA_CUBE and not _monster_light_ok_spawner(cell):
			continue
		var m := _spawn(type, q)
		if m != null:
			m.yaw = rng.randf_range(-PI, PI)
			effect("smoke", q + Vector3(0, 0.5, 0))
			made += 1
	if p == null:
		return made
	return made


func _count_near(type: int, center: Vector3) -> int:
	var near := 0
	for m in mobs:
		if is_instance_valid(m) and not m.is_dead() and m.type == type:
			var d := m.position - center
			if absf(d.x) <= 8.5 and absf(d.y) <= 4.5 and absf(d.z) <= 8.5:
				near += 1
	return near


## Для рассадника: только итоговый свет ≤ 7 (подземелья тёмные).
func _monster_light_ok_spawner(c: Vector3i) -> bool:
	var level := 15
	if manager != null and manager.game != null and manager.game.has_method("sky_light_level"):
		level = int(manager.game.call("sky_light_level"))
	var sky_now := maxi(0, world.get_sky_light(c) - (15 - level))
	return maxi(sky_now, world.get_block_light(c)) <= rng.randi_range(0, 7) + 1


# --- Деревни: железные големы и рождение жителей ------------------------------------------

## Число деревянных дверей (по 2 блока) в квадрате чанков вокруг точки — быстро, по данным чанков.
func doors_near(pos: Vector3, chunk_r := 2) -> int:
	var k := World.key_of(pos)
	var blocks := 0
	for dz in range(-chunk_r, chunk_r + 1):
		for dx in range(-chunk_r, chunk_r + 1):
			var ch: Chunk = world.chunks.get(k + Vector2i(dx, dz))
			if ch != null:
				blocks += ch.blocks.count(Blocks.WOODEN_DOOR)
	return blocks >> 1


## 1.2: в деревне с 10+ жителями и 21+ дверью иногда появляется железный голем.
func _village_golems() -> void:
	var villagers: Array[Mob] = []
	for m in mobs:
		if m is PassiveMobs.Villager and not m.is_dead():
			villagers.append(m)
	if villagers.size() < 10:
		return
	var v: Mob = villagers[rng.randi_range(0, villagers.size() - 1)]
	var count := 0
	for m in villagers:
		if m.position.distance_to(v.position) < 32.0:
			count += 1
	var golems := 0
	for m in mobs_near(v.position, 48.0):
		if m is PassiveMobs.IronGolem:
			golems += 1
	if count < 10 or golems >= count / 10.0 or doors_near(v.position) <= 20:
		return
	if rng.randi_range(0, 34) != 0:
		return
	for i in 10:
		var c := Vector3i(floori(v.position.x) + rng.randi_range(-8, 8), floori(v.position.y) + 3, floori(v.position.z) + rng.randi_range(-8, 8))
		c = _settle(c)
		if c.y < 0:
			continue
		var pos := Vector3(c.x + 0.5, c.y, c.z + 0.5)
		if not BodyPhysics.collides(world, pos, 0.7, 2.9):
			_spawn(MobDefs.IRON_GOLEM, pos)
			return


## Рождение жителя (1.2): если жителей меньше 35% от числа дверей и рядом есть второй взрослый.
func villager_mate(v: Mob) -> void:
	var count := 0
	var partner: Mob = null
	for m in mobs_near(v.position, 32.0):
		if m is PassiveMobs.Villager:
			count += 1
			if m != v and not m.baby and m.position.distance_to(v.position) < 8.0:
				partner = m
	if partner == null or float(count) >= doors_near(v.position) * 0.35:
		return
	var b := _spawn(MobDefs.VILLAGER, (v.position + partner.position) * 0.5, true)
	if b != null:
		effect("hearts", b.center())


# --- Дракон Края -----------------------------------------------------------------------

func _check_dragon(p: Player) -> void:
	if world.dimension != 1 or _dragon_is_killed() or p.dead:
		return
	for m in mobs:
		if m is EnderDragon and is_instance_valid(m):
			return
	if not world.has_chunk_at(0, 0):
		return
	var top := world.top_solid_y(0, 0)
	var island := float(top) if top > 0 else 64.0
	var d := _spawn(MobDefs.ENDER_DRAGON, Vector3(0.5, island + 30.0, 0.5))
	if d != null:
		(d as EnderDragon).island_y = island


# --- Сохранение -------------------------------------------------------------------------

## Выгрузка чанка: существа сохраняются в чанк; монстры вдали «исчезают» (как в оригинале).
func unload_chunk(key: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Mob in mobs.duplicate():
		if not is_instance_valid(m) or World.key_of(m.position) != key:
			continue
		if not m.is_dead() and not can_despawn(m):
			var d := m.to_dict()
			if not d.is_empty():
				out.append(d)
		if m is EnderDragon:
			continue
		remove_mob(m)
	spawners.erase(key)
	return out


## Все сохраняемые существа по чанкам (без удаления).
func save_by_chunk() -> Dictionary:
	var out := {}
	for m in mobs:
		if not is_instance_valid(m) or m.is_dead():
			continue
		var d := m.to_dict()
		if d.is_empty():
			continue
		var key := World.key_of(m.position)
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(d)
	return out


## Восстановление из словаря {"kind": "mob", "type": id, "pos": [x, y, z], ...}.
func restore(d: Dictionary) -> Node3D:
	var type := int(d.get("type", -1))
	var p: Variant = d.get("pos", [])
	if not MobDefs.exists(type) or not p is Array or (p as Array).size() != 3:
		return null
	if type == MobDefs.ENDER_DRAGON:
		return null
	var pa := p as Array
	var pos := Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
	var baby := bool(d.get("baby", false)) or float(d.get("grow", 0.0)) > 0.0
	var m := _spawn(type, pos, baby)
	if m == null:
		return null
	m.from_dict(d)
	return m
