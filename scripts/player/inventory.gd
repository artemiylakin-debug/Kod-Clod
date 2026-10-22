class_name Inventory
extends RefCounted
## Инвентарь: 9 слотов хотбара (0–8) и 27 слотов рюкзака (9–35).

signal changed

const SIZE := 36
const HOTBAR_SIZE := 9
const MAX_STACK := 64
const CREATIVE_HOTBAR := [Blocks.GRASS, Blocks.DIRT, Blocks.STONE, Blocks.COBBLESTONE, Blocks.LOG,
	Blocks.PLANKS, Blocks.GLASS, Blocks.BRICKS, Blocks.SAND]

var ids := PackedInt32Array()
var counts := PackedInt32Array()
var selected := 0


func _init() -> void:
	ids.resize(SIZE)
	counts.resize(SIZE)


func get_selected_block() -> int:
	return ids[selected] if counts[selected] > 0 else Blocks.AIR


func select(slot: int) -> void:
	slot = posmod(slot, HOTBAR_SIZE)
	if slot != selected:
		selected = slot
		changed.emit()


func set_slot(slot: int, id: int, count: int) -> void:
	if count <= 0 or id == Blocks.AIR:
		ids[slot] = Blocks.AIR
		counts[slot] = 0
	else:
		ids[slot] = id
		counts[slot] = mini(count, MAX_STACK)
	changed.emit()


## Добавляет предметы (сначала в существующие стопки, затем в пустые слоты).
## Возвращает количество, которое не поместилось.
func add_item(id: int, count: int) -> int:
	if id == Blocks.AIR or count <= 0:
		return 0
	for i in SIZE:
		if count == 0:
			break
		if ids[i] == id and counts[i] > 0 and counts[i] < MAX_STACK:
			var add := mini(count, MAX_STACK - counts[i])
			counts[i] += add
			count -= add
	for i in SIZE:
		if count == 0:
			break
		if counts[i] == 0:
			var add := mini(count, MAX_STACK)
			ids[i] = id
			counts[i] = add
			count -= add
	changed.emit()
	return count


func count_of(id: int) -> int:
	var total := 0
	for i in SIZE:
		if ids[i] == id:
			total += counts[i]
	return total


## Убирает предметы из любых слотов (начиная с рюкзака). false — если предметов не хватает.
func remove_item(id: int, count: int) -> bool:
	if count_of(id) < count:
		return false
	for i in range(SIZE - 1, -1, -1):
		if count == 0:
			break
		if ids[i] == id and counts[i] > 0:
			var take := mini(count, counts[i])
			counts[i] -= take
			count -= take
			if counts[i] == 0:
				ids[i] = Blocks.AIR
	changed.emit()
	return true


func consume_selected(n: int = 1) -> void:
	if counts[selected] <= 0:
		return
	counts[selected] = maxi(counts[selected] - n, 0)
	if counts[selected] == 0:
		ids[selected] = Blocks.AIR
	changed.emit()


## Перемещение из слота a в слот b: одинаковые предметы складываются, разные — меняются местами.
func move_slot(a: int, b: int) -> void:
	if a == b:
		return
	if ids[a] == ids[b] and counts[a] > 0 and counts[b] > 0:
		var add := mini(counts[a], MAX_STACK - counts[b])
		counts[b] += add
		counts[a] -= add
		if counts[a] == 0:
			ids[a] = Blocks.AIR
	else:
		var tid := ids[a]
		var tc := counts[a]
		ids[a] = ids[b]
		counts[a] = counts[b]
		ids[b] = tid
		counts[b] = tc
	changed.emit()


func clear() -> void:
	ids.fill(0)
	counts.fill(0)
	changed.emit()


func fill_creative_hotbar() -> void:
	for i in HOTBAR_SIZE:
		ids[i] = CREATIVE_HOTBAR[i]
		counts[i] = 1
	changed.emit()


func is_empty() -> bool:
	for c in counts:
		if c > 0:
			return false
	return true


func to_data() -> Array:
	var out := []
	for i in SIZE:
		out.append([ids[i], counts[i]])
	return out


func from_data(data: Array) -> void:
	ids.fill(0)
	counts.fill(0)
	for i in mini(data.size(), SIZE):
		var slot: Variant = data[i]
		if slot is Array and slot.size() == 2:
			var id := int(slot[0])
			var c := int(slot[1])
			if id > Blocks.AIR and id < Blocks.COUNT and c > 0:
				ids[i] = id
				counts[i] = mini(c, MAX_STACK)
	changed.emit()
