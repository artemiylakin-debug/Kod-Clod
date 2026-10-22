class_name HotbarView
extends Control
## Хотбар из 9 слотов. В сенсорном режиме справа добавляется кнопка инвентаря «•••».

const MENU_SLOT := 99

var inventory: Inventory
var creative := true
var touch_mode := false
var slot_size := 56.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func slots_width() -> float:
	return slot_size * Inventory.HOTBAR_SIZE


func total_width() -> float:
	return slots_width() + (slot_size + 10.0 if touch_mode else 0.0)


func slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(i * slot_size, 0.0), Vector2(slot_size, slot_size))


func menu_rect() -> Rect2:
	return Rect2(Vector2(slots_width() + 10.0, 0.0), Vector2(slot_size, slot_size))


## Слот под точкой экрана: 0–8, MENU_SLOT или -1.
func slot_at(screen_pos: Vector2) -> int:
	if not is_visible_in_tree():
		return -1
	var p := get_global_transform_with_canvas().affine_inverse() * screen_pos
	if p.y < 0.0 or p.y > slot_size:
		return -1
	if touch_mode and menu_rect().has_point(p):
		return MENU_SLOT
	if p.x < 0.0 or p.x >= slots_width():
		return -1
	return int(p.x / slot_size)


func _draw() -> void:
	if inventory == null:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(slots_width(), slot_size)), Color(0.0, 0.0, 0.0, 0.42))
	var font := get_theme_default_font()
	for i in Inventory.HOTBAR_SIZE:
		var r := slot_rect(i).grow(-2.0)
		draw_rect(r, Color(0.62, 0.62, 0.62, 0.55), false, 2.0)
		var id := inventory.ids[i]
		var cnt := inventory.counts[i]
		if cnt > 0 and id > 0:
			draw_texture_rect(TextureFactory.icon(id, inventory.datas[i]), r.grow(-5.0), false)
			var max_d := Items.max_damage(id)
			if max_d > 0 and inventory.datas[i] > 0:
				SlotView.draw_durability(self, r, inventory.datas[i], max_d)
			if not creative and cnt > 1:
				draw_count(self, font, r, cnt)
	var sel := slot_rect(inventory.selected).grow(1.0)
	draw_rect(sel, Color(0.0, 0.0, 0.0, 0.6), false, 6.0)
	draw_rect(sel, Color(1.0, 1.0, 1.0), false, 3.0)
	if touch_mode:
		var m := menu_rect()
		draw_rect(m, Color(0.0, 0.0, 0.0, 0.42))
		draw_rect(m.grow(-2.0), Color(0.62, 0.62, 0.62, 0.55), false, 2.0)
		for k in 3:
			draw_circle(m.get_center() + Vector2((k - 1) * 12.0, 0.0), 4.0, Color(1, 1, 1, 0.9))


## Число предметов в правом нижнем углу слота (с тенью).
static func draw_count(ci: CanvasItem, font: Font, r: Rect2, cnt: int) -> void:
	var fs := 20
	var text := str(cnt)
	var pos := Vector2(r.position.x, r.end.y - 4.0)
	ci.draw_string(font, pos + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 3.0, fs, Color(0.1, 0.1, 0.1))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 3.0, fs, Color(1, 1, 1))
