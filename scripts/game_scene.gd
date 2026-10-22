extends Node3D
## Игровая сцена: связывает мир, игрока и интерфейс; смена дня и ночи, выпавшие предметы,
## автосохранение (каждые 15 секунд, при паузе, сворачивании и выходе).

const DAY_LENGTH := 1200.0
const AUTOSAVE_INTERVAL := 15.0
const PICKUP_RADIUS := 2.2
const CLOUD_HEIGHT := 110.0

const DAY_TOP := Color(0.32, 0.55, 0.96)
const DAY_HORIZON := Color(0.68, 0.82, 1.0)
const NIGHT_TOP := Color(0.01, 0.015, 0.05)
const NIGHT_HORIZON := Color(0.05, 0.06, 0.12)
const DUSK_HORIZON := Color(0.98, 0.58, 0.32)
const WATER_FOG := Color(0.08, 0.2, 0.48)

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
var player: Player
var hud: HUD
var touch: TouchControls
var inventory_ui: InventoryUI
var pause_menu: PauseMenu
var settings_panel: SettingsPanel
var meta: Dictionary = {}
var world_dir := ""
var time_of_day := 0.08
var loading := true
var creative := true

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _drops: Node3D
var _selection: MeshInstance3D
var _crack: MeshInstance3D
var _clouds: MeshInstance3D
var _cloud_material: ShaderMaterial
var _autosave := 0.0
var _sky_time := -1.0
var _needs_spawn := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world_dir = Game.current_world_dir
	meta = WorldStorage.load_meta(world_dir)
	if meta.is_empty():
		push_error("Мир не найден: %s" % world_dir)
		Game.goto_main_menu.call_deferred()
		return
	creative = bool(meta.get("creative", true))
	time_of_day = float(meta.get("time", 0.08))
	_build_environment()

	world = World.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.setup(int(meta.get("seed", 0)), world_dir, int(Game.settings["render_distance"]))
	add_child(world)

	_drops = Node3D.new()
	_drops.name = "Drops"
	_drops.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_drops)

	player = Player.new()
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.world = world
	player.creative = creative
	add_child(player)
	if meta.get("player") is Dictionary:
		player.from_dict(meta["player"])
	else:
		var col := world.generator.find_spawn_column()
		var h := world.generator.get_height(col.x, col.y)
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
	_crack.mesh = TextureFactory.block_mesh(Blocks.STONE)
	_crack.material_override = TextureFactory.crack_material
	_crack.scale = Vector3.ONE * 1.006
	_crack.visible = false
	add_child(_crack)
	_build_clouds()

	_build_ui()
	_restore_drops()
	player.block_broken.connect(_on_block_broken)
	player.died.connect(_on_player_died)
	player.flying_changed.connect(func(on: bool) -> void:
		hud.show_toast("Полёт включён" if on else "Полёт выключен", 1.2))
	Game.settings_changed.connect(_apply_settings)
	_apply_settings()
	_update_sky()
	hud.show_loading(true)


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


func _update_sky() -> void:
	var a := time_of_day * TAU
	var s := sin(a)
	var day := clampf(s * 2.5 + 0.35, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(s) * 3.5, 0.0, 1.0) * clampf(day * 2.0, 0.0, 1.0)
	var top := NIGHT_TOP.lerp(DAY_TOP, day)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK_HORIZON, dusk * 0.45)
	# Небо и солнце перерисовываются не каждый кадр, а при заметном сдвиге времени (~раз в секунду):
	# изменение материала неба заставляет движок заново рендерить небо, что дорого на телефонах.
	if absf(time_of_day - _sky_time) > 0.0008:
		_sky_time = time_of_day
		_sky.sky_top_color = top
		_sky.sky_horizon_color = horizon
		# Нижняя полусфера неба совпадает с цветом тумана — край прорисовки не виден.
		_sky.ground_horizon_color = horizon
		_sky.ground_bottom_color = horizon
		var sun_dir := Vector3(cos(a), s, 0.3).normalized()
		_sun.basis = Basis.looking_at(-sun_dir, Vector3.BACK)
		_sun.light_energy = clampf(s * 4.0, 0.0, 1.0)
	var daylight := lerpf(0.3, 1.0, day)
	var rd := float(world.render_distance * WorldGen.CHUNK_SIZE)
	var underwater := player.head_in_water
	if underwater:
		var water_fog := WATER_FOG * daylight
		TextureFactory.set_environment(water_fog, 1.0, 18.0, daylight)
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = water_fog
	else:
		TextureFactory.set_environment(horizon, rd * 0.7, rd - 6.0, daylight)
		_env.background_mode = Environment.BG_SKY
	_clouds.visible = not underwater
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
	inventory_ui = InventoryUI.new()
	menus.add_child(inventory_ui)
	inventory_ui.setup(player)
	inventory_ui.closed.connect(_ui_state_changed)
	inventory_ui.overflow.connect(func(id: int, count: int) -> void:
		spawn_drop(id, count, player.position + Vector3(0, 1.2, 0), Vector3.ZERO, 1.5))
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
	_ui_state_changed()


func gameplay_active() -> bool:
	return not loading and not player.dead and not inventory_ui.visible \
		and not pause_menu.visible and not settings_panel.visible


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


func open_inventory() -> void:
	if not gameplay_active():
		return
	inventory_ui.open(creative)
	_ui_state_changed()


func open_pause() -> void:
	if loading or pause_menu.visible:
		return
	if inventory_ui.visible:
		inventory_ui.close_inventory()
	pause_menu.set_info(str(meta.get("name", "")), int(meta.get("seed", 0)), creative)
	pause_menu.visible = true
	get_tree().paused = true
	_ui_state_changed()
	save_game()


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


func _unhandled_input(event: InputEvent) -> void:
	if loading or player == null:
		return
	if event.is_action_pressed("pause"):
		if settings_panel.visible:
			settings_panel.close_panel()
		elif inventory_ui.visible:
			inventory_ui.close_inventory()
		elif pause_menu.visible:
			resume()
		elif not player.dead:
			open_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		if inventory_ui.visible:
			inventory_ui.close_inventory()
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


func _notification(what: int) -> void:
	if world == null or loading:
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			save_game()
			if not Game.test_mode and gameplay_active():
				open_pause()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if settings_panel.visible:
				settings_panel.close_panel()
			elif inventory_ui.visible:
				inventory_ui.close_inventory()
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
	_update_sky()
	_update_selection()
	_update_drops(delta)
	hud.set_underwater(player.head_in_water)
	_autosave += delta
	if _autosave >= AUTOSAVE_INTERVAL:
		_autosave = 0.0
		save_game()


func _update_loading() -> void:
	var r := world.render_distance
	var total := (2 * r + 1) * (2 * r + 1)
	hud.set_loading_text("Генерация ландшафта… %d%%" % mini(99, roundi(100.0 * world.loaded_count() / total)))
	if not world.is_area_ready(player.position, 1):
		return
	if _needs_spawn:
		_find_safe_spawn()
		_needs_spawn = false
	else:
		_unstuck_player()
	loading = false
	player.frozen = false
	hud.show_loading(false)
	_ui_state_changed()
	save_game()


## Новая точка появления: ближайшая колонка с землёй/травой и свободным местом над ней.
func _find_safe_spawn() -> void:
	var base := Vector2i(floori(player.position.x), floori(player.position.z))
	var ground := [Blocks.GRASS, Blocks.DIRT, Blocks.SAND, Blocks.SNOW, Blocks.STONE, Blocks.GRAVEL]
	for r in range(0, 12):
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


func _unstuck_player() -> void:
	var x := floori(player.position.x)
	var z := floori(player.position.z)
	var y := floori(player.position.y)
	if Blocks.is_solid(world.get_block(x, y, z)) or Blocks.is_solid(world.get_block(x, y + 1, z)):
		player.position.y = world.top_solid_y(x, z) + 1.001


func _update_selection() -> void:
	var t := player.target
	_selection.visible = not t.is_empty()
	if _selection.visible:
		var p: Vector3i = t["pos"]
		_selection.position = Vector3(p) + Vector3(0.5, 0.5, 0.5)
	_crack.visible = player.break_progress > 0.0 and not player.creative
	if _crack.visible:
		_crack.position = Vector3(player.break_pos) + Vector3(0.5, 0.5, 0.5)
		var stage := clampi(int(player.break_progress * Blocks.CRACK_STAGES), 0, Blocks.CRACK_STAGES - 1)
		TextureFactory.crack_material.set_shader_parameter("layer", float(Blocks.T_CRACK_0 + stage))


# --- Предметы --------------------------------------------------------------

func spawn_drop(id: int, count: int, pos: Vector3, vel: Vector3, pickup_delay: float = 0.0) -> ItemDrop:
	var d := ItemDrop.new()
	d.setup(world, id, count, pos, vel)
	d.age = -pickup_delay
	_drops.add_child(d)
	return d


func _on_block_broken(pos: Vector3i, id: int) -> void:
	if creative:
		return
	var drop := Blocks.drop_of(id)
	if drop != Blocks.AIR:
		var vel := Vector3(randf_range(-1.2, 1.2), 3.5, randf_range(-1.2, 1.2))
		spawn_drop(drop, 1, Vector3(pos) + Vector3(0.5, 0.25, 0.5), vel)


func _drop_selected() -> void:
	var id := player.inventory.get_selected_block()
	if id == Blocks.AIR:
		return
	if not creative:
		player.inventory.consume_selected(1)
	var dir := -player.camera.global_transform.basis.z
	spawn_drop(id, 1, player.camera.global_position + dir * 0.4 - Vector3(0, 0.35, 0), dir * 5.0 + Vector3(0, 1.5, 0), 1.5)


func _update_drops(delta: float) -> void:
	if player.dead:
		return
	var center := player.position + Vector3(0, 0.8, 0)
	for n in _drops.get_children():
		var d := n as ItemDrop
		if d == null or d.is_queued_for_deletion() or not d.can_pickup():
			continue
		var dist := d.position.distance_to(center)
		if dist < 0.9:
			var left := player.inventory.add_item(d.item_id, d.count)
			if left == 0:
				d.queue_free()
			else:
				d.count = left
		elif dist < PICKUP_RADIUS:
			d.position = d.position.move_toward(center, delta * 7.0)
			d.velocity = Vector3.ZERO


func _restore_drops() -> void:
	var list: Variant = meta.get("drops", [])
	if not list is Array:
		return
	for item: Variant in list:
		if not item is Dictionary:
			continue
		var p: Array = item.get("pos", [0, 0, 0])
		var id := int(item.get("id", 0))
		if id <= Blocks.AIR or id >= Blocks.COUNT or p.size() != 3:
			continue
		spawn_drop(id, int(item.get("count", 1)), Vector3(float(p[0]), float(p[1]), float(p[2])), Vector3.ZERO)


# --- Смерть и возрождение --------------------------------------------------

func _on_player_died() -> void:
	# Всё содержимое инвентаря выпадает на месте гибели.
	var inv := player.inventory
	for i in Inventory.SIZE:
		if inv.counts[i] > 0:
			var vel := Vector3(randf_range(-2.0, 2.0), randf_range(2.0, 4.0), randf_range(-2.0, 2.0))
			spawn_drop(inv.ids[i], inv.counts[i], player.position + Vector3(0, 1.0, 0), vel, 1.0)
	inv.clear()
	hud.show_death(true)
	_ui_state_changed()
	save_game()


func _respawn() -> void:
	player.respawn()
	_unstuck_player()
	hud.show_death(false)
	_ui_state_changed()


# --- Сохранение ------------------------------------------------------------

func save_game() -> void:
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
	meta["last_played"] = Time.get_unix_time_from_system()
	var drops := []
	for n in _drops.get_children():
		var d := n as ItemDrop
		if d != null and not d.is_queued_for_deletion():
			drops.append(d.to_dict())
	meta["drops"] = drops
	WorldStorage.save_meta(world_dir, meta)
	if world.save_dirty_chunks() > 0:
		hud.flash_saved()


func quit_to_menu() -> void:
	save_game()
	world.wait_for_jobs()
	Game.goto_main_menu()
