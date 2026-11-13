class_name EndGen
extends RefCounted
## Край 1.2 (как ChunkProviderEnd): парящий остров из камня Края вокруг (0, 0) — плотность шума,
## убывающая к краям острова и вниз, вокруг — пустота. На острове — обсидиановые столбы
## (WorldGenSpikes) с бедроком и кристаллом Края на вершине. Интерфейс как у WorldGen.

const LEVELS := 17
const ISLAND_RADIUS := 82.0
const TOP := 62.0
const PILLARS := 10

var seed_value := 0
var _noise := FastNoiseLite.new()
var buf: GenChunk
var _cols: Array[PackedFloat32Array] = []
var _pillars: Array = []


func _init(p_seed: int) -> void:
	seed_value = p_seed
	_noise.seed = p_seed + 201
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0 / 38.0
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_pillars = _layout_pillars()


## Столбы: [x, z, радиус, верх] — детерминированно по зерну мира.
func _layout_pillars() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	var out := []
	var tries := 0
	while out.size() < PILLARS and tries < 400:
		tries += 1
		var a := rng.randf() * TAU
		var d := rng.randf_range(18.0, 62.0)
		var x := int(cos(a) * d)
		var z := int(sin(a) * d)
		var r := rng.randi_range(1, 4)
		var clear := true
		for p: Array in out:
			if Vector2(x - int(p[0]), z - int(p[1])).length() < r + int(p[2]) + 6:
				clear = false
				break
		if not clear:
			continue
		out.append([x, z, r, int(TOP) + rng.randi_range(14, 40)])
	return out


func pillars() -> Array:
	return _pillars


func grid_column(gx: int, gz: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(LEVELS)
	var wx := float(gx * 4)
	var wz := float(gz * 4)
	var dist := sqrt(wx * wx + wz * wz)
	var edge := (ISLAND_RADIUS - dist) * 0.6
	for k in LEVELS:
		var y := float(k * 8)
		var d := _noise.get_noise_3d(wx, y * 1.4, wz) * 14.0 + minf(edge, 24.0)
		# Сверху остров ровный, снизу сужается в «перевёрнутый конус».
		if y > TOP - 6.0:
			d -= (y - (TOP - 6.0)) * 2.4
		else:
			d -= (TOP - 6.0 - y) * 0.55
		out[k] = d
	return out


func _column(wx: int, wz: int) -> PackedFloat32Array:
	var gx := wx >> 2
	var gz := wz >> 2
	var a := grid_column(gx, gz)
	var b := grid_column(gx + 1, gz)
	var c := grid_column(gx, gz + 1)
	var e := grid_column(gx + 1, gz + 1)
	var fx := (wx & 3) * 0.25
	var fz := (wz & 3) * 0.25
	var out := PackedFloat32Array()
	out.resize(LEVELS)
	for k in LEVELS:
		var p := a[k] + (b[k] - a[k]) * fx
		var q := c[k] + (e[k] - c[k]) * fx
		out[k] = p + (q - p) * fz
	return out


func get_height(wx: int, wz: int) -> int:
	var d := _column(wx, wz)
	for y in range(127, 0, -1):
		var k := y >> 3
		if k < LEVELS - 1 and d[k] + (d[k + 1] - d[k]) * ((y & 7) * 0.125) > 0.0:
			return y
	return 0


func biome_at(_wx: int, _wz: int) -> int:
	return Biomes.SKY


func find_spawn_column() -> Vector2i:
	return Vector2i(Portals.END_SPAWN.x, Portals.END_SPAWN.z)


func generate_chunk(cx: int, cz: int) -> Dictionary:
	begin_chunk(cx, cz)
	fill_rows(0, 16)
	return finish_chunk()


func begin_chunk(cx: int, cz: int) -> void:
	buf = GenChunk.new()
	buf.setup(cx, cz)
	_cols = []
	_cols.resize(25)


func fill_rows(z0: int, z1: int) -> void:
	for s in range(z0, z1):
		if s < 4:
			_terrain_rows(s * 4, s * 4 + 4)
		elif s == 4:
			_pillars_here()


func finish_chunk() -> Dictionary:
	var biomes := PackedByteArray()
	biomes.resize(256)
	biomes.fill(Biomes.SKY)
	var out := {"blocks": buf.blocks, "meta": buf.meta, "biomes": biomes, "block_entities": buf.block_entities,
		"entities": buf.entities}
	buf = null
	_cols = []
	return out


func _terrain_rows(z0: int, z1: int) -> void:
	# Далеко от острова — пустота, считать нечего.
	var near := Vector2(buf.ox + 8, buf.oz + 8).length() < ISLAND_RADIUS + 48.0
	if not near:
		return
	var data := buf.blocks
	var gx0 := buf.cx * 4
	var gz0 := buf.cz * 4
	var dens := PackedFloat32Array()
	dens.resize(LEVELS)
	for z in range(z0, z1):
		var gj := z >> 2
		for gi in 5:
			for dj in 2:
				var ci := gi + (gj + dj) * 5
				if _cols[ci].is_empty():
					_cols[ci] = grid_column(gx0 + gi, gz0 + gj + dj)
		var fz := (z & 3) * 0.25
		for x in 16:
			var gi := x >> 2
			var fx := (x & 3) * 0.25
			var a := _cols[gi + gj * 5]
			var b := _cols[gi + 1 + gj * 5]
			var c := _cols[gi + (gj + 1) * 5]
			var e := _cols[gi + 1 + (gj + 1) * 5]
			for k in LEVELS:
				var p := a[k] + (b[k] - a[k]) * fx
				var q := c[k] + (e[k] - c[k]) * fx
				dens[k] = p + (q - p) * fz
			var col := x + (z << 4)
			for k in LEVELS - 1:
				var d0 := dens[k]
				var d1 := dens[k + 1]
				if d0 <= 0.0 and d1 <= 0.0:
					continue
				for j in 8:
					if d0 + (d1 - d0) * (j * 0.125) > 0.0:
						data[col + ((k * 8 + j) << 8)] = Blocks.END_STONE


## Части обсидиановых столбов в этом чанке; кристалл — в чанке с центром столба.
func _pillars_here() -> void:
	for p: Array in _pillars:
		var px: int = p[0]
		var pz: int = p[1]
		var r: int = p[2]
		var top: int = p[3]
		if not buf.overlaps(px - r, pz - r, px + r, pz + r):
			continue
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r + 1:
					continue
				# От поверхности острова (чуть глубже) до вершины столба.
				var ground := buf.top_y(px + dx, pz + dz, int(TOP) + 8)
				if ground < 0:
					continue
				buf.fill(px + dx, maxi(ground - 3, 1), pz + dz, px + dx, top, pz + dz, Blocks.OBSIDIAN)
		buf.set_b(px, top + 1, pz, Blocks.BEDROCK)
		buf.add_mob(200, px + 0.5, top + 2.0, pz + 0.5)
