class_name World
extends Node3D
## Мир из чанков: подгрузка вокруг игрока в фоновых потоках, правки блоков, рейкаст, сохранение.

const CS := WorldGen.CHUNK_SIZE
const CH := WorldGen.CHUNK_HEIGHT
## Сколько задач генерации/мешинга может одновременно стоять в пуле потоков.
const MAX_STREAM_JOBS := 12
## Сколько готовых мешей применять за кадр (чтобы не было рывков).
const MESH_APPLY_PER_FRAME := 4

var seed_value := 0
var save_dir := ""
var render_distance := 6
var chunks: Dictionary = {}
var generator: WorldGen

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


func setup(p_seed: int, p_save_dir: String, p_render_distance: int) -> void:
	seed_value = p_seed
	save_dir = p_save_dir
	render_distance = p_render_distance
	generator = WorldGen.new(p_seed)


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


func has_chunk_at(x: float, z: float) -> bool:
	return chunks.has(Vector2i(floori(x) >> 4, floori(z) >> 4))


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


func set_block(x: int, y: int, z: int, id: int) -> bool:
	if y < 0 or y >= CH:
		return false
	var key := Vector2i(x >> 4, z >> 4)
	var ch: Chunk = chunks.get(key)
	if ch == null:
		return false
	var lx := x & 15
	var lz := z & 15
	var i := Chunk.index_of(lx, y, lz)
	if ch.blocks[i] == id:
		return false
	ch.blocks[i] = id
	ch.modified = true
	ch.dirty = true
	if id != Blocks.AIR:
		ch.top_y = maxi(ch.top_y, y)
	# Соседние чанки тоже перестраиваются: их грани и AO зависят от блока на границе.
	var keys: Array[Vector2i] = [key]
	var nx := -1 if lx == 0 else (1 if lx == CS - 1 else 0)
	var nz := -1 if lz == 0 else (1 if lz == CS - 1 else 0)
	if nx != 0:
		keys.append(key + Vector2i(nx, 0))
	if nz != 0:
		keys.append(key + Vector2i(0, nz))
	if nx != 0 and nz != 0:
		keys.append(key + Vector2i(nx, nz))
	_remesh_batch(keys)
	return true


## Заполняет параллелепипед [from, to] блоком id; меши затронутых чанков перестраиваются один раз.
func fill_region(from: Vector3i, to: Vector3i, id: int) -> void:
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
				ch.blocks[Chunk.index_of(x & 15, y, z & 15)] = id
			ch.modified = true
			ch.dirty = true
			if id != Blocks.AIR:
				ch.top_y = maxi(ch.top_y, hi.y)
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					touched[key + Vector2i(dx, dz)] = true
	var keys: Array[Vector2i] = []
	for k: Vector2i in touched:
		keys.append(k)
	_remesh_batch(keys)


## Ломает блок. Если рядом вода — она затекает в образовавшуюся пустоту.
func break_block(p: Vector3i) -> int:
	var old := get_block_v(p)
	if old == Blocks.AIR:
		return old
	var fill := Blocks.AIR
	for n in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
		if get_block_v(p + n) == Blocks.WATER:
			fill = Blocks.WATER
			break
	set_block(p.x, p.y, p.z, fill)
	return old


## Пошаговый обход вокселей (DDA). Возвращает {pos, normal, block} или пустой словарь.
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
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
		if Blocks.is_targetable(b):
			return {"pos": p, "normal": normal, "block": b}
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


# --- Подгрузка чанков ------------------------------------------------------

func update_streaming(focus: Vector3) -> void:
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
		var ch: Chunk = chunks[key]
		if ch.dirty:
			WorldStorage.save_chunk(save_dir, key, ch.blocks)
		ch.free_nodes()
		chunks.erase(key)


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
	job.top_y = ch.top_y
	var vol_top := ch.top_y
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n: Chunk = chunks[ch.key + Vector2i(dx, dz)]
			# Копия: главный поток может менять блоки, пока задача читает данные.
			job.neighbors.append(n.blocks.duplicate())
			vol_top = maxi(vol_top, n.top_y)
	job.vol_top = mini(vol_top, CH - 1)
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
	ch.blocks = job.blocks
	ch.top_y = job.computed_top
	ch.modified = job.from_disk
	chunks[job.key] = ch


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
		elif applied >= MESH_APPLY_PER_FRAME:
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
	ch.water_node = _update_node(ch.water_node, job.result["water"], TextureFactory.water_material, ch.key)


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
	if key_of(focus) != _center or not _jobs.is_empty() or not _done_meshes.is_empty():
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
			if WorldStorage.save_chunk(save_dir, ch.key, ch.blocks):
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
