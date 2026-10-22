class_name ChunkMesher
extends RefCounted
## Строит меш чанка: отсечение невидимых граней, ambient occlusion по вершинам
## и упрощённый «небесный» свет по карте высот. Работает в рабочих потоках.

const S := WorldGen.CHUNK_SIZE
const H := WorldGen.CHUNK_HEIGHT
const LAYER := S * S
## Объём с рамкой в 1 блок из соседних чанков.
const PS := S + 2
const SZ := PS
const SY := PS * PS
const WATER_TOP := 0.875

## Яркость граней по направлению: +X, -X, +Y, -Y, +Z, -Z.
const FACE_SHADE := [0.62, 0.62, 1.0, 0.5, 0.8, 0.8]
const AO_CURVE := [0.42, 0.62, 0.8, 1.0]
## Освещённость в зависимости от глубины под ближайшим непрозрачным блоком сверху.
const LIGHT_BY_DEPTH := [1.0, 0.8, 0.7, 0.6, 0.5, 0.42, 0.35, 0.3, 0.26, 0.23, 0.2]

const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const AXIS_U := [Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 0)]
const AXIS_V := [Vector3i(0, 1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(0, 1, 0)]

static var neighbor_off := PackedInt32Array()
static var corner_pos: Array[PackedVector3Array] = []
static var corner_uv: Array[PackedVector2Array] = []
static var ao_off: Array[PackedInt32Array] = []
## 1, если обход вершин 0→1→2 идёт против часовой стрелки при взгляде снаружи.
static var ccw := PackedByteArray()


class Surface:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var layers := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func to_arrays() -> Array:
		if verts.is_empty():
			return []
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = layers
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_INDEX] = indices
		return arr


var _vol := PackedByteArray()
var _hm := PackedInt32Array()
var _solid := Surface.new()
var _water := Surface.new()


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
			verts.append(plane + Vector3(u) * cu + Vector3(v) * cv)
			if d == 2 or d == 3:
				uvs.append(Vector2(cu, cv))
			else:
				uvs.append(Vector2(cu, 1 - cv))
			var su := u * (cu * 2 - 1)
			var sv := v * (cv * 2 - 1)
			ao.append(_offset(n + su))
			ao.append(_offset(n + sv))
			ao.append(_offset(n + su + sv))
		corner_pos.append(verts)
		corner_uv.append(uvs)
		ao_off.append(ao)
		ccw.append(1 if Vector3(u).cross(Vector3(v)).dot(Vector3(n)) > 0.0 else 0)


static func _offset(p: Vector3i) -> int:
	return p.x + p.y * SY + p.z * SZ


## chunks — 9 массивов блоков в порядке [dz][dx] (dz, dx ∈ -1..1), центральный — индекс 4.
## top_y — верхний непустой слой центрального чанка, vol_top — максимум по соседям.
static func build(chunks: Array, top_y: int, vol_top: int) -> Dictionary:
	var m := ChunkMesher.new()
	m._vol = pad_volume(chunks, vol_top)
	m._compute_heightmap(vol_top)
	m._mesh(top_y)
	return {"opaque": m._solid.to_arrays(), "water": m._water.to_arrays()}


## Собирает объём (18 × 18 × (vol_top + 3)): нижний слой — коренная порода, затем y = 0..vol_top+1.
static func pad_volume(chunks: Array, vol_top: int) -> PackedByteArray:
	var vol := PackedByteArray()
	var bottom := PackedByteArray()
	bottom.resize(SY)
	bottom.fill(Blocks.BEDROCK)
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


func _compute_heightmap(vol_top: int) -> void:
	var opq := Blocks.opaque_flags
	var top := vol_top + 2
	_hm.resize(SY)
	for col in SY:
		var py := top
		while py > 0 and opq[_vol[col + py * SY]] == 0:
			py -= 1
		_hm[col] = py


@warning_ignore("integer_division")
func _light(j: int) -> float:
	var py := j / SY
	var depth := _hm[j - py * SY] - py
	if depth < 0:
		return 1.0
	return LIGHT_BY_DEPTH[mini(depth, LIGHT_BY_DEPTH.size() - 1)]


## Для каждой строки из 18 блоков: 0 — смешанная, 1 — только воздух, 2 — только непрозрачные.
func _row_kinds(layers: int) -> PackedByteArray:
	var kinds := PackedByteArray()
	kinds.resize(layers * PS)
	var transparent := Blocks.non_opaque_ids
	for py in layers:
		for pz in PS:
			var start := py * SY + pz * SZ
			var row := _vol.slice(start, start + PS)
			var air := row.count(Blocks.AIR)
			if air == PS:
				kinds[py * PS + pz] = 1
				continue
			var see_through := air
			for id in transparent:
				if id != Blocks.AIR:
					see_through += row.count(id)
			if see_through == 0:
				kinds[py * PS + pz] = 2
	return kinds


@warning_ignore("integer_division")
func _mesh(top_y: int) -> void:
	var vol := _vol
	var opq := Blocks.opaque_flags
	var rnd := Blocks.render_types
	var ftex := Blocks.face_tex
	var noff := neighbor_off
	var layers := _vol.size() / SY
	var kinds := _row_kinds(layers)
	for py in range(1, mini(top_y + 2, layers - 1)):
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
				var r := rnd[b]
				if r == Blocks.RENDER_WATER:
					_water_block(i, px - 1, wy, pz - 1)
					continue
				for d in 6:
					var nb := vol[i + noff[d]]
					if opq[nb] == 1:
						continue
					if nb == b and b == Blocks.GLASS:
						continue
					_add_face(i, px - 1, wy, pz - 1, d, ftex[b * 6 + d])


func _add_face(i: int, x: int, y: int, z: int, d: int, layer: int) -> void:
	var vol := _vol
	var aof := Blocks.ao_flags
	var offs: PackedInt32Array = ao_off[d]
	var corners: PackedVector3Array = corner_pos[d]
	var cuv: PackedVector2Array = corner_uv[d]
	var shade: float = FACE_SHADE[d]
	var base := Vector3(x, y, z)
	var l_out := _light(i + neighbor_off[d])
	var layer_v := Vector2(layer, 0)
	var surf := _solid
	var start := surf.verts.size()
	var ao0 := 0
	var ao1 := 0
	var ao2 := 0
	var ao3 := 0
	for k in 4:
		var s1 := i + offs[k * 3]
		var s2 := i + offs[k * 3 + 1]
		var cr := i + offs[k * 3 + 2]
		var o1 := aof[vol[s1]]
		var o2 := aof[vol[s2]]
		var o3 := aof[vol[cr]]
		var ao := 0
		var lsum := l_out
		var lcnt := 1.0
		if o1 == 0 or o2 == 0:
			ao = 3 - o1 - o2 - o3
			if o3 == 0:
				lsum += _light(cr)
				lcnt += 1.0
		if o1 == 0:
			lsum += _light(s1)
			lcnt += 1.0
		if o2 == 0:
			lsum += _light(s2)
			lcnt += 1.0
		var br: float = shade * AO_CURVE[ao] * (lsum / lcnt)
		surf.verts.append(base + corners[k])
		surf.uvs.append(cuv[k])
		surf.layers.append(layer_v)
		surf.colors.append(Color(br, br, br))
		if k == 0:
			ao0 = ao
		elif k == 1:
			ao1 = ao
		elif k == 2:
			ao2 = ao
		else:
			ao3 = ao
	_add_quad_indices(surf, start, ccw[d] == 1, ao0 + ao2 < ao1 + ao3)


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


func _water_block(i: int, x: int, y: int, z: int) -> void:
	var vol := _vol
	var opq := Blocks.opaque_flags
	var top_h := 1.0 if vol[i + SY] == Blocks.WATER else WATER_TOP
	var base := Vector3(x, y, z)
	var layer_v := Vector2(Blocks.T_WATER, 0)
	var surf := _water
	for d in 6:
		var nb := vol[i + neighbor_off[d]]
		if nb == Blocks.WATER or opq[nb] == 1:
			continue
		var corners: PackedVector3Array = corner_pos[d]
		var cuv: PackedVector2Array = corner_uv[d]
		var br: float = FACE_SHADE[d] * _light(i + neighbor_off[d])
		var col := Color(br, br, br)
		var start := surf.verts.size()
		for k in 4:
			var p := corners[k]
			if p.y > 0.5:
				p.y = top_h
			surf.verts.append(base + p)
			surf.uvs.append(cuv[k])
			surf.layers.append(layer_v)
			surf.colors.append(col)
		_add_quad_indices(surf, start, ccw[d] == 1, false)


## Куб 1×1×1 с центром в начале координат — для выпавших предметов и блока в руке.
static func cube_arrays(block_id: int) -> Array:
	var surf := Surface.new()
	for d in 6:
		var corners: PackedVector3Array = corner_pos[d]
		var cuv: PackedVector2Array = corner_uv[d]
		var br: float = FACE_SHADE[d]
		var start := surf.verts.size()
		for k in 4:
			surf.verts.append(corners[k] - Vector3(0.5, 0.5, 0.5))
			surf.uvs.append(cuv[k])
			surf.layers.append(Vector2(Blocks.texture_of(block_id, d), 0))
			surf.colors.append(Color(br, br, br))
		_add_quad_indices(surf, start, ccw[d] == 1, false)
	return surf.to_arrays()
