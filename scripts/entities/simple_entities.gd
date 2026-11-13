class_name SimpleEntities
extends RefCounted
## Вспомогательные сущности: шарик опыта, падающий блок, подожжённый динамит, снаряд, око Края.
## Каждая — Node3D с update_entity(dt), to_dict() и полем kind.


class XpOrb extends Node3D:
	var kind := "xp"
	var world: World
	var amount := 1
	var velocity := Vector3.ZERO
	var age := 0.0
	var _mesh: MeshInstance3D

	func _ready() -> void:
		_mesh = MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.09 + minf(amount, 20) * 0.006
		m.height = m.radius * 2.0
		m.radial_segments = 8
		m.rings = 4
		_mesh.mesh = m
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.55, 1.0, 0.2)
		_mesh.material_override = mat
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)

	func update_entity(dt: float) -> void:
		age += dt
		if age > 300.0:
			queue_free()
			return
		(_mesh.material_override as StandardMaterial3D).albedo_color = Color(0.55 + sin(age * 6.0) * 0.2, 1.0, 0.2)
		_mesh.position.y = 0.15 + sin(age * 3.0) * 0.04
		if world == null:
			return
		velocity.y = maxf(velocity.y - 10.0 * dt, -10.0)
		velocity.x *= 0.95
		velocity.z *= 0.95
		var res := BodyPhysics.move(world, position, 0.1, 0.2, velocity * dt, 0.0, false)
		position = res["pos"]
		if res["hit_y"]:
			velocity.y = 0.0

	func attract(target: Vector3, dt: float) -> void:
		var d := target - position
		var dist := d.length()
		if dist > 0.01:
			velocity = d / dist * minf(8.0, 2.0 + 10.0 / maxf(dist, 0.5))
			position += velocity * dt

	func to_dict() -> Dictionary:
		return {"kind": "xp", "amount": amount, "pos": [position.x, position.y, position.z]}


class FallingBlock extends Node3D:
	var kind := "falling"
	var world: World
	var logic: BlockLogic
	var block_id := Blocks.SAND
	var meta := 0
	var velocity := Vector3.ZERO
	var age := 0.0
	var _mesh: MeshInstance3D

	func _ready() -> void:
		_mesh = MeshInstance3D.new()
		_mesh.mesh = TextureFactory.item_mesh(block_id, meta)
		_mesh.material_override = TextureFactory.instance_material(TextureFactory.entity_material)
		_mesh.position.y = 0.5
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)

	func update_entity(dt: float) -> void:
		age += dt
		if world == null:
			return
		velocity.y = maxf(velocity.y - 30.0 * dt, -40.0)
		var res := BodyPhysics.move(world, position, 0.49, 0.98, velocity * dt, 0.0, false)
		position = res["pos"]
		var cell := Vector3i(floori(position.x), floori(position.y + 0.5), floori(position.z))
		TextureFactory.set_light(_mesh, world.get_sky_light(cell) / 15.0, ChunkMesher.block_curve[clampi(world.get_block_light(cell), 0, 15)])
		if res["hit_y"] or age > 30.0 or position.y < -64.0:
			if logic != null:
				logic.land_falling_block(Vector3i(floori(position.x), roundi(position.y), floori(position.z)), block_id, meta)
			queue_free()

	func to_dict() -> Dictionary:
		return {"kind": "falling", "id": block_id, "meta": meta, "pos": [position.x, position.y, position.z]}


class PrimedTnt extends Node3D:
	var kind := "tnt"
	var world: World
	var logic: BlockLogic
	var fuse := 4.0
	var velocity := Vector3(0, 2.0, 0)
	var _mesh: MeshInstance3D

	func _ready() -> void:
		_mesh = MeshInstance3D.new()
		_mesh.mesh = TextureFactory.item_mesh(Blocks.TNT, 0)
		_mesh.material_override = TextureFactory.instance_material(TextureFactory.entity_material)
		_mesh.position.y = 0.5
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)

	func update_entity(dt: float) -> void:
		fuse -= dt
		# Мигает белым перед взрывом.
		var flash := 1.0 if fmod(fuse, 0.4) < 0.2 else 0.0
		TextureFactory.set_light(_mesh, 1.0, flash)
		_mesh.scale = Vector3.ONE * (1.0 + maxf(0.0, 0.5 - fuse) * 0.3)
		if world != null:
			velocity.y = maxf(velocity.y - 20.0 * dt, -30.0)
			velocity.x *= 0.9
			velocity.z *= 0.9
			var res := BodyPhysics.move(world, position, 0.49, 0.98, velocity * dt, 0.0, false)
			position = res["pos"]
			if res["hit_y"]:
				velocity.y = 0.0
		if fuse <= 0.0:
			queue_free()
			if logic != null:
				logic.explode(position + Vector3(0, 0.5, 0), 4.0, false, null)

	func to_dict() -> Dictionary:
		return {"kind": "tnt", "fuse": fuse, "pos": [position.x, position.y, position.z]}


## Снаряды: стрела, снежок, яйцо, жемчуг Края, пузырёк опыта, взрывное зелье, огненный шар.
class Projectile extends Node3D:
	var kind := "projectile"
	var type := "arrow"
	var world: World
	var manager: Node
	var shooter: Node3D
	var velocity := Vector3.ZERO
	var damage := 2.0
	var data := 0
	var stuck := false
	var from_player := false
	var age := 0.0
	var _mesh: MeshInstance3D

	func _ready() -> void:
		_mesh = MeshInstance3D.new()
		var tex := Items.ARROW
		match type:
			"snowball":
				tex = Items.SNOWBALL
			"egg":
				tex = Items.EGG
			"ender_pearl":
				tex = Items.ENDER_PEARL
			"xp_bottle":
				tex = Items.EXPERIENCE_BOTTLE
			"potion":
				tex = Items.POTION
			"fireball", "small_fireball":
				tex = Items.FIRE_CHARGE
		_mesh.mesh = TextureFactory.item_mesh(tex, data)
		_mesh.material_override = TextureFactory.instance_material(TextureFactory.entity_material)
		_mesh.scale = Vector3.ONE * (0.5 if type == "arrow" else (1.0 if type == "fireball" else 0.35))
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)

	func update_entity(dt: float) -> void:
		age += dt
		if age > (60.0 if stuck else 30.0):
			queue_free()
			return
		if world == null:
			return
		var cell := Vector3i(floori(position.x), floori(position.y), floori(position.z))
		var glow := 1.0 if type.ends_with("fireball") else ChunkMesher.block_curve[clampi(world.get_block_light(cell), 0, 15)]
		TextureFactory.set_light(_mesh, world.get_sky_light(cell) / 15.0, glow)
		if stuck:
			return
		var gravity := 20.0 if type == "arrow" else (0.0 if type.ends_with("fireball") else 12.0)
		velocity.y -= gravity * dt
		var step := velocity * dt
		var origin := position
		var hit := world.raycast(origin, step.normalized(), step.length() + 0.05)
		# Попадание в существо.
		if manager != null and manager.has_method("projectile_hit_test"):
			var who: Variant = manager.call("projectile_hit_test", self, origin, origin + step)
			if who != null:
				manager.call("projectile_hit", self, who)
				if type != "arrow" or not is_instance_valid(self):
					return
		if not hit.is_empty() and Blocks.is_solid(int(hit["block"])):
			position = hit["hit"]
			if manager != null:
				manager.call("projectile_block_hit", self, hit)
			return
		position += step
		if velocity.length_squared() > 0.01:
			look_at(position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)

	func to_dict() -> Dictionary:
		if type != "arrow" or not stuck:
			return {}
		return {"kind": "arrow", "pos": [position.x, position.y, position.z]}


## Брошенное око Края (EntityEnderEye 1.2): летит к ближайшей крепости — не дальше 12 блоков
## по горизонтали и с подъёмом на 8, — зависает и через 4 секунды падает предметом (в 4 случаях
## из 5) или разбивается.
class EnderEye extends Node3D:
	var kind := "ender_eye"
	var world: World
	var manager: Node
	var target := Vector3.ZERO
	## Скорость в блоках за тик (1/20 с), как в оригинале.
	var motion := Vector3.ZERO
	var drops := true
	var ticks := 0
	var _acc := 0.0
	var _mesh: MeshInstance3D

	## Цель — точка крепости (x, 64, z); rng решает, уцелеет ли око.
	func aim(stronghold: Vector3, rng: RandomNumberGenerator) -> void:
		var dx := stronghold.x - position.x
		var dz := stronghold.z - position.z
		var dist := sqrt(dx * dx + dz * dz)
		if dist > 12.0:
			target = Vector3(position.x + dx / dist * 12.0, position.y + 8.0, position.z + dz / dist * 12.0)
		else:
			target = stronghold
		drops = rng.randi_range(0, 4) > 0

	func _ready() -> void:
		_mesh = MeshInstance3D.new()
		_mesh.mesh = TextureFactory.item_mesh(Items.ENDER_EYE, 0)
		_mesh.material_override = TextureFactory.instance_material(TextureFactory.entity_material)
		_mesh.scale = Vector3.ONE * 0.4
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)

	func update_entity(dt: float) -> void:
		_acc += dt
		while _acc >= 0.05 and not is_queued_for_deletion():
			_acc -= 0.05
			_tick()
		if is_queued_for_deletion() or world == null:
			return
		var cell := Vector3i(floori(position.x), floori(position.y), floori(position.z))
		TextureFactory.set_light(_mesh, world.get_sky_light(cell) / 15.0, 0.6)
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null and cam.global_position.distance_squared_to(global_position) > 0.01:
			_mesh.look_at(cam.global_position, Vector3.UP)

	func _tick() -> void:
		position += motion
		var horiz := Vector2(motion.x, motion.z).length()
		var dx := target.x - position.x
		var dz := target.z - position.z
		var d := sqrt(dx * dx + dz * dz)
		var angle := atan2(dz, dx)
		var speed := horiz + (d - horiz) * 0.0025
		if d < 1.0:
			speed *= 0.8
			motion.y *= 0.8
		motion.x = cos(angle) * speed
		motion.z = sin(angle) * speed
		if position.y < target.y:
			motion.y += (1.0 - motion.y) * 0.015
		else:
			motion.y += (-1.0 - motion.y) * 0.015
		ticks += 1
		if manager != null and ticks % 2 == 0:
			manager.call("_fx", "portal_trail", position - motion * 0.25)
		if ticks > 80:
			if manager != null:
				if drops:
					manager.call("spawn_drop", Items.ENDER_EYE, 1, 0, position, Vector3.ZERO)
				else:
					manager.call("_fx", "eye_shatter", position)
					manager.call("_fx_sound", "glass_break", position, 0.8)
			queue_free()

	func to_dict() -> Dictionary:
		return {}
