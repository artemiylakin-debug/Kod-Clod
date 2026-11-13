extends Node
## Сценарий-автотест настроек мира 1.2 (тип «суперплоский», генерация построек) и полёта ока Края.
## Запуск: godot --path . --rendering-driver opengl3 -- --test-script=res://tests/options_visual.gd --shots=/путь

const WORLD_FLAT := "Автотест суперплоского"
const WORLD_EYE := "Автотест ока Края"

var shots_dir := "user://screenshots_options"
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


func _remove_worlds() -> void:
	for w in WorldStorage.list_worlds():
		var n := str(w.get("name", ""))
		if n.begins_with(WORLD_FLAT) or n.begins_with(WORLD_EYE):
			WorldStorage.delete_world(w["id"])


func _run() -> void:
	await frames(10)
	Game.set_setting("render_distance", 4)
	Game.set_setting("touch_controls", 2)
	_remove_worlds()

	# --- Форма нового мира ---
	var menu := game()
	menu.call("_show", "create")
	await frames(5)
	var wt: OptionButton = menu.get("_world_type")
	var sb: Button = menu.get("_structures_btn")
	check(wt != null and wt.item_count == 2 and wt.selected == 0, "выбор типа мира: обычный по умолчанию")
	check(sb != null and sb.button_pressed and sb.text == "Постройки: да", "генерация построек включена по умолчанию")
	wt.select(1)
	sb.button_pressed = false
	await frames(3)
	check(sb.text == "Постройки: нет", "переключатель построек меняет подпись")
	await shot("create_form_flat")
	var create_btn: Button = null
	for b in menu.find_children("*", "Button", true, false):
		if (b as Button).text == "Создать мир" and (b as Button).is_visible_in_tree():
			create_btn = b
	var inside := create_btn != null and get_viewport().get_visible_rect().encloses(create_btn.get_global_rect())
	check(inside, "кнопка «Создать мир» видна целиком")
	wt.select(0)
	sb.button_pressed = true

	# --- Суперплоский мир с деревнями ---
	var id := Game.create_world(WORLD_FLAT, true, "4242", 2, false, "flat", true)
	var meta := WorldStorage.load_meta(WorldStorage.world_dir(id))
	check(str(meta.get("world_type", "")) == "flat" and bool(meta.get("structures", false)), "тип мира сохранён в meta.json")
	Game.start_world(id)
	await frames(2)
	check(await wait_loaded(), "суперплоский мир загрузился")
	await wait_idle()
	var g := game()
	var p: Player = g.player
	var w: World = g.world
	check(w.generator is FlatGen, "генератор — суперплоский")
	check(is_equal_approx(p.position.y, 4.001) or p.position.y < 6.0, "игрок стоит на траве y=3 (y ног %.2f)" % p.position.y)
	var cell := Vector3i(floori(p.position.x) + 3, 0, floori(p.position.z) + 3)
	check(w.get_block(cell.x, 0, cell.z) == Blocks.BEDROCK and w.get_block(cell.x, 3, cell.z) == Blocks.GRASS
		and w.get_block(cell.x, 4, cell.z) == Blocks.AIR, "слои мира: коренная порода … трава на y=3")
	p.set_look(deg_to_rad(20.0), deg_to_rad(-12.0))
	await frames(10)
	await shot("flat_spawn")
	# Летим к ближайшей деревне.
	var village := Vector2i(1 << 30, 0)
	var best := INF
	for rz in range(-2, 3):
		for rx in range(-2, 3):
			var v: Vector2i = w.generator.call("village_center", rx, rz)
			if v.x != 1 << 30 and Vector2(v).length() < best:
				best = Vector2(v).length()
				village = v
	check(village.x != 1 << 30, "в суперплоском мире есть деревня (%s)" % str(village))
	if village.x != 1 << 30:
		p.position = Vector3(village.x + 0.5, 30.0, village.y + 22.5)
		p.flying = true
		p.velocity = Vector3.ZERO
		await frames(5)
		await wait_idle()
		await frames(30)
		p.set_look(0.0, deg_to_rad(-45.0))
		await frames(10)
		var doors := 0
		for dz in range(-40, 41):
			for dx in range(-40, 41):
				for y in range(4, 7):
					if w.get_block(village.x + dx, y, village.y + dz) == Blocks.WOODEN_DOOR:
						doors += 1
		check(doors >= 4, "дома деревни стоят на земле (%d блоков дверей на y=4…6)" % doors)
		await shot("flat_village")
	g.call("save_game")
	Game.goto_main_menu()
	await frames(10)

	# --- Око Края в обычном мире ---
	var id2 := Game.create_world(WORLD_EYE, false, "4242")
	Game.start_world(id2)
	await frames(2)
	check(await wait_loaded(), "обычный мир загрузился")
	await wait_idle()
	g = game()
	p = g.player
	w = g.world
	await wait(2.0)
	check(g.logic.springs_started > 0, "родники в пещерах потекли (%d)" % g.logic.springs_started)
	var target: Vector3 = g.call("nearest_stronghold", p.position)
	check(target != Vector3.INF, "ближайшая крепость известна (%s)" % str(target))
	p.inventory.set_slot(p.inventory.selected, Items.ENDER_EYE, 2)
	p.set_look(0.0, 0.0)
	var hp := p.health
	var start := p.position
	var used: bool = g.actions.call("_use_item", p, Items.ENDER_EYE, 0, {})
	check(used and p.inventory.counts[p.inventory.selected] == 1, "око брошено и потрачено")
	var eye: Node3D = null
	for n in g.entities.get_children():
		if n is SimpleEntities.EnderEye:
			eye = n
	check(eye != null, "в мире летит око Края")
	if eye != null:
		var to_target := Vector2(target.x - start.x, target.z - start.z).normalized()
		p.set_look(atan2(-to_target.x, -to_target.y), deg_to_rad(15.0))
		await wait(1.2)
		await shot("ender_eye_flight")
		var moved := Vector2(eye.position.x - start.x, eye.position.z - start.z)
		check(moved.length() > 4.0 and moved.normalized().dot(to_target) > 0.9,
			"око летит в сторону крепости (%.1f блока, cos=%.2f)" % [moved.length(), moved.normalized().dot(to_target)])
		check(eye.position.y > start.y + 2.0, "око поднимается")
		await wait(3.5)
		check(not is_instance_valid(eye) or eye.is_queued_for_deletion(), "через 4 с око исчезло (упало или разбилось)")
	check(p.health == hp and p.position.distance_to(start) < 0.5, "бросок ока не телепортирует и не ранит игрока")

	# --- Достижения: всплывающее окно и экран в меню паузы ---
	var saved_path := Achievements.path
	Achievements.path = "user://test_stats_visual.json"
	Achievements.reset()
	Achievements.add_stat("walk", 4321.0)
	Achievements.add_stat("blocks_mined", 57.0)
	g.call("open_inventory")
	await frames(3)
	check(Achievements.has("open_inventory"), "открыт инвентарь — «Инвентаризация»")
	g.inventory_ui.close_ui()
	p.set_look(deg_to_rad(40.0), deg_to_rad(5.0))
	await frames(20)
	var popup: Control = g.hud.get("_ach")
	check(popup != null and popup.visible, "всплывающее «Достижение получено!»")
	await shot("achievement_popup")
	Achievements.on_pickup(Blocks.LOG)
	Achievements.on_crafted(Blocks.CRAFTING_TABLE)
	g.call("open_pause")
	await frames(5)
	g.pause_menu.emit_signal("achievements_requested")
	await frames(10)
	check(g.achievements_panel.visible, "экран достижений открыт из меню паузы")
	await shot("achievements_screen")
	g.achievements_panel.call("_show", true)
	await frames(10)
	await shot("statistics_screen")
	g.achievements_panel.close_panel()
	await frames(3)
	check(g.pause_menu.visible, "после закрытия — снова меню паузы")
	g.call("resume")
	Achievements.path = saved_path
	Achievements.reset(true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_stats_visual.json"))
	g.call("save_game")
	_remove_worlds()
	var report := "\n".join(_log) + "\n\nИтог: %d пройдено, %d провалено\n" % [_passed, _failed]
	var f := FileAccess.open(shots_dir.path_join("report.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string(report)
	print("\n==== Настройки мира и око Края: %d пройдено, %d провалено ====" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
