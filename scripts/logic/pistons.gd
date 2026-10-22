class_name Pistons
extends RefCounted
## Поршни Minecraft 1.2 (обычный и липкий): по сигналу выдвигают головку и толкают до 12 блоков,
## липкий при втягивании тянет блок перед головкой назад. Перемещение мгновенное (без анимации).
##
## Нельзя сдвинуть: обсидиан, коренную породу и прочие неразрушимые блоки, выдвинутые поршни
## и их головки, блоки с данными (сундуки, печи, раздатчики, рассадники, нотные блоки…).
## Блоки, которые от толчка ломаются (факелы, провод, растения, двери, листва, тыквы, паутина…),
## выпадают предметами, жидкости вытесняются. Поршень (meta 0 вниз, 1 вверх, 2 север, 3 юг,
## 4 запад, 5 восток; 8 — выдвинут), головка — то же направление, 8 — липкая.

const MAX_PUSH := 12

## Что происходит с блоком на пути головки.
enum { FREE, BREAK, MOVE, BLOCKED }

var rs: Redstone
var logic: BlockLogic
var world: World
## Идёт перемещение блоков: удаление головки/основания не трогает вторую часть.
var moving := false
## Поршень → тик, когда он сработал: повторное переключение — не раньше следующего тика
## (иначе схема «поршень сам себя выключает» зациклилась бы в одном тике).
var _moved: Dictionary = {}


func _init(p_rs: Redstone) -> void:
	rs = p_rs
	logic = p_rs.logic
	world = p_rs.world


func on_tick() -> void:
	for p: Vector3i in _moved.keys():
		if int(_moved[p]) < logic.tick:
			_moved.erase(p)


static func is_piston(id: int) -> bool:
	return id == Blocks.PISTON or id == Blocks.STICKY_PISTON


## Поведение блока при толчке (как getMobilityFlag и canPushBlock в 1.2).
static func push_kind(id: int, meta: int) -> int:
	if id == Blocks.AIR:
		return FREE
	if id == Blocks.OBSIDIAN or Blocks.hardness(id) < 0.0:
		return BLOCKED
	if is_piston(id):
		return BLOCKED if meta & 8 else MOVE
	if id == Blocks.PISTON_HEAD or id == Blocks.ENCHANTING_TABLE or Blocks.has_block_entity(id):
		return BLOCKED
	if Blocks.is_liquid(id) or Blocks.needs_support[id] == 1 or Blocks.is_replaceable(id):
		return BREAK
	if id in [Blocks.LEAVES, Blocks.PUMPKIN, Blocks.JACK_O_LANTERN, Blocks.MELON, Blocks.DRAGON_EGG, Blocks.BED,
			Blocks.CAKE, Blocks.WEB, Blocks.FIRE, Blocks.VINE]:
		return BREAK
	return MOVE


## Пересчёт поршня в p: выдвинуть, если есть сигнал, втянуть — если нет.
func update(p: Vector3i) -> void:
	var id := world.get_block_v(p)
	if not is_piston(id):
		return
	var meta := world.get_meta_v(p)
	var dir := meta & 7
	if dir > 5:
		return
	var extended := meta & 8 != 0
	if rs.piston_powered(p, dir) == extended:
		return
	if int(_moved.get(p, -1)) == logic.tick:
		logic.schedule(p, 1)
		return
	if extended:
		retract(p, id, dir)
		_moved[p] = logic.tick
	elif extend(p, id, dir):
		_moved[p] = logic.tick


## Выдвигает головку, толкая блоки перед ней. false — путь заблокирован.
func extend(p: Vector3i, id: int, dir: int) -> bool:
	var v := Blocks.piston_vec(dir)
	var line: Array[Vector3i] = []
	var q := p + v
	while true:
		if q.y <= 0 or q.y >= World.CH - 1 or not world.is_loaded(q):
			return false
		var k := push_kind(world.get_block_v(q), world.get_meta_v(q))
		if k == BLOCKED:
			return false
		if k != MOVE:
			break
		if line.size() >= MAX_PUSH:
			return false
		line.append(q)
		q += v
	moving = true
	# Клетка в конце ряда: ломающийся блок выпадает, жидкость вытесняется.
	if world.get_block_v(q) != Blocks.AIR:
		logic.break_naturally(q)
	for k in range(line.size() - 1, -1, -1):
		var from := line[k]
		world.set_block_v(from + v, world.get_block_v(from), world.get_meta_v(from))
	world.set_block_v(p + v, Blocks.PISTON_HEAD, dir | (8 if id == Blocks.STICKY_PISTON else 0))
	world.set_block_v(p, id, dir | 8)
	moving = false
	_push_entities(p + v, q, v)
	return true


## Втягивает головку; липкий поршень тянет за собой блок перед головкой.
func retract(p: Vector3i, id: int, dir: int) -> void:
	var v := Blocks.piston_vec(dir)
	var head := p + v
	moving = true
	world.set_block_v(p, id, dir)
	if world.get_block_v(head) == Blocks.PISTON_HEAD and world.get_meta_v(head) & 7 == dir:
		world.set_block_v(head, Blocks.AIR, 0)
	if id == Blocks.STICKY_PISTON and world.get_block_v(head) == Blocks.AIR:
		var q := head + v
		var b := world.get_block_v(q)
		var m := world.get_meta_v(q)
		if q.y > 0 and q.y < World.CH - 1 and push_kind(b, m) == MOVE:
			world.set_block_v(head, b, m)
			world.set_block_v(q, Blocks.AIR, 0)
	moving = false


## Головку сломали (игрок, взрыв): выдвинутый поршень за ней выпадает предметом.
func head_removed(p: Vector3i, meta: int) -> void:
	var dir := meta & 7
	if dir > 5:
		return
	var base := p - Blocks.piston_vec(dir)
	var b := world.get_block_v(base)
	var bm := world.get_meta_v(base)
	if is_piston(b) and bm & 8 and bm & 7 == dir:
		logic.break_naturally(base)


## Сломали выдвинутый поршень: его головка исчезает.
func base_removed(p: Vector3i, meta: int) -> void:
	var dir := meta & 7
	if dir > 5:
		return
	var head := p + Blocks.piston_vec(dir)
	if world.get_block_v(head) == Blocks.PISTON_HEAD and world.get_meta_v(head) & 7 == dir:
		moving = true
		world.set_block_v(head, Blocks.AIR, 0)
		moving = false


## Существа в клетках, занятых головкой и сдвинутыми блоками (от first до last), сдвигаются на v.
func _push_entities(first: Vector3i, last: Vector3i, v: Vector3i) -> void:
	var game := logic.game
	if game == null:
		return
	var lo := Vector3(Vector3i(mini(first.x, last.x), mini(first.y, last.y), mini(first.z, last.z)))
	var hi := Vector3(Vector3i(maxi(first.x, last.x), maxi(first.y, last.y), maxi(first.z, last.z))) + Vector3.ONE
	var zone := AABB(lo, hi - lo).grow(-0.001)
	var pl: Variant = game.get("player")
	if pl is Node3D and is_instance_valid(pl) and (pl as Node3D).has_method("body_box"):
		var pn := pl as Node3D
		var box: AABB = pn.call("body_box")
		if zone.intersects(box):
			pn.position += Vector3(v)
	var ents: Variant = game.get("entities")
	if ents is Node and is_instance_valid(ents):
		for n in (ents as Node).get_children():
			if n is Node3D and n.has_method("update_entity") and zone.has_point((n as Node3D).position + Vector3(0, 0.05, 0)):
				(n as Node3D).position += Vector3(v)
