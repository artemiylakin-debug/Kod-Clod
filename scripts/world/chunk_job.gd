class_name ChunkJob
extends RefCounted
## Задача для WorkerThreadPool: загрузка/генерация чанка или построение его меша.
## Объект не обращается к дереву сцены — главный поток забирает результат после завершения.

const GENERATE := 0
const MESH := 1

var kind := GENERATE
var key := Vector2i.ZERO
var task_id := -1
var done := false

# Генерация.
var seed_value := 0
var save_dir := ""
var blocks := PackedByteArray()
var from_disk := false
var computed_top := 0

# Построение меша.
var chunk: Chunk
var neighbors: Array = []
var top_y := 0
var vol_top := 0
var mesh_gen := 0
var result: Dictionary = {}
## Задачи, которые нужно применить в одном кадре (правка блока на границе чанков).
var batch: Array = []


## Однопоточный режим: задача выполнена (в многопоточном завершение узнаётся у пула).
var completed := false

var _stage := 0
var _row := 0
var _gen: WorldGen
var _mesher: ChunkMesher


## Выполнение целиком (в рабочем потоке).
func run() -> void:
	step(-1)


## Выполняет задачу порциями до момента deadline_usec (-1 — без ограничения). true — задача готова.
## В однопоточной веб-сборке так работа над чанками растягивается на несколько кадров без рывков.
func step(deadline_usec: int) -> bool:
	if kind == GENERATE:
		return _step_generate(deadline_usec)
	return _step_mesh(deadline_usec)


static func _out_of_time(deadline_usec: int) -> bool:
	return deadline_usec >= 0 and Time.get_ticks_usec() >= deadline_usec


func _step_generate(deadline_usec: int) -> bool:
	if _stage == 0:
		_stage = 1
		blocks = WorldStorage.load_chunk(save_dir, key)
		from_disk = not blocks.is_empty()
		if from_disk:
			computed_top = Chunk.compute_top(blocks)
			return true
		_gen = WorldGen.new(seed_value)
		_gen.begin_chunk(key.x, key.y)
		if _out_of_time(deadline_usec):
			return false
	while _row < WorldGen.CHUNK_SIZE:
		_gen.fill_rows(_row, _row + 1)
		_row += 1
		if _row < WorldGen.CHUNK_SIZE and _out_of_time(deadline_usec):
			return false
	blocks = _gen.finish_chunk()
	_gen = null
	computed_top = Chunk.compute_top(blocks)
	return true


func _step_mesh(deadline_usec: int) -> bool:
	if _mesher == null:
		_mesher = ChunkMesher.begin(neighbors, top_y, vol_top)
		neighbors.clear()
		if _out_of_time(deadline_usec):
			return false
	while not _mesher.mesh_layers(1):
		if _out_of_time(deadline_usec):
			return false
	result = _mesher.result()
	_mesher = null
	return true
