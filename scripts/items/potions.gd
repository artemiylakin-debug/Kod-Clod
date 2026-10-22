class_name Potions
extends RefCounted
## Зелья 1.2: значение данных предмета «Зелье» кодирует эффект (биты 0–3), уровень II (бит 5),
## продление (бит 6), пригодность для питья (бит 13) и взрывное зелье (бит 14) — как в оригинале.

## Эффекты состояния (номера как у эффектов зелий 1.2).
enum { NONE = 0, SPEED = 1, SLOWNESS = 2, HASTE = 3, MINING_FATIGUE = 4, STRENGTH = 5, INSTANT_HEALTH = 6,
	INSTANT_DAMAGE = 7, JUMP = 8, NAUSEA = 9, REGENERATION = 10, RESISTANCE = 11, FIRE_RESISTANCE = 12,
	WATER_BREATHING = 13, INVISIBILITY = 14, BLINDNESS = 15, NIGHT_VISION = 16, HUNGER = 17, WEAKNESS = 18,
	POISON = 19 }

const EFFECT_NAMES := {
	SPEED: "Скорость", SLOWNESS: "Замедление", STRENGTH: "Сила", INSTANT_HEALTH: "Исцеление",
	INSTANT_DAMAGE: "Вред", REGENERATION: "Регенерация", FIRE_RESISTANCE: "Огнестойкость",
	HUNGER: "Голод", WEAKNESS: "Слабость", POISON: "Отравление",
}

const WATER := 0
const AWKWARD := 16
const THICK := 32
const MUNDANE := 64
const DRINKABLE := 8192
const SPLASH := 16384
const LEVEL_TWO := 32
const EXTENDED := 64

## Тип зелья (биты 0–3) → [эффект, длительность в секундах (обычная, продлённая, уровень II), цвет].
const KINDS := {
	1: [REGENERATION, [45, 120, 22], Color8(205, 92, 171)],
	2: [SPEED, [180, 480, 90], Color8(124, 175, 198)],
	3: [FIRE_RESISTANCE, [180, 480, 180], Color8(228, 154, 58)],
	4: [POISON, [45, 120, 22], Color8(78, 147, 49)],
	5: [INSTANT_HEALTH, [0, 0, 0], Color8(248, 36, 35)],
	8: [WEAKNESS, [90, 240, 90], Color8(72, 77, 72)],
	9: [STRENGTH, [180, 480, 90], Color8(147, 36, 35)],
	10: [SLOWNESS, [90, 240, 90], Color8(90, 108, 129)],
	12: [INSTANT_DAMAGE, [0, 0, 0], Color8(67, 10, 9)],
}

const CREATIVE := [0, 16, 32, 64, 8193, 8225, 8257, 8194, 8226, 8258, 8195, 8259, 8196, 8228, 8260, 8197, 8229,
	8200, 8264, 8201, 8233, 8265, 8202, 8266, 8204, 8236, 16385, 16386, 16388, 16389, 16392, 16393, 16394, 16396]


static func kind(data: int) -> int:
	return data & 15


static func is_splash(data: int) -> bool:
	return data & SPLASH != 0


static func is_level_two(data: int) -> bool:
	return data & LEVEL_TWO != 0 and KINDS.has(kind(data))


static func is_extended(data: int) -> bool:
	return data & EXTENDED != 0 and KINDS.has(kind(data))


## Эффект зелья: [эффект, уровень (0 — I, 1 — II), длительность в секундах] или пустой массив.
static func effect_of(data: int) -> Array:
	var k := kind(data)
	if not KINDS.has(k):
		return []
	var info: Array = KINDS[k]
	var durations: Array = info[1]
	var level := 1 if is_level_two(data) else 0
	var seconds: int = durations[2] if level == 1 else (durations[1] if is_extended(data) else durations[0])
	if is_splash(data):
		seconds = int(seconds * 0.75)
	return [int(info[0]), level, seconds]


static func color_of(data: int) -> Color:
	var k := kind(data)
	if KINDS.has(k):
		return KINDS[k][2]
	return Color8(56, 93, 198)


static func name_of(data: int) -> String:
	var k := kind(data)
	var prefix := "Взрывное зелье" if is_splash(data) else "Зелье"
	if not KINDS.has(k):
		match data:
			WATER:
				return "Бутылочка воды"
			AWKWARD:
				return "Грубое зелье"
			THICK:
				return "Густое зелье"
		return "Обычное зелье"
	var eff: int = KINDS[k][0]
	var n := "%s: %s" % [prefix, EFFECT_NAMES.get(eff, "?")]
	if is_level_two(data):
		n += " II"
	if is_extended(data):
		n += " (долгое)"
	return n


## Результат варки: зелье data + ингредиент (ID предмета) → новое значение данных или -1 (не варится).
static func brew(data: int, ingredient: int) -> int:
	var k := kind(data)
	if ingredient == Items.GUNPOWDER:
		if data & DRINKABLE:
			return (data & ~DRINKABLE) | SPLASH
		return -1
	if data == WATER:
		match ingredient:
			Items.NETHER_WART:
				return AWKWARD
			Items.GLOWSTONE_DUST:
				return THICK
			Items.REDSTONE, Items.SUGAR, Items.GHAST_TEAR, Items.SPIDER_EYE, Items.BLAZE_POWDER, Items.MAGMA_CREAM, \
					Items.SPECKLED_MELON:
				return MUNDANE
			Items.FERMENTED_SPIDER_EYE:
				return DRINKABLE | 8
		return -1
	if data == AWKWARD:
		match ingredient:
			Items.SUGAR:
				return DRINKABLE | 2
			Items.GHAST_TEAR:
				return DRINKABLE | 1
			Items.SPIDER_EYE:
				return DRINKABLE | 4
			Items.MAGMA_CREAM:
				return DRINKABLE | 3
			Items.SPECKLED_MELON:
				return DRINKABLE | 5
			Items.BLAZE_POWDER:
				return DRINKABLE | 9
		return -1
	if not KINDS.has(k):
		return -1
	var flags := data & (SPLASH | DRINKABLE)
	match ingredient:
		Items.REDSTONE:
			if k == 5 or k == 12:
				return -1
			return flags | EXTENDED | k
		Items.GLOWSTONE_DUST:
			if k == 3 or k == 8 or k == 10:
				return -1
			return flags | LEVEL_TWO | k
		Items.FERMENTED_SPIDER_EYE:
			var to := -1
			match k:
				2, 3:
					to = 10
				5, 4:
					to = 12
				1, 9:
					to = 8
			if to < 0:
				return -1
			return flags | (data & (LEVEL_TWO | EXTENDED)) | to
	return -1
