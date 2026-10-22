class_name Player
extends Node3D
## Игрок от первого лица: собственная воксельная физика, полёт, плавание, лестницы;
## здоровье, голод, воздух, опыт, броня, эффекты; добыча блоков инструментами, установка
## и использование предметов (через PlayerActions). Управление — мышь/клавиатура и сенсор.

signal health_changed(health: int)
signal damaged(amount: int)
signal died
signal stats_changed
signal block_broken(pos: Vector3i, block_id: int, meta: int)
signal block_placed(pos: Vector3i, block_id: int)
signal flying_changed(flying: bool)

const HALF_WIDTH := 0.3
const HEIGHT := 1.8
const EYE_HEIGHT := 1.62
const SNEAK_EYE_HEIGHT := 1.42
const GRAVITY := 30.0
const JUMP_VELOCITY := 8.7
const WALK_SPEED := 4.3
const SPRINT_SPEED := 5.6
const SNEAK_SPEED := 1.3
const FLY_SPEED := 10.9
const FLY_SPRINT_SPEED := 21.6
const MAX_FALL_SPEED := 60.0
const CLIMB_SPEED := 2.4
const STEP_HEIGHT := 0.5
const REACH := 5.0
const CREATIVE_REACH := 5.0
const MAX_HEALTH := 20
const MAX_FOOD := 20
const MAX_AIR := 300
const EPS := 0.001
const DOUBLE_TAP := 0.3
const CREATIVE_BREAK_DELAY := 0.22
const PLACE_DELAY := 0.22
const EAT_TIME := 1.6
const HAND_POS := Vector3(0.56, -0.48, -0.82)
const HAND_ROT := Vector3(0.0, 0.733, 0.0)
const ITEM_HAND_POS := Vector3(0.5, -0.42, -0.7)
const ITEM_HAND_ROT := Vector3(0.0, -1.2, 0.35)

var world: World
var inventory := Inventory.new()
## Обработчик действий (атака, использование, взаимодействие с блоками) — игровая сцена.
var actions: Object
var camera: Camera3D
var hand: MeshInstance3D

var creative := true
var flying := false
var velocity := Vector3.ZERO
var on_ground := false
var in_water := false
var in_lava := false
var head_in_water := false
var on_ladder := false
var in_web := false
var sneaking := false
var sprinting := false
var yaw := 0.0
var pitch := 0.0
var health := MAX_HEALTH
var food := MAX_FOOD
var saturation := 5.0
var exhaustion := 0.0
var air := MAX_AIR
var xp_level := 0
var xp_progress := 0.0
var xp_total := 0
## Эффекты: id → [уровень, оставшиеся секунды].
var effects: Dictionary = {}
var fire_time := 0.0
var dead := false
var spawn_point := Vector3.ZERO
## Сложность: 0 мирная, 1 лёгкая, 2 нормальная, 3 сложная.
var difficulty := 2
## Пока чанк под игроком не загружен, физика заморожена.
var frozen := true
var controls_enabled := true
var auto_jump := false
var base_fov := 75.0
var mouse_sensitivity := 0.15
## Обзор мышью без захвата курсора (запасной вариант, если браузер не дал захватить мышь).
var free_look := false
## Сразу после захвата мыши браузер может прислать «скачок» на сотни пикселей — такие события пропускаем.
const MAX_MOUSE_STEP := 250.0
## Chrome с захваченным курсором иногда присылает одиночный ложный скачок посреди обычного
## движения — пропускаем событие, если оно резко больше недавних.
const MOUSE_SPIKE_MIN := 90.0
const MOUSE_SPIKE_RATIO := 6.0
var _was_captured := false
var _skip_motion := 0
var _mouse_avg := 0.0

# Сенсорный ввод (выставляется TouchControls).
var touch_move := Vector2.ZERO
var touch_jump := false
var touch_sneak := false
var touch_sprint := false
var touch_break := false
var touch_place := false
# Мышь.
var mouse_break := false
var mouse_place := false

## Текущий блок под прицелом: {pos, normal, block, meta, hit} или пустой словарь.
var target: Dictionary = {}
var break_progress := 0.0
var break_pos := Vector3i(0, -1000, 0)
## Прогресс поедания (0..1) и натяжения лука (секунды).
var eat_progress := 0.0
var bow_charge := 0.0
var sleeping := false

var _move_input := Vector2.ZERO
var _jump_held := false
var _fly_down := false
var _sprint_latched := false
var _break_cooldown := 0.0
var _place_cooldown := 0.0
var _place_queued := false
var _primary_was := false
var _use_was := false
var _auto_eat := false
var _last_jump_time := -10.0
var _last_forward_time := -10.0
var _fall_start := 0.0
var _regen := 0.0
var _starve := 0.0
var _drown := 0.0
var _fire_tick := 0.0
var _effect_tick := 0.0
var _invulnerable := 0.0
var _last_damage := 0
var _swing := 0.0
var _bob := 0.0
var _hit_wall := false
var _hand_key := -1
var _last_pos := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, EYE_HEIGHT, 0)
	camera.near = 0.05
	camera.fov = base_fov
	add_child(camera)
	hand = MeshInstance3D.new()
	hand.material_override = TextureFactory.hand_material
	hand.scale = Vector3.ONE * 0.3
	hand.position = HAND_POS
	hand.rotation = HAND_ROT
	hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(hand)
	_fall_start = position.y
	_last_pos = position
	_rng.randomize()


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- Ввод ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or dead or frozen:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _mouse_active() and mm.device != InputEvent.DEVICE_ID_EMULATION:
			if _skip_motion > 0:
				_skip_motion -= 1
			elif _accept_mouse_step(mm.relative.length()):
				rotate_view(-mm.relative.x * mouse_sensitivity, -mm.relative.y * mouse_sensitivity)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Касания экрана эмулируют мышь — их обрабатывает TouchControls.
		if mb.device == InputEvent.DEVICE_ID_EMULATION or not _mouse_active():
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				mouse_break = mb.pressed
				if mb.pressed:
					_break_cooldown = 0.0
			MOUSE_BUTTON_RIGHT:
				mouse_place = mb.pressed
				if mb.pressed:
					_place_cooldown = 0.0
					_place_queued = true
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					pick_block()
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					inventory.select(inventory.selected - 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					inventory.select(inventory.selected + 1)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_9:
			inventory.select(k.physical_keycode - KEY_1)
		elif k.is_action("jump"):
			on_jump_pressed()
		elif k.is_action("move_forward"):
			if now() - _last_forward_time < DOUBLE_TAP:
				_sprint_latched = true
			_last_forward_time = now()


func _mouse_active() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or free_look


func _accept_mouse_step(step: float) -> bool:
	if step > MAX_MOUSE_STEP:
		return false
	if step > MOUSE_SPIKE_MIN and step > _mouse_avg * MOUSE_SPIKE_RATIO:
		# Если это начало настоящего быстрого движения, следующие такие же шаги уже пройдут.
		_mouse_avg = step / MOUSE_SPIKE_RATIO * 1.2
		return false
	_mouse_avg = lerpf(_mouse_avg, step, 0.25)
	return true


func rotate_view(yaw_deg: float, pitch_deg: float) -> void:
	yaw = wrapf(yaw + deg_to_rad(yaw_deg), -PI, PI)
	pitch = clampf(pitch + deg_to_rad(pitch_deg), deg_to_rad(-89.0), deg_to_rad(89.0))


func set_look(p_yaw: float, p_pitch: float) -> void:
	yaw = p_yaw
	pitch = clampf(p_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
	_apply_rotation()


## Горизонтальное направление взгляда: 0 юг (+Z), 1 запад (-X), 2 север (-Z), 3 восток (+X).
func facing() -> int:
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	if absf(f.x) > absf(f.z):
		return 3 if f.x > 0.0 else 1
	return 0 if f.z > 0.0 else 2


func look_dir() -> Vector3:
	return -camera.global_transform.basis.z


func eye_position() -> Vector3:
	return camera.global_position


## Двойное нажатие прыжка в креативе включает/выключает полёт.
func on_jump_pressed() -> void:
	if not creative:
		return
	var t := now()
	if t - _last_jump_time < DOUBLE_TAP:
		set_flying(not flying)
		_last_jump_time = -10.0
	else:
		_last_jump_time = t


func set_flying(value: bool) -> void:
	value = value and creative
	if value == flying:
		return
	flying = value
	velocity.y = 0.0
	_fall_start = position.y
	flying_changed.emit(flying)


func queue_place() -> void:
	_place_queued = true


func release_all_input() -> void:
	touch_move = Vector2.ZERO
	touch_jump = false
	touch_sneak = false
	touch_sprint = false
	touch_break = false
	touch_place = false
	mouse_break = false
	mouse_place = false
	_place_queued = false
	_sprint_latched = false
	_auto_eat = false
	break_progress = 0.0
	eat_progress = 0.0
	bow_charge = 0.0


# --- Кадр ------------------------------------------------------------------

func _process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured and not _was_captured:
		_skip_motion = 2
	_was_captured = captured
	_apply_rotation()
	if world == null:
		return
	if dead or frozen or sleeping:
		target = {}
		break_progress = 0.0
		_update_hand(delta)
		return
	# Физика идёт подшагами, поэтому большой кадр безопасен; ограничение — только от «рывков» после зависаний.
	var dt := minf(delta, 0.1)
	# Таймеры (добыча, перезарядка, голод) — по реальному времени, иначе при низком FPS всё замедляется.
	var timer_dt := minf(delta, 0.25)
	_read_movement_input()
	if world.has_chunk_at(position.x, position.z):
		var steps := maxi(ceili(dt * 60.0), ceili(velocity.length() * dt / 0.45))
		steps = clampi(steps, 1, 12)
		for _s in steps:
			_physics_step(dt / steps)
	_update_environment_state(timer_dt)
	_update_camera(dt)
	_update_target()
	var primary := controls_enabled and (mouse_break or touch_break)
	if primary and not _primary_was and actions != null:
		if actions.call("attack", self):
			_swing = 1.0
			break_progress = 0.0
			_break_cooldown = 0.25
	_primary_was = primary
	_update_breaking(timer_dt)
	_update_using(timer_dt)
	_update_survival(timer_dt)
	_update_hand(delta)
	_track_movement()
	if position.y < -64.0:
		# Страховка от падения в пустоту.
		if creative:
			position = spawn_point
			velocity = Vector3.ZERO
		else:
			take_damage(4, "void")


func _apply_rotation() -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	if camera:
		camera.rotation = Vector3(pitch, 0.0, 0.0)


func _read_movement_input() -> void:
	var kb := Vector2.ZERO
	var jump := touch_jump
	var sneak := touch_sneak
	var sprint := touch_sprint
	if controls_enabled:
		kb = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		jump = jump or Input.is_action_pressed("jump")
		sneak = sneak or Input.is_action_pressed("sneak")
		sprint = sprint or Input.is_action_pressed("sprint")
	var mv := kb + touch_move
	if mv.length() > 1.0:
		mv = mv.normalized()
	if eat_progress > 0.0 or bow_charge > 0.0:
		mv *= 0.3
	_move_input = mv
	_jump_held = jump
	_fly_down = sneak and flying
	sneaking = sneak and not flying
	var forward := mv.y < -0.5
	if not forward or sneaking:
		_sprint_latched = false
	var can_sprint := creative or food > 6
	sprinting = forward and not sneaking and can_sprint and (sprint or _sprint_latched) and eat_progress <= 0.0


func speed_multiplier() -> float:
	var m := 1.0
	if effects.has(Potions.SPEED):
		m *= 1.0 + 0.2 * (int(effects[Potions.SPEED][0]) + 1)
	if effects.has(Potions.SLOWNESS):
		m *= maxf(0.0, 1.0 - 0.15 * (int(effects[Potions.SLOWNESS][0]) + 1))
	return m


func _physics_step(dt: float) -> void:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var wish := right * _move_input.x - fwd * _move_input.y
	var speed := WALK_SPEED
	if flying:
		speed = FLY_SPRINT_SPEED if sprinting else FLY_SPEED
	elif sneaking:
		speed = SNEAK_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	if not flying:
		speed *= speed_multiplier()
	var under := world.get_block(floori(position.x), floori(position.y - 0.05), floori(position.z))
	if (in_water or in_lava) and not flying:
		speed *= 0.6 if in_water else 0.35
	if under == Blocks.SOUL_SAND and on_ground:
		speed *= 0.4
	if in_web:
		speed *= 0.25
	var accel := 14.0 if (on_ground or flying) else 5.0
	if under == Blocks.ICE and on_ground:
		accel = 2.0
	if (in_water or in_lava) and not flying:
		accel = 7.0
	var k := 1.0 - exp(-accel * dt)
	velocity.x = lerpf(velocity.x, wish.x * speed, k)
	velocity.z = lerpf(velocity.z, wish.z * speed, k)
	if flying:
		var vy := 0.0
		if _jump_held:
			vy += FLY_SPEED * 0.8
		if _fly_down:
			vy -= FLY_SPEED * 0.8
		velocity.y = lerpf(velocity.y, vy, 1.0 - exp(-12.0 * dt))
	elif in_water or in_lava:
		velocity.y -= (10.0 if in_water else 6.0) * dt
		if _jump_held:
			velocity.y += 22.0 * dt
			# У берега рывок вверх, чтобы можно было выбраться из воды.
			if _hit_wall:
				velocity.y = maxf(velocity.y, 6.0)
		velocity.y = clampf(velocity.y, -3.0, 6.0)
	elif on_ladder:
		velocity.y = maxf(velocity.y - GRAVITY * dt, -3.0)
		if _jump_held or (_hit_wall and _move_input.length() > 0.3):
			velocity.y = CLIMB_SPEED
		elif sneaking:
			velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - GRAVITY * dt, -MAX_FALL_SPEED)
		if _jump_held and on_ground:
			velocity.y = JUMP_VELOCITY
			on_ground = false
			add_exhaustion(0.8 if sprinting else 0.2)
	if in_web:
		velocity.y = clampf(velocity.y, -1.0, 1.0)
	_move(velocity * dt)


func _move(motion: Vector3) -> void:
	var was_on_ground := on_ground
	# Приседание не даёт упасть с края блока.
	if sneaking and on_ground and not flying:
		for axis: int in [0, 2]:
			if motion[axis] == 0.0:
				continue
			var test := position
			test[axis] += motion[axis]
			if not BodyPhysics.has_support(world, test, HALF_WIDTH):
				motion[axis] = 0.0
				velocity[axis] = 0.0
	var res := BodyPhysics.move(world, position, HALF_WIDTH, HEIGHT, motion, STEP_HEIGHT if not flying else 0.0, on_ground)
	position = res["pos"]
	on_ground = res["on_ground"]
	if res["hit_y"]:
		velocity.y = 0.0
	_hit_wall = res["hit_x"] or res["hit_z"]
	if res["hit_x"]:
		velocity.x = 0.0
	if res["hit_z"]:
		velocity.z = 0.0
	if not on_ground and motion.y <= 0.0 and was_on_ground and absf(motion.y) < 0.01:
		on_ground = BodyPhysics.has_support(world, position, HALF_WIDTH)
	if _hit_wall and auto_jump and on_ground and not flying and _move_input.length() > 0.3:
		_try_auto_jump()
	if flying and on_ground:
		set_flying(false)
	if on_ground and not was_on_ground:
		_on_landed()
	if on_ground or flying or in_water or in_lava or on_ladder or in_web:
		_fall_start = position.y
	else:
		_fall_start = maxf(_fall_start, position.y)


func _on_landed() -> void:
	var fall := _fall_start - position.y
	var feet := world.get_block(floori(position.x), floori(position.y + 0.1), floori(position.z))
	if fall > 3.5 and not Blocks.is_water(feet) and not in_water:
		take_damage(floori(fall - 3.0), "fall")
	# Прыжки по грядке вытаптывают её.
	var below := Vector3i(floori(position.x), floori(position.y - 0.05), floori(position.z))
	if fall > 0.9 and world.get_block_v(below) == Blocks.FARMLAND and _rng.randf() < 0.25:
		world.set_block(below.x, below.y, below.z, Blocks.DIRT)


func _try_auto_jump() -> void:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dir := (right * _move_input.x - fwd * _move_input.y).normalized()
	var ahead := position + dir * (HALF_WIDTH + 0.4)
	var fx := floori(ahead.x)
	var fz := floori(ahead.z)
	var fy := floori(position.y + 0.01)
	if Blocks.is_solid(world.get_block(fx, fy, fz)) \
			and not Blocks.is_solid(world.get_block(fx, fy + 1, fz)) \
			and not Blocks.is_solid(world.get_block(fx, fy + 2, fz)) \
			and not Blocks.is_solid(world.get_block(floori(position.x), fy + 2, floori(position.z))):
		velocity.y = JUMP_VELOCITY
		on_ground = false


## Пересекает ли блок в клетке cell тело игрока.
func intersects_block(cell: Vector3i) -> bool:
	return position.x + HALF_WIDTH > cell.x + EPS and position.x - HALF_WIDTH < cell.x + 1 - EPS \
		and position.y + HEIGHT > cell.y + EPS and position.y < cell.y + 1 - EPS \
		and position.z + HALF_WIDTH > cell.z + EPS and position.z - HALF_WIDTH < cell.z + 1 - EPS


func body_box() -> AABB:
	return BodyPhysics.body_box(position, HALF_WIDTH, HEIGHT)


func _update_environment_state(dt: float) -> void:
	var fx := floori(position.x)
	var fz := floori(position.z)
	var feet := world.get_block(fx, floori(position.y + 0.4), fz)
	in_water = Blocks.is_water(feet)
	in_lava = Blocks.is_lava(feet) or Blocks.is_lava(world.get_block(fx, floori(position.y + 1.2), fz))
	var head := world.get_block(fx, floori(position.y + camera.position.y), fz)
	head_in_water = Blocks.is_water(head)
	on_ladder = Blocks.climbable_flags[world.get_block(fx, floori(position.y + 0.1), fz)] == 1 \
		or Blocks.climbable_flags[world.get_block(fx, floori(position.y + 1.0), fz)] == 1
	in_web = feet == Blocks.WEB or world.get_block(fx, floori(position.y + 1.2), fz) == Blocks.WEB
	# Кактус колется, огонь и лава поджигают.
	if not creative:
		var box := body_box().grow(0.05)
		for y in range(floori(box.position.y), floori(box.end.y) + 1):
			for z in range(floori(box.position.z), floori(box.end.z) + 1):
				for x in range(floori(box.position.x), floori(box.end.x) + 1):
					var b := world.get_block(x, y, z)
					if b == Blocks.CACTUS:
						take_damage(1, "cactus")
					elif b == Blocks.FIRE:
						if not effects.has(Potions.FIRE_RESISTANCE):
							fire_time = maxf(fire_time, 8.0)
		if in_lava and not effects.has(Potions.FIRE_RESISTANCE):
			fire_time = maxf(fire_time, 15.0)
			take_damage(4, "lava")
	if in_water or head_in_water:
		fire_time = 0.0
	if fire_time > 0.0:
		fire_time -= dt
		_fire_tick += dt
		if _fire_tick >= 1.0:
			_fire_tick = 0.0
			if not effects.has(Potions.FIRE_RESISTANCE):
				take_damage(1, "fire")


func _update_camera(dt: float) -> void:
	var eye := SNEAK_EYE_HEIGHT if sneaking else EYE_HEIGHT
	camera.position.y = lerpf(camera.position.y, eye, 1.0 - exp(-15.0 * dt))
	var moving := _move_input.length() > 0.1
	var fov_target := base_fov * (1.1 if sprinting and moving else 1.0)
	if effects.has(Potions.SPEED):
		fov_target *= 1.05
	if bow_charge > 0.0:
		fov_target *= 1.0 - 0.15 * minf(bow_charge, 1.0)
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-10.0 * dt))
	if on_ground and moving:
		_bob += dt * (11.0 if sprinting else 8.5)
	else:
		_bob = lerpf(_bob, roundf(_bob / PI) * PI, 1.0 - exp(-8.0 * dt))


func _track_movement() -> void:
	var moved := Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length()
	_last_pos = position
	if creative or moved > 2.0:
		return
	if in_water:
		add_exhaustion(0.015 * moved)
	elif sprinting:
		add_exhaustion(0.1 * moved)
	elif on_ground:
		add_exhaustion(0.01 * moved)


# --- Взаимодействие с блоками ----------------------------------------------

func reach() -> float:
	return CREATIVE_REACH if creative else REACH


func _update_target() -> void:
	if not controls_enabled:
		target = {}
		return
	var stop_liquid := inventory.selected_id() == Items.BUCKET
	target = world.raycast(camera.global_position, look_dir(), reach(), stop_liquid)
	if not target.is_empty() and Blocks.is_liquid(int(target["block"])) and not stop_liquid:
		target = {}


func held_tool() -> int:
	var id := inventory.selected_id()
	return Items.tool_kind(id)


func held_tier() -> int:
	var id := inventory.selected_id()
	return Items.tool_tier(id)


## Время добычи блока выбранным в руке предметом (секунды).
func dig_time(id: int) -> float:
	var item := inventory.selected_id()
	var tool := Items.tool_kind(item)
	var t := Blocks.break_time(id, tool, Items.tool_tier(item), Items.tool_speed(item))
	if (head_in_water) or (not on_ground and not flying and not on_ladder):
		t *= 5.0
	return t


func _update_breaking(dt: float) -> void:
	_break_cooldown -= dt
	var holding := controls_enabled and (mouse_break or touch_break)
	if not holding or target.is_empty():
		break_progress = 0.0
		return
	var pos: Vector3i = target["pos"]
	var id: int = target["block"]
	if pos != break_pos:
		break_pos = pos
		break_progress = 0.0
	if _break_cooldown > 0.0:
		return
	if creative:
		# Мечом в креативе блоки не ломаются (как в оригинале).
		if not Items.is_sword(inventory.selected_id()):
			_break_block(pos, id)
		_break_cooldown = CREATIVE_BREAK_DELAY
		return
	var t := dig_time(id)
	if t == INF:
		break_progress = 0.0
		return
	if _swing <= 0.0:
		_swing = 1.0
	break_progress += dt / maxf(t, 0.05) if t > 0.0 else 1.0
	if break_progress >= 1.0:
		_break_block(pos, id)
		break_progress = 0.0
		_break_cooldown = 0.18


func _break_block(pos: Vector3i, id: int) -> void:
	var meta := world.get_meta_v(pos)
	_swing = 1.0
	if actions != null:
		actions.call("on_block_break", self, pos, id, meta)
	else:
		world.break_block(pos)
	if not creative:
		add_exhaustion(0.025)
		var item := inventory.selected_id()
		if Items.is_damageable(item) and Blocks.hardness(id) > 0.0:
			# Мечи изнашиваются вдвое быстрее на блоках.
			inventory.damage_slot(inventory.selected, 2 if Items.is_sword(item) else 1)
	block_broken.emit(pos, id, meta)


## Правая кнопка / тап: еда, лук, использование предмета или блока, установка.
func _update_using(dt: float) -> void:
	_place_cooldown -= dt
	var holding := controls_enabled and (mouse_place or touch_place)
	var id := inventory.selected_id()
	# Поедание: удерживать (или тап на сенсорном экране — доедается само).
	if (Items.is_food(id) or id == Items.MILK_BUCKET or id == Items.POTION) and _can_consume(id):
		if _place_queued and (target.is_empty() or not _block_is_usable(target)):
			_place_queued = false
			_auto_eat = not holding
			if eat_progress <= 0.0:
				eat_progress = 0.001
		if eat_progress > 0.0:
			if holding or _auto_eat:
				eat_progress += dt / EAT_TIME
				if eat_progress >= 1.0:
					eat_progress = 0.0
					_auto_eat = false
					if actions != null:
						actions.call("finish_consume", self)
			else:
				eat_progress = 0.0
			_use_was = holding
			return
	else:
		eat_progress = 0.0
		_auto_eat = false
	# Лук: натягивается, пока кнопка удерживается; выстрел — при отпускании.
	if id == Items.BOW and (creative or inventory.count_of(Items.ARROW) > 0):
		if holding or _place_queued:
			_place_queued = false
			bow_charge += dt
		elif bow_charge > 0.0:
			if actions != null:
				actions.call("shoot_bow", self, bow_charge)
			bow_charge = 0.0
		_use_was = holding
		return
	bow_charge = 0.0
	if _place_queued:
		_place_queued = false
		if actions != null and actions.call("use", self, true):
			_swing = 1.0
			_place_cooldown = PLACE_DELAY * 1.5
		_use_was = holding
		return
	if holding and _place_cooldown <= 0.0 and actions != null:
		if actions.call("use", self, false):
			_swing = 1.0
			_place_cooldown = PLACE_DELAY
	_use_was = holding


func _can_consume(id: int) -> bool:
	if creative and Items.is_food(id):
		return false
	if Items.is_food(id) and id != Items.GOLDEN_APPLE:
		return food < MAX_FOOD
	return true


func _block_is_usable(t: Dictionary) -> bool:
	return actions != null and bool(actions.call("is_usable_block", int(t["block"])))


## Совместимость: поставить блок из руки по текущему прицелу.
func try_place() -> bool:
	return actions != null and bool(actions.call("use", self, true))


## Средняя кнопка мыши: взять блок под прицелом в руку.
func pick_block() -> void:
	if target.is_empty():
		return
	var id: int = target["block"]
	var data := 0
	var meta: int = target.get("meta", 0)
	match id:
		Blocks.PLANKS, Blocks.LOG, Blocks.LEAVES, Blocks.SAPLING:
			data = meta & 3
		Blocks.WOOL, Blocks.SANDSTONE, Blocks.STONE_BRICKS:
			data = meta
		Blocks.SLAB:
			data = meta & 7
	var drops := Blocks.drops(id, meta, Blocks.TOOL_PICKAXE, 4, _rng)
	if id == Blocks.REDSTONE_WIRE or id == Blocks.WOODEN_DOOR or id == Blocks.IRON_DOOR or id == Blocks.BED \
			or id == Blocks.SIGN_POST or id == Blocks.WALL_SIGN or id == Blocks.REEDS or id == Blocks.CAKE \
			or id == Blocks.REPEATER_OFF or id == Blocks.REPEATER_ON:
		if not drops.is_empty():
			id = drops[0][0]
			data = 0
	if id == Blocks.CAKE:
		id = Items.CAKE
	for i in Inventory.HOTBAR_SIZE:
		if inventory.ids[i] == id and inventory.counts[i] > 0 and inventory.datas[i] == data:
			inventory.select(i)
			return
	if creative:
		inventory.set_slot(inventory.selected, id, 1, data)


# --- Здоровье, голод, опыт -------------------------------------------------

## Урон с учётом брони. source: fall, void, drown, starve, magic, poison — без брони.
func take_damage(amount: int, source := "generic", attacker: Node3D = null) -> void:
	if creative or dead or amount <= 0:
		return
	if difficulty == 0 and source in ["mob", "arrow"]:
		return
	if source in ["mob", "arrow"] and difficulty == 1:
		amount = maxi(amount / 2 + 1, 1)
	elif source in ["mob", "arrow"] and difficulty == 3:
		amount = amount * 3 / 2
	# Неуязвимость после удара: проходит только разница с предыдущим уроном.
	if _invulnerable > 0.0:
		if amount <= _last_damage:
			return
		var extra := amount - _last_damage
		_last_damage = amount
		amount = extra
	else:
		_last_damage = amount
		_invulnerable = 0.5
	if not source in ["fall", "void", "drown", "starve", "magic", "poison"]:
		var armor := inventory.armor_points()
		if armor > 0:
			inventory.damage_armor(amount)
			amount = int(round(amount * (25.0 - armor) / 25.0))
	if amount <= 0:
		return
	add_exhaustion(0.3)
	health = maxi(health - amount, 0)
	if attacker != null:
		var dir := position - attacker.global_position
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			velocity += dir.normalized() * 6.0
			velocity.y = maxf(velocity.y, 4.0)
	health_changed.emit(health)
	damaged.emit(amount)
	if health <= 0:
		die()


func heal(amount: int) -> void:
	if dead:
		return
	health = mini(health + amount, MAX_HEALTH)
	health_changed.emit(health)


func add_exhaustion(v: float) -> void:
	if creative:
		return
	exhaustion += v


func eat(hunger: int, sat: float) -> void:
	food = mini(food + hunger, MAX_FOOD)
	saturation = minf(saturation + sat, float(food))
	stats_changed.emit()


func add_effect(effect: int, level: int, seconds: float) -> void:
	if effect == Potions.INSTANT_HEALTH:
		heal(4 << level)
		return
	if effect == Potions.INSTANT_DAMAGE:
		take_damage(6 << level, "magic")
		return
	var cur: Array = effects.get(effect, [-1, 0.0])
	if level > int(cur[0]) or (level == int(cur[0]) and seconds > float(cur[1])):
		effects[effect] = [level, seconds]
	stats_changed.emit()


func clear_effects() -> void:
	effects.clear()
	stats_changed.emit()


## Очки опыта до следующего уровня (формула 1.2).
static func xp_for_level(level: int) -> int:
	return 7 + (level * 7 >> 1)


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp_total += amount
	# Очки внутри уровня считаются целыми, чтобы не копить ошибку округления.
	var need := xp_for_level(xp_level)
	var points := roundi(xp_progress * need) + amount
	while points >= need:
		points -= need
		xp_level += 1
		need = xp_for_level(xp_level)
	xp_progress = float(points) / need
	stats_changed.emit()


func remove_levels(n: int) -> void:
	xp_level = maxi(xp_level - n, 0)
	if xp_level == 0:
		xp_progress = 0.0
	stats_changed.emit()


func _update_survival(dt: float) -> void:
	_invulnerable = maxf(_invulnerable - dt, 0.0)
	# Эффекты.
	_effect_tick += dt
	if not effects.is_empty():
		var expired := []
		for e: int in effects:
			var rec: Array = effects[e]
			rec[1] = float(rec[1]) - dt
			if float(rec[1]) <= 0.0:
				expired.append(e)
		for e: int in expired:
			effects.erase(e)
		if not expired.is_empty():
			stats_changed.emit()
		if _effect_tick >= 0.5:
			_effect_tick = 0.0
			if effects.has(Potions.REGENERATION) and health < MAX_HEALTH:
				heal(1)
			if effects.has(Potions.POISON) and health > 1:
				take_damage(1, "poison")
				_invulnerable = 0.0
			if effects.has(Potions.HUNGER):
				add_exhaustion(0.5)
	if creative:
		air = MAX_AIR
		return
	# Воздух под водой.
	if head_in_water:
		air -= int(dt * 20.0 + 0.5)
		if air <= -20:
			air = 0
			take_damage(2, "drown")
	else:
		air = mini(air + int(dt * 60.0 + 0.5), MAX_AIR)
	# Голод (как в 1.2: 4 единицы усталости = 1 насыщения или 1 голода).
	while exhaustion >= 4.0:
		exhaustion -= 4.0
		if saturation > 0.0:
			saturation = maxf(saturation - 1.0, 0.0)
		elif difficulty > 0:
			food = maxi(food - 1, 0)
		stats_changed.emit()
	if food >= 18 and health < MAX_HEALTH:
		_regen += dt
		if _regen >= 4.0:
			_regen = 0.0
			heal(1)
			add_exhaustion(3.0)
	else:
		_regen = 0.0
	if food <= 0:
		_starve += dt
		if _starve >= 4.0:
			_starve = 0.0
			var floor_hp := 10 if difficulty <= 1 else (1 if difficulty == 2 else 0)
			if health > floor_hp:
				take_damage(1, "starve")
	else:
		_starve = 0.0
	if difficulty == 0:
		# Мирная сложность: здоровье и сытость восстанавливаются сами.
		if health < MAX_HEALTH and _regen == 0.0:
			_regen = 0.001
		if food < MAX_FOOD:
			food = MAX_FOOD


func die() -> void:
	dead = true
	velocity = Vector3.ZERO
	flying = false
	fire_time = 0.0
	sleeping = false
	release_all_input()
	died.emit()


func respawn() -> void:
	dead = false
	health = MAX_HEALTH
	food = MAX_FOOD
	saturation = 5.0
	exhaustion = 0.0
	air = MAX_AIR
	fire_time = 0.0
	xp_level = 0
	xp_progress = 0.0
	xp_total = 0
	effects.clear()
	position = spawn_point
	velocity = Vector3.ZERO
	_fall_start = position.y
	health_changed.emit(health)
	stats_changed.emit()


# --- Предмет в руке --------------------------------------------------------

func _update_hand(dt: float) -> void:
	var id := inventory.selected_id()
	var data := inventory.selected_data()
	var key := id * 65536 + (0 if Items.is_damageable(id) else data)
	if key != _hand_key:
		_hand_key = key
		hand.mesh = TextureFactory.item_mesh(id, data) if id != 0 else null
	hand.visible = id != 0 and not dead and not sleeping
	var block_like := Items.is_block(id) and not Items.is_flat_block(id)
	_swing = maxf(_swing - dt * 4.0, 0.0)
	var s := sin(_swing * PI)
	var bob := Vector3(cos(_bob) * 0.025, -absf(sin(_bob)) * 0.03, 0.0)
	var base_pos := HAND_POS if block_like else ITEM_HAND_POS
	var base_rot := HAND_ROT if block_like else ITEM_HAND_ROT
	hand.scale = Vector3.ONE * (0.3 if block_like else 0.42)
	var eat := Vector3.ZERO
	if eat_progress > 0.0:
		eat = Vector3(-0.25, 0.1 + sin(eat_progress * 40.0) * 0.02, 0.1)
	hand.position = base_pos + bob + eat + Vector3(-0.12 * s, 0.08 * s, -0.12 * s)
	hand.rotation = base_rot + Vector3(-0.7 * s, 0.0, 0.25 * s)
	# Освещение предмета в руке — по клетке, где стоит игрок.
	if world != null:
		var cell := Vector3i(floori(position.x), floori(position.y + 1.0), floori(position.z))
		TextureFactory.set_light(hand, world.get_sky_light(cell) / 15.0, ChunkMesher.block_curve[clampi(world.get_block_light(cell), 0, 15)])


# --- Сохранение ------------------------------------------------------------

func to_dict() -> Dictionary:
	var eff := {}
	for e: int in effects:
		eff[str(e)] = effects[e]
	return {
		"pos": [position.x, position.y, position.z],
		"yaw": yaw,
		"pitch": pitch,
		"health": health,
		"food": food,
		"saturation": saturation,
		"air": air,
		"xp": [xp_level, xp_progress, xp_total],
		"effects": eff,
		"fire": fire_time,
		"flying": flying,
		"spawn": [spawn_point.x, spawn_point.y, spawn_point.z],
		"inventory": inventory.to_data(),
		"selected": inventory.selected,
	}


func from_dict(d: Dictionary, legacy := false) -> void:
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var sp: Array = d.get("spawn", [])
	if sp.size() == 3:
		spawn_point = Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
	set_look(float(d.get("yaw", 0.0)), float(d.get("pitch", 0.0)))
	health = clampi(int(d.get("health", MAX_HEALTH)), 1, MAX_HEALTH)
	food = clampi(int(d.get("food", MAX_FOOD)), 0, MAX_FOOD)
	saturation = clampf(float(d.get("saturation", 5.0)), 0.0, 20.0)
	air = clampi(int(d.get("air", MAX_AIR)), 0, MAX_AIR)
	var xp: Array = d.get("xp", [0, 0.0, 0])
	if xp.size() == 3:
		xp_level = int(xp[0])
		xp_progress = float(xp[1])
		xp_total = int(xp[2])
	effects.clear()
	var eff: Variant = d.get("effects", {})
	if eff is Dictionary:
		for k: Variant in eff:
			var rec: Variant = eff[k]
			if rec is Array and rec.size() == 2:
				effects[int(str(k))] = [int(rec[0]), float(rec[1])]
	fire_time = float(d.get("fire", 0.0))
	flying = bool(d.get("flying", false)) and creative
	inventory.from_data(d.get("inventory", []), legacy)
	inventory.select(int(d.get("selected", 0)))
	_fall_start = position.y
	_last_pos = position
