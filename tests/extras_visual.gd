extends Node
## Сценарий-автотест погоды, частиц, порталов и измерений (со скриншотами).
## Запуск: godot --path . --rendering-driver opengl3 -- --test-script=res://tests/extras_visual.gd --shots=/путь

const WORLD_NAME := "Автотест измерений"

var shots_dir := "user://screenshots_extras"
var _passed := 0
var _failed := 0
var _shot_index := 0
var _log := PackedStringArray()


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
	print("[SHOT] ", path)


func game() -> Node:
	return get_tree().current_scene


func wait_loaded(timeout: float = 180.0) -> bool:
	var t := 0.0
	while t < timeout:
		var g := game()
		if g != null and g.get("loading") == false and g.get("world") != null:
			return true
		await wait(0.25)
		t += 0.25
	return false


func wait_idle(timeout: float = 120.0) -> void:
	var t := 0.0
	while t < timeout:
		var g := game()
		var w: World = g.world
		if w.is_streaming_idle(g.player.position):
			return
		await wait(0.25)
		t += 0.25


func _run() -> void:
	await frames(10)
	var started := Time.get_ticks_msec()
	Game.set_setting("render_distance", 4)
	Game.set_setting("touch_controls", 2)
	for w in WorldStorage.list_worlds():
		if str(w.get("name", "")).begins_with(WORLD_NAME):
			WorldStorage.delete_world(w["id"])
	var id := Game.create_world(WORLD_NAME, true, "4242")
	Game.start_world(id)
	await frames(2)
	check(await wait_loaded(), "мир загрузился")
	await wait_idle()
	var g := game()
	var p: Player = g.player
	var w: World = g.world
	# Площадка.
	var c := Vector3i(floori(p.position.x), floori(p.position.y) - 1, floori(p.position.z))
	w.fill_region(c + Vector3i(-10, -2, -10), c + Vector3i(10, 0, 10), Blocks.GRASS)
	w.fill_region(c + Vector3i(-10, 1, -10), c + Vector3i(10, 12, 10), Blocks.AIR)
	p.position = Vector3(c) + Vector3(0.5, 1.001, 0.5)
	await frames(10)

	# --- Погода ---
	var weather: Weather = g.weather
	weather.set_weather(true, false)
	weather.rain = 1.0
	p.set_look(deg_to_rad(30.0), deg_to_rad(5.0))
	await frames(20)
	check(g.logic.raining, "идёт дождь (логика блоков знает)")
	await shot("rain")
	weather.set_weather(true, true)
	weather.thunder = 1.0
	weather.strike(Vector3(c) + Vector3(6.5, 1.0, -6.5))
	await frames(2)
	await shot("lightning")
	await frames(30)
	weather.set_weather(false, false)
	weather.rain = 0.0
	weather.thunder = 0.0
	await frames(5)

	# --- Частицы ---
	w.set_block(c.x + 2, c.y + 1, c.z - 3, Blocks.STONE)
	g.particles.block_break(Vector3i(c.x + 2, c.y + 1, c.z - 3), Blocks.GRASS, 0)
	g.particles.block_break(Vector3i(c.x + 1, c.y + 1, c.z - 3), Blocks.LEAVES, 0)
	g.particles.explosion(Vector3(c) + Vector3(-2.0, 2.0, -4.0), 3.0)
	for i in 6:
		g.particles.splash(Vector3(c) + Vector3(3.0, 1.2, -2.0))
	p.set_look(0.0, deg_to_rad(-20.0))
	await frames(4)
	check(g.particles.count() > 50, "частицы появились (%d)" % g.particles.count())
	await shot("particles")
	w.set_block(c.x - 1, c.y + 1, c.z - 2, Blocks.TORCH, 5)
	w.set_block(c.x, c.y + 1, c.z - 2, Blocks.FIRE)
	w.set_block(c.x, c.y, c.z - 2, Blocks.NETHERRACK)
	g.set("time_of_day", 0.75)
	await wait(1.5)
	await shot("torch_fire_night")
	g.set("time_of_day", 0.15)
	w.set_block(c.x, c.y + 1, c.z - 2, Blocks.AIR)

	# --- Портал в Нижний мир ---
	var o := c + Vector3i(-2, 1, 4)
	for i in 4:
		for j in 5:
			if i == 0 or i == 3 or j == 0 or j == 4:
				w.set_block(o.x + i, o.y + j, o.z, Blocks.OBSIDIAN)
	check(Portals.try_light(w, o + Vector3i(1, 1, 0)), "огонь в рамке зажигает портал")
	check(w.get_block_v(o + Vector3i(2, 3, 0)) == Blocks.PORTAL, "портал заполнил рамку 2×3")
	p.position = Vector3(o) + Vector3(1.5, 1.0, -3.0)
	p.set_look(PI, deg_to_rad(-5.0))
	await frames(30)
	await shot("nether_portal")
	# Вход в портал.
	p.position = Vector3(o) + Vector3(1.5, 1.001, 0.5)
	var t := 0.0
	while game() == g and t < 10.0:
		await wait(0.25)
		t += 0.25
	check(game() != g, "портал перенёс игрока")
	check(await wait_loaded(), "Нижний мир загрузился")
	g = game()
	p = g.player
	w = g.world
	check(int(g.get("dimension")) == -1, "игрок в Нижнем мире")
	check(w.get_block_v(Vector3i(floori(p.position.x), floori(p.position.y + 0.1), floori(p.position.z))) == Blocks.PORTAL,
		"в Нижнем мире игрок стоит в обратном портале")
	await wait_idle()
	p.set_look(PI, deg_to_rad(-10.0))
	await frames(10)
	await shot("nether_arrival")
	p.set_flying(true)
	p.position += Vector3(0, 0, 4)
	p.set_look(deg_to_rad(20.0), deg_to_rad(-15.0))
	await frames(20)
	await shot("nether_view")
	# Назад через тот же портал.
	var back := Portals.find_portal(w, p.position, 16)
	p.set_flying(false)
	p.position = Vector3(back) + Vector3(0.5, 0.001, 0.5)
	t = 0.0
	while game() == g and t < 10.0:
		await wait(0.25)
		t += 0.25
	check(await wait_loaded(), "вернулись в обычный мир")
	g = game()
	p = g.player
	w = g.world
	check(int(g.get("dimension")) == 0, "игрок снова в обычном мире")
	await wait_idle()
	await frames(5)

	# --- Портал в Край ---
	var ec := Vector3i(floori(p.position.x) + 6, floori(p.position.y), floori(p.position.z))
	w.fill_region(ec + Vector3i(-3, -1, -3), ec + Vector3i(3, -1, 3), Blocks.STONE_BRICKS)
	w.fill_region(ec + Vector3i(-3, 0, -3), ec + Vector3i(3, 3, 3), Blocks.AIR)
	for k in range(-1, 2):
		w.set_block(ec.x + k, ec.y, ec.z - 2, Blocks.END_PORTAL_FRAME, 0 | 4)
		w.set_block(ec.x + k, ec.y, ec.z + 2, Blocks.END_PORTAL_FRAME, 2 | 4)
		w.set_block(ec.x - 2, ec.y, ec.z + k, Blocks.END_PORTAL_FRAME, 3 | 4)
	for k in range(-1, 1):
		w.set_block(ec.x + 2, ec.y, ec.z + k, Blocks.END_PORTAL_FRAME, 1 | 4)
	w.set_block(ec.x + 2, ec.y, ec.z + 1, Blocks.END_PORTAL_FRAME, 1)
	check(not Portals.check_end_portal(w, ec), "кольцо без последнего ока не открывается")
	w.set_block(ec.x + 2, ec.y, ec.z + 1, Blocks.END_PORTAL_FRAME, 1 | 4)
	g.call("check_end_portal", ec + Vector3i(2, 0, 1))
	check(w.get_block_v(ec) == Blocks.END_PORTAL, "портал в Край открылся")
	p.position = Vector3(ec) + Vector3(-4.5, 1.5, 0.5)
	p.set_look(-PI / 2.0, deg_to_rad(-25.0))
	await frames(20)
	await shot("end_portal")
	p.position = Vector3(ec) + Vector3(0.5, 0.2, 0.5)
	t = 0.0
	while game() == g and t < 10.0:
		await wait(0.25)
		t += 0.25
	check(await wait_loaded(), "Край загрузился")
	g = game()
	p = g.player
	w = g.world
	check(int(g.get("dimension")) == 1, "игрок в Краю")
	check(w.get_block_v(Portals.END_SPAWN + Vector3i(0, -1, 0)) == Blocks.OBSIDIAN, "обсидиановая площадка прибытия")
	await wait_idle()
	p.set_look(deg_to_rad(90.0), deg_to_rad(-10.0))
	await frames(10)
	await shot("end_arrival")
	# Гибель в Краю — возрождение в обычном мире.
	p.take_damage(1000)
	await frames(3)
	g.call("_respawn")
	t = 0.0
	while game() == g and t < 10.0:
		await wait(0.25)
		t += 0.25
	check(await wait_loaded(), "возрождение загрузилось")
	g = game()
	check(int(g.get("dimension")) == 0 and not g.player.dead, "после гибели в Краю — обычный мир")
	await frames(10)
	await shot("respawn_overworld")
	_finish(started)


func _finish(started: int) -> void:
	Game.set_setting("render_distance", 6)
	Game.set_setting("touch_controls", 0)
	Game.save_settings()
	var summary := "Сценарий измерений: %d пройдено, %d провалено за %.0f с" % [_passed, _failed, (Time.get_ticks_msec() - started) / 1000.0]
	print(summary)
	_log.append(summary)
	var f := FileAccess.open(shots_dir.path_join("report.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log))
		f.close()
	if game() != null and game().has_method("quit_to_menu"):
		game().call("quit_to_menu")
		await frames(5)
	for wd in WorldStorage.list_worlds():
		if str(wd.get("name", "")).begins_with(WORLD_NAME):
			WorldStorage.delete_world(wd["id"])
	get_tree().quit(1 if _failed > 0 else 0)
