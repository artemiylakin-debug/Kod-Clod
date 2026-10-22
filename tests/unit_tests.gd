extends SceneTree
## Юнит-тесты логики (без рендеринга).
## Запуск: godot --headless --path . -s res://tests/unit_tests.gd

var _failed := 0
var _passed := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# Раскладка клавиш регистрируется автозагрузкой Game, которой нет в режиме -s.
	var game: Node = load("res://scripts/globals/game.gd").new()
	game.call("_setup_input_map")
	game.free()
	TextureFactory.ensure_initialized()
	_test_blocks()
	_test_textures()
	_test_worldgen()
	_test_mesher()
	_test_inventory()
	_test_storage()
	await _test_world_and_player()
	_test_threaded_job()
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


func _test_blocks() -> void:
	print("Блоки")
	check(Blocks.DEFS.size() == Blocks.COUNT, "DEFS описывает все %d блоков" % Blocks.COUNT)
	check(Blocks.face_tex.size() == Blocks.COUNT * 6, "таблица текстур граней полная")
	var ok := true
	for t in Blocks.face_tex:
		if t < 0 or t >= Blocks.TEXTURE_COUNT:
			ok = false
	check(ok, "все индексы текстур в пределах массива")
	check(not Blocks.is_solid(Blocks.WATER) and Blocks.is_solid(Blocks.STONE), "вода не твёрдая, камень твёрдый")
	check(not Blocks.is_opaque(Blocks.GLASS) and not Blocks.is_opaque(Blocks.LEAVES), "стекло и листва прозрачны для соседних граней")
	check(Blocks.drop_of(Blocks.STONE) == Blocks.COBBLESTONE and Blocks.drop_of(Blocks.GRASS) == Blocks.DIRT, "дроп: камень → булыжник, трава → земля")
	check(not Blocks.creative_palette().has(Blocks.WATER) and not Blocks.creative_palette().has(Blocks.AIR), "в креативной палитре нет воды и воздуха")


func _test_textures() -> void:
	print("Текстуры")
	check(TextureFactory.tiles.size() == Blocks.TEXTURE_COUNT, "сгенерированы все %d тайлов" % Blocks.TEXTURE_COUNT)
	check(TextureFactory.atlas != null and TextureFactory.atlas.get_layers() == Blocks.TEXTURE_COUNT, "текстурный массив создан")
	check(TextureFactory.icons.size() == Blocks.COUNT, "иконки для всех блоков")
	var icon: Image = TextureFactory.icons[Blocks.GRASS].get_image()
	var center := icon.get_pixel(TextureFactory.ICON_SIZE / 2, TextureFactory.ICON_SIZE / 2)
	check(center.a > 0.9, "иконка травы непрозрачна в центре")
	check(icon.get_pixel(0, 0).a == 0.0, "угол иконки прозрачен")


func _test_worldgen() -> void:
	print("Генерация мира")
	var gen := WorldGen.new(12345)
	var a := gen.generate_chunk(0, 0)
	var b := WorldGen.new(12345).generate_chunk(0, 0)
	var c := WorldGen.new(999).generate_chunk(0, 0)
	check(a.size() == WorldGen.VOLUME, "размер чанка %d" % WorldGen.VOLUME)
	check(a == b, "генерация детерминирована")
	check(a != c, "разные сиды дают разные чанки")
	var bedrock := true
	for i in WorldGen.LAYER:
		if a[i] != Blocks.BEDROCK:
			bedrock = false
	check(bedrock, "на y=0 везде коренная порода")
	# Статистика высот и наличие разных биомов.
	var hmin := 999
	var hmax := -1
	var water := 0
	var total := 0
	var snow := 0
	for z in range(-512, 512, 8):
		for x in range(-512, 512, 8):
			var h := gen.get_height(x, z)
			hmin = mini(hmin, h)
			hmax = maxi(hmax, h)
			total += 1
			if h < WorldGen.SEA_LEVEL:
				water += 1
			if h >= WorldGen.SNOW_LINE:
				snow += 1
	print("    высоты: %d..%d, вода: %.0f%%, снег: %.1f%%" % [hmin, hmax, 100.0 * water / total, 100.0 * snow / total])
	check(hmin >= 4 and hmax < WorldGen.CHUNK_HEIGHT - 8, "высоты в допустимых пределах")
	check(water > total * 0.05 and water < total * 0.75, "есть и суша, и водоёмы")
	# Деревья и пещеры.
	var logs := 0
	var leaves := 0
	var caves := 0
	for cz in range(-3, 3):
		for cx in range(-3, 3):
			var d := gen.generate_chunk(cx, cz)
			logs += d.count(Blocks.LOG)
			leaves += d.count(Blocks.LEAVES)
			for y in range(5, 30):
				caves += d.slice(y * WorldGen.LAYER, (y + 1) * WorldGen.LAYER).count(Blocks.AIR)
	print("    в 36 чанках: брёвен %d, листвы %d, пустот пещер (y 5..30) %d" % [logs, leaves, caves])
	check(logs > 0 and leaves > logs, "есть деревья")
	check(caves > 0, "есть пещеры")
	var spawn := gen.find_spawn_column()
	check(gen.get_height(spawn.x, spawn.y) > WorldGen.SEA_LEVEL, "точка появления на суше")


func _single_block_volume(id: int) -> Array:
	var chunks := []
	for i in 9:
		var d := PackedByteArray()
		d.resize(WorldGen.VOLUME)
		chunks.append(d)
	var center: PackedByteArray = chunks[4]
	center[Chunk.index_of(5, 10, 5)] = id
	return chunks


func _test_mesher() -> void:
	print("Построение мешей")
	var res := ChunkMesher.build(_single_block_volume(Blocks.STONE), 10, 10)
	var arr: Array = res["opaque"]
	check(arr.size() == Mesh.ARRAY_MAX, "есть непрозрачная поверхность")
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	check(verts.size() == 24 and idx.size() == 36, "одиночный блок: 6 граней (24 вершины, 36 индексов)")
	# Порядок обхода: в Godot лицевые треугольники идут по часовой стрелке,
	# поэтому (b - a) × (c - a) должен смотреть внутрь блока.
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

	var two := _single_block_volume(Blocks.STONE)
	var center_chunk: PackedByteArray = two[4]
	center_chunk[Chunk.index_of(6, 10, 5)] = Blocks.DIRT
	arr = ChunkMesher.build(two, 10, 10)["opaque"]
	check((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 40, "два соседних блока: 10 граней")

	var water := ChunkMesher.build(_single_block_volume(Blocks.WATER), 10, 10)
	check((water["opaque"] as Array).is_empty() and not (water["water"] as Array).is_empty(), "вода попадает в отдельную поверхность")
	var wverts: PackedVector3Array = (water["water"] as Array)[Mesh.ARRAY_VERTEX]
	var top := -INF
	for v in wverts:
		top = maxf(top, v.y)
	check(is_equal_approx(top, 10.0 + ChunkMesher.WATER_TOP), "поверхность воды чуть ниже края блока")

	# Блок на границе чанка не рисует грань, закрытую соседним чанком.
	var border := _single_block_volume(Blocks.AIR)
	var c4: PackedByteArray = border[4]
	c4[Chunk.index_of(15, 10, 5)] = Blocks.STONE
	var east: PackedByteArray = border[5]
	east[Chunk.index_of(0, 10, 5)] = Blocks.STONE
	arr = ChunkMesher.build(border, 10, 10)["opaque"]
	check((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 20, "грань на границе чанков скрыта соседом")

	# AO: блок в углу между двумя стенами затемнён у угла.
	var ao := _single_block_volume(Blocks.AIR)
	var c: PackedByteArray = ao[4]
	c[Chunk.index_of(5, 10, 5)] = Blocks.STONE
	c[Chunk.index_of(4, 11, 5)] = Blocks.STONE
	c[Chunk.index_of(5, 11, 4)] = Blocks.STONE
	arr = ChunkMesher.build(ao, 11, 11)["opaque"]
	var colors: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var cv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var corner := -1.0
	var far := -1.0
	for i in cv.size():
		if cv[i] == Vector3(5, 11, 5):
			corner = maxf(corner, colors[i].r)
		if cv[i] == Vector3(6, 11, 6):
			far = maxf(far, colors[i].r)
	check(corner > 0.0 and far > corner, "ambient occlusion затемняет внутренний угол (%.2f < %.2f)" % [corner, far])


func _test_inventory() -> void:
	print("Инвентарь")
	var inv := Inventory.new()
	check(inv.add_item(Blocks.DIRT, 100) == 0, "100 земли помещаются")
	check(inv.counts[0] == 64 and inv.counts[1] == 36, "стопки по 64")
	check(inv.count_of(Blocks.DIRT) == 100, "подсчёт предметов")
	check(inv.remove_item(Blocks.DIRT, 50) and inv.count_of(Blocks.DIRT) == 50, "удаление предметов")
	check(not inv.remove_item(Blocks.DIRT, 51), "нельзя удалить больше, чем есть")
	inv.clear()
	inv.set_slot(0, Blocks.STONE, 10)
	inv.set_slot(1, Blocks.STONE, 60)
	inv.move_slot(0, 1)
	check(inv.counts[1] == 64 and inv.counts[0] == 6, "одинаковые стопки складываются")
	inv.set_slot(2, Blocks.SAND, 5)
	inv.move_slot(0, 2)
	check(inv.ids[0] == Blocks.SAND and inv.ids[2] == Blocks.STONE, "разные стопки меняются местами")
	var copy := Inventory.new()
	copy.from_data(JSON.parse_string(JSON.stringify(inv.to_data())))
	check(copy.ids == inv.ids and copy.counts == inv.counts, "сохранение/загрузка через JSON")
	inv.select(0)
	inv.consume_selected(5)
	check(inv.counts[0] == 0 and inv.ids[0] == Blocks.AIR, "израсходованный слот очищается")
	var full := Inventory.new()
	check(full.add_item(Blocks.DIRT, 64 * 36 + 5) == 5, "переполнение возвращает остаток")


func _test_storage() -> void:
	print("Сохранения")
	var id := "unit_test_world"
	WorldStorage.delete_world(id)
	var dir := WorldStorage.world_dir(id)
	var data := WorldGen.new(7).generate_chunk(-3, 5)
	data[Chunk.index_of(1, 100, 2)] = Blocks.BRICKS
	check(WorldStorage.save_chunk(dir, Vector2i(-3, 5), data), "чанк записан")
	var loaded := WorldStorage.load_chunk(dir, Vector2i(-3, 5))
	check(loaded == data, "чанк прочитан без изменений")
	check(WorldStorage.load_chunk(dir, Vector2i(0, 0)).is_empty(), "несохранённый чанк не найден")
	var size := FileAccess.open(WorldStorage.chunk_path(dir, Vector2i(-3, 5)), FileAccess.READ).get_length()
	print("    размер сжатого чанка: %d байт из %d" % [size, data.size()])
	check(size < data.size() / 4, "чанк сжимается")
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


## Плоский мир: камень до y=10, вода в клетке (3, 11, 3).
func _make_flat_world() -> World:
	var w := World.new()
	w.setup(1, "", 2)
	root.add_child(w)
	for cz in range(-2, 3):
		for cx in range(-2, 3):
			var ch := Chunk.new()
			ch.key = Vector2i(cx, cz)
			ch.blocks.resize(WorldGen.VOLUME)
			for y in 11:
				for i in WorldGen.LAYER:
					ch.blocks[y * WorldGen.LAYER + i] = Blocks.STONE
			ch.top_y = 10
			ch.applied_gen = 1
			w.chunks[ch.key] = ch
	return w


func _test_world_and_player() -> void:
	print("Мир и игрок")
	var w := _make_flat_world()
	check(w.get_block(5, 10, 5) == Blocks.STONE and w.get_block(5, 11, 5) == Blocks.AIR, "чтение блоков")
	check(w.get_block(-1, 5, -1) == Blocks.STONE and w.get_block(-17, 5, -17) == Blocks.STONE, "отрицательные координаты")
	var hit := w.raycast(Vector3(5.5, 14.0, 5.5), Vector3.DOWN, 5.0)
	check(not hit.is_empty() and hit["pos"] == Vector3i(5, 10, 5) and hit["normal"] == Vector3i(0, 1, 0), "луч вниз попадает в верхнюю грань")
	hit = w.raycast(Vector3(5.5, 16.0, 5.5), Vector3.DOWN, 4.0)
	check(hit.is_empty(), "луч ограничен дальностью")
	hit = w.raycast(Vector3(0.5, 11.5, 0.5), Vector3(1, -0.3, 0.2), 6.0)
	check(not hit.is_empty() and int(hit["pos"].y) == 10, "наклонный луч")
	check(w.set_block(-1, 11, -1, Blocks.BRICKS) and w.get_block(-1, 11, -1) == Blocks.BRICKS, "установка блока")
	var ch: Chunk = w.chunks[Vector2i(-1, -1)]
	check(ch.modified and ch.dirty, "изменённый чанк помечен для сохранения")
	w.set_block(3, 11, 3, Blocks.WATER)
	w.set_block(4, 11, 3, Blocks.DIRT)
	w.break_block(Vector3i(4, 11, 3))
	check(w.get_block(4, 11, 3) == Blocks.WATER, "вода затекает в сломанный блок рядом")

	var p := Player.new()
	p.world = w
	p.creative = false
	root.add_child(p)
	await process_frame
	p.frozen = false
	p.position = Vector3(8.5, 20.0, 8.5)
	for i in 120:
		p._process(1.0 / 60.0)
	check(p.on_ground and absf(p.position.y - 11.0) < 0.01, "игрок падает и встаёт на землю (y=%.3f)" % p.position.y)
	check(p.health < Player.MAX_HEALTH, "урон от падения с 9 блоков (здоровье %d)" % p.health)
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
	# Прыжок на блок.
	p.position = Vector3(8.5, 11.001, 8.5)
	p.touch_jump = true
	var peak := 0.0
	for i in 40:
		p._process(1.0 / 60.0)
		peak = maxf(peak, p.position.y)
	p.touch_jump = false
	check(peak > 12.1 and peak < 12.6, "высота прыжка ≈1.25 блока (%.2f)" % (peak - 11.0))
	# Постановка блока не внутрь игрока.
	p.position = Vector3(8.5, 11.001, 8.5)
	p.target = {"pos": Vector3i(8, 10, 8), "normal": Vector3i(0, 1, 0), "block": Blocks.STONE}
	p.inventory.set_slot(0, Blocks.PLANKS, 3)
	p.inventory.select(0)
	check(not p.try_place(), "нельзя поставить блок туда, где стоит игрок")
	p.target = {"pos": Vector3i(12, 10, 8), "normal": Vector3i(0, 1, 0), "block": Blocks.STONE}
	check(p.try_place() and w.get_block(12, 11, 8) == Blocks.PLANKS and p.inventory.counts[0] == 2, "блок поставлен и списан из инвентаря")
	# Скорость добычи не зависит от FPS: 8 кадров/с и 60 кадров/с ломают землю за одно время.
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
		check(absf(t - Blocks.hardness(Blocks.DIRT)) < 0.2, "земля добывается за %.2f с при %d FPS" % [t, fps])
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
	check(p2.position.is_equal_approx(p.position) and p2.inventory.counts == p.inventory.counts, "игрок сохраняется и загружается")
	p.queue_free()
	p2.queue_free()
	w.queue_free()
	await process_frame


func _test_threaded_job() -> void:
	print("Фоновые задачи")
	var job := ChunkJob.new()
	job.kind = ChunkJob.GENERATE
	job.key = Vector2i(2, -1)
	job.seed_value = 4242
	var tid := WorkerThreadPool.add_task(job.run, true)
	WorkerThreadPool.wait_for_task_completion(tid)
	check(job.blocks == WorldGen.new(4242).generate_chunk(2, -1), "генерация в потоке совпадает с обычной")
	check(job.computed_top > WorldGen.SEA_LEVEL - 20 and job.computed_top < WorldGen.CHUNK_HEIGHT, "верхний слой вычислен (%d)" % job.computed_top)


func _test_performance() -> void:
	print("Производительность (отладочная сборка движка)")
	var gen := WorldGen.new(12345)
	var t0 := Time.get_ticks_usec()
	var chunks := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			chunks.append(gen.generate_chunk(dx, dz))
	var t_gen := (Time.get_ticks_usec() - t0) / 9000.0
	var top := 0
	for c: PackedByteArray in chunks:
		top = maxi(top, Chunk.compute_top(c))
	t0 = Time.get_ticks_usec()
	var res := ChunkMesher.build(chunks, Chunk.compute_top(chunks[4]), top)
	var t_mesh := (Time.get_ticks_usec() - t0) / 1000.0
	var faces := (res["opaque"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
	print("    генерация чанка: %.1f мс, меш: %.1f мс (%d граней)" % [t_gen, t_mesh, faces])
	check(t_mesh < 400.0, "меш строится за разумное время")
