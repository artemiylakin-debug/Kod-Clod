extends Control
## Главное меню: список миров, создание нового мира (выживание/креатив, сид), настройки.

const SPLASHES := ["Теперь на Godot!", "Копай и строй!", "Сохраняется само!", "И на телефоне тоже!", "Кубы повсюду!"]

var _main: Control
var _worlds: Control
var _world_list: VBoxContainer
var _create: Control
var _name_edit: LineEdit
var _seed_edit: LineEdit
var _creative_btn: Button
var _survival_btn: Button
var _mode_hint: Label
var _confirm: Control
var _confirm_label: Label
var _confirm_id := ""
var _settings: SettingsPanel
var _splash: Label
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := TextureRect.new()
	bg.texture = TextureFactory.background
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_main()
	_build_worlds()
	_build_create()
	_build_confirm()
	_settings = SettingsPanel.new()
	_settings.closed.connect(_show.bind("main"))
	add_child(_settings)
	var version := UITheme.label("BlockCraft %s · Godot %s" % [Game.VERSION, Engine.get_version_info()["string"]], 16, Color(0.85, 0.85, 0.85))
	UITheme.place(version, Vector2(0, 1), Vector2(12, -34), Vector2(600, 28))
	add_child(version)
	_show("main")


func _build_main() -> void:
	_main = Control.new()
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_main)
	var title := UITheme.label("BLOCKCRAFT", 96)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.15, 0.15))
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 5)
	UITheme.place(title, Vector2(0.5, 0.0), Vector2(-500, 70), Vector2(1000, 120))
	_main.add_child(title)
	_splash = UITheme.label(SPLASHES[randi() % SPLASHES.size()], 26, Color(1.0, 1.0, 0.3))
	_splash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.place(_splash, Vector2(0.5, 0.0), Vector2(170, 170), Vector2(360, 40))
	_splash.pivot_offset = Vector2(180, 20)
	_splash.rotation = deg_to_rad(-14.0)
	_main.add_child(_splash)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	UITheme.place(box, Vector2(0.5, 0.5), Vector2(-250, -30), Vector2(500, 260))
	_main.add_child(box)
	var play := UITheme.button("Одиночная игра", 500, 28)
	play.pressed.connect(_show.bind("worlds"))
	box.add_child(play)
	var settings := UITheme.button("Настройки", 500, 28)
	settings.pressed.connect(func() -> void:
		_show("")
		_settings.open())
	box.add_child(settings)
	if not OS.has_feature("web"):
		var quit := UITheme.button("Выход", 500, 28)
		quit.pressed.connect(Game.quit_game)
		box.add_child(quit)


func _panel_screen(title_text: String, size: Vector2) -> Array:
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	screen.add_child(UITheme.dim(0.35))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	var title := UITheme.label(title_text, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	return [screen, vbox]


func _build_worlds() -> void:
	var res := _panel_screen("Выбор мира", Vector2(860, 0))
	_worlds = res[0]
	var vbox: VBoxContainer = res[1]
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_world_list = VBoxContainer.new()
	_world_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_world_list)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)
	var create := UITheme.button("Создать новый мир", 400)
	create.pressed.connect(_show.bind("create"))
	buttons.add_child(create)
	var back := UITheme.button("Назад", 220)
	back.pressed.connect(_show.bind("main"))
	buttons.add_child(back)


func _refresh_worlds() -> void:
	for c in _world_list.get_children():
		c.queue_free()
	var worlds := WorldStorage.list_worlds()
	if worlds.is_empty():
		var empty := UITheme.label("Пока нет ни одного мира — создайте первый!", 22, Color(0.8, 0.8, 0.8))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(800, 120)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_world_list.add_child(empty)
		return
	for meta in worlds:
		var id: String = meta["id"]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UITheme.box(Color(0.18, 0.18, 0.2, 0.9), Color(0.4, 0.4, 0.42), 2, 14.0, 10.0))
		_world_list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		var icon := TextureRect.new()
		icon.texture = TextureFactory.icon(Blocks.BRICKS if bool(meta.get("creative", false)) else Blocks.GRASS)
		icon.custom_minimum_size = Vector2(56, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(icon)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var name_label := UITheme.label(str(meta.get("name", "Мир")), 24)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size = Vector2(300, 0)
		info.add_child(name_label)
		var mode := "Креатив" if bool(meta.get("creative", false)) else "Выживание"
		var details := "%s · сид %d · %s" % [mode, int(meta.get("seed", 0)), _format_time(float(meta.get("last_played", 0)))]
		info.add_child(UITheme.label(details, 17, Color(0.72, 0.72, 0.72)))
		var play := UITheme.button("Играть", 150, 22)
		play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		play.pressed.connect(Game.start_world.bind(id))
		h.add_child(play)
		var del := UITheme.button("Удалить", 140, 20)
		del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		del.pressed.connect(_ask_delete.bind(id, str(meta.get("name", "Мир"))))
		h.add_child(del)


func _format_time(unix: float) -> String:
	if unix <= 0.0:
		return "—"
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + bias * 60)
	return "%02d.%02d.%04d %02d:%02d" % [d["day"], d["month"], d["year"], d["hour"], d["minute"]]


func _build_create() -> void:
	var res := _panel_screen("Новый мир", Vector2(640, 0))
	_create = res[0]
	var vbox: VBoxContainer = res[1]
	vbox.add_child(UITheme.label("Название мира", 20, Color(0.8, 0.8, 0.8)))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(600, 52)
	_name_edit.max_length = 32
	vbox.add_child(_name_edit)
	vbox.add_child(UITheme.label("Режим игры", 20, Color(0.8, 0.8, 0.8)))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 12)
	vbox.add_child(modes)
	var group := ButtonGroup.new()
	_survival_btn = UITheme.button("Выживание", 294)
	_survival_btn.toggle_mode = true
	_survival_btn.button_group = group
	modes.add_child(_survival_btn)
	_creative_btn = UITheme.button("Креатив", 294)
	_creative_btn.toggle_mode = true
	_creative_btn.button_group = group
	modes.add_child(_creative_btn)
	var chosen := UITheme.box(Color(0.24, 0.48, 0.24, 0.96), Color(0.92, 1.0, 0.85), 3)
	for btn: Button in [_survival_btn, _creative_btn]:
		btn.add_theme_stylebox_override("pressed", chosen)
		btn.add_theme_stylebox_override("hover_pressed", chosen)
	_mode_hint = UITheme.label("", 17, Color(0.75, 0.75, 0.75))
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_hint.custom_minimum_size = Vector2(600, 50)
	vbox.add_child(_mode_hint)
	_survival_btn.toggled.connect(func(_on: bool) -> void: _update_mode_hint())
	_creative_btn.toggled.connect(func(_on: bool) -> void: _update_mode_hint())
	vbox.add_child(UITheme.label("Сид генератора", 20, Color(0.8, 0.8, 0.8)))
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Оставьте пустым для случайного мира"
	_seed_edit.custom_minimum_size = Vector2(600, 52)
	vbox.add_child(_seed_edit)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)
	var create := UITheme.button("Создать мир", 300)
	create.pressed.connect(_create_world)
	buttons.add_child(create)
	var cancel := UITheme.button("Отмена", 200)
	cancel.pressed.connect(_show.bind("worlds"))
	buttons.add_child(cancel)


func _update_mode_hint() -> void:
	if _creative_btn.button_pressed:
		_mode_hint.text = "Бесконечные блоки, мгновенное разрушение, полёт (двойной прыжок), нет урона."
	else:
		_mode_hint.text = "Здоровье и урон от падения, блоки добываются со временем и попадают в инвентарь, есть крафт."


func _create_world() -> void:
	var world_name := _name_edit.text.strip_edges()
	if world_name.is_empty():
		world_name = "Новый мир"
	var id := Game.create_world(world_name, _creative_btn.button_pressed, _seed_edit.text)
	Game.start_world(id)


func _build_confirm() -> void:
	var res := _panel_screen("Удалить мир?", Vector2(600, 0))
	_confirm = res[0]
	var vbox: VBoxContainer = res[1]
	_confirm_label = UITheme.label("", 22)
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.custom_minimum_size = Vector2(560, 80)
	vbox.add_child(_confirm_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)
	var yes := UITheme.button("Удалить", 240)
	yes.pressed.connect(func() -> void:
		WorldStorage.delete_world(_confirm_id)
		_show("worlds"))
	buttons.add_child(yes)
	var no := UITheme.button("Отмена", 240)
	no.pressed.connect(_show.bind("worlds"))
	buttons.add_child(no)


func _ask_delete(id: String, world_name: String) -> void:
	_confirm_id = id
	_confirm_label.text = "Мир «%s» будет удалён навсегда." % world_name
	_show("confirm")


func _show(screen: String) -> void:
	_main.visible = screen == "main"
	_worlds.visible = screen == "worlds"
	_create.visible = screen == "create"
	_confirm.visible = screen == "confirm"
	if screen == "worlds":
		_refresh_worlds()
	elif screen == "create":
		_name_edit.text = "Новый мир"
		_seed_edit.text = ""
		_survival_btn.button_pressed = true
		_update_mode_hint()


## Кнопка «Назад» на Android: возврат на предыдущий экран, из главного — выход.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or _main == null:
		return
	if _settings.visible:
		_settings.close_panel()
	elif _create.visible or _confirm.visible:
		_show("worlds")
	elif _worlds.visible:
		_show("main")
	else:
		Game.quit_game()


## Показ экранов для автотестов.
func show_screen(screen: String) -> void:
	_show(screen)


func _process(delta: float) -> void:
	_time += delta
	_splash.scale = Vector2.ONE * (1.0 + sin(_time * 6.0) * 0.04)
