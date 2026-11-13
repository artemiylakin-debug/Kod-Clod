class_name Biomes
extends RefCounted
## Биомы Minecraft 1.2 (номера — как в оригинале): название, температура, влажность,
## цвет травы и листвы, параметры рельефа (minHeight/maxHeight) и поверхность.
## Джунгли (21–22) появились именно в 1.2.

enum {
	OCEAN = 0, PLAINS = 1, DESERT = 2, EXTREME_HILLS = 3, FOREST = 4, TAIGA = 5, SWAMPLAND = 6, RIVER = 7,
	HELL = 8, SKY = 9, FROZEN_OCEAN = 10, FROZEN_RIVER = 11, ICE_PLAINS = 12, ICE_MOUNTAINS = 13,
	MUSHROOM_ISLAND = 14, MUSHROOM_SHORE = 15, BEACH = 16, DESERT_HILLS = 17, FOREST_HILLS = 18,
	TAIGA_HILLS = 19, EXTREME_HILLS_EDGE = 20, JUNGLE = 21, JUNGLE_HILLS = 22,
	COUNT = 23,
}

## [название, температура, влажность, цвет травы, цвет листвы]
static var INFO := [
	["Океан", 0.5, 0.5, Color8(142, 185, 113), Color8(113, 167, 77)],
	["Равнины", 0.8, 0.4, Color8(145, 189, 89), Color8(119, 171, 47)],
	["Пустыня", 2.0, 0.0, Color8(191, 183, 85), Color8(174, 164, 42)],
	["Горы", 0.2, 0.3, Color8(138, 182, 137), Color8(109, 163, 107)],
	["Лес", 0.7, 0.8, Color8(121, 192, 90), Color8(89, 174, 48)],
	["Тайга", 0.05, 0.8, Color8(134, 183, 131), Color8(104, 164, 100)],
	["Болото", 0.8, 0.9, Color8(106, 112, 57), Color8(106, 112, 57)],
	["Река", 0.5, 0.5, Color8(142, 185, 113), Color8(113, 167, 77)],
	["Ад", 2.0, 0.0, Color8(191, 183, 85), Color8(174, 164, 42)],
	["Край", 0.5, 0.5, Color8(142, 185, 113), Color8(113, 167, 77)],
	["Замёрзший океан", 0.0, 0.5, Color8(128, 180, 151), Color8(96, 161, 123)],
	["Замёрзшая река", 0.0, 0.5, Color8(128, 180, 151), Color8(96, 161, 123)],
	["Ледяная равнина", 0.0, 0.5, Color8(128, 180, 151), Color8(96, 161, 123)],
	["Ледяные горы", 0.0, 0.5, Color8(128, 180, 151), Color8(96, 161, 123)],
	["Грибной остров", 0.9, 1.0, Color8(85, 201, 63), Color8(43, 187, 15)],
	["Берег грибного острова", 0.9, 1.0, Color8(85, 201, 63), Color8(43, 187, 15)],
	["Пляж", 0.8, 0.4, Color8(145, 189, 89), Color8(119, 171, 47)],
	["Пустынные холмы", 2.0, 0.0, Color8(191, 183, 85), Color8(174, 164, 42)],
	["Лесистые холмы", 0.7, 0.8, Color8(121, 192, 90), Color8(89, 174, 48)],
	["Холмы тайги", 0.05, 0.8, Color8(134, 183, 131), Color8(104, 164, 100)],
	["Предгорья", 0.2, 0.3, Color8(138, 182, 137), Color8(109, 163, 107)],
	["Джунгли", 1.2, 0.9, Color8(89, 201, 60), Color8(48, 187, 11)],
	["Холмы джунглей", 1.2, 0.9, Color8(89, 201, 60), Color8(48, 187, 11)],
]

## Рельеф биома, как setMinMaxHeight в 1.2: [minHeight (глубина), maxHeight (разброс высот)].
static var HEIGHTS := [
	[-1.0, 0.4], [0.1, 0.3], [0.1, 0.2], [0.2, 1.3], [0.1, 0.3], [0.1, 0.4], [-0.2, 0.1], [-0.5, 0.0],
	[0.1, 0.3], [0.1, 0.3], [-1.0, 0.5], [-0.5, 0.0], [0.1, 0.3], [0.2, 1.2], [0.2, 1.0], [-1.0, 0.1],
	[0.0, 0.1], [0.2, 0.7], [0.2, 0.6], [0.2, 0.7], [0.2, 0.8], [0.2, 0.4], [1.8, 0.5],
]

## Верхний блок и наполнитель поверхности (topBlock / fillerBlock).
static var TOP_BLOCKS := [
	Blocks.GRASS, Blocks.GRASS, Blocks.SAND, Blocks.GRASS, Blocks.GRASS, Blocks.GRASS, Blocks.GRASS, Blocks.GRASS,
	Blocks.NETHERRACK, Blocks.END_STONE, Blocks.GRASS, Blocks.GRASS, Blocks.GRASS, Blocks.GRASS, Blocks.MYCELIUM,
	Blocks.MYCELIUM, Blocks.SAND, Blocks.SAND, Blocks.GRASS, Blocks.GRASS, Blocks.GRASS, Blocks.GRASS, Blocks.GRASS,
]
static var FILLER_BLOCKS := [
	Blocks.DIRT, Blocks.DIRT, Blocks.SAND, Blocks.DIRT, Blocks.DIRT, Blocks.DIRT, Blocks.DIRT, Blocks.DIRT,
	Blocks.NETHERRACK, Blocks.END_STONE, Blocks.DIRT, Blocks.DIRT, Blocks.DIRT, Blocks.DIRT, Blocks.DIRT,
	Blocks.DIRT, Blocks.SAND, Blocks.SAND, Blocks.DIRT, Blocks.DIRT, Blocks.DIRT, Blocks.DIRT, Blocks.DIRT,
]

## Биомы, в которых может оказаться точка появления (как biomesToSpawnIn в 1.2).
static var SPAWN_BIOMES := [FOREST, PLAINS, TAIGA, TAIGA_HILLS, FOREST_HILLS, JUNGLE, JUNGLE_HILLS]


static func name_of(b: int) -> String:
	return INFO[clampi(b, 0, COUNT - 1)][0]


static func temperature(b: int) -> float:
	return INFO[clampi(b, 0, COUNT - 1)][1]


static func rainfall(b: int) -> float:
	return INFO[clampi(b, 0, COUNT - 1)][2]


static func grass_color(b: int) -> Color:
	return INFO[clampi(b, 0, COUNT - 1)][3]


static func foliage_color(b: int) -> Color:
	return INFO[clampi(b, 0, COUNT - 1)][4]


## Снег вместо дождя.
static func is_snowy(b: int) -> bool:
	return temperature(b) < 0.15


## Дождя не бывает (пустыни, Ад).
static func is_dry(b: int) -> bool:
	return rainfall(b) <= 0.0


static func min_height(b: int) -> float:
	return HEIGHTS[clampi(b, 0, COUNT - 1)][0]


static func max_height(b: int) -> float:
	return HEIGHTS[clampi(b, 0, COUNT - 1)][1]


static func top_block(b: int) -> int:
	return TOP_BLOCKS[clampi(b, 0, COUNT - 1)]


static func filler_block(b: int) -> int:
	return FILLER_BLOCKS[clampi(b, 0, COUNT - 1)]


static func is_ocean(b: int) -> bool:
	return b == OCEAN or b == FROZEN_OCEAN


static func is_river(b: int) -> bool:
	return b == RIVER or b == FROZEN_RIVER


static func is_desert(b: int) -> bool:
	return b == DESERT or b == DESERT_HILLS


static func is_jungle(b: int) -> bool:
	return b == JUNGLE or b == JUNGLE_HILLS


static func is_taiga(b: int) -> bool:
	return b == TAIGA or b == TAIGA_HILLS


static func is_forest(b: int) -> bool:
	return b == FOREST or b == FOREST_HILLS


static func is_mushroom(b: int) -> bool:
	return b == MUSHROOM_ISLAND or b == MUSHROOM_SHORE
