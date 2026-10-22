class_name SettingsPanel
extends Control
## Настройки: дальность прорисовки, поле зрения, чувствительность, сенсорное управление.

signal closed

var _rows: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_child(UITheme.dim(0.6))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var title := UITheme.label("Настройки", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	vbox.add_child(_rows)

	_add_slider("Дальность прорисовки", "render_distance", 2, 12, 1, func(v: float) -> String: return "%d чанков" % int(v))
	_add_slider("Поле зрения", "fov", 55, 110, 1, func(v: float) -> String: return "%d°" % int(v))
	_add_slider("Чувствительность мыши", "mouse_sensitivity", 0.03, 0.5, 0.01, func(v: float) -> String: return "%d%%" % roundi(v / 0.15 * 100.0))
	_add_slider("Чувствительность касаний", "touch_sensitivity", 0.08, 1.0, 0.01, func(v: float) -> String: return "%d%%" % roundi(v / 0.3 * 100.0))

	var row := _row("Сенсорное управление")
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(300, 52)
	opt.add_item("Автоматически", 0)
	opt.add_item("Включено", 1)
	opt.add_item("Выключено", 2)
	opt.select(int(Game.settings["touch_controls"]))
	opt.item_selected.connect(func(i: int) -> void: Game.set_setting("touch_controls", i))
	row.add_child(opt)

	_add_check("Автопрыжок (сенсорное управление)", "auto_jump")
	_add_check("Показывать FPS и координаты", "show_fps")

	var done := UITheme.button("Готово", 0)
	done.pressed.connect(close_panel)
	vbox.add_child(done)


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := UITheme.label(text, 22)
	l.custom_minimum_size = Vector2(330, 0)
	row.add_child(l)
	_rows.add_child(row)
	return row


func _add_slider(text: String, key: String, min_v: float, max_v: float, step: float, fmt: Callable) -> void:
	var row := _row(text)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = float(Game.settings[key])
	slider.custom_minimum_size = Vector2(300, 44)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := UITheme.label(fmt.call(slider.value), 20, Color(0.85, 0.85, 0.85))
	value_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = fmt.call(v)
		Game.set_setting(key, v))


func _add_check(text: String, key: String) -> void:
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = bool(Game.settings[key])
	cb.add_theme_font_size_override("font_size", 22)
	cb.toggled.connect(func(on: bool) -> void: Game.set_setting(key, on))
	_rows.add_child(cb)


func open() -> void:
	visible = true


func close_panel() -> void:
	if not visible:
		return
	visible = false
	Game.save_settings()
	closed.emit()
