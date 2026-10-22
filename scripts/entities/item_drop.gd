class_name ItemDrop
extends Node3D
## Выпавший предмет: маленький вращающийся блок или спрайт с простой физикой. Подбирается игроком,
## одинаковые предметы рядом объединяются в одну стопку (как в оригинале).

const SIZE := 0.25
const LIFETIME := 300.0
const PICKUP_DELAY := 0.6

var kind := "item"
var item_id := Blocks.DIRT
var count := 1
var data := 0
var world: World
var velocity := Vector3.ZERO
var age := 0.0
var _mesh: MeshInstance3D
var _block_like := true


func setup(p_world: World, id: int, cnt: int, p_data: int, pos: Vector3, vel: Vector3) -> void:
	world = p_world
	item_id = id
	count = cnt
	data = p_data
	position = pos
	velocity = vel


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = TextureFactory.item_mesh(item_id, data)
	_mesh.material_override = TextureFactory.instance_material(TextureFactory.entity_material)
	_block_like = Items.is_block(item_id) and not Items.is_flat_block(item_id)
	_mesh.scale = Vector3.ONE * (SIZE if _block_like else SIZE * 1.6)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	# Стопка из нескольких предметов показывается несколькими копиями.
	if count > 1:
		var extra := MeshInstance3D.new()
		extra.mesh = _mesh.mesh
		extra.material_override = _mesh.material_override
		extra.position = Vector3(0.12, 0.08, 0.1) / _mesh.scale.x
		extra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh.add_child(extra)


func can_pickup() -> bool:
	return age >= PICKUP_DELAY


func update_entity(delta: float) -> void:
	age += delta
	if age > LIFETIME:
		queue_free()
		return
	_mesh.rotation.y = age * 1.6
	_mesh.position.y = SIZE * 0.5 + 0.06 + sin(age * 2.5) * 0.05
	if world == null or not world.has_chunk_at(position.x, position.z):
		return
	var cell := Vector3i(floori(position.x), floori(position.y + 0.1), floori(position.z))
	TextureFactory.set_light(_mesh, world.get_sky_light(cell) / 15.0, ChunkMesher.block_curve[clampi(world.get_block_light(cell), 0, 15)])
	var dt := minf(delta, 0.05)
	var here := world.get_block(floori(position.x), floori(position.y + 0.05), floori(position.z))
	if Blocks.is_lava(here) or here == Blocks.FIRE:
		queue_free()
		return
	if Blocks.is_opaque(here):
		# Внутри блока (например, на предмет поставили блок) — выталкиваем вверх.
		position.y = floorf(position.y + 0.05) + 1.001
		velocity = Vector3.ZERO
		return
	if Blocks.is_water(here):
		velocity.y = maxf(velocity.y - 4.0 * dt, -1.2)
		velocity *= 0.96
		# Течение воды сносит предметы.
		velocity += _water_push(Vector3i(floori(position.x), floori(position.y + 0.05), floori(position.z))) * dt
	else:
		velocity.y = maxf(velocity.y - 18.0 * dt, -30.0)
	var res := BodyPhysics.move(world, position, 0.125, 0.25, velocity * dt, 0.0, false)
	position = res["pos"]
	if res["hit_x"]:
		velocity.x *= -0.3
	if res["hit_z"]:
		velocity.z *= -0.3
	if res["hit_y"]:
		if velocity.y < 0.0:
			velocity.x *= 0.6
			velocity.z *= 0.6
		velocity.y = 0.0


## Направление течения: к соседям с более «мелкой» водой.
func _water_push(p: Vector3i) -> Vector3:
	var m := world.get_meta_v(p)
	var level := 0 if m >= 8 else m
	var push := Vector3.ZERO
	for d in 4:
		var q: Vector3i = p + Blocks.DIR_VEC[d]
		var b := world.get_block_v(q)
		if Blocks.is_water(b):
			var qm := world.get_meta_v(q)
			var ql := 0 if qm >= 8 else qm
			if ql > level:
				push += Vector3(Blocks.DIR_VEC[d]) * 2.0
		elif b == Blocks.AIR:
			push += Vector3(Blocks.DIR_VEC[d]) * 1.0
	return push


func to_dict() -> Dictionary:
	return {"kind": "item", "id": item_id, "count": count, "data": data, "pos": [position.x, position.y, position.z]}
