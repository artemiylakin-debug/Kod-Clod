class_name TextureFactory
extends RefCounted
## Процедурные пиксельные текстуры 16×16, изометрические иконки блоков, шейдеры и общие меши.
## Никаких внешних ассетов: всё рисуется при запуске игры.

const TILE := 16
const ICON_SIZE := 48

const CHUNK_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2DArray atlas : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec3 fog_color : source_color = vec3(0.68, 0.82, 1.0);
uniform float fog_start = 48.0;
uniform float fog_end = 96.0;
uniform float daylight = 1.0;

varying float v_dist;
varying flat float v_layer;

void vertex() {
	v_layer = UV2.x;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 tex = texture(atlas, vec3(UV, v_layer));
	if (tex.a < 0.5) {
		discard;
	}
	vec3 col = tex.rgb * COLOR.rgb * daylight;
	float fog = clamp((v_dist - fog_start) / (fog_end - fog_start), 0.0, 1.0);
	ALBEDO = mix(col, fog_color, fog);
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2DArray atlas : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec3 fog_color : source_color = vec3(0.68, 0.82, 1.0);
uniform float fog_start = 48.0;
uniform float fog_end = 96.0;
uniform float daylight = 1.0;

varying float v_dist;
varying flat float v_layer;

void vertex() {
	v_layer = UV2.x;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 tex = texture(atlas, vec3(UV, v_layer));
	vec3 col = tex.rgb * COLOR.rgb * daylight;
	float fog = clamp((v_dist - fog_start) / (fog_end - fog_start), 0.0, 1.0);
	ALBEDO = mix(col, fog_color, fog);
	ALPHA = mix(tex.a, 1.0, fog);
}
"""

const CRACK_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never;

uniform sampler2DArray atlas : source_color, filter_nearest;
uniform float layer = 0.0;

void fragment() {
	vec4 tex = texture(atlas, vec3(UV, layer));
	ALBEDO = tex.rgb;
	ALPHA = tex.a * 0.8;
}
"""

## Блок в руке рисуется поверх мира (без теста глубины), поэтому не «проваливается» в стены.
const HAND_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_test_disabled, depth_draw_never;

uniform sampler2DArray atlas : source_color, filter_nearest;
uniform float daylight = 1.0;

varying flat float v_layer;

void vertex() {
	v_layer = UV2.x;
}

void fragment() {
	vec4 tex = texture(atlas, vec3(UV, v_layer));
	if (tex.a < 0.5) {
		discard;
	}
	ALBEDO = tex.rgb * COLOR.rgb * daylight;
	ALPHA = 1.0;
}
"""

static var tiles: Array[Image] = []
static var atlas: Texture2DArray
static var icons: Array[Texture2D] = []
static var background: Texture2D
static var chunk_material: ShaderMaterial
static var water_material: ShaderMaterial
static var crack_material: ShaderMaterial
static var hand_material: ShaderMaterial
static var selection_material: StandardMaterial3D

static var _rng := RandomNumberGenerator.new()
static var _cube_meshes: Dictionary = {}
static var _selection_mesh: ArrayMesh
static var _initialized := false


static func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_build_tiles()
	_build_atlas()
	_build_icons()
	_build_background()
	_build_materials()


## Освобождает ресурсы, хранящиеся в статических переменных (вызывается при выходе).
static func release() -> void:
	tiles.clear()
	icons.clear()
	_cube_meshes.clear()
	atlas = null
	background = null
	chunk_material = null
	water_material = null
	crack_material = null
	hand_material = null
	selection_material = null
	_selection_mesh = null
	_initialized = false


# --- Материалы и меши ------------------------------------------------------

static func _build_materials() -> void:
	chunk_material = _shader_material(CHUNK_SHADER)
	water_material = _shader_material(WATER_SHADER)
	water_material.render_priority = 1
	crack_material = _shader_material(CRACK_SHADER)
	crack_material.render_priority = 2
	hand_material = _shader_material(HAND_SHADER)
	hand_material.render_priority = 100
	selection_material = StandardMaterial3D.new()
	selection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_material.albedo_color = Color(0.0, 0.0, 0.0, 0.6)
	selection_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	selection_material.render_priority = 3


static func _shader_material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("atlas", atlas)
	return m


static func set_environment(fog_color: Color, fog_start: float, fog_end: float, daylight: float) -> void:
	for m: ShaderMaterial in [chunk_material, water_material]:
		m.set_shader_parameter("fog_color", fog_color)
		m.set_shader_parameter("fog_start", fog_start)
		m.set_shader_parameter("fog_end", fog_end)
		m.set_shader_parameter("daylight", daylight)
	hand_material.set_shader_parameter("daylight", maxf(daylight, 0.45))


static func block_mesh(id: int) -> ArrayMesh:
	if _cube_meshes.has(id):
		return _cube_meshes[id]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ChunkMesher.cube_arrays(id))
	_cube_meshes[id] = mesh
	return mesh


## Рамка выделения блока: 12 тонких брусков (линии в 1 пиксель плохо видны на телефонах).
static func selection_mesh() -> ArrayMesh:
	if _selection_mesh:
		return _selection_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var e := 0.503
	var t := 0.012
	for a in 3:
		var b := (a + 1) % 3
		var c := (a + 2) % 3
		for sb in [-1.0, 1.0]:
			for sc in [-1.0, 1.0]:
				var lo := Vector3.ZERO
				var hi := Vector3.ZERO
				lo[a] = -e - t
				hi[a] = e + t
				lo[b] = sb * e - t
				hi[b] = sb * e + t
				lo[c] = sc * e - t
				hi[c] = sc * e + t
				_add_box(st, lo, hi)
	_selection_mesh = st.commit()
	return _selection_mesh


static func _add_box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var p := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for f: Array in faces:
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k: int in tri:
				st.add_vertex(p[f[k]])


# --- Текстуры --------------------------------------------------------------

static func _build_tiles() -> void:
	_rng.seed = 20241022
	tiles.clear()
	tiles.resize(Blocks.TEXTURE_COUNT)
	var grass_top := _paint_grass_top()
	var dirt := _paint_dirt()
	var stone := _paint_stone()
	var planks := _paint_planks()
	tiles[Blocks.T_GRASS_TOP] = grass_top
	tiles[Blocks.T_GRASS_SIDE] = _paint_grass_side(dirt, grass_top)
	tiles[Blocks.T_DIRT] = dirt
	tiles[Blocks.T_STONE] = stone
	tiles[Blocks.T_COBBLE] = _paint_cobble()
	tiles[Blocks.T_LOG_SIDE] = _paint_log_side()
	tiles[Blocks.T_LOG_TOP] = _paint_log_top()
	tiles[Blocks.T_LEAVES] = _paint_leaves()
	tiles[Blocks.T_PLANKS] = planks
	tiles[Blocks.T_SAND] = _paint_speckled(Color(0.86, 0.8, 0.58), 0.05, Color(0.76, 0.69, 0.48), 0.1)
	tiles[Blocks.T_GLASS] = _paint_glass()
	tiles[Blocks.T_BEDROCK] = _paint_bedrock()
	tiles[Blocks.T_WATER] = _paint_water()
	tiles[Blocks.T_COAL_ORE] = _paint_ore(stone, Color(0.1, 0.1, 0.1))
	tiles[Blocks.T_IRON_ORE] = _paint_ore(stone, Color(0.85, 0.66, 0.52))
	tiles[Blocks.T_BRICKS] = _paint_bricks()
	tiles[Blocks.T_SNOW] = _paint_speckled(Color(0.95, 0.97, 1.0), 0.025, Color(0.84, 0.9, 0.98), 0.07)
	tiles[Blocks.T_GRAVEL] = _paint_gravel()
	tiles[Blocks.T_STONE_BRICKS] = _paint_stone_bricks()
	tiles[Blocks.T_BOOKSHELF] = _paint_bookshelf(planks)
	var cracks := _paint_cracks()
	for s in Blocks.CRACK_STAGES:
		tiles[Blocks.T_CRACK_0 + s] = cracks[s]


static func _build_atlas() -> void:
	var images: Array[Image] = []
	for t in tiles:
		var im: Image = t.duplicate()
		im.generate_mipmaps()
		images.append(im)
	atlas = Texture2DArray.new()
	var err := atlas.create_from_images(images)
	if err != OK:
		push_error("Не удалось создать текстурный массив: %s" % err)


static func _build_background() -> void:
	var img: Image = tiles[Blocks.T_DIRT].duplicate()
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _shade(img.get_pixel(x, y), 0.42))
	img.resize(TILE * 4, TILE * 4, Image.INTERPOLATE_NEAREST)
	background = ImageTexture.create_from_image(img)


static func _new_tile() -> Image:
	return Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)


static func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


static func _vary(c: Color, amount: float) -> Color:
	return _shade(c, 1.0 + _rng.randf_range(-amount, amount))


static func _paint_grass_top() -> Image:
	var img := _new_tile()
	var base := Color(0.4, 0.66, 0.24)
	for y in TILE:
		for x in TILE:
			var f := _rng.randf_range(0.84, 1.1)
			if _rng.randf() < 0.12:
				f *= 0.8
			img.set_pixel(x, y, _shade(base, f))
	return img


static func _paint_dirt() -> Image:
	var img := _new_tile()
	var base := Color(0.55, 0.39, 0.26)
	for y in TILE:
		for x in TILE:
			var c := _vary(base, 0.1)
			var r := _rng.randf()
			if r < 0.1:
				c = _vary(Color(0.42, 0.29, 0.19), 0.06)
			elif r < 0.15:
				c = _vary(Color(0.66, 0.5, 0.36), 0.05)
			img.set_pixel(x, y, c)
	return img


static func _paint_grass_side(dirt: Image, grass: Image) -> Image:
	var img: Image = dirt.duplicate()
	for x in TILE:
		var depth := 3 + _rng.randi_range(0, 1)
		if _rng.randf() < 0.3:
			depth += 1
		if _rng.randf() < 0.12:
			depth += 2
		for y in depth:
			img.set_pixel(x, y, _shade(grass.get_pixel(x, y), 0.93))
	return img


static func _paint_stone() -> Image:
	var img := _new_tile()
	var base := Color(0.5, 0.5, 0.5)
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _shade(base, _rng.randf_range(0.9, 1.07)))
	for i in 9:
		var sx := _rng.randi_range(0, TILE - 1)
		var sy := _rng.randi_range(0, TILE - 1)
		var f := 0.78 if i % 3 != 0 else 1.13
		for k in _rng.randi_range(2, 4):
			img.set_pixel((sx + k) % TILE, sy, _shade(base, f))
	return img


static func _paint_cobble() -> Image:
	var img := _new_tile()
	var pts: Array[Vector2] = []
	var shades: Array[float] = []
	for i in 9:
		pts.append(Vector2(_rng.randf() * TILE, _rng.randf() * TILE))
		shades.append(_rng.randf_range(0.42, 0.64))
	for y in TILE:
		for x in TILE:
			var d1 := 1e9
			var d2 := 1e9
			var idx := 0
			for i in pts.size():
				var dx := absf(x + 0.5 - pts[i].x)
				var dy := absf(y + 0.5 - pts[i].y)
				dx = minf(dx, TILE - dx)
				dy = minf(dy, TILE - dy)
				var d := sqrt(dx * dx + dy * dy)
				if d < d1:
					d2 = d1
					d1 = d
					idx = i
				elif d < d2:
					d2 = d
			var c: Color
			if d2 - d1 < 1.0:
				c = _vary(Color(0.27, 0.27, 0.27), 0.08)
			else:
				var s := shades[idx] * (1.12 if d1 < 1.6 else 1.0)
				c = _vary(Color(s, s, s), 0.06)
			img.set_pixel(x, y, c)
	return img


static func _paint_log_side() -> Image:
	var img := _new_tile()
	var base := Color(0.42, 0.32, 0.19)
	var col_f: Array[float] = []
	for x in TILE:
		col_f.append(0.74 if x % 4 == 1 else _rng.randf_range(0.88, 1.1))
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _shade(base, col_f[x] * _rng.randf_range(0.93, 1.05)))
	for i in 3:
		var kx := _rng.randi_range(0, TILE - 2)
		var ky := _rng.randi_range(0, TILE - 1)
		img.set_pixel(kx, ky, _shade(base, 0.6))
		img.set_pixel(kx + 1, ky, _shade(base, 0.65))
	return img


static func _paint_log_top() -> Image:
	var img := _new_tile()
	for y in TILE:
		for x in TILE:
			var c: Color
			if x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1:
				c = _vary(Color(0.4, 0.3, 0.18), 0.08)
			else:
				var cheb := maxf(absf(x - 7.5), absf(y - 7.5))
				c = Color(0.72, 0.58, 0.36) if int(cheb) % 2 == 0 else Color(0.62, 0.48, 0.29)
				c = _vary(c, 0.04)
			img.set_pixel(x, y, c)
	return img


static func _paint_leaves() -> Image:
	var img := _new_tile()
	var base := Color(0.23, 0.5, 0.15)
	for y in TILE:
		for x in TILE:
			if _rng.randf() < 0.18:
				# Прозрачный пиксель хранит цвет листвы, чтобы мипмапы не темнели.
				var hole := _shade(base, 0.6)
				hole.a = 0.0
				img.set_pixel(x, y, hole)
			else:
				var f := _rng.randf_range(0.72, 1.15)
				img.set_pixel(x, y, _shade(base, f))
	return img


static func _paint_planks() -> Image:
	var img := _new_tile()
	var base := Color(0.7, 0.54, 0.32)
	for y in TILE:
		var board := y >> 2
		var row_f := _rng.randf_range(0.93, 1.06)
		var joint := (board * 5 + 3) % TILE
		for x in TILE:
			var c: Color
			if y % 4 == 3:
				c = _shade(base, 0.66)
			elif x == joint:
				c = _shade(base, 0.72)
			else:
				c = _shade(base, row_f * _rng.randf_range(0.95, 1.04))
			img.set_pixel(x, y, c)
	return img


static func _paint_speckled(base: Color, amount: float, speck: Color, chance: float) -> Image:
	var img := _new_tile()
	for y in TILE:
		for x in TILE:
			var c := _vary(base, amount)
			if _rng.randf() < chance:
				c = _vary(speck, amount)
			img.set_pixel(x, y, c)
	return img


static func _paint_glass() -> Image:
	var img := _new_tile()
	var clear := Color(0.8, 0.92, 0.96, 0.0)
	var edge := Color(0.8, 0.92, 0.96, 1.0)
	for y in TILE:
		for x in TILE:
			var c := clear
			if x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1:
				c = _vary(edge, 0.04)
			elif (x + y == 7 and x >= 2 and x <= 5) or (x + y == 8 and x >= 3 and x <= 5):
				c = Color(1, 1, 1, 1)
			elif x + y == 20 and x >= 9 and x <= 12:
				c = Color(1, 1, 1, 1)
			img.set_pixel(x, y, c)
	return img


static func _paint_bedrock() -> Image:
	var img := _new_tile()
	var tones := [0.16, 0.27, 0.38, 0.5]
	for y in TILE:
		for x in TILE:
			var t: float = tones[_rng.randi_range(0, 3)]
			img.set_pixel(x, y, _vary(Color(t, t, t), 0.05))
	return img


static func _paint_water() -> Image:
	var img := _new_tile()
	var base := Color(0.22, 0.42, 0.86, 0.72)
	for y in TILE:
		for x in TILE:
			var w := sin((x + y * 0.5) * 0.8) * 0.5 + 0.5
			var c := _shade(base, 0.9 + w * 0.15 + _rng.randf_range(-0.03, 0.03))
			c.a = 0.72
			img.set_pixel(x, y, c)
	return img


static func _paint_ore(stone: Image, color: Color) -> Image:
	var img: Image = stone.duplicate()
	for i in 5:
		var cx := _rng.randi_range(1, 12)
		var cy := _rng.randi_range(1, 12)
		for k in _rng.randi_range(4, 6):
			var px := (cx + _rng.randi_range(0, 2)) % TILE
			var py := (cy + _rng.randi_range(0, 2)) % TILE
			img.set_pixel(px, py, _vary(color, 0.12))
	return img


static func _paint_bricks() -> Image:
	var img := _new_tile()
	var mortar := Color(0.68, 0.65, 0.6)
	var brick := Color(0.62, 0.28, 0.21)
	for y in TILE:
		var row := y >> 2
		var off := 4 if row % 2 == 1 else 0
		for x in TILE:
			if y % 4 == 3 or (x + off) % 8 == 7:
				img.set_pixel(x, y, _vary(mortar, 0.04))
			else:
				img.set_pixel(x, y, _vary(brick, 0.1))
	return img


static func _paint_gravel() -> Image:
	var img := _new_tile()
	var tones := [Color(0.52, 0.5, 0.49), Color(0.4, 0.38, 0.37), Color(0.63, 0.61, 0.59), Color(0.48, 0.43, 0.39)]
	for by in TILE >> 1:
		for bx in TILE >> 1:
			var c: Color = tones[_rng.randi_range(0, 3)]
			for k in 4:
				img.set_pixel(bx * 2 + (k & 1), by * 2 + (k >> 1), _vary(c, 0.07))
	return img


static func _paint_stone_bricks() -> Image:
	var img := _new_tile()
	var base := Color(0.5, 0.5, 0.5)
	var mortar := Color(0.3, 0.3, 0.3)
	for y in TILE:
		var row := y >> 3
		var ly := y % 8
		var seam_x := TILE - 1 if row == 0 else 7
		for x in TILE:
			var c: Color
			if ly == 7 or x == seam_x:
				c = _vary(mortar, 0.05)
			elif ly == 0 or x == (seam_x + 1) % TILE:
				c = _vary(_shade(base, 1.16), 0.03)
			else:
				c = _vary(base, 0.06)
			img.set_pixel(x, y, c)
	return img


static func _paint_bookshelf(planks: Image) -> Image:
	var img: Image = planks.duplicate()
	var colors := [Color(0.62, 0.16, 0.13), Color(0.18, 0.3, 0.62), Color(0.2, 0.5, 0.22),
		Color(0.55, 0.4, 0.15), Color(0.45, 0.2, 0.5), Color(0.75, 0.66, 0.3)]
	for shelf: int in [2, 9]:
		for yy in range(shelf, shelf + 5):
			for x in TILE:
				img.set_pixel(x, yy, Color(0.16, 0.11, 0.07))
		var x := 0
		while x < TILE:
			var w := _rng.randi_range(1, 2)
			var col: Color = colors[_rng.randi_range(0, colors.size() - 1)]
			var top := shelf + _rng.randi_range(0, 1)
			for xx in w:
				if x + xx >= TILE:
					break
				for yy in range(top, shelf + 5):
					var f := 1.2 if yy == top else (0.85 if xx == w - 1 else 1.0)
					img.set_pixel(x + xx, yy, _shade(col, f))
			x += w + (1 if _rng.randf() < 0.25 else 0)
	return img


static func _paint_cracks() -> Array[Image]:
	var pts: Array = []
	for line in 7:
		var ang := line * TAU / 7.0 + _rng.randf_range(-0.3, 0.3)
		var p := Vector2(7.5, 7.5)
		for step in 14:
			ang += _rng.randf_range(-0.55, 0.55)
			p += Vector2(cos(ang), sin(ang)) * 0.9
			var ip := Vector2i(int(p.x), int(p.y))
			if ip.x < 0 or ip.y < 0 or ip.x >= TILE or ip.y >= TILE:
				break
			pts.append([Vector2(ip).distance_to(Vector2(7.5, 7.5)) + step * 0.15, ip])
	pts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array[Image] = []
	for s in Blocks.CRACK_STAGES:
		var img := _new_tile()
		var n := int(ceil(pts.size() * (s + 1) / float(Blocks.CRACK_STAGES)))
		for i in n:
			var ip: Vector2i = pts[i][1]
			img.set_pixel(ip.x, ip.y, Color(0.1, 0.1, 0.1, 0.9))
		out.append(img)
	return out


# --- Иконки ----------------------------------------------------------------

static func _build_icons() -> void:
	icons.clear()
	for id in Blocks.COUNT:
		if id == Blocks.AIR:
			icons.append(ImageTexture.create_from_image(Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)))
		else:
			icons.append(_make_icon(id))


## Изометрический куб: верх, левая (+Z) и правая (+X) грани с разной яркостью.
static func _make_icon(id: int) -> Texture2D:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var top: Image = tiles[Blocks.texture_of(id, 2)]
	var left: Image = tiles[Blocks.texture_of(id, 4)]
	var right: Image = tiles[Blocks.texture_of(id, 0)]
	var w := ICON_SIZE - 4.0
	var side_h := w * 0.56
	var o := Vector2(ICON_SIZE / 2.0, (ICON_SIZE - (w * 0.5 + side_h)) / 2.0)
	var ax := Vector2(w / 2.0, w / 4.0)
	var bx := Vector2(-w / 2.0, w / 4.0)
	var cx := Vector2(0.0, side_h)
	for py in ICON_SIZE:
		for px in ICON_SIZE:
			var p := Vector2(px + 0.5, py + 0.5)
			var c := Color(0, 0, 0, 0)
			var st := _solve(p - o, ax, bx)
			if _inside(st):
				c = _shade(_sample(top, st.x, st.y), 1.0)
			else:
				st = _solve(p - o - ax, bx, cx)
				if _inside(st):
					c = _shade(_sample(right, 1.0 - st.x, st.y), 0.62)
				else:
					st = _solve(p - o - bx, ax, cx)
					if _inside(st):
						c = _shade(_sample(left, st.x, st.y), 0.82)
			if c.a >= 0.5:
				c.a = 1.0
				img.set_pixel(px, py, c)
	return ImageTexture.create_from_image(img)


static func _solve(v: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var det := a.x * b.y - a.y * b.x
	return Vector2((v.x * b.y - v.y * b.x) / det, (a.x * v.y - a.y * v.x) / det)


static func _inside(st: Vector2) -> bool:
	return st.x >= 0.0 and st.x < 1.0 and st.y >= 0.0 and st.y < 1.0


static func _sample(img: Image, u: float, v: float) -> Color:
	return img.get_pixel(clampi(int(u * TILE), 0, TILE - 1), clampi(int(v * TILE), 0, TILE - 1))
