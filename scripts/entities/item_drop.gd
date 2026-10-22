class_name ItemDrop
extends Node3D
## Выпавший предмет: маленький вращающийся блок с простой физикой. Подбирается игроком.

const SIZE := 0.25
const LIFETIME := 300.0
const PICKUP_DELAY := 0.6

var item_id := Blocks.DIRT
var count := 1
var world: World
var velocity := Vector3.ZERO
var age := 0.0
var _mesh: MeshInstance3D


func setup(p_world: World, id: int, cnt: int, pos: Vector3, vel: Vector3) -> void:
	world = p_world
	item_id = id
	count = cnt
	position = pos
	velocity = vel


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = TextureFactory.block_mesh(item_id)
	_mesh.material_override = TextureFactory.chunk_material
	_mesh.scale = Vector3.ONE * SIZE
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func can_pickup() -> bool:
	return age >= PICKUP_DELAY


func _process(delta: float) -> void:
	age += delta
	if age > LIFETIME:
		queue_free()
		return
	_mesh.rotation.y = age * 1.6
	_mesh.position.y = SIZE * 0.5 + 0.06 + sin(age * 2.5) * 0.05
	if world == null or not world.has_chunk_at(position.x, position.z):
		return
	var dt := minf(delta, 0.05)
	var here := world.get_block(floori(position.x), floori(position.y + 0.05), floori(position.z))
	if Blocks.is_solid(here):
		# Внутри блока (например, на предмет поставили блок) — выталкиваем вверх.
		position.y = floorf(position.y + 0.05) + 1.001
		velocity = Vector3.ZERO
		return
	if here == Blocks.WATER:
		velocity.y = maxf(velocity.y - 4.0 * dt, -1.2)
		velocity *= 0.96
	else:
		velocity.y = maxf(velocity.y - 18.0 * dt, -30.0)
	var next := position + velocity * dt
	if Blocks.is_solid(world.get_block(floori(next.x), floori(position.y + 0.1), floori(position.z))):
		next.x = position.x
		velocity.x *= -0.3
	if Blocks.is_solid(world.get_block(floori(next.x), floori(position.y + 0.1), floori(next.z))):
		next.z = position.z
		velocity.z *= -0.3
	if velocity.y < 0.0 and Blocks.is_solid(world.get_block(floori(next.x), floori(next.y), floori(next.z))):
		next.y = floorf(next.y) + 1.0
		velocity.y = 0.0
		velocity.x *= 0.6
		velocity.z *= 0.6
	elif velocity.y > 0.0 and Blocks.is_solid(world.get_block(floori(next.x), floori(next.y + SIZE), floori(next.z))):
		next.y = position.y
		velocity.y = 0.0
	position = next


func to_dict() -> Dictionary:
	return {"id": item_id, "count": count, "pos": [position.x, position.y, position.z]}
