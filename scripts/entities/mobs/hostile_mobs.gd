class_name HostileMobs
extends RefCounted
## Монстры 1.2: зомби, зомби-свиночеловек, скелет, крипер, паук и пещерный паук, эндермен,
## слизень и магмовый куб, чешуйница, гаст, ифрит, гигант.


## Общий монстр: ищет игрока поблизости, преследует и бьёт; в ответ на удар нападает на обидчика.
class Monster extends Mob:
	var follow_range := 16.0
	var _retarget := 0.0

	func ai_tick() -> void:
		_retarget -= TICK
		if _retarget <= 0.0:
			_retarget = rng.randf_range(0.4, 0.6)
			if not target_valid(target) or dist_to(target) > follow_range * 2.0:
				target = find_target()
		if target_valid(target):
			chase()
		else:
			target = null
			wander(speed * 0.6)

	func find_target() -> Node3D:
		return hostile_player_near(follow_range)

	func chase() -> void:
		look_at_point(target_center(target))
		move_to(target.position, speed)
		melee(target, attack_damage)

	func on_attacked_by(attacker: Node3D) -> void:
		if attacker is Player or (attacker is Mob and (attacker as Mob).type != type):
			if target_valid(attacker):
				target = attacker


## Зомби: нападает на игрока и жителей, горит на солнце, на сложном уровне выбивает двери.
class Zombie extends Monster:
	var _door_time := 0.0
	var _door := Vector3i(0, -1000, 0)

	func _setup() -> void:
		follow_range = 24.0

	func model_key() -> String:
		return "biped"

	func skin_keys() -> Array:
		return ["zombie"]

	func ambient_sound() -> String:
		return "zombie"

	func armor() -> int:
		return 2

	func find_target() -> Node3D:
		var p := hostile_player_near(follow_range)
		if p != null:
			return p
		return system.call("nearest_mob", position, 16.0, [MobDefs.VILLAGER], self)

	func chase() -> void:
		super.chase()
		_try_break_door()

	## Сложный уровень: удары по деревянной двери на пути — через 12 с дверь выбита.
	func _try_break_door() -> void:
		if difficulty() < 3 or not hit_wall:
			_door_time = 0.0
			return
		var f := facing()
		var c := Vector3i(floori(position.x + f.x * 0.8), floori(position.y + 0.1), floori(position.z + f.z * 0.8))
		if world.get_block_v(c) != Blocks.WOODEN_DOOR:
			_door_time = 0.0
			return
		if c != _door:
			_door = c
			_door_time = 0.0
		_door_time += TICK
		if ticks % 20 == 0:
			swing = 1.0
		if _door_time >= 12.0:
			var lower := c if world.get_meta_v(c) & 8 == 0 else c - Vector3i(0, 1, 0)
			world.set_block(lower.x, lower.y + 1, lower.z, Blocks.AIR)
			world.set_block(lower.x, lower.y, lower.z, Blocks.AIR)
			_door_time = 0.0

	func drop_loot(by_player: bool, _source: String) -> void:
		loot(Items.ROTTEN_FLESH, rng.randi_range(0, 2))
		if by_player and rare_drop():
			drop([Items.IRON_INGOT, Items.IRON_SWORD, Items.IRON_HELMET, Items.IRON_SHOVEL][rng.randi_range(0, 3)], 1)

	func pose(ph: float, amt: float, hy: float, hp: float, t: float) -> void:
		super.pose(ph, amt, hy, hp, t)
		var bob := sin(t * 1.5) * 0.05
		var hit := -sin(swing * PI) * 0.6
		model.rot("rarm", Vector3(-PI / 2.0 + bob + hit, -0.1, 0.05))
		model.rot("larm", Vector3(-PI / 2.0 - bob + hit, 0.1, -0.05))


## Гигант (только яйцом/командой): огромный зомби.
class Giant extends Zombie:
	func model_key() -> String:
		return "giant"

	func _setup() -> void:
		follow_range = 32.0

	func drop_loot(_by_player: bool, _source: String) -> void:
		drop(Items.ROTTEN_FLESH, rng.randi_range(5, 10))


## Зомби-свиночеловек: нейтрален, пока его (или собратьев рядом) не ударят; с золотым мечом.
class PigZombie extends Zombie:
	var anger := 0.0

	func _setup() -> void:
		follow_range = 32.0

	func skin_keys() -> Array:
		return ["pigman"]

	func ambient_sound() -> String:
		return "pigman"

	func armor() -> int:
		return 2

	func _after_model() -> void:
		model.attach_item("rarm", Items.GOLDEN_SWORD, 0, Vector3(-1, -10, 1), Vector3(0, 90, -45), 0.7)

	func find_target() -> Node3D:
		if anger <= 0.0:
			return null
		var p := player()
		if p != null and target_valid(p) and dist_to(p) < follow_range:
			return p
		return null

	func ai_tick() -> void:
		anger = maxf(anger - TICK, 0.0)
		if anger <= 0.0 and target is Player:
			target = null
		super.ai_tick()

	func on_attacked_by(attacker: Node3D) -> void:
		if attacker is Player:
			become_angry(attacker)
			system.call("alert_pigmen", position, attacker)
		else:
			super.on_attacked_by(attacker)

	func become_angry(attacker: Node3D) -> void:
		anger = rng.randf_range(20.0, 40.0)
		target = attacker

	func drop_loot(by_player: bool, _source: String) -> void:
		loot(Items.ROTTEN_FLESH, rng.randi_range(0, 1))
		loot(Items.GOLD_NUGGET, rng.randi_range(0, 1))
		if by_player and rare_drop():
			drop(Items.GOLD_INGOT, 1)

	func save_extra(d: Dictionary) -> void:
		if anger > 0.0:
			d["anger"] = anger

	func load_extra(d: Dictionary) -> void:
		anger = float(d.get("anger", 0.0))


## Скелет: держит дистанцию и стреляет из лука, горит на солнце.
class Skeleton extends Monster:
	var _shoot := 0.0

	func model_key() -> String:
		return "skeleton"

	func skin_keys() -> Array:
		return ["skeleton"]

	func ambient_sound() -> String:
		return "skeleton"

	func _after_model() -> void:
		model.attach_item("rarm", Items.BOW, 0, Vector3(0, -10, 1), Vector3(0, 0, -45), 0.75)

	func chase() -> void:
		var tc := target_center(target)
		look_at_point(tc)
		var d := dist_to(target)
		var visible := can_see_target(target)
		_shoot -= TICK
		if d < 10.0 and visible:
			turn_to(tc - position, 0.4)
			if d < 4.0:
				# Отходит, если игрок слишком близко.
				flee_from(target.position, speed * 0.7)
			if _shoot <= 0.0:
				_shoot = rng.randf_range(1.5, 2.2)
				shoot_arrow(tc)
		else:
			move_to(target.position, speed)

	func shoot_arrow(at: Vector3) -> void:
		var m := manager()
		if m == null:
			return
		var from := eye_position() + facing() * 0.4 - Vector3(0, 0.15, 0)
		var spd := 32.0
		var d := at - from
		var flat := Vector2(d.x, d.z).length()
		var t := flat / spd
		# Поправка на падение стрелы (тяжесть 20 блоков/с²).
		d.y += 0.5 * 20.0 * t * t
		var dir := d.normalized()
		var spread := 0.04 * (4 - difficulty())
		dir = (dir + Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))).normalized()
		m.spawn_projectile("arrow", from, dir * spd, self, 4.0)
		swing = 1.0
		sound("bow")

	func drop_loot(by_player: bool, _source: String) -> void:
		loot(Items.ARROW, rng.randi_range(0, 2))
		loot(Items.BONE, rng.randi_range(0, 2))
		if by_player and rare_drop():
			drop(Items.BOW, 1)

	func pose(ph: float, amt: float, hy: float, hp: float, t: float) -> void:
		super.pose(ph, amt, hy, hp, t)
		if target != null:
			model.rot("rarm", Vector3(-PI / 2.0 + hp, hy - 0.1, 0))
			model.rot("larm", Vector3(-PI / 2.0 + hp, hy + 0.5, 0))


## Крипер: подкрадывается, шипит и взрывается (сила 3, заряженный — 6). Боится кошек.
class Creeper extends Monster:
	var fuse := 0.0
	var charged := false
	var _hissing := false

	func model_key() -> String:
		return "creeper"

	func skin_keys() -> Array:
		return ["creeper"]

	func _after_model() -> void:
		if charged:
			model.set_tint(0, Color(0.75, 0.9, 1.0))

	func set_charged(v: bool) -> void:
		charged = v
		if model != null:
			model.set_tint(0, Color(0.75, 0.9, 1.0) if v else Color.WHITE)

	func ai_tick() -> void:
		# Кошки и оцелоты отпугивают криперов.
		var cat: Variant = system.call("nearest_mob", position, 6.0, [MobDefs.OCELOT], self)
		if cat != null:
			fuse = maxf(fuse - TICK, 0.0)
			flee_from((cat as Node3D).position, speed * 1.2)
			return
		super.ai_tick()
		var lit := false
		if target_valid(target) and dist_to(target) < 3.0 and can_see_target(target):
			lit = true
		elif target_valid(target) and fuse > 0.0 and dist_to(target) < 7.0:
			lit = true
		if lit:
			if not _hissing:
				_hissing = true
				sound("creeper_fuse")
			fuse += TICK
			stop_moving()
			if fuse >= 1.5:
				explode()
		else:
			_hissing = false
			fuse = maxf(fuse - TICK, 0.0)

	func chase() -> void:
		look_at_point(target_center(target))
		if dist_to(target) > 2.2 or fuse <= 0.0:
			move_to(target.position, speed)

	func explode() -> void:
		var m := manager()
		if m == null or m.logic == null or is_dead():
			return
		removed = true
		var c := center()
		system.call("remove_mob", self)
		system.call("effect", "explosion", c, 30 if not charged else 60)
		m.logic.explode(c, 6.0 if charged else 3.0, false, null)

	func drop_loot(_by_player: bool, _source: String) -> void:
		loot(Items.GUNPOWDER, rng.randi_range(0, 2))

	func on_death(_source: String, attacker: Node3D) -> void:
		if attacker is Skeleton:
			drop(Items.RECORD_13 + rng.randi_range(0, 9), 1)

	func animate(delta: float) -> void:
		super.animate(delta)
		var f := clampf(fuse / 1.5, 0.0, 1.0)
		var sw := 1.0 + sin(f * 100.0) * f * 0.01
		f = f * f * f * f
		var sxz := (1.0 + f * 0.4) * sw
		var sy := (1.0 + f * 0.1) / sw
		model.pivot.scale = Vector3(sxz, sy, sxz) * model_scale()
		var flash := 0.0
		if fuse > 0.0 and int(fuse * 10.0) % 2 == 0:
			flash = clampf(fuse / 1.5, 0.2, 1.0)
		model.set_flash(flash)

	func save_extra(d: Dictionary) -> void:
		if charged:
			d["charged"] = true
		if fuse > 0.0:
			d["fuse"] = fuse

	func load_extra(d: Dictionary) -> void:
		set_charged(bool(d.get("charged", false)))
		fuse = float(d.get("fuse", 0.0))


## Паук: днём нейтрален, ночью нападает, прыгает на жертву, лазает по стенам.
class Spider extends Monster:
	var cave := false

	func _setup() -> void:
		cave = type == MobDefs.CAVE_SPIDER

	func model_key() -> String:
		return "spider"

	func skin_keys() -> Array:
		return ["cave_spider" if cave else "spider"]

	func model_scale() -> float:
		return (0.7 if cave else 1.0) * (0.5 if baby else 1.0)

	func ambient_sound() -> String:
		return "spider"

	func _bright() -> bool:
		var c := Vector3i(floori(position.x), floori(position.y + 0.5), floori(position.z))
		var sky := world.get_sky_light(c) if is_day() else 0
		return maxi(sky, world.get_block_light(c)) >= 8

	func find_target() -> Node3D:
		if _bright():
			return null
		return hostile_player_near(follow_range)

	func ai_tick() -> void:
		# На свету теряет интерес (1% за тик).
		if target is Player and _bright() and rng.randi_range(0, 99) == 0:
			target = null
		super.ai_tick()

	func chase() -> void:
		look_at_point(target_center(target))
		var d := dist_to(target)
		if d > 2.0 and d < 6.0 and on_ground and rng.randi_range(0, 9) == 0:
			var dir := target.position - position
			dir.y = 0.0
			dir = dir.normalized()
			velocity.x = dir.x * 7.0 + velocity.x * 0.2
			velocity.z = dir.z * 7.0 + velocity.z * 0.2
			velocity.y = 7.0
			on_ground = false
			turn_to(dir, 1.0)
		else:
			move_to(target.position, speed)
		if melee(target, attack_damage) and cave and target is Player:
			var secs: float = [0.0, 0.0, 7.0, 15.0][clampi(difficulty(), 0, 3)]
			if secs > 0.0:
				(target as Player).add_effect(Potions.POISON, 0, secs)

	func is_climbing() -> bool:
		return hit_wall and move_dir.length_squared() > 0.01

	func drop_loot(by_player: bool, _source: String) -> void:
		loot(Items.STRING, rng.randi_range(0, 2))
		if by_player and (rng.randi_range(0, 2) == 0 or rng.randi_range(0, looting) > 0):
			drop(Items.SPIDER_EYE, 1)


## Эндермен: нейтрален, злится от взгляда, телепортируется, переносит блоки, боится воды.
class Enderman extends Monster:
	var carried := 0
	var carried_meta := 0
	var angry := false
	var _stare := 0
	var _tp_cd := 0.0
	var _carry_mesh: MeshInstance3D

	func _setup() -> void:
		follow_range = 64.0

	func model_key() -> String:
		return "enderman"

	func skin_keys() -> Array:
		return ["enderman"]

	func ambient_sound() -> String:
		return "enderman"

	func _after_model() -> void:
		_update_carry_mesh()

	func _update_carry_mesh() -> void:
		if model == null:
			return
		model.detach(_carry_mesh)
		_carry_mesh = null
		if carried != 0:
			_carry_mesh = model.attach_item("body", carried, carried_meta, Vector3(0, -4, 6), Vector3(10, 45, 0), 0.45)

	func find_target() -> Node3D:
		var p := player()
		if p == null or not target_valid(p):
			return null
		if angry and dist_to(p) < follow_range:
			return p
		# Злится, если игрок смотрит прямо на голову (кроме игрока в тыкве).
		var eye := eye_position()
		var to := eye - p.eye_position()
		var dist := to.length()
		if dist > 64.0 or dist < 0.1:
			return null
		if _wears_pumpkin(p):
			return null
		var dot := p.look_dir().dot(to / dist)
		if dot > 1.0 - 0.025 / dist * 2.0 and can_see(p.eye_position()):
			_stare += 1
			if _stare >= 3:
				angry = true
				sound("enderman")
				return p
		else:
			_stare = 0
		return null

	func _wears_pumpkin(p: Player) -> bool:
		var helmet := Inventory.ARMOR_START
		return helmet < p.inventory.ids.size() and p.inventory.counts[helmet] > 0 and p.inventory.ids[helmet] == Blocks.PUMPKIN

	func ai_tick() -> void:
		_retarget = minf(_retarget, 0.05)
		_tp_cd = maxf(_tp_cd - TICK, 0.0)
		super.ai_tick()
		if not target_valid(target):
			angry = false
		# Вода, дождь и солнце заставляют исчезнуть.
		if in_water and _tp_cd <= 0.0:
			teleport_random()
		elif target == null and is_day() and world.dimension == 0 and _exposed_to_sky() and rng.randi_range(0, 60) == 0:
			teleport_random()
		_handle_blocks()

	func _exposed_to_sky() -> bool:
		var c := Vector3i(floori(position.x), floori(position.y + 2.5), floori(position.z))
		return world.get_sky_light(c) >= 15

	func chase() -> void:
		look_at_point(target_center(target))
		var d := dist_to(target)
		if d > 16.0 and _tp_cd <= 0.0 and rng.randi_range(0, 30) == 0:
			teleport_toward(target.position)
			return
		move_to(target.position, speed * 1.6)
		melee(target, attack_damage)

	func on_hurt(_amount: int, source: String, _attacker: Node3D) -> bool:
		if source == "arrow":
			teleport_random()
			return false
		return true

	func after_hurt(amount: int, source: String, attacker: Node3D) -> void:
		super.after_hurt(amount, source, attacker)
		if attacker is Player:
			angry = true
			target = attacker
		if source != "void" and rng.randi_range(0, 9) < 6:
			teleport_random()

	func teleport_random() -> bool:
		for i in 12:
			var p := position + Vector3(rng.randf_range(-32, 32), rng.randf_range(-16, 16), rng.randf_range(-32, 32))
			if teleport_to(p):
				return true
		return false

	func teleport_toward(goal: Vector3) -> bool:
		var dir := (position - goal).normalized()
		var p := position + Vector3(rng.randf_range(-4, 4), rng.randf_range(-8, 8), rng.randf_range(-4, 4)) - dir * 16.0
		return teleport_to(p)

	## Перемещение на твёрдую опору рядом с точкой (как в оригинале — опускаемся до земли).
	func teleport_to(p: Vector3) -> bool:
		for attempt in 4:
			var c := Vector3i(floori(p.x) + (rng.randi_range(-3, 3) if attempt > 0 else 0), floori(p.y),
				floori(p.z) + (rng.randi_range(-3, 3) if attempt > 0 else 0))
			if not world.is_loaded(c):
				continue
			var k := 0
			while c.y > 1 and k < 24 and not Blocks.is_solid(world.get_block_v(c + Vector3i(0, -1, 0))):
				c.y -= 1
				k += 1
			var below := world.get_block_v(c + Vector3i(0, -1, 0))
			if not Blocks.is_solid(below) or Blocks.is_liquid(world.get_block_v(c)):
				continue
			var np := Vector3(c.x + 0.5, c.y, c.z + 0.5)
			if BodyPhysics.collides(world, np, half_w, height):
				continue
			if Blocks.is_liquid(world.get_block_v(c + Vector3i(0, 1, 0))):
				continue
			effect("portal")
			position = np
			prev_pos = np
			velocity = Vector3.ZERO
			path.clear()
			wander_target = Vector3.INF
			_tp_cd = 1.0
			sound("enderman_teleport")
			effect("portal")
			return true
		return false

	## Берёт и ставит блоки (трава, земля, песок, цветы, тыквы…).
	func _handle_blocks() -> void:
		if carried == 0:
			if rng.randi_range(0, 19) == 0:
				var c := Vector3i(floori(position.x) + rng.randi_range(-2, 2), floori(position.y) + rng.randi_range(-1, 2),
					floori(position.z) + rng.randi_range(-2, 2))
				var b := world.get_block_v(c)
				if b in MobDefs.ENDERMAN_CARRY:
					carried = b
					carried_meta = world.get_meta_v(c)
					world.set_block(c.x, c.y, c.z, Blocks.AIR)
					_update_carry_mesh()
		elif rng.randi_range(0, 1999) == 0:
			var c := Vector3i(floori(position.x) + rng.randi_range(-1, 1), floori(position.y) + rng.randi_range(-1, 2),
				floori(position.z) + rng.randi_range(-1, 1))
			var below := world.get_block_v(c + Vector3i(0, -1, 0))
			if world.get_block_v(c) == Blocks.AIR and Blocks.is_opaque(below):
				world.set_block(c.x, c.y, c.z, carried, carried_meta)
				carried = 0
				carried_meta = 0
				_update_carry_mesh()

	func drop_loot(_by_player: bool, _source: String) -> void:
		loot(Items.ENDER_PEARL, rng.randi_range(0, 1))
		if carried != 0:
			drop(carried, 1, carried_meta if carried != Blocks.GRASS else 0)

	func pose(ph: float, amt: float, hy: float, hp: float, t: float) -> void:
		super.pose(ph, amt, hy, hp, t)
		# Злой — раскрытая пасть и дрожь; с блоком — руки вперёд.
		var shake := Vector3.ZERO
		if angry:
			shake = Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
			model.shift("head", Vector3(0, 5, 0) + shake)
		else:
			model.shift("head", Vector3.ZERO)
		if carried != 0:
			model.rot("rarm", Vector3(-0.5, 0, 0.05))
			model.rot("larm", Vector3(-0.5, 0, -0.05))

	func save_extra(d: Dictionary) -> void:
		if carried != 0:
			d["carried"] = [carried, carried_meta]

	func load_extra(d: Dictionary) -> void:
		var c: Variant = d.get("carried", null)
		if c is Array and (c as Array).size() == 2:
			carried = int(c[0])
			carried_meta = int(c[1])
		_update_carry_mesh()


## Слизень (размер 1, 2 или 4): прыгает к игроку, делится при смерти. Магмовый куб — его огненный
## вариант из Нижнего мира: выше прыгает, сильнее бьёт, не боится огня.
class Slime extends Monster:
	var size := 1
	var magma := false
	var _jump_delay := 0
	var _squish := 0.0
	var _squish_prev := 0.0
	var _was_ground := true

	func _setup() -> void:
		magma = type == MobDefs.MAGMA_CUBE
		set_size(1 << rng.randi_range(0, 2))

	func set_size(s: int) -> void:
		size = clampi(s, 1, 8)
		max_health = size * size
		health = max_health
		xp_value = size
		_apply_size()

	func _apply_size() -> void:
		half_w = 0.3 * size
		height = 0.6 * size
		if model != null:
			model.pivot.scale = Vector3.ONE * size
			model.pivot.position.y = model.ground * size

	func model_scale() -> float:
		return float(size)

	func model_key() -> String:
		return "magma_cube" if magma else "slime"

	func skin_keys() -> Array:
		return ["magma_cube"] if magma else ["slime", "slime"]

	func armor() -> int:
		return size * 3 if magma else 0

	func swims_up() -> bool:
		return not magma

	func ai_tick() -> void:
		_retarget -= TICK
		if _retarget <= 0.0:
			_retarget = 0.5
			if not target_valid(target) or dist_to(target) > 32.0:
				target = hostile_player_near(16.0, false)
		if not target_valid(target):
			target = null
		if on_ground and not _was_ground:
			_squish = -0.5
			if size > 1 or magma:
				sound("slime")
		_was_ground = on_ground
		_squish *= 0.6
		if on_ground:
			stop_moving()
			velocity.x *= 0.5
			velocity.z *= 0.5
			_jump_delay -= 1
			if _jump_delay <= 0:
				_jump_delay = rng.randi_range(10, 30)
				var dir := Vector3(sin(yaw), 0, cos(yaw))
				if target != null:
					_jump_delay = maxi(int(_jump_delay / 3.0), 4)
					var to := target.position - position
					to.y = 0.0
					if to.length_squared() > 0.01:
						dir = to.normalized()
				else:
					dir = dir.rotated(Vector3.UP, rng.randf_range(-1.2, 1.2))
				turn_to(dir, PI)
				velocity.y = (8.4 + size * 2.0) if magma else 8.4
				var hs := 2.5 + size * 0.4
				velocity.x = dir.x * hs
				velocity.z = dir.z * hs
				on_ground = false
				_squish = 1.0
		else:
			# В прыжке держит направление.
			move_dir = facing() * (2.5 + size * 0.4)
		if target != null:
			look_at_point(target_center(target))
			var dmg := size + 2 if magma else (size if size > 1 else 0)
			if dmg > 0:
				melee(target, dmg, 1.0)

	func on_death(_source: String, _attacker: Node3D) -> void:
		if size <= 1:
			return
		var n := rng.randi_range(2, 4)
		for i in n:
			var off := Vector3((float(i & 1) - 0.5) * size * 0.5, 0.5, (float(i >> 1) - 0.5) * size * 0.5)
			var s: Variant = system.call("spawn", type, position + off, false)
			if s is Slime:
				(s as Slime).set_size(size >> 1)

	func drop_loot(_by_player: bool, _source: String) -> void:
		if magma:
			if size > 1:
				loot(Items.MAGMA_CREAM, rng.randi_range(0, 1))
		elif size == 1:
			loot(Items.SLIME_BALL, rng.randi_range(0, 2))

	func pose(_ph: float, _amt: float, _hy: float, _hp: float, _t: float) -> void:
		var a := clampf(tick_acc / TICK, 0.0, 1.0)
		var sq := lerpf(_squish_prev, _squish, a)
		_squish_prev = lerpf(_squish_prev, _squish, 0.3)
		var s := float(size)
		model.pivot.scale = Vector3(s / (1.0 + sq * 0.5), s * (1.0 + sq * 0.5), s / (1.0 + sq * 0.5))
		if magma:
			for i in 8:
				model.shift("s%d" % i, Vector3(0, (4.0 - i) * maxf(sq, 0.0) * 1.7, 0))

	func save_extra(d: Dictionary) -> void:
		d["size"] = size

	func load_extra(d: Dictionary) -> void:
		var hp := int(d.get("health", size * size))
		set_size(int(d.get("size", size)))
		health = clampi(hp, 1, max_health)


## Чешуйница: выскакивает из каменных блоков-яиц, зовёт сородичей, прячется в камень.
class Silverfish extends Monster:
	var _summon := 0.0

	func _setup() -> void:
		follow_range = 12.0

	func model_key() -> String:
		return "silverfish"

	func skin_keys() -> Array:
		return ["silverfish"]

	func ambient_sound() -> String:
		return "silverfish"

	func ai_tick() -> void:
		super.ai_tick()
		if _summon > 0.0:
			_summon -= TICK
			if _summon <= 0.0:
				_call_friends()
		if target == null and on_ground and rng.randi_range(0, 9) == 0 and age > 3.0:
			_try_hide()

	func after_hurt(amount: int, source: String, attacker: Node3D) -> void:
		super.after_hurt(amount, source, attacker)
		if attacker is Player and _summon <= 0.0:
			_summon = 1.0

	func _call_friends() -> void:
		var base := Vector3i(floori(position.x), floori(position.y), floori(position.z))
		var found := 0
		for dy in range(-5, 6):
			for dz in range(-10, 11):
				for dx in range(-5, 6):
					var c := base + Vector3i(dx, dy, dz)
					if world.get_block_v(c) == Blocks.MONSTER_EGG:
						world.set_block(c.x, c.y, c.z, Blocks.AIR)
						system.call("spawn", MobDefs.SILVERFISH, Vector3(c) + Vector3(0.5, 0.0, 0.5), false)
						found += 1
						if found >= 6:
							return

	func _try_hide() -> void:
		var base := Vector3i(floori(position.x), floori(position.y + 0.5), floori(position.z))
		var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
		var c: Vector3i = base + dirs[rng.randi_range(0, 5)]
		var b := world.get_block_v(c)
		var meta := -1
		match b:
			Blocks.STONE:
				meta = 0
			Blocks.COBBLESTONE:
				meta = 1
			Blocks.STONE_BRICKS:
				meta = 2
		if meta < 0:
			return
		world.set_block(c.x, c.y, c.z, Blocks.MONSTER_EGG, meta)
		effect("smoke")
		system.call("remove_mob", self)


## Гаст: летает в Нижнем мире, плюётся огненными шарами (их можно отбить ударом).
class Ghast extends Mob:
	var _waypoint := Vector3.INF
	var _attack := 0
	var _course_cd := 0
	var _fire_skin := false

	func model_key() -> String:
		return "ghast"

	func skin_keys() -> Array:
		return ["ghast"]

	func ambient_sound() -> String:
		return "ghast"

	func ai_tick() -> void:
		# Блуждание по воздуху.
		if _waypoint == Vector3.INF or position.distance_to(_waypoint) < 1.5 or _waypoint.distance_to(position) > 60.0:
			_waypoint = position + Vector3(rng.randf_range(-16, 16), rng.randf_range(-16, 16), rng.randf_range(-16, 16))
		_course_cd -= 1
		if _course_cd <= 0:
			_course_cd = rng.randi_range(5, 10)
			if not _course_clear(_waypoint):
				_waypoint = Vector3.INF
		if _waypoint != Vector3.INF:
			var d := (_waypoint - position).normalized()
			move_dir = d * speed
		if not target_valid(target) or ticks % 20 == 0:
			var p := player()
			target = p if p != null and target_valid(p) and dist_to(p) < 100.0 else null
		if target != null:
			var tc := target_center(target)
			var to := tc - center()
			turn_to(to, 0.3)
			look_at_point(tc)
			if can_see(tc):
				_attack += 1
				if _attack == 10:
					sound("ghast")
				if _attack >= 20:
					_shoot(tc)
					_attack = -40
			elif _attack > 0:
				_attack -= 1
		else:
			if move_dir.length_squared() > 0.01:
				turn_to(move_dir, 0.2)
			if _attack > 0:
				_attack -= 1
		var want_fire := _attack > 10
		if want_fire != _fire_skin and model != null:
			_fire_skin = want_fire
			model.set_skin(0, MobSkins.get_skin("ghast_fire" if want_fire else "ghast"))

	func _course_clear(p: Vector3) -> bool:
		var d := p - position
		var steps := ceili(d.length())
		for i in range(1, steps):
			var q := position + d * (float(i) / steps)
			if BodyPhysics.collides(world, q, half_w, height):
				return false
		return true

	func _shoot(at: Vector3) -> void:
		var m := manager()
		if m == null:
			return
		var from := center() + facing() * 2.4
		var dir := (at - from).normalized()
		m.spawn_projectile("fireball", from, dir * 16.0, self, 6.0)
		sound("ghast_shoot")

	func hurt(amount: int, source: String, attacker: Node3D, kb: Vector3, ignore_invuln := false) -> bool:
		# Отбитый игроком огненный шар убивает гаста сразу (как в оригинале).
		if source == "fire" and attacker != null and attacker == player():
			Achievements.unlock("ghast")
			return super.hurt(1000, "mob", attacker, kb, true)
		return super.hurt(amount, source, attacker, kb, ignore_invuln)

	func drop_loot(_by_player: bool, _source: String) -> void:
		loot(Items.GHAST_TEAR, rng.randi_range(0, 1))
		loot(Items.GUNPOWDER, rng.randi_range(0, 2))

	func pose(_ph: float, _amt: float, _hy: float, _hp: float, t: float) -> void:
		for i in 9:
			model.rot("t%d" % i, Vector3(0.2 * sin(t * 6.0 + i) + 0.4, 0, 0))


## Ифрит: парит, поджигает огненными шарами (по три подряд), в ближнем бою жжёт.
class Blaze extends Monster:
	var _volley := 0
	var _attack := 0
	var _hover := 0.0

	func _setup() -> void:
		follow_range = 48.0

	func model_key() -> String:
		return "blaze"

	func skin_keys() -> Array:
		return ["blaze"]

	func ambient_sound() -> String:
		return "blaze"

	func find_target() -> Node3D:
		return hostile_player_near(follow_range)

	func fall_limit() -> float:
		return -2.5

	func swims_up() -> bool:
		return true

	func on_hurt(amount: int, source: String, attacker: Node3D) -> bool:
		if source == "arrow" and amount == 0 and attacker != null:
			# Снежок ранит ифрита (3 единицы).
			hurt(3, "snowball", attacker, Vector3.ZERO)
			return false
		return true

	func chase() -> void:
		var tc := target_center(target)
		look_at_point(tc)
		turn_to(tc - position, 0.4)
		var d := dist_to(target)
		# Держится чуть выше цели.
		if target.position.y + 1.0 > position.y + 0.5 or _hover > 0.0:
			velocity.y = lerpf(velocity.y, 3.0, 0.3)
		_attack -= 1
		if d < 2.0:
			melee(target, attack_damage)
			if target is Player and attack_cd > 0.9:
				(target as Player).fire_time = maxf((target as Player).fire_time, 3.0)
		elif d < 30.0 and can_see(tc):
			if _attack <= 0:
				if _volley == 0:
					_volley = 1
					_attack = 20
				elif _volley <= 3:
					_shoot(tc, d)
					_volley += 1
					_attack = 6
				else:
					_volley = 0
					_attack = rng.randi_range(60, 100)
			if d > 8.0:
				move_to(target.position, speed * 0.6)
		else:
			move_to(target.position, speed)

	func _shoot(at: Vector3, d: float) -> void:
		var m := manager()
		if m == null:
			return
		var from := center() + Vector3(0, 0.3, 0)
		var spread := sqrt(d) * 0.04
		var dir := (at - from).normalized() + Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread) * 0.5,
			rng.randf_range(-spread, spread))
		m.spawn_projectile("small_fireball", from, dir.normalized() * 15.0, self, 5.0)
		sound("blaze")

	func ai_tick() -> void:
		_hover = maxf(_hover - TICK, 0.0)
		if rng.randi_range(0, 60) == 0:
			_hover = rng.randf_range(0.3, 0.8)
		super.ai_tick()
		if ticks % 30 == 0 and rng.randi_range(0, 2) == 0:
			effect("smoke")

	func drop_loot(by_player: bool, _source: String) -> void:
		if by_player:
			loot(Items.BLAZE_ROD, rng.randi_range(0, 1))

	func pose(_ph: float, _amt: float, hy: float, hp: float, t: float) -> void:
		model.rot("head", Vector3(hp, hy, 0))
		# Три кольца стержней вращаются вокруг тела (как ModelBlaze).
		var tt := t * 20.0
		for i in 12:
			var ring := i >> 2
			var k := float(i & 3)
			var ang := 0.0
			var r := 0.0
			var y := 0.0
			match ring:
				0:
					ang = tt * PI * -0.1 + k * PI * 0.5
					r = 9.0
					y = 26.0 - cos((k * 2.0 + tt) * 0.25)
				1:
					ang = PI / 4.0 + tt * PI * 0.03 + k * PI * 0.5
					r = 7.0
					y = 22.0 - cos((k * 2.0 + tt) * 0.25)
				_:
					ang = 0.47 + tt * PI * -0.05 + k * PI * 0.5
					r = 5.0
					y = 13.0 - cos((k * 1.5 + tt) * 0.5)
			model.place("rod%d" % i, Vector3(cos(ang) * r - 1.0, y, -sin(ang) * r + 1.0))
