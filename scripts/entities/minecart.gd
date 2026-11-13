class_name Minecart
extends Node3D
## Вагонетка 1.2: обычная (в ней можно ехать), с сундуком (27 слотов) и с печью (едет на угле).
## Движется вдоль рельсов: скорость направлена по пути, на уклонах разгоняется, ускоряющий рельс
## под током толкает, без тока — тормозит; нажимной рельс включается, пока на нём вагонетка.

const MAX_SPEED := 8.0
const SLOPE_ACCEL := 4.4
const BOOST := 12.0
const FURNACE_SPEED := 4.0

var kind := "minecart"
var world: World
var manager: EntityManager
var velocity := Vector3.ZERO
var rider: Player
var hits := 0.0
var fuel := 0.0
var push := Vector3.ZERO
## Содержимое вагонетки с сундуком — в формате данных блока ({"items": …}).
var storage: Dictionary = {}
var _mesh: MeshInstance3D
var _detector := Vector3i(0, -999, 0)
var _yaw := 0.0
var _hurt := 0.0

static var _meshes: Dictionary = {}


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _model(kind)
	_mesh.material_override = TextureFactory.instance_material(TextureFactory.entity_material)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


static func _model(k: String) -> ArrayMesh:
	if _meshes.has(k):
		return _meshes[k]
	var iron := Tex.IRON_BLOCK
	var parts := [
		[AABB(Vector3(-0.5, 0.1, -0.4), Vector3(1.0, 0.08, 0.8)), iron, true],
		[AABB(Vector3(-0.5, 0.1, -0.4), Vector3(0.08, 0.55, 0.8)), iron, true],
		[AABB(Vector3(0.42, 0.1, -0.4), Vector3(0.08, 0.55, 0.8)), iron, true],
		[AABB(Vector3(-0.42, 0.1, -0.4), Vector3(0.84, 0.55, 0.08)), iron, true],
		[AABB(Vector3(-0.42, 0.1, 0.32), Vector3(0.84, 0.55, 0.08)), iron, true],
	]
	# Колёса.
	for x: float in [-0.32, 0.22]:
		for z: float in [-0.45, 0.4]:
			parts.append([AABB(Vector3(x, 0.0, z), Vector3(0.1, 0.16, 0.05)), Tex.OBSIDIAN])
	if k == "chest_minecart":
		parts.append([AABB(Vector3(-0.38, 0.18, -0.34), Vector3(0.76, 0.66, 0.68)),
			[Tex.CHEST_SIDE, Tex.CHEST_SIDE, Tex.CHEST_TOP, Tex.CHEST_TOP, Tex.CHEST_FRONT, Tex.CHEST_SIDE]])
	elif k == "furnace_minecart":
		parts.append([AABB(Vector3(-0.38, 0.18, -0.34), Vector3(0.76, 0.66, 0.68)),
			[Tex.FURNACE_FRONT, Tex.FURNACE_SIDE, Tex.FURNACE_TOP, Tex.FURNACE_TOP, Tex.FURNACE_SIDE, Tex.FURNACE_SIDE]])
	var m := BoxModel.build(parts)
	_meshes[k] = m
	return m


func item_id() -> int:
	match kind:
		"chest_minecart":
			return Items.CHEST_MINECART
		"furnace_minecart":
			return Items.FURNACE_MINECART
	return Items.MINECART


func body_box() -> AABB:
	return AABB(position + Vector3(-0.49, 0.0, -0.49), Vector3(0.98, 0.7, 0.98))


func seat_position() -> Vector3:
	return position + Vector3(0, -0.15, 0)


# --- Взаимодействие ------------------------------------------------------------

## Правый клик: сесть, открыть сундук, подбросить угля в печь.
func interact(player: Player) -> bool:
	match kind:
		"minecart":
			if rider == null and player.vehicle == null:
				rider = player
				player.mount(self)
				return true
		"chest_minecart":
			var g := manager.game
			if g != null and g.has_method("open_entity_container"):
				if not storage.has("items"):
					storage["items"] = []
				g.call("open_entity_container", "chest", storage)
				return true
		"furnace_minecart":
			if player.inventory.selected_id() == Items.COAL:
				if not player.creative:
					player.inventory.consume_selected(1)
				fuel += 180.0
				var d := position - player.position
				push = Vector3(d.x, 0, d.z).normalized()
				return true
	return false


func remove_rider() -> void:
	rider = null


## Удар: несколько ударов (в креативе — один) разбивают вагонетку.
func hit(player: Player, _damage: int) -> void:
	hits += 10.0
	_hurt = 0.3
	velocity += (position - player.position).normalized() * Vector3(1, 0, 1) * 2.0
	if hits >= 40.0 or player.creative:
		if rider != null:
			rider.dismount()
		if not player.creative:
			manager.spawn_drop(Items.MINECART, 1, 0, position + Vector3(0, 0.5, 0))
			if kind == "chest_minecart":
				manager.spawn_drop(Blocks.CHEST, 1, 0, position + Vector3(0, 0.6, 0))
				var inv := Containers.load_items(storage, 27)
				for i in 27:
					if inv.counts[i] > 0:
						manager.spawn_drop(inv.ids[i], inv.counts[i], inv.datas[i], position + Vector3(0, 0.6, 0))
			elif kind == "furnace_minecart":
				manager.spawn_drop(Blocks.FURNACE, 1, 0, position + Vector3(0, 0.6, 0))
		_clear_detector()
		queue_free()


# --- Движение -------------------------------------------------------------------

func update_entity(dt: float) -> void:
	if world == null or not world.has_chunk_at(position.x, position.z):
		return
	hits = maxf(hits - dt * 10.0, 0.0)
	_hurt = maxf(_hurt - dt, 0.0)
	var steps := clampi(ceili(velocity.length() * dt / 0.3), 1, 8)
	for s in steps:
		_step(dt / steps)
	# Игрок, идущий в вагонетку, толкает её.
	var pl := manager.player
	if pl != null and rider == null and pl.vehicle == null and not pl.dead and pl.body_box().intersects(body_box()):
		var d := position - pl.position
		d.y = 0.0
		if d.length() > 0.01:
			velocity += d.normalized() * 6.0 * dt
	_update_visual(dt)


func _rail_cell() -> Vector3i:
	var cell := Vector3i(floori(position.x), floori(position.y), floori(position.z))
	if Rails.is_rail(world.get_block_v(cell)):
		return cell
	var below := cell + Vector3i(0, -1, 0)
	if Rails.is_rail(world.get_block_v(below)):
		return below
	return Vector3i(0, -999, 0)


func _step(dt: float) -> void:
	var rail := _rail_cell()
	if rail.y <= -999:
		_clear_detector()
		_free_move(dt)
		return
	var id := world.get_block_v(rail)
	var meta := world.get_meta_v(rail)
	var shape := Rails.shape_of(id, meta)
	var seg := Rails.segment(rail, shape)
	var a: Vector3 = seg[0]
	var b: Vector3 = seg[1]
	var dir := (b - a).normalized()
	# Прижимаемся к линии пути.
	var t := clampf((position - a).dot(dir), 0.0, (b - a).length())
	position = a + dir * t
	var speed := velocity.dot(dir)
	if absf(speed) < 0.01 and velocity.length() > 0.01:
		speed = velocity.length() * signf(velocity.dot(dir) + 0.0001)
	# Уклон: ускорение вдоль пути ≈ 3,1 блока/с², как в 1.2.
	speed -= SLOPE_ACCEL * dir.y * dt
	# Ускоряющий рельс: под током толкает, без тока тормозит.
	if id == Blocks.POWERED_RAIL:
		if meta & 8:
			if absf(speed) > 0.05:
				speed += signf(speed) * BOOST * dt
			else:
				# Стоя у стены, вагонетка отталкивается от неё.
				var ends := Rails.ends(shape)
				for k in 2:
					var c := Rails.end_cell(rail, ends[k])
					if Blocks.is_solid(world.get_block_v(c)):
						speed = (1.0 if k == 0 else -1.0) * 2.0
		else:
			speed = move_toward(speed, 0.0, 30.0 * dt)
	# Нажимной рельс.
	if id == Blocks.DETECTOR_RAIL:
		if _detector != rail:
			_clear_detector()
			_detector = rail
			if meta & 8 == 0:
				world.set_block(rail.x, rail.y, rail.z, id, meta | 8)
	else:
		_clear_detector()
	# Едущий игрок разгоняет вагонетку взглядом и «вперёд».
	if rider != null:
		var mv := rider.get_move_input()
		if mv.y < -0.3:
			var look := Vector3(-sin(rider.yaw), 0, -cos(rider.yaw))
			var push_k := look.dot(dir)
			if absf(speed) < 3.0:
				speed += push_k * 3.0 * dt
	# Вагонетка с печью тянет сама.
	if kind == "furnace_minecart" and fuel > 0.0:
		fuel -= dt
		var pk := push.dot(dir)
		if absf(pk) > 0.1:
			speed = move_toward(speed, signf(pk) * FURNACE_SPEED, 6.0 * dt)
	# Трение.
	speed *= exp(-(0.06 if rider != null or kind != "minecart" else 0.4) * dt)
	speed = clampf(speed, -MAX_SPEED, MAX_SPEED)
	if absf(speed) < 0.02:
		speed = 0.0
	velocity = dir * speed
	var np := position + velocity * dt
	var nt := (np - a).dot(dir)
	var length := (b - a).length()
	if nt > length or nt < 0.0:
		# Конец рельса: дальше — следующий рельс, стена (стоп) или обрыв (слетаем).
		var end_idx := 1 if nt > length else 0
		var e: Array = Rails.ends(shape)[end_idx]
		var next := Rails.end_cell(rail, e)
		var next_rail := Rails.is_rail(world.get_block_v(next)) or Rails.is_rail(world.get_block_v(next + Vector3i(0, -1, 0)))
		if not next_rail and Blocks.is_solid(world.get_block_v(next)):
			position = b if end_idx == 1 else a
			velocity = Vector3.ZERO
			return
		# Переходим в следующую клетку, сохраняя скорость по направлению конца.
		var out_dir := Vector3(e[0] as Vector3i)
		var spd := absf(speed)
		position = (b if end_idx == 1 else a) + out_dir * 0.02
		velocity = out_dir * spd
		if not next_rail:
			position.y += 0.01
		return
	position = np


func _free_move(dt: float) -> void:
	velocity.y -= 20.0 * dt
	var res := BodyPhysics.move(world, position, 0.45, 0.7, velocity * dt, 0.0, false)
	position = res["pos"]
	if res["hit_y"]:
		velocity.y = 0.0
		velocity.x *= exp(-4.0 * dt)
		velocity.z *= exp(-4.0 * dt)
	if res["hit_x"]:
		velocity.x = 0.0
	if res["hit_z"]:
		velocity.z = 0.0
	if Blocks.is_water(world.get_block(floori(position.x), floori(position.y), floori(position.z))):
		velocity *= exp(-3.0 * dt)
	if position.y < -64.0:
		queue_free()


func _clear_detector() -> void:
	if _detector.y <= -999:
		return
	var id := world.get_block_v(_detector)
	if id == Blocks.DETECTOR_RAIL:
		var m := world.get_meta_v(_detector)
		if m & 8:
			world.set_block(_detector.x, _detector.y, _detector.z, id, m & 7)
	_detector = Vector3i(0, -999, 0)


func _update_visual(dt: float) -> void:
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.05:
		_yaw = lerp_angle(_yaw, atan2(flat.x, flat.y), minf(dt * 10.0, 1.0))
	_mesh.rotation = Vector3(0, _yaw, 0)
	if velocity.length() > 0.05:
		var pitch := asin(clampf(velocity.normalized().y, -1.0, 1.0))
		_mesh.rotation.x = -pitch
	BoxModel.light(_mesh, world, position)
	if _hurt > 0.0:
		TextureFactory.set_light(_mesh, 1.0, 0.0, 0.6)


func to_dict() -> Dictionary:
	var d := {"kind": kind, "pos": [position.x, position.y, position.z], "vel": [velocity.x, velocity.y, velocity.z]}
	if kind == "chest_minecart":
		d["storage"] = storage
	if kind == "furnace_minecart":
		d["fuel"] = fuel
		d["push"] = [push.x, push.z]
	return d


func from_dict(d: Dictionary) -> void:
	var v: Array = d.get("vel", [0, 0, 0])
	if v.size() == 3:
		velocity = Vector3(float(v[0]), float(v[1]), float(v[2]))
	if d.get("storage") is Dictionary:
		storage = d["storage"]
	fuel = float(d.get("fuel", 0.0))
	var p: Array = d.get("push", [0, 0])
	if p.size() == 2:
		push = Vector3(float(p[0]), 0, float(p[1]))
