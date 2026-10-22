class_name Biomes
extends RefCounted
## Биомы Minecraft 1.2 (номера — как в оригинале): название, температура, влажность,
## цвет травы и листвы. Джунгли (21–22) появились именно в 1.2.

enum {
	OCEAN = 0, PLAINS = 1, DESERT = 2, EXTREME_HILLS = 3, FOREST = 4, TAIGA = 5, SWAMPLAND = 6, RIVER = 7,
	HELL = 8, SKY = 9, FROZEN_OCEAN = 10, FROZEN_RIVER = 11, ICE_PLAINS = 12, ICE_MOUNTAINS = 13,
	MUSHROOM_ISLAND = 14, MUSHROOM_SHORE = 15, BEACH = 16, DESERT_HILLS = 17, FOREST_HILLS = 18,
	TAIGA_HILLS = 19, EXTREME_HILLS_EDGE = 20, JUNGLE = 21, JUNGLE_HILLS = 22,
	COUNT = 23,
}

## [название, температура, влажность, цвет травы, цвет листвы]
const INFO := [
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
