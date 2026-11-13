class_name Achievements
extends RefCounted
## Достижения и статистика Minecraft 1.2 (AchievementList и StatList): 27 достижений с «родителями» —
## достижение открывается, только если уже получено предыдущее в дереве, — и счётчики игры.
## Общие для всех миров (как файл статистики игрока), хранятся в user://stats.json.
## Всё статическое: доступно из любого кода без автозагрузки, в том числе в тестах.

## Файл статистики (тесты подменяют его, чтобы не трогать настоящий).
static var path := "user://stats.json"

## Порядок показа: [id, название, описание, значок (предмет или блок), родитель].
static var LIST := [
	["open_inventory", "Инвентаризация", "Нажмите «E», чтобы открыть инвентарь", Items.BOOK, ""],
	["mine_wood", "Добыча древесины", "Бейте дерево, пока из него не выпадет бревно", Blocks.LOG, "open_inventory"],
	["build_workbench", "Рабочее место", "Сделайте верстак из четырёх досок", Blocks.CRAFTING_TABLE, "mine_wood"],
	["build_pickaxe", "Пора в шахту!", "Сделайте кирку из досок и палок", Items.WOODEN_PICKAXE, "build_workbench"],
	["build_furnace", "Горячая тема", "Сложите печь из восьми булыжников", Blocks.FURNACE, "build_pickaxe"],
	["acquire_iron", "Железо в руках", "Выплавьте железный слиток", Items.IRON_INGOT, "build_furnace"],
	["build_hoe", "Пора на ферму!", "Сделайте мотыгу из досок и палок", Items.WOODEN_HOE, "build_workbench"],
	["make_bread", "Испечь хлеб", "Превратите пшеницу в хлеб", Items.BREAD, "build_hoe"],
	["bake_cake", "Это ложь", "Пшеница, сахар, молоко и яйцо!", Items.CAKE, "build_hoe"],
	["better_pickaxe", "Улучшение", "Сделайте кирку получше", Items.STONE_PICKAXE, "build_pickaxe"],
	["cook_fish", "Вкусная рыба", "Поймайте и приготовьте рыбу", Items.COOKED_FISH, "build_furnace"],
	["on_a_rail", "По рельсам", "Проедьте на вагонетке не меньше километра от начала пути", Blocks.RAIL, "acquire_iron"],
	["build_sword", "Пора в бой!", "Сделайте меч из досок и палок", Items.WOODEN_SWORD, "build_workbench"],
	["kill_enemy", "Охотник на монстров", "Атакуйте и уничтожьте монстра", Items.BONE, "build_sword"],
	["kill_cow", "Коровий переворот", "Добудьте кожу", Items.LEATHER, "build_sword"],
	["fly_pig", "Когда свиньи полетят", "Слетите со скалы верхом на свинье", Items.SADDLE, "kill_cow"],
	["snipe_skeleton", "Снайперская дуэль", "Убейте скелета стрелой с расстояния больше 50 метров", Items.BOW, "kill_enemy"],
	["diamonds", "Алмазы!", "Добудьте алмазы железными инструментами", Items.DIAMOND, "acquire_iron"],
	["portal", "Нужно копнуть глубже", "Постройте портал в Нижний мир", Blocks.OBSIDIAN, "diamonds"],
	["ghast", "Вернуть отправителю", "Убейте гаста его же огненным шаром", Items.GHAST_TEAR, "portal"],
	["blaze_rod", "В огонь", "Отберите у ифрита его стержень", Items.BLAZE_ROD, "portal"],
	["potion", "Домашняя пивоварня", "Сварите зелье", Items.POTION, "blaze_rod"],
	["the_end", "Конец?", "Найдите Край", Items.ENDER_EYE, "blaze_rod"],
	["the_end2", "Конец.", "Победите дракона Края", Blocks.DRAGON_EGG, "the_end"],
	["enchantments", "Зачарователь", "Сделайте стол зачарований из книги, обсидиана и алмазов", Blocks.ENCHANTING_TABLE,
		"diamonds"],
	["overkill", "Перебор", "Нанесите девять сердец урона одним ударом", Items.DIAMOND_SWORD, "enchantments"],
	["bookcase", "Библиотекарь", "Поставьте книжные полки, чтобы усилить стол зачарований", Blocks.BOOKSHELF,
		"enchantments"],
]

## Счётчики: [id, название, вид значения: "count", "distance" (блоки = метры), "time" (секунды), "hp" (половинки сердец)].
static var STATS := [
	["play_time", "Время в игре", "time"],
	["walk", "Пройдено пешком", "distance"],
	["swim", "Проплыто", "distance"],
	["fall", "Пролетел при падении", "distance"],
	["climb", "Пролезено по лестницам", "distance"],
	["fly", "Пролетел (творческий режим)", "distance"],
	["minecart", "Проехал на вагонетке", "distance"],
	["boat", "Проплыл на лодке", "distance"],
	["pig", "Проехал на свинье", "distance"],
	["jumps", "Прыжков", "count"],
	["blocks_mined", "Добыто блоков", "count"],
	["blocks_placed", "Поставлено блоков", "count"],
	["items_crafted", "Создано предметов", "count"],
	["damage_dealt", "Нанесено урона", "hp"],
	["damage_taken", "Получено урона", "hp"],
	["mob_kills", "Убито существ", "count"],
	["deaths", "Смертей", "count"],
	["fish_caught", "Поймано рыбы", "count"],
]

static var unlocked := {}
static var stats := {}
## Только что полученные достижения — интерфейс показывает их по очереди.
static var pending: Array[String] = []
static var _loaded := false
static var _index := {}


static func info(id: String) -> Array:
	if _index.is_empty():
		for a: Array in LIST:
			_index[a[0]] = a
	return _index.get(id, [])


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		var u: Variant = (d as Dictionary).get("achievements", {})
		var s: Variant = (d as Dictionary).get("stats", {})
		if u is Dictionary:
			for k: String in u:
				if not info(k).is_empty():
					unlocked[k] = float(u[k])
		if s is Dictionary:
			for k: String in s:
				stats[k] = float(s[k])


static func save() -> void:
	if not _loaded:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"achievements": unlocked, "stats": stats}))


## Сбросить всё (для тестов); load_again — перечитать файл при следующем обращении.
static func reset(load_again := false) -> void:
	_loaded = not load_again
	unlocked.clear()
	stats.clear()
	pending.clear()


static func has(id: String) -> bool:
	ensure_loaded()
	return unlocked.has(id)


## Можно ли получить: родитель уже получен (как canUnlockAchievement в 1.2).
static func can_unlock(id: String) -> bool:
	var a := info(id)
	if a.is_empty():
		return false
	var parent: String = a[4]
	return parent.is_empty() or has(parent)


## Получить достижение; true — получено только что.
static func unlock(id: String) -> bool:
	ensure_loaded()
	if unlocked.has(id) or not can_unlock(id):
		return false
	unlocked[id] = Time.get_unix_time_from_system()
	pending.append(id)
	return true


static func add_stat(id: String, amount: float = 1.0) -> void:
	ensure_loaded()
	stats[id] = float(stats.get(id, 0.0)) + amount


static func stat(id: String) -> float:
	ensure_loaded()
	return float(stats.get(id, 0.0))


## Значение счётчика для экрана статистики.
static func format_stat(id: String, kind: String) -> String:
	var v := stat(id)
	match kind:
		"distance":
			return "%.2f км" % (v / 1000.0) if v >= 1000.0 else "%d м" % int(v)
		"time":
			var t := int(v)
			@warning_ignore("integer_division")
			var h := t / 3600
			@warning_ignore("integer_division")
			var m := (t / 60) % 60
			return "%d ч %02d мин" % [h, m] if h > 0 else "%d мин %02d с" % [m, t % 60]
		"hp":
			return "%s ♥" % str(snappedf(v / 2.0, 0.5))
	return str(int(v))


# --- Поводы для достижений --------------------------------------------------------

## Подобран предмет (EntityItem.onCollideWithPlayer в 1.2).
static func on_pickup(id: int) -> void:
	match id:
		Blocks.LOG:
			unlock("mine_wood")
		Items.LEATHER:
			unlock("kill_cow")
		Items.DIAMOND:
			unlock("diamonds")
		Items.BLAZE_ROD:
			unlock("blaze_rod")


## Забран результат крафта (SlotCrafting.onPickupFromSlot).
static func on_crafted(id: int, count := 1) -> void:
	add_stat("items_crafted", count)
	match id:
		Blocks.CRAFTING_TABLE:
			unlock("build_workbench")
		Items.WOODEN_PICKAXE:
			unlock("build_pickaxe")
		Blocks.FURNACE:
			unlock("build_furnace")
		Items.WOODEN_HOE:
			unlock("build_hoe")
		Items.BREAD:
			unlock("make_bread")
		Items.CAKE:
			unlock("bake_cake")
		Items.STONE_PICKAXE:
			unlock("better_pickaxe")
		Items.WOODEN_SWORD:
			unlock("build_sword")
		Blocks.ENCHANTING_TABLE:
			unlock("enchantments")
		Blocks.BOOKSHELF:
			unlock("bookcase")


## Забран результат печи (SlotFurnace) или зелье из варочной стойки (SlotBrewingStandPotion).
static func on_taken_output(kind: String, id: int, data: int) -> void:
	if kind == "furnace":
		if id == Items.IRON_INGOT:
			unlock("acquire_iron")
		elif id == Items.COOKED_FISH:
			unlock("cook_fish")
	elif kind == "brewing" and id == Items.POTION and data > 0:
		unlock("potion")


## Игрок убил существо: монстра (IMob), скелета стрелой издалека.
static func on_mob_killed(mob: Node3D, source: String, killer: Node3D) -> void:
	add_stat("mob_kills")
	var type := int(mob.get("type"))
	if MobDefs.category(type) == MobDefs.CAT_MONSTER or type == MobDefs.ENDER_DRAGON:
		unlock("kill_enemy")
	if type == MobDefs.SKELETON and source == "arrow" and killer != null:
		var d := Vector2(killer.position.x - mob.position.x, killer.position.z - mob.position.z)
		if d.length() >= 50.0:
			unlock("snipe_skeleton")
