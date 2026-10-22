class_name TextureFactory
extends RefCounted
## Текстурный массив из тайлов TexturePainter, значки предметов (изометрические — для блоков,
## плоские — для остальных), меши предметов в руке и на земле, шейдеры.
## Никаких внешних ассетов: всё рисуется при запуске игры.

const TILE := 16
const ICON_SIZE := 48

## Мир: небесный свет (UV2.y) × освещённость дня и свет от блоков (COLOR.a) тёплого оттенка.
const CHUNK_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2DArray atlas : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec3 fog_color : source_color = vec3(0.68, 0.82, 1.0);
uniform float fog_start = 48.0;
uniform float fog_end = 96.0;
uniform float daylight = 1.0;
uniform float min_light = 0.07;

varying float v_dist;
varying flat float v_layer;
varying float v_sky;

void vertex() {
	v_layer = UV2.x;
	v_sky = UV2.y;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 tex = texture(atlas, vec3(UV, v_layer));
	if (tex.a < 0.5) {
		discard;
	}
	vec3 light = max(vec3(v_sky * daylight), vec3(COLOR.a) * vec3(1.0, 0.9, 0.75));
	light = max(light, vec3(min_light));
	vec3 col = tex.rgb * COLOR.rgb * light;
	float fog = clamp((v_dist - fog_start) / (fog_end - fog_start), 0.0, 1.0);
	ALBEDO = mix(col, fog_color, fog);
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never;

uniform sampler2DArray atlas : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec3 fog_color : source_color = vec3(0.68, 0.82, 1.0);
uniform float fog_start = 48.0;
uniform float fog_end = 96.0;
uniform float daylight = 1.0;
uniform float min_light = 0.07;

varying float v_dist;
varying flat float v_layer;
varying float v_sky;

void vertex() {
	v_layer = UV2.x;
	v_sky = UV2.y;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec2 uv = UV;
	if (v_layer == float(%d)) {
		uv += vec2(TIME * 0.03, TIME * 0.05);
	}
	vec4 tex = texture(atlas, vec3(uv, v_layer));
	vec3 light = max(vec3(v_sky * daylight), vec3(COLOR.a) * vec3(1.0, 0.9, 0.75));
	light = max(light, vec3(min_light));
	vec3 col = tex.rgb * COLOR.rgb * light;
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

## Предметы и блоки вне сетки чанков (в руке, на земле, падающий песок): освещение задаётся
## параметрами материала объекта (небесный свет и свет от блоков в клетке, где он находится).
## Параметры экземпляра (instance uniform) веб-рендер не поддерживает, поэтому у каждого
## объекта своя копия материала — см. instance_material() и set_light().
const ENTITY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back%s;

uniform sampler2DArray atlas : source_color, filter_nearest_mipmap, repeat_enable;
uniform float daylight = 1.0;
uniform vec3 fog_color : source_color = vec3(0.68, 0.82, 1.0);
uniform float fog_start = 48.0;
uniform float fog_end = 96.0;
uniform float local_sky = 1.0;
uniform float local_block = 0.0;
uniform float hurt = 0.0;

varying flat float v_layer;
varying float v_shade;
varying float v_dist;

void vertex() {
	v_layer = UV2.x;
	v_shade = UV2.y;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 tex = texture(atlas, vec3(UV, v_layer));
	if (tex.a < 0.5) {
		discard;
	}
	vec3 light = max(vec3(local_sky * daylight), vec3(local_block) * vec3(1.0, 0.9, 0.75));
	light = max(light, vec3(0.07)) * v_shade;
	vec3 col = tex.rgb * COLOR.rgb * light;
	col = mix(col, vec3(1.0, 0.1, 0.1) * max(light.r, 0.3), hurt * 0.55);
	float fog = clamp((v_dist - fog_start) / (fog_end - fog_start), 0.0, 1.0);
	ALBEDO = mix(col, fog_color, fog);
	ALPHA = 1.0;
}
"""

## Существа: обычная текстура (развёртка-«скин»), освещение — параметрами экземпляра.
const MOB_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D skin : source_color, filter_nearest, repeat_disable;
uniform float daylight = 1.0;
uniform vec3 fog_color : source_color = vec3(0.68, 0.82, 1.0);
uniform float fog_start = 48.0;
uniform float fog_end = 96.0;
uniform float local_sky = 1.0;
uniform float local_block = 0.0;
uniform float hurt = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

varying float v_dist;

void vertex() {
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 tex = texture(skin, UV);
	if (tex.a < 0.5) {
		discard;
	}
	vec3 light = max(vec3(local_sky * daylight), vec3(local_block) * vec3(1.0, 0.9, 0.75));
	light = max(light, vec3(0.07)) * COLOR.rgb;
	vec3 col = tex.rgb * tint.rgb * light;
	col = mix(col, vec3(1.0, 0.1, 0.1) * max(light.r, 0.3), hurt * 0.55);
	float fog = clamp((v_dist - fog_start) / (fog_end - fog_start), 0.0, 1.0);
	ALBEDO = mix(col, fog_color, fog);
}
"""

static var tiles: Array[Image] = []
static var atlas: Texture2DArray
static var background: Texture2D
static var chunk_material: ShaderMaterial
static var water_material: ShaderMaterial
static var crack_material: ShaderMaterial
## Блок/предмет в руке: поверх мира, без теста глубины.
static var hand_material: ShaderMaterial
## Предметы на земле, падающие блоки.
static var entity_material: ShaderMaterial
static var mob_shader: Shader
static var selection_material: StandardMaterial3D

static var _icons: Dictionary = {}
static var _item_meshes: Dictionary = {}
static var _selection_mesh: ArrayMesh
## Копии материалов отдельных объектов; освобождённые удаляются в set_environment().
static var _instance_materials: Array[ShaderMaterial] = []
static var _initialized := false


static func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	tiles = TexturePainter.paint_all()
	_build_atlas()
	_build_background()
	_build_materials()


## Освобождает ресурсы, хранящиеся в статических переменных (вызывается при выходе).
static func release() -> void:
	tiles.clear()
	_icons.clear()
	_item_meshes.clear()
	_instance_materials.clear()
	atlas = null
	background = null
	chunk_material = null
	water_material = null
	crack_material = null
	hand_material = null
	entity_material = null
	mob_shader = null
	selection_material = null
	_selection_mesh = null
	_initialized = false


# --- Материалы и меши ------------------------------------------------------

static func _build_materials() -> void:
	chunk_material = _shader_material(CHUNK_SHADER)
	water_material = _shader_material(WATER_SHADER % Tex.WATER)
	water_material.render_priority = 1
	crack_material = _shader_material(CRACK_SHADER)
	crack_material.render_priority = 2
	entity_material = _shader_material(ENTITY_SHADER % "")
	hand_material = _shader_material(ENTITY_SHADER % ", depth_test_disabled, depth_draw_never")
	hand_material.render_priority = 100
	mob_shader = Shader.new()
	mob_shader.code = MOB_SHADER
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


## Материал существа с текстурой-скином: свой у каждого существа (свет, покраснение от урона).
static func mob_material(skin: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = mob_shader
	m.set_shader_parameter("skin", skin)
	_instance_materials.append(m)
	_apply_environment(m)
	return m


## Копия материала для одного объекта (освещение задаётся через set_light).
static func instance_material(base: ShaderMaterial) -> ShaderMaterial:
	var m := base.duplicate() as ShaderMaterial
	if base != hand_material:
		_instance_materials.append(m)
	return m


## Освещение объекта: небесный свет (0–1), свет блоков (0–1) и покраснение от урона.
static func set_light(mi: GeometryInstance3D, sky: float, block: float, hurt := 0.0) -> void:
	var m := mi.material_override as ShaderMaterial
	if m == null:
		return
	var key := Vector3(snappedf(sky, 0.01), snappedf(block, 0.01), snappedf(hurt, 0.01))
	if mi.has_meta("light") and mi.get_meta("light") == key:
		return
	mi.set_meta("light", key)
	m.set_shader_parameter("local_sky", key.x)
	m.set_shader_parameter("local_block", key.y)
	m.set_shader_parameter("hurt", key.z)


static var _env := [Color(0.68, 0.82, 1.0), 48.0, 96.0, 1.0]


static func _apply_environment(m: ShaderMaterial) -> void:
	m.set_shader_parameter("fog_color", _env[0])
	m.set_shader_parameter("fog_start", _env[1])
	m.set_shader_parameter("fog_end", _env[2])
	m.set_shader_parameter("daylight", _env[3])


static func set_environment(fog_color: Color, fog_start: float, fog_end: float, daylight: float) -> void:
	_env = [fog_color, fog_start, fog_end, daylight]
	for m: ShaderMaterial in [chunk_material, water_material, entity_material]:
		_apply_environment(m)
	hand_material.set_shader_parameter("daylight", daylight)
	hand_material.set_shader_parameter("fog_start", 1000.0)
	hand_material.set_shader_parameter("fog_end", 2000.0)
	var alive: Array[ShaderMaterial] = []
	for m in _instance_materials:
		# Ссылки держат только этот список и цикл — объект удалён.
		if m.get_reference_count() > 2:
			_apply_environment(m)
			alive.append(m)
	_instance_materials = alive


## Меш предмета для руки и земли: блок — объёмный, остальное — выдавленный спрайт.
static func item_mesh(id: int, data: int = 0) -> ArrayMesh:
	var key := id * 65536 + (data & 0xFFFF)
	if _item_meshes.has(key):
		return _item_meshes[key]
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	if Items.is_block(id) and not Items.is_flat_block(id):
		var meta := data & 15
		if id == Blocks.CHEST or id == Blocks.FURNACE or id == Blocks.DISPENSER or id == Blocks.PUMPKIN \
				or id == Blocks.JACK_O_LANTERN or Blocks.is_stairs(id):
			meta = 0
		if id == Blocks.SNOW_LAYER:
			meta = 0
		arrays = ChunkMesher.block_arrays(id, meta)
	if arrays.is_empty():
		arrays = _sprite_arrays(id, data)
	if not arrays.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_item_meshes[key] = mesh
	return mesh


## Совместимость со старым кодом: меш блока.
static func block_mesh(id: int, meta: int = 0) -> ArrayMesh:
	return item_mesh(id, meta)


## Выдавленный спрайт 16×16 (как предметы в оригинале): лицевая и задняя грани + бортики.
static func _sprite_arrays(id: int, data: int) -> Array:
	var layer := Items.sprite_tile(id, data)
	var img: Image = tiles[layer]
	var tint := Items.sprite_tint(id, data)
	var surf := ChunkMesher.Surface.new()
	var px := 1.0 / TILE
	var depth := px
	var s := Vector3(-0.5, -0.5, 0.0)
	var front := [s + Vector3(0, 0, depth / 2), s + Vector3(1, 0, depth / 2), s + Vector3(1, 1, depth / 2), s + Vector3(0, 1, depth / 2)]
	var back := [s + Vector3(1, 0, -depth / 2), s + Vector3(0, 0, -depth / 2), s + Vector3(0, 1, -depth / 2), s + Vector3(1, 1, -depth / 2)]
	surf.quad(front, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], layer, 1.0, 0.0, tint)
	surf.quad(back, [Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)], layer, 0.8, 0.0, tint)
	var ov := Items.overlay(id, data)
	if ov.size() == 2:
		var lift := Vector3(0, 0, 0.002)
		surf.quad([front[0] + lift, front[1] + lift, front[2] + lift, front[3] + lift],
			[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], int(ov[0]), 1.0, 0.0, ov[1])
	# Бортики по краям непрозрачных пикселей.
	for y in TILE:
		for x in TILE:
			if img.get_pixel(x, y).a < 0.5:
				continue
			var x0 := x * px - 0.5
			var x1 := x0 + px
			var y1 := 0.5 - y * px
			var y0 := y1 - px
			var zf := depth / 2
			var zb := -depth / 2
			var uv_c := Vector2((x + 0.5) * px, (y + 0.5) * px)
			var uv := [uv_c, uv_c, uv_c, uv_c]
			if x == TILE - 1 or img.get_pixel(x + 1, y).a < 0.5:
				surf.quad([Vector3(x1, y0, zf), Vector3(x1, y0, zb), Vector3(x1, y1, zb), Vector3(x1, y1, zf)], uv, layer, 0.6, 0.0, tint)
			if x == 0 or img.get_pixel(x - 1, y).a < 0.5:
				surf.quad([Vector3(x0, y0, zb), Vector3(x0, y0, zf), Vector3(x0, y1, zf), Vector3(x0, y1, zb)], uv, layer, 0.6, 0.0, tint)
			if y == 0 or img.get_pixel(x, y - 1).a < 0.5:
				surf.quad([Vector3(x0, y1, zf), Vector3(x1, y1, zf), Vector3(x1, y1, zb), Vector3(x0, y1, zb)], uv, layer, 0.9, 0.0, tint)
			if y == TILE - 1 or img.get_pixel(x, y + 1).a < 0.5:
				surf.quad([Vector3(x0, y0, zb), Vector3(x1, y0, zb), Vector3(x1, y0, zf), Vector3(x0, y0, zf)], uv, layer, 0.5, 0.0, tint)
	return surf.to_arrays()


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

static func _build_atlas() -> void:
	var images: Array[Image] = []
	for t in tiles:
		var im: Image = t.duplicate()
		_bleed_transparent(im)
		im.generate_mipmaps()
		images.append(im)
	atlas = Texture2DArray.new()
	var err := atlas.create_from_images(images)
	if err != OK:
		push_error("Не удалось создать текстурный массив: %s" % err)


## Прозрачные пиксели получают цвет соседних непрозрачных — иначе мипмапы темнеют по краям.
static func _bleed_transparent(img: Image) -> void:
	var src: Image = img.duplicate()
	for y in TILE:
		for x in TILE:
			var c := src.get_pixel(x, y)
			if c.a >= 0.5:
				continue
			var sum := Color(0, 0, 0, 0)
			var n := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var q := src.get_pixel(clampi(x + dx, 0, TILE - 1), clampi(y + dy, 0, TILE - 1))
					if q.a >= 0.5:
						sum += q
						n += 1
			if n > 0:
				var avg := sum / n
				img.set_pixel(x, y, Color(avg.r, avg.g, avg.b, c.a))


static func _build_background() -> void:
	var img: Image = tiles[Tex.DIRT].duplicate()
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _shade(img.get_pixel(x, y), 0.42))
	img.resize(TILE * 4, TILE * 4, Image.INTERPOLATE_NEAREST)
	background = ImageTexture.create_from_image(img)


static func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


static func _mul(c: Color, t: Color) -> Color:
	return Color(c.r * t.r, c.g * t.g, c.b * t.b, c.a)


# --- Значки ----------------------------------------------------------------

## Значок предмета (кэшируется).
static func icon(id: int, data: int = 0) -> Texture2D:
	if Items.is_damageable(id):
		data = 0
	var key := id * 65536 + (data & 0xFFFF)
	if _icons.has(key):
		return _icons[key]
	var img: Image
	if Items.is_block(id) and not Items.is_flat_block(id):
		img = _block_icon(id, data)
	else:
		img = _flat_icon(id, data)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


static func _flat_icon(id: int, data: int) -> Image:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var src: Image = tiles[Items.sprite_tile(id, data)]
	var tint := Items.sprite_tint(id, data)
	var ov := Items.overlay(id, data)
	var k := ICON_SIZE / TILE
	for y in TILE:
		for x in TILE:
			var c := _mul(src.get_pixel(x, y), tint)
			if ov.size() == 2:
				var o: Color = (tiles[int(ov[0])] as Image).get_pixel(x, y)
				if o.a >= 0.5:
					c = _mul(o, ov[1])
			if c.a < 0.5:
				continue
			c.a = 1.0
			img.fill_rect(Rect2i(x * k, y * k, k, k), c)
	return img


## Изометрический значок блока любой формы: верх, южная (слева) и восточная (справа) грани
## всех параллелепипедов формы, с буфером глубины.
static func _block_icon(id: int, data: int) -> Image:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var meta := data & 15
	if Blocks.is_stairs(id):
		meta = 2
	elif id in [Blocks.CHEST, Blocks.FURNACE, Blocks.DISPENSER, Blocks.PUMPKIN, Blocks.JACK_O_LANTERN, Blocks.LIT_FURNACE]:
		meta = 0
	var conn := 0
	if Blocks.shapes[id] == Blocks.SH_FENCE:
		conn = 2 | 8
	var boxes: Array[AABB] = Blocks.shape_boxes(id, meta, conn)
	if Blocks.shapes[id] == Blocks.SH_CUBE or boxes.is_empty():
		boxes = [AABB(Vector3.ZERO, Vector3.ONE)]
	var depth := PackedFloat32Array()
	depth.resize(ICON_SIZE * ICON_SIZE)
	depth.fill(-INF)
	var w := ICON_SIZE - 6.0
	var ax := Vector2(w / 2.0, w / 4.0)
	var bx := Vector2(-w / 2.0, w / 4.0)
	var side_h := w * 0.56
	var origin := Vector2(ICON_SIZE / 2.0, (ICON_SIZE - (w * 0.5 + side_h)) / 2.0)
	# Проекция: (x, y, z) блока → экран. Вершина (0, 1, 0) — верхний угол значка.
	var proj := func(p: Vector3) -> Vector2:
		return origin + ax * p.x + bx * p.z + Vector2(0, side_h) * (1.0 - p.y)
	for box in boxes:
		var lo := box.position
		var hi := box.end
		# Верх (y = hi.y): параметры (x, z).
		_icon_face(img, depth, id, meta, 2, proj, [Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z)],
			Vector2(lo.x, lo.z), Vector2(hi.x, hi.z), 1.0)
		# Юг (z = hi.z): параметры (x, y).
		_icon_face(img, depth, id, meta, 4, proj, [Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z)],
			Vector2(lo.x, 1.0 - hi.y), Vector2(hi.x, 1.0 - lo.y), 0.82)
		# Восток (x = hi.x): параметры (1 - z, y).
		_icon_face(img, depth, id, meta, 0, proj, [Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, hi.z)],
			Vector2(1.0 - hi.z, 1.0 - hi.y), Vector2(1.0 - lo.z, 1.0 - lo.y), 0.62)
	return img


## Растеризация грани-параллелограмма: p — [начало, конец по u, конец по v] в координатах блока,
## uv0/uv1 — область текстуры.
static func _icon_face(img: Image, depth: PackedFloat32Array, id: int, meta: int, face: int, proj: Callable, p: Array,
		uv0: Vector2, uv1: Vector2, shade: float) -> void:
	var o: Vector2 = proj.call(p[0])
	var eu: Vector2 = proj.call(p[1]) - o
	var ev: Vector2 = proj.call(p[2]) - o
	var det := eu.x * ev.y - eu.y * ev.x
	if absf(det) < 1e-6:
		return
	var tile: Image = tiles[Blocks.texture_of(id, face, meta)]
	var tint := Color.WHITE
	if Blocks.tinted[id] == 1 and not (id == Blocks.GRASS and face != 2):
		tint = Items.sprite_tint(id, meta)
	var corners := [o, o + eu, o + ev, o + eu + ev]
	var mn := Vector2(INF, INF)
	var mx := -mn
	for c: Vector2 in corners:
		mn = mn.min(c)
		mx = mx.max(c)
	var p0: Vector3 = p[0]
	var du: Vector3 = p[1] - p0
	var dv: Vector3 = p[2] - p0
	for py in range(maxi(int(mn.y), 0), mini(int(ceil(mx.y)), ICON_SIZE)):
		for px in range(maxi(int(mn.x), 0), mini(int(ceil(mx.x)), ICON_SIZE)):
			var q := Vector2(px + 0.5, py + 0.5) - o
			var s := (q.x * ev.y - q.y * ev.x) / det
			var t := (eu.x * q.y - eu.y * q.x) / det
			if s < 0.0 or s >= 1.0 or t < 0.0 or t >= 1.0:
				continue
			var wp := p0 + du * s + dv * t
			var dpt := wp.x + wp.y + wp.z
			var di := px + py * ICON_SIZE
			if dpt <= depth[di]:
				continue
			var u := lerpf(uv0.x, uv1.x, s)
			var v := lerpf(uv0.y, uv1.y, t)
			var c := tile.get_pixel(clampi(int(u * TILE), 0, TILE - 1), clampi(int(v * TILE), 0, TILE - 1))
			if c.a < 0.5:
				continue
			c = _shade(_mul(c, tint), shade)
			c.a = 1.0
			img.set_pixel(px, py, c)
			depth[di] = dpt
