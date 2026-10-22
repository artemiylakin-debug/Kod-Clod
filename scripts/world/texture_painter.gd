class_name TexturePainter
extends RefCounted
## Процедурные пиксельные текстуры 16×16 для всех тайлов Tex: грани блоков, спрайты предметов, трещины.
## Никаких внешних ассетов. paint_all() возвращает Tex.COUNT картинок RGBA8 без мипмапов.
## Результат детерминирован: перед каждым тайлом генератор получает своё фиксированное зерно,
## поэтому правка одного тайла не меняет остальные.
##
## Соглашения для рендера:
## - Tex.TINTED, REDSTONE_DUST_*, POTION_OVERLAY, SPAWN_EGG и SPAWN_EGG_OVERLAY — в оттенках серого (r == g == b);
## - «вырезные» тайлы используют только альфу 0 или 1; WATER (0.72), ICE (0.75) и PORTAL (0.8) полупрозрачны;
## - низкие блоки повторяют раскладку Minecraft: у боковин кровати тело в строках 7–15 (ножки — 13–15),
##   у торта боковина в строках 8–15 и столбцах 1–14, верх и низ торта — с прозрачной рамкой в 1 пиксель,
##   у стола зачарований боковина начинается со строки 4, у рамки портала Края — со строки 3,
##   у котла внизу боковины прозрачный проём между ножками, у верха котла прозрачна середина.

const S := 16
const CLEAR := Color(0, 0, 0, 0)
const INK := Color(0.1, 0.08, 0.07)
const WHITE := Color(1, 1, 1)
## Цвет каймы на боковой грани травы (≈ типичный оттенок биома × серый верх).
const GRASS_TINT := Color(0.47, 0.75, 0.35)

## Шерсть и красители — по значению данных Minecraft 0–15.
const WOOL_COLORS := [
	Color(0.87, 0.87, 0.87), Color(0.92, 0.53, 0.25), Color(0.75, 0.31, 0.79), Color(0.42, 0.55, 0.84),
	Color(0.78, 0.71, 0.16), Color(0.27, 0.72, 0.22), Color(0.85, 0.52, 0.6), Color(0.27, 0.27, 0.27),
	Color(0.62, 0.65, 0.65), Color(0.16, 0.46, 0.58), Color(0.49, 0.24, 0.73), Color(0.16, 0.21, 0.6),
	Color(0.34, 0.21, 0.12), Color(0.22, 0.31, 0.11), Color(0.63, 0.18, 0.16), Color(0.1, 0.1, 0.1),
]
const DYE_COLORS := [
	Color(0.16, 0.16, 0.2), Color(0.78, 0.16, 0.14), Color(0.33, 0.48, 0.12), Color(0.45, 0.27, 0.13),
	Color(0.18, 0.32, 0.78), Color(0.52, 0.22, 0.75), Color(0.16, 0.55, 0.62), Color(0.66, 0.66, 0.66),
	Color(0.34, 0.34, 0.34), Color(0.94, 0.58, 0.69), Color(0.5, 0.82, 0.16), Color(0.96, 0.86, 0.2),
	Color(0.53, 0.68, 0.96), Color(0.8, 0.32, 0.76), Color(0.95, 0.56, 0.16), Color(0.95, 0.95, 0.91),
]
## Цвет наклейки пластинок: 13, cat, blocks, chirp, far, mall, mellohi, stal, strad, ward, 11.
const RECORD_COLORS := [
	Color(0.95, 0.82, 0.2), Color(0.42, 0.85, 0.2), Color(0.9, 0.4, 0.14), Color(0.86, 0.14, 0.14),
	Color(0.66, 0.9, 0.32), Color(0.5, 0.36, 0.9), Color(0.9, 0.55, 0.9), Color(0.45, 0.45, 0.48),
	Color(0.96, 0.96, 0.96), Color(0.22, 0.52, 0.26), Color(0.15, 0.62, 0.58),
]
## Материалы инструментов: дерево, камень, железо, золото, алмаз.
const TOOL_COLORS := [Color(0.68, 0.52, 0.3), Color(0.54, 0.54, 0.54), Color(0.86, 0.86, 0.86),
	Color(0.98, 0.84, 0.25), Color(0.36, 0.9, 0.85)]
## Материалы брони: кожа, кольчуга, железо, алмаз, золото.
const ARMOR_COLORS := [Color(0.62, 0.38, 0.2), Color(0.64, 0.64, 0.66), Color(0.84, 0.84, 0.84),
	Color(0.36, 0.9, 0.85), Color(0.98, 0.84, 0.25)]
const STICK := Color(0.54, 0.38, 0.18)
const IRON := Color(0.8, 0.8, 0.82)
const GOLD := Color(0.98, 0.83, 0.24)
const SAND := Color(0.86, 0.81, 0.61)
const BED_RED := Color(0.64, 0.12, 0.12)
const BED_WOOD := Color(0.5, 0.35, 0.18)
const CHEST_WOOD := Color(0.62, 0.43, 0.2)
const DARK_WOOD := Color(0.4, 0.25, 0.17)
const PLANT := Color(0.3, 0.58, 0.16)

static var _rng := RandomNumberGenerator.new()
static var _cache: Dictionary = {}


## Рисует все тайлы. Индекс в массиве = значение перечисления Tex.
static func paint_all() -> Array[Image]:
	var out: Array[Image] = []
	out.resize(Tex.COUNT)
	_cache.clear()
	for i in Tex.COUNT:
		_rng.seed = 1202 + 7919 * i
		var img := _paint(i)
		if img == null:
			push_error("TexturePainter: нет рисунка для тайла %d" % i)
			img = _missing()
		# Прозрачные пиксели получают цвет соседей (альфа остаётся 0), чтобы мипмапы не давали тёмной каймы.
		img.fix_alpha_edges()
		out[i] = img
	_cache.clear()
	return out


static func _paint(i: int) -> Image:
	if i >= Tex.WOOL_0 and i <= Tex.WOOL_15:
		return _wool(WOOL_COLORS[i - Tex.WOOL_0])
	if i >= Tex.LOG_OAK and i <= Tex.LOG_JUNGLE:
		return _log_side(i - Tex.LOG_OAK)
	if i >= Tex.PLANKS_OAK and i <= Tex.PLANKS_JUNGLE:
		return _copy("planks%d" % (i - Tex.PLANKS_OAK))
	if i >= Tex.LEAVES_OAK and i <= Tex.LEAVES_JUNGLE:
		return _leaves(i - Tex.LEAVES_OAK)
	if i >= Tex.SAPLING_OAK and i <= Tex.SAPLING_JUNGLE:
		return _sapling(i - Tex.SAPLING_OAK)
	if i >= Tex.WHEAT_0 and i <= Tex.WHEAT_7:
		return _wheat(i - Tex.WHEAT_0)
	if i >= Tex.NETHER_WART_0 and i <= Tex.NETHER_WART_2:
		return _nether_wart(i - Tex.NETHER_WART_0)
	if i >= Tex.CRACK_0 and i <= Tex.CRACK_9:
		return _crack(i - Tex.CRACK_0)
	if i >= Tex.SWORD_WOOD and i <= Tex.HOE_DIAMOND:
		var k := i - Tex.SWORD_WOOD
		return _tool(floori(k / 5.0), k % 5)
	if i >= Tex.HELMET_LEATHER and i <= Tex.BOOTS_GOLD:
		var k := i - Tex.HELMET_LEATHER
		return _armor(k % 4, floori(k / 4.0))
	if i >= Tex.DYE_0 and i <= Tex.DYE_15:
		return _dye(i - Tex.DYE_0)
	if i >= Tex.RECORD_13 and i <= Tex.RECORD_11:
		return _record(i - Tex.RECORD_13)
	match i:
		# --- Природа ---
		Tex.STONE: return _copy("stone")
		Tex.GRASS_TOP: return _copy("grass_top")
		Tex.GRASS_SIDE: return _fringe(_copy("dirt"), _base("grass_top"), GRASS_TINT, 3)
		Tex.GRASS_SIDE_SNOWED: return _fringe(_copy("dirt"), _base("snow"), WHITE, 3)
		Tex.DIRT: return _copy("dirt")
		Tex.COBBLESTONE: return _copy("cobble")
		Tex.MOSSY_COBBLESTONE: return _mossy(_copy("cobble"))
		Tex.BEDROCK: return _bedrock()
		Tex.SAND: return _copy("sand")
		Tex.GRAVEL: return _gravel()
		Tex.CLAY: return _clay()
		Tex.SNOW: return _copy("snow")
		Tex.ICE: return _ice()
		Tex.OBSIDIAN: return _copy("obsidian")
		Tex.MYCELIUM_TOP: return _copy("mycelium")
		Tex.MYCELIUM_SIDE: return _fringe(_copy("dirt"), _base("mycelium"), WHITE, 2)
		Tex.SOUL_SAND: return _soul_sand()
		Tex.NETHERRACK: return _netherrack()
		Tex.GLOWSTONE: return _glowstone()
		Tex.END_STONE: return _copy("end_stone")
		Tex.SPONGE: return _sponge()
		Tex.WEB: return _web()
		Tex.WATER: return _water()
		Tex.LAVA: return _lava()
		# --- Руды и блоки ресурсов ---
		Tex.COAL_ORE: return _ore(Color(0.13, 0.13, 0.13), Color(0.32, 0.32, 0.32))
		Tex.IRON_ORE: return _ore(Color(0.84, 0.66, 0.52), Color(0.95, 0.84, 0.74))
		Tex.GOLD_ORE: return _ore(Color(0.98, 0.84, 0.18), Color(1.0, 0.98, 0.6))
		Tex.DIAMOND_ORE: return _ore(Color(0.36, 0.88, 0.86), Color(0.82, 1.0, 1.0))
		Tex.REDSTONE_ORE: return _ore(Color(0.82, 0.04, 0.04), Color(1.0, 0.42, 0.38))
		Tex.LAPIS_ORE: return _ore(Color(0.14, 0.28, 0.74), Color(0.4, 0.56, 0.95))
		Tex.IRON_BLOCK: return _metal_block(Color(0.84, 0.84, 0.84), 0)
		Tex.GOLD_BLOCK: return _metal_block(Color(0.98, 0.82, 0.22), 1)
		Tex.DIAMOND_BLOCK: return _metal_block(Color(0.45, 0.9, 0.86), 2)
		Tex.LAPIS_BLOCK: return _lapis_block()
		# --- Дерево и растения ---
		Tex.LOG_TOP: return _log_top()
		Tex.TALLGRASS: return _tallgrass()
		Tex.FERN: return _fern()
		Tex.DEADBUSH: return _deadbush()
		Tex.DANDELION: return _spr(DANDELION, [Color(0.98, 0.86, 0.14), PLANT])
		Tex.ROSE: return _spr(ROSE, [Color(0.86, 0.12, 0.1), PLANT])
		Tex.MUSHROOM_BROWN: return _spr(MUSHROOM_BROWN, [Color(0.64, 0.47, 0.34), Color(0.86, 0.8, 0.7)])
		Tex.MUSHROOM_RED: return _spr(MUSHROOM_RED, [Color(0.86, 0.12, 0.12), Color(0.86, 0.8, 0.7)])
		Tex.REEDS: return _reeds()
		Tex.CACTUS_SIDE: return _cactus_side()
		Tex.CACTUS_TOP: return _cactus_end(false)
		Tex.CACTUS_BOTTOM: return _cactus_end(true)
		Tex.VINE: return _vine()
		Tex.WATERLILY: return _waterlily()
		Tex.STEM_STRAIGHT: return _stem(false)
		Tex.STEM_BENT: return _stem(true)
		Tex.PUMPKIN_TOP: return _pumpkin_top()
		Tex.PUMPKIN_SIDE: return _copy("pumpkin_side")
		Tex.PUMPKIN_FACE: return _pumpkin_face(false)
		Tex.PUMPKIN_FACE_LIT: return _pumpkin_face(true)
		Tex.MELON_SIDE: return _melon_side()
		Tex.MELON_TOP: return _melon_top()
		Tex.MUSHROOM_SKIN_BROWN: return _speckled(Color(0.56, 0.42, 0.3), 0.05, Color(0.47, 0.34, 0.23), 0.16)
		Tex.MUSHROOM_SKIN_RED: return _mushroom_skin_red()
		Tex.MUSHROOM_SKIN_STEM: return _mushroom_stem()
		Tex.MUSHROOM_INSIDE: return _mushroom_inside()
		Tex.FARMLAND_DRY: return _farmland(false)
		Tex.FARMLAND_WET: return _farmland(true)
		# --- Строительные блоки ---
		Tex.SANDSTONE_SIDE: return _sandstone(0)
		Tex.SANDSTONE_TOP: return _sandstone(1)
		Tex.SANDSTONE_BOTTOM: return _sandstone(2)
		Tex.SANDSTONE_CARVED: return _sandstone(3)
		Tex.SANDSTONE_SMOOTH: return _sandstone(4)
		Tex.BRICK: return _bricks()
		Tex.STONEBRICK: return _copy("stonebrick")
		Tex.STONEBRICK_MOSSY: return _mossy(_copy("stonebrick"))
		Tex.STONEBRICK_CRACKED: return _stonebrick_cracked()
		Tex.STONEBRICK_CARVED: return _stonebrick_carved()
		Tex.SLAB_STONE_SIDE: return _slab_side()
		Tex.SLAB_STONE_TOP: return _copy("smooth")
		Tex.NETHER_BRICK: return _nether_brick()
		Tex.GLASS: return _glass()
		Tex.IRON_BARS: return _iron_bars()
		Tex.BOOKSHELF: return _bookshelf()
		# --- Механизмы и мебель ---
		Tex.CRAFTING_TABLE_TOP: return _crafting_top()
		Tex.CRAFTING_TABLE_SIDE: return _crafting_side(false)
		Tex.CRAFTING_TABLE_FRONT: return _crafting_side(true)
		Tex.FURNACE_SIDE: return _copy("furnace_side")
		Tex.FURNACE_TOP: return _copy("furnace_top")
		Tex.FURNACE_FRONT: return _furnace_front(false)
		Tex.FURNACE_FRONT_LIT: return _furnace_front(true)
		Tex.DISPENSER_FRONT: return _dispenser_front()
		Tex.CHEST_TOP: return _chest(0)
		Tex.CHEST_SIDE: return _chest(1)
		Tex.CHEST_FRONT: return _chest(2)
		Tex.JUKEBOX_TOP: return _jukebox_top()
		Tex.JUKEBOX_SIDE: return _jukebox_side()
		Tex.NOTEBLOCK: return _copy("noteblock")
		Tex.TNT_SIDE: return _tnt_side()
		Tex.TNT_TOP: return _tnt_end(true)
		Tex.TNT_BOTTOM: return _tnt_end(false)
		Tex.SPAWNER: return _spawner()
		Tex.TORCH: return _torch(0)
		Tex.REDSTONE_TORCH_ON: return _torch(1)
		Tex.REDSTONE_TORCH_OFF: return _torch(2)
		Tex.LADDER: return _ladder()
		Tex.LEVER: return _lever()
		Tex.DOOR_WOOD_LOWER: return _door(false, false)
		Tex.DOOR_WOOD_UPPER: return _door(false, true)
		Tex.DOOR_IRON_LOWER: return _door(true, false)
		Tex.DOOR_IRON_UPPER: return _door(true, true)
		Tex.TRAPDOOR: return _trapdoor()
		Tex.RAIL: return _rail(0)
		Tex.RAIL_CURVED: return _rail_curved()
		Tex.RAIL_POWERED: return _rail(1)
		Tex.RAIL_POWERED_ON: return _rail(2)
		Tex.RAIL_DETECTOR: return _rail(3)
		Tex.REDSTONE_DUST_CROSS: return _dust(true)
		Tex.REDSTONE_DUST_LINE: return _dust(false)
		Tex.REPEATER_OFF: return _repeater(false)
		Tex.REPEATER_ON: return _repeater(true)
		Tex.REDSTONE_LAMP_OFF: return _lamp(false)
		Tex.REDSTONE_LAMP_ON: return _lamp(true)
		Tex.PISTON_SIDE: return _piston_side()
		Tex.PISTON_TOP: return _piston_top(false)
		Tex.PISTON_TOP_STICKY: return _piston_top(true)
		Tex.PISTON_BOTTOM: return _piston_bottom()
		Tex.PISTON_INNER: return _piston_inner()
		Tex.BED_FEET_TOP: return _bed_top(false)
		Tex.BED_FEET_SIDE: return _bed_side(false)
		Tex.BED_FEET_END: return _bed_end(false)
		Tex.BED_HEAD_TOP: return _bed_top(true)
		Tex.BED_HEAD_SIDE: return _bed_side(true)
		Tex.BED_HEAD_END: return _bed_end(true)
		Tex.CAKE_TOP: return _cake(0)
		Tex.CAKE_SIDE: return _cake(1)
		Tex.CAKE_INNER: return _cake(2)
		Tex.CAKE_BOTTOM: return _cake(3)
		Tex.FIRE: return _fire()
		Tex.PORTAL: return _portal()
		Tex.END_PORTAL: return _end_portal()
		Tex.ENCHANTING_TABLE_TOP: return _enchanting(0)
		Tex.ENCHANTING_TABLE_SIDE: return _enchanting(1)
		Tex.ENCHANTING_TABLE_BOTTOM: return _copy("obsidian")
		Tex.BREWING_STAND: return _spr(BREWING_STAND, [Color(0.5, 0.5, 0.5), Color(0.96, 0.74, 0.24)],
				{"g": Color(0.8, 0.88, 0.96)})
		Tex.BREWING_STAND_BASE: return _brewing_base()
		Tex.CAULDRON_SIDE: return _cauldron(0)
		Tex.CAULDRON_TOP: return _cauldron(1)
		Tex.CAULDRON_INNER: return _cauldron(2)
		Tex.CAULDRON_BOTTOM: return _cauldron(3)
		Tex.END_FRAME_TOP: return _end_frame(0)
		Tex.END_FRAME_SIDE: return _end_frame(1)
		Tex.END_FRAME_EYE: return _end_frame(2)
		Tex.DRAGON_EGG: return _dragon_egg()
		# --- Снаряжение ---
		Tex.FLINT_AND_STEEL: return _outline(_spr(FLINT_STEEL, [IRON, Color(0.32, 0.32, 0.34)]), INK)
		Tex.BOW: return _bow(-1)
		Tex.BOW_PULL_0: return _bow(0)
		Tex.BOW_PULL_1: return _bow(1)
		Tex.BOW_PULL_2: return _bow(2)
		Tex.ARROW: return _outline(_spr(ARROW, [IRON, STICK]), INK)
		Tex.FISHING_ROD: return _fishing_rod(false)
		Tex.FISHING_ROD_CAST: return _fishing_rod(true)
		Tex.SHEARS: return _shears()
		Tex.BUCKET: return _bucket(0)
		Tex.BUCKET_WATER: return _bucket(1)
		Tex.BUCKET_LAVA: return _bucket(2)
		Tex.BUCKET_MILK: return _bucket(3)
		Tex.COMPASS: return _compass()
		Tex.CLOCK: return _clock()
		Tex.MAP: return _map()
		Tex.SADDLE: return _outline(_spr(SADDLE, [Color(0.56, 0.32, 0.15), IRON]), INK)
		Tex.MINECART: return _minecart(0)
		Tex.MINECART_CHEST: return _minecart(1)
		Tex.MINECART_FURNACE: return _minecart(2)
		Tex.BOAT: return _outline(_spr(BOAT, [Color(0.58, 0.41, 0.22)]), INK)
		Tex.SIGN: return _sign()
		Tex.DOOR_WOOD: return _door_item(false)
		Tex.DOOR_IRON: return _door_item(true)
		Tex.BED: return _bed_item()
		Tex.CAKE: return _cake_item()
		Tex.REPEATER: return _repeater_item()
		Tex.CAULDRON: return _cauldron_item()
		Tex.BREWING_STAND_ITEM: return _brewing_item()
		Tex.PAINTING: return _painting()
		# --- Материалы ---
		Tex.COAL: return _lump(Color(0.2, 0.2, 0.22), Color(0.42, 0.42, 0.45))
		Tex.CHARCOAL: return _lump(Color(0.24, 0.19, 0.15), Color(0.42, 0.34, 0.27))
		Tex.DIAMOND: return _outline(_spr(DIAMOND, [Color(0.36, 0.9, 0.85)]), Color(0.08, 0.3, 0.3))
		Tex.IRON_INGOT: return _outline(_spr(INGOT, [Color(0.84, 0.84, 0.84)]), Color(0.25, 0.25, 0.27))
		Tex.GOLD_INGOT: return _outline(_spr(INGOT, [GOLD]), Color(0.4, 0.27, 0.02))
		Tex.GOLD_NUGGET: return _nugget()
		Tex.STICK: return _stick()
		Tex.BOWL: return _bowl(false)
		Tex.STRING: return _string()
		Tex.FEATHER: return _feather()
		Tex.GUNPOWDER: return _pile(Color(0.36, 0.36, 0.37), Color(0.6, 0.6, 0.6))
		Tex.FLINT: return _outline(_spr(FLINT, [Color(0.36, 0.36, 0.38)]), INK)
		Tex.LEATHER: return _leather()
		Tex.BRICK_ITEM: return _outline(_spr(INGOT, [Color(0.68, 0.32, 0.22)]), Color(0.25, 0.08, 0.04))
		Tex.CLAY_BALL: return _ball_item(Color(0.64, 0.67, 0.75), 4.6)
		Tex.REEDS_ITEM: return _reeds_item()
		Tex.PAPER: return _paper()
		Tex.BOOK: return _book()
		Tex.SLIMEBALL: return _slimeball()
		Tex.REDSTONE: return _pile(Color(0.72, 0.04, 0.03), Color(1.0, 0.34, 0.28))
		Tex.GLOWSTONE_DUST: return _pile(Color(0.94, 0.78, 0.34), Color(1.0, 0.98, 0.72))
		Tex.BONE: return _bone()
		Tex.SUGAR: return _pile(Color(0.95, 0.95, 0.96), Color(0.78, 0.8, 0.85))
		Tex.SNOWBALL: return _ball_item(Color(0.96, 0.98, 1.0), 4.8)
		Tex.EGG: return _egg()
		Tex.ENDER_PEARL: return _ender_pearl()
		Tex.EYE_OF_ENDER: return _eye_of_ender()
		Tex.BLAZE_ROD: return _blaze_rod()
		Tex.BLAZE_POWDER: return _pile(Color(0.98, 0.58, 0.1), Color(1.0, 0.92, 0.4))
		Tex.GHAST_TEAR: return _ghast_tear()
		Tex.MAGMA_CREAM: return _magma_cream()
		Tex.NETHER_WART_ITEM: return _nether_wart_item()
		Tex.SPIDER_EYE: return _spider_eye(false)
		Tex.FERMENTED_SPIDER_EYE: return _spider_eye(true)
		Tex.SPECKLED_MELON: return _melon_slice(true)
		Tex.GLASS_BOTTLE: return _bottle(BOTTLE, CLEAR)
		Tex.POTION: return _bottle(BOTTLE, CLEAR)
		Tex.POTION_SPLASH: return _bottle(BOTTLE_SPLASH, CLEAR)
		Tex.POTION_OVERLAY: return _potion_overlay()
		Tex.EXP_BOTTLE: return _bottle(BOTTLE, Color(0.52, 0.86, 0.22))
		Tex.FIRE_CHARGE: return _fire_charge()
		Tex.SPAWN_EGG: return _spawn_egg(false)
		Tex.SPAWN_EGG_OVERLAY: return _spawn_egg(true)
		Tex.SEEDS_WHEAT: return _seeds(Color(0.42, 0.66, 0.18), 7, 1)
		Tex.SEEDS_PUMPKIN: return _seeds(Color(0.93, 0.88, 0.64), 4, 2)
		Tex.SEEDS_MELON: return _seeds(Color(0.2, 0.14, 0.08), 5, 1)
		Tex.WHEAT: return _wheat_item()
		# --- Еда ---
		Tex.APPLE: return _outline(_spr(APPLE, [Color(0.86, 0.12, 0.12), STICK, PLANT]), Color(0.3, 0.03, 0.03))
		Tex.APPLE_GOLDEN: return _outline(_spr(APPLE, [GOLD, STICK, Color(0.9, 0.74, 0.2)]), Color(0.4, 0.26, 0.02))
		Tex.BREAD: return _bread()
		Tex.MUSHROOM_STEW: return _bowl(true)
		Tex.PORKCHOP_RAW: return _chop(Color(0.94, 0.58, 0.58), Color(0.99, 0.88, 0.85), Color(0.42, 0.16, 0.16))
		Tex.PORKCHOP_COOKED: return _chop(Color(0.56, 0.32, 0.19), Color(0.86, 0.66, 0.44), Color(0.22, 0.1, 0.04))
		Tex.BEEF_RAW: return _steak(false)
		Tex.BEEF_COOKED: return _steak(true)
		Tex.CHICKEN_RAW: return _drumstick(Color(0.96, 0.78, 0.72))
		Tex.CHICKEN_COOKED: return _drumstick(Color(0.78, 0.52, 0.26))
		Tex.FISH_RAW: return _fish(false)
		Tex.FISH_COOKED: return _fish(true)
		Tex.COOKIE: return _cookie()
		Tex.MELON_SLICE: return _melon_slice(false)
		Tex.ROTTEN_FLESH: return _rotten_flesh()
	return null


# --- Общие помощники ----------------------------------------------------------

static func _new() -> Image:
	return Image.create(S, S, false, Image.FORMAT_RGBA8)


static func _missing() -> Image:
	var img := _new()
	for y in S:
		for x in S:
			img.set_pixel(x, y, Color(1, 0, 1) if ((x >> 2) + (y >> 2)) % 2 == 0 else Color(0, 0, 0))
	return img


## Общие заготовки (камень, земля, доски…) рисуются один раз со своим зерном.
static func _base(key: String) -> Image:
	if not _cache.has(key):
		var saved := _rng.state
		_rng.seed = hash(key)
		_cache[key] = _make_base(key)
		_rng.state = saved
	return _cache[key]


static func _copy(key: String) -> Image:
	return _base(key).duplicate() as Image


static func _make_base(key: String) -> Image:
	match key:
		"stone": return _stone()
		"dirt": return _dirt()
		"grass_top": return _grass_top()
		"cobble": return _voronoi(9, [_g(0.42), _g(0.47), _g(0.52), _g(0.57), _g(0.63)], _g(0.27))
		"planks0": return _planks(Color(0.7, 0.54, 0.32))
		"planks1": return _planks(Color(0.42, 0.31, 0.18))
		"planks2": return _planks(Color(0.8, 0.72, 0.5))
		"planks3": return _planks(Color(0.62, 0.43, 0.3))
		"sand": return _speckled(Color(0.86, 0.8, 0.58), 0.05, Color(0.76, 0.69, 0.48), 0.1)
		"snow": return _speckled(Color(0.95, 0.97, 1.0), 0.02, Color(0.86, 0.9, 0.97), 0.08)
		"obsidian": return _obsidian()
		"mycelium": return _mycelium()
		"end_stone": return _end_stone()
		"stonebrick": return _stonebrick()
		"smooth": return _smooth_stone(Color(0.66, 0.66, 0.66))
		"furnace_top": return _smooth_stone(Color(0.46, 0.46, 0.46))
		"furnace_side": return _furnace_side()
		"pumpkin_side": return _pumpkin_side()
		"noteblock": return _noteblock()
	push_error("TexturePainter: неизвестная заготовка " + key)
	return _missing()


static func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


static func _vary(c: Color, amount: float) -> Color:
	return _shade(c, 1.0 + _rng.randf_range(-amount, amount))


static func _light(c: Color, t: float) -> Color:
	return Color(lerpf(c.r, 1.0, t), lerpf(c.g, 1.0, t), lerpf(c.b, 1.0, t), c.a)


static func _g(v: float, a: float = 1.0) -> Color:
	return Color(v, v, v, a)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < S and y < S:
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)


static func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	for _guard in 64:
		_px(img, x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


static func _opaque(img: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < S and y < S and img.get_pixel(x, y).a > 0.5


## Каждый пиксель — базовый цвет со случайной яркостью.
static func _noise_fill(base: Color, amount: float) -> Image:
	var img := _new()
	for y in S:
		for x in S:
			img.set_pixel(x, y, _vary(base, amount))
	return img


static func _speckled(base: Color, amount: float, speck: Color, chance: float) -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var c := _vary(base, amount)
			if _rng.randf() < chance:
				c = _vary(speck, amount)
			img.set_pixel(x, y, c)
	return img


## Бесшовный value-шум 16×16 (значения 0..1); cells — число ячеек решётки по горизонтали,
## cells_y — по вертикали (0 — столько же).
static func _vnoise(cells: int, cells_y: int = 0) -> PackedFloat32Array:
	var cy := cells if cells_y <= 0 else cells_y
	var grid := PackedFloat32Array()
	grid.resize(cells * cy)
	for i in grid.size():
		grid[i] = _rng.randf()
	var out := PackedFloat32Array()
	out.resize(S * S)
	var kx := float(cells) / S
	var ky := float(cy) / S
	for y in S:
		var fy := y * ky
		var iy := int(fy)
		var ty := fy - iy
		ty = ty * ty * (3.0 - 2.0 * ty)
		var y1 := (iy + 1) % cy
		for x in S:
			var fx := x * kx
			var ix := int(fx)
			var tx := fx - ix
			tx = tx * tx * (3.0 - 2.0 * tx)
			var x1 := (ix + 1) % cells
			var a := lerpf(grid[iy * cells + ix], grid[iy * cells + x1], tx)
			var b := lerpf(grid[y1 * cells + ix], grid[y1 * cells + x1], tx)
			out[y * S + x] = lerpf(a, b, ty)
	return out


static func _fractal() -> PackedFloat32Array:
	var a := _vnoise(4)
	var b := _vnoise(8)
	for i in a.size():
		a[i] = a[i] * 0.65 + b[i] * 0.35
	return a


## Клеточный узор (булыжник, светокамень): ячейки Вороного с «раствором» на границах.
static func _voronoi(n: int, tones: Array, mortar: Color) -> Image:
	var img := _new()
	var pts: Array[Vector2] = []
	var cols: Array[Color] = []
	for i in n:
		pts.append(Vector2(_rng.randf() * S, _rng.randf() * S))
		cols.append(tones[_rng.randi_range(0, tones.size() - 1)])
	for y in S:
		for x in S:
			var d1 := 1e9
			var d2 := 1e9
			var idx := 0
			for i in n:
				var dx := absf(x + 0.5 - pts[i].x)
				var dy := absf(y + 0.5 - pts[i].y)
				dx = minf(dx, S - dx)
				dy = minf(dy, S - dy)
				var d := sqrt(dx * dx + dy * dy)
				if d < d1:
					d2 = d1
					d1 = d
					idx = i
				elif d < d2:
					d2 = d
			var c: Color
			if d2 - d1 < 1.0:
				c = _vary(mortar, 0.08)
			else:
				c = _vary(_shade(cols[idx], 1.12 if d1 < 1.6 else 1.0), 0.06)
			img.set_pixel(x, y, c)
	return img


## Пять ступеней яркости цвета: тень → блик.
static func _ramp(c: Color) -> Array[Color]:
	return [_shade(c, 0.42), _shade(c, 0.66), _shade(c, 0.84), c, _light(c, 0.45)]


const _RAMP_KEYS := ["12345", "abcde", "pqrst", "ABCDE"]


## Спрайт из 16 строк по 16 символов. «.» — прозрачно; 1–5, a–e, p–t, A–E — ступени цветов ramps[0..3];
## k — почти чёрный, K — тёмно-серый, G — серый, W — светло-серый, w — белый; extra переопределяет символы.
static func _spr(rows: Array, ramps: Array = [], extra: Dictionary = {}) -> Image:
	var img := _new()
	var pal := {"k": INK, "K": _g(0.24), "G": _g(0.5), "W": _g(0.78), "w": WHITE}
	for r in ramps.size():
		var ramp := _ramp(ramps[r])
		var keys: String = _RAMP_KEYS[r]
		for j in 5:
			pal[keys[j]] = ramp[j]
	pal.merge(extra, true)
	if rows.size() != S:
		push_error("TexturePainter: в спрайте %d строк" % rows.size())
	for y in mini(rows.size(), S):
		var row: String = rows[y]
		if row.length() != S:
			push_error("TexturePainter: строка спрайта длиной %d: '%s'" % [row.length(), row])
		for x in mini(row.length(), S):
			var ch := row[x]
			if ch == ".":
				continue
			if pal.has(ch):
				img.set_pixel(x, y, pal[ch])
			else:
				push_error("TexturePainter: неизвестный символ '%s'" % ch)
	return img


## Обводка в 1 пиксель вокруг непрозрачных пикселей (по 4 соседям).
static func _outline(img: Image, c: Color) -> Image:
	var data := img.get_data()  # копия: соседей проверяем по исходному состоянию
	for y in S:
		for x in S:
			var i := (y * S + x) * 4 + 3
			if data[i] > 127:
				continue
			if (x > 0 and data[i - 4] > 127) or (x < S - 1 and data[i + 4] > 127) \
					or (y > 0 and data[i - S * 4] > 127) or (y < S - 1 and data[i + S * 4] > 127):
				img.set_pixel(x, y, c)
	return img


## Цвет точки на выпуклой поверхности: свет сверху-слева.
static func _lit(col: Color, nx: float, ny: float) -> Color:
	var nz := sqrt(maxf(0.0, 1.0 - nx * nx - ny * ny))
	var l := -0.45 * nx - 0.55 * ny + 0.7 * nz
	var c := _shade(col, 0.68 + 0.4 * l)
	if l > 0.9:
		c = _light(c, 0.4)
	return c


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	for y in range(maxi(0, floori(cy - ry)), mini(S, ceili(cy + ry) + 1)):
		for x in range(maxi(0, floori(cx - rx)), mini(S, ceili(cx + rx) + 1)):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, _lit(col, dx, dy))


## Объёмный «стержень» радиуса r между точками a и b.
static func _capsule(img: Image, a: Vector2, b: Vector2, r: float, col: Color) -> void:
	var ab := b - a
	var len2 := ab.length_squared()
	for y in range(maxi(0, floori(minf(a.y, b.y) - r)), mini(S, ceili(maxf(a.y, b.y) + r) + 1)):
		for x in range(maxi(0, floori(minf(a.x, b.x) - r)), mini(S, ceili(maxf(a.x, b.x) + r) + 1)):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
			var d := p - (a + ab * t)
			if d.length() <= r:
				img.set_pixel(x, y, _lit(col, d.x / r, d.y / r))


## Случайные пиксели заданного цвета поверх непрозрачной части.
static func _specks(img: Image, col: Color, n: int) -> void:
	var done := 0
	for _try in n * 8:
		var x := _rng.randi_range(0, S - 1)
		var y := _rng.randi_range(0, S - 1)
		if img.get_pixel(x, y).a > 0.5:
			img.set_pixel(x, y, col)
			done += 1
			if done >= n:
				return


static func _edge(x: int, y: int) -> int:
	return mini(mini(x, y), mini(S - 1 - x, S - 1 - y))


# --- Природа -------------------------------------------------------------------

static func _stone() -> Image:
	var img := _new()
	var base := Color(0.5, 0.5, 0.5)
	for y in S:
		for x in S:
			img.set_pixel(x, y, _shade(base, _rng.randf_range(0.9, 1.07)))
	for i in 10:
		var sx := _rng.randi_range(0, S - 1)
		var sy := _rng.randi_range(0, S - 1)
		var f := 0.78 if i % 3 != 0 else 1.13
		for k in _rng.randi_range(2, 4):
			img.set_pixel((sx + k) % S, sy, _shade(base, f))
	return img


## Верх травы — серый: шейдер умножает его на цвет биома.
static func _grass_top() -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var v := _rng.randf_range(0.8, 0.97)
			var r := _rng.randf()
			if r < 0.16:
				v *= 0.8
			elif r < 0.22:
				v = minf(v * 1.07, 1.0)
			img.set_pixel(x, y, _g(v))
	return img


static func _dirt() -> Image:
	var img := _new()
	var base := Color(0.55, 0.39, 0.26)
	for y in S:
		for x in S:
			var c := _vary(base, 0.1)
			var r := _rng.randf()
			if r < 0.1:
				c = _vary(Color(0.42, 0.29, 0.19), 0.06)
			elif r < 0.15:
				c = _vary(Color(0.66, 0.5, 0.36), 0.05)
			img.set_pixel(x, y, c)
	return img


## Кайма сверху (трава, снег, мицелий) с неровным нижним краем.
static func _fringe(dst: Image, colors: Image, tint: Color, min_depth: int) -> Image:
	for x in S:
		var depth := min_depth + _rng.randi_range(0, 1)
		if _rng.randf() < 0.3:
			depth += 1
		if _rng.randf() < 0.12:
			depth += 2
		for y in depth:
			var c := colors.get_pixel(x, y)
			c = Color(c.r * tint.r, c.g * tint.g, c.b * tint.b)
			if y == depth - 1:
				c = _shade(c, 0.86)
			dst.set_pixel(x, y, c)
	return dst


static func _mossy(img: Image) -> Image:
	var n := _vnoise(4)
	for y in S:
		for x in S:
			var t := n[y * S + x]
			if t > 0.58 or (t > 0.47 and _rng.randf() < 0.35):
				var c := img.get_pixel(x, y)
				var lum := (c.r + c.g + c.b) / 3.0
				img.set_pixel(x, y, _vary(_shade(Color(0.33, 0.5, 0.22), 0.55 + lum * 0.9), 0.06))
	return img


static func _bedrock() -> Image:
	var img := _new()
	var tones := [0.16, 0.27, 0.38, 0.5]
	for y in S:
		for x in S:
			var t: float = tones[_rng.randi_range(0, 3)]
			img.set_pixel(x, y, _vary(_g(t), 0.05))
	return img


static func _gravel() -> Image:
	var img := _new()
	var tones := [Color(0.52, 0.5, 0.49), Color(0.4, 0.38, 0.37), Color(0.63, 0.61, 0.59), Color(0.48, 0.43, 0.39)]
	for by in S >> 1:
		for bx in S >> 1:
			var c: Color = tones[_rng.randi_range(0, 3)]
			for k in 4:
				img.set_pixel(bx * 2 + (k & 1), by * 2 + (k >> 1), _vary(c, 0.07))
	return img


static func _clay() -> Image:
	var img := _speckled(Color(0.62, 0.64, 0.71), 0.025, Color(0.56, 0.58, 0.65), 0.18)
	for k in 10:
		img.set_pixel(_rng.randi_range(0, 15), _rng.randi_range(0, 15), Color(0.71, 0.73, 0.79))
	return img


static func _ice() -> Image:
	var img := _new()
	var n := _vnoise(4)
	for y in S:
		for x in S:
			var c := _vary(Color(0.55, 0.71, 0.98).lerp(Color(0.68, 0.81, 1.0), n[y * S + x]), 0.02)
			c.a = 0.75
			img.set_pixel(x, y, c)
	var hi := Color(0.86, 0.93, 1.0, 0.75)
	_line(img, 2, 7, 7, 2, hi)
	_line(img, 3, 8, 5, 6, hi)
	_line(img, 8, 14, 14, 8, hi)
	_line(img, 11, 14, 14, 11, hi)
	return img


static func _obsidian() -> Image:
	var img := _new()
	var n := _fractal()
	for y in S:
		for x in S:
			var t := n[y * S + x]
			var c := Color(0.07, 0.05, 0.11)
			if t > 0.62:
				c = Color(0.24, 0.15, 0.34)
			elif t > 0.5:
				c = Color(0.14, 0.09, 0.2)
			c = _vary(c, 0.12)
			if _rng.randf() < 0.025:
				c = Color(0.42, 0.34, 0.52)
			img.set_pixel(x, y, c)
	return img


static func _mycelium() -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var c := _vary(Color(0.44, 0.38, 0.43), 0.06)
			var r := _rng.randf()
			if r < 0.1:
				c = _vary(Color(0.63, 0.56, 0.63), 0.05)
			elif r < 0.18:
				c = _vary(Color(0.33, 0.28, 0.33), 0.05)
			elif r < 0.22:
				c = Color(0.56, 0.44, 0.53)
			img.set_pixel(x, y, c)
	return img


static func _soul_sand() -> Image:
	var img := _speckled(Color(0.33, 0.25, 0.2), 0.07, Color(0.26, 0.19, 0.15), 0.18)
	var dark := Color(0.17, 0.12, 0.09)
	var lit := Color(0.44, 0.35, 0.28)
	for f in 4:
		var fx := (f % 2) * 8 + _rng.randi_range(1, 4)
		var fy := (f >> 1) * 8 + _rng.randi_range(1, 3)
		for d in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(1, 3)]:
			img.set_pixel((fx + d.x) % S, (fy + d.y) % S, dark)
		img.set_pixel(fx % S, posmod(fy - 1, S), lit)
		img.set_pixel((fx + 2) % S, posmod(fy - 1, S), lit)
	return img


static func _netherrack() -> Image:
	var img := _new()
	var n := _fractal()
	for y in S:
		for x in S:
			var t := n[y * S + x]
			var c: Color
			if t < 0.38:
				c = Color(0.3, 0.12, 0.12)
			elif t < 0.55:
				c = Color(0.43, 0.19, 0.19)
			elif t < 0.7:
				c = Color(0.5, 0.24, 0.23)
			else:
				c = Color(0.6, 0.31, 0.29)
			c = _vary(c, 0.07)
			if _rng.randf() < 0.06:
				c = Color(0.25, 0.09, 0.09)
			img.set_pixel(x, y, c)
	return img


static func _glowstone() -> Image:
	var tones := [Color(1.0, 0.92, 0.62), Color(0.96, 0.76, 0.4), Color(0.84, 0.6, 0.3), Color(1.0, 0.97, 0.8)]
	return _voronoi(11, tones, Color(0.52, 0.34, 0.17))


static func _end_stone() -> Image:
	var img := _speckled(Color(0.86, 0.87, 0.63), 0.035, Color(0.8, 0.81, 0.56), 0.15)
	for k in 12:
		var x := _rng.randi_range(0, 15)
		var y := _rng.randi_range(0, 15)
		img.set_pixel(x, y, Color(0.68, 0.68, 0.46))
		img.set_pixel((x + 1) % S, y, Color(0.75, 0.75, 0.52))
		img.set_pixel(x, (y + 1) % S, Color(0.93, 0.94, 0.74))
	return img


static func _sponge() -> Image:
	var img := _speckled(Color(0.8, 0.78, 0.3), 0.05, Color(0.74, 0.72, 0.26), 0.2)
	var hole := Color(0.53, 0.49, 0.13)
	for k in 13:
		var x := _rng.randi_range(0, 15)
		var y := _rng.randi_range(0, 15)
		img.set_pixel(x, y, hole)
		if _rng.randf() < 0.4:
			img.set_pixel((x + 1) % S, y, hole)
			img.set_pixel(x, (y + 1) % S, _shade(hole, 1.1))
		img.set_pixel(x, posmod(y - 1, S), Color(0.9, 0.88, 0.44))
	return img


static func _web() -> Image:
	var img := _new()
	var c := Color(0.88, 0.88, 0.9)
	var center := Vector2(7.5, 7.5)
	var dirs: Array[Vector2] = []
	for k in 8:
		var a := k * TAU / 8.0 + 0.2
		dirs.append(Vector2(cos(a), sin(a)))
		var end := center + dirs[k] * 11.0
		_line(img, 7, 7, roundi(end.x), roundi(end.y), c)
	for r in [3.2, 6.4]:
		for k in 8:
			var p0: Vector2 = center + dirs[k] * r
			var p1: Vector2 = center + dirs[(k + 1) % 8] * r
			var mid := center + ((p0 + p1) * 0.5 - center) * 0.8
			_line(img, roundi(p0.x), roundi(p0.y), roundi(mid.x), roundi(mid.y), c)
			_line(img, roundi(mid.x), roundi(mid.y), roundi(p1.x), roundi(p1.y), c)
	return img


static func _water() -> Image:
	var img := _new()
	var base := Color(0.2, 0.4, 0.86)
	var n := _vnoise(4)
	for y in S:
		for x in S:
			var w := sin((x * 2 + y) * TAU / S) * 0.5 + 0.5
			var c := _shade(base, 0.86 + 0.12 * w + 0.12 * n[y * S + x] + _rng.randf_range(-0.02, 0.02))
			c.a = 0.72
			img.set_pixel(x, y, c)
	return img


static func _lava() -> Image:
	var img := _new()
	var n := _fractal()
	for y in S:
		for x in S:
			var t := n[y * S + x] + _rng.randf_range(-0.04, 0.04)
			var c: Color
			if t < 0.32:
				c = Color(0.62, 0.13, 0.03)
			elif t < 0.48:
				c = Color(0.84, 0.3, 0.05)
			elif t < 0.66:
				c = Color(0.96, 0.47, 0.09)
			elif t < 0.8:
				c = Color(1.0, 0.64, 0.16)
			else:
				c = Color(1.0, 0.86, 0.36)
			img.set_pixel(x, y, c)
	return img


# --- Руды и блоки ресурсов -----------------------------------------------------

static func _ore(col: Color, hi: Color) -> Image:
	var img := _copy("stone")
	var dark := _shade(col, 0.62)
	for q in 5:
		var cx := _rng.randi_range(0, 15)
		var cy := _rng.randi_range(0, 15)
		if q < 4:
			cx = (q % 2) * 8 + _rng.randi_range(0, 4)
			cy = (q >> 1) * 8 + _rng.randi_range(0, 4)
		for dy in 3:
			for dx in 3:
				if (dx >= 1 and dy >= 1 and dx + dy <= 3) or _rng.randf() < 0.6:
					var c := col
					if dx + dy == 0 or (dx + dy == 1 and _rng.randf() < 0.5):
						c = hi
					elif dx + dy >= 3:
						c = dark
					img.set_pixel((cx + dx) % S, (cy + dy) % S, _vary(c, 0.05))
	return img


## Блок металла/алмаза: фаска по краю и блик по диагонали. kind: 0 железо, 1 золото, 2 алмаз.
static func _metal_block(base: Color, kind: int) -> Image:
	var img := _noise_fill(base, 0.025)
	for y in S:
		for x in S:
			var c := img.get_pixel(x, y)
			if x == 0 or y == 0:
				c = _light(base, 0.5)
			elif x == S - 1 or y == S - 1:
				c = _shade(base, 0.6)
			elif x == 1 or y == 1:
				c = _light(base, 0.2)
			elif x == S - 2 or y == S - 2:
				c = _shade(base, 0.8)
			elif kind == 0 and (y == 7 or y == 8):
				c = _shade(base, 0.88 if y == 7 else 1.06)
			elif kind == 2 and (x + y) % 6 == 0:
				c = _shade(base, 0.82)
			elif x + y == 11 or x + y == 12:
				c = _light(c, 0.25)
			img.set_pixel(x, y, c)
	if kind == 1:
		for k in 5:
			_px(img, _rng.randi_range(3, 12), _rng.randi_range(3, 12), Color(1, 0.98, 0.75))
	return img


static func _lapis_block() -> Image:
	var img := _speckled(Color(0.15, 0.29, 0.68), 0.06, Color(0.26, 0.43, 0.86), 0.2)
	for y in S:
		for x in S:
			var c := img.get_pixel(x, y)
			if x == 0 or y == 0:
				c = _light(c, 0.2)
			elif x == S - 1 or y == S - 1:
				c = _shade(c, 0.65)
			elif _rng.randf() < 0.1:
				c = Color(0.1, 0.18, 0.48)
			img.set_pixel(x, y, c)
	return img


# --- Дерево --------------------------------------------------------------------

## Кора: 0 дуб, 1 ель, 2 берёза, 3 тропическое дерево.
static func _log_side(kind: int) -> Image:
	var img := _new()
	var bases := [Color(0.42, 0.32, 0.19), Color(0.25, 0.18, 0.1), Color(0.85, 0.85, 0.81), Color(0.37, 0.28, 0.13)]
	var base: Color = bases[kind]
	var col_f: Array[float] = []
	for x in S:
		var f := _rng.randf_range(0.88, 1.08)
		if kind == 0 and x % 4 == 1:
			f = 0.74
		elif kind == 1 and x % 3 == 0:
			f = 0.72
		elif kind == 2:
			f = _rng.randf_range(0.95, 1.03)
		elif kind == 3:
			if x % 4 == 0:
				f = 0.62
			elif x % 4 == 2:
				f = 1.14
		col_f.append(f)
	for y in S:
		for x in S:
			img.set_pixel(x, y, _shade(base, col_f[x] * _rng.randf_range(0.93, 1.05)))
	if kind == 2:
		# Берёза: чёрные штрихи и серые пятна.
		for k in 9:
			var x := _rng.randi_range(0, 15)
			var y := _rng.randi_range(0, 15)
			var dark := k < 6
			for j in _rng.randi_range(2, 5):
				img.set_pixel((x + j) % S, y, Color(0.16, 0.15, 0.14) if dark else Color(0.6, 0.6, 0.57))
			if dark and _rng.randf() < 0.5:
				img.set_pixel((x + 1) % S, (y + 1) % S, Color(0.3, 0.29, 0.27))
	else:
		# Продольные трещины коры и сучки — чтобы полосы не выглядели как доски.
		for k in 7:
			var sx := _rng.randi_range(0, S - 1)
			var sy := _rng.randi_range(0, S - 1)
			var dark := k % 2 == 0
			for j in _rng.randi_range(2, 5):
				var c := img.get_pixel(sx, (sy + j) % S)
				img.set_pixel(sx, (sy + j) % S, _shade(c, 0.72 if dark else 1.18))
		for i in 2:
			var kx := _rng.randi_range(0, S - 2)
			var ky := _rng.randi_range(0, S - 1)
			img.set_pixel(kx, ky, _shade(base, 0.6))
			img.set_pixel(kx + 1, ky, _shade(base, 0.65))
	return img


static func _log_top() -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var c: Color
			if _edge(x, y) == 0:
				c = _vary(Color(0.4, 0.3, 0.18), 0.08)
			else:
				var dx := absf(x - 7.5)
				var dy := absf(y - 7.5)
				var d := maxf(dx, dy) * 0.7 + sqrt(dx * dx + dy * dy) * 0.3
				c = Color(0.72, 0.58, 0.36) if int(d) % 2 == 0 else Color(0.61, 0.47, 0.28)
				c = _vary(c, 0.04)
			img.set_pixel(x, y, c)
	return img


static func _planks(base: Color) -> Image:
	var img := _new()
	for y in S:
		var board := y >> 2
		var row_f := _rng.randf_range(0.93, 1.06)
		var joint := (board * 5 + 3) % S
		for x in S:
			var c: Color
			if y % 4 == 3:
				c = _shade(base, 0.66)
			elif x == joint:
				c = _shade(base, 0.72)
			else:
				c = _shade(base, row_f * _rng.randf_range(0.95, 1.04))
			img.set_pixel(x, y, c)
	return img


## Листва в оттенках серого («красивая» — со сквозными дырками): 0 дуб, 1 ель, 2 берёза, 3 джунгли.
static func _leaves(kind: int) -> Image:
	var img := _new()
	var n := _vnoise(8)
	var holes: float = [0.2, 0.12, 0.17, 0.14][kind]
	var lo: float = [0.5, 0.42, 0.56, 0.45][kind]
	var hi: float = [0.86, 0.74, 0.93, 0.86][kind]
	for y in S:
		for x in S:
			var t := n[y * S + x] * 0.55 + _rng.randf() * 0.45
			if kind == 1 and (x + (y >> 1)) % 3 == 0:
				t *= 0.65
			elif kind == 3:
				t = n[(y & ~1) * S + (x & ~1)] * 0.7 + _rng.randf() * 0.3
			var v := lerpf(lo, hi, t)
			if _rng.randf() < holes:
				img.set_pixel(x, y, _g(v * 0.7, 0.0))
			else:
				img.set_pixel(x, y, _g(v))
	return img


const SAPLING_OAK := [
	"................",
	"......44........",
	"....3454.44.....",
	"...345544543....",
	"..34554455443...",
	"..2445443544432.",
	".23445344454432.",
	"..2344d4433432..",
	"...23.d.d.332...",
	".....2dd.d......",
	".......dd.......",
	".......dc.......",
	".......dc.......",
	".......cd.......",
	".......dc.......",
	"......cdc.......",
]
const SAPLING_SPRUCE := [
	"................",
	".......4........",
	"......343.......",
	".......4........",
	".....34543......",
	"......343.......",
	"....3445443.....",
	".....34543......",
	"...234454432....",
	"....3445443.....",
	"..23444544432...",
	"...2334d4332....",
	".......d........",
	".......d........",
	".......dc.......",
	"......cdc.......",
]
const SAPLING_BIRCH := [
	"................",
	"................",
	".......44.......",
	".....345543.....",
	"....34554543....",
	"...3455444543...",
	"...2445545443...",
	"....24w4443.....",
	".....23w32......",
	".......w........",
	".......W........",
	".......wK.......",
	".......w........",
	".......W........",
	".......wW.......",
	"......WwK.......",
]
const SAPLING_JUNGLE := [
	"................",
	"....44....44....",
	"...4554..4554...",
	"..455443344554..",
	".34544334454543.",
	".2344.3dd3.4432.",
	"..23...dd...32..",
	"....443dd344....",
	"...45543d34554..",
	"..2344..d..4432.",
	"...22...d...22..",
	".......dd.......",
	".......dc.......",
	".......dc.......",
	".......cd.......",
	"......cdc.......",
]


static func _sapling(kind: int) -> Image:
	match kind:
		0: return _spr(SAPLING_OAK, [Color(0.28, 0.56, 0.15), Color(0.44, 0.31, 0.15)])
		1: return _spr(SAPLING_SPRUCE, [Color(0.19, 0.38, 0.21), Color(0.36, 0.25, 0.12)])
		2: return _spr(SAPLING_BIRCH, [Color(0.46, 0.64, 0.26), Color(0.44, 0.31, 0.15)])
	return _spr(SAPLING_JUNGLE, [Color(0.2, 0.5, 0.1), Color(0.4, 0.29, 0.13)])


# --- Растения ------------------------------------------------------------------

static func _tallgrass() -> Image:
	var img := _new()
	for b in 13:
		var x0 := _rng.randf_range(0.5, 15.5)
		var h := _rng.randi_range(5, 14)
		var lean := _rng.randf_range(-3.0, 3.0)
		var v := _rng.randf_range(0.66, 0.96)
		for t in h:
			var k := float(t) / h
			_px(img, int(x0 + lean * k * k), 15 - t, _g(v * (0.72 + 0.28 * k)))
	return img


static func _fern() -> Image:
	var img := _new()
	for f in 3:
		var side := f - 1
		var ang := -PI / 2.0 + side * 0.5 + _rng.randf_range(-0.08, 0.08)
		var p := Vector2(7.5 + side * 1.5, 15.5)
		var steps := 13 if side == 0 else 10
		for s in steps:
			ang += side * 0.07
			var dir := Vector2(cos(ang), sin(ang))
			p += dir
			var v := 0.6 + 0.3 * float(s) / steps
			_px(img, int(p.x), int(p.y), _g(v * 0.88))
			if s >= 1 and s % 2 == 1:
				var leaf := 3 if s < steps * 0.4 else (2 if s < steps * 0.75 else 1)
				var nrm := Vector2(-dir.y, dir.x)
				for sd in [-1.0, 1.0]:
					for l in range(1, leaf + 1):
						var q: Vector2 = p + nrm * sd * l + dir * 0.45 * l
						_px(img, int(q.x), int(q.y), _g(v))
	return img


static func _deadbush() -> Image:
	var img := _new()
	_branch(img, Vector2(7.5, 15.5), -PI / 2.0, 4.0, 3)
	return img


static func _branch(img: Image, p: Vector2, ang: float, length: float, depth: int) -> void:
	var q := p + Vector2(cos(ang), sin(ang)) * length
	var c := Color(0.48, 0.32, 0.14) if depth % 2 == 1 else Color(0.37, 0.24, 0.1)
	_line(img, int(p.x), int(p.y), int(q.x), int(q.y), c)
	if depth > 0:
		_branch(img, q, ang - _rng.randf_range(0.35, 0.75), length * 0.8, depth - 1)
		_branch(img, q, ang + _rng.randf_range(0.35, 0.75), length * 0.8, depth - 1)


const DANDELION := [
	"................",
	"................",
	"................",
	"................",
	"................",
	".......45.......",
	"......4554......",
	".....345543.....",
	"......3443......",
	".......dc.......",
	"........d.......",
	"...dd...d.......",
	"....ddc.d..cd...",
	"......dcd.dd....",
	".......dcd......",
	"........d.......",
]
const ROSE := [
	"................",
	"................",
	"................",
	"......4.4.......",
	".....454544.....",
	"....34555543....",
	"....24554542....",
	".....234432.....",
	"......2332......",
	".......dc.......",
	"....d...d.......",
	".....dd.d..dd...",
	"......dcd.dd....",
	".......dc.......",
	".......cd.......",
	"........d.......",
]
const MUSHROOM_BROWN := [
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"......4554......",
	".....455554.....",
	"....34444443....",
	"....22333322....",
	".......dd.......",
	".......de.......",
	".......dd.......",
	"......cddc......",
	"................",
	"................",
]
const MUSHROOM_RED := [
	"................",
	"................",
	"................",
	"................",
	"................",
	"......4444......",
	".....45w454.....",
	"....4444w444....",
	"....3w444443....",
	"....22333w22....",
	".......dd.......",
	".......de.......",
	".......dd.......",
	"......cddc......",
	"................",
	"................",
]


static func _reeds() -> Image:
	var img := _new()
	var col := Color(0.56, 0.78, 0.38)
	var xs := [2, 7, 12]
	var tops := [3, 0, 2]
	for s in 3:
		var x0: int = xs[s]
		var top: int = tops[s]
		var off := _rng.randi_range(0, 4)
		for y in range(top, S):
			var joint := (y + off) % 5 == 0
			img.set_pixel(x0, y, _light(col, 0.3) if joint else _vary(col, 0.04))
			img.set_pixel(x0 + 1, y, _shade(col, 0.95 if joint else 0.76))
		for k in 2:
			var ly := _rng.randi_range(top + 2, 12)
			var dir := -1 if _rng.randf() < 0.5 else 1
			var lx := x0 + (2 if dir > 0 else -1)
			_px(img, lx, ly, _shade(col, 0.9))
			_px(img, lx + dir, ly - 1, _shade(col, 0.82))
	return img


static func _cactus_side() -> Image:
	var img := _new()
	var base := Color(0.16, 0.48, 0.12)
	for y in S:
		for x in S:
			var f := 1.0
			if x == 0 or x == S - 1:
				f = 0.62
			elif x % 4 == 2:
				f = 0.8
			elif x % 4 == 0:
				f = 1.14
			img.set_pixel(x, y, _shade(base, f * _rng.randf_range(0.95, 1.05)))
	for y in range(1, S, 4):
		for x in [3, 7, 11]:
			var yy: int = (y + (2 if x == 7 else 0)) % S
			img.set_pixel(x, yy, Color(0.08, 0.1, 0.06))
			img.set_pixel(x, (yy + 1) % S, Color(0.86, 0.86, 0.74))
	return img


static func _cactus_end(bottom: bool) -> Image:
	var img := _new()
	var base := Color(0.2, 0.52, 0.15) if not bottom else Color(0.16, 0.42, 0.12)
	for y in S:
		for x in S:
			var e := _edge(x, y)
			var f := 1.0
			if e == 0:
				f = 0.6
			elif e == 1:
				f = 0.85
			elif e == 3:
				f = 0.8
			elif e >= 6:
				f = 1.15
			img.set_pixel(x, y, _shade(base, f * _rng.randf_range(0.95, 1.05)))
	if not bottom:
		for p in [Vector2i(4, 2), Vector2i(11, 2), Vector2i(2, 7), Vector2i(13, 8), Vector2i(5, 13), Vector2i(10, 13)]:
			img.set_pixel(p.x, p.y, Color(0.86, 0.86, 0.74))
	return img


static func _vine() -> Image:
	var img := _new()
	for v in 5:
		var x := float(v * 3 + _rng.randi_range(0, 2))
		var length := _rng.randi_range(9, 16)
		for y in length:
			x += _rng.randf_range(-0.6, 0.6)
			var ix := posmod(roundi(x), S)
			img.set_pixel(ix, y, _g(0.5))
			if _rng.randf() < 0.7:
				for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(0, 1)]:
					if _rng.randf() < 0.5 and y + d.y >= 0 and y + d.y < S:
						img.set_pixel(posmod(ix + d.x, S), y + d.y, _g(_rng.randf_range(0.66, 0.94)))
	return img


static func _waterlily() -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var dx := x + 0.5 - 8.0
			var dy := y + 0.5 - 8.0
			var r := sqrt(dx * dx + dy * dy)
			if r > 7.4:
				continue
			var a := atan2(dy, dx)
			if absf(wrapf(a + PI / 4.0, -PI, PI)) < 0.32 and r > 1.0:
				continue
			var v := 0.68 + _rng.randf_range(-0.04, 0.04)
			if r > 6.4:
				v = 0.52
			elif r < 1.5:
				v = 0.58
			elif fposmod(a + 0.2, PI / 3.0) < 0.16:
				v = 0.58
			img.set_pixel(x, y, _g(v))
	return img


static func _wheat(stage: int) -> Image:
	var img := _new()
	var t := stage / 7.0
	var stalk := Color(0.26, 0.58, 0.12).lerp(Color(0.6, 0.58, 0.2), t)
	var ear := Color(0.32, 0.62, 0.14).lerp(Color(0.86, 0.72, 0.28), t)
	var h := 2 + int(stage * 1.75)
	var xs := [1, 4, 6, 9, 11, 14]
	for k in xs.size():
		var x0: int = xs[k]
		var hk := maxi(1, h - _rng.randi_range(0, 2))
		var lean := _rng.randi_range(-1, 1)
		var ear_len := 0 if stage < 3 else mini(stage - 1, 5)
		for j in hk:
			var x := x0 + (lean if j > (hk >> 1) else 0)
			var is_ear := j >= hk - ear_len
			var c := _vary(ear if is_ear else stalk, 0.06)
			if is_ear:
				# Колос: 2 пикселя в ширину, зёрна через ряд светлее; сверху — ость.
				var grain := 1.12 if j % 2 == 0 else 0.92
				_px(img, x, 15 - j, _shade(c, grain))
				_px(img, x + 1, 15 - j, _shade(c, grain * 0.8))
				if j == hk - 1:
					_px(img, x, 14 - j, _light(c, 0.2))
			else:
				_px(img, x, 15 - j, c)
		if stage < 4 and hk > 2:
			_px(img, x0 + 1, 13 - _rng.randi_range(0, 1), stalk)
	return img


static func _stem(bent: bool) -> Image:
	var img := _new()
	var top := 7 if bent else 1
	for y in range(top, S):
		img.set_pixel(7, y, _g(0.8))
		img.set_pixel(8, y, _g(0.62))
		if y % 3 == 0 and y > top:
			var lx := 6 if y % 6 == 0 else 9
			img.set_pixel(lx, y, _g(0.88))
			_px(img, lx + (-1 if lx == 6 else 1), y - 1, _g(0.74))
	if bent:
		for x in range(8, S):
			img.set_pixel(x, 6, _g(0.82))
			img.set_pixel(x, 7, _g(0.64))
		img.set_pixel(7, 6, _g(0.74))
	return img


static func _pumpkin_side() -> Image:
	var img := _new()
	var base := Color(0.86, 0.5, 0.1)
	for y in S:
		for x in S:
			var f := 1.0
			match x % 4:
				0: f = 0.72
				1: f = 1.08
				3: f = 0.92
			if y == 0 or y == S - 1:
				f *= 0.85
			img.set_pixel(x, y, _shade(base, f * _rng.randf_range(0.95, 1.04)))
	return img


static func _pumpkin_top() -> Image:
	var img := _new()
	var base := Color(0.84, 0.48, 0.1)
	for y in S:
		for x in S:
			var e := _edge(x, y)
			var f := 1.0
			if e == 0:
				f = 0.75
			elif e == 2 or e == 5:
				f = 0.84
			img.set_pixel(x, y, _shade(base, f * _rng.randf_range(0.95, 1.04)))
	_rect(img, 7, 7, 2, 2, Color(0.42, 0.36, 0.12))
	img.set_pixel(7, 7, Color(0.52, 0.46, 0.16))
	img.set_pixel(6, 8, Color(0.36, 0.3, 0.1))
	img.set_pixel(9, 7, Color(0.36, 0.3, 0.1))
	return img


const PUMPKIN_FACE := [
	"................",
	"................",
	"................",
	"....#......#....",
	"...###....###...",
	"..#####..#####..",
	"................",
	"................",
	"................",
	"..#..........#..",
	"..############..",
	"..####.##.####..",
	"...##########...",
	"................",
	"................",
	"................",
]


static func _pumpkin_face(lit: bool) -> Image:
	var img := _copy("pumpkin_side")
	for y in S:
		var row: String = PUMPKIN_FACE[y]
		for x in S:
			if row[x] != "#":
				continue
			var c := Color(0.22, 0.12, 0.03)
			if lit:
				var inner := true
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or ny < 0 or nx >= S or ny >= S or (PUMPKIN_FACE[ny] as String)[nx] != "#":
						inner = false
				c = Color(1.0, 0.9, 0.4) if inner else Color(0.98, 0.66, 0.14)
			img.set_pixel(x, y, c)
	return img


static func _melon_side() -> Image:
	var img := _new()
	var dark := Color(0.38, 0.55, 0.1)
	var light := Color(0.58, 0.73, 0.2)
	for y in S:
		var w := roundi(sin(y * TAU / S) * 1.2)
		for x in S:
			var m := posmod(x + w, 4)
			var c := light if m == 0 else (dark if m != 2 else _shade(dark, 0.88))
			img.set_pixel(x, y, _vary(c, 0.06))
	return img


static func _melon_top() -> Image:
	var img := _new()
	var dark := Color(0.38, 0.55, 0.1)
	var light := Color(0.58, 0.73, 0.2)
	for y in S:
		for x in S:
			var dx := x + 0.5 - 8.0
			var dy := y + 0.5 - 8.0
			var a := atan2(dy, dx)
			var c := light if fposmod(a * 8.0 / TAU + sqrt(dx * dx + dy * dy) * 0.04, 1.0) < 0.28 else dark
			img.set_pixel(x, y, _vary(c, 0.06))
	_rect(img, 7, 7, 2, 2, Color(0.5, 0.44, 0.16))
	return img


static func _mushroom_skin_red() -> Image:
	var img := _speckled(Color(0.78, 0.11, 0.1), 0.05, Color(0.68, 0.08, 0.08), 0.12)
	var spots := [Vector2i(2, 2), Vector2i(10, 1), Vector2i(6, 6), Vector2i(13, 8), Vector2i(2, 11), Vector2i(9, 12)]
	for p: Vector2i in spots:
		var q := p + Vector2i(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1))
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			img.set_pixel(posmod(q.x + d.x, S), posmod(q.y + d.y, S), Color(0.95, 0.92, 0.9))
		img.set_pixel(posmod(q.x + 1, S), posmod(q.y + 1, S), Color(0.8, 0.78, 0.76))
		if _rng.randf() < 0.5:
			img.set_pixel(posmod(q.x + 2, S), posmod(q.y, S), Color(0.92, 0.88, 0.86))
	return img


static func _mushroom_stem() -> Image:
	var img := _new()
	var base := Color(0.84, 0.81, 0.72)
	for y in S:
		for x in S:
			var f := 1.04 if x % 3 == 0 else 0.97
			if x % 5 == 2 and _rng.randf() < 0.7:
				f = 0.88
			img.set_pixel(x, y, _shade(base, f * _rng.randf_range(0.96, 1.03)))
	return img


static func _mushroom_inside() -> Image:
	var img := _speckled(Color(0.84, 0.73, 0.58), 0.03, Color(0.77, 0.64, 0.49), 0.12)
	for k in 8:
		img.set_pixel(_rng.randi_range(0, 15), _rng.randi_range(0, 15), Color(0.92, 0.84, 0.72))
	return img


const NETHER_WART := [
	[
		"................", "................", "................", "................",
		"................", "................", "................", "................",
		"................", "................", "................", "................",
		"....4......4....", "...434..4.434...", "....3..434..3...", "....2...3...2...",
	],
	[
		"................", "................", "................", "................",
		"................", "................", "................", "................",
		"......45........", ".....4554...4...", "..4...44...454..", ".454...3....3...",
		"..3....3....3...", "..3...323...3...", "..2....3...323..", "..2....2....2...",
	],
	[
		"................", "................", "......44........", ".....4554...44..",
		".44..45543.4554.", "4554..343..4554.", "4554...3...343..", ".343...3....3...",
		"..3...323...3...", "..3..44344..3...", "..3.45543.432...", ".43...3...434...",
		"4554..3..45543..", ".33...3...343...", "..3...3....3....", "..2...2....2....",
	],
]


static func _nether_wart(stage: int) -> Image:
	return _spr(NETHER_WART[stage], [Color(0.62, 0.1, 0.12)])


static func _farmland(wet: bool) -> Image:
	var img := _copy("dirt")
	var f := 0.6 if wet else 1.0
	for y in S:
		for x in S:
			var c := img.get_pixel(x, y)
			var m := y % 4
			if m == 0:
				c = _shade(c, 0.7)
			elif m == 1:
				c = _shade(c, 1.12)
			if _edge(x, y) == 0:
				c = _shade(c, 0.82)
			img.set_pixel(x, y, _shade(c, f))
	return img


# --- Строительные блоки --------------------------------------------------------

const CREEPER := [
	"........",
	".##..##.",
	".##..##.",
	"...##...",
	"..####..",
	"..####..",
	"..#..#..",
	"........",
]


## Песчаник: 0 бок, 1 верх, 2 низ, 3 резной, 4 гладкий.
static func _sandstone(kind: int) -> Image:
	var img := _speckled(SAND, 0.03, _shade(SAND, 0.94), 0.2)
	if kind == 1:
		return img
	if kind == 2:
		for k in 7:
			var x := _rng.randi_range(0, 15)
			var y := _rng.randi_range(0, 15)
			for j in _rng.randi_range(2, 4):
				img.set_pixel((x + j) % S, y, _shade(SAND, 0.78))
		return img
	var band := 3 if kind != 4 else 2
	for x in S:
		for y in band:
			img.set_pixel(x, y, _vary(_light(SAND, 0.14), 0.02))
		img.set_pixel(x, band, _shade(SAND, 0.8))
	if kind == 0:
		for y in range(4, 12):
			if y % 3 == 0:
				for x in S:
					if _rng.randf() < 0.6:
						img.set_pixel(x, y, _shade(SAND, 0.93))
		for x in S:
			img.set_pixel(x, 11, _shade(SAND, 0.84))
			for y in range(12, S):
				var c := _vary(_shade(SAND, 0.92), 0.05)
				if _rng.randf() < 0.18:
					c = _shade(SAND, 0.74)
				img.set_pixel(x, y, c)
	else:
		for x in S:
			img.set_pixel(x, S - 1 - band, _shade(SAND, 0.8))
			for y in range(S - band, S):
				img.set_pixel(x, y, _vary(_light(SAND, 0.14), 0.02))
		if kind == 4:
			for y in range(band + 1, S - 1 - band):
				for x in S:
					img.set_pixel(x, y, _vary(SAND, 0.015))
		else:
			for y in 8:
				var row: String = CREEPER[y]
				for x in 8:
					if row[x] == "#":
						img.set_pixel(4 + x, 4 + y, _shade(SAND, 0.68))
						if row[mini(x + 1, 7)] != "#" or x == 7:
							_px(img, 5 + x, 4 + y, _light(SAND, 0.18))
	return img


static func _bricks() -> Image:
	var img := _new()
	var mortar := Color(0.68, 0.65, 0.6)
	var brick := Color(0.62, 0.28, 0.21)
	for y in S:
		var row := y >> 2
		var off := 4 if row % 2 == 1 else 0
		for x in S:
			if y % 4 == 3 or (x + off) % 8 == 7:
				img.set_pixel(x, y, _vary(mortar, 0.04))
			else:
				img.set_pixel(x, y, _vary(brick, 0.1))
	return img


static func _stonebrick() -> Image:
	var img := _new()
	var base := Color(0.5, 0.5, 0.5)
	var mortar := Color(0.3, 0.3, 0.3)
	for y in S:
		var row := y >> 3
		var ly := y % 8
		var seam_x := S - 1 if row == 0 else 7
		for x in S:
			var c: Color
			if ly == 7 or x == seam_x:
				c = _vary(mortar, 0.05)
			elif ly == 0 or x == (seam_x + 1) % S:
				c = _vary(_shade(base, 1.16), 0.03)
			else:
				c = _vary(base, 0.06)
			img.set_pixel(x, y, c)
	return img


static func _stonebrick_cracked() -> Image:
	var img := _copy("stonebrick")
	var dark := Color(0.22, 0.22, 0.22)
	for k in 3:
		var p := Vector2(_rng.randf_range(2.0, 13.0), _rng.randf_range(1.0, 14.0))
		var ang := _rng.randf() * TAU
		for s in 8:
			ang += _rng.randf_range(-0.7, 0.7)
			p += Vector2(cos(ang), sin(ang))
			_px(img, int(p.x), int(p.y), dark)
	return img


static func _stonebrick_carved() -> Image:
	var img := _new()
	var base := Color(0.5, 0.5, 0.5)
	for y in S:
		for x in S:
			var c := _vary(base, 0.05)
			var e := _edge(x, y)
			var r := Vector2(x - 7.5, y - 7.5).length()
			if e == 0:
				c = _shade(base, 0.6)
			elif e == 1:
				c = _light(base, 0.22) if (x == 1 or y == 1) else _shade(base, 0.75)
			elif r > 4.4 and r < 5.5:
				c = _shade(base, 0.68)
			elif r >= 5.5 and r < 6.3:
				c = _light(base, 0.12)
			elif r < 2.2:
				c = _light(base, 0.15)
			img.set_pixel(x, y, c)
	return img


static func _smooth_stone(base: Color) -> Image:
	var img := _noise_fill(base, 0.03)
	for i in S:
		img.set_pixel(i, 0, _light(base, 0.15))
		img.set_pixel(0, i, _light(base, 0.15))
		img.set_pixel(i, S - 1, _shade(base, 0.7))
		img.set_pixel(S - 1, i, _shade(base, 0.7))
	return img


static func _slab_side() -> Image:
	var base := Color(0.66, 0.66, 0.66)
	var img := _noise_fill(base, 0.03)
	for x in S:
		for y in [0, 8]:
			img.set_pixel(x, y, _light(base, 0.15))
		for y in [7, 15]:
			img.set_pixel(x, y, _shade(base, 0.62))
	for y in S:
		if y != 7 and y != 15:
			img.set_pixel(0, y, _light(base, 0.1))
			img.set_pixel(S - 1, y, _shade(base, 0.8))
	return img


static func _nether_brick() -> Image:
	var img := _new()
	var mortar := Color(0.13, 0.06, 0.07)
	var brick := Color(0.27, 0.13, 0.15)
	for y in S:
		var off := 4 if (y >> 2) % 2 == 1 else 0
		for x in S:
			var c: Color
			if y % 4 == 3 or (x + off) % 8 == 7:
				c = _vary(mortar, 0.1)
			elif y % 4 == 0:
				c = _vary(_light(brick, 0.12), 0.08)
			else:
				c = _vary(brick, 0.1)
			img.set_pixel(x, y, c)
	return img


static func _glass() -> Image:
	var img := _new()
	var edge := Color(0.8, 0.92, 0.96)
	img.fill(Color(edge.r, edge.g, edge.b, 0.0))
	for y in S:
		for x in S:
			if _edge(x, y) == 0:
				var c := edge
				if (x == 0 or x == S - 1) and (y == 0 or y == S - 1):
					c = Color(0.6, 0.74, 0.82)
				img.set_pixel(x, y, _vary(c, 0.03))
			elif (x + y == 7 and x >= 2 and x <= 5) or (x + y == 8 and x >= 3 and x <= 5) or (x + y == 20 and x >= 9 and x <= 12):
				img.set_pixel(x, y, WHITE)
	return img


static func _iron_bars() -> Image:
	var img := _new()
	img.fill(Color(0.6, 0.6, 0.6, 0.0))
	for y in S:
		for bx in [1, 5, 9, 13]:
			img.set_pixel(bx, y, _g(0.78))
			img.set_pixel(bx + 1, y, _g(0.46))
	for x in S:
		for by in [3, 12]:
			img.set_pixel(x, by, _g(0.7))
			img.set_pixel(x, by + 1, _g(0.42))
	return img


## Шерсть: тканевая фактура с мягкими косыми стежками.
static func _wool(col: Color) -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var d := _rng.randf_range(-0.05, 0.05)
			var s := (x + 2 * y) % 8
			if s == 0:
				d -= 0.12
			elif s == 1:
				d -= 0.05
			elif s == 4:
				d += 0.04
			img.set_pixel(x, y, Color(clampf(col.r * (1.0 + d) + d * 0.15, 0.0, 1.0),
					clampf(col.g * (1.0 + d) + d * 0.15, 0.0, 1.0), clampf(col.b * (1.0 + d) + d * 0.15, 0.0, 1.0)))
	return img


static func _bookshelf() -> Image:
	var img := _copy("planks0")
	var colors := [Color(0.62, 0.16, 0.13), Color(0.18, 0.3, 0.62), Color(0.2, 0.5, 0.22),
		Color(0.55, 0.4, 0.15), Color(0.45, 0.2, 0.5), Color(0.75, 0.66, 0.3)]
	for shelf: int in [2, 9]:
		for yy in range(shelf, shelf + 5):
			for x in S:
				img.set_pixel(x, yy, Color(0.16, 0.11, 0.07))
		var x := 0
		while x < S:
			var w := _rng.randi_range(1, 2)
			var col: Color = colors[_rng.randi_range(0, colors.size() - 1)]
			var top := shelf + _rng.randi_range(0, 1)
			for xx in w:
				if x + xx >= S:
					break
				for yy in range(top, shelf + 5):
					var f := 1.2 if yy == top else (0.85 if xx == w - 1 else 1.0)
					img.set_pixel(x + xx, yy, _shade(col, f))
			x += w + (1 if _rng.randf() < 0.25 else 0)
	return img


# --- Механизмы и мебель --------------------------------------------------------

static func _crafting_top() -> Image:
	var img := _copy("planks0")
	var dark := Color(0.3, 0.2, 0.1)
	var grid := Color(0.44, 0.31, 0.16)
	for i in S:
		img.set_pixel(i, 0, dark)
		img.set_pixel(i, S - 1, dark)
		img.set_pixel(0, i, dark)
		img.set_pixel(S - 1, i, dark)
	for i in range(1, S - 1):
		for k in [5, 10]:
			img.set_pixel(k, i, grid)
			img.set_pixel(i, k, grid)
	return img


static func _crafting_side(front: bool) -> Image:
	var img := _copy("planks0")
	var top := Color(0.46, 0.32, 0.17)
	for x in S:
		for y in 3:
			img.set_pixel(x, y, _vary(top, 0.06))
		img.set_pixel(x, 3, Color(0.25, 0.16, 0.08))
	for y in range(4, S):
		img.set_pixel(0, y, _shade(img.get_pixel(0, y), 0.7))
		img.set_pixel(S - 1, y, _shade(img.get_pixel(S - 1, y), 0.7))
	var steel := Color(0.7, 0.7, 0.72)
	var handle := Color(0.33, 0.2, 0.09)
	if front:
		# Молоток и пила на стене.
		_rect(img, 4, 7, 1, 7, handle)
		_rect(img, 2, 5, 5, 2, steel)
		img.set_pixel(2, 5, _light(steel, 0.4))
		_rect(img, 9, 6, 4, 6, steel)
		for y in range(6, 12, 2):
			img.set_pixel(8, y, steel)
		_rect(img, 10, 12, 2, 2, handle)
		img.set_pixel(9, 6, _light(steel, 0.4))
	else:
		# Пила.
		_rect(img, 2, 7, 9, 3, steel)
		for x in range(2, 11, 2):
			img.set_pixel(x, 10, steel)
		img.set_pixel(2, 7, _light(steel, 0.4))
		_rect(img, 11, 6, 3, 5, handle)
		img.set_pixel(12, 8, Color(0.6, 0.45, 0.26))
	return img


static func _furnace_side() -> Image:
	var img := _copy("stone")
	var top := _base("furnace_top")
	for x in S:
		for y in 3:
			img.set_pixel(x, y, top.get_pixel(x, y + 1))
		img.set_pixel(x, 3, _g(0.3))
		img.set_pixel(x, S - 1, _g(0.32))
	for y in range(4, S):
		img.set_pixel(0, y, _shade(img.get_pixel(0, y), 0.75))
		img.set_pixel(S - 1, y, _shade(img.get_pixel(S - 1, y), 0.65))
	return img


static func _furnace_front(lit: bool) -> Image:
	var img := _copy("furnace_side")
	_rect(img, 4, 5, 8, 2, _g(0.22))
	_rect(img, 5, 5, 6, 1, _g(0.1))
	_rect(img, 3, 8, 10, 6, _g(0.26))
	_rect(img, 4, 9, 8, 4, _g(0.06))
	for x in range(3, 13):
		img.set_pixel(x, 8, _g(0.6))
	if lit:
		for y in range(9, 13):
			for x in range(4, 12):
				var t := (y - 9) / 3.0 + _rng.randf_range(-0.3, 0.3)
				var c := Color(0.55, 0.12, 0.04)
				if t > 0.8:
					c = Color(1.0, 0.88, 0.36)
				elif t > 0.45:
					c = Color(1.0, 0.58, 0.12)
				elif t < 0.05:
					c = Color(0.1, 0.05, 0.03)
				img.set_pixel(x, y, c)
	return img


static func _dispenser_front() -> Image:
	var img := _copy("furnace_side")
	_rect(img, 4, 5, 8, 8, _g(0.3))
	_rect(img, 5, 6, 6, 6, _g(0.08))
	_rect(img, 6, 7, 4, 4, _g(0.16))
	for i in range(4, 12):
		img.set_pixel(i, 5, _g(0.62))
		img.set_pixel(4, i + 1, _g(0.56))
	return img


## Сундук: 0 верх, 1 бок, 2 перед с замком.
static func _chest(kind: int) -> Image:
	var img := _new()
	var dark := Color(0.28, 0.17, 0.07)
	for y in S:
		for x in S:
			var c := _vary(CHEST_WOOD, 0.05)
			if kind == 0 and y % 4 == 2:
				c = _shade(c, 0.86)
			if _edge(x, y) == 0:
				c = dark
			img.set_pixel(x, y, c)
	if kind > 0:
		for x in range(1, S - 1):
			img.set_pixel(x, 5, dark)
			img.set_pixel(x, 6, _light(CHEST_WOOD, 0.15))
	if kind == 2:
		_rect(img, 6, 3, 4, 6, dark)
		_rect(img, 7, 4, 2, 4, Color(0.74, 0.74, 0.78))
		img.set_pixel(7, 4, Color(0.94, 0.94, 0.96))
		img.set_pixel(8, 7, Color(0.5, 0.5, 0.54))
	return img


static func _noteblock() -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var c := _vary(DARK_WOOD, 0.06)
			if x % 4 == 3:
				c = _shade(c, 0.8)
			var e := _edge(x, y)
			if e == 0:
				c = Color(0.2, 0.12, 0.08)
			elif e == 1 and (x == 1 or y == 1):
				c = _light(DARK_WOOD, 0.1)
			img.set_pixel(x, y, c)
	return img


static func _jukebox_side() -> Image:
	var img := _copy("noteblock")
	for x in S:
		for y in [1, 2, 13, 14]:
			img.set_pixel(x, y, _vary(_light(DARK_WOOD, 0.12), 0.04))
	return img


static func _jukebox_top() -> Image:
	var img := _copy("noteblock")
	_rect(img, 3, 3, 10, 10, Color(0.5, 0.33, 0.22))
	for i in range(3, 13):
		img.set_pixel(i, 3, Color(0.6, 0.42, 0.28))
		img.set_pixel(3, i, Color(0.6, 0.42, 0.28))
	_rect(img, 4, 7, 8, 2, Color(0.07, 0.05, 0.04))
	return img


const TNT_LETTERS := ["TTT.N..N.TTT", ".T..NN.N..T.", ".T..N.NN..T.", ".T..N..N..T.", ".T..N..N..T."]


static func _tnt_side() -> Image:
	var img := _new()
	var red := Color(0.8, 0.2, 0.14)
	for y in S:
		for x in S:
			var f := 1.0
			if x % 4 == 3:
				f = 0.68
			elif x % 4 == 0:
				f = 1.1
			img.set_pixel(x, y, _shade(red, f * _rng.randf_range(0.95, 1.05)))
	for y in range(5, 12):
		for x in S:
			img.set_pixel(x, y, _vary(Color(0.92, 0.9, 0.86), 0.02))
	for y in 5:
		var row: String = TNT_LETTERS[y]
		for x in 12:
			if row[x] != ".":
				img.set_pixel(2 + x, 6 + y, Color(0.12, 0.1, 0.1))
	return img


static func _tnt_end(fuse: bool) -> Image:
	var img := _noise_fill(Color(0.7, 0.17, 0.12), 0.05)
	for c in [Vector2(4, 4), Vector2(12, 4), Vector2(4, 12), Vector2(12, 12)]:
		for y in S:
			for x in S:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
				if d < 3.4:
					var col := Color(0.86, 0.3, 0.22) if d < 2.4 else Color(0.48, 0.1, 0.07)
					if d < 1.0:
						col = Color(0.88, 0.84, 0.74)
					img.set_pixel(x, y, _vary(col, 0.04))
	if fuse:
		_rect(img, 7, 7, 2, 2, _g(0.22))
		img.set_pixel(7, 7, _g(0.42))
	return img


static func _spawner() -> Image:
	var img := _new()
	var bar := Color(0.24, 0.27, 0.34)
	for y in S:
		for x in S:
			var vx := x % 5 == 0
			var vy := y % 5 == 0
			if vx or vy:
				var c := _vary(bar, 0.1)
				if vx and vy:
					c = _light(bar, 0.3)
				elif (vx and y % 5 == 1) or (vy and x % 5 == 1):
					c = _light(bar, 0.12)
				img.set_pixel(x, y, c)
			else:
				img.set_pixel(x, y, Color(bar.r, bar.g, bar.b, 0.0))
	return img


## Факел: 0 обычный, 1 редстоун включён, 2 выключен. Палочка — столбцы 7–8, строки 6–15; пламя — 4–6.
static func _torch(kind: int) -> Image:
	var img := _new()
	for y in range(6, S):
		img.set_pixel(7, y, Color(0.56, 0.41, 0.2))
		img.set_pixel(8, y, Color(0.41, 0.29, 0.13))
	var tip: Array
	match kind:
		0:
			tip = [Color(1, 1, 0.78), Color(1, 0.88, 0.34), Color(1, 0.9, 0.46), Color(1, 0.64, 0.14),
				Color(0.98, 0.56, 0.1), Color(0.86, 0.36, 0.05)]
		1:
			tip = [Color(1, 0.66, 0.58), Color(1, 0.3, 0.2), Color(1, 0.26, 0.16), Color(0.86, 0.06, 0.03),
				Color(0.8, 0.08, 0.04), Color(0.58, 0.04, 0.02)]
		_:
			tip = [Color(0.5, 0.16, 0.12), Color(0.4, 0.1, 0.07), Color(0.42, 0.11, 0.08), Color(0.33, 0.07, 0.05),
				Color(0.36, 0.08, 0.06), Color(0.28, 0.06, 0.04)]
	for r in 3:
		img.set_pixel(7, 4 + r, tip[r * 2])
		img.set_pixel(8, 4 + r, tip[r * 2 + 1])
	return img


static func _ladder() -> Image:
	var img := _new()
	var wood := Color(0.54, 0.39, 0.2)
	var dark := Color(0.36, 0.25, 0.12)
	for y in S:
		img.set_pixel(1, y, _vary(wood, 0.05))
		img.set_pixel(2, y, _vary(dark, 0.05))
		img.set_pixel(13, y, _vary(wood, 0.05))
		img.set_pixel(14, y, _vary(dark, 0.05))
	for ry in [1, 5, 9, 13]:
		for x in range(3, 13):
			img.set_pixel(x, ry, _vary(_light(wood, 0.1), 0.05))
			img.set_pixel(x, ry + 1, _vary(dark, 0.05))
	return img


static func _lever() -> Image:
	var img := _new()
	for y in range(6, S):
		img.set_pixel(7, y, Color(0.52, 0.38, 0.19))
		img.set_pixel(8, y, Color(0.38, 0.27, 0.12))
	img.set_pixel(7, 6, Color(0.34, 0.24, 0.12))
	img.set_pixel(8, 6, Color(0.26, 0.18, 0.08))
	return img


static func _door(iron: bool, upper: bool) -> Image:
	var img := _new()
	var base := Color(0.78, 0.78, 0.8) if iron else Color(0.6, 0.44, 0.24)
	var frame := _shade(base, 0.6)
	for y in S:
		for x in S:
			var c := base
			if not iron and x % 4 == 0:
				c = _shade(base, 0.84)
			c = _vary(c, 0.04)
			if x == 0 or x == S - 1 or (upper and y == 0) or (not upper and y == S - 1):
				c = frame
			img.set_pixel(x, y, c)
	if iron:
		for x in range(1, S - 1):
			for y in ([5, 10] if not upper else [11]):
				img.set_pixel(x, y, _shade(base, 0.7))
				img.set_pixel(x, y + 1, _light(base, 0.3))
		for p in [Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13)]:
			img.set_pixel(p.x, p.y, _shade(base, 0.55))
		if upper:
			_rect(img, 3, 3, 4, 4, CLEAR)
			_rect(img, 9, 3, 4, 4, CLEAR)
	else:
		if upper:
			_rect(img, 3, 3, 4, 6, CLEAR)
			_rect(img, 9, 3, 4, 6, CLEAR)
			for x in range(1, S - 1):
				img.set_pixel(x, 11, frame)
				img.set_pixel(x, 12, _shade(base, 0.75))
		else:
			for x in range(1, S - 1):
				img.set_pixel(x, 6, frame)
				img.set_pixel(x, 7, _shade(base, 0.75))
			_rect(img, 12, 0, 2, 2, Color(0.25, 0.2, 0.15))
	return img


static func _trapdoor() -> Image:
	var img := _new()
	var base := Color(0.56, 0.41, 0.21)
	for y in S:
		for x in S:
			var hx := (x >= 3 and x <= 6) or (x >= 9 and x <= 12)
			var hy := (y >= 3 and y <= 6) or (y >= 9 and y <= 12)
			if hx and hy:
				continue
			var c := _vary(base, 0.05)
			if _edge(x, y) <= 1 or x == 7 or x == 8 or y == 7 or y == 8:
				c = _shade(c, 0.78)
			if _edge(x, y) == 0:
				c = _shade(base, 0.55)
			img.set_pixel(x, y, c)
	return img


## Рельсы: 0 обычные, 1 энергорельсы выкл., 2 энергорельсы вкл., 3 нажимные.
static func _rail(kind: int) -> Image:
	var img := _new()
	var tie := Color(0.47, 0.34, 0.18)
	for ty in [1, 5, 9, 13]:
		for x in range(1, 15):
			img.set_pixel(x, ty, _vary(_light(tie, 0.1), 0.05))
			img.set_pixel(x, ty + 1, _vary(_shade(tie, 0.78), 0.05))
	if kind == 1 or kind == 2:
		var dust := Color(0.95, 0.15, 0.08) if kind == 2 else Color(0.42, 0.06, 0.05)
		for y in S:
			img.set_pixel(7, y, dust)
			img.set_pixel(8, y, _shade(dust, 0.8))
	elif kind == 3:
		_rect(img, 5, 4, 6, 8, Color(0.58, 0.12, 0.1))
		for i in range(5, 11):
			img.set_pixel(i, 4, Color(0.75, 0.2, 0.16))
		for i in range(4, 12):
			img.set_pixel(5, i, Color(0.72, 0.18, 0.14))
	var metal := GOLD if kind == 1 or kind == 2 else Color(0.68, 0.68, 0.7)
	for y in S:
		img.set_pixel(2, y, _shade(metal, 0.65))
		img.set_pixel(3, y, metal)
		img.set_pixel(12, y, metal)
		img.set_pixel(13, y, _shade(metal, 0.65))
	return img


static func _rail_curved() -> Image:
	var img := _new()
	var tie := Color(0.47, 0.34, 0.18)
	var metal := Color(0.68, 0.68, 0.7)
	for y in S:
		for x in S:
			var dx := 16.0 - (x + 0.5)
			var dy := 16.0 - (y + 0.5)
			var r := sqrt(dx * dx + dy * dy)
			var a := atan2(dy, dx)
			if r > 15.2:
				continue
			# Шпалы — по радиусам, рельсы — дугами (r ≈ 12.5 и 3.5 совпадают с x = 2–3 и 12–13 прямых).
			for ta in [0.2, 0.6, 0.97, 1.37]:
				var off: float = (a - ta) * r
				if absf(off) < 1.05 and r > 1.0:
					img.set_pixel(x, y, _vary(_light(tie, 0.1) if off < 0.0 else _shade(tie, 0.78), 0.05))
			for rr in [12.5, 3.5]:
				if absf(r - rr) < 1.0:
					img.set_pixel(x, y, metal if r < rr else _shade(metal, 0.65))
	return img


## Редстоун-пыль (серая, окрашивается по мощности): крест или вертикальная полоса.
static func _dust(cross: bool) -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var on := x >= 6 and x <= 9
			if cross:
				var d := Vector2(x - 7.5, y - 7.5).length()
				on = on or (y >= 6 and y <= 9) or d < 4.2 + _rng.randf_range(-0.6, 0.6)
			var edge_px := (x == 6 or x == 9) and not (cross and y >= 5 and y <= 10)
			if on and not (edge_px and _rng.randf() < 0.25):
				img.set_pixel(x, y, _g(_rng.randf_range(0.6, 1.0)))
	return img


static func _repeater(on: bool) -> Image:
	var img := _copy("smooth")
	var dust := Color(0.95, 0.12, 0.08) if on else Color(0.45, 0.07, 0.05)
	for y in range(1, S - 1):
		img.set_pixel(7, y, dust)
		img.set_pixel(8, y, _shade(dust, 0.82))
	var tip := Color(1.0, 0.35, 0.25) if on else Color(0.38, 0.1, 0.08)
	for ty in [3, 10]:
		_rect(img, 6, ty - 1, 4, 4, Color(0.42, 0.3, 0.15))
		_rect(img, 7, ty, 2, 2, tip)
		if on:
			img.set_pixel(7, ty, Color(1.0, 0.7, 0.6))
	return img


static func _lamp(on: bool) -> Image:
	var base := Color(0.95, 0.72, 0.38) if on else Color(0.42, 0.26, 0.14)
	var line := Color(1.0, 0.95, 0.75) if on else Color(0.62, 0.43, 0.27)
	var dark := Color(0.72, 0.46, 0.2) if on else Color(0.25, 0.15, 0.08)
	var img := _noise_fill(base, 0.06)
	for y in S:
		for x in S:
			if _edge(x, y) == 0:
				img.set_pixel(x, y, dark)
			elif x == 5 or x == 10 or y == 5 or y == 10:
				img.set_pixel(x, y, line)
			elif on and maxf(absf(x - 7.5), absf(y - 7.5)) < 2.0:
				img.set_pixel(x, y, Color(1.0, 0.98, 0.86))
	return img


static func _piston_side() -> Image:
	var img := _copy("cobble")
	var planks := _base("planks0")
	for x in S:
		for y in 4:
			img.set_pixel(x, y, planks.get_pixel(x, y + 4))
		img.set_pixel(x, 4, Color(0.28, 0.22, 0.15))
	for y in range(5, S):
		for x in range(6, 10):
			img.set_pixel(x, y, _vary(_g(0.7 if x < 8 else 0.58), 0.04))
	return img


static func _piston_top(sticky: bool) -> Image:
	var img := _copy("planks0")
	for y in S:
		for x in S:
			var e := _edge(x, y)
			if e == 0:
				img.set_pixel(x, y, _g(0.36))
			elif e == 1:
				img.set_pixel(x, y, _vary(_g(0.72), 0.03))
			elif sticky and e >= 2:
				var c := _vary(Color(0.46, 0.74, 0.33), 0.08)
				if _rng.randf() < 0.12:
					c = Color(0.68, 0.9, 0.55)
				img.set_pixel(x, y, c)
	return img


static func _piston_bottom() -> Image:
	var img := _copy("cobble")
	for y in S:
		for x in S:
			if _edge(x, y) == 0:
				img.set_pixel(x, y, _g(0.24))
	_rect(img, 6, 6, 4, 4, _g(0.3))
	return img


static func _piston_inner() -> Image:
	var img := _copy("smooth")
	_rect(img, 5, 5, 6, 6, _g(0.76))
	for i in range(5, 11):
		img.set_pixel(i, 5, _g(0.88))
		img.set_pixel(5, i, _g(0.86))
		img.set_pixel(i, 10, _g(0.5))
		img.set_pixel(10, i, _g(0.52))
	return img


static func _bed_top(head: bool) -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var c := _vary(BED_RED, 0.05)
			if x == 0 or x == S - 1:
				c = _shade(BED_RED, 0.78)
			img.set_pixel(x, y, c)
	if head:
		var pillow := Color(0.93, 0.93, 0.9)
		_rect(img, 1, 1, 14, 6, pillow)
		for x in range(1, 15):
			img.set_pixel(x, 6, Color(0.76, 0.76, 0.74))
			img.set_pixel(x, 7, Color(0.88, 0.88, 0.86))
		for y in range(1, 7):
			img.set_pixel(1, y, Color(0.8, 0.8, 0.78))
			img.set_pixel(14, y, Color(0.8, 0.8, 0.78))
		for x in S:
			img.set_pixel(x, 0, BED_WOOD)
	else:
		for x in range(1, 15):
			img.set_pixel(x, 12, _shade(BED_RED, 0.75))
		for x in S:
			img.set_pixel(x, S - 1, BED_WOOD)
	return img


static func _bed_side(head: bool) -> Image:
	var img := _new()
	for x in S:
		for y in range(7, 13):
			var c: Color
			if y <= 9:
				c = BED_RED if not (head and x >= 10) else Color(0.92, 0.92, 0.9)
				if y == 7:
					c = _light(c, 0.12)
			else:
				c = BED_WOOD if y != 12 else _shade(BED_WOOD, 0.75)
			img.set_pixel(x, y, _vary(c, 0.04))
	var lx := 13 if head else 0
	_rect(img, lx, 13, 3, 3, _shade(BED_WOOD, 0.85))
	return img


static func _bed_end(head: bool) -> Image:
	var img := _new()
	for x in S:
		for y in range(7, 13):
			var c: Color
			if y <= 9:
				c = Color(0.92, 0.92, 0.9) if head else BED_RED
			else:
				c = BED_WOOD if y != 12 else _shade(BED_WOOD, 0.75)
			img.set_pixel(x, y, _vary(c, 0.04))
	_rect(img, 0, 13, 3, 3, _shade(BED_WOOD, 0.85))
	_rect(img, 13, 13, 3, 3, _shade(BED_WOOD, 0.85))
	return img


## Торт: 0 верх, 1 бок, 2 срез, 3 низ (раскладка как в Minecraft, края прозрачны).
static func _cake(kind: int) -> Image:
	var img := _new()
	var frost := Color(0.96, 0.94, 0.92)
	var sponge := Color(0.76, 0.5, 0.27)
	var jam := Color(0.78, 0.12, 0.12)
	match kind:
		0:
			for y in range(1, 15):
				for x in range(1, 15):
					var c := _vary(frost, 0.02)
					if x == 1 or y == 1 or x == 14 or y == 14:
						c = _shade(frost, 0.9)
					img.set_pixel(x, y, c)
			for k in 7:
				img.set_pixel(_rng.randi_range(3, 12), _rng.randi_range(3, 12), jam)
		3:
			for y in range(1, 15):
				for x in range(1, 15):
					img.set_pixel(x, y, _vary(_shade(sponge, 0.85), 0.05))
		_:
			for x in range(1, 15):
				var drip := kind == 1 and _rng.randf() < 0.45
				for y in range(8, S):
					var c := _vary(sponge, 0.05)
					if y <= 9 or (y == 10 and drip):
						c = _vary(frost, 0.02)
					elif y == 12:
						c = _vary(jam if kind == 2 else _light(jam, 0.25), 0.04)
					img.set_pixel(x, y, c)
	return img


static func _fire() -> Image:
	var img := _new()
	# Вытянутый по вертикали шум даёт «языки» пламени.
	var n := _vnoise(8, 2)
	var n2 := _vnoise(16, 4)
	for y in S:
		for x in S:
			var h := 1.0 - (y + 0.5) / S
			var v := n[y * S + x] * 0.65 + n2[y * S + x] * 0.35 - h * 1.0 + 0.5
			if v < 0.16:
				continue
			var c := Color(0.82, 0.22, 0.04)
			if v > 0.62:
				c = Color(1.0, 0.94, 0.56)
			elif v > 0.44:
				c = Color(1.0, 0.8, 0.26)
			elif v > 0.27:
				c = Color(1.0, 0.54, 0.1)
			img.set_pixel(x, y, c)
	return img


static func _portal() -> Image:
	var img := _new()
	var n := _vnoise(4)
	for y in S:
		for x in S:
			var dx := x + 0.5 - 8.0
			var dy := y + 0.5 - 8.0
			var r := sqrt(dx * dx + dy * dy)
			var s := sin(atan2(dy, dx) * 2.0 + r * 0.85 + n[y * S + x] * 2.0) * 0.5 + 0.5
			var c := _vary(Color(0.3, 0.04, 0.6).lerp(Color(0.74, 0.4, 1.0), s), 0.05)
			c.a = 0.8
			img.set_pixel(x, y, c)
	return img


static func _end_portal() -> Image:
	var img := _noise_fill(Color(0.04, 0.05, 0.07), 0.2)
	var dots := [Color(0.3, 0.85, 0.75), Color(0.45, 0.95, 0.5), Color(0.2, 0.55, 0.6), Color(0.62, 0.96, 0.9)]
	for k in 12:
		img.set_pixel(_rng.randi_range(0, 15), _rng.randi_range(0, 15), dots[k % dots.size()])
	return img


## Стол зачарований: 0 верх, 1 бок (сверху 4 прозрачные строки).
static func _enchanting(kind: int) -> Image:
	var img := _copy("obsidian")
	var red := Color(0.62, 0.1, 0.12)
	var dia := Color(0.42, 0.94, 0.9)
	if kind == 0:
		for y in S:
			for x in S:
				var e := _edge(x, y)
				if e >= 2:
					var c := _vary(red, 0.06)
					if (x + y) % 4 == 0:
						c = _light(red, 0.15)
					if e == 2:
						c = _shade(red, 0.7)
					img.set_pixel(x, y, c)
		for p in [Vector2i(1, 1), Vector2i(13, 1), Vector2i(1, 13), Vector2i(13, 13)]:
			_rect(img, p.x, p.y, 2, 2, dia)
			img.set_pixel(p.x, p.y, _light(dia, 0.5))
		_rect(img, 6, 6, 4, 4, Color(0.34, 0.05, 0.07))
		return img
	_rect(img, 0, 0, S, 4, CLEAR)
	for x in S:
		for y in range(4, 7):
			img.set_pixel(x, y, _vary(red if y < 6 else _shade(red, 0.65), 0.05))
	for x in [2, 7, 12]:
		img.set_pixel(x, 5, dia)
		img.set_pixel(x + 1, 5, _shade(dia, 0.7))
	return img


const BREWING_STAND := [
	"................",
	".......dd.......",
	".......ed.......",
	".......dc.......",
	".......dc.......",
	"..44444dc44444..",
	"..3....dc....3..",
	"..W....dc....W..",
	".WgW...dc...WgW.",
	"WgggW..dc..WgggW",
	"WgwgW..dc..WgwgW",
	"WgggW..dc..WgggW",
	".WWW...dc...WWW.",
	".......dc.......",
	"......cddc......",
	"......cddc......",
]


static func _brewing_base() -> Image:
	var img := _speckled(Color(0.5, 0.5, 0.52), 0.04, Color(0.42, 0.42, 0.44), 0.15)
	for y in S:
		for x in S:
			if _edge(x, y) == 0:
				img.set_pixel(x, y, _g(0.34))
	return img


## Котёл: 0 бок (ножки снизу), 1 верх (кольцо), 2 внутренность, 3 дно.
static func _cauldron(kind: int) -> Image:
	var base := Color(0.27, 0.27, 0.29)
	var img := _noise_fill(base, 0.08)
	match kind:
		0:
			for x in S:
				img.set_pixel(x, 0, _light(base, 0.3))
				img.set_pixel(x, 1, _light(base, 0.15))
				img.set_pixel(x, 12, _shade(base, 0.7))
			_rect(img, 4, 13, 8, 3, CLEAR)
			_rect(img, 2, 13, 2, 3, CLEAR)
			_rect(img, 12, 13, 2, 3, CLEAR)
			for y in range(13, S):
				img.set_pixel(0, y, _light(base, 0.1))
				img.set_pixel(1, y, _shade(base, 0.8))
				img.set_pixel(14, y, _light(base, 0.1))
				img.set_pixel(15, y, _shade(base, 0.8))
		1:
			for y in S:
				for x in S:
					var e := _edge(x, y)
					if e >= 2:
						img.set_pixel(x, y, Color(base.r, base.g, base.b, 0.0))
					elif e == 0:
						img.set_pixel(x, y, _light(base, 0.25))
		2:
			img = _noise_fill(_shade(base, 0.68), 0.08)
		3:
			for y in S:
				for x in S:
					if _edge(x, y) == 0:
						img.set_pixel(x, y, _light(base, 0.2))
	return img


## Рамка портала Края: 0 верх, 1 бок (строки 0–2 прозрачны), 2 око.
static func _end_frame(kind: int) -> Image:
	var teal := Color(0.24, 0.43, 0.36)
	if kind == 2:
		var eye := _new()
		for y in S:
			for x in S:
				var d := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.0).length()
				if d < 3.2:
					var c := Color(0.2, 0.48, 0.34)
					if d < 2.2:
						c = Color(0.42, 0.78, 0.5)
					if d < 1.1:
						c = Color(0.04, 0.08, 0.06)
					eye.set_pixel(x, y, c)
		return eye
	if kind == 1:
		var img := _copy("end_stone")
		_rect(img, 0, 0, S, 3, CLEAR)
		for x in S:
			for y in range(3, 6):
				img.set_pixel(x, y, _vary(teal if y < 5 else _shade(teal, 0.6), 0.06))
			if x % 4 == 1:
				img.set_pixel(x, 4, _light(teal, 0.3))
		return img
	var top := _noise_fill(teal, 0.07)
	for y in S:
		for x in S:
			var e := _edge(x, y)
			if e == 0:
				top.set_pixel(x, y, Color(0.8, 0.82, 0.6))
			elif e == 1:
				top.set_pixel(x, y, _light(teal, 0.25))
			elif e == 3 and (x + y) % 2 == 0:
				top.set_pixel(x, y, _shade(teal, 0.7))
	_rect(top, 5, 5, 6, 6, _shade(teal, 0.45))
	_rect(top, 6, 6, 4, 4, Color(0.06, 0.12, 0.1))
	return top


static func _dragon_egg() -> Image:
	var img := _speckled(Color(0.07, 0.03, 0.09), 0.3, Color(0.26, 0.08, 0.32), 0.12)
	for k in 6:
		img.set_pixel(_rng.randi_range(0, 15), _rng.randi_range(0, 15), Color(0.46, 0.22, 0.52))
	return img


# --- Трещины -------------------------------------------------------------------

## Порядок появления пикселей трещины: сначала лучи из центра, затем ответвления от уже
## существующих трещин, пока сетка не покроет почти весь тайл.
static func _crack_order() -> Array:
	if _cache.has("cracks"):
		return _cache["cracks"]
	var saved := _rng.state
	_rng.seed = 991
	var seen: Dictionary = {}
	var order: Array = []
	var first := 6
	for seg in 600:
		if order.size() >= 196:
			break
		var p := Vector2(7.5, 7.5)
		var ang := seg * TAU / first + _rng.randf_range(-0.3, 0.3)
		var steps := _rng.randi_range(4, 7)
		if seg >= first:
			# Ответвление: чаще от недавних (внешних) пикселей, иногда от любого.
			var lo := maxi(0, order.size() - 40) if _rng.randf() < 0.6 else 0
			var sp: Vector2i = order[_rng.randi_range(lo, order.size() - 1)]
			p = Vector2(sp.x + 0.5, sp.y + 0.5)
			ang = _rng.randf() * TAU
			steps = _rng.randi_range(3, 6)
		for s in steps:
			ang += _rng.randf_range(-0.55, 0.55)
			p += Vector2(cos(ang), sin(ang))
			var ip := Vector2i(floori(p.x), floori(p.y))
			if ip.x < 0 or ip.y < 0 or ip.x >= S or ip.y >= S:
				break
			if not seen.has(ip):
				seen[ip] = true
				order.append(ip)
	_rng.state = saved
	_cache["cracks"] = order
	return order


static func _crack(stage: int) -> Image:
	var img := _new()
	var pts := _crack_order()
	var n := int(ceil(pts.size() * pow((stage + 1) / 10.0, 1.25)))
	for i in mini(n, pts.size()):
		var ip: Vector2i = pts[i]
		img.set_pixel(ip.x, ip.y, Color(0.08, 0.08, 0.08, 0.85))
	return img


# --- Инструменты и броня -------------------------------------------------------

const SWORD := [
	"................",
	"..............5.",
	".............53.",
	"............53..",
	"...........53...",
	"..........53....",
	".........53.....",
	"........53......",
	"...2...53.......",
	"....2.53........",
	".....2..........",
	"....d.2.........",
	"...d...2........",
	"..d.............",
	".3..............",
	"................",
]
const SHOVEL := [
	"................",
	"............5...",
	"...........544..",
	"..........54432.",
	".........54432..",
	"..........432...",
	".........d.2....",
	"........d.......",
	".......d........",
	"......d.........",
	".....d..........",
	"....d...........",
	"...d............",
	"..d.............",
	".b..............",
	"................",
]
const PICKAXE := [
	"................",
	"................",
	"...455555554....",
	"....333333334...",
	"...........34...",
	"..........d34...",
	".........d.34...",
	"........d..34...",
	".......d...34...",
	"......d....34...",
	".....d.....34...",
	"....d.......4...",
	"...d............",
	"..d.............",
	".b..............",
	"................",
]
const AXE := [
	"................",
	"........554.....",
	".......55443.d..",
	"......554432d...",
	".....554432d....",
	".....54...d.....",
	".........d......",
	"........d.......",
	".......d........",
	"......d.........",
	".....d..........",
	"....d...........",
	"...d............",
	"..d.............",
	".b..............",
	"................",
]
const HOE := [
	"................",
	"................",
	".....55554444...",
	".....3....333...",
	"...........d....",
	"..........d.....",
	".........d......",
	"........d.......",
	".......d........",
	"......d.........",
	".....d..........",
	"....d...........",
	"...d............",
	"..d.............",
	".b..............",
	"................",
]


static func _tool(kind: int, mat: int) -> Image:
	var maps := [SWORD, SHOVEL, PICKAXE, AXE, HOE]
	return _outline(_spr(maps[kind], [TOOL_COLORS[mat], STICK]), INK)


const HELMET := [
	"................",
	"................",
	"................",
	"................",
	"....44444444....",
	"...4555555554...",
	"...4444444444...",
	"...3444444443...",
	"...33......33...",
	"...33......33...",
	"...22......22...",
	"................",
	"................",
	"................",
	"................",
	"................",
]
const CHESTPLATE := [
	"................",
	"................",
	"..3444....4443..",
	".344444..444443.",
	".34444455444443.",
	".34444444444443.",
	".34444444444443.",
	".33.44444444.33.",
	"....44444444....",
	"....44455444....",
	"....44444444....",
	"....44444444....",
	"....33333333....",
	"................",
	"................",
	"................",
]
const LEGGINGS := [
	"................",
	"................",
	"....33333333....",
	"....44444444....",
	"....44455444....",
	"....544..544....",
	"....544..544....",
	"....444..444....",
	"....444..444....",
	"....444..444....",
	"....444..444....",
	"....444..444....",
	"....333..333....",
	"................",
	"................",
	"................",
]
const BOOTS := [
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"...444....444...",
	"...454....454...",
	"...444....444...",
	"..4444....4444..",
	"..3333....3333..",
	"................",
	"................",
	"................",
]


static func _armor(piece: int, mat: int) -> Image:
	var maps := [HELMET, CHESTPLATE, LEGGINGS, BOOTS]
	var col: Color = ARMOR_COLORS[mat]
	var img := _spr(maps[piece], [col])
	if mat == 1:
		# Кольчуга: шахматные «кольца».
		for y in S:
			for x in S:
				if img.get_pixel(x, y).a > 0.5 and (x + y) % 2 == 0:
					img.set_pixel(x, y, _shade(img.get_pixel(x, y), 0.55))
	return _outline(img, _shade(col, 0.3))


# --- Снаряжение ----------------------------------------------------------------

const FLINT_STEEL := [
	"................",
	".........4444...",
	"........455554..",
	".......453..354.",
	".......43....34.",
	".......43....34.",
	"........3...34..",
	"...bbb..........",
	"..bdddb.........",
	".bdeddcb........",
	".bddddcb........",
	".bdddccb........",
	"..bdccb.........",
	"...bbb..........",
	"................",
	"................",
]
const ARROW := [
	"................",
	"..............w.",
	"...........WWw..",
	"..........KWWW..",
	"...........WKK..",
	"..........d.K...",
	".........d......",
	"........d.......",
	".......d........",
	"......d.........",
	"...w.d..........",
	"..w.d...........",
	".W.d.w..........",
	"..d.w...........",
	".d.W............",
	"................",
]


## Лук: -1 — без натяжения, 0–2 — стадии натяжения со стрелой.
static func _bow(pull: int) -> Image:
	var img := _new()
	var wood := Color(0.56, 0.38, 0.17)
	var a := Vector2(12.5, 1.5)
	var b := Vector2(1.5, 12.5)
	var c := Vector2(1.0, 1.0)
	for s in 81:
		var t := s / 80.0
		var p := a * (1.0 - t) * (1.0 - t) + c * 2.0 * t * (1.0 - t) + b * t * t
		var col := wood
		if t > 0.42 and t < 0.58:
			col = Color(0.3, 0.2, 0.1)
		elif t < 0.1 or t > 0.9:
			col = _light(wood, 0.25)
		_px(img, int(p.x), int(p.y), col)
	_outline(img, INK)
	var string := Color(0.86, 0.86, 0.86)
	if pull < 0:
		_line(img, 12, 2, 2, 12, string)
		return img
	var tip: int = [0, 1, 3][pull]
	var nock := tip + 8
	_line(img, 12, 2, nock, nock, string)
	_line(img, nock, nock, 2, 12, string)
	for k in range(tip + 2, nock):
		img.set_pixel(k, k, STICK)
	_px(img, tip, tip, WHITE)
	_px(img, tip + 1, tip, _g(0.65))
	_px(img, tip, tip + 1, _g(0.65))
	_px(img, tip + 1, tip + 1, _g(0.8))
	_px(img, nock - 1, nock, WHITE)
	_px(img, nock, nock - 1, WHITE)
	return img


static func _fishing_rod(cast: bool) -> Image:
	var img := _new()
	for k in 12:
		img.set_pixel(1 + k, 14 - k, STICK if k % 3 != 2 else _shade(STICK, 0.7))
	img.set_pixel(13, 2, _shade(STICK, 0.85))
	_outline(img, INK)
	var line := Color(0.9, 0.9, 0.9)
	if cast:
		img.set_pixel(14, 2, line)
		img.set_pixel(15, 2, line)
	else:
		_line(img, 14, 3, 14, 11, line)
		var hook := _g(0.45)
		img.set_pixel(14, 12, hook)
		img.set_pixel(13, 13, hook)
		img.set_pixel(12, 12, hook)
	return img


const SHEARS := [
	"................",
	"................",
	"............54..",
	"...........54K4.",
	"..........54K43.",
	".........54K43..",
	"...22...54K43...",
	"..2..2354K43....",
	"..2..2..K3......",
	"...22....3......",
	"........22......",
	".......2..2.....",
	".......2..2.....",
	"........22......",
	"................",
	"................",
]


static func _shears() -> Image:
	return _outline(_spr(SHEARS, [Color(0.82, 0.82, 0.85)]), INK)


const BUCKET := [
	"................",
	"................",
	"................",
	"....44444444....",
	"...4MLLLLLLL4...",
	"...4LLLLLLLL4...",
	"...5444444443...",
	"...4544444433...",
	"....54444433....",
	"....54444433....",
	"....54444433....",
	".....544433.....",
	".....544433.....",
	".....333333.....",
	"................",
	"................",
]


## Ведро: 0 пустое, 1 вода, 2 лава, 3 молоко.
static func _bucket(fill: int) -> Image:
	var insides := [Color(0.3, 0.3, 0.32), Color(0.22, 0.38, 0.86), Color(1.0, 0.45, 0.08), Color(0.97, 0.97, 0.97)]
	var inside: Color = insides[fill]
	var img := _spr(BUCKET, [IRON], {"L": inside, "M": _light(inside, 0.3)})
	if fill == 2:
		img.set_pixel(7, 4, Color(1.0, 0.85, 0.3))
		img.set_pixel(10, 5, Color(1.0, 0.85, 0.3))
	return _outline(img, INK)


static func _compass() -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var d := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.0).length()
			if d < 5.6:
				img.set_pixel(x, y, _shade(Color(0.88, 0.88, 0.92), 1.0 - (y - 2) * 0.012))
			elif d < 6.9:
				img.set_pixel(x, y, _g(0.72 if x + y < 15 else 0.5))
	for y in range(3, 8):
		img.set_pixel(7, y, Color(0.9, 0.12, 0.1))
		img.set_pixel(8, y, Color(0.7, 0.06, 0.05))
	for y in range(8, 13):
		img.set_pixel(7, y, _g(0.55))
		img.set_pixel(8, y, _g(0.4))
	img.set_pixel(7, 7, _g(0.2))
	return _outline(img, INK)


static func _clock() -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var d := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.0).length()
			if d < 5.6:
				var c := Color(0.45, 0.68, 0.95) if y < 8 else Color(0.12, 0.14, 0.34)
				img.set_pixel(x, y, c)
			elif d < 6.9:
				img.set_pixel(x, y, GOLD if x + y < 15 else _shade(GOLD, 0.72))
	_rect(img, 6, 3, 2, 2, Color(1.0, 0.92, 0.3))
	img.set_pixel(9, 11, Color(0.9, 0.92, 1.0))
	img.set_pixel(5, 10, Color(0.8, 0.82, 0.9))
	for x in range(3, 13):
		img.set_pixel(x, 8, Color(0.3, 0.58, 0.22))
	return _outline(img, Color(0.33, 0.22, 0.04))


static func _map() -> Image:
	var img := _new()
	var paper := Color(0.88, 0.83, 0.62)
	var n := _vnoise(4)
	for y in range(1, 15):
		for x in range(1, 15):
			var c := _vary(paper, 0.03)
			if x == 1 or y == 1 or x == 14 or y == 14:
				c = Color(0.66, 0.55, 0.35)
			elif x >= 3 and x <= 12 and y >= 3 and y <= 12:
				var t := n[y * S + x]
				if t > 0.58:
					c = Color(0.46, 0.63, 0.3)
				elif t < 0.36:
					c = Color(0.42, 0.56, 0.82)
				elif absf(t - 0.47) < 0.02:
					c = Color(0.55, 0.42, 0.25)
			img.set_pixel(x, y, c)
	return _outline(img, Color(0.33, 0.26, 0.14))


const SADDLE := [
	"................",
	"................",
	"................",
	"................",
	"...........44...",
	".44.......4554..",
	".4544444444544..",
	"..34444444443...",
	"...333333333....",
	"....3222223.....",
	"....3222223.....",
	".....22222......",
	".......c........",
	"......cbc.......",
	"......ccc.......",
	"................",
]
const MINECART := [
	"................",
	"................",
	"................",
	"................",
	"................",
	".55555555555555.",
	".43KKKKKKKKKK34.",
	".44444444444444.",
	".43333333333334.",
	"..444444444444..",
	"..433333333334..",
	"...4444444444...",
	"...KkK....KkK...",
	"....K......K....",
	"................",
	"................",
]
const MINECART_CHEST := [
	"................",
	"...aaaaaaaaaa...",
	"...deeeeeeeed...",
	"...acccWWccca...",
	"...adddWWddda...",
]
const MINECART_FURNACE := [
	"................",
	"...rrrrrrrrrr...",
	"...rssssssssr...",
	"...rqkkkkkkqr...",
	"...rqkkkkkkqr...",
]


static func _minecart(kind: int) -> Image:
	var img := _spr(MINECART, [Color(0.62, 0.62, 0.66)])
	if kind > 0:
		var top := _spr((MINECART_CHEST if kind == 1 else MINECART_FURNACE) + MINECART.slice(5),
				[WHITE, CHEST_WOOD, Color(0.5, 0.5, 0.5)])
		for y in 5:
			for x in S:
				if top.get_pixel(x, y).a > 0.5:
					img.set_pixel(x, y, top.get_pixel(x, y))
		if kind == 2:
			img.set_pixel(7, 4, Color(1.0, 0.6, 0.15))
			img.set_pixel(8, 4, Color(1.0, 0.8, 0.3))
	return _outline(img, INK)


const BOAT := [
	"................",
	"................",
	"................",
	"................",
	"................",
	".4............4.",
	".45..........54.",
	".44555555555544.",
	"..444444444444..",
	"..433333333334..",
	"...4444444444...",
	"....33333333....",
	"................",
	"................",
	"................",
	"................",
]


static func _sign() -> Image:
	var img := _new()
	var wood := Color(0.7, 0.54, 0.32)
	for y in range(2, 10):
		for x in range(1, 15):
			img.set_pixel(x, y, _vary(wood if y != 5 else _shade(wood, 0.85), 0.04))
	for x in range(3, 13):
		if x != 7:
			img.set_pixel(x, 4, Color(0.3, 0.22, 0.12))
	for x in range(3, 10):
		img.set_pixel(x, 7, Color(0.3, 0.22, 0.12))
	_rect(img, 7, 10, 2, 5, _shade(STICK, 0.9))
	img.set_pixel(8, 11, _shade(STICK, 0.7))
	return _outline(img, INK)


static func _door_item(iron: bool) -> Image:
	var img := _new()
	var base := IRON if iron else Color(0.62, 0.45, 0.24)
	for y in range(1, 15):
		for x in range(4, 12):
			var c := base
			if not iron and x % 2 == 0:
				c = _shade(base, 0.88)
			if y == 7 or x == 4 or x == 11:
				c = _shade(base, 0.74)
			img.set_pixel(x, y, _vary(c, 0.03))
	if iron:
		_rect(img, 5, 3, 2, 2, CLEAR)
		_rect(img, 9, 3, 2, 2, CLEAR)
	else:
		_rect(img, 5, 2, 2, 4, CLEAR)
		_rect(img, 9, 2, 2, 4, CLEAR)
	img.set_pixel(10, 9, _g(0.2))
	return _outline(img, INK)


static func _bed_item() -> Image:
	var img := _new()
	_rect(img, 1, 9, 14, 2, BED_WOOD)
	_rect(img, 1, 11, 1, 2, _shade(BED_WOOD, 0.8))
	_rect(img, 14, 11, 1, 2, _shade(BED_WOOD, 0.8))
	_rect(img, 1, 6, 14, 3, BED_RED)
	for x in range(1, 15):
		img.set_pixel(x, 6, _light(BED_RED, 0.15))
	_rect(img, 1, 5, 4, 3, Color(0.94, 0.94, 0.92))
	img.set_pixel(4, 7, Color(0.78, 0.78, 0.76))
	return _outline(img, INK)


static func _cake_item() -> Image:
	var img := _new()
	var frost := Color(0.96, 0.94, 0.92)
	var sponge := Color(0.76, 0.5, 0.27)
	for y in S:
		for x in S:
			var dx := (x + 0.5 - 8.0) / 6.6
			var top_dy := (y + 0.5 - 6.0) / 2.6
			if dx * dx + top_dy * top_dy <= 1.0:
				img.set_pixel(x, y, _vary(frost, 0.02))
			elif absf(dx) <= 1.0 and y >= 6 and y <= 12:
				var c := _shade(sponge, 1.08 - (x - 1) * 0.03)
				if y == 12:
					c = _shade(sponge, 0.75)
				img.set_pixel(x, y, c)
	for x in range(2, 14):
		if _rng.randf() < 0.5:
			_px(img, x, 9, frost)
	for p in [Vector2i(5, 5), Vector2i(9, 4), Vector2i(11, 6), Vector2i(7, 7), Vector2i(4, 7)]:
		img.set_pixel(p.x, p.y, Color(0.8, 0.1, 0.1))
	return _outline(img, Color(0.3, 0.18, 0.08))


static func _repeater_item() -> Image:
	var img := _new()
	_rect(img, 1, 10, 14, 3, _g(0.62))
	for x in range(1, 15):
		img.set_pixel(x, 10, _g(0.76))
		img.set_pixel(x, 12, _g(0.46))
	for tx in [4, 10]:
		_rect(img, tx, 6, 2, 4, STICK)
		_rect(img, tx, 4, 2, 2, Color(0.95, 0.15, 0.08))
		img.set_pixel(tx, 4, Color(1.0, 0.6, 0.5))
	for x in range(3, 13):
		img.set_pixel(x, 11, Color(0.75, 0.08, 0.06))
	return _outline(img, INK)


static func _cauldron_item() -> Image:
	var img := _new()
	var base := Color(0.32, 0.32, 0.34)
	for y in range(3, 13):
		for x in range(2, 14):
			var inset := 0 if y < 10 else y - 9
			if x < 2 + inset or x > 13 - inset:
				continue
			img.set_pixel(x, y, _shade(base, 1.15 - (x - 2) * 0.035))
	_rect(img, 3, 4, 10, 2, _g(0.12))
	for x in range(2, 14):
		img.set_pixel(x, 3, _light(base, 0.3))
	_rect(img, 3, 13, 2, 1, base)
	_rect(img, 11, 13, 2, 1, base)
	return _outline(img, INK)


const BREWING_ITEM := [
	"................",
	".......ed.......",
	".......dc.......",
	".......dc.......",
	"..33333dc33333..",
	"..3....dc....3..",
	".ggg...dc...ggg.",
	".gwg...dc...gwg.",
	".ggg...dc...ggg.",
	".......dc.......",
	".......dc.......",
	"...4444dc4444...",
	"..455555555554..",
	"..333333333333..",
	"................",
	"................",
]


static func _brewing_item() -> Image:
	return _outline(_spr(BREWING_ITEM, [Color(0.56, 0.56, 0.58), Color(0.96, 0.74, 0.24)],
			{"g": Color(0.8, 0.88, 0.96)}), INK)


static func _painting() -> Image:
	var img := _new()
	var frame := Color(0.55, 0.36, 0.18)
	for y in range(2, 14):
		for x in range(1, 15):
			var c: Color
			if x == 1 or x == 14 or y == 2 or y == 13:
				c = frame
			elif y < 8:
				c = Color(0.5, 0.72, 0.95)
			elif y < 10:
				c = Color(0.36, 0.62, 0.26)
			else:
				c = Color(0.28, 0.5, 0.2)
			img.set_pixel(x, y, c)
	_rect(img, 10, 4, 2, 2, Color(1.0, 0.9, 0.3))
	# Гора: залитый пик с белой вершиной.
	for x in range(3, 10):
		for y in range(5 + absi(x - 6), 9):
			img.set_pixel(x, y, Color(0.5, 0.5, 0.54) if x < 6 else Color(0.4, 0.4, 0.44))
	img.set_pixel(6, 5, WHITE)
	return _outline(img, INK)


# --- Материалы -----------------------------------------------------------------

const DIAMOND := [
	"................",
	"................",
	"....45555554....",
	"...45w55555554..",
	"..455555555554..",
	"..344444444443..",
	"...3444444443...",
	"....34444443....",
	".....344443.....",
	"......3443......",
	".......33.......",
	"................",
	"................",
	"................",
	"................",
	"................",
]
const INGOT := [
	"................",
	"................",
	"................",
	"................",
	"................",
	"....55555555....",
	"...5555555555...",
	"..444444444444..",
	"..444444444443..",
	"..333333333332..",
	"..222222222221..",
	"................",
	"................",
	"................",
	"................",
	"................",
]
const FLINT := [
	"................",
	"................",
	"................",
	"......45........",
	".....4554.......",
	"....45544.......",
	"...4554443......",
	"...45444433.....",
	"..454444433.....",
	"..3444443333....",
	"..34444333332...",
	"...333333222....",
	"....3322222.....",
	".......22.......",
	"................",
	"................",
]
const PILE := [
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	".......45.......",
	"......4554......",
	".....445544.....",
	"....44455444....",
	"...3444444443...",
	"..334444444433..",
	"..223333333322..",
	"................",
	"................",
]


static func _lump(col: Color, hi: Color) -> Image:
	var img := _new()
	_ellipse(img, 7.5, 8.5, 4.6, 4.2, col)
	_ellipse(img, 10.0, 6.5, 3.0, 2.8, col)
	_ellipse(img, 5.0, 10.5, 3.0, 2.6, col)
	_specks(img, hi, 6)
	_specks(img, _shade(col, 0.6), 4)
	return _outline(img, _shade(col, 0.35))


static func _nugget() -> Image:
	var img := _new()
	_ellipse(img, 6.5, 9.0, 2.6, 2.2, GOLD)
	_ellipse(img, 10.0, 7.0, 2.2, 2.0, GOLD)
	_ellipse(img, 9.5, 10.5, 1.8, 1.6, GOLD)
	return _outline(img, Color(0.42, 0.28, 0.02))


static func _stick() -> Image:
	var img := _new()
	for x in range(3, 13):
		img.set_pixel(x, 15 - x, STICK)
		img.set_pixel(x + 1, 15 - x, _shade(STICK, 0.72))
	return _outline(img, INK)


## Миска; stew — с грибным супом.
static func _bowl(stew: bool) -> Image:
	var img := _new()
	var wood := Color(0.6, 0.42, 0.22)
	for y in range(7, 14):
		for x in S:
			var dx := (x + 0.5 - 8.0) / 6.6
			var dy := (y + 0.5 - 7.5) / 5.6
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, _lit(wood, dx, dy * 0.6 + 0.2))
	var inside := Color(0.8, 0.62, 0.44) if stew else _shade(wood, 0.5)
	for x in range(2, 14):
		img.set_pixel(x, 7, inside if x > 2 and x < 13 else _light(wood, 0.2))
		img.set_pixel(x, 8, _shade(inside, 0.85) if x > 2 and x < 13 else wood)
	if stew:
		# Суп горкой над краем миски, с кусочками грибов.
		for x in range(4, 12):
			img.set_pixel(x, 6, _light(inside, 0.1))
		for x in range(6, 10):
			img.set_pixel(x, 5, _light(inside, 0.2))
		for p in [Vector2i(5, 6), Vector2i(8, 5), Vector2i(10, 7), Vector2i(4, 7)]:
			img.set_pixel(p.x, p.y, Color(0.52, 0.32, 0.2))
		img.set_pixel(7, 7, Color(0.78, 0.14, 0.12))
	return _outline(img, Color(0.25, 0.15, 0.06))


static func _string() -> Image:
	var img := _new()
	var col := Color(0.95, 0.95, 0.95)
	var prev := Vector2i(2, 11)
	for s in 41:
		var t := s / 40.0
		var p := Vector2i(roundi(2.0 + t * 11.0), roundi(11.0 - t * 6.0 + sin(t * TAU * 1.5) * 2.5))
		_line(img, prev.x, prev.y, p.x, p.y, col if s % 6 != 0 else _g(0.8))
		prev = p
	return _outline(img, _g(0.35))


static func _feather() -> Image:
	var img := _new()
	var a := Vector2(3.5, 12.5)
	var b := Vector2(12.5, 3.5)
	for y in S:
		for x in S:
			var p := Vector2(x + 0.5, y + 0.5)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var d := (p - (a + ab * t)).length()
			var w := lerpf(0.6, 3.0, minf(t * 1.6, 1.0)) * (1.0 - maxf(t - 0.8, 0.0) * 3.5)
			if t > 0.15 and d <= w:
				var upper := (p - a).cross(ab) < 0.0
				img.set_pixel(x, y, WHITE if upper else _g(0.84))
	for k in 10:
		img.set_pixel(3 + k, 12 - k, _g(0.6))
	return _outline(img, _g(0.4))


static func _pile(col: Color, speck: Color) -> Image:
	var img := _spr(PILE, [col])
	_specks(img, speck, 7)
	_specks(img, _shade(col, 0.6), 5)
	img.set_pixel(2, 12, col)
	img.set_pixel(13, 11, col)
	return _outline(img, _shade(col, 0.35))


static func _leather() -> Image:
	var img := _new()
	var col := Color(0.58, 0.35, 0.18)
	_ellipse(img, 8.0, 8.0, 5.6, 5.0, col)
	for p in [Vector2i(3, 3), Vector2i(12, 3), Vector2i(3, 12), Vector2i(12, 12)]:
		_rect(img, p.x, p.y, 2, 2, _shade(col, 0.9))
	for k in 6:
		var x := _rng.randi_range(2, 13)
		var y := _rng.randi_range(2, 13)
		if img.get_pixel(x, y).a > 0.5:
			img.set_pixel(x, y, _shade(col, 0.78))
	return _outline(img, Color(0.24, 0.13, 0.06))


static func _ball_item(col: Color, r: float) -> Image:
	var img := _new()
	_ellipse(img, 8.0, 8.0, r, r, col)
	return _outline(img, _shade(col, 0.42))


static func _reeds_item() -> Image:
	var img := _new()
	var col := Color(0.56, 0.78, 0.38)
	_capsule(img, Vector2(4.5, 14.0), Vector2(8.5, 2.0), 1.0, col)
	_capsule(img, Vector2(8.5, 14.0), Vector2(12.0, 3.5), 1.0, col)
	for p in [Vector2i(5, 11), Vector2i(7, 5), Vector2i(10, 9), Vector2i(11, 5)]:
		img.set_pixel(p.x, p.y, _light(col, 0.4))
	img.set_pixel(3, 7, col)
	img.set_pixel(4, 8, col)
	return _outline(img, Color(0.2, 0.36, 0.12))


static func _paper() -> Image:
	var img := _new()
	_rect(img, 4, 2, 10, 10, _g(0.8))
	_rect(img, 3, 3, 10, 10, _g(0.9))
	_rect(img, 2, 4, 10, 10, Color(0.98, 0.98, 0.96))
	for y in [7, 9, 11]:
		for x in range(4, 10):
			img.set_pixel(x, y, Color(0.84, 0.84, 0.88))
	return _outline(img, _g(0.45))


static func _book() -> Image:
	var img := _new()
	var cover := Color(0.52, 0.3, 0.15)
	_rect(img, 3, 2, 10, 12, cover)
	_rect(img, 3, 2, 2, 12, _shade(cover, 0.7))
	_rect(img, 12, 3, 2, 11, Color(0.95, 0.94, 0.88))
	_rect(img, 4, 13, 10, 1, Color(0.95, 0.94, 0.88))
	for y in range(4, 13, 2):
		img.set_pixel(13, y, Color(0.75, 0.74, 0.68))
	_rect(img, 7, 5, 4, 2, _light(cover, 0.3))
	return _outline(img, Color(0.2, 0.1, 0.04))


static func _slimeball() -> Image:
	var img := _new()
	var col := Color(0.45, 0.8, 0.35)
	_ellipse(img, 8.0, 8.5, 4.8, 4.4, col)
	_ellipse(img, 7.5, 8.0, 2.2, 2.0, Color(0.62, 0.9, 0.5))
	return _outline(img, Color(0.18, 0.4, 0.12))


static func _bone() -> Image:
	var img := _new()
	var col := Color(0.93, 0.91, 0.84)
	_capsule(img, Vector2(4.5, 11.5), Vector2(11.5, 4.5), 1.2, col)
	for c in [Vector2(3.0, 11.5), Vector2(4.5, 13.0), Vector2(11.5, 3.0), Vector2(13.0, 4.5)]:
		_ellipse(img, c.x, c.y, 1.6, 1.6, col)
	return _outline(img, Color(0.42, 0.4, 0.34))


static func _egg() -> Image:
	var img := _new()
	var col := Color(0.93, 0.86, 0.68)
	for y in S:
		for x in S:
			var dy := (y + 0.5 - 9.0) / 5.4
			var rx := 4.2 if dy > 0.0 else 4.2 * (1.0 - dy * dy * 0.28)
			var dx := (x + 0.5 - 8.0) / rx
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, _lit(col, dx, dy))
	_specks(img, Color(0.72, 0.58, 0.4), 4)
	return _outline(img, Color(0.45, 0.36, 0.22))


static func _ender_pearl() -> Image:
	var img := _new()
	_ellipse(img, 8.0, 8.0, 5.0, 5.0, Color(0.12, 0.44, 0.4))
	_ellipse(img, 7.5, 7.5, 2.4, 2.4, Color(0.34, 0.78, 0.66))
	img.set_pixel(6, 6, Color(0.7, 1.0, 0.92))
	return _outline(img, Color(0.03, 0.14, 0.12))


static func _eye_of_ender() -> Image:
	var img := _new()
	_ellipse(img, 8.0, 8.0, 5.0, 5.0, Color(0.3, 0.56, 0.28))
	_ellipse(img, 8.0, 8.0, 3.0, 3.6, Color(0.62, 0.86, 0.4))
	for y in range(5, 11):
		img.set_pixel(7, y, Color(0.08, 0.16, 0.08))
		img.set_pixel(8, y, Color(0.08, 0.16, 0.08))
	img.set_pixel(6, 5, Color(0.9, 1.0, 0.8))
	return _outline(img, Color(0.06, 0.16, 0.06))


static func _blaze_rod() -> Image:
	var img := _new()
	_capsule(img, Vector2(3.5, 12.5), Vector2(12.5, 3.5), 1.5, Color(1.0, 0.72, 0.18))
	for k in 4:
		var p := 4 + k * 2
		_px(img, p, 14 - p, Color(1.0, 0.95, 0.6))
	return _outline(img, Color(0.5, 0.26, 0.04))


static func _ghast_tear() -> Image:
	var img := _new()
	var col := Color(0.82, 0.96, 0.96)
	for y in S:
		for x in S:
			var dx := x + 0.5 - 8.0
			var dy := y + 0.5 - 10.0
			if dx * dx + dy * dy <= 3.6 * 3.6 or (y >= 3 and y < 10 and absf(dx) <= (y - 2) * 0.48):
				img.set_pixel(x, y, _lit(col, dx / 3.6, clampf(dy / 3.6, -1.0, 1.0)))
	img.set_pixel(6, 9, WHITE)
	return _outline(img, Color(0.38, 0.56, 0.62))


static func _magma_cream() -> Image:
	var img := _new()
	_ellipse(img, 8.0, 8.0, 4.8, 4.6, Color(0.88, 0.46, 0.14))
	_ellipse(img, 8.0, 8.0, 2.0, 2.0, Color(1.0, 0.82, 0.3))
	for p in [Vector2i(5, 6), Vector2i(10, 5), Vector2i(11, 10), Vector2i(6, 11), Vector2i(4, 9)]:
		img.set_pixel(p.x, p.y, Color(0.3, 0.12, 0.05))
	return _outline(img, Color(0.32, 0.12, 0.04))


static func _nether_wart_item() -> Image:
	var img := _new()
	var col := Color(0.64, 0.12, 0.14)
	_ellipse(img, 6.0, 7.0, 3.2, 3.0, col)
	_ellipse(img, 10.5, 8.0, 2.8, 2.8, col)
	_ellipse(img, 7.5, 11.0, 2.8, 2.6, col)
	_specks(img, _shade(col, 0.6), 6)
	return _outline(img, Color(0.24, 0.03, 0.04))


static func _spider_eye(fermented: bool) -> Image:
	var img := _new()
	var col := Color(0.6, 0.2, 0.32) if fermented else Color(0.72, 0.2, 0.24)
	_ellipse(img, 8.0, 9.0, 4.8, 4.4, col)
	for p in [Vector2i(6, 8), Vector2i(10, 8), Vector2i(8, 11)]:
		img.set_pixel(p.x, p.y, Color(0.25, 0.04, 0.08))
		img.set_pixel(p.x + 1, p.y, Color(0.35, 0.06, 0.1))
	if fermented:
		_ellipse(img, 5.5, 4.5, 3.0, 1.8, Color(0.58, 0.42, 0.3))
		_rect(img, 5, 6, 1, 2, Color(0.86, 0.8, 0.7))
		_specks(img, Color(0.95, 0.95, 0.95), 3)
	return _outline(img, Color(0.25, 0.05, 0.08))


## Ломтик арбуза; speckled — блестящий (с золотыми крапинками).
static func _melon_slice(speckled: bool) -> Image:
	var img := _new()
	for y in S:
		for x in S:
			var dx := x + 0.5 - 12.0
			var dy := y + 0.5 - 4.0
			var r := sqrt(dx * dx + dy * dy)
			var a := atan2(dy, dx)
			if r > 10.5 or a < PI / 2.0 - 0.05 or a > PI + 0.05:
				continue
			var c := Color(0.9, 0.2, 0.18)
			if r > 9.4:
				c = Color(0.34, 0.6, 0.15)
			elif r > 8.6:
				c = Color(0.84, 0.88, 0.62)
			img.set_pixel(x, y, c)
	for p in [Vector2i(8, 7), Vector2i(5, 9), Vector2i(9, 10), Vector2i(4, 6)]:
		img.set_pixel(p.x, p.y, Color(0.1, 0.06, 0.04) if not speckled else Color(1.0, 0.88, 0.3))
	if speckled:
		_specks(img, Color(1.0, 0.92, 0.45), 6)
	return _outline(img, Color(0.12, 0.25, 0.05))


## Бутылка (пустое стекло); liquid — цвет содержимого (CLEAR — пустая).
const BOTTLE := [
	"................",
	"......oooo......",
	"......ogwo......",
	"......oLLo......",
	"......oLLo......",
	".....oLLLLo.....",
	"....oLLLLLLo....",
	"...oLLLLLLLLo...",
	"...owLLLLLLLo...",
	"...owLLLLLLLo...",
	"...oLLLLLLLLo...",
	"...oLLLLLLLLo...",
	"....oLLLLLLo....",
	".....oooooo.....",
	"................",
	"................",
]
const BOTTLE_SPLASH := [
	"................",
	"................",
	".....oooooo.....",
	".....ogwggo.....",
	"......oLLo......",
	".....oLLLLo.....",
	"...ooLLLLLLoo...",
	"..ogLLLLLLLLgo..",
	"..ogwLLLLLLLgo..",
	"..ogwLLLLLLLgo..",
	"..ogLLLLLLLLgo..",
	"...oLLLLLLLLo...",
	"....oLLLLLLo....",
	".....oooooo.....",
	"................",
	"................",
]


static func _bottle(rows: Array, liquid: Color) -> Image:
	var img := _spr(rows, [], {"o": Color(0.36, 0.42, 0.55), "g": Color(0.78, 0.86, 0.96), "L": CLEAR})
	if liquid.a > 0.0:
		for y in range(5, S):
			for x in S:
				if (rows[y] as String)[x] == "L":
					img.set_pixel(x, y, _shade(liquid, 1.08 - (x - 4) * 0.04))
		img.set_pixel(6, 8, Color(1.0, 1.0, 0.7))
		img.set_pixel(9, 10, Color(1.0, 1.0, 0.7))
	return img


## Жидкость зелья (серая, окрашивается цветом эффекта) — ровно внутренность BOTTLE со строки 6.
static func _potion_overlay() -> Image:
	var img := _new()
	for y in range(6, S):
		var row: String = BOTTLE[y]
		for x in S:
			if row[x] == "L":
				var v := 0.88 - (x - 5) * 0.035
				if row[x + 1] != "L" or y == 12:
					v = 0.66
				img.set_pixel(x, y, _g(clampf(v, 0.6, 1.0)))
	img.set_pixel(6, 9, _g(1.0))
	img.set_pixel(7, 11, _g(1.0))
	return img


static func _fire_charge() -> Image:
	var img := _new()
	_ellipse(img, 8.0, 8.0, 4.8, 4.8, Color(0.3, 0.2, 0.14))
	var n := _vnoise(4)
	for y in S:
		for x in S:
			if img.get_pixel(x, y).a > 0.5:
				var t := n[y * S + x]
				if t > 0.62:
					img.set_pixel(x, y, Color(1.0, 0.72, 0.2))
				elif t > 0.5:
					img.set_pixel(x, y, Color(0.9, 0.36, 0.08))
	return _outline(img, Color(0.08, 0.05, 0.03))


## Яйцо призыва: серое яйцо (окрашивается первым цветом) или только серые пятна (вторым).
static func _spawn_egg(overlay: bool) -> Image:
	var img := _new()
	var mask := _new()
	for y in S:
		for x in S:
			var dy := (y + 0.5 - 8.8) / 6.0
			var dx := (x + 0.5 - 8.0) / 4.6
			if dy < 0.0:
				dx *= 1.0 + dy * dy * 0.35
			if dx * dx + dy * dy <= 1.0:
				mask.set_pixel(x, y, _lit(_g(0.92), dx, dy))
	if not overlay:
		return _outline(mask, _g(0.3))
	for p in [Vector2i(6, 5), Vector2i(10, 7), Vector2i(5, 10), Vector2i(9, 11), Vector2i(8, 3)]:
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var q: Vector2i = p + d
			if mask.get_pixel(q.x, q.y).a > 0.5:
				img.set_pixel(q.x, q.y, _g(0.95 if d == Vector2i(0, 0) else 0.82))
	return img


static func _seeds(col: Color, count: int, size: int) -> Image:
	var img := _new()
	var spots := [Vector2i(4, 4), Vector2i(10, 3), Vector2i(7, 7), Vector2i(3, 10), Vector2i(11, 9),
		Vector2i(6, 12), Vector2i(12, 13)]
	for k in count:
		var p: Vector2i = spots[k] + Vector2i(_rng.randi_range(-1, 1), _rng.randi_range(-1, 0))
		_rect(img, p.x, p.y, size, size + 1, col)
		img.set_pixel(p.x, p.y, _light(col, 0.3))
		img.set_pixel(p.x + size - 1, p.y + size, _shade(col, 0.7))
	return _outline(img, _shade(col, 0.35) if col.get_luminance() > 0.3 else Color(0.02, 0.01, 0.0))


static func _wheat_item() -> Image:
	var img := _new()
	var stalk := Color(0.72, 0.63, 0.28)
	var ear := Color(0.88, 0.74, 0.32)
	for s in 3:
		var x0: int = [3, 5, 2][s]
		var y0: int = [14, 14, 12][s]
		var x1: int = [9, 12, 7][s]
		var y1: int = [5, 6, 4][s]
		_line(img, x0, y0, x1, y1, stalk)
		for k in 4:
			_px(img, x1 + (k & 1) - 1, y1 - 2 + k, ear if k % 2 == 0 else _shade(ear, 0.8))
			_px(img, x1 + (k & 1), y1 - 3 + k, _light(ear, 0.2))
	return _outline(img, Color(0.36, 0.28, 0.08))


# --- Красители -----------------------------------------------------------------

static func _dye(k: int) -> Image:
	var col: Color = DYE_COLORS[k]
	match k:
		0:
			var sac := _new()
			_ellipse(sac, 8.0, 9.5, 4.6, 4.4, col)
			_rect(sac, 7, 3, 2, 3, _light(col, 0.15))
			sac.set_pixel(6, 5, _light(col, 0.25))
			sac.set_pixel(9, 5, _light(col, 0.25))
			return _outline(sac, Color(0.03, 0.03, 0.05))
		3:
			var beans := _new()
			_ellipse(beans, 5.5, 8.5, 2.7, 4.2, col)
			_ellipse(beans, 10.5, 7.5, 2.7, 4.2, col)
			for y in range(6, 11):
				beans.set_pixel(5, y, _shade(col, 0.55))
				beans.set_pixel(10, y - 1, _shade(col, 0.55))
			return _outline(beans, Color(0.18, 0.09, 0.03))
		4:
			var gem := _spr(FLINT, [col])
			_specks(gem, Color(0.62, 0.74, 1.0), 6)
			return _outline(gem, Color(0.04, 0.08, 0.28))
		15:
			return _pile(col, Color(0.8, 0.8, 0.76))
	# Обычный краситель — комочек порошка «бутылочкой».
	var blob := _new()
	_ellipse(blob, 8.0, 10.0, 4.8, 3.9, col)
	_ellipse(blob, 8.0, 6.0, 2.6, 2.5, col)
	_specks(blob, _light(col, 0.45), 4)
	_specks(blob, _shade(col, 0.7), 3)
	return _outline(blob, _shade(col, 0.35))


# --- Еда -----------------------------------------------------------------------

const APPLE := [
	"................",
	"........c.......",
	"........cqr.....",
	"....444.4444....",
	"...4554444443...",
	"...4554444443...",
	"...4544444443...",
	"...4444444443...",
	"...4444444433...",
	"...3444444433...",
	"...3344444333...",
	"....33443333....",
	".....333333.....",
	"......2..2......",
	"................",
	"................",
]


static func _bread() -> Image:
	var img := _new()
	var col := Color(0.74, 0.52, 0.26)
	_capsule(img, Vector2(4.0, 11.5), Vector2(11.5, 4.5), 2.8, col)
	for k in 3:
		var c := Vector2(5.5 + k * 2.5, 10.0 - k * 2.5)
		_px(img, int(c.x) - 1, int(c.y) - 1, Color(0.95, 0.82, 0.55))
		_px(img, int(c.x), int(c.y) - 1, Color(0.95, 0.82, 0.55))
		_px(img, int(c.x), int(c.y), Color(0.95, 0.82, 0.55))
	return _outline(img, Color(0.3, 0.18, 0.07))


static func _chop(meat: Color, fat: Color, outline: Color) -> Image:
	var img := _new()
	# Отбивная: округлый кусок с выступом и светлым жиром по верхнему правому краю.
	_ellipse(img, 7.5, 9.0, 5.4, 4.4, meat)
	_ellipse(img, 11.0, 5.5, 3.0, 2.6, meat)
	var src := img.duplicate() as Image
	for y in S:
		for x in S:
			if src.get_pixel(x, y).a > 0.5 and (not _opaque(src, x + 1, y) or not _opaque(src, x, y - 1)) and x + y > 11:
				img.set_pixel(x, y, fat)
	img.set_pixel(6, 9, _shade(meat, 0.78))
	img.set_pixel(7, 10, _shade(meat, 0.78))
	return _outline(img, outline)


static func _steak(cooked: bool) -> Image:
	var img := _new()
	var col := Color(0.47, 0.29, 0.16) if cooked else Color(0.78, 0.18, 0.16)
	_ellipse(img, 8.0, 8.5, 5.8, 4.6, col)
	_ellipse(img, 3.5, 10.0, 2.2, 2.0, col)
	var line := Color(0.26, 0.15, 0.08) if cooked else Color(0.96, 0.72, 0.7)
	for k in 3:
		_line(img, 5 + k * 3, 6, 3 + k * 3, 11, line)
	return _outline(img, Color(0.2, 0.08, 0.04))


static func _drumstick(meat: Color) -> Image:
	var img := _new()
	_capsule(img, Vector2(3.5, 12.5), Vector2(7.0, 9.0), 0.9, Color(0.95, 0.94, 0.88))
	_ellipse(img, 2.5, 12.5, 1.3, 1.3, Color(0.95, 0.94, 0.88))
	_ellipse(img, 3.5, 13.5, 1.3, 1.3, Color(0.95, 0.94, 0.88))
	_ellipse(img, 9.5, 6.5, 4.4, 4.0, meat)
	return _outline(img, _shade(meat, 0.3))


static func _fish(cooked: bool) -> Image:
	var img := _new()
	var col := Color(0.78, 0.6, 0.38) if cooked else Color(0.55, 0.66, 0.76)
	_ellipse(img, 9.0, 8.0, 5.2, 3.2, col)
	for y in range(4, 12):
		var w := absi(y - 8)
		for x in range(1, 4):
			if x >= 1 + (3 - w) and w <= 3 or (x == 3 and w <= 1):
				img.set_pixel(x, y, _shade(col, 0.85))
	img.set_pixel(12, 7, Color(0.08, 0.08, 0.08))
	for x in range(6, 13):
		img.set_pixel(x, 6, _shade(col, 0.8))
	return _outline(img, _shade(col, 0.32))


static func _cookie() -> Image:
	var img := _new()
	var col := Color(0.82, 0.58, 0.3)
	for y in S:
		for x in S:
			var d := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.0).length()
			if d < 5.6:
				img.set_pixel(x, y, _vary(col, 0.05))
	for p in [Vector2i(5, 6), Vector2i(9, 5), Vector2i(10, 9), Vector2i(6, 10), Vector2i(8, 8)]:
		img.set_pixel(p.x, p.y, Color(0.3, 0.17, 0.08))
	return _outline(img, Color(0.38, 0.23, 0.1))


static func _rotten_flesh() -> Image:
	var img := _new()
	_ellipse(img, 8.0, 8.0, 5.4, 4.2, Color(0.62, 0.44, 0.3))
	_ellipse(img, 5.0, 11.0, 2.4, 2.2, Color(0.62, 0.44, 0.3))
	_ellipse(img, 11.5, 5.0, 2.2, 2.0, Color(0.62, 0.44, 0.3))
	var n := _vnoise(4)
	for y in S:
		for x in S:
			if img.get_pixel(x, y).a > 0.5 and n[y * S + x] > 0.55:
				img.set_pixel(x, y, _vary(Color(0.44, 0.55, 0.25), 0.08))
	return _outline(img, Color(0.22, 0.13, 0.07))


# --- Пластинки -----------------------------------------------------------------

static func _record(k: int) -> Image:
	var img := _new()
	var label: Color = RECORD_COLORS[k]
	for y in S:
		for x in S:
			var dx := x + 0.5 - 8.0
			var dy := y + 0.5 - 8.0
			var r := sqrt(dx * dx + dy * dy)
			if r > 6.9:
				continue
			var c := Color(0.1, 0.1, 0.11)
			if r < 0.8:
				c = Color(0.04, 0.04, 0.04)
			elif r <= 2.6:
				c = _shade(label, 1.08 - (dx + dy) * 0.06)
			elif int(r * 1.6) % 2 == 0:
				c = Color(0.18, 0.18, 0.2)
			if r > 3.0 and absf(dx + dy) < 0.8 and dx < 0.0:
				c = Color(0.36, 0.36, 0.4)
			img.set_pixel(x, y, c)
	if k == 10:
		_line(img, 2, 5, 13, 10, Color(0.02, 0.02, 0.02))
		_line(img, 3, 5, 13, 9, Color(0.3, 0.3, 0.32))
	return _outline(img, Color(0.02, 0.02, 0.02))
