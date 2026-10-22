class_name Recipes
extends RefCounted
## Рецепты Minecraft 1.2: крафт по форме (с зеркальным отражением) и без формы, переплавка в печи.
## Сетка крафта — массив [id, data] размером 2×2 (инвентарь) или 3×3 (верстак).

const ANY := -1

## Рецепты по форме: {w, h, cells: [[id, data]…], out: [id, count, data]}.
static var shaped: Array[Dictionary] = []
## Бесформенные: {items: [[id, data]…], out: [id, count, data]}.
static var shapeless: Array[Dictionary] = []
## Переплавка: id → [результат, количество, данные, опыт]; ключ — id*16 + data или id*16 + 15 для любых данных.
static var smelting: Dictionary = {}


static func _static_init() -> void:
	_register()
	_register_smelting()


# --- Регистрация -----------------------------------------------------------

static func _sh(out: Array, pattern: Array, keys: Dictionary) -> void:
	var h := pattern.size()
	var w := 0
	for row: String in pattern:
		w = maxi(w, row.length())
	var cells := []
	for row: String in pattern:
		for x in w:
			var ch := row[x] if x < row.length() else " "
			if ch == " ":
				cells.append([0, 0])
			else:
				var k: Variant = keys[ch]
				if k is Array:
					cells.append(k)
				else:
					cells.append([int(k), ANY])
	shaped.append({"w": w, "h": h, "cells": cells, "out": out})


static func _sl(out: Array, items: Array) -> void:
	var list := []
	for it: Variant in items:
		list.append(it if it is Array else [int(it), ANY])
	shapeless.append({"items": list, "out": out})


static func _register() -> void:
	var P := [Blocks.PLANKS, ANY]
	var S := Items.STICK
	var C := Blocks.COBBLESTONE
	var I := Items.IRON_INGOT
	var G := Items.GOLD_INGOT
	var D := Items.DIAMOND
	var R := Items.REDSTONE
	# Дерево.
	for w in 4:
		_sl([Blocks.PLANKS, 4, w], [[Blocks.LOG, w]])
	_sh([S, 4, 0], ["P", "P"], {"P": P})
	_sh([Blocks.TORCH, 4, 0], ["C", "S"], {"C": [Items.COAL, 0], "S": S})
	_sh([Blocks.TORCH, 4, 0], ["C", "S"], {"C": [Items.COAL, 1], "S": S})
	_sh([Blocks.CRAFTING_TABLE, 1, 0], ["PP", "PP"], {"P": P})
	_sh([Blocks.FURNACE, 1, 0], ["CCC", "C C", "CCC"], {"C": C})
	_sh([Blocks.CHEST, 1, 0], ["PPP", "P P", "PPP"], {"P": P})
	_sh([Blocks.LADDER, 2, 0], ["S S", "SSS", "S S"], {"S": S})
	_sh([Blocks.FENCE, 2, 0], ["SSS", "SSS"], {"S": S})
	_sh([Blocks.FENCE_GATE, 1, 0], ["SPS", "SPS"], {"S": S, "P": P})
	_sh([Items.WOODEN_DOOR, 1, 0], ["PP", "PP", "PP"], {"P": P})
	_sh([Items.IRON_DOOR, 1, 0], ["II", "II", "II"], {"I": I})
	_sh([Blocks.TRAPDOOR, 2, 0], ["PPP", "PPP"], {"P": P})
	_sh([Items.SIGN, 1, 0], ["PPP", "PPP", " S "], {"P": P, "S": S})
	_sh([Items.BOAT, 1, 0], ["P P", "PPP"], {"P": P})
	_sh([Items.BOWL, 4, 0], ["P P", " P "], {"P": P})
	_sh([Blocks.WOODEN_PLATE, 1, 0], ["PP"], {"P": P})
	_sh([Blocks.STONE_PLATE, 1, 0], ["SS"], {"S": [Blocks.STONE, 0]})
	_sh([Blocks.STONE_BUTTON, 1, 0], ["S", "S"], {"S": [Blocks.STONE, 0]})
	_sh([Blocks.LEVER, 1, 0], ["S", "C"], {"S": S, "C": C})
	_sh([Blocks.OAK_STAIRS, 4, 0], ["P  ", "PP ", "PPP"], {"P": P})
	_sh([Blocks.COBBLESTONE_STAIRS, 4, 0], ["C  ", "CC ", "CCC"], {"C": C})
	_sh([Blocks.BRICK_STAIRS, 4, 0], ["C  ", "CC ", "CCC"], {"C": Blocks.BRICKS})
	_sh([Blocks.STONE_BRICK_STAIRS, 4, 0], ["C  ", "CC ", "CCC"], {"C": Blocks.STONE_BRICKS})
	_sh([Blocks.NETHER_BRICK_STAIRS, 4, 0], ["C  ", "CC ", "CCC"], {"C": Blocks.NETHER_BRICK})
	_sh([Blocks.NETHER_FENCE, 6, 0], ["NNN", "NNN"], {"N": Blocks.NETHER_BRICK})
	# Плиты: 0 камень, 1 песчаник, 2 дерево, 3 булыжник, 4 кирпич, 5 каменные кирпичи.
	_sh([Blocks.SLAB, 3, 0], ["SSS"], {"S": [Blocks.STONE, 0]})
	_sh([Blocks.SLAB, 3, 1], ["SSS"], {"S": [Blocks.SANDSTONE, ANY]})
	_sh([Blocks.SLAB, 3, 2], ["SSS"], {"S": P})
	_sh([Blocks.SLAB, 3, 3], ["SSS"], {"S": C})
	_sh([Blocks.SLAB, 3, 4], ["SSS"], {"S": Blocks.BRICKS})
	_sh([Blocks.SLAB, 3, 5], ["SSS"], {"S": [Blocks.STONE_BRICKS, ANY]})
	# Механизмы и редстоун.
	_sh([Blocks.REDSTONE_TORCH, 1, 0], ["R", "S"], {"R": R, "S": S})
	_sh([Items.REPEATER, 1, 0], ["TRT", "SSS"], {"T": Blocks.REDSTONE_TORCH, "R": R, "S": [Blocks.STONE, 0]})
	_sh([Blocks.DISPENSER, 1, 0], ["CCC", "CBC", "CRC"], {"C": C, "B": Items.BOW, "R": R})
	_sh([Blocks.NOTE_BLOCK, 1, 0], ["PPP", "PRP", "PPP"], {"P": P, "R": R})
	_sh([Blocks.JUKEBOX, 1, 0], ["PPP", "PDP", "PPP"], {"P": P, "D": D})
	_sh([Blocks.PISTON, 1, 0], ["PPP", "CIC", "CRC"], {"P": P, "C": C, "I": I, "R": R})
	_sh([Blocks.STICKY_PISTON, 1, 0], ["S", "P"], {"S": Items.SLIME_BALL, "P": Blocks.PISTON})
	_sh([Blocks.RAIL, 16, 0], ["I I", "ISI", "I I"], {"I": I, "S": S})
	_sh([Blocks.POWERED_RAIL, 6, 0], ["G G", "GSG", "GRG"], {"G": G, "S": S, "R": R})
	_sh([Blocks.DETECTOR_RAIL, 6, 0], ["I I", "IPI", "IRI"], {"I": I, "P": Blocks.STONE_PLATE, "R": R})
	_sh([Blocks.REDSTONE_LAMP, 1, 0], [" R ", "RGR", " R "], {"R": R, "G": Blocks.GLOWSTONE})
	_sh([Items.MINECART, 1, 0], ["I I", "III"], {"I": I})
	_sh([Items.CHEST_MINECART, 1, 0], ["C", "M"], {"C": Blocks.CHEST, "M": Items.MINECART})
	_sh([Items.FURNACE_MINECART, 1, 0], ["F", "M"], {"F": Blocks.FURNACE, "M": Items.MINECART})
	# Снаряжение.
	_sh([Items.BUCKET, 1, 0], ["I I", " I "], {"I": I})
	_sl([Items.FLINT_AND_STEEL, 1, 0], [I, Items.FLINT])
	_sh([Items.SHEARS, 1, 0], [" I", "I "], {"I": I})
	_sh([Items.COMPASS, 1, 0], [" I ", "IRI", " I "], {"I": I, "R": R})
	_sh([Items.CLOCK, 1, 0], [" G ", "GRG", " G "], {"G": G, "R": R})
	_sh([Items.MAP, 1, 0], ["PPP", "PCP", "PPP"], {"P": Items.PAPER, "C": Items.COMPASS})
	_sh([Items.FISHING_ROD, 1, 0], ["  S", " ST", "S T"], {"S": S, "T": Items.STRING})
	_sh([Items.BOW, 1, 0], [" ST", "S T", " ST"], {"S": S, "T": Items.STRING})
	_sh([Items.ARROW, 4, 0], ["F", "S", "E"], {"F": Items.FLINT, "S": S, "E": Items.FEATHER})
	# Инструменты и оружие.
	var mats := [[P, 0], [C, 1], [I, 2], [D, 3], [G, 4]]
	var tool_ids := [
		[Items.WOODEN_PICKAXE, Items.STONE_PICKAXE, Items.IRON_PICKAXE, Items.DIAMOND_PICKAXE, Items.GOLDEN_PICKAXE],
		[Items.WOODEN_AXE, Items.STONE_AXE, Items.IRON_AXE, Items.DIAMOND_AXE, Items.GOLDEN_AXE],
		[Items.WOODEN_SHOVEL, Items.STONE_SHOVEL, Items.IRON_SHOVEL, Items.DIAMOND_SHOVEL, Items.GOLDEN_SHOVEL],
		[Items.WOODEN_HOE, Items.STONE_HOE, Items.IRON_HOE, Items.DIAMOND_HOE, Items.GOLDEN_HOE],
		[Items.WOODEN_SWORD, Items.STONE_SWORD, Items.IRON_SWORD, Items.DIAMOND_SWORD, Items.GOLDEN_SWORD],
	]
	var patterns := [["MMM", " S ", " S "], ["MM", "MS", " S"], ["M", "S", "S"], ["MM", " S", " S"], ["M", "M", "S"]]
	for m: Array in mats:
		var k: int = m[1]
		for t in 5:
			_sh([tool_ids[t][k], 1, 0], patterns[t], {"M": m[0], "S": S})
	# Броня (кольчугу в 1.2 не скрафтить).
	var armor_mats := [[Items.LEATHER, Items.LEATHER_HELMET], [I, Items.IRON_HELMET], [D, Items.DIAMOND_HELMET], [G, Items.GOLDEN_HELMET]]
	var armor_patterns := [["MMM", "M M"], ["M M", "MMM", "MMM"], ["MMM", "M M", "M M"], ["M M", "M M"]]
	for a: Array in armor_mats:
		for slot in 4:
			_sh([int(a[1]) + slot, 1, 0], armor_patterns[slot], {"M": a[0]})
	# Блоки из ресурсов и обратно.
	for pair: Array in [[Blocks.IRON_BLOCK, I], [Blocks.GOLD_BLOCK, G], [Blocks.DIAMOND_BLOCK, D], [Blocks.LAPIS_BLOCK, [Items.DYE, 4]]]:
		_sh([pair[0], 1, 0], ["XXX", "XXX", "XXX"], {"X": pair[1]})
		var item: Variant = pair[1]
		if item is Array:
			_sl([item[0], 9, item[1]], [pair[0]])
		else:
			_sl([item, 9, 0], [pair[0]])
	_sh([Blocks.GLOWSTONE, 1, 0], ["XX", "XX"], {"X": Items.GLOWSTONE_DUST})
	_sh([Blocks.SNOW, 1, 0], ["XX", "XX"], {"X": Items.SNOWBALL})
	_sh([Blocks.CLAY, 1, 0], ["XX", "XX"], {"X": Items.CLAY_BALL})
	_sh([Blocks.BRICKS, 1, 0], ["XX", "XX"], {"X": Items.BRICK})
	_sh([Blocks.WOOL, 1, 0], ["XX", "XX"], {"X": Items.STRING})
	_sh([Blocks.SANDSTONE, 1, 0], ["XX", "XX"], {"X": Blocks.SAND})
	_sh([Blocks.SANDSTONE, 4, 2], ["XX", "XX"], {"X": [Blocks.SANDSTONE, 0]})
	_sh([Blocks.SANDSTONE, 1, 1], ["X", "X"], {"X": [Blocks.SLAB, 1]})
	_sh([Blocks.STONE_BRICKS, 4, 0], ["XX", "XX"], {"X": [Blocks.STONE, 0]})
	_sh([Blocks.TNT, 1, 0], ["XSX", "SXS", "XSX"], {"X": Items.GUNPOWDER, "S": Blocks.SAND})
	_sh([Blocks.BOOKSHELF, 1, 0], ["PPP", "BBB", "PPP"], {"P": P, "B": Items.BOOK})
	_sh([Blocks.GLASS_PANE, 16, 0], ["GGG", "GGG"], {"G": Blocks.GLASS})
	_sh([Blocks.IRON_BARS, 16, 0], ["III", "III"], {"I": I})
	_sh([Blocks.JACK_O_LANTERN, 1, 0], ["P", "T"], {"P": Blocks.PUMPKIN, "T": Blocks.TORCH})
	_sh([Blocks.MELON, 1, 0], ["MMM", "MMM", "MMM"], {"M": Items.MELON})
	_sh([Items.GOLD_INGOT, 1, 0], ["NNN", "NNN", "NNN"], {"N": Items.GOLD_NUGGET})
	_sl([Items.GOLD_NUGGET, 9, 0], [G])
	# Еда.
	_sh([Items.BREAD, 1, 0], ["WWW"], {"W": Items.WHEAT})
	_sh([Items.COOKIE, 8, 0], ["WCW"], {"W": Items.WHEAT, "C": [Items.DYE, 3]})
	_sh([Items.CAKE, 1, 0], ["MMM", "SES", "WWW"], {"M": Items.MILK_BUCKET, "S": Items.SUGAR, "E": Items.EGG, "W": Items.WHEAT})
	_sh([Items.GOLDEN_APPLE, 1, 0], ["GGG", "GAG", "GGG"], {"G": Blocks.GOLD_BLOCK, "A": Items.APPLE})
	_sl([Items.MUSHROOM_STEW, 1, 0], [Items.BOWL, Blocks.RED_MUSHROOM, Blocks.BROWN_MUSHROOM])
	_sl([Items.SUGAR, 1, 0], [Items.REEDS])
	_sh([Items.PAPER, 3, 0], ["RRR"], {"R": Items.REEDS})
	_sh([Items.BOOK, 1, 0], ["P", "P", "P"], {"P": Items.PAPER})
	_sl([Items.MELON_SEEDS, 1, 0], [Items.MELON])
	_sl([Items.PUMPKIN_SEEDS, 4, 0], [Blocks.PUMPKIN])
	# Прочее.
	_sh([Items.BED, 1, 0], ["WWW", "PPP"], {"W": [Blocks.WOOL, ANY], "P": P})
	_sh([Items.PAINTING, 1, 0], ["SSS", "SWS", "SSS"], {"S": S, "W": [Blocks.WOOL, ANY]})
	_sh([Blocks.ENCHANTING_TABLE, 1, 0], [" B ", "DOD", "OOO"], {"B": Items.BOOK, "D": D, "O": Blocks.OBSIDIAN})
	_sh([Items.BREWING_STAND, 1, 0], [" B ", "CCC"], {"B": Items.BLAZE_ROD, "C": C})
	_sh([Items.CAULDRON, 1, 0], ["I I", "I I", "III"], {"I": I})
	_sh([Items.GLASS_BOTTLE, 3, 0], ["G G", " G "], {"G": Blocks.GLASS})
	_sl([Items.BLAZE_POWDER, 2, 0], [Items.BLAZE_ROD])
	_sl([Items.MAGMA_CREAM, 1, 0], [Items.SLIME_BALL, Items.BLAZE_POWDER])
	_sl([Items.FERMENTED_SPIDER_EYE, 1, 0], [Items.SPIDER_EYE, Blocks.BROWN_MUSHROOM, Items.SUGAR])
	_sh([Items.SPECKLED_MELON, 1, 0], ["NNN", "NMN", "NNN"], {"N": Items.GOLD_NUGGET, "M": Items.MELON})
	_sl([Items.ENDER_EYE, 1, 0], [Items.ENDER_PEARL, Items.BLAZE_POWDER])
	_sl([Items.FIRE_CHARGE, 3, 0], [Items.BLAZE_POWDER, [Items.COAL, ANY], Items.GUNPOWDER])
	# Красители.
	_sl([Items.DYE, 2, Items.DYE_RED], [Blocks.ROSE])
	_sl([Items.DYE, 2, Items.DYE_YELLOW], [Blocks.DANDELION])
	_sl([Items.DYE, 3, Items.DYE_BONE_MEAL], [Items.BONE])
	var mixes := [
		[Items.DYE_ORANGE, 2, [Items.DYE_RED, Items.DYE_YELLOW]],
		[Items.DYE_PINK, 2, [Items.DYE_RED, Items.DYE_BONE_MEAL]],
		[Items.DYE_LIGHT_BLUE, 2, [Items.DYE_LAPIS, Items.DYE_BONE_MEAL]],
		[Items.DYE_GRAY, 2, [Items.DYE_INK, Items.DYE_BONE_MEAL]],
		[Items.DYE_LIGHT_GRAY, 2, [Items.DYE_GRAY, Items.DYE_BONE_MEAL]],
		[Items.DYE_LIGHT_GRAY, 3, [Items.DYE_INK, Items.DYE_BONE_MEAL, Items.DYE_BONE_MEAL]],
		[Items.DYE_PURPLE, 2, [Items.DYE_LAPIS, Items.DYE_RED]],
		[Items.DYE_CYAN, 2, [Items.DYE_LAPIS, Items.DYE_GREEN]],
		[Items.DYE_LIME, 2, [Items.DYE_GREEN, Items.DYE_BONE_MEAL]],
		[Items.DYE_MAGENTA, 2, [Items.DYE_PURPLE, Items.DYE_PINK]],
		[Items.DYE_MAGENTA, 3, [Items.DYE_LAPIS, Items.DYE_RED, Items.DYE_PINK]],
		[Items.DYE_MAGENTA, 4, [Items.DYE_LAPIS, Items.DYE_RED, Items.DYE_RED, Items.DYE_BONE_MEAL]],
	]
	for mix: Array in mixes:
		var parts := []
		for d: int in mix[2]:
			parts.append([Items.DYE, d])
		_sl([Items.DYE, mix[1], mix[0]], parts)
	# Окраска шерсти: краситель (data d) + шерсть → шерсть цвета 15 − d.
	for d in 16:
		_sl([Blocks.WOOL, 1, 15 - d], [[Items.DYE, d], [Blocks.WOOL, 0]])


static func _register_smelting() -> void:
	_smelt(Blocks.IRON_ORE, ANY, [Items.IRON_INGOT, 1, 0], 0.7)
	_smelt(Blocks.GOLD_ORE, ANY, [Items.GOLD_INGOT, 1, 0], 1.0)
	_smelt(Blocks.DIAMOND_ORE, ANY, [Items.DIAMOND, 1, 0], 1.0)
	_smelt(Blocks.COBBLESTONE, ANY, [Blocks.STONE, 1, 0], 0.1)
	_smelt(Blocks.SAND, ANY, [Blocks.GLASS, 1, 0], 0.1)
	_smelt(Blocks.LOG, ANY, [Items.COAL, 1, 1], 0.15)
	_smelt(Blocks.CACTUS, ANY, [Items.DYE, 1, Items.DYE_GREEN], 0.2)
	_smelt(Items.CLAY_BALL, ANY, [Items.BRICK, 1, 0], 0.3)
	_smelt(Items.PORKCHOP, ANY, [Items.COOKED_PORKCHOP, 1, 0], 0.35)
	_smelt(Items.BEEF, ANY, [Items.COOKED_BEEF, 1, 0], 0.35)
	_smelt(Items.CHICKEN, ANY, [Items.COOKED_CHICKEN, 1, 0], 0.35)
	_smelt(Items.FISH, ANY, [Items.COOKED_FISH, 1, 0], 0.35)
	_smelt(Blocks.COAL_ORE, ANY, [Items.COAL, 1, 0], 0.1)
	_smelt(Blocks.REDSTONE_ORE, ANY, [Items.REDSTONE, 1, 0], 0.7)
	_smelt(Blocks.LAPIS_ORE, ANY, [Items.DYE, 1, Items.DYE_LAPIS], 0.2)


static func _smelt(id: int, data: int, out: Array, xp: float) -> void:
	smelting[id * 16 + (15 if data == ANY else data)] = [out[0], out[1], out[2], xp]


# --- Поиск -----------------------------------------------------------------

## Результат переплавки предмета: [id, количество, данные, опыт] или [].
static func smelt_result(id: int, data: int) -> Array:
	if smelting.has(id * 16 + (data & 15)):
		return smelting[id * 16 + (data & 15)]
	return smelting.get(id * 16 + 15, [])


static func _match_cell(want: Array, have: Array) -> bool:
	if int(want[0]) == 0:
		return int(have[0]) == 0
	if int(have[0]) != int(want[0]):
		return false
	return int(want[1]) == ANY or int(want[1]) == int(have[1])


## Результат крафта для сетки size×size (массив [id, data], пустые клетки — [0, 0]).
## Возвращает [id, количество, данные] или [].
static func match_grid(grid: Array, size: int) -> Array:
	# Ограничивающий прямоугольник непустых клеток.
	var x0 := size
	var y0 := size
	var x1 := -1
	var y1 := -1
	var items := []
	for y in size:
		for x in size:
			var c: Array = grid[x + y * size]
			if int(c[0]) != 0:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
				items.append(c)
	if x1 < 0:
		return []
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	for r in shaped:
		if int(r["w"]) != w or int(r["h"]) != h:
			continue
		for mirror in 2:
			var ok := true
			for y in h:
				for x in w:
					var rx := (w - 1 - x) if mirror == 1 else x
					var want: Array = r["cells"][rx + y * w]
					var have: Array = grid[(x0 + x) + (y0 + y) * size]
					if not _match_cell(want, have):
						ok = false
						break
				if not ok:
					break
			if ok:
				return r["out"]
	for r in shapeless:
		var need: Array = (r["items"] as Array).duplicate()
		if need.size() != items.size():
			continue
		var ok := true
		for have: Array in items:
			var found := -1
			for i in need.size():
				if _match_cell(need[i], have):
					found = i
					break
			if found < 0:
				ok = false
				break
			need.remove_at(found)
		if ok:
			return r["out"]
	# Починка: два одинаковых изношенных инструмента → один с суммарной прочностью + 10 %.
	if items.size() == 2 and int(items[0][0]) == int(items[1][0]) and Items.is_damageable(int(items[0][0])):
		var id := int(items[0][0])
		var max_d := Items.max_damage(id)
		@warning_ignore("integer_division")
		var left := (max_d - Enchantments.damage_of(int(items[0][1]))) + (max_d - Enchantments.damage_of(int(items[1][1]))) + max_d / 10
		return [id, 1, maxi(max_d - left, 0)]
	return []
