class_name Weather
extends Node3D
## Погода обычного мира (1.2): дождь, снег в холодных биомах, грозы с молниями.
## Осадки рисуются полосами вокруг камеры: в каждой колонке — от поверхности до высоты над игроком,
## поэтому под крышей дождя нет. Во время снегопада на холодных биомах ложится снег и замерзает вода.

signal lightning_struck(pos: Vector3)

const RADIUS := 5
const ABOVE := 14.0
const BELOW := 10.0

const PRECIP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform float strength = 1.0;
uniform float speed = 6.0;
uniform float light = 1.0;

varying float v_fade;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(world_pos.xz - CAMERA_POSITION_WORLD.xz);
	// Вблизи камеры и у края круга полосы прозрачнее.
	v_fade = clamp((d - 0.6) / 1.4, 0.0, 1.0) * clamp((5.5 - d) / 2.5, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV + vec2(UV2.x, TIME * speed * (0.8 + UV2.y * 0.4));
	vec4 c = texture(tex, uv);
	ALBEDO = c.rgb * light;
	ALPHA = c.a * strength * v_fade;
}
"""

var world: World
var logic: BlockLogic
var game: Node
var player: Player

## 0..1 — плавно нарастающая сила дождя и грозы.
var rain := 0.0
var thunder := 0.0
var raining := false
var thundering := false
var rain_time := 0.0
var thunder_time := 0.0
var rng := RandomNumberGenerator.new()

var _mesh: MeshInstance3D
var _snow_mesh: MeshInstance3D
var _rain_mat: ShaderMaterial
var _snow_mat: ShaderMaterial
var _last_cell := Vector3i(1 << 30, 0, 0)
var _rebuild_cooldown := 0.0
var _next_bolt := 10.0
var _bolts: Array[Dictionary] = []
var _flash := 0.0
var _snow_acc := 0.0


func setup(p_world: World, p_logic: BlockLogic, p_game: Node, p_player: Player) -> void:
	world = p_world
	logic = p_logic
	game = p_game
	player = p_player
	rng.randomize()
	rain_time = rng.randf_range(300.0, 1800.0)
	thunder_time = rng.randf_range(600.0, 3600.0)
	_rain_mat = _material(_paint_rain(), 7.0)
	_snow_mat = _material(_paint_snow(), 0.6)
	_mesh = MeshInstance3D.new()
	_mesh.material_override = _rain_mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_snow_mesh = MeshInstance3D.new()
	_snow_mesh.material_override = _snow_mat
	_snow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_snow_mesh)


func _material(tex: Texture2D, speed: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = PRECIP_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("speed", speed)
	return m


## Текстура струй дождя (тайлится по вертикали).
func _paint_rain() -> Texture2D:
	var img := Image.create(16, 64, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for k in 9:
		var x := r.randi_range(0, 15)
		var y0 := r.randi_range(0, 63)
		var streak := r.randi_range(6, 12)
		for i in streak:
			var a := 0.2 + 0.45 * float(i) / streak
			img.set_pixel(x, (y0 + i) % 64, Color(0.7, 0.78, 0.98, a))
	return ImageTexture.create_from_image(img)


func _paint_snow() -> Texture2D:
	var img := Image.create(16, 64, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	for k in 22:
		var x := r.randi_range(0, 14)
		var y := r.randi_range(0, 62)
		img.set_pixel(x, y, Color(1, 1, 1, 0.95))
		if r.randf() < 0.5:
			img.set_pixel(x + 1, y, Color(0.92, 0.94, 1.0, 0.8))
			img.set_pixel(x, y + 1, Color(0.92, 0.94, 1.0, 0.8))
	return ImageTexture.create_from_image(img)


# --- Состояние ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"raining": raining, "thundering": thundering, "rain_time": rain_time, "thunder_time": thunder_time}


func from_dict(d: Dictionary) -> void:
	raining = bool(d.get("raining", false))
	thundering = bool(d.get("thundering", false))
	rain_time = float(d.get("rain_time", rain_time))
	thunder_time = float(d.get("thunder_time", thunder_time))
	rain = 1.0 if raining else 0.0
	thunder = 1.0 if thundering and raining else 0.0


func set_weather(p_rain: bool, p_thunder: bool) -> void:
	raining = p_rain
	thundering = p_thunder
	rain_time = rng.randf_range(600.0, 1200.0) if raining else rng.randf_range(300.0, 1800.0)
	thunder_time = rng.randf_range(180.0, 600.0) if thundering else rng.randf_range(600.0, 3600.0)


## Насколько погода затемняет небо (0 — ясно).
func darkness() -> float:
	return rain * 0.3 + thunder * 0.35


## Вспышка молнии (0..1) — подсвечивает небо.
func flash() -> float:
	return _flash


func is_precipitating_at(p: Vector3) -> bool:
	if rain < 0.2:
		return false
	var b := world.biome_at(floori(p.x), floori(p.z))
	return not Biomes.is_dry(b) and _column_top(floori(p.x), floori(p.z), p.y + 3.0) <= p.y


## Верх колонки для осадков: первый твёрдый блок или жидкость сверху вниз.
func _column_top(x: int, z: int, from_y: float) -> int:
	var hm := world.height_at(x, z)
	var y := mini(floori(from_y), WorldGen.CHUNK_HEIGHT - 1)
	while y > hm:
		var id := world.get_block(x, y, z)
		if Blocks.is_solid(id) or Blocks.is_liquid(id) or id == Blocks.LEAVES:
			return y
		y -= 1
	return hm


# --- Кадр --------------------------------------------------------------------

func update(delta: float, cam: Vector3) -> void:
	if world.dimension != 0:
		visible = false
		return
	rain_time -= delta
	if rain_time <= 0.0:
		raining = not raining
		rain_time = rng.randf_range(600.0, 1200.0) if raining else rng.randf_range(300.0, 1800.0)
	thunder_time -= delta
	if thunder_time <= 0.0:
		thundering = not thundering
		thunder_time = rng.randf_range(180.0, 600.0) if thundering else rng.randf_range(600.0, 3600.0)
	rain = move_toward(rain, 1.0 if raining else 0.0, delta * 0.1)
	thunder = move_toward(thunder, 1.0 if raining and thundering else 0.0, delta * 0.1)
	logic.raining = rain > 0.2
	_flash = maxf(_flash - delta * 3.0, 0.0)
	visible = rain > 0.01
	if visible:
		_rebuild_cooldown -= delta
		var cell := Vector3i(floori(cam.x), floori(cam.y), floori(cam.z))
		if cell != _last_cell and _rebuild_cooldown <= 0.0:
			_last_cell = cell
			_rebuild_cooldown = 0.15
			_rebuild(cam)
		var daylight := float(game.get("_daylight")) if game != null else 1.0
		for m: ShaderMaterial in [_rain_mat, _snow_mat]:
			m.set_shader_parameter("strength", rain * 0.7)
			m.set_shader_parameter("light", clampf(daylight + _flash, 0.25, 1.0))
		# Дождь тушит горящего игрока под открытым небом.
		if player != null and player.fire_time > 0.0 and is_precipitating_at(player.position):
			player.fire_time = 0.0
		_snow_acc += delta
		if _snow_acc >= 0.5:
			_snow_acc = 0.0
			_accumulate_snow(cam)
	if thunder > 0.5:
		_next_bolt -= delta
		if _next_bolt <= 0.0:
			_next_bolt = rng.randf_range(4.0, 18.0)
			_random_strike(cam)
	_update_bolts(delta)


## Полосы осадков вокруг камеры: дождь и снег — отдельными мешами.
func _rebuild(cam: Vector3) -> void:
	var rain_st := SurfaceTool.new()
	var snow_st := SurfaceTool.new()
	rain_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	snow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_rain := false
	var has_snow := false
	var cx := floori(cam.x)
	var cz := floori(cam.z)
	var y_top := cam.y + ABOVE
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			if dx * dx + dz * dz > RADIUS * RADIUS:
				continue
			var x := cx + dx
			var z := cz + dz
			if not world.has_chunk_at(x, z):
				continue
			var b := world.biome_at(x, z)
			if Biomes.is_dry(b):
				continue
			var ground := float(_column_top(x, z, y_top) + 1)
			var y0 := maxf(ground, cam.y - BELOW)
			if y0 >= y_top:
				continue
			var snowy := Biomes.is_snowy(b)
			var st := snow_st if snowy else rain_st
			if snowy:
				has_snow = true
			else:
				has_rain = true
			var h := WorldGen.hash3(x, 0, z, 77)
			var off := Vector2(float(h & 255) / 255.0, float((h >> 8) & 255) / 255.0)
			# Одна полоса через центр клетки, повёрнутая к камере (как в оригинале).
			var center := Vector3(x + 0.5, 0, z + 0.5)
			var to_cam := Vector2(cam.x - center.x, cam.z - center.z)
			var side := Vector3(-to_cam.y, 0, to_cam.x).normalized() * 0.5 if to_cam.length() > 0.01 else Vector3(0.5, 0, 0)
			_quad(st, center - side, center + side, y0, y_top, off)
	_mesh.mesh = rain_st.commit() if has_rain else null
	_snow_mesh.mesh = snow_st.commit() if has_snow else null


func _quad(st: SurfaceTool, a: Vector3, c: Vector3, y0: float, y1: float, off: Vector2) -> void:
	var v0 := y0 / 4.0
	var v1 := y1 / 4.0
	var pts := [Vector3(a.x, y0, a.z), Vector3(c.x, y0, c.z), Vector3(c.x, y1, c.z), Vector3(a.x, y1, a.z)]
	var uvs := [Vector2(0, -v0), Vector2(1, -v0), Vector2(1, -v1), Vector2(0, -v1)]
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[i])
		st.set_uv2(off)
		st.add_vertex(pts[i])


## Снег ложится, вода замерзает (холодные биомы, во время снегопада).
func _accumulate_snow(cam: Vector3) -> void:
	for i in 3:
		var x := floori(cam.x) + rng.randi_range(-24, 24)
		var z := floori(cam.z) + rng.randi_range(-24, 24)
		if not world.has_chunk_at(x, z) or not Biomes.is_snowy(world.biome_at(x, z)):
			continue
		var y := world.top_solid_y(x, z)
		var id := world.get_block(x, y, z)
		if id == Blocks.WATER and world.get_meta_v(Vector3i(x, y, z)) == 0:
			world.set_block(x, y, z, Blocks.ICE)
		elif Blocks.is_opaque(id) and world.get_block(x, y + 1, z) == Blocks.AIR and world.get_block_light(Vector3i(x, y + 1, z)) < 10:
			world.set_block(x, y + 1, z, Blocks.SNOW_LAYER, 0)


# --- Молнии --------------------------------------------------------------------

func _random_strike(cam: Vector3) -> void:
	var x := floori(cam.x) + rng.randi_range(-48, 48)
	var z := floori(cam.z) + rng.randi_range(-48, 48)
	if not world.has_chunk_at(x, z) or Biomes.is_dry(world.biome_at(x, z)):
		return
	strike(Vector3(x + 0.5, _column_top(x, z, WorldGen.CHUNK_HEIGHT - 1) + 1, z + 0.5))


## Удар молнии: вспышка, поджог (на нормальной и высокой сложности), урон рядом.
func strike(pos: Vector3) -> void:
	_flash = 1.0
	_spawn_bolt(pos)
	var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
	var difficulty := int(game.get("difficulty")) if game != null else 2
	if difficulty >= 2 and logic != null:
		logic.place_fire(cell)
		for i in 4:
			logic.place_fire(cell + Vector3i(rng.randi_range(-1, 1), rng.randi_range(-1, 1), rng.randi_range(-1, 1)))
	if player != null and not player.dead and player.position.distance_to(pos) < 3.0:
		player.take_damage(5, "lightning")
		player.fire_time = maxf(player.fire_time, 8.0)
	var entities: Variant = game.get("entities") if game != null else null
	if entities != null and entities.get("mobs") != null:
		var mobs: Object = entities.get("mobs")
		if mobs.has_method("lightning"):
			mobs.call("lightning", pos)
	lightning_struck.emit(pos)


func _spawn_bolt(pos: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := pos
	var top := pos.y + 110.0
	var y := pos.y
	var points: Array[Vector3] = [p]
	while y < top:
		y += rng.randf_range(4.0, 9.0)
		p = Vector3(p.x + rng.randf_range(-2.5, 2.5), y, p.z + rng.randf_range(-2.5, 2.5))
		points.append(p)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		for side: Vector3 in [Vector3(0.25, 0, 0), Vector3(0, 0, 0.25)]:
			for v: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.88, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_bolts.append({"node": mi, "life": 0.35})


func _update_bolts(delta: float) -> void:
	for i in range(_bolts.size() - 1, -1, -1):
		var b := _bolts[i]
		b["life"] = float(b["life"]) - delta
		var mi: MeshInstance3D = b["node"]
		if float(b["life"]) <= 0.0:
			mi.queue_free()
			_bolts.remove_at(i)
		else:
			mi.visible = fmod(float(b["life"]), 0.1) > 0.03
