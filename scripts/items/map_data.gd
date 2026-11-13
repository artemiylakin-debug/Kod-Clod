class_name MapData
extends RefCounted
## Карта 1.2: картинка 128×128, один пиксель — квадрат 8×8 блоков (1024×1024 блоков вокруг центра).
## Рисуется постепенно, пока игрок держит карту в руке: цвет — по верхнему блоку колонки,
## оттенок — по перепаду высот (северные склоны темнее, как в оригинале).

const SIZE := 128
const SCALE := 8
## Сколько пикселей пересчитывать за кадр.
const PIXELS_PER_FRAME := 48
## Радиус обзора карты вокруг игрока (в пикселях).
const VIEW := 16

var id := 0
var center := Vector2i.ZERO
var image: Image
var texture: ImageTexture
var dirty := false
var _cursor := 0


static func create(p_id: int, at: Vector3) -> MapData:
	var m := MapData.new()
	m.id = p_id
	# Центр привязан к сетке карт (как в оригинале), чтобы соседние карты стыковались.
	var span := SIZE * SCALE
	m.center = Vector2i(floori((at.x + span / 2.0) / span) * span, floori((at.z + span / 2.0) / span) * span)
	m.image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	m.image.fill(Color(0, 0, 0, 0))
	m.texture = ImageTexture.create_from_image(m.image)
	return m


static func path_of(world_dir: String, map_id: int) -> String:
	return world_dir.path_join("maps").path_join("map_%d" % map_id)


static func load_map(world_dir: String, map_id: int) -> MapData:
	var base := path_of(world_dir, map_id)
	var info := FileAccess.open(base + ".json", FileAccess.READ)
	if info == null:
		return null
	var d: Variant = JSON.parse_string(info.get_as_text())
	if not d is Dictionary:
		return null
	var m := MapData.new()
	m.id = map_id
	m.center = Vector2i(int(d.get("cx", 0)), int(d.get("cz", 0)))
	m.image = Image.load_from_file(ProjectSettings.globalize_path(base + ".png")) if FileAccess.file_exists(base + ".png") else null
	if m.image == null or m.image.get_width() != SIZE:
		m.image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		m.image.fill(Color(0, 0, 0, 0))
	m.image.convert(Image.FORMAT_RGBA8)
	m.texture = ImageTexture.create_from_image(m.image)
	return m


func save(world_dir: String) -> void:
	if world_dir.is_empty():
		return
	var base := path_of(world_dir, id)
	DirAccess.make_dir_recursive_absolute(base.get_base_dir())
	image.save_png(base + ".png")
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"cx": center.x, "cz": center.y}))
	dirty = false


## Пиксель карты, на котором находится точка мира (может быть вне 0..127).
func pixel_of(p: Vector3) -> Vector2:
	return Vector2((p.x - center.x) / SCALE + SIZE / 2.0, (p.z - center.y) / SCALE + SIZE / 2.0)


## Дорисовать часть карты вокруг игрока (только загруженные чанки).
func explore(world: World, around: Vector3) -> void:
	var c := pixel_of(around)
	var cx := int(c.x)
	var cz := int(c.y)
	var side := VIEW * 2 + 1
	var changed := false
	for n in PIXELS_PER_FRAME:
		_cursor = (_cursor + 1) % (side * side)
		@warning_ignore("integer_division")
		var px := cx - VIEW + _cursor % side
		@warning_ignore("integer_division")
		var pz := cz - VIEW + _cursor / side
		if px < 0 or pz < 0 or px >= SIZE or pz >= SIZE:
			continue
		if (px - cx) * (px - cx) + (pz - cz) * (pz - cz) > VIEW * VIEW:
			continue
		@warning_ignore("integer_division")
		var wx := center.x + (px - SIZE / 2) * SCALE + SCALE / 2
		@warning_ignore("integer_division")
		var wz := center.y + (pz - SIZE / 2) * SCALE + SCALE / 2
		if not world.has_chunk_at(wx, wz) or not world.has_chunk_at(wx, wz - SCALE):
			continue
		var col := _column_color(world, wx, wz)
		if image.get_pixel(px, pz) != col:
			image.set_pixel(px, pz, col)
			changed = true
	if changed:
		texture.update(image)
		dirty = true


func _column_color(world: World, x: int, z: int) -> Color:
	var y := _top(world, x, z)
	var id := world.get_block(x, y, z)
	var base := block_color(id, world.get_meta_v(Vector3i(x, y, z)))
	if Blocks.is_water(id):
		# Глубина воды — чем глубже, тем темнее.
		var d := 0
		while d < 10 and Blocks.is_water(world.get_block(x, y - d - 1, z)):
			d += 1
		return base.darkened(clampf(d / 14.0, 0.0, 0.6))
	var north := _top(world, x, z - SCALE)
	var shade := 1.0
	if north > y:
		shade = 0.82
	elif north < y:
		shade = 1.08
	return Color(base.r * shade, base.g * shade, base.b * shade, 1.0)


static func _top(world: World, x: int, z: int) -> int:
	var y := world.height_at(x, z)
	# Над непрозрачной вершиной могут лежать вода, снег, листва — берём самый верхний видимый блок.
	var up := y + 1
	while up < WorldGen.CHUNK_HEIGHT and up < y + 12:
		var id := world.get_block(x, up, z)
		if id == Blocks.AIR:
			break
		y = up
		up += 1
	return y


## Цвета материалов карты (как в оригинале 1.2).
static func block_color(id: int, meta: int) -> Color:
	match id:
		Blocks.GRASS, Blocks.TALLGRASS, Blocks.SAPLING, Blocks.REEDS, Blocks.MYCELIUM:
			return Color8(127, 178, 56) if id != Blocks.MYCELIUM else Color8(127, 63, 178)
		Blocks.SAND, Blocks.SANDSTONE, Blocks.GLOWSTONE, Blocks.END_STONE:
			return Color8(247, 233, 163)
		Blocks.WATER, Blocks.FLOWING_WATER:
			return Color8(64, 64, 255)
		Blocks.LAVA, Blocks.FLOWING_LAVA, Blocks.TNT, Blocks.FIRE, Blocks.NETHERRACK:
			return Color8(255, 0, 0)
		Blocks.ICE:
			return Color8(160, 160, 255)
		Blocks.SNOW, Blocks.SNOW_LAYER, Blocks.WOOL:
			return Color8(255, 255, 255)
		Blocks.LEAVES, Blocks.VINE, Blocks.CACTUS, Blocks.WATERLILY, Blocks.PUMPKIN, Blocks.MELON:
			return Color8(0, 124, 0)
		Blocks.CLAY:
			return Color8(164, 168, 184)
		Blocks.DIRT, Blocks.FARMLAND, Blocks.GRAVEL:
			return Color8(151, 109, 77) if id != Blocks.GRAVEL else Color8(112, 112, 112)
		Blocks.LOG, Blocks.PLANKS, Blocks.FENCE, Blocks.BOOKSHELF, Blocks.CHEST, Blocks.CRAFTING_TABLE, Blocks.OAK_STAIRS, \
				Blocks.WOODEN_DOOR, Blocks.TRAPDOOR, Blocks.SIGN_POST, Blocks.WALL_SIGN, Blocks.NOTE_BLOCK, Blocks.JUKEBOX:
			return Color8(104, 83, 50)
		Blocks.IRON_BLOCK, Blocks.IRON_DOOR, Blocks.BREWING_STAND, Blocks.CAULDRON:
			return Color8(167, 167, 167)
		Blocks.WEB, Blocks.DEADBUSH, Blocks.DANDELION, Blocks.ROSE:
			return Color8(0, 124, 0) if id != Blocks.WEB else Color8(199, 199, 199)
	return Color8(112, 112, 112)
