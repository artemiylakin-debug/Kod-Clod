class_name PlayerActions
extends RefCounted
## Действия игрока: удар, использование предмета (правая кнопка / тап), взаимодействие с блоками,
## установка блоков с ориентацией, еда и зелья, стрельба из лука. Связывает игрока, мир, логику
## блоков, существ и интерфейс (через игровую сцену).

var game: Node
var world: World
var logic: BlockLogic
var entities: EntityManager
var rng := RandomNumberGenerator.new()


func _init(p_game: Node, p_world: World, p_logic: BlockLogic, p_entities: EntityManager) -> void:
	game = p_game
	world = p_world
	logic = p_logic
	entities = p_entities
	rng.randomize()


## Звук и эффекты — через игровую сцену (если она их поддерживает).
func _sound(sound_name: String, p: Vector3, vol := 1.0) -> void:
	if game != null and game.has_method("play_sound"):
		game.call("play_sound", sound_name, p, vol)


func _effect(kind: String, p: Vector3, data := 0) -> void:
	if game != null and game.has_method("effect"):
		game.call("effect", kind, p, data)


func _placed(p: Vector3i, id: int) -> void:
	if game != null and game.has_method("on_block_placed"):
		game.call("on_block_placed", p, id)


## Блоки, на которые действует правая кнопка (вместо установки предмета).
func is_usable_block(id: int) -> bool:
	return id in [Blocks.CRAFTING_TABLE, Blocks.FURNACE, Blocks.LIT_FURNACE, Blocks.CHEST, Blocks.DISPENSER,
		Blocks.WOODEN_DOOR, Blocks.TRAPDOOR, Blocks.FENCE_GATE, Blocks.LEVER, Blocks.STONE_BUTTON, Blocks.BED,
		Blocks.CAKE, Blocks.REPEATER_OFF, Blocks.REPEATER_ON, Blocks.NOTE_BLOCK, Blocks.JUKEBOX,
		Blocks.ENCHANTING_TABLE, Blocks.BREWING_STAND, Blocks.CAULDRON, Blocks.DRAGON_EGG, Blocks.REDSTONE_ORE,
		Blocks.LOCKED_CHEST]


# --- Удар ------------------------------------------------------------------

## Левая кнопка по существу. true — удар нанесён (блок не ломаем).
func attack(player: Player) -> bool:
	var hit := entities.raycast(player.eye_position(), player.look_dir(), 3.5)
	if hit.is_empty():
		return false
	if not player.target.is_empty():
		var block_dist: float = player.eye_position().distance_to(player.target["hit"])
		if block_dist < float(hit["dist"]):
			return false
	var item := player.inventory.selected_id()
	var idata := player.inventory.selected_data()
	var dmg := Items.attack_damage(item)
	# Острота, небесная кара (нежить), бич членистоногих: + случайно до 3 (4) за уровень, как в 1.2.
	var mob_type := int(hit["entity"].get("type")) if hit["entity"] is Object and hit["entity"].get("type") != null else -1
	var bonus := Enchantments.level_of(idata, Enchantments.SHARPNESS) * 3
	if mob_type in [51, 54, 57]:
		bonus += Enchantments.level_of(idata, Enchantments.SMITE) * 4
	if mob_type in [52, 59, 60]:
		bonus += Enchantments.level_of(idata, Enchantments.BANE_OF_ARTHROPODS) * 4
	if bonus > 0:
		dmg += rng.randi_range(0, bonus)
		if hit["entity"] is Node3D:
			_effect("magic_crit", (hit["entity"] as Node3D).position + Vector3(0, 1.0, 0))
	if player.effects.has(Potions.STRENGTH):
		dmg += 3 << int(player.effects[Potions.STRENGTH][0])
	if player.effects.has(Potions.WEAKNESS):
		dmg -= 2
	# Критический удар в падении.
	var target: Node3D = hit["entity"] as Node3D
	if not player.on_ground and player.velocity.y < 0.0 and not player.in_water and not player.on_ladder:
		@warning_ignore("integer_division")
		dmg += rng.randi_range(0, dmg / 2 + 1)
		if target != null:
			_effect("crit", target.position + Vector3(0, 1.0, 0))
	entities.attack(hit["entity"], maxi(dmg, 0))
	if target != null:
		# Отбрасывание и заговор огня.
		var kb := Enchantments.level_of(idata, Enchantments.KNOCKBACK)
		if kb > 0 and target.get("velocity") is Vector3:
			var dir := (target.position - player.position) * Vector3(1, 0, 1)
			target.set("velocity", (target.get("velocity") as Vector3) + dir.normalized() * 5.0 * kb + Vector3(0, 1.5, 0))
		var fa := Enchantments.level_of(idata, Enchantments.FIRE_ASPECT)
		if fa > 0:
			for prop: String in ["fire_time", "fire"]:
				if target.get(prop) is float:
					target.set(prop, maxf(float(target.get(prop)), 4.0 * fa))
					break
	player.add_exhaustion(0.3)
	if Items.is_damageable(item) and not player.creative:
		player.inventory.damage_slot(player.inventory.selected, 1 if Items.is_sword(item) else 2)
	return true


# --- Разрушение блока ------------------------------------------------------

func on_block_break(player: Player, pos: Vector3i, id: int, meta: int) -> void:
	var tool := player.held_tool()
	var tier := player.held_tier()
	if player.creative:
		logic._remove_with_partner(pos, id, meta)
		return
	# Лёд превращается в воду, если под ним не пустота.
	if id == Blocks.ICE:
		world.set_block(pos.x, pos.y, pos.z, Blocks.AIR)
		var below := world.get_block_v(pos + Vector3i(0, -1, 0))
		if below != Blocks.AIR and not Blocks.is_liquid(below):
			world.set_block(pos.x, pos.y, pos.z, Blocks.WATER)
		return
	if id == Blocks.MONSTER_EGG and entities.mobs != null:
		world.set_block(pos.x, pos.y, pos.z, Blocks.AIR)
		entities.spawn_mob(60, Vector3(pos) + Vector3(0.5, 0, 0.5))
		return
	var idata := player.inventory.selected_data()
	# Шёлковое касание: блок выпадает целиком (камень, руды, стекло, трава, лёд, полки…).
	if Enchantments.level_of(idata, Enchantments.SILK_TOUCH) > 0 and _silk_drop(id) and Blocks.can_harvest(id, tool, tier):
		logic._remove_with_partner(pos, id, meta)
		var m := meta & 3 if id == Blocks.LEAVES else (0 if id == Blocks.LIT_REDSTONE_ORE else meta)
		entities.spawn_drop(Blocks.REDSTONE_ORE if id == Blocks.LIT_REDSTONE_ORE else id, 1, m, Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		return
	logic.break_naturally(pos, tool, tier)
	# Удача: дополнительные предметы из руд.
	var fortune := Enchantments.level_of(idata, Enchantments.FORTUNE)
	if fortune > 0 and id in [Blocks.COAL_ORE, Blocks.DIAMOND_ORE, Blocks.LAPIS_ORE, Blocks.REDSTONE_ORE, Blocks.LIT_REDSTONE_ORE, Blocks.GLOWSTONE] \
			and Blocks.can_harvest(id, tool, tier):
		var extra := maxi(rng.randi_range(0, fortune + 1) - 1, 0)
		if extra > 0:
			for d: Array in Blocks.drops(id, meta, tool, tier, rng):
				entities.spawn_drop(int(d[0]), int(d[1]) * extra, int(d[2]), Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	# Опыт за руду.
	if Blocks.can_harvest(id, tool, tier):
		var xp := 0
		match id:
			Blocks.COAL_ORE:
				xp = rng.randi_range(0, 2)
			Blocks.DIAMOND_ORE:
				xp = rng.randi_range(3, 7)
			Blocks.REDSTONE_ORE, Blocks.LIT_REDSTONE_ORE:
				xp = rng.randi_range(1, 5)
			Blocks.LAPIS_ORE:
				xp = rng.randi_range(2, 5)
		if xp > 0:
			entities.spawn_xp(Vector3(pos) + Vector3(0.5, 0.5, 0.5), xp)


# --- Использование (правая кнопка) -----------------------------------------

## first — первое нажатие (а не удержание). true — что-то произошло.
func use(player: Player, first: bool) -> bool:
	var inv := player.inventory
	var id := inv.selected_id()
	var data := inv.selected_data()
	# Существо под прицелом.
	if first:
		var hit := entities.raycast(player.eye_position(), player.look_dir(), 3.5)
		if not hit.is_empty():
			var closer := player.target.is_empty() or player.eye_position().distance_to(player.target["hit"]) > float(hit["dist"])
			if closer and entities.interact(hit["entity"]):
				return true
	var t := player.target
	# Блок с действием (кроме приседания — тогда ставим предмет рядом).
	if first and not t.is_empty() and not player.sneaking and is_usable_block(int(t["block"])):
		if _use_block(player, t):
			return true
	# Предметы, которые не ставятся как блок.
	if first and _use_item(player, id, data, t):
		return true
	if t.is_empty():
		return false
	return _place(player, id, data, t)


func _use_block(player: Player, t: Dictionary) -> bool:
	var p: Vector3i = t["pos"]
	var id: int = t["block"]
	var meta: int = t.get("meta", 0)
	match id:
		Blocks.CRAFTING_TABLE:
			game.call("open_container", "crafting", p)
		Blocks.FURNACE, Blocks.LIT_FURNACE:
			game.call("open_container", "furnace", p)
		Blocks.CHEST, Blocks.LOCKED_CHEST:
			if Blocks.is_opaque(world.get_block_v(p + Vector3i(0, 1, 0))):
				return true
			_sound("chest_open", Vector3(p) + Vector3(0.5, 0.5, 0.5), 0.6)
			game.call("open_container", "chest", p)
		Blocks.DISPENSER:
			game.call("open_container", "dispenser", p)
		Blocks.ENCHANTING_TABLE:
			game.call("open_container", "enchanting", p)
		Blocks.BREWING_STAND:
			game.call("open_container", "brewing", p)
		Blocks.WOODEN_DOOR:
			_toggle_door(p, id, meta)
		Blocks.TRAPDOOR, Blocks.FENCE_GATE:
			var m := meta ^ 4
			if id == Blocks.FENCE_GATE and m & 4:
				# Калитка открывается от игрока.
				m = (m & ~3) | player.facing()
			world.set_block(p.x, p.y, p.z, id, m)
			_sound("door_open" if m & 4 else "door_close", Vector3(p) + Vector3(0.5, 0.5, 0.5), 0.7)
		Blocks.LEVER:
			world.set_block(p.x, p.y, p.z, id, meta ^ 8)
			_sound("click", Vector3(p) + Vector3(0.5, 0.5, 0.5), 0.5)
		Blocks.STONE_BUTTON:
			if meta & 8 == 0:
				world.set_block(p.x, p.y, p.z, id, meta | 8)
				logic.schedule(p, 20)
				_sound("click", Vector3(p) + Vector3(0.5, 0.5, 0.5), 0.5)
		Blocks.REPEATER_OFF, Blocks.REPEATER_ON:
			world.set_block(p.x, p.y, p.z, id, (meta + 4) & 15)
		Blocks.BED:
			game.call("try_sleep", p)
		Blocks.CAKE:
			if player.food >= Player.MAX_FOOD and not player.creative:
				return false
			player.eat(2, 0.4)
			if meta >= 5:
				world.set_block(p.x, p.y, p.z, Blocks.AIR)
			else:
				world.set_block(p.x, p.y, p.z, id, meta + 1)
		Blocks.NOTE_BLOCK:
			var be := world.get_block_entity(p)
			be["note"] = (int(be.get("note", 0)) + 1) % 25
			world.mark_dirty(p)
			game.call("play_note", p, int(be["note"]))
		Blocks.JUKEBOX:
			var be := world.get_block_entity(p)
			var rec := int(be.get("record", 0))
			if rec != 0:
				be["record"] = 0
				world.mark_dirty(p)
				if game.has_method("play_record"):
					game.call("play_record", 0, p)
				entities.spawn_drop(rec, 1, 0, Vector3(p) + Vector3(0.5, 1.1, 0.5))
				game.call("show_toast", "Пластинка извлечена")
			elif Items.is_record(player.inventory.selected_id()):
				be["record"] = player.inventory.selected_id()
				world.mark_dirty(p)
				if not player.creative:
					player.inventory.consume_selected(1)
				game.call("show_toast", "Играет: %s" % Items.name_of(int(be["record"])))
				if game.has_method("play_record"):
					game.call("play_record", int(be["record"]), p)
			else:
				return false
		Blocks.CAULDRON:
			return _use_cauldron(player, p, meta)
		Blocks.DRAGON_EGG:
			_teleport_egg(p)
		Blocks.REDSTONE_ORE:
			world.set_block(p.x, p.y, p.z, Blocks.LIT_REDSTONE_ORE)
			return false
		_:
			return false
	return true


func _toggle_door(p: Vector3i, id: int, meta: int) -> void:
	var lower := p + Vector3i(0, -1, 0) if meta & 8 else p
	var upper := lower + Vector3i(0, 1, 0)
	var m := world.get_meta_v(lower) ^ 4
	world.set_block(lower.x, lower.y, lower.z, id, m & 7)
	world.set_block(upper.x, upper.y, upper.z, id, (m & 7) | 8)
	_sound("door_open" if m & 4 else "door_close", Vector3(upper), 0.7)


func _use_cauldron(player: Player, p: Vector3i, meta: int) -> bool:
	var id := player.inventory.selected_id()
	if id == Items.WATER_BUCKET:
		world.set_block(p.x, p.y, p.z, Blocks.CAULDRON, 3)
		if not player.creative:
			player.inventory.replace_selected(Items.BUCKET)
		return true
	if id == Items.GLASS_BOTTLE and meta > 0:
		world.set_block(p.x, p.y, p.z, Blocks.CAULDRON, meta - 1)
		player.inventory.replace_selected(Items.POTION, 0)
		return true
	return false


func _teleport_egg(p: Vector3i) -> void:
	for k in 100:
		var q := p + Vector3i(rng.randi_range(-15, 15), rng.randi_range(-7, 7), rng.randi_range(-15, 15))
		if world.get_block_v(q) == Blocks.AIR and Blocks.is_solid(world.get_block_v(q + Vector3i(0, -1, 0))):
			world.set_block(p.x, p.y, p.z, Blocks.AIR)
			world.set_block(q.x, q.y, q.z, Blocks.DRAGON_EGG)
			return


## Особые предметы. true — использованы.
func _use_item(player: Player, id: int, data: int, t: Dictionary) -> bool:
	var inv := player.inventory
	var has_target := not t.is_empty()
	var tp: Vector3i = t.get("pos", Vector3i.ZERO)
	var np: Vector3i = tp + t.get("normal", Vector3i.ZERO)
	var tb: int = t.get("block", 0)
	match id:
		Items.BUCKET:
			if has_target and Blocks.is_liquid(tb) and world.get_meta_v(tp) == 0:
				world.set_block(tp.x, tp.y, tp.z, Blocks.AIR)
				_sound("splash" if Blocks.is_water(tb) else "fizz", Vector3(tp) + Vector3(0.5, 0.5, 0.5), 0.5)
				if not player.creative:
					inv.replace_selected(Items.WATER_BUCKET if Blocks.is_water(tb) else Items.LAVA_BUCKET)
				return true
			return false
		Items.WATER_BUCKET, Items.LAVA_BUCKET:
			if not has_target:
				return false
			var cell := np if not Blocks.is_replaceable(tb) else tp
			var cur := world.get_block_v(cell)
			if cur != Blocks.AIR and not Blocks.is_replaceable(cur):
				return false
			if id == Items.WATER_BUCKET and world.dimension == -1:
				game.call("show_toast", "Вода испарилась")
				_sound("fizz", Vector3(cell) + Vector3(0.5, 0.5, 0.5))
				_effect("smoke", Vector3(cell) + Vector3(0.5, 0.5, 0.5))
			else:
				world.set_block(cell.x, cell.y, cell.z, Blocks.WATER if id == Items.WATER_BUCKET else Blocks.LAVA, 0)
				_sound("splash" if id == Items.WATER_BUCKET else "fizz", Vector3(cell) + Vector3(0.5, 0.5, 0.5), 0.5)
			if not player.creative:
				inv.replace_selected(Items.BUCKET)
			return true
		Items.FLINT_AND_STEEL, Items.FIRE_CHARGE:
			if not has_target:
				return false
			if tb == Blocks.TNT:
				logic.ignite_tnt(tp)
				_sound("fuse", Vector3(tp) + Vector3(0.5, 0.5, 0.5))
			elif not logic.place_fire(np):
				return false
			else:
				_sound("click", Vector3(np) + Vector3(0.5, 0.5, 0.5), 0.6)
			if not player.creative:
				if id == Items.FLINT_AND_STEEL:
					inv.damage_slot(inv.selected)
				else:
					inv.consume_selected(1)
			return true
		Items.WOODEN_HOE, Items.STONE_HOE, Items.IRON_HOE, Items.DIAMOND_HOE, Items.GOLDEN_HOE:
			if has_target and (tb == Blocks.GRASS or tb == Blocks.DIRT) and t.get("normal") != Vector3i(0, -1, 0) \
					and world.get_block_v(tp + Vector3i(0, 1, 0)) == Blocks.AIR:
				world.set_block(tp.x, tp.y, tp.z, Blocks.FARMLAND, 0)
				if tb == Blocks.GRASS and rng.randi_range(0, 7) == 0:
					entities.spawn_drop(Items.SEEDS, 1, 0, Vector3(tp) + Vector3(0.5, 1.2, 0.5))
				if not player.creative:
					inv.damage_slot(inv.selected)
				return true
			return false
		Items.DYE:
			if data == Items.DYE_BONE_MEAL and has_target and logic.apply_bone_meal(tp):
				if not player.creative:
					inv.consume_selected(1)
				return true
			return false
		Items.SEEDS, Items.PUMPKIN_SEEDS, Items.MELON_SEEDS, Items.NETHER_WART:
			if not has_target or t.get("normal") != Vector3i(0, 1, 0):
				return false
			var need := Blocks.SOUL_SAND if id == Items.NETHER_WART else Blocks.FARMLAND
			if tb != need or world.get_block_v(np) != Blocks.AIR:
				return false
			var plant: int = {Items.SEEDS: Blocks.WHEAT, Items.PUMPKIN_SEEDS: Blocks.PUMPKIN_STEM,
				Items.MELON_SEEDS: Blocks.MELON_STEM, Items.NETHER_WART: Blocks.NETHER_WART}[id]
			world.set_block(np.x, np.y, np.z, plant, 0)
			if not player.creative:
				inv.consume_selected(1)
			return true
		Items.SNOWBALL, Items.EGG, Items.ENDER_PEARL, Items.EXPERIENCE_BOTTLE:
			var type: String = {Items.SNOWBALL: "snowball", Items.EGG: "egg", Items.ENDER_PEARL: "ender_pearl",
				Items.EXPERIENCE_BOTTLE: "xp_bottle"}[id]
			_throw(player, type, 0, 22.0 if id != Items.EXPERIENCE_BOTTLE else 14.0)
			if not player.creative:
				inv.consume_selected(1)
			return true
		Items.POTION:
			if Potions.is_splash(data):
				_throw(player, "potion", data, 12.0)
				if not player.creative:
					inv.consume_selected(1)
				return true
			return false
		Items.GLASS_BOTTLE:
			var wt := player.world.raycast(player.eye_position(), player.look_dir(), player.reach(), true)
			if not wt.is_empty() and Blocks.is_water(int(wt["block"])):
				inv.replace_selected(Items.POTION, 0)
				return true
			return false
		Items.SPAWN_EGG:
			if not has_target:
				return false
			var m := entities.spawn_mob(data, Vector3(np) + Vector3(0.5, 0.0, 0.5))
			if m != null and not player.creative:
				inv.consume_selected(1)
			return m != null
		Items.ENDER_EYE:
			if has_target and tb == Blocks.END_PORTAL_FRAME and world.get_meta_v(tp) & 4 == 0:
				world.set_block(tp.x, tp.y, tp.z, tb, world.get_meta_v(tp) | 4)
				if not player.creative:
					inv.consume_selected(1)
				game.call("check_end_portal", tp)
				return true
			_throw(player, "ender_pearl", 0, 0.0)
			return false
		Blocks.WATERLILY:
			var wt := world.raycast(player.eye_position(), player.look_dir(), player.reach(), true)
			if wt.is_empty() or int(wt["block"]) != Blocks.WATER:
				return false
			var above: Vector3i = wt["pos"] + Vector3i(0, 1, 0)
			if world.get_block_v(above) != Blocks.AIR:
				return false
			world.set_block(above.x, above.y, above.z, Blocks.WATERLILY)
			_consume(player)
			return true
		Items.MAP, Items.COMPASS, Items.CLOCK:
			game.call("show_item_info", id)
			return true
		Items.FISHING_ROD:
			game.call("use_fishing_rod")
			return true
		Items.MINECART, Items.CHEST_MINECART, Items.FURNACE_MINECART, Items.BOAT, Items.PAINTING, Items.SADDLE:
			if has_target and game.has_method("place_vehicle") and bool(game.call("place_vehicle", id, t)):
				if not player.creative:
					inv.consume_selected(1)
				return true
			return false
	return false


func _throw(player: Player, type: String, data: int, speed: float) -> void:
	var dir := player.look_dir()
	var pos := player.eye_position() + dir * 0.4 - Vector3(0, 0.1, 0)
	entities.spawn_projectile(type, pos, dir * speed + player.velocity * 0.5, player, 0.0, data)


# --- Установка блоков ------------------------------------------------------

## Какой блок и с какими данными ставит предмет (id, data). [-1] — не ставится.
func _block_for_item(id: int, data: int) -> Array:
	if Items.is_block(id):
		return [id, data & 15]
	match id:
		Items.REDSTONE:
			return [Blocks.REDSTONE_WIRE, 0]
		Items.REEDS:
			return [Blocks.REEDS, 0]
		Items.SIGN:
			return [Blocks.SIGN_POST, 0]
		Items.WOODEN_DOOR:
			return [Blocks.WOODEN_DOOR, 0]
		Items.IRON_DOOR:
			return [Blocks.IRON_DOOR, 0]
		Items.BED:
			return [Blocks.BED, 0]
		Items.CAKE:
			return [Blocks.CAKE, 0]
		Items.REPEATER:
			return [Blocks.REPEATER_OFF, 0]
		Items.CAULDRON:
			return [Blocks.CAULDRON, 0]
		Items.BREWING_STAND:
			return [Blocks.BREWING_STAND, 0]
	return [-1]


func _place(player: Player, id: int, data: int, t: Dictionary) -> bool:
	var spec := _block_for_item(id, data)
	var block: int = spec[0]
	if block < 0:
		return false
	var meta: int = spec[1] if spec.size() > 1 else 0
	var tp: Vector3i = t["pos"]
	var normal: Vector3i = t["normal"]
	var tb := world.get_block_v(tp)
	var face := Blocks.FACE_VEC.find(normal)
	# Плита на плиту того же вида — двойная плита.
	if block == Blocks.SLAB and tb == Blocks.SLAB and normal == Vector3i(0, 1, 0) and (world.get_meta_v(tp) & 7) == (meta & 7):
		world.set_block(tp.x, tp.y, tp.z, Blocks.DOUBLE_SLAB, meta & 7)
		_consume(player)
		return true
	# Снег на снег — толще.
	if block == Blocks.SNOW_LAYER and tb == Blocks.SNOW_LAYER and world.get_meta_v(tp) < 7:
		world.set_block(tp.x, tp.y, tp.z, Blocks.SNOW_LAYER, world.get_meta_v(tp) + 1)
		_consume(player)
		return true
	var p := tp + normal
	if Blocks.is_replaceable(tb) and tb != Blocks.AIR and not Blocks.is_liquid(tb):
		p = tp
		face = 2
	if p.y < 0 or p.y >= WorldGen.CHUNK_HEIGHT:
		return false
	var cur := world.get_block_v(p)
	if not Blocks.is_replaceable(cur):
		return false
	var facing := player.facing()
	var toward := (facing + 2) % 4
	match block:
		Blocks.FURNACE, Blocks.CHEST, Blocks.DISPENSER, Blocks.PUMPKIN, Blocks.JACK_O_LANTERN, Blocks.END_PORTAL_FRAME:
			meta = toward
		Blocks.OAK_STAIRS, Blocks.COBBLESTONE_STAIRS, Blocks.BRICK_STAIRS, Blocks.STONE_BRICK_STAIRS, Blocks.NETHER_BRICK_STAIRS:
			meta = facing
		Blocks.REPEATER_OFF, Blocks.FENCE_GATE:
			meta = facing
		Blocks.LEAVES:
			meta = (meta & 3) | 4
		Blocks.TORCH, Blocks.REDSTONE_TORCH, Blocks.LEVER, Blocks.STONE_BUTTON:
			var att := Blocks.attach_from_face(face)
			if att == 5 or (block == Blocks.STONE_BUTTON and att == 0):
				return false
			meta = att
			if block == Blocks.LEVER and att == 0:
				meta = 0
		Blocks.LADDER:
			if face < 0 or face == 2 or face == 3:
				return false
			meta = Blocks.DIR_FACE.find(face)
		Blocks.VINE:
			if face < 0 or face == 2 or face == 3:
				return false
			meta = 1 << Blocks.DIR_FACE.find(face)
		Blocks.SIGN_POST:
			if face >= 0 and face != 2 and face != 3:
				block = Blocks.WALL_SIGN
				meta = Blocks.DIR_FACE.find(face)
			elif face == 2:
				meta = int(round(fposmod(-player.yaw / TAU * 16.0 + 8.0, 16.0))) & 15
			else:
				return false
		Blocks.TRAPDOOR:
			match face:
				4:
					meta = 1
				5:
					meta = 0
				0:
					meta = 3
				1:
					meta = 2
				_:
					meta = [0, 3, 1, 2][facing]
		Blocks.PISTON, Blocks.STICKY_PISTON:
			meta = _piston_dir(player)
		Blocks.RAIL, Blocks.POWERED_RAIL, Blocks.DETECTOR_RAIL:
			meta = 0 if facing == 0 or facing == 2 else 1
		Blocks.WOODEN_DOOR, Blocks.IRON_DOOR:
			return _place_door(player, block, p)
		Blocks.BED:
			return _place_bed(player, p)
		Blocks.WATERLILY:
			return false
	# Твёрдый блок не ставится внутрь игрока или существа.
	if Blocks.is_solid(block):
		var cell_box := AABB(Vector3(p), Vector3.ONE)
		if player.body_box().grow(-0.01).intersects(cell_box):
			return false
	if Blocks.needs_support[block] == 1 and not logic.is_supported_placement(p, block, meta):
		return false
	if not world.set_block(p.x, p.y, p.z, block, meta):
		return false
	_consume(player)
	_placed(p, block)
	if block == Blocks.PUMPKIN or block == Blocks.JACK_O_LANTERN:
		_check_golems(p)
	if block == Blocks.SIGN_POST or block == Blocks.WALL_SIGN:
		game.call("edit_sign", p)
	return true


## Блоки, которые шёлковое касание добывает целиком.
static func _silk_drop(id: int) -> bool:
	return id in [Blocks.STONE, Blocks.GRASS, Blocks.MYCELIUM, Blocks.COAL_ORE, Blocks.IRON_ORE, Blocks.GOLD_ORE,
		Blocks.DIAMOND_ORE, Blocks.LAPIS_ORE, Blocks.REDSTONE_ORE, Blocks.LIT_REDSTONE_ORE, Blocks.GLASS, Blocks.GLASS_PANE,
		Blocks.ICE, Blocks.BOOKSHELF, Blocks.CLAY, Blocks.GLOWSTONE, Blocks.SNOW, Blocks.LEAVES, Blocks.MELON,
		Blocks.BROWN_MUSHROOM_BLOCK, Blocks.RED_MUSHROOM_BLOCK, Blocks.TALLGRASS, Blocks.DEADBUSH, Blocks.WEB,
		Blocks.GRAVEL, Blocks.MONSTER_EGG]


func _consume(player: Player) -> void:
	if not player.creative:
		player.inventory.consume_selected(1)


## Направление поршня: к игроку (вертикально, если смотрит сильно вверх/вниз).
func _piston_dir(player: Player) -> int:
	var pitch := player.pitch
	if pitch < -0.8:
		return 1
	if pitch > 0.8:
		return 0
	return [2, 5, 3, 4][player.facing()]


func _place_door(player: Player, block: int, p: Vector3i) -> bool:
	var up := p + Vector3i(0, 1, 0)
	if not Blocks.is_replaceable(world.get_block_v(up)) or not Blocks.is_solid(world.get_block_v(p + Vector3i(0, -1, 0))):
		return false
	var meta := (player.facing() + 2) % 4
	world.set_block(p.x, p.y, p.z, block, meta, false)
	world.set_block(up.x, up.y, up.z, block, meta | 8)
	_consume(player)
	_placed(p, block)
	return true


func _place_bed(player: Player, p: Vector3i) -> bool:
	var dir := player.facing()
	var head: Vector3i = p + Blocks.DIR_VEC[dir]
	if not Blocks.is_replaceable(world.get_block_v(head)) or not Blocks.is_solid(world.get_block_v(p + Vector3i(0, -1, 0))) \
			or not Blocks.is_solid(world.get_block_v(head + Vector3i(0, -1, 0))):
		return false
	world.set_block(p.x, p.y, p.z, Blocks.BED, dir, false)
	world.set_block(head.x, head.y, head.z, Blocks.BED, dir | 8)
	_consume(player)
	_placed(p, Blocks.BED)
	return true


## Снежный голем (2 снежных блока + тыква) и железный голем (4 железных блока «Т» + тыква) — 1.2.
func _check_golems(p: Vector3i) -> void:
	var below := p + Vector3i(0, -1, 0)
	if world.get_block_v(below) == Blocks.SNOW and world.get_block_v(below + Vector3i(0, -1, 0)) == Blocks.SNOW:
		for q: Vector3i in [p, below, below + Vector3i(0, -1, 0)]:
			world.set_block(q.x, q.y, q.z, Blocks.AIR)
		entities.spawn_mob(97, Vector3(below) + Vector3(0.5, -1.0, 0.5))
		return
	if world.get_block_v(below) != Blocks.IRON_BLOCK or world.get_block_v(below + Vector3i(0, -1, 0)) != Blocks.IRON_BLOCK:
		return
	for axis: Vector3i in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
		if world.get_block_v(below + axis) == Blocks.IRON_BLOCK and world.get_block_v(below - axis) == Blocks.IRON_BLOCK:
			for q: Vector3i in [p, below, below + Vector3i(0, -1, 0), below + axis, below - axis]:
				world.set_block(q.x, q.y, q.z, Blocks.AIR)
			entities.spawn_mob(99, Vector3(below) + Vector3(0.5, -1.0, 0.5))
			return


# --- Еда, зелья, лук -------------------------------------------------------

func finish_consume(player: Player) -> void:
	var inv := player.inventory
	var id := inv.selected_id()
	var data := inv.selected_data()
	match id:
		Items.MILK_BUCKET:
			player.clear_effects()
			if not player.creative:
				inv.replace_selected(Items.BUCKET)
			return
		Items.POTION:
			var eff := Potions.effect_of(data)
			if not eff.is_empty():
				player.add_effect(int(eff[0]), int(eff[1]), float(eff[2]))
			if not player.creative:
				inv.replace_selected(Items.GLASS_BOTTLE)
			return
	if not Items.is_food(id):
		return
	player.eat(Items.food_value(id), Items.food_saturation(id))
	_sound("burp", player.position + Vector3(0, 1.5, 0), 0.5)
	match id:
		Items.GOLDEN_APPLE:
			player.add_effect(Potions.REGENERATION, 3, 30.0)
		Items.CHICKEN:
			if rng.randf() < 0.3:
				player.add_effect(Potions.HUNGER, 0, 30.0)
		Items.ROTTEN_FLESH:
			if rng.randf() < 0.8:
				player.add_effect(Potions.HUNGER, 0, 30.0)
		Items.SPIDER_EYE:
			player.add_effect(Potions.POISON, 0, 4.0)
	if id == Items.MUSHROOM_STEW:
		if not player.creative:
			inv.replace_selected(Items.BOWL)
	elif not player.creative:
		inv.consume_selected(1)


func shoot_bow(player: Player, charge: float) -> void:
	var f := minf(charge, 1.0)
	var power := minf((f * f + 2.0 * f) / 3.0, 1.0)
	if power < 0.1:
		return
	var inv := player.inventory
	var bdata := inv.selected_data()
	if not player.creative:
		# Бесконечность: нужна хотя бы одна стрела, но она не тратится.
		if Enchantments.level_of(bdata, Enchantments.INFINITY) > 0:
			if inv.count_of(Items.ARROW) <= 0:
				return
		elif not inv.remove_item(Items.ARROW, 1):
			return
		inv.damage_slot(inv.selected)
	var dir := player.look_dir()
	var pos := player.eye_position() + dir * 0.5
	var dmg := 6.0 if power >= 1.0 else 4.0 * power + 1.0
	var pw := Enchantments.level_of(bdata, Enchantments.POWER)
	if pw > 0:
		dmg += pw * 0.5 + 0.5
	var arrow := entities.spawn_projectile("arrow", pos, dir * (power * 55.0), player, dmg)
	if arrow != null:
		arrow.set_meta("punch", Enchantments.level_of(bdata, Enchantments.PUNCH))
		arrow.set_meta("flame", Enchantments.level_of(bdata, Enchantments.FLAME) > 0)
	_sound("bow", pos, 0.6)
