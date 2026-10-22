class_name Player
extends Node3D
## Игрок от первого лица: собственная воксельная физика (AABB против блоков), полёт,
## плавание, урон от падения, добыча и установка блоков. Управление — мышь/клавиатура и сенсор.

signal health_changed(health: int)
signal damaged(amount: int)
signal died
signal block_broken(pos: Vector3i, block_id: int)
signal block_placed(pos: Vector3i, block_id: int)
signal flying_changed(flying: bool)

const HALF_WIDTH := 0.3
const HEIGHT := 1.8
const EYE_HEIGHT := 1.62
const SNEAK_EYE_HEIGHT := 1.42
const GRAVITY := 30.0
const JUMP_VELOCITY := 8.7
const WALK_SPEED := 4.3
const SPRINT_SPEED := 5.8
const SNEAK_SPEED := 1.6
const FLY_SPEED := 10.0
const FLY_SPRINT_SPEED := 20.0
const MAX_FALL_SPEED := 60.0
const REACH := 5.0
const MAX_HEALTH := 20
const EPS := 0.001
const DOUBLE_TAP := 0.3
const CREATIVE_BREAK_DELAY := 0.22
const PLACE_DELAY := 0.22
const HAND_POS := Vector3(0.56, -0.48, -0.82)
const HAND_ROT := Vector3(0.0, 0.733, 0.0)

var world: World
var inventory := Inventory.new()
var camera: Camera3D
var hand: MeshInstance3D

var creative := true
var flying := false
var velocity := Vector3.ZERO
var on_ground := false
var in_water := false
var head_in_water := false
var sneaking := false
var sprinting := false
var yaw := 0.0
var pitch := 0.0
var health := MAX_HEALTH
var dead := false
var spawn_point := Vector3.ZERO
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
var _was_captured := false
var _skip_motion := 0

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

## Текущий блок под прицелом: {pos, normal, block} или пустой словарь.
var target: Dictionary = {}
var break_progress := 0.0
var break_pos := Vector3i(0, -1000, 0)

var _move_input := Vector2.ZERO
var _jump_held := false
var _fly_down := false
var _sprint_latched := false
var _break_cooldown := 0.0
var _place_cooldown := 0.0
var _place_queued := false
var _last_jump_time := -10.0
var _last_forward_time := -10.0
var _fall_start := 0.0
var _regen := 0.0
var _swing := 0.0
var _bob := 0.0
var _hit_wall := false
var _hand_id := -1


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
			elif mm.relative.length() <= MAX_MOUSE_STEP:
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


func rotate_view(yaw_deg: float, pitch_deg: float) -> void:
	yaw = wrapf(yaw + deg_to_rad(yaw_deg), -PI, PI)
	pitch = clampf(pitch + deg_to_rad(pitch_deg), deg_to_rad(-89.0), deg_to_rad(89.0))


func set_look(p_yaw: float, p_pitch: float) -> void:
	yaw = p_yaw
	pitch = clampf(p_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
	_apply_rotation()


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
	break_progress = 0.0


# --- Кадр ------------------------------------------------------------------

func _process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured and not _was_captured:
		_skip_motion = 2
	_was_captured = captured
	_apply_rotation()
	if world == null:
		return
	if dead or frozen:
		target = {}
		break_progress = 0.0
		_update_hand(delta)
		return
	# Физика идёт подшагами, поэтому большой кадр безопасен; ограничение — только от «рывков» после зависаний.
	var dt := minf(delta, 0.1)
	# Таймеры (добыча, перезарядка, регенерация) — по реальному времени, иначе при низком FPS всё замедляется.
	var timer_dt := minf(delta, 0.25)
	_read_movement_input()
	if world.has_chunk_at(position.x, position.z):
		# Подшаги: за один шаг тело смещается меньше чем на полблока (нет «туннелирования»).
		var steps := maxi(ceili(dt * 60.0), ceili(velocity.length() * dt / 0.45))
		steps = clampi(steps, 1, 12)
		for _s in steps:
			_physics_step(dt / steps)
	_update_environment_state()
	_update_camera(dt)
	_update_target()
	_update_breaking(timer_dt)
	_update_placing(timer_dt)
	_update_regen(timer_dt)
	_update_hand(delta)
	if position.y < -32.0:
		# Страховка от падения в пустоту.
		if creative:
			position = spawn_point
			velocity = Vector3.ZERO
		else:
			take_damage(MAX_HEALTH)


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
	_move_input = mv
	_jump_held = jump
	_fly_down = sneak and flying
	sneaking = sneak and not flying
	var forward := mv.y < -0.5
	if not forward or sneaking:
		_sprint_latched = false
	sprinting = forward and not sneaking and (sprint or _sprint_latched)


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
	if in_water and not flying:
		speed *= 0.6
	var accel := 14.0 if (on_ground or flying) else 5.0
	if in_water and not flying:
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
	elif in_water:
		velocity.y -= 10.0 * dt
		if _jump_held:
			velocity.y += 22.0 * dt
			# У берега рывок вверх, чтобы можно было выбраться из воды.
			if _hit_wall:
				velocity.y = maxf(velocity.y, 6.0)
		velocity.y = clampf(velocity.y, -3.0, 6.0)
	else:
		velocity.y = maxf(velocity.y - GRAVITY * dt, -MAX_FALL_SPEED)
		if _jump_held and on_ground:
			velocity.y = JUMP_VELOCITY
			on_ground = false
	_move(velocity * dt)


func _move(motion: Vector3) -> void:
	var was_on_ground := on_ground
	var hit_y := false
	if motion.y != 0.0:
		hit_y = _move_axis(1, motion.y)
	on_ground = hit_y and motion.y < 0.0
	_hit_wall = false
	for axis: int in [0, 2]:
		var amount: float = motion[axis]
		if amount == 0.0:
			continue
		# Приседание не даёт упасть с края блока.
		if sneaking and on_ground:
			var test := position
			test[axis] += amount
			if not _has_support(test):
				velocity[axis] = 0.0
				continue
		if _move_axis(axis, amount):
			_hit_wall = true
	if _hit_wall and auto_jump and on_ground and not flying and _move_input.length() > 0.3:
		_try_auto_jump()
	if flying and on_ground:
		set_flying(false)
	if on_ground and not was_on_ground:
		_on_landed()
	if on_ground or flying or in_water:
		_fall_start = position.y
	else:
		_fall_start = maxf(_fall_start, position.y)


func _on_landed() -> void:
	var fall := _fall_start - position.y
	# Флаг in_water обновляется после физики, поэтому воду под ногами проверяем здесь.
	var water := world.get_block(floori(position.x), floori(position.y + 0.1), floori(position.z)) == Blocks.WATER
	if fall > 3.5 and not water and not in_water:
		take_damage(floori(fall - 3.0))


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


## Сдвиг по одной оси с упором в блоки. true — было столкновение.
func _move_axis(axis: int, amount: float) -> bool:
	var p := position
	p[axis] += amount
	if not _collides(p):
		position = p
		return false
	var ext_pos := HEIGHT if axis == 1 else HALF_WIDTH
	var ext_neg := 0.0 if axis == 1 else HALF_WIDTH
	if amount > 0.0:
		p[axis] = floorf(p[axis] + ext_pos) - ext_pos - EPS
	else:
		p[axis] = floorf(p[axis] - ext_neg) + 1.0 + ext_neg + EPS
	if not _collides(p):
		position = p
	velocity[axis] = 0.0
	return true


func _collides(p: Vector3) -> bool:
	var x0 := floori(p.x - HALF_WIDTH)
	var x1 := floori(p.x + HALF_WIDTH)
	var y0 := floori(p.y)
	var y1 := floori(p.y + HEIGHT)
	var z0 := floori(p.z - HALF_WIDTH)
	var z1 := floori(p.z + HALF_WIDTH)
	for y in range(y0, y1 + 1):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				if Blocks.is_solid(world.get_block(x, y, z)):
					return true
	return false


func _has_support(p: Vector3) -> bool:
	var y := floori(p.y - 0.05)
	for z in range(floori(p.z - HALF_WIDTH), floori(p.z + HALF_WIDTH) + 1):
		for x in range(floori(p.x - HALF_WIDTH), floori(p.x + HALF_WIDTH) + 1):
			if Blocks.is_solid(world.get_block(x, y, z)):
				return true
	return false


## Пересекает ли блок в клетке cell тело игрока.
func intersects_block(cell: Vector3i) -> bool:
	return position.x + HALF_WIDTH > cell.x + EPS and position.x - HALF_WIDTH < cell.x + 1 - EPS \
		and position.y + HEIGHT > cell.y + EPS and position.y < cell.y + 1 - EPS \
		and position.z + HALF_WIDTH > cell.z + EPS and position.z - HALF_WIDTH < cell.z + 1 - EPS


func _update_environment_state() -> void:
	var fx := floori(position.x)
	var fz := floori(position.z)
	in_water = world.get_block(fx, floori(position.y + 0.4), fz) == Blocks.WATER
	head_in_water = world.get_block(fx, floori(position.y + camera.position.y), fz) == Blocks.WATER


func _update_camera(dt: float) -> void:
	var eye := SNEAK_EYE_HEIGHT if sneaking else EYE_HEIGHT
	camera.position.y = lerpf(camera.position.y, eye, 1.0 - exp(-15.0 * dt))
	var moving := _move_input.length() > 0.1
	var fov_target := base_fov * (1.1 if sprinting and moving else 1.0)
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-10.0 * dt))
	if on_ground and moving:
		_bob += dt * (11.0 if sprinting else 8.5)
	else:
		_bob = lerpf(_bob, roundf(_bob / PI) * PI, 1.0 - exp(-8.0 * dt))


# --- Взаимодействие с блоками ----------------------------------------------

func _update_target() -> void:
	if not controls_enabled:
		target = {}
		return
	target = world.raycast(camera.global_position, -camera.global_transform.basis.z, REACH)


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
		_break_block(pos, id)
		_break_cooldown = CREATIVE_BREAK_DELAY
		return
	var h := Blocks.hardness(id)
	if h < 0.0:
		break_progress = 0.0
		return
	break_progress += dt / maxf(h, 0.05)
	if _swing <= 0.0:
		_swing = 1.0
	if break_progress >= 1.0:
		_break_block(pos, id)
		break_progress = 0.0
		_break_cooldown = 0.18


func _break_block(pos: Vector3i, id: int) -> void:
	world.break_block(pos)
	_swing = 1.0
	block_broken.emit(pos, id)


func _update_placing(dt: float) -> void:
	_place_cooldown -= dt
	var holding := controls_enabled and (mouse_place or touch_place)
	if _place_queued:
		_place_queued = false
		if try_place():
			_place_cooldown = PLACE_DELAY * 1.5
		return
	if holding and _place_cooldown <= 0.0:
		if try_place():
			_place_cooldown = PLACE_DELAY


func try_place() -> bool:
	if target.is_empty():
		return false
	var id := inventory.get_selected_block()
	if id == Blocks.AIR:
		return false
	var pos: Vector3i = target["pos"] + target["normal"]
	if pos.y < 0 or pos.y >= WorldGen.CHUNK_HEIGHT:
		return false
	if not Blocks.is_replaceable(world.get_block_v(pos)):
		return false
	if Blocks.is_solid(id) and intersects_block(pos):
		return false
	if not world.set_block(pos.x, pos.y, pos.z, id):
		return false
	if not creative:
		inventory.consume_selected(1)
	_swing = 1.0
	block_placed.emit(pos, id)
	return true


## Средняя кнопка мыши: взять блок под прицелом в руку.
func pick_block() -> void:
	if target.is_empty():
		return
	var id: int = target["block"]
	for i in Inventory.HOTBAR_SIZE:
		if inventory.ids[i] == id and inventory.counts[i] > 0:
			inventory.select(i)
			return
	if creative:
		inventory.set_slot(inventory.selected, id, 1)


# --- Здоровье --------------------------------------------------------------

func take_damage(amount: int) -> void:
	if creative or dead or amount <= 0:
		return
	health = maxi(health - amount, 0)
	health_changed.emit(health)
	damaged.emit(amount)
	if health <= 0:
		die()


func heal(amount: int) -> void:
	if dead:
		return
	health = mini(health + amount, MAX_HEALTH)
	health_changed.emit(health)


func die() -> void:
	dead = true
	velocity = Vector3.ZERO
	flying = false
	release_all_input()
	died.emit()


func respawn() -> void:
	dead = false
	health = MAX_HEALTH
	position = spawn_point
	velocity = Vector3.ZERO
	_fall_start = position.y
	health_changed.emit(health)


func _update_regen(dt: float) -> void:
	if creative or health >= MAX_HEALTH:
		_regen = 0.0
		return
	_regen += dt
	if _regen >= 4.0:
		_regen = 0.0
		heal(1)


# --- Блок в руке -----------------------------------------------------------

func _update_hand(dt: float) -> void:
	var id := inventory.get_selected_block()
	if id != _hand_id:
		_hand_id = id
		hand.mesh = TextureFactory.block_mesh(id) if id != Blocks.AIR else null
	hand.visible = id != Blocks.AIR and not dead
	_swing = maxf(_swing - dt * 4.0, 0.0)
	var s := sin(_swing * PI)
	var bob := Vector3(cos(_bob) * 0.025, -absf(sin(_bob)) * 0.03, 0.0)
	hand.position = HAND_POS + bob + Vector3(-0.12 * s, 0.08 * s, -0.12 * s)
	hand.rotation = HAND_ROT + Vector3(-0.7 * s, 0.0, 0.25 * s)


# --- Сохранение ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"pos": [position.x, position.y, position.z],
		"yaw": yaw,
		"pitch": pitch,
		"health": health,
		"flying": flying,
		"spawn": [spawn_point.x, spawn_point.y, spawn_point.z],
		"inventory": inventory.to_data(),
		"selected": inventory.selected,
	}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var sp: Array = d.get("spawn", [])
	if sp.size() == 3:
		spawn_point = Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
	set_look(float(d.get("yaw", 0.0)), float(d.get("pitch", 0.0)))
	health = clampi(int(d.get("health", MAX_HEALTH)), 1, MAX_HEALTH)
	flying = bool(d.get("flying", false)) and creative
	inventory.from_data(d.get("inventory", []))
	inventory.select(int(d.get("selected", 0)))
	_fall_start = position.y
