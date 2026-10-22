class_name PauseMenu
extends Control
## Меню паузы: продолжить, сменить режим игры, настройки, сохранить и выйти.

signal resume_requested
signal mode_toggle_requested
signal settings_requested
signal quit_requested

var _mode_button: Button
var _info: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_child(UITheme.dim(0.55))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)
	var title := UITheme.label("Игра на паузе", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_info = UITheme.label("", 18, Color(0.8, 0.8, 0.8))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_info)
	var resume := UITheme.button("Вернуться к игре", 460)
	resume.pressed.connect(func() -> void: resume_requested.emit())
	vbox.add_child(resume)
	_mode_button = UITheme.button("", 460)
	_mode_button.pressed.connect(func() -> void: mode_toggle_requested.emit())
	vbox.add_child(_mode_button)
	var settings := UITheme.button("Настройки", 460)
	settings.pressed.connect(func() -> void: settings_requested.emit())
	vbox.add_child(settings)
	var quit := UITheme.button("Сохранить и выйти в меню", 460)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	vbox.add_child(quit)


func set_info(world_name: String, seed_value: int, creative: bool) -> void:
	_info.text = "Мир «%s» · сид %d" % [world_name, seed_value]
	_mode_button.text = "Режим: Креатив (сменить)" if creative else "Режим: Выживание (сменить)"
