class_name Mob
extends Node3D
## Существо: физика тела (BodyPhysics), здоровье и урон с неуязвимостью 0,5 с, отбрасывание,
## огонь, лава, утопление, удушье, падение, эффекты зелий; базовый ИИ (блуждание, преследование
## с коротким поиском пути A*, рукопашная атака, бегство); коробочная модель и анимация;
## сохранение в словарь. Логика идёт тиками по 20 в секунду (у каждого существа своя фаза —
## нагрузка распределяется по кадрам), между тиками положение и повороты модели сглаживаются.

const TICK := 0.05
const GRAVITY := 32.0
const JUMP_SPEED := 9.0
const STEP_HEIGHT := 0.55
const MAX_FALL := 60.0
## Сколько узлов проверяет поиск пути (короткие обходы стен, заборов и ям).
const PATH_NODES := 160

var kind := "mob"
var type := 0
var system: Node
var world: World
var model: MobModel
var rng := RandomNumberGenerator.new()

var health := 10
var max_health := 10
var half_w := 0.3
var height := 1.8
## Скорость ходьбы (блоков в секунду).
var speed := 2.0
var attack_damage := 0
var xp_value := 0
var flags := 0
var baby := false
## Секунд до взросления (у детёнышей).
var grow := 0.0
## Не исчезает вдали от игрока.
var persistent := false

var velocity := Vector3.ZERO
var on_ground := false
var in_water := false
var in_lava := false
var head_in_water := false
var hit_wall := false
var fall_dist := 0.0

## Поворот корпуса: смотрит в (sin yaw, 0, cos yaw).
var yaw := 0.0
var head_yaw := 0.0
var head_pitch := 0.0
var prev_pos := Vector3.ZERO
var prev_yaw := 0.0
var prev_head_yaw := 0.0
var prev_head_pitch := 0.0

## Решения ИИ на текущий тик.
var move_dir := Vector3.ZERO
var want_jump := false
var look_pos := Vector3.INF

var hurt_time := 0.0
var invuln := 0.0
var last_damage := 0
var death_time := -1.0
var fire_time := 0.0
var air := 15.0
## Эффекты: id → [уровень, оставшиеся секунды].
var effects: Dictionary = {}
var last_attacker: Node3D
## Секунд с последнего удара игрока (опыт выпадает только если игрок бил недавно).
var player_hurt := 0.0
var removed := false

var target: Node3D
var attack_cd := 0.0
var wander_target := Vector3.INF
var wander_cd := 0.0
var panic := 0.0
var age := 0.0
var path: Array[Vector3] = []
var path_goal := Vector3.INF
var path_cd := 0.0
var stuck_time := 0.0
var ambient_cd := 10.0

var limb_phase := 0.0
var limb_amount := 0.0
var swing := 0.0
var anim_time := 0.0
var tick_acc := 0.0
var ticks := 0

var _light_sky := 1.0
var _light_block := 0.0
var _env_tick := 0
var _fire_tick := 0.0
var _drown_tick := 0.0
var _effect_tick := 0.0
var _lava_tick := 0.0


# --- Создание ----------------------------------------------------------------

## Начальные свойства вида (вызывается системой до добавления в дерево).
func init_type(p_type: int, p_system: Node, p_baby: bool) -> void:
	type = p_type
	system = p_system
	world = p_system.get("world")
	rng.randomize()
	var info := MobDefs.info(type)
	max_health = int(info[1])
	health = max_health
	half_w = float(info[2])
	height = float(info[3])
	speed = float(info[4])
	attack_damage = int(info[5])
	xp_value = int(info[6])
	flags = int(info[8])
	persistent = flags & MobDefs.F_PERSISTENT != 0
	baby = p_baby
	if baby:
		grow = 1200.0
	yaw = rng.randf_range(-PI, PI)
	head_yaw = yaw
	tick_acc = rng.randf_range(0.0, TICK)
	ambient_cd = rng.randf_range(4.0, 20.0)
	_setup()
	_apply_size()


## Особые свойства вида (переопределяется).
func _setup() -> void:
	pass


## Ключ модели и скины по слоям (переопределяется).
func model_key() -> String:
	return "pig"


func skin_keys() -> Array:
	return ["pig"]


func _ready() -> void:
	prev_pos = position
	prev_yaw = yaw
	_build_model()


func _build_model() -> void:
	if model != null and is_instance_valid(model.root):
		model.root.queue_free()
	var skins := []
	for k: String in skin_keys():
		skins.append(MobSkins.get_skin(k))
	model = MobModel.create(model_key(), skins)
	add_child(model.root)
	_after_model()
	_apply_size()
	_update_light(true)


## Дополнительные части модели (предметы в руках и т. п.).
func _after_model() -> void:
	pass


## Размер тела и модели с учётом детёныша.
func _apply_size() -> void:
	var info := MobDefs.info(type)
	var k := 0.5 if baby else 1.0
	half_w = float(info[2]) * k
	height = float(info[3]) * k
	if model != null:
		model.pivot.scale = Vector3.ONE * model_scale()
		model.pivot.position.y = model.ground * model_scale()
		if model.has_part("head"):
			(model.parts["head"] as Node3D).scale = Vector3.ONE * (1.5 if baby else 1.0)


func model_scale() -> float:
	return 0.5 if baby else 1.0


func is_dead() -> bool:
	return death_time >= 0.0 or removed


func has_flag(f: int) -> bool:
	return flags & f != 0


func box() -> AABB:
	return BodyPhysics.body_box(position, half_w, height)


## Габариты для попаданий (у дракона — несколько).
func hit_boxes() -> Array[AABB]:
	return [box()]


func eye_position() -> Vector3:
	return position + Vector3(0, height * 0.85, 0)


func center() -> Vector3:
	return position + Vector3(0, height * 0.5, 0)


func facing() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func manager() -> EntityManager:
	return system.get("manager")


func player() -> Player:
	var m := manager()
	return m.player if m != null else null


func difficulty() -> int:
	var m := manager()
	if m == null or m.game == null:
		return 2
	var d: Variant = m.game.get("difficulty")
	return int(d) if d != null else 2


func is_day() -> bool:
	var m := manager()
	if m == null or m.game == null or not m.game.has_method("is_night"):
		return true
	return not bool(m.game.call("is_night"))


func sound(sound_name: String) -> void:
	system.call("sound", sound_name, position)


func effect(effect_kind: String, data := 0) -> void:
	system.call("effect", effect_kind, center(), data)


# --- Кадр и тик --------------------------------------------------------------

## Вызывается каждый кадр: тики логики (20/с) и сглаженная анимация.
func update_frame(delta: float) -> void:
	tick_acc += delta
	var n := 0
	while tick_acc >= TICK and n < 3:
		tick_acc -= TICK
		n += 1
		tick()
		if removed:
			return
	if tick_acc > TICK:
		tick_acc = 0.0
	animate(delta)


func tick() -> void:
	prev_pos = position
	prev_yaw = yaw
	prev_head_yaw = head_yaw
	prev_head_pitch = head_pitch
	ticks += 1
	age += TICK
	anim_time += TICK
	if death_time >= 0.0:
		death_time += TICK
		velocity.x *= 0.7
		velocity.z *= 0.7
		_physics()
		_update_light(false)
		if death_time >= 1.0:
			effect("smoke")
			system.call("remove_mob", self)
		return
	if grow > 0.0:
		grow -= TICK
		if grow <= 0.0:
			grow = 0.0
			baby = false
			_apply_size()
	hurt_time = maxf(hurt_time - TICK, 0.0)
	invuln = maxf(invuln - TICK, 0.0)
	attack_cd = maxf(attack_cd - TICK, 0.0)
	player_hurt = maxf(player_hurt - TICK, 0.0)
	panic = maxf(panic - TICK, 0.0)
	swing = maxf(swing - TICK * 3.0, 0.0)
	_env_tick += 1
	if _env_tick >= 2:
		_env_tick = 0
		_update_environment()
	_tick_effects()
	_tick_hazards()
	if is_dead():
		return
	move_dir = Vector3.ZERO
	want_jump = false
	look_pos = Vector3.INF
	if system.get("ai_enabled") != false:
		ai_tick()
	_physics()
	_update_look()
	_update_limbs()
	_update_light(false)
	ambient_cd -= TICK
	if ambient_cd <= 0.0:
		ambient_cd = rng.randf_range(8.0, 20.0)
		var s := ambient_sound()
		if s != "":
			sound(s)


## Решения ИИ (переопределяется). По умолчанию — блуждание.
func ai_tick() -> void:
	wander(speed * 0.5)


func ambient_sound() -> String:
	return ""


# --- Физика ------------------------------------------------------------------

func _physics() -> void:
	var dt := TICK
	var spd_mul := 1.0
	if effects.has(Potions.SPEED):
		spd_mul += 0.2 * (int(effects[Potions.SPEED][0]) + 1)
	if effects.has(Potions.SLOWNESS):
		spd_mul = maxf(spd_mul - 0.15 * (int(effects[Potions.SLOWNESS][0]) + 1), 0.0)
	var want := move_dir * spd_mul
	if has_flag(MobDefs.F_FLYING):
		_physics_flying(want)
		return
	if in_water or in_lava:
		var k := 0.35 if in_lava else 0.5
		velocity.x = lerpf(velocity.x, want.x * k, 0.3)
		velocity.z = lerpf(velocity.z, want.z * k, 0.3)
		velocity.y = velocity.y * 0.8 - GRAVITY * 0.2 * dt
		if swims_up():
			velocity.y = minf(velocity.y + 18.0 * dt, 2.5)
	else:
		var accel := 0.55 if on_ground else 0.12
		velocity.x = lerpf(velocity.x, want.x, accel)
		velocity.z = lerpf(velocity.z, want.z, accel)
		velocity.y = maxf((velocity.y - GRAVITY * dt) * 0.98, -MAX_FALL)
		velocity.y = maxf(velocity.y, fall_limit())
	if want_jump and (on_ground or ((in_water or in_lava) and hit_wall)):
		velocity.y = jump_speed() if on_ground else 5.0
		on_ground = false
	if is_climbing():
		velocity.y = maxf(velocity.y, 2.2)
		fall_dist = 0.0
	var motion := velocity * dt
	var res := BodyPhysics.move(world, position, half_w, height, motion, STEP_HEIGHT, on_ground)
	position = res["pos"]
	hit_wall = res["hit_x"] or res["hit_z"]
	if res["hit_x"]:
		velocity.x = 0.0
	if res["hit_z"]:
		velocity.z = 0.0
	var was_ground := on_ground
	on_ground = res["on_ground"] or (was_ground and res["stepped"])
	if res["hit_y"]:
		if velocity.y < 0.0:
			_land()
		velocity.y = 0.0
	if not on_ground and motion.y < 0.0:
		fall_dist -= motion.y
	if in_water or in_lava:
		fall_dist = 0.0
	if position.y < -64.0:
		hurt(4, "void", null, Vector3.ZERO)


## Полёт (гаст, ифрит, дракон): скорость задаётся ИИ напрямую, без тяжести.
func _physics_flying(want: Vector3) -> void:
	velocity = velocity.lerp(want, 0.15)
	var res := BodyPhysics.move(world, position, half_w, height, velocity * TICK, 0.0, false)
	position = res["pos"]
	hit_wall = res["hit_x"] or res["hit_z"] or res["hit_y"]
	on_ground = res["on_ground"]
	if res["hit_x"]:
		velocity.x = 0.0
	if res["hit_y"]:
		velocity.y = 0.0
	if res["hit_z"]:
		velocity.z = 0.0


func jump_speed() -> float:
	return JUMP_SPEED


## Наименьшая скорость падения (курица планирует).
func fall_limit() -> float:
	return -MAX_FALL


## Всплывать в воде (почти все сухопутные существа держатся у поверхности).
func swims_up() -> bool:
	return true


func is_climbing() -> bool:
	if not hit_wall or move_dir.length_squared() < 0.01:
		return false
	var c := Vector3i(floori(position.x), floori(position.y + 0.1), floori(position.z))
	return Blocks.climbable_flags[world.get_block_v(c)] == 1


func _land() -> void:
	if fall_dist > 3.0 and not has_flag(MobDefs.F_NO_FALL):
		hurt(ceili(fall_dist - 3.0), "fall", null, Vector3.ZERO)
	fall_dist = 0.0


# --- Окружение и опасности ---------------------------------------------------

func _update_environment() -> void:
	var fx := floori(position.x)
	var fz := floori(position.z)
	var feet := world.get_block(fx, floori(position.y + 0.2), fz)
	var mid := world.get_block(fx, floori(position.y + height * 0.5), fz)
	in_water = Blocks.is_water(feet) or Blocks.is_water(mid)
	in_lava = Blocks.is_lava(feet) or Blocks.is_lava(mid)
	head_in_water = Blocks.is_water(world.get_block(fx, floori(position.y + height * 0.85), fz))


func _tick_hazards() -> void:
	var immune := has_flag(MobDefs.F_FIRE_IMMUNE) or effects.has(Potions.FIRE_RESISTANCE)
	if in_water:
		fire_time = 0.0
	if in_lava and not immune:
		fire_time = maxf(fire_time, 15.0)
		_lava_tick -= TICK
		if _lava_tick <= 0.0:
			_lava_tick = 0.5
			hurt(4, "lava", null, Vector3.ZERO)
	if _env_tick == 0 and not immune and world.get_block(floori(position.x), floori(position.y + 0.3), floori(position.z)) == Blocks.FIRE:
		fire_time = maxf(fire_time, 8.0)
	if fire_time > 0.0:
		fire_time -= TICK
		if immune:
			fire_time = 0.0
		else:
			_fire_tick -= TICK
			if _fire_tick <= 0.0:
				_fire_tick = 1.0
				hurt(1, "fire", null, Vector3.ZERO)
	# Утопление.
	if head_in_water and not has_flag(MobDefs.F_WATER_BREATHER):
		air -= TICK
		if air <= 0.0:
			_drown_tick -= TICK
			if _drown_tick <= 0.0:
				_drown_tick = 1.0
				hurt(2, "drown", null, Vector3.ZERO)
	else:
		air = 15.0
	# Вода ранит эндерменов, ифритов, снежных големов.
	if has_flag(MobDefs.F_WATER_HURTS) and in_water and ticks % 10 == 0:
		hurt(1, "drown", null, Vector3.ZERO)
	# Удушье в блоке и кактус.
	if ticks % 10 == 0:
		var head := Vector3i(floori(position.x), floori(position.y + height * 0.85), floori(position.z))
		if Blocks.is_opaque(world.get_block_v(head)) and not has_flag(MobDefs.F_FLYING):
			hurt(1, "suffocate", null, Vector3.ZERO)
		var b := box().grow(0.05)
		for c in _cells(b):
			if world.get_block_v(c) == Blocks.CACTUS:
				hurt(1, "cactus", null, Vector3.ZERO)
				break
	# Солнце сжигает зомби и скелетов.
	if has_flag(MobDefs.F_SUN_BURN) and ticks % 5 == 0 and _sun_exposed() and rng.randi_range(0, 4) == 0:
		fire_time = maxf(fire_time, 8.0)


func _sun_exposed() -> bool:
	if world.dimension != 0 or in_water or not is_day():
		return false
	var m := manager()
	if m != null and m.logic != null and m.logic.raining:
		return false
	var head := Vector3i(floori(position.x), floori(position.y + height * 0.85), floori(position.z))
	return world.get_sky_light(head) >= 15


func _cells(b: AABB) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for y in range(floori(b.position.y), floori(b.end.y) + 1):
		for z in range(floori(b.position.z), floori(b.end.z) + 1):
			for x in range(floori(b.position.x), floori(b.end.x) + 1):
				out.append(Vector3i(x, y, z))
	return out


# --- Эффекты -----------------------------------------------------------------

func is_undead() -> bool:
	return has_flag(MobDefs.F_UNDEAD)


func add_effect(id: int, level: int, seconds: float) -> void:
	if is_dead():
		return
	var undead := is_undead()
	if id == Potions.INSTANT_HEALTH:
		if undead:
			hurt(6 << level, "magic", null, Vector3.ZERO)
		else:
			heal(4 << level)
		return
	if id == Potions.INSTANT_DAMAGE:
		if undead:
			heal(6 << level)
		else:
			hurt(6 << level, "magic", null, Vector3.ZERO)
		return
	if (id == Potions.POISON or id == Potions.REGENERATION) and undead:
		return
	if id == Potions.POISON and has_flag(MobDefs.F_ARTHROPOD):
		return
	var cur: Array = effects.get(id, [-1, 0.0])
	if level > int(cur[0]) or (level == int(cur[0]) and seconds > float(cur[1])):
		effects[id] = [level, seconds]


func _tick_effects() -> void:
	if effects.is_empty():
		return
	_effect_tick += TICK
	var expired := []
	for e: int in effects:
		var rec: Array = effects[e]
		rec[1] = float(rec[1]) - TICK
		if float(rec[1]) <= 0.0:
			expired.append(e)
	for e: int in expired:
		effects.erase(e)
	if _effect_tick >= 1.25:
		_effect_tick = 0.0
		if effects.has(Potions.POISON) and health > 1:
			hurt(1, "poison", null, Vector3.ZERO, true)
		if effects.has(Potions.REGENERATION):
			heal(1)


func heal(amount: int) -> void:
	if is_dead():
		return
	health = mini(health + amount, max_health)


# --- Урон и смерть -----------------------------------------------------------

## Урон. kb — направление отбрасывания (длина — сила, блоков/с). true — урон прошёл.
func hurt(amount: int, source: String, attacker: Node3D, kb: Vector3, ignore_invuln := false) -> bool:
	if is_dead():
		return false
	if source in ["fire", "lava"] and (has_flag(MobDefs.F_FIRE_IMMUNE) or effects.has(Potions.FIRE_RESISTANCE)):
		return false
	if source == "fall" and has_flag(MobDefs.F_NO_FALL):
		return false
	if not on_hurt(amount, source, attacker):
		return false
	amount = _apply_armor(amount, source)
	if not ignore_invuln and invuln > 0.0:
		if amount <= last_damage:
			return false
		var extra := amount - last_damage
		last_damage = amount
		amount = extra
	else:
		last_damage = amount
		invuln = 0.5
	var p := player()
	if attacker != null and attacker == p:
		player_hurt = 5.0
	if attacker != null:
		last_attacker = attacker
	if kb != Vector3.ZERO and knockback_scale() > 0.0:
		var k := kb * knockback_scale()
		velocity.x = velocity.x * 0.5 + k.x
		velocity.z = velocity.z * 0.5 + k.z
		if not has_flag(MobDefs.F_FLYING):
			velocity.y = minf(velocity.y * 0.5 + 5.5 * knockback_scale(), 8.0)
		else:
			velocity.y += k.y
		on_ground = false
	if amount <= 0:
		return true
	health -= amount
	hurt_time = 0.5
	after_hurt(amount, source, attacker)
	if health <= 0:
		health = 0
		die(source, attacker)
	else:
		sound("mob_hurt")
	return true


## Защита (зомби 2 очка, магмовый куб — по размеру).
func armor() -> int:
	return 0


func _apply_armor(amount: int, source: String) -> int:
	var a := armor()
	if a <= 0 or source in ["fall", "void", "drown", "starve", "magic", "poison", "fire", "suffocate"]:
		return amount
	return maxi(int(round(amount * (25.0 - a) / 25.0)), 1 if amount > 0 else 0)


func knockback_scale() -> float:
	return 1.0


## Перед уроном: false — урон отменён (эндермен уклоняется от стрел и т. п.).
func on_hurt(_amount: int, _source: String, _attacker: Node3D) -> bool:
	return true


## После урона: злость, паника, телепортация.
func after_hurt(_amount: int, _source: String, attacker: Node3D) -> void:
	if attacker != null and attacker != self:
		on_attacked_by(attacker)


func on_attacked_by(_attacker: Node3D) -> void:
	pass


func die(source: String, attacker: Node3D) -> void:
	if death_time >= 0.0:
		return
	death_time = 0.0
	hurt_time = 0.5
	move_dir = Vector3.ZERO
	velocity = Vector3(0, minf(velocity.y, 2.0), 0)
	sound("mob_death")
	var m := manager()
	if m == null:
		return
	if not baby:
		drop_loot(attacker == player() or player_hurt > 0.0, source)
		if xp_value > 0 and (attacker == player() or player_hurt > 0.0):
			m.spawn_xp(center(), xp_value)
	on_death(source, attacker)


## Добыча при смерти (переопределяется). by_player — убит игроком.
func drop_loot(_by_player: bool, _source: String) -> void:
	pass


func on_death(_source: String, _attacker: Node3D) -> void:
	pass


func drop(id: int, count: int, data := 0) -> void:
	if count <= 0:
		return
	var m := manager()
	if m != null:
		m.spawn_drop(id, count, data, center())


func burning() -> bool:
	return fire_time > 0.0


# --- Цели ---------------------------------------------------------------------

## Цель жива и досягаема (игрок не в творческом режиме).
func target_valid(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or t.is_queued_for_deletion():
		return false
	if t is Player:
		var p := t as Player
		return not p.dead and not p.creative
	if t is Mob:
		return not (t as Mob).is_dead()
	return false


func target_box(t: Node3D) -> AABB:
	if t is Player:
		return (t as Player).body_box()
	if t is Mob:
		return (t as Mob).box()
	return AABB(t.position, Vector3.ONE * 0.5)


func target_center(t: Node3D) -> Vector3:
	var b := target_box(t)
	return b.get_center()


## Нанести удар цели (игроку — через take_damage со сложностью, существу — hurt).
func damage_target(t: Node3D, amount: int, source := "mob") -> void:
	if t is Player:
		(t as Player).take_damage(amount, source, self)
		system.call("player_attacked_by", self)
	elif t is Mob:
		var dir := t.position - position
		dir.y = 0.0
		var kb := dir.normalized() * 6.0 if dir.length_squared() > 0.0001 else Vector3.ZERO
		(t as Mob).hurt(amount, source, self, kb)


## В пределах удара: центры близко по горизонтали, тела пересекаются по высоте.
func can_reach(t: Node3D, extra := 0.0) -> bool:
	var tb := target_box(t)
	var mb := box()
	if tb.end.y < mb.position.y - 0.2 or tb.position.y > mb.end.y + 0.2:
		return false
	var tc := tb.get_center()
	var reach := half_w * 2.0 + tb.size.x * 0.5 + 0.45 + extra
	return Vector2(tc.x - position.x, tc.z - position.z).length() <= reach


## Рукопашная атака с перезарядкой 1 с.
func melee(t: Node3D, amount: int, cooldown := 1.0) -> bool:
	if attack_cd > 0.0 or not can_reach(t):
		return false
	attack_cd = cooldown
	swing = 1.0
	if effects.has(Potions.STRENGTH):
		amount += 3 << int(effects[Potions.STRENGTH][0])
	if effects.has(Potions.WEAKNESS):
		amount -= 2
	damage_target(t, maxi(amount, 0))
	return true


## Видна ли точка из глаз (луч по блокам).
func can_see(p: Vector3) -> bool:
	var from := eye_position()
	var d := p - from
	var dist := d.length()
	if dist < 0.5:
		return true
	var hit := world.raycast(from, d / dist, dist)
	if hit.is_empty():
		return true
	var b := int(hit["block"])
	if not Blocks.is_solid(b) and not Blocks.is_opaque(b):
		return true
	return from.distance_to(hit["hit"]) >= dist - 0.3


func can_see_target(t: Node3D) -> bool:
	if t is Player:
		return can_see((t as Player).eye_position())
	return can_see(target_center(t))


func dist_to(t: Node3D) -> float:
	return position.distance_to(t.position)


## Игрок, на которого можно нападать (живой, не в творческом режиме), ближе r.
func hostile_player_near(r: float, need_sight := true) -> Player:
	var p := player()
	if p == null or not target_valid(p):
		return null
	if position.distance_to(p.position) > r:
		return null
	if need_sight and not can_see(p.eye_position()):
		return null
	return p


# --- Движение ИИ ---------------------------------------------------------------

static func yaw_of(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)


## Поворачивать корпус к направлению не быстрее max_step радиан за тик.
func turn_to(dir: Vector3, max_step := 0.5) -> void:
	if Vector2(dir.x, dir.z).length_squared() < 1e-6:
		return
	var t := yaw_of(dir)
	var d := wrapf(t - yaw, -PI, PI)
	yaw = wrapf(yaw + clampf(d, -max_step, max_step), -PI, PI)


func look_at_point(p: Vector3) -> void:
	look_pos = p


func _update_look() -> void:
	if look_pos == Vector3.INF:
		head_yaw = lerp_angle(head_yaw, yaw, 0.3)
		head_pitch = lerpf(head_pitch, 0.0, 0.3)
		return
	var d := look_pos - eye_position()
	var want := yaw_of(d)
	var rel := clampf(wrapf(want - yaw, -PI, PI), -1.3, 1.3)
	head_yaw = lerp_angle(head_yaw, yaw + rel, 0.5)
	var hd := Vector2(d.x, d.z).length()
	head_pitch = lerpf(head_pitch, clampf(atan2(-d.y, hd), -0.9, 0.9), 0.5)


## Идти в точку со скоростью spd (обходя препятствия по найденному пути).
func move_to(goal: Vector3, spd: float) -> void:
	var to := goal - position
	var flat := Vector2(to.x, to.z).length()
	var use_path := hit_wall or stuck_time > 0.6 or absf(to.y) > 1.6
	path_cd -= TICK
	if use_path and flat > 1.2:
		if (path.is_empty() or path_goal.distance_to(goal) > 2.0 or stuck_time > 1.5) and path_cd <= 0.0 \
				and int(system.get("path_budget")) > 0:
			system.set("path_budget", int(system.get("path_budget")) - 1)
			path_cd = rng.randf_range(0.8, 1.4)
			path = _find_path(goal)
			path_goal = goal
			stuck_time = 0.0
	var aim := goal
	while not path.is_empty():
		var n: Vector3 = path[0]
		if Vector2(n.x - position.x, n.z - position.z).length() < 0.35 and absf(n.y - position.y) < 1.3:
			path.remove_at(0)
			continue
		aim = n
		break
	if path.is_empty() and flat < 0.25:
		return
	var dir := aim - position
	var hdir := Vector3(dir.x, 0, dir.z)
	if hdir.length_squared() < 1e-4:
		return
	hdir = hdir.normalized()
	move_dir = hdir * spd
	turn_to(hdir)
	# Прыжок через блок впереди.
	if on_ground and (hit_wall or (aim.y > position.y + 0.6 and Vector2(dir.x, dir.z).length() < 1.6)):
		if _block_ahead(hdir):
			want_jump = true
	if (in_water or in_lava) and (hit_wall or aim.y > position.y + 0.3):
		want_jump = true
	# Застревание.
	var moved := Vector2(position.x - prev_pos.x, position.z - prev_pos.z).length()
	if moved < spd * TICK * 0.25:
		stuck_time += TICK
	else:
		stuck_time = maxf(stuck_time - TICK * 2.0, 0.0)


## Впереди препятствие высотой в блок, через которое можно перепрыгнуть.
func _block_ahead(dir: Vector3) -> bool:
	var p := position + dir * (half_w + 0.45)
	var c := Vector3i(floori(p.x), floori(position.y + 0.1), floori(p.z))
	var b := world.get_block_v(c)
	if not Blocks.is_solid(b):
		return hit_wall
	if Blocks.is_fence_like(b):
		return false
	var above := world.get_block_v(c + Vector3i(0, 1, 0))
	var above2 := world.get_block_v(c + Vector3i(0, 2, 0))
	return not Blocks.is_solid(above) and (height <= 1.0 or not Blocks.is_solid(above2))


func stop_moving() -> void:
	move_dir = Vector3.ZERO
	path.clear()


## Случайное блуждание: изредка выбирает точку в радиусе 10 блоков.
func wander(spd: float, chance := 120) -> void:
	wander_cd -= TICK
	if wander_target == Vector3.INF:
		if wander_cd <= 0.0 and rng.randi_range(0, chance) == 0:
			wander_target = _pick_wander_spot(10, 7)
			wander_cd = rng.randf_range(2.0, 6.0)
		return
	move_to(wander_target, spd)
	if Vector2(wander_target.x - position.x, wander_target.z - position.z).length() < 0.6 or stuck_time > 2.5:
		wander_target = Vector3.INF
		path.clear()
		stuck_time = 0.0


## Точка для блуждания: несколько случайных клеток, лучшая по оценке wander_weight.
func _pick_wander_spot(r: int, ry: int) -> Vector3:
	var best := Vector3.INF
	var best_w := -INF
	for i in 10:
		var c := Vector3i(floori(position.x) + rng.randi_range(-r, r), floori(position.y) + rng.randi_range(-ry, ry),
			floori(position.z) + rng.randi_range(-r, r))
		# Опускаемся на опору.
		var k := 0
		while k < 8 and c.y > 0 and not Blocks.is_solid(world.get_block_v(c + Vector3i(0, -1, 0))) \
				and not Blocks.is_liquid(world.get_block_v(c)):
			c.y -= 1
			k += 1
		if Blocks.is_solid(world.get_block_v(c)) or not world.is_loaded(c):
			continue
		var w := wander_weight(c)
		if w > best_w:
			best_w = w
			best = Vector3(c.x + 0.5, c.y, c.z + 0.5)
	return best


## Предпочтение места блуждания: животные любят траву и свет, монстры — темноту.
func wander_weight(c: Vector3i) -> float:
	var below := world.get_block_v(c + Vector3i(0, -1, 0))
	if Blocks.is_lava(world.get_block_v(c)) or below == Blocks.LAVA or below == Blocks.FIRE:
		return -100.0
	if MobDefs.category(type) == MobDefs.CAT_MONSTER:
		return 0.5 - float(maxi(world.get_block_light(c), world.get_sky_light(c))) / 15.0
	if below == Blocks.GRASS:
		return 10.0
	return float(world.get_sky_light(c)) / 15.0 - (5.0 if Blocks.is_water(world.get_block_v(c)) else 0.0)


## Убегать от точки.
func flee_from(p: Vector3, spd: float) -> void:
	var away := position - p
	away.y = 0.0
	if away.length_squared() < 1e-4:
		away = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
	away = away.normalized()
	if wander_target == Vector3.INF or wander_target.distance_to(position) < 1.0 or stuck_time > 1.0:
		var goal := position + away.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6)) * 8.0
		wander_target = _pick_near(goal)
		stuck_time = 0.0
	move_to(wander_target, spd)


func _pick_near(goal: Vector3) -> Vector3:
	var c := Vector3i(floori(goal.x), floori(position.y) + 3, floori(goal.z))
	for k in 8:
		if Blocks.is_solid(world.get_block_v(c + Vector3i(0, -1, 0))) and not Blocks.is_solid(world.get_block_v(c)):
			break
		c.y -= 1
	return Vector3(c.x + 0.5, c.y, c.z + 0.5)


# --- Поиск пути --------------------------------------------------------------------

func _passable(c: Vector3i) -> bool:
	var b := world.get_block_v(c)
	if b == Blocks.AIR:
		return true
	if Blocks.is_lava(b) or b == Blocks.FIRE or b == Blocks.CACTUS:
		return false
	return not Blocks.is_solid(b)


func _standable(c: Vector3i, h: int) -> bool:
	var below := world.get_block_v(c + Vector3i(0, -1, 0))
	var here := world.get_block_v(c)
	if Blocks.is_water(here):
		pass
	elif not Blocks.is_solid(below) or Blocks.is_fence_like(below) or below == Blocks.CACTUS:
		return false
	for i in h:
		if not _passable(c + Vector3i(0, i, 0)):
			return false
	return true


## A* по клеткам: шаг, подъём на блок, спуск до 3 блоков. Не дальше PATH_NODES узлов.
func _find_path(goal: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var h := maxi(ceili(height - 0.05), 1)
	var start := Vector3i(floori(position.x), floori(position.y + 0.1), floori(position.z))
	var g := Vector3i(floori(goal.x), floori(goal.y + 0.1), floori(goal.z))
	var open: Array = [start]
	var came := {start: start}
	var cost := {start: 0.0}
	var best := start
	var best_h := INF
	var expanded := 0
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	while not open.is_empty() and expanded < PATH_NODES:
		# Узел с наименьшей оценкой.
		var bi := 0
		var bf := INF
		for i in open.size():
			var n: Vector3i = open[i]
			var f: float = float(cost[n]) + _heur(n, g)
			if f < bf:
				bf = f
				bi = i
		var cur: Vector3i = open[bi]
		open.remove_at(bi)
		expanded += 1
		var hh := _heur(cur, g)
		if hh < best_h:
			best_h = hh
			best = cur
		if cur == g or hh < 1.0:
			best = cur
			break
		for d: Vector3i in dirs:
			var n := cur + d
			var step_cost := 1.0
			if not _standable(n, h):
				# Подъём на блок.
				if _standable(n + Vector3i(0, 1, 0), h) and _passable(cur + Vector3i(0, h, 0)):
					n += Vector3i(0, 1, 0)
					step_cost = 2.0
				else:
					var found := false
					if _passable(n) and _passable(n + Vector3i(0, h - 1, 0)):
						for k in range(1, 4):
							var q := n - Vector3i(0, k, 0)
							if _standable(q, h):
								n = q
								step_cost = 1.0 + k * 0.4
								found = true
								break
							if not _passable(q):
								break
					if not found:
						continue
			var nc: float = float(cost[cur]) + step_cost
			if not cost.has(n) or nc < float(cost[n]):
				cost[n] = nc
				came[n] = cur
				if not open.has(n):
					open.append(n)
	if best == start:
		return out
	var node := best
	var rev: Array[Vector3] = []
	while node != start:
		rev.append(Vector3(node.x + 0.5, node.y, node.z + 0.5))
		node = came[node]
	rev.reverse()
	return rev


static func _heur(a: Vector3i, b: Vector3i) -> float:
	return absf(a.x - b.x) + absf(a.z - b.z) + absf(a.y - b.y) * 1.5


# --- Свет и анимация -----------------------------------------------------------

func _update_light(force: bool) -> void:
	if model == null:
		return
	if not force and ticks % 4 != 0 and hurt_time <= 0.0 and death_time < 0.0:
		return
	if force or ticks % 4 == 0:
		var c := Vector3i(floori(position.x), floori(position.y + minf(height * 0.6, 1.5)), floori(position.z))
		_light_sky = float(world.get_sky_light(c)) / 15.0
		_light_block = ChunkMesher.block_curve[clampi(world.get_block_light(c), 0, 15)]
		if world.dimension == -1:
			_light_block = maxf(_light_block, 0.42)
		elif world.dimension == 1:
			_light_block = maxf(_light_block, 0.5)
		if burning():
			_light_block = maxf(_light_block, 0.9)
	var hurt_v := 1.0 if hurt_time > 0.3 or death_time >= 0.0 else 0.0
	model.set_light(_light_sky, _light_block, hurt_v)


func _update_limbs() -> void:
	var d := Vector2(position.x - prev_pos.x, position.z - prev_pos.z).length() * 4.0
	limb_amount += (minf(d, 1.0) - limb_amount) * 0.4
	limb_phase += limb_amount


## Сглаженная поза модели между тиками.
func animate(_delta: float) -> void:
	if model == null:
		return
	var a := clampf(tick_acc / TICK, 0.0, 1.0)
	model.root.position = (prev_pos - position) * (1.0 - a)
	var ry := lerp_angle(prev_yaw, yaw, a)
	model.root.rotation.y = ry
	var hy := wrapf(lerp_angle(prev_head_yaw, head_yaw, a) - ry, -PI, PI)
	var hp := lerpf(prev_head_pitch, head_pitch, a)
	var ph := limb_phase + limb_amount * a
	if death_time >= 0.0:
		model.pivot.rotation.z = minf(death_time * 1.6, 1.0) * PI * 0.5
	pose(ph, limb_amount, hy, hp, anim_time + a * TICK)


## Поза частей (по семейству моделей). ph — фаза шага, amt — размах (0–1), hy/hp — голова.
func pose(ph: float, amt: float, hy: float, hp: float, t: float) -> void:
	var c := cos(ph * 0.6662)
	var s := cos(ph * 0.6662 + PI)
	match model.key:
		"biped", "skeleton", "giant":
			model.rot("head", Vector3(hp, hy, 0))
			model.rot("rleg", Vector3(c * 1.4 * amt, 0, 0))
			model.rot("lleg", Vector3(s * 1.4 * amt, 0, 0))
			model.rot("rarm", Vector3(s * amt, 0, 0.05 + sin(t * 1.3) * 0.05))
			model.rot("larm", Vector3(c * amt, 0, -0.05 - sin(t * 1.3) * 0.05))
		"pig", "cow", "sheep":
			model.rot("head", Vector3(hp, hy, 0))
			model.rot("leg1", Vector3(c * 1.4 * amt, 0, 0))
			model.rot("leg2", Vector3(s * 1.4 * amt, 0, 0))
			model.rot("leg3", Vector3(s * 1.4 * amt, 0, 0))
			model.rot("leg4", Vector3(c * 1.4 * amt, 0, 0))
		"creeper":
			model.rot("head", Vector3(hp, hy, 0))
			model.rot("leg1", Vector3(c * 1.4 * amt, 0, 0))
			model.rot("leg2", Vector3(s * 1.4 * amt, 0, 0))
			model.rot("leg3", Vector3(s * 1.4 * amt, 0, 0))
			model.rot("leg4", Vector3(c * 1.4 * amt, 0, 0))
		"chicken":
			model.rot("head", Vector3(hp, hy, 0))
			model.rot("rleg", Vector3(c * 1.4 * amt, 0, 0))
			model.rot("lleg", Vector3(s * 1.4 * amt, 0, 0))
			var flap := 0.0 if on_ground else sin(t * 30.0) * 0.6 + 0.6
			model.rot("rwing", Vector3(0, 0, -flap))
			model.rot("lwing", Vector3(0, 0, flap))
		"spider":
			model.rot("head", Vector3(hp, hy, 0))
			for i in 4:
				var k := float(i)
				var ya := -cos(ph * 0.6662 * 2.0 + k * PI * 0.5 + (PI if i % 2 == 1 else 0.0)) * 0.4 * amt
				var za := absf(sin(ph * 0.6662 + k * PI * 0.5)) * 0.4 * amt
				model.rot("leg%d" % (i * 2 + 1), Vector3(0, ya, za))
				model.rot("leg%d" % (i * 2 + 2), Vector3(0, -ya, -za))
		"villager":
			model.rot("head", Vector3(hp, hy, 0))
			model.rot("rleg", Vector3(c * 1.4 * amt * 0.5, 0, 0))
			model.rot("lleg", Vector3(s * 1.4 * amt * 0.5, 0, 0))
		"enderman":
			model.rot("head", Vector3(hp, hy, 0))
			model.rot("jaw", Vector3(hp, hy, 0))
			model.rot("rleg", Vector3(clampf(c * 1.4 * amt * 0.5, -0.4, 0.4), 0, 0))
			model.rot("lleg", Vector3(clampf(s * 1.4 * amt * 0.5, -0.4, 0.4), 0, 0))
			model.rot("rarm", Vector3(clampf(s * amt * 0.5, -0.4, 0.4), 0, 0.05))
			model.rot("larm", Vector3(clampf(c * amt * 0.5, -0.4, 0.4), 0, -0.05))
		"silverfish":
			for i in 7:
				model.rot("s%d" % i, Vector3(0, cos(t * 18.0 + i * 0.45) * 0.05 * PI * (1 + absi(i - 2)), 0))
				model.shift("s%d" % i, Vector3(sin(t * 18.0 + i * 0.45) * PI * 0.2 * absi(i - 2), 0, 0))
			for i in 3:
				var seg: int = [2, 4, 1][i]
				model.rot("f%d" % i, Vector3(0, cos(t * 18.0 + seg * 0.45) * 0.05 * PI * (1 + absi(seg - 2)), 0))
				model.shift("f%d" % i, Vector3(sin(t * 18.0 + seg * 0.45) * PI * 0.2 * absi(seg - 2), 0, 0))


# --- Взаимодействие ---------------------------------------------------------------

## Правая кнопка игрока (переопределяется). true — действие выполнено.
func interact(_p: Player) -> bool:
	return false


## Расходовать предмет в руке игрока (кроме творческого режима).
func consume_held(p: Player, n := 1) -> void:
	if not p.creative:
		p.inventory.consume_selected(n)


# --- Сохранение -----------------------------------------------------------------

func to_dict() -> Dictionary:
	var d := {"kind": "mob", "type": type, "pos": [snappedf(position.x, 0.01), snappedf(position.y, 0.01), snappedf(position.z, 0.01)],
		"yaw": snappedf(yaw, 0.01), "health": health}
	if baby:
		d["grow"] = grow
	if fire_time > 0.0:
		d["fire"] = fire_time
	if persistent and not has_flag(MobDefs.F_PERSISTENT):
		d["persistent"] = true
	save_extra(d)
	return d


func from_dict(d: Dictionary) -> void:
	yaw = float(d.get("yaw", yaw))
	head_yaw = yaw
	if d.has("grow") and float(d["grow"]) > 0.0:
		baby = true
		grow = float(d["grow"])
	fire_time = float(d.get("fire", 0.0))
	if bool(d.get("persistent", false)):
		persistent = true
	load_extra(d)
	health = clampi(int(d.get("health", max_health)), 1, max_health)
	_apply_size()


## Дополнительные поля вида (переопределяются).
func save_extra(_d: Dictionary) -> void:
	pass


func load_extra(_d: Dictionary) -> void:
	pass
