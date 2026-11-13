class_name Loot
extends RefCounted
## Содержимое сундуков построек 1.2 (формат Inventory.to_data(): [[id, количество, данные] × 27]).

const SLOTS := 27


static func _empty() -> Array:
	var out := []
	for i in SLOTS:
		out.append([0, 0, 0])
	return out


static func _ri(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 0:
		return 0
	return int(rng.randi() % n)


## Сундук данжа (pickCheckLootItem): 8 попыток, каждая кладёт предмет в случайную ячейку.
static func dungeon_chest(rng: RandomNumberGenerator) -> Array:
	var out := _empty()
	for i in 8:
		var item: Array = []
		match _ri(rng, 11):
			0:
				item = [Items.SADDLE, 1, 0]
			1:
				item = [Items.IRON_INGOT, _ri(rng, 4) + 1, 0]
			2:
				item = [Items.BREAD, 1, 0]
			3:
				item = [Items.WHEAT, _ri(rng, 4) + 1, 0]
			4:
				item = [Items.GUNPOWDER, _ri(rng, 4) + 1, 0]
			5:
				item = [Items.STRING, _ri(rng, 4) + 1, 0]
			6:
				item = [Items.BUCKET, 1, 0]
			7:
				if _ri(rng, 100) == 0:
					item = [Items.GOLDEN_APPLE, 1, 0]
			8:
				if _ri(rng, 2) == 0:
					item = [Items.REDSTONE, _ri(rng, 4) + 1, 0]
			9:
				if _ri(rng, 10) == 0:
					item = [Items.RECORD_13 + _ri(rng, 2), 1, 0]
			10:
				item = [Items.DYE, 1, Items.DYE_COCOA]
		if not item.is_empty():
			out[_ri(rng, SLOTS)] = item
	return out


## Взвешенная таблица: [[id, данные, мин, макс, вес], …]; count — число попыток.
static func weighted(rng: RandomNumberGenerator, table: Array, count: int) -> Array:
	var out := _empty()
	var total := 0
	for e: Array in table:
		total += int(e[4])
	for i in count:
		var r := _ri(rng, total)
		for e: Array in table:
			r -= int(e[4])
			if r < 0:
				var lo: int = e[2]
				var hi: int = e[3]
				out[_ri(rng, SLOTS)] = [int(e[0]), lo + _ri(rng, hi - lo + 1), int(e[1])]
				break
	return out


## Кузница деревни (StructureVillagePieces.House2): 3–7 предметов.
static func blacksmith(rng: RandomNumberGenerator) -> Array:
	return weighted(rng, [
		[Items.DIAMOND, 0, 1, 3, 3], [Items.IRON_INGOT, 0, 1, 5, 10], [Items.GOLD_INGOT, 0, 1, 3, 5],
		[Items.BREAD, 0, 1, 3, 15], [Items.APPLE, 0, 1, 3, 15], [Items.IRON_PICKAXE, 0, 1, 1, 5],
		[Items.IRON_SWORD, 0, 1, 1, 5], [Items.IRON_CHESTPLATE, 0, 1, 1, 5], [Items.IRON_HELMET, 0, 1, 1, 5],
		[Items.IRON_LEGGINGS, 0, 1, 1, 5], [Items.IRON_BOOTS, 0, 1, 1, 5], [Blocks.OBSIDIAN, 0, 3, 7, 5],
		[Blocks.SAPLING, 0, 3, 7, 5],
	], 3 + _ri(rng, 5))


## Заброшенная шахта (StructureMineshaftPieces): 3–6 предметов.
static func mineshaft(rng: RandomNumberGenerator) -> Array:
	return weighted(rng, [
		[Items.IRON_INGOT, 0, 1, 5, 10], [Items.GOLD_INGOT, 0, 1, 3, 5], [Items.REDSTONE, 0, 4, 9, 5],
		[Items.DYE, Items.DYE_LAPIS, 4, 9, 5], [Items.DIAMOND, 0, 1, 2, 3], [Items.COAL, 0, 3, 8, 10],
		[Items.BREAD, 0, 1, 3, 15], [Items.IRON_PICKAXE, 0, 1, 1, 1], [Blocks.RAIL, 0, 4, 8, 1],
		[Items.MELON_SEEDS, 0, 2, 4, 10], [Items.PUMPKIN_SEEDS, 0, 2, 4, 10],
	], 3 + _ri(rng, 4))


## Коридор крепости (StrongholdChestCorridor): 2–4 предмета.
static func stronghold_corridor(rng: RandomNumberGenerator) -> Array:
	return weighted(rng, [
		[Items.ENDER_PEARL, 0, 1, 1, 10], [Items.DIAMOND, 0, 1, 3, 3], [Items.IRON_INGOT, 0, 1, 5, 10],
		[Items.GOLD_INGOT, 0, 1, 3, 5], [Items.REDSTONE, 0, 4, 9, 5], [Items.BREAD, 0, 1, 3, 15],
		[Items.APPLE, 0, 1, 3, 15], [Items.IRON_PICKAXE, 0, 1, 1, 5], [Items.IRON_SWORD, 0, 1, 1, 5],
		[Items.IRON_CHESTPLATE, 0, 1, 1, 5], [Items.IRON_HELMET, 0, 1, 1, 5], [Items.IRON_LEGGINGS, 0, 1, 1, 5],
		[Items.IRON_BOOTS, 0, 1, 1, 5], [Items.GOLDEN_APPLE, 0, 1, 1, 1],
	], 2 + _ri(rng, 3))


## Перекрёсток крепости (StrongholdRoomCrossing): 1–4 предмета.
static func stronghold_crossing(rng: RandomNumberGenerator) -> Array:
	return weighted(rng, [
		[Items.IRON_INGOT, 0, 1, 5, 10], [Items.GOLD_INGOT, 0, 1, 3, 5], [Items.REDSTONE, 0, 4, 9, 5],
		[Items.COAL, 0, 3, 8, 10], [Items.BREAD, 0, 1, 3, 15], [Items.APPLE, 0, 1, 3, 15],
		[Items.IRON_PICKAXE, 0, 1, 1, 1],
	], 1 + _ri(rng, 4))


## Библиотека крепости: книги, бумага, карта, компас.
static func stronghold_library(rng: RandomNumberGenerator) -> Array:
	return weighted(rng, [
		[Items.BOOK, 0, 1, 3, 20], [Items.PAPER, 0, 2, 7, 20], [Items.MAP, 0, 1, 1, 1], [Items.COMPASS, 0, 1, 1, 1],
	], 1 + _ri(rng, 4))
