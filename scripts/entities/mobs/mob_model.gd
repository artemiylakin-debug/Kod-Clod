class_name MobModel
extends RefCounted
## Коробочная модель существа, как в оригинале: части (голова, тело, лапы…) из параллелепипедов
## с развёрткой текстуры по схеме Minecraft (скин 64×32 и т. п., фильтрация «ближайший пиксель»).
##
## Описания частей задаются в координатах моделей Minecraft (пиксели, ось Y вниз, морда к −Z,
## земля на y = 24) и переводятся в координаты Godot: (x, 24 − y, −z) / 16 — морда смотрит на +Z.
## Повороты частей: X — без изменений, Y и Z — с обратным знаком; порядок как в оригинале (Z·Y·X).
##
## Меши частей общие для всех существ одного вида; материал (скин, свет, покраснение) — свой у
## каждого существа. Освещение задаётся через TextureFactory.set_light().

## Шейдер существ: как MOB_SHADER из TextureFactory, плюс светящиеся пиксели (альфа 0.5–0.9:
## глаза паука и эндермена, ифрит, магма) и белая вспышка (крипер перед взрывом).
const SHADER_CODE := """
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
uniform float flash = 0.0;

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
	light = mix(light, vec3(1.0), step(tex.a, 0.9));
	vec3 col = tex.rgb * tint.rgb * light;
	col = mix(col, vec3(1.0, 0.1, 0.1) * max(light.r, 0.3), hurt * 0.55);
	col = mix(col, vec3(1.0), flash * 0.7);
	float fog = clamp((v_dist - fog_start) / (fog_end - fog_start), 0.0, 1.0);
	ALBEDO = mix(col, fog_color, fog);
}
"""

## Полупрозрачный слой (внешняя оболочка слизня, свечение кристалла).
const SHADER_TRANSLUCENT := """
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque;

uniform sampler2D skin : source_color, filter_nearest, repeat_disable;
uniform float daylight = 1.0;
uniform vec3 fog_color : source_color = vec3(0.68, 0.82, 1.0);
uniform float fog_start = 48.0;
uniform float fog_end = 96.0;
uniform float local_sky = 1.0;
uniform float local_block = 0.0;
uniform float hurt = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float flash = 0.0;

varying float v_dist;

void vertex() {
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 tex = texture(skin, UV);
	if (tex.a < 0.03) {
		discard;
	}
	vec3 light = max(vec3(local_sky * daylight), vec3(local_block) * vec3(1.0, 0.9, 0.75));
	light = max(light, vec3(0.07)) * COLOR.rgb;
	vec3 col = tex.rgb * tint.rgb * light;
	col = mix(col, vec3(1.0, 0.1, 0.1) * max(light.r, 0.3), hurt * 0.55);
	col = mix(col, vec3(1.0), flash * 0.7);
	float fog = clamp((v_dist - fog_start) / (fog_end - fog_start), 0.0, 1.0);
	ALBEDO = mix(col, fog_color, fog);
	ALPHA = tex.a;
}
"""

## Затенение граней: верх, низ, перед/зад, бока.
const SHADE_TOP := 1.0
const SHADE_BOTTOM := 0.5
const SHADE_Z := 0.8
const SHADE_X := 0.62

static var _shader: Shader
static var _shader_translucent: Shader
## Описания моделей (с готовыми мешами частей): ключ → словарь.
static var _defs: Dictionary = {}

# --- Экземпляр модели --------------------------------------------------------

## Узел модели внутри существа: смещение для сглаживания движения и поворот корпуса.
var root: Node3D
## Внутренний узел: масштаб (детёныши, размер слизня), наклон при смерти.
var pivot: Node3D
## Части: имя → MeshInstance3D (узел поворота части).
var parts: Dictionary = {}
var rest_rot: Dictionary = {}
var rest_pos: Dictionary = {}
var materials: Array[ShaderMaterial] = []
## По одному узлу на материал (для set_light) и предметы в руках/на спине.
var lit: Array[GeometryInstance3D] = []
var key := ""
## Смещение модели по высоте (низ модели — на уровне ног).
var ground := 0.0
var _flash := 0.0
var _tint := Color.WHITE


## Создаёт модель по описанию key со скинами (по одному на слой).
static func create(model_key: String, skins: Array) -> MobModel:
	var m := MobModel.new()
	m.key = model_key
	var def := get_def(model_key)
	m.root = Node3D.new()
	m.root.name = "Model"
	m.pivot = Node3D.new()
	m.root.add_child(m.pivot)
	var layers: Array = def["layers"]
	for i in layers.size():
		var layer: Dictionary = layers[i]
		var skin: Texture2D = skins[mini(i, skins.size() - 1)] if not skins.is_empty() else null
		if layer.has("skin_index"):
			skin = skins[int(layer["skin_index"])]
		m.materials.append(make_material(skin, bool(layer.get("translucent", false))))
	var meshes: Dictionary = def["meshes"]
	var first_lit := {}
	for p: Dictionary in def["parts"]:
		var n: String = p["n"]
		var mi := MeshInstance3D.new()
		mi.name = n
		mi.mesh = meshes[n]
		var layer_i: int = p.get("layer", 0)
		mi.material_override = m.materials[layer_i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation_order = EULER_ORDER_ZYX
		mi.position = p["pos"]
		mi.rotation = p["rot"]
		m.rest_pos[n] = p["pos"]
		m.rest_rot[n] = p["rot"]
		var parent: String = p.get("parent", "")
		if parent != "" and m.parts.has(parent):
			(m.parts[parent] as Node3D).add_child(mi)
		else:
			m.pivot.add_child(mi)
		m.parts[n] = mi
		if not first_lit.has(layer_i):
			first_lit[layer_i] = true
			m.lit.append(mi)
	m.ground = float(def["ground"])
	m.pivot.position.y = m.ground
	return m


static func make_material(skin: Texture2D, translucent := false) -> ShaderMaterial:
	_ensure_shaders()
	var mat := TextureFactory.mob_material(skin)
	mat.shader = _shader_translucent if translucent else _shader
	mat.set_shader_parameter("skin", skin)
	TextureFactory._apply_environment(mat)
	return mat


static func _ensure_shaders() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
		_shader_translucent = Shader.new()
		_shader_translucent.code = SHADER_TRANSLUCENT


## Освещение всех материалов модели (небо 0–1, свет блоков 0–1, покраснение 0–1).
func set_light(sky: float, block: float, hurt: float) -> void:
	for gi in lit:
		if is_instance_valid(gi):
			TextureFactory.set_light(gi, sky, block, hurt)


## Белая вспышка (крипер).
func set_flash(v: float) -> void:
	v = snappedf(v, 0.05)
	if v == _flash:
		return
	_flash = v
	for m in materials:
		m.set_shader_parameter("flash", v)


## Оттенок слоя (шерсть овцы).
func set_tint(layer: int, c: Color) -> void:
	if layer < materials.size():
		materials[layer].set_shader_parameter("tint", c)


## Сменить скин слоя (рот гаста, окрас кошки, профессия).
func set_skin(layer: int, tex: Texture2D) -> void:
	if layer < materials.size():
		materials[layer].set_shader_parameter("skin", tex)


func has_part(n: String) -> bool:
	return parts.has(n)


## Поворот части относительно положения покоя (в координатах Godot, радианы).
func rot(n: String, r: Vector3) -> void:
	var mi: Node3D = parts.get(n)
	if mi != null:
		mi.rotation = (rest_rot[n] as Vector3) + r


## Абсолютный поворот части.
func set_rot(n: String, r: Vector3) -> void:
	var mi: Node3D = parts.get(n)
	if mi != null:
		mi.rotation = r


## Сдвиг части от положения покоя (в пикселях модели, ось Y вверх).
func shift(n: String, d: Vector3) -> void:
	var mi: Node3D = parts.get(n)
	if mi != null:
		mi.position = (rest_pos[n] as Vector3) + d / 16.0


## Положение части (в пикселях модели относительно земли, ось Y вверх, морда к +Z).
func place(n: String, p: Vector3) -> void:
	var mi: Node3D = parts.get(n)
	if mi != null:
		mi.position = p / 16.0


func set_visible(n: String, v: bool) -> void:
	var mi: Node3D = parts.get(n)
	if mi != null:
		mi.visible = v


## Предмет (меш из TextureFactory) на части модели: меч в руке, блок у эндермена, грибы на спине.
func attach_item(part: String, id: int, data: int, pos: Vector3, rot_deg: Vector3, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = TextureFactory.item_mesh(id, data)
	mi.material_override = TextureFactory.instance_material(TextureFactory.entity_material)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos / 16.0
	mi.rotation_degrees = rot_deg
	mi.scale = Vector3.ONE * size
	var parent: Node3D = parts.get(part, pivot)
	parent.add_child(mi)
	lit.append(mi)
	return mi


func detach(mi: MeshInstance3D) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	lit.erase(mi)
	mi.queue_free()


# --- Описания и меши ---------------------------------------------------------

## Описание модели с готовыми мешами (строится один раз).
static func get_def(model_key: String) -> Dictionary:
	if _defs.has(model_key):
		return _defs[model_key]
	var def := _describe(model_key)
	var tex: Vector2i = def["tex"]
	var meshes := {}
	var scale: float = def.get("scale", 1.0)
	for p: Dictionary in def["parts"]:
		var parent: String = p.get("parent", "")
		var pv: Vector3 = p["p"]
		# Корневые части — от земли модели, дочерние — от точки поворота родителя.
		var pos := Vector3(pv.x, (0.0 if parent != "" else 24.0) - pv.y, -pv.z) / 16.0 * scale
		var r: Vector3 = p.get("r", Vector3.ZERO)
		p["pos"] = pos
		p["rot"] = Vector3(r.x, -r.y, -r.z)
		meshes[p["n"]] = _part_mesh(p["b"], tex, scale)
	def["meshes"] = meshes
	if not def.has("layers"):
		def["layers"] = [{}]
	if not def.has("ground"):
		def["ground"] = -_rest_min_y(def)
	_defs[model_key] = def
	return def


## Нижняя точка модели в положении покоя (для постановки на землю).
static func _rest_min_y(def: Dictionary) -> float:
	var xf := {}
	var min_y := INF
	var scale: float = def.get("scale", 1.0)
	for p: Dictionary in def["parts"]:
		var t := Transform3D(Basis.from_euler(p["rot"], EULER_ORDER_ZYX), p["pos"])
		var parent: String = p.get("parent", "")
		if parent != "" and xf.has(parent):
			t = (xf[parent] as Transform3D) * t
		xf[p["n"]] = t
		if p.get("no_ground", false):
			continue
		for b: Array in p["b"]:
			var g: float = b[8] if b.size() > 8 else 0.0
			var lo := Vector3(float(b[2]) - g, -(float(b[3]) + float(b[6]) + g), -(float(b[4]) + float(b[7]) + g)) / 16.0 * scale
			var hi := Vector3(float(b[2]) + float(b[5]) + g, -(float(b[3]) - g), -(float(b[4]) - g)) / 16.0 * scale
			for i in 8:
				var c := Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z)
				min_y = minf(min_y, (t * c).y)
	return 0.0 if min_y == INF else min_y


## Меш части: параллелепипеды [u, v, x, y, z, w, h, d, раздувание, зеркально].
static func _part_mesh(boxes: Array, tex: Vector2i, scale: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for b: Array in boxes:
		_add_box(b, tex, scale, verts, uvs, cols, idx)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _add_box(b: Array, tex: Vector2i, scale: float, verts: PackedVector3Array, uvs: PackedVector2Array,
		cols: PackedColorArray, idx: PackedInt32Array) -> void:
	var u := float(b[0])
	var v := float(b[1])
	var bx := float(b[2])
	var by := float(b[3])
	var bz := float(b[4])
	var w := float(b[5])
	var h := float(b[6])
	var d := float(b[7])
	var g: float = b[8] if b.size() > 8 else 0.0
	var mirror: bool = b[9] if b.size() > 9 else false
	var k := scale / 16.0
	# Перевод в координаты Godot: y → −y, z → −z.
	var x0 := (bx - g) * k
	var x1 := (bx + w + g) * k
	var y0 := -(by + h + g) * k
	var y1 := -(by - g) * k
	var z0 := -(bz + d + g) * k
	var z1 := -(bz - g) * k
	var tw := float(tex.x)
	var th := float(tex.y)
	# Области развёртки (как ModelBox в оригинале).
	var r_right := Rect2(u, v + d, d, h)
	var r_left := Rect2(u + d + w, v + d, d, h)
	if mirror:
		var tmp := r_right
		r_right = r_left
		r_left = tmp
	var faces := [
		# +Z (морда): слева −X, справа +X.
		[Rect2(u + d, v + d, w, h), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x0, y0, z1), SHADE_Z, w * h],
		# −Z (спина).
		[Rect2(u + d + w + d, v + d, w, h), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x1, y0, z0), SHADE_Z, w * h],
		# −X (правый бок существа).
		[r_right, Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3(x0, y0, z0), SHADE_X, d * h],
		# +X (левый бок).
		[r_left, Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), SHADE_X, d * h],
		# Верх.
		[Rect2(u + d, v, w, d), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), SHADE_TOP, w * d],
		# Низ.
		[Rect2(u + d + w, v, w, d), Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x0, y0, z0), SHADE_BOTTOM, w * d],
	]
	for f: Array in faces:
		if float(f[6]) <= 0.0:
			continue
		var r: Rect2 = f[0]
		var ua := r.position.x / tw
		var ub := r.end.x / tw
		if mirror:
			var t := ua
			ua = ub
			ub = t
		var va := r.position.y / th
		var vb := r.end.y / th
		var base := verts.size()
		verts.append(f[1])
		verts.append(f[2])
		verts.append(f[3])
		verts.append(f[4])
		uvs.append(Vector2(ua, va))
		uvs.append(Vector2(ub, va))
		uvs.append(Vector2(ub, vb))
		uvs.append(Vector2(ua, vb))
		var s: float = f[5]
		var c := Color(s, s, s, 1.0)
		for i in 4:
			cols.append(c)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


static func _p(n: String, pivot: Vector3, boxes: Array, parent := "", r := Vector3.ZERO, layer := 0) -> Dictionary:
	var d := {"n": n, "p": pivot, "b": boxes}
	if parent != "":
		d["parent"] = parent
	if r != Vector3.ZERO:
		d["r"] = r
	if layer != 0:
		d["layer"] = layer
	return d


# --- Модели (координаты и развёртки — по моделям Minecraft 1.2) --------------

static func _describe(model_key: String) -> Dictionary:
	match model_key:
		"biped":
			return {"tex": Vector2i(64, 32), "parts": [
				_p("head", Vector3(0, 0, 0), [[0, 0, -4, -8, -4, 8, 8, 8], [32, 0, -4, -8, -4, 8, 8, 8, 0.5]]),
				_p("body", Vector3(0, 0, 0), [[16, 16, -4, 0, -2, 8, 12, 4]]),
				_p("rarm", Vector3(-5, 2, 0), [[40, 16, -3, -2, -2, 4, 12, 4]]),
				_p("larm", Vector3(5, 2, 0), [[40, 16, -1, -2, -2, 4, 12, 4, 0.0, true]]),
				_p("rleg", Vector3(-1.9, 12, 0), [[0, 16, -2, 0, -2, 4, 12, 4]]),
				_p("lleg", Vector3(1.9, 12, 0), [[0, 16, -2, 0, -2, 4, 12, 4, 0.0, true]]),
			]}
		"giant":
			var gd := _describe("biped")
			gd["scale"] = 6.0
			return gd
		"skeleton":
			return {"tex": Vector2i(64, 32), "parts": [
				_p("head", Vector3(0, 0, 0), [[0, 0, -4, -8, -4, 8, 8, 8]]),
				_p("body", Vector3(0, 0, 0), [[16, 16, -4, 0, -2, 8, 12, 4]]),
				_p("rarm", Vector3(-5, 2, 0), [[40, 16, -1, -2, -1, 2, 12, 2]]),
				_p("larm", Vector3(5, 2, 0), [[40, 16, -1, -2, -1, 2, 12, 2, 0.0, true]]),
				_p("rleg", Vector3(-2, 12, 0), [[0, 16, -1, 0, -1, 2, 12, 2]]),
				_p("lleg", Vector3(2, 12, 0), [[0, 16, -1, 0, -1, 2, 12, 2, 0.0, true]]),
			]}
		"creeper":
			return {"tex": Vector2i(64, 32), "parts": [
				_p("head", Vector3(0, 6, 0), [[0, 0, -4, -8, -4, 8, 8, 8]]),
				_p("body", Vector3(0, 6, 0), [[16, 16, -4, 0, -2, 8, 12, 4]]),
				_p("leg1", Vector3(-2, 18, 4), [[0, 16, -2, 0, -2, 4, 6, 4]]),
				_p("leg2", Vector3(2, 18, 4), [[0, 16, -2, 0, -2, 4, 6, 4]]),
				_p("leg3", Vector3(-2, 18, -4), [[0, 16, -2, 0, -2, 4, 6, 4]]),
				_p("leg4", Vector3(2, 18, -4), [[0, 16, -2, 0, -2, 4, 6, 4]]),
			]}
		"spider":
			var q := PI / 4.0
			var e := 0.3926991
			var sp := [
				_p("head", Vector3(0, 15, -3), [[32, 4, -4, -4, -8, 8, 8, 8]]),
				_p("neck", Vector3(0, 15, 0), [[0, 0, -3, -3, -3, 6, 6, 6]]),
				_p("body", Vector3(0, 15, 9), [[0, 12, -5, -4, -6, 10, 8, 12]]),
			]
			var zs := [2, 2, 1, 1, 0, 0, -1, -1]
			var rz := [-q, q, -q * 0.74, q * 0.74, -q * 0.74, q * 0.74, -q, q]
			var ry := [e * 2.0, -e * 2.0, e, -e, -e, e, -e * 2.0, e * 2.0]
			for i in 8:
				var right := i % 2 == 0
				var box: Array = [18, 0, -15, -1, -1, 16, 2, 2] if right else [18, 0, -1, -1, -1, 16, 2, 2]
				sp.append(_p("leg%d" % (i + 1), Vector3(-4 if right else 4, 15, zs[i]), [box], "", Vector3(0, ry[i], rz[i])))
			return {"tex": Vector2i(64, 32), "parts": sp}
		"pig":
			return {"tex": Vector2i(64, 32), "parts": [
				_p("head", Vector3(0, 12, -6), [[0, 0, -4, -4, -8, 8, 8, 8], [16, 16, -2, 0, -9, 4, 3, 1]]),
				_p("body", Vector3(0, 11, 2), [[28, 8, -5, -10, -7, 10, 16, 8]], "", Vector3(PI / 2.0, 0, 0)),
				_p("leg1", Vector3(-3, 18, 7), [[0, 16, -2, 0, -2, 4, 6, 4]]),
				_p("leg2", Vector3(3, 18, 7), [[0, 16, -2, 0, -2, 4, 6, 4]]),
				_p("leg3", Vector3(-3, 18, -5), [[0, 16, -2, 0, -2, 4, 6, 4]]),
				_p("leg4", Vector3(3, 18, -5), [[0, 16, -2, 0, -2, 4, 6, 4]]),
			]}
		"cow":
			return {"tex": Vector2i(64, 32), "parts": [
				_p("head", Vector3(0, 4, -8), [[0, 0, -4, -4, -6, 8, 8, 6], [22, 0, -5, -5, -4, 1, 3, 1], [22, 0, 4, -5, -4, 1, 3, 1]]),
				_p("body", Vector3(0, 5, 2), [[18, 4, -6, -10, -7, 12, 18, 10], [52, 0, -2, 2, -8, 4, 6, 1]], "", Vector3(PI / 2.0, 0, 0)),
				_p("leg1", Vector3(-4, 12, 7), [[0, 16, -2, 0, -2, 4, 12, 4]]),
				_p("leg2", Vector3(4, 12, 7), [[0, 16, -2, 0, -2, 4, 12, 4]]),
				_p("leg3", Vector3(-4, 12, -6), [[0, 16, -2, 0, -2, 4, 12, 4]]),
				_p("leg4", Vector3(4, 12, -6), [[0, 16, -2, 0, -2, 4, 12, 4]]),
			]}
		"sheep":
			return {"tex": Vector2i(64, 32), "layers": [{}, {"skin_index": 1}], "parts": [
				_p("head", Vector3(0, 6, -8), [[0, 0, -3, -4, -6, 6, 6, 8]]),
				_p("body", Vector3(0, 5, 2), [[28, 8, -4, -10, -7, 8, 16, 6]], "", Vector3(PI / 2.0, 0, 0)),
				_p("leg1", Vector3(-3, 12, 7), [[0, 16, -2, 0, -2, 4, 12, 4]]),
				_p("leg2", Vector3(3, 12, 7), [[0, 16, -2, 0, -2, 4, 12, 4]]),
				_p("leg3", Vector3(-3, 12, -5), [[0, 16, -2, 0, -2, 4, 12, 4]]),
				_p("leg4", Vector3(3, 12, -5), [[0, 16, -2, 0, -2, 4, 12, 4]]),
				_p("wool_head", Vector3(0, 0, 0), [[0, 0, -3, -4, -4, 6, 6, 6, 0.6]], "head", Vector3.ZERO, 1),
				_p("wool_body", Vector3(0, 0, 0), [[28, 8, -4, -10, -7, 8, 16, 6, 1.75]], "body", Vector3.ZERO, 1),
				_p("wool_leg1", Vector3(0, 0, 0), [[0, 16, -2, 0, -2, 4, 6, 4, 0.5]], "leg1", Vector3.ZERO, 1),
				_p("wool_leg2", Vector3(0, 0, 0), [[0, 16, -2, 0, -2, 4, 6, 4, 0.5]], "leg2", Vector3.ZERO, 1),
				_p("wool_leg3", Vector3(0, 0, 0), [[0, 16, -2, 0, -2, 4, 6, 4, 0.5]], "leg3", Vector3.ZERO, 1),
				_p("wool_leg4", Vector3(0, 0, 0), [[0, 16, -2, 0, -2, 4, 6, 4, 0.5]], "leg4", Vector3.ZERO, 1),
			]}
		"chicken":
			return {"tex": Vector2i(64, 32), "parts": [
				_p("head", Vector3(0, 15, -4), [[0, 0, -2, -6, -2, 4, 6, 3], [14, 0, -2, -4, -4, 4, 2, 2], [14, 4, -1, -2, -3, 2, 2, 2]]),
				_p("body", Vector3(0, 16, 0), [[0, 9, -3, -4, -3, 6, 8, 6]], "", Vector3(PI / 2.0, 0, 0)),
				_p("rleg", Vector3(-2, 19, 1), [[26, 0, -1, 0, -3, 3, 5, 3]]),
				_p("lleg", Vector3(1, 19, 1), [[26, 0, -1, 0, -3, 3, 5, 3]]),
				_p("rwing", Vector3(-4, 13, 0), [[24, 13, 0, 0, -3, 1, 4, 6]]),
				_p("lwing", Vector3(4, 13, 0), [[24, 13, -1, 0, -3, 1, 4, 6]]),
			]}
		"squid":
			var sq := [_p("body", Vector3(0, 8, 0), [[0, 0, -6, -8, -6, 12, 16, 12]])]
			for i in 8:
				var a := i * TAU / 8.0 + PI / 2.0
				sq.append(_p("t%d" % i, Vector3(cos(a) * 5.0, 15, sin(a) * 5.0), [[48, 0, -1, 0, -1, 2, 18, 2]], "",
					Vector3(0, -i * TAU / 8.0 + PI / 2.0, 0)))
			return {"tex": Vector2i(64, 32), "parts": sq, "ground": -0.5}
		"wolf":
			return {"tex": Vector2i(64, 32), "parts": [
				_p("head", Vector3(0, 13.5, -7), [[0, 0, -3, -3, -2, 6, 6, 4], [16, 14, -3, -5, 0, 2, 2, 1], [16, 14, 1, -5, 0, 2, 2, 1],
					[0, 10, -1.5, 0, -5, 3, 3, 4]]),
				_p("body", Vector3(0, 14, 2), [[18, 14, -3, -2, -3, 6, 9, 6]], "", Vector3(PI / 2.0, 0, 0)),
				_p("mane", Vector3(0, 14, 2), [[21, 0, -4, -3, -3, 8, 6, 7]], "", Vector3(PI / 2.0, 0, 0)),
				_p("leg1", Vector3(-1.5, 16, 7), [[0, 18, -1, 0, -1, 2, 8, 2]]),
				_p("leg2", Vector3(1.5, 16, 7), [[0, 18, -1, 0, -1, 2, 8, 2]]),
				_p("leg3", Vector3(-1.5, 16, -4), [[0, 18, -1, 0, -1, 2, 8, 2]]),
				_p("leg4", Vector3(1.5, 16, -4), [[0, 18, -1, 0, -1, 2, 8, 2]]),
				_p("tail", Vector3(0, 12, 8), [[9, 18, -1, 0, -1, 2, 8, 2]], "", Vector3(PI / 5.0, 0, 0)),
			]}
		"ocelot":
			return {"tex": Vector2i(64, 32), "parts": [
				_p("head", Vector3(0, 15, -9), [[0, 0, -2.5, -2, -3, 5, 4, 5], [0, 24, -1.5, 0, -4, 3, 2, 2], [0, 10, -2, -3, 0, 1, 1, 2],
					[6, 10, 1, -3, 0, 1, 1, 2]]),
				_p("body", Vector3(0, 12, -10), [[20, 0, -2, 3, -8, 4, 16, 6]], "", Vector3(PI / 2.0, 0, 0)),
				_p("tail1", Vector3(0, 15, 8), [[0, 15, -0.5, 0, 0, 1, 8, 1]], "", Vector3(0.9, 0, 0)),
				_p("tail2", Vector3(0, 20, 14), [[4, 15, -0.5, 0, 0, 1, 8, 1]], "", Vector3(1.73, 0, 0)),
				_p("leg1", Vector3(-1.1, 18, 5), [[8, 13, -1, 0, 1, 2, 6, 2]]),
				_p("leg2", Vector3(1.1, 18, 5), [[8, 13, -1, 0, 1, 2, 6, 2]]),
				_p("leg3", Vector3(-1.2, 13.8, -5), [[40, 0, -1, 0, 0, 2, 10, 2]]),
				_p("leg4", Vector3(1.2, 13.8, -5), [[40, 0, -1, 0, 0, 2, 10, 2]]),
			]}
		"villager":
			return {"tex": Vector2i(64, 64), "parts": [
				_p("head", Vector3(0, 0, 0), [[0, 0, -4, -10, -4, 8, 10, 8], [24, 0, -1, -5, -6, 2, 4, 2]]),
				_p("body", Vector3(0, 0, 0), [[16, 20, -4, 0, -3, 8, 12, 6], [0, 38, -4, 0, -3, 8, 18, 6, 0.5]]),
				_p("arms", Vector3(0, 2, 0), [[44, 22, -8, -2, -2, 4, 8, 4], [44, 22, 4, -2, -2, 4, 8, 4, 0.0, true], [40, 38, -4, 2, -2, 8, 4, 4]],
					"", Vector3(-0.75, 0, 0)),
				_p("rleg", Vector3(-2, 12, 0), [[0, 22, -2, 0, -2, 4, 12, 4]]),
				_p("lleg", Vector3(2, 12, 0), [[0, 22, -2, 0, -2, 4, 12, 4, 0.0, true]]),
			]}
		"iron_golem":
			return {"tex": Vector2i(128, 128), "parts": [
				_p("head", Vector3(0, -7, -2), [[0, 0, -4, -12, -5.5, 8, 10, 8], [24, 0, -1, -5, -7.5, 2, 4, 2]]),
				_p("body", Vector3(0, -7, 0), [[0, 40, -9, -2, -6, 18, 12, 11], [0, 70, -4.5, 10, -3, 9, 5, 6, 0.5]]),
				_p("rarm", Vector3(0, -7, 0), [[60, 21, -13, -2.5, -3, 4, 30, 6]]),
				_p("larm", Vector3(0, -7, 0), [[60, 58, 9, -2.5, -3, 4, 30, 6]]),
				_p("rleg", Vector3(-4, 11, 0), [[37, 0, -3.5, -3, -3, 6, 16, 5]]),
				_p("lleg", Vector3(5, 11, 0), [[60, 0, -3.5, -3, -3, 6, 16, 5, 0.0, true]]),
			]}
		"snow_golem":
			return {"tex": Vector2i(64, 64), "parts": [
				_p("head", Vector3(0, 4, 0), [[0, 0, -4, -8, -4, 8, 8, 8, -0.5]]),
				_p("rarm", Vector3(-4, 6, 0), [[32, 0, -11, -1, -1, 12, 2, 2, -0.5]], "", Vector3(0, 0, 0.55)),
				_p("larm", Vector3(4, 6, 0), [[32, 0, -1, -1, -1, 12, 2, 2, -0.5, true]], "", Vector3(0, 0, -0.55)),
				_p("body", Vector3(0, 13, 0), [[0, 16, -5, -10, -5, 10, 10, 10, -0.5]]),
				_p("bottom", Vector3(0, 24, 0), [[0, 36, -6, -12, -6, 12, 12, 12, -0.5]]),
			]}
		"slime":
			return {"tex": Vector2i(64, 32), "layers": [{}, {"translucent": true}], "parts": [
				_p("inner", Vector3(0, 0, 0), [[0, 16, -3, 17, -3, 6, 6, 6], [32, 0, -3.25, 18, -3.5, 2, 2, 2], [32, 4, 1.25, 18, -3.5, 2, 2, 2],
					[32, 8, 0, 21, -3.5, 1, 1, 1]]),
				_p("outer", Vector3(0, 0, 0), [[0, 0, -4, 16, -4, 8, 8, 8]], "", Vector3.ZERO, 1),
			]}
		"magma_cube":
			var mg := [_p("core", Vector3(0, 0, 0), [[0, 40, -2, 18, -2, 4, 4, 4]])]
			for i in 8:
				var uu := 0 if i < 4 else 32
				var vv := (i % 4) * 9
				mg.append(_p("s%d" % i, Vector3(0, 0, 0), [[uu, vv, -4, 16 + i, -4, 8, 1, 8]]))
			return {"tex": Vector2i(64, 64), "parts": mg}
		"ghast":
			var gh := [_p("body", Vector3(0, 8, 0), [[0, 0, -8, -8, -8, 16, 16, 16]])]
			var lens := [11, 9, 13, 10, 12, 9, 13, 11, 10]
			for i in 9:
				@warning_ignore("integer_division")
				var row := i / 3
				var x := ((float(i % 3) - float(row % 2) * 0.5 + 0.25) / 2.0 * 2.0 - 1.0) * 5.0
				var z := (float(row) / 2.0 * 2.0 - 1.0) * 5.0
				gh.append(_p("t%d" % i, Vector3(x, 15, z), [[0, 0, -1, 0, -1, 2, lens[i], 2]]))
				gh[-1]["no_ground"] = true
			return {"tex": Vector2i(64, 32), "parts": gh, "scale": 4.5, "ground": -2.5}
		"blaze":
			var bl := [_p("head", Vector3(0, 0, 0), [[0, 0, -4, -4, -4, 8, 8, 8]])]
			for i in 12:
				bl.append(_p("rod%d" % i, Vector3(0, 0, 0), [[0, 16, 0, 0, 0, 2, 8, 2]]))
			return {"tex": Vector2i(64, 32), "parts": bl, "ground": 0.0}
		"enderman":
			return {"tex": Vector2i(64, 32), "parts": [
				_p("head", Vector3(0, -14, 0), [[0, 0, -4, -8, -4, 8, 8, 8]]),
				_p("jaw", Vector3(0, -14, 0), [[0, 16, -4, -8, -4, 8, 8, 8, -0.5]]),
				_p("body", Vector3(0, -14, 0), [[32, 16, -4, 0, -2, 8, 12, 4]]),
				_p("rarm", Vector3(-5, -12, 0), [[56, 0, -1, -2, -1, 2, 30, 2]]),
				_p("larm", Vector3(5, -12, 0), [[56, 0, -1, -2, -1, 2, 30, 2, 0.0, true]]),
				_p("rleg", Vector3(-2, -6, 0), [[56, 0, -1, 0, -1, 2, 30, 2]]),
				_p("lleg", Vector3(2, -6, 0), [[56, 0, -1, 0, -1, 2, 30, 2, 0.0, true]]),
			]}
		"silverfish":
			var sizes := [[3, 2, 2], [4, 3, 2], [6, 4, 3], [3, 3, 3], [2, 2, 3], [2, 1, 2], [1, 1, 2]]
			var uvs := [[0, 0], [0, 4], [0, 9], [0, 16], [0, 22], [11, 0], [13, 4]]
			var sf := []
			var zz := -3.5
			var seg_z := []
			for i in 7:
				var s: Array = sizes[i]
				sf.append(_p("s%d" % i, Vector3(0, 24 - float(s[1]), zz),
					[[uvs[i][0], uvs[i][1], -float(s[0]) * 0.5, 0, -float(s[2]) * 0.5, s[0], s[1], s[2]]]))
				seg_z.append(zz)
				if i < 6:
					zz += (float(s[2]) + float(sizes[i + 1][2])) * 0.5
			sf.append(_p("f0", Vector3(0, 16, seg_z[2]), [[20, 0, -5, 0, -1.5, 10, 8, 3]]))
			sf.append(_p("f1", Vector3(0, 20, seg_z[4]), [[20, 11, -3, 0, -1.5, 6, 4, 3]]))
			sf.append(_p("f2", Vector3(0, 19, seg_z[1]), [[20, 18, -3, 0, -1.5, 6, 5, 2]]))
			return {"tex": Vector2i(64, 32), "parts": sf}
		"end_crystal":
			return {"tex": Vector2i(64, 32), "scale": 2.0, "parts": [
				_p("base", Vector3(0, 24, 0), [[0, 16, -6, -4, -6, 12, 4, 12]]),
				_p("glass", Vector3(0, 12, 0), [[0, 0, -4, -4, -4, 8, 8, 8]]),
				_p("cube", Vector3(0, 0, 0), [[32, 0, -3, -3, -3, 6, 6, 6]], "glass"),
			]}
		"dragon":
			return _describe_dragon()
	push_warning("Нет модели: " + model_key)
	return _describe("pig")


## Дракон Края: голова с челюстью, шея и хвост из позвонков, тело, крылья с перепонками, лапы.
## Развёртка своя (текстура 256×256), размеры частей — как в оригинале.
static func _describe_dragon() -> Dictionary:
	var parts := []
	parts.append(_p("head", Vector3(0, 10, -60), [
		[0, 88, -8, -8, -10, 16, 16, 16], [64, 88, -6, -1, -26, 12, 5, 16],
		[176, 18, -5, -12, -4, 2, 4, 6, 0.0, true], [192, 18, -5, -3, -24, 2, 2, 4, 0.0, true],
		[176, 18, 3, -12, -4, 2, 4, 6], [192, 18, 3, -3, -24, 2, 2, 4]]))
	parts.append(_p("jaw", Vector3(0, 4, -10), [[120, 88, -6, 0, -16, 12, 4, 16]], "head"))
	for i in 5:
		parts.append(_p("neck%d" % i, Vector3(0, 10, -13 - i * 10), [[176, 88, -5, -5, -5, 10, 10, 10], [204, 0, -1, -9, -3, 2, 4, 6]]))
	parts.append(_p("body", Vector3(0, 4, 8), [[0, 0, -12, 0, -16, 24, 24, 64], [176, 0, -1, -6, -10, 2, 6, 12],
		[176, 0, -1, -6, 10, 2, 6, 12], [176, 0, -1, -6, 30, 2, 6, 12]]))
	for i in 12:
		parts.append(_p("tail%d" % i, Vector3(0, 10, 61 + i * 10), [[176, 88, -5, -5, -5, 10, 10, 10], [204, 0, -1, -9, -3, 2, 4, 6]]))
	# Крылья: правое (−X) и зеркальное левое.
	parts.append(_p("rwing", Vector3(-12, 5, 2), [[0, 120, -56, -4, -4, 56, 8, 8], [0, 136, -56, 0, 2, 56, 0, 56]]))
	parts.append(_p("rwingtip", Vector3(-56, 0, 0), [[128, 120, -56, -2, -2, 56, 4, 4], [0, 192, -56, 0, 2, 56, 0, 56]], "rwing"))
	parts.append(_p("lwing", Vector3(12, 5, 2), [[0, 120, 0, -4, -4, 56, 8, 8, 0.0, true], [0, 136, 0, 0, 2, 56, 0, 56, 0.0, true]]))
	parts.append(_p("lwingtip", Vector3(56, 0, 0), [[128, 120, 0, -2, -2, 56, 4, 4, 0.0, true], [0, 192, 0, 0, 2, 56, 0, 56, 0.0, true]], "lwing"))
	for side: int in [-1, 1]:
		var s := "r" if side < 0 else "l"
		var mir := side > 0
		parts.append(_p(s + "fleg", Vector3(12 * side, 20, 2), [[176, 136, -4, -4, -4, 8, 24, 8, 0.0, mir]], "", Vector3(1.3, 0, 0)))
		parts.append(_p(s + "flegtip", Vector3(0, 20, -1), [[208, 136, -3, -1, -3, 6, 24, 6, 0.0, mir]], s + "fleg", Vector3(-0.5, 0, 0)))
		parts.append(_p(s + "ffoot", Vector3(0, 23, 0), [[176, 168, -4, 0, -12, 8, 4, 16, 0.0, mir]], s + "flegtip", Vector3(0.75, 0, 0)))
		parts.append(_p(s + "rleg", Vector3(16 * side, 16, 42), [[168, 192, -8, -4, -8, 16, 32, 16, 0.0, mir]], "", Vector3(1.0, 0, 0)))
		parts.append(_p(s + "rlegtip", Vector3(0, 32, -4), [[168, 192, -6, -2, 0, 12, 32, 12, 0.0, mir]], s + "rleg", Vector3(0.5, 0, 0)))
		parts.append(_p(s + "rfoot", Vector3(0, 31, 4), [[0, 0, -9, 0, -20, 18, 6, 24, 0.0, mir]], s + "rlegtip", Vector3(0.75, 0, 0)))
	return {"tex": Vector2i(256, 256), "parts": parts, "ground": 0.0}
