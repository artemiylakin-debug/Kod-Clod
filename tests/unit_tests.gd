extends SceneTree
## Юнит-тесты логики (без рендеринга).
## Запуск: godot --headless --path . -s res://tests/unit_tests.gd

var _failed := 0
var _passed := 0


## Заглушка игровой сцены для логики блоков и действий игрока.
class FakeGame extends Node:
	var entities: EntityManager
	var opened := ""
	var toasts: Array[String] = []

	func spawn_drop(id: int, count: int, data: int, pos: Vector3, vel := Vector3.INF, delay := 0.0) -> ItemDrop:
		return entities.spawn_drop(id, count, data, pos, vel, delay)

	func open_container(kind: String, _p: Vector3i) -> void:
		opened = kind

	func show_toast(text: String, _d := 2.5) -> void:
		toasts.append(text)

	func explosion_damage(center: Vector3, power: float, source: Node) -> void:
		entities.explosion_damage(center, power, source)

	func sky_light_level() -> int:
		return 15

	func is_night() -> bool:
		return false

	func edit_sign(_p: Vector3i) -> void:
		pass

	func try_sleep(_p: Vector3i) -> void:
		pass


func _initialize() -> void:
	_run()


func _run() -> void:
	# Раскладка клавиш регистрируется автозагрузкой Game, которой нет в режиме -s.
	var game: Node = load("res://scripts/globals/game.gd").new()
	game.call("_setup_input_map")
	game.free()
	TextureFactory.ensure_initialized()
	_test_blocks()
	_test_items_and_recipes()
	_test_enchantments()
	_test_textures()
	_test_worldgen()
	_test_mesher()
	_test_light()
	_test_inventory()
	_test_storage()
	await _test_world_and_player()
	await _test_block_logic()
	_test_threaded_job()
	_test_sliced_jobs()
	await _test_single_thread_world()
	_test_performance()
	print("\n==== Итог: %d пройдено, %d провалено ====" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("  [OK]   ", what)
	else:
		_failed += 1
		print("  [FAIL] ", what)


# --- Реестры ----------------------------------------------------------------

func _test_blocks() -> void:
	print("Блоки")
	var named := true
	for id in Blocks.COUNT:
		if id != Blocks.PISTON_MOVING and Blocks.block_name(id).is_empty():
			named = false
			print("    без имени: ", id)
	check(named, "у всех %d блоков 1.2 есть имена" % Blocks.COUNT)
	var tiles_ok := true
	for t in Blocks.tile_table:
		if t < 0 or t >= Tex.COUNT:
			tiles_ok = false
	check(tiles_ok, "все текстуры граней в пределах атласа (%d тайлов)" % Tex.COUNT)
	check(not Blocks.is_solid(Blocks.WATER) and Blocks.is_solid(Blocks.STONE), "вода не твёрдая, камень твёрдый")
	check(not Blocks.is_opaque(Blocks.GLASS) and not Blocks.is_opaque(Blocks.LEAVES) and not Blocks.is_opaque(Blocks.SLAB),
		"стекло, листва и плиты не скрывают соседние грани")
	check(Blocks.light_of(Blocks.TORCH) == 14 and Blocks.light_of(Blocks.GLOWSTONE) == 15 and Blocks.light_of(Blocks.LIT_REDSTONE_LAMP) == 15
		and Blocks.light_of(Blocks.REDSTONE_LAMP) == 0, "свечение: факел 14, светокамень 15, лампа — только включённая")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var d: Array = Blocks.drops(Blocks.STONE, 0, Blocks.TOOL_PICKAXE, 0, rng)
	check(d.size() == 1 and d[0][0] == Blocks.COBBLESTONE, "камень киркой → булыжник")
	check(Blocks.drops(Blocks.STONE, 0, Blocks.TOOL_NONE, -1, rng).is_empty(), "камень рукой ничего не даёт")
	check(Blocks.drops(Blocks.DIAMOND_ORE, 0, Blocks.TOOL_PICKAXE, 1, rng).is_empty()
		and Blocks.drops(Blocks.DIAMOND_ORE, 0, Blocks.TOOL_PICKAXE, 2, rng)[0][0] == Items.DIAMOND,
		"алмазная руда — только железной киркой и лучше")
	check(Blocks.drops(Blocks.GRASS, 0, Blocks.TOOL_NONE, -1, rng)[0][0] == Blocks.DIRT, "трава → земля")
	var wool: Array = Blocks.drops(Blocks.WOOL, 14, Blocks.TOOL_NONE, -1, rng)
	check(wool[0][0] == Blocks.WOOL and wool[0][2] == 14, "шерсть сохраняет цвет")
	var hand := Blocks.break_time(Blocks.STONE, Blocks.TOOL_NONE, -1, 1.0)
	var wood_pick := Blocks.break_time(Blocks.STONE, Blocks.TOOL_PICKAXE, 0, 2.0)
	check(absf(hand - 7.5) < 0.01 and absf(wood_pick - 1.125) < 0.01, "время добычи камня: рукой 7,5 с, деревянной киркой 1,125 с")
	var boxes := Blocks.shape_boxes(Blocks.SLAB, 0, 0, true)
	check(boxes.size() == 1 and is_equal_approx(boxes[0].size.y, 0.5), "нижняя плита — полблока")
	check(Blocks.shape_boxes(Blocks.OAK_STAIRS, 0, 0, true).size() == 2, "ступеньки — два параллелепипеда")
	check(not Blocks.is_solid(Blocks.TORCH) and not Blocks.is_solid(Blocks.TALLGRASS) and Blocks.is_solid(Blocks.FENCE),
		"сквозь факел и траву можно пройти, сквозь забор — нет")


func _test_items_and_recipes() -> void:
	print("Предметы и рецепты")
	check(Items.max_stack(Items.DIAMOND_SWORD) == 1 and Items.max_stack(Items.ENDER_PEARL) == 16
		and Items.max_stack(Items.SNOWBALL) == 16 and Items.max_stack(Blocks.DIRT) == 64, "размеры стопок")
	check(Items.max_damage(Items.WOODEN_PICKAXE) == 59 and Items.max_damage(Items.DIAMOND_PICKAXE) == 1561
		and Items.max_damage(Items.BOW) == 384, "прочность инструментов как в 1.2")
	check(Items.food_value(Items.BREAD) == 5 and Items.food_value(Items.COOKED_PORKCHOP) == 8, "сытость еды")
	var unnamed := 0
	for id in range(256, Items.FIRE_CHARGE + 1):
		if Items.name_of(id, 0).is_empty():
			unnamed += 1
	check(unnamed == 0, "у всех предметов 256–385 есть названия")
	var log_grid := [[Blocks.LOG, 2], [0, 0], [0, 0], [0, 0]]
	var r: Array = Recipes.match_grid(log_grid, 2)
	check(r.size() >= 3 and r[0] == Blocks.PLANKS and r[1] == 4 and r[2] == 2, "берёзовое бревно → 4 берёзовые доски")
	var P := [Blocks.PLANKS, 0]
	var S := [Items.STICK, 0]
	var E := [0, 0]
	r = Recipes.match_grid([P, P, P, E, S, E, E, S, E], 3)
	check(not r.is_empty() and r[0] == Items.WOODEN_PICKAXE, "деревянная кирка")
	r = Recipes.match_grid([[Items.REDSTONE, 0], [Blocks.GLOWSTONE, 0], E, E], 2)
	var lamp: Array = Recipes.match_grid([E, [Items.REDSTONE, 0], E, [Items.REDSTONE, 0], [Blocks.GLOWSTONE, 0], [Items.REDSTONE, 0],
		E, [Items.REDSTONE, 0], E], 3)
	check(not lamp.is_empty() and lamp[0] == Blocks.REDSTONE_LAMP, "лампа из редстоуна и светокамня (новое в 1.2)")
	var charge: Array = Recipes.match_grid([[Items.BLAZE_POWDER, 0], [Items.COAL, 0], [Items.GUNPOWDER, 0], E], 2)
	check(not charge.is_empty() and charge[0] == Items.FIRE_CHARGE and charge[1] == 3, "огненный шар: 3 шт. (новое в 1.2)")
	# Отражённый рецепт (топор «влево» и «вправо»).
	var axe_l: Array = Recipes.match_grid([P, P, E, P, S, E, E, S, E], 3)
	var axe_r: Array = Recipes.match_grid([E, P, P, E, S, P, E, S, E], 3)
	check(not axe_l.is_empty() and not axe_r.is_empty() and axe_l[0] == Items.WOODEN_AXE and axe_r[0] == Items.WOODEN_AXE, "зеркальные рецепты")
	var smelt := Recipes.smelt_result(Blocks.IRON_ORE, 0)
	check(not smelt.is_empty() and smelt[0] == Items.IRON_INGOT, "переплавка железной руды")
	check(Recipes.smelt_result(Blocks.LOG, 0)[0] == Items.COAL and Recipes.smelt_result(Blocks.LOG, 0)[2] == 1, "бревно → древесный уголь")
	check(Potions.brew(0, Items.NETHER_WART) == 16 and Potions.brew(16, Items.SUGAR) > 0, "зельеварение: адский нарост → неуклюжее зелье")


func _test_enchantments() -> void:
	print("Зачарования")
	var d := Enchantments.with_damage(0, 37)
	d = Enchantments.add(d, Enchantments.SHARPNESS, 4)
	d = Enchantments.add(d, Enchantments.UNBREAKING, 3)
	check(Enchantments.damage_of(d) == 37 and Enchantments.level_of(d, Enchantments.SHARPNESS) == 4
		and Enchantments.level_of(d, Enchantments.UNBREAKING) == 3 and Enchantments.level_of(d, Enchantments.SMITE) == 0,
		"зачарования хранятся в данных предмета вместе с износом")
	check(Enchantments.describe(d) == "Острота IV, Прочность III", "названия: %s" % Enchantments.describe(d))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var top := 0
	var bad := 0
	for i in 200:
		var lv := Enchantments.table_levels(Items.DIAMOND_PICKAXE, 15, rng)
		top = maxi(top, lv[2])
		if lv[0] < 1 or lv[0] > lv[1] or lv[1] > lv[2] or lv[2] > 50:
			bad += 1
	check(bad == 0 and top >= 45, "стол с 15 полками: уровни до %d (максимум 50)" % top)
	check(Enchantments.table_levels(Blocks.DIRT, 15, rng) == [0, 0, 0], "землю не зачаровать")
	var wrong := 0
	var any := 0
	for i in 100:
		var e := Enchantments.enchant(Items.DIAMOND_SWORD, 0, 30, rng)
		for en: Array in Enchantments.list(e):
			any += 1
			if not Enchantments.applies(int(en[0]), Items.DIAMOND_SWORD):
				wrong += 1
	check(any >= 100 and wrong == 0, "меч получает только зачарования для оружия (%d)" % any)
	var inv := Inventory.new()
	inv.set_slot(0, Items.IRON_PICKAXE, 1, Enchantments.add(0, Enchantments.UNBREAKING, 3))
	for i in 400:
		inv.damage_slot(0, 1)
	var dmg := Enchantments.damage_of(inv.datas[0])
	check(dmg > 50 and dmg < 160, "прочность III: износ около четверти (%d из 400)" % dmg)
	inv.set_slot(Inventory.ARMOR_START + 3, Items.DIAMOND_BOOTS, 1, Enchantments.add(0, Enchantments.FEATHER_FALLING, 4))
	check(Enchantments.protection_factor(inv, "fall") < 0.5 and is_equal_approx(Enchantments.protection_factor(inv, "mob"), 1.0),
		"невесомость IV снижает урон от падения больше чем вдвое")


func _test_textures() -> void:
	print("Текстуры")
	check(TextureFactory.tiles.size() == Tex.COUNT, "нарисованы все %d тайлов" % Tex.COUNT)
	check(TextureFactory.atlas != null and TextureFactory.atlas.get_layers() == Tex.COUNT, "текстурный массив создан")
	var icon: Image = TextureFactory.icon(Blocks.GRASS).get_image()
	var c := icon.get_width() / 2
	check(icon.get_pixel(c, c).a > 0.9, "иконка травы непрозрачна в центре")
	check(icon.get_pixel(0, 0).a == 0.0, "угол иконки прозрачен")
	var sword: Image = TextureFactory.icon(Items.DIAMOND_SWORD).get_image()
	var opaque := 0
	for y in sword.get_height():
		for x in sword.get_width():
			if sword.get_pixel(x, y).a > 0.5:
				opaque += 1
	check(opaque > 20 and opaque < sword.get_width() * sword.get_height() / 2, "иконка меча — спрайт с прозрачным фоном")
	check(TextureFactory.item_mesh(Items.BOW, 0).get_surface_count() == 1 and TextureFactory.item_mesh(Blocks.CHEST, 0).get_surface_count() == 1,
		"меши предметов для руки")


# --- Генерация и меши ---------------------------------------------------------

func _test_worldgen() -> void:
	print("Генерация мира")
	var gen := WorldGen.new(12345)
	var a: Dictionary = gen.generate_chunk(0, 0)
	var b: Dictionary = WorldGen.new(12345).generate_chunk(0, 0)
	var c: Dictionary = WorldGen.new(999).generate_chunk(0, 0)
	var ab: PackedByteArray = a["blocks"]
	check(ab.size() == WorldGen.VOLUME and (a["meta"] as PackedByteArray).size() == WorldGen.VOLUME, "размер чанка 16×256×16 и данные блоков")
	check((a["biomes"] as PackedByteArray).size() == WorldGen.LAYER, "биомы по колонкам")
	check(ab == b["blocks"] and a["meta"] == b["meta"], "генерация детерминирована")
	check(ab != c["blocks"], "разные сиды дают разные чанки")
	var bedrock := true
	for i in WorldGen.LAYER:
		if ab[i] != Blocks.BEDROCK:
			bedrock = false
	check(bedrock, "на y=0 везде коренная порода")
	var hmin := 999
	var hmax := -1
	var water := 0
	var total := 0
	for z in range(-512, 512, 8):
		for x in range(-512, 512, 8):
			var h := gen.get_height(x, z)
			hmin = mini(hmin, h)
			hmax = maxi(hmax, h)
			total += 1
			if h < WorldGen.SEA_LEVEL:
				water += 1
	print("    высоты: %d..%d, вода: %.0f%%" % [hmin, hmax, 100.0 * water / total])
	check(hmin >= 4 and hmax < WorldGen.CHUNK_HEIGHT - 8, "высоты в допустимых пределах")
	check(water > total * 0.03 and water < total * 0.8, "есть и суша, и водоёмы")
	var logs := 0
	var leaves := 0
	var caves := 0
	var ores := {}
	for cz in range(-3, 3):
		for cx in range(-3, 3):
			var d: PackedByteArray = gen.generate_chunk(cx, cz)["blocks"]
			logs += d.count(Blocks.LOG)
			leaves += d.count(Blocks.LEAVES)
			for y in range(5, 40):
				caves += d.slice(y * WorldGen.LAYER, (y + 1) * WorldGen.LAYER).count(Blocks.AIR)
			for o in [Blocks.COAL_ORE, Blocks.IRON_ORE, Blocks.GOLD_ORE, Blocks.REDSTONE_ORE, Blocks.DIAMOND_ORE, Blocks.LAPIS_ORE]:
				ores[o] = int(ores.get(o, 0)) + d.count(o)
	print("    в 36 чанках: брёвен %d, листвы %d, пустот (y 5..40) %d, руды %s" % [logs, leaves, caves, ores])
	check(logs > 0 and leaves > logs, "есть деревья")
	check(caves > 0, "есть пещеры")
	check(int(ores[Blocks.COAL_ORE]) > int(ores[Blocks.IRON_ORE]) and int(ores[Blocks.IRON_ORE]) > int(ores[Blocks.DIAMOND_ORE])
		and int(ores[Blocks.DIAMOND_ORE]) > 0, "руды: угля больше железа, железа больше алмазов")
	var spawn: Vector2i = gen.find_spawn_column()
	check(gen.get_height(spawn.x, spawn.y) >= WorldGen.SEA_LEVEL, "точка появления на суше")


func _empty_chunks() -> Array:
	var chunks := []
	for i in 9:
		var d := PackedByteArray()
		d.resize(WorldGen.VOLUME)
		chunks.append(d)
	return chunks


func _mesh(blocks: Array, metas: Array = [], top := 20, lights: Array = []) -> Dictionary:
	if metas.is_empty():
		metas = _empty_chunks()
	return ChunkMesher.build({"blocks": blocks, "metas": metas, "lights": lights, "top_y": top, "vol_top": top})


func _single(id: int, meta := 0) -> Array:
	var blocks := _empty_chunks()
	var metas := _empty_chunks()
	_put(blocks, 4, Vector3i(5, 10, 5), id)
	_put(metas, 4, Vector3i(5, 10, 5), meta)
	return [blocks, metas]


## Запись в чанк из списка соседей (через переменную: packed-массив в Array меняется по ссылке).
func _put(chunks: Array, k: int, p: Vector3i, v: int) -> void:
	var c: PackedByteArray = chunks[k]
	c[Chunk.index_of(p.x, p.y, p.z)] = v


func _verts(arr: Array) -> PackedVector3Array:
	return arr[Mesh.ARRAY_VERTEX] if not arr.is_empty() else PackedVector3Array()


func _test_mesher() -> void:
	print("Построение мешей")
	var s := _single(Blocks.STONE)
	var res := _mesh(s[0], s[1])
	var arr: Array = res["opaque"]
	check(arr.size() == Mesh.ARRAY_MAX, "есть непрозрачная поверхность")
	var verts := _verts(arr)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	check(verts.size() == 24 and idx.size() == 36, "одиночный блок: 6 граней (24 вершины, 36 индексов)")
	var center := Vector3(5.5, 10.5, 5.5)
	var cw := true
	for t in range(0, idx.size(), 3):
		var va := verts[idx[t]]
		var vb := verts[idx[t + 1]]
		var vc := verts[idx[t + 2]]
		var n := (vb - va).cross(vc - va)
		var outward := (va + vb + vc) / 3.0 - center
		if n.dot(outward) >= 0.0:
			cw = false
	check(cw, "все треугольники обходятся по часовой стрелке (лицом наружу)")
	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	for v in verts:
		mn = mn.min(v)
		mx = mx.max(v)
	check(mn == Vector3(5, 10, 5) and mx == Vector3(6, 11, 6), "вершины блока в правильной клетке")

	var two := _single(Blocks.STONE)
	_put(two[0], 4, Vector3i(6, 10, 5), Blocks.DIRT)
	check(_verts(_mesh(two[0], two[1])["opaque"]).size() == 40, "два соседних блока: 10 граней")

	var w := _single(Blocks.WATER)
	var water := _mesh(w[0], w[1])
	check((water["opaque"] as Array).is_empty() and not (water["translucent"] as Array).is_empty(), "вода — в полупрозрачной поверхности")
	var top := -INF
	for v in _verts(water["translucent"]):
		top = maxf(top, v.y)
	check(top < 10.95 and top > 10.6, "поверхность одиночного источника ниже края блока (%.3f)" % top)

	var border := _empty_chunks()
	_put(border, 4, Vector3i(15, 10, 5), Blocks.STONE)
	_put(border, 5, Vector3i(0, 10, 5), Blocks.STONE)
	check(_verts(_mesh(border)["opaque"]).size() == 20, "грань на границе чанков скрыта соседом")

	# Формы: плита, факел, ступеньки, забор с соседом.
	var slab := _single(Blocks.SLAB)
	var sv := _verts(_mesh(slab[0], slab[1])["opaque"])
	var smax := -INF
	for v in sv:
		smax = maxf(smax, v.y)
	check(sv.size() == 24 and is_equal_approx(smax, 10.5), "плита: 6 граней высотой полблока")
	var torch := _single(Blocks.TORCH, 5)
	check(_verts(_mesh(torch[0], torch[1])["opaque"]).size() > 0, "факел рисуется")
	var stairs := _single(Blocks.OAK_STAIRS, 0)
	check(_verts(_mesh(stairs[0], stairs[1])["opaque"]).size() >= 40, "ступеньки рисуются двумя частями")
	var fence := _single(Blocks.FENCE)
	var lone := _verts(_mesh(fence[0], fence[1])["opaque"]).size()
	_put(fence[0], 4, Vector3i(6, 10, 5), Blocks.FENCE)
	var joined := _verts(_mesh(fence[0], fence[1])["opaque"]).size()
	check(joined > lone * 2, "соседние заборы соединяются перекладинами (%d → %d вершин)" % [lone, joined])
	# Каждый блок 1.2 строится без ошибок и не пустой (кроме воздуха и служебных).
	var empty: Array[String] = []
	for id in range(1, Blocks.COUNT):
		if id == Blocks.PISTON_MOVING:
			continue
		var one := _single(id, 0)
		var r := _mesh(one[0], one[1])
		if _verts(r["opaque"]).is_empty() and _verts(r["translucent"]).is_empty():
			empty.append(Blocks.block_name(id))
	check(empty.is_empty(), "все блоки видимы при meta 0 %s" % str(empty))

	# AO: блок в углу между двумя стенами затемнён у угла.
	var ao := _empty_chunks()
	var cc: PackedByteArray = ao[4]
	cc[Chunk.index_of(5, 10, 5)] = Blocks.STONE
	cc[Chunk.index_of(4, 11, 5)] = Blocks.STONE
	cc[Chunk.index_of(5, 11, 4)] = Blocks.STONE
	arr = _mesh(ao)["opaque"]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var cv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var corner := -1.0
	var far := -1.0
	for i in cv.size():
		if cv[i] == Vector3(5, 11, 5):
			corner = maxf(corner, uv2[i].y)
		if cv[i] == Vector3(6, 11, 6):
			far = maxf(far, uv2[i].y)
	check(corner > 0.0 and far > corner, "ambient occlusion затемняет внутренний угол (%.2f < %.2f)" % [corner, far])


func _test_light() -> void:
	print("Освещение")
	var blocks := PackedByteArray()
	blocks.resize(WorldGen.VOLUME)
	blocks[Chunk.index_of(8, 20, 8)] = Blocks.TORCH
	blocks[Chunk.index_of(10, 20, 8)] = Blocks.STONE
	var light := ChunkLight.compute(blocks)
	check(light[Chunk.index_of(8, 20, 8)] == 14, "факел светит на 14")
	check(light[Chunk.index_of(9, 20, 8)] == 13 and light[Chunk.index_of(8, 23, 8)] == 11, "свет ослабевает на 1 за блок")
	check(light[Chunk.index_of(10, 20, 8)] == 0, "непрозрачный блок не освещается внутри")
	check(light[Chunk.index_of(11, 20, 8)] == 9, "свет огибает препятствие (14 − 5)")


func _test_inventory() -> void:
	print("Инвентарь")
	var inv := Inventory.new()
	check(inv.add_item(Blocks.DIRT, 100) == 0, "100 земли помещаются")
	check(inv.counts[0] == 64 and inv.counts[1] == 36, "стопки по 64")
	check(inv.count_of(Blocks.DIRT) == 100, "подсчёт предметов")
	check(inv.remove_item(Blocks.DIRT, 50) and inv.count_of(Blocks.DIRT) == 50, "удаление предметов")
	check(not inv.remove_item(Blocks.DIRT, 51), "нельзя удалить больше, чем есть")
	inv.clear()
	inv.add_item(Blocks.WOOL, 3, 14)
	inv.add_item(Blocks.WOOL, 2, 4)
	check(inv.counts[0] == 3 and inv.datas[0] == 14 and inv.counts[1] == 2 and inv.datas[1] == 4, "шерсть разных цветов — разные стопки")
	inv.add_item(Items.IRON_SWORD, 2)
	check(inv.count_of(Items.IRON_SWORD) == 2 and inv.counts[2] == 1 and inv.counts[3] == 1, "мечи не складываются")
	inv.add_item(Items.ENDER_PEARL, 20)
	check(inv.counts[4] == 16 and inv.counts[5] == 4, "жемчуг Края — по 16")
	inv.clear()
	inv.set_slot(0, Blocks.STONE, 10)
	inv.set_slot(1, Blocks.STONE, 60)
	inv.move_slot(0, 1)
	check(inv.counts[1] == 64 and inv.counts[0] == 6, "одинаковые стопки складываются")
	inv.set_slot(2, Blocks.SAND, 5)
	inv.move_slot(0, 2)
	check(inv.ids[0] == Blocks.SAND and inv.ids[2] == Blocks.STONE, "разные стопки меняются местами")
	inv.set_slot(5, Items.DIAMOND_PICKAXE, 1, 37)
	inv.set_slot(Inventory.ARMOR_START + 1, Items.IRON_CHESTPLATE, 1)
	check(inv.armor_points() == 6, "железный нагрудник: 6 очков брони")
	var copy := Inventory.new()
	copy.from_data(JSON.parse_string(JSON.stringify(inv.to_data())))
	check(copy.ids == inv.ids and copy.counts == inv.counts and copy.datas == inv.datas, "сохранение/загрузка через JSON (с износом и бронёй)")
	inv.select(5)
	for i in Items.max_damage(Items.DIAMOND_PICKAXE):
		inv.damage_slot(5, 1)
	check(inv.counts[5] == 0, "инструмент ломается после полного износа")
	inv.select(0)
	inv.consume_selected(5)
	check(inv.counts[0] == 0 and inv.ids[0] == Blocks.AIR, "израсходованный слот очищается")
	var full := Inventory.new()
	check(full.add_item(Blocks.DIRT, 64 * 36 + 5) == 5, "переполнение возвращает остаток")
	var legacy := Inventory.new()
	legacy.from_data([[4, 10], [9, 5]], true)
	check(legacy.ids[0] == Blocks.COBBLESTONE and legacy.ids[1] == Blocks.GLASS, "старые сохранения: номера блоков переводятся")


func _test_storage() -> void:
	print("Сохранения")
	var id := "unit_test_world"
	WorldStorage.delete_world(id)
	var dir := WorldStorage.world_dir(id)
	var data: Dictionary = WorldGen.new(7).generate_chunk(-3, 5)
	var db: PackedByteArray = data["blocks"]
	var dm: PackedByteArray = data["meta"]
	db[Chunk.index_of(1, 100, 2)] = Blocks.WOOL
	dm[Chunk.index_of(1, 100, 2)] = 11
	data["block_entities"] = {Chunk.index_of(1, 101, 2): {"items": [[Items.DIAMOND, 3, 0]]}}
	data["entities"] = [{"kind": "item", "id": Items.APPLE, "count": 2}]
	check(WorldStorage.save_chunk(dir, Vector2i(-3, 5), data), "чанк записан")
	var loaded := WorldStorage.load_chunk(dir, Vector2i(-3, 5))
	check(loaded["blocks"] == data["blocks"] and loaded["meta"] == data["meta"] and loaded["biomes"] == data["biomes"],
		"блоки, данные блоков и биомы прочитаны без изменений")
	var be: Dictionary = loaded["block_entities"].get(Chunk.index_of(1, 101, 2), {})
	check(be.has("items") and int(be["items"][0][0]) == Items.DIAMOND, "содержимое сундука сохраняется")
	check((loaded["entities"] as Array).size() == 1, "предметы на земле сохраняются")
	check(WorldStorage.load_chunk(dir, Vector2i(0, 0)).is_empty(), "несохранённый чанк не найден")
	var size := FileAccess.open(WorldStorage.chunk_path(dir, Vector2i(-3, 5)), FileAccess.READ).get_length()
	print("    размер сжатого чанка: %d байт" % size)
	check(size < WorldGen.VOLUME / 8, "чанк сжимается")
	# Старый формат (BKC1, 16×128×16, старые номера).
	var old := PackedByteArray()
	old.resize(WorldGen.LAYER * WorldStorage.V1_HEIGHT)
	old[Chunk.index_of(0, 5, 0)] = 4 # старый булыжник
	old[Chunk.index_of(1, 5, 0)] = 11 # старая вода
	var f := FileAccess.open_compressed(WorldStorage.chunk_path(dir, Vector2i(9, 9)), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_32(WorldStorage.CHUNK_MAGIC_V1)
	f.store_32(old.size())
	f.store_buffer(old)
	f.close()
	var migrated := WorldStorage.load_chunk(dir, Vector2i(9, 9))
	var mb: PackedByteArray = migrated.get("blocks", PackedByteArray())
	check(mb.size() == WorldGen.VOLUME and mb[Chunk.index_of(0, 5, 0)] == Blocks.COBBLESTONE and mb[Chunk.index_of(1, 5, 0)] == Blocks.WATER,
		"старый чанк переводится в новый формат")
	check(WorldStorage.save_meta(dir, {"name": "Тест", "seed": 7, "creative": false, "last_played": 1.0}), "meta.json записан")
	var meta := WorldStorage.load_meta(dir)
	check(meta.get("name") == "Тест" and int(meta.get("seed")) == 7, "meta.json прочитан")
	var found := false
	for w in WorldStorage.list_worlds():
		if w["id"] == id:
			found = true
	check(found, "мир есть в списке")
	WorldStorage.delete_world(id)
	check(not DirAccess.dir_exists_absolute(dir), "мир удалён вместе с файлами")


# --- Мир, игрок, логика ---------------------------------------------------------

## Плоский мир: камень до y=10.
func _make_flat_world() -> World:
	var w := World.new()
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
	return w


func _make_game(w: World) -> FakeGame:
	var g := FakeGame.new()
	root.add_child(g)
	var logic := BlockLogic.new()
	logic.name = "Logic"
	g.add_child(logic)
	logic.setup(w, g)
	logic.set_process(false)
	var ent := EntityManager.new()
	g.add_child(ent)
	g.entities = ent
	return g


func _ticks(logic: BlockLogic, n: int) -> void:
	for i in n:
		logic.game_tick()


func _test_world_and_player() -> void:
	print("Мир и игрок")
	var w := _make_flat_world()
	var g := _make_game(w)
	var logic: BlockLogic = g.get_node("Logic")
	check(w.get_block(5, 10, 5) == Blocks.STONE and w.get_block(5, 11, 5) == Blocks.AIR, "чтение блоков")
	check(w.get_block(-1, 5, -1) == Blocks.STONE and w.get_block(-17, 5, -17) == Blocks.STONE, "отрицательные координаты")
	var hit := w.raycast(Vector3(5.5, 14.0, 5.5), Vector3.DOWN, 5.0)
	check(not hit.is_empty() and hit["pos"] == Vector3i(5, 10, 5) and hit["normal"] == Vector3i(0, 1, 0), "луч вниз попадает в верхнюю грань")
	check(w.raycast(Vector3(5.5, 16.0, 5.5), Vector3.DOWN, 4.0).is_empty(), "луч ограничен дальностью")
	hit = w.raycast(Vector3(0.5, 11.5, 0.5), Vector3(1, -0.3, 0.2), 6.0)
	check(not hit.is_empty() and int(hit["pos"].y) == 10, "наклонный луч")
	w.set_block(3, 11, 3, Blocks.SLAB, 0)
	hit = w.raycast(Vector3(3.5, 11.9, 2.0), Vector3(0, 0, 1), 4.0)
	check(hit.is_empty() or hit["pos"] != Vector3i(3, 11, 3), "луч проходит над нижней плитой")
	hit = w.raycast(Vector3(3.5, 11.3, 2.0), Vector3(0, 0, 1), 4.0)
	check(not hit.is_empty() and hit["pos"] == Vector3i(3, 11, 3), "луч попадает в плиту ниже середины")
	check(w.set_block(-1, 11, -1, Blocks.BRICKS) and w.get_block(-1, 11, -1) == Blocks.BRICKS, "установка блока")
	var ch: Chunk = w.chunks[Vector2i(-1, -1)]
	check(ch.modified and ch.dirty, "изменённый чанк помечен для сохранения")
	w.set_block(4, 11, 4, Blocks.TORCH, 5)
	check(w.get_block_light(Vector3i(5, 11, 4)) == 13, "факел освещает соседнюю клетку (13)")
	w.set_block(4, 11, 4, Blocks.AIR)
	check(w.get_block_light(Vector3i(5, 11, 4)) == 0, "свет гаснет, когда факел убран")

	var p := Player.new()
	p.world = w
	p.creative = false
	root.add_child(p)
	p.actions = PlayerActions.new(g, w, logic, g.entities)
	g.entities.setup(w, logic, p, g)
	await process_frame
	p.frozen = false
	p.position = Vector3(8.5, 20.0, 8.5)
	for i in 120:
		p._process(1.0 / 60.0)
	check(p.on_ground and absf(p.position.y - 11.0) < 0.01, "игрок падает и встаёт на землю (y=%.3f)" % p.position.y)
	check(p.health < Player.MAX_HEALTH, "урон от падения с 9 блоков (здоровье %d)" % p.health)
	var steady := 0
	for i in 20:
		steady += int(p._accept_mouse_step(15.0))
	var spike := p._accept_mouse_step(200.0)
	var after := p._accept_mouse_step(15.0)
	var flick := 0
	for st: float in [40.0, 160.0, 170.0, 180.0, 175.0]:
		flick += int(p._accept_mouse_step(st))
	check(steady == 20 and not spike and after and flick >= 4, "фильтр скачков мыши (%d/20, рывок %d/5)" % [steady, flick])
	# Стена: игрок не проходит сквозь блок.
	p.health = Player.MAX_HEALTH
	w.set_block(10, 11, 8, Blocks.STONE)
	w.set_block(10, 12, 8, Blocks.STONE)
	p.set_look(-PI / 2.0, 0.0)
	p.touch_move = Vector2(0, -1)
	for i in 90:
		p._process(1.0 / 60.0)
	p.touch_move = Vector2.ZERO
	check(p.position.x < 10.0 - Player.HALF_WIDTH + 0.01 and p.position.x > 9.0, "столкновение со стеной (x=%.3f)" % p.position.x)
	# Ступенька-плита: игрок поднимается на полблока без прыжка.
	w.set_block(10, 12, 8, Blocks.AIR)
	w.set_block(10, 11, 8, Blocks.SLAB, 0)
	p.position = Vector3(8.5, 11.001, 8.5)
	p.touch_move = Vector2(0, -1)
	var on_slab := 0.0
	for i in 40:
		p._process(1.0 / 60.0)
		if p.position.x > 10.3 and p.position.x < 10.7:
			on_slab = p.position.y
	p.touch_move = Vector2.ZERO
	check(absf(on_slab - 11.5) < 0.01, "игрок заходит на плиту без прыжка (y=%.2f)" % on_slab)
	w.set_block(10, 11, 8, Blocks.AIR)
	# Прыжок.
	p.position = Vector3(8.5, 11.001, 8.5)
	for i in 5:
		p._process(1.0 / 60.0)
	p.touch_jump = true
	var peak := 0.0
	for i in 40:
		p._process(1.0 / 60.0)
		peak = maxf(peak, p.position.y)
	p.touch_jump = false
	check(peak > 12.1 and peak < 12.6, "высота прыжка ≈1.25 блока (%.2f)" % (peak - 11.0))
	for i in 30:
		p._process(1.0 / 60.0)
	# Постановка блока через действия игрока.
	p.position = Vector3(8.5, 11.001, 8.5)
	p.target = {"pos": Vector3i(8, 10, 8), "normal": Vector3i(0, 1, 0), "block": Blocks.STONE, "meta": 0, "hit": Vector3(8.5, 11, 8.5)}
	p.inventory.set_slot(0, Blocks.PLANKS, 3)
	p.inventory.select(0)
	check(not p.actions.use(p, true), "нельзя поставить блок туда, где стоит игрок")
	p.target = {"pos": Vector3i(12, 10, 8), "normal": Vector3i(0, 1, 0), "block": Blocks.STONE, "meta": 0, "hit": Vector3(12.5, 11, 8.5)}
	check(p.actions.use(p, true) and w.get_block(12, 11, 8) == Blocks.PLANKS and p.inventory.counts[0] == 2, "блок поставлен и списан из инвентаря")
	p.inventory.set_slot(0, Blocks.FURNACE, 1)
	p.set_look(0.0, 0.0)
	p.target = {"pos": Vector3i(14, 10, 8), "normal": Vector3i(0, 1, 0), "block": Blocks.STONE, "meta": 0, "hit": Vector3(14.5, 11, 8.5)}
	p.actions.use(p, true)
	check(w.get_block(14, 11, 8) == Blocks.FURNACE and w.get_meta_v(Vector3i(14, 11, 8)) == 0, "печь ставится лицом к игроку")
	p.target = {"pos": Vector3i(14, 11, 8), "normal": Vector3i(0, 1, 0), "block": Blocks.FURNACE, "meta": 0, "hit": Vector3(14.5, 12, 8.5)}
	p.actions.use(p, true)
	check(g.opened == "furnace", "правый клик по печи открывает её")
	# Скорость добычи не зависит от FPS и зависит от инструмента.
	for fps: float in [60.0, 8.0]:
		w.set_block(12, 11, 10, Blocks.DIRT)
		p.position = Vector3(12.5, 11.001, 11.5)
		p.set_look(0.0, deg_to_rad(-30.0))
		p.inventory.set_slot(0, Blocks.AIR, 0)
		p.velocity = Vector3.ZERO
		for i in 30:
			p._process(1.0 / 60.0)
		p.touch_break = true
		var t := 0.0
		while w.get_block(12, 11, 10) == Blocks.DIRT and t < 3.0:
			p._process(1.0 / fps)
			t += 1.0 / fps
		p.touch_break = false
		check(absf(t - Blocks.break_time(Blocks.DIRT, Blocks.TOOL_NONE, -1, 1.0)) < 0.2, "земля добывается за %.2f с при %d FPS" % [t, fps])
	w.set_block(12, 11, 10, Blocks.STONE)
	p.inventory.set_slot(0, Items.STONE_PICKAXE, 1)
	for i in 5:
		p._process(1.0 / 60.0)
	p.touch_break = true
	var tp := 0.0
	while w.get_block(12, 11, 10) == Blocks.STONE and tp < 10.0:
		p._process(1.0 / 30.0)
		tp += 1.0 / 30.0
	p.touch_break = false
	check(absf(tp - 0.5625) < 0.15 and p.inventory.datas[0] == 1, "каменная кирка: камень за %.2f с, износ +1" % tp)
	# Голод: бег и прыжки тратят сытость.
	p.food = 20
	p.saturation = 0.0
	p.exhaustion = 3.9
	p.add_exhaustion(0.2)
	p._update_survival(0.01)
	check(p.food == 19, "истощение 4 снимает единицу сытости")
	# Опыт: 7 очков на 1-й уровень, 10 — на 2-й, 14 — на 3-й.
	p.add_xp(17)
	var lvl2 := p.xp_level == 2 and p.xp_progress < 0.001
	p.add_xp(7)
	check(lvl2 and p.xp_level == 2 and absf(p.xp_progress - 0.5) < 0.001, "опыт: 17 очков → уровень 2, ещё 7 → половина шкалы")
	# Броня уменьшает урон.
	p.health = 20
	p.inventory.set_slot(Inventory.ARMOR_START + 1, Items.DIAMOND_CHESTPLATE, 1)
	p._invulnerable = 0.0
	p.take_damage(10, "mob", null)
	check(p.health > 10 and p.health < 20, "броня уменьшает урон (здоровье %d)" % p.health)
	# Креатив: полёт двойным прыжком.
	p.creative = true
	p.on_jump_pressed()
	p.on_jump_pressed()
	check(p.flying, "двойной прыжок включает полёт")
	p.set_flying(false)
	# Сохранение игрока.
	var d := p.to_dict()
	var p2 := Player.new()
	p2.world = w
	root.add_child(p2)
	await process_frame
	p2.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(p2.position.is_equal_approx(p.position) and p2.inventory.counts == p.inventory.counts and p2.xp_level == p.xp_level,
		"игрок сохраняется и загружается")
	p.queue_free()
	p2.queue_free()
	g.queue_free()
	w.queue_free()
	await process_frame


func _test_block_logic() -> void:
	print("Поведение блоков")
	var w := _make_flat_world()
	var g := _make_game(w)
	var logic: BlockLogic = g.get_node("Logic")
	var ent := g.entities
	ent.setup(w, logic, null, g)
	# Вода растекается на 7 блоков по ровной поверхности.
	w.set_block(0, 11, 0, Blocks.WATER, 0)
	_ticks(logic, 200)
	check(Blocks.is_water(w.get_block(7, 11, 0)) and w.get_block(8, 11, 0) == Blocks.AIR, "вода растекается на 7 блоков")
	# Бесконечный источник: два источника рядом создают третий.
	w.set_block(0, 11, 0, Blocks.AIR)
	_ticks(logic, 200)
	check(w.get_block(5, 11, 0) == Blocks.AIR, "без источника текущая вода уходит")
	# Лава + вода → булыжник/обсидиан.
	w.set_block(-5, 11, -5, Blocks.LAVA, 0)
	w.set_block(-5, 12, -5, Blocks.WATER, 0)
	_ticks(logic, 60)
	check(w.get_block(-5, 11, -5) == Blocks.OBSIDIAN, "вода на источник лавы → обсидиан")
	# Песок падает.
	w.set_block(3, 15, 3, Blocks.SAND)
	_ticks(logic, 5)
	for i in 120:
		ent.update(1.0 / 60.0)
	check(w.get_block(3, 15, 3) == Blocks.AIR and w.get_block(3, 11, 3) == Blocks.SAND, "песок падает на землю")
	# Факел без опоры выпадает предметом.
	w.set_block(6, 11, 6, Blocks.STONE)
	w.set_block(6, 12, 6, Blocks.TORCH, 5)
	w.set_block(6, 11, 6, Blocks.AIR)
	_ticks(logic, 2)
	var torch_drop := false
	for n in ent.get_children():
		if n is ItemDrop and (n as ItemDrop).item_id == Blocks.TORCH:
			torch_drop = true
	check(w.get_block(6, 12, 6) == Blocks.AIR and torch_drop, "факел без опоры выпадает")
	# Дверь: две половины, ломается целиком.
	w.set_block(-3, 11, 2, Blocks.WOODEN_DOOR, 0)
	w.set_block(-3, 12, 2, Blocks.WOODEN_DOOR, 8)
	logic.break_naturally(Vector3i(-3, 11, 2))
	check(w.get_block(-3, 12, 2) == Blocks.AIR, "сломанная дверь убирает обе половины")
	# Листва опадает, когда срублено бревно; поставленная игроком — остаётся.
	w.set_block(-8, 14, -8, Blocks.LOG, 0)
	w.set_block(-8, 15, -8, Blocks.LEAVES, 0)
	w.set_block(-7, 14, -8, Blocks.LEAVES, 4)
	_ticks(logic, 300)
	var kept := w.get_block(-8, 15, -8) == Blocks.LEAVES
	w.set_block(-8, 14, -8, Blocks.AIR)
	_ticks(logic, 300)
	check(kept and w.get_block(-8, 15, -8) == Blocks.AIR, "листва без бревна опадает")
	check(w.get_block(-7, 14, -8) == Blocks.LEAVES, "листва, поставленная игроком, не опадает")
	# Пшеница растёт от костной муки.
	w.set_block(9, 10, 9, Blocks.FARMLAND, 7)
	w.set_block(9, 11, 9, Blocks.WHEAT, 0)
	logic.apply_bone_meal(Vector3i(9, 11, 9))
	check(w.get_meta_v(Vector3i(9, 11, 9)) == 7, "костная мука дорастила пшеницу")
	# Саженец вырастает в дерево.
	w.set_block(-12, 10, 12, Blocks.DIRT)
	w.set_block(-12, 11, 12, Blocks.SAPLING, 0)
	var grown := logic.grow_tree(Vector3i(-12, 11, 12), 0)
	check(grown and w.get_block(-12, 11, 12) == Blocks.LOG and w.get_block(-12, 14, 12) == Blocks.LOG, "саженец вырастает в дуб")
	# Взрыв ТНТ оставляет воронку, обсидиан выдерживает.
	w.set_block(0, 10, -12, Blocks.OBSIDIAN)
	logic.explode(Vector3(0.5, 11.5, -10.5), 4.0, false)
	check(w.get_block(0, 10, -11) == Blocks.AIR and w.get_block(0, 10, -12) == Blocks.OBSIDIAN, "взрыв: камень разрушен, обсидиан цел")
	# Печь работает по игровым тикам.
	var fp := Vector3i(4, 11, -4)
	w.set_block(fp.x, fp.y, fp.z, Blocks.FURNACE, 0)
	var be := w.get_block_entity(fp)
	var inv := Inventory.new(3)
	inv.set_slot(0, Blocks.SAND, 2)
	inv.set_slot(1, Blocks.PLANKS, 1)
	Containers.store(be, inv)
	logic.containers.mark_active(fp)
	_ticks(logic, 150)
	check(w.get_block_v(fp) == Blocks.LIT_FURNACE and w.get_block_light(fp + Vector3i(1, 0, 0)) == 12, "горящая печь светится (13)")
	_ticks(logic, 300)
	var out := Containers.load_items(w.get_block_entity(fp), 3)
	check(out.ids[2] == Blocks.GLASS and out.counts[2] == 1, "доски (1,5 предмета) переплавили 1 песок в стекло")
	_ticks(logic, 20)
	check(w.get_block_v(fp) == Blocks.FURNACE, "печь гаснет без топлива")
	g.queue_free()
	w.queue_free()
	await process_frame


# --- Фоновые задачи -----------------------------------------------------------

func _test_threaded_job() -> void:
	print("Фоновые задачи")
	var job := ChunkJob.new()
	job.kind = ChunkJob.GENERATE
	job.key = Vector2i(2, -1)
	job.seed_value = 4242
	var tid := WorkerThreadPool.add_task(job.run, true)
	WorkerThreadPool.wait_for_task_completion(tid)
	check(job.data["blocks"] == WorldGen.new(4242).generate_chunk(2, -1)["blocks"], "генерация в потоке совпадает с обычной")
	check(job.computed_top > WorldGen.SEA_LEVEL - 20 and job.computed_top < WorldGen.CHUNK_HEIGHT, "верхний слой вычислен (%d)" % job.computed_top)
	check(job.light.size() == WorldGen.VOLUME and job.heightmap.size() == WorldGen.LAYER, "свет и карта высот посчитаны в потоке")


func _neighborhood(gen: WorldGen) -> Dictionary:
	var blocks := []
	var metas := []
	var top := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var d: Dictionary = gen.generate_chunk(dx, dz)
			blocks.append(d["blocks"])
			metas.append(d["meta"])
			top = maxi(top, Chunk.compute_top(d["blocks"]))
	return {"blocks": blocks, "metas": metas, "top_y": Chunk.compute_top(blocks[4]), "vol_top": top}


func _test_sliced_jobs() -> void:
	print("Порционные задачи (однопоточная веб-сборка)")
	var gen := WorldGen.new(777)
	gen.begin_chunk(3, -2)
	for z in range(0, WorldGen.CHUNK_SIZE, 3):
		gen.fill_rows(z, mini(z + 3, WorldGen.CHUNK_SIZE))
	check(gen.finish_chunk()["blocks"] == WorldGen.new(777).generate_chunk(3, -2)["blocks"], "генерация по частям совпадает с обычной")
	var input := _neighborhood(gen)
	var full := ChunkMesher.build(input)
	var m := ChunkMesher.begin(input)
	var steps := 1
	while not m.mesh_layers(1):
		steps += 1
	var sliced := m.result()
	check(full["opaque"] == sliced["opaque"] and full["translucent"] == sliced["translucent"],
		"меш по слоям (%d шагов) совпадает с обычным" % steps)
	var job := ChunkJob.new()
	job.kind = ChunkJob.GENERATE
	job.key = Vector2i(-4, 9)
	job.seed_value = 777
	var calls := 0
	while not job.step(Time.get_ticks_usec() + 200):
		calls += 1
	check(calls > 3 and job.data["blocks"] == WorldGen.new(777).generate_chunk(-4, 9)["blocks"],
		"генерация с бюджетом 0,2 мс: %d шагов, результат верный" % (calls + 1))


func _test_single_thread_world() -> void:
	print("Мир в однопоточном режиме")
	var w := World.new()
	w.setup(4242, "", 3)
	w.set("_no_threads", true)
	root.add_child(w)
	var worst := 0
	var frames := 0
	var focus := Vector3(8, 80, 8)
	while not w.is_streaming_idle(focus) and frames < 8000:
		var t0 := Time.get_ticks_usec()
		w.update_streaming(focus)
		worst = maxi(worst, Time.get_ticks_usec() - t0)
		frames += 1
		await process_frame
	check(w.is_streaming_idle(focus) and w.loaded_count() > 40, "мир загрузился без потоков: %d чанков за %d кадров" % [w.loaded_count(), frames])
	print("    самый долгий кадр подгрузки: %.1f мс (бюджет %.0f мс + один шаг)" % [worst / 1000.0, World.SYNC_BUDGET_USEC / 1000.0])
	check(worst < World.SYNC_BUDGET_USEC + 12000, "работа над чанками укладывается в бюджет кадра")
	check(w.set_block(8, 120, 8, Blocks.BRICKS) and w.get_block(8, 120, 8) == Blocks.BRICKS, "правка блока в однопоточном режиме")
	w.queue_free()
	await process_frame


func _test_performance() -> void:
	print("Производительность (отладочная сборка движка)")
	var gen := WorldGen.new(12345)
	var t0 := Time.get_ticks_usec()
	var input := _neighborhood(gen)
	var t_gen := (Time.get_ticks_usec() - t0) / 9000.0
	t0 = Time.get_ticks_usec()
	var light := ChunkLight.compute(input["blocks"][4])
	var t_light := (Time.get_ticks_usec() - t0) / 1000.0
	var lights := []
	for i in 9:
		lights.append(light if i == 4 else PackedByteArray())
	t0 = Time.get_ticks_usec()
	var res := ChunkMesher.build(input)
	var t_mesh := (Time.get_ticks_usec() - t0) / 1000.0
	var faces := _verts(res["opaque"]).size() / 4
	print("    генерация чанка: %.1f мс, свет: %.1f мс, меш: %.1f мс (%d граней)" % [t_gen, t_light, t_mesh, faces])
	check(t_mesh < 600.0, "меш строится за разумное время")
