class_name Structures
extends RefCounted
## Крупные постройки Обычного мира (MapGenStructure 1.2): деревни, заброшенные шахты и крепости.
## Расположение и план каждой постройки вычисляются из сида; чанк ставит только свою часть.

var gen: WorldGen


func _init(p_gen: WorldGen) -> void:
	gen = p_gen


func begin() -> void:
	pass


func generate() -> void:
	pass


## Мешает ли постройка дереву в этой колонке (деревья не растут посреди деревни).
func blocks_tree(_x: int, _z: int) -> bool:
	return false
