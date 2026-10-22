class_name Redstone
extends RefCounted
## Красная пыль и механизмы (заглушка до полной реализации): вызывается BlockLogic.

var logic: BlockLogic


func _init(p_logic: BlockLogic) -> void:
	logic = p_logic


func on_tick() -> void:
	pass


func on_block_changed(_p: Vector3i, _old: int, _old_meta: int, _id: int, _meta: int) -> void:
	pass


func on_neighbor_changed(_p: Vector3i, _from: Vector3i) -> void:
	pass


func on_scheduled(_p: Vector3i, _id: int) -> void:
	pass


## Получает ли блок в p заряд (от рычага, кнопки, пыли, факела…).
func is_powered(_p: Vector3i) -> bool:
	return false
