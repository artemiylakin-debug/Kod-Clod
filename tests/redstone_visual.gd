extends Node
## Визуальный сценарий красной пыли: строит схемы в творческом мире, переключает рычаги,
## проверяет механику и снимает скриншоты (день и ночь).
## Запуск (нужен видеовывод, например Xvfb):
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 -- \
##     --test-script=res://tests/redstone_visual.gd --shots=/абсолютный/путь

const WORLD_NAME := "Редстоун-тест"

var shots_dir := "user://screenshots_redstone"
var _passed := 0
var _failed := 0
var _log := PackedStringArray()
var _shot_index := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
	DirAccess.make_dir_recursive_absolute(shots_dir)
	_run()


func check(cond: bool, what: String) -> void:
	var line := ("[OK]   " if cond else "[FAIL] ") + what
	if cond:
		_passed += 1
	else:
		_failed += 1
	print(line)
	_log.append(line)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	_shot_index += 1
	var img := get_viewport().get_texture().get_image()
	var path := shots_dir.path_join("%02d_%s.png" % [_shot_index, shot_name])
	img.save_png(path)
	print("[SHOT] ", path, " ", img.get_size())
	_log.append("[SHOT] %s" % path)


func game() -> Node:
	return get_tree().current_scene


func wait_loaded(timeout: float = 120.0) -> bool:
	var t := 0.0
	while t < timeout:
		var g := game()
		if g != null and g.get("loading") == false:
			return true
		await wait(0.25)
		t += 0.25
	return false


func wait_world_idle(timeout: float = 120.0) -> void:
	var t := 0.0
	while t < timeout:
		var w: World = game().world
		if w.is_streaming_idle(game().player.position):
			return
		await wait(0.25)
		t += 0.25
	print("[WARN] мир не догрузился за %.0f с" % timeout)


## Камера: из точки eye смотрим на точку at.
func look_at_point(p: Player, eye: Vector3, at: Vector3) -> void:
	# Полёт выключается при касании земли — включаем заново перед каждым снимком.
	p.set_flying(true)
	p.velocity = Vector3.ZERO
	p.position = eye - Vector3(0, Player.EYE_HEIGHT, 0)
	var d := (at - eye).normalized()
	var yaw := atan2(-d.x, -d.z)
	var pitch := asin(clampf(d.y, -1.0, 1.0))
	p.set_look(yaw, pitch)


func _run() -> void:
	await frames(15)
	var started := Time.get_ticks_msec()
	Game.set_setting("render_distance", 4)
	Game.set_setting("touch_controls", 0)
	for wd in WorldStorage.list_worlds():
		if str(wd.get("name", "")).begins_with(WORLD_NAME):
			WorldStorage.delete_world(wd["id"])
	var id := Game.create_world(WORLD_NAME, true, "12345")
	Game.start_world(id)
	await frames(2)
	check(await wait_loaded(), "мир загрузился")
	var g := game()
	var p: Player = g.player
	var w: World = g.world
	await wait_world_idle()
	await frames(5)
	g.set("time_of_day", 0.15)
	p.set_flying(true)
	var c := Vector3i(floori(p.position.x), floori(p.position.y) - 1, floori(p.position.z))
	# Площадка: камень, над ним пусто.
	w.fill_region(c + Vector3i(-16, -4, -8), c + Vector3i(16, -1, 20), Blocks.STONE)
	w.fill_region(c + Vector3i(-16, 0, -8), c + Vector3i(16, 0, 20), Blocks.STONE)
	# Воздух до самого верха: иначе склоны холмов нависают и дают тень.
	w.fill_region(c + Vector3i(-16, 1, -8), c + Vector3i(16, World.CH - 2 - c.y, 20), Blocks.AIR)
	await frames(5)
	var o := c + Vector3i(0, 1, 0)
	_build_wires(w, o + Vector3i(-14, 0, 2))
	_build_torches(w, o + Vector3i(-2, 0, 2))
	_build_repeaters(w, o + Vector3i(6, 0, 2))
	_build_pistons(w, o + Vector3i(-14, 0, 11))
	_build_doors(g, w, o + Vector3i(0, 0, 11))
	w.flush_remesh()
	await wait(1.5)
	await frames(5)
	_checks(w, o)

	# Снимки по группам.
	look_at_point(p, Vector3(o + Vector3i(-10, 6, -3)), Vector3(o + Vector3i(-10, 0, 5)))
	await frames(12)
	await shot("wires")
	look_at_point(p, Vector3(o + Vector3i(1, 5, -2)), Vector3(o + Vector3i(1, 0, 5)))
	await frames(12)
	await shot("torches")
	look_at_point(p, Vector3(o + Vector3i(11, 5, -2)), Vector3(o + Vector3i(11, 0, 5)))
	await frames(12)
	await shot("repeaters")
	look_at_point(p, Vector3(o + Vector3i(-9, 6, 6)), Vector3(o + Vector3i(-9, 0, 13)))
	await frames(12)
	await shot("pistons")
	look_at_point(p, Vector3(o + Vector3i(-9, 3, 20)), Vector3(o + Vector3i(-9, 1, 12)))
	await frames(12)
	await shot("pistons_back")
	look_at_point(p, Vector3(o + Vector3i(5, 4, 6)), Vector3(o + Vector3i(5, 1, 12)))
	await frames(12)
	await shot("doors")
	look_at_point(p, Vector3(o + Vector3i(0, 14, -6)), Vector3(o + Vector3i(0, 0, 8)))
	await frames(12)
	await shot("overview")
	# Ночь: лампы и факелы.
	g.set("time_of_day", 0.75)
	look_at_point(p, Vector3(o + Vector3i(-3, 9, -5)), Vector3(o + Vector3i(-3, 0, 5)))
	await frames(12)
	await shot("night_lamps")

	# Переключения через действия игрока.
	g.set("time_of_day", 0.15)
	await _toggle_tests(g, w, p, o)
	await _finish(started)


# --- Схемы -------------------------------------------------------------------

## Провода: заряженная и незаряженная линии с лампами, развилки, кресты, ступеньки.
func _build_wires(w: World, o: Vector3i) -> void:
	# Линия от включённого рычага к лампе.
	w.set_block_v(o, Blocks.LEVER, 8)
	for i in range(1, 9):
		w.set_block_v(o + Vector3i(i, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(o + Vector3i(9, 0, 0), Blocks.REDSTONE_LAMP)
	# Та же линия, рычаг выключен.
	var b := o + Vector3i(0, 0, 2)
	w.set_block_v(b, Blocks.LEVER, 0)
	for i in range(1, 9):
		w.set_block_v(b + Vector3i(i, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(b + Vector3i(9, 0, 0), Blocks.REDSTONE_LAMP)
	# Развилка и крест.
	var t := o + Vector3i(0, 0, 5)
	w.set_block_v(t, Blocks.REDSTONE_TORCH, 0)
	for i in range(1, 6):
		w.set_block_v(t + Vector3i(i, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(t + Vector3i(2, 0, 1), Blocks.REDSTONE_WIRE)
	w.set_block_v(t + Vector3i(2, 0, 2), Blocks.REDSTONE_WIRE)
	w.set_block_v(t + Vector3i(4, 0, 1), Blocks.REDSTONE_WIRE)
	w.set_block_v(t + Vector3i(4, 0, -1), Blocks.REDSTONE_WIRE)
	# Ступенька вверх и вниз.
	w.set_block_v(t + Vector3i(6, 0, 0), Blocks.STONE)
	w.set_block_v(t + Vector3i(6, 1, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(t + Vector3i(7, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(t + Vector3i(8, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(t + Vector3i(9, 0, 0), Blocks.REDSTONE_LAMP)


## Факелы: горящий на стене блока, погасший (блок запитан рычагом), инвертор лампы.
func _build_torches(w: World, o: Vector3i) -> void:
	w.set_block_v(o, Blocks.STONE)
	w.set_block_v(o + Vector3i(0, 0, -1), Blocks.REDSTONE_TORCH, 4)
	w.set_block_v(o + Vector3i(0, 1, 0), Blocks.REDSTONE_TORCH, 0)
	var b := o + Vector3i(3, 0, 0)
	w.set_block_v(b, Blocks.STONE)
	w.set_block_v(b + Vector3i(0, 0, -1), Blocks.REDSTONE_TORCH, 4)
	w.set_block_v(b + Vector3i(0, 1, 0), Blocks.LEVER, 8)
	# Инвертор: рычаг → провод → блок с факелом → лампа над факелом-блоком.
	var n := o + Vector3i(0, 0, 3)
	w.set_block_v(n, Blocks.LEVER, 0)
	w.set_block_v(n + Vector3i(1, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(n + Vector3i(2, 0, 0), Blocks.STONE)
	w.set_block_v(n + Vector3i(3, 0, 0), Blocks.REDSTONE_TORCH, 1)
	w.set_block_v(n + Vector3i(4, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(n + Vector3i(5, 0, 0), Blocks.REDSTONE_LAMP)


## Повторители: включённые с задержкой 1 и 4, выключенные, лампа на выходе.
func _build_repeaters(w: World, o: Vector3i) -> void:
	w.set_block_v(o, Blocks.LEVER, 8)
	w.set_block_v(o + Vector3i(1, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(o + Vector3i(2, 0, 0), Blocks.REPEATER_OFF, 3)
	w.set_block_v(o + Vector3i(3, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(o + Vector3i(4, 0, 0), Blocks.REPEATER_OFF, 3 | (3 << 2))
	w.set_block_v(o + Vector3i(5, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(o + Vector3i(6, 0, 0), Blocks.REDSTONE_LAMP)
	var b := o + Vector3i(0, 0, 2)
	w.set_block_v(b, Blocks.LEVER, 0)
	w.set_block_v(b + Vector3i(1, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(b + Vector3i(2, 0, 0), Blocks.REPEATER_OFF, 3 | (1 << 2))
	w.set_block_v(b + Vector3i(3, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(b + Vector3i(4, 0, 0), Blocks.REPEATER_OFF, 3 | (2 << 2))
	w.set_block_v(b + Vector3i(5, 0, 0), Blocks.REDSTONE_WIRE)
	w.set_block_v(b + Vector3i(6, 0, 0), Blocks.REDSTONE_LAMP)
	# Повторители в другие стороны (проверка поворота).
	var r := o + Vector3i(0, 0, 4)
	for d in 4:
		w.set_block_v(r + Vector3i(d * 2, 0, 0), Blocks.REPEATER_OFF, d | (d << 2))


## Поршни: выдвинутые (обычный и липкий), втянутые, вертикальный, толкание ряда блоков.
func _build_pistons(w: World, o: Vector3i) -> void:
	# Обычный поршень на восток толкает два блока.
	w.set_block_v(o, Blocks.PISTON, 5)
	w.set_block_v(o + Vector3i(1, 0, 0), Blocks.COBBLESTONE)
	w.set_block_v(o + Vector3i(2, 0, 0), Blocks.PLANKS)
	w.set_block_v(o + Vector3i(-1, 0, 0), Blocks.LEVER, 8)
	# Липкий выдвинутый.
	var s := o + Vector3i(0, 0, 2)
	w.set_block_v(s, Blocks.STICKY_PISTON, 5)
	w.set_block_v(s + Vector3i(1, 0, 0), Blocks.WOOL, 14)
	w.set_block_v(s + Vector3i(-1, 0, 0), Blocks.LEVER, 8)
	# Липкий: выдвинули и втянули — блок вернулся.
	var r := o + Vector3i(0, 0, 4)
	w.set_block_v(r, Blocks.STICKY_PISTON, 5)
	w.set_block_v(r + Vector3i(1, 0, 0), Blocks.WOOL, 11)
	w.set_block_v(r + Vector3i(-1, 0, 0), Blocks.LEVER, 0)
	# Вертикальный поршень поднимает блок.
	var u := o + Vector3i(6, 0, 0)
	w.set_block_v(u, Blocks.PISTON, 1)
	w.set_block_v(u + Vector3i(0, 1, 0), Blocks.GOLD_BLOCK)
	w.set_block_v(u + Vector3i(1, 0, 0), Blocks.LEVER, 8)
	# Втянутые поршни в разные стороны.
	for d in 6:
		w.set_block_v(o + Vector3i(9 + (d % 3) * 2, 2 if d >= 3 else 0, 2), Blocks.PISTON if d % 2 == 0 else Blocks.STICKY_PISTON, d)
	# Липкий поршень на запад, выдвинутый.
	var west := o + Vector3i(9, 0, 5)
	w.set_block_v(west, Blocks.STICKY_PISTON, 4)
	w.set_block_v(west + Vector3i(1, 0, 0), Blocks.LEVER, 8)


## Двери: деревянная с нажатой плитой (на ней предмет), железная с кнопкой, люк и калитка.
func _build_doors(g: Node, w: World, o: Vector3i) -> void:
	w.set_block_v(o, Blocks.WOODEN_DOOR, 0)
	w.set_block_v(o + Vector3i(0, 1, 0), Blocks.WOODEN_DOOR, 8)
	w.set_block_v(o + Vector3i(0, 0, -1), Blocks.WOODEN_PLATE)
	g.call("spawn_drop", Blocks.DIRT, 1, 0, Vector3(o + Vector3i(0, 0, -1)) + Vector3(0.5, 0.05, 0.5), Vector3.ZERO, 1000.0)
	var d := o + Vector3i(3, 0, 0)
	w.set_block_v(d, Blocks.IRON_DOOR, 0)
	w.set_block_v(d + Vector3i(0, 1, 0), Blocks.IRON_DOOR, 8)
	w.set_block_v(d + Vector3i(1, 0, 0), Blocks.STONE)
	w.set_block_v(d + Vector3i(1, 1, 0), Blocks.STONE)
	w.set_block_v(d + Vector3i(1, 1, -1), Blocks.STONE_BUTTON, 4)
	# Закрытая железная дверь рядом — для сравнения.
	var e := o + Vector3i(6, 0, 0)
	w.set_block_v(e, Blocks.IRON_DOOR, 0)
	w.set_block_v(e + Vector3i(0, 1, 0), Blocks.IRON_DOOR, 8)
	var t := o + Vector3i(8, 0, 0)
	w.set_block_v(t, Blocks.TRAPDOOR, 0)
	w.set_block_v(t + Vector3i(0, 0, -1), Blocks.LEVER, 8)
	w.set_block_v(t + Vector3i(2, 0, 0), Blocks.FENCE_GATE, 0)
	w.set_block_v(t + Vector3i(2, 0, -1), Blocks.LEVER, 8)


func _checks(w: World, o: Vector3i) -> void:
	var wires := o + Vector3i(-14, 0, 2)
	check(w.get_meta_v(wires + Vector3i(1, 0, 0)) == 15 and w.get_meta_v(wires + Vector3i(8, 0, 0)) == 8, "провод от рычага: 15 → 8")
	check(w.get_block_v(wires + Vector3i(9, 0, 0)) == Blocks.LIT_REDSTONE_LAMP, "лампа на конце провода горит")
	check(w.get_block_v(wires + Vector3i(9, 0, 2)) == Blocks.REDSTONE_LAMP, "лампа без сигнала не горит")
	check(w.get_meta_v(wires + Vector3i(6, 1, 5)) > 0 and w.get_block_v(wires + Vector3i(9, 0, 5)) == Blocks.LIT_REDSTONE_LAMP,
		"провод через ступеньку и лампа за ней")
	var torches := o + Vector3i(-2, 0, 2)
	check(w.get_block_v(torches + Vector3i(0, 0, -1)) == Blocks.REDSTONE_TORCH, "факел на незапитанном блоке горит")
	check(w.get_block_v(torches + Vector3i(3, 0, -1)) == Blocks.REDSTONE_TORCH_OFF, "факел на запитанном блоке погас")
	check(w.get_block_v(torches + Vector3i(5, 0, 3)) == Blocks.LIT_REDSTONE_LAMP, "инвертор: рычаг выключен — лампа горит")
	var rep := o + Vector3i(6, 0, 2)
	check(w.get_block_v(rep + Vector3i(2, 0, 0)) == Blocks.REPEATER_ON and w.get_block_v(rep + Vector3i(4, 0, 0)) == Blocks.REPEATER_ON
		and w.get_block_v(rep + Vector3i(6, 0, 0)) == Blocks.LIT_REDSTONE_LAMP, "цепочка повторителей включена, лампа горит")
	var pis := o + Vector3i(-14, 0, 11)
	check(w.get_meta_v(pis) == (5 | 8) and w.get_block_v(pis + Vector3i(1, 0, 0)) == Blocks.PISTON_HEAD
		and w.get_block_v(pis + Vector3i(3, 0, 0)) == Blocks.PLANKS, "поршень выдвинут и толкнул блоки")
	check(w.get_block_v(pis + Vector3i(6, 2, 0)) == Blocks.GOLD_BLOCK, "вертикальный поршень поднял золотой блок")
	var doors := o + Vector3i(0, 0, 11)
	check(w.get_meta_v(doors + Vector3i(0, 0, -1)) == 1 and w.get_meta_v(doors) & 4 != 0, "предмет на деревянной плите — дверь открыта")
	check(w.get_meta_v(doors + Vector3i(8, 0, 0)) & 4 != 0 and w.get_meta_v(doors + Vector3i(10, 0, 0)) & 4 != 0, "люк и калитка открыты сигналом")


## Переключения через PlayerActions (как правой кнопкой мыши).
func _toggle_tests(g: Node, w: World, p: Player, o: Vector3i) -> void:
	var actions: PlayerActions = g.actions
	# Кнопка у железной двери.
	var btn := o + Vector3i(4, 1, 10)
	actions.call("_use_block", p, {"pos": btn, "block": Blocks.STONE_BUTTON, "meta": w.get_meta_v(btn)})
	await frames(3)
	var door := o + Vector3i(3, 0, 11)
	check(w.get_meta_v(btn) & 8 != 0 and w.get_meta_v(door) & 4 != 0, "кнопка (через действия игрока) открыла железную дверь")
	look_at_point(p, Vector3(o + Vector3i(5, 4, 6)), Vector3(o + Vector3i(5, 1, 12)))
	await frames(8)
	await shot("button_door")
	await wait(1.6)
	check(w.get_meta_v(btn) & 8 == 0 and w.get_meta_v(door) & 4 == 0, "кнопка отпущена через секунду, дверь закрылась")
	# Рычаг выключенной линии — включаем действием игрока.
	var lever := o + Vector3i(-14, 0, 4)
	actions.call("_use_block", p, {"pos": lever, "block": Blocks.LEVER, "meta": w.get_meta_v(lever)})
	await frames(3)
	check(w.get_block_v(lever + Vector3i(9, 0, 0)) == Blocks.LIT_REDSTONE_LAMP, "рычаг (через действия игрока) зажёг лампу")
	# Инвертор: включаем рычаг — лампа гаснет.
	var inv := o + Vector3i(-2, 0, 5)
	actions.call("_use_block", p, {"pos": inv, "block": Blocks.LEVER, "meta": w.get_meta_v(inv)})
	await wait(0.6)
	check(w.get_block_v(inv + Vector3i(3, 0, 0)) == Blocks.REDSTONE_TORCH_OFF and w.get_block_v(inv + Vector3i(5, 0, 0)) == Blocks.REDSTONE_LAMP,
		"инвертор: рычаг включён — факел и лампа погасли")
	# Липкий поршень: втягиваем — блок шерсти возвращается.
	var sp := o + Vector3i(-14, 0, 13)
	var sl := sp + Vector3i(-1, 0, 0)
	actions.call("_use_block", p, {"pos": sl, "block": Blocks.LEVER, "meta": w.get_meta_v(sl)})
	await wait(0.3)
	check(w.get_meta_v(sp) & 8 == 0 and w.get_block_v(sp + Vector3i(1, 0, 0)) == Blocks.WOOL, "липкий поршень втянул блок")
	# Повторитель: смена задержки действием.
	var r := o + Vector3i(8, 0, 2)
	var before := w.get_meta_v(r)
	actions.call("_use_block", p, {"pos": r, "block": w.get_block_v(r), "meta": before})
	check(w.get_meta_v(r) == (before + 4) & 15, "повторитель: задержка переключается")
	look_at_point(p, Vector3(o + Vector3i(-3, 9, -5)), Vector3(o + Vector3i(-3, 0, 5)))
	await frames(12)
	await shot("after_toggles")


func _finish(started: int) -> void:
	Game.set_setting("render_distance", 6)
	Game.save_settings()
	var summary := "Редстоун: %d пройдено, %d провалено за %.0f с" % [_passed, _failed, (Time.get_ticks_msec() - started) / 1000.0]
	print(summary)
	_log.append(summary)
	var f := FileAccess.open(shots_dir.path_join("report.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log))
		f.close()
	var g := game()
	if g != null and g.has_method("quit_to_menu"):
		g.call("quit_to_menu")
		await frames(5)
	for wd in WorldStorage.list_worlds():
		if str(wd.get("name", "")).begins_with(WORLD_NAME):
			WorldStorage.delete_world(wd["id"])
	get_tree().quit(1 if _failed > 0 else 0)
