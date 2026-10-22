class_name SlotView
extends Control
## Слот инвентаря: иконка, количество, подсветка. Нажатие — мышью или пальцем.

signal pressed(slot: int)

var slot := 0
var item_id := 0
var count := 0
var show_count := true
var highlighted := false
var _hover := false


func _init(p_slot: int = 0, p_size: float = 58.0) -> void:
	slot = p_slot
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _set_hover(value: bool) -> void:
	_hover = value
	queue_redraw()


func set_item(id: int, cnt: int) -> void:
	if id == item_id and cnt == count:
		return
	item_id = id
	count = cnt
	queue_redraw()


func set_highlighted(value: bool) -> void:
	if value != highlighted:
		highlighted = value
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(slot)
			accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.2, 0.2, 0.22, 0.95))
	draw_rect(r.grow(-2.0), Color(0.42, 0.42, 0.45, 0.95))
	if _hover:
		draw_rect(r.grow(-2.0), Color(1, 1, 1, 0.16))
	if item_id > 0 and count > 0:
		draw_texture_rect(TextureFactory.icons[item_id], r.grow(-6.0), false)
		if show_count and count > 1:
			HotbarView.draw_count(self, get_theme_default_font(), r.grow(-2.0), count)
	if highlighted:
		draw_rect(r.grow(-1.5), Color(1.0, 0.86, 0.25), false, 3.0)
