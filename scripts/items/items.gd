class_name Items
extends RefCounted
## Предметы Minecraft 1.2. ID 0–124 — блоки (предмет-блок), 256–385 — предметы, 2256–2266 — пластинки.
## «Данные» стопки (data) — как в оригинале: вариант блока, цвет красителя, тип зелья, моб у яйца
## призыва, а у инструментов и брони — накопленный износ.

enum {
	IRON_SHOVEL = 256, IRON_PICKAXE, IRON_AXE, FLINT_AND_STEEL, APPLE, BOW, ARROW, COAL, DIAMOND, IRON_INGOT,
	GOLD_INGOT, IRON_SWORD, WOODEN_SWORD, WOODEN_SHOVEL, WOODEN_PICKAXE, WOODEN_AXE, STONE_SWORD, STONE_SHOVEL,
	STONE_PICKAXE, STONE_AXE, DIAMOND_SWORD, DIAMOND_SHOVEL, DIAMOND_PICKAXE, DIAMOND_AXE, STICK, BOWL,
	MUSHROOM_STEW, GOLDEN_SWORD, GOLDEN_SHOVEL, GOLDEN_PICKAXE, GOLDEN_AXE, STRING, FEATHER, GUNPOWDER,
	WOODEN_HOE, STONE_HOE, IRON_HOE, DIAMOND_HOE, GOLDEN_HOE, SEEDS, WHEAT, BREAD,
	LEATHER_HELMET, LEATHER_CHESTPLATE, LEATHER_LEGGINGS, LEATHER_BOOTS,
	CHAIN_HELMET, CHAIN_CHESTPLATE, CHAIN_LEGGINGS, CHAIN_BOOTS,
	IRON_HELMET, IRON_CHESTPLATE, IRON_LEGGINGS, IRON_BOOTS,
	DIAMOND_HELMET, DIAMOND_CHESTPLATE, DIAMOND_LEGGINGS, DIAMOND_BOOTS,
	GOLDEN_HELMET, GOLDEN_CHESTPLATE, GOLDEN_LEGGINGS, GOLDEN_BOOTS,
	FLINT, PORKCHOP, COOKED_PORKCHOP, PAINTING, GOLDEN_APPLE, SIGN, WOODEN_DOOR, BUCKET, WATER_BUCKET,
	LAVA_BUCKET, MINECART, SADDLE, IRON_DOOR, REDSTONE, SNOWBALL, BOAT, LEATHER, MILK_BUCKET, BRICK, CLAY_BALL,
	REEDS, PAPER, BOOK, SLIME_BALL, CHEST_MINECART, FURNACE_MINECART, EGG, COMPASS, FISHING_ROD, CLOCK,
	GLOWSTONE_DUST, FISH, COOKED_FISH, DYE, BONE, SUGAR, CAKE, BED, REPEATER, COOKIE, MAP, SHEARS, MELON,
	PUMPKIN_SEEDS, MELON_SEEDS, BEEF, COOKED_BEEF, CHICKEN, COOKED_CHICKEN, ROTTEN_FLESH, ENDER_PEARL,
	BLAZE_ROD, GHAST_TEAR, GOLD_NUGGET, NETHER_WART, POTION, GLASS_BOTTLE, SPIDER_EYE, FERMENTED_SPIDER_EYE,
	BLAZE_POWDER, MAGMA_CREAM, BREWING_STAND, CAULDRON, ENDER_EYE, SPECKLED_MELON, SPAWN_EGG,
	EXPERIENCE_BOTTLE, FIRE_CHARGE,
	LAST_ITEM = FIRE_CHARGE,
	RECORD_13 = 2256, RECORD_CAT, RECORD_BLOCKS, RECORD_CHIRP, RECORD_FAR, RECORD_MALL, RECORD_MELLOHI,
	RECORD_STAL, RECORD_STRAD, RECORD_WARD, RECORD_11,
	MAX_ID = RECORD_11,
}

const FIRST_ITEM := 256
## Красители (данные предмета DYE).
enum { DYE_INK, DYE_RED, DYE_GREEN, DYE_COCOA, DYE_LAPIS, DYE_PURPLE, DYE_CYAN, DYE_LIGHT_GRAY, DYE_GRAY,
	DYE_PINK, DYE_LIME, DYE_YELLOW, DYE_LIGHT_BLUE, DYE_MAGENTA, DYE_ORANGE, DYE_BONE_MEAL }
const DYE_NAMES := ["Чернильный мешок", "Красный краситель", "Зелёный краситель", "Какао-бобы", "Лазурит",
	"Фиолетовый краситель", "Бирюзовый краситель", "Светло-серый краситель", "Серый краситель",
	"Розовый краситель", "Лаймовый краситель", "Жёлтый краситель", "Голубой краситель",
	"Пурпурный краситель", "Оранжевый краситель", "Костная мука"]
## Цвета шерсти/красителей (data шерсти = 15 − data красителя).
const WOOL_COLORS := [Color(0.92, 0.92, 0.92), Color(0.92, 0.53, 0.25), Color(0.75, 0.3, 0.79), Color(0.42, 0.55, 0.85),
	Color(0.78, 0.71, 0.15), Color(0.25, 0.71, 0.2), Color(0.85, 0.52, 0.6), Color(0.26, 0.26, 0.26),
	Color(0.62, 0.65, 0.65), Color(0.15, 0.46, 0.57), Color(0.5, 0.24, 0.71), Color(0.15, 0.2, 0.6),
	Color(0.34, 0.2, 0.11), Color(0.22, 0.3, 0.1), Color(0.64, 0.17, 0.16), Color(0.1, 0.09, 0.09)]

## Материалы инструментов: дерево, камень, железо, алмаз, золото.
enum { MAT_WOOD, MAT_STONE, MAT_IRON, MAT_DIAMOND, MAT_GOLD }
const MAT_TIER := [0, 1, 2, 3, 0]
const MAT_SPEED := [2.0, 4.0, 6.0, 8.0, 12.0]
const MAT_DURABILITY := [59, 131, 250, 1561, 32]
const MAT_DAMAGE := [0, 1, 2, 3, 0]
## Слоты брони: 0 шлем, 1 нагрудник, 2 поножи, 3 ботинки.
const ARMOR_DURABILITY_BASE := [11, 16, 15, 13]
## Броня: кожа, кольчуга, железо, алмаз, золото.
const ARMOR_MAT_DURABILITY := [5, 15, 15, 33, 7]
const ARMOR_POINTS := [[1, 3, 2, 1], [2, 5, 4, 1], [2, 6, 5, 2], [3, 8, 6, 3], [2, 5, 3, 1]]

## Яйца призыва: data → [имя, основной цвет, цвет пятен].
const SPAWN_EGGS := {
	50: ["Крипер", Color8(13, 167, 11), Color8(0, 0, 0)],
	51: ["Скелет", Color8(193, 193, 193), Color8(73, 73, 73)],
	52: ["Паук", Color8(52, 45, 39), Color8(168, 14, 14)],
	54: ["Зомби", Color8(0, 175, 175), Color8(121, 156, 101)],
	55: ["Слизень", Color8(81, 160, 62), Color8(126, 191, 110)],
	56: ["Гаст", Color8(249, 249, 249), Color8(188, 188, 188)],
	57: ["Зомби-свиночеловек", Color8(234, 147, 147), Color8(76, 113, 41)],
	58: ["Эндермен", Color8(22, 22, 22), Color8(0, 0, 0)],
	59: ["Пещерный паук", Color8(12, 66, 78), Color8(168, 14, 14)],
	60: ["Чешуйница", Color8(110, 110, 110), Color8(48, 48, 48)],
	61: ["Ифрит", Color8(246, 178, 1), Color8(255, 248, 126)],
	62: ["Магмовый куб", Color8(52, 0, 0), Color8(252, 252, 0)],
	90: ["Свинья", Color8(240, 165, 162), Color8(219, 99, 95)],
	91: ["Овца", Color8(231, 231, 231), Color8(255, 181, 181)],
	92: ["Корова", Color8(68, 54, 38), Color8(161, 161, 161)],
	93: ["Курица", Color8(161, 161, 161), Color8(255, 0, 0)],
	94: ["Спрут", Color8(34, 59, 77), Color8(112, 136, 153)],
	95: ["Волк", Color8(215, 211, 211), Color8(206, 175, 150)],
	96: ["Грибная корова", Color8(160, 15, 16), Color8(183, 183, 183)],
	98: ["Оцелот", Color8(239, 222, 125), Color8(86, 68, 52)],
	120: ["Житель", Color8(86, 60, 51), Color8(189, 139, 114)],
}

const RECORD_NAMES := ["13", "cat", "blocks", "chirp", "far", "mall", "mellohi", "stal", "strad", "ward", "11"]

## Свойства предметов 256–385: индекс = id − 256.
static var _names: Array[String] = []
static var _tex := PackedInt32Array()
static var _stack := PackedInt32Array()
static var _durability := PackedInt32Array()
static var _tool := PackedInt32Array()
static var _tier := PackedInt32Array()
static var _speed := PackedFloat32Array()
static var _damage := PackedInt32Array()
## Еда: голод (полусердечки «окорочков») и насыщение.
static var _food := PackedInt32Array()
static var _saturation := PackedFloat32Array()
static var _armor_slot := PackedInt32Array()
static var _armor_points := PackedInt32Array()


static func _static_init() -> void:
	var n := LAST_ITEM - FIRST_ITEM + 1
	_names.resize(n)
	_tex.resize(n)
	_stack.resize(n)
	_stack.fill(64)
	_durability.resize(n)
	_tool.resize(n)
	_tier.resize(n)
	_tier.fill(-1)
	_speed.resize(n)
	_speed.fill(1.0)
	_damage.resize(n)
	_damage.fill(1)
	_food.resize(n)
	_saturation.resize(n)
	_armor_slot.resize(n)
	_armor_slot.fill(-1)
	_armor_points.resize(n)
	_register_all()


static func _reg(id: int, n: String, tex: int, stack := 64) -> void:
	var i := id - FIRST_ITEM
	_names[i] = n
	_tex[i] = tex
	_stack[i] = stack


static func _reg_tool(id: int, n: String, tex: int, tool: int, mat: int) -> void:
	_reg(id, n, tex, 1)
	var i := id - FIRST_ITEM
	_tool[i] = tool
	_tier[i] = MAT_TIER[mat]
	_speed[i] = MAT_SPEED[mat]
	_durability[i] = MAT_DURABILITY[mat]
	var base := 1
	match tool:
		Blocks.TOOL_SWORD:
			base = 4
		Blocks.TOOL_AXE:
			base = 3
		Blocks.TOOL_PICKAXE:
			base = 2
		Blocks.TOOL_SHOVEL:
			base = 1
	_damage[i] = base + MAT_DAMAGE[mat] if tool != Blocks.TOOL_HOE else 1


static func _reg_food(id: int, n: String, tex: int, food: int, sat_mod: float) -> void:
	_reg(id, n, tex)
	_food[id - FIRST_ITEM] = food
	_saturation[id - FIRST_ITEM] = food * sat_mod * 2.0


static func _reg_armor(id: int, n: String, tex: int, mat: int, slot: int) -> void:
	_reg(id, n, tex, 1)
	var i := id - FIRST_ITEM
	_armor_slot[i] = slot
	_armor_points[i] = ARMOR_POINTS[mat][slot]
	_durability[i] = ARMOR_DURABILITY_BASE[slot] * ARMOR_MAT_DURABILITY[mat]


static func _register_all() -> void:
	var mats := ["деревянн", "каменн", "железн", "алмазн", "золот"]
	var tools := [
		[[WOODEN_SWORD, STONE_SWORD, IRON_SWORD, DIAMOND_SWORD, GOLDEN_SWORD], "ый меч", Blocks.TOOL_SWORD, Tex.SWORD_WOOD],
		[[WOODEN_SHOVEL, STONE_SHOVEL, IRON_SHOVEL, DIAMOND_SHOVEL, GOLDEN_SHOVEL], "ая лопата", Blocks.TOOL_SHOVEL, Tex.SHOVEL_WOOD],
		[[WOODEN_PICKAXE, STONE_PICKAXE, IRON_PICKAXE, DIAMOND_PICKAXE, GOLDEN_PICKAXE], "ая кирка", Blocks.TOOL_PICKAXE, Tex.PICKAXE_WOOD],
		[[WOODEN_AXE, STONE_AXE, IRON_AXE, DIAMOND_AXE, GOLDEN_AXE], "ый топор", Blocks.TOOL_AXE, Tex.AXE_WOOD],
		[[WOODEN_HOE, STONE_HOE, IRON_HOE, DIAMOND_HOE, GOLDEN_HOE], "ая мотыга", Blocks.TOOL_HOE, Tex.HOE_WOOD],
	]
	# Порядок текстур в Tex: дерево, камень, железо, золото, алмаз.
	var tex_order := [0, 1, 2, 4, 3]
	for t: Array in tools:
		for m in 5:
			var nm: String = (mats[m] as String).capitalize() + str(t[1])
			if m == MAT_GOLD:
				nm = "Золот" + str(t[1]).replace("ый", "ой")
			_reg_tool(int(t[0][m]), nm, int(t[3]) + tex_order[m], int(t[2]), m)
	var armor := [[LEATHER_HELMET, "Кожаный шлем", "Кожаная куртка", "Кожаные штаны", "Кожаные ботинки"],
		[CHAIN_HELMET, "Кольчужный шлем", "Кольчуга", "Кольчужные поножи", "Кольчужные ботинки"],
		[IRON_HELMET, "Железный шлем", "Железный нагрудник", "Железные поножи", "Железные ботинки"],
		[DIAMOND_HELMET, "Алмазный шлем", "Алмазный нагрудник", "Алмазные поножи", "Алмазные ботинки"],
		[GOLDEN_HELMET, "Золотой шлем", "Золотой нагрудник", "Золотые поножи", "Золотые ботинки"]]
	var armor_mats := [0, 1, 2, 3, 4]
	var armor_tex := [Tex.HELMET_LEATHER, Tex.HELMET_CHAIN, Tex.HELMET_IRON, Tex.HELMET_DIAMOND, Tex.HELMET_GOLD]
	for k in 5:
		for slot in 4:
			_reg_armor(int(armor[k][0]) + slot, str(armor[k][slot + 1]), int(armor_tex[k]) + slot, armor_mats[k], slot)

	_reg(FLINT_AND_STEEL, "Огниво", Tex.FLINT_AND_STEEL, 1)
	_durability[FLINT_AND_STEEL - FIRST_ITEM] = 64
	_reg_food(APPLE, "Яблоко", Tex.APPLE, 4, 0.3)
	_reg(BOW, "Лук", Tex.BOW, 1)
	_durability[BOW - FIRST_ITEM] = 384
	_reg(ARROW, "Стрела", Tex.ARROW)
	_reg(COAL, "Уголь", Tex.COAL)
	_reg(DIAMOND, "Алмаз", Tex.DIAMOND)
	_reg(IRON_INGOT, "Железный слиток", Tex.IRON_INGOT)
	_reg(GOLD_INGOT, "Золотой слиток", Tex.GOLD_INGOT)
	_reg(STICK, "Палка", Tex.STICK)
	_reg(BOWL, "Миска", Tex.BOWL)
	_reg_food(MUSHROOM_STEW, "Грибной суп", Tex.MUSHROOM_STEW, 6, 0.6)
	_stack[MUSHROOM_STEW - FIRST_ITEM] = 1
	_reg(STRING, "Нить", Tex.STRING)
	_reg(FEATHER, "Перо", Tex.FEATHER)
	_reg(GUNPOWDER, "Порох", Tex.GUNPOWDER)
	_reg(SEEDS, "Семена", Tex.SEEDS_WHEAT)
	_reg(WHEAT, "Пшеница", Tex.WHEAT)
	_reg_food(BREAD, "Хлеб", Tex.BREAD, 5, 0.6)
	_reg(FLINT, "Кремень", Tex.FLINT)
	_reg_food(PORKCHOP, "Сырая свинина", Tex.PORKCHOP_RAW, 3, 0.3)
	_reg_food(COOKED_PORKCHOP, "Жареная свинина", Tex.PORKCHOP_COOKED, 8, 0.8)
	_reg(PAINTING, "Картина", Tex.PAINTING)
	_reg_food(GOLDEN_APPLE, "Золотое яблоко", Tex.APPLE_GOLDEN, 4, 1.2)
	_reg(SIGN, "Табличка", Tex.SIGN, 1)
	_reg(WOODEN_DOOR, "Деревянная дверь", Tex.DOOR_WOOD, 1)
	_reg(BUCKET, "Ведро", Tex.BUCKET, 16)
	_reg(WATER_BUCKET, "Ведро воды", Tex.BUCKET_WATER, 1)
	_reg(LAVA_BUCKET, "Ведро лавы", Tex.BUCKET_LAVA, 1)
	_reg(MINECART, "Вагонетка", Tex.MINECART, 1)
	_reg(SADDLE, "Седло", Tex.SADDLE, 1)
	_reg(IRON_DOOR, "Железная дверь", Tex.DOOR_IRON, 1)
	_reg(REDSTONE, "Красная пыль", Tex.REDSTONE)
	_reg(SNOWBALL, "Снежок", Tex.SNOWBALL, 16)
	_reg(BOAT, "Лодка", Tex.BOAT, 1)
	_reg(LEATHER, "Кожа", Tex.LEATHER)
	_reg(MILK_BUCKET, "Ведро молока", Tex.BUCKET_MILK, 1)
	_reg(BRICK, "Кирпич", Tex.BRICK_ITEM)
	_reg(CLAY_BALL, "Глина", Tex.CLAY_BALL)
	_reg(REEDS, "Сахарный тростник", Tex.REEDS_ITEM)
	_reg(PAPER, "Бумага", Tex.PAPER)
	_reg(BOOK, "Книга", Tex.BOOK)
	_reg(SLIME_BALL, "Слизь", Tex.SLIMEBALL)
	_reg(CHEST_MINECART, "Вагонетка с сундуком", Tex.MINECART_CHEST, 1)
	_reg(FURNACE_MINECART, "Вагонетка с печью", Tex.MINECART_FURNACE, 1)
	_reg(EGG, "Яйцо", Tex.EGG, 16)
	_reg(COMPASS, "Компас", Tex.COMPASS)
	_reg(FISHING_ROD, "Удочка", Tex.FISHING_ROD, 1)
	_durability[FISHING_ROD - FIRST_ITEM] = 64
	_reg(CLOCK, "Часы", Tex.CLOCK)
	_reg(GLOWSTONE_DUST, "Светопыль", Tex.GLOWSTONE_DUST)
	_reg_food(FISH, "Сырая рыба", Tex.FISH_RAW, 2, 0.3)
	_reg_food(COOKED_FISH, "Жареная рыба", Tex.FISH_COOKED, 5, 0.6)
	_reg(DYE, "Краситель", Tex.DYE_0)
	_reg(BONE, "Кость", Tex.BONE)
	_reg(SUGAR, "Сахар", Tex.SUGAR)
	_reg(CAKE, "Торт", Tex.CAKE, 1)
	_reg(BED, "Кровать", Tex.BED, 1)
	_reg(REPEATER, "Повторитель", Tex.REPEATER)
	_reg_food(COOKIE, "Печенье", Tex.COOKIE, 2, 0.1)
	_reg(MAP, "Карта", Tex.MAP, 1)
	_reg(SHEARS, "Ножницы", Tex.SHEARS, 1)
	_durability[SHEARS - FIRST_ITEM] = 238
	_tool[SHEARS - FIRST_ITEM] = Blocks.TOOL_SHEARS
	_speed[SHEARS - FIRST_ITEM] = 15.0
	_reg_food(MELON, "Ломтик арбуза", Tex.MELON_SLICE, 2, 0.3)
	_reg(PUMPKIN_SEEDS, "Семена тыквы", Tex.SEEDS_PUMPKIN)
	_reg(MELON_SEEDS, "Семена арбуза", Tex.SEEDS_MELON)
	_reg_food(BEEF, "Сырая говядина", Tex.BEEF_RAW, 3, 0.3)
	_reg_food(COOKED_BEEF, "Стейк", Tex.BEEF_COOKED, 8, 0.8)
	_reg_food(CHICKEN, "Сырая курица", Tex.CHICKEN_RAW, 2, 0.3)
	_reg_food(COOKED_CHICKEN, "Жареная курица", Tex.CHICKEN_COOKED, 6, 0.6)
	_reg_food(ROTTEN_FLESH, "Гнилая плоть", Tex.ROTTEN_FLESH, 4, 0.1)
	_reg(ENDER_PEARL, "Жемчуг Края", Tex.ENDER_PEARL, 16)
	_reg(BLAZE_ROD, "Огненный стержень", Tex.BLAZE_ROD)
	_reg(GHAST_TEAR, "Слеза гаста", Tex.GHAST_TEAR)
	_reg(GOLD_NUGGET, "Золотой самородок", Tex.GOLD_NUGGET)
	_reg(NETHER_WART, "Адский нарост", Tex.NETHER_WART_ITEM)
	_reg(POTION, "Зелье", Tex.POTION, 1)
	_reg(GLASS_BOTTLE, "Бутылочка", Tex.GLASS_BOTTLE)
	_reg_food(SPIDER_EYE, "Паучий глаз", Tex.SPIDER_EYE, 2, 0.8)
	_reg(FERMENTED_SPIDER_EYE, "Приготовленный паучий глаз", Tex.FERMENTED_SPIDER_EYE)
	_reg(BLAZE_POWDER, "Огненный порошок", Tex.BLAZE_POWDER)
	_reg(MAGMA_CREAM, "Сгусток магмы", Tex.MAGMA_CREAM)
	_reg(BREWING_STAND, "Варочная стойка", Tex.BREWING_STAND_ITEM)
	_reg(CAULDRON, "Котёл", Tex.CAULDRON)
	_reg(ENDER_EYE, "Око Края", Tex.EYE_OF_ENDER)
	_reg(SPECKLED_MELON, "Сверкающий ломтик арбуза", Tex.SPECKLED_MELON)
	_reg(SPAWN_EGG, "Яйцо призыва", Tex.SPAWN_EGG)
	_reg(EXPERIENCE_BOTTLE, "Пузырёк опыта", Tex.EXP_BOTTLE)
	_reg(FIRE_CHARGE, "Огненный шар", Tex.FIRE_CHARGE)


# --- Запросы ---------------------------------------------------------------

static func is_block(id: int) -> bool:
	return id > 0 and id < Blocks.COUNT


static func is_record(id: int) -> bool:
	return id >= RECORD_13 and id <= RECORD_11


static func exists(id: int) -> bool:
	return is_block(id) or (id >= FIRST_ITEM and id <= LAST_ITEM) or is_record(id)


static func _i(id: int) -> int:
	return id - FIRST_ITEM if id >= FIRST_ITEM and id <= LAST_ITEM else -1


static func name_of(id: int, data: int = 0) -> String:
	if is_block(id):
		return block_item_name(id, data)
	if is_record(id):
		return "Пластинка «%s»" % RECORD_NAMES[id - RECORD_13]
	var i := _i(id)
	if i < 0:
		return "?"
	match id:
		DYE:
			return DYE_NAMES[clampi(data, 0, 15)]
		COAL:
			return "Древесный уголь" if data == 1 else "Уголь"
		SPAWN_EGG:
			if SPAWN_EGGS.has(data):
				return "Яйцо призыва: %s" % SPAWN_EGGS[data][0]
		POTION:
			return Potions.name_of(data)
	return _names[i]


static func block_item_name(id: int, data: int) -> String:
	match id:
		Blocks.PLANKS:
			return "%s доски" % Blocks.WOOD_NAMES[data & 3]
		Blocks.LOG:
			return ["Дубовая", "Еловая", "Берёзовая", "Тропическая"][data & 3] + " древесина"
		Blocks.LEAVES:
			return ["Дубовая", "Еловая", "Берёзовая", "Тропическая"][data & 3] + " листва"
		Blocks.SAPLING:
			return ["Саженец дуба", "Саженец ели", "Саженец берёзы", "Саженец тропического дерева"][data & 3]
		Blocks.WOOL:
			return "%s шерсть" % Blocks.COLOR_NAMES[data & 15]
		Blocks.SANDSTONE:
			return ["Песчаник", "Резной песчаник", "Гладкий песчаник"][clampi(data, 0, 2)]
		Blocks.STONE_BRICKS:
			return ["Каменные кирпичи", "Замшелые каменные кирпичи", "Потрескавшиеся каменные кирпичи",
				"Резные каменные кирпичи"][clampi(data, 0, 3)]
		Blocks.SLAB, Blocks.DOUBLE_SLAB:
			return ["Каменная плита", "Плита из песчаника", "Деревянная плита", "Плита из булыжника",
				"Кирпичная плита", "Плита из каменных кирпичей", "Каменная плита", "Каменная плита"][data & 7]
		Blocks.TALLGRASS:
			return ["Куст", "Высокая трава", "Папоротник"][clampi(data, 0, 2)]
		Blocks.MONSTER_EGG:
			return "Камень с чешуйницей"
	return Blocks.block_name(id)


static func max_stack(id: int) -> int:
	var i := _i(id)
	if i >= 0:
		return _stack[i]
	if is_record(id):
		return 1
	return 64


static func max_damage(id: int) -> int:
	var i := _i(id)
	return _durability[i] if i >= 0 else 0


## Предмет изнашивается (у него data — износ, а не вариант).
static func is_damageable(id: int) -> bool:
	return max_damage(id) > 0


static func tool_kind(id: int) -> int:
	var i := _i(id)
	return _tool[i] if i >= 0 else Blocks.TOOL_NONE


static func tool_tier(id: int) -> int:
	var i := _i(id)
	return _tier[i] if i >= 0 else -1


static func tool_speed(id: int) -> float:
	var i := _i(id)
	return _speed[i] if i >= 0 else 1.0


## Урон в ударе (в полусердечках).
static func attack_damage(id: int) -> int:
	var i := _i(id)
	return _damage[i] if i >= 0 else 1


static func food_value(id: int) -> int:
	var i := _i(id)
	return _food[i] if i >= 0 else 0


static func food_saturation(id: int) -> float:
	var i := _i(id)
	return _saturation[i] if i >= 0 else 0.0


static func is_food(id: int) -> bool:
	return food_value(id) > 0


static func armor_slot(id: int) -> int:
	var i := _i(id)
	return _armor_slot[i] if i >= 0 else -1


static func armor_points(id: int) -> int:
	var i := _i(id)
	return _armor_points[i] if i >= 0 else 0


static func is_sword(id: int) -> bool:
	return tool_kind(id) == Blocks.TOOL_SWORD


## Сколько тиков (1/20 с) горит топливо в печи (0 — не топливо).
static func fuel_ticks(id: int) -> int:
	match id:
		COAL:
			return 1600
		BLAZE_ROD:
			return 2400
		LAVA_BUCKET:
			return 20000
		STICK:
			return 100
		WOODEN_SWORD, WOODEN_SHOVEL, WOODEN_PICKAXE, WOODEN_AXE, WOODEN_HOE:
			return 200
		Blocks.SAPLING:
			return 100
		Blocks.PLANKS, Blocks.LOG, Blocks.OAK_STAIRS, Blocks.FENCE, Blocks.FENCE_GATE, Blocks.CHEST, Blocks.CRAFTING_TABLE, Blocks.BOOKSHELF, Blocks.JUKEBOX, Blocks.NOTE_BLOCK, Blocks.TRAPDOOR, Blocks.WOODEN_PLATE:
			return 300
	return 0


## Предмет-блок рисуется в инвентаре плоским спрайтом (растения, факелы, рельсы…).
static func is_flat_block(id: int) -> bool:
	if not is_block(id):
		return false
	return Blocks.shapes[id] in [Blocks.SH_CROSS, Blocks.SH_TORCH, Blocks.SH_RAIL, Blocks.SH_LADDER, Blocks.SH_VINE,
		Blocks.SH_LEVER, Blocks.SH_LILYPAD, Blocks.SH_PANE, Blocks.SH_FIRE, Blocks.SH_PORTAL, Blocks.SH_CROPS,
		Blocks.SH_STEM]


## Тайл значка/спрайта предмета (для плоских предметов-блоков — тайл блока).
static func sprite_tile(id: int, data: int = 0) -> int:
	if is_block(id):
		if id == Blocks.IRON_BARS:
			return Tex.IRON_BARS
		if id == Blocks.GLASS_PANE:
			return Tex.GLASS
		return Blocks.texture_of(id, 4, data if id != Blocks.TORCH else 0)
	if is_record(id):
		return Tex.RECORD_13 + (id - RECORD_13)
	match id:
		DYE:
			return Tex.DYE_0 + clampi(data, 0, 15)
		COAL:
			return Tex.CHARCOAL if data == 1 else Tex.COAL
		POTION:
			return Tex.POTION_SPLASH if Potions.is_splash(data) else Tex.POTION
	var i := _i(id)
	return _tex[i] if i >= 0 else Tex.STONE


## Второй (накладываемый) слой значка и его цвет: зелья и яйца призыва. Пустой массив — нет.
static func overlay(id: int, data: int) -> Array:
	if id == POTION and data != 0:
		return [Tex.POTION_OVERLAY, Potions.color_of(data)]
	if id == SPAWN_EGG:
		var e: Array = SPAWN_EGGS.get(data, ["", Color.WHITE, Color.BLACK])
		return [Tex.SPAWN_EGG_OVERLAY, e[2]]
	return []


## Цвет, на который умножается основной спрайт (листва, трава, яйцо призыва).
static func sprite_tint(id: int, data: int) -> Color:
	if id == SPAWN_EGG:
		var e: Array = SPAWN_EGGS.get(data, ["", Color.WHITE, Color.BLACK])
		return e[1]
	if is_block(id) and Blocks.tinted[id] == 1:
		if id == Blocks.LEAVES:
			return [Color(0.38, 0.6, 0.22), Color(0.38, 0.52, 0.38), Color(0.5, 0.65, 0.33), Color(0.38, 0.62, 0.2)][data & 3]
		return Color(0.47, 0.75, 0.35)
	return Color.WHITE


## Все предметы для креативного инвентаря: [id, data].
static func creative_items() -> Array:
	var out := Blocks.creative_blocks()
	for id in range(FIRST_ITEM, LAST_ITEM + 1):
		match id:
			DYE:
				for d in 16:
					out.append([id, d])
			COAL:
				out.append([id, 0])
				out.append([id, 1])
			SPAWN_EGG:
				for d: int in SPAWN_EGGS.keys():
					out.append([id, d])
			POTION:
				for d: int in Potions.CREATIVE:
					out.append([id, d])
			_:
				out.append([id, 0])
	for r in range(RECORD_13, RECORD_11 + 1):
		out.append([r, 0])
	return out
