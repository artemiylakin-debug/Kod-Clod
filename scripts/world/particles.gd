class_name Particles
extends MeshInstance3D
## Частицы: осколки блоков, дым, пламя, брызги, искры крита, портал, взрывы.
## Квадраты, повёрнутые к камере, пересобираются в один меш каждый кадр (их немного — до MAX).
## Как в оригинале, факелы, огонь, лава и порталы рядом с игроком «искрят»: каждый кадр
## проверяется несколько случайных клеток вокруг.

const MAX := 400
const AMBIENT_SAMPLES := 48
## «Слой» круглого клуба дыма (маска вместо тайла атласа).
const PUFF := -2
const AMBIENT_RADIUS := 12

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2DArray atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D puff : filter_nearest, repeat_disable;
uniform float daylight = 1.0;

void fragment() {
	vec4 c = COLOR;
	if (UV2.x < -1.5) {
		// Клуб дыма: круглая маска.
		if (texture(puff, UV * 4.0).a < 0.5) {
			discard;
		}
	} else if (UV2.x >= 0.0) {
		vec4 t = texture(atlas, vec3(UV, floor(UV2.x + 0.5)));
		if (t.a < 0.5) {
			discard;
		}
		c.rgb *= t.rgb;
	}
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * max(UV2.y * daylight, 0.08);
}
"""

var world: World
var camera: Camera3D
var rng := RandomNumberGenerator.new()

# Данные частиц (параллельные массивы).
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _grow := PackedFloat32Array()
var _gravity := PackedFloat32Array()
var _layer := PackedFloat32Array()
var _uv := PackedVector2Array()
var _color := PackedColorArray()
var _light := PackedFloat32Array()
var _collide := PackedByteArray()
var _material: ShaderMaterial


func setup(p_world: World, p_camera: Camera3D) -> void:
	world = p_world
	camera = p_camera
	rng.randomize()
	var sh := Shader.new()
	sh.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = sh
	_material.set_shader_parameter("atlas", TextureFactory.atlas)
	_material.set_shader_parameter("puff", _make_puff())
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Круглая пиксельная маска для дыма (8×8).
static func _make_puff() -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var d := Vector2(x - 3.5, y - 3.5).length()
			if d < 3.6:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


func count() -> int:
	return _pos.size()


## Базовое добавление частицы. layer < 0 — однотонная.
func add(p: Vector3, v: Vector3, life: float, size: float, color: Color, layer := -1, uv := Vector2.ZERO,
		gravity := 0.0, grow := 0.0, collide := false) -> void:
	if _pos.size() >= MAX:
		return
	_pos.append(p)
	_vel.append(v)
	_life.append(life)
	_max_life.append(life)
	_size.append(size)
	_grow.append(grow)
	_gravity.append(gravity)
	_layer.append(float(layer))
	_uv.append(uv)
	_color.append(color)
	_light.append(_light_at(p))
	_collide.append(1 if collide else 0)


func _light_at(p: Vector3) -> float:
	if world == null:
		return 1.0
	var c := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var sky := world.get_sky_light(c) / 15.0
	var blk := ChunkMesher.block_curve[clampi(world.get_block_light(c), 0, 15)]
	return maxf(sky, blk)


# --- Готовые эффекты -----------------------------------------------------------

## Осколки сломанного блока.
func block_break(cell: Vector3i, id: int, meta: int) -> void:
	if id == Blocks.AIR:
		return
	var tile := Blocks.texture_of(id, 0, meta)
	var tint := _tint_for(cell, id, meta)
	for i in 4:
		for j in 4:
			for k in 2:
				var p := Vector3(cell) + Vector3((i + 0.5) / 4.0, (j + 0.5) / 4.0, (k + 0.5) / 2.0)
				var v := (p - Vector3(cell) - Vector3(0.5, 0.5, 0.5)) * rng.randf_range(2.0, 4.0) + Vector3(0, rng.randf_range(1.0, 3.0), 0)
				_add_piece(p, v, tile, tint)


## Мелкие осколки при добыче (с грани, куда смотрит игрок).
func block_hit(cell: Vector3i, id: int, meta: int, normal: Vector3i) -> void:
	if id == Blocks.AIR:
		return
	var tile := Blocks.texture_of(id, 0, meta)
	var tint := _tint_for(cell, id, meta)
	var p := Vector3(cell) + Vector3(0.5, 0.5, 0.5) + Vector3(normal) * 0.55
	p += Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)) * (Vector3.ONE - Vector3(normal).abs())
	_add_piece(p, Vector3(normal) * 1.5 + Vector3(0, 1.0, 0), tile, tint)


## Крошки предмета (еда).
func crumbs(p: Vector3, tile: int) -> void:
	for i in 3:
		var v := Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.5, 1.5), rng.randf_range(-0.8, 0.8))
		_add_piece(p, v, tile, Color.WHITE)


func _add_piece(p: Vector3, v: Vector3, tile: int, tint: Color) -> void:
	var uv := Vector2(rng.randi_range(0, 12) / 16.0, rng.randi_range(0, 12) / 16.0)
	add(p, v, rng.randf_range(0.5, 1.2), rng.randf_range(0.08, 0.14), tint, tile, uv, 14.0, 0.0, true)


func _tint_for(cell: Vector3i, id: int, meta: int) -> Color:
	if Blocks.tinted[id] == 0 or world == null:
		return Color.WHITE
	var b := world.biome_at(cell.x, cell.z)
	if id == Blocks.LEAVES:
		match meta & 3:
			1:
				return Color(0.38, 0.6, 0.38)
			2:
				return Color(0.5, 0.65, 0.33)
		return Biomes.foliage_color(b)
	return Biomes.grass_color(b)


func smoke(p: Vector3, amount := 1, big := false) -> void:
	for i in amount:
		var g := rng.randf_range(0.15, 0.35) if not big else rng.randf_range(0.3, 0.55)
		var v := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.4, 1.0), rng.randf_range(-0.3, 0.3))
		add(p + Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)), v, rng.randf_range(0.8, 1.6),
			0.08 if not big else 0.22, Color(g, g, g), PUFF, Vector2.ZERO, -0.3, 0.1 if not big else 0.25)


func flame(p: Vector3) -> void:
	add(p, Vector3(0, 0.05, 0), rng.randf_range(0.4, 0.8), 0.07, Color(1.0, rng.randf_range(0.5, 0.8), 0.15), -1, Vector2.ZERO, 0.0, -0.05)


func explosion(center: Vector3, power: float) -> void:
	var n := clampi(int(power * 7.0), 8, 40)
	for i in n:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 1), rng.randf_range(-1, 1)).normalized()
		var g := rng.randf_range(0.45, 0.75)
		add(center + dir * rng.randf_range(0.0, power * 0.6), dir * rng.randf_range(1.0, 4.0), rng.randf_range(0.6, 1.4),
			rng.randf_range(0.25, 0.5), Color(g, g, g), PUFF, Vector2.ZERO, -0.5, 0.35)
	@warning_ignore("integer_division")
	for i in n / 2:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		add(center + dir * rng.randf_range(0.0, power * 0.4), dir * rng.randf_range(3.0, 8.0), rng.randf_range(0.3, 0.7),
			0.1, Color(0.95, 0.9, 0.8), PUFF, Vector2.ZERO, 0.0, 0.0)


func splash(p: Vector3, amount := 12) -> void:
	for i in amount:
		var v := Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(2.0, 4.0), rng.randf_range(-1.5, 1.5))
		add(p, v, rng.randf_range(0.4, 0.8), 0.06, Color(0.75, 0.85, 1.0), -1, Vector2.ZERO, 16.0, 0.0, true)


func crit(p: Vector3, magic := false) -> void:
	for i in 10:
		var v := Vector3(rng.randf_range(-2, 2), rng.randf_range(0.5, 3.0), rng.randf_range(-2, 2))
		var c := Color(0.5, 0.95, 1.0) if magic else Color(1.0, 0.95, 0.6)
		add(p, v, rng.randf_range(0.3, 0.6), 0.07, c, -1, Vector2.ZERO, 6.0)


func portal(p: Vector3) -> void:
	var v := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.5, 0.5))
	add(p, v, rng.randf_range(0.8, 1.5), 0.06, Color(0.75, 0.3, 0.95), -1, Vector2.ZERO, -0.2)


## Цветные частицы (зелья, ноты, сердечки и т. п.).
func colored(p: Vector3, color: Color, amount := 6, spread := 0.4, rise := 0.6) -> void:
	for i in amount:
		var v := Vector3(rng.randf_range(-spread, spread), rng.randf_range(0.0, rise * 2.0), rng.randf_range(-spread, spread))
		add(p, v, rng.randf_range(0.6, 1.2), 0.08, color, -1, Vector2.ZERO, 0.0)


# --- Кадр ---------------------------------------------------------------------

func update(delta: float, daylight: float) -> void:
	_material.set_shader_parameter("daylight", daylight)
	_ambient()
	var n := _pos.size()
	var i := 0
	while i < n:
		_life[i] -= delta
		if _life[i] <= 0.0:
			_remove(i)
			n -= 1
			continue
		var v := _vel[i]
		v.y -= _gravity[i] * delta
		var drag := exp(-1.5 * delta)
		v.x *= drag
		v.z *= drag
		var np := _pos[i] + v * delta
		if _collide[i] == 1 and world != null:
			var id := world.get_block(floori(np.x), floori(np.y), floori(np.z))
			if Blocks.is_solid(id) and Blocks.is_opaque(id):
				np = _pos[i]
				v = Vector3(v.x * 0.3, 0.0, v.z * 0.3)
		_pos[i] = np
		_vel[i] = v
		_size[i] = maxf(_size[i] + _grow[i] * delta, 0.01)
		i += 1
	_rebuild()


func _remove(i: int) -> void:
	var last := _pos.size() - 1
	if i != last:
		_pos[i] = _pos[last]
		_vel[i] = _vel[last]
		_life[i] = _life[last]
		_max_life[i] = _max_life[last]
		_size[i] = _size[last]
		_grow[i] = _grow[last]
		_gravity[i] = _gravity[last]
		_layer[i] = _layer[last]
		_uv[i] = _uv[last]
		_color[i] = _color[last]
		_light[i] = _light[last]
		_collide[i] = _collide[last]
	_pos.resize(last)
	_vel.resize(last)
	_life.resize(last)
	_max_life.resize(last)
	_size.resize(last)
	_grow.resize(last)
	_gravity.resize(last)
	_layer.resize(last)
	_uv.resize(last)
	_color.resize(last)
	_light.resize(last)
	_collide.resize(last)


func _rebuild() -> void:
	var n := _pos.size()
	if n == 0 or camera == null:
		mesh = null
		return
	var basis := camera.global_transform.basis
	var right := basis.x
	var up := basis.y
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * 4)
	uvs.resize(n * 4)
	uv2.resize(n * 4)
	cols.resize(n * 4)
	idx.resize(n * 6)
	for i in n:
		var s := _size[i] * 0.5
		var c := _pos[i]
		var r := right * s
		var u := up * s
		var k := i * 4
		verts[k] = c - r - u
		verts[k + 1] = c + r - u
		verts[k + 2] = c + r + u
		verts[k + 3] = c - r + u
		var o := _uv[i]
		var t := 0.25
		uvs[k] = o + Vector2(0, t)
		uvs[k + 1] = o + Vector2(t, t)
		uvs[k + 2] = o + Vector2(t, 0)
		uvs[k + 3] = o
		var l2 := Vector2(_layer[i], _light[i])
		uv2[k] = l2
		uv2[k + 1] = l2
		uv2[k + 2] = l2
		uv2[k + 3] = l2
		var col := _color[i]
		col.a = minf(1.0, _life[i] / (_max_life[i] * 0.3))
		cols[k] = col
		cols[k + 1] = col
		cols[k + 2] = col
		cols[k + 3] = col
		var j := i * 6
		idx[j] = k
		idx[j + 1] = k + 1
		idx[j + 2] = k + 2
		idx[j + 3] = k
		idx[j + 4] = k + 2
		idx[j + 5] = k + 3
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh = m


## Случайные клетки вокруг камеры: факелы дымят, огонь и лава искрят, порталы мерцают.
func _ambient() -> void:
	if world == null or camera == null:
		return
	var c := camera.global_position
	var cx := floori(c.x)
	var cy := floori(c.y)
	var cz := floori(c.z)
	for i in AMBIENT_SAMPLES:
		var x := cx + rng.randi_range(-AMBIENT_RADIUS, AMBIENT_RADIUS)
		var y := cy + rng.randi_range(-AMBIENT_RADIUS, AMBIENT_RADIUS)
		var z := cz + rng.randi_range(-AMBIENT_RADIUS, AMBIENT_RADIUS)
		var id := world.get_block(x, y, z)
		match id:
			Blocks.TORCH, Blocks.REDSTONE_TORCH:
				var meta := world.get_meta_v(Vector3i(x, y, z))
				var tip := Vector3(x + 0.5, y + 0.7, z + 0.5)
				if meta >= 1 and meta <= 4:
					tip += Vector3(Blocks.attach_offset(meta)) * -0.27 + Vector3(0, 0.15, 0)
				if id == Blocks.TORCH:
					flame(tip)
					smoke(tip)
				else:
					colored(tip, Color(1.0, 0.15, 0.1), 1, 0.05, 0.2)
			Blocks.FIRE:
				smoke(Vector3(x + rng.randf(), y + rng.randf() * 0.8, z + rng.randf()), 1, true)
			Blocks.LAVA, Blocks.FLOWING_LAVA:
				if world.get_block(x, y + 1, z) == Blocks.AIR and rng.randf() < 0.3:
					var p := Vector3(x + rng.randf(), y + 0.95, z + rng.randf())
					add(p, Vector3(rng.randf_range(-1, 1), rng.randf_range(3, 5), rng.randf_range(-1, 1)), 1.0, 0.08,
						Color(1.0, 0.5, 0.1), -1, Vector2.ZERO, 14.0, 0.0, true)
			Blocks.PORTAL:
				portal(Vector3(x + rng.randf(), y + rng.randf(), z + rng.randf()))
			Blocks.LIT_FURNACE:
				var d: Vector3i = Blocks.DIR_VEC[world.get_meta_v(Vector3i(x, y, z)) & 3]
				var fp := Vector3(x + 0.5, y + 0.3, z + 0.5) + Vector3(d) * 0.52
				flame(fp)
				smoke(fp)
			Blocks.LIT_REDSTONE_ORE:
				colored(Vector3(x + rng.randf(), y + rng.randf(), z + rng.randf()), Color(1.0, 0.1, 0.1), 1, 0.05, 0.1)
			Blocks.MYCELIUM:
				if world.get_block(x, y + 1, z) == Blocks.AIR and rng.randf() < 0.2:
					colored(Vector3(x + rng.randf(), y + 1.05, z + rng.randf()), Color(0.6, 0.5, 0.65), 1, 0.05, 0.1)
			Blocks.REDSTONE_WIRE:
				if world.get_meta_v(Vector3i(x, y, z)) > 0 and rng.randf() < 0.4:
					colored(Vector3(x + rng.randf(), y + 0.1, z + rng.randf()), Color(0.9, 0.1, 0.1), 1, 0.05, 0.1)
			Blocks.END_PORTAL:
				add(Vector3(x + rng.randf(), y + 0.8, z + rng.randf()), Vector3(0, 0.3, 0), 1.0, 0.05, Color(0.1, 0.1, 0.12))
			Blocks.ENCHANTING_TABLE:
				colored(Vector3(x + 0.5, y + 1.5, z + 0.5) + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)),
					Color(0.85, 0.85, 1.0), 1, 0.2, 0.0)
