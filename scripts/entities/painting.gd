class_name Painting
extends Node3D
## Картина на стене (1.2): размер от 1×1 до 4×4 блоков, изображение выбирается случайно из тех,
## что помещаются. Картины нарисованы процедурно (пейзажи, абстракции) — по семени варианта.
## Сорвать картину можно ударом; без стены за ней она падает предметом.

## [название, ширина, высота] — набор размеров как в оригинале.
const ARTS := [
	["Kebab", 1, 1], ["Aztec", 1, 1], ["Alban", 1, 1], ["Aztec2", 1, 1], ["Bomb", 1, 1], ["Plant", 1, 1],
	["Wasteland", 1, 1], ["Pool", 2, 1], ["Courbet", 2, 1], ["Sea", 2, 1], ["Sunset", 2, 1], ["Creebet", 2, 1],
	["Wanderer", 1, 2], ["Graham", 1, 2], ["Match", 2, 2], ["Bust", 2, 2], ["Stage", 2, 2], ["Void", 2, 2],
	["SkullAndRoses", 2, 2], ["Fighters", 4, 2], ["Skeleton", 4, 3], ["DonkeyKong", 4, 3], ["Pointer", 4, 4],
	["Pigscene", 4, 4], ["BurningSkull", 4, 4],
]
const PX := 16

var kind := "painting"
var world: World
var manager: EntityManager
## Нижний левый блок картины (если смотреть на неё), направление «лица» 0–3 (Blocks.DIR_VEC), вариант.
var cell := Vector3i.ZERO
var facing := 0
var art := 0
var _mesh: MeshInstance3D
var _check := 0.0

static var _textures: Dictionary = {}


func size() -> Vector2i:
	return Vector2i(int(ARTS[art][1]), int(ARTS[art][2]))


## Вектор «вправо» для смотрящего на картину (вдоль стены).
static func right_of(face: int) -> Vector3i:
	var f: Vector3i = Blocks.DIR_VEC[face]
	return Vector3i(-f.z, 0, f.x)


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _quad(size())
	_mesh.material_override = TextureFactory.mob_material(art_texture(art))
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_place_visual()


func _place_visual() -> void:
	var f := Vector3(Blocks.DIR_VEC[facing])
	var r := Vector3(right_of(facing))
	var s := size()
	# Центр картины у самой стены (стена — за клеткой, в направлении −f).
	var center := Vector3(cell) + Vector3(0.5, 0.0, 0.5) + r * (s.x - 1) * 0.5 + Vector3(0, s.y * 0.5, 0) - f * (0.5 - 1.0 / 16.0)
	position = center
	rotation = Vector3(0, atan2(f.x, f.z), 0)


## Квадрат w×h, лицом к +Z (после поворота — от стены), с деревянной кромкой.
static func _quad(s: Vector2i) -> ArrayMesh:
	var w := float(s.x) * 0.5
	var h := float(s.y) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-w, -h, 0), Vector3(w, -h, 0), Vector3(w, h, 0), Vector3(-w, h, 0)]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i: int in [0, 2, 1, 0, 3, 2]:
		st.set_color(Color.WHITE)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	return st.commit()


## Изображение варианта: процедурная картина в рамке.
static func art_texture(index: int) -> Texture2D:
	if _textures.has(index):
		return _textures[index]
	var w := int(ARTS[index][1]) * PX
	var h := int(ARTS[index][2]) * PX
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + index * 7919
	var style := index % 4
	var sky_a := Color.from_hsv(rng.randf_range(0.5, 0.7), rng.randf_range(0.3, 0.6), rng.randf_range(0.6, 0.95))
	var sky_b := Color.from_hsv(rng.randf_range(0.0, 0.15), rng.randf_range(0.3, 0.7), rng.randf_range(0.7, 1.0))
	var ground := Color.from_hsv(rng.randf_range(0.2, 0.4), rng.randf_range(0.4, 0.7), rng.randf_range(0.35, 0.6))
	var horizon := int(h * rng.randf_range(0.45, 0.7))
	var hills := []
	for k in 3:
		hills.append([rng.randf_range(0.0, w), rng.randf_range(2.0, h * 0.35), rng.randf_range(w * 0.2, w * 0.6)])
	var sun := Vector2(rng.randf_range(w * 0.2, w * 0.8), rng.randf_range(h * 0.12, horizon * 0.6))
	for y in h:
		for x in w:
			var c: Color
			match style:
				0, 1:
					# Пейзаж: небо с градиентом, солнце, холмы.
					c = sky_a.lerp(sky_b, float(y) / maxf(horizon, 1.0))
					if Vector2(x, y).distance_to(sun) < 2.6 + w * 0.03:
						c = Color(1.0, 0.92, 0.55)
					var top := float(horizon)
					for hl: Array in hills:
						var dx := (x - float(hl[0])) / float(hl[2])
						top = minf(top, horizon - float(hl[1]) * maxf(0.0, 1.0 - dx * dx))
					if y >= top:
						c = ground.darkened(0.15 * float(y - top) / maxf(h - top, 1.0))
						if style == 1 and y > horizon + 2:
							c = Color(0.25, 0.4, 0.75).lerp(Color(0.15, 0.25, 0.55), float(y - horizon) / h)
				2:
					# Абстракция: цветные прямоугольники.
					c = sky_b.darkened(0.3)
				_:
					# Узор из ромбов.
					var d := absi((x % 8) - 4) + absi((y % 8) - 4)
					c = sky_a if d < 3 else ground.lerp(sky_b, 0.5)
			c = c.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.05)
			img.set_pixel(x, y, c)
	if style == 2:
		for k in 5 + index % 4:
			@warning_ignore("integer_division")
			var rw := rng.randi_range(2, maxi(w / 2, 3))
			@warning_ignore("integer_division")
			var rh := rng.randi_range(2, maxi(h / 2, 3))
			var rx := rng.randi_range(1, maxi(w - rw - 1, 1))
			var ry := rng.randi_range(1, maxi(h - rh - 1, 1))
			img.fill_rect(Rect2i(rx, ry, rw, rh), Color.from_hsv(rng.randf(), 0.7, 0.85))
	# Деревянная рамка.
	var frame := Color(0.45, 0.3, 0.15)
	for x in w:
		img.set_pixel(x, 0, frame)
		img.set_pixel(x, h - 1, frame.darkened(0.2))
	for y in h:
		img.set_pixel(0, y, frame)
		img.set_pixel(w - 1, y, frame.darkened(0.2))
	var tex := ImageTexture.create_from_image(img)
	_textures[index] = tex
	return tex


## Клетки, которые занимает картина.
func cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var r := right_of(facing)
	var s := size()
	for i in s.x:
		for j in s.y:
			out.append(cell + r * i + Vector3i(0, j, 0))
	return out


## Помещается ли картина размера s: за каждой клеткой — твёрдая стена, сами клетки свободны.
static func fits(world: World, at: Vector3i, face: int, s: Vector2i, others: Array) -> bool:
	var r := right_of(face)
	var back: Vector3i = -Blocks.DIR_VEC[face]
	for i in s.x:
		for j in s.y:
			var c := at + r * i + Vector3i(0, j, 0)
			if world.get_block_v(c) != Blocks.AIR or not Blocks.is_solid(world.get_block_v(c + back)):
				return false
			for o: Painting in others:
				if o.facing == face and c in o.cells():
					return false
	return true


func body_box() -> AABB:
	var s := size()
	var f := Vector3(Blocks.DIR_VEC[facing])
	var r := Vector3(right_of(facing))
	var half := (r * s.x * 0.5).abs() + Vector3(0, s.y * 0.5, 0) + f.abs() * 0.06
	return AABB(position - half, half * 2.0)


func interact(_player: Player) -> bool:
	return false


func hit(player: Player, _damage: int) -> void:
	if not player.creative:
		manager.spawn_drop(Items.PAINTING, 1, 0, position + Vector3(Blocks.DIR_VEC[facing]) * 0.3)
	queue_free()


func update_entity(dt: float) -> void:
	_check -= dt
	if _check > 0.0 or world == null:
		return
	_check = 0.5
	BoxModel.light(_mesh, world, position + Vector3(Blocks.DIR_VEC[facing]) * 0.3)
	# Стена за картиной исчезла — картина падает.
	var back: Vector3i = -Blocks.DIR_VEC[facing]
	for c in cells():
		if not Blocks.is_solid(world.get_block_v(c + back)) or world.get_block_v(c) != Blocks.AIR:
			manager.spawn_drop(Items.PAINTING, 1, 0, position)
			queue_free()
			return


func to_dict() -> Dictionary:
	return {"kind": "painting", "pos": [position.x, position.y, position.z], "cell": [cell.x, cell.y, cell.z],
		"facing": facing, "art": art}


func from_dict(d: Dictionary) -> void:
	var c: Array = d.get("cell", [])
	if c.size() == 3:
		cell = Vector3i(int(c[0]), int(c[1]), int(c[2]))
	facing = int(d.get("facing", 0)) & 3
	art = clampi(int(d.get("art", 0)), 0, ARTS.size() - 1)
