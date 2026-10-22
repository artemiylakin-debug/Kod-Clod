extends Node
## Автозагрузка «Game»: настройки, раскладка управления, переходы между сценами, создание миров.

signal settings_changed

const VERSION := "1.0"
const SETTINGS_PATH := "user://settings.cfg"
const MAIN_MENU := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/game.tscn"

var settings := {
	"render_distance": 6,
	"fov": 75.0,
	"mouse_sensitivity": 0.15,
	"touch_sensitivity": 0.3,
	"touch_controls": 0, # 0 — авто, 1 — всегда, 2 — никогда
	"auto_jump": true,
	"show_fps": false,
}
## Тема интерфейса. Назначается корню окна и верхним Control внутри CanvasLayer
## (CanvasLayer прерывает наследование темы от окна).
var ui_theme: Theme
var current_world_id := ""
var current_world_dir := ""
## Запущен автотест (--visual-test): не ставим игру на паузу при потере фокуса и т. п.
var test_mode := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_mobile() or OS.has_feature("web"):
		settings["render_distance"] = 4
	_setup_input_map()
	load_settings()
	TextureFactory.ensure_initialized()
	# Статические таблицы мешера инициализируются в главном потоке, до запуска фоновых задач.
	if ChunkMesher.neighbor_off.size() != 6:
		push_error("Таблицы мешера не инициализированы")
	ui_theme = UITheme.build()
	get_tree().root.theme = ui_theme
	get_tree().set_auto_accept_quit(false)
	var args := OS.get_cmdline_user_args()
	if "--visual-test" in args:
		test_mode = true
		var runner: Node = load("res://tests/visual_test.gd").new()
		add_child.call_deferred(runner)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


func _exit_tree() -> void:
	TextureFactory.release()


func quit_game() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("save_game"):
		scene.call("save_game")
	get_tree().quit()


# --- Управление ------------------------------------------------------------

func _setup_input_map() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("jump", [KEY_SPACE])
	_bind("sneak", [KEY_SHIFT])
	_bind("sprint", [KEY_CTRL])
	_bind("inventory", [KEY_E])
	_bind("pause", [KEY_ESCAPE])
	_bind("drop_item", [KEY_Q])
	_bind("toggle_debug", [KEY_F3])
	_bind("toggle_mode", [KEY_F4])


## Используются физические клавиши, чтобы WASD работали и в русской раскладке.
func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	for k: int in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func is_touch_enabled() -> bool:
	match int(settings["touch_controls"]):
		1:
			return true
		2:
			return false
	return is_mobile() or DisplayServer.is_touchscreen_available()


## Отступы безопасной зоны (вырезы экрана) в координатах интерфейса: x — слева, y — сверху, z — справа, w — снизу.
func safe_margins() -> Vector4:
	if not is_mobile():
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or safe.size.x <= 0:
		return Vector4.ZERO
	var k := get_viewport().get_visible_rect().size.x / win.x
	return Vector4(maxf(safe.position.x, 0.0), maxf(safe.position.y, 0.0),
		maxf(win.x - safe.end.x, 0.0), maxf(win.y - safe.end.y, 0.0)) * k


# --- Настройки -------------------------------------------------------------

func set_setting(key: String, value: Variant) -> void:
	if key == "render_distance" or key == "touch_controls":
		value = int(value)
	settings[key] = value
	settings_changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key: String in settings.keys():
		if cfg.has_section_key("settings", key):
			settings[key] = cfg.get_value("settings", key)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: String in settings.keys():
		cfg.set_value("settings", key, settings[key])
	cfg.save(SETTINGS_PATH)


# --- Миры ------------------------------------------------------------------

func create_world(world_name: String, creative: bool, seed_text: String) -> String:
	var seed_value := randi() & 0x7FFFFFFF
	seed_text = seed_text.strip_edges()
	if not seed_text.is_empty():
		seed_value = (seed_text.to_int() if seed_text.is_valid_int() else seed_text.hash()) & 0x7FFFFFFF
	var now := Time.get_unix_time_from_system()
	var id := "world_%d_%04d" % [int(now), randi() % 10000]
	var meta := {
		"name": world_name,
		"seed": seed_value,
		"creative": creative,
		"created": now,
		"last_played": now,
		"time": 0.08,
		"version": 2,
		"difficulty": 2,
	}
	WorldStorage.save_meta(WorldStorage.world_dir(id), meta)
	return id


func start_world(id: String) -> void:
	current_world_id = id
	current_world_dir = WorldStorage.world_dir(id)
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func goto_main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)
