class_name Chunk
extends RefCounted
## Данные одного чанка 16×128×16 и состояние его меша.

var key := Vector2i.ZERO
var blocks := PackedByteArray()
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


static func compute_top(data: PackedByteArray) -> int:
	var layer := WorldGen.LAYER
	for y in range(WorldGen.CHUNK_HEIGHT - 1, -1, -1):
		if data.slice(y * layer, (y + 1) * layer).count(Blocks.AIR) != layer:
			return y
	return 0


func free_nodes() -> void:
	if is_instance_valid(opaque_node):
		opaque_node.queue_free()
	if is_instance_valid(water_node):
		water_node.queue_free()
	opaque_node = null
	water_node = null
