class_name Chunk
extends RefCounted
## Данные одного чанка 16×256×16: блоки, их данные (meta), свет от блоков, биомы колонок,
## данные блоков-контейнеров и сохранённые существа; состояние меша.

var key := Vector2i.ZERO
var blocks := PackedByteArray()
var meta := PackedByteArray()
## Свет от блоков (0–15), только от источников этого чанка — см. ChunkLight.
var light := PackedByteArray()
## Биом каждой колонки (16×16).
var biomes := PackedByteArray()
## Высота верхнего непрозрачного блока колонки (для небесного света и появления мобов).
var heightmap := PackedInt32Array()
## Данные блоков-контейнеров: локальный индекс → словарь (сундуки, печи, таблички…).
var block_entities: Dictionary = {}
## Существа, сохранённые вместе с чанком (восстанавливаются при загрузке).
var entities: Array = []
## Блоки, участвующие в случайных тиках: локальный индекс → true.
var tickers: Dictionary = {}
## Верхний непустой слой (для ограничения объёма при построении меша).
var top_y := 0
## Чанк отличается от сгенерированного и должен храниться на диске.
var modified := false
## Есть изменения, ещё не записанные на диск.
var dirty := false
## Требуемое и применённое «поколение» меша: результат старее применённого отбрасывается.
var mesh_gen := 1
var applied_gen := 0
var jobs_in_flight := 0
var opaque_node: MeshInstance3D
var water_node: MeshInstance3D


static func index_of(lx: int, y: int, lz: int) -> int:
	return lx + lz * WorldGen.CHUNK_SIZE + y * WorldGen.LAYER


static func local_pos(i: int) -> Vector3i:
	return Vector3i(i & 15, i >> 8, (i >> 4) & 15)


static func compute_top(data: PackedByteArray) -> int:
	var layer := WorldGen.LAYER
	for y in range(WorldGen.CHUNK_HEIGHT - 1, -1, -1):
		if data.slice(y * layer, (y + 1) * layer).count(Blocks.AIR) != layer:
			return y
	return 0


static func compute_heightmap(data: PackedByteArray, top: int) -> PackedInt32Array:
	var hm := PackedInt32Array()
	hm.resize(WorldGen.LAYER)
	var opq := Blocks.opaque_flags
	for col in WorldGen.LAYER:
		var y := top
		while y > 0 and opq[data[col + y * WorldGen.LAYER]] == 0:
			y -= 1
		hm[col] = y
	return hm


## Блоки для случайных тиков (растения, огонь, грядки…). Трава, лёд и лианы слишком
## многочисленны — их изменения обрабатываются точечно.
static func scan_tickers(data: PackedByteArray) -> Dictionary:
	var out := {}
	for id in [Blocks.SAPLING, Blocks.WHEAT, Blocks.FARMLAND, Blocks.REEDS, Blocks.CACTUS, Blocks.PUMPKIN_STEM,
			Blocks.MELON_STEM, Blocks.NETHER_WART, Blocks.FIRE, Blocks.LIT_REDSTONE_ORE, Blocks.BROWN_MUSHROOM,
			Blocks.RED_MUSHROOM]:
		var i := data.find(id)
		while i >= 0:
			out[i] = true
			i = data.find(id, i + 1)
	return out


func free_nodes() -> void:
	if is_instance_valid(opaque_node):
		opaque_node.queue_free()
	if is_instance_valid(water_node):
		water_node.queue_free()
	opaque_node = null
	water_node = null
