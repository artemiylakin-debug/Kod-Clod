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


func run() -> void:
	if kind == GENERATE:
		blocks = WorldStorage.load_chunk(save_dir, key)
		from_disk = not blocks.is_empty()
		if not from_disk:
			blocks = WorldGen.new(seed_value).generate_chunk(key.x, key.y)
		computed_top = Chunk.compute_top(blocks)
	else:
		result = ChunkMesher.build(neighbors, top_y, vol_top)
		neighbors.clear()
