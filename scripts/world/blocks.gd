class_name Blocks
extends RefCounted
## Реестр блоков: физические свойства, текстуры граней, прочность и дроп.

enum {
	AIR, GRASS, DIRT, STONE, COBBLESTONE, LOG, LEAVES, PLANKS, SAND, GLASS,
	BEDROCK, WATER, COAL_ORE, IRON_ORE, BRICKS, SNOW, GRAVEL, STONE_BRICKS,
	BOOKSHELF, COUNT,
}

## Слои текстурного массива: по одному тайлу 16×16 на слой.
enum {
	T_GRASS_TOP, T_GRASS_SIDE, T_DIRT, T_STONE, T_COBBLE, T_LOG_SIDE, T_LOG_TOP,
	T_LEAVES, T_PLANKS, T_SAND, T_GLASS, T_BEDROCK, T_WATER, T_COAL_ORE,
	T_IRON_ORE, T_BRICKS, T_SNOW, T_GRAVEL, T_STONE_BRICKS, T_BOOKSHELF,
	T_CRACK_0,
}

const CRACK_STAGES := 10
const TEXTURE_COUNT: int = T_CRACK_0 + CRACK_STAGES

const RENDER_NONE := 0
const RENDER_OPAQUE := 1
const RENDER_CUTOUT := 2
const RENDER_WATER := 3

## Грани: 0 +X, 1 -X, 2 +Y (верх), 3 -Y (низ), 4 +Z, 5 -Z.
## hardness — время добычи рукой в секундах (-1 — блок неразрушим).
const DEFS := [
	{"name": "Воздух", "solid": false, "render": RENDER_NONE,
		"tex": [0, 0, 0, 0, 0, 0], "hardness": 0.0, "drop": AIR},
	{"name": "Блок травы", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_GRASS_SIDE, T_GRASS_SIDE, T_GRASS_TOP, T_DIRT, T_GRASS_SIDE, T_GRASS_SIDE],
		"hardness": 0.6, "drop": DIRT},
	{"name": "Земля", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_DIRT, T_DIRT, T_DIRT, T_DIRT, T_DIRT, T_DIRT], "hardness": 0.5, "drop": DIRT},
	{"name": "Камень", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_STONE, T_STONE, T_STONE, T_STONE, T_STONE, T_STONE], "hardness": 1.5, "drop": COBBLESTONE},
	{"name": "Булыжник", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_COBBLE, T_COBBLE, T_COBBLE, T_COBBLE, T_COBBLE, T_COBBLE], "hardness": 2.0, "drop": COBBLESTONE},
	{"name": "Бревно", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_LOG_SIDE, T_LOG_SIDE, T_LOG_TOP, T_LOG_TOP, T_LOG_SIDE, T_LOG_SIDE], "hardness": 1.6, "drop": LOG},
	{"name": "Листва", "solid": true, "render": RENDER_CUTOUT,
		"tex": [T_LEAVES, T_LEAVES, T_LEAVES, T_LEAVES, T_LEAVES, T_LEAVES], "hardness": 0.25, "drop": AIR},
	{"name": "Доски", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_PLANKS, T_PLANKS, T_PLANKS, T_PLANKS, T_PLANKS, T_PLANKS], "hardness": 1.4, "drop": PLANKS},
	{"name": "Песок", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_SAND, T_SAND, T_SAND, T_SAND, T_SAND, T_SAND], "hardness": 0.5, "drop": SAND},
	{"name": "Стекло", "solid": true, "render": RENDER_CUTOUT,
		"tex": [T_GLASS, T_GLASS, T_GLASS, T_GLASS, T_GLASS, T_GLASS], "hardness": 0.3, "drop": AIR},
	{"name": "Коренная порода", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_BEDROCK, T_BEDROCK, T_BEDROCK, T_BEDROCK, T_BEDROCK, T_BEDROCK], "hardness": -1.0, "drop": AIR},
	{"name": "Вода", "solid": false, "render": RENDER_WATER,
		"tex": [T_WATER, T_WATER, T_WATER, T_WATER, T_WATER, T_WATER], "hardness": -1.0, "drop": AIR},
	{"name": "Угольная руда", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_COAL_ORE, T_COAL_ORE, T_COAL_ORE, T_COAL_ORE, T_COAL_ORE, T_COAL_ORE], "hardness": 2.4, "drop": COAL_ORE},
	{"name": "Железная руда", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_IRON_ORE, T_IRON_ORE, T_IRON_ORE, T_IRON_ORE, T_IRON_ORE, T_IRON_ORE], "hardness": 2.8, "drop": IRON_ORE},
	{"name": "Кирпичи", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_BRICKS, T_BRICKS, T_BRICKS, T_BRICKS, T_BRICKS, T_BRICKS], "hardness": 2.0, "drop": BRICKS},
	{"name": "Снег", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_SNOW, T_SNOW, T_SNOW, T_SNOW, T_SNOW, T_SNOW], "hardness": 0.4, "drop": SNOW},
	{"name": "Гравий", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_GRAVEL, T_GRAVEL, T_GRAVEL, T_GRAVEL, T_GRAVEL, T_GRAVEL], "hardness": 0.6, "drop": GRAVEL},
	{"name": "Каменные кирпичи", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_STONE_BRICKS, T_STONE_BRICKS, T_STONE_BRICKS, T_STONE_BRICKS, T_STONE_BRICKS, T_STONE_BRICKS],
		"hardness": 1.8, "drop": STONE_BRICKS},
	{"name": "Книжная полка", "solid": true, "render": RENDER_OPAQUE,
		"tex": [T_BOOKSHELF, T_BOOKSHELF, T_PLANKS, T_PLANKS, T_BOOKSHELF, T_BOOKSHELF], "hardness": 1.2, "drop": BOOKSHELF},
]

## Плоские таблицы свойств — быстрый доступ из горячих циклов (в том числе из рабочих потоков).
static var solid_flags := PackedByteArray()
## Непрозрачный полный куб: скрывает соседние грани и перекрывает небо.
static var opaque_flags := PackedByteArray()
## Отбрасывает ambient occlusion на соседние грани.
static var ao_flags := PackedByteArray()
static var render_types := PackedByteArray()
static var face_tex := PackedInt32Array()
## Блоки, которые не являются непрозрачными (используется для быстрых проверок слоёв).
static var non_opaque_ids := PackedInt32Array()


static func _static_init() -> void:
	for id in COUNT:
		var d: Dictionary = DEFS[id]
		var render: int = d["render"]
		solid_flags.append(1 if d["solid"] else 0)
		opaque_flags.append(1 if render == RENDER_OPAQUE else 0)
		ao_flags.append(1 if render == RENDER_OPAQUE or id == LEAVES else 0)
		render_types.append(render)
		if render != RENDER_OPAQUE:
			non_opaque_ids.append(id)
		var tex: Array = d["tex"]
		for f in 6:
			face_tex.append(int(tex[f]))


static func is_solid(id: int) -> bool:
	return solid_flags[id] == 1


static func is_opaque(id: int) -> bool:
	return opaque_flags[id] == 1


## Можно ли навести прицел на блок (вода и воздух — нельзя).
static func is_targetable(id: int) -> bool:
	return id != AIR and id != WATER


static func is_replaceable(id: int) -> bool:
	return id == AIR or id == WATER


static func block_name(id: int) -> String:
	return DEFS[id]["name"]


static func hardness(id: int) -> float:
	return DEFS[id]["hardness"]


static func drop_of(id: int) -> int:
	return DEFS[id]["drop"]


static func texture_of(id: int, face: int) -> int:
	return face_tex[id * 6 + face]


## Блоки, доступные в креативном инвентаре.
static func creative_palette() -> Array[int]:
	var out: Array[int] = []
	for id in range(1, COUNT):
		if id != WATER:
			out.append(id)
	return out
