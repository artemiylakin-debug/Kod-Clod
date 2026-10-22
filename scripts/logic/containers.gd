class_name Containers
extends RefCounted
## Блоки-контейнеры: содержимое хранится в данных блока (World.get_block_entity) как массив
## [id, количество, данные]. Здесь же работа печей и варочных стоек (каждый игровой тик).

const SIZES := {"chest": 27, "dispenser": 9, "furnace": 3, "brewing": 4}
const COOK_TICKS := 200
const BREW_TICKS := 400

var logic: BlockLogic
## Работающие печи и стойки: позиция → true.
var active: Dictionary = {}


func _init(p_logic: BlockLogic) -> void:
	logic = p_logic


static func kind_of(id: int) -> String:
	match id:
		Blocks.CHEST, Blocks.LOCKED_CHEST:
			return "chest"
		Blocks.DISPENSER:
			return "dispenser"
		Blocks.FURNACE, Blocks.LIT_FURNACE:
			return "furnace"
		Blocks.BREWING_STAND:
			return "brewing"
	return ""


## Содержимое контейнера как Inventory (копия; изменения сохраняются через store()).
static func load_items(be: Dictionary, size: int) -> Inventory:
	var inv := Inventory.new(size)
	var items: Variant = be.get("items", [])
	if items is Array:
		inv.from_data(items)
	return inv


static func store(be: Dictionary, inv: Inventory) -> void:
	be["items"] = inv.to_data()


func mark_active(p: Vector3i) -> void:
	active[p] = true


func tick() -> void:
	if active.is_empty():
		return
	var world := logic.world
	for p: Vector3i in active.keys():
		var id := world.get_block_v(p)
		var keep := false
		match id:
			Blocks.FURNACE, Blocks.LIT_FURNACE:
				keep = _furnace_tick(p, id)
			Blocks.BREWING_STAND:
				keep = _brewing_tick(p)
		if not keep:
			active.erase(p)


# --- Печь ------------------------------------------------------------------

func _furnace_tick(p: Vector3i, id: int) -> bool:
	var world := logic.world
	if not world.is_loaded(p):
		return false
	var be := world.get_block_entity(p)
	var inv := load_items(be, 3)
	var burn := int(be.get("burn", 0))
	var cook := int(be.get("cook", 0))
	var result := Recipes.smelt_result(inv.ids[0], inv.datas[0]) if inv.counts[0] > 0 else []
	var can_cook := not result.is_empty() and (inv.counts[2] == 0 or (Inventory.stacks_with(inv.ids[2], inv.datas[2], int(result[0]), int(result[2])) \
		and inv.counts[2] + int(result[1]) <= Items.max_stack(int(result[0]))))
	var changed := false
	if burn > 0:
		burn -= 1
	if burn <= 0 and can_cook and inv.counts[1] > 0:
		var fuel := Items.fuel_ticks(inv.ids[1])
		if fuel > 0:
			burn = fuel
			be["burn_max"] = fuel
			if inv.ids[1] == Items.LAVA_BUCKET:
				inv.set_slot(1, Items.BUCKET, 1)
			else:
				inv.consume_slot(1, 1)
			changed = true
	if burn > 0 and can_cook:
		cook += 1
		if cook >= COOK_TICKS:
			cook = 0
			inv.consume_slot(0, 1)
			if inv.counts[2] == 0:
				inv.set_slot(2, int(result[0]), int(result[1]), int(result[2]))
			else:
				inv.counts[2] += int(result[1])
			be["xp"] = float(be.get("xp", 0.0)) + float(result[3])
			changed = true
	else:
		cook = maxi(cook - 2, 0) if burn <= 0 else 0
	be["burn"] = burn
	be["cook"] = cook
	if changed:
		store(be, inv)
	world.mark_dirty(p)
	var lit := burn > 0
	var want := Blocks.LIT_FURNACE if lit else Blocks.FURNACE
	if want != id:
		world.set_block(p.x, p.y, p.z, want, world.get_meta_v(p), false)
		world.set_block_entity(p, be)
	return lit or (can_cook and inv.counts[1] > 0)


## Забрать опыт, накопленный печью (при извлечении результата).
static func take_furnace_xp(be: Dictionary) -> int:
	var xp := float(be.get("xp", 0.0))
	be["xp"] = 0.0
	var whole := int(xp)
	if randf() < xp - whole:
		whole += 1
	return whole


# --- Варочная стойка -------------------------------------------------------

func _brewing_tick(p: Vector3i) -> bool:
	var world := logic.world
	if not world.is_loaded(p):
		return false
	var be := world.get_block_entity(p)
	var inv := load_items(be, 4)
	if inv.counts[3] <= 0 or not _can_brew(inv):
		be["brew"] = 0
		return false
	var t := int(be.get("brew", 0))
	if t <= 0:
		t = BREW_TICKS
	t -= 1
	if t <= 0:
		var ing := inv.ids[3]
		for i in 3:
			if inv.counts[i] > 0 and inv.ids[i] == Items.POTION:
				var out := Potions.brew(inv.datas[i], ing)
				if out >= 0:
					inv.datas[i] = out
		inv.consume_slot(3, 1)
		store(be, inv)
		t = 0
	be["brew"] = t
	world.mark_dirty(p)
	return t > 0


static func _can_brew(inv: Inventory) -> bool:
	for i in 3:
		if inv.counts[i] > 0 and inv.ids[i] == Items.POTION and Potions.brew(inv.datas[i], inv.ids[3]) >= 0:
			return true
	return false


# --- Раздатчик -------------------------------------------------------------

## Выбрасывает случайный предмет из раздатчика (по сигналу редстоуна).
func dispense(p: Vector3i) -> void:
	var world := logic.world
	var be := world.get_block_entity(p)
	var inv := load_items(be, 9)
	var filled: Array[int] = []
	for i in 9:
		if inv.counts[i] > 0:
			filled.append(i)
	if filled.is_empty():
		return
	var i: int = filled[logic.rng.randi_range(0, filled.size() - 1)]
	var dir: Vector3i = Blocks.DIR_VEC[world.get_meta_v(p) & 3]
	var front := Vector3(p) + Vector3(0.5, 0.5, 0.5) + Vector3(dir) * 0.7
	var id := inv.ids[i]
	var data := inv.datas[i]
	var game := logic.game
	var entities: EntityManager = game.get("entities") if game != null else null
	var vel := Vector3(dir) * 12.0 + Vector3(0, 2.0, 0)
	match id:
		Items.ARROW:
			if entities != null:
				entities.spawn_projectile("arrow", front, vel * 1.5, null, 3.0)
		Items.SNOWBALL, Items.EGG:
			if entities != null:
				entities.spawn_projectile("snowball" if id == Items.SNOWBALL else "egg", front, vel, null)
		Items.FIRE_CHARGE:
			if entities != null:
				entities.spawn_projectile("small_fireball", front, Vector3(dir) * 15.0, null)
		Items.POTION:
			if entities != null and Potions.is_splash(data):
				entities.spawn_projectile("potion", front, vel, null, 0.0, data)
			elif entities != null:
				entities.spawn_drop(id, 1, data, front, Vector3(dir) * 3.0)
		Items.SPAWN_EGG:
			if entities != null:
				entities.spawn_mob(data, front)
		_:
			if entities != null:
				entities.spawn_drop(id, 1, data, front, Vector3(dir) * 4.0)
	inv.consume_slot(i, 1)
	store(be, inv)
	world.mark_dirty(p)
