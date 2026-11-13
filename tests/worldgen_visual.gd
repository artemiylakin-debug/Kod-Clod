extends Node
## Сценарий-облёт генератора мира 1.2: разные биомы, деревня, комната портала в крепости,
## Нижний мир и Край. Запуск:
##   godot --path . --rendering-driver opengl3 -- --test-script=res://tests/worldgen_visual.gd --shots=/путь

const WORLD_NAME := "Автотест генератора"

var shots_dir := "user://screenshots_worldgen"
var _passed := 0
var _failed := 0
var _shot_index := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
	DirAccess.make_dir_recursive_absolute(shots_dir)
	_run()


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
	print(("[OK]   " if cond else "[FAIL] ") + what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	_shot_index += 1
	var path := shots_dir.path_join("%02d_%s.png" % [_shot_index, shot_name])
	get_viewport().get_texture().get_image().save_png(path)
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
		if (g.world as World).is_streaming_idle(g.player.position):
			return
		await wait(0.25)
		t += 0.25


## Перелёт в точку (x, z) на высоте над рельефом и снимок.
func fly_to(x: int, z: int, label: String, height := 18.0, pitch := -22.0, yaw := 30.0) -> void:
	var g := game()
	var p: Player = g.player
	var gen: Object = (g.world as World).generator
	var h: int = gen.call("get_height", x, z)
	p.set_flying(true)
	p.position = Vector3(x + 0.5, maxf(h, WorldGen.SEA_LEVEL) + height, z + 0.5)
	p.set_look(deg_to_rad(yaw), deg_to_rad(pitch))
	await frames(3)
	await wait_idle()
	await frames(8)
	await shot(label)


## Ближайшая к началу координат точка с биомом b (поиск по спирали с шагом 32 блока).
func find_biome(gen: Object, b: int, max_r := 2400) -> Vector2i:
	for r in range(0, max_r, 32):
		for k in maxi(1, r / 8):
			var a := TAU * k / maxf(1.0, r / 8.0)
			var x := int(cos(a) * r)
			var z := int(sin(a) * r)
			if int(gen.call("biome_at", x, z)) == b and int(gen.call("biome_at", x + 24, z)) == b \
					and int(gen.call("biome_at", x, z + 24)) == b:
				return Vector2i(x, z)
	return Vector2i(1 << 30, 0)


func _run() -> void:
	await frames(10)
	Game.set_setting("render_distance", 5)
	Game.set_setting("touch_controls", 2)
	for w in WorldStorage.list_worlds():
		if str(w.get("name", "")).begins_with(WORLD_NAME):
			WorldStorage.delete_world(w["id"])
	var id := Game.create_world(WORLD_NAME, true, "12345")
	Game.start_world(id)
	await frames(2)
	check(await wait_loaded(), "мир загрузился")
	await wait_idle()
	var g := game()
	var p: Player = g.player
	var gen: Object = (g.world as World).generator
	await frames(10)
	await shot("spawn")
	var sp := Vector2i(floori(p.position.x), floori(p.position.z))
	await fly_to(sp.x, sp.y, "spawn_above", 30.0, -30.0)
	# Биомы.
	var biomes := [[Biomes.JUNGLE, "jungle"], [Biomes.DESERT, "desert"], [Biomes.TAIGA, "taiga"],
		[Biomes.ICE_PLAINS, "ice_plains"], [Biomes.EXTREME_HILLS, "extreme_hills"], [Biomes.SWAMPLAND, "swamp"],
		[Biomes.FOREST, "forest"], [Biomes.MUSHROOM_ISLAND, "mushroom_island"], [Biomes.PLAINS, "plains"]]
	for bi: Array in biomes:
		var at := find_biome(gen, int(bi[0]))
		if at.x == 1 << 30:
			print("[WARN] биом не найден: ", bi[1])
			continue
		await fly_to(at.x, at.y, str(bi[1]))
	# Деревня.
	var village := Vector2i(1 << 30, 0)
	for rz in range(-3, 4):
		for rx in range(-3, 4):
			var c: Vector2i = gen.call("village_center", rx, rz)
			if c.x != 1 << 30 and (village.x == 1 << 30 or c.length() < village.length()):
				village = c
	check(village.x != 1 << 30, "деревня найдена (%s)" % str(village))
	if village.x != 1 << 30:
		await fly_to(village.x, village.y, "village", 22.0, -40.0)
		await fly_to(village.x + 6, village.y + 6, "village_close", 6.0, -20.0, 200.0)
	# Крепость: ищем рамки портала рядом с её центром.
	var strongholds: Array = gen.call("stronghold_positions")
	check(strongholds.size() == 3, "три крепости (%d)" % strongholds.size())
	if not strongholds.is_empty():
		var s: Vector2i = strongholds[0]
		p.set_flying(true)
		p.position = Vector3(s.x, 40, s.y)
		await frames(3)
		await wait_idle()
		var w: World = g.world
		var frame := Vector3i(0, -1, 0)
		for dz in range(-80, 81):
			for dx in range(-80, 81):
				var x := s.x + dx
				var z := s.y + dz
				if not w.has_chunk_at(x, z):
					continue
				for y in range(6, 60):
					if w.get_block(x, y, z) == Blocks.END_PORTAL_FRAME:
						frame = Vector3i(x, y, z)
						break
				if frame.y >= 0:
					break
			if frame.y >= 0:
				break
		check(frame.y >= 0, "в крепости есть рамка портала (%s)" % str(frame))
		if frame.y >= 0:
			p.position = Vector3(frame) + Vector3(0.5, 2.5, -4.5)
			p.set_look(PI, deg_to_rad(-30.0))
			g.set("time_of_day", 0.25)
			await frames(15)
			await shot("stronghold_portal_room")
	_finish()


func _finish() -> void:
	print("Облёт генератора: %d пройдено, %d провалено" % [_passed, _failed])
	Game.set_setting("render_distance", 6)
	Game.set_setting("touch_controls", 0)
	Game.save_settings()
	if game() != null and game().has_method("quit_to_menu"):
		game().call("quit_to_menu")
		await frames(5)
	for wd in WorldStorage.list_worlds():
		if str(wd.get("name", "")).begins_with(WORLD_NAME):
			WorldStorage.delete_world(wd["id"])
	get_tree().quit(1 if _failed > 0 else 0)
