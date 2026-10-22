class_name InventoryUI
extends Control
## Окно инвентаря.
## Креатив: палитра всех блоков → нажатие кладёт блок в выбранный слот хотбара.
## Выживание: рюкзак + хотбар (нажать предмет, затем слот — переместить) и простой крафт.

signal closed
signal overflow(id: int, count: int)

const SLOT := 58.0
const RECIPES := [
	{"in": [[Blocks.LOG, 1]], "out": [Blocks.PLANKS, 4]},
	{"in": [[Blocks.SAND, 1]], "out": [Blocks.GLASS, 1]},
	{"in": [[Blocks.COBBLESTONE, 1]], "out": [Blocks.STONE, 1]},
	{"in": [[Blocks.STONE, 4]], "out": [Blocks.STONE_BRICKS, 4]},
	{"in": [[Blocks.DIRT, 2], [Blocks.SAND, 2]], "out": [Blocks.BRICKS, 2]},
	{"in": [[Blocks.PLANKS, 6]], "out": [Blocks.BOOKSHELF, 1]},
]

var player: Player
var creative := true

var _title: Label
var _hint: Label
var _creative_box: VBoxContainer
var _survival_box: HBoxContainer
var _palette: Array[SlotView] = []
var _backpack: Array[SlotView] = []
var _hotbar: Array[SlotView] = []
var _recipe_buttons: Array[Button] = []
var _selected := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_child(UITheme.dim(0.5))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	_title = UITheme.label("Инвентарь", 30)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := UITheme.button("Закрыть", 160, 22)
	close.custom_minimum_size.y = 50
	close.pressed.connect(close_inventory)
	header.add_child(close)

	# Креатив.
	_creative_box = VBoxContainer.new()
	vbox.add_child(_creative_box)
	_creative_box.add_child(UITheme.label("Все блоки", 20, Color(0.8, 0.8, 0.8)))
	var pal_grid := _grid()
	_creative_box.add_child(pal_grid)
	for id in Blocks.creative_palette():
		var sv := SlotView.new(id, SLOT)
		sv.set_item(id, 1)
		sv.tooltip_text = Blocks.block_name(id)
		sv.pressed.connect(_on_palette_pressed)
		pal_grid.add_child(sv)
		_palette.append(sv)

	# Выживание: рюкзак и крафт.
	_survival_box = HBoxContainer.new()
	_survival_box.add_theme_constant_override("separation", 24)
	vbox.add_child(_survival_box)
	var bp_box := VBoxContainer.new()
	_survival_box.add_child(bp_box)
	bp_box.add_child(UITheme.label("Рюкзак", 20, Color(0.8, 0.8, 0.8)))
	var bp_grid := _grid()
	bp_box.add_child(bp_grid)
	for i in range(Inventory.HOTBAR_SIZE, Inventory.SIZE):
		var sv := SlotView.new(i, SLOT)
		sv.pressed.connect(_on_slot_pressed)
		bp_grid.add_child(sv)
		_backpack.append(sv)
	var craft_box := VBoxContainer.new()
	craft_box.add_theme_constant_override("separation", 6)
	_survival_box.add_child(craft_box)
	craft_box.add_child(UITheme.label("Крафт", 20, Color(0.8, 0.8, 0.8)))
	for i in RECIPES.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(330, 0)
		b.add_theme_font_size_override("font_size", 17)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 30)
		b.text = _recipe_text(RECIPES[i])
		b.icon = TextureFactory.icons[int(RECIPES[i]["out"][0])]
		b.pressed.connect(_craft.bind(i))
		craft_box.add_child(b)
		_recipe_buttons.append(b)

	vbox.add_child(UITheme.label("Хотбар", 20, Color(0.8, 0.8, 0.8)))
	var hb_grid := _grid()
	vbox.add_child(hb_grid)
	for i in Inventory.HOTBAR_SIZE:
		var sv := SlotView.new(i, SLOT)
		sv.pressed.connect(_on_slot_pressed)
		hb_grid.add_child(sv)
		_hotbar.append(sv)
	_hint = UITheme.label("", 17, Color(0.75, 0.75, 0.75))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(540, 0)
	vbox.add_child(_hint)


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = Inventory.HOTBAR_SIZE
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	return g


func _recipe_text(r: Dictionary) -> String:
	var parts := PackedStringArray()
	for ing: Array in r["in"]:
		parts.append("%s ×%d" % [Blocks.block_name(ing[0]), ing[1]])
	var out: Array = r["out"]
	return "%s → %s ×%d" % [" + ".join(parts), Blocks.block_name(out[0]), out[1]]


func setup(p_player: Player) -> void:
	player = p_player
	player.inventory.changed.connect(refresh)


func open(p_creative: bool) -> void:
	creative = p_creative
	_selected = -1
	_title.text = "Креативный инвентарь" if creative else "Инвентарь"
	_creative_box.visible = creative
	_survival_box.visible = not creative
	_hint.text = "Нажмите на блок, чтобы положить его в выбранный слот хотбара." if creative \
		else "Нажмите на предмет, затем на другой слот, чтобы переместить его."
	visible = true
	refresh()


func close_inventory() -> void:
	if not visible:
		return
	visible = false
	_selected = -1
	closed.emit()


func refresh() -> void:
	if player == null or not visible:
		return
	var inv := player.inventory
	for sv in _hotbar:
		sv.set_item(inv.ids[sv.slot], inv.counts[sv.slot])
		sv.show_count = not creative
		sv.set_highlighted(sv.slot == _selected or (creative and sv.slot == inv.selected))
		sv.queue_redraw()
	for sv in _backpack:
		sv.set_item(inv.ids[sv.slot], inv.counts[sv.slot])
		sv.set_highlighted(sv.slot == _selected)
	for i in RECIPES.size():
		_recipe_buttons[i].disabled = not _can_craft(RECIPES[i])


func _on_palette_pressed(id: int) -> void:
	player.inventory.set_slot(player.inventory.selected, id, 1)


func _on_slot_pressed(slot: int) -> void:
	var inv := player.inventory
	if creative:
		if slot < Inventory.HOTBAR_SIZE:
			inv.select(slot)
		refresh()
		return
	if _selected == -1:
		if inv.counts[slot] > 0:
			_selected = slot
	elif _selected == slot:
		_selected = -1
	else:
		inv.move_slot(_selected, slot)
		_selected = -1
	refresh()


func _can_craft(r: Dictionary) -> bool:
	for ing: Array in r["in"]:
		if player.inventory.count_of(int(ing[0])) < int(ing[1]):
			return false
	return true


func _craft(index: int) -> void:
	var r: Dictionary = RECIPES[index]
	if not _can_craft(r):
		return
	for ing: Array in r["in"]:
		player.inventory.remove_item(int(ing[0]), int(ing[1]))
	var out: Array = r["out"]
	var left := player.inventory.add_item(int(out[0]), int(out[1]))
	if left > 0:
		overflow.emit(int(out[0]), left)
	_selected = -1
	refresh()
