extends SceneTree
## Тесты существ (без рендеринга): появление всех видов, ИИ, бой, разведение, приручение,
## стрижка, дойка, сохранение, рассадники, естественное появление, дракон, производительность.
## Запуск: godot --headless --path . -s res://tests/mob_tests.gd

var _failed := 0
var _passed := 0


## Заглушка игровой сцены.
class FakeGame extends Node:
	var entities: EntityManager
	var difficulty := 2
	var sky_level := 15
	var night := false
	var dragon_killed := false
	var meta: Dictionary = {}
	var toasts: Array[String] = []
	var sounds: Array[String] = []
	var effects: Array[String] = []

	func spawn_drop(id: int, count: int, data: int, pos: Vector3, vel := Vector3.INF, delay := 0.0) -> ItemDrop:
		return entities.spawn_drop(id, count, data, pos, vel, delay)

	func open_container(_kind: String, _p: Vector3i) -> void:
		pass

	func show_toast(text: String, _d := 2.5) -> void:
		toasts.append(text)

	func explosion_damage(center: Vector3, power: float, source: Node) -> void:
		entities.explosion_damage(center, power, source)

	func sky_light_level() -> int:
		return sky_level

	func is_night() -> bool:
		return night

	func play_sound(n: String, _pos: Vector3, _vol := 1.0, _pitch := 1.0) -> void:
		sounds.append(n)

	func effect(kind: String, _pos: Vector3, _data := 0) -> void:
		effects.append(kind)


func _initialize() -> void:
	_run()


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("  [OK]   ", what)
	else:
		_failed += 1
		print("  [FAIL] ", what)


func _run() -> void:
	var game: Node = load("res://scripts/globals/game.gd").new()
	game.call("_setup_input_map")
	game.free()
	TextureFactory.ensure_initialized()
	await _test_all_types()
	await _test_hostiles()
	await _test_animals()
	await _test_pets()
	await _test_misc()
	await _test_saving()
	await _test_spawning()
	await _test_dragon()
	await _test_performance()
	print("\n==== Существа: %d пройдено, %d провалено ====" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --- Мир ------------------------------------------------------------------------

## Плоский мир 5×5 чанков: камень до y=9, трава на y=10.
func _make_world() -> World:
	var w := World.new()
	w.setup(7, "", 2)
	root.add_child(w)
	for cz in range(-2, 3):
		for cx in range(-2, 3):
			var ch := Chunk.new()
			ch.key = Vector2i(cx, cz)
			ch.blocks.resize(WorldGen.VOLUME)
			ch.meta.resize(WorldGen.VOLUME)
			for y in 11:
				for i in WorldGen.LAYER:
					ch.blocks[y * WorldGen.LAYER + i] = Blocks.GRASS if y == 10 else (Blocks.DIRT if y > 7 else Blocks.STONE)
			ch.biomes.resize(WorldGen.LAYER)
			ch.biomes.fill(Biomes.PLAINS)
			ch.top_y = 10
			ch.light = ChunkLight.compute(ch.blocks)
			ch.heightmap = Chunk.compute_heightmap(ch.blocks, ch.top_y)
			ch.applied_gen = 1
			w.chunks[ch.key] = ch
	return w


class Ctx:
	var w: World
	var g: FakeGame
	var logic: BlockLogic
	var ent: EntityManager
	var p: Player
	var mobs: MobSystem


func _make_ctx(creative := false) -> Ctx:
	var c := Ctx.new()
	c.w = _make_world()
	c.g = FakeGame.new()
	root.add_child(c.g)
	c.logic = BlockLogic.new()
	c.logic.name = "Logic"
	c.g.add_child(c.logic)
	c.logic.setup(c.w, c.g)
	c.logic.set_process(false)
	c.ent = EntityManager.new()
	c.g.add_child(c.ent)
	c.g.entities = c.ent
	c.p = Player.new()
	c.p.world = c.w
	c.p.creative = creative
	root.add_child(c.p)
	c.p.actions = PlayerActions.new(c.g, c.w, c.logic, c.ent)
	c.ent.setup(c.w, c.logic, c.p, c.g)
	c.mobs = c.ent.mobs as MobSystem
	# Случайные существа не должны мешать проверкам (появление проверяется отдельно, вызовами напрямую).
	c.mobs.natural_spawning = false
	await process_frame
	c.p.frozen = false
	c.p.position = Vector3(0.5, 11.0, 0.5)
	return c


func _free_ctx(c: Ctx) -> void:
	c.p.queue_free()
	c.g.queue_free()
	c.w.queue_free()
	await process_frame


## Обновить существ на sec секунд (по 1/20 с).
func _run_mobs(c: Ctx, sec: float, with_player := false) -> void:
	var n := int(sec * 20.0)
	for i in n:
		c.ent.update(0.05)
		if with_player:
			c.p._process(0.05)


## Игрок снова жив и здоров (в тестах его кадры не обновляются, поэтому сбрасываем вручную).
func _reset_player(c: Ctx) -> void:
	c.p.dead = false
	c.p.health = Player.MAX_HEALTH
	c.p.fire_time = 0.0
	c.p.velocity = Vector3.ZERO
	c.p.clear_effects()
	c.p.set("_invulnerable", 0.0)


func _drops(c: Ctx, id: int) -> int:
	var n := 0
	for ch in c.ent.get_children():
		if ch is ItemDrop and (ch as ItemDrop).item_id == id and not ch.is_queued_for_deletion():
			n += (ch as ItemDrop).count
	return n


func _clear_drops(c: Ctx) -> void:
	for ch in c.ent.get_children():
		if ch is ItemDrop or ch is SimpleEntities.XpOrb:
			ch.free()


func _xp(c: Ctx) -> int:
	var n := 0
	for ch in c.ent.get_children():
		if ch is SimpleEntities.XpOrb:
			n += (ch as SimpleEntities.XpOrb).amount
	return n


## Направить взгляд игрока на точку.
func _look(p: Player, at: Vector3) -> void:
	var d := at - p.eye_position()
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


# --- Тесты ---------------------------------------------------------------------------

func _test_all_types() -> void:
	print("Все виды существ")
	var c := await _make_ctx(true)
	check(c.mobs != null, "MobSystem подключён к EntityManager")
	var types := [50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 120, 200]
	var ok := true
	var models_ok := true
	var spawned: Array = []
	for i in types.size():
		var t: int = types[i]
		var m := c.ent.spawn_mob(t, Vector3(-30.5 + (i % 9) * 7.0, 11.0, -30.5 + int(i / 9.0) * 12.0))
		if m == null:
			ok = false
			print("    не создан: ", t)
			continue
		spawned.append(m)
		var mob := m as Mob
		if mob.model == null or mob.model.parts.is_empty() or mob.model.materials.is_empty():
			models_ok = false
			print("    нет модели: ", t)
	check(ok, "созданы все %d видов (50–63, 90–99, 120, 200)" % types.size())
	check(models_ok, "у каждого вида есть модель из частей и материал")
	_run_mobs(c, 3.0)
	var alive := 0
	for m in spawned:
		if is_instance_valid(m) and not (m as Mob).removed:
			alive += 1
	check(alive >= types.size() - 3, "существа живут 3 с без ошибок (%d/%d)" % [alive, types.size()])
	# Модели стоят на земле: нижняя точка модели около ног.
	var floating := []
	for m in spawned:
		if not is_instance_valid(m):
			continue
		var mob := m as Mob
		if mob.has_flag(MobDefs.F_FLYING) or mob.type in [MobDefs.SQUID, MobDefs.BLAZE, MobDefs.END_CRYSTAL]:
			continue
		var g := mob.model.ground
		if absf(g) > 0.3 and mob.type != MobDefs.GIANT:
			floating.append([mob.type, g])
	check(floating.is_empty(), "модели наземных существ поставлены на землю %s" % [floating])
	# Минимальные словари из генератора мира.
	for t: int in [120, 90, 91, 92, 93, 94, 95, 96, 98, 200]:
		c.mobs.restore({"kind": "mob", "type": t, "pos": [5.5, 11.0, 5.5]})
	var restored := 0
	for m in c.mobs.mobs:
		if m.position.distance_to(Vector3(5.5, 11, 5.5)) < 0.5:
			restored += 1
	check(restored == 10, "минимальные словари {kind, type, pos} восстанавливаются (%d/10)" % restored)
	var v := c.mobs.restore({"kind": "mob", "type": 120, "pos": [6.5, 11.0, 6.5], "prof": 3}) as PassiveMobs.Villager
	check(v != null and v.profession == 3, "житель восстанавливается с профессией")
	check(c.mobs.restore({"kind": "mob", "type": 999, "pos": [0, 11, 0]}) == null, "неизвестный вид игнорируется")
	await _free_ctx(c)


func _test_hostiles() -> void:
	print("Монстры")
	var c := await _make_ctx(false)
	c.g.night = true
	c.g.sky_level = 4
	# Зомби догоняет и бьёт игрока.
	var z := c.ent.spawn_mob(MobDefs.ZOMBIE, Vector3(8.5, 11.0, 0.5)) as Mob
	var hp := c.p.health
	_run_mobs(c, 6.0)
	check(z.position.distance_to(c.p.position) < 2.0, "зомби подходит к игроку (%.1f)" % z.position.distance_to(c.p.position))
	check(c.p.health < hp, "зомби бьёт игрока (здоровье %d → %d)" % [hp, c.p.health])
	# Обход стены: стена между зомби и игроком.
	_reset_player(c)
	for y in range(11, 14):
		for zz in range(-3, 4):
			c.w.set_block(4, y, zz, Blocks.STONE)
	z.position = Vector3(8.5, 11.0, 0.5)
	z.velocity = Vector3.ZERO
	_run_mobs(c, 12.0)
	check(z.position.x < 4.0, "зомби обходит стену (x=%.1f)" % z.position.x)
	c.w.fill_region(Vector3i(4, 11, -3), Vector3i(4, 13, 3), Blocks.AIR)
	# Удар игрока: отбрасывание, неуязвимость 0,5 с.
	_reset_player(c)
	z.position = Vector3(2.5, 11.0, 0.5)
	z.velocity = Vector3.ZERO
	var zhp := z.health
	c.mobs.player_attack(z, 5)
	c.mobs.player_attack(z, 5)
	check(z.health == zhp - 5, "неуязвимость после удара (%d → %d)" % [zhp, z.health])
	check(z.velocity.x > 2.0 and z.velocity.y > 0.0, "отбрасывание от игрока")
	# Смерть: гнилая плоть и опыт.
	_clear_drops(c)
	for i in 6:
		z.invuln = 0.0
		c.mobs.player_attack(z, 10)
	check(z.is_dead(), "зомби убит")
	check(_xp(c) == 5, "опыт за зомби: %d" % _xp(c))
	_run_mobs(c, 1.2)
	check(not is_instance_valid(z) or z.removed, "тело исчезает после анимации смерти")
	# Солнце: зомби загорается днём на открытом месте.
	c.g.night = false
	c.g.sky_level = 15
	var z2 := c.ent.spawn_mob(MobDefs.ZOMBIE, Vector3(-20.5, 11.0, -20.5)) as Mob
	_run_mobs(c, 6.0)
	check(z2.fire_time > 0.0 or z2.is_dead(), "зомби горит на солнце")
	_run_mobs(c, 25.0)
	check(not is_instance_valid(z2) or z2.is_dead() or z2.removed, "зомби сгорает на солнце")
	c.g.night = true
	c.g.sky_level = 4
	# Скелет стреляет.
	_reset_player(c)
	var sk := c.ent.spawn_mob(MobDefs.SKELETON, Vector3(0.5, 11.0, 7.5)) as Mob
	var seen := {}
	for i in 200:
		c.ent.update(0.05)
		for ch in c.ent.get_children():
			if ch is SimpleEntities.Projectile and (ch as SimpleEntities.Projectile).type == "arrow" and (ch as SimpleEntities.Projectile).shooter == sk:
				seen[ch.get_instance_id()] = true
	var arrows := seen.size()
	check(arrows > 0, "скелет стреляет из лука")
	check(c.p.health < 20, "стрелы скелета ранят игрока (%d)" % c.p.health)
	c.mobs.remove_mob(sk)
	# Крипер: шипит и взрывается рядом с игроком.
	_reset_player(c)
	var cr := c.ent.spawn_mob(MobDefs.CREEPER, Vector3(2.5, 11.0, 0.5)) as HostileMobs.Creeper
	var fused := false
	for i in 60:
		c.ent.update(0.05)
		if is_instance_valid(cr) and cr.fuse > 0.0:
			fused = true
	check(fused, "крипер шипит рядом с игроком")
	check(not is_instance_valid(cr) or cr.removed, "крипер взорвался")
	check(c.w.get_block(2, 10, 0) == Blocks.AIR or c.w.get_block(1, 10, 0) == Blocks.AIR, "взрыв крипера разрушил блоки")
	check(c.p.health < 20, "взрыв крипера ранил игрока (%d)" % c.p.health)
	check("creeper_fuse" in c.g.sounds, "звук шипения крипера")
	# Кошка отпугивает крипера.
	var cr2 := c.ent.spawn_mob(MobDefs.CREEPER, Vector3(-10.5, 11.0, 10.5)) as HostileMobs.Creeper
	var cat := c.ent.spawn_mob(MobDefs.OCELOT, Vector3(-12.5, 11.0, 10.5)) as Mob
	var d0 := cr2.position.distance_to(cat.position)
	for i in 40:
		cat.position = Vector3(-12.5, 11.0, 10.5)
		c.ent.update(0.05)
	check(cr2.position.distance_to(cat.position) > d0 + 1.0, "крипер убегает от оцелота")
	c.mobs.remove_mob(cr2)
	c.mobs.remove_mob(cat)
	# Паук днём нейтрален, ночью нападает; пещерный — отравляет.
	_reset_player(c)
	c.p.position = Vector3(-24.5, 11.0, 0.5)
	var cs := c.ent.spawn_mob(MobDefs.CAVE_SPIDER, Vector3(-21.5, 11.0, 0.5)) as Mob
	_run_mobs(c, 5.0)
	check(c.p.effects.has(Potions.POISON), "пещерный паук отравляет (нормальная сложность)")
	c.mobs.remove_mob(cs)
	c.g.night = false
	c.g.sky_level = 15
	var sp := c.ent.spawn_mob(MobDefs.SPIDER, Vector3(-19.5, 11.0, 0.5)) as Mob
	_run_mobs(c, 1.0)
	check(sp.target == null, "паук днём не нападает")
	c.mobs.player_attack(sp, 1)
	check(sp.target == c.p, "паук отвечает на удар днём")
	c.mobs.remove_mob(sp)
	c.g.night = true
	c.g.sky_level = 4
	c.p.position = Vector3(0.5, 11.0, 0.5)
	_reset_player(c)
	# Свинозомби: группа злится от удара.
	var pz1 := c.ent.spawn_mob(MobDefs.PIG_ZOMBIE, Vector3(10.5, 11.0, 10.5)) as HostileMobs.PigZombie
	var pz2 := c.ent.spawn_mob(MobDefs.PIG_ZOMBIE, Vector3(14.5, 11.0, 10.5)) as HostileMobs.PigZombie
	_run_mobs(c, 1.0)
	check(pz1.target == null and pz1.anger <= 0.0, "свинозомби нейтрален")
	c.mobs.player_attack(pz1, 1)
	check(pz1.anger > 0.0 and pz2.anger > 0.0 and pz2.target == c.p, "удар по свинозомби злит всю группу")
	c.mobs.remove_mob(pz1)
	c.mobs.remove_mob(pz2)
	# Слизень делится.
	var sl := c.ent.spawn_mob(MobDefs.SLIME, Vector3(-10.5, 11.0, -10.5)) as HostileMobs.Slime
	sl.set_size(4)
	var before := c.mobs.mobs.size()
	sl.hurt(100, "player", c.p, Vector3.ZERO)
	var after := c.mobs.mobs.size()
	var small := 0
	for m in c.mobs.mobs:
		if m is HostileMobs.Slime and (m as HostileMobs.Slime).size == 2:
			small += 1
	check(after - before >= 2 and small >= 2, "большой слизень делится на %d средних" % small)
	# Магмовый куб огнестоек.
	var mc := c.ent.spawn_mob(MobDefs.MAGMA_CUBE, Vector3(-14.5, 11.0, -10.5)) as Mob
	var mhp := mc.health
	mc.hurt(5, "fire", null, Vector3.ZERO)
	check(mc.health == mhp, "магмовый куб не горит")
	# Эндермен: телепортация при уроне, вода ранит, поднимает блоки.
	var en := c.ent.spawn_mob(MobDefs.ENDERMAN, Vector3(-5.5, 11.0, 15.5)) as HostileMobs.Enderman
	var epos := en.position
	en.hurt(2, "arrow", c.p, Vector3.ZERO)
	check(en.position.distance_to(epos) > 2.0 and en.health == en.max_health, "эндермен уклоняется от стрелы телепортом")
	var picked := false
	for i in 400:
		c.ent.update(0.05)
		if en.carried != 0:
			picked = true
			break
	check(picked, "эндермен поднимает блок (%s)" % Blocks.block_name(en.carried))
	# Чешуйница зовёт сородичей из камней-яиц.
	for i in 3:
		c.w.set_block(20 + i, 9, 20, Blocks.MONSTER_EGG, 0)
	var sf := c.ent.spawn_mob(MobDefs.SILVERFISH, Vector3(21.5, 11.0, 21.5)) as Mob
	c.mobs.player_attack(sf, 1)
	_run_mobs(c, 1.5)
	var fish := 0
	for m in c.mobs.mobs:
		if m.type == MobDefs.SILVERFISH:
			fish += 1
	check(fish >= 3 and c.w.get_block(21, 9, 20) == Blocks.AIR, "чешуйница позвала сородичей (%d)" % fish)
	# Ифрит стреляет огненными шарами.
	_reset_player(c)
	var bl := c.ent.spawn_mob(MobDefs.BLAZE, Vector3(0.5, 11.0, -12.5)) as Mob
	var fb := {}
	for i in 120:
		c.ent.update(0.05)
		for ch in c.ent.get_children():
			if ch is SimpleEntities.Projectile and (ch as SimpleEntities.Projectile).shooter == bl:
				fb[ch.get_instance_id()] = true
	var fireballs := fb.size()
	check(fireballs >= 2, "ифрит стреляет огненными шарами (%d)" % fireballs)
	c.mobs.remove_mob(bl)
	for ch in c.ent.get_children():
		if ch is SimpleEntities.Projectile:
			ch.free()
	# Гаст: огненный шар можно отбить, отбитый убивает гаста.
	_reset_player(c)
	var gh := c.ent.spawn_mob(MobDefs.GHAST, Vector3(0.5, 20.0, -20.5)) as Mob
	var ball: SimpleEntities.Projectile = null
	for i in 80:
		c.ent.update(0.05)
		for ch in c.ent.get_children():
			if ch is SimpleEntities.Projectile and (ch as SimpleEntities.Projectile).shooter == gh:
				ball = ch
		if ball != null:
			break
	check(ball != null, "гаст выпускает огненный шар")
	if ball != null:
		_look(c.p, ball.position)
		var hit := c.mobs.raycast(c.p.eye_position(), c.p.look_dir(), 100.0)
		check(not hit.is_empty() and hit["entity"] == ball, "огненный шар можно взять на прицел %s" % [hit])
		c.mobs.player_attack(ball, 1)
		check(ball.shooter == c.p, "удар отбивает огненный шар")
		c.mobs.damage(gh, 6, "fire", c.p, Vector3.ZERO)
		check(gh.is_dead(), "отбитый шар убивает гаста")
	# Мирная сложность: монстры исчезают.
	c.g.difficulty = 0
	c.mobs._despawn(c.p)
	check(c.mobs.count_category(MobDefs.CAT_MONSTER) == 0, "на мирной сложности монстры исчезают")
	await _free_ctx(c)


func _test_animals() -> void:
	print("Животные")
	var c := await _make_ctx(false)
	var inv := c.p.inventory
	inv.select(0)
	# Овца: стрижка, окраска, поедание травы.
	var sh := c.ent.spawn_mob(MobDefs.SHEEP, Vector3(2.5, 11.0, 0.5)) as PassiveMobs.Sheep
	sh.color = 14
	inv.set_slot(0, Items.SHEARS, 1)
	_clear_drops(c)
	check(c.mobs.interact(sh, c.p), "ножницы стригут овцу")
	var wool := 0
	for ch in c.ent.get_children():
		if ch is ItemDrop and (ch as ItemDrop).item_id == Blocks.WOOL and (ch as ItemDrop).data == 14:
			wool += (ch as ItemDrop).count
	check(sh.sheared and wool >= 1 and wool <= 3, "1–3 шерсти цвета овцы (%d красной)" % wool)
	check(inv.datas[0] == 1, "ножницы изнашиваются")
	check(not c.mobs.interact(sh, c.p), "стриженую овцу нельзя стричь")
	sh._eat = 40
	for i in 40:
		sh.ai_tick()
	check(not sh.sheared and c.w.get_block(2, 10, 0) == Blocks.DIRT, "овца ест траву и обрастает шерстью")
	inv.set_slot(0, Items.DYE, 3, Items.DYE_LAPIS)
	check(c.mobs.interact(sh, c.p) and sh.color == 11 and inv.counts[0] == 2, "краситель перекрашивает овцу (лазурит → синяя)")
	# Корова: дойка.
	var cow := c.ent.spawn_mob(MobDefs.COW, Vector3(-3.5, 11.0, 0.5)) as Mob
	inv.set_slot(0, Items.BUCKET, 1)
	check(c.mobs.interact(cow, c.p) and inv.ids[0] == Items.MILK_BUCKET, "ведро → ведро молока")
	# Разведение пшеницей.
	var cow2 := c.ent.spawn_mob(MobDefs.COW, Vector3(-5.5, 11.0, 0.5)) as Mob
	inv.set_slot(0, Items.WHEAT, 10)
	check(c.mobs.interact(cow, c.p) and c.mobs.interact(cow2, c.p), "коровы едят пшеницу")
	check(inv.counts[0] == 8, "пшеница расходуется")
	check(not c.mobs.interact(cow, c.p), "повторно кормить влюблённую корову нельзя")
	_run_mobs(c, 8.0)
	var babies := 0
	var baby: Mob = null
	for m in c.mobs.mobs:
		if m.type == MobDefs.COW and m.baby:
			babies += 1
			baby = m
	check(babies == 1, "родился телёнок")
	check("hearts" in c.g.effects, "сердечки при разведении")
	check(baby != null and baby.height < 1.0, "телёнок вдвое меньше")
	if baby != null:
		baby.grow = 0.06
		_run_mobs(c, 0.2)
		check(not baby.baby and baby.height > 1.2, "телёнок вырастает")
	check((cow as PassiveMobs.Animal).breed_cd > 200.0, "у родителей перерыв 5 минут")
	# Грибная корова: суп и стрижка.
	var mo := c.ent.spawn_mob(MobDefs.MOOSHROOM, Vector3(6.5, 11.0, 6.5)) as Mob
	inv.set_slot(0, Items.BOWL, 1)
	check(c.mobs.interact(mo, c.p) and inv.ids[0] == Items.MUSHROOM_STEW, "миска → грибной суп")
	inv.set_slot(0, Items.SHEARS, 1)
	_clear_drops(c)
	check(c.mobs.interact(mo, c.p), "ножницы стригут грибную корову")
	check(_drops(c, Blocks.RED_MUSHROOM) == 5, "5 красных грибов")
	var cows_here := 0
	for m in c.mobs.mobs:
		if m.type == MobDefs.COW and m.position.distance_to(Vector3(6.5, 11, 6.5)) < 0.5:
			cows_here += 1
	check(cows_here == 1 and mo.removed, "грибная корова стала обычной")
	# Свинья: седло.
	var pig := c.ent.spawn_mob(MobDefs.PIG, Vector3(-8.5, 11.0, -8.5)) as PassiveMobs.Pig
	inv.set_slot(0, Items.SADDLE, 1)
	check(c.mobs.interact(pig, c.p) and pig.saddled and inv.counts[0] == 0, "седло на свинью")
	_clear_drops(c)
	pig.fire_time = 5.0
	pig.hurt(50, "player", c.p, Vector3.ZERO)
	check(_drops(c, Items.SADDLE) == 1, "свинья роняет седло")
	check(_drops(c, Items.PORKCHOP) == 0, "горящая свинья — только жареная свинина")
	# Курица: яйца, медленное падение, разведение семенами.
	var ch := c.ent.spawn_mob(MobDefs.CHICKEN, Vector3(12.5, 20.0, -8.5)) as PassiveMobs.Chicken
	var fell := 0.0
	for i in 10:
		var y0 := ch.position.y
		c.ent.update(0.05)
		fell = maxf(fell, y0 - ch.position.y)
	check(fell < 0.2, "курица медленно падает (%.2f за тик)" % fell)
	_run_mobs(c, 3.0)
	check(ch.health == ch.max_health, "курица не разбивается при падении")
	_clear_drops(c)
	ch.egg_timer = 0.06
	_run_mobs(c, 0.2)
	check(_drops(c, Items.EGG) == 1, "курица снесла яйцо")
	inv.set_slot(0, Items.SEEDS, 2)
	check(c.mobs.interact(ch, c.p), "курица ест семена")
	# Животное убегает после удара.
	var pig2 := c.ent.spawn_mob(MobDefs.PIG, Vector3(-12.5, 11.0, 12.5)) as Mob
	var pp := pig2.position
	c.mobs.player_attack(pig2, 1)
	_run_mobs(c, 2.0)
	check(pig2.position.distance_to(pp) > 2.0 and pig2.panic > 0.0, "свинья в панике убегает")
	# Спрут в воде плавает, в воздухе задыхается.
	c.w.fill_region(Vector3i(16, 6, -16), Vector3i(24, 10, -8), Blocks.WATER)
	var sq := c.ent.spawn_mob(MobDefs.SQUID, Vector3(20.5, 7.0, -12.5)) as Mob
	_run_mobs(c, 5.0)
	check(sq.in_water and sq.health == sq.max_health, "спрут живёт в воде")
	_clear_drops(c)
	sq.hurt(100, "player", c.p, Vector3.ZERO)
	check(_drops(c, Items.DYE) >= 1, "спрут роняет чернильные мешки")
	await _free_ctx(c)


func _test_pets() -> void:
	print("Волки и кошки")
	var c := await _make_ctx(false)
	var inv := c.p.inventory
	inv.select(0)
	# Приручение волка костями.
	var w := c.ent.spawn_mob(MobDefs.WOLF, Vector3(2.5, 11.0, 0.5)) as PassiveMobs.Wolf
	inv.set_slot(0, Items.BONE, 64)
	var bones := 0
	while not w.tamed and bones < 60:
		c.mobs.interact(w, c.p)
		bones += 1
	check(w.tamed and w.sitting and w.max_health == 20, "волк приручён костями (%d костей), сидит" % bones)
	check(inv.counts[0] == 64 - bones, "кости расходуются")
	# Команда «встать» и следование за хозяином.
	inv.set_slot(0, 0, 0)
	c.mobs.interact(w, c.p)
	check(not w.sitting, "правая кнопка — встать")
	c.p.position = Vector3(-20.5, 11.0, 0.5)
	c.p.on_ground = true
	_run_mobs(c, 3.0)
	check(w.position.distance_to(c.p.position) < 8.0, "волк следует за хозяином (телепорт) %.1f" % w.position.distance_to(c.p.position))
	c.mobs.interact(w, c.p)
	var spos := w.position
	c.p.position = Vector3(0.5, 11.0, 0.5)
	_run_mobs(c, 2.0)
	check(w.sitting and w.position.distance_to(spos) < 0.5, "сидящий волк остаётся на месте")
	c.mobs.interact(w, c.p)
	# Защита хозяина: зомби ранил игрока.
	c.g.night = true
	c.g.sky_level = 4
	var z := c.ent.spawn_mob(MobDefs.ZOMBIE, Vector3(3.5, 11.0, 3.5)) as Mob
	w.position = Vector3(-2.5, 11.0, -2.5)
	_run_mobs(c, 6.0)
	check(w.target == z or z.is_dead() or z.removed, "волк защищает хозяина")
	if is_instance_valid(z) and not z.removed:
		c.mobs.remove_mob(z)
	# Лечение мясом через правую кнопку (голодный игрок).
	w.health = 10
	inv.set_slot(0, Items.BEEF, 5)
	c.p.food = 10
	_look(c.p, w.center())
	c.p.position = w.position + Vector3(0, 0, 2.0)
	_look(c.p, w.center())
	var acted := (c.p.actions as PlayerActions).use_on_entity(c.p)
	check(acted and w.health > 10 and inv.counts[0] == 4, "голодный игрок кормит волка мясом, а не ест сам (hp %d)" % w.health)
	# Разведение волков мясом.
	var w2 := c.ent.spawn_mob(MobDefs.WOLF, w.position + Vector3(1, 0, 0)) as PassiveMobs.Wolf
	w2.tamed = true
	w2.on_tamed()
	w.health = w.max_health
	w2.health = w2.max_health
	w.sitting = false
	w2.sitting = false
	c.mobs.interact(w, c.p)
	c.mobs.interact(w2, c.p)
	c.p.position = w.position + Vector3(2, 0, 0)
	_run_mobs(c, 6.0)
	var pups := 0
	for m in c.mobs.mobs:
		if m is PassiveMobs.Wolf and m.baby and (m as PassiveMobs.Wolf).tamed:
			pups += 1
	check(pups == 1, "у прирученных волков родился прирученный щенок")
	# Дикая стая злится.
	var wa := c.ent.spawn_mob(MobDefs.WOLF, Vector3(20.5, 11.0, 20.5)) as PassiveMobs.Wolf
	var wb := c.ent.spawn_mob(MobDefs.WOLF, Vector3(22.5, 11.0, 20.5)) as PassiveMobs.Wolf
	c.mobs.player_attack(wa, 1)
	check(wa.angry > 0.0 and wb.angry > 0.0, "удар по дикому волку злит стаю")
	# Оцелот: приручение рыбой → кошка.
	var oc := c.ent.spawn_mob(MobDefs.OCELOT, Vector3(-10.5, 11.0, -10.5)) as PassiveMobs.Ocelot
	c.p.position = Vector3(-8.5, 11.0, -10.5)
	c.p.velocity = Vector3.ZERO
	inv.set_slot(0, Items.FISH, 64)
	var fish := 0
	while not oc.tamed and fish < 60:
		c.mobs.interact(oc, c.p)
		fish += 1
	check(oc.tamed and oc.skin >= 1 and oc.skin <= 3, "оцелот приручён рыбой (%d), стал кошкой: %s" % [fish, MobDefs.CAT_SKINS[oc.skin]])
	check(oc.sitting, "кошка сидит после приручения")
	await _free_ctx(c)


func _test_misc() -> void:
	print("Големы, взрывы, зелья, молния")
	var c := await _make_ctx(true)
	c.g.night = true
	c.g.sky_level = 4
	# Железный голем бьёт зомби и подбрасывает.
	var golem := c.ent.spawn_mob(MobDefs.IRON_GOLEM, Vector3(0.5, 11.0, 6.5)) as PassiveMobs.IronGolem
	check(golem.player_made, "голем из блоков — построен игроком")
	var z := c.ent.spawn_mob(MobDefs.ZOMBIE, Vector3(4.5, 11.0, 6.5)) as Mob
	var hit := false
	for i in 200:
		c.ent.update(0.05)
		if is_instance_valid(z) and (z.health < z.max_health or z.is_dead()):
			hit = true
			break
	check(hit, "железный голем бьёт зомби")
	# Снежный голем: снежный след (в холодном биоме) и снежки в монстров.
	(c.w.chunks[Vector2i(-1, -1)] as Chunk).biomes.fill(Biomes.TAIGA)
	var sg := c.ent.spawn_mob(MobDefs.SNOW_GOLEM, Vector3(-10.5, 11.0, -10.5)) as Mob
	c.ent.spawn_mob(MobDefs.SPIDER, Vector3(-10.5, 11.0, -4.5))
	var sb := {}
	for i in 60:
		c.ent.update(0.05)
		for ch in c.ent.get_children():
			if ch is SimpleEntities.Projectile and (ch as SimpleEntities.Projectile).type == "snowball":
				sb[ch.get_instance_id()] = true
	var balls := sb.size()
	check(balls >= 1, "снежный голем кидает снежки в монстров (%d)" % balls)
	var snow := false
	for x in range(-13, -8):
		for zz in range(-13, -8):
			if c.w.get_block(x, 11, zz) == Blocks.SNOW_LAYER:
				snow = true
	check(snow, "снежный голем оставляет снежный след")
	c.mobs.remove_mob(sg)
	# Взрыв ранит существ.
	var cow := c.ent.spawn_mob(MobDefs.COW, Vector3(15.5, 11.0, 15.5)) as Mob
	c.mobs.explosion(Vector3(15.5, 11.5, 13.5), 3.0, null)
	check(cow.health < cow.max_health and cow.velocity.length() > 1.0, "взрыв ранит и отбрасывает (hp %d)" % cow.health)
	# Взрывное зелье лечения ранит нежить.
	var zz2 := c.ent.spawn_mob(MobDefs.ZOMBIE, Vector3(-15.5, 11.0, 15.5)) as Mob
	var list := c.mobs.in_radius(Vector3(-15.5, 12.0, 15.5), 4.0)
	check(list.has(zz2), "in_radius находит существ")
	zz2.add_effect(Potions.INSTANT_HEALTH, 0, 1.0)
	check(zz2.health < zz2.max_health, "зелье лечения ранит нежить")
	var cow2 := c.ent.spawn_mob(MobDefs.COW, Vector3(-20.5, 11.0, 20.5)) as Mob
	cow2.add_effect(Potions.POISON, 0, 10.0)
	var chp := cow2.health
	_run_mobs(c, 3.0)
	check(cow2.health < chp, "отравление ранит корову (%d → %d)" % [chp, cow2.health])
	# Молния: свинья → свинозомби, крипер → заряженный.
	var pig := c.ent.spawn_mob(MobDefs.PIG, Vector3(20.5, 11.0, -20.5)) as Mob
	var cr := c.ent.spawn_mob(MobDefs.CREEPER, Vector3(21.5, 11.0, -20.5)) as HostileMobs.Creeper
	c.mobs.lightning(Vector3(21.0, 11.0, -20.5))
	var pz := c.mobs.nearest_mob(Vector3(20.5, 11.0, -20.5), 2.0, [MobDefs.PIG_ZOMBIE])
	check(pig.removed and pz != null, "молния превращает свинью в свинозомби")
	check(cr.charged, "молния заряжает крипера")
	# Монстры рядом мешают спать.
	for m in c.mobs.mobs.duplicate():
		if m != cr and m.has_flag(MobDefs.F_MOB):
			c.mobs.remove_mob(m)
	check(c.mobs.monsters_near(cr.position + Vector3(3, 0, 3), 8.0), "monsters_near: крипер рядом")
	check(not c.mobs.monsters_near(Vector3(-25, 11, -25), 8.0), "monsters_near: пусто вдали")
	# Звуки и частицы.
	check(not c.g.sounds.is_empty(), "звуки существ уходят в play_sound (%d)" % c.g.sounds.size())
	await _free_ctx(c)


func _test_saving() -> void:
	print("Сохранение")
	var c := await _make_ctx(true)
	var sh := c.ent.spawn_mob(MobDefs.SHEEP, Vector3(3.5, 11.0, 3.5)) as PassiveMobs.Sheep
	sh.color = 5
	sh.sheared = true
	var w := c.ent.spawn_mob(MobDefs.WOLF, Vector3(4.5, 11.0, 3.5)) as PassiveMobs.Wolf
	w.tamed = true
	w.on_tamed()
	w.sitting = true
	w.health = 13
	var cat := c.ent.spawn_mob(MobDefs.OCELOT, Vector3(5.5, 11.0, 3.5)) as PassiveMobs.Ocelot
	cat.tamed = true
	cat.skin = 3
	cat.on_tamed()
	var baby := c.mobs.spawn(MobDefs.PIG, Vector3(6.5, 11.0, 3.5), true) as Mob
	var en := c.ent.spawn_mob(MobDefs.ENDERMAN, Vector3(7.5, 11.0, 3.5)) as HostileMobs.Enderman
	en.carried = Blocks.TNT
	var by := c.mobs.save_by_chunk()
	var list: Array = by.get(Vector2i(0, 0), [])
	check(list.size() == 5, "save_by_chunk: 5 существ в чанке (0,0)")
	# Выгрузка чанка: животные и питомцы сохраняются, монстр исчезает.
	var saved := c.mobs.unload_chunk(Vector2i(0, 0))
	check(saved.size() == 4 and c.mobs.mobs.is_empty(), "unload_chunk сохраняет животных (%d), монстр исчезает" % saved.size())
	for d in saved:
		c.mobs.restore(JSON.parse_string(JSON.stringify(d)))
	var sh2 := c.mobs.nearest_mob(Vector3(3.5, 11, 3.5), 0.5, [MobDefs.SHEEP]) as PassiveMobs.Sheep
	var w2 := c.mobs.nearest_mob(Vector3(4.5, 11, 3.5), 0.5, [MobDefs.WOLF]) as PassiveMobs.Wolf
	var cat2 := c.mobs.nearest_mob(Vector3(5.5, 11, 3.5), 0.5, [MobDefs.OCELOT]) as PassiveMobs.Ocelot
	var baby2 := c.mobs.nearest_mob(Vector3(6.5, 11, 3.5), 0.5, [MobDefs.PIG]) as Mob
	check(sh2 != null and sh2.color == 5 and sh2.sheared, "овца: цвет и стрижка после загрузки (через JSON)")
	check(w2 != null and w2.tamed and w2.sitting and w2.health == 13, "волк: приручён, сидит, здоровье")
	check(cat2 != null and cat2.tamed and cat2.skin == 3, "кошка: окрас")
	check(baby2 != null and baby2.baby, "детёныш остаётся детёнышем")
	# EntityManager сохраняет мобов в чанках и восстанавливает при загрузке.
	c.ent.save_into_chunks()
	var ch: Chunk = c.w.chunks[Vector2i(0, 0)]
	var mob_dicts := 0
	for d: Dictionary in ch.entities:
		if d.get("kind") == "mob":
			mob_dicts += 1
	check(mob_dicts == 4, "EntityManager.save_into_chunks записывает существ в чанк (%d)" % mob_dicts)
	c.ent.clear_saved_lists()
	await _free_ctx(c)


func _test_spawning() -> void:
	print("Появление")
	var c := await _make_ctx(false)
	# Ночью в темноте появляются монстры.
	c.g.night = true
	c.g.sky_level = 4
	for i in 60:
		c.mobs._natural_spawn(c.p)
	var monsters := c.mobs.count_category(MobDefs.CAT_MONSTER)
	check(monsters > 0 and monsters <= MobSystem.HOSTILE_CAP, "ночью появляются монстры (%d, предел %d)" % [monsters, MobSystem.HOSTILE_CAP])
	var too_close := false
	for m in c.mobs.mobs:
		if m.position.distance_to(c.p.position) < MobSystem.SPAWN_MIN_DIST - 0.01:
			too_close = true
	check(not too_close, "не ближе 24 блоков к игроку")
	# Днём на светлой траве монстры не появляются.
	for m in c.mobs.mobs.duplicate():
		c.mobs.remove_mob(m)
	c.g.night = false
	c.g.sky_level = 15
	for i in 60:
		c.mobs._natural_spawn(c.p)
	check(c.mobs.count_category(MobDefs.CAT_MONSTER) == 0, "днём на свету монстров нет")
	check(c.mobs.count_category(MobDefs.CAT_CREATURE) > 0, "животные появляются на траве (%d)" % c.mobs.count_category(MobDefs.CAT_CREATURE))
	# Рассадник.
	for m in c.mobs.mobs.duplicate():
		c.mobs.remove_mob(m)
	c.w.fill_region(Vector3i(-6, 11, -6), Vector3i(-2, 13, -2), Blocks.AIR)
	c.w.fill_region(Vector3i(-7, 14, -7), Vector3i(-1, 14, -1), Blocks.STONE)
	var sp := Vector3i(-4, 11, -4)
	c.w.set_block(sp.x, sp.y, sp.z, Blocks.SPAWNER)
	c.w.get_block_entity(sp)["mob"] = MobDefs.SKELETON
	c.mobs._scan_spawners(c.w.chunks[Vector2i(-1, -1)])
	c.g.night = true
	c.g.sky_level = 4
	c.p.position = Vector3(-10.5, 11.0, -10.5)
	var made := 0
	for i in 40:
		made += c.mobs._spawner_spawn(sp, MobDefs.SKELETON, c.p)
	var sk := 0
	for m in c.mobs.mobs:
		if m.type == MobDefs.SKELETON:
			sk += 1
	check(sk > 0 and sk <= 6, "рассадник создаёт скелетов, не больше 6 рядом (%d)" % sk)
	for m in c.mobs.mobs.duplicate():
		c.mobs.remove_mob(m)
	c.w.get_block_entity(sp)["delay"] = 0.1
	_run_mobs(c, 3.0)
	check(c.mobs.mobs.size() > 0, "рассадник срабатывает сам, когда игрок ближе 16 блоков")
	check(float(c.w.get_block_entity(sp).get("delay", 0.0)) >= 6.0, "следующая задержка 10–40 с")
	# Курица из яйца.
	c.ent.spawn_projectile("egg", Vector3(0.5, 12, 0.5), Vector3.ZERO)
	var chicks := 0
	for i in 40:
		c.ent._impact(c.ent.spawn_projectile("egg", Vector3(0.5, 12, 0.5), Vector3.ZERO), Vector3(0.5, 11, 0.5))
	for m in c.mobs.mobs:
		if m.type == MobDefs.CHICKEN and m.baby:
			chicks += 1
	check(chicks > 0, "из брошенного яйца иногда вылупляется цыплёнок (%d из 40)" % chicks)
	await _free_ctx(c)


func _test_dragon() -> void:
	print("Дракон Края")
	var c := await _make_ctx(false)
	c.w.dimension = 1
	c.w.fill_region(Vector3i(-20, 10, -20), Vector3i(20, 10, 20), Blocks.END_STONE)
	c.mobs._check_dragon(c.p)
	var dragon: EnderDragon = null
	for m in c.mobs.mobs:
		if m is EnderDragon:
			dragon = m
	check(dragon != null, "в Крае появляется дракон")
	if dragon == null:
		await _free_ctx(c)
		return
	var crystal := c.mobs.restore({"kind": "mob", "type": 200, "pos": [10.5, 11.0, 10.5]}) as Mob
	dragon.position = Vector3(10.5, 16.0, 10.5)
	dragon.health = 150
	_run_mobs(c, 1.2)
	check(dragon.health > 150, "дракон лечится от кристалла (%d)" % dragon.health)
	var dhp := dragon.health
	c.mobs.damage(crystal, 1, "arrow", c.p, Vector3.ZERO)
	check(crystal.removed and dragon.health < dhp, "стрела взрывает кристалл, дракон ранен (%d)" % dragon.health)
	# Ломает блоки, кроме камня Края.
	c.w.set_block(int(dragon.position.x), int(dragon.position.y) + 1, int(dragon.position.z), Blocks.PLANKS)
	var bp := Vector3i(floori(dragon.position.x), floori(dragon.position.y) + 1, floori(dragon.position.z))
	dragon._break_blocks()
	check(c.w.get_block_v(bp) == Blocks.AIR, "дракон ломает доски на пути")
	c.w.set_block(bp.x, bp.y, bp.z, Blocks.OBSIDIAN)
	dragon._break_blocks()
	check(c.w.get_block_v(bp) == Blocks.OBSIDIAN, "обсидиан дракон не ломает")
	# Только игрок и взрывы ранят.
	var h := dragon.health
	dragon.hurt(20, "fire", null, Vector3.ZERO)
	check(dragon.health == h, "огонь дракона не ранит")
	dragon.invuln = 0.0
	dragon.hurt(1000, "player", c.p, Vector3.ZERO)
	check(dragon.is_dead(), "дракон побеждён")
	_clear_drops(c)
	_run_mobs(c, 10.5)
	check(dragon.removed, "агония длится 10 с")
	check(c.g.dragon_killed and bool(c.g.meta.get("dragon_killed", false)), "флаг dragon_killed установлен")
	var portal := 0
	var egg := false
	for y in range(5, 30):
		for z in range(-4, 5):
			for x in range(-4, 5):
				var b := c.w.get_block(x, y, z)
				if b == Blocks.END_PORTAL:
					portal += 1
				elif b == Blocks.DRAGON_EGG:
					egg = true
	check(portal >= 20, "портал выхода из блоков портала Края (%d)" % portal)
	check(egg, "яйцо дракона на столбе")
	check(_xp(c) >= 11000, "поток опыта (%d)" % _xp(c))
	c.mobs._check_dragon(c.p)
	var again := false
	for m in c.mobs.mobs:
		if m is EnderDragon:
			again = true
	check(not again, "побеждённый дракон не появляется снова")
	await _free_ctx(c)


func _test_performance() -> void:
	print("Производительность (отладочная сборка)")
	var c := await _make_ctx(false)
	c.g.night = true
	c.g.sky_level = 4
	c.p.creative = true
	var types := [MobDefs.ZOMBIE, MobDefs.SKELETON, MobDefs.CREEPER, MobDefs.SPIDER, MobDefs.PIG, MobDefs.COW, MobDefs.SHEEP,
		MobDefs.CHICKEN, MobDefs.WOLF, MobDefs.VILLAGER]
	for i in 40:
		c.ent.spawn_mob(types[i % types.size()], Vector3(-28.5 + (i % 8) * 8.0, 11.0, -28.5 + int(i / 8.0) * 12.0))
	# Прогрев (скины, меши).
	_run_mobs(c, 1.0)
	var t0 := Time.get_ticks_usec()
	var frames := 300
	var worst := 0
	for i in frames:
		var f0 := Time.get_ticks_usec()
		c.ent.update(1.0 / 60.0)
		worst = maxi(worst, Time.get_ticks_usec() - f0)
	var avg := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("    40 существ: %.2f мс/кадр в среднем (60 кадров/с), худший кадр %.2f мс" % [avg, worst / 1000.0])
	check(avg < 8.0, "40 существ укладываются в бюджет кадра (%.2f мс)" % avg)
	await _free_ctx(c)
