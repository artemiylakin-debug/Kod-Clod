class_name Boat
extends Node3D
## Лодка 1.2: держится на поверхности воды, плывёт туда, куда смотрит сидящий в ней игрок;
## на суше еле ползёт. Если на полном ходу врезаться в берег, разбивается на доски и палки (как в 1.2).

const WATER_SPEED := 8.0
const LAND_SPEED := 1.0
const CRASH_SPEED := 6.5

var kind := "boat"
var world: World
var manager: EntityManager
var velocity := Vector3.ZERO
var rider: Player
var yaw := 0.0
var hits := 0.0
var _mesh: MeshInstance3D
var _hurt := 0.0
var _bob := 0.0

static var _boat_mesh: ArrayMesh


func _ready() -> void:
	if _boat_mesh == null:
		var w := Tex.PLANKS_OAK
		_boat_mesh = BoxModel.build([
			[AABB(Vector3(-0.75, 0.0, -0.45), Vector3(1.5, 0.12, 0.9)), w, true],
			[AABB(Vector3(-0.75, 0.0, -0.5), Vector3(1.5, 0.4, 0.1)), w, true],
			[AABB(Vector3(-0.75, 0.0, 0.4), Vector3(1.5, 0.4, 0.1)), w, true],
			[AABB(Vector3(-0.85, 0.0, -0.45), Vector3(0.12, 0.4, 0.9)), w, true],
			[AABB(Vector3(0.73, 0.0, -0.45), Vector3(0.12, 0.4, 0.9)), w, true],
		])
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _boat_mesh
	_mesh.material_override = TextureFactory.instance_material(TextureFactory.entity_material)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func item_id() -> int:
	return Items.BOAT


func body_box() -> AABB:
	return AABB(position + Vector3(-0.75, 0.0, -0.75), Vector3(1.5, 0.6, 1.5))


func seat_position() -> Vector3:
	return position + Vector3(0, -0.3, 0)


func interact(player: Player) -> bool:
	if rider == null and player.vehicle == null:
		rider = player
		player.mount(self)
		yaw = player.yaw
		return true
	return false


func remove_rider() -> void:
	rider = null


func hit(player: Player, _damage: int) -> void:
	hits += 10.0
	_hurt = 0.3
	if hits >= 40.0 or player.creative:
		if rider != null:
			rider.dismount()
		if not player.creative:
			manager.spawn_drop(Items.BOAT, 1, 0, position + Vector3(0, 0.5, 0))
		queue_free()


## Вода в клетке и уровень её поверхности.
func _water_surface() -> float:
	var cell := Vector3i(floori(position.x), floori(position.y + 0.2), floori(position.z))
	if not Blocks.is_water(world.get_block_v(cell)):
		var below := cell + Vector3i(0, -1, 0)
		if Blocks.is_water(world.get_block_v(below)):
			return float(below.y) + 0.88
		return -INF
	var top := cell
	while Blocks.is_water(world.get_block_v(top + Vector3i(0, 1, 0))) and top.y < cell.y + 6:
		top.y += 1
	return float(top.y) + 0.88


func update_entity(dt: float) -> void:
	if world == null or not world.has_chunk_at(position.x, position.z):
		return
	hits = maxf(hits - dt * 10.0, 0.0)
	_hurt = maxf(_hurt - dt, 0.0)
	var surface := _water_surface()
	var on_water := surface > -INF
	# Плавучесть: тянемся к поверхности воды.
	if on_water:
		var target := surface - 0.12 + sin(_bob) * 0.02
		_bob += dt * 2.0
		velocity.y = (target - position.y) * 6.0
	else:
		velocity.y -= 20.0 * dt
	# Управление.
	var max_speed := WATER_SPEED if on_water else LAND_SPEED
	if rider != null:
		yaw = lerp_angle(yaw, rider.yaw, minf(dt * 4.0, 1.0))
		var mv := rider.get_move_input()
		var fwd := Vector3(-sin(rider.yaw), 0, -cos(rider.yaw))
		var right := Vector3(cos(rider.yaw), 0, -sin(rider.yaw))
		var wish := (right * mv.x - fwd * mv.y)
		var flat := Vector3(velocity.x, 0, velocity.z)
		flat = flat.move_toward(wish * max_speed, (4.0 if on_water else 8.0) * dt)
		velocity.x = flat.x
		velocity.z = flat.z
	var drag := exp(-(0.6 if on_water else 6.0) * dt)
	velocity.x *= drag
	velocity.z *= drag
	var speed_before := Vector2(velocity.x, velocity.z).length()
	var res := BodyPhysics.move(world, position, 0.7, 0.55, velocity * dt, 0.0, false)
	position = res["pos"]
	if res["hit_y"]:
		velocity.y = 0.0
	if res["hit_x"] or res["hit_z"]:
		# Удар о берег на полном ходу — лодка разбивается (1.2).
		if speed_before > CRASH_SPEED:
			_crash()
			return
		if res["hit_x"]:
			velocity.x = 0.0
		if res["hit_z"]:
			velocity.z = 0.0
	_mesh.rotation = Vector3(0, yaw + PI / 2.0, 0)
	BoxModel.light(_mesh, world, position)
	if _hurt > 0.0:
		TextureFactory.set_light(_mesh, 1.0, 0.0, 0.6)
	if position.y < -64.0:
		queue_free()


func _crash() -> void:
	if rider != null:
		rider.dismount()
	manager.spawn_drop(Blocks.PLANKS, 3, 0, position + Vector3(0, 0.5, 0))
	manager.spawn_drop(Items.STICK, 2, 0, position + Vector3(0, 0.5, 0))
	if manager.game != null and manager.game.has_method("play_sound"):
		manager.game.call("play_sound", "dig_wood", position, 1.0)
	queue_free()


func to_dict() -> Dictionary:
	return {"kind": "boat", "pos": [position.x, position.y, position.z], "yaw": yaw}


func from_dict(d: Dictionary) -> void:
	yaw = float(d.get("yaw", 0.0))
