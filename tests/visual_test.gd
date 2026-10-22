extends Node
## Визуальный автотест: проходит по сценарию игры, проверяет механику и сохраняет скриншоты.
## Запуск (нужен видеовывод, например Xvfb):
##   godot --path . --rendering-driver opengl3 -- --visual-test --shots=/абсолютный/путь

const WORLD_NAME := "Автотест"

var shots_dir := "user://screenshots"
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


func key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	var r := e.duplicate() as InputEventKey
	r.pressed = false
	Input.parse_input_event(r)
	await frames(2)


## Точка интерфейса (в координатах холста) → пиксели окна, как их присылает ОС.
func to_window(canvas_pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * canvas_pos


func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = to_window(pos)
	e.pressed = pressed
	Input.parse_input_event(e)


func drag(index: int, from: Vector2, to: Vector2, steps: int) -> void:
	for i in steps:
		var e := InputEventScreenDrag.new()
		e.index = index
		var a := to_window(from.lerp(to, float(i) / steps))
		var b := to_window(from.lerp(to, float(i + 1) / steps))
		e.position = b
		e.relative = b - a
		Input.parse_input_event(e)
		await frames(1)


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


## Ждём, пока все чанки в радиусе прорисовки будут построены.
func wait_world_idle(timeout: float = 120.0) -> void:
	var t := 0.0
	while t < timeout:
		var w: World = game().world
		if w.is_streaming_idle(game().player.position):
			return
		await wait(0.25)
		t += 0.25
	print("[WARN] мир не догрузился за %.0f с" % timeout)


func _run() -> void:
	await frames(15)
	if "--layout-test" in OS.get_cmdline_user_args():
		await _run_layout()
		return
	var started := Time.get_ticks_msec()
	# Программный рендер медленный — уменьшаем дальность прорисовки на время теста.
	Game.set_setting("render_distance", 5)
	Game.set_setting("touch_controls", 2)
	# Удаляем миры от прошлых прогонов.
	for w in WorldStorage.list_worlds():
		if str(w.get("name", "")).begins_with(WORLD_NAME):
			WorldStorage.delete_world(w["id"])

	# --- Главное меню ---
	await shot("main_menu")
	var menu := game()
	menu.call("show_screen", "create")
	await frames(3)
	await shot("create_world")
	var id := Game.create_world(WORLD_NAME + " (креатив)", true, "12345")
	menu.call("show_screen", "worlds")
	await frames(3)
	await shot("world_list")

	# --- Креатив ---
	Game.start_world(id)
	await frames(2)
	check(await wait_loaded(), "мир загрузился")
	var g := game()
	var p: Player = g.player
	var w: World = g.world
	await wait_world_idle()
	await frames(10)
	check(not p.frozen and p.on_ground, "игрок стоит на земле после появления (y=%.2f)" % p.position.y)
	check(p.creative and p.inventory.get_selected_block() != Blocks.AIR, "креатив: хотбар заполнен")
	await shot("creative_spawn")
	var arena := _make_arena(w, p)
	await frames(10)

	# Пейзаж с высоты.
	p.set_flying(true)
	p.position += Vector3(0, 12, 0)
	p.set_look(deg_to_rad(35.0), deg_to_rad(-12.0))
	await wait_world_idle()
	await frames(10)
	await shot("landscape")
	g.set("time_of_day", 0.72)
	await frames(5)
	await shot("night")
	g.set("time_of_day", 0.49)
	await frames(5)
	await shot("sunset")
	g.set("time_of_day", 0.15)
	p.set_flying(false)
	p.position = Vector3(arena) + Vector3(0.5, 1.001, 0.5)
	await frames(20)
	await _cave_shot(w, p)
	p.position = Vector3(arena) + Vector3(0.5, 1.001, 0.5)
	await frames(10)

	# Ломаем блок под прицелом (левая кнопка мыши).
	p.set_look(0.0, deg_to_rad(-60.0))
	await frames(3)
	check(not p.target.is_empty(), "прицел наведён на блок")
	var target_pos: Vector3i = p.target.get("pos", Vector3i.ZERO)
	var before := w.get_block_v(target_pos)
	p.mouse_break = true
	await frames(3)
	p.mouse_break = false
	await frames(5)
	check(before != Blocks.AIR and w.get_block_v(target_pos) != before, "креатив: блок сломан мгновенно (%s)" % Blocks.block_name(before))
	var dig_pos := target_pos

	# Ставим блок (правая кнопка).
	p.inventory.select(6) # стекло
	await frames(3)
	var tgt := p.target
	if not tgt.is_empty():
		var place_pos: Vector3i = tgt["pos"] + tgt["normal"]
		p.mouse_place = true
		await frames(3)
		p.mouse_place = false
		await frames(5)
		check(w.get_block_v(place_pos) == Blocks.GLASS, "креатив: блок стекла поставлен")
	else:
		check(false, "нет цели для установки блока")

	# Домик из разных блоков рядом с игроком.
	var base := arena + Vector3i(2, 1, -9)
	_build_house(w, base)
	p.set_look(deg_to_rad(-25.0), deg_to_rad(-8.0))
	p.position = Vector3(arena) + Vector3(-1.5, 1.001, 4.5)
	await frames(20)
	await shot("house_build")

	# Креативный инвентарь (клавиша E).
	await key(KEY_E)
	await frames(3)
	check(g.inventory_ui.visible, "инвентарь открывается клавишей E")
	await shot("creative_inventory")
	await key(KEY_E)
	check(not g.inventory_ui.visible, "инвентарь закрывается клавишей E")

	# Отладочный экран F3.
	await key(KEY_F3)
	await frames(3)
	await shot("debug_overlay")
	await key(KEY_F3)

	# --- Выживание (F4) ---
	await key(KEY_F4)
	check(not p.creative and not g.creative, "F4 переключает в выживание")
	p.inventory.clear()
	await frames(5)
	await shot("survival_hud")

	# Добыча блока со временем: трещины и выпавший предмет.
	p.position = Vector3(arena) + Vector3(-4.5, 1.001, 5.5)
	p.set_look(0.0, deg_to_rad(-55.0))
	await frames(3)
	var mine_pos: Vector3i = p.target.get("pos", Vector3i.ZERO)
	var mine_id := w.get_block_v(mine_pos)
	p.mouse_break = true
	await wait(minf(Blocks.hardness(mine_id) * 0.55, 1.0))
	check(p.break_progress > 0.2 and w.get_block_v(mine_pos) == mine_id, "выживание: блок ломается постепенно (%.0f%%)" % (p.break_progress * 100.0))
	await shot("survival_mining_cracks")
	await wait(Blocks.hardness(mine_id) + 0.3)
	p.mouse_break = false
	check(w.get_block_v(mine_pos) != mine_id, "выживание: блок добыт")
	await frames(2)
	var drops := 0
	for n in g.get_node("Drops").get_children():
		drops += 1
	check(drops > 0 or p.inventory.count_of(Blocks.drop_of(mine_id)) > 0, "выпал предмет")
	p.set_look(0.0, deg_to_rad(-35.0))
	await frames(8)
	await shot("item_drop")
	await wait(1.5)
	check(p.inventory.count_of(Blocks.drop_of(mine_id)) >= 1, "предмет подобран в инвентарь (%s)" % Blocks.block_name(Blocks.drop_of(mine_id)))

	# Урон от падения.
	var hp := p.health
	p.position += Vector3(0, 10, 0)
	await wait(2.0)
	check(p.health < hp, "урон от падения: %d → %d" % [hp, p.health])
	await shot("fall_damage")

	# Инвентарь выживания и крафт.
	p.inventory.add_item(Blocks.LOG, 5)
	p.inventory.add_item(Blocks.COBBLESTONE, 20)
	p.inventory.add_item(Blocks.SAND, 7)
	await key(KEY_E)
	await frames(3)
	var planks_before := p.inventory.count_of(Blocks.PLANKS)
	g.inventory_ui.call("_craft", 0)
	check(p.inventory.count_of(Blocks.PLANKS) == planks_before + 4 and p.inventory.count_of(Blocks.LOG) == 4, "крафт: бревно → 4 доски")
	g.inventory_ui.call("_on_slot_pressed", 0)
	await frames(2)
	await shot("survival_inventory")
	g.inventory_ui.call("_on_slot_pressed", 12)
	check(p.inventory.counts[0] == 0 and p.inventory.counts[12] > 0, "перемещение предмета между слотами")
	await key(KEY_E)
	p.position = Vector3(arena) + Vector3(5.5, 1.001, 5.5)
	p.set_look(0.0, deg_to_rad(-10.0))

	# --- Сенсорное управление ---
	Game.set_setting("touch_controls", 1)
	await frames(5)
	check(g.touch.visible, "сенсорное управление включено")
	p.inventory.set_slot(5, Blocks.DIRT, 10)
	p.inventory.select(5)
	await frames(3)
	await shot("touch_controls")
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var start := p.position
	var joy := Vector2(190, vs.y - 170)
	touch(0, joy, true)
	await frames(2)
	await drag(0, joy, joy + Vector2(0, -95), 6)
	await wait(1.0)
	await shot("touch_joystick")
	touch(0, joy + Vector2(0, -95), false)
	await frames(3)
	var moved := Vector2(p.position.x - start.x, p.position.z - start.z).length()
	check(moved > 1.5, "джойстик двигает игрока (%.1f блока)" % moved)
	var yaw0 := p.yaw
	var look := Vector2(vs.x * 0.62, vs.y * 0.4)
	touch(1, look, true)
	await drag(1, look, look + Vector2(-120, 0), 6)
	touch(1, look + Vector2(-120, 0), false)
	await frames(3)
	check(absf(p.yaw - yaw0) > 0.2, "свайп справа поворачивает камеру")
	# Тап — поставить блок, удержание — ломать.
	p.position = Vector3(arena) + Vector3(0.5, 1.001, 0.5)
	p.set_look(0.0, deg_to_rad(-60.0))
	await frames(3)
	var t2 := p.target
	var dirt_before := p.inventory.count_of(Blocks.DIRT)
	touch(2, look, true)
	await frames(1)
	touch(2, look, false)
	await frames(4)
	check(p.inventory.count_of(Blocks.DIRT) == dirt_before - 1 and not t2.is_empty(), "тап ставит блок")
	await frames(3)
	var hold_target: Vector3i = p.target.get("pos", Vector3i.ZERO)
	var hold_id := w.get_block_v(hold_target)
	touch(3, look, true)
	await wait(TouchControls.HOLD_TIME + Blocks.hardness(hold_id) + 0.4)
	touch(3, look, false)
	await frames(3)
	check(w.get_block_v(hold_target) != hold_id, "удержание пальца ломает блок (%s)" % Blocks.block_name(hold_id))
	# Кнопка прыжка.
	var jump_btn: Array = g.touch.get("_buttons")[TouchControls.R_JUMP]
	var y0 := p.position.y
	touch(4, jump_btn[0], true)
	var peak := y0
	for i in 20:
		await frames(1)
		peak = maxf(peak, p.position.y)
	touch(4, jump_btn[0], false)
	check(peak > y0 + 0.8, "кнопка прыжка работает")
	# Тап по хотбару.
	var slot_rect: Rect2 = g.hud.hotbar.get_global_rect()
	touch(5, slot_rect.position + Vector2(g.hud.hotbar.slot_size * 4.5, slot_rect.size.y / 2.0), true)
	await frames(2)
	touch(5, Vector2.ZERO, false)
	check(p.inventory.selected == 4, "тап по хотбару выбирает слот")

	# Меню паузы и настройки.
	await key(KEY_ESCAPE)
	await frames(3)
	check(g.pause_menu.visible and get_tree().paused, "Esc открывает паузу")
	await shot("pause_menu")
	g.pause_menu.emit_signal("settings_requested")
	await frames(3)
	await shot("settings")
	g.settings_panel.call("close_panel")
	await frames(2)
	g.call("resume")
	await frames(3)
	check(not get_tree().paused, "игра продолжается после паузы")

	# Под водой.
	var water := _find_water(w, p.position)
	if water != Vector3i.ZERO:
		p.position = Vector3(water.x + 0.5, water.y - 1.5, water.z + 0.5)
		p.set_look(0.3, deg_to_rad(10.0))
		await frames(15)
		check(p.in_water, "игрок в воде")
		await shot("underwater")
		p.position = Vector3(water.x + 0.5, water.y + 6.0, water.z + 0.5)
		p.set_look(0.3, deg_to_rad(-30.0))
		g.call("set_creative", true)
		p.set_flying(true)
		await frames(15)
		await shot("water_surface")
		p.set_flying(false)
		g.call("set_creative", false)
	else:
		print("[WARN] вода рядом не найдена")

	# Телефон (широкий экран) и планшет.
	p.position = Vector3(arena) + Vector3(0.5, 1.001, 0.5)
	p.set_look(deg_to_rad(20.0), deg_to_rad(-10.0))
	Game.set_setting("touch_controls", 2)
	await frames(3)

	# Смерть и возрождение.
	p.take_damage(Player.MAX_HEALTH)
	await frames(5)
	check(p.dead, "игрок погибает при нулевом здоровье")
	await shot("death_screen")
	g.call("_respawn")
	await frames(5)
	check(not p.dead and p.health == Player.MAX_HEALTH, "возрождение")

	# --- Сохранение и загрузка ---
	g.call("set_creative", true)
	p.inventory.set_slot(8, Blocks.BOOKSHELF, 1)
	var saved_pos := p.position
	var house_block := w.get_block_v(base + Vector3i(0, 1, 0))
	var dug_block := w.get_block_v(dig_pos)
	g.call("quit_to_menu")
	await frames(10)
	check(game().name == "MainMenu", "выход в главное меню")
	Game.start_world(id)
	await frames(2)
	check(await wait_loaded(), "мир загружается повторно")
	await wait_world_idle()
	g = game()
	p = g.player
	w = g.world
	check(p.position.distance_to(saved_pos) < 0.5, "позиция игрока сохранилась")
	check(p.inventory.ids[8] == Blocks.BOOKSHELF, "инвентарь сохранился")
	check(w.get_block_v(base + Vector3i(0, 1, 0)) == house_block and house_block != Blocks.AIR, "постройка сохранилась")
	check(w.get_block_v(dig_pos) == dug_block, "выкопанный блок остался выкопанным")
	await frames(10)
	await shot("after_reload")

	# Дальняя прогулка: чанки выгружаются и сохраняются, при возврате изменения на месте.
	var far_target := Vector3(p.position.x + 16 * (w.render_distance + 5), 100, p.position.z)
	var marker := Vector3i(floori(p.position.x) + 1, w.top_solid_y(floori(p.position.x) + 1, floori(p.position.z)) + 1, floori(p.position.z))
	w.set_block(marker.x, marker.y, marker.z, Blocks.BRICKS)
	var home := p.position
	p.set_flying(true)
	p.position = far_target
	await wait_world_idle()
	check(not w.chunks.has(World.key_of(home)), "далёкие чанки выгружены")
	check(WorldStorage.load_chunk(w.save_dir, World.key_of(Vector3(marker))).size() == WorldGen.VOLUME, "изменённый чанк записан на диск при выгрузке")
	p.position = home
	await wait_world_idle()
	check(w.get_block_v(marker) == Blocks.BRICKS, "изменения на месте после возвращения")
	print("FPS в конце (программный рендер): ", Engine.get_frames_per_second())

	_finish(started)


## Ровная площадка 25×25 вокруг игрока: детерминированное место для проверок.
func _make_arena(w: World, p: Player) -> Vector3i:
	var c := Vector3i(floori(p.position.x), floori(p.position.y) - 1, floori(p.position.z))
	w.fill_region(c + Vector3i(-12, -3, -12), c + Vector3i(12, -1, 12), Blocks.DIRT)
	w.fill_region(c + Vector3i(-12, 0, -12), c + Vector3i(12, 0, 12), Blocks.GRASS)
	w.fill_region(c + Vector3i(-12, 1, -12), c + Vector3i(12, 14, 12), Blocks.AIR)
	p.position = Vector3(c) + Vector3(0.5, 1.001, 0.5)
	return c


## Снимок пещеры: ищем подземную пустоту рядом и смотрим на неё.
func _cave_shot(w: World, p: Player) -> void:
	var c := Vector3i(floori(p.position.x), 0, floori(p.position.z))
	for r in range(2, 60, 2):
		for dz in range(-r, r + 1, 2):
			for dx in range(-r, r + 1, 2):
				var x := c.x + dx
				var z := c.z + dz
				var top := w.top_solid_y(x, z)
				for y in range(8, top - 8):
					if w.get_block(x, y, z) == Blocks.AIR and w.get_block(x, y + 1, z) == Blocks.AIR \
							and w.get_block(x, y - 1, z) != Blocks.AIR and w.get_block(x + 3, y, z) == Blocks.AIR:
						p.set_flying(true)
						p.position = Vector3(x + 0.5, y + 0.001, z + 0.5)
						p.set_look(-PI / 2.0, deg_to_rad(-10.0))
						await frames(15)
						await shot("cave")
						p.set_flying(false)
						return
	print("[WARN] пещера рядом не найдена")


## Проверка вёрстки при текущем размере окна (запускается с --resolution).
func _run_layout() -> void:
	var tag := "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	for wd in WorldStorage.list_worlds():
		if str(wd.get("name", "")).begins_with(WORLD_NAME):
			WorldStorage.delete_world(wd["id"])
	await shot("menu_" + tag)
	var id := Game.create_world(WORLD_NAME + " (вёрстка)", false, "777")
	Game.set_setting("touch_controls", 1)
	Game.start_world(id)
	await frames(3)
	await shot("loading_" + tag)
	check(await wait_loaded(), "мир загрузился (%s)" % tag)
	var g := game()
	var p: Player = g.player
	p.inventory.add_item(Blocks.COBBLESTONE, 30)
	p.inventory.add_item(Blocks.PLANKS, 12)
	p.set_look(deg_to_rad(30.0), deg_to_rad(-12.0))
	await wait_world_idle(60.0)
	await frames(5)
	await shot("touch_hud_" + tag)
	# Тап по 3-му слоту хотбара — проверяем пересчёт координат касания.
	var hb: HotbarView = g.hud.hotbar
	var r := hb.get_global_rect()
	touch(0, r.position + Vector2(hb.slot_size * 2.5, r.size.y * 0.5), true)
	await frames(2)
	touch(0, r.position + Vector2(hb.slot_size * 2.5, r.size.y * 0.5), false)
	await frames(2)
	check(p.inventory.selected == 2, "тап по хотбару попадает в слот (%s)" % tag)
	# Кнопка паузы в углу.
	var pause_btn: Array = g.touch.get("_buttons")[TouchControls.R_PAUSE]
	touch(1, pause_btn[0], true)
	await frames(2)
	touch(1, pause_btn[0], false)
	await frames(3)
	check(g.pause_menu.visible, "кнопка паузы работает (%s)" % tag)
	await shot("pause_" + tag)
	g.call("resume")
	await frames(3)
	g.call("open_inventory")
	await frames(3)
	await shot("inventory_" + tag)
	g.inventory_ui.call("close_inventory")
	await frames(3)
	Game.set_setting("touch_controls", 0)
	g.call("quit_to_menu")
	await frames(5)
	_finish(Time.get_ticks_msec())


func _build_house(w: World, b: Vector3i) -> void:
	for y in range(0, 5):
		for z in range(0, 5):
			for x in range(0, 6):
				var edge_x := x == 0 or x == 5
				var edge_z := z == 0 or z == 4
				var id := Blocks.AIR
				if y == 0:
					id = Blocks.STONE_BRICKS
				elif y == 4:
					id = Blocks.PLANKS
				elif edge_x and edge_z:
					id = Blocks.LOG
				elif edge_x or edge_z:
					id = Blocks.BRICKS if y != 2 else Blocks.GLASS
					if z == 4 and x == 2 and y < 3:
						id = Blocks.AIR
				w.set_block(b.x + x, b.y + y, b.z + z, id)
	w.set_block(b.x + 4, b.y + 1, b.z + 1, Blocks.BOOKSHELF)
	for x in range(-1, 7):
		w.set_block(b.x + x, b.y + 5, b.z - 1, Blocks.LEAVES)
		w.set_block(b.x + x, b.y + 5, b.z + 5, Blocks.LEAVES)


func _find_water(w: World, around: Vector3) -> Vector3i:
	var best := Vector3i.ZERO
	var best_d := INF
	for z in range(-90, 91, 3):
		for x in range(-90, 91, 3):
			var wx := floori(around.x) + x
			var wz := floori(around.z) + z
			if w.get_block(wx, WorldGen.SEA_LEVEL, wz) == Blocks.WATER and w.get_block(wx, WorldGen.SEA_LEVEL - 3, wz) == Blocks.WATER:
				var d := Vector2(x, z).length()
				if d < best_d:
					best_d = d
					best = Vector3i(wx, WorldGen.SEA_LEVEL, wz)
	return best


func _finish(started: int) -> void:
	Game.set_setting("render_distance", 6)
	Game.set_setting("touch_controls", 0)
	Game.save_settings()
	var summary := "Визуальный тест: %d пройдено, %d провалено за %.0f с" % [_passed, _failed, (Time.get_ticks_msec() - started) / 1000.0]
	print(summary)
	_log.append(summary)
	var f := FileAccess.open(shots_dir.path_join("report.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log))
		f.close()
	for wd in WorldStorage.list_worlds():
		if str(wd.get("name", "")).begins_with(WORLD_NAME):
			WorldStorage.delete_world(wd["id"])
	get_tree().quit(1 if _failed > 0 else 0)
