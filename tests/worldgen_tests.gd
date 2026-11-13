extends SceneTree
## Тесты генераторов миров (Обычный мир, Ад, Край): детерминизм, порционная генерация,
## согласованность построек и деревьев на границах чанков, руды, постройки, время этапов.
## Запуск: godot --headless --path . -s res://tests/worldgen_tests.gd

const SEED := 12345

var _failed := 0
var _passed := 0


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
	_test_determinism(WorldGen, "Обычный мир")
	_test_biomes()
	_test_terrain_and_ores()
	_test_tree_borders()
	_test_village()
	_test_mineshaft()
	_test_stronghold()
	_test_spawn()
	var nether: Script = load("res://scripts/world/gen/nether_gen.gd")
	var end: Script = load("res://scripts/world/gen/end_gen.gd")
	if nether != null:
		_test_determinism(nether, "Ад")
		_test_nether(nether)
	if end != null:
		_test_determinism(end, "Край")
		_test_end(end)
	_test_timings(WorldGen, "Обычный мир", _sample_chunks(48))
	if nether != null:
		_test_timings(nether, "Ад", _sample_chunks(16))
	if end != null:
		_test_timings(end, "Край", [Vector2i(0, 0), Vector2i(1, -2), Vector2i(-3, 2), Vector2i(4, 4), Vector2i(-5, -1),
			Vector2i(2, 5), Vector2i(-2, -4), Vector2i(6, 0)])
	print("\n==== Итог: %d пройдено, %d провалено ====" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


static func _sample_chunks(n: int) -> Array:
	var out := []
	for i in n:
		out.append(Vector2i((i % 8) * 13 - 50, (i / 8) * 11 - 30))
	return out


func _count(d: Dictionary, id: int) -> int:
	return (d["blocks"] as PackedByteArray).count(id)


# --- Общее ---------------------------------------------------------------------

func _test_determinism(script: Script, title: String) -> void:
	print(title + ": детерминизм и порционная генерация")
	var a: Dictionary = script.new(SEED).generate_chunk(3, -2)
	var b: Dictionary = script.new(SEED).generate_chunk(3, -2)
	check(a["blocks"] == b["blocks"] and a["meta"] == b["meta"], "одинаковый сид — одинаковый чанк")
	check((a["blocks"] as PackedByteArray).size() == WorldGen.VOLUME and (a["biomes"] as PackedByteArray).size() == WorldGen.LAYER,
		"размеры массивов чанка")
	# Тот же чанк после генерации других (порядок не важен) и по частям разного размера.
	var g: Object = script.new(SEED)
	g.call("generate_chunk", 4, -2)
	g.call("generate_chunk", 2, -3)
	g.call("begin_chunk", 3, -2)
	var z := 0
	while z < WorldGen.CHUNK_SIZE:
		g.call("fill_rows", z, mini(z + 3, WorldGen.CHUNK_SIZE))
		z += 3
	var c: Dictionary = g.call("finish_chunk")
	check(c["blocks"] == a["blocks"] and c["meta"] == a["meta"], "по частям и в другом порядке — тот же результат")
	check(str(c["block_entities"]) == str(a["block_entities"]) and str(c["entities"]) == str(a["entities"]),
		"контейнеры и существа тоже совпадают")
	var other: Dictionary = script.new(SEED + 1).generate_chunk(3, -2)
	check(other["blocks"] != a["blocks"], "другой сид — другой чанк")


func _test_timings(script: Script, title: String, coords: Array) -> void:
	print(title + ": время этапов (отладочная сборка движка)")
	var worst := PackedFloat64Array()
	var sum := PackedFloat64Array()
	worst.resize(18)
	sum.resize(18)
	var t_all := Time.get_ticks_usec()
	for c: Vector2i in coords:
		var t0 := Time.get_ticks_usec()
		var g: Object = script.new(SEED)
		g.call("begin_chunk", c.x, c.y)
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		worst[0] = maxf(worst[0], dt)
		sum[0] += dt
		for s in 16:
			t0 = Time.get_ticks_usec()
			g.call("fill_rows", s, s + 1)
			dt = (Time.get_ticks_usec() - t0) / 1000.0
			worst[s + 1] = maxf(worst[s + 1], dt)
			sum[s + 1] += dt
		t0 = Time.get_ticks_usec()
		g.call("finish_chunk")
		dt = (Time.get_ticks_usec() - t0) / 1000.0
		worst[17] = maxf(worst[17], dt)
		sum[17] += dt
	var n := coords.size()
	var line := "    begin %.2f/%.2f, " % [sum[0] / n, worst[0]]
	for s in 16:
		line += "%d: %.2f/%.2f, " % [s, sum[s + 1] / n, worst[s + 1]]
	line += "finish %.2f/%.2f (среднее/худшее, мс)" % [sum[17] / n, worst[17]]
	print(line)
	var avg_total := (Time.get_ticks_usec() - t_all) / 1000.0 / n
	print("    чанк целиком: %.1f мс в среднем" % avg_total)
	var avg_ok := true
	for s in 18:
		if sum[s] / n > 4.0:
			avg_ok = false
	check(avg_ok, "каждый шаг в среднем ≤ 4 мс")
	check(avg_total < 60.0, "чанк в среднем быстрее 60 мс")


# --- Обычный мир -----------------------------------------------------------

func _test_biomes() -> void:
	print("Биомы")
	var src := BiomeSource.new(SEED)
	var seen := {}
	for j in range(-300, 300, 3):
		for i in range(-300, 300, 3):
			seen[src.cell(i, j)] = true
	var need := [Biomes.OCEAN, Biomes.PLAINS, Biomes.DESERT, Biomes.EXTREME_HILLS, Biomes.FOREST, Biomes.TAIGA,
		Biomes.SWAMPLAND, Biomes.RIVER, Biomes.ICE_PLAINS, Biomes.BEACH, Biomes.JUNGLE, Biomes.JUNGLE_HILLS,
		Biomes.DESERT_HILLS, Biomes.FOREST_HILLS, Biomes.TAIGA_HILLS, Biomes.EXTREME_HILLS_EDGE]
	var missing := []
	for b: int in need:
		if not seen.has(b):
			missing.append(Biomes.name_of(b))
	check(missing.is_empty(), "в квадрате 2400×2400 есть все основные биомы 1.2 %s" % str(missing))
	var g := WorldGen.new(SEED)
	var d := g.generate_chunk(1, 1)
	var same := true
	for z in 16:
		for x in 16:
			if d["biomes"][x + z * 16] != g.biome_at(16 + x, 16 + z):
				same = false
	check(same, "биомы чанка совпадают с biome_at")


func _test_terrain_and_ores() -> void:
	print("Рельеф и руды")
	var g := WorldGen.new(SEED)
	var ores := {}
	var heights_ok := true
	for cz in range(-2, 2):
		for cx in range(-2, 2):
			var d := g.generate_chunk(cx * 5, cz * 5)
			var blocks: PackedByteArray = d["blocks"]
			for o: int in [Blocks.COAL_ORE, Blocks.IRON_ORE, Blocks.GOLD_ORE, Blocks.REDSTONE_ORE, Blocks.DIAMOND_ORE, Blocks.LAPIS_ORE]:
				ores[o] = int(ores.get(o, 0)) + blocks.count(o)
			for col in 256:
				if blocks[col] != Blocks.BEDROCK:
					heights_ok = false
			# Высота из get_height совпадает с верхним твёрдым блоком рельефа там, где нет построек/деревьев.
			var x := cx * 80 + 5
			var z := cz * 80 + 7
			var h := g.get_height(x, z)
			var lx := x - cx * 80
			var lz := z - cz * 80
			var b := blocks[lx + lz * 16 + h * 256]
			var above := blocks[lx + lz * 16 + (h + 1) * 256]
			if b == Blocks.AIR or b == Blocks.WATER or (above != Blocks.AIR and above != Blocks.WATER and not Blocks.is_replaceable(above) \
					and above != Blocks.LOG and above != Blocks.LEAVES and above != Blocks.CACTUS and above != Blocks.REEDS \
					and above != Blocks.ICE and above != Blocks.PUMPKIN and above != Blocks.MELON):
				if b == Blocks.AIR:
					print("    колонка (%d, %d): get_height=%d, блок %d, над ним %d" % [x, z, h, b, above])
	print("    руды в 16 чанках: ", ores)
	check(heights_ok, "коренная порода на y = 0")
	check(int(ores[Blocks.COAL_ORE]) > int(ores[Blocks.IRON_ORE]) and int(ores[Blocks.IRON_ORE]) > int(ores[Blocks.GOLD_ORE])
		and int(ores[Blocks.REDSTONE_ORE]) > int(ores[Blocks.DIAMOND_ORE]) and int(ores[Blocks.DIAMOND_ORE]) > 0
		and int(ores[Blocks.LAPIS_ORE]) > 0, "соотношение руд как в 1.2")
	# Алмазы и красная руда — только глубоко.
	var deep_ok := true
	var d2 := g.generate_chunk(7, 7)
	var bl: PackedByteArray = d2["blocks"]
	for y in range(20, 128):
		var layer := bl.slice(y * 256, (y + 1) * 256)
		if layer.count(Blocks.DIAMOND_ORE) > 0 or layer.count(Blocks.REDSTONE_ORE) > 0:
			deep_ok = false
	check(deep_ok, "алмазы и красная руда только ниже y = 20")


## Листва на границах чанков: каждая листва рядом с бревном (кроны не обрезаны и не висят в воздухе).
func _test_tree_borders() -> void:
	print("Деревья на границах чанков")
	var g := WorldGen.new(SEED)
	# Ищем лес/джунгли рядом с точкой появления.
	var spawn := g.find_spawn_column()
	var c0 := Vector2i(spawn.x >> 4, spawn.y >> 4)
	var area := {}
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			area[Vector2i(dx, dz)] = WorldGen.new(SEED).generate_chunk(c0.x + dx, c0.y + dz)["blocks"]
	var leaves := 0
	var orphans := 0
	var border_leaves := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var blocks: PackedByteArray = area[Vector2i(dx, dz)]
			var i := blocks.find(Blocks.LEAVES)
			while i >= 0:
				leaves += 1
				var lx := i & 15
				var lz := (i >> 4) & 15
				var y := i >> 8
				if lx == 0 or lx == 15 or lz == 0 or lz == 15:
					border_leaves += 1
				if not _log_near(area, dx * 16 + lx, y, dz * 16 + lz, 7):
					orphans += 1
				i = blocks.find(Blocks.LEAVES, i + 1)
	print("    листвы %d (на границах %d), без бревна поблизости %d" % [leaves, border_leaves, orphans])
	check(leaves > 0 and border_leaves > 0, "кроны пересекают границы чанков")
	check(orphans == 0, "нет листвы, оторванной от ствола")


func _log_near(area: Dictionary, x: int, y: int, z: int, r: int) -> bool:
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var wx := x + dx
			var wz := z + dz
			var key := Vector2i(floori(wx / 16.0), floori(wz / 16.0))
			if not area.has(key):
				return true
			var blocks: PackedByteArray = area[key]
			for dy in range(-r, 3):
				var yy := y + dy
				if yy < 0 or yy > 255:
					continue
				if blocks[(wx - key.x * 16) + ((wz - key.y * 16) << 4) + (yy << 8)] == Blocks.LOG:
					return true
	return false


func _find_village(g: WorldGen) -> Vector2i:
	for r in range(0, 6):
		for rz in range(-r, r + 1):
			for rx in range(-r, r + 1):
				if maxi(absi(rx), absi(rz)) != r:
					continue
				var c := g.village_center(rx, rz)
				if c.x != 1 << 30:
					return c
	return Vector2i(1 << 30, 0)


func _test_village() -> void:
	print("Деревня")
	var g := WorldGen.new(SEED)
	var c := _find_village(g)
	check(c.x != 1 << 30, "деревня нашлась в радиусе ~3000 блоков (%s)" % str(c))
	if c.x == 1 << 30:
		return
	var counts := {}
	var villagers := 0
	var chests := 0
	var cx := c.x >> 4
	var cz := c.y >> 4
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var d := WorldGen.new(SEED).generate_chunk(cx + dx, cz + dz)
			for id: int in [Blocks.COBBLESTONE, Blocks.PLANKS, Blocks.WOODEN_DOOR, Blocks.WHEAT, Blocks.GLASS_PANE, Blocks.TORCH,
					Blocks.GRAVEL, Blocks.SANDSTONE, Blocks.BOOKSHELF, Blocks.FARMLAND]:
				counts[id] = int(counts.get(id, 0)) + _count(d, id)
			for e: Dictionary in d["entities"]:
				if int(e.get("type", 0)) == 120:
					villagers += 1
			for be: Dictionary in (d["block_entities"] as Dictionary).values():
				if be.has("items"):
					chests += 1
	print("    деревня в %s (%s): %s, жителей %d, сундуков %d" % [str(c), Biomes.name_of(g.biome_at(c.x, c.y)), str(counts),
		villagers, chests])
	check(int(counts[Blocks.WOODEN_DOOR]) >= 6 and int(counts[Blocks.TORCH]) > 0, "дома с дверями и фонари")
	check(int(counts[Blocks.WHEAT]) > 0 and int(counts[Blocks.FARMLAND]) > 0, "поля пшеницы")
	check(villagers >= 2, "жители появились")


func _test_mineshaft() -> void:
	print("Заброшенная шахта")
	var g := WorldGen.new(SEED)
	var ms := MineshaftGen.new(SEED)
	var start := Vector2i(1 << 30, 0)
	for r in range(10, 60):
		for t in r * 8:
			var p := WorldGen._ring_cell(r, t)
			if ms.has_start(p.x, p.y):
				start = p
				break
		if start.x != 1 << 30:
			break
	check(start.x != 1 << 30, "шахта нашлась")
	if start.x == 1 << 30:
		return
	var rails := 0
	var fences := 0
	var webs := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var d := WorldGen.new(SEED).generate_chunk(start.x + dx, start.y + dz)
			rails += _count(d, Blocks.RAIL)
			fences += _count(d, Blocks.FENCE)
			webs += _count(d, Blocks.WEB)
	print("    шахта в чанке %s: рельсов %d, заборов %d, паутины %d" % [str(start), rails, fences, webs])
	check(fences > 10, "крепи коридоров")


func _test_stronghold() -> void:
	print("Крепость")
	var g := WorldGen.new(SEED)
	var pos := g.stronghold_positions()
	check(pos.size() == 3, "три крепости")
	var dist_ok := true
	for p: Vector2i in pos:
		var d := sqrt(float(p.x * p.x + p.y * p.y))
		if d < 560 or d > 1250:
			dist_ok = false
	check(dist_ok, "крепости в 640–1152 блоках от начала координат %s" % str(pos))
	var s: Vector2i = pos[0]
	var sh := StrongholdGen.new(SEED)
	var plan := sh.layout(s.x >> 4, s.y >> 4)
	var portal: GenPiece = null
	for p: GenPiece in plan:
		if p.kind == StrongholdGen.PORTAL:
			portal = p
	check(portal != null, "в плане крепости есть комната с порталом (%d частей)" % plan.size())
	if portal == null:
		return
	var frames := 0
	var spawners := 0
	for cz in range(portal.z0 >> 4, (portal.z1 >> 4) + 1):
		for cx in range(portal.x0 >> 4, (portal.x1 >> 4) + 1):
			var d := WorldGen.new(SEED).generate_chunk(cx, cz)
			frames += _count(d, Blocks.END_PORTAL_FRAME)
			for be: Dictionary in (d["block_entities"] as Dictionary).values():
				if int(be.get("mob", 0)) == 60:
					spawners += 1
	check(frames == 12, "рамка портала из 12 блоков (%d)" % frames)
	check(spawners == 1, "рассадник чешуйниц")


func _test_spawn() -> void:
	print("Точка появления")
	for sd: int in [SEED, 1, 777, 4242]:
		var g := WorldGen.new(sd)
		var sp := g.find_spawn_column()
		var h := g.get_height(sp.x, sp.y)
		check(h >= WorldGen.SEA_LEVEL and sp.length() < 400, "сид %d: суша у начала координат %s, высота %d, %s" % [sd, str(sp), h,
			Biomes.name_of(g.biome_at(sp.x, sp.y))])


# --- Ад и Край -------------------------------------------------------------

func _test_nether(script: Script) -> void:
	print("Ад")
	var g: Object = script.new(SEED)
	var nr := 0
	var lava := 0
	var glow := 0
	var bedrock_ok := true
	for cz in range(-2, 2):
		for cx in range(-2, 2):
			var d: Dictionary = g.call("generate_chunk", cx, cz)
			nr += _count(d, Blocks.NETHERRACK)
			lava += _count(d, Blocks.LAVA)
			glow += _count(d, Blocks.GLOWSTONE)
			var b: PackedByteArray = d["blocks"]
			for col in 256:
				if b[col] != Blocks.BEDROCK or b[col + 127 * 256] != Blocks.BEDROCK:
					bedrock_ok = false
			if b.slice(128 * 256).count(Blocks.AIR) != 128 * 256:
				bedrock_ok = false
	check(nr > 0 and lava > 0 and glow > 0, "адский камень, лава и светокамень")
	check(bedrock_ok, "коренная порода снизу и сверху, выше 127 — пусто")
	var sp: Vector2i = g.call("find_spawn_column")
	var h: int = g.call("get_height", sp.x, sp.y)
	check(h > 31 and h < 120, "точка появления в Аду на твёрдом полу (%s, y=%d)" % [str(sp), h])
	# Крепость: ищем ближайшую и проверяем адский кирпич и рассадники ифритов.
	var fort: Vector2i = g.call("fortress_near", 0, 0)
	check(fort.x != 1 << 30, "адская крепость нашлась (%s)" % str(fort))
	if fort.x != 1 << 30:
		var bricks := 0
		var blaze := 0
		var wart := 0
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				var d: Dictionary = script.new(SEED).generate_chunk((fort.x >> 4) + dx, (fort.y >> 4) + dz)
				bricks += _count(d, Blocks.NETHER_BRICK)
				wart += _count(d, Blocks.NETHER_WART)
				for be: Dictionary in (d["block_entities"] as Dictionary).values():
					if int(be.get("mob", 0)) == 61:
						blaze += 1
		print("    крепость: кирпичей %d, нароста %d, рассадников ифритов %d" % [bricks, wart, blaze])
		check(bricks > 500, "крепость из адского кирпича")


func _test_end(script: Script) -> void:
	print("Край")
	var g: Object = script.new(SEED)
	var stone := 0
	var obsidian := 0
	var crystals := 0
	for cz in range(-5, 5):
		for cx in range(-5, 5):
			var d: Dictionary = g.call("generate_chunk", cx, cz)
			stone += _count(d, Blocks.END_STONE)
			obsidian += _count(d, Blocks.OBSIDIAN)
			for e: Dictionary in d["entities"]:
				if int(e.get("type", 0)) == 200:
					crystals += 1
	var far: Dictionary = g.call("generate_chunk", 40, 40)
	print("    камня Края %d, обсидиана %d, кристаллов %d" % [stone, obsidian, crystals])
	check(stone > 10000 and obsidian > 100 and crystals >= 4, "остров из камня Края, обсидиановые столбы с кристаллами")
	check(_count(far, Blocks.AIR) == WorldGen.VOLUME, "вдали от острова — пустота")
	var sp: Vector2i = g.call("find_spawn_column")
	var h: int = g.call("get_height", sp.x, sp.y)
	check(h > 20, "точка появления на острове (%s, y=%d)" % [str(sp), h])
