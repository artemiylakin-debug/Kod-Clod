class_name Inventory
extends RefCounted
## Инвентарь игрока: 9 слотов хотбара (0–8), 27 слотов рюкзака (9–35) и 4 слота брони (36–39:
## шлем, нагрудник, поножи, ботинки). Слот — ID предмета, количество и данные (вариант или износ).
## Тот же класс хранит содержимое сундуков, печей и раздатчиков (с другим размером).

signal changed

const SIZE := 36
const HOTBAR_SIZE := 9
const ARMOR_START := 36
const TOTAL := 40
const MAX_STACK := 64
const CREATIVE_HOTBAR := [[Blocks.STONE, 0], [Blocks.GRASS, 0], [Blocks.DIRT, 0], [Blocks.COBBLESTONE, 0],
	[Blocks.PLANKS, 0], [Blocks.LOG, 0], [Blocks.GLASS, 0], [Blocks.TORCH, 0], [Blocks.CRAFTING_TABLE, 0]]
## Старые номера блоков (сохранения до набора 1.2) → номера Minecraft.
const V1_IDS := [0, 2, 3, 1, 4, 17, 18, 5, 12, 20, 7, 9, 16, 15, 45, 80, 13, 98, 47]

var ids := PackedInt32Array()
var counts := PackedInt32Array()
var datas := PackedInt32Array()
var selected := 0
var size := TOTAL


func _init(p_size: int = TOTAL) -> void:
	size = p_size
	ids.resize(size)
	counts.resize(size)
	datas.resize(size)


func is_slot_empty(slot: int) -> bool:
	return counts[slot] <= 0 or ids[slot] == 0


## ID предмета в руке (0 — пусто). Старое имя сохранено для совместимости.
func get_selected_block() -> int:
	return selected_id()


func selected_id() -> int:
	return ids[selected] if counts[selected] > 0 else 0


func selected_data() -> int:
	return datas[selected] if counts[selected] > 0 else 0


func select(slot: int) -> void:
	slot = posmod(slot, HOTBAR_SIZE)
	if slot != selected:
		selected = slot
		changed.emit()


func set_slot(slot: int, id: int, count: int, data: int = 0) -> void:
	if count <= 0 or id == 0:
		ids[slot] = 0
		counts[slot] = 0
		datas[slot] = 0
	else:
		ids[slot] = id
		counts[slot] = mini(count, Items.max_stack(id))
		datas[slot] = data
	changed.emit()


static func stacks_with(id_a: int, data_a: int, id_b: int, data_b: int) -> bool:
	return id_a == id_b and data_a == data_b and not Items.is_damageable(id_a) and Items.max_stack(id_a) > 1


## Добавляет предметы (сначала в существующие стопки, затем в пустые слоты основной части).
## Возвращает количество, которое не поместилось.
func add_item(id: int, count: int, data: int = 0) -> int:
	if id == 0 or count <= 0:
		return 0
	var limit := mini(size, SIZE)
	var max_s := Items.max_stack(id)
	for i in limit:
		if count == 0:
			break
		if counts[i] > 0 and stacks_with(ids[i], datas[i], id, data) and counts[i] < max_s:
			var add := mini(count, max_s - counts[i])
			counts[i] += add
			count -= add
	for i in limit:
		if count == 0:
			break
		if counts[i] <= 0:
			var add := mini(count, max_s)
			ids[i] = id
			counts[i] = add
			datas[i] = data
			count -= add
	changed.emit()
	return count


## Количество предметов id (data < 0 — любые данные).
func count_of(id: int, data: int = -1) -> int:
	var total := 0
	for i in mini(size, SIZE):
		if ids[i] == id and counts[i] > 0 and (data < 0 or datas[i] == data):
			total += counts[i]
	return total


## Убирает предметы из любых слотов (начиная с рюкзака). false — если предметов не хватает.
func remove_item(id: int, count: int, data: int = -1) -> bool:
	if count_of(id, data) < count:
		return false
	for i in range(mini(size, SIZE) - 1, -1, -1):
		if count == 0:
			break
		if ids[i] == id and counts[i] > 0 and (data < 0 or datas[i] == data):
			var take := mini(count, counts[i])
			counts[i] -= take
			count -= take
			if counts[i] == 0:
				ids[i] = 0
				datas[i] = 0
	changed.emit()
	return true


func consume_selected(n: int = 1) -> void:
	consume_slot(selected, n)


func consume_slot(slot: int, n: int = 1) -> void:
	if counts[slot] <= 0:
		return
	counts[slot] = maxi(counts[slot] - n, 0)
	if counts[slot] == 0:
		ids[slot] = 0
		datas[slot] = 0
	changed.emit()


## Заменяет предмет в руке (например, ведро воды → пустое ведро).
func replace_selected(id: int, data: int = 0) -> void:
	if counts[selected] > 1:
		counts[selected] -= 1
		if add_item(id, 1, data) > 0:
			counts[selected] += 1
			return
	else:
		ids[selected] = id
		counts[selected] = 1
		datas[selected] = data
	changed.emit()


## Износ предмета в слоте. true — предмет сломался.
func damage_slot(slot: int, amount: int = 1) -> bool:
	var id := ids[slot]
	var max_d := Items.max_damage(id)
	if max_d <= 0 or counts[slot] <= 0:
		return false
	# Прочность (Unbreaking): износ проходит с шансом 1 / (уровень + 1).
	var unbreaking := Enchantments.level_of(datas[slot], Enchantments.UNBREAKING)
	if unbreaking > 0 and randi() % (unbreaking + 1) != 0:
		return false
	datas[slot] = Enchantments.with_damage(datas[slot], Enchantments.damage_of(datas[slot]) + amount)
	if Enchantments.damage_of(datas[slot]) >= max_d:
		ids[slot] = 0
		counts[slot] = 0
		datas[slot] = 0
		changed.emit()
		return true
	changed.emit()
	return false


## Перемещение из слота a в слот b: одинаковые предметы складываются, разные — меняются местами.
func move_slot(a: int, b: int) -> void:
	if a == b:
		return
	if counts[a] > 0 and counts[b] > 0 and stacks_with(ids[a], datas[a], ids[b], datas[b]):
		var add := mini(counts[a], Items.max_stack(ids[b]) - counts[b])
		counts[b] += add
		counts[a] -= add
		if counts[a] == 0:
			ids[a] = 0
			datas[a] = 0
	else:
		var tid := ids[a]
		var tc := counts[a]
		var td := datas[a]
		ids[a] = ids[b]
		counts[a] = counts[b]
		datas[a] = datas[b]
		ids[b] = tid
		counts[b] = tc
		datas[b] = td
	changed.emit()


func clear() -> void:
	ids.fill(0)
	counts.fill(0)
	datas.fill(0)
	changed.emit()


func fill_creative_hotbar() -> void:
	for i in HOTBAR_SIZE:
		ids[i] = CREATIVE_HOTBAR[i][0]
		datas[i] = CREATIVE_HOTBAR[i][1]
		counts[i] = 1
	changed.emit()


func is_empty() -> bool:
	for c in counts:
		if c > 0:
			return false
	return true


## Очки брони (0–20) от надетых вещей.
func armor_points() -> int:
	var total := 0
	if size < TOTAL:
		return 0
	for i in range(ARMOR_START, TOTAL):
		if counts[i] > 0:
			total += Items.armor_points(ids[i])
	return total


## Износ брони при получении урона (как в оригинале: 1 единица на каждые 4 урона, минимум 1).
func damage_armor(amount: int) -> void:
	if size < TOTAL:
		return
	var wear := maxi(amount / 4, 1)
	for i in range(ARMOR_START, TOTAL):
		if counts[i] > 0:
			damage_slot(i, wear)


func to_data() -> Array:
	var out := []
	for i in size:
		out.append([ids[i], counts[i], datas[i]])
	return out


## legacy — данные из сохранения старой версии (другие номера блоков).
func from_data(data: Array, legacy := false) -> void:
	ids.fill(0)
	counts.fill(0)
	datas.fill(0)
	for i in mini(data.size(), size):
		var slot: Variant = data[i]
		if slot is Array and slot.size() >= 2:
			var id := int(slot[0])
			var c := int(slot[1])
			var d := int(slot[2]) if slot.size() >= 3 else 0
			if legacy:
				id = V1_IDS[id] if id >= 0 and id < V1_IDS.size() else 0
			if Items.exists(id) and c > 0:
				ids[i] = id
				counts[i] = mini(c, Items.max_stack(id))
				datas[i] = d
	changed.emit()
