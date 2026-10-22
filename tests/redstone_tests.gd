extends SceneTree
## Тесты красной пыли, механизмов и поршней (без рендеринга).
## Запуск: godot --headless --path . -s res://tests/redstone_tests.gd

var _failed := 0
var _passed := 0
var w: World
var g: FakeGame
var logic: BlockLogic


## Заглушка игровой сцены (как в unit_tests.gd) + ноты и игрок-«манекен».
class FakeGame extends Node:
	var entities: EntityManager
	var player: Node3D
	var notes: Array[int] = []

	func spawn_drop(id: int, count: int, data: int, pos: Vector3, vel := Vector3.INF, delay := 0.0) -> ItemDrop:
		return entities.spawn_drop(id, count, data, pos, vel, delay)

	func explosion_damage(center: Vector3, power: float, source: Node) -> void:
		entities.explosion_damage(center, power, source)

	func sky_light_level() -> int:
		return 15

	func play_note(_p: Vector3i, note: int) -> void:
		notes.append(note)


class FakePlayer extends Node3D:
	func body_box() -> AABB:
		return BodyPhysics.body_box(position, 0.3, 1.8)


func _initialize() -> void:
	_run()


func _run() -> void:
	TextureFactory.ensure_initialized()
	_setup()
	_test_wire_line()
	_test_lamp()
	_test_wire_direction()
	_test_torch()
	_test_repeater()
	_test_steps()
	_test_button_and_plates()
	_test_doors_and_hatches()
	_test_tnt_dispenser_note()
	_test_pistons()
	_test_burnout()
	_test_rails()
	_test_breaking()
	_test_mesher()
	_test_performance()
	g.queue_free()
	w.queue_free()
	await process_frame
	print("\n==== Итог: %d пройдено, %d провалено ====" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("  [OK]   ", what)
	else:
		_failed += 1
		print("  [FAIL] ", what)


# --- Мир ---------------------------------------------------------------------

## Плоский мир: камень до y=10 (поверхность — y=11), чанки −2..2.
func _setup() -> void:
	w = World.new()
	w.setup(1, "", 2)
	root.add_child(w)
	for cz in range(-2, 3):
		for cx in range(-2, 3):
			var ch := Chunk.new()
			ch.key = Vector2i(cx, cz)
			ch.blocks.resize(WorldGen.VOLUME)
			ch.meta.resize(WorldGen.VOLUME)
			for y in 11:
				for i in WorldGen.LAYER:
					ch.blocks[y * WorldGen.LAYER + i] = Blocks.STONE
			ch.biomes.resize(WorldGen.LAYER)
			ch.biomes.fill(Biomes.PLAINS)
			ch.top_y = 10
			ch.light = ChunkLight.compute(ch.blocks)
			ch.heightmap = Chunk.compute_heightmap(ch.blocks, ch.top_y)
			ch.applied_gen = 1
			w.chunks[ch.key] = ch
	g = FakeGame.new()
	root.add_child(g)
	logic = BlockLogic.new()
	logic.name = "Logic"
	g.add_child(logic)
	logic.setup(w, g)
	logic.set_process(false)
	var ent := EntityManager.new()
	g.add_child(ent)
	g.entities = ent
	ent.setup(w, logic, null, g)


func put(p: Vector3i, id: int, meta := 0) -> void:
	w.set_block(p.x, p.y, p.z, id, meta)


func id_at(p: Vector3i) -> int:
	return w.get_block_v(p)


func meta_at(p: Vector3i) -> int:
	return w.get_meta_v(p)


func ticks(n: int) -> void:
	for i in n:
		logic.game_tick()


## Очищает область над землёй (y 11–16) и возвращает её угол на поверхности.
func area(x: int, z: int, sx := 20, sz := 6) -> Vector3i:
	for y in range(11, 17):
		for zz in range(z - 1, z + sz + 1):
			for xx in range(x - 1, x + sx + 1):
				if w.get_block(xx, y, zz) != Blocks.AIR:
					w.set_block(xx, y, zz, Blocks.AIR, 0, false)
	for zz in range(z - 1, z + sz + 1):
		for xx in range(x - 1, x + sx + 1):
			w.set_block(xx, 10, zz, Blocks.STONE, 0, false)
	ticks(30)
	return Vector3i(x, 11, z)


func lever_on(p: Vector3i, on: bool) -> void:
	put(p, Blocks.LEVER, (meta_at(p) & 7) | (8 if on else 0))


func count_children(type_check: Callable) -> int:
	var n := 0
	for c in g.entities.get_children():
		if not c.is_queued_for_deletion() and type_check.call(c):
			n += 1
	return n


func clear_entities() -> void:
	for c in g.entities.get_children():
		if c.has_method("update_entity"):
			g.entities.remove_child(c)
			c.free()


# --- Провода -------------------------------------------------------------------

func _test_wire_line() -> void:
	print("Провода")
	var o := area(-30, -30)
	put(o, Blocks.LEVER, 0)
	for i in range(1, 18):
		put(o + Vector3i(i, 0, 0), Blocks.REDSTONE_WIRE)
	check(meta_at(o + Vector3i(1, 0, 0)) == 0, "без сигнала провод не заряжен")
	lever_on(o, true)
	var levels: Array[int] = []
	for i in range(1, 18):
		levels.append(meta_at(o + Vector3i(i, 0, 0)))
	check(levels[0] == 15 and levels[1] == 14 and levels[14] == 1 and levels[15] == 0 and levels[16] == 0,
		"рычаг: заряд 15 у рычага и −1 на каждый блок, 15 блоков (%s)" % str(levels))
	lever_on(o, false)
	var all_zero := true
	for i in range(1, 18):
		all_zero = all_zero and meta_at(o + Vector3i(i, 0, 0)) == 0
	check(all_zero, "рычаг выключен — провода разряжены сразу")
	# Ветвление: два источника, заряд — по ближайшему.
	lever_on(o, true)
	put(o + Vector3i(18, 0, 0), Blocks.REDSTONE_TORCH, 0)
	check(meta_at(o + Vector3i(17, 0, 0)) == 15 and meta_at(o + Vector3i(9, 0, 0)) == 7 and meta_at(o + Vector3i(10, 0, 0)) == 8,
		"два источника: заряд по ближайшему (%d, %d)" % [meta_at(o + Vector3i(9, 0, 0)), meta_at(o + Vector3i(10, 0, 0))])
	# Разрыв цепи.
	put(o + Vector3i(17, 0, 0), Blocks.AIR)
	put(o + Vector3i(8, 0, 0), Blocks.AIR)
	check(meta_at(o + Vector3i(9, 0, 0)) == 0 and meta_at(o + Vector3i(7, 0, 0)) == 9, "разрыв провода: дальняя часть разряжена")
	# Провод ломается без опоры и выпадает.
	put(o + Vector3i(3, -1, 0), Blocks.AIR)
	check(id_at(o + Vector3i(3, 0, 0)) == Blocks.AIR and meta_at(o + Vector3i(4, 0, 0)) == 0, "провод без опоры выпадает, сеть разрывается")


func _test_lamp() -> void:
	print("Лампы")
	var o := area(-5, -30)
	put(o, Blocks.LEVER, 0)
	for i in range(1, 4):
		put(o + Vector3i(i, 0, 0), Blocks.REDSTONE_WIRE)
	put(o + Vector3i(4, 0, 0), Blocks.REDSTONE_LAMP)
	lever_on(o, true)
	check(id_at(o + Vector3i(4, 0, 0)) == Blocks.LIT_REDSTONE_LAMP, "лампа включается сразу (провод направлен в неё)")
	check(w.get_block_light(o + Vector3i(5, 0, 0)) == 14, "включённая лампа светит (15)")
	lever_on(o, false)
	ticks(3)
	var still := id_at(o + Vector3i(4, 0, 0)) == Blocks.LIT_REDSTONE_LAMP
	ticks(1)
	check(still and id_at(o + Vector3i(4, 0, 0)) == Blocks.REDSTONE_LAMP, "лампа гаснет через 4 тика (1.2)")
	# Короткий импульс: включение до выключения — лампа не мигает.
	lever_on(o, true)
	ticks(2)
	lever_on(o, false)
	ticks(2)
	lever_on(o, true)
	ticks(4)
	check(id_at(o + Vector3i(4, 0, 0)) == Blocks.LIT_REDSTONE_LAMP, "повторное включение до задержки — лампа горит")
	lever_on(o, false)
	ticks(5)
	# Лампа рядом с рычагом и под рычагом.
	put(o + Vector3i(0, 0, 2), Blocks.REDSTONE_LAMP)
	put(o + Vector3i(0, 1, 2), Blocks.LEVER, 0)
	lever_on(o + Vector3i(0, 1, 2), true)
	check(id_at(o + Vector3i(0, 0, 2)) == Blocks.LIT_REDSTONE_LAMP, "рычаг на лампе включает её")
	put(o + Vector3i(1, 0, 2), Blocks.REDSTONE_LAMP)
	check(id_at(o + Vector3i(1, 0, 2)) == Blocks.LIT_REDSTONE_LAMP, "сильно запитанный блок питает соседнюю лампу")


func _test_wire_direction() -> void:
	print("Направление провода и проводимость")
	var o := area(20, -30)
	put(o, Blocks.LEVER, 0)
	for i in range(1, 6):
		put(o + Vector3i(i, 0, 0), Blocks.REDSTONE_WIRE)
	put(o + Vector3i(2, 0, 1), Blocks.REDSTONE_LAMP)
	put(o + Vector3i(6, 0, 0), Blocks.STONE)
	put(o + Vector3i(7, 0, 0), Blocks.REDSTONE_WIRE)
	put(o + Vector3i(6, 0, 1), Blocks.REDSTONE_LAMP)
	put(o + Vector3i(6, 1, 0), Blocks.REDSTONE_TORCH, 0)
	lever_on(o, true)
	ticks(4)
	check(id_at(o + Vector3i(2, 0, 1)) == Blocks.REDSTONE_LAMP, "провод, идущий мимо лампы, её не включает")
	check(id_at(o + Vector3i(6, 0, 1)) == Blocks.LIT_REDSTONE_LAMP, "провод питает блок, в который направлен, а тот — лампу")
	check(meta_at(o + Vector3i(7, 0, 0)) == 0, "блок, запитанный проводом, не передаёт заряд другому проводу")
	check(id_at(o + Vector3i(6, 1, 0)) == Blocks.REDSTONE_TORCH_OFF, "факел на блоке, запитанном проводом, гаснет")
	# Провод-«точка» питает все стороны.
	var d := o + Vector3i(0, 0, 4)
	put(d, Blocks.STONE_PLATE, 1)
	put(d + Vector3i(1, 0, 0), Blocks.STONE)
	put(d + Vector3i(1, 1, 0), Blocks.LEVER, 8)
	put(d + Vector3i(3, 0, 0), Blocks.REDSTONE_WIRE)
	put(d + Vector3i(2, 0, 0), Blocks.STONE)
	put(d + Vector3i(2, 1, 0), Blocks.LEVER, 8)
	put(d + Vector3i(3, 0, 1), Blocks.REDSTONE_LAMP)
	check(meta_at(d + Vector3i(3, 0, 0)) == 15, "провод у сильно запитанного блока заряжен")
	check(id_at(d + Vector3i(3, 0, 1)) == Blocks.LIT_REDSTONE_LAMP, "провод без соединений питает соседей со всех сторон")


func _test_torch() -> void:
	print("Факелы")
	var o := area(-30, -22)
	put(o + Vector3i(2, 0, 0), Blocks.STONE)
	put(o + Vector3i(3, 0, 0), Blocks.REDSTONE_TORCH, 1)
	put(o + Vector3i(4, 0, 0), Blocks.REDSTONE_WIRE)
	put(o + Vector3i(5, 0, 0), Blocks.REDSTONE_WIRE)
	check(meta_at(o + Vector3i(4, 0, 0)) == 15 and meta_at(o + Vector3i(5, 0, 0)) == 14, "горящий факел питает провод рядом")
	put(o + Vector3i(2, 1, 0), Blocks.LEVER, 0)
	lever_on(o + Vector3i(2, 1, 0), true)
	ticks(1)
	var still_on := id_at(o + Vector3i(3, 0, 0)) == Blocks.REDSTONE_TORCH
	ticks(1)
	check(still_on and id_at(o + Vector3i(3, 0, 0)) == Blocks.REDSTONE_TORCH_OFF, "факел гаснет через 2 тика, когда его блок запитан")
	check(meta_at(o + Vector3i(4, 0, 0)) == 0, "погасший факел не питает провод")
	lever_on(o + Vector3i(2, 1, 0), false)
	ticks(2)
	check(id_at(o + Vector3i(3, 0, 0)) == Blocks.REDSTONE_TORCH and meta_at(o + Vector3i(4, 0, 0)) == 15, "сигнал пропал — факел снова горит")
	check(not logic.redstone.is_powered(o + Vector3i(2, 0, 0)), "факел не питает блок, на котором висит")
	# Факел питает блок над собой (сильно): лампа рядом с этим блоком горит.
	put(o + Vector3i(8, 0, 0), Blocks.REDSTONE_TORCH, 0)
	put(o + Vector3i(8, 1, 0), Blocks.STONE)
	put(o + Vector3i(9, 1, 0), Blocks.REDSTONE_LAMP)
	check(id_at(o + Vector3i(9, 1, 0)) == Blocks.LIT_REDSTONE_LAMP, "факел запитывает блок над собой, тот — лампу")
	# Факел, поставленный на запитанный блок, гаснет.
	put(o + Vector3i(12, 0, 0), Blocks.STONE)
	put(o + Vector3i(12, 1, 0), Blocks.LEVER, 8)
	put(o + Vector3i(13, 0, 0), Blocks.REDSTONE_TORCH, 1)
	ticks(2)
	check(id_at(o + Vector3i(13, 0, 0)) == Blocks.REDSTONE_TORCH_OFF, "факел на запитанном блоке гаснет после установки")


func _test_repeater() -> void:
	print("Повторители")
	var o := area(-5, -22)
	put(o, Blocks.LEVER, 0)
	put(o + Vector3i(1, 0, 0), Blocks.REDSTONE_WIRE)
	put(o + Vector3i(2, 0, 0), Blocks.REPEATER_OFF, 3)
	put(o + Vector3i(3, 0, 0), Blocks.REDSTONE_WIRE)
	put(o + Vector3i(4, 0, 0), Blocks.REDSTONE_WIRE)
	lever_on(o, true)
	ticks(1)
	var early := id_at(o + Vector3i(2, 0, 0)) == Blocks.REPEATER_OFF and meta_at(o + Vector3i(3, 0, 0)) == 0
	ticks(1)
	check(early and id_at(o + Vector3i(2, 0, 0)) == Blocks.REPEATER_ON and meta_at(o + Vector3i(3, 0, 0)) == 15,
		"повторитель (1): включается через 2 тика и выдаёт 15")
	lever_on(o, false)
	ticks(2)
	check(id_at(o + Vector3i(2, 0, 0)) == Blocks.REPEATER_OFF and meta_at(o + Vector3i(4, 0, 0)) == 0, "повторитель выключается с той же задержкой")
	put(o + Vector3i(2, 0, 0), Blocks.REPEATER_OFF, 3 | (3 << 2))
	lever_on(o, true)
	ticks(7)
	var not_yet := id_at(o + Vector3i(2, 0, 0)) == Blocks.REPEATER_OFF
	ticks(1)
	check(not_yet and id_at(o + Vector3i(2, 0, 0)) == Blocks.REPEATER_ON, "повторитель (4): задержка 8 тиков")
	lever_on(o, false)
	ticks(10)
	# Короткий импульс удлиняется до задержки.
	lever_on(o, true)
	ticks(1)
	lever_on(o, false)
	ticks(7)
	var on_late := id_at(o + Vector3i(2, 0, 0)) == Blocks.REPEATER_ON
	ticks(8)
	check(on_late and id_at(o + Vector3i(2, 0, 0)) == Blocks.REPEATER_OFF, "короткий импульс проходит через повторитель и не залипает")
	# Однонаправленность: повторитель, смотрящий на запад, не пропускает сигнал на восток.
	put(o + Vector3i(2, 0, 0), Blocks.REPEATER_OFF, 1)
	lever_on(o, true)
	ticks(4)
	check(id_at(o + Vector3i(2, 0, 0)) == Blocks.REPEATER_OFF and meta_at(o + Vector3i(3, 0, 0)) == 0, "повторитель не пропускает сигнал в обратную сторону")
	lever_on(o, false)
	ticks(4)
	# Усиление: 15 блоков провода → повторитель → снова 15.
	var b := o + Vector3i(0, 0, 3)
	put(b, Blocks.LEVER, 8)
	for i in range(1, 15):
		put(b + Vector3i(i, 0, 0), Blocks.REDSTONE_WIRE)
	put(b + Vector3i(15, 0, 0), Blocks.REPEATER_OFF, 3)
	put(b + Vector3i(16, 0, 0), Blocks.REDSTONE_WIRE)
	put(b + Vector3i(17, 0, 0), Blocks.STONE)
	put(b + Vector3i(17, 1, 0), Blocks.REDSTONE_LAMP)
	ticks(3)
	check(meta_at(b + Vector3i(14, 0, 0)) == 2 and meta_at(b + Vector3i(16, 0, 0)) == 15, "повторитель восстанавливает заряд до 15")
	# Повторитель сильно запитывает блок перед собой.
	put(b + Vector3i(16, 0, 0), Blocks.STONE)
	check(id_at(b + Vector3i(16, 1, 0)) == Blocks.AIR, "")
	put(b + Vector3i(16, 1, 0), Blocks.REDSTONE_LAMP)
	check(id_at(b + Vector3i(16, 1, 0)) == Blocks.LIT_REDSTONE_LAMP, "повторитель запитывает блок перед собой, тот — лампу сверху")
	# Повторитель на входе читает провод с любым зарядом и любым направлением.
	var c := o + Vector3i(0, 0, 5)
	put(c + Vector3i(0, 0, -1), Blocks.LEVER, 8)
	put(c, Blocks.REDSTONE_WIRE)
	put(c + Vector3i(1, 0, 0), Blocks.REPEATER_OFF, 3)
	put(c + Vector3i(2, 0, 0), Blocks.REDSTONE_LAMP)
	ticks(3)
	check(id_at(c + Vector3i(2, 0, 0)) == Blocks.LIT_REDSTONE_LAMP, "повторитель берёт сигнал с провода, идущего поперёк")


func _test_steps() -> void:
	print("Провод по ступенькам")
	var o := area(20, -22)
	put(o, Blocks.LEVER, 8)
	put(o + Vector3i(1, 0, 0), Blocks.REDSTONE_WIRE)
	put(o + Vector3i(2, 0, 0), Blocks.STONE)
	put(o + Vector3i(2, 1, 0), Blocks.REDSTONE_WIRE)
	put(o + Vector3i(3, 1, 0), Blocks.STONE)
	put(o + Vector3i(3, 2, 0), Blocks.REDSTONE_WIRE)
	check(meta_at(o + Vector3i(2, 1, 0)) == 14 and meta_at(o + Vector3i(3, 2, 0)) == 13, "заряд поднимается по ступенькам")
	put(o + Vector3i(1, 1, 0), Blocks.STONE)
	check(meta_at(o + Vector3i(2, 1, 0)) == 0, "непрозрачный блок над проводом перекрывает подъём")
	put(o + Vector3i(1, 1, 0), Blocks.AIR)
	check(meta_at(o + Vector3i(2, 1, 0)) == 14, "блок убран — подъём снова работает")
	# Спуск: рычаг наверху.
	var d := o + Vector3i(0, 0, 3)
	put(d + Vector3i(1, 0, 0), Blocks.STONE)
	put(d + Vector3i(2, 0, 0), Blocks.STONE)
	put(d + Vector3i(2, 1, 0), Blocks.LEVER, 8)
	put(d + Vector3i(1, 1, 0), Blocks.REDSTONE_WIRE)
	put(d, Blocks.REDSTONE_WIRE)
	put(d + Vector3i(-1, 0, 0), Blocks.REDSTONE_WIRE)
	check(meta_at(d + Vector3i(1, 1, 0)) == 15 and meta_at(d) == 14 and meta_at(d + Vector3i(-1, 0, 0)) == 13, "заряд спускается по ступенькам")
	# Прозрачная ступенька (стекло): вверх проходит, вниз — нет.
	var t := o + Vector3i(8, 0, 0)
	put(t, Blocks.LEVER, 8)
	put(t + Vector3i(1, 0, 0), Blocks.REDSTONE_WIRE)
	put(t + Vector3i(2, 0, 0), Blocks.GLASS)
	put(t + Vector3i(2, 1, 0), Blocks.REDSTONE_WIRE)
	check(meta_at(t + Vector3i(2, 1, 0)) == 14, "по стеклянной ступеньке сигнал поднимается")
	var t2 := o + Vector3i(8, 0, 3)
	put(t2 + Vector3i(2, 0, 0), Blocks.GLASS)
	put(t2 + Vector3i(3, 0, 0), Blocks.STONE)
	put(t2 + Vector3i(3, 1, 0), Blocks.LEVER, 8)
	put(t2 + Vector3i(2, 1, 0), Blocks.REDSTONE_WIRE)
	put(t2 + Vector3i(1, 0, 0), Blocks.REDSTONE_WIRE)
	check(meta_at(t2 + Vector3i(2, 1, 0)) == 15 and meta_at(t2 + Vector3i(1, 0, 0)) == 0, "со стеклянной ступеньки сигнал не спускается")


func _test_button_and_plates() -> void:
	print("Кнопки и нажимные плиты")
	var o := area(-30, -14)
	put(o, Blocks.STONE)
	put(o + Vector3i(1, 0, 0), Blocks.STONE_BUTTON, 1)
	put(o + Vector3i(-1, 0, 0), Blocks.REDSTONE_LAMP)
	put(o + Vector3i(1, 0, 0), Blocks.STONE_BUTTON, 1 | 8)
	check(id_at(o + Vector3i(-1, 0, 0)) == Blocks.LIT_REDSTONE_LAMP, "кнопка запитывает блок, на котором висит")
	ticks(19)
	var held := meta_at(o + Vector3i(1, 0, 0)) & 8 != 0
	ticks(1)
	check(held and meta_at(o + Vector3i(1, 0, 0)) & 8 == 0, "кнопка отпускается через 20 тиков (1 с)")
	ticks(4)
	check(id_at(o + Vector3i(-1, 0, 0)) == Blocks.REDSTONE_LAMP, "после кнопки лампа гаснет")
	# Деревянная плита: любой предмет.
	var wp := o + Vector3i(5, 0, 0)
	put(wp, Blocks.WOODEN_PLATE)
	put(wp + Vector3i(1, 0, 0), Blocks.REDSTONE_LAMP)
	var sp := o + Vector3i(5, 0, 3)
	put(sp, Blocks.STONE_PLATE)
	put(sp + Vector3i(1, 0, 0), Blocks.REDSTONE_LAMP)
	ticks(2)
	check(meta_at(wp) == 0 and id_at(wp + Vector3i(1, 0, 0)) == Blocks.REDSTONE_LAMP, "пустая плита не нажата")
	var drop := g.entities.spawn_drop(Blocks.DIRT, 1, 0, Vector3(wp) + Vector3(0.5, 0.0, 0.5), Vector3.ZERO)
	var drop2 := g.entities.spawn_drop(Blocks.COBBLESTONE, 1, 0, Vector3(sp) + Vector3(0.5, 0.0, 0.5), Vector3.ZERO)
	ticks(1)
	check(meta_at(wp) == 1 and id_at(wp + Vector3i(1, 0, 0)) == Blocks.LIT_REDSTONE_LAMP, "предмет на деревянной плите нажимает её")
	check(meta_at(sp) == 0, "предмет не нажимает каменную плиту")
	drop.position += Vector3(0, 0, 3.0)
	drop2.queue_free()
	ticks(19)
	var still := meta_at(wp) == 1
	ticks(2)
	check(still and meta_at(wp) == 0, "плита отпускается через секунду после того, как предмет ушёл")
	var pl := FakePlayer.new()
	root.add_child(pl)
	g.player = pl
	pl.position = Vector3(sp) + Vector3(0.9, 0.001, 0.5)
	ticks(1)
	check(meta_at(sp) == 1 and id_at(sp + Vector3i(1, 0, 0)) == Blocks.LIT_REDSTONE_LAMP, "игрок, задевший каменную плиту, нажимает её")
	pl.position = Vector3(sp) + Vector3(-3.0, 0.001, 0.5)
	ticks(25)
	check(meta_at(sp) == 0 and id_at(sp + Vector3i(1, 0, 0)) == Blocks.REDSTONE_LAMP, "игрок ушёл — плита отпущена, лампа погасла")
	g.player = null
	pl.queue_free()
	drop.queue_free()
	# Плита запитывает блок под собой: факел на нём гаснет.
	var under := o + Vector3i(10, 0, 0)
	put(under + Vector3i(0, -1, 0), Blocks.STONE)
	put(under + Vector3i(1, -1, 0), Blocks.AIR)
	put(under + Vector3i(1, -1, 0), Blocks.REDSTONE_TORCH, 1)
	put(under, Blocks.STONE_PLATE, 1)
	ticks(2)
	check(id_at(under + Vector3i(1, -1, 0)) == Blocks.REDSTONE_TORCH_OFF, "плита запитывает блок под собой")
	ticks(25)
	check(meta_at(under) == 0 and id_at(under + Vector3i(1, -1, 0)) == Blocks.REDSTONE_TORCH, "без существ плита отпускается")


func _test_doors_and_hatches() -> void:
	print("Двери, люки, калитки")
	var o := area(-5, -14)
	put(o, Blocks.WOODEN_DOOR, 0)
	put(o + Vector3i(0, 1, 0), Blocks.WOODEN_DOOR, 8)
	put(o + Vector3i(1, 0, 0), Blocks.LEVER, 0)
	lever_on(o + Vector3i(1, 0, 0), true)
	check(meta_at(o) & 4 != 0 and meta_at(o + Vector3i(0, 1, 0)) == (meta_at(o) | 8), "рычаг открывает деревянную дверь (обе половины)")
	lever_on(o + Vector3i(1, 0, 0), false)
	check(meta_at(o) & 4 == 0 and meta_at(o + Vector3i(0, 1, 0)) & 4 == 0, "без сигнала дверь закрывается")
	# Открытая рукой дверь не закрывается от постороннего изменения рядом.
	put(o, Blocks.WOODEN_DOOR, 4)
	put(o + Vector3i(0, 1, 0), Blocks.WOODEN_DOOR, 12)
	put(o + Vector3i(-1, 0, 0), Blocks.STONE)
	put(o + Vector3i(-1, 0, 1), Blocks.REDSTONE_WIRE)
	check(meta_at(o) & 4 != 0, "открытая рукой дверь остаётся открытой")
	# Железная дверь: сигнал на верхнюю половину тоже открывает.
	var d := o + Vector3i(4, 0, 0)
	put(d, Blocks.IRON_DOOR, 1)
	put(d + Vector3i(0, 1, 0), Blocks.IRON_DOOR, 9)
	put(d + Vector3i(1, 1, 0), Blocks.STONE)
	put(d + Vector3i(1, 2, 0), Blocks.LEVER, 0)
	lever_on(d + Vector3i(1, 2, 0), true)
	check(meta_at(d) & 4 != 0, "железная дверь открывается сигналом на верхнюю половину")
	lever_on(d + Vector3i(1, 2, 0), false)
	check(meta_at(d) & 4 == 0, "железная дверь закрывается")
	# Люк и калитка.
	var t := o + Vector3i(8, 0, 0)
	put(t, Blocks.TRAPDOOR, 0)
	put(t + Vector3i(1, 0, 0), Blocks.LEVER, 0)
	put(t + Vector3i(4, 0, 0), Blocks.FENCE_GATE, 0)
	put(t + Vector3i(3, 0, 0), Blocks.LEVER, 0)
	lever_on(t + Vector3i(1, 0, 0), true)
	lever_on(t + Vector3i(3, 0, 0), true)
	check(meta_at(t) & 4 != 0 and meta_at(t + Vector3i(4, 0, 0)) & 4 != 0, "сигнал открывает люк и калитку")
	lever_on(t + Vector3i(1, 0, 0), false)
	lever_on(t + Vector3i(3, 0, 0), false)
	check(meta_at(t) & 4 == 0 and meta_at(t + Vector3i(4, 0, 0)) & 4 == 0, "без сигнала люк и калитка закрываются")


func _test_tnt_dispenser_note() -> void:
	print("Динамит, раздатчик, нотный блок")
	var o := area(20, -14)
	put(o, Blocks.TNT)
	put(o + Vector3i(1, 0, 0), Blocks.LEVER, 0)
	lever_on(o + Vector3i(1, 0, 0), true)
	var primed := count_children(func(c: Node) -> bool: return c is SimpleEntities.PrimedTnt)
	check(id_at(o) == Blocks.AIR and primed == 1, "сигнал поджигает динамит")
	put(o + Vector3i(0, 0, 2), Blocks.TNT)
	check(id_at(o + Vector3i(0, 0, 2)) == Blocks.TNT, "")
	put(o + Vector3i(1, 0, 2), Blocks.REDSTONE_TORCH, 0)
	check(id_at(o + Vector3i(0, 0, 2)) == Blocks.AIR, "динамит рядом с горящим факелом поджигается сразу")
	clear_entities()
	# Раздатчик: стреляет по фронту сигнала через 4 тика.
	var d := o + Vector3i(5, 0, 0)
	put(d, Blocks.DISPENSER, 3)
	var be := w.get_block_entity(d)
	var inv := Inventory.new(9)
	inv.set_slot(0, Blocks.COBBLESTONE, 3)
	Containers.store(be, inv)
	put(d + Vector3i(0, 0, 1), Blocks.LEVER, 0)
	lever_on(d + Vector3i(0, 0, 1), true)
	ticks(3)
	var none_yet := Containers.load_items(w.get_block_entity(d), 9).counts[0] == 3
	ticks(1)
	check(none_yet and Containers.load_items(w.get_block_entity(d), 9).counts[0] == 2, "раздатчик выбрасывает предмет через 4 тика после сигнала")
	ticks(20)
	check(Containers.load_items(w.get_block_entity(d), 9).counts[0] == 2, "постоянный сигнал — только один выстрел")
	lever_on(d + Vector3i(0, 0, 1), false)
	lever_on(d + Vector3i(0, 0, 1), true)
	ticks(4)
	check(Containers.load_items(w.get_block_entity(d), 9).counts[0] == 1, "новый фронт — новый выстрел")
	var drops := count_children(func(c: Node) -> bool: return c is ItemDrop and (c as ItemDrop).item_id == Blocks.COBBLESTONE)
	check(drops >= 1, "выброшенный предмет появился в мире")
	clear_entities()
	# Нотный блок.
	var n := o + Vector3i(9, 0, 0)
	put(n, Blocks.NOTE_BLOCK)
	w.get_block_entity(n)["note"] = 7
	put(n + Vector3i(1, 0, 0), Blocks.LEVER, 0)
	g.notes.clear()
	lever_on(n + Vector3i(1, 0, 0), true)
	ticks(5)
	check(g.notes == [7], "нотный блок играет по фронту сигнала (%s)" % str(g.notes))
	lever_on(n + Vector3i(1, 0, 0), false)
	lever_on(n + Vector3i(1, 0, 0), true)
	check(g.notes == [7, 7], "повторный сигнал — снова нота")


func _test_pistons() -> void:
	print("Поршни")
	var o := area(-30, -6, 22, 14)
	put(o, Blocks.PISTON, 5)
	for i in range(1, 4):
		put(o + Vector3i(i, 0, 0), Blocks.COBBLESTONE)
	put(o + Vector3i(-1, 0, 0), Blocks.LEVER, 0)
	lever_on(o + Vector3i(-1, 0, 0), true)
	check(meta_at(o) == (5 | 8) and id_at(o + Vector3i(1, 0, 0)) == Blocks.PISTON_HEAD and meta_at(o + Vector3i(1, 0, 0)) == 5,
		"поршень выдвигается по сигналу")
	check(id_at(o + Vector3i(2, 0, 0)) == Blocks.COBBLESTONE and id_at(o + Vector3i(4, 0, 0)) == Blocks.COBBLESTONE, "три блока сдвинуты на один")
	lever_on(o + Vector3i(-1, 0, 0), false)
	var same_tick := meta_at(o) & 8 != 0
	ticks(1)
	check(same_tick and meta_at(o) == 5 and id_at(o + Vector3i(1, 0, 0)) == Blocks.AIR and id_at(o + Vector3i(2, 0, 0)) == Blocks.COBBLESTONE,
		"обычный поршень втягивается (со следующего тика после выдвижения) без блока")
	# Липкий поршень.
	var s := o + Vector3i(0, 0, 2)
	put(s, Blocks.STICKY_PISTON, 5)
	put(s + Vector3i(1, 0, 0), Blocks.SAND)
	put(s + Vector3i(-1, 0, 0), Blocks.LEVER, 0)
	lever_on(s + Vector3i(-1, 0, 0), true)
	check(id_at(s + Vector3i(2, 0, 0)) == Blocks.SAND and meta_at(s + Vector3i(1, 0, 0)) == (5 | 8), "липкий поршень толкает, головка липкая")
	lever_on(s + Vector3i(-1, 0, 0), false)
	ticks(4)
	check(id_at(s + Vector3i(1, 0, 0)) == Blocks.SAND and id_at(s + Vector3i(2, 0, 0)) == Blocks.AIR, "липкий поршень тянет блок назад")
	# Предел — 12 блоков.
	var l := o + Vector3i(0, 0, 4)
	put(l, Blocks.PISTON, 5)
	for i in range(1, 13):
		put(l + Vector3i(i, 0, 0), Blocks.STONE)
	put(l + Vector3i(-1, 0, 0), Blocks.LEVER, 0)
	lever_on(l + Vector3i(-1, 0, 0), true)
	check(meta_at(l) & 8 != 0 and id_at(l + Vector3i(13, 0, 0)) == Blocks.STONE, "поршень толкает 12 блоков")
	lever_on(l + Vector3i(-1, 0, 0), false)
	ticks(1)
	put(l + Vector3i(1, 0, 0), Blocks.STONE)
	lever_on(l + Vector3i(-1, 0, 0), true)
	check(meta_at(l) & 8 == 0 and id_at(l + Vector3i(14, 0, 0)) == Blocks.AIR, "13 блоков поршень не сдвигает")
	lever_on(l + Vector3i(-1, 0, 0), false)
	# Обсидиан, сундук и выдвинутый поршень не двигаются.
	var b := o + Vector3i(0, 0, 6)
	put(b, Blocks.PISTON, 5)
	put(b + Vector3i(1, 0, 0), Blocks.STONE)
	put(b + Vector3i(2, 0, 0), Blocks.OBSIDIAN)
	put(b + Vector3i(-1, 0, 0), Blocks.LEVER, 8)
	check(meta_at(b) & 8 == 0, "обсидиан не сдвигается")
	put(b + Vector3i(2, 0, 0), Blocks.CHEST)
	lever_on(b + Vector3i(-1, 0, 0), false)
	lever_on(b + Vector3i(-1, 0, 0), true)
	check(meta_at(b) & 8 == 0, "сундук не сдвигается")
	put(b + Vector3i(2, 0, 0), Blocks.AIR)
	lever_on(b + Vector3i(-1, 0, 0), false)
	lever_on(b + Vector3i(-1, 0, 0), true)
	check(meta_at(b) & 8 != 0 and id_at(b + Vector3i(2, 0, 0)) == Blocks.STONE, "путь свободен — поршень выдвигается")
	lever_on(b + Vector3i(-1, 0, 0), false)
	ticks(1)
	# Ломающиеся блоки выпадают.
	var t := o + Vector3i(0, 0, 8)
	put(t, Blocks.PISTON, 5)
	put(t + Vector3i(1, 0, 0), Blocks.STONE)
	put(t + Vector3i(2, 0, 0), Blocks.TORCH, 0)
	clear_entities()
	put(t + Vector3i(-1, 0, 0), Blocks.LEVER, 8)
	var torch_drop := count_children(func(c: Node) -> bool: return c is ItemDrop and (c as ItemDrop).item_id == Blocks.TORCH)
	check(id_at(t + Vector3i(2, 0, 0)) == Blocks.STONE and torch_drop == 1, "факел на пути выпадает предметом")
	# Поршень вверх поднимает блок и игрока.
	var u := o + Vector3i(6, 0, 0)
	put(u, Blocks.STICKY_PISTON, 1)
	put(u + Vector3i(0, 1, 0), Blocks.STONE)
	var pl := FakePlayer.new()
	root.add_child(pl)
	g.player = pl
	pl.position = Vector3(u) + Vector3(0.5, 2.001, 0.5)
	put(u + Vector3i(1, 0, 0), Blocks.LEVER, 8)
	check(id_at(u + Vector3i(0, 2, 0)) == Blocks.STONE and id_at(u + Vector3i(0, 1, 0)) == Blocks.PISTON_HEAD
		and pl.position.y > float(u.y) + 2.9, "поршень вверх поднимает блок вместе с игроком")
	g.player = null
	pl.queue_free()
	# Головку сломали — поршень выпадает; сломали поршень — головка исчезает.
	clear_entities()
	logic.break_naturally(u + Vector3i(0, 1, 0))
	var piston_drop := count_children(func(c: Node) -> bool: return c is ItemDrop and (c as ItemDrop).item_id == Blocks.STICKY_PISTON)
	check(id_at(u) == Blocks.AIR and piston_drop == 1, "сломанная головка — поршень выпадает")
	var v := o + Vector3i(9, 0, 0)
	put(v, Blocks.PISTON, 5)
	put(v + Vector3i(0, 0, -1), Blocks.LEVER, 8)
	check(id_at(v + Vector3i(1, 0, 0)) == Blocks.PISTON_HEAD, "")
	logic.break_naturally(v)
	check(id_at(v + Vector3i(1, 0, 0)) == Blocks.AIR, "сломанный выдвинутый поршень убирает головку")
	# Поршень толкает поршень; выдвинутый — нет.
	var c := o + Vector3i(12, 0, 0)
	put(c, Blocks.PISTON, 5)
	put(c + Vector3i(1, 0, 0), Blocks.PISTON, 5)
	put(c + Vector3i(0, 0, -1), Blocks.LEVER, 8)
	check(meta_at(c) & 8 != 0 and id_at(c + Vector3i(2, 0, 0)) == Blocks.PISTON, "поршень толкает втянутый поршень")
	# Квазисвязность (1.2): сигнал на клетку над поршнем.
	var q := o + Vector3i(16, 0, 0)
	put(q, Blocks.PISTON, 5)
	put(q + Vector3i(0, 2, 0), Blocks.REDSTONE_LAMP)
	put(q + Vector3i(0, 3, 0), Blocks.LEVER, 0)
	lever_on(q + Vector3i(0, 3, 0), true)
	check(meta_at(q) & 8 != 0, "поршень срабатывает от сигнала на клетку над ним (как в 1.2)")
	# Поршень вниз выдавливает жидкость и не толкает за пределы мира.
	clear_entities()


func _test_burnout() -> void:
	print("Перегорание факела")
	var o := area(-5, -6)
	put(o, Blocks.STONE)
	put(o + Vector3i(1, 0, 0), Blocks.REDSTONE_TORCH, 1)
	for p: Vector3i in [Vector3i(2, 0, 0), Vector3i(2, 0, -1), Vector3i(2, 0, -2), Vector3i(1, 0, -2), Vector3i(0, 0, -2), Vector3i(0, 0, -1)]:
		put(o + p, Blocks.REDSTONE_WIRE)
	var toggles := 0
	var last := id_at(o + Vector3i(1, 0, 0))
	for i in 50:
		ticks(1)
		var now := id_at(o + Vector3i(1, 0, 0))
		if now != last:
			toggles += 1
			last = now
	check(toggles >= 10, "факел в петле мигает (тактовый генератор), переключений: %d" % toggles)
	var off_since := 0
	for i in 40:
		ticks(1)
		if id_at(o + Vector3i(1, 0, 0)) == Blocks.REDSTONE_TORCH_OFF:
			off_since += 1
	check(off_since >= 30, "факел перегорел (8 переключений за 3 с) и остаётся выключенным")
	ticks(80)
	var relit := false
	for i in 20:
		ticks(1)
		relit = relit or id_at(o + Vector3i(1, 0, 0)) == Blocks.REDSTONE_TORCH
	check(relit, "перегоревший факел со временем зажигается снова")
	put(o + Vector3i(0, 0, -1), Blocks.AIR)


func _test_rails() -> void:
	print("Энергорельсы")
	var o := area(20, -6)
	for i in 12:
		put(o + Vector3i(i, 0, 0), Blocks.POWERED_RAIL, 1)
	put(o + Vector3i(-1, 0, 0), Blocks.LEVER, 0)
	lever_on(o + Vector3i(-1, 0, 0), true)
	var on := PackedInt32Array()
	for i in 12:
		on.append(1 if meta_at(o + Vector3i(i, 0, 0)) & 8 else 0)
	check(on == PackedInt32Array([1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0]), "сигнал проходит по 8 рельсам от запитанного (%s)" % str(on))
	lever_on(o + Vector3i(-1, 0, 0), false)
	var off := true
	for i in 12:
		off = off and meta_at(o + Vector3i(i, 0, 0)) & 8 == 0
	check(off, "без сигнала рельсы выключаются")


func _test_breaking() -> void:
	print("Разрушение компонентов")
	var o := area(-30, 10)
	put(o, Blocks.STONE)
	put(o + Vector3i(0, 1, 0), Blocks.LEVER, 8)
	put(o + Vector3i(1, 0, 0), Blocks.REDSTONE_WIRE)
	check(meta_at(o + Vector3i(1, 0, 0)) == 15, "рычаг на блоке питает провод рядом с блоком")
	put(o, Blocks.AIR)
	check(id_at(o + Vector3i(0, 1, 0)) == Blocks.AIR and meta_at(o + Vector3i(1, 0, 0)) == 0, "блок убран — рычаг выпал, провод разряжен")
	# Провод на поршне: при толчке выпадает.
	var p := o + Vector3i(4, 0, 0)
	put(p, Blocks.PISTON, 5)
	put(p + Vector3i(1, 0, 0), Blocks.REDSTONE_WIRE)
	put(p + Vector3i(0, 0, 1), Blocks.LEVER, 8)
	check(id_at(p + Vector3i(1, 0, 0)) == Blocks.PISTON_HEAD and id_at(p + Vector3i(2, 0, 0)) == Blocks.AIR, "провод перед поршнем ломается")
	# Вода не растекается по проводу с нарушением сети.
	put(p + Vector3i(0, 0, 1), Blocks.LEVER, 0)
	ticks(3)
	check(meta_at(p) & 8 == 0, "")


## Вершины меша одного блока в клетке (8, 1, 8) центрального чанка (относительно угла клетки).
func _mesh_one(id: int, meta: int) -> PackedVector3Array:
	var blocks := []
	var metas := []
	for k in 9:
		var d := PackedByteArray()
		d.resize(WorldGen.VOLUME)
		blocks.append(d)
		var m := PackedByteArray()
		m.resize(WorldGen.VOLUME)
		metas.append(m)
	var idx := Chunk.index_of(8, 1, 8)
	var cb: PackedByteArray = blocks[4]
	cb[idx] = id
	var cm: PackedByteArray = metas[4]
	cm[idx] = meta
	var res := ChunkMesher.build({"blocks": blocks, "metas": metas, "top_y": 1, "vol_top": 1})
	var out := PackedVector3Array()
	for key: String in ["opaque", "translucent"]:
		var arr: Array = res[key]
		if not arr.is_empty():
			for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
				out.append(v - Vector3(8, 1, 8))
	return out


func _bounds(verts: PackedVector3Array) -> AABB:
	if verts.is_empty():
		return AABB()
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	return box


func _test_mesher() -> void:
	print("Отрисовка механизмов")
	var ok := true
	for spec: Array in [[Blocks.REPEATER_OFF, 0], [Blocks.REPEATER_ON, 1 | 12], [Blocks.PISTON, 2], [Blocks.STICKY_PISTON, 5 | 8],
			[Blocks.PISTON_HEAD, 4], [Blocks.PISTON_HEAD, 1 | 8], [Blocks.REDSTONE_WIRE, 15], [Blocks.LEVER, 8], [Blocks.REDSTONE_TORCH_OFF, 1]]:
		if _mesh_one(int(spec[0]), int(spec[1])).is_empty():
			ok = false
			print("    пустой меш: ", spec)
	check(ok, "повторители, поршни, головки, провода, рычаги строятся мешером")
	var rep := _bounds(_mesh_one(Blocks.REPEATER_OFF, 0))
	check(rep.end.y > 0.3, "у повторителя есть факелы над плитой (верх %.2f)" % rep.end.y)
	var ext := _bounds(_mesh_one(Blocks.PISTON, 1 | 8))
	check(ext.end.y < 0.8 and ext.position.y < 0.01, "выдвинутый поршень (вверх) — основание 12/16 (верх %.2f)" % ext.end.y)
	var head := _bounds(_mesh_one(Blocks.PISTON_HEAD, 5))
	check(head.end.x > 0.99 and head.position.x < -0.2, "головка поршня на восток: плита у восточного края и шток назад (%s)" % str(head))


func _test_performance() -> void:
	print("Производительность")
	var o := area(0, 20, 40, 20)
	# Змейка из ~400 проводов.
	var n := 0
	for row in 20:
		for i in 20:
			var x := i if row % 2 == 0 else 19 - i
			put(o + Vector3i(x, 0, row), Blocks.REDSTONE_WIRE)
			n += 1
		if row < 19:
			var x := 19 if row % 2 == 0 else 0
			put(o + Vector3i(x, 0, row), Blocks.REDSTONE_WIRE)
	put(o + Vector3i(-1, 0, 0), Blocks.LEVER, 0)
	var t0 := Time.get_ticks_usec()
	lever_on(o + Vector3i(-1, 0, 0), true)
	var t1 := Time.get_ticks_usec()
	lever_on(o + Vector3i(-1, 0, 0), false)
	var t2 := Time.get_ticks_usec()
	print("    сеть из %d проводов: включение %.1f мс, выключение %.1f мс" % [n, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	check(meta_at(o) == 0, "")
	check((t1 - t0) < 250000, "пересчёт большой сети за разумное время")
	var t3 := Time.get_ticks_usec()
	put(o + Vector3i(25, 0, 0), Blocks.STONE)
	put(o + Vector3i(25, 0, 3), Blocks.WATER)
	ticks(20)
	var t4 := Time.get_ticks_usec()
	print("    20 тиков с текущей водой: %.1f мс" % ((t4 - t3) / 1000.0))
