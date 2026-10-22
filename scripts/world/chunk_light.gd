class_name ChunkLight
extends RefCounted
## Свет от блоков (факелы, лава, светокамень…): уровни 0–15 для каждой клетки чанка.
## Считается волной (BFS) от источников внутри чанка; переход света через границы чанков
## досчитывается при построении меша (ChunkMesher) по значениям соседей.
## Небесный свет приближается картой высот и здесь не хранится.

const S := 16
const LAYER := 256


## Карта света чанка (длина = blocks.size()). Работает в любом потоке.
static func compute(blocks: PackedByteArray) -> PackedByteArray:
	var light := PackedByteArray()
	light.resize(blocks.size())
	var queue := PackedInt32Array()
	var emission := Blocks.light_emission
	for id in Blocks.emitter_ids:
		var level := emission[id]
		var i := blocks.find(id)
		while i >= 0:
			light[i] = level
			queue.append(i)
			i = blocks.find(id, i + 1)
	if queue.is_empty():
		return light
	spread(blocks, light, queue)
	return light


## Распространение света из клеток очереди (их уровни уже записаны в light).
static func spread(blocks: PackedByteArray, light: PackedByteArray, queue: PackedInt32Array) -> void:
	var opq := Blocks.opaque_flags
	var n := blocks.size()
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var l := light[i] - 1
		if l <= 0:
			continue
		var x := i & 15
		var z := (i >> 4) & 15
		# Соседи по шести направлениям, внутри чанка.
		if x < 15:
			_try(blocks, light, queue, opq, i + 1, l)
		if x > 0:
			_try(blocks, light, queue, opq, i - 1, l)
		if z < 15:
			_try(blocks, light, queue, opq, i + S, l)
		if z > 0:
			_try(blocks, light, queue, opq, i - S, l)
		if i + LAYER < n:
			_try(blocks, light, queue, opq, i + LAYER, l)
		if i >= LAYER:
			_try(blocks, light, queue, opq, i - LAYER, l)


static func _try(blocks: PackedByteArray, light: PackedByteArray, queue: PackedInt32Array, opq: PackedByteArray, j: int, l: int) -> void:
	if light[j] >= l or opq[blocks[j]] == 1:
		return
	light[j] = l
	queue.append(j)
