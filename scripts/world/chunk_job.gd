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

# Генерация: результат — словарь {blocks, meta, biomes, block_entities, entities} + свет и пр.
var seed_value := 0
var save_dir := ""
var generator_script: Script
var data: Dictionary = {}
var from_disk := false
var computed_top := 0
var light := PackedByteArray()
var heightmap := PackedInt32Array()
var tickers: Dictionary = {}

# Построение меша.
var chunk: Chunk
var mesh_input: Dictionary = {}
var mesh_gen := 0
var result: Dictionary = {}
## Задачи, которые нужно применить в одном кадре (правка блока на границе чанков).
var batch: Array = []


## Однопоточный режим: задача выполнена (в многопоточном завершение узнаётся у пула).
var completed := false

var _stage := 0
var _row := 0
var _gen: Object
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
		data = WorldStorage.load_chunk(save_dir, key)
		from_disk = not data.is_empty()
		if from_disk:
			_stage = 3
		else:
			_gen = generator_script.new(seed_value) if generator_script != null else WorldGen.new(seed_value)
			_gen.call("begin_chunk", key.x, key.y)
			if _out_of_time(deadline_usec):
				return false
	if _stage == 1:
		while _row < WorldGen.CHUNK_SIZE:
			_gen.call("fill_rows", _row, _row + 1)
			_row += 1
			if _row < WorldGen.CHUNK_SIZE and _out_of_time(deadline_usec):
				return false
		data = _gen.call("finish_chunk")
		_gen = null
		_stage = 3
		if _out_of_time(deadline_usec):
			return false
	# Свет, высоты и тикающие блоки — тоже в рабочем потоке.
	var blocks: PackedByteArray = data["blocks"]
	computed_top = Chunk.compute_top(blocks)
	light = ChunkLight.compute(blocks)
	heightmap = Chunk.compute_heightmap(blocks, computed_top)
	tickers = Chunk.scan_tickers(blocks)
	return true


func _step_mesh(deadline_usec: int) -> bool:
	if _mesher == null:
		_mesher = ChunkMesher.begin(mesh_input)
		mesh_input = {}
	if not _mesher.prepare(deadline_usec) or _out_of_time(deadline_usec):
		return false
	while not _mesher.mesh_layers(1):
		if _out_of_time(deadline_usec):
			return false
	result = _mesher.result()
	_mesher = null
	return true
