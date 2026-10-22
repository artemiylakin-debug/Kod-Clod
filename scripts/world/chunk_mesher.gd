class_name ChunkMesher
extends RefCounted
## Строит меш чанка: полные кубы с отсечением граней и ambient occlusion, блоки других форм
## (растения, ступеньки, заборы, двери, факелы, рельсы, провода…), жидкости с уровнями.
## Свет: небесный (по карте высот) и от блоков (волна в ChunkLight + перетекание с соседей).
## Формат вершины: UV — координаты в тайле, UV2 = (слой текстуры, небесный свет),
## COLOR = (оттенок биома RGB, свет от блоков). Работает в рабочих потоках.

const S := WorldGen.CHUNK_SIZE
const H := WorldGen.CHUNK_HEIGHT
const LAYER := S * S
## Объём с рамкой в 1 блок из соседних чанков.
const PS := S + 2
const SZ := PS
const SY := PS * PS

## Яркость граней по направлению: +X, -X, +Y, -Y, +Z, -Z.
const FACE_SHADE := [0.6, 0.6, 1.0, 0.5, 0.8, 0.8]
const AO_CURVE := [0.42, 0.62, 0.8, 1.0]
## Небесный свет в зависимости от глубины под ближайшим непрозрачным блоком сверху.
const SKY_BY_DEPTH := [1.0, 0.82, 0.68, 0.56, 0.46, 0.38, 0.31, 0.25, 0.2, 0.16, 0.13, 0.1, 0.08, 0.065, 0.055, 0.05]

const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const AXIS_U := [Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 0)]
const AXIS_V := [Vector3i(0, 1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(0, 1, 0)]

static var neighbor_off := PackedInt32Array()
static var corner_pos: Array[PackedVector3Array] = []
static var corner_uv: Array[PackedVector2Array] = []
static var ao_off: Array[PackedInt32Array] = []
## 1, если обход вершин 0→1→2 идёт против часовой стрелки при взгляде снаружи.
static var ccw := PackedByteArray()
## Яркость от уровня света блоков 0–15 (кривая как в оригинале).
static var block_curve := PackedFloat32Array()
static var sky_curve := PackedFloat32Array()


class Surface:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func to_arrays() -> Array:
		if verts.is_empty():
			return []
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_INDEX] = indices
		return arr

	## Четырёхугольник; вершины перечислены против часовой стрелки при взгляде с лицевой стороны.
	func quad(p: Array, uv: Array, layer: float, sky: float, blk: float, tint: Color, two_sided := false) -> void:
		var s := verts.size()
		for k in 4:
			verts.append(p[k])
			uvs.append(uv[k])
			uv2.append(Vector2(layer, sky))
			colors.append(Color(tint.r, tint.g, tint.b, blk))
		indices.append_array(PackedInt32Array([s, s + 2, s + 1, s, s + 3, s + 2]))
		if two_sided:
			indices.append_array(PackedInt32Array([s, s + 1, s + 2, s, s + 2, s + 3]))


var _vol := PackedByteArray()
var _meta := PackedByteArray()
var _light := PackedByteArray()
var _hm := PackedInt32Array()
var _kinds := PackedByteArray()
var _grass := PackedColorArray()
var _foliage := PackedColorArray()
var _cx := 0
var _cz := 0
var _py := 1
var _py_end := 1
var _solid := Surface.new()
var _trans := Surface.new()
const PREP_STEPS := 5
var _input: Dictionary = {}
var _prep := 0
var _vol_top := 0
var _top_y := 0


static func _static_init() -> void:
	for d in 6:
		var n: Vector3i = DIRS[d]
		var u: Vector3i = AXIS_U[d]
		var v: Vector3i = AXIS_V[d]
		neighbor_off.append(_offset(n))
		var plane := Vector3(maxi(n.x, 0), maxi(n.y, 0), maxi(n.z, 0))
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var ao := PackedInt32Array()
		for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			var cu: int = c.x
			var cv: int = c.y
			var p := plane + Vector3(u) * cu + Vector3(v) * cv
			verts.append(p)
			uvs.append(_face_uv(d, p))
			var su := u * (cu * 2 - 1)
			var sv := v * (cv * 2 - 1)
			ao.append(_offset(n + su))
			ao.append(_offset(n + sv))
			ao.append(_offset(n + su + sv))
		corner_pos.append(verts)
		corner_uv.append(uvs)
		ao_off.append(ao)
		ccw.append(1 if Vector3(u).cross(Vector3(v)).dot(Vector3(n)) > 0.0 else 0)
	for l in 16:
		var f := l / 15.0
		block_curve.append(0.04 + 0.96 * f / (3.0 - 2.0 * f))
	for d in SKY_BY_DEPTH.size():
		sky_curve.append(SKY_BY_DEPTH[d])


static func _offset(p: Vector3i) -> int:
	return p.x + p.y * SY + p.z * SZ


## Текстурные координаты точки p (в пределах блока) на грани d, без зеркалирования снаружи.
static func _face_uv(d: int, p: Vector3) -> Vector2:
	match d:
		0:
			return Vector2(1.0 - p.z, 1.0 - p.y)
		1:
			return Vector2(p.z, 1.0 - p.y)
		2, 3:
			return Vector2(p.x, p.z)
		4:
			return Vector2(p.x, 1.0 - p.y)
	return Vector2(1.0 - p.x, 1.0 - p.y)


## input: blocks/metas/lights — по 9 массивов в порядке [dz][dx] (центр — 4), grass/foliage —
## цвета колонок рамки 18×18, top_y — верхний непустой слой центра, vol_top — максимум по соседям.
static func build(input: Dictionary) -> Dictionary:
	var m := ChunkMesher.begin(input)
	m.mesh_layers(H + 2)
	return m.result()


## Меш строится в два этапа: подготовка объёма (prepare, по шагам) и слои (mesh_layers).
## В однопоточной веб-сборке оба этапа растягиваются на несколько кадров.
static func begin(input: Dictionary) -> ChunkMesher:
	var m := ChunkMesher.new()
	m._input = input
	m._vol_top = input["vol_top"]
	m._top_y = input["top_y"]
	return m


## Подготовка: true — готово. deadline_usec = -1 — без ограничения по времени.
func prepare(deadline_usec: int) -> bool:
	while _prep < PREP_STEPS:
		match _prep:
			0:
				_grass = _input.get("grass", PackedColorArray())
				_foliage = _input.get("foliage", PackedColorArray())
				_cx = int(_input.get("cx", 0))
				_cz = int(_input.get("cz", 0))
				if _grass.size() != SY:
					_grass.resize(SY)
					_grass.fill(Color(0.47, 0.75, 0.35))
				if _foliage.size() != SY:
					_foliage.resize(SY)
					_foliage.fill(Color(0.38, 0.62, 0.22))
				_vol = pad_volume(_input["blocks"], _vol_top, Blocks.BEDROCK)
			1:
				_meta = pad_volume(_input["metas"], _vol_top, 0)
			2:
				var lights: Array = _input.get("lights", [])
				if lights.size() == 9:
					_light = pad_volume(lights, _vol_top, 0)
					_spread_border_light()
				else:
					_light.resize(_vol.size())
			3:
				_compute_heightmap(_vol_top)
			4:
				@warning_ignore("integer_division")
				var layers := _vol.size() / SY
				_kinds = _row_kinds(layers)
				_py = 1
				_py_end = mini(_top_y + 2, layers - 1)
				_input = {}
		_prep += 1
		if deadline_usec >= 0 and Time.get_ticks_usec() >= deadline_usec:
			break
	return _prep >= PREP_STEPS


func result() -> Dictionary:
	return {"opaque": _solid.to_arrays(), "translucent": _trans.to_arrays()}


## Объём 18 × 18 × (vol_top + 3): нижний слой — bottom, затем y = 0..vol_top+1.
static func pad_volume(chunks: Array, vol_top: int, bottom_value: int) -> PackedByteArray:
	var vol := PackedByteArray()
	var bottom := PackedByteArray()
	bottom.resize(SY)
	bottom.fill(bottom_value)
	vol.append_array(bottom)
	for y in range(0, vol_top + 2):
		if y >= H:
			var empty := PackedByteArray()
			empty.resize(SY)
			vol.append_array(empty)
			continue
		var yo := y * LAYER
		for pz in PS:
			var row := 1
			var lz := pz - 1
			if lz < 0:
				row = 0
				lz = S - 1
			elif lz >= S:
				row = 2
				lz = 0
			var west: PackedByteArray = chunks[row * 3]
			var mid: PackedByteArray = chunks[row * 3 + 1]
			var east: PackedByteArray = chunks[row * 3 + 2]
			var ri := yo + lz * S
			vol.append(west[ri + S - 1])
			vol.append_array(mid.slice(ri, ri + S))
			vol.append(east[ri])
	return vol


## Свет соседних чанков перетекает внутрь (и свет центра — на один шаг в рамку).
func _spread_border_light() -> void:
	var light := _light
	var vol := _vol
	var opq := Blocks.opaque_flags
	@warning_ignore("integer_division")
	var layers := vol.size() / SY
	var queue := PackedInt32Array()
	for py in range(1, layers):
		var base := py * SY
		# Слой без света от блоков (почти все слои) пропускаем целиком — проверка встроенной функцией.
		if light.slice(base, base + SY).count(0) == SY:
			continue
		for pz in PS:
			var edge_row := pz < 2 or pz >= PS - 2
			for px in PS:
				# Клетки рамки и прилегающие к ней клетки центра.
				if not edge_row and px > 1 and px < PS - 2:
					continue
				var i := base + pz * SZ + px
				if light[i] > 1:
					queue.append(i)
	var head := 0
	var n := vol.size()
	while head < queue.size():
		var i := queue[head]
		head += 1
		var l := light[i] - 1
		if l <= 0:
			continue
		var px := i % PS
		@warning_ignore("integer_division")
		var pz := (i / PS) % PS
		for d in 6:
			var j := i + neighbor_off[d]
			if j < SY or j >= n:
				continue
			if d == 0 and px == PS - 1 or d == 1 and px == 0 or d == 4 and pz == PS - 1 or d == 5 and pz == 0:
				continue
			if light[j] >= l or opq[vol[j]] == 1:
				continue
			light[j] = l
			queue.append(j)


func _compute_heightmap(vol_top: int) -> void:
	var opq := Blocks.opaque_flags
	var top := vol_top + 2
	_hm.resize(SY)
	for col in SY:
		var py := top
		while py > 0 and opq[_vol[col + py * SY]] == 0:
			py -= 1
		_hm[col] = py


## Небесный свет клетки (0..1).
@warning_ignore("integer_division")
func _sky(j: int) -> float:
	var py := j / SY
	var depth := _hm[j - py * SY] - py
	if depth < 0:
		return 1.0
	return sky_curve[mini(depth, sky_curve.size() - 1)]


func _blk(j: int) -> float:
	return block_curve[_light[j]]


## Самые частые непрозрачные блоки толщи: по ним (встроенным подсчётом) узнаём сплошные строки.
const SOLID_COMMON := [Blocks.STONE, Blocks.DIRT, Blocks.GRASS, Blocks.SAND, Blocks.GRAVEL, Blocks.BEDROCK,
	Blocks.SANDSTONE, Blocks.COAL_ORE, Blocks.IRON_ORE, Blocks.NETHERRACK, Blocks.END_STONE, Blocks.CLAY,
	Blocks.SOUL_SAND, Blocks.MYCELIUM, Blocks.SNOW]


## Для каждой строки из 18 блоков: 0 — смешанная, 1 — только воздух, 2 — только непрозрачные.
## Строка, где встречаются редкие непрозрачные блоки, считается смешанной — это только чуть медленнее.
func _row_kinds(layers: int) -> PackedByteArray:
	var kinds := PackedByteArray()
	kinds.resize(layers * PS)
	for py in layers:
		for pz in PS:
			var start := py * SY + pz * SZ
			var row := _vol.slice(start, start + PS)
			var air := row.count(Blocks.AIR)
			if air == PS:
				kinds[py * PS + pz] = 1
				continue
			if air > 0:
				continue
			var solid := 0
			for id: int in SOLID_COMMON:
				solid += row.count(id)
				if solid == PS:
					kinds[py * PS + pz] = 2
					break
	return kinds


## Строит до count слоёв (y) меша. true — меш готов.
func mesh_layers(count: int) -> bool:
	if _prep < PREP_STEPS:
		prepare(-1)
	var vol := _vol
	var opq := Blocks.opaque_flags
	var shp := Blocks.shapes
	var kinds := _kinds
	var end := mini(_py + count, _py_end)
	for py in range(_py, end):
		var wy := py - 1
		for pz in range(1, S + 1):
			var rk := py * PS + pz
			var kind := kinds[rk]
			if kind == 1:
				continue
			# Строка внутри сплошного массива: все соседние строки тоже непрозрачны.
			if kind == 2 and kinds[rk - 1] == 2 and kinds[rk + 1] == 2 and kinds[rk - PS] == 2 and kinds[rk + PS] == 2:
				continue
			var row := py * SY + pz * SZ
			for px in range(1, S + 1):
				var i := row + px
				var b := vol[i]
				if b == Blocks.AIR:
					continue
				var sh := shp[b]
				if sh == Blocks.SH_CUBE and opq[b] == 1:
					_cube(i, px - 1, wy, pz - 1, b)
				else:
					_shaped(i, px - 1, wy, pz - 1, b, sh)
	_py = end
	return _py >= _py_end


# --- Полные кубы -----------------------------------------------------------

func _cube(i: int, x: int, y: int, z: int, b: int) -> void:
	var vol := _vol
	var opq := Blocks.opaque_flags
	var meta := _meta[i]
	var col := i % SY
	for d in 6:
		var nb := vol[i + neighbor_off[d]]
		if opq[nb] == 1:
			continue
		if nb == b and (b == Blocks.GLASS or b == Blocks.ICE):
			continue
		var tile := Blocks.tile_table[(b * 16 + meta) * 6 + d]
		var tint := Color.WHITE
		if b == Blocks.GRASS:
			if d == 2:
				tint = _grass[col]
			elif d != 3:
				var above := vol[i + SY]
				if above == Blocks.SNOW_LAYER or above == Blocks.SNOW:
					tile = Tex.GRASS_SIDE_SNOWED
		elif b == Blocks.LEAVES:
			tint = _leaf_tint(meta, col)
		var surf := _trans if Blocks.passes[b] == Blocks.PASS_TRANSLUCENT else _solid
		_ao_face(surf, i, x, y, z, d, tile, tint)


func _leaf_tint(meta: int, col: int) -> Color:
	match meta & 3:
		1:
			return Color(0.38, 0.6, 0.38)
		2:
			return Color(0.5, 0.65, 0.33)
	return _foliage[col]


## Грань полного куба с AO и сглаженным светом по вершинам.
func _ao_face(surf: Surface, i: int, x: int, y: int, z: int, d: int, tile: int, tint: Color) -> void:
	var vol := _vol
	var aof := Blocks.ao_flags
	var offs: PackedInt32Array = ao_off[d]
	var corners: PackedVector3Array = corner_pos[d]
	var cuv: PackedVector2Array = corner_uv[d]
	var shade: float = FACE_SHADE[d]
	var base := Vector3(x, y, z)
	var n := i + neighbor_off[d]
	var s_out := _sky(n)
	var b_out := _blk(n)
	var start := surf.verts.size()
	var ao4 := [0, 0, 0, 0]
	for k in 4:
		var s1 := i + offs[k * 3]
		var s2 := i + offs[k * 3 + 1]
		var cr := i + offs[k * 3 + 2]
		var o1 := aof[vol[s1]]
		var o2 := aof[vol[s2]]
		var o3 := aof[vol[cr]]
		var ao := 0
		var ssum := s_out
		var bsum := b_out
		var cnt := 1.0
		if o1 == 0 or o2 == 0:
			ao = 3 - o1 - o2 - o3
			if o3 == 0:
				ssum += _sky(cr)
				bsum += _blk(cr)
				cnt += 1.0
		if o1 == 0:
			ssum += _sky(s1)
			bsum += _blk(s1)
			cnt += 1.0
		if o2 == 0:
			ssum += _sky(s2)
			bsum += _blk(s2)
			cnt += 1.0
		var f: float = shade * AO_CURVE[ao]
		surf.verts.append(base + corners[k])
		surf.uvs.append(cuv[k])
		surf.uv2.append(Vector2(tile, f * ssum / cnt))
		surf.colors.append(Color(tint.r, tint.g, tint.b, f * bsum / cnt))
		ao4[k] = ao
	_add_quad_indices(surf, start, ccw[d] == 1, ao4[0] + ao4[2] < ao4[1] + ao4[3])


## Godot считает лицевыми треугольники с обходом по часовой стрелке.
## flip — разрезать квад по диагонали 1–3 (убирает анизотропию AO).
static func _add_quad_indices(surf: Surface, s: int, is_ccw: bool, flip: bool) -> void:
	var idx := surf.indices
	if is_ccw:
		if flip:
			idx.append_array(PackedInt32Array([s + 1, s + 3, s + 2, s + 1, s, s + 3]))
		else:
			idx.append_array(PackedInt32Array([s, s + 2, s + 1, s, s + 3, s + 2]))
	else:
		if flip:
			idx.append_array(PackedInt32Array([s + 1, s + 2, s + 3, s + 1, s + 3, s]))
		else:
			idx.append_array(PackedInt32Array([s, s + 1, s + 2, s, s + 2, s + 3]))


# --- Блоки особых форм -----------------------------------------------------

func _shaped(i: int, x: int, y: int, z: int, b: int, sh: int) -> void:
	var meta := _meta[i]
	var col := i % SY
	var base := Vector3(x, y, z)
	match sh:
		Blocks.SH_LIQUID:
			_liquid(i, base, b, meta)
		Blocks.SH_CUBE:
			# Прозрачные кубы (листва, стекло, лёд, рассадник) — без AO-затемнения от себя.
			_cube(i, x, y, z, b)
		Blocks.SH_CROSS:
			var tint := Color.WHITE
			if b == Blocks.TALLGRASS and meta != 0:
				tint = _grass[col]
			var off := Vector3.ZERO
			if b == Blocks.TALLGRASS or b == Blocks.DANDELION or b == Blocks.ROSE:
				var h := WorldGen.hash3(_cx * 16 + x, y, _cz * 16 + z, 77)
				off = Vector3(((h & 15) - 7.5) / 64.0, 0.0, (((h >> 4) & 15) - 7.5) / 64.0)
			_cross(i, base + off, Blocks.tile_table[(b * 16 + meta) * 6 + 2], tint, 1.0)
		Blocks.SH_CROPS:
			_crops(i, base, Blocks.tile_table[(b * 16 + meta) * 6 + 2])
		Blocks.SH_STEM:
			var age := meta & 7
			var tint := Color(0.4 + age * 0.05, 0.75 - age * 0.04, 0.2) if age < 7 else Color(0.75, 0.6, 0.2)
			_cross(i, base, Tex.STEM_STRAIGHT, tint, (age + 1) * 2.0 / 16.0)
		Blocks.SH_TORCH:
			_torch(i, base, b, meta)
		Blocks.SH_FIRE:
			_fire(i, base)
		Blocks.SH_LADDER:
			_wall_plane(i, base, meta & 3, Tex.LADDER, Color.WHITE, 1.0 / 16.0)
		Blocks.SH_VINE:
			var tint := _foliage[col]
			var any := false
			for d in 4:
				if meta & (1 << d):
					_wall_plane(i, base, d, Tex.VINE, tint, 0.8 / 16.0)
					any = true
			if not any or Blocks.is_opaque(_vol[i + SY]):
				_flat(i, base, 15.2 / 16.0, Tex.VINE, tint, 0, true)
		Blocks.SH_RAIL:
			_rail(i, base, b, meta)
		Blocks.SH_WIRE:
			_wire(i, base, meta)
		Blocks.SH_LILYPAD:
			_flat(i, base, 0.25 / 16.0, Tex.WATERLILY, Color(0.13, 0.5, 0.19), WorldGen.hash3(x, y, z, 3) & 3, true)
		Blocks.SH_PORTAL:
			for box in Blocks.shape_boxes(b, meta):
				_box(i, base, box, b, meta, Color.WHITE, _trans)
		_:
			var tint := Color.WHITE
			if Blocks.is_fence_like(b) or sh == Blocks.SH_PANE:
				var conn := _connections(i, b)
				for box in Blocks.shape_boxes(b, meta, conn):
					_box(i, base, box, b, meta, tint, _solid)
				return
			if sh == Blocks.SH_REPEATER:
				_box(i, base, Blocks.shape_boxes(b, meta)[0], b, meta, tint, _solid, meta & 3)
				return
			if sh == Blocks.SH_BED:
				_box(i, base, Blocks.shape_boxes(b, meta)[0], b, meta, tint, _solid, _bed_rot(meta))
				return
			if sh == Blocks.SH_CAULDRON:
				_cauldron(i, base, meta)
				return
			if sh == Blocks.SH_LEVER:
				_lever(i, base, meta)
				return
			if sh == Blocks.SH_SIGN:
				_sign(i, base, b, meta)
				return
			if sh == Blocks.SH_BREWING:
				_brewing(i, base)
				return
			if sh == Blocks.SH_END_FRAME:
				_box(i, base, Blocks.shape_boxes(b, meta)[0], b, meta, tint, _solid)
				if meta & 4:
					_box(i, base, AABB(Vector3(4, 13, 4) / 16.0, Vector3(8, 3, 8) / 16.0), b, meta, tint, _solid, 0, Tex.END_FRAME_EYE)
				return
			if sh == Blocks.SH_DRAGON_EGG:
				for k in 4:
					var r: float = [3.0, 5.0, 6.0, 4.0][k]
					var y0: float = [0.0, 2.0, 7.0, 13.0][k]
					var y1: float = [2.0, 7.0, 13.0, 16.0][k]
					_box(i, base, AABB(Vector3(8 - r, y0, 8 - r) / 16.0, Vector3(2 * r, y1 - y0, 2 * r) / 16.0), b, meta, tint, _solid)
				return
			if sh == Blocks.SH_END_PORTAL:
				_flat(i, base, 12.0 / 16.0, Tex.END_PORTAL, Color.WHITE, 0, true)
				return
			for box in Blocks.shape_boxes(b, meta):
				_box(i, base, box, b, meta, tint, _solid)


## Параллелепипед: грани на границе клетки отсекаются непрозрачными соседями.
func _box(i: int, base: Vector3, box: AABB, b: int, meta: int, tint: Color, surf: Surface, top_rot := 0, force_tile := -1) -> void:
	var lo := box.position
	var hi := box.end
	var vol := _vol
	var opq := Blocks.opaque_flags
	var own_s := _sky(i)
	var own_b := _blk(i)
	for d in 6:
		var on_edge := false
		match d:
			0:
				on_edge = hi.x >= 0.999
			1:
				on_edge = lo.x <= 0.001
			2:
				on_edge = hi.y >= 0.999
			3:
				on_edge = lo.y <= 0.001
			4:
				on_edge = hi.z >= 0.999
			5:
				on_edge = lo.z <= 0.001
		var s := own_s
		var bl := own_b
		if on_edge:
			var n := i + neighbor_off[d]
			var nb := vol[n]
			if opq[nb] == 1:
				continue
			if nb == b and Blocks.passes[b] == Blocks.PASS_TRANSLUCENT:
				continue
			s = _sky(n)
			bl = _blk(n)
		var tile := force_tile if force_tile >= 0 else Blocks.tile_table[(b * 16 + meta) * 6 + d]
		var f: float = FACE_SHADE[d]
		var p := _box_face(lo, hi, d)
		var uv := []
		for k in 4:
			uv.append(_rot_uv(_face_uv(d, p[k]), top_rot if d == 2 else 0))
		for k in 4:
			p[k] = base + p[k]
		surf.quad(p, uv, tile, s * f, bl * f, tint)


## Углы грани d параллелепипеда [lo, hi] против часовой стрелки при взгляде снаружи.
static func _box_face(lo: Vector3, hi: Vector3, d: int) -> Array:
	match d:
		0:
			return [Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z)]
		1:
			return [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]
		2:
			return [Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)]
		3:
			return [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]
		4:
			return [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	return [Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z)]


## Поворот текстуры на rot четвертей оборота вокруг центра тайла.
static func _rot_uv(uv: Vector2, rot: int) -> Vector2:
	match rot & 3:
		1:
			return Vector2(1.0 - uv.y, uv.x)
		2:
			return Vector2(1.0 - uv.x, 1.0 - uv.y)
		3:
			return Vector2(uv.y, 1.0 - uv.x)
	return uv


func _bed_rot(meta: int) -> int:
	# Изголовье в текстуре — сверху (v = 0): поворачиваем так, чтобы оно смотрело по направлению кровати.
	return [2, 3, 0, 1][meta & 3]


## Две диагональные плоскости (трава, цветы, саженцы). height — доля высоты блока.
func _cross(i: int, base: Vector3, tile: int, tint: Color, height: float) -> void:
	var s := _sky(i)
	var bl := _blk(i)
	var a := 0.15
	var b := 0.85
	var h := height
	var v0 := 1.0 - h
	var planes := [
		[Vector3(a, 0, a), Vector3(b, 0, b)],
		[Vector3(a, 0, b), Vector3(b, 0, a)],
	]
	for pl: Array in planes:
		var p0: Vector3 = pl[0]
		var p1: Vector3 = pl[1]
		var pts := [base + p0, base + p1, base + p1 + Vector3(0, h, 0), base + p0 + Vector3(0, h, 0)]
		_solid.quad(pts, [Vector2(0, 1), Vector2(1, 1), Vector2(1, v0), Vector2(0, v0)], tile, s * 0.9, bl * 0.9, tint, true)


## Посевы: четыре вертикальные плоскости «решёткой».
func _crops(i: int, base: Vector3, tile: int) -> void:
	var s := _sky(i) * 0.9
	var bl := _blk(i) * 0.9
	var top := 15.0 / 16.0
	for k in 2:
		var o := 4.0 / 16.0 if k == 0 else 12.0 / 16.0
		var px := [base + Vector3(o, -1.0 / 16.0, 0), base + Vector3(o, -1.0 / 16.0, 1), base + Vector3(o, top, 1), base + Vector3(o, top, 0)]
		_solid.quad(px, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], tile, s, bl, Color.WHITE, true)
		var pz := [base + Vector3(0, -1.0 / 16.0, o), base + Vector3(1, -1.0 / 16.0, o), base + Vector3(1, top, o), base + Vector3(0, top, o)]
		_solid.quad(pz, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], tile, s, bl, Color.WHITE, true)


## Факел: четыре плоскости вокруг «стержня» 2×2 пикселя; настенный — у стены и наклонён от неё.
func _torch(i: int, base: Vector3, b: int, meta: int) -> void:
	var tile := Blocks.tile_table[(b * 16 + meta) * 6 + 2]
	var s := _sky(i)
	var bl := maxf(_blk(i), 0.8)
	var att := meta & 7
	var bottom := Vector3(0.5, 0.0, 0.5)
	var up := Vector3(0, 1, 0)
	if att >= 1 and att <= 4:
		var wall := Vector3(Blocks.attach_offset(att))
		bottom += wall * 0.36 + Vector3(0, 0.2, 0)
		up -= wall * 0.36
	var w := 1.0 / 16.0
	var c := base + bottom
	for k in 4:
		var n: Vector3 = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][k]
		var t := Vector3(-n.z, 0, n.x) * 0.5
		var p0 := c + n * w + t
		var p1 := c + n * w - t
		var pts := [p0, p1, p1 + up, p0 + up]
		_solid.quad(pts, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], tile, s, bl, Color.WHITE, true)
	# Верхушка: квадратик 2×2 пикселя из середины тайла.
	var top_c := c + up * (10.0 / 16.0)
	var q := [top_c + Vector3(-w, 0, w), top_c + Vector3(w, 0, w), top_c + Vector3(w, 0, -w), top_c + Vector3(-w, 0, -w)]
	_solid.quad(q, [Vector2(7, 8) / 16.0, Vector2(9, 8) / 16.0, Vector2(9, 6) / 16.0, Vector2(7, 6) / 16.0], tile, s, bl, Color.WHITE)


func _fire(i: int, base: Vector3) -> void:
	_cross(i, base, Tex.FIRE, Color.WHITE, 1.0)
	var s := _sky(i)
	for d in 4:
		var n: Vector3i = Blocks.DIR_VEC[d]
		var o := Vector3(0.5, 0, 0.5) + Vector3(n) * 0.45
		var t := Vector3(-n.z, 0, n.x) * 0.5
		var pts := [base + o - t, base + o + t, base + o + t + Vector3(0, 1.1, 0), base + o - t + Vector3(0, 1.1, 0)]
		_solid.quad(pts, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Tex.FIRE, s, 1.0, Color.WHITE, true)


## Плоскость у стены (лестница, лианы): d — направление, куда смотрит блок; стена — сзади.
func _wall_plane(i: int, base: Vector3, d: int, tile: int, tint: Color, inset: float) -> void:
	var s := _sky(i) * 0.85
	var bl := _blk(i) * 0.85
	var n: Vector3i = Blocks.DIR_VEC[d]
	# Стена со стороны, противоположной направлению.
	var o := Vector3(0.5, 0, 0.5) - Vector3(n) * (0.5 - inset)
	var t := Vector3(n.z, 0, -n.x) * 0.5
	var pts := [base + o - t, base + o + t, base + o + t + Vector3(0, 1, 0), base + o - t + Vector3(0, 1, 0)]
	_solid.quad(pts, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], tile, s, bl, tint, true)


## Горизонтальная плоскость на высоте h (рельсы, провода, кувшинка).
func _flat(i: int, base: Vector3, h: float, tile: int, tint: Color, rot: int, two_sided := false) -> void:
	var s := _sky(i)
	var bl := _blk(i)
	var pts := [base + Vector3(0, h, 1), base + Vector3(1, h, 1), base + Vector3(1, h, 0), base + Vector3(0, h, 0)]
	var uv := [_rot_uv(Vector2(0, 1), rot), _rot_uv(Vector2(1, 1), rot), _rot_uv(Vector2(1, 0), rot), _rot_uv(Vector2(0, 0), rot)]
	_solid.quad(pts, uv, tile, s, bl, tint, two_sided)


func _rail(i: int, base: Vector3, b: int, meta: int) -> void:
	var shape := meta & 7 if b != Blocks.RAIL else meta & 15
	var tile := Blocks.tile_table[(b * 16 + meta) * 6 + 2]
	var s := _sky(i)
	var bl := _blk(i)
	var h := 1.0 / 16.0
	if shape >= 2 and shape <= 5:
		# Наклонные рельсы: 2 — вверх на восток, 3 — на запад, 4 — на север, 5 — на юг.
		var pts: Array
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		match shape:
			2:
				pts = [Vector3(0, h, 1), Vector3(1, 1 + h, 1), Vector3(1, 1 + h, 0), Vector3(0, h, 0)]
				uv = [Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)]
			3:
				pts = [Vector3(0, 1 + h, 1), Vector3(1, h, 1), Vector3(1, h, 0), Vector3(0, 1 + h, 0)]
				uv = [Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)]
			4:
				pts = [Vector3(0, h, 1), Vector3(1, h, 1), Vector3(1, 1 + h, 0), Vector3(0, 1 + h, 0)]
			_:
				pts = [Vector3(0, 1 + h, 1), Vector3(1, 1 + h, 1), Vector3(1, h, 0), Vector3(0, h, 0)]
		for k in 4:
			pts[k] = base + pts[k]
		_solid.quad(pts, uv, tile, s, bl, Color.WHITE, true)
		return
	var rot := 0
	match shape:
		1:
			rot = 1
		6:
			rot = 0
		7:
			rot = 1
		8:
			rot = 2
		9:
			rot = 3
	_flat(i, base, h, tile, Color.WHITE, rot, true)


## Красная пыль: крест/линия в зависимости от соединений, оттенок — по заряду.
func _wire(i: int, base: Vector3, meta: int) -> void:
	var p := meta & 15
	var tint := Color(0.3 + 0.7 * p / 15.0, 0.0 + 0.2 * p / 15.0 * (1.0 if p > 12 else 0.0), 0.0)
	if p == 0:
		tint = Color(0.3, 0.0, 0.0)
	var conn := 0
	var up_conn := 0
	for d in 4:
		var n: Vector3i = Blocks.DIR_VEC[d]
		var j := i + _offset(n)
		var nb := _vol[j]
		if _wire_connects(nb, _meta[j], d):
			conn |= 1 << d
		elif not Blocks.is_opaque(nb) and _vol[j - SY] == Blocks.REDSTONE_WIRE:
			conn |= 1 << d
		elif Blocks.is_opaque(nb) and not Blocks.is_opaque(_vol[i + SY]) and _vol[j + SY] == Blocks.REDSTONE_WIRE:
			conn |= 1 << d
			up_conn |= 1 << d
	var h := 0.25 / 16.0
	var ns := conn & 5
	var ew := conn & 10
	if conn != 0 and ((ns != 0 and ew == 0) or (ew != 0 and ns == 0)):
		_flat(i, base, h, Tex.REDSTONE_DUST_LINE, tint, 0 if ns != 0 else 1)
	else:
		_flat(i, base, h, Tex.REDSTONE_DUST_CROSS, tint, 0)
	for d in 4:
		if up_conn & (1 << d):
			var n: Vector3i = Blocks.DIR_VEC[d]
			# Провод «поднимается» по стене соседнего блока.
			var o := Vector3(0.5, 0, 0.5) + Vector3(n) * (0.5 - 0.25 / 16.0)
			var t := Vector3(-n.z, 0, n.x) * 0.5
			var pts := [base + o - t, base + o + t, base + o + t + Vector3(0, 1, 0), base + o - t + Vector3(0, 1, 0)]
			_solid.quad(pts, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Tex.REDSTONE_DUST_LINE, _sky(i), _blk(i), tint, true)


static func _wire_connects(nb: int, nmeta: int, d: int) -> bool:
	match nb:
		Blocks.REDSTONE_WIRE, Blocks.REDSTONE_TORCH, Blocks.REDSTONE_TORCH_OFF, Blocks.LEVER, Blocks.STONE_BUTTON, \
				Blocks.STONE_PLATE, Blocks.WOODEN_PLATE, Blocks.DETECTOR_RAIL:
			return true
		Blocks.REPEATER_OFF, Blocks.REPEATER_ON:
			return (nmeta & 1) == (d & 1)
	return false


func _connections(i: int, b: int) -> int:
	var conn := 0
	for d in 4:
		var n: Vector3i = Blocks.DIR_VEC[d]
		if Blocks.connects_to(b, _vol[i + _offset(n)]):
			conn |= 1 << d
	return conn


func _cauldron(i: int, base: Vector3, meta: int) -> void:
	var b := Blocks.CAULDRON
	var t := 2.0 / 16.0
	var boxes := [AABB(Vector3(0, 3.0 / 16.0, 0), Vector3(1, 1.0 / 16.0, 1)),
		AABB(Vector3(0, 0.25, 0), Vector3(t, 0.75, 1)), AABB(Vector3(1 - t, 0.25, 0), Vector3(t, 0.75, 1)),
		AABB(Vector3(t, 0.25, 0), Vector3(1 - 2 * t, 0.75, t)), AABB(Vector3(t, 0.25, 1 - t), Vector3(1 - 2 * t, 0.75, t)),
		AABB(Vector3(0, 0, 0), Vector3(4, 3, 4) / 16.0), AABB(Vector3(12, 0, 0) / 16.0, Vector3(4, 3, 4) / 16.0),
		AABB(Vector3(0, 0, 12) / 16.0, Vector3(4, 3, 4) / 16.0), AABB(Vector3(12, 0, 12) / 16.0, Vector3(4, 3, 4) / 16.0)]
	for box: AABB in boxes:
		_box(i, base, box, b, 0, Color.WHITE, _solid)
	if meta > 0:
		var h := (6.0 + 3.0 * mini(meta, 3)) / 16.0
		var pts := [base + Vector3(t, h, 1 - t), base + Vector3(1 - t, h, 1 - t), base + Vector3(1 - t, h, t), base + Vector3(t, h, t)]
		_trans.quad(pts, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Tex.WATER, _sky(i), _blk(i), Color.WHITE)


func _lever(i: int, base: Vector3, meta: int) -> void:
	var att := meta & 7
	var on := meta & 8 != 0
	var plate := Blocks.shape_boxes(Blocks.LEVER, meta)[0]
	# Основание из булыжника, ручка — тонкая палочка.
	var lo := plate.position
	var hi := plate.end
	var thin := plate
	match att:
		0:
			thin = AABB(Vector3(lo.x, 0, lo.z + 0.12), Vector3(hi.x - lo.x, 3.0 / 16.0, hi.z - lo.z - 0.24))
		1:
			thin = AABB(Vector3(0, lo.y, lo.z), Vector3(3.0 / 16.0, hi.y - lo.y, hi.z - lo.z))
		2:
			thin = AABB(Vector3(13.0 / 16.0, lo.y, lo.z), Vector3(3.0 / 16.0, hi.y - lo.y, hi.z - lo.z))
		3:
			thin = AABB(Vector3(lo.x, lo.y, 0), Vector3(hi.x - lo.x, hi.y - lo.y, 3.0 / 16.0))
		4:
			thin = AABB(Vector3(lo.x, lo.y, 13.0 / 16.0), Vector3(hi.x - lo.x, hi.y - lo.y, 3.0 / 16.0))
	_box(i, base, thin, Blocks.COBBLESTONE, 0, Color.WHITE, _solid)
	var c := thin.get_center()
	var dir := Vector3(0, 1, 0)
	var tilt := 0.35 if on else -0.35
	match att:
		0:
			dir = Vector3(0, 1, tilt)
		1:
			dir = Vector3(1, tilt, 0)
		2:
			dir = Vector3(-1, tilt, 0)
		3:
			dir = Vector3(0, tilt, 1)
		4:
			dir = Vector3(0, tilt, -1)
	dir = dir.normalized() * (9.0 / 16.0)
	var w := 1.0 / 16.0
	var stick := AABB(c - Vector3(w, w, w), Vector3(2 * w, 2 * w, 2 * w)).expand(c + dir)
	_box(i, base, stick, Blocks.LEVER, 0, Color.WHITE, _solid, 0, Tex.LOG_OAK)


func _sign(i: int, base: Vector3, b: int, meta: int) -> void:
	if b == Blocks.WALL_SIGN:
		var d := meta & 3
		var n: Vector3i = Blocks.DIR_VEC[d]
		var lo := Vector3(0, 4.5 / 16.0, 0)
		var hi := Vector3(1, 12.5 / 16.0, 1)
		match d:
			0:
				hi.z = 2.0 / 16.0
			1:
				lo.x = 14.0 / 16.0
			2:
				lo.z = 14.0 / 16.0
			3:
				hi.x = 2.0 / 16.0
		_box(i, base, AABB(lo, hi - lo), b, meta, Color.WHITE, _solid)
		return
	# Табличка на столбике: доска и палка (поворот в meta 0–15 приближаем к четырём сторонам).
	@warning_ignore("integer_division")
	var axis_x := ((meta + 2) / 4) % 2 == 1
	if axis_x:
		_box(i, base, AABB(Vector3(7, 8, 0) / 16.0, Vector3(2, 8, 16) / 16.0), b, meta, Color.WHITE, _solid)
	else:
		_box(i, base, AABB(Vector3(0, 8, 7) / 16.0, Vector3(16, 8, 2) / 16.0), b, meta, Color.WHITE, _solid)
	_box(i, base, AABB(Vector3(7.5, 0, 7.5) / 16.0, Vector3(1, 8, 1) / 16.0), b, meta, Color.WHITE, _solid, 0, Tex.LOG_OAK)


func _brewing(i: int, base: Vector3) -> void:
	_box(i, base, AABB(Vector3(7, 0, 7) / 16.0, Vector3(2, 14, 2) / 16.0), Blocks.BREWING_STAND, 0, Color.WHITE, _solid, 0, Tex.BLAZE_ROD)
	for c: Vector3 in [Vector3(2, 0, 6), Vector3(9, 0, 2), Vector3(9, 0, 10)]:
		_box(i, base, AABB(c / 16.0, Vector3(6, 2, 6) / 16.0), Blocks.BREWING_STAND, 0, Color.WHITE, _solid, 0, Tex.BREWING_STAND_BASE)
	_cross(i, base, Tex.BREWING_STAND, Color.WHITE, 1.0)


# --- Жидкости --------------------------------------------------------------

## Высота поверхности жидкости в клетке j (или -1, если там другая жидкость/блок).
func _liquid_height(j: int, water: bool) -> float:
	var b := _vol[j]
	if water and not Blocks.is_water(b) or not water and not Blocks.is_lava(b):
		return -1.0
	var above := _vol[j + SY]
	if water and Blocks.is_water(above) or not water and Blocks.is_lava(above):
		return 1.0
	var m := _meta[j]
	if m >= 8:
		return 8.0 / 9.0
	return (8.0 - m) / 9.0 if m > 0 else 8.0 / 9.0


func _liquid(i: int, base: Vector3, b: int, meta: int) -> void:
	var water := Blocks.is_water(b)
	var vol := _vol
	var opq := Blocks.opaque_flags
	var surf := _trans if water else _solid
	var tile := Tex.WATER if water else Tex.LAVA
	var own_b := 1.0 if not water else -1.0
	# Высоты четырёх углов верхней грани: среднее по четырём клеткам вокруг угла.
	var hs := PackedFloat32Array([0, 0, 0, 0])
	var corners := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0)]
	var full := _liquid_height(i, water) >= 1.0
	for k in 4:
		if full:
			hs[k] = 1.0
			continue
		# Как в оригинале: источник (и падающая жидкость) весит 11, текущая — 1, воздух — 1 с высотой 0.
		var c: Vector2i = corners[k]
		var sum := 0.0
		var cnt := 0
		var top := false
		for dz in [c.y - 1, c.y]:
			for dx in [c.x - 1, c.x]:
				var j: int = i + dx + dz * SZ
				var h := _liquid_height(j, water)
				if h >= 1.0:
					top = true
				if h >= 0.0:
					var m := _meta[j]
					var w := 11 if m == 0 or m >= 8 else 1
					sum += h * w
					cnt += w
				elif not Blocks.is_solid(vol[j]):
					cnt += 1
		hs[k] = 1.0 if top else (sum / maxi(cnt, 1))
	var above := vol[i + SY]
	var same_above := (water and Blocks.is_water(above)) or (not water and Blocks.is_lava(above))
	for d in 6:
		var n := i + neighbor_off[d]
		var nb := vol[n]
		if water and Blocks.is_water(nb) or not water and Blocks.is_lava(nb):
			continue
		if d == 2 and same_above:
			continue
		if opq[nb] == 1 and d != 2:
			continue
		var s := _sky(n) if opq[nb] == 0 else _sky(i)
		var bl := _blk(n) if opq[nb] == 0 else _blk(i)
		if own_b > 0.0:
			bl = 1.0
		var f: float = FACE_SHADE[d]
		var p := _box_face(Vector3.ZERO, Vector3.ONE, d)
		var uv := []
		for k in 4:
			var q: Vector3 = p[k]
			if q.y > 0.5:
				var kk := _corner_index(q)
				q.y = hs[kk]
			p[k] = base + q
			uv.append(_face_uv(d, q))
		surf.quad(p, uv, tile, s * f, bl * f, Color.WHITE)
		if d == 2 and water:
			# Поверхность видна и снизу (из-под воды).
			surf.quad([p[1], p[0], p[3], p[2]], [uv[1], uv[0], uv[3], uv[2]], tile, s * f, bl * f, Color.WHITE)


static func _corner_index(q: Vector3) -> int:
	if q.x < 0.5:
		return 0 if q.z > 0.5 else 3
	return 1 if q.z > 0.5 else 2


# --- Отдельные блоки (предметы в руке и на земле) --------------------------

## Меш одного блока с центром в начале координат, при полном освещении.
static func block_arrays(id: int, meta: int) -> Array:
	var blocks := []
	var metas := []
	for k in 9:
		var d := PackedByteArray()
		d.resize(WorldGen.VOLUME)
		blocks.append(d)
		var m := PackedByteArray()
		m.resize(WorldGen.VOLUME)
		metas.append(m)
	var idx := Chunk.index_of(8, 1, 8)
	(blocks[4] as PackedByteArray)[idx] = id
	(metas[4] as PackedByteArray)[idx] = meta
	var res := build({"blocks": blocks, "metas": metas, "top_y": 1, "vol_top": 1})
	var arr: Array = res["opaque"]
	if arr.is_empty():
		arr = res["translucent"]
	if arr.is_empty():
		return []
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for k in verts.size():
		verts[k] -= Vector3(8.5, 1.5, 8.5)
	arr[Mesh.ARRAY_VERTEX] = verts
	return arr
