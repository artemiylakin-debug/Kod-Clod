class_name Enchantments
extends RefCounted
## Зачарования 1.2. Хранятся в данных предмета (data) поверх износа: биты 0–11 — износ,
## с бита 16 — до пяти зачарований по 8 бит (5 бит — номер в таблице, 3 бита — уровень − 1).
## Стол зачарований: три варианта, уровни до 50 при 15 книжных полках вокруг (как в 1.0–1.2).

const DAMAGE_MASK := 0xFFF
const SHIFT := 16
const SLOTS := 5

enum {
	NONE, PROTECTION, FIRE_PROTECTION, FEATHER_FALLING, BLAST_PROTECTION, PROJECTILE_PROTECTION, RESPIRATION,
	AQUA_AFFINITY, SHARPNESS, SMITE, BANE_OF_ARTHROPODS, KNOCKBACK, FIRE_ASPECT, LOOTING, EFFICIENCY,
	SILK_TOUCH, UNBREAKING, FORTUNE, POWER, PUNCH, FLAME, INFINITY,
}

## Тип предмета, к которому применимо зачарование.
enum { T_ARMOR, T_HELMET, T_BOOTS, T_WEAPON, T_TOOL, T_BOW, T_DAMAGEABLE }

## [название, максимальный уровень, вес, тип, группа несовместимости (−1 — нет), id в Minecraft]
const INFO := [
	["", 0, 0, -1, -1, -1],
	["Защита", 4, 10, T_ARMOR, 1, 0],
	["Огнеупорность", 4, 5, T_ARMOR, 1, 1],
	["Невесомость", 4, 5, T_BOOTS, -1, 2],
	["Взрывоустойчивость", 4, 2, T_ARMOR, 1, 3],
	["Защита от снарядов", 4, 5, T_ARMOR, 1, 4],
	["Подводное дыхание", 3, 2, T_HELMET, -1, 5],
	["Подводник", 1, 2, T_HELMET, -1, 6],
	["Острота", 5, 10, T_WEAPON, 2, 16],
	["Небесная кара", 5, 5, T_WEAPON, 2, 17],
	["Бич членистоногих", 5, 5, T_WEAPON, 2, 18],
	["Отбрасывание", 2, 5, T_WEAPON, -1, 19],
	["Заговор огня", 2, 2, T_WEAPON, -1, 20],
	["Добыча", 3, 2, T_WEAPON, -1, 21],
	["Эффективность", 5, 10, T_TOOL, -1, 32],
	["Шёлковое касание", 1, 1, T_TOOL, 3, 33],
	["Прочность", 3, 5, T_TOOL, -1, 34],
	["Удача", 3, 2, T_TOOL, 3, 35],
	["Сила", 5, 10, T_BOW, -1, 48],
	["Откидывание", 2, 2, T_BOW, -1, 49],
	["Горящая стрела", 1, 2, T_BOW, -1, 50],
	["Бесконечность", 1, 1, T_BOW, -1, 51],
]

const ROMAN := ["", "I", "II", "III", "IV", "V"]


static func damage_of(data: int) -> int:
	return data & DAMAGE_MASK


static func with_damage(data: int, damage: int) -> int:
	return (data & ~DAMAGE_MASK) | clampi(damage, 0, DAMAGE_MASK)


## Список [номер, уровень] зачарований предмета.
static func list(data: int) -> Array:
	var out := []
	for k in SLOTS:
		var e := (data >> (SHIFT + k * 8)) & 0xFF
		if e != 0:
			out.append([e & 31, (e >> 5) + 1])
	return out


static func is_enchanted(data: int) -> bool:
	return (data >> SHIFT) != 0


static func level_of(data: int, ench: int) -> int:
	for k in SLOTS:
		var e := (data >> (SHIFT + k * 8)) & 0xFF
		if e != 0 and (e & 31) == ench:
			return (e >> 5) + 1
	return 0


static func add(data: int, ench: int, level: int) -> int:
	for k in SLOTS:
		var shift := SHIFT + k * 8
		if (data >> shift) & 0xFF == 0:
			return data | (((ench & 31) | ((clampi(level, 1, 8) - 1) << 5)) << shift)
	return data


static func name_of(ench: int, level: int) -> String:
	var n: String = INFO[ench][0]
	if int(INFO[ench][1]) > 1:
		n += " " + (ROMAN[level] if level < ROMAN.size() else str(level))
	return n


## Подпись для подсказки: названия зачарований через запятую.
static func describe(data: int) -> String:
	var parts := PackedStringArray()
	for e: Array in list(data):
		parts.append(name_of(int(e[0]), int(e[1])))
	return ", ".join(parts)


# --- Применимость и зачаровываемость ---------------------------------------------

## Зачаровываемость материала (1.2): дерево 15, камень 5, железо 14, алмаз 10, золото 22;
## броня: кожа 15, кольчуга 12, железо 9, алмаз 10, золото 25; лук 1.
static func enchantability(item: int) -> int:
	if item >= Items.LEATHER_HELMET and item <= Items.GOLDEN_BOOTS:
		@warning_ignore("integer_division")
		return [15, 12, 9, 10, 25][(item - Items.LEATHER_HELMET) / 4]
	if item == Items.BOW:
		return 1
	if item in [Items.WOODEN_SWORD, Items.WOODEN_SHOVEL, Items.WOODEN_PICKAXE, Items.WOODEN_AXE]:
		return 15
	if item in [Items.STONE_SWORD, Items.STONE_SHOVEL, Items.STONE_PICKAXE, Items.STONE_AXE]:
		return 5
	if item in [Items.IRON_SWORD, Items.IRON_SHOVEL, Items.IRON_PICKAXE, Items.IRON_AXE]:
		return 14
	if item in [Items.DIAMOND_SWORD, Items.DIAMOND_SHOVEL, Items.DIAMOND_PICKAXE, Items.DIAMOND_AXE]:
		return 10
	if item in [Items.GOLDEN_SWORD, Items.GOLDEN_SHOVEL, Items.GOLDEN_PICKAXE, Items.GOLDEN_AXE]:
		return 22
	return 0


static func applies(ench: int, item: int) -> bool:
	match int(INFO[ench][3]):
		T_ARMOR:
			return Items.armor_slot(item) >= 0
		T_HELMET:
			return Items.armor_slot(item) == 0
		T_BOOTS:
			return Items.armor_slot(item) == 3
		T_WEAPON:
			return Items.is_sword(item)
		T_TOOL:
			var t := Items.tool_kind(item)
			return t == Blocks.TOOL_PICKAXE or t == Blocks.TOOL_AXE or t == Blocks.TOOL_SHOVEL \
				or (ench == UNBREAKING and (Items.is_sword(item) or Items.armor_slot(item) >= 0 or item == Items.BOW))
		T_BOW:
			return item == Items.BOW
	return false


## Диапазон «модифицированного уровня», при котором зачарование уровня lvl доступно (формулы 1.2).
static func _range(ench: int, lvl: int) -> Vector2i:
	match ench:
		PROTECTION:
			return Vector2i(1 + (lvl - 1) * 11, 1 + (lvl - 1) * 11 + 20)
		FIRE_PROTECTION:
			return Vector2i(10 + (lvl - 1) * 8, 10 + (lvl - 1) * 8 + 12)
		FEATHER_FALLING:
			return Vector2i(5 + (lvl - 1) * 6, 5 + (lvl - 1) * 6 + 10)
		BLAST_PROTECTION:
			return Vector2i(5 + (lvl - 1) * 8, 5 + (lvl - 1) * 8 + 12)
		PROJECTILE_PROTECTION:
			return Vector2i(3 + (lvl - 1) * 6, 3 + (lvl - 1) * 6 + 15)
		RESPIRATION:
			return Vector2i(10 * lvl, 10 * lvl + 30)
		AQUA_AFFINITY:
			return Vector2i(1, 41)
		SHARPNESS:
			return Vector2i(1 + (lvl - 1) * 11, 1 + (lvl - 1) * 11 + 20)
		SMITE, BANE_OF_ARTHROPODS:
			return Vector2i(5 + (lvl - 1) * 8, 5 + (lvl - 1) * 8 + 20)
		KNOCKBACK:
			return Vector2i(5 + 20 * (lvl - 1), 5 + 20 * (lvl - 1) + 50)
		FIRE_ASPECT, LOOTING:
			return Vector2i(10 + 20 * (lvl - 1), 10 + 20 * (lvl - 1) + 50)
		EFFICIENCY:
			return Vector2i(1 + 15 * (lvl - 1), 1 + 15 * (lvl - 1) + 50)
		SILK_TOUCH:
			return Vector2i(15, 65)
		UNBREAKING:
			return Vector2i(5 + (lvl - 1) * 10, 5 + (lvl - 1) * 10 + 50)
		FORTUNE:
			return Vector2i(15 + (lvl - 1) * 9, 15 + (lvl - 1) * 9 + 50)
		POWER:
			return Vector2i(1 + (lvl - 1) * 10, 1 + (lvl - 1) * 10 + 15)
		PUNCH:
			return Vector2i(12 + (lvl - 1) * 20, 12 + (lvl - 1) * 20 + 25)
		FLAME, INFINITY:
			return Vector2i(20, 50)
	return Vector2i(999, 0)


## Уровни трёх вариантов стола (слоты 0–2) при данном числе книжных полок.
static func table_levels(item: int, shelves: int, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = [0, 0, 0]
	if enchantability(item) <= 0:
		return out
	shelves = mini(shelves, 15)
	# В 1.0–1.2 верхний вариант доходил до 50.
	var base := rng.randi_range(1, 5) + (shelves >> 1) + rng.randi_range(0, shelves)
	var top := maxi(roundi(base * 50.0 / 27.0), 1)
	@warning_ignore("integer_division")
	out[0] = maxi(top / 3, 1)
	@warning_ignore("integer_division")
	out[1] = maxi(top * 2 / 3 + 1, 1)
	out[2] = maxi(top, out[1])
	return out


## Зачаровать предмет на уровне level: возвращает новые данные (износ сохраняется).
static func enchant(item: int, data: int, level: int, rng: RandomNumberGenerator) -> int:
	var ench := enchantability(item)
	if ench <= 0:
		return data
	# Модифицированный уровень: уровень + случайная прибавка от зачаровываемости, ±25 %.
	@warning_ignore("integer_division")
	var bonus := rng.randi_range(0, ench / 2) + rng.randi_range(0, ench / 2) + 1
	var mod := level + bonus
	var factor := 1.0 + (rng.randf() + rng.randf() - 1.0) * 0.25
	mod = maxi(roundi(mod * factor), 1)
	var chosen := []
	var pool := _candidates(item, mod)
	while not pool.is_empty() and chosen.size() < SLOTS:
		var pick: Array = _weighted(pool, rng)
		chosen.append(pick)
		# Несовместимые и уже выбранные — из списка.
		var group := int(INFO[int(pick[0])][4])
		var rest := []
		for c: Array in pool:
			if int(c[0]) == int(pick[0]):
				continue
			if group >= 0 and int(INFO[int(c[0])][4]) == group:
				continue
			rest.append(c)
		pool = rest
		# Шанс ещё одного зачарования падает с уровнем.
		if rng.randi_range(0, 50) > mod:
			break
		@warning_ignore("integer_division")
		mod = mod / 2
	var out := data & DAMAGE_MASK
	for c: Array in chosen:
		out = add(out, int(c[0]), int(c[1]))
	return out


static func _candidates(item: int, mod: int) -> Array:
	var out := []
	for e in range(1, INFO.size()):
		if not applies(e, item):
			continue
		for lvl in range(int(INFO[e][1]), 0, -1):
			var r := _range(e, lvl)
			if mod >= r.x and mod <= r.y:
				out.append([e, lvl])
				break
	return out


static func _weighted(pool: Array, rng: RandomNumberGenerator) -> Array:
	var total := 0
	for c: Array in pool:
		total += int(INFO[int(c[0])][2])
	var r := rng.randi_range(0, maxi(total - 1, 0))
	for c: Array in pool:
		r -= int(INFO[int(c[0])][2])
		if r < 0:
			return c
	return pool[0]


## Книжные полки вокруг стола (кольцо на расстоянии 2, на уровне стола и выше; между ними — воздух).
static func count_shelves(world: World, p: Vector3i) -> int:
	var n := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dz != 0) and world.get_block_v(p + Vector3i(dx, 0, dz)) == Blocks.AIR \
					and world.get_block_v(p + Vector3i(dx, 1, dz)) == Blocks.AIR:
				for dy in 2:
					if world.get_block_v(p + Vector3i(dx * 2, dy, dz * 2)) == Blocks.BOOKSHELF:
						n += 1
					if dx != 0 and dz != 0:
						if world.get_block_v(p + Vector3i(dx * 2, dy, dz)) == Blocks.BOOKSHELF:
							n += 1
						if world.get_block_v(p + Vector3i(dx, dy, dz * 2)) == Blocks.BOOKSHELF:
							n += 1
	return n


# --- Действие зачарований ----------------------------------------------------------

## Сумма уровней зачарования ench на надетой броне.
static func armor_level(inv: Inventory, ench: int) -> int:
	var total := 0
	for i in range(Inventory.ARMOR_START, Inventory.TOTAL):
		if inv.counts[i] > 0:
			total += level_of(inv.datas[i], ench)
	return total


## Множитель урона после защитных зачарований (до −80 %).
static func protection_factor(inv: Inventory, source: String) -> float:
	if inv.size < Inventory.TOTAL:
		return 1.0
	var epf := 0.0
	for i in range(Inventory.ARMOR_START, Inventory.TOTAL):
		if inv.counts[i] <= 0:
			continue
		var d := inv.datas[i]
		epf += _epf(level_of(d, PROTECTION), 0.75)
		match source:
			"fire", "lava":
				epf += _epf(level_of(d, FIRE_PROTECTION), 1.25)
			"fall":
				epf += _epf(level_of(d, FEATHER_FALLING), 2.5)
			"explosion":
				epf += _epf(level_of(d, BLAST_PROTECTION), 1.5)
			"arrow":
				epf += _epf(level_of(d, PROJECTILE_PROTECTION), 1.5)
	epf = minf(epf, 20.0)
	return 1.0 - epf * 0.04


static func _epf(level: int, k: float) -> float:
	if level <= 0:
		return 0.0
	return floorf((6.0 + level * level) * k / 3.0)
