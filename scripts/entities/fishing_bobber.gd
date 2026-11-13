class_name FishingBobber
extends Node3D
## Поплавок удочки (1.2): летит по дуге, плавает на воде и через 5–45 секунд (в дождь чаще)
## «клюёт» — ныряет на секунду. Если в этот момент подсечь, выпадает сырая рыба и немного опыта.

const GRAVITY := 18.0
const MAX_DISTANCE := 32.0

var world: World
var player: Player
var game: Node
var velocity := Vector3.ZERO
var in_water := false
var on_ground := false
var age := 0.0
var _wait := 0.0
var _bite := 0.0
var _rng := RandomNumberGenerator.new()
var _mesh: MeshInstance3D
var _line: MeshInstance3D
var _line_mesh := ImmediateMesh.new()


func _ready() -> void:
	_rng.randomize()
	_wait = _rng.randf_range(5.0, 45.0)
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.18, 0.18)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.15, 0.12)
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var top := MeshInstance3D.new()
	var cap := BoxMesh.new()
	cap.size = Vector3(0.12, 0.08, 0.12)
	top.mesh = cap
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(0.95, 0.95, 0.95)
	top.material_override = white
	top.position = Vector3(0, 0.12, 0)
	_mesh.add_child(top)
	_line = MeshInstance3D.new()
	_line.mesh = _line_mesh
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.1, 0.1, 0.1)
	_line.material_override = lm
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)


func is_biting() -> bool:
	return _bite > 0.0


func update_entity(dt: float) -> void:
	age += dt
	if player == null or player.dead or player.inventory.selected_id() != Items.FISHING_ROD \
			or player.position.distance_to(position) > MAX_DISTANCE:
		queue_free()
		return
	var cell := Vector3i(floori(position.x), floori(position.y), floori(position.z))
	var id := world.get_block_v(cell)
	in_water = Blocks.is_water(id)
	if in_water:
		# Плавает у поверхности воды.
		var surface := float(cell.y) + 0.9
		while Blocks.is_water(world.get_block(cell.x, int(surface) + 1, cell.z)) and surface < cell.y + 8:
			surface += 1.0
		velocity = velocity * 0.85
		var target_y := surface - 0.1 + sin(age * 3.0) * 0.03
		if _bite > 0.0:
			target_y -= 0.35
		position.y = lerpf(position.y, target_y, minf(dt * 6.0, 1.0))
		position.x += velocity.x * dt
		position.z += velocity.z * dt
		_update_fishing(dt)
	elif not on_ground:
		# Полёт считаем подшагами по 1/60 с, чтобы дальность заброса не зависела от FPS.
		var left := dt
		while left > 0.0 and not on_ground:
			var h := minf(left, 1.0 / 60.0)
			left -= h
			velocity.y -= GRAVITY * h
			var res := BodyPhysics.move(world, position, 0.1, 0.2, velocity * h, 0.0, false)
			position = res["pos"]
			if res["hit_y"] and velocity.y < 0.0:
				on_ground = true
				velocity = Vector3.ZERO
			if res["hit_x"]:
				velocity.x = 0.0
			if res["hit_z"]:
				velocity.z = 0.0
			if Blocks.is_water(world.get_block(floori(position.x), floori(position.y), floori(position.z))):
				break
	_draw_line()


func _update_fishing(dt: float) -> void:
	if _bite > 0.0:
		_bite -= dt
		if _bite <= 0.0:
			_wait = _rng.randf_range(5.0, 45.0)
		return
	var raining := game != null and game.get("weather") != null and float(game.get("weather").get("rain")) > 0.5
	_wait -= dt * (1.25 if raining else 1.0)
	if _wait <= 0.0:
		_bite = _rng.randf_range(0.6, 1.1)
		if game != null and game.has_method("effect"):
			game.call("effect", "splash", position)
			game.call("play_sound", "splash", position, 0.4)


func _draw_line() -> void:
	_line_mesh.clear_surfaces()
	if player == null or player.camera == null:
		return
	var tip := player.camera.global_transform * Vector3(0.38, -0.2, -0.75)
	var end := position + Vector3(0, 0.1, 0)
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# Леска чуть провисает.
	var prev := tip
	for k in range(1, 9):
		var t := k / 8.0
		var p := tip.lerp(end, t) - Vector3(0, sin(t * PI) * 0.4, 0)
		_line_mesh.surface_add_vertex(prev)
		_line_mesh.surface_add_vertex(p)
		prev = p
	_line_mesh.surface_end()


## Подсечь: true — рыба поймана.
func reel() -> int:
	var caught := 0
	if in_water and _bite > 0.0:
		caught = 1
	elif on_ground:
		caught = -1
	queue_free()
	return caught
