class_name TouchControls
extends Control
## Сенсорное управление (мультитач):
## • левая часть экрана — плавающий джойстик (толкнуть вперёд до упора — бег);
## • правая часть — обзор пальцем; короткий тап — поставить блок, удержание — ломать;
## • кнопки: прыжок (двойной тап в креативе — полёт), присесть/вниз, ломать, поставить, полёт, пауза;
## • тап по хотбару выбирает слот, «•••» открывает инвентарь.

signal pause_requested
signal inventory_requested

enum { R_NONE, R_JOY, R_LOOK, R_JUMP, R_SNEAK, R_BREAK, R_PLACE, R_FLY, R_PAUSE, R_INVENTORY, R_HOTBAR }

const TAP_TIME := 0.25
const TAP_SLOP := 16.0
const HOLD_TIME := 0.35
const JOY_RADIUS := 95.0
const KNOB_RADIUS := 40.0

var player: Player
var hotbar: HotbarView
var sensitivity := 0.3

var _touches: Dictionary = {}
var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _joy_default := Vector2.ZERO
var _buttons: Dictionary = {}
var _sneak_toggled := false
var _margins := Vector4.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	_layout()


func set_margins(m: Vector4) -> void:
	_margins = m
	_layout()


func _layout() -> void:
	var w := size.x
	var h := size.y
	var l := 34.0 + _margins.x
	var r := 30.0 + _margins.z
	var t := 18.0 + _margins.y
	var b := 26.0 + _margins.w
	_joy_default = Vector2(l + 140.0, h - b - 150.0)
	var jump := Vector2(w - r - 88.0, h - b - 100.0)
	_buttons.clear()
	_buttons[R_JUMP] = [jump, 68.0]
	_buttons[R_SNEAK] = [jump + Vector2(0.0, -168.0), 50.0]
	_buttons[R_BREAK] = [jump + Vector2(-168.0, -38.0), 56.0]
	_buttons[R_PLACE] = [jump + Vector2(-150.0, -178.0), 56.0]
	_buttons[R_FLY] = [jump + Vector2(0.0, -284.0), 44.0]
	_buttons[R_PAUSE] = [Vector2(w - r - 30.0, t + 30.0), 30.0]
	queue_redraw()


func _button_visible(role: int) -> bool:
	if role == R_FLY:
		return player != null and player.creative
	return true


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or player == null:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_press(st.index, st.position)
		else:
			_release(st.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_drag(sd.index, sd.position, sd.relative)
		get_viewport().set_input_as_handled()


func _press(index: int, pos: Vector2) -> void:
	if _touches.has(index):
		_release(index)
	var role := R_LOOK
	for rid: int in _buttons:
		if not _button_visible(rid):
			continue
		var btn: Array = _buttons[rid]
		var center: Vector2 = btn[0]
		var radius: float = btn[1]
		if pos.distance_to(center) <= radius * 1.2:
			role = rid
			break
	if role == R_LOOK and hotbar != null:
		var slot := hotbar.slot_at(pos)
		if slot == HotbarView.MENU_SLOT:
			role = R_INVENTORY
		elif slot >= 0:
			role = R_HOTBAR
			player.inventory.select(slot)
	if role == R_LOOK and _joy_index == -1 and pos.x < size.x * 0.4 and pos.y > size.y * 0.3:
		role = R_JOY
		_joy_index = index
		_joy_center = pos
		_joy_knob = pos
	_touches[index] = {"role": role, "t0": _now(), "moved": 0.0, "holding": false}
	match role:
		R_JUMP:
			player.touch_jump = true
			player.on_jump_pressed()
		R_SNEAK:
			if player.flying:
				player.touch_sneak = true
			else:
				_sneak_toggled = not _sneak_toggled
				player.touch_sneak = _sneak_toggled
		R_BREAK:
			_refresh_break()
		R_PLACE:
			player.queue_place()
			player.touch_place = true
		R_FLY:
			player.set_flying(not player.flying)
		R_PAUSE:
			pause_requested.emit()
		R_INVENTORY:
			inventory_requested.emit()
	queue_redraw()


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var t: Dictionary = _touches.get(index, {})
	if t.is_empty():
		return
	t["moved"] = float(t["moved"]) + rel.length()
	match int(t["role"]):
		R_JOY:
			_joy_knob = pos
			_update_joystick()
		R_LOOK:
			player.rotate_view(-rel.x * sensitivity, -rel.y * sensitivity)
	queue_redraw()


func _release(index: int) -> void:
	var t: Dictionary = _touches.get(index, {})
	if t.is_empty():
		return
	_touches.erase(index)
	match int(t["role"]):
		R_JOY:
			_joy_index = -1
			player.touch_move = Vector2.ZERO
			player.touch_sprint = false
		R_LOOK:
			if not bool(t["holding"]) and _now() - float(t["t0"]) < TAP_TIME and float(t["moved"]) < TAP_SLOP:
				player.queue_place()
		R_JUMP:
			player.touch_jump = false
		R_SNEAK:
			player.touch_sneak = _sneak_toggled and not player.flying
		R_PLACE:
			player.touch_place = false
	_refresh_break()
	queue_redraw()


func _refresh_break() -> void:
	var breaking := false
	for idx: int in _touches:
		var t: Dictionary = _touches[idx]
		var role := int(t["role"])
		if role == R_BREAK or (role == R_LOOK and bool(t["holding"])):
			breaking = true
	player.touch_break = breaking


func _update_joystick() -> void:
	var v := (_joy_knob - _joy_center) / JOY_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() < 0.15:
		v = Vector2.ZERO
	player.touch_move = v
	player.touch_sprint = v.y < -0.9


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or player == null:
		return
	var changed := false
	for idx: int in _touches:
		var t: Dictionary = _touches[idx]
		if int(t["role"]) == R_LOOK and not bool(t["holding"]) \
				and _now() - float(t["t0"]) >= HOLD_TIME and float(t["moved"]) < TAP_SLOP * 2.0:
			t["holding"] = true
			changed = true
	if changed:
		_refresh_break()


## Сброс всех касаний (например, при открытии меню).
func reset() -> void:
	_touches.clear()
	_joy_index = -1
	if player != null:
		player.touch_move = Vector2.ZERO
		player.touch_sprint = false
		player.touch_jump = false
		player.touch_break = false
		player.touch_place = false
		player.touch_sneak = _sneak_toggled
	queue_redraw()


func _on_visibility_changed() -> void:
	if not visible:
		reset()


func _role_pressed(role: int) -> bool:
	for idx: int in _touches:
		if int(_touches[idx]["role"]) == role:
			return true
	return false


# --- Отрисовка -------------------------------------------------------------

func _draw() -> void:
	if player == null:
		return
	var active := _joy_index != -1
	var c := _joy_center if active else _joy_default
	var knob := _joy_knob if active else c
	if active:
		var off := knob - c
		if off.length() > JOY_RADIUS:
			knob = c + off.normalized() * JOY_RADIUS
	draw_circle(c, JOY_RADIUS, Color(1, 1, 1, 0.1))
	draw_arc(c, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.38), 3.0, true)
	draw_circle(knob, KNOB_RADIUS, Color(1, 1, 1, 0.38 if active else 0.25))
	for rid: int in _buttons:
		if _button_visible(rid):
			_draw_button(rid)


func _draw_button(role: int) -> void:
	var btn: Array = _buttons[role]
	var c: Vector2 = btn[0]
	var r: float = btn[1]
	var on := _role_pressed(role)
	if role == R_SNEAK:
		on = on or (_sneak_toggled and not player.flying)
	elif role == R_FLY:
		on = on or player.flying
	draw_circle(c, r, Color(1, 1, 1, 0.34 if on else 0.14))
	draw_arc(c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.55), 2.5, true)
	var ic := Color(1, 1, 1, 0.9)
	match role:
		R_JUMP:
			_draw_arrow(c, -1.0, 22.0, ic)
		R_SNEAK:
			_draw_arrow(c + Vector2(0, -4), 1.0, 16.0, ic)
			if not player.flying:
				draw_rect(Rect2(c.x - 16.0, c.y + 16.0, 32.0, 4.0), ic)
		R_BREAK:
			_draw_pickaxe(c, ic)
		R_PLACE:
			var id := player.inventory.get_selected_block()
			if id != Blocks.AIR:
				draw_texture_rect(TextureFactory.icons[id], Rect2(c - Vector2(26, 26), Vector2(52, 52)), false)
			else:
				draw_rect(Rect2(c - Vector2(16, 16), Vector2(32, 32)), ic, false, 3.0)
		R_FLY:
			var font := get_theme_default_font()
			draw_string(font, c + Vector2(-r, 7.0), "ПОЛЁТ", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 17, ic)
		R_PAUSE:
			draw_rect(Rect2(c.x - 9.0, c.y - 11.0, 6.0, 22.0), ic)
			draw_rect(Rect2(c.x + 3.0, c.y - 11.0, 6.0, 22.0), ic)


## Стрелка вверх (dir = -1) или вниз (dir = 1).
func _draw_arrow(c: Vector2, dir: float, s: float, col: Color) -> void:
	var tip := c + Vector2(0.0, dir * s)
	var base_y := c.y + dir * s * 0.05
	draw_colored_polygon(PackedVector2Array([tip, Vector2(c.x - s, base_y), Vector2(c.x + s, base_y)]), col)
	var stem_top := minf(base_y, c.y - dir * s * 0.85)
	draw_rect(Rect2(c.x - s * 0.32, stem_top, s * 0.64, absf(base_y - (c.y - dir * s * 0.85))), col)


func _draw_pickaxe(c: Vector2, col: Color) -> void:
	draw_set_transform(c, -PI / 4.0, Vector2.ONE)
	draw_line(Vector2(0, -14), Vector2(0, 26), Color(0.75, 0.55, 0.32, 0.95), 6.0)
	draw_arc(Vector2(0, 12), 26.0, deg_to_rad(205.0), deg_to_rad(335.0), 14, col, 7.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)
