class_name EnderDragon
extends Mob
## Дракон Края (босс 1.2): кружит над островом, пикирует на игрока, лечится от кристаллов Края,
## ломает все блоки на пути, кроме обсидиана, камня Края и коренной породы. После смерти —
## поток опыта (12000), портал выхода из коренной породы с порталом Края и яйцо дракона.

const CIRCLE_RADIUS := 40.0
const NO_BREAK := [Blocks.OBSIDIAN, Blocks.END_STONE, Blocks.BEDROCK, Blocks.END_PORTAL, Blocks.END_PORTAL_FRAME,
	Blocks.FIRE]

var island_y := 64.0
var _dest := Vector3.ZERO
var _angle := 0.0
var _charging := false
var _charge_cd := 15.0
var _pitch := 0.0
var _heal_from: Mob
var _beam: MeshInstance3D
var _hit_head := false
var _xp_left := 12000
var _flap := 0.0


func _setup() -> void:
	half_w = 4.0
	height = 4.0
	_angle = rng.randf_range(0, TAU)


func model_key() -> String:
	return "dragon"


func skin_keys() -> Array:
	return ["dragon"]


func ambient_sound() -> String:
	return "dragon"


func _apply_size() -> void:
	half_w = 4.0
	height = 4.0
	if model != null:
		# Центр туловища модели — в центре тела.
		model.pivot.position = Vector3(0, 1.5, 1.5)


func _after_model() -> void:
	_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.18, 1.0)
	_beam.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.55, 1.0)
	_beam.material_override = mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)


## Не сохраняется в чанках: при возвращении в Край появится заново (если не побеждён).
func to_dict() -> Dictionary:
	return {}


func knockback_scale() -> float:
	return 0.0


## Попадания: голова и туловище с крыльями.
func hit_boxes() -> Array[AABB]:
	var out: Array[AABB] = [AABB(position + Vector3(-4, 0.5, -4), Vector3(8, 3, 8))]
	if model != null and model.parts.has("head"):
		var h := (model.parts["head"] as Node3D).global_position
		out.append(AABB(h - Vector3(1.2, 1.2, 1.2), Vector3(2.4, 2.4, 2.4)))
	return out


func head_position() -> Vector3:
	if model != null and model.parts.has("head"):
		return (model.parts["head"] as Node3D).global_position
	return center() + facing() * 6.0


func ai_tick() -> void:
	_flap += TICK * (5.0 if _charging else 3.2)
	_charge_cd -= TICK
	var p := player()
	var center_xz := Vector3(0, island_y + 25.0, 0)
	if _charging:
		if p == null or not target_valid(p) or position.distance_to(p.position) > 150.0:
			_charging = false
		else:
			_dest = p.position + Vector3(0, 1.0, 0)
			if head_position().distance_to(_dest) < 4.0 or position.distance_to(_dest) < 5.0:
				_charging = false
				_charge_cd = rng.randf_range(12.0, 22.0)
				_angle += PI * 0.6
	if not _charging:
		if position.distance_to(_dest) < 10.0 or _dest == Vector3.ZERO:
			_angle += rng.randf_range(0.35, 0.8)
			var r := CIRCLE_RADIUS + rng.randf_range(-10.0, 15.0)
			_dest = center_xz + Vector3(cos(_angle) * r, rng.randf_range(-8.0, 18.0), sin(_angle) * r)
		if _charge_cd <= 0.0 and p != null and target_valid(p) and position.distance_to(p.position) < 120.0:
			_charging = true
	var to := _dest - position
	var want_speed := 16.0 if _charging else 12.0
	var dir := to.normalized()
	velocity = velocity.lerp(dir * want_speed, 0.06)
	if Vector2(velocity.x, velocity.z).length() > 0.5:
		turn_to(velocity, 0.08)
	_pitch = lerpf(_pitch, clampf(-velocity.y / want_speed, -0.6, 0.6), 0.1)
	look_pos = _dest
	_heal_tick()
	_hit_entities()
	if ticks % 2 == 0:
		_break_blocks()


func _physics() -> void:
	# Летит сквозь всё (блоки на пути ломает сам).
	position += velocity * TICK
	if position.y < 2.0:
		position.y = 2.0
		velocity.y = absf(velocity.y)


## Лечение от ближайшего кристалла Края (1 единица каждые полсекунды).
func _heal_tick() -> void:
	if ticks % 10 == 0:
		_heal_from = null
		var best := 32.0
		for m: Mob in system.call("mobs_near", position, 32.0):
			if m.type == MobDefs.END_CRYSTAL and not m.is_dead():
				var d := m.position.distance_to(position)
				if d < best:
					best = d
					_heal_from = m
		if _heal_from != null and health < max_health:
			health = mini(health + 1, max_health)
	if _beam == null:
		return
	_beam.visible = _heal_from != null and is_instance_valid(_heal_from)
	if _beam.visible:
		var a := _heal_from.position + Vector3(0, 1.6, 0) - position
		var b := center() - position
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		_beam.position = mid
		if len > 0.1:
			_beam.look_at_from_position(mid, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
		_beam.scale = Vector3(1, 1, len)


## Удары: голова — 10, крылья отбрасывают (5).
func _hit_entities() -> void:
	var p := player()
	var head := AABB(head_position() - Vector3(1.5, 1.5, 1.5), Vector3(3, 3, 3))
	var body := AABB(position + Vector3(-4, 0, -4), Vector3(8, 4, 8))
	if p != null and target_valid(p) and attack_cd <= 0.0:
		var pb := p.body_box()
		if pb.intersects(head):
			attack_cd = 0.5
			p.take_damage(10, "mob", self)
		elif pb.intersects(body):
			attack_cd = 0.5
			p.take_damage(5, "mob", self)
			var away := p.position - position
			away.y = 0.0
			p.velocity += away.normalized() * 10.0 + Vector3(0, 6, 0)
	for m: Mob in system.call("mobs_near", position, 8.0):
		if m != self and m.type != MobDefs.END_CRYSTAL and m.box().intersects(body) and m.invuln <= 0.0:
			m.hurt(5, "mob", self, (m.position - position).normalized() * 8.0)


func _break_blocks() -> void:
	var b := AABB(position + Vector3(-3, 0, -3), Vector3(6, 4, 6))
	var head := head_position()
	var broke := 0
	for c in _cells(b) + _cells(AABB(head - Vector3(1, 1, 1), Vector3(2, 2, 2))):
		var id := world.get_block_v(c)
		if id == Blocks.AIR or id in NO_BREAK or Blocks.is_liquid(id):
			continue
		world.set_block(c.x, c.y, c.z, Blocks.AIR)
		broke += 1
		if broke > 24:
			return


func on_hurt(_amount: int, source: String, attacker: Node3D) -> bool:
	# Ранят только игрок и взрывы.
	return attacker == player() or source == "explosion"


func hurt(amount: int, source: String, attacker: Node3D, kb: Vector3, ignore_invuln := false) -> bool:
	if not _hit_head and source != "crystal":
		amount = int(amount / 4.0) + 1 if amount > 0 else 0
	_hit_head = false
	var ok := super.hurt(amount, source, attacker, Vector3.ZERO, ignore_invuln)
	if ok and not is_dead():
		# После удара меняет курс.
		_charging = false
		_charge_cd = rng.randf_range(8.0, 16.0)
		_angle += PI * 0.5
		_dest = Vector3.ZERO
	return ok


## Взрыв кристалла, от которого дракон лечился, ранит его на 10.
func crystal_destroyed(c: Mob) -> void:
	if c == _heal_from and not is_dead():
		_hit_head = true
		hurt(10, "crystal", player(), Vector3.ZERO, true)
		_heal_from = null


func die(source: String, attacker: Node3D) -> void:
	if death_time >= 0.0:
		return
	death_time = 0.0
	velocity = Vector3(0, 1.0, 0)
	sound("mob_death")
	if _beam != null:
		_beam.visible = false


## 10 секунд агонии: поднимается, взрывы, поток опыта; затем портал и яйцо.
func tick() -> void:
	if death_time < 0.0:
		super.tick()
		return
	prev_pos = position
	prev_yaw = yaw
	prev_head_yaw = head_yaw
	prev_head_pitch = head_pitch
	ticks += 1
	anim_time += TICK
	death_time += TICK
	position.y += TICK * 1.0
	yaw += 0.02
	hurt_time = 0.5
	_update_light(false)
	var m := manager()
	if ticks % 4 == 0:
		effect("explosion", 40)
	if ticks % 10 == 0 and m != null and _xp_left > 2000:
		m.spawn_xp(center(), 500)
		_xp_left -= 500
	if death_time >= 10.0:
		if m != null:
			m.spawn_xp(center(), _xp_left)
		_xp_left = 0
		_make_exit_portal()
		system.call("dragon_killed")
		system.call("remove_mob", self)


## Портал выхода (как в 1.2): чаша из коренной породы, порталы Края, столб с факелами и яйцом.
func _make_exit_portal() -> void:
	var px := 0
	var pz := 0
	var top := world.top_solid_y(px, pz)
	var y0 := top + 1 if top > 0 else 64
	for y in range(y0 - 1, y0 + 33):
		for z in range(pz - 4, pz + 5):
			for x in range(px - 4, px + 5):
				var dd := float((x - px) * (x - px) + (z - pz) * (z - pz))
				if dd > 3.5 * 3.5:
					continue
				if y < y0:
					if dd <= 2.5 * 2.5:
						world.set_block(x, y, z, Blocks.BEDROCK)
				elif y > y0:
					if world.get_block(x, y, z) != Blocks.AIR:
						world.set_block(x, y, z, Blocks.AIR)
				elif dd > 2.5 * 2.5:
					world.set_block(x, y, z, Blocks.BEDROCK)
				else:
					world.set_block(x, y, z, Blocks.END_PORTAL)
	for k in 4:
		world.set_block(px, y0 + k, pz, Blocks.BEDROCK)
	for f in [0, 1, 4, 5]:
		var d: Vector3i = Blocks.FACE_VEC[f]
		world.set_block(px + d.x, y0 + 2, pz + d.z, Blocks.TORCH, Blocks.attach_from_face(f))
	world.set_block(px, y0 + 4, pz, Blocks.DRAGON_EGG)


func animate(delta: float) -> void:
	super.animate(delta)
	if model == null:
		return
	model.root.rotation.x = -_pitch


func pose(_ph: float, _amt: float, _hy: float, _hp: float, t: float) -> void:
	var f := sin(_flap * 2.0)
	model.rot("rwing", Vector3(0.1, 0, f * 0.7 - 0.1))
	model.rot("lwing", Vector3(0.1, 0, -f * 0.7 + 0.1))
	model.rot("rwingtip", Vector3(0, 0, -(sin(_flap * 2.0 - 1.0) + 0.5) * 0.75))
	model.rot("lwingtip", Vector3(0, 0, (sin(_flap * 2.0 - 1.0) + 0.5) * 0.75))
	model.rot("jaw", Vector3(maxf(sin(t * 2.0), 0.0) * 0.4, 0, 0))
	for i in 5:
		model.shift("neck%d" % i, Vector3(sin(t * 1.5 + i * 0.6) * 0.8, sin(_flap * 2.0 + i * 0.4) * 1.5 - i * 0.6, 0))
	model.shift("head", Vector3(sin(t * 1.5 + 3.0) * 0.8, sin(_flap * 2.0 + 2.0) * 1.5 - 3.0, 0))
	for i in 12:
		var k := float(i) / 11.0
		model.shift("tail%d" % i, Vector3(sin(t * 1.2 - i * 0.45) * 3.0 * k, sin(_flap * 2.0 - i * 0.5) * 2.0 * k + i * 0.8, 0))


## Кристалл Края: лечит дракона, от любого удара взрывается (сила 6), под ним горит огонь.
class EndCrystal extends Mob:
	var _spin := 0.0

	func _setup() -> void:
		_spin = rng.randf_range(0, TAU)

	func model_key() -> String:
		return "end_crystal"

	func skin_keys() -> Array:
		return ["end_crystal"]

	func knockback_scale() -> float:
		return 0.0

	func _physics() -> void:
		pass

	func ai_tick() -> void:
		if ticks % 20 == 0 and world.dimension == 1:
			var c := Vector3i(floori(position.x), floori(position.y), floori(position.z))
			if world.get_block_v(c) == Blocks.AIR and Blocks.is_solid(world.get_block_v(c + Vector3i(0, -1, 0))):
				world.set_block(c.x, c.y, c.z, Blocks.FIRE)

	func _tick_hazards() -> void:
		pass

	func hurt(_amount: int, source: String, _attacker: Node3D, _kb: Vector3, _ignore := false) -> bool:
		if is_dead() or source in ["fire", "lava", "drown", "fall", "magic", "poison"]:
			return false
		removed = true
		var m := manager()
		var c := center()
		system.call("crystal_destroyed", self)
		system.call("remove_mob", self)
		if m != null and m.logic != null:
			m.logic.explode(c, 6.0, false, null)
		return true

	func add_effect(_id: int, _level: int, _seconds: float) -> void:
		pass

	func pose(_ph: float, _amt: float, _hy: float, _hp: float, t: float) -> void:
		var s := t * 3.0 + _spin
		model.set_rot("glass", Vector3(s * 0.7, s, 0.6))
		model.set_rot("cube", Vector3(0.6, -s * 1.3, s * 0.5))
		model.shift("glass", Vector3(0, sin(t * 2.0 + _spin) * 3.0 + 2.0, 0))
