class_name SlotView
extends Control
## Слот инвентаря: значок, количество, полоска износа, подсветка.
## Нажатия: левая кнопка / тап — 0, правая кнопка / удержание пальца — 1, Shift+клик / двойной тап — 2.

signal clicked(view: SlotView, action: int)
signal hovered(view: SlotView)

const LONG_PRESS := 0.4
const DOUBLE_TAP := 0.3

var section := ""
var slot := 0
var item_id := 0
var count := 0
var data := 0
var show_count := true
var highlighted := false
## Фоновый значок пустого слота (силуэт брони и т. п.).
var placeholder := ""
var _hover := false
var _press_time := -1.0
var _press_touch := false
var _last_tap := -10.0


func _init(p_section: String = "", p_slot: int = 0, p_size: float = 54.0) -> void:
	section = p_section
	slot = p_slot
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _set_hover(value: bool) -> void:
	_hover = value
	if value:
		hovered.emit(self)
	queue_redraw()


func set_item(id: int, cnt: int, p_data: int = 0) -> void:
	if id == item_id and cnt == count and p_data == data:
		return
	item_id = id
	count = cnt
	data = p_data
	queue_redraw()


func set_highlighted(value: bool) -> void:
	if value != highlighted:
		highlighted = value
		queue_redraw()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var touch := mb.device == InputEvent.DEVICE_ID_EMULATION
		if touch:
			# Касание: тап, удержание (как правая кнопка), двойной тап (как Shift+клик).
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if mb.pressed:
				_press_time = _now()
				_press_touch = true
			elif _press_time >= 0.0:
				var held := _now() - _press_time
				_press_time = -1.0
				if held >= LONG_PRESS:
					clicked.emit(self, 1)
				elif _now() - _last_tap < DOUBLE_TAP:
					_last_tap = -10.0
					clicked.emit(self, 2)
				else:
					_last_tap = _now()
					clicked.emit(self, 0)
				hovered.emit(self)
			accept_event()
			return
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(self, 2 if mb.shift_pressed else 0)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			clicked.emit(self, 1)
			accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.2, 0.2, 0.22, 0.95))
	draw_rect(r.grow(-2.0), Color(0.42, 0.42, 0.45, 0.95))
	if _hover:
		draw_rect(r.grow(-2.0), Color(1, 1, 1, 0.16))
	if item_id > 0 and count > 0:
		draw_texture_rect(TextureFactory.icon(item_id, data), r.grow(-5.0), false)
		var max_d := Items.max_damage(item_id)
		if max_d > 0 and Enchantments.damage_of(data) > 0:
			draw_durability(self, r, Enchantments.damage_of(data), max_d)
		if Enchantments.is_enchanted(data):
			draw_glint(self, r)
		if show_count and count > 1:
			HotbarView.draw_count(self, get_theme_default_font(), r.grow(-2.0), count)
	elif placeholder != "":
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, size.y * 0.62), placeholder, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(1, 1, 1, 0.35))
	if highlighted:
		draw_rect(r.grow(-1.5), Color(1.0, 0.86, 0.25), false, 3.0)


## Отблеск зачарованного предмета (переливающаяся фиолетовая рамка).
static func draw_glint(ci: CanvasItem, r: Rect2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var a := 0.18 + 0.1 * sin(t * 3.0)
	ci.draw_rect(r.grow(-4.0), Color(0.65, 0.35, 1.0, a))
	ci.draw_rect(r.grow(-3.0), Color(0.8, 0.55, 1.0, 0.55), false, 2.0)


## Полоска прочности инструмента (зелёная → красная).
static func draw_durability(ci: CanvasItem, r: Rect2, damage: int, max_d: int) -> void:
	var left := clampf(1.0 - float(damage) / max_d, 0.0, 1.0)
	var bar := Rect2(r.position.x + r.size.x * 0.14, r.end.y - r.size.y * 0.16, r.size.x * 0.72, maxf(r.size.y * 0.06, 3.0))
	ci.draw_rect(bar, Color(0, 0, 0))
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * left, bar.size.y)), Color(1.0 - left, left, 0.0).lerp(Color(0.2, 1, 0.2), 0.0))
