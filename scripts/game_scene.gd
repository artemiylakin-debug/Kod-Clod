extends Node3D
## Игровая сцена: связывает мир, логику блоков, существ, игрока и интерфейс; смена дня и ночи,
## сон, смерть и возрождение, автосохранение (каждые 15 секунд, при паузе, сворачивании и выходе).

const DAY_LENGTH := 1200.0
const AUTOSAVE_INTERVAL := 15.0
const CLOUD_HEIGHT := 128.0

const DAY_TOP := Color(0.32, 0.55, 0.96)
const DAY_HORIZON := Color(0.68, 0.82, 1.0)
const NIGHT_TOP := Color(0.01, 0.015, 0.05)
const NIGHT_HORIZON := Color(0.05, 0.06, 0.12)
const DUSK_HORIZON := Color(0.98, 0.58, 0.32)
const WATER_FOG := Color(0.08, 0.2, 0.48)
const LAVA_FOG := Color(0.6, 0.12, 0.0)

const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D clouds : source_color, filter_nearest, repeat_enable;
uniform float daylight = 1.0;
uniform float fade_start = 80.0;
uniform float fade_end = 160.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (v_world.xz + vec2(TIME * 1.5, 0.0)) / 768.0;
	vec4 c = texture(clouds, uv);
	float d = length(v_world.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	ALBEDO = c.rgb * mix(0.25, 1.0, daylight);
	ALPHA = c.a * fade;
}
"""

var world: World
var logic: BlockLogic
var entities: EntityManager
var actions: PlayerActions
var player: Player
var hud: HUD
var touch: TouchControls
var inventory_ui: ContainerUI
var pause_menu: PauseMenu
var settings_panel: SettingsPanel
var weather: Weather
var particles: Particles
var sound: SoundSystem
var meta: Dictionary = {}
var world_dir := ""
var time_of_day := 0.08
var loading := true
var creative := true
var difficulty := 2
## Измерение: 0 — обычный мир, -1 — Нижний мир, 1 — Край.
var dimension := 0
## Дракон Края побеждён (больше не появляется).
var dragon_killed := false

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _selection: MeshInstance3D
var _crack: MeshInstance3D
var _clouds: MeshInstance3D
var _cloud_material: ShaderMaterial
var _autosave := 0.0
var _sky_time := -1.0
var _was_captured := false
var _capture_requested_at := -1.0
var _needs_spawn := false
var _legacy := false
var _daylight := 1.0
var _sleep_fade := 0.0
## Как игрок попал в это измерение: "nether_portal", "end", "end_exit", "respawn" или "".
var _arrival := ""
var _portal_time := 0.0
## После перехода игрок стоит в портале — новый переход только после выхода из него.
var _portal_wait_exit := false
var _switching := false

const NETHER_GEN_PATH := "res://scripts/world/gen/nether_gen.gd"
const END_GEN_PATH := "res://scripts/world/gen/end_gen.gd"
const PORTAL_TIME := 4.0
const NETHER_FOG := Color(0.22, 0.04, 0.03)
const END_FOG := Color(0.07, 0.05, 0.09)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world_dir = Game.current_world_dir
	meta = WorldStorage.load_meta(world_dir)
	if meta.is_empty():
		push_error("Мир не найден: %s" % world_dir)
		Game.goto_main_menu.call_deferred()
		return
	creative = bool(meta.get("creative", true))
	difficulty = int(meta.get("difficulty", 2))
	time_of_day = float(meta.get("time", 0.08))
	dimension = int(meta.get("dimension", 0))
	dragon_killed = bool(meta.get("dragon_killed", false))
	_arrival = str(meta.get("arrival", ""))
	meta.erase("arrival")
	_portal_wait_exit = _arrival == "nether_portal"
	_legacy = int(meta.get("version", 1)) < 2
	meta["version"] = 2
	_build_environment()
	TextureFactory.set_min_light(0.07 if dimension == 0 else (0.16 if dimension == -1 else 0.12))

	world = World.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.setup(int(meta.get("seed", 0)), dimension_dir(dimension), int(Game.settings["render_distance"]),
		generator_for(dimension), dimension)
	world.sync_budget_usec = 40000
	add_child(world)

	logic = BlockLogic.new()
	logic.name = "BlockLogic"
	logic.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(logic)
	logic.setup(world, self)

	player = Player.new()
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.world = world
	player.creative = creative
	player.difficulty = difficulty
	add_child(player)

	entities = EntityManager.new()
	entities.name = "Entities"
	entities.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(entities)
	entities.setup(world, logic, player, self)

	actions = PlayerActions.new(self, world, logic, entities)
	player.actions = actions

	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(world, logic, self, player)
	if meta.get("weather") is Dictionary:
		weather.from_dict(meta["weather"])
	weather.lightning_struck.connect(_on_lightning)
	particles = Particles.new()
	particles.name = "Particles"
	add_child(particles)
	particles.setup(world, player.camera)
	sound = SoundSystem.new()
	sound.name = "Sound"
	sound.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sound)
	player.block_broken.connect(func(pos: Vector3i, id: int, m: int) -> void:
		particles.block_break(pos, id, m)
		sound.play_block("break", id, Vector3(pos) + Vector3(0.5, 0.5, 0.5)))
	player.damaged.connect(func(_a: int) -> void: sound.play_ui("hurt", 0.8))

	if meta.get("player") is Dictionary:
		player.from_dict(meta["player"], _legacy)
	else:
		var col: Vector2i = world.generator.call("find_spawn_column")
		var h: int = world.generator.call("get_height", col.x, col.y)
		player.position = Vector3(col.x + 0.5, h + 1.001, col.y + 0.5)
		player.spawn_point = player.position
		_needs_spawn = true
		if creative:
			player.inventory.fill_creative_hotbar()

	_selection = MeshInstance3D.new()
	_selection.mesh = TextureFactory.selection_mesh()
	_selection.material_override = TextureFactory.selection_material
	_selection.visible = false
	add_child(_selection)
	_crack = MeshInstance3D.new()
	_crack.mesh = TextureFactory.item_mesh(Blocks.STONE)
	_crack.material_override = TextureFactory.crack_material
	_crack.scale = Vector3.ONE * 1.006
	_crack.visible = false
	add_child(_crack)
	_build_clouds()

	_build_ui()
	_restore_legacy_drops()
	player.died.connect(_on_player_died)
	player.flying_changed.connect(func(on: bool) -> void:
		hud.show_toast("Полёт включён" if on else "Полёт выключен", 1.2))
	Game.settings_changed.connect(_apply_settings)
	_apply_settings()
	_update_sky()
	hud.show_loading(true)
	_update_loading_text()


# --- Окружение -------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_SKY
	_sky = ProceduralSkyMaterial.new()
	_sky.sun_angle_max = 12.0
	_sky.sun_curve = 0.05
	var sky := Sky.new()
	sky.sky_material = _sky
	# Отражения и фоновое освещение от неба не используются — минимальная карта излучения.
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = false
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	add_child(_sun)


func _build_clouds() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = int(meta.get("seed", 0))
	noise.frequency = 0.09
	for y in 64:
		for x in 64:
			# Все координаты шума — функции cos/sin углов, поэтому текстура бесшовно повторяется.
			var a := TAU * x / 64.0
			var b := TAU * y / 64.0
			var v := noise.get_noise_3d(cos(a) * 6.0, sin(a) * 6.0 + cos(b) * 6.0, sin(b) * 6.0)
			if v > 0.1:
				img.set_pixel(x, y, Color(1, 1, 1, 0.82))
	var tex := ImageTexture.create_from_image(img)
	var sh := Shader.new()
	sh.code = CLOUD_SHADER
	_cloud_material = ShaderMaterial.new()
	_cloud_material.shader = sh
	_cloud_material.set_shader_parameter("clouds", tex)
	var plane := PlaneMesh.new()
	plane.size = Vector2(640, 640)
	_clouds = MeshInstance3D.new()
	_clouds.mesh = plane
	_clouds.material_override = _cloud_material
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_clouds)


## Освещённость дня 0..1 (ночью около 0.3).
func _day_factor() -> float:
	var s := sin(time_of_day * TAU)
	return clampf(s * 2.5 + 0.35, 0.0, 1.0)


## Уровень небесного света сейчас (0–15): ночью около 4, как в оригинале; дождь и гроза темнее.
func sky_light_level() -> int:
	var l := lerpf(4.0, 15.0, _day_factor())
	if weather != null:
		l -= weather.rain * 3.0 + weather.thunder * 5.0
	return clampi(int(round(l)), 4, 15)


func is_night() -> bool:
	return sky_light_level() < 8


func focus_position() -> Vector3:
	return player.position if player != null else Vector3.ZERO


func _update_sky() -> void:
	var a := time_of_day * TAU
	var s := sin(a)
	var day := _day_factor()
	var dusk := clampf(1.0 - absf(s) * 3.5, 0.0, 1.0) * clampf(day * 2.0, 0.0, 1.0)
	var gloom := weather.darkness() if weather != null else 0.0
	var top := NIGHT_TOP.lerp(DAY_TOP, day)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK_HORIZON, dusk * 0.45)
	# Пасмурное небо: серое и темнее.
	var grey := Color(0.45, 0.47, 0.5) * lerpf(0.25, 1.0, day)
	top = top.lerp(grey * 0.85, minf(gloom * 1.6, 0.9))
	horizon = horizon.lerp(grey, minf(gloom * 1.6, 0.9))
	if weather != null and weather.flash() > 0.0:
		top = top.lerp(Color(0.85, 0.88, 1.0), weather.flash() * 0.6)
		horizon = horizon.lerp(Color(0.85, 0.88, 1.0), weather.flash() * 0.6)
	# Небо и солнце перерисовываются не каждый кадр, а при заметном сдвиге времени (~раз в секунду):
	# изменение материала неба заставляет движок заново рендерить небо, что дорого на телефонах.
	if absf(time_of_day - _sky_time) > 0.0008 or gloom > 0.0 or (weather != null and weather.flash() > 0.0):
		_sky_time = time_of_day
		_sky.sky_top_color = top
		_sky.sky_horizon_color = horizon
		# Нижняя полусфера неба совпадает с цветом тумана — край прорисовки не виден.
		_sky.ground_horizon_color = horizon
		_sky.ground_bottom_color = horizon
		var sun_dir := Vector3(cos(a), s, 0.3).normalized()
		_sun.basis = Basis.looking_at(-sun_dir, Vector3.BACK)
		_sun.light_energy = clampf(s * 4.0, 0.0, 1.0)
	_daylight = lerpf(0.22, 1.0, day) * (1.0 - gloom * 0.6)
	if weather != null:
		_daylight = minf(_daylight + weather.flash() * 0.5, 1.0)
	var daylight := _daylight * (1.0 - _sleep_fade * 0.9)
	var rd := float(world.render_distance * WorldGen.CHUNK_SIZE)
	if dimension != 0 and not player.head_in_water and not player.in_lava:
		# Нижний мир и Край: без неба, смены дня и облаков; густой цветной туман.
		var fog := NETHER_FOG if dimension == -1 else END_FOG
		TextureFactory.set_environment(fog, rd * (0.25 if dimension == -1 else 0.5), rd - 6.0, 1.0 if dimension == -1 else 0.55)
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = fog
		_clouds.visible = false
		player.camera.far = rd + 32.0
		return
	if player.head_in_water or player.in_lava:
		var fog := WATER_FOG * daylight if player.head_in_water else LAVA_FOG
		TextureFactory.set_environment(fog, 0.5 if player.in_lava else 1.0, 3.0 if player.in_lava else 18.0, daylight)
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = fog
	else:
		TextureFactory.set_environment(horizon * (1.0 - _sleep_fade), rd * 0.7, rd - 6.0, daylight)
		_env.background_mode = Environment.BG_SKY
	_clouds.visible = not player.head_in_water and dimension == 0
	player.camera.far = rd + 96.0
	_cloud_material.set_shader_parameter("daylight", daylight)
	_cloud_material.set_shader_parameter("fade_start", rd * 0.6)
	_cloud_material.set_shader_parameter("fade_end", rd + 48.0)
	_clouds.position = Vector3(snappedf(player.position.x, 16.0), CLOUD_HEIGHT, snappedf(player.position.z, 16.0))


# --- Интерфейс -------------------------------------------------------------

func _build_ui() -> void:
	hud = HUD.new()
	add_child(hud)
	hud.setup(player, creative)
	hud.respawn_requested.connect(_respawn)
	hud.menu_requested.connect(quit_to_menu)

	touch = TouchControls.new()
	touch.player = player
	touch.hotbar = hud.hotbar
	touch.visible = false
	hud.root.add_child(touch)
	touch.pause_requested.connect(open_pause)
	touch.inventory_requested.connect(open_inventory)
	# Кнопка «поставить» показывает выбранный блок, кнопка «ПОЛЁТ» — режим: перерисовываем при изменениях.
	player.inventory.changed.connect(touch.queue_redraw)
	player.flying_changed.connect(func(_on: bool) -> void: touch.queue_redraw())

	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var menus := Control.new()
	menus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menus.theme = Game.ui_theme
	layer.add_child(menus)
	inventory_ui = ContainerUI.new()
	menus.add_child(inventory_ui)
	inventory_ui.setup(player, world, logic)
	inventory_ui.closed.connect(_ui_state_changed)
	inventory_ui.overflow.connect(func(id: int, count: int, data: int) -> void:
		spawn_drop(id, count, data, player.position + Vector3(0, 1.2, 0), Vector3.ZERO, 1.5))
	pause_menu = PauseMenu.new()
	menus.add_child(pause_menu)
	pause_menu.set_info(str(meta.get("name", "")), int(meta.get("seed", 0)), creative)
	pause_menu.resume_requested.connect(resume)
	pause_menu.mode_toggle_requested.connect(func() -> void: set_creative(not creative))
	pause_menu.settings_requested.connect(func() -> void:
		pause_menu.visible = false
		settings_panel.open())
	pause_menu.quit_requested.connect(quit_to_menu)
	settings_panel = SettingsPanel.new()
	menus.add_child(settings_panel)
	settings_panel.closed.connect(func() -> void:
		if get_tree().paused:
			pause_menu.visible = true
		_ui_state_changed())


func _apply_settings() -> void:
	var s := Game.settings
	var touch_on := Game.is_touch_enabled()
	world.set_render_distance(int(s["render_distance"]))
	player.base_fov = float(s["fov"])
	player.mouse_sensitivity = float(s["mouse_sensitivity"])
	player.auto_jump = bool(s["auto_jump"]) and touch_on
	touch.sensitivity = float(s["touch_sensitivity"])
	var margins := Game.safe_margins()
	touch.set_margins(margins)
	hud.set_touch_mode(touch_on, margins)
	hud.show_debug = bool(s["show_fps"])
	if sound != null:
		sound.volume = float(s.get("sound_volume", 0.8))
		sound.music_volume = float(s.get("music_volume", 0.5))
	_ui_state_changed()


func gameplay_active() -> bool:
	return not loading and not player.dead and not inventory_ui.visible \
		and not pause_menu.visible and not settings_panel.visible and not player.sleeping


func _ui_state_changed() -> void:
	var active := gameplay_active()
	player.controls_enabled = active
	if not active:
		player.release_all_input()
	touch.visible = active and Game.is_touch_enabled()
	hud.set_gameplay_visible(active)
	_update_mouse_mode()


func _update_mouse_mode() -> void:
	var capture := gameplay_active() and not Game.is_touch_enabled() and not Game.test_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


## В браузере Esc снимает захват мыши, а сама клавиша до игры не доходит:
## потерю захвата во время игры считаем нажатием Esc и открываем паузу.
## Если браузер так и не дал захватить мышь — включаем обзор без захвата.
func _check_browser_pointer_lock() -> void:
	if not OS.has_feature("web") or Game.is_touch_enabled():
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _was_captured and not captured and gameplay_active():
		_was_captured = false
		open_pause()
		return
	_was_captured = captured
	if captured:
		player.free_look = false
		_capture_requested_at = -1.0
	elif _capture_requested_at > 0.0 and Time.get_ticks_msec() / 1000.0 - _capture_requested_at > 0.8:
		_capture_requested_at = -1.0
		if not player.free_look:
			player.free_look = true
			hud.show_toast("Браузер не дал захватить мышь — обзор движением курсора", 4.0)


func open_inventory() -> void:
	if not gameplay_active():
		return
	inventory_ui.open("inventory", Vector3i.ZERO, creative)
	_ui_state_changed()


## Окно блока-контейнера (верстак, печь, сундук, раздатчик, варочная стойка).
func open_container(kind: String, pos: Vector3i) -> void:
	if not gameplay_active():
		return
	if kind == "enchanting":
		hud.show_toast("Стол зачарований: зачарование появится в следующей версии", 2.5)
		return
	inventory_ui.open(kind, pos, false)
	_ui_state_changed()


func open_pause() -> void:
	if loading or pause_menu.visible:
		return
	if inventory_ui.visible:
		inventory_ui.close_ui()
	pause_menu.set_info(str(meta.get("name", "")), int(meta.get("seed", 0)), creative)
	pause_menu.visible = true
	get_tree().paused = true
	_ui_state_changed()
	save_game(true)


func resume() -> void:
	pause_menu.visible = false
	settings_panel.visible = false
	get_tree().paused = false
	_ui_state_changed()


func set_creative(value: bool) -> void:
	creative = value
	player.creative = value
	if not value:
		player.set_flying(false)
	elif player.inventory.is_empty():
		player.inventory.fill_creative_hotbar()
	player.heal(Player.MAX_HEALTH)
	meta["creative"] = value
	hud.set_creative(value)
	touch.queue_redraw()
	pause_menu.set_info(str(meta.get("name", "")), int(meta.get("seed", 0)), value)
	hud.show_toast("Режим игры: %s" % ("Креатив" if value else "Выживание"))


func show_toast(text: String, duration := 2.5) -> void:
	hud.show_toast(text, duration)


func show_item_info(id: int) -> void:
	match id:
		Items.COMPASS:
			var d := Vector2(player.spawn_point.x - player.position.x, player.spawn_point.z - player.position.z)
			hud.show_toast("Компас: точка появления в %d блоках" % roundi(d.length()), 3.0)
		Items.CLOCK:
			var hours := int(fposmod(time_of_day * 24.0 + 6.0, 24.0))
			hud.show_toast("Часы: %s (%02d:00)" % ["день" if not is_night() else "ночь", hours], 3.0)
		Items.MAP:
			hud.show_toast("Карта: X %d, Z %d" % [floori(player.position.x), floori(player.position.z)], 3.0)


func play_note(p: Vector3i, note: int) -> void:
	sound.play_note(Vector3(p) + Vector3(0.5, 0.5, 0.5), note, world.get_block_v(p + Vector3i(0, -1, 0)))
	var hue := note / 24.0
	particles.colored(Vector3(p) + Vector3(0.5, 1.2, 0.5), Color.from_hsv(hue, 0.9, 1.0), 1, 0.05, 0.4)


## Пластинка: id предмета или 0 — тишина.
func play_record(record_id: int, p: Vector3i) -> void:
	sound.play_record(record_id, Vector3(p) + Vector3(0.5, 0.5, 0.5))


## Звук в мире (для логики блоков, существ и т. п.).
func play_sound(sound_name: String, pos: Vector3, vol := 1.0, pitch := 1.0) -> void:
	sound.play(sound_name, pos, vol, pitch)


## Визуальный эффект: hearts, smoke, angry, portal, crit, magic_crit, explosion (data — мощность ×10),
## splash, flame, potion (data — цвет RGB).
func effect(kind: String, pos: Vector3, data := 0) -> void:
	match kind:
		"hearts":
			particles.colored(pos, Color(1.0, 0.3, 0.4), 6, 0.4, 0.6)
		"smoke":
			particles.smoke(pos, 8)
		"angry":
			particles.colored(pos, Color(0.35, 0.05, 0.05), 4, 0.3, 0.5)
		"portal":
			for i in 8:
				particles.portal(pos)
		"crit":
			particles.crit(pos)
		"magic_crit":
			particles.crit(pos, true)
		"explosion":
			particles.explosion(pos, data / 10.0)
		"splash":
			particles.splash(pos)
		"flame":
			particles.flame(pos)
		"potion":
			particles.colored(pos, Color.hex(data << 8 | 0xFF), 10, 0.5, 0.6)


## Звуки событий блоков (вызывается действиями игрока и логикой).
func on_block_placed(p: Vector3i, id: int) -> void:
	sound.play_block("place", id, Vector3(p) + Vector3(0.5, 0.5, 0.5))


func edit_sign(_p: Vector3i) -> void:
	pass


func check_end_portal(p: Vector3i) -> void:
	if Portals.check_end_portal(world, p):
		hud.show_toast("Портал в Край открыт", 2.5)


func use_fishing_rod() -> void:
	hud.show_toast("Рыбалка: закиньте удочку в воду", 1.5)


func on_item_picked(_id: int, _count: int) -> void:
	sound.play_ui("pop", 0.35, randf_range(0.8, 1.6))


func on_item_crafted(_id: int) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if loading or player == null:
		return
	if event.is_action_pressed("pause"):
		if settings_panel.visible:
			settings_panel.close_panel()
		elif inventory_ui.visible:
			inventory_ui.close_ui()
		elif pause_menu.visible:
			resume()
		elif player.sleeping:
			_wake_up()
		elif not player.dead:
			open_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		if inventory_ui.visible:
			inventory_ui.close_ui()
		else:
			open_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_debug"):
		hud.toggle_debug()
	elif event.is_action_pressed("toggle_mode") and gameplay_active():
		set_creative(not creative)
	elif event.is_action_pressed("drop_item") and gameplay_active():
		_drop_selected()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Клик по окну возвращает захват мыши (например, после Alt+Tab).
		if mb.pressed and mb.device != InputEvent.DEVICE_ID_EMULATION and gameplay_active() \
				and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_update_mouse_mode()
			_capture_requested_at = Time.get_ticks_msec() / 1000.0


func _notification(what: int) -> void:
	if world == null or loading:
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			save_game(true)
			if not Game.test_mode and gameplay_active():
				open_pause()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if settings_panel.visible:
				settings_panel.close_panel()
			elif inventory_ui.visible:
				inventory_ui.close_ui()
			elif pause_menu.visible:
				resume()
			else:
				open_pause()


# --- Кадр ------------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null:
		return
	var paused := get_tree().paused
	if not paused:
		world.update_streaming(player.position)
	if loading:
		_update_loading()
		return
	if paused:
		return
	time_of_day = fposmod(time_of_day + delta / DAY_LENGTH, 1.0)
	_update_portals(delta)
	_update_sleep(delta)
	_check_browser_pointer_lock()
	weather.update(delta, player.camera.global_position)
	_update_sky()
	_update_selection()
	entities.update(delta)
	particles.update(delta, _daylight)
	_update_sounds(delta)
	hud.set_underwater(player.head_in_water)
	_autosave += delta
	if _autosave >= AUTOSAVE_INTERVAL:
		_autosave = 0.0
		save_game(false)


func _update_loading_text() -> void:
	var r := world.render_distance
	var total := (2 * r + 1) * (2 * r + 1)
	var title := "Генерация ландшафта…"
	match _arrival:
		"nether_portal":
			title = "Вход в Нижний мир…" if dimension == -1 else "Выход из Нижнего мира…"
		"end":
			title = "Вход в Край…"
		"end_exit", "respawn":
			title = "Возвращение в обычный мир…"
	hud.set_loading_text("%s %d%%" % [title, mini(99, roundi(100.0 * world.loaded_count() / total))])


func _update_loading() -> void:
	_update_loading_text()
	# Для поиска портала рядом нужна область пошире.
	if not world.is_area_ready(player.position, 2 if _arrival == "nether_portal" else 1):
		return
	if _needs_spawn:
		_find_safe_spawn()
		_needs_spawn = false
	else:
		_place_on_arrival()
	loading = false
	world.sync_budget_usec = World.SYNC_BUDGET_USEC
	player.frozen = false
	hud.show_loading(false)
	_ui_state_changed()
	save_game(true)


## Новая точка появления: ближайшая колонка с землёй/травой и свободным местом над ней.
func _find_safe_spawn() -> void:
	var base := Vector2i(floori(player.position.x), floori(player.position.z))
	var ground := [Blocks.GRASS, Blocks.DIRT, Blocks.SAND, Blocks.SNOW, Blocks.STONE, Blocks.GRAVEL, Blocks.MYCELIUM]
	for r in range(0, 16):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var x := base.x + dx
				var z := base.y + dz
				var y := world.top_solid_y(x, z)
				if y < 0 or not ground.has(world.get_block(x, y, z)):
					continue
				if world.get_block(x, y + 1, z) != Blocks.AIR or world.get_block(x, y + 2, z) != Blocks.AIR:
					continue
				player.position = Vector3(x + 0.5, y + 1.001, z + 0.5)
				player.spawn_point = player.position
				return
	player.position.y = world.top_solid_y(base.x, base.y) + 1.001
	player.spawn_point = player.position


## Куда поставить игрока после перехода между измерениями.
func _place_on_arrival() -> void:
	match _arrival:
		"nether_portal":
			var found := Portals.find_portal(world, player.position, 32)
			if found.y < 0:
				found = Portals.build_portal(world, player.position)
				hud.show_toast("Построен обратный портал", 2.0)
			player.position = Vector3(found) + Vector3(0.5, 0.001, 0.5)
		"end":
			Portals.make_end_platform(world)
			player.position = Vector3(Portals.END_SPAWN) + Vector3(0.5, 0.001, 0.5)
		_:
			_unstuck_player()
	_arrival = ""
	player.velocity = Vector3.ZERO


func _unstuck_player() -> void:
	if BodyPhysics.collides(world, player.position, Player.HALF_WIDTH, Player.HEIGHT):
		player.position.y = world.top_solid_y(floori(player.position.x), floori(player.position.z)) + 1.001


func _update_selection() -> void:
	var t := player.target
	_selection.visible = not t.is_empty()
	if _selection.visible:
		var p: Vector3i = t["pos"]
		var boxes := world.block_boxes(p, false)
		var box := AABB(Vector3(p), Vector3.ONE)
		if not boxes.is_empty():
			box = boxes[0]
			for b in boxes:
				box = box.merge(b)
		_selection.position = box.get_center()
		_selection.scale = box.size.max(Vector3(0.05, 0.05, 0.05))
	_crack.visible = player.break_progress > 0.0 and not player.creative
	if _crack.visible:
		_crack.position = Vector3(player.break_pos) + Vector3(0.5, 0.5, 0.5)
		var stage := clampi(int(player.break_progress * Blocks.CRACK_STAGES), 0, Blocks.CRACK_STAGES - 1)
		TextureFactory.crack_material.set_shader_parameter("layer", float(Tex.CRACK_0 + stage))


# --- Предметы --------------------------------------------------------------

func spawn_drop(id: int, count: int, data: int, pos: Vector3, vel := Vector3.INF, pickup_delay := 0.0) -> ItemDrop:
	return entities.spawn_drop(id, count, data, pos, vel, pickup_delay)


func _drop_selected() -> void:
	var id := player.inventory.selected_id()
	if id == 0:
		return
	var data := player.inventory.selected_data()
	if not creative:
		player.inventory.consume_selected(1)
	var dir := player.look_dir()
	spawn_drop(id, 1, data, player.eye_position() + dir * 0.4 - Vector3(0, 0.35, 0), dir * 5.0 + Vector3(0, 1.5, 0), 1.5)


## Предметы, сохранённые в meta.json старой версией (до хранения в чанках).
func _restore_legacy_drops() -> void:
	var list: Variant = meta.get("drops", [])
	meta.erase("drops")
	if not list is Array:
		return
	for item: Variant in list:
		if not item is Dictionary:
			continue
		var p: Array = item.get("pos", [0, 0, 0])
		var id := int(item.get("id", 0))
		if _legacy:
			id = Inventory.V1_IDS[id] if id >= 0 and id < Inventory.V1_IDS.size() else 0
		if not Items.exists(id) or p.size() != 3:
			continue
		spawn_drop(id, int(item.get("count", 1)), 0, Vector3(float(p[0]), float(p[1]), float(p[2])), Vector3.ZERO)


func explosion_damage(center: Vector3, power: float, source: Node) -> void:
	entities.explosion_damage(center, power, source)
	particles.explosion(center, power)
	sound.play("explode", center, 1.0 + power * 0.1, 0.9)


# --- Сон -------------------------------------------------------------------

func try_sleep(p: Vector3i) -> void:
	if world.dimension != 0:
		logic.explode(Vector3(p) + Vector3(0.5, 0.5, 0.5), 5.0, true)
		return
	if not is_night():
		player.spawn_point = Vector3(p) + Vector3(0.5, 0.6, 0.5)
		hud.show_toast("Спать можно только ночью. Точка появления установлена.", 2.5)
		return
	if entities.mobs != null and bool(entities.mobs.call("monsters_near", player.position, 8.0)):
		hud.show_toast("Нельзя спать: рядом монстры", 2.5)
		return
	player.spawn_point = Vector3(p) + Vector3(0.5, 0.6, 0.5)
	player.sleeping = true
	player.velocity = Vector3.ZERO
	player.position = Vector3(p) + Vector3(0.5, 0.6, 0.5)
	_sleep_fade = 0.0
	hud.show_toast("Сон…", 2.0)
	_ui_state_changed()


func _update_sleep(delta: float) -> void:
	if not player.sleeping:
		_sleep_fade = maxf(_sleep_fade - delta, 0.0)
		return
	_sleep_fade = minf(_sleep_fade + delta / 2.5, 1.0)
	if _sleep_fade >= 1.0:
		time_of_day = 0.0
		_wake_up()
		hud.show_toast("Доброе утро!", 2.0)


func _wake_up() -> void:
	player.sleeping = false
	player.position.y += 0.6
	_unstuck_player()
	_ui_state_changed()


# --- Смерть и возрождение --------------------------------------------------

func _on_player_died() -> void:
	# Всё содержимое инвентаря и часть опыта выпадают на месте гибели.
	var inv := player.inventory
	for i in Inventory.TOTAL:
		if inv.counts[i] > 0:
			var vel := Vector3(randf_range(-2.0, 2.0), randf_range(2.0, 4.0), randf_range(-2.0, 2.0))
			spawn_drop(inv.ids[i], inv.counts[i], inv.datas[i], player.position + Vector3(0, 1.0, 0), vel, 1.0)
	inv.clear()
	entities.spawn_xp(player.position + Vector3(0, 0.5, 0), mini(player.xp_level * 7, 100))
	if inventory_ui.visible:
		inventory_ui.close_ui()
	hud.show_death(true)
	_ui_state_changed()
	save_game(true)


func _respawn() -> void:
	if dimension != 0:
		# Возрождение — всегда в обычном мире.
		player.respawn()
		change_dimension(0, player.spawn_point, "respawn")
		return
	player.respawn()
	_unstuck_player()
	hud.show_death(false)
	_ui_state_changed()


# --- Сохранение ------------------------------------------------------------

## full — вместе с существами и предметами на земле (при паузе и выходе).
func save_game(full := true) -> void:
	if world == null or player == null or _needs_spawn:
		return
	var pd := player.to_dict()
	if player.dead:
		var sp := player.spawn_point
		pd["pos"] = [sp.x, sp.y, sp.z]
		pd["health"] = Player.MAX_HEALTH
	meta["player"] = pd
	meta["time"] = time_of_day
	meta["creative"] = creative
	meta["difficulty"] = difficulty
	meta["dimension"] = dimension
	meta["dragon_killed"] = dragon_killed
	if dimension == 0:
		meta["weather"] = weather.to_dict()
	meta["last_played"] = Time.get_unix_time_from_system()
	WorldStorage.save_meta(world_dir, meta)
	if full:
		entities.save_into_chunks()
	var n := world.save_dirty_chunks()
	if full:
		entities.clear_saved_lists()
	if n > 0:
		hud.flash_saved()


# --- Звуки и частицы -----------------------------------------------------------

var _step_acc := 0.0
var _dig_acc := 0.0
var _eat_acc := 0.0
var _last_pos := Vector3.ZERO
var _was_in_water := false
var _last_level := 0


func _update_sounds(delta: float) -> void:
	sound.listener_pos = player.camera.global_position
	sound.update_music(delta)
	# Шаги — по блоку под ногами.
	var moved := Vector2(player.position.x - _last_pos.x, player.position.z - _last_pos.z).length()
	_last_pos = player.position
	if player.on_ground and not player.flying and moved < 1.0:
		_step_acc += moved
		if _step_acc > 1.7:
			_step_acc = 0.0
			var below := Vector3i(floori(player.position.x), floori(player.position.y - 0.2), floori(player.position.z))
			sound.play_block("step", world.get_block_v(below), player.position)
	# Звук и осколки при добыче.
	if player.break_progress > 0.0 and not player.target.is_empty():
		_dig_acc += delta
		if _dig_acc > 0.22:
			_dig_acc = 0.0
			var bp := player.break_pos
			var id := world.get_block_v(bp)
			sound.play_block("dig", id, Vector3(bp) + Vector3(0.5, 0.5, 0.5))
			particles.block_hit(bp, id, world.get_meta_v(bp), player.target.get("normal", Vector3i.UP))
	# Еда и питьё.
	if player.eat_progress > 0.0:
		_eat_acc += delta
		if _eat_acc > 0.25:
			_eat_acc = 0.0
			var item := player.inventory.selected_id()
			var drink := item == Items.POTION or item == Items.MILK_BUCKET
			sound.play(("drink" if drink else "eat"), player.position + Vector3(0, 1.5, 0), 0.6)
			if not drink:
				var tile := Items.sprite_tile(item, player.inventory.selected_data())
				particles.crumbs(player.eye_position() + player.look_dir() * 0.45 - Vector3(0, 0.25, 0), tile)
	# Всплеск при падении в воду.
	if player.in_water and not _was_in_water and player.velocity.y < -3.0:
		sound.play("splash", player.position, 0.7)
		particles.splash(player.position + Vector3(0, 0.3, 0))
	_was_in_water = player.in_water
	# Новый уровень опыта (каждые 5 уровней — фанфары, как в оригинале).
	if player.xp_level > _last_level:
		sound.play_ui("levelup" if player.xp_level % 5 == 0 else "orb", 0.6)
	elif player.xp_level == _last_level and player.xp_progress > 0.0 and _xp_seen != player.xp_total:
		sound.play_ui("orb", 0.3, randf_range(0.8, 1.3))
	_xp_seen = player.xp_total
	_last_level = player.xp_level
	# Дождь (тише под крышей).
	var rain_vol := 0.0
	if weather.rain > 0.05 and dimension == 0:
		rain_vol = weather.rain * (0.7 if weather.is_precipitating_at(player.position) else 0.25)
	sound.set_loop("rain", rain_vol)


var _xp_seen := 0


func _on_lightning(pos: Vector3) -> void:
	var d := pos.distance_to(player.position)
	sound.play_ui("thunder", clampf(1.4 - d / 80.0, 0.3, 1.2), randf_range(0.8, 1.1))
	particles.smoke(pos, 6, true)


# --- Измерения ---------------------------------------------------------------

static func generator_for(dim: int) -> Script:
	var path := NETHER_GEN_PATH if dim == -1 else (END_GEN_PATH if dim == 1 else "")
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path)
	return null


## Папка чанков измерения (как в оригинале: DIM-1 — Нижний мир, DIM1 — Край).
func dimension_dir(dim: int) -> String:
	if dim == 0:
		return world_dir
	return world_dir.path_join("DIM%d" % dim)


## Порталы: стоя в портале в Нижний мир 4 секунды (в креативе — секунду), игрок переходит
## в другое измерение; портал Края переносит сразу.
func _update_portals(delta: float) -> void:
	if _switching or player.dead:
		return
	var feet := Vector3i(floori(player.position.x), floori(player.position.y + 0.1), floori(player.position.z))
	var head := feet + Vector3i(0, 1, 0)
	var fid := world.get_block_v(feet)
	if fid == Blocks.END_PORTAL:
		if dimension == 1:
			change_dimension(0, player.spawn_point, "end_exit")
		else:
			change_dimension(1, Vector3(Portals.END_SPAWN) + Vector3(0.5, 0.0, 0.5), "end")
		return
	var in_portal := fid == Blocks.PORTAL or world.get_block_v(head) == Blocks.PORTAL
	sound.set_loop("portal_hum", 0.5 if in_portal else 0.0)
	if not in_portal:
		_portal_wait_exit = false
		_portal_time = maxf(_portal_time - delta * 2.0, 0.0)
		hud.set_portal_effect(_portal_time / PORTAL_TIME)
		return
	if _portal_wait_exit or dimension == 1:
		return
	_portal_time += delta
	var need := 1.0 if creative else PORTAL_TIME
	hud.set_portal_effect(_portal_time / need)
	if _portal_time >= need:
		var pos := player.position
		if dimension == 0:
			change_dimension(-1, Vector3(pos.x / 8.0, clampf(pos.y, 34.0, 110.0), pos.z / 8.0), "nether_portal")
		else:
			change_dimension(0, Vector3(pos.x * 8.0, pos.y, pos.z * 8.0), "nether_portal")


## Переход в другое измерение: сохранение и перезагрузка игровой сцены с другим миром.
func change_dimension(to: int, pos: Vector3, arrival: String) -> void:
	if _switching:
		return
	_switching = true
	sound.stop_all()
	sound.play_ui("portal_travel", 0.6)
	if inventory_ui.visible:
		inventory_ui.close_ui()
	save_game(true)
	var pd := player.to_dict()
	pd["pos"] = [pos.x, pos.y, pos.z]
	meta["player"] = pd
	meta["dimension"] = to
	meta["arrival"] = arrival
	WorldStorage.save_meta(world_dir, meta)
	world.wait_for_jobs()
	Game.start_world(Game.current_world_id)


func quit_to_menu() -> void:
	if inventory_ui.visible:
		inventory_ui.close_ui()
	save_game(true)
	world.wait_for_jobs()
	Game.goto_main_menu()
