class_name AchievementsPanel
extends Control
## Экран достижений и статистики (меню паузы): 27 достижений 1.2 с отметками и счётчики игры.

signal closed

var _list: VBoxContainer
var _summary: Label
var _tab_ach: Button
var _tab_stats: Button
var _showing_stats := false


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
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(tabs)
	var group := ButtonGroup.new()
	_tab_ach = UITheme.button("Достижения", 300)
	_tab_stats = UITheme.button("Статистика", 300)
	var chosen := UITheme.box(Color(0.24, 0.48, 0.24, 0.96), Color(0.92, 1.0, 0.85), 3)
	for b: Button in [_tab_ach, _tab_stats]:
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_stylebox_override("pressed", chosen)
		b.add_theme_stylebox_override("hover_pressed", chosen)
		tabs.add_child(b)
	_tab_ach.pressed.connect(func() -> void: _show(false))
	_tab_stats.pressed.connect(func() -> void: _show(true))
	_summary = UITheme.label("", 18, Color(0.8, 0.8, 0.8))
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_summary)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var done := UITheme.button("Готово", 0)
	done.pressed.connect(close_panel)
	vbox.add_child(done)


func open() -> void:
	visible = true
	_tab_ach.button_pressed = true
	_show(false)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _show(stats: bool) -> void:
	_showing_stats = stats
	(_tab_stats if stats else _tab_ach).set_pressed_no_signal(true)
	for c in _list.get_children():
		c.queue_free()
	if stats:
		_fill_stats()
	else:
		_fill_achievements()


func _fill_achievements() -> void:
	var got := 0
	for a: Array in Achievements.LIST:
		var id: String = a[0]
		var have := Achievements.has(id)
		if have:
			got += 1
		var open := have or Achievements.can_unlock(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var icon := TextureRect.new()
		icon.texture = TextureFactory.icon(int(a[3]))
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if not have:
			icon.modulate = Color(0.35, 0.35, 0.35) if open else Color(0.15, 0.15, 0.15)
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var title := UITheme.label(("✔ " if have else "") + str(a[1]), 21,
			Color(0.55, 1.0, 0.45) if have else (Color(1, 1, 1) if open else Color(0.55, 0.55, 0.55)))
		text.add_child(title)
		var desc := str(a[2])
		if not open:
			desc = "Сначала получите «%s»" % str(Achievements.info(str(a[4]))[1])
		var d := UITheme.label(desc, 16, Color(0.75, 0.75, 0.75) if open else Color(0.5, 0.5, 0.5))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(600, 0)
		text.add_child(d)
		_list.add_child(row)
	_summary.text = "Получено %d из %d" % [got, Achievements.LIST.size()]


func _fill_stats() -> void:
	for s: Array in Achievements.STATS:
		var row := HBoxContainer.new()
		var name_label := UITheme.label(str(s[1]), 20)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var value := UITheme.label(Achievements.format_stat(str(s[0]), str(s[2])), 20, Color(1.0, 0.9, 0.45))
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(200, 0)
		row.add_child(value)
		_list.add_child(row)
	_summary.text = "Общая статистика всех миров"
