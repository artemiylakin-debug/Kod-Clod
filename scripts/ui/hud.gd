class_name HUD
extends CanvasLayer
## Игровой интерфейс: прицел, хотбар, здоровье, подсказки, экраны загрузки и смерти.

signal respawn_requested
signal menu_requested

var player: Player
var root: Control
var hotbar: HotbarView
var show_debug := false
var creative := true
var touch_mode := false

var _crosshair: Painter
var _hearts: Painter
var _debug: Label
var _toast: Label
var _item_name: Label
var _saved: Label
var _underwater: ColorRect
var _damage: ColorRect
var _loading: Control
var _loading_label: Label
var _death: Control
var _rotate_hint: Control
var _toast_time := 0.0
var _item_time := 0.0
var _saved_time := 0.0
var _last_item := -1
var _last_slot := -1
var _margins := Vector4.ZERO


## Control, рисующий себя переданной функцией.
class Painter extends Control:
	var paint: Callable

	func _init(p_paint: Callable) -> void:
		paint = p_paint
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		paint.call(self)


func setup(p_player: Player, p_creative: bool) -> void:
	player = p_player
	creative = p_creative
	hotbar.inventory = player.inventory
	hotbar.creative = creative
	player.inventory.changed.connect(_on_inventory_changed)
	player.health_changed.connect(func(_h: int) -> void: _hearts.queue_redraw())
	player.damaged.connect(func(_a: int) -> void: _damage.color.a = 0.38)
	_layout()


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Game.ui_theme
	add_child(root)

	_underwater = _overlay(Color(0.08, 0.22, 0.7, 0.38))
	_underwater.visible = false
	_damage = _overlay(Color(0.85, 0.0, 0.0, 0.0))

	_crosshair = Painter.new(_paint_crosshair)
	root.add_child(_crosshair)
	hotbar = HotbarView.new()
	root.add_child(hotbar)
	_hearts = Painter.new(_paint_hearts)
	root.add_child(_hearts)

	_item_name = _make_label(24, HORIZONTAL_ALIGNMENT_CENTER)
	_toast = _make_label(26, HORIZONTAL_ALIGNMENT_CENTER)
	_saved = _make_label(18, HORIZONTAL_ALIGNMENT_RIGHT)
	_saved.text = "Мир сохранён"
	_saved.modulate.a = 0.0
	_debug = _make_label(18, HORIZONTAL_ALIGNMENT_LEFT)
	_debug.visible = false

	_build_loading()
	_build_death()
	_rotate_hint = ColorRect.new()
	(_rotate_hint as ColorRect).color = Color(0.05, 0.05, 0.07, 0.92)
	_rotate_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rotate_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	_rotate_hint.visible = false
	root.add_child(_rotate_hint)
	var hint := UITheme.label("Поверните устройство горизонтально", 40)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rotate_hint.add_child(hint)
	root.resized.connect(_layout)


func _overlay(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r


func _make_label(size: int, align: HorizontalAlignment) -> Label:
	var l := UITheme.label("", size)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func _build_loading() -> void:
	_loading = Control.new()
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_loading)
	var bg := TextureRect.new()
	bg.texture = TextureFactory.background
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	UITheme.place(box, Vector2(0.5, 0.5), Vector2(-300, -60), Vector2(600, 120))
	_loading.add_child(box)
	var title := UITheme.label("Загрузка мира", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_loading_label = UITheme.label("Генерация ландшафта…", 22, Color(0.8, 0.8, 0.8))
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_loading_label)


func _build_death() -> void:
	_death = ColorRect.new()
	(_death as ColorRect).color = Color(0.55, 0.0, 0.0, 0.45)
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_STOP
	_death.visible = false
	root.add_child(_death)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	UITheme.place(box, Vector2(0.5, 0.5), Vector2(-220, -150), Vector2(440, 300))
	_death.add_child(box)
	var title := UITheme.label("Вы погибли!", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var respawn := UITheme.button("Возродиться", 440)
	respawn.pressed.connect(func() -> void: respawn_requested.emit())
	box.add_child(respawn)
	var menu := UITheme.button("Выйти в главное меню", 440)
	menu.pressed.connect(func() -> void: menu_requested.emit())
	box.add_child(menu)


# --- Публичные методы ------------------------------------------------------

func set_creative(value: bool) -> void:
	creative = value
	hotbar.creative = value
	hotbar.queue_redraw()
	_hearts.queue_redraw()


func set_touch_mode(value: bool, margins: Vector4) -> void:
	touch_mode = value
	_margins = margins
	hotbar.touch_mode = value
	hotbar.slot_size = 66.0 if value else 56.0
	_layout()


func show_loading(value: bool) -> void:
	_loading.visible = value


func set_loading_text(text: String) -> void:
	_loading_label.text = text


func show_death(value: bool) -> void:
	_death.visible = value
	hotbar.visible = not value
	_hearts.visible = not value


func set_underwater(value: bool) -> void:
	_underwater.visible = value


func show_toast(text: String, duration: float = 2.5) -> void:
	_toast.text = text
	_toast_time = duration


func flash_saved() -> void:
	_saved_time = 1.6


func toggle_debug() -> void:
	show_debug = not show_debug


func set_gameplay_visible(value: bool) -> void:
	_crosshair.visible = value


# --- Обновление ------------------------------------------------------------

func _layout() -> void:
	if hotbar == null:
		return
	# Игра рассчитана на альбомную ориентацию; в портретной (например, в мобильном браузере) — подсказка.
	_rotate_hint.visible = touch_mode and root.size.y > root.size.x
	var bottom := 10.0 + _margins.w
	var s := hotbar.slot_size
	var w := hotbar.total_width()
	var hw := hotbar.slots_width()
	# Центрируются именно 9 слотов; кнопка меню выступает справа.
	UITheme.place(hotbar, Vector2(0.5, 1.0), Vector2(-hw / 2.0, -s - bottom), Vector2(w, s))
	UITheme.place(_hearts, Vector2(0.5, 1.0), Vector2(-hw / 2.0, -s - bottom - 30.0), Vector2(240, 24))
	UITheme.place(_item_name, Vector2(0.5, 1.0), Vector2(-320, -s - bottom - 74.0), Vector2(640, 34))
	UITheme.place(_crosshair, Vector2(0.5, 0.5), Vector2(-16, -16), Vector2(32, 32))
	UITheme.place(_toast, Vector2(0.5, 0.0), Vector2(-420, 64.0 + _margins.y), Vector2(840, 40))
	UITheme.place(_saved, Vector2(1.0, 0.0), Vector2(-360 - _margins.z, 14.0 + _margins.y), Vector2(260, 28))
	UITheme.place(_debug, Vector2(0.0, 0.0), Vector2(12.0 + _margins.x, 8.0 + _margins.y), Vector2(760, 260))
	hotbar.queue_redraw()
	_hearts.queue_redraw()


func _on_inventory_changed() -> void:
	hotbar.queue_redraw()
	var id := player.inventory.get_selected_block()
	if id != _last_item or player.inventory.selected != _last_slot:
		_last_item = id
		_last_slot = player.inventory.selected
		if id != Blocks.AIR:
			_item_name.text = Blocks.block_name(id)
			_item_time = 2.0
		else:
			_item_time = 0.0


func _process(delta: float) -> void:
	_toast_time -= delta
	_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	_item_time -= delta
	_item_name.modulate.a = clampf(_item_time, 0.0, 1.0)
	_saved_time -= delta
	_saved.modulate.a = clampf(_saved_time, 0.0, 1.0) * 0.85
	if _damage.color.a > 0.0:
		_damage.color.a = maxf(_damage.color.a - delta * 0.9, 0.0)
	_debug.visible = show_debug
	if show_debug and player != null:
		_debug.text = _debug_text()


func _debug_text() -> String:
	var p := player.position
	var key := World.key_of(p)
	var facings := ["Юг (+Z)", "Восток (+X)", "Север (-Z)", "Запад (-X)"]
	var facing: String = facings[posmod(roundi(player.yaw / (PI / 2.0)) + 2, 4)]
	var lines := PackedStringArray([
		"BlockCraft · FPS: %d" % Engine.get_frames_per_second(),
		"XYZ: %.2f / %.2f / %.2f" % [p.x, p.y, p.z],
		"Чанк: %d, %d · загружено: %d · задач: %d" % [key.x, key.y, player.world.loaded_count(), player.world.pending_jobs()],
		"Направление: %s" % facing,
		"Режим: %s%s" % ["креатив" if player.creative else "выживание", " · полёт" if player.flying else ""],
	])
	if not player.target.is_empty():
		var t: Vector3i = player.target["pos"]
		lines.append("Блок: %s (%d, %d, %d)" % [Blocks.block_name(player.target["block"]), t.x, t.y, t.z])
	return "\n".join(lines)


func _paint_crosshair(c: Control) -> void:
	var ctr := c.size / 2.0
	var shadow := Color(0.0, 0.0, 0.0, 0.55)
	var col := Color(1.0, 1.0, 1.0, 0.92)
	c.draw_rect(Rect2(ctr.x - 11.0, ctr.y - 2.0, 22.0, 4.0), shadow)
	c.draw_rect(Rect2(ctr.x - 2.0, ctr.y - 11.0, 4.0, 22.0), shadow)
	c.draw_rect(Rect2(ctr.x - 10.0, ctr.y - 1.0, 20.0, 2.0), col)
	c.draw_rect(Rect2(ctr.x - 1.0, ctr.y - 10.0, 2.0, 20.0), col)


func _paint_hearts(c: Control) -> void:
	if player == null or creative:
		return
	var hp := player.health
	for i in 10:
		var center := Vector2(i * 24.0 + 11.0, 12.0)
		c.draw_colored_polygon(heart_points(center, 11.0, false), Color(0.08, 0.02, 0.02, 0.9))
		c.draw_colored_polygon(heart_points(center, 8.5, false), Color(0.3, 0.06, 0.06, 0.9))
		if hp >= (i + 1) * 2:
			c.draw_colored_polygon(heart_points(center, 8.5, false), Color(0.86, 0.1, 0.1))
			c.draw_rect(Rect2(center + Vector2(-5.0, -5.0), Vector2(3.0, 3.0)), Color(1.0, 0.75, 0.75))
		elif hp == i * 2 + 1:
			c.draw_colored_polygon(heart_points(center, 8.5, true), Color(0.86, 0.1, 0.1))


## Контур сердечка (параметрическая кривая). half — только левая половина.
static func heart_points(center: Vector2, r: float, half: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 28
	var t0 := PI if half else 0.0
	var count := n + 1 if half else n
	var span := PI if half else TAU
	for i in count:
		var t := t0 + span * float(i) / n
		var s := sin(t)
		var x := 16.0 * s * s * s
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(center + Vector2(x, -y + 2.5) * (r / 17.0))
	return pts
