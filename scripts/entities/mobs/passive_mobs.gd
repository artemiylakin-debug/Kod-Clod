class_name PassiveMobs
extends RefCounted
## Мирные и нейтральные существа 1.2: свинья, овца, корова, грибная корова, курица, спрут,
## волк, оцелот и кошки, житель, железный и снежный големы. Разведение и рост детёнышей.


## Животное: паника после удара, приманка едой, разведение (30 с «любви», детёныш растёт 20 минут,
## родителям 5 минут перерыва), детёныши держатся рядом со взрослыми.
class Animal extends Mob:
	var love := 0.0
	var breed_cd := 0.0
	var _mate: Mob
	var _mate_time := 0.0
	var _follow_cd := 0.0
	var _parent: Mob

	func _tick_love() -> void:
		love = maxf(love - TICK, 0.0)
		breed_cd = maxf(breed_cd - TICK, 0.0)

	func ai_tick() -> void:
		_tick_love()
		if panic > 0.0:
			var from := last_attacker.position if last_attacker != null and is_instance_valid(last_attacker) else position - facing()
			flee_from(from, speed * 1.5)
			return
		if love > 0.0 and _seek_mate():
			return
		var p := player()
		if p != null and not p.dead and _tempted_by(p):
			look_at_point(p.eye_position())
			if dist_to(p) > 2.0:
				move_to(p.position, speed * 0.9)
			return
		if baby and _follow_parent():
			return
		_idle()

	## Обычное поведение без событий (переопределяется).
	func _idle() -> void:
		var p := player()
		if p != null and dist_to(p) < 6.0 and rng.randi_range(0, 49) == 0:
			look_pos = p.eye_position()
		wander(speed * 0.5)

	func _tempted_by(p: Player) -> bool:
		var items := MobDefs.breed_item(type)
		return not items.is_empty() and p.inventory.selected_id() in items and dist_to(p) < 10.0

	func _follow_parent() -> bool:
		_follow_cd -= TICK
		if _follow_cd <= 0.0:
			_follow_cd = 1.0
			_parent = system.call("nearest_mob", position, 8.0, [type], self, true)
		if _parent == null or not is_instance_valid(_parent) or _parent.is_dead():
			return false
		if dist_to(_parent) < 3.0:
			return false
		move_to(_parent.position, speed * 0.8)
		return true

	func _seek_mate() -> bool:
		if _mate == null or not is_instance_valid(_mate) or _mate.is_dead() or not _can_mate(_mate):
			_mate = null
			_mate_time = 0.0
			for m: Mob in system.call("mobs_near", position, 8.0):
				if m != self and _can_mate(m):
					_mate = m
					break
		if _mate == null:
			return false
		look_at_point(_mate.eye_position())
		move_to(_mate.position, speed * 0.8)
		if dist_to(_mate) < 1.5:
			_mate_time += TICK
			if _mate_time >= 3.0:
				_breed(_mate as Animal)
		return true

	func _can_mate(m: Mob) -> bool:
		if not m is Animal or m.type != type or m.baby or m.is_dead():
			return false
		var a := m as Animal
		return a.love > 0.0 and can_breed() and a.can_breed()

	func can_breed() -> bool:
		return not baby

	func _breed(other: Animal) -> void:
		love = 0.0
		other.love = 0.0
		breed_cd = 300.0
		other.breed_cd = 300.0
		_mate = null
		_mate_time = 0.0
		var pos := (position + other.position) * 0.5
		var child: Variant = system.call("spawn", type, pos, true)
		if child is Animal:
			inherit(child as Animal, other)
		system.call("effect", "hearts", pos + Vector3(0, 0.5, 0))

	## Детёныш наследует признаки родителей (окрас овцы, приручённость волка/кошки).
	func inherit(_child: Animal, _other: Animal) -> void:
		pass

	## Накормить предметом разведения: «любовь» на 30 с.
	func feed_for_love(p: Player) -> bool:
		if baby or love > 0.0 or breed_cd > 0.0:
			return false
		consume_held(p)
		love = 30.0
		effect("hearts")
		return true

	func interact(p: Player) -> bool:
		var id := p.inventory.selected_id()
		if id in MobDefs.breed_item(type) and type != MobDefs.WOLF and type != MobDefs.OCELOT:
			return feed_for_love(p)
		return false

	func after_hurt(amount: int, source: String, attacker: Node3D) -> void:
		super.after_hurt(amount, source, attacker)
		panic = 5.0
		wander_target = Vector3.INF
		love = 0.0

	func drop_meat(raw: int, cooked: int, count: int, looted := true) -> void:
		if looted:
			loot(cooked if burning() else raw, count)
		else:
			drop(cooked if burning() else raw, count)

	func save_extra(d: Dictionary) -> void:
		if love > 0.0:
			d["love"] = love
		if breed_cd > 0.0:
			d["breed_cd"] = breed_cd

	func load_extra(d: Dictionary) -> void:
		love = float(d.get("love", 0.0))
		breed_cd = float(d.get("breed_cd", 0.0))


## Свинья: седло (правая кнопка с седлом), свинина. Удар молнии превращает в свинозомби.
class Pig extends Animal:
	var saddled := false

	func model_key() -> String:
		return "pig"

	func skin_keys() -> Array:
		return ["pig_saddle" if saddled else "pig"]

	func ambient_sound() -> String:
		return "pig"

	func interact(p: Player) -> bool:
		if p.inventory.selected_id() == Items.SADDLE and not saddled and not baby:
			saddled = true
			consume_held(p)
			if model != null:
				model.set_skin(0, MobSkins.get_skin("pig_saddle"))
			return true
		return super.interact(p)

	func drop_loot(_by_player: bool, _source: String) -> void:
		drop_meat(Items.PORKCHOP, Items.COOKED_PORKCHOP, rng.randi_range(0, 2))
		if saddled:
			drop(Items.SADDLE, 1)

	func save_extra(d: Dictionary) -> void:
		super.save_extra(d)
		if saddled:
			d["saddle"] = true

	func load_extra(d: Dictionary) -> void:
		super.load_extra(d)
		saddled = bool(d.get("saddle", false))
		if model != null and saddled:
			model.set_skin(0, MobSkins.get_skin("pig_saddle"))


## Овца: шерсть её цвета (ножницы — 1–3 шерсти), отрастает, когда овца ест траву; красится красителем.
class Sheep extends Animal:
	var color := 0
	var sheared := false
	var _eat := 0

	func _setup() -> void:
		color = MobDefs.random_fleece(rng)

	func model_key() -> String:
		return "sheep"

	func skin_keys() -> Array:
		return ["sheep", "sheep_wool"]

	func ambient_sound() -> String:
		return "sheep"

	func _after_model() -> void:
		_update_wool()

	func _update_wool() -> void:
		if model == null:
			return
		model.set_tint(1, Items.WOOL_COLORS[clampi(color, 0, 15)])
		for n in ["wool_head", "wool_body", "wool_leg1", "wool_leg2", "wool_leg3", "wool_leg4"]:
			model.set_visible(n, not sheared)

	func _idle() -> void:
		if _eat > 0:
			_eat -= 1
			stop_moving()
			if _eat == 4:
				_eat_grass()
			return
		if on_ground and rng.randi_range(0, 49 if baby else 999) == 0:
			var below := world.get_block(floori(position.x), floori(position.y - 0.5), floori(position.z))
			var here := world.get_block(floori(position.x), floori(position.y + 0.2), floori(position.z))
			if below == Blocks.GRASS or here == Blocks.TALLGRASS:
				_eat = 40
				return
		super._idle()

	func _eat_grass() -> void:
		var c := Vector3i(floori(position.x), floori(position.y + 0.2), floori(position.z))
		if world.get_block_v(c) == Blocks.TALLGRASS:
			world.set_block(c.x, c.y, c.z, Blocks.AIR)
		elif world.get_block_v(c + Vector3i(0, -1, 0)) == Blocks.GRASS:
			world.set_block(c.x, c.y - 1, c.z, Blocks.DIRT)
		else:
			return
		sheared = false
		_update_wool()
		if baby:
			grow = maxf(grow - 60.0, 0.1)

	func interact(p: Player) -> bool:
		var id := p.inventory.selected_id()
		if id == Items.SHEARS and not sheared and not baby:
			sheared = true
			_update_wool()
			var m := manager()
			var n := rng.randi_range(1, 3)
			for i in n:
				if m != null:
					m.spawn_drop(Blocks.WOOL, 1, color, center() + Vector3(0, 0.3, 0),
						Vector3(rng.randf_range(-1.5, 1.5), 3.5, rng.randf_range(-1.5, 1.5)))
			if not p.creative:
				p.inventory.damage_slot(p.inventory.selected, 1)
			sound("shear")
			return true
		if id == Items.DYE and not sheared:
			var c := 15 - p.inventory.selected_data()
			if c != color and p.inventory.selected_data() != Items.DYE_BONE_MEAL:
				color = c
				_update_wool()
				consume_held(p)
				return true
			return false
		return super.interact(p)

	func inherit(child: Animal, other: Animal) -> void:
		var s := child as Sheep
		s.color = color if rng.randi_range(0, 1) == 0 else (other as Sheep).color
		s._update_wool()

	func drop_loot(_by_player: bool, _source: String) -> void:
		if not sheared:
			drop(Blocks.WOOL, 1, color)

	func pose(ph: float, amt: float, hy: float, hp: float, t: float) -> void:
		super.pose(ph, amt, hy, hp, t)
		if _eat > 0:
			var k := clampf(minf(40 - _eat, _eat) / 4.0, 0.0, 1.0)
			model.shift("head", Vector3(0, -9.0 * k, 0))
			model.rot("head", Vector3(hp * (1.0 - k) + k * (0.9 + sin(t * 25.0) * 0.15), hy * (1.0 - k), 0))

	func save_extra(d: Dictionary) -> void:
		super.save_extra(d)
		d["color"] = color
		if sheared:
			d["sheared"] = true

	func load_extra(d: Dictionary) -> void:
		super.load_extra(d)
		if d.has("color"):
			color = clampi(int(d["color"]), 0, 15)
		sheared = bool(d.get("sheared", false))
		_update_wool()


## Корова: доится ведром, кожа и говядина.
class Cow extends Animal:
	func model_key() -> String:
		return "cow"

	func skin_keys() -> Array:
		return ["cow"]

	func ambient_sound() -> String:
		return "cow"

	func interact(p: Player) -> bool:
		if p.inventory.selected_id() == Items.BUCKET and not baby:
			p.inventory.replace_selected(Items.MILK_BUCKET)
			sound("milk")
			return true
		return super.interact(p)

	func drop_loot(_by_player: bool, _source: String) -> void:
		loot(Items.LEATHER, rng.randi_range(0, 2))
		drop_meat(Items.BEEF, Items.COOKED_BEEF, rng.randi_range(1, 3))


## Грибная корова: миска → грибной суп, ножницы → обычная корова и 5 красных грибов.
class Mooshroom extends Cow:
	var _shrooms: Array[MeshInstance3D] = []

	func skin_keys() -> Array:
		return ["mooshroom"]

	func _after_model() -> void:
		_shrooms.clear()
		for p: Vector3 in [Vector3(-2, 26, -3), Vector3(2, 26, 3)]:
			for r in [45.0, -45.0]:
				_shrooms.append(model.attach_item("", Blocks.RED_MUSHROOM, 0, p, Vector3(0, r, 0), 0.55))
		for r in [45.0, -45.0]:
			_shrooms.append(model.attach_item("head", Blocks.RED_MUSHROOM, 0, Vector3(0, 8.5, 1), Vector3(0, r, 0), 0.5))

	func _apply_size() -> void:
		super._apply_size()
		for s in _shrooms:
			if is_instance_valid(s):
				s.visible = not baby

	func interact(p: Player) -> bool:
		var id := p.inventory.selected_id()
		if id == Items.BOWL and not baby:
			p.inventory.replace_selected(Items.MUSHROOM_STEW)
			return true
		if id == Items.SHEARS and not baby:
			var cow: Variant = system.call("spawn", MobDefs.COW, position, false)
			if cow is Mob:
				(cow as Mob).yaw = yaw
				(cow as Mob).health = health
			for i in 5:
				drop(Blocks.RED_MUSHROOM, 1)
			if not p.creative:
				p.inventory.damage_slot(p.inventory.selected, 1)
			sound("shear")
			effect("explosion", 5)
			system.call("remove_mob", self)
			return true
		return super.interact(p)


## Курица: откладывает яйца каждые 5–10 минут, медленно падает, разводится семенами.
class Chicken extends Animal:
	var egg_timer := 0.0

	func _setup() -> void:
		egg_timer = rng.randf_range(300.0, 600.0)

	func model_key() -> String:
		return "chicken"

	func skin_keys() -> Array:
		return ["chicken"]

	func ambient_sound() -> String:
		return "chicken"

	func fall_limit() -> float:
		return -3.0

	func ai_tick() -> void:
		super.ai_tick()
		if not baby:
			egg_timer -= TICK
			if egg_timer <= 0.0:
				egg_timer = rng.randf_range(300.0, 600.0)
				drop(Items.EGG, 1)
				sound("plop")

	func drop_loot(_by_player: bool, _source: String) -> void:
		loot(Items.FEATHER, rng.randi_range(0, 2))
		drop_meat(Items.CHICKEN, Items.COOKED_CHICKEN, 1, false)

	func save_extra(d: Dictionary) -> void:
		super.save_extra(d)
		d["egg"] = snappedf(egg_timer, 0.1)

	func load_extra(d: Dictionary) -> void:
		super.load_extra(d)
		egg_timer = float(d.get("egg", egg_timer))


## Спрут: плавает толчками в воде, на суше задыхается; чернильные мешки.
class Squid extends Mob:
	var _swim_dir := Vector3.ZERO
	var _swim_cd := 0.0
	var _pulse := 0.0
	var _out_air := 15.0
	var _pitch := 0.0

	func model_key() -> String:
		return "squid"

	func skin_keys() -> Array:
		return ["squid"]

	func swims_up() -> bool:
		return false

	func ai_tick() -> void:
		_swim_cd -= TICK
		if _swim_cd <= 0.0 or (in_water and hit_wall):
			_swim_cd = rng.randf_range(1.0, 4.0)
			if rng.randi_range(0, 4) == 0:
				_swim_dir = Vector3.ZERO
			else:
				_swim_dir = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.4), rng.randf_range(-1, 1)).normalized()
		if not in_water:
			_out_air -= TICK
			if _out_air <= 0.0 and ticks % 20 == 0:
				hurt(2, "drown", null, Vector3.ZERO)
		else:
			_out_air = 15.0
		if in_water and _swim_dir != Vector3.ZERO:
			turn_to(_swim_dir, 0.1)

	func _physics() -> void:
		if not in_water:
			super._physics()
			return
		_pulse += TICK * 4.0
		var thrust := maxf(sin(_pulse), 0.0)
		var want := _swim_dir * speed * (0.4 + thrust)
		# Не всплывать выше воды.
		var above := world.get_block(floori(position.x), floori(position.y + height + 0.2), floori(position.z))
		if not Blocks.is_water(above) and want.y > 0.0:
			want.y = -0.2
		velocity = velocity.lerp(want, 0.08)
		var res := BodyPhysics.move(world, position, half_w, height, velocity * TICK, 0.0, false)
		position = res["pos"]
		hit_wall = res["hit_x"] or res["hit_z"]
		on_ground = res["on_ground"]
		if res["hit_y"]:
			velocity.y = 0.0
		fall_dist = 0.0

	func drop_loot(_by_player: bool, _source: String) -> void:
		loot(Items.DYE, rng.randi_range(1, 3), Items.DYE_INK)

	func pose(_ph: float, _amt: float, _hy: float, _hp: float, t: float) -> void:
		var spread := 0.35 + maxf(sin(_pulse), 0.0) * 0.45 if in_water else 0.1 + sin(t * 2.0) * 0.05
		for i in 8:
			model.rot("t%d" % i, Vector3(-spread, 0, 0))
		var want := 0.0
		if in_water:
			want = clampf(-velocity.y * 0.3, -0.5, 0.5)
		_pitch = lerpf(_pitch, want, 0.05)
		model.rot("body", Vector3(_pitch, 0, 0))


## Прирученные питомцы (волк, кошка): хозяин, сидение по команде, следование, телепортация к хозяину.
class Pet extends Animal:
	var tamed := false
	var sitting := false
	var _tp_cd := 0.0

	func follow_owner() -> bool:
		var p := player()
		if p == null or p.dead:
			return false
		var d := dist_to(p)
		if d > 12.0 and _tp_cd <= 0.0 and p.on_ground:
			_tp_cd = 1.0
			_teleport_near(p.position)
			return true
		if d > 5.0:
			look_at_point(p.eye_position())
			move_to(p.position, speed * 1.2)
			return true
		return false

	func _teleport_near(p: Vector3) -> void:
		for i in 12:
			var c := Vector3i(floori(p.x) + rng.randi_range(-2, 2), floori(p.y), floori(p.z) + rng.randi_range(-2, 2))
			if absi(c.x - floori(p.x)) < 1 and absi(c.z - floori(p.z)) < 1:
				continue
			if Blocks.is_solid(world.get_block_v(c + Vector3i(0, -1, 0))) and not Blocks.is_solid(world.get_block_v(c)) \
					and not Blocks.is_solid(world.get_block_v(c + Vector3i(0, 1, 0))):
				position = Vector3(c.x + 0.5, c.y, c.z + 0.5)
				prev_pos = position
				velocity = Vector3.ZERO
				path.clear()
				return

	func can_breed() -> bool:
		return tamed and not baby and not sitting

	func toggle_sit() -> void:
		sitting = not sitting
		target = null
		stop_moving()
		wander_target = Vector3.INF

	func inherit(child: Animal, _other: Animal) -> void:
		(child as Pet).tamed = true
		(child as Pet).on_tamed()

	func on_tamed() -> void:
		persistent = true

	func save_extra(d: Dictionary) -> void:
		super.save_extra(d)
		if tamed:
			d["tamed"] = true
			d["owner"] = "player"
		if sitting:
			d["sitting"] = true

	func load_extra(d: Dictionary) -> void:
		super.load_extra(d)
		tamed = bool(d.get("tamed", false))
		sitting = bool(d.get("sitting", false))
		if tamed:
			on_tamed()


## Волк: приручается костями, сидит по команде, защищает хозяина, лечится и разводится мясом.
## Дикие стаи злятся, если ударить одного.
class Wolf extends Pet:
	var angry := 0.0
	var _skin_state := -1
	var _beg := 0.0

	func model_key() -> String:
		return "wolf"

	func skin_keys() -> Array:
		return [_skin_name()]

	func _skin_name() -> String:
		if tamed:
			return "wolf_tame"
		return "wolf_angry" if angry > 0.0 else "wolf"

	func ambient_sound() -> String:
		return "wolf_growl" if angry > 0.0 else "wolf"

	func on_tamed() -> void:
		super.on_tamed()
		max_health = 20
		attack_damage = 4
		angry = 0.0
		_refresh_skin()

	func _refresh_skin() -> void:
		var s := 2 if tamed else (1 if angry > 0.0 else 0)
		if s != _skin_state and model != null:
			_skin_state = s
			model.set_skin(0, MobSkins.get_skin(_skin_name()))

	func ai_tick() -> void:
		_tick_love()
		angry = maxf(angry - TICK, 0.0)
		_tp_cd = maxf(_tp_cd - TICK, 0.0)
		_refresh_skin()
		var p := player()
		# Выпрашивает еду, когда игрок держит кость или мясо.
		_beg = 0.0
		if p != null and dist_to(p) < 8.0 and (p.inventory.selected_id() == Items.BONE or p.inventory.selected_id() in MobDefs.WOLF_FOOD):
			_beg = 1.0
		if sitting:
			stop_moving()
			if p != null and dist_to(p) < 8.0:
				look_at_point(p.eye_position())
			return
		if target_valid(target):
			look_at_point(target_center(target))
			move_to(target.position, speed * 1.3)
			melee(target, attack_damage)
			if target is Mob and (target as Mob).is_dead():
				target = null
			return
		target = null
		if angry > 0.0 and p != null and target_valid(p) and dist_to(p) < 16.0:
			target = p
			return
		if tamed:
			if panic > 0.0:
				panic = 0.0
			if love > 0.0 and _seek_mate():
				return
			if follow_owner():
				return
			if _beg > 0.0:
				look_at_point(p.eye_position())
				return
			wander(speed * 0.5, 200)
			return
		# Дикий волк изредка охотится на овец.
		if ticks % 40 == 0 and rng.randi_range(0, 9) == 0:
			var sheep: Variant = system.call("nearest_mob", position, 12.0, [MobDefs.SHEEP], self)
			if sheep != null:
				target = sheep
				return
		if panic > 0.0:
			panic = 0.0
		if _beg > 0.0 and p != null:
			look_at_point(p.eye_position())
		wander(speed * 0.5)

	func after_hurt(amount: int, source: String, attacker: Node3D) -> void:
		super.after_hurt(amount, source, attacker)
		panic = 0.0
		if sitting:
			sitting = false
		if attacker is Player:
			if not tamed:
				angry = rng.randf_range(20.0, 40.0)
				target = attacker
				system.call("alert_wolves", position, attacker)
		elif attacker is Mob and attacker != self:
			target = attacker

	func defend_owner(attacker: Node3D) -> void:
		if tamed and not sitting and attacker != self and not (attacker is Wolf and (attacker as Wolf).tamed):
			target = attacker

	func interact(p: Player) -> bool:
		var id := p.inventory.selected_id()
		if not tamed:
			if id == Items.BONE and angry <= 0.0:
				consume_held(p)
				if rng.randi_range(0, 2) == 0:
					tamed = true
					on_tamed()
					health = max_health
					sitting = true
					target = null
					stop_moving()
					effect("hearts")
				else:
					effect("smoke")
				return true
			return false
		if id in MobDefs.WOLF_FOOD:
			if health < max_health:
				consume_held(p)
				heal(maxi(Items.food_value(id), 1))
				effect("hearts")
				return true
			return feed_for_love(p)
		toggle_sit()
		return true

	func drop_loot(_by_player: bool, _source: String) -> void:
		pass

	func knockback_scale() -> float:
		return 0.8

	func pose(ph: float, amt: float, hy: float, hp: float, t: float) -> void:
		var c := cos(ph * 0.6662)
		var s := cos(ph * 0.6662 + PI)
		model.rot("head", Vector3(hp, hy, _beg * 0.35))
		var tail := PI / 5.0
		if angry > 0.0:
			tail = 1.54
		elif tamed:
			tail = (0.55 - (20 - health) * 0.02) * PI
		var wag := sin(t * 12.0) * 0.4 if tamed and _beg > 0.0 else c * 1.4 * amt * 0.3
		if sitting:
			_place_mc("body", Vector3(0, 18, 0), Vector3(PI / 4.0, 0, 0))
			_place_mc("mane", Vector3(0, 16, -3), Vector3(2.0 * PI / 5.0, 0, 0))
			_place_mc("tail", Vector3(0, 21, 6), Vector3(tail, wag, 0))
			_place_mc("leg1", Vector3(-1.5, 22, 2), Vector3(3.0 * PI / 2.0, 0, 0))
			_place_mc("leg2", Vector3(1.5, 22, 2), Vector3(3.0 * PI / 2.0, 0, 0))
			_place_mc("leg3", Vector3(-1.49, 17, -4), Vector3(5.811947, 0, 0))
			_place_mc("leg4", Vector3(1.51, 17, -4), Vector3(5.811947, 0, 0))
		else:
			_place_mc("body", Vector3(0, 14, 2), Vector3(PI / 2.0, 0, 0))
			_place_mc("mane", Vector3(0, 14, 2), Vector3(PI / 2.0, 0, 0))
			_place_mc("tail", Vector3(0, 12, 8), Vector3(tail, wag, 0))
			_place_mc("leg1", Vector3(-1.5, 16, 7), Vector3(c * 1.4 * amt, 0, 0))
			_place_mc("leg2", Vector3(1.5, 16, 7), Vector3(s * 1.4 * amt, 0, 0))
			_place_mc("leg3", Vector3(-1.5, 16, -4), Vector3(s * 1.4 * amt, 0, 0))
			_place_mc("leg4", Vector3(1.5, 16, -4), Vector3(c * 1.4 * amt, 0, 0))

	## Положение и поворот части в координатах моделей Minecraft.
	func _place_mc(n: String, p: Vector3, r: Vector3) -> void:
		model.place(n, Vector3(p.x, 24.0 - p.y, -p.z))
		model.set_rot(n, Vector3(r.x, -r.y, -r.z))

	func save_extra(d: Dictionary) -> void:
		super.save_extra(d)
		if angry > 0.0:
			d["angry"] = angry

	func load_extra(d: Dictionary) -> void:
		super.load_extra(d)
		angry = float(d.get("angry", 0.0))
		_refresh_skin()


## Оцелот (джунгли, 1.2): пуглив, приручается сырой рыбой, если подпустит — становится кошкой
## одного из трёх окрасов. Кошки ходят за хозяином, сидят на сундуках и кроватях, пугают криперов.
class Ocelot extends Pet:
	var skin := 0
	var _tempting := 0.0
	var _seat_cd := 0.0
	var _seat := Vector3.INF

	func model_key() -> String:
		return "ocelot"

	func skin_keys() -> Array:
		return [_skin_key()]

	func _skin_key() -> String:
		return ["ocelot", "cat_black", "cat_red", "cat_siamese"][clampi(skin, 0, 3)]

	func ambient_sound() -> String:
		return "cat" if tamed else ""

	func on_tamed() -> void:
		super.on_tamed()
		if skin == 0:
			skin = rng.randi_range(1, 3)
		if model != null:
			model.set_skin(0, MobSkins.get_skin(_skin_key()))

	func ai_tick() -> void:
		_tick_love()
		_tp_cd = maxf(_tp_cd - TICK, 0.0)
		_tempting = maxf(_tempting - TICK, 0.0)
		var p := player()
		if tamed:
			if sitting:
				stop_moving()
				return
			if love > 0.0 and _seek_mate():
				return
			if follow_owner():
				return
			_sit_on_blocks()
			if _seat == Vector3.INF:
				wander(speed * 0.4, 200)
			return
		# Дикий: подходит к игроку с рыбой, если тот стоит спокойно; иначе убегает.
		if p != null and not p.dead and dist_to(p) < 10.0:
			var holding := p.inventory.selected_id() == Items.FISH
			var still := Vector2(p.velocity.x, p.velocity.z).length() < 1.0 and not p.sprinting
			if holding and still:
				_tempting = 1.0
				look_at_point(p.eye_position())
				if dist_to(p) > 2.0:
					move_to(p.position, speed * 0.5)
				return
			if not holding or not still:
				if dist_to(p) < 7.0 and _tempting <= 0.0:
					flee_from(p.position, speed * 2.0)
					return
		# Охота на кур.
		if target_valid(target):
			look_at_point(target_center(target))
			move_to(target.position, speed * 1.4)
			melee(target, attack_damage)
			return
		target = null
		if ticks % 40 == 0 and rng.randi_range(0, 19) == 0:
			var ch: Variant = system.call("nearest_mob", position, 10.0, [MobDefs.CHICKEN], self)
			if ch != null:
				target = ch
		wander(speed * 0.5)

	## Кошки садятся на сундук, кровать или горящую печь поблизости.
	func _sit_on_blocks() -> void:
		_seat_cd -= TICK
		if _seat != Vector3.INF:
			move_to(_seat, speed * 0.6)
			if position.distance_to(_seat) < 0.6 or stuck_time > 3.0:
				if position.distance_to(_seat) < 0.6:
					sitting = true
				_seat = Vector3.INF
			return
		if _seat_cd > 0.0:
			return
		_seat_cd = rng.randf_range(15.0, 30.0)
		var base := Vector3i(floori(position.x), floori(position.y), floori(position.z))
		for i in 40:
			var c := base + Vector3i(rng.randi_range(-6, 6), rng.randi_range(-1, 2), rng.randi_range(-6, 6))
			var b := world.get_block_v(c)
			if (b == Blocks.CHEST or b == Blocks.BED or b == Blocks.LIT_FURNACE) and world.get_block_v(c + Vector3i(0, 1, 0)) == Blocks.AIR:
				_seat = Vector3(c.x + 0.5, c.y + 1.0, c.z + 0.5)
				return

	func interact(p: Player) -> bool:
		var id := p.inventory.selected_id()
		if not tamed:
			if id == Items.FISH and dist_to(p) < 3.5:
				consume_held(p)
				if rng.randi_range(0, 2) == 0:
					tamed = true
					on_tamed()
					sitting = true
					stop_moving()
					effect("hearts")
				else:
					effect("smoke")
				return true
			return false
		if id == Items.FISH:
			if feed_for_love(p):
				return true
		toggle_sit()
		return true

	func after_hurt(amount: int, source: String, attacker: Node3D) -> void:
		super.after_hurt(amount, source, attacker)
		if sitting:
			sitting = false

	func pose(ph: float, amt: float, hy: float, hp: float, t: float) -> void:
		var c := cos(ph * 0.6662)
		var s := cos(ph * 0.6662 + PI)
		_place_mc("head", Vector3(0, 15, -9), Vector3(hp, hy, 0))
		_place_mc("body", Vector3(0, 12, -10), Vector3(PI / 2.0, 0, 0))
		_place_mc("tail1", Vector3(0, 15, 8), Vector3(0.9 + c * 0.2 * amt, 0, 0))
		_place_mc("tail2", Vector3(0, 20, 14), Vector3(1.73 + 0.47 * c * amt + sin(t * 3.0) * 0.1, 0, 0))
		if sitting:
			_place_mc("body", Vector3(0, 8, -5), Vector3(PI / 4.0, 0, 0))
			_place_mc("head", Vector3(0, 11.7, -8), Vector3(hp, hy, 0))
			_place_mc("tail1", Vector3(0, 23, 6), Vector3(1.7278761, 0, 0))
			_place_mc("tail2", Vector3(0, 22, 13.2), Vector3(2.670354, 0, 0))
			_place_mc("leg3", Vector3(-1.2, 15.8, -7), Vector3(-0.15707964, 0, 0))
			_place_mc("leg4", Vector3(1.2, 15.8, -7), Vector3(-0.15707964, 0, 0))
			_place_mc("leg1", Vector3(-1.1, 21, 1), Vector3(-PI / 2.0, 0, 0))
			_place_mc("leg2", Vector3(1.1, 21, 1), Vector3(-PI / 2.0, 0, 0))
		else:
			_place_mc("leg1", Vector3(-1.1, 18, 5), Vector3(c * amt, 0, 0))
			_place_mc("leg2", Vector3(1.1, 18, 5), Vector3(s * amt, 0, 0))
			_place_mc("leg3", Vector3(-1.2, 13.8, -5), Vector3(s * amt, 0, 0))
			_place_mc("leg4", Vector3(1.2, 13.8, -5), Vector3(c * amt, 0, 0))

	func _place_mc(n: String, p: Vector3, r: Vector3) -> void:
		model.place(n, Vector3(p.x, 24.0 - p.y, -p.z))
		model.set_rot(n, Vector3(r.x, -r.y, -r.z))

	func save_extra(d: Dictionary) -> void:
		super.save_extra(d)
		if skin != 0:
			d["skin"] = skin

	func load_extra(d: Dictionary) -> void:
		skin = clampi(int(d.get("skin", 0)), 0, 3)
		super.load_extra(d)
		if model != null:
			model.set_skin(0, MobSkins.get_skin(_skin_key()))


## Житель (1.2: без торговли): бродит у деревни, убегает от зомби, смотрит на игрока, дети играют.
class Villager extends Mob:
	var profession := 0
	var _mate_cd := 0.0

	func _setup() -> void:
		profession = rng.randi_range(0, 4)
		_mate_cd = rng.randf_range(20.0, 60.0)

	func model_key() -> String:
		return "villager"

	func skin_keys() -> Array:
		return ["villager_%d" % profession]

	func ambient_sound() -> String:
		return "villager"

	func ai_tick() -> void:
		var z: Variant = system.call("nearest_mob", position, 8.0, [MobDefs.ZOMBIE], self)
		if z != null:
			flee_from((z as Node3D).position, speed * 1.6)
			return
		if panic > 0.0:
			var from := last_attacker.position if last_attacker != null and is_instance_valid(last_attacker) else position - facing()
			flee_from(from, speed * 1.4)
			return
		var p := player()
		if p != null and not p.dead and dist_to(p) < 4.0 and rng.randi_range(0, 3) != 0:
			look_at_point(p.eye_position())
			if dist_to(p) < 2.5:
				stop_moving()
				return
		# Ночью почти не выходят.
		if not is_day() and rng.randi_range(0, 3) != 0:
			wander_target = Vector3.INF
			return
		wander(speed * (0.9 if baby else 0.5), 60 if baby else 120)
		if not baby:
			_mate_cd -= TICK
			if _mate_cd <= 0.0:
				_mate_cd = rng.randf_range(60.0, 120.0)
				system.call("villager_mate", self)

	func after_hurt(amount: int, source: String, attacker: Node3D) -> void:
		super.after_hurt(amount, source, attacker)
		panic = 4.0
		if attacker is Player:
			system.call("village_alarm", position, attacker)

	func pose(ph: float, amt: float, hy: float, hp: float, t: float) -> void:
		super.pose(ph, amt, hy, hp, t)

	func save_extra(d: Dictionary) -> void:
		d["prof"] = profession

	func load_extra(d: Dictionary) -> void:
		if d.has("prof"):
			profession = clampi(int(d["prof"]), 0, 4)
			if model != null:
				model.set_skin(0, MobSkins.get_skin("villager_%d" % profession))


## Железный голем (1.2): охраняет жителей, бьёт монстров (подбрасывая их), дарит розы.
class IronGolem extends Mob:
	var player_made := false
	var angry_at_player := 0.0
	var _attack_anim := 0
	var _rose := 0
	var _rose_mesh: MeshInstance3D
	var _retarget := 0.0

	func model_key() -> String:
		return "iron_golem"

	func skin_keys() -> Array:
		return ["iron_golem"]

	func ambient_sound() -> String:
		return ""

	func knockback_scale() -> float:
		return 0.15

	func ai_tick() -> void:
		angry_at_player = maxf(angry_at_player - TICK, 0.0)
		_attack_anim = maxi(_attack_anim - 1, 0)
		if _rose > 0:
			_rose -= 1
			if _rose == 0:
				_show_rose(false)
		_retarget -= TICK
		if _retarget <= 0.0:
			_retarget = 0.5
			if not target_valid(target):
				target = system.call("nearest_monster", position, 16.0, self)
				if target == null and angry_at_player > 0.0:
					var p := player()
					if p != null and target_valid(p) and dist_to(p) < 16.0:
						target = p
		if target_valid(target):
			look_at_point(target_center(target))
			move_to(target.position, speed * 1.1)
			if attack_cd <= 0.0 and can_reach(target, 0.6):
				attack_cd = 1.0
				_attack_anim = 10
				damage_target(target, 7 + rng.randi_range(0, 14))
				if target is Mob:
					(target as Mob).velocity.y += 9.0
				elif target is Player:
					(target as Player).velocity.y += 9.0
				sound("golem")
			return
		target = null
		# Иногда протягивает розу жителю.
		if _rose == 0 and rng.randi_range(0, 1999) == 0:
			var v: Variant = system.call("nearest_mob", position, 8.0, [MobDefs.VILLAGER], self)
			if v != null:
				_rose = 400
				_show_rose(true)
		if _rose > 0:
			var v: Variant = system.call("nearest_mob", position, 8.0, [MobDefs.VILLAGER], self)
			if v != null:
				look_at_point((v as Mob).eye_position())
				turn_to((v as Mob).position - position, 0.2)
			return
		wander(speed * 0.5, 160)

	func _show_rose(v: bool) -> void:
		if model == null:
			return
		model.detach(_rose_mesh)
		_rose_mesh = null
		if v:
			_rose_mesh = model.attach_item("rarm", Blocks.ROSE, 0, Vector3(-11, -27, 3), Vector3(0, 90, 0), 0.6)

	func after_hurt(amount: int, source: String, attacker: Node3D) -> void:
		super.after_hurt(amount, source, attacker)
		if attacker is Player and not player_made:
			angry_at_player = 60.0
			target = attacker
		elif attacker is Mob and attacker != self:
			target = attacker

	func drop_loot(_by_player: bool, _source: String) -> void:
		drop(Items.IRON_INGOT, rng.randi_range(3, 5))
		drop(Blocks.ROSE, rng.randi_range(0, 2))

	func pose(ph: float, amt: float, hy: float, hp: float, _t: float) -> void:
		var c := cos(ph * 0.6662)
		model.rot("head", Vector3(hp, hy, 0))
		model.rot("rleg", Vector3(-1.5 * _tri(ph, 13.0) * amt, 0, 0))
		model.rot("lleg", Vector3(1.5 * _tri(ph, 13.0) * amt, 0, 0))
		if _attack_anim > 0:
			var a := -2.0 + 1.5 * _tri(float(_attack_anim), 10.0)
			model.rot("rarm", Vector3(a, 0, 0))
			model.rot("larm", Vector3(a, 0, 0))
		elif _rose > 0:
			model.rot("rarm", Vector3(-0.8 + 0.025 * _tri(float(_rose), 70.0), 0, 0))
			model.rot("larm", Vector3(0, 0, 0))
		else:
			model.rot("rarm", Vector3((-0.2 + 1.5 * _tri(ph, 13.0)) * amt * 0.6 + c * 0.0, 0, 0))
			model.rot("larm", Vector3((-0.2 - 1.5 * _tri(ph, 13.0)) * amt * 0.6, 0, 0))

	## Треугольная волна (как в модели голема).
	static func _tri(x: float, period: float) -> float:
		return (absf(fposmod(x, period) - period * 0.5) - period * 0.25) / (period * 0.25)

	func save_extra(d: Dictionary) -> void:
		if player_made:
			d["player_made"] = true

	func load_extra(d: Dictionary) -> void:
		player_made = bool(d.get("player_made", false))


## Снежный голем (1.2): кидает снежки в монстров, оставляет снежный след, тает в жаре и под водой.
class SnowGolem extends Mob:
	var _throw := 0.0
	var _retarget := 0.0

	func model_key() -> String:
		return "snow_golem"

	func skin_keys() -> Array:
		return ["snow_golem"]

	func ambient_sound() -> String:
		return ""

	func ai_tick() -> void:
		_throw -= TICK
		_retarget -= TICK
		# Жара (пустыня, джунгли, Нижний мир) растапливает.
		var biome := world.biome_at(floori(position.x), floori(position.z))
		if (world.dimension == -1 or Biomes.temperature(biome) > 1.0) and ticks % 20 == 0:
			hurt(1, "melt", null, Vector3.ZERO)
		if Biomes.temperature(biome) < 0.8 and world.dimension == 0:
			_leave_snow()
		if _retarget <= 0.0:
			_retarget = 0.5
			if not target_valid(target) or dist_to(target) > 16.0:
				target = system.call("nearest_monster", position, 10.0, self)
		if target_valid(target):
			var tc := target_center(target)
			look_at_point(tc)
			turn_to(tc - position, 0.4)
			if dist_to(target) > 8.0:
				move_to(target.position, speed)
			if _throw <= 0.0 and can_see(tc):
				_throw = 1.0
				_snowball(tc)
			return
		target = null
		wander(speed * 0.5)

	func _leave_snow() -> void:
		for i in 4:
			var x := floori(position.x + (float(i % 2 * 2) - 1.0) * 0.25)
			var z := floori(position.z + (float((i >> 1) % 2 * 2) - 1.0) * 0.25)
			var y := floori(position.y + 0.1)
			if world.get_block(x, y, z) == Blocks.AIR and Blocks.is_opaque(world.get_block(x, y - 1, z)):
				world.set_block(x, y, z, Blocks.SNOW_LAYER, 0)

	func _snowball(at: Vector3) -> void:
		var m := manager()
		if m == null:
			return
		var from := eye_position() + facing() * 0.3
		var d := at - from
		var flat := Vector2(d.x, d.z).length()
		var spd := 18.0
		var t := flat / spd
		d.y += 0.5 * 12.0 * t * t
		m.spawn_projectile("snowball", from, d.normalized() * spd, self, 0.0)
		swing = 1.0

	func drop_loot(_by_player: bool, _source: String) -> void:
		drop(Items.SNOWBALL, rng.randi_range(0, 15))

	func pose(_ph: float, _amt: float, hy: float, hp: float, t: float) -> void:
		model.rot("head", Vector3(hp, hy, 0))
		var throw := -sin(swing * PI) * 0.8
		model.rot("rarm", Vector3(0, hy * 0.5, sin(t * 2.0) * 0.05 + throw))
		model.rot("larm", Vector3(0, hy * 0.5, -sin(t * 2.0) * 0.05))
