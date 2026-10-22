class_name EntityManager
extends Node3D
## Все существа и объекты вне сетки блоков: выпавшие предметы, опыт, падающие блоки, динамит,
## снаряды и мобы (через MobSystem). Обновляет их, сохраняет вместе с чанками.

const PICKUP_RADIUS := 2.2
const MOB_SYSTEM_PATH := "res://scripts/entities/mobs/mob_system.gd"

var world: World
var logic: BlockLogic
var player: Player
var game: Node
## Мобы: объект MobSystem (если есть в проекте).
var mobs: Object
var rng := RandomNumberGenerator.new()


func setup(p_world: World, p_logic: BlockLogic, p_player: Player, p_game: Node) -> void:
	world = p_world
	logic = p_logic
	player = p_player
	game = p_game
	rng.randomize()
	if ResourceLoader.exists(MOB_SYSTEM_PATH):
		var script: Script = load(MOB_SYSTEM_PATH)
		mobs = script.new()
		if mobs is Node:
			add_child(mobs)
		mobs.call("setup", self)
	world.chunk_unloading.connect(_on_chunk_unloading)
	world.chunk_loaded.connect(_on_chunk_loaded)


func update(delta: float) -> void:
	for n in get_children():
		if n.has_method("update_entity") and not n.is_queued_for_deletion():
			n.call("update_entity", delta)
	if mobs != null:
		mobs.call("update", delta)
	_pickup(delta)


# --- Создание --------------------------------------------------------------

func spawn_drop(id: int, count: int, data: int, pos: Vector3, vel := Vector3.INF, pickup_delay := 0.0) -> ItemDrop:
	if id <= 0 or count <= 0:
		return null
	if vel == Vector3.INF:
		vel = Vector3(rng.randf_range(-1.2, 1.2), 3.0, rng.randf_range(-1.2, 1.2))
	# Объединение с такой же стопкой рядом.
	for n in get_children():
		var d := n as ItemDrop
		if d == null or d.is_queued_for_deletion() or d.position.distance_to(pos) > 1.0:
			continue
		if Inventory.stacks_with(d.item_id, d.data, id, data) and d.count + count <= Items.max_stack(id):
			d.count += count
			return d
	var drop := ItemDrop.new()
	drop.setup(world, id, count, data, pos, vel)
	drop.age = -pickup_delay
	add_child(drop)
	return drop


func spawn_xp(pos: Vector3, amount: int) -> void:
	# Крупные порции делятся на несколько шариков, как в оригинале.
	while amount > 0:
		var part := 1
		for v: int in [2477, 1237, 617, 307, 149, 73, 37, 17, 7, 3]:
			if amount >= v:
				part = v
				break
		amount -= part
		var orb := SimpleEntities.XpOrb.new()
		orb.world = world
		orb.amount = part
		orb.position = pos
		orb.velocity = Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(2.0, 4.0), rng.randf_range(-1.5, 1.5))
		add_child(orb)


func spawn_falling_block(id: int, meta: int, pos: Vector3) -> Node3D:
	var f := SimpleEntities.FallingBlock.new()
	f.world = world
	f.logic = logic
	f.block_id = id
	f.meta = meta
	f.position = pos
	add_child(f)
	return f


func spawn_primed_tnt(pos: Vector3, fuse := 4.0) -> Node3D:
	var t := SimpleEntities.PrimedTnt.new()
	t.world = world
	t.logic = logic
	t.fuse = fuse
	t.position = pos
	t.velocity = Vector3(rng.randf_range(-0.5, 0.5), 2.0, rng.randf_range(-0.5, 0.5))
	add_child(t)
	return t


## type: arrow, snowball, egg, ender_pearl, xp_bottle, potion, fireball, small_fireball.
func spawn_projectile(type: String, pos: Vector3, vel: Vector3, shooter: Node3D = null, damage := 2.0, data := 0) -> Node3D:
	var p := SimpleEntities.Projectile.new()
	p.type = type
	p.world = world
	p.manager = self
	p.shooter = shooter
	p.velocity = vel
	p.damage = damage
	p.data = data
	p.from_player = shooter == player
	p.position = pos
	add_child(p)
	return p


# --- Снаряды ---------------------------------------------------------------

## Кого задевает снаряд на отрезке a→b: моба или игрока (не стрелявшего).
func projectile_hit_test(proj: Node3D, a: Vector3, b: Vector3) -> Variant:
	var shooter: Node3D = proj.get("shooter")
	var seg := b - a
	if player != null and shooter != player and not player.dead and proj.get("age") > 0.0:
		if _segment_hits(player.body_box(), a, seg):
			return player
	if mobs != null:
		var m: Variant = mobs.call("segment_hit", a, b, shooter)
		if m != null:
			return m
	return null


static func _segment_hits(box: AABB, a: Vector3, seg: Vector3) -> bool:
	var len := seg.length()
	if len < 1e-6:
		return box.has_point(a)
	var r := World._ray_aabb(a, seg / len, box.grow(0.1))
	return r.size() == 2 and float(r[0]) <= len


func projectile_hit(proj: Node3D, who: Variant) -> void:
	var type: String = proj.get("type")
	var vel: Vector3 = proj.get("velocity")
	match type:
		"arrow":
			var dmg := int(ceil(float(proj.get("damage")) * clampf(vel.length() / 50.0, 0.2, 1.2)))
			_damage_target(who, maxi(dmg, 1), "arrow", proj.get("shooter"), vel)
			# Зачарования лука: откидывание и горящие стрелы.
			var target := who as Node3D
			if target != null:
				var punch := int(proj.get_meta("punch", 0))
				if punch > 0 and target.get("velocity") is Vector3:
					var dir := Vector3(vel.x, 0.0, vel.z).normalized()
					target.set("velocity", (target.get("velocity") as Vector3) + dir * 6.0 * punch + Vector3(0, 1.5, 0))
				if bool(proj.get_meta("flame", false)):
					for prop: String in ["fire_time", "fire"]:
						if target.get(prop) is float:
							target.set(prop, maxf(float(target.get(prop)), 5.0))
							break
			_fx_sound("arrow_hit", proj.position, 0.6)
			proj.queue_free()
		"snowball", "egg":
			_damage_target(who, 0, "arrow", proj.get("shooter"), vel)
			_impact(proj, proj.position)
		"fireball", "small_fireball":
			_damage_target(who, 5 if type == "small_fireball" else 6, "fire", proj.get("shooter"), vel)
			_impact(proj, proj.position)
		_:
			_impact(proj, proj.position)


func projectile_block_hit(proj: Node3D, hit: Dictionary) -> void:
	var type: String = proj.get("type")
	if type == "arrow":
		proj.set("stuck", true)
		_fx_sound("arrow_hit", proj.position, 0.5)
		return
	_impact(proj, hit["hit"])


func _impact(proj: Node3D, at: Vector3) -> void:
	var type: String = proj.get("type")
	match type:
		"egg":
			if rng.randi_range(0, 7) == 0 and mobs != null:
				mobs.call("spawn", 93, at, true)
		"ender_pearl":
			_fx("portal", at)
			if proj.get("shooter") == player and player != null:
				player.position = at + Vector3(0, 0.2, 0)
				player.velocity = Vector3.ZERO
				player.take_damage(5, "fall")
		"xp_bottle":
			spawn_xp(at, 3 + rng.randi_range(0, 4) + rng.randi_range(0, 4))
		"potion":
			_fx_sound("glass_break", at, 0.6)
			_fx("potion", at, Potions.color_of(int(proj.get("data"))).to_rgba32() >> 8)
			_splash_potion(at, int(proj.get("data")))
		"fireball":
			if logic != null:
				logic.explode(at, 1.0, true, proj.get("shooter"))
		"small_fireball":
			if logic != null:
				var cell := Vector3i(floori(at.x), floori(at.y), floori(at.z))
				logic.place_fire(cell)
	proj.queue_free()


func _fx(kind: String, at: Vector3, data := 0) -> void:
	if game != null and game.has_method("effect"):
		game.call("effect", kind, at, data)


func _fx_sound(sound_name: String, at: Vector3, vol := 1.0) -> void:
	if game != null and game.has_method("play_sound"):
		game.call("play_sound", sound_name, at, vol)


func _splash_potion(at: Vector3, data: int) -> void:
	var eff := Potions.effect_of(data)
	if eff.is_empty():
		return
	var targets := []
	if player != null and player.position.distance_to(at) < 4.0:
		targets.append(player)
	if mobs != null:
		targets.append_array(mobs.call("in_radius", at, 4.0))
	for t: Object in targets:
		if t.has_method("add_effect"):
			t.call("add_effect", int(eff[0]), int(eff[1]), float(eff[2]))


func _damage_target(who: Variant, amount: int, source: String, attacker: Variant, vel: Vector3) -> void:
	if who == player:
		player.take_damage(amount, source, attacker as Node3D)
	elif who != null and mobs != null:
		mobs.call("damage", who, amount, source, attacker, vel)


# --- Мобы (делегирование) --------------------------------------------------

## Существо под прицелом: {entity, dist} или {}.
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	if mobs == null:
		return {}
	return mobs.call("raycast", origin, dir, max_dist)


func attack(entity: Variant, damage: int) -> void:
	if mobs != null:
		mobs.call("player_attack", entity, damage)


func interact(entity: Variant) -> bool:
	if mobs == null:
		return false
	return bool(mobs.call("interact", entity, player))


func spawn_mob(type: int, pos: Vector3) -> Node3D:
	if mobs == null:
		return null
	return mobs.call("spawn", type, pos, false)


## Урон и отбрасывание от взрыва игроку и существам.
func explosion_damage(center: Vector3, power: float, source: Node) -> void:
	var radius := power * 2.0
	if player != null and not player.dead:
		var c := player.position + Vector3(0, 0.9, 0)
		var dist := c.distance_to(center)
		if dist < radius:
			var impact := 1.0 - dist / radius
			var dmg := int((impact * impact + impact) / 2.0 * 8.0 * power + 1.0)
			player.take_damage(dmg, "explosion", source as Node3D)
			player.velocity += (c - center).normalized() * impact * 12.0
	if mobs != null:
		mobs.call("explosion", center, power, source)
	for n in get_children():
		var d := n as ItemDrop
		if d != null and d.position.distance_to(center) < radius * 0.5:
			d.queue_free()


# --- Подбор предметов и опыта ----------------------------------------------

func _pickup(delta: float) -> void:
	if player == null or player.dead:
		return
	var center := player.position + Vector3(0, 0.8, 0)
	for n in get_children():
		if n.is_queued_for_deletion():
			continue
		if n is ItemDrop:
			var d := n as ItemDrop
			if not d.can_pickup():
				continue
			var dist := d.position.distance_to(center)
			if dist < 0.9:
				var left := player.inventory.add_item(d.item_id, d.count, d.data)
				if game != null and game.has_method("on_item_picked"):
					game.call("on_item_picked", d.item_id, d.count - left)
				if left == 0:
					d.queue_free()
				else:
					d.count = left
			elif dist < PICKUP_RADIUS:
				d.position = d.position.move_toward(center, delta * 7.0)
				d.velocity = Vector3.ZERO
		elif n is SimpleEntities.XpOrb:
			var orb := n as SimpleEntities.XpOrb
			var dist := orb.position.distance_to(center)
			if dist < 0.7 and orb.age > 0.3:
				player.add_xp(orb.amount)
				orb.queue_free()
			elif dist < 6.0 and orb.age > 0.3:
				orb.attract(center, delta)


# --- Сохранение вместе с чанками -------------------------------------------

func _in_chunk(n: Node3D, key: Vector2i) -> bool:
	return World.key_of(n.position) == key


func _on_chunk_unloading(ch: Chunk) -> void:
	var saved := []
	for n in get_children():
		var e := n as Node3D
		if e == null or e.is_queued_for_deletion() or not e.has_method("to_dict") or not _in_chunk(e, ch.key):
			continue
		var d: Dictionary = e.call("to_dict")
		if not d.is_empty():
			saved.append(d)
		e.queue_free()
	if mobs != null:
		saved.append_array(mobs.call("unload_chunk", ch.key))
	if not saved.is_empty() or not ch.entities.is_empty():
		ch.entities = saved
		ch.dirty = true
		ch.modified = true


func _on_chunk_loaded(ch: Chunk) -> void:
	if ch.entities.is_empty():
		return
	var list := ch.entities
	ch.entities = []
	for d: Variant in list:
		if d is Dictionary:
			restore(d)


## Восстановление сущности из словаря to_dict().
func restore(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0, 0, 0])
	if p.size() != 3:
		return
	var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
	match str(d.get("kind", "")):
		"item":
			var id := int(d.get("id", 0))
			if Items.exists(id):
				spawn_drop(id, int(d.get("count", 1)), int(d.get("data", 0)), pos, Vector3.ZERO)
		"xp":
			spawn_xp(pos, int(d.get("amount", 1)))
		"falling":
			spawn_falling_block(int(d.get("id", Blocks.SAND)), int(d.get("meta", 0)), pos)
		"tnt":
			spawn_primed_tnt(pos, float(d.get("fuse", 4.0)))
		"arrow":
			var a := spawn_projectile("arrow", pos, Vector3.ZERO)
			a.set("stuck", true)
		"mob":
			if mobs != null:
				mobs.call("restore", d)


## Все сохраняемые сущности (для сохранения игры без выгрузки чанков).
func save_into_chunks() -> void:
	var by_chunk: Dictionary = {}
	for n in get_children():
		var e := n as Node3D
		if e == null or e.is_queued_for_deletion() or not e.has_method("to_dict"):
			continue
		var d: Dictionary = e.call("to_dict")
		if d.is_empty():
			continue
		var key := World.key_of(e.position)
		if not by_chunk.has(key):
			by_chunk[key] = []
		(by_chunk[key] as Array).append(d)
	if mobs != null:
		var mob_data: Dictionary = mobs.call("save_by_chunk")
		for key: Vector2i in mob_data:
			if not by_chunk.has(key):
				by_chunk[key] = []
			(by_chunk[key] as Array).append_array(mob_data[key])
	for key: Vector2i in world.chunks:
		var ch: Chunk = world.chunks[key]
		var list: Array = by_chunk.get(key, [])
		if list.is_empty() and ch.entities.is_empty():
			continue
		ch.entities = list
		ch.dirty = true
		ch.modified = true


## После сохранения сущности остаются в мире, а не в данных чанка.
func clear_saved_lists() -> void:
	for ch: Chunk in world.chunks.values():
		ch.entities = []
