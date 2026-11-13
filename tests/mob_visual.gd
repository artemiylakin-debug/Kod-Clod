extends Node
## Визуальный сценарий существ: выстраивает всех мобов 1.2 на площадке и снимает скриншоты
## (день, ночь с факелами, крупные планы, вид сбоку и сзади, ходьба, бой, гаст, дракон).
## Запуск (нужен видеовывод, например Xvfb):
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 -- \
##     --test-script=res://tests/mob_visual.gd --shots=/абсолютный/путь

const WORLD_NAME := "Мобы (сценарий)"

var shots_dir := "user://mob_shots"
var _shot_index := 0
var _only := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a.begins_with("--only="):
			_only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(shots_dir)
	_run()


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


func _run() -> void:
	await frames(10)
	Game.set_setting("render_distance", 5)
	for w in WorldStorage.list_worlds():
		if str(w.get("name", "")).begins_with(WORLD_NAME):
			WorldStorage.delete_world(w["id"])
	var id := Game.create_world(WORLD_NAME, true, "12345")
	Game.start_world(id)
	await frames(2)
	if not await wait_loaded():
		print("[FAIL] мир не загрузился")
		get_tree().quit(1)
		return
	var g := game()
	var p: Player = g.player
	var w: World = g.world
	var ent: EntityManager = g.entities
	var ms := ent.mobs as MobSystem
	ms.natural_spawning = false
	ms.ai_enabled = false
	for m in ms.mobs.duplicate():
		ms.remove_mob(m)
	await wait_world_idle()
	g.set("time_of_day", 0.25)
	var base := _make_arena(w, p)
	await frames(10)
	p.set_flying(true)

	# --- Строй: монстры ---
	var hostiles := [[MobDefs.CREEPER, 1.6], [MobDefs.ZOMBIE, 1.6], [MobDefs.SKELETON, 1.6], [MobDefs.PIG_ZOMBIE, 1.6],
		[MobDefs.ENDERMAN, 1.8], [MobDefs.BLAZE, 1.8]]
	var row1 := _row(ms, base + Vector3(-5, 0, 0), hostiles)
	(row1[4] as HostileMobs.Enderman).carried = Blocks.GRASS
	(row1[4] as HostileMobs.Enderman)._update_carry_mesh()
	await _view(p, base + Vector3(-1.0, 1.4, 6.5), base + Vector3(-1.0, 1.1, 0), "hostiles_front")
	var row2 := _row(ms, base + Vector3(-6, 0, -6), [[MobDefs.SPIDER, 2.4], [MobDefs.CAVE_SPIDER, 2.0], [MobDefs.SLIME, 2.2],
		[MobDefs.MAGMA_CUBE, 2.2], [MobDefs.SILVERFISH, 1.6], [MobDefs.SLIME, 1.4]])
	(row2[2] as HostileMobs.Slime).set_size(2)
	(row2[3] as HostileMobs.Slime).set_size(2)
	(row2[5] as HostileMobs.Slime).set_size(1)
	await _view(p, base + Vector3(-1.0, 1.6, 0.0), base + Vector3(-1.0, 0.4, -6), "hostiles2_front")

	# --- Животные ---
	var a := _row(ms, base + Vector3(-6, 0, -12), [[MobDefs.PIG, 1.6], [MobDefs.SHEEP, 1.6], [MobDefs.SHEEP, 1.6],
		[MobDefs.SHEEP, 1.6], [MobDefs.COW, 1.8], [MobDefs.MOOSHROOM, 1.8], [MobDefs.CHICKEN, 1.4]])
	(a[0] as PassiveMobs.Pig).saddled = true
	(a[0] as PassiveMobs.Pig).model.set_skin(0, MobSkins.get_skin("pig_saddle"))
	(a[1] as PassiveMobs.Sheep).color = 0
	(a[2] as PassiveMobs.Sheep).color = 6
	(a[3] as PassiveMobs.Sheep).sheared = true
	for i in [1, 2, 3]:
		(a[i] as PassiveMobs.Sheep)._update_wool()
	await _view(p, base + Vector3(-1.0, 1.6, -5.8), base + Vector3(-1.0, 0.6, -12), "animals_front")
	var pets := _row(ms, base + Vector3(-6, 0, -18), [[MobDefs.WOLF, 1.4], [MobDefs.WOLF, 1.4], [MobDefs.WOLF, 1.4],
		[MobDefs.OCELOT, 1.4], [MobDefs.OCELOT, 1.4], [MobDefs.OCELOT, 1.4], [MobDefs.OCELOT, 1.4]])
	var tame := pets[1] as PassiveMobs.Wolf
	tame.tamed = true
	tame.on_tamed()
	tame.sitting = true
	var angry := pets[2] as PassiveMobs.Wolf
	angry.angry = 30.0
	angry._refresh_skin()
	for i in 3:
		var cat := pets[4 + i] as PassiveMobs.Ocelot
		cat.skin = i + 1
		cat.tamed = true
		cat.on_tamed()
		cat.sitting = i == 1
	await _view(p, base + Vector3(-1.5, 1.3, -14.0), base + Vector3(-1.5, 0.4, -18), "pets_front")

	# --- Жители, големы, кристалл, детёныши ---
	var v := _row(ms, base + Vector3(-7, 0, -24), [[MobDefs.VILLAGER, 1.5], [MobDefs.VILLAGER, 1.5], [MobDefs.VILLAGER, 1.5],
		[MobDefs.VILLAGER, 1.5], [MobDefs.VILLAGER, 1.8], [MobDefs.IRON_GOLEM, 2.2], [MobDefs.SNOW_GOLEM, 2.2], [MobDefs.END_CRYSTAL, 2.0]])
	for i in 5:
		(v[i] as PassiveMobs.Villager).load_extra({"prof": i})
	var golem := v[5] as PassiveMobs.IronGolem
	golem._rose = 100000
	golem._show_rose(true)
	await _view(p, base + Vector3(-0.5, 2.0, -16.5), base + Vector3(-0.5, 1.2, -24), "villagers_golems_front")
	var babies := _row(ms, base + Vector3(-4, 0, -29), [[MobDefs.PIG, 1.4], [MobDefs.COW, 1.4], [MobDefs.SHEEP, 1.4],
		[MobDefs.CHICKEN, 1.2], [MobDefs.WOLF, 1.2], [MobDefs.VILLAGER, 1.4]], true)
	await _view(p, base + Vector3(-1.0, 1.2, -25.5), base + Vector3(-1.0, 0.3, -29), "babies_front")
	if babies.is_empty():
		print("[WARN] нет детёнышей")

	# --- Вид сзади и сбоку (проверка развёрток) ---
	await _view(p, base + Vector3(-1.0, 1.6, -5.0), base + Vector3(-1.0, 1.0, 0), "hostiles_back")
	for m in row1 + a:
		_face(m, PI * 0.5)
	await _view(p, base + Vector3(-1.0, 1.6, 6.5), base + Vector3(-1.0, 1.1, 0), "hostiles_side")
	await _view(p, base + Vector3(-1.0, 1.6, -6.0), base + Vector3(-1.0, 0.6, -12), "animals_side")
	for m in row1 + a:
		_face(m, 0.0)
	await _view(p, base + Vector3(-1.0, 4.0, 4.0), base + Vector3(-1.0, 0.0, -2), "from_above")

	# --- Крупные планы ---
	await _view(p, row1[0].position + Vector3(0.0, 1.4, 1.6), row1[0].position + Vector3(0, 1.3, 0), "closeup_creeper")
	await _view(p, row1[4].position + Vector3(0.0, 2.6, 1.6), row1[4].position + Vector3(0, 2.5, 0), "closeup_enderman")
	await _view(p, row2[0].position + Vector3(0.0, 0.8, 1.8), row2[0].position + Vector3(0, 0.5, 0), "closeup_spider")
	await _view(p, v[0].position + Vector3(0.0, 1.7, 1.4), v[0].position + Vector3(0, 1.6, 0), "closeup_villager")
	await _view(p, golem.position + Vector3(0.0, 2.4, 3.2), golem.position + Vector3(0, 1.6, 0), "closeup_iron_golem")

	# --- Ночь с факелами ---
	for x in range(-8, 10, 3):
		for z in [3, -3, -9, -15, -21, -27]:
			var c := Vector3i(floori(base.x) + x, floori(base.y), floori(base.z) + z)
			w.set_block(c.x, c.y, c.z, Blocks.TORCH, 5)
	w.flush_remesh()
	g.set("time_of_day", 0.75)
	await frames(10)
	await _view(p, base + Vector3(-1.0, 1.4, 6.5), base + Vector3(-1.0, 1.1, 0), "night_hostiles")
	await _view(p, base + Vector3(-1.0, 1.6, -5.8), base + Vector3(-1.0, 0.6, -12), "night_animals")
	await _view(p, base + Vector3(-1.0, 7.0, 10.0), base + Vector3(-1.0, 0.0, -14), "night_lineup")
	await _view(p, row2[0].position + Vector3(0.0, 0.8, 1.8), row2[0].position + Vector3(0, 0.5, 0), "night_spider_eyes")
	g.set("time_of_day", 0.25)
	await frames(5)

	# --- Ходьба (ИИ включён) ---
	ms.ai_enabled = true
	g.set("difficulty", 0)
	for m in ms.mobs.duplicate():
		if MobDefs.category(m.type) == MobDefs.CAT_MONSTER:
			ms.remove_mob(m)
	g.set("difficulty", 2)
	for m in a:
		if is_instance_valid(m):
			m.wander_target = m.position + Vector3(6, 0, 1)
	await wait(1.2)
	await _view(p, base + Vector3(2.0, 1.6, -6.0), base + Vector3(2.0, 0.6, -12), "animals_walking", 1)
	await wait(0.4)
	await _view(p, base + Vector3(3.0, 1.6, -6.0), base + Vector3(3.0, 0.6, -12), "animals_walking2", 1)

	# --- Бой: зомби, скелет и крипер против игрока; голем и волки помогают ---
	g.call("set_creative", false)
	p.set_flying(false)
	var arena := base + Vector3(0, 0, 14)
	p.position = arena
	p.set_look(0.0, deg_to_rad(-5.0))
	var golem2 := ms.spawn(MobDefs.IRON_GOLEM, arena + Vector3(-3, 0, -2)) as Mob
	var z1 := ms.spawn(MobDefs.ZOMBIE, arena + Vector3(-1.5, 0, -6)) as Mob
	ms.spawn(MobDefs.ZOMBIE, arena + Vector3(1.5, 0, -7))
	ms.spawn(MobDefs.SKELETON, arena + Vector3(4, 0, -9))
	var wolf := ms.spawn(MobDefs.WOLF, arena + Vector3(2, 0, -1)) as PassiveMobs.Wolf
	wolf.tamed = true
	wolf.on_tamed()
	var cr := ms.spawn(MobDefs.CREEPER, arena + Vector3(0.5, 0, -4)) as HostileMobs.Creeper
	cr.fuse = 1.0
	await wait(1.0)
	p.health = Player.MAX_HEALTH
	await _view(p, arena + Vector3(0, 1.6, 2), arena + Vector3(0, 1.0, -6), "fight_1", 2)
	await wait(1.5)
	p.health = Player.MAX_HEALTH
	await _view(p, arena + Vector3(0, 1.6, 2), arena + Vector3(0, 1.0, -6), "fight_2", 2)
	if is_instance_valid(z1) and is_instance_valid(golem2):
		print("[INFO] зомби: %d hp, голем: %d hp" % [z1.health, golem2.health])
	g.call("set_creative", true)
	p.set_flying(true)

	# --- Гаст и дракон ---
	ms.ai_enabled = false
	var gh := ms.spawn(MobDefs.GHAST, base + Vector3(10, 4, -8)) as Mob
	_face(gh, -PI * 0.5)
	await _view(p, base + Vector3(2.0, 6.0, -4.0), gh.center(), "ghast")
	gh.set("_attack", 15)
	gh.call("ai_tick")
	await _view(p, base + Vector3(2.0, 6.0, -4.0), gh.center(), "ghast_firing")
	ms.remove_mob(gh)
	var dragon := ms.spawn(MobDefs.ENDER_DRAGON, base + Vector3(0, 12, -40)) as Mob
	_face(dragon, PI * 0.75)
	await _view(p, base + Vector3(14.0, 16.0, -24.0), dragon.center(), "dragon")
	_face(dragon, -PI * 0.5)
	await _view(p, base + Vector3(0.0, 13.0, -22.0), dragon.center(), "dragon_side")
	g.set("time_of_day", 0.75)
	await frames(5)
	await _view(p, base + Vector3(0.0, 13.0, -22.0), dragon.center(), "dragon_night")
	ms.remove_mob(dragon)

	print("Сценарий мобов: %d снимков" % _shot_index)
	for wd in WorldStorage.list_worlds():
		if str(wd.get("name", "")).begins_with(WORLD_NAME):
			WorldStorage.delete_world(wd["id"])
	get_tree().quit(0)


## Ровная площадка с травой вокруг игрока.
func _make_arena(w: World, p: Player) -> Vector3:
	var c := Vector3i(floori(p.position.x), floori(p.position.y) - 1, floori(p.position.z))
	w.fill_region(c + Vector3i(-16, -3, -36), c + Vector3i(16, -1, 20), Blocks.DIRT)
	w.fill_region(c + Vector3i(-16, 0, -36), c + Vector3i(16, 0, 20), Blocks.GRASS)
	w.fill_region(c + Vector3i(-16, 1, -36), c + Vector3i(16, 24, 20), Blocks.AIR)
	w.flush_remesh()
	return Vector3(c.x + 0.5, c.y + 1.0, c.z + 0.5)


## Ряд существ слева направо (по +X), мордой к +Z (к камере).
func _row(ms: MobSystem, start: Vector3, list: Array, baby := false) -> Array:
	var out := []
	var x := 0.0
	for e: Array in list:
		var m := ms.spawn(int(e[0]), start + Vector3(x, 0, 0), baby) as Mob
		if m != null:
			_face(m, 0.0)
			out.append(m)
		x += float(e[1])
	return out


func _face(m: Mob, yaw: float) -> void:
	m.yaw = yaw
	m.prev_yaw = yaw
	m.head_yaw = yaw
	m.prev_head_yaw = yaw


func _view(p: Player, eye: Vector3, at: Vector3, shot_name: String, settle := 6) -> void:
	if _only != "" and not shot_name.contains(_only):
		return
	p.position = eye - Vector3(0, Player.EYE_HEIGHT, 0)
	p.velocity = Vector3.ZERO
	var d := at - eye
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	await frames(settle)
	await shot(shot_name)
