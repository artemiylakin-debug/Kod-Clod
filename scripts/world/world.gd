class_name World
extends Node3D
## Мир из чанков: подгрузка вокруг игрока в фоновых потоках, правки блоков, свет, рейкаст,
## столкновения, сохранение. Логика блоков (жидкости, редстоун, рост растений…) — в BlockLogic.

signal chunk_loaded(ch: Chunk)
## Перед выгрузкой: игра сохраняет существ этого чанка в ch.entities.
signal chunk_unloading(ch: Chunk)

const CS := WorldGen.CHUNK_SIZE
const CH := WorldGen.CHUNK_HEIGHT
## Сколько задач генерации/мешинга может одновременно стоять в пуле потоков.
const MAX_STREAM_JOBS := 12
## Сколько готовых мешей применять за кадр (чтобы не было рывков).
const MESH_APPLY_PER_FRAME := 4

var seed_value := 0
var save_dir := ""
var render_distance := 6
## 0 — Обычный мир, -1 — Ад, 1 — Край.
var dimension := 0
var chunks: Dictionary = {}
var generator: Object
var generator_script: Script
## Обработчик изменений блоков (BlockLogic); может отсутствовать (тесты).
var logic: Object

var _jobs: Array[ChunkJob] = []
var _done_meshes: Array[ChunkJob] = []
var _pending_gen: Dictionary = {}
var _stream_jobs := 0
var _center := Vector2i(1 << 30, 1 << 30)
var _gen_order: Array[Vector2i] = []
var _mesh_order: Array[Vector2i] = []
## Однопоточная сборка (например, Web без SharedArrayBuffer): задачи выполняются в основном потоке
## порциями — не больше SYNC_BUDGET_USEC за кадр, чтобы игра не подтормаживала при подгрузке мира.
var _no_threads := OS.has_feature("nothreads")
const SYNC_BUDGET_USEC := 6000
## Бюджет можно увеличить, пока показан экран загрузки (рывки там не видны).
var sync_budget_usec := SYNC_BUDGET_USEC
var _sync_queue: Array[ChunkJob] = []
## Статистика синхронных задач (однопоточный режим): число и суммарное время, мс.
var sync_job_count := 0
var sync_job_ms := 0.0
## Чанки, меш которых нужно перестроить (накапливаются за кадр и строятся пакетом).
var _remesh_pending: Dictionary = {}


func setup(p_seed: int, p_save_dir: String, p_render_distance: int, p_generator: Script = null, p_dimension := 0) -> void:
	seed_value = p_seed
	save_dir = p_save_dir
	render_distance = p_render_distance
	generator_script = p_generator
	dimension = p_dimension
	generator = p_generator.new(p_seed) if p_generator != null else WorldGen.new(p_seed)


static func key_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x) >> 4, floori(pos.z) >> 4)


func set_render_distance(rd: int) -> void:
	if rd == render_distance:
		return
	render_distance = rd
	_center = Vector2i(1 << 30, 1 << 30)


# --- Доступ к блокам -------------------------------------------------------

func get_block(x: int, y: int, z: int) -> int:
	if y < 0 or y >= CH:
		return Blocks.AIR
	var ch: Chunk = chunks.get(Vector2i(x >> 4, z >> 4))
	if ch == null:
		return Blocks.AIR
	return ch.blocks[(x & 15) + ((z & 15) << 4) + (y << 8)]


func get_block_v(p: Vector3i) -> int:
	return get_block(p.x, p.y, p.z)


func meta_at(x: int, y: int, z: int) -> int:
	if y < 0 or y >= CH:
		return 0
	var ch: Chunk = chunks.get(Vector2i(x >> 4, z >> 4))
	if ch == null:
		return 0
	return ch.meta[(x & 15) + ((z & 15) << 4) + (y << 8)]


func get_meta_v(p: Vector3i) -> int:
	return meta_at(p.x, p.y, p.z)


func has_chunk_at(x: float, z: float) -> bool:
	return chunks.has(Vector2i(floori(x) >> 4, floori(z) >> 4))


func is_loaded(p: Vector3i) -> bool:
	return chunks.has(Vector2i(p.x >> 4, p.z >> 4))


## Чанк загружен и уже отрисован.
func is_chunk_ready(key: Vector2i) -> bool:
	var ch: Chunk = chunks.get(key)
	return ch != null and ch.applied_gen > 0


func is_area_ready(pos: Vector3, radius: int) -> bool:
	var c := key_of(pos)
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if not is_chunk_ready(c + Vector2i(dx, dz)):
				return false
	return true


## Верхний твёрдый блок колонки (или -1, если чанк не загружен).
func top_solid_y(x: int, z: int) -> int:
	if not has_chunk_at(x, z):
		return -1
	for y in range(CH - 1, -1, -1):
		if Blocks.is_solid(get_block(x, y, z)):
			return y
	return 0


## Высота верхнего непрозрачного блока колонки (по карте высот).
func height_at(x: int, z: int) -> int:
	var ch: Chunk = chunks.get(Vector2i(x >> 4, z >> 4))
	if ch == null or ch.heightmap.is_empty():
		return 0
	return ch.heightmap[(x & 15) + ((z & 15) << 4)]


func biome_at(x: int, z: int) -> int:
	var ch: Chunk = chunks.get(Vector2i(x >> 4, z >> 4))
	if ch == null or ch.biomes.is_empty():
		return Biomes.PLAINS
	return ch.biomes[(x & 15) + ((z & 15) << 4)]


## Небесный свет клетки (0–15) без учёта времени суток.
func get_sky_light(p: Vector3i) -> int:
	if dimension != 0:
		return 0
	var h := height_at(p.x, p.z)
	if p.y > h:
		return 15
	return maxi(0, 15 - (h - p.y) * 3)


## Свет от блоков (0–15) — с учётом соседних чанков (приближённо, по расстоянию).
func get_block_light(p: Vector3i) -> int:
	if p.y < 0 or p.y >= CH:
		return 0
	var key := Vector2i(p.x >> 4, p.z >> 4)
	var best := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ch: Chunk = chunks.get(key + Vector2i(dx, dz))
			if ch == null or ch.light.is_empty():
				continue
			var ox := (key.x + dx) * CS
			var oz := (key.y + dz) * CS
			var qx := clampi(p.x, ox, ox + CS - 1)
			var qz := clampi(p.z, oz, oz + CS - 1)
			var l: int = ch.light[(qx - ox) + ((qz - oz) << 4) + (p.y << 8)] - absi(qx - p.x) - absi(qz - p.z)
			best = maxi(best, l)
	return best


# --- Изменение блоков ------------------------------------------------------

## Ставит блок. notify — сообщить логике (соседи, жидкости, редстоун). Возвращает false, если ничего не изменилось.
func set_block(x: int, y: int, z: int, id: int, meta: int = 0, notify := true) -> bool:
	if y < 0 or y >= CH:
		return false
	var key := Vector2i(x >> 4, z >> 4)
	var ch: Chunk = chunks.get(key)
	if ch == null:
		return false
	var lx := x & 15
	var lz := z & 15
	var i := Chunk.index_of(lx, y, lz)
	var old := ch.blocks[i]
	var old_meta := ch.meta[i]
	if old == id and old_meta == meta:
		return false
	ch.blocks[i] = id
	ch.meta[i] = meta
	ch.modified = true
	ch.dirty = true
	if id != Blocks.AIR:
		ch.top_y = maxi(ch.top_y, y)
	if old != id:
		if ch.block_entities.has(i) and not Blocks.has_block_entity(id):
			ch.block_entities.erase(i)
		_update_tickers(ch, i, id)
		_update_heightmap(ch, lx, y, lz, id)
	var light_changed := _update_light(ch, i, old, id)
	_queue_remesh(key, lx, lz, light_changed)
	if notify and logic != null and is_instance_valid(logic):
		logic.call("on_block_changed", Vector3i(x, y, z), old, old_meta, id, meta)
	return true


func set_block_v(p: Vector3i, id: int, meta: int = 0, notify := true) -> bool:
	return set_block(p.x, p.y, p.z, id, meta, notify)


## Меняет только данные блока (например, уровень жидкости, заряд провода).
func set_meta_at(x: int, y: int, z: int, meta: int, notify := true) -> bool:
	return set_block(x, y, z, get_block(x, y, z), meta, notify)


func _update_tickers(ch: Chunk, i: int, id: int) -> void:
	if id in [Blocks.SAPLING, Blocks.WHEAT, Blocks.FARMLAND, Blocks.REEDS, Blocks.CACTUS, Blocks.PUMPKIN_STEM,
			Blocks.MELON_STEM, Blocks.NETHER_WART, Blocks.FIRE, Blocks.LIT_REDSTONE_ORE, Blocks.BROWN_MUSHROOM,
			Blocks.RED_MUSHROOM, Blocks.DIRT, Blocks.ICE, Blocks.SNOW_LAYER, Blocks.GRASS, Blocks.MYCELIUM]:
		ch.tickers[i] = true
	else:
		ch.tickers.erase(i)


func _update_heightmap(ch: Chunk, lx: int, y: int, lz: int, id: int) -> void:
	if ch.heightmap.is_empty():
		return
	var col := lx + (lz << 4)
	var h := ch.heightmap[col]
	if Blocks.is_opaque(id):
		if y > h:
			ch.heightmap[col] = y
	elif y == h:
		var yy := y - 1
		while yy > 0 and not Blocks.is_opaque(ch.blocks[col + (yy << 8)]):
			yy -= 1
		ch.heightmap[col] = yy


## Пересчёт света чанка, если правка могла его изменить. true — свет изменился.
func _update_light(ch: Chunk, i: int, old: int, id: int) -> bool:
	var emits := Blocks.light_of(old) != Blocks.light_of(id)
	var opacity := Blocks.is_opaque(old) != Blocks.is_opaque(id)
	if not emits and not (opacity and ch.light[i] > 0 or opacity and _near_light(ch, i)):
		return false
	var fresh := ChunkLight.compute(ch.blocks)
	var changed := fresh != ch.light
	ch.light = fresh
	return changed


func _near_light(ch: Chunk, i: int) -> bool:
	for d in 6:
		var p: Vector3i = Chunk.local_pos(i) + Blocks.FACE_VEC[d]
		if p.x < 0 or p.x > 15 or p.z < 0 or p.z > 15 or p.y < 0 or p.y >= CH:
			continue
		if ch.light[Chunk.index_of(p.x, p.y, p.z)] > 1:
			return true
	return false


func _queue_remesh(key: Vector2i, lx: int, lz: int, light_changed: bool) -> void:
	_remesh_pending[key] = true
	# Соседние чанки тоже перестраиваются: их грани, AO и свет зависят от блоков на границе.
	if light_changed:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				_remesh_pending[key + Vector2i(dx, dz)] = true
		return
	var nx := -1 if lx == 0 else (1 if lx == CS - 1 else 0)
	var nz := -1 if lz == 0 else (1 if lz == CS - 1 else 0)
	if nx != 0:
		_remesh_pending[key + Vector2i(nx, 0)] = true
	if nz != 0:
		_remesh_pending[key + Vector2i(0, nz)] = true
	if nx != 0 and nz != 0:
		_remesh_pending[key + Vector2i(nx, nz)] = true


## Перестраивает накопленные меши сразу (иначе — в начале следующего кадра).
func flush_remesh() -> void:
	if _remesh_pending.is_empty():
		return
	var keys: Array[Vector2i] = []
	for k: Vector2i in _remesh_pending:
		keys.append(k)
	_remesh_pending.clear()
	_remesh_batch(keys)


## Заполняет параллелепипед [from, to] блоком id; меши затронутых чанков перестраиваются один раз.
func fill_region(from: Vector3i, to: Vector3i, id: int, meta: int = 0) -> void:
	var lo := Vector3i(mini(from.x, to.x), clampi(mini(from.y, to.y), 0, CH - 1), mini(from.z, to.z))
	var hi := Vector3i(maxi(from.x, to.x), clampi(maxi(from.y, to.y), 0, CH - 1), maxi(from.z, to.z))
	var touched: Dictionary = {}
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			var key := Vector2i(x >> 4, z >> 4)
			var ch: Chunk = chunks.get(key)
			if ch == null:
				continue
			for y in range(lo.y, hi.y + 1):
				var i := Chunk.index_of(x & 15, y, z & 15)
				ch.blocks[i] = id
				ch.meta[i] = meta
				ch.block_entities.erase(i)
			ch.modified = true
			ch.dirty = true
			if id != Blocks.AIR:
				ch.top_y = maxi(ch.top_y, hi.y)
			touched[key] = ch
	for key: Vector2i in touched:
		var ch: Chunk = touched[key]
		ch.light = ChunkLight.compute(ch.blocks)
		ch.heightmap = Chunk.compute_heightmap(ch.blocks, maxi(ch.top_y, Chunk.compute_top(ch.blocks)))
		ch.tickers = Chunk.scan_tickers(ch.blocks)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				_remesh_pending[key + Vector2i(dx, dz)] = true
	flush_remesh()


## Ломает блок (без дропа). Возвращает прежний ID.
func break_block(p: Vector3i) -> int:
	var old := get_block_v(p)
	if old == Blocks.AIR:
		return old
	set_block(p.x, p.y, p.z, Blocks.AIR, 0)
	return old


# --- Данные блоков-контейнеров ---------------------------------------------

func get_block_entity(p: Vector3i, create := true) -> Dictionary:
	var ch: Chunk = chunks.get(Vector2i(p.x >> 4, p.z >> 4))
	if ch == null or p.y < 0 or p.y >= CH:
		return {}
	var i := Chunk.index_of(p.x & 15, p.y, p.z & 15)
	if ch.block_entities.has(i):
		return ch.block_entities[i]
	if not create:
		return {}
	var d := {}
	ch.block_entities[i] = d
	return d


func set_block_entity(p: Vector3i, data: Dictionary) -> void:
	var ch: Chunk = chunks.get(Vector2i(p.x >> 4, p.z >> 4))
	if ch == null:
		return
	ch.block_entities[Chunk.index_of(p.x & 15, p.y, p.z & 15)] = data
	ch.dirty = true
	ch.modified = true


func remove_block_entity(p: Vector3i) -> Dictionary:
	var ch: Chunk = chunks.get(Vector2i(p.x >> 4, p.z >> 4))
	if ch == null:
		return {}
	var i := Chunk.index_of(p.x & 15, p.y, p.z & 15)
	var d: Dictionary = ch.block_entities.get(i, {})
	ch.block_entities.erase(i)
	return d


func mark_dirty(p: Vector3i) -> void:
	var ch: Chunk = chunks.get(Vector2i(p.x >> 4, p.z >> 4))
	if ch != null:
		ch.dirty = true
		ch.modified = true


# --- Формы блоков в мире ---------------------------------------------------

## Маска соединений забора/панели в клетке p (бит 0 юг, 1 запад, 2 север, 3 восток).
func connections_at(p: Vector3i, id: int) -> int:
	var conn := 0
	for d in 4:
		if Blocks.connects_to(id, get_block_v(p + Blocks.DIR_VEC[d])):
			conn |= 1 << d
	return conn


## Габариты блока в мировых координатах (для столкновений или прицела).
func block_boxes(p: Vector3i, for_collision: bool) -> Array[AABB]:
	var id := get_block_v(p)
	var out: Array[AABB] = []
	if id == Blocks.AIR:
		return out
	if for_collision and not Blocks.is_solid(id):
		return out
	var meta := get_meta_v(p)
	var conn := 0
	var sh := Blocks.shapes[id]
	if sh == Blocks.SH_FENCE or sh == Blocks.SH_PANE:
		conn = connections_at(p, id)
	if sh == Blocks.SH_CUBE:
		out.append(AABB(Vector3(p), Vector3.ONE))
		return out
	for b in Blocks.shape_boxes(id, meta, conn, for_collision):
		out.append(AABB(b.position + Vector3(p), b.size))
	return out


## Твёрдые параллелепипеды, пересекающие область box (для физики игрока и существ).
func collision_boxes(box: AABB) -> Array[AABB]:
	var out: Array[AABB] = []
	var lo := box.position
	var hi := box.end
	# Заборы выше блока — проверяем и клетку под нижней границей.
	for y in range(floori(lo.y) - 1, floori(hi.y) + 1):
		for z in range(floori(lo.z), floori(hi.z) + 1):
			for x in range(floori(lo.x), floori(hi.x) + 1):
				var id := get_block(x, y, z)
				if id == Blocks.AIR or not Blocks.is_solid(id):
					continue
				if Blocks.shapes[id] == Blocks.SH_CUBE:
					var b := AABB(Vector3(x, y, z), Vector3.ONE)
					if b.intersects(box):
						out.append(b)
					continue
				for b in block_boxes(Vector3i(x, y, z), true):
					if b.intersects(box):
						out.append(b)
	return out


## Пошаговый обход вокселей (DDA) с проверкой формы блока.
## Возвращает {pos, normal, block, meta, hit} или пустой словарь. stop_at_liquid — цель на жидкости (вёдра).
func raycast(origin: Vector3, dir: Vector3, max_dist: float, stop_at_liquid := false) -> Dictionary:
	if dir.length_squared() < 1e-10:
		return {}
	dir = dir.normalized()
	var p := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(1 if dir.x > 0.0 else -1, 1 if dir.y > 0.0 else -1, 1 if dir.z > 0.0 else -1)
	var t_delta := Vector3(INF, INF, INF)
	var t_max := Vector3(INF, INF, INF)
	for a in 3:
		if dir[a] != 0.0:
			t_delta[a] = absf(1.0 / dir[a])
			var boundary: float = (p[a] + 1.0 - origin[a]) if dir[a] > 0.0 else (origin[a] - p[a])
			t_max[a] = boundary * t_delta[a]
	var normal := Vector3i.ZERO
	for _i in 256:
		var b := get_block(p.x, p.y, p.z)
		var target := Blocks.is_targetable(b) or (stop_at_liquid and Blocks.is_liquid(b) and get_meta_v(p) == 0)
		if target:
			if Blocks.shapes[b] == Blocks.SH_CUBE or Blocks.is_liquid(b):
				return {"pos": p, "normal": normal, "block": b, "meta": get_meta_v(p), "hit": origin + dir * _t_entry(t_max, t_delta, normal)}
			var hit := _ray_boxes(origin, dir, p, max_dist)
			if not hit.is_empty():
				hit["pos"] = p
				hit["block"] = b
				hit["meta"] = get_meta_v(p)
				return hit
		var axis := 0
		if t_max.y < t_max.x and t_max.y <= t_max.z:
			axis = 1
		elif t_max.z < t_max.x and t_max.z < t_max.y:
			axis = 2
		if t_max[axis] > max_dist:
			break
		p[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {}


static func _t_entry(t_max: Vector3, t_delta: Vector3, normal: Vector3i) -> float:
	if normal == Vector3i.ZERO:
		return 0.0
	for a in 3:
		if normal[a] != 0:
			return t_max[a] - t_delta[a]
	return 0.0


## Луч против параллелепипедов формы блока: ближайшее попадание {normal, hit} или {}.
func _ray_boxes(origin: Vector3, dir: Vector3, p: Vector3i, max_dist: float) -> Dictionary:
	var best := INF
	var best_n := Vector3i.ZERO
	for box in block_boxes(p, false):
		var r := _ray_aabb(origin, dir, box)
		if r.size() == 2 and float(r[0]) < best and float(r[0]) <= max_dist:
			best = r[0]
			best_n = r[1]
	if best == INF:
		return {}
	return {"normal": best_n, "hit": origin + dir * best}


## Пересечение луча с параллелепипедом: [t, нормаль] или [].
static func _ray_aabb(o: Vector3, d: Vector3, box: AABB) -> Array:
	var lo := box.position
	var hi := box.end
	var t0 := -INF
	var t1 := INF
	var n := Vector3i.ZERO
	for a in 3:
		if absf(d[a]) < 1e-9:
			if o[a] < lo[a] or o[a] > hi[a]:
				return []
			continue
		var ta := (lo[a] - o[a]) / d[a]
		var tb := (hi[a] - o[a]) / d[a]
		var na := Vector3i.ZERO
		na[a] = -1
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
			na[a] = 1
		if ta > t0:
			t0 = ta
			n = na
		t1 = minf(t1, tb)
		if t0 > t1:
			return []
	if t1 < 0.0:
		return []
	return [maxf(t0, 0.0), n]


# --- Подгрузка чанков ------------------------------------------------------

func update_streaming(focus: Vector3) -> void:
	flush_remesh()
	_run_sync_queue()
	_poll_jobs()
	_apply_done_meshes()
	var c := key_of(focus)
	if c != _center:
		_center = c
		_rebuild_orders()
		_unload_far()
	_schedule()


func _mesh_radius_ok(dx: int, dz: int) -> bool:
	return dx * dx + dz * dz <= render_distance * render_distance + render_distance


func _data_radius_ok(dx: int, dz: int) -> bool:
	var ax := maxi(absi(dx) - 1, 0)
	var az := maxi(absi(dz) - 1, 0)
	return ax * ax + az * az <= render_distance * render_distance + render_distance


func _keep_radius_ok(dx: int, dz: int) -> bool:
	var ax := maxi(absi(dx) - 2, 0)
	var az := maxi(absi(dz) - 2, 0)
	return ax * ax + az * az <= render_distance * render_distance + render_distance


func _rebuild_orders() -> void:
	_gen_order.clear()
	_mesh_order.clear()
	var r := render_distance + 1
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var key := _center + Vector2i(dx, dz)
			if _data_radius_ok(dx, dz):
				_gen_order.append(key)
			if _mesh_radius_ok(dx, dz):
				_mesh_order.append(key)
	var c := _center
	var closer := func(a: Vector2i, b: Vector2i) -> bool:
		return (a - c).length_squared() < (b - c).length_squared()
	_gen_order.sort_custom(closer)
	_mesh_order.sort_custom(closer)


func _unload_far() -> void:
	var drop: Array[Vector2i] = []
	for key: Vector2i in chunks:
		var d := key - _center
		if not _keep_radius_ok(d.x, d.y):
			drop.append(key)
	for key in drop:
		unload_chunk(key)


func unload_chunk(key: Vector2i) -> void:
	var ch: Chunk = chunks.get(key)
	if ch == null:
		return
	chunk_unloading.emit(ch)
	if ch.dirty:
		WorldStorage.save_chunk(save_dir, key, chunk_data(ch))
	ch.free_nodes()
	chunks.erase(key)


static func chunk_data(ch: Chunk) -> Dictionary:
	return {"blocks": ch.blocks, "meta": ch.meta, "biomes": ch.biomes, "block_entities": ch.block_entities,
		"entities": ch.entities}


func _schedule() -> void:
	# Без потоков очередь короткая: ближайшие чанки всегда идут первыми.
	var limit := 3 if _no_threads else MAX_STREAM_JOBS
	# Сначала меши для уже загруженных чанков (видимый результат), затем генерация новых.
	for key in _mesh_order:
		if _stream_jobs >= limit:
			return
		var ch: Chunk = chunks.get(key)
		if ch == null or ch.jobs_in_flight > 0 or ch.applied_gen >= ch.mesh_gen:
			continue
		if not _neighbors_ready(key):
			continue
		_start_job(_make_mesh_job(ch), false)
	for key in _gen_order:
		if _stream_jobs >= limit:
			return
		if chunks.has(key) or _pending_gen.has(key):
			continue
		var job := ChunkJob.new()
		job.kind = ChunkJob.GENERATE
		job.key = key
		job.seed_value = seed_value
		job.save_dir = save_dir
		job.generator_script = generator_script
		_pending_gen[key] = true
		_start_job(job, false)


func _neighbors_ready(key: Vector2i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if not chunks.has(key + Vector2i(dx, dz)):
				return false
	return true


func _make_mesh_job(ch: Chunk) -> ChunkJob:
	var job := ChunkJob.new()
	job.kind = ChunkJob.MESH
	job.key = ch.key
	job.chunk = ch
	job.mesh_gen = ch.mesh_gen
	var vol_top := ch.top_y
	var blocks := []
	var metas := []
	var lights := []
	var neighbors: Array[Chunk] = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n: Chunk = chunks[ch.key + Vector2i(dx, dz)]
			neighbors.append(n)
			# Копии: главный поток может менять блоки, пока задача читает данные.
			blocks.append(n.blocks.duplicate())
			metas.append(n.meta.duplicate())
			lights.append(n.light.duplicate())
			vol_top = maxi(vol_top, n.top_y)
	var grass := PackedColorArray()
	var foliage := PackedColorArray()
	grass.resize(ChunkMesher.SY)
	foliage.resize(ChunkMesher.SY)
	for pz in ChunkMesher.PS:
		for px in ChunkMesher.PS:
			var x := px - 1
			var z := pz - 1
			var ci := (1 if x >= 0 and x < CS else (0 if x < 0 else 2)) + 3 * (1 if z >= 0 and z < CS else (0 if z < 0 else 2))
			var n := neighbors[ci]
			var b := Biomes.PLAINS
			if n.biomes.size() == WorldGen.LAYER:
				b = n.biomes[(x & 15) + ((z & 15) << 4)]
			grass[px + pz * ChunkMesher.PS] = Biomes.grass_color(b)
			foliage[px + pz * ChunkMesher.PS] = Biomes.foliage_color(b)
	job.mesh_input = {"blocks": blocks, "metas": metas, "lights": lights, "grass": grass, "foliage": foliage,
		"top_y": ch.top_y, "vol_top": mini(vol_top, CH - 1), "cx": ch.key.x, "cz": ch.key.y}
	ch.jobs_in_flight += 1
	return job


func _start_job(job: ChunkJob, high_priority: bool) -> void:
	if not high_priority:
		_stream_jobs += 1
	_dispatch(job, high_priority, "chunk")


func _dispatch(job: ChunkJob, high_priority: bool, label: String) -> void:
	if _no_threads:
		job.task_id = -1
		if high_priority:
			_timed_step(job, -1) # Правка блока: результат нужен сразу.
		else:
			_sync_queue.append(job)
	else:
		job.task_id = WorkerThreadPool.add_task(job.run, high_priority, label)
	_jobs.append(job)


func _job_finished(job: ChunkJob) -> bool:
	if job.task_id < 0:
		return job.completed
	if not WorkerThreadPool.is_task_completed(job.task_id):
		return false
	WorkerThreadPool.wait_for_task_completion(job.task_id)
	return true


## Правка блока: меши затронутых чанков строятся с высоким приоритетом и применяются одним кадром,
## чтобы на границе чанков не мелькали дыры.
func _remesh_batch(keys: Array[Vector2i]) -> void:
	var batch: Array = []
	for key in keys:
		var ch: Chunk = chunks.get(key)
		if ch == null:
			continue
		ch.mesh_gen += 1
		if ch.applied_gen == 0 or not _neighbors_ready(key):
			continue # Ещё не отрисован — его построит обычная очередь.
		var job := _make_mesh_job(ch)
		job.batch = batch
		batch.append(job)
	for job: ChunkJob in batch:
		_dispatch(job, true, "chunk_edit")


func _run_sync_queue() -> void:
	if _sync_queue.is_empty():
		return
	var deadline := Time.get_ticks_usec() + sync_budget_usec
	while not _sync_queue.is_empty() and Time.get_ticks_usec() < deadline:
		if _timed_step(_sync_queue[0], deadline):
			_sync_queue.pop_front()


func _timed_step(job: ChunkJob, deadline_usec: int) -> bool:
	var t0 := Time.get_ticks_usec()
	var finished := job.step(deadline_usec)
	sync_job_ms += (Time.get_ticks_usec() - t0) / 1000.0
	if finished:
		job.completed = true
		sync_job_count += 1
	return finished


func _poll_jobs() -> void:
	var i := 0
	while i < _jobs.size():
		var job := _jobs[i]
		if not _job_finished(job):
			i += 1
			continue
		_jobs.remove_at(i)
		job.done = true
		if job.batch.is_empty():
			_stream_jobs -= 1
		if job.kind == ChunkJob.GENERATE:
			_on_generated(job)
		else:
			_done_meshes.append(job)


func _on_generated(job: ChunkJob) -> void:
	_pending_gen.erase(job.key)
	var d := job.key - _center
	if chunks.has(job.key) or not _data_radius_ok(d.x, d.y):
		return
	var ch := Chunk.new()
	ch.key = job.key
	ch.blocks = job.data["blocks"]
	ch.meta = job.data["meta"]
	ch.biomes = job.data.get("biomes", PackedByteArray())
	ch.block_entities = job.data.get("block_entities", {})
	ch.entities = job.data.get("entities", [])
	ch.light = job.light
	ch.heightmap = job.heightmap
	ch.tickers = job.tickers
	ch.top_y = job.computed_top
	ch.modified = job.from_disk
	# Сгенерированные контейнеры (сундуки в данжах и деревнях) и существа — сохранять сразу.
	if not job.from_disk and (not ch.block_entities.is_empty() or not ch.entities.is_empty()):
		ch.modified = true
		ch.dirty = true
	chunks[job.key] = ch
	chunk_loaded.emit(ch)


func _apply_done_meshes() -> void:
	var applied := 0
	var i := 0
	while i < _done_meshes.size():
		var job := _done_meshes[i]
		if not job.batch.is_empty():
			var all_done := true
			for other: ChunkJob in job.batch:
				if not other.done:
					all_done = false
					break
			if not all_done:
				i += 1
				continue
		elif applied >= (1 if _no_threads else MESH_APPLY_PER_FRAME):
			i += 1
			continue
		else:
			applied += 1
		_done_meshes.remove_at(i)
		_finish_mesh(job)
		# Задачи пакета ссылаются на общий массив, а он — на них: разрываем цикл ссылок,
		# иначе RefCounted-объекты (вместе с готовыми мешами) никогда не освободятся.
		job.batch = []
		job.result = {}


func _finish_mesh(job: ChunkJob) -> void:
	var ch := job.chunk
	ch.jobs_in_flight -= 1
	if chunks.get(job.key) != ch:
		return # Чанк уже выгружен.
	if job.mesh_gen <= ch.applied_gen:
		return # Устаревший результат.
	ch.applied_gen = job.mesh_gen
	ch.opaque_node = _update_node(ch.opaque_node, job.result["opaque"], TextureFactory.chunk_material, ch.key)
	ch.water_node = _update_node(ch.water_node, job.result["translucent"], TextureFactory.water_material, ch.key)


func _update_node(node: MeshInstance3D, arrays: Array, mat: Material, key: Vector2i) -> MeshInstance3D:
	if arrays.is_empty():
		if is_instance_valid(node):
			node.queue_free()
		return null
	if not is_instance_valid(node):
		node = MeshInstance3D.new()
		node.position = Vector3(key.x * CS, 0, key.y * CS)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	node.mesh = mesh
	return node


## Все чанки в радиусе прорисовки вокруг focus загружены и отрисованы, фоновых задач нет.
func is_streaming_idle(focus: Vector3) -> bool:
	if key_of(focus) != _center or not _jobs.is_empty() or not _done_meshes.is_empty() or not _remesh_pending.is_empty():
		return false
	for key in _mesh_order:
		var ch: Chunk = chunks.get(key)
		if ch == null or ch.applied_gen < ch.mesh_gen:
			return false
	return true


func loaded_count() -> int:
	return chunks.size()


func pending_jobs() -> int:
	return _jobs.size()


# --- Сохранение ------------------------------------------------------------

## Записывает на диск все изменённые чанки. Возвращает количество записанных.
func save_dirty_chunks() -> int:
	var n := 0
	for ch: Chunk in chunks.values():
		if ch.dirty:
			if WorldStorage.save_chunk(save_dir, ch.key, chunk_data(ch)):
				ch.dirty = false
				n += 1
	return n


func wait_for_jobs() -> void:
	for job in _jobs:
		if job.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(job.task_id)
		job.batch = []
	for job in _done_meshes:
		job.batch = []
	_sync_queue.clear()
	_jobs.clear()
	_done_meshes.clear()
	_stream_jobs = 0


func _exit_tree() -> void:
	wait_for_jobs()
