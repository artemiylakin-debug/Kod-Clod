class_name ContainerUI
extends Control
## Окна с предметами: инвентарь (броня, крафт 2×2), верстак (3×3), печь, сундук (одинарный и
## двойной), раздатчик, варочная стойка и креативный инвентарь.
## Как в оригинале: стопка «на курсоре»; левая кнопка — взять/положить/поменять, правая — половину
## или по одному, Shift — быстрый перенос. На сенсоре: тап, удержание и двойной тап.

signal closed
## Предметы, которые некуда положить при закрытии окна (выпадают на землю).
signal overflow(id: int, count: int, data: int)

const SLOT := 50.0
const COLS := 9

var player: Player
var world: World
var logic: BlockLogic
var mode := "inventory"
var container_pos := Vector3i.ZERO
var creative := false

var _panel: PanelContainer
var _body: VBoxContainer
var _title: Label
var _info: Label
var _cursor_view: Control
var _views: Array[SlotView] = []
var _cursor := [0, 0, 0]
var _craft := Inventory.new(9)
var _craft_size := 2
var _result_view: SlotView
## Контейнер: одна или две (двойной сундук) записи данных блоков.
var _bes: Array[Dictionary] = []
var _cont := Inventory.new(0)
var _progress: Control
var _creative_page := 0
var _creative_items: Array = []
var _pointer := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_child(UITheme.dim(0.5))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	_title = UITheme.label("Инвентарь", 26)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := UITheme.button("Закрыть", 150, 20)
	close.custom_minimum_size.y = 44
	close.pressed.connect(close_ui)
	header.add_child(close)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	outer.add_child(_body)
	_info = UITheme.label("", 16, Color(0.85, 0.85, 0.85))
	_info.custom_minimum_size = Vector2(COLS * (SLOT + 4), 24)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_info)
	_cursor_view = HUD.Painter.new(_paint_cursor)
	_cursor_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cursor_view.z_index = 10
	add_child(_cursor_view)
	_creative_items = Items.creative_items()


func setup(p_player: Player, p_world: World, p_logic: BlockLogic) -> void:
	player = p_player
	world = p_world
	logic = p_logic
	player.inventory.changed.connect(refresh)


# --- Открытие и закрытие ---------------------------------------------------

## kind: inventory, crafting, furnace, chest, dispenser, brewing.
func open(kind: String, pos: Vector3i, p_creative: bool) -> void:
	creative = p_creative
	mode = kind
	container_pos = pos
	if kind == "inventory" and creative:
		mode = "creative"
	_cursor = [0, 0, 0]
	_craft_size = 3 if mode == "crafting" else 2
	_craft = Inventory.new(9)
	_bes.clear()
	if mode in ["chest", "dispenser", "furnace", "brewing"]:
		_bes.append(world.get_block_entity(pos))
		if mode == "chest":
			for d in 4:
				var q: Vector3i = pos + Blocks.DIR_VEC[d]
				if world.get_block_v(q) == Blocks.CHEST:
					# Двойной сундук: верхняя половина — сундук западнее/севернее.
					if d == 1 or d == 2:
						_bes.push_front(world.get_block_entity(q))
					else:
						_bes.append(world.get_block_entity(q))
					break
		_load_container()
	_build()
	visible = true
	refresh()


func _load_container() -> void:
	var size: int = Containers.SIZES.get(mode, 0)
	_cont = Inventory.new(size * _bes.size())
	for k in _bes.size():
		var part := Containers.load_items(_bes[k], size)
		for i in size:
			_cont.ids[k * size + i] = part.ids[i]
			_cont.counts[k * size + i] = part.counts[i]
			_cont.datas[k * size + i] = part.datas[i]


func _save_container() -> void:
	if _bes.is_empty():
		return
	var size: int = Containers.SIZES.get(mode, 0)
	for k in _bes.size():
		var part := Inventory.new(size)
		for i in size:
			part.ids[i] = _cont.ids[k * size + i]
			part.counts[i] = _cont.counts[k * size + i]
			part.datas[i] = _cont.datas[k * size + i]
		Containers.store(_bes[k], part)
	world.mark_dirty(container_pos)
	if mode == "furnace" or mode == "brewing":
		logic.containers.mark_active(container_pos)


func close_ui() -> void:
	if not visible:
		return
	visible = false
	# Предметы с сетки крафта и курсора возвращаются в инвентарь.
	for i in 9:
		if _craft.counts[i] > 0:
			_give(_craft.ids[i], _craft.counts[i], _craft.datas[i])
	_craft.clear()
	if int(_cursor[1]) > 0 and not (mode == "creative"):
		_give(int(_cursor[0]), int(_cursor[1]), int(_cursor[2]))
	_cursor = [0, 0, 0]
	_save_container()
	closed.emit()


func _give(id: int, count: int, data: int) -> void:
	var left := player.inventory.add_item(id, count, data)
	if left > 0:
		overflow.emit(id, left, data)


# --- Построение окна -------------------------------------------------------

func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()
	_views.clear()
	_result_view = null
	_progress = null


func _slot(section: String, index: int, size := SLOT) -> SlotView:
	var v := SlotView.new(section, index, size)
	v.clicked.connect(_on_slot_clicked)
	v.hovered.connect(_on_hover)
	_views.append(v)
	return v


func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	return g


func _label(text: String) -> Label:
	return UITheme.label(text, 17, Color(0.8, 0.8, 0.8))


func _build() -> void:
	_clear()
	var titles := {"inventory": "Инвентарь", "creative": "Креативный инвентарь", "crafting": "Верстак", "furnace": "Печь",
		"chest": "Большой сундук" if _bes.size() > 1 else "Сундук", "dispenser": "Раздатчик", "brewing": "Варочная стойка"}
	_title.text = titles.get(mode, "Инвентарь")
	_info.text = "Тап — взять/положить, удержание — половина или по одному, двойной тап — быстрый перенос." \
		if Game.is_touch_enabled() else "ЛКМ — взять/положить, ПКМ — половина или по одному, Shift+клик — быстрый перенос."
	match mode:
		"creative":
			_build_creative()
		"inventory":
			_build_inventory_top()
		"crafting":
			_build_crafting_top()
		"furnace":
			_build_furnace_top()
		"brewing":
			_build_brewing_top()
		"chest", "dispenser":
			_body.add_child(_label(_title.text))
			var g := _grid(COLS if mode == "chest" else 3)
			for i in _cont.size:
				g.add_child(_slot("cont", i))
			var c := CenterContainer.new()
			c.add_child(g)
			_body.add_child(c)
	if mode != "creative":
		_body.add_child(_label("Инвентарь"))
		var bp := _grid(COLS)
		for i in range(Inventory.HOTBAR_SIZE, Inventory.SIZE):
			bp.add_child(_slot("player", i))
		_body.add_child(bp)
	var hb := _grid(COLS)
	for i in Inventory.HOTBAR_SIZE:
		hb.add_child(_slot("player", i))
	_body.add_child(hb)


func _build_inventory_top() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_body.add_child(row)
	var armor := VBoxContainer.new()
	armor.add_theme_constant_override("separation", 4)
	var names := ["Шлем", "Броня", "Штаны", "Сапоги"]
	for k in 4:
		var v := _slot("player", Inventory.ARMOR_START + k)
		v.placeholder = names[k]
		armor.add_child(v)
	row.add_child(armor)
	var stats := VBoxContainer.new()
	stats.custom_minimum_size = Vector2(150, 0)
	stats.add_child(_label("Уровень: %d" % player.xp_level))
	stats.add_child(_label("Броня: %d" % player.inventory.armor_points()))
	row.add_child(stats)
	row.add_child(_craft_block())


func _build_crafting_top() -> void:
	var c := CenterContainer.new()
	c.add_child(_craft_block())
	_body.add_child(c)


func _craft_block() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var g := _grid(_craft_size)
	for y in _craft_size:
		for x in _craft_size:
			g.add_child(_slot("craft", x + y * 3))
	box.add_child(g)
	var arrow := UITheme.label("→", 34)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(arrow)
	var res_box := CenterContainer.new()
	_result_view = _slot("result", 0, SLOT * 1.2)
	res_box.add_child(_result_view)
	box.add_child(res_box)
	return box


func _build_furnace_top() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.add_child(_slot("cont", 0))
	_progress = HUD.Painter.new(_paint_furnace_progress)
	_progress.custom_minimum_size = Vector2(SLOT, 26)
	col.add_child(_progress)
	col.add_child(_slot("cont", 1))
	row.add_child(col)
	var arrow := UITheme.label("→", 34)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(arrow)
	var out := CenterContainer.new()
	out.add_child(_slot("cont", 2, SLOT * 1.2))
	row.add_child(out)
	_body.add_child(row)


func _build_brewing_top() -> void:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var top := CenterContainer.new()
	top.add_child(_slot("cont", 3))
	col.add_child(top)
	_progress = HUD.Painter.new(_paint_brew_progress)
	_progress.custom_minimum_size = Vector2(SLOT * 3, 22)
	col.add_child(_progress)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for i in 3:
		row.add_child(_slot("cont", i))
	col.add_child(row)
	_body.add_child(col)


func _build_creative() -> void:
	var per_page := COLS * 5
	var pages := ceili(_creative_items.size() / float(per_page))
	_creative_page = clampi(_creative_page, 0, pages - 1)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	var prev := UITheme.button("◀", 70, 22)
	prev.pressed.connect(func() -> void:
		_creative_page = posmod(_creative_page - 1, pages)
		_build()
		refresh())
	var next := UITheme.button("▶", 70, 22)
	next.pressed.connect(func() -> void:
		_creative_page = posmod(_creative_page + 1, pages)
		_build()
		refresh())
	nav.add_child(prev)
	nav.add_child(_label("Страница %d из %d" % [_creative_page + 1, pages]))
	nav.add_child(next)
	_body.add_child(nav)
	var g := _grid(COLS)
	for k in per_page:
		var idx := _creative_page * per_page + k
		var v := _slot("palette", idx)
		if idx < _creative_items.size():
			var it: Array = _creative_items[idx]
			v.set_item(int(it[0]), 1, int(it[1]))
			v.tooltip_text = Items.name_of(int(it[0]), int(it[1]))
		g.add_child(v)
	_body.add_child(g)
	var trash_row := HBoxContainer.new()
	trash_row.add_child(_label("Хотбар (тап по предмету сверху кладёт его в выбранный слот)"))
	var trash := _slot("trash", 0)
	trash.placeholder = "Удалить"
	trash_row.add_child(trash)
	_body.add_child(trash_row)


# --- Отображение -----------------------------------------------------------

func refresh() -> void:
	if not visible or player == null:
		return
	var inv := player.inventory
	for v in _views:
		if not is_instance_valid(v):
			continue
		match v.section:
			"player":
				v.set_item(inv.ids[v.slot], inv.counts[v.slot], inv.datas[v.slot])
				v.show_count = mode != "creative"
				v.set_highlighted(mode == "creative" and v.slot == inv.selected)
			"craft":
				v.set_item(_craft.ids[v.slot], _craft.counts[v.slot], _craft.datas[v.slot])
			"cont":
				v.set_item(_cont.ids[v.slot], _cont.counts[v.slot], _cont.datas[v.slot])
			"result":
				var r := _craft_result()
				if r.is_empty():
					v.set_item(0, 0)
				else:
					v.set_item(int(r[0]), int(r[1]), int(r[2]))
	_cursor_view.queue_redraw()
	if _progress != null:
		_progress.queue_redraw()


func _process(_delta: float) -> void:
	if not visible:
		return
	# Печь и стойка работают и при открытом окне: подтягиваем изменения из данных блока.
	if mode == "furnace" or mode == "brewing":
		_load_container()
		refresh()
	_pointer = get_local_mouse_position()
	_cursor_view.queue_redraw()


func _paint_cursor(c: Control) -> void:
	if int(_cursor[1]) <= 0 or int(_cursor[0]) == 0:
		return
	var r := Rect2(_pointer - Vector2(SLOT, SLOT) * 0.45, Vector2(SLOT, SLOT) * 0.9)
	c.draw_texture_rect(TextureFactory.icon(int(_cursor[0]), int(_cursor[2])), r, false)
	if int(_cursor[1]) > 1 and mode != "creative":
		HotbarView.draw_count(c, c.get_theme_default_font(), r, int(_cursor[1]))


func _paint_furnace_progress(c: Control) -> void:
	if _bes.is_empty():
		return
	var be: Dictionary = _bes[0]
	var burn := float(be.get("burn", 0))
	var burn_max := maxf(float(be.get("burn_max", 1)), 1.0)
	var cook := float(be.get("cook", 0)) / Containers.COOK_TICKS
	var w := c.size.x
	# Огонь (оставшееся топливо) и стрелка готовности.
	c.draw_rect(Rect2(0, 2, w, 8), Color(0.2, 0.2, 0.2))
	c.draw_rect(Rect2(0, 2, w * burn / burn_max, 8), Color(1.0, 0.55, 0.1))
	c.draw_rect(Rect2(0, 14, w, 8), Color(0.2, 0.2, 0.2))
	c.draw_rect(Rect2(0, 14, w * cook, 8), Color(0.9, 0.9, 0.9))


func _paint_brew_progress(c: Control) -> void:
	if _bes.is_empty():
		return
	var t := float(_bes[0].get("brew", 0))
	var f := 0.0 if t <= 0.0 else 1.0 - t / Containers.BREW_TICKS
	c.draw_rect(Rect2(0, 6, c.size.x, 10), Color(0.2, 0.2, 0.2))
	c.draw_rect(Rect2(0, 6, c.size.x * f, 10), Color(0.95, 0.75, 0.3))


func _on_hover(v: SlotView) -> void:
	if v.item_id > 0 and v.count > 0:
		var n := Items.name_of(v.item_id, v.data)
		var max_d := Items.max_damage(v.item_id)
		if max_d > 0:
			n += "  (прочность %d/%d)" % [max_d - v.data, max_d]
		_info.text = n


# --- Нажатия на слоты ------------------------------------------------------

func _stack_of(v: SlotView) -> Array:
	match v.section:
		"player":
			var inv := player.inventory
			return [inv.ids[v.slot], inv.counts[v.slot], inv.datas[v.slot]]
		"craft":
			return [_craft.ids[v.slot], _craft.counts[v.slot], _craft.datas[v.slot]]
		"cont":
			return [_cont.ids[v.slot], _cont.counts[v.slot], _cont.datas[v.slot]]
	return [0, 0, 0]


func _set_stack(v: SlotView, s: Array) -> void:
	var id := int(s[0]) if int(s[1]) > 0 else 0
	var cnt := int(s[1]) if id != 0 else 0
	var d := int(s[2]) if id != 0 else 0
	match v.section:
		"player":
			player.inventory.ids[v.slot] = id
			player.inventory.counts[v.slot] = cnt
			player.inventory.datas[v.slot] = d
			player.inventory.changed.emit()
		"craft":
			_craft.ids[v.slot] = id
			_craft.counts[v.slot] = cnt
			_craft.datas[v.slot] = d
		"cont":
			_cont.ids[v.slot] = id
			_cont.counts[v.slot] = cnt
			_cont.datas[v.slot] = d
			_save_container()


## Можно ли положить предмет в слот (броня — только в свой слот, результат печи — только забрать).
func _accepts(v: SlotView, id: int) -> bool:
	if v.section == "player" and v.slot >= Inventory.ARMOR_START:
		var want := v.slot - Inventory.ARMOR_START
		return Items.armor_slot(id) == want or (want == 0 and (id == Blocks.PUMPKIN))
	if v.section == "cont" and mode == "furnace" and v.slot == 2:
		return false
	if v.section == "cont" and mode == "brewing":
		if v.slot < 3:
			return id == Items.POTION or id == Items.GLASS_BOTTLE
		return id in [Items.NETHER_WART, Items.REDSTONE, Items.GLOWSTONE_DUST, Items.FERMENTED_SPIDER_EYE, Items.SUGAR,
			Items.GHAST_TEAR, Items.SPIDER_EYE, Items.BLAZE_POWDER, Items.MAGMA_CREAM, Items.SPECKLED_MELON, Items.GUNPOWDER]
	return true


func _max_in(v: SlotView, id: int) -> int:
	if v.section == "player" and v.slot >= Inventory.ARMOR_START:
		return 1
	if v.section == "cont" and mode == "brewing" and v.slot < 3:
		return 1
	return Items.max_stack(id)


func _on_slot_clicked(v: SlotView, action: int) -> void:
	match v.section:
		"palette":
			_palette_click(v, action)
		"trash":
			_cursor = [0, 0, 0]
		"result":
			_take_result(action == 2)
		_:
			if action == 2:
				_quick_move(v)
			else:
				_click(v, action == 1)
	refresh()


func _click(v: SlotView, right: bool) -> void:
	var s := _stack_of(v)
	var sid := int(s[0])
	var sc := int(s[1])
	var sd := int(s[2])
	var cid := int(_cursor[0])
	var cc := int(_cursor[1])
	var cd := int(_cursor[2])
	var took_furnace_output := mode == "furnace" and v.section == "cont" and v.slot == 2 and sc > 0
	if cc <= 0:
		if sc <= 0:
			return
		var take := (sc + 1) / 2 if right else sc
		_cursor = [sid, take, sd]
		_set_stack(v, [sid, sc - take, sd])
		if took_furnace_output:
			player.add_xp(Containers.take_furnace_xp(_bes[0]))
		return
	if not _accepts(v, cid):
		# Из результата печи можно только забрать.
		if took_furnace_output and Inventory.stacks_with(sid, sd, cid, cd):
			var add := mini(sc, Items.max_stack(cid) - cc)
			_cursor = [cid, cc + add, cd]
			_set_stack(v, [sid, sc - add, sd])
			player.add_xp(Containers.take_furnace_xp(_bes[0]))
		return
	var max_s := _max_in(v, cid)
	if sc <= 0:
		var put := 1 if right else mini(cc, max_s)
		_set_stack(v, [cid, put, cd])
		_cursor = [cid, cc - put, cd]
	elif Inventory.stacks_with(sid, sd, cid, cd):
		var room := max_s - sc
		var put := mini(1 if right else cc, room)
		_set_stack(v, [sid, sc + put, sd])
		_cursor = [cid, cc - put, cd]
	elif not right and cc <= max_s:
		_set_stack(v, [cid, cc, cd])
		_cursor = [sid, sc, sd]
	if int(_cursor[1]) <= 0:
		_cursor = [0, 0, 0]


## Быстрый перенос: контейнер ↔ инвентарь, хотбар ↔ рюкзак, броня — в свои слоты.
func _quick_move(v: SlotView) -> void:
	var s := _stack_of(v)
	if int(s[1]) <= 0:
		return
	var id := int(s[0])
	var count := int(s[1])
	var data := int(s[2])
	var left := count
	if v.section == "player":
		var armor := Items.armor_slot(id)
		if armor >= 0 and v.slot < Inventory.ARMOR_START and player.inventory.counts[Inventory.ARMOR_START + armor] == 0:
			player.inventory.set_slot(Inventory.ARMOR_START + armor, id, 1, data)
			left = count - 1
		elif mode in ["chest", "dispenser"] or (mode == "furnace") or (mode == "brewing"):
			left = _insert_container(id, count, data)
		elif v.slot < Inventory.HOTBAR_SIZE:
			left = _insert_range(player.inventory, Inventory.HOTBAR_SIZE, Inventory.SIZE, id, count, data)
		else:
			left = _insert_range(player.inventory, 0, Inventory.HOTBAR_SIZE, id, count, data)
	else:
		left = _insert_range(player.inventory, 0, Inventory.SIZE, id, count, data)
		if v.section == "cont" and mode == "furnace" and v.slot == 2 and left < count:
			player.add_xp(Containers.take_furnace_xp(_bes[0]))
	_set_stack(v, [id, left, data])


func _insert_container(id: int, count: int, data: int) -> int:
	if mode == "furnace":
		var slot := 1 if Items.fuel_ticks(id) > 0 and Recipes.smelt_result(id, data).is_empty() else 0
		return _insert_range(_cont, slot, slot + 1, id, count, data, true)
	if mode == "brewing":
		if id == Items.POTION or id == Items.GLASS_BOTTLE:
			var left := count
			for i in 3:
				if _cont.counts[i] == 0 and left > 0:
					_cont.set_slot(i, id, 1, data)
					left -= 1
			_save_container()
			return left
		return _insert_range(_cont, 3, 4, id, count, data, true)
	return _insert_range(_cont, 0, _cont.size, id, count, data, true)


func _insert_range(inv: Inventory, from: int, to: int, id: int, count: int, data: int, save := false) -> int:
	var max_s := Items.max_stack(id)
	for i in range(from, to):
		if count == 0:
			break
		if inv.counts[i] > 0 and Inventory.stacks_with(inv.ids[i], inv.datas[i], id, data) and inv.counts[i] < max_s:
			var add := mini(count, max_s - inv.counts[i])
			inv.counts[i] += add
			count -= add
	for i in range(from, to):
		if count == 0:
			break
		if inv.counts[i] <= 0:
			var add := mini(count, max_s)
			inv.ids[i] = id
			inv.counts[i] = add
			inv.datas[i] = data
			count -= add
	inv.changed.emit()
	if save:
		_save_container()
	return count


func _palette_click(v: SlotView, action: int) -> void:
	if v.item_id <= 0:
		return
	var full := Items.max_stack(v.item_id)
	if action == 0 and int(_cursor[1]) <= 0:
		# Тап по палитре кладёт предмет в выбранный слот хотбара (удобно на телефоне).
		player.inventory.set_slot(player.inventory.selected, v.item_id, full, v.data)
		return
	_cursor = [v.item_id, 1 if action == 1 else full, v.data]


# --- Крафт -----------------------------------------------------------------

func _craft_grid() -> Array:
	var grid := []
	for y in _craft_size:
		for x in _craft_size:
			var i := x + y * 3
			grid.append([_craft.ids[i], _craft.datas[i]] if _craft.counts[i] > 0 else [0, 0])
	return grid


func _craft_result() -> Array:
	if mode != "inventory" and mode != "crafting":
		return []
	return Recipes.match_grid(_craft_grid(), _craft_size)


func _consume_ingredients() -> void:
	for y in _craft_size:
		for x in _craft_size:
			var i := x + y * 3
			if _craft.counts[i] <= 0:
				continue
			var id := _craft.ids[i]
			_craft.counts[i] -= 1
			# Ведро молока возвращает пустое ведро.
			if id == Items.MILK_BUCKET or id == Items.WATER_BUCKET or id == Items.LAVA_BUCKET:
				_craft.ids[i] = Items.BUCKET
				_craft.counts[i] = 1
				_craft.datas[i] = 0
				continue
			if _craft.counts[i] <= 0:
				_craft.ids[i] = 0
				_craft.datas[i] = 0


func _take_result(all: bool) -> void:
	var r := _craft_result()
	if r.is_empty():
		return
	var id := int(r[0])
	var cnt := int(r[1])
	var data := int(r[2])
	if all:
		var guard := 0
		while not r.is_empty() and int(r[0]) == id and guard < 64:
			guard += 1
			if player.inventory.add_item(id, cnt, data) > 0:
				break
			_consume_ingredients()
			_on_crafted(id)
			r = _craft_result()
		return
	if int(_cursor[1]) > 0:
		if not Inventory.stacks_with(int(_cursor[0]), int(_cursor[2]), id, data) or int(_cursor[1]) + cnt > Items.max_stack(id):
			return
		_cursor = [id, int(_cursor[1]) + cnt, data]
	else:
		_cursor = [id, cnt, data]
	_consume_ingredients()
	_on_crafted(id)


func _on_crafted(id: int) -> void:
	var g := get_tree().current_scene
	if g != null and g.has_method("on_item_crafted"):
		g.call("on_item_crafted", id)
