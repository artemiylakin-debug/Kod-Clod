class_name Blocks
extends RefCounted
## Реестр блоков Minecraft 1.2 (номера ID — как в оригинале, 0–124): форма, текстуры граней,
## прочность, инструмент, свечение, горючесть, дроп. Данные блока (meta, 0–15) — вариант
## (порода дерева, цвет шерсти), ориентация, уровень жидкости, стадия роста, заряд и т. п.
##
## Грани: 0 +X (восток), 1 -X (запад), 2 +Y (верх), 3 -Y (низ), 4 +Z (юг), 5 -Z (север).
## Горизонтальное направление в meta: 0 юг (+Z), 1 запад (-X), 2 север (-Z), 3 восток (+X).

enum {
	AIR = 0, STONE = 1, GRASS = 2, DIRT = 3, COBBLESTONE = 4, PLANKS = 5, SAPLING = 6, BEDROCK = 7,
	FLOWING_WATER = 8, WATER = 9, FLOWING_LAVA = 10, LAVA = 11, SAND = 12, GRAVEL = 13, GOLD_ORE = 14,
	IRON_ORE = 15, COAL_ORE = 16, LOG = 17, LEAVES = 18, SPONGE = 19, GLASS = 20, LAPIS_ORE = 21,
	LAPIS_BLOCK = 22, DISPENSER = 23, SANDSTONE = 24, NOTE_BLOCK = 25, BED = 26, POWERED_RAIL = 27,
	DETECTOR_RAIL = 28, STICKY_PISTON = 29, WEB = 30, TALLGRASS = 31, DEADBUSH = 32, PISTON = 33,
	PISTON_HEAD = 34, WOOL = 35, PISTON_MOVING = 36, DANDELION = 37, ROSE = 38, BROWN_MUSHROOM = 39,
	RED_MUSHROOM = 40, GOLD_BLOCK = 41, IRON_BLOCK = 42, DOUBLE_SLAB = 43, SLAB = 44, BRICKS = 45,
	TNT = 46, BOOKSHELF = 47, MOSSY_COBBLESTONE = 48, OBSIDIAN = 49, TORCH = 50, FIRE = 51, SPAWNER = 52,
	OAK_STAIRS = 53, CHEST = 54, REDSTONE_WIRE = 55, DIAMOND_ORE = 56, DIAMOND_BLOCK = 57,
	CRAFTING_TABLE = 58, WHEAT = 59, FARMLAND = 60, FURNACE = 61, LIT_FURNACE = 62, SIGN_POST = 63,
	WOODEN_DOOR = 64, LADDER = 65, RAIL = 66, COBBLESTONE_STAIRS = 67, WALL_SIGN = 68, LEVER = 69,
	STONE_PLATE = 70, IRON_DOOR = 71, WOODEN_PLATE = 72, REDSTONE_ORE = 73, LIT_REDSTONE_ORE = 74,
	REDSTONE_TORCH_OFF = 75, REDSTONE_TORCH = 76, STONE_BUTTON = 77, SNOW_LAYER = 78, ICE = 79, SNOW = 80,
	CACTUS = 81, CLAY = 82, REEDS = 83, JUKEBOX = 84, FENCE = 85, PUMPKIN = 86, NETHERRACK = 87,
	SOUL_SAND = 88, GLOWSTONE = 89, PORTAL = 90, JACK_O_LANTERN = 91, CAKE = 92, REPEATER_OFF = 93,
	REPEATER_ON = 94, LOCKED_CHEST = 95, TRAPDOOR = 96, MONSTER_EGG = 97, STONE_BRICKS = 98,
	BROWN_MUSHROOM_BLOCK = 99, RED_MUSHROOM_BLOCK = 100, IRON_BARS = 101, GLASS_PANE = 102, MELON = 103,
	PUMPKIN_STEM = 104, MELON_STEM = 105, VINE = 106, FENCE_GATE = 107, BRICK_STAIRS = 108,
	STONE_BRICK_STAIRS = 109, MYCELIUM = 110, WATERLILY = 111, NETHER_BRICK = 112, NETHER_FENCE = 113,
	NETHER_BRICK_STAIRS = 114, NETHER_WART = 115, ENCHANTING_TABLE = 116, BREWING_STAND = 117,
	CAULDRON = 118, END_PORTAL = 119, END_PORTAL_FRAME = 120, END_STONE = 121, DRAGON_EGG = 122,
	REDSTONE_LAMP = 123, LIT_REDSTONE_LAMP = 124,
	COUNT = 125,
}

## Форма блока — как его рисовать и какие у него габариты.
enum {
	SH_NONE, SH_CUBE, SH_CROSS, SH_CROPS, SH_LIQUID, SH_TORCH, SH_SLAB, SH_STAIRS, SH_FENCE, SH_PANE,
	SH_DOOR, SH_TRAPDOOR, SH_LADDER, SH_VINE, SH_RAIL, SH_WIRE, SH_LEVER, SH_BUTTON, SH_PLATE, SH_BED,
	SH_CHEST, SH_CACTUS, SH_FARMLAND, SH_SNOW_LAYER, SH_CAKE, SH_REPEATER, SH_FIRE, SH_PORTAL, SH_LILYPAD,
	SH_SIGN, SH_BREWING, SH_CAULDRON, SH_ENCHANT, SH_END_FRAME, SH_PISTON_HEAD, SH_DRAGON_EGG, SH_STEM,
	SH_GATE, SH_END_PORTAL, SH_PISTON,
}

## Проход отрисовки: непрозрачный (с вырезанием по альфе) или полупрозрачный.
const PASS_SOLID := 0
const PASS_TRANSLUCENT := 1

## Инструменты.
enum { TOOL_NONE, TOOL_PICKAXE, TOOL_AXE, TOOL_SHOVEL, TOOL_SWORD, TOOL_SHEARS, TOOL_HOE }
## Звук (материал) — шаги, добыча, установка.
enum { SND_STONE, SND_WOOD, SND_GRAVEL, SND_GRASS, SND_SAND, SND_GLASS, SND_CLOTH, SND_METAL, SND_SNOW, SND_NONE }

const DIR_VEC := [Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 0)]
## Грань, смотрящая в горизонтальном направлении 0–3.
const DIR_FACE := [4, 1, 5, 0]
const FACE_VEC := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const OPPOSITE_FACE := [1, 0, 3, 2, 5, 4]

const CRACK_STAGES := 10
const WOOD_NAMES := ["Дубовые", "Еловые", "Берёзовые", "Тропические"]
const COLOR_NAMES := ["Белая", "Оранжевая", "Пурпурная", "Голубая", "Жёлтая", "Лаймовая", "Розовая", "Серая",
	"Светло-серая", "Бирюзовая", "Фиолетовая", "Синяя", "Коричневая", "Зелёная", "Красная", "Чёрная"]

## Свойства (заполняются в _static_init). Индекс — ID блока.
static var names: Array[String] = []
static var shapes := PackedByteArray()
static var passes := PackedByteArray()
static var solid_flags := PackedByteArray()
## Полный непрозрачный куб: скрывает соседние грани, отбрасывает AO и закрывает небо.
static var opaque_flags := PackedByteArray()
static var ao_flags := PackedByteArray()
static var light_emission := PackedByteArray()
static var hardness_table := PackedFloat32Array()
static var blast_table := PackedFloat32Array()
static var tool_table := PackedByteArray()
## Минимальный уровень инструмента для дропа: -1 — любой (даже рука), 0 дерево, 1 камень, 2 железо, 3 алмаз.
static var tier_table := PackedInt32Array()
static var sound_table := PackedByteArray()
static var replaceable_flags := PackedByteArray()
static var gravity_flags := PackedByteArray()
static var climbable_flags := PackedByteArray()
## Горючесть: [шанс воспламениться от соседнего огня, шанс сгореть].
static var fire_spread := PackedInt32Array()
static var fire_burn := PackedInt32Array()
## Нужна опора (факел, растение, рельсы…): блок разрушается, если опору убрать.
static var needs_support := PackedByteArray()
## Окрашивается цветом биома.
static var tinted := PackedByteArray()
## Блоки, участвующие в случайных тиках (рост растений и т. п.).
static var random_tick := PackedByteArray()
## Для быстрой проверки «строка целиком из воздуха/непрозрачных блоков» в мешере.
static var non_opaque_ids := PackedInt32Array()
## Текстура грани: tile_table[(id * 16 + meta) * 6 + face].
static var tile_table := PackedInt32Array()
## Блоки, испускающие свет.
static var emitter_ids := PackedInt32Array()


static func _static_init() -> void:
	names.resize(COUNT)
	# Packed-массивы копируются по значению, поэтому размер задаётся каждому отдельно.
	shapes.resize(COUNT)
	passes.resize(COUNT)
	solid_flags.resize(COUNT)
	opaque_flags.resize(COUNT)
	ao_flags.resize(COUNT)
	light_emission.resize(COUNT)
	tool_table.resize(COUNT)
	sound_table.resize(COUNT)
	replaceable_flags.resize(COUNT)
	gravity_flags.resize(COUNT)
	climbable_flags.resize(COUNT)
	needs_support.resize(COUNT)
	tinted.resize(COUNT)
	random_tick.resize(COUNT)
	hardness_table.resize(COUNT)
	blast_table.resize(COUNT)
	tier_table.resize(COUNT)
	fire_spread.resize(COUNT)
	fire_burn.resize(COUNT)
	tier_table.fill(-1)
	_register_all()
	for id in COUNT:
		var sh := shapes[id]
		var opaque := sh == SH_CUBE and passes[id] == PASS_SOLID and not _is_cutout_cube(id)
		opaque_flags[id] = 1 if opaque else 0
		ao_flags[id] = 1 if opaque or id == LEAVES else 0
		if not opaque:
			non_opaque_ids.append(id)
		if light_emission[id] > 0:
			emitter_ids.append(id)
	tile_table.resize(COUNT * 16 * 6)
	for id in COUNT:
		for meta in 16:
			for f in 6:
				tile_table[(id * 16 + meta) * 6 + f] = _tile(id, meta, f)


static func _is_cutout_cube(id: int) -> bool:
	return id in [LEAVES, GLASS, SPAWNER, ICE]


## Регистрация одного блока. Параметры: имя, форма, прочность, взрывоустойчивость, инструмент,
## уровень инструмента, звук; дополнительные свойства — в словаре extra.
static func _reg(id: int, n: String, sh: int, hard: float, blast: float, tool: int, tier: int, snd: int, extra := {}) -> void:
	names[id] = n
	shapes[id] = sh
	hardness_table[id] = hard
	blast_table[id] = blast
	tool_table[id] = tool
	tier_table[id] = tier
	sound_table[id] = snd
	passes[id] = int(extra.get("pass", PASS_SOLID))
	light_emission[id] = int(extra.get("light", 0))
	replaceable_flags[id] = 1 if extra.get("replace", false) else 0
	gravity_flags[id] = 1 if extra.get("gravity", false) else 0
	climbable_flags[id] = 1 if extra.get("climb", false) else 0
	needs_support[id] = 1 if extra.get("support", false) else 0
	tinted[id] = 1 if extra.get("tint", false) else 0
	random_tick[id] = 1 if extra.get("tick", false) else 0
	var fire: Array = extra.get("fire", [0, 0])
	fire_spread[id] = int(fire[0])
	fire_burn[id] = int(fire[1])
	var solid := sh in [SH_CUBE, SH_SLAB, SH_STAIRS, SH_FENCE, SH_PANE, SH_DOOR, SH_TRAPDOOR, SH_BED, SH_CHEST,
		SH_CACTUS, SH_FARMLAND, SH_CAKE, SH_REPEATER, SH_BREWING, SH_CAULDRON, SH_ENCHANT, SH_END_FRAME,
		SH_PISTON_HEAD, SH_DRAGON_EGG, SH_GATE, SH_LILYPAD, SH_PISTON]
	if extra.has("solid"):
		solid = bool(extra["solid"])
	solid_flags[id] = 1 if solid else 0


static func _register_all() -> void:
	var P := TOOL_PICKAXE
	var A := TOOL_AXE
	var S := TOOL_SHOVEL
	var N := TOOL_NONE
	var wood_fire := [5, 20]
	_reg(AIR, "Воздух", SH_NONE, 0.0, 0.0, N, -1, SND_NONE, {"replace": true, "solid": false})
	_reg(STONE, "Камень", SH_CUBE, 1.5, 30.0, P, 0, SND_STONE)
	_reg(GRASS, "Блок травы", SH_CUBE, 0.6, 3.0, S, -1, SND_GRASS, {"tick": true})
	_reg(DIRT, "Земля", SH_CUBE, 0.5, 2.5, S, -1, SND_GRAVEL)
	_reg(COBBLESTONE, "Булыжник", SH_CUBE, 2.0, 30.0, P, 0, SND_STONE)
	_reg(PLANKS, "Доски", SH_CUBE, 2.0, 15.0, A, -1, SND_WOOD, {"fire": wood_fire})
	_reg(SAPLING, "Саженец", SH_CROSS, 0.0, 0.0, N, -1, SND_GRASS, {"support": true, "tick": true})
	_reg(BEDROCK, "Коренная порода", SH_CUBE, -1.0, 18000000.0, N, -1, SND_STONE)
	_reg(FLOWING_WATER, "Вода", SH_LIQUID, 100.0, 500.0, N, -1, SND_NONE, {"pass": PASS_TRANSLUCENT, "replace": true, "solid": false})
	_reg(WATER, "Вода", SH_LIQUID, 100.0, 500.0, N, -1, SND_NONE, {"pass": PASS_TRANSLUCENT, "replace": true, "solid": false})
	_reg(FLOWING_LAVA, "Лава", SH_LIQUID, 100.0, 500.0, N, -1, SND_NONE, {"light": 15, "replace": true, "solid": false})
	_reg(LAVA, "Лава", SH_LIQUID, 100.0, 500.0, N, -1, SND_NONE, {"light": 15, "replace": true, "solid": false})
	_reg(SAND, "Песок", SH_CUBE, 0.5, 2.5, S, -1, SND_SAND, {"gravity": true})
	_reg(GRAVEL, "Гравий", SH_CUBE, 0.6, 3.0, S, -1, SND_GRAVEL, {"gravity": true})
	_reg(GOLD_ORE, "Золотая руда", SH_CUBE, 3.0, 15.0, P, 2, SND_STONE)
	_reg(IRON_ORE, "Железная руда", SH_CUBE, 3.0, 15.0, P, 1, SND_STONE)
	_reg(COAL_ORE, "Угольная руда", SH_CUBE, 3.0, 15.0, P, 0, SND_STONE)
	_reg(LOG, "Древесина", SH_CUBE, 2.0, 10.0, A, -1, SND_WOOD, {"fire": [5, 5]})
	_reg(LEAVES, "Листва", SH_CUBE, 0.2, 1.0, TOOL_SHEARS, -1, SND_GRASS, {"tint": true, "fire": [30, 60]})
	_reg(SPONGE, "Губка", SH_CUBE, 0.6, 3.0, N, -1, SND_CLOTH)
	_reg(GLASS, "Стекло", SH_CUBE, 0.3, 1.5, N, -1, SND_GLASS)
	_reg(LAPIS_ORE, "Лазуритовая руда", SH_CUBE, 3.0, 15.0, P, 1, SND_STONE)
	_reg(LAPIS_BLOCK, "Лазуритовый блок", SH_CUBE, 3.0, 15.0, P, 1, SND_STONE)
	_reg(DISPENSER, "Раздатчик", SH_CUBE, 3.5, 17.5, P, 0, SND_STONE)
	_reg(SANDSTONE, "Песчаник", SH_CUBE, 0.8, 4.0, P, 0, SND_STONE)
	_reg(NOTE_BLOCK, "Нотный блок", SH_CUBE, 0.8, 4.0, A, -1, SND_WOOD, {"fire": wood_fire})
	_reg(BED, "Кровать", SH_BED, 0.2, 1.0, N, -1, SND_WOOD)
	_reg(POWERED_RAIL, "Энергорельсы", SH_RAIL, 0.7, 3.5, P, -1, SND_METAL, {"support": true, "solid": false})
	_reg(DETECTOR_RAIL, "Нажимные рельсы", SH_RAIL, 0.7, 3.5, P, -1, SND_METAL, {"support": true, "solid": false})
	_reg(STICKY_PISTON, "Липкий поршень", SH_PISTON, 0.5, 2.5, P, -1, SND_STONE)
	_reg(WEB, "Паутина", SH_CROSS, 4.0, 20.0, TOOL_SWORD, -1, SND_CLOTH, {"solid": false})
	_reg(TALLGRASS, "Высокая трава", SH_CROSS, 0.0, 0.0, TOOL_SHEARS, -1, SND_GRASS, {"replace": true, "support": true, "tint": true, "fire": [60, 100]})
	_reg(DEADBUSH, "Мёртвый куст", SH_CROSS, 0.0, 0.0, TOOL_SHEARS, -1, SND_GRASS, {"replace": true, "support": true, "fire": [60, 100]})
	_reg(PISTON, "Поршень", SH_PISTON, 0.5, 2.5, P, -1, SND_STONE)
	_reg(PISTON_HEAD, "Головка поршня", SH_PISTON_HEAD, 0.5, 2.5, P, -1, SND_STONE)
	_reg(WOOL, "Шерсть", SH_CUBE, 0.8, 4.0, TOOL_SHEARS, -1, SND_CLOTH, {"fire": [30, 60]})
	_reg(PISTON_MOVING, "Движущийся блок", SH_NONE, -1.0, 0.0, N, -1, SND_NONE, {"solid": false})
	_reg(DANDELION, "Одуванчик", SH_CROSS, 0.0, 0.0, N, -1, SND_GRASS, {"support": true, "fire": [60, 100]})
	_reg(ROSE, "Роза", SH_CROSS, 0.0, 0.0, N, -1, SND_GRASS, {"support": true, "fire": [60, 100]})
	_reg(BROWN_MUSHROOM, "Коричневый гриб", SH_CROSS, 0.0, 0.0, N, -1, SND_GRASS, {"support": true, "light": 1, "tick": true})
	_reg(RED_MUSHROOM, "Красный гриб", SH_CROSS, 0.0, 0.0, N, -1, SND_GRASS, {"support": true, "tick": true})
	_reg(GOLD_BLOCK, "Золотой блок", SH_CUBE, 3.0, 30.0, P, 2, SND_METAL)
	_reg(IRON_BLOCK, "Железный блок", SH_CUBE, 5.0, 30.0, P, 1, SND_METAL)
	_reg(DOUBLE_SLAB, "Двойная плита", SH_CUBE, 2.0, 30.0, P, 0, SND_STONE)
	_reg(SLAB, "Плита", SH_SLAB, 2.0, 30.0, P, 0, SND_STONE)
	_reg(BRICKS, "Кирпичи", SH_CUBE, 2.0, 30.0, P, 0, SND_STONE)
	_reg(TNT, "Динамит", SH_CUBE, 0.0, 0.0, N, -1, SND_GRASS, {"fire": [15, 100]})
	_reg(BOOKSHELF, "Книжная полка", SH_CUBE, 1.5, 7.5, A, -1, SND_WOOD, {"fire": [30, 20]})
	_reg(MOSSY_COBBLESTONE, "Замшелый булыжник", SH_CUBE, 2.0, 30.0, P, 0, SND_STONE)
	_reg(OBSIDIAN, "Обсидиан", SH_CUBE, 50.0, 6000.0, P, 3, SND_STONE)
	_reg(TORCH, "Факел", SH_TORCH, 0.0, 0.0, N, -1, SND_WOOD, {"light": 14, "support": true})
	_reg(FIRE, "Огонь", SH_FIRE, 0.0, 0.0, N, -1, SND_NONE, {"light": 15, "replace": true, "solid": false, "tick": true})
	_reg(SPAWNER, "Рассадник монстров", SH_CUBE, 5.0, 25.0, P, 0, SND_METAL)
	_reg(OAK_STAIRS, "Деревянные ступеньки", SH_STAIRS, 2.0, 15.0, A, -1, SND_WOOD, {"fire": wood_fire})
	_reg(CHEST, "Сундук", SH_CHEST, 2.5, 12.5, A, -1, SND_WOOD)
	_reg(REDSTONE_WIRE, "Красная пыль", SH_WIRE, 0.0, 0.0, N, -1, SND_STONE, {"support": true, "solid": false})
	_reg(DIAMOND_ORE, "Алмазная руда", SH_CUBE, 3.0, 15.0, P, 2, SND_STONE)
	_reg(DIAMOND_BLOCK, "Алмазный блок", SH_CUBE, 5.0, 30.0, P, 2, SND_METAL)
	_reg(CRAFTING_TABLE, "Верстак", SH_CUBE, 2.5, 12.5, A, -1, SND_WOOD, {"fire": wood_fire})
	_reg(WHEAT, "Пшеница", SH_CROPS, 0.0, 0.0, N, -1, SND_GRASS, {"support": true, "tick": true, "solid": false})
	_reg(FARMLAND, "Грядка", SH_FARMLAND, 0.6, 3.0, S, -1, SND_GRAVEL, {"tick": true})
	_reg(FURNACE, "Печь", SH_CUBE, 3.5, 17.5, P, 0, SND_STONE)
	_reg(LIT_FURNACE, "Горящая печь", SH_CUBE, 3.5, 17.5, P, 0, SND_STONE, {"light": 13})
	_reg(SIGN_POST, "Табличка", SH_SIGN, 1.0, 5.0, A, -1, SND_WOOD, {"support": true, "solid": false})
	_reg(WOODEN_DOOR, "Деревянная дверь", SH_DOOR, 3.0, 15.0, A, -1, SND_WOOD, {"support": true})
	_reg(LADDER, "Лестница", SH_LADDER, 0.4, 2.0, A, -1, SND_WOOD, {"support": true, "climb": true, "solid": false})
	_reg(RAIL, "Рельсы", SH_RAIL, 0.7, 3.5, P, -1, SND_METAL, {"support": true, "solid": false})
	_reg(COBBLESTONE_STAIRS, "Ступеньки из булыжника", SH_STAIRS, 2.0, 30.0, P, 0, SND_STONE)
	_reg(WALL_SIGN, "Настенная табличка", SH_SIGN, 1.0, 5.0, A, -1, SND_WOOD, {"support": true, "solid": false})
	_reg(LEVER, "Рычаг", SH_LEVER, 0.5, 2.5, N, -1, SND_WOOD, {"support": true, "solid": false})
	_reg(STONE_PLATE, "Каменная нажимная плита", SH_PLATE, 0.5, 2.5, P, 0, SND_STONE, {"support": true, "solid": false})
	_reg(IRON_DOOR, "Железная дверь", SH_DOOR, 5.0, 25.0, P, 0, SND_METAL, {"support": true})
	_reg(WOODEN_PLATE, "Деревянная нажимная плита", SH_PLATE, 0.5, 2.5, A, -1, SND_WOOD, {"support": true, "solid": false})
	_reg(REDSTONE_ORE, "Красная руда", SH_CUBE, 3.0, 15.0, P, 2, SND_STONE)
	_reg(LIT_REDSTONE_ORE, "Светящаяся красная руда", SH_CUBE, 3.0, 15.0, P, 2, SND_STONE, {"light": 9, "tick": true})
	_reg(REDSTONE_TORCH_OFF, "Красный факел", SH_TORCH, 0.0, 0.0, N, -1, SND_WOOD, {"support": true})
	_reg(REDSTONE_TORCH, "Красный факел", SH_TORCH, 0.0, 0.0, N, -1, SND_WOOD, {"light": 7, "support": true})
	_reg(STONE_BUTTON, "Кнопка", SH_BUTTON, 0.5, 2.5, P, -1, SND_STONE, {"support": true, "solid": false})
	_reg(SNOW_LAYER, "Снег", SH_SNOW_LAYER, 0.1, 0.5, S, 0, SND_SNOW, {"replace": true, "support": true, "solid": false, "tick": true})
	_reg(ICE, "Лёд", SH_CUBE, 0.5, 2.5, P, -1, SND_GLASS, {"pass": PASS_TRANSLUCENT, "tick": true})
	_reg(SNOW, "Снежный блок", SH_CUBE, 0.2, 1.0, S, 0, SND_SNOW)
	_reg(CACTUS, "Кактус", SH_CACTUS, 0.4, 2.0, N, -1, SND_CLOTH, {"support": true, "tick": true})
	_reg(CLAY, "Глина", SH_CUBE, 0.6, 3.0, S, -1, SND_GRAVEL)
	_reg(REEDS, "Сахарный тростник", SH_CROSS, 0.0, 0.0, N, -1, SND_GRASS, {"support": true, "tick": true})
	_reg(JUKEBOX, "Проигрыватель", SH_CUBE, 2.0, 30.0, A, -1, SND_WOOD, {"fire": wood_fire})
	_reg(FENCE, "Забор", SH_FENCE, 2.0, 15.0, A, -1, SND_WOOD, {"fire": wood_fire})
	_reg(PUMPKIN, "Тыква", SH_CUBE, 1.0, 5.0, A, -1, SND_WOOD)
	_reg(NETHERRACK, "Адский камень", SH_CUBE, 0.4, 2.0, P, 0, SND_STONE)
	_reg(SOUL_SAND, "Песок душ", SH_CUBE, 0.5, 2.5, S, -1, SND_SAND)
	_reg(GLOWSTONE, "Светокамень", SH_CUBE, 0.3, 1.5, N, -1, SND_GLASS, {"light": 15})
	_reg(PORTAL, "Портал", SH_PORTAL, -1.0, 0.0, N, -1, SND_GLASS, {"light": 11, "pass": PASS_TRANSLUCENT, "solid": false})
	_reg(JACK_O_LANTERN, "Светильник Джека", SH_CUBE, 1.0, 5.0, A, -1, SND_WOOD, {"light": 15})
	_reg(CAKE, "Торт", SH_CAKE, 0.5, 2.5, N, -1, SND_CLOTH, {"support": true})
	_reg(REPEATER_OFF, "Повторитель", SH_REPEATER, 0.0, 0.0, N, -1, SND_WOOD, {"support": true})
	_reg(REPEATER_ON, "Повторитель", SH_REPEATER, 0.0, 0.0, N, -1, SND_WOOD, {"support": true, "light": 9})
	_reg(LOCKED_CHEST, "Запертый сундук", SH_CHEST, 0.0, 0.0, N, -1, SND_WOOD, {"light": 15})
	_reg(TRAPDOOR, "Люк", SH_TRAPDOOR, 3.0, 15.0, A, -1, SND_WOOD, {"fire": wood_fire})
	_reg(MONSTER_EGG, "Камень", SH_CUBE, 0.75, 3.75, P, -1, SND_STONE)
	_reg(STONE_BRICKS, "Каменные кирпичи", SH_CUBE, 1.5, 30.0, P, 0, SND_STONE)
	_reg(BROWN_MUSHROOM_BLOCK, "Коричневый гриб (блок)", SH_CUBE, 0.2, 1.0, A, -1, SND_WOOD)
	_reg(RED_MUSHROOM_BLOCK, "Красный гриб (блок)", SH_CUBE, 0.2, 1.0, A, -1, SND_WOOD)
	_reg(IRON_BARS, "Железная решётка", SH_PANE, 5.0, 30.0, P, 0, SND_METAL)
	_reg(GLASS_PANE, "Стеклянная панель", SH_PANE, 0.3, 1.5, N, -1, SND_GLASS)
	_reg(MELON, "Арбуз", SH_CUBE, 1.0, 5.0, A, -1, SND_WOOD)
	_reg(PUMPKIN_STEM, "Росток тыквы", SH_STEM, 0.0, 0.0, N, -1, SND_GRASS, {"support": true, "tick": true, "tint": true, "solid": false})
	_reg(MELON_STEM, "Росток арбуза", SH_STEM, 0.0, 0.0, N, -1, SND_GRASS, {"support": true, "tick": true, "tint": true, "solid": false})
	_reg(VINE, "Лианы", SH_VINE, 0.2, 1.0, TOOL_SHEARS, -1, SND_GRASS, {"replace": true, "climb": true, "tint": true, "tick": true, "fire": [15, 100], "solid": false})
	_reg(FENCE_GATE, "Калитка", SH_GATE, 2.0, 15.0, A, -1, SND_WOOD, {"fire": wood_fire})
	_reg(BRICK_STAIRS, "Кирпичные ступеньки", SH_STAIRS, 2.0, 30.0, P, 0, SND_STONE)
	_reg(STONE_BRICK_STAIRS, "Ступеньки из каменных кирпичей", SH_STAIRS, 1.5, 30.0, P, 0, SND_STONE)
	_reg(MYCELIUM, "Мицелий", SH_CUBE, 0.6, 3.0, S, -1, SND_GRASS, {"tick": true})
	_reg(WATERLILY, "Кувшинка", SH_LILYPAD, 0.0, 0.0, N, -1, SND_GRASS, {"support": true, "tint": true})
	_reg(NETHER_BRICK, "Адский кирпич", SH_CUBE, 2.0, 30.0, P, 0, SND_STONE)
	_reg(NETHER_FENCE, "Забор из адского кирпича", SH_FENCE, 2.0, 30.0, P, 0, SND_STONE)
	_reg(NETHER_BRICK_STAIRS, "Ступеньки из адского кирпича", SH_STAIRS, 2.0, 30.0, P, 0, SND_STONE)
	_reg(NETHER_WART, "Адский нарост", SH_CROPS, 0.0, 0.0, N, -1, SND_GRASS, {"support": true, "tick": true, "solid": false})
	_reg(ENCHANTING_TABLE, "Стол зачарований", SH_ENCHANT, 5.0, 6000.0, P, 0, SND_STONE)
	_reg(BREWING_STAND, "Варочная стойка", SH_BREWING, 0.5, 2.5, P, 0, SND_METAL, {"light": 1})
	_reg(CAULDRON, "Котёл", SH_CAULDRON, 2.0, 10.0, P, 0, SND_METAL)
	_reg(END_PORTAL, "Портал Края", SH_END_PORTAL, -1.0, 18000000.0, N, -1, SND_NONE, {"light": 15, "solid": false})
	_reg(END_PORTAL_FRAME, "Рамка портала Края", SH_END_FRAME, -1.0, 18000000.0, N, -1, SND_GLASS, {"light": 1})
	_reg(END_STONE, "Камень Края", SH_CUBE, 3.0, 45.0, P, 0, SND_STONE)
	_reg(DRAGON_EGG, "Яйцо дракона", SH_DRAGON_EGG, 3.0, 45.0, N, -1, SND_STONE, {"light": 1, "gravity": true})
	_reg(REDSTONE_LAMP, "Лампа", SH_CUBE, 0.3, 1.5, N, -1, SND_GLASS)
	_reg(LIT_REDSTONE_LAMP, "Лампа", SH_CUBE, 0.3, 1.5, N, -1, SND_GLASS, {"light": 15})


# --- Текстуры --------------------------------------------------------------

static func _side_top_bottom(face: int, side: int, top: int, bottom: int) -> int:
	if face == 2:
		return top
	if face == 3:
		return bottom
	return side


## Лицевая грань ориентированного блока (печь, тыква, раздатчик…) с направлением 0–3 в meta.
static func _front(face: int, meta: int, front: int, side: int, top: int) -> int:
	if face == 2 or face == 3:
		return top
	return front if face == DIR_FACE[meta & 3] else side


static func _tile(id: int, meta: int, face: int) -> int:
	match id:
		STONE:
			return Tex.STONE
		GRASS:
			return _side_top_bottom(face, Tex.GRASS_SIDE, Tex.GRASS_TOP, Tex.DIRT)
		DIRT:
			return Tex.DIRT
		COBBLESTONE:
			return Tex.COBBLESTONE
		PLANKS:
			return Tex.PLANKS_OAK + (meta & 3)
		SAPLING:
			return Tex.SAPLING_OAK + (meta & 3)
		BEDROCK:
			return Tex.BEDROCK
		FLOWING_WATER, WATER:
			return Tex.WATER
		FLOWING_LAVA, LAVA:
			return Tex.LAVA
		SAND:
			return Tex.SAND
		GRAVEL:
			return Tex.GRAVEL
		GOLD_ORE:
			return Tex.GOLD_ORE
		IRON_ORE:
			return Tex.IRON_ORE
		COAL_ORE:
			return Tex.COAL_ORE
		LOG:
			return _side_top_bottom(face, Tex.LOG_OAK + (meta & 3), Tex.LOG_TOP, Tex.LOG_TOP)
		LEAVES:
			return Tex.LEAVES_OAK + (meta & 3)
		SPONGE:
			return Tex.SPONGE
		GLASS:
			return Tex.GLASS
		LAPIS_ORE:
			return Tex.LAPIS_ORE
		LAPIS_BLOCK:
			return Tex.LAPIS_BLOCK
		DISPENSER:
			return _front(face, meta, Tex.DISPENSER_FRONT, Tex.FURNACE_SIDE, Tex.FURNACE_TOP)
		SANDSTONE:
			if face == 2:
				return Tex.SANDSTONE_TOP
			if face == 3:
				return Tex.SANDSTONE_BOTTOM if meta == 0 else Tex.SANDSTONE_TOP
			return [Tex.SANDSTONE_SIDE, Tex.SANDSTONE_CARVED, Tex.SANDSTONE_SMOOTH][clampi(meta, 0, 2)]
		NOTE_BLOCK:
			return Tex.NOTEBLOCK
		BED:
			return _bed_tile(meta, face)
		POWERED_RAIL:
			return Tex.RAIL_POWERED_ON if meta & 8 else Tex.RAIL_POWERED
		DETECTOR_RAIL:
			return Tex.RAIL_DETECTOR
		RAIL:
			return Tex.RAIL_CURVED if meta >= 6 else Tex.RAIL
		STICKY_PISTON, PISTON:
			return _piston_tile(id, meta, face)
		PISTON_HEAD:
			return Tex.PISTON_TOP_STICKY if meta & 8 else Tex.PISTON_TOP
		WEB:
			return Tex.WEB
		TALLGRASS:
			return [Tex.DEADBUSH, Tex.TALLGRASS, Tex.FERN][clampi(meta, 0, 2)]
		DEADBUSH:
			return Tex.DEADBUSH
		WOOL:
			return Tex.WOOL_0 + meta
		DANDELION:
			return Tex.DANDELION
		ROSE:
			return Tex.ROSE
		BROWN_MUSHROOM:
			return Tex.MUSHROOM_BROWN
		RED_MUSHROOM:
			return Tex.MUSHROOM_RED
		GOLD_BLOCK:
			return Tex.GOLD_BLOCK
		IRON_BLOCK:
			return Tex.IRON_BLOCK
		DOUBLE_SLAB, SLAB:
			return _slab_tile(meta & 7, face)
		BRICKS:
			return Tex.BRICK
		TNT:
			return _side_top_bottom(face, Tex.TNT_SIDE, Tex.TNT_TOP, Tex.TNT_BOTTOM)
		BOOKSHELF:
			return _side_top_bottom(face, Tex.BOOKSHELF, Tex.PLANKS_OAK, Tex.PLANKS_OAK)
		MOSSY_COBBLESTONE:
			return Tex.MOSSY_COBBLESTONE
		OBSIDIAN:
			return Tex.OBSIDIAN
		TORCH:
			return Tex.TORCH
		FIRE:
			return Tex.FIRE
		SPAWNER:
			return Tex.SPAWNER
		OAK_STAIRS, FENCE, FENCE_GATE, SIGN_POST, WALL_SIGN, WOODEN_PLATE:
			return Tex.PLANKS_OAK
		COBBLESTONE_STAIRS:
			return Tex.COBBLESTONE
		BRICK_STAIRS:
			return Tex.BRICK
		STONE_BRICK_STAIRS:
			return Tex.STONEBRICK
		NETHER_BRICK_STAIRS, NETHER_FENCE, NETHER_BRICK:
			return Tex.NETHER_BRICK
		CHEST, LOCKED_CHEST:
			return _front(face, meta, Tex.CHEST_FRONT, Tex.CHEST_SIDE, Tex.CHEST_TOP)
		REDSTONE_WIRE:
			return Tex.REDSTONE_DUST_CROSS
		DIAMOND_ORE:
			return Tex.DIAMOND_ORE
		DIAMOND_BLOCK:
			return Tex.DIAMOND_BLOCK
		CRAFTING_TABLE:
			if face == 2:
				return Tex.CRAFTING_TABLE_TOP
			if face == 3:
				return Tex.PLANKS_OAK
			return Tex.CRAFTING_TABLE_FRONT if face == 4 or face == 1 else Tex.CRAFTING_TABLE_SIDE
		WHEAT:
			return Tex.WHEAT_0 + mini(meta, 7)
		FARMLAND:
			if face == 2:
				return Tex.FARMLAND_WET if meta > 0 else Tex.FARMLAND_DRY
			return Tex.DIRT
		FURNACE:
			return _front(face, meta, Tex.FURNACE_FRONT, Tex.FURNACE_SIDE, Tex.FURNACE_TOP)
		LIT_FURNACE:
			return _front(face, meta, Tex.FURNACE_FRONT_LIT, Tex.FURNACE_SIDE, Tex.FURNACE_TOP)
		WOODEN_DOOR:
			return Tex.DOOR_WOOD_UPPER if meta & 8 else Tex.DOOR_WOOD_LOWER
		IRON_DOOR:
			return Tex.DOOR_IRON_UPPER if meta & 8 else Tex.DOOR_IRON_LOWER
		LADDER:
			return Tex.LADDER
		LEVER:
			return Tex.LEVER
		STONE_PLATE, STONE_BUTTON:
			return Tex.STONE
		REDSTONE_ORE, LIT_REDSTONE_ORE:
			return Tex.REDSTONE_ORE
		REDSTONE_TORCH_OFF:
			return Tex.REDSTONE_TORCH_OFF
		REDSTONE_TORCH:
			return Tex.REDSTONE_TORCH_ON
		SNOW_LAYER, SNOW:
			return Tex.SNOW
		ICE:
			return Tex.ICE
		CACTUS:
			return _side_top_bottom(face, Tex.CACTUS_SIDE, Tex.CACTUS_TOP, Tex.CACTUS_BOTTOM)
		CLAY:
			return Tex.CLAY
		REEDS:
			return Tex.REEDS
		JUKEBOX:
			return Tex.JUKEBOX_TOP if face == 2 else Tex.JUKEBOX_SIDE
		PUMPKIN:
			return _front(face, meta, Tex.PUMPKIN_FACE, Tex.PUMPKIN_SIDE, Tex.PUMPKIN_TOP)
		JACK_O_LANTERN:
			return _front(face, meta, Tex.PUMPKIN_FACE_LIT, Tex.PUMPKIN_SIDE, Tex.PUMPKIN_TOP)
		NETHERRACK:
			return Tex.NETHERRACK
		SOUL_SAND:
			return Tex.SOUL_SAND
		GLOWSTONE:
			return Tex.GLOWSTONE
		PORTAL:
			return Tex.PORTAL
		CAKE:
			if face == 2:
				return Tex.CAKE_TOP
			if face == 3:
				return Tex.CAKE_BOTTOM
			return Tex.CAKE_INNER if face == 1 and meta > 0 else Tex.CAKE_SIDE
		REPEATER_OFF:
			return Tex.REPEATER_OFF if face == 2 else Tex.SLAB_STONE_TOP
		REPEATER_ON:
			return Tex.REPEATER_ON if face == 2 else Tex.SLAB_STONE_TOP
		TRAPDOOR:
			return Tex.TRAPDOOR
		MONSTER_EGG:
			return [Tex.STONE, Tex.COBBLESTONE, Tex.STONEBRICK][clampi(meta, 0, 2)]
		STONE_BRICKS:
			return Tex.STONEBRICK + clampi(meta, 0, 3)
		BROWN_MUSHROOM_BLOCK, RED_MUSHROOM_BLOCK:
			return _mushroom_tile(id, meta, face)
		IRON_BARS:
			return Tex.IRON_BARS
		GLASS_PANE:
			return Tex.GLASS
		MELON:
			return _side_top_bottom(face, Tex.MELON_SIDE, Tex.MELON_TOP, Tex.MELON_TOP)
		PUMPKIN_STEM, MELON_STEM:
			return Tex.STEM_STRAIGHT
		VINE:
			return Tex.VINE
		MYCELIUM:
			return _side_top_bottom(face, Tex.MYCELIUM_SIDE, Tex.MYCELIUM_TOP, Tex.DIRT)
		WATERLILY:
			return Tex.WATERLILY
		NETHER_WART:
			return [Tex.NETHER_WART_0, Tex.NETHER_WART_1, Tex.NETHER_WART_1, Tex.NETHER_WART_2][mini(meta, 3)]
		ENCHANTING_TABLE:
			return _side_top_bottom(face, Tex.ENCHANTING_TABLE_SIDE, Tex.ENCHANTING_TABLE_TOP, Tex.ENCHANTING_TABLE_BOTTOM)
		BREWING_STAND:
			return Tex.BREWING_STAND
		CAULDRON:
			return _side_top_bottom(face, Tex.CAULDRON_SIDE, Tex.CAULDRON_TOP, Tex.CAULDRON_BOTTOM)
		END_PORTAL:
			return Tex.END_PORTAL
		END_PORTAL_FRAME:
			return _side_top_bottom(face, Tex.END_FRAME_SIDE, Tex.END_FRAME_TOP, Tex.END_STONE)
		END_STONE:
			return Tex.END_STONE
		DRAGON_EGG:
			return Tex.DRAGON_EGG
		REDSTONE_LAMP:
			return Tex.REDSTONE_LAMP_OFF
		LIT_REDSTONE_LAMP:
			return Tex.REDSTONE_LAMP_ON
	return Tex.STONE


static func _slab_tile(kind: int, face: int) -> int:
	match kind:
		1:
			return _side_top_bottom(face, Tex.SANDSTONE_SIDE, Tex.SANDSTONE_TOP, Tex.SANDSTONE_BOTTOM)
		2:
			return Tex.PLANKS_OAK
		3:
			return Tex.COBBLESTONE
		4:
			return Tex.BRICK
		5:
			return Tex.STONEBRICK
	return Tex.SLAB_STONE_TOP if face == 2 or face == 3 else Tex.SLAB_STONE_SIDE


## Кровать: meta 0–1 — направление от изножья к изголовью, 8 — изголовье.
static func _bed_tile(meta: int, face: int) -> int:
	var head := meta & 8 != 0
	if face == 2:
		return Tex.BED_HEAD_TOP if head else Tex.BED_FEET_TOP
	if face == 3:
		return Tex.PLANKS_OAK
	var dir := meta & 3
	var toward_head: int = DIR_FACE[dir]
	var toward_feet: int = OPPOSITE_FACE[toward_head]
	if head:
		return Tex.BED_HEAD_END if face == toward_head else Tex.BED_HEAD_SIDE
	return Tex.BED_FEET_END if face == toward_feet else Tex.BED_FEET_SIDE


## Поршень: meta 0–5 — направление (0 вниз, 1 вверх, 2 север, 3 юг, 4 запад, 5 восток), 8 — выдвинут.
static func _piston_tile(id: int, meta: int, face: int) -> int:
	var front := piston_face(meta & 7)
	if face == front:
		if meta & 8:
			return Tex.PISTON_INNER
		return Tex.PISTON_TOP_STICKY if id == STICKY_PISTON else Tex.PISTON_TOP
	if face == OPPOSITE_FACE[front]:
		return Tex.PISTON_BOTTOM
	return Tex.PISTON_SIDE


## Грань по направлению поршня (0 вниз, 1 вверх, 2 север, 3 юг, 4 запад, 5 восток).
static func piston_face(dir: int) -> int:
	return [3, 2, 5, 4, 1, 0][clampi(dir, 0, 5)]


static func piston_vec(dir: int) -> Vector3i:
	return FACE_VEC[piston_face(dir)]


## Огромные грибы: 0 — всё мякоть, 10 — ножка сбоку, 14 — всё шляпка, 15 — всё ножка,
## 1–9 — шляпка сверху и по краям (как в оригинале).
static func _mushroom_tile(id: int, meta: int, face: int) -> int:
	var skin := Tex.MUSHROOM_SKIN_BROWN if id == BROWN_MUSHROOM_BLOCK else Tex.MUSHROOM_SKIN_RED
	match meta:
		10:
			return Tex.MUSHROOM_INSIDE if face == 2 or face == 3 else Tex.MUSHROOM_SKIN_STEM
		14:
			return skin
		15:
			return Tex.MUSHROOM_SKIN_STEM
		0:
			return Tex.MUSHROOM_INSIDE
	if face == 2:
		return skin
	if face == 3:
		return Tex.MUSHROOM_INSIDE
	# Сетка 3×3 (1 — северо-запад … 9 — юго-восток): шляпка на внешних сторонах.
	var col := (meta - 1) % 3
	@warning_ignore("integer_division")
	var row := (meta - 1) / 3
	if (face == 1 and col == 0) or (face == 0 and col == 2) or (face == 5 and row == 0) or (face == 4 and row == 2):
		return skin
	return Tex.MUSHROOM_INSIDE


# --- Запросы ---------------------------------------------------------------

static func is_solid(id: int) -> bool:
	return solid_flags[id] == 1


static func is_opaque(id: int) -> bool:
	return opaque_flags[id] == 1


static func is_liquid(id: int) -> bool:
	return id >= FLOWING_WATER and id <= LAVA


static func is_water(id: int) -> bool:
	return id == WATER or id == FLOWING_WATER


static func is_lava(id: int) -> bool:
	return id == LAVA or id == FLOWING_LAVA


## Можно ли навести прицел на блок (жидкости и воздух — нельзя).
static func is_targetable(id: int) -> bool:
	return id != AIR and not is_liquid(id) and id != PISTON_MOVING


static func is_replaceable(id: int) -> bool:
	return replaceable_flags[id] == 1


static func block_name(id: int) -> String:
	return names[id] if id >= 0 and id < COUNT else "?"


static func hardness(id: int) -> float:
	return hardness_table[id]


static func light_of(id: int) -> int:
	return light_emission[id]


static func texture_of(id: int, face: int, meta: int = 0) -> int:
	return tile_table[(id * 16 + (meta & 15)) * 6 + face]


static func is_stairs(id: int) -> bool:
	return id == OAK_STAIRS or id == COBBLESTONE_STAIRS or id == BRICK_STAIRS or id == STONE_BRICK_STAIRS \
		or id == NETHER_BRICK_STAIRS


static func is_door(id: int) -> bool:
	return id == WOODEN_DOOR or id == IRON_DOOR


static func is_rail(id: int) -> bool:
	return id == RAIL or id == POWERED_RAIL or id == DETECTOR_RAIL


static func is_fence_like(id: int) -> bool:
	return id == FENCE or id == NETHER_FENCE


## Забор/панель соединяется с соседом.
static func connects_to(self_id: int, other: int) -> bool:
	if other == AIR:
		return false
	if self_id == FENCE or self_id == NETHER_FENCE:
		return other == self_id or other == FENCE_GATE or (is_opaque(other) and other != PUMPKIN and other != JACK_O_LANTERN)
	# Стеклянные панели и решётки.
	return other == GLASS_PANE or other == IRON_BARS or other == GLASS or is_opaque(other)


## Текстура верха травы под снегом.
static func grass_side_snowed() -> int:
	return Tex.GRASS_SIDE_SNOWED


# --- Добыча и дроп ---------------------------------------------------------

## Можно ли получить дроп этим инструментом (tool — Blocks.TOOL_*, tier — 0..4 или -1 рукой).
static func can_harvest(id: int, tool: int, tier: int) -> bool:
	var need := tier_table[id]
	if need < 0:
		if id == WEB:
			return tool == TOOL_SWORD or tool == TOOL_SHEARS
		if id == SNOW_LAYER or id == SNOW:
			return tool == TOOL_SHOVEL
		return true
	var t := tool_table[id]
	if t == TOOL_PICKAXE:
		return tool == TOOL_PICKAXE and tier >= need
	if t == TOOL_SHOVEL:
		return tool == TOOL_SHOVEL
	return true


## Подходит ли инструмент (ускоряет добычу).
static func tool_matches(id: int, tool: int) -> bool:
	var t := tool_table[id]
	if t == TOOL_NONE:
		return false
	if t == tool:
		return true
	if tool == TOOL_SWORD and id == WEB:
		return true
	if tool == TOOL_SHEARS and (id == LEAVES or id == WOOL or id == WEB or id == VINE):
		return true
	return false


## Время добычи в секундах (формула 1.2: прочность × 1.5 ÷ скорость, если блок «добывается»,
## иначе × 5). speed — скорость инструмента, если он подходит (1 — рука).
static func break_time(id: int, tool: int, tier: int, speed: float) -> float:
	var h := hardness_table[id]
	if h < 0.0:
		return INF
	if h == 0.0:
		return 0.0
	var mult := speed if tool_matches(id, tool) else 1.0
	if id == WOOL and tool == TOOL_SHEARS:
		mult = 5.0
	var base := 1.5 if can_harvest(id, tool, tier) else 5.0
	return h * base / maxf(mult, 0.1)


## Что выпадает при разрушении блока: массив [id предмета, количество, данные].
## rng — для случайных дропов (саженцы, семена, кремень…).
static func drops(id: int, meta: int, tool: int, tier: int, rng: RandomNumberGenerator) -> Array:
	if not can_harvest(id, tool, tier):
		return []
	match id:
		AIR, BEDROCK, FLOWING_WATER, WATER, FLOWING_LAVA, LAVA, PISTON_HEAD, PISTON_MOVING, FIRE, SPAWNER, \
				PORTAL, END_PORTAL, END_PORTAL_FRAME, GLASS, GLASS_PANE, ICE, BOOKSHELF, MONSTER_EGG, CAKE, \
				LOCKED_CHEST:
			return []
		STONE:
			return [[COBBLESTONE, 1, 0]]
		GRASS, MYCELIUM, FARMLAND:
			return [[DIRT, 1, 0]]
		PLANKS, SAPLING, LOG, WOOL:
			return [[id, 1, meta & 3 if id != WOOL else meta]]
		LEAVES:
			if tool == TOOL_SHEARS:
				return [[LEAVES, 1, meta & 3]]
			var out := []
			if rng.randi_range(1, 40 if (meta & 3) == 3 else 20) == 1:
				out.append([SAPLING, 1, meta & 3])
			if (meta & 3) == 0 and rng.randi_range(1, 200) == 1:
				out.append([Items.APPLE, 1, 0])
			return out
		GRAVEL:
			return [[Items.FLINT, 1, 0]] if rng.randi_range(1, 10) == 1 else [[GRAVEL, 1, 0]]
		COAL_ORE:
			return [[Items.COAL, 1, 0]]
		DIAMOND_ORE:
			return [[Items.DIAMOND, 1, 0]]
		LAPIS_ORE:
			return [[Items.DYE, rng.randi_range(4, 8), 4]]
		REDSTONE_ORE, LIT_REDSTONE_ORE:
			return [[Items.REDSTONE, rng.randi_range(4, 5), 0]]
		SANDSTONE:
			return [[SANDSTONE, 1, meta]]
		STONE_BRICKS:
			return [[STONE_BRICKS, 1, meta]]
		TALLGRASS:
			if tool == TOOL_SHEARS:
				return [[TALLGRASS, 1, meta]]
			return [[Items.SEEDS, 1, 0]] if rng.randi_range(1, 8) == 1 else []
		DEADBUSH:
			return [[DEADBUSH, 1, 0]] if tool == TOOL_SHEARS else []
		WEB:
			return [[Items.STRING, 1, 0]]
		VINE:
			return [[VINE, 1, 0]] if tool == TOOL_SHEARS else []
		DOUBLE_SLAB:
			return [[SLAB, 2, meta & 7]]
		SLAB:
			return [[SLAB, 1, meta & 7]]
		REDSTONE_WIRE:
			return [[Items.REDSTONE, 1, 0]]
		WHEAT:
			if meta >= 7:
				return [[Items.WHEAT, 1, 0], [Items.SEEDS, rng.randi_range(0, 3), 0]]
			return [[Items.SEEDS, 1, 0]]
		LIT_FURNACE:
			return [[FURNACE, 1, 0]]
		SIGN_POST, WALL_SIGN:
			return [[Items.SIGN, 1, 0]]
		WOODEN_DOOR:
			return [[Items.WOODEN_DOOR, 1, 0]] if meta & 8 == 0 else []
		IRON_DOOR:
			return [[Items.IRON_DOOR, 1, 0]] if meta & 8 == 0 else []
		BED:
			return [[Items.BED, 1, 0]] if meta & 8 == 0 else []
		REDSTONE_TORCH_OFF:
			return [[REDSTONE_TORCH, 1, 0]]
		SNOW_LAYER:
			return [[Items.SNOWBALL, 1, 0]]
		SNOW:
			return [[Items.SNOWBALL, 4, 0]]
		CLAY:
			return [[Items.CLAY_BALL, 4, 0]]
		REEDS:
			return [[Items.REEDS, 1, 0]]
		GLOWSTONE:
			return [[Items.GLOWSTONE_DUST, rng.randi_range(2, 4), 0]]
		REPEATER_OFF, REPEATER_ON:
			return [[Items.REPEATER, 1, 0]]
		BROWN_MUSHROOM_BLOCK:
			return [[BROWN_MUSHROOM, maxi(rng.randi_range(-7, 2), 0), 0]]
		RED_MUSHROOM_BLOCK:
			return [[RED_MUSHROOM, maxi(rng.randi_range(-7, 2), 0), 0]]
		MELON:
			return [[Items.MELON, rng.randi_range(3, 7), 0]]
		PUMPKIN_STEM:
			return [[Items.PUMPKIN_SEEDS, 1, 0]]
		MELON_STEM:
			return [[Items.MELON_SEEDS, 1, 0]]
		NETHER_WART:
			return [[Items.NETHER_WART, rng.randi_range(2, 4) if meta >= 3 else 1, 0]]
		BREWING_STAND:
			return [[Items.BREWING_STAND, 1, 0]]
		CAULDRON:
			return [[Items.CAULDRON, 1, 0]]
		LIT_REDSTONE_LAMP:
			return [[REDSTONE_LAMP, 1, 0]]
		PISTON, STICKY_PISTON:
			return [[id, 1, 0]]
		TORCH, REDSTONE_TORCH, LEVER, STONE_BUTTON, LADDER, RAIL, POWERED_RAIL, DETECTOR_RAIL, CHEST, FURNACE, \
				DISPENSER, PUMPKIN, JACK_O_LANTERN, TRAPDOOR, FENCE_GATE, TNT, DRAGON_EGG:
			return [[id, 1, 0]]
	return [[id, 1, 0]]


# --- Формы -----------------------------------------------------------------

## Параллелепипеды формы блока в координатах клетки (0..1). conn — маска соединений забора/панели
## (бит 0 юг, 1 запад, 2 север, 3 восток). for_collision — габариты для столкновений
## (забор выше, у некоторых форм своих столкновений нет).
static func shape_boxes(id: int, meta: int, conn: int = 0, for_collision: bool = false) -> Array[AABB]:
	var out: Array[AABB] = []
	match shapes[id]:
		SH_CUBE, SH_PISTON:
			out.append(AABB(Vector3.ZERO, Vector3.ONE))
		SH_SLAB:
			if meta & 8:
				out.append(_box(0, 8, 0, 16, 16, 16))
			else:
				out.append(_box(0, 0, 0, 16, 8, 16))
		SH_STAIRS:
			out.append(_box(0, 0, 0, 16, 8, 16))
			# Верхняя половина — с «дальней» стороны от того, кто ставил (meta — направление 0–3).
			match meta & 3:
				0:
					out.append(_box(0, 8, 8, 16, 16, 16))
				1:
					out.append(_box(0, 8, 0, 8, 16, 16))
				2:
					out.append(_box(0, 8, 0, 16, 16, 8))
				3:
					out.append(_box(8, 8, 0, 16, 16, 16))
		SH_FENCE:
			var top := 24.0 if for_collision else 16.0
			var lo := 6.0
			var hi := 10.0
			if for_collision:
				var x0 := 0.0 if conn & 2 else lo
				var x1 := 16.0 if conn & 8 else hi
				var z0 := 0.0 if conn & 4 else lo
				var z1 := 16.0 if conn & 1 else hi
				out.append(_box(x0, 0, lo, x1, top, hi))
				out.append(_box(lo, 0, z0, hi, top, z1))
			else:
				out.append(_box(lo, 0, lo, hi, 16, hi))
				for d in 4:
					if conn & (1 << d):
						for y: float in [6.0, 12.0]:
							out.append(_fence_bar(d, y))
		SH_PANE:
			var a := 7.0
			var b := 9.0
			var any := conn != 0
			var x0 := 0.0 if (conn & 2 or not any) else a
			var x1 := 16.0 if (conn & 8 or not any) else b
			var z0 := 0.0 if (conn & 4 or not any) else a
			var z1 := 16.0 if (conn & 1 or not any) else b
			if conn & 10 or not any:
				out.append(_box(x0, 0, a, x1, 16, b))
			if conn & 5 or not any:
				out.append(_box(a, 0, z0, b, 16, z1))
		SH_DOOR:
			out.append(_door_box(meta))
		SH_TRAPDOOR:
			if meta & 4:
				match meta & 3:
					0:
						out.append(_box(0, 0, 13, 16, 16, 16))
					1:
						out.append(_box(0, 0, 0, 16, 16, 3))
					2:
						out.append(_box(13, 0, 0, 16, 16, 16))
					3:
						out.append(_box(0, 0, 0, 3, 16, 16))
			else:
				out.append(_box(0, 0, 0, 16, 3, 16))
		SH_LADDER:
			out.append(_wall_box(meta & 3, 1.0))
		SH_VINE:
			for d in 4:
				if meta & (1 << d):
					out.append(_wall_box(d, 0.8))
			if out.is_empty():
				out.append(_box(0, 15.2, 0, 16, 16, 16))
		SH_BED:
			out.append(_box(0, 0, 0, 16, 9, 16))
		SH_CHEST:
			out.append(_box(1, 0, 1, 15, 14, 15))
		SH_CACTUS:
			out.append(_box(1, 0, 1, 15, 16 if not for_collision else 15, 15))
		SH_FARMLAND:
			out.append(_box(0, 0, 0, 16, 15, 16))
		SH_SNOW_LAYER:
			var h := 2.0 * ((meta & 7) + 1)
			if for_collision and (meta & 7) == 0:
				return out
			out.append(_box(0, 0, 0, 16, h, 16))
		SH_CAKE:
			out.append(_box(1 + 2 * (meta & 7), 0, 1, 15, 8, 15))
		SH_REPEATER:
			out.append(_box(0, 0, 0, 16, 2, 16))
		SH_LILYPAD:
			out.append(_box(0, 0, 0, 16, 0.25 if not for_collision else 1.0, 16))
		SH_ENCHANT:
			out.append(_box(0, 0, 0, 16, 12, 16))
		SH_END_FRAME:
			out.append(_box(0, 0, 0, 16, 13, 16))
		SH_CAULDRON:
			out.append(_box(0, 0, 0, 16, 16, 16))
		SH_BREWING:
			out.append(_box(7, 0, 7, 9, 14, 9))
			out.append(_box(0, 0, 0, 16, 2, 16))
		SH_DRAGON_EGG:
			out.append(_box(1, 0, 1, 15, 16, 15))
		SH_PISTON_HEAD:
			out.append(_piston_head_box(meta & 7))
		SH_GATE:
			if for_collision:
				if meta & 4:
					return out
				if (meta & 1) == 0:
					out.append(_box(0, 0, 6, 16, 24, 10))
				else:
					out.append(_box(6, 0, 0, 10, 24, 16))
			else:
				if (meta & 1) == 0:
					out.append(_box(0, 5, 7, 16, 16, 9))
				else:
					out.append(_box(7, 5, 0, 9, 16, 16))
		SH_PLATE:
			out.append(_box(1, 0, 1, 15, 0.5 if meta & 1 else 1, 15))
		SH_BUTTON:
			out.append(_button_box(meta & 7, meta & 8 != 0))
		SH_LEVER:
			out.append(_lever_box(meta & 7))
		SH_TORCH:
			out.append(_torch_box(meta & 7))
		SH_RAIL, SH_WIRE:
			out.append(_box(0, 0, 0, 16, 2, 16))
		SH_SIGN:
			if id == WALL_SIGN:
				out.append(_wall_box(meta & 3, 2.0).intersection(_box(0, 4.5, 0, 16, 12.5, 16)))
			else:
				out.append(_box(4, 0, 4, 12, 16, 12))
		SH_CROSS, SH_FIRE:
			out.append(_box(2, 0, 2, 14, 13, 14))
		SH_CROPS:
			out.append(_box(0, 0, 0, 16, 4 if id == NETHER_WART else 2 + 2 * mini(meta, 7), 16))
		SH_STEM:
			out.append(_box(6, 0, 6, 10, 2 + 2 * mini(meta, 7), 10))
		SH_PORTAL:
			if meta & 1:
				out.append(_box(6, 0, 0, 10, 16, 16))
			else:
				out.append(_box(0, 0, 6, 16, 16, 10))
		SH_END_PORTAL:
			out.append(_box(0, 0, 0, 16, 12, 16))
	return out


static func _box(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> AABB:
	return AABB(Vector3(x0, y0, z0) / 16.0, Vector3(x1 - x0, y1 - y0, z1 - z0) / 16.0)


static func _fence_bar(d: int, y: float) -> AABB:
	match d:
		0:
			return _box(7, y, 10, 9, y + 3, 16)
		1:
			return _box(0, y, 7, 6, y + 3, 9)
		2:
			return _box(7, y, 0, 9, y + 3, 6)
	return _box(10, y, 7, 16, y + 3, 9)


## Плоский блок у стены: d — направление, куда «смотрит» блок (его стена — с противоположной стороны).
static func _wall_box(d: int, thickness: float) -> AABB:
	var t := thickness
	match d:
		0:
			return _box(0, 0, 0, 16, 16, t)
		1:
			return _box(16 - t, 0, 0, 16, 16, 16)
		2:
			return _box(0, 0, 16 - t, 16, 16, 16)
	return _box(0, 0, 0, t, 16, 16)


## Дверь: meta 0–1 — направление (куда смотрит закрытая дверь), 4 — открыта, 8 — верхняя половина.
static func _door_box(meta: int) -> AABB:
	var d := meta & 3
	if meta & 4:
		d = (d + 1) % 4
	return _wall_box(d, 3.0)


static func _piston_head_box(dir: int) -> AABB:
	match dir:
		0:
			return _box(0, 0, 0, 16, 4, 16)
		1:
			return _box(0, 12, 0, 16, 16, 16)
		2:
			return _box(0, 0, 0, 16, 16, 4)
		3:
			return _box(0, 0, 12, 16, 16, 16)
		4:
			return _box(0, 0, 0, 4, 16, 16)
	return _box(12, 0, 0, 16, 16, 16)


## Крепление (факел, рычаг, кнопка): 0 — на полу, 1 — на блоке с запада (торчит на восток),
## 2 — на блоке с востока, 3 — на блоке с севера, 4 — на блоке с юга.
static func _torch_box(att: int) -> AABB:
	match att:
		1:
			return _box(0, 3, 5.5, 5, 13, 10.5)
		2:
			return _box(11, 3, 5.5, 16, 13, 10.5)
		3:
			return _box(5.5, 3, 0, 10.5, 13, 5)
		4:
			return _box(5.5, 3, 11, 10.5, 13, 16)
	return _box(6, 0, 6, 10, 10, 10)


static func _button_box(att: int, pressed: bool) -> AABB:
	var depth := 1.0 if pressed else 2.0
	match att:
		1:
			return _box(0, 6, 5, depth, 10, 11)
		2:
			return _box(16 - depth, 6, 5, 16, 10, 11)
		3:
			return _box(5, 6, 0, 11, 10, depth)
		4:
			return _box(5, 6, 16 - depth, 11, 10, 16)
	return _box(5, 0, 6, 11, depth, 10)


static func _lever_box(att: int) -> AABB:
	match att:
		1:
			return _box(0, 4, 5, 6, 12, 11)
		2:
			return _box(10, 4, 5, 16, 12, 11)
		3:
			return _box(5, 4, 0, 11, 12, 6)
		4:
			return _box(5, 4, 10, 11, 12, 16)
	return _box(4, 0, 4, 12, 10, 12)


## Направление крепления (0 — пол, 1–4 — стены) → смещение к опорному блоку.
static func attach_offset(att: int) -> Vector3i:
	match att:
		1:
			return Vector3i(-1, 0, 0)
		2:
			return Vector3i(1, 0, 0)
		3:
			return Vector3i(0, 0, -1)
		4:
			return Vector3i(0, 0, 1)
		5:
			return Vector3i(0, 1, 0)
	return Vector3i(0, -1, 0)


## Крепление по грани блока, к которой прикрепляют (грань опорного блока, на которую кликнули).
static func attach_from_face(face: int) -> int:
	match face:
		0:
			return 1
		1:
			return 2
		4:
			return 3
		5:
			return 4
		3:
			return 5
	return 0


# --- Блоки-контейнеры и прочее --------------------------------------------

## Блоки с данными-«сущностями» (содержимое сундука, печи, текст таблички…).
static func has_block_entity(id: int) -> bool:
	return id in [CHEST, FURNACE, LIT_FURNACE, DISPENSER, SIGN_POST, WALL_SIGN, SPAWNER, NOTE_BLOCK, JUKEBOX,
		BREWING_STAND, PISTON_MOVING, LOCKED_CHEST]


## Блоки, доступные в креативном инвентаре: [id, данные].
static func creative_blocks() -> Array:
	var out := []
	var simple := [STONE, GRASS, DIRT, COBBLESTONE]
	for id: int in simple:
		out.append([id, 0])
	for m in 4:
		out.append([PLANKS, m])
	for m in 4:
		out.append([SAPLING, m])
	out.append_array([[BEDROCK, 0], [SAND, 0], [GRAVEL, 0], [GOLD_ORE, 0], [IRON_ORE, 0], [COAL_ORE, 0]])
	for m in 4:
		out.append([LOG, m])
	for m in 4:
		out.append([LEAVES, m])
	out.append_array([[SPONGE, 0], [GLASS, 0], [LAPIS_ORE, 0], [LAPIS_BLOCK, 0], [DISPENSER, 0]])
	for m in 3:
		out.append([SANDSTONE, m])
	out.append_array([[NOTE_BLOCK, 0], [POWERED_RAIL, 0], [DETECTOR_RAIL, 0], [STICKY_PISTON, 0], [WEB, 0],
		[TALLGRASS, 1], [TALLGRASS, 2], [DEADBUSH, 0], [PISTON, 0]])
	for m in 16:
		out.append([WOOL, m])
	out.append_array([[DANDELION, 0], [ROSE, 0], [BROWN_MUSHROOM, 0], [RED_MUSHROOM, 0], [GOLD_BLOCK, 0],
		[IRON_BLOCK, 0]])
	for m in 6:
		out.append([SLAB, m])
	out.append_array([[BRICKS, 0], [TNT, 0], [BOOKSHELF, 0], [MOSSY_COBBLESTONE, 0], [OBSIDIAN, 0], [TORCH, 0],
		[SPAWNER, 0], [OAK_STAIRS, 0], [CHEST, 0], [DIAMOND_ORE, 0], [DIAMOND_BLOCK, 0], [CRAFTING_TABLE, 0],
		[FURNACE, 0], [LADDER, 0], [RAIL, 0], [COBBLESTONE_STAIRS, 0], [LEVER, 0], [STONE_PLATE, 0],
		[WOODEN_PLATE, 0], [REDSTONE_ORE, 0], [REDSTONE_TORCH, 0], [STONE_BUTTON, 0], [SNOW_LAYER, 0], [ICE, 0],
		[SNOW, 0], [CACTUS, 0], [CLAY, 0], [JUKEBOX, 0], [FENCE, 0], [PUMPKIN, 0], [NETHERRACK, 0],
		[SOUL_SAND, 0], [GLOWSTONE, 0], [JACK_O_LANTERN, 0], [TRAPDOOR, 0]])
	for m in 4:
		out.append([STONE_BRICKS, m])
	out.append_array([[BROWN_MUSHROOM_BLOCK, 14], [RED_MUSHROOM_BLOCK, 14], [IRON_BARS, 0], [GLASS_PANE, 0],
		[MELON, 0], [VINE, 0], [FENCE_GATE, 0], [BRICK_STAIRS, 0], [STONE_BRICK_STAIRS, 0], [MYCELIUM, 0],
		[WATERLILY, 0], [NETHER_BRICK, 0], [NETHER_FENCE, 0], [NETHER_BRICK_STAIRS, 0], [ENCHANTING_TABLE, 0],
		[END_PORTAL_FRAME, 0], [END_STONE, 0], [DRAGON_EGG, 0], [REDSTONE_LAMP, 0]])
	return out
