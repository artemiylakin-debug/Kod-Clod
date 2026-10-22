class_name UITheme
extends RefCounted
## Тема интерфейса в духе Minecraft: серые кнопки с рамкой, тени у текста, крупные элементы для пальцев.

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22

	var normal := box(Color(0.36, 0.36, 0.38, 0.96), Color(0.05, 0.05, 0.05), 3)
	var hover := box(Color(0.42, 0.45, 0.64, 0.96), Color(0.95, 0.95, 0.95), 3)
	var pressed := box(Color(0.24, 0.24, 0.3, 0.96), Color(0.05, 0.05, 0.05), 3)
	var disabled := box(Color(0.2, 0.2, 0.2, 0.85), Color(0.1, 0.1, 0.1), 3)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, hover)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, Color(0.95, 0.95, 0.95))
		t.set_color("font_hover_color", type, Color(1.0, 1.0, 0.62))
		t.set_color("font_hover_pressed_color", type, Color(1.0, 1.0, 0.62))
		t.set_color("font_pressed_color", type, Color(0.88, 0.88, 0.88))
		t.set_color("font_focus_color", type, Color(0.95, 0.95, 0.95))
		t.set_color("font_disabled_color", type, Color(0.52, 0.52, 0.52))
		t.set_color("font_outline_color", type, Color(0.1, 0.1, 0.1))
		t.set_constant("outline_size", type, 4)

	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.7))
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)

	var panel := box(Color(0.08, 0.08, 0.1, 0.86), Color(0.55, 0.55, 0.58), 3, 20.0, 18.0)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var edit := box(Color(0.0, 0.0, 0.0, 0.8), Color(0.62, 0.62, 0.62), 2, 12.0, 8.0)
	var edit_focus := box(Color(0.0, 0.0, 0.0, 0.85), Color(1.0, 1.0, 1.0), 2, 12.0, 8.0)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", Color(0.95, 0.95, 0.95))
	t.set_color("font_placeholder_color", "LineEdit", Color(0.6, 0.6, 0.6))

	var popup := box(Color(0.12, 0.12, 0.14, 0.98), Color(0.6, 0.6, 0.6), 2, 10.0, 10.0)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_constant("v_separation", "PopupMenu", 14)

	# Крупные ползунки и полосы прокрутки — удобно пальцем.
	var slider := box(Color(0.0, 0.0, 0.0, 0.75), Color(0.55, 0.55, 0.55), 2, 0.0, 5.0)
	t.set_stylebox("slider", "HSlider", slider)
	var grabber_area := box(Color(0.55, 0.62, 0.85, 0.9), Color(0.55, 0.62, 0.85, 0.9), 0, 0.0, 5.0)
	t.set_stylebox("grabber_area", "HSlider", grabber_area)
	t.set_stylebox("grabber_area_highlight", "HSlider", grabber_area)
	var grabber := _circle_icon(30, Color(0.92, 0.92, 0.92), Color(0.2, 0.2, 0.2))
	t.set_icon("grabber", "HSlider", grabber)
	t.set_icon("grabber_highlight", "HSlider", _circle_icon(30, Color(1.0, 1.0, 0.7), Color(0.2, 0.2, 0.2)))

	var scroll := box(Color(0.0, 0.0, 0.0, 0.35), Color(0.0, 0.0, 0.0, 0.0), 0, 7.0, 7.0)
	var scroll_grab := box(Color(0.7, 0.7, 0.7, 0.8), Color(0.0, 0.0, 0.0, 0.0), 0, 7.0, 7.0)
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("grabber", "VScrollBar", scroll_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", scroll_grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", scroll_grab)
	return t


static func box(bg: Color, border: Color, width: int, margin_h: float = 16.0, margin_v: float = 8.0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(4)
	b.content_margin_left = margin_h
	b.content_margin_right = margin_h
	b.content_margin_top = margin_v
	b.content_margin_bottom = margin_v
	return b


static func _circle_icon(size: int, fill: Color, outline: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			if d <= c - 2.0:
				img.set_pixel(x, y, fill)
			elif d <= c:
				img.set_pixel(x, y, outline)
	return ImageTexture.create_from_image(img)


## Утилита: прикрепить элемент к точке-якорю (доли экрана) со смещением и размером.
static func place(c: Control, anchor: Vector2, offset: Vector2, size: Vector2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + size.x
	c.offset_bottom = offset.y + size.y


static func label(text: String, font_size: int = 22, color: Color = Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, min_width: float = 0.0, font_size: int = 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 58)
	b.add_theme_font_size_override("font_size", font_size)
	return b


## Полупрозрачное затемнение на весь экран (перехватывает клики по миру).
static func dim(alpha: float = 0.55) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r
