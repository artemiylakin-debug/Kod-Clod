class_name MobDefs
extends RefCounted
## Справочник существ Minecraft 1.2: номера (как ID сущностей в оригинале), названия, здоровье,
## размеры тела, скорость, урон, опыт, категория появления и особые свойства.

enum {
	CREEPER = 50, SKELETON = 51, SPIDER = 52, GIANT = 53, ZOMBIE = 54, SLIME = 55, GHAST = 56,
	PIG_ZOMBIE = 57, ENDERMAN = 58, CAVE_SPIDER = 59, SILVERFISH = 60, BLAZE = 61, MAGMA_CUBE = 62,
	ENDER_DRAGON = 63, PIG = 90, SHEEP = 91, COW = 92, CHICKEN = 93, SQUID = 94, WOLF = 95,
	MOOSHROOM = 96, SNOW_GOLEM = 97, OCELOT = 98, IRON_GOLEM = 99, VILLAGER = 120, END_CRYSTAL = 200,
}

## Категории появления: монстры, животные, водные, прочие (жители, големы, босс).
enum { CAT_MONSTER, CAT_CREATURE, CAT_WATER, CAT_MISC }

## Свойства-флаги.
const F_FIRE_IMMUNE := 1
const F_UNDEAD := 2
const F_FLYING := 4
const F_NO_FALL := 8
const F_WATER_BREATHER := 16
const F_ARTHROPOD := 32
## Не исчезает вдали от игрока.
const F_PERSISTENT := 64
## Монстр для проверки сна (EntityMob в оригинале).
const F_MOB := 128
## Сгорает на солнце.
const F_SUN_BURN := 256
## Получает урон от воды.
const F_WATER_HURTS := 512

## Тип → [название, здоровье, половина ширины, высота, скорость (блоков/с), урон (нормальная сложность),
## опыт, категория, флаги].
const INFO := {
	CREEPER: ["Крипер", 20, 0.3, 1.7, 2.3, 0, 5, CAT_MONSTER, F_MOB],
	SKELETON: ["Скелет", 20, 0.3, 1.8, 2.5, 4, 5, CAT_MONSTER, F_MOB | F_UNDEAD | F_SUN_BURN],
	SPIDER: ["Паук", 16, 0.7, 0.9, 3.2, 2, 5, CAT_MONSTER, F_MOB | F_ARTHROPOD],
	GIANT: ["Гигант", 100, 1.8, 10.8, 2.3, 50, 5, CAT_MONSTER, F_MOB | F_UNDEAD],
	ZOMBIE: ["Зомби", 20, 0.3, 1.8, 2.3, 4, 5, CAT_MONSTER, F_MOB | F_UNDEAD | F_SUN_BURN],
	SLIME: ["Слизень", 16, 0.3, 0.6, 2.5, 0, 1, CAT_MONSTER, 0],
	GHAST: ["Гаст", 10, 2.0, 4.0, 1.6, 0, 5, CAT_MONSTER, F_FIRE_IMMUNE | F_FLYING | F_NO_FALL],
	PIG_ZOMBIE: ["Зомби-свиночеловек", 20, 0.3, 1.8, 2.3, 5, 5, CAT_MONSTER, F_MOB | F_UNDEAD | F_FIRE_IMMUNE],
	ENDERMAN: ["Эндермен", 40, 0.3, 2.9, 2.8, 7, 5, CAT_MONSTER, F_MOB | F_WATER_HURTS],
	CAVE_SPIDER: ["Пещерный паук", 12, 0.35, 0.5, 3.4, 2, 5, CAT_MONSTER, F_MOB | F_ARTHROPOD],
	SILVERFISH: ["Чешуйница", 8, 0.15, 0.7, 2.6, 1, 5, CAT_MONSTER, F_MOB | F_ARTHROPOD],
	BLAZE: ["Ифрит", 20, 0.3, 1.8, 2.2, 6, 10, CAT_MONSTER, F_MOB | F_FIRE_IMMUNE | F_NO_FALL | F_WATER_HURTS],
	MAGMA_CUBE: ["Магмовый куб", 16, 0.3, 0.6, 2.5, 0, 1, CAT_MONSTER, F_FIRE_IMMUNE | F_NO_FALL],
	ENDER_DRAGON: ["Дракон Края", 200, 4.0, 4.0, 14.0, 10, 12000, CAT_MISC,
		F_FIRE_IMMUNE | F_FLYING | F_NO_FALL | F_PERSISTENT | F_WATER_BREATHER],
	PIG: ["Свинья", 10, 0.45, 0.9, 2.2, 0, 1, CAT_CREATURE, F_PERSISTENT],
	SHEEP: ["Овца", 8, 0.45, 1.3, 2.2, 0, 1, CAT_CREATURE, F_PERSISTENT],
	COW: ["Корова", 10, 0.45, 1.3, 2.0, 0, 1, CAT_CREATURE, F_PERSISTENT],
	CHICKEN: ["Курица", 4, 0.2, 0.7, 2.0, 0, 1, CAT_CREATURE, F_PERSISTENT | F_NO_FALL],
	SQUID: ["Спрут", 10, 0.475, 0.95, 2.0, 0, 1, CAT_WATER, F_WATER_BREATHER],
	WOLF: ["Волк", 8, 0.3, 0.8, 3.0, 2, 1, CAT_CREATURE, F_PERSISTENT],
	MOOSHROOM: ["Грибная корова", 10, 0.45, 1.3, 2.0, 0, 1, CAT_CREATURE, F_PERSISTENT],
	SNOW_GOLEM: ["Снежный голем", 4, 0.2, 1.8, 2.2, 0, 0, CAT_MISC, F_PERSISTENT | F_WATER_HURTS],
	OCELOT: ["Оцелот", 10, 0.3, 0.8, 2.8, 3, 1, CAT_CREATURE, F_PERSISTENT | F_NO_FALL],
	IRON_GOLEM: ["Железный голем", 100, 0.7, 2.9, 1.7, 7, 0, CAT_MISC, F_PERSISTENT | F_NO_FALL | F_WATER_BREATHER],
	VILLAGER: ["Житель", 20, 0.3, 1.8, 1.8, 0, 0, CAT_MISC, F_PERSISTENT],
	END_CRYSTAL: ["Кристалл Края", 1, 1.0, 2.0, 0.0, 0, 0, CAT_MISC,
		F_PERSISTENT | F_FIRE_IMMUNE | F_NO_FALL | F_WATER_BREATHER],
}

## Профессии жителей 1.2 (цвет одежды).
const PROFESSIONS := ["Фермер", "Библиотекарь", "Священник", "Кузнец", "Мясник"]
## Окрасы кошек: 0 — дикий оцелот, 1 — чёрная, 2 — рыжая, 3 — сиамская.
const CAT_SKINS := ["Оцелот", "Чёрная кошка", "Рыжая кошка", "Сиамская кошка"]

## Мясо, которым кормят и разводят прирученных волков.
const WOLF_FOOD := [Items.PORKCHOP, Items.COOKED_PORKCHOP, Items.BEEF, Items.COOKED_BEEF, Items.CHICKEN,
	Items.COOKED_CHICKEN, Items.ROTTEN_FLESH]
## Блоки, которые эндермен может поднять (1.2).
const ENDERMAN_CARRY := [Blocks.GRASS, Blocks.DIRT, Blocks.SAND, Blocks.GRAVEL, Blocks.DANDELION, Blocks.ROSE,
	Blocks.BROWN_MUSHROOM, Blocks.RED_MUSHROOM, Blocks.TNT, Blocks.CACTUS, Blocks.CLAY, Blocks.PUMPKIN,
	Blocks.MELON, Blocks.MYCELIUM]


static func exists(type: int) -> bool:
	return INFO.has(type)


static func info(type: int) -> Array:
	return INFO.get(type, INFO[PIG])


static func name_of(type: int) -> String:
	return str(info(type)[0])


static func max_health(type: int) -> int:
	return int(info(type)[1])


static func category(type: int) -> int:
	return int(info(type)[7])


static func flags(type: int) -> int:
	return int(info(type)[8])


static func has_flag(type: int, flag: int) -> bool:
	return flags(type) & flag != 0


static func is_hostile_category(type: int) -> bool:
	return category(type) == CAT_MONSTER


## Предмет, которым животное приманивают и разводят (1.2: пшеница, семена, рыба, мясо).
static func breed_item(type: int) -> Array:
	match type:
		PIG, SHEEP, COW, MOOSHROOM:
			return [Items.WHEAT]
		CHICKEN:
			return [Items.SEEDS]
		OCELOT:
			return [Items.FISH]
		WOLF:
			return WOLF_FOOD
	return []


## Естественный окрас шерсти овцы (вероятности 1.2).
static func random_fleece(rng: RandomNumberGenerator) -> int:
	var r := rng.randi_range(0, 99)
	if r < 5:
		return 15
	if r < 10:
		return 7
	if r < 15:
		return 8
	if r < 18:
		return 12
	if rng.randi_range(0, 500) == 0:
		return 6
	return 0
