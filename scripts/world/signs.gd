class_name Signs
extends Node3D
## Надписи на табличках: текст хранится в данных блока ({"text": [4 строки]}), а показывается
## объектами Label3D на лицевой стороне доски. Надписи создаются при загрузке чанка и убираются
## при выгрузке или когда табличку сломали.

const LINES := 4
const MAX_CHARS := 15

var world: World
var _labels: Dictionary = {}
var _check := 0.0


func setup(p_world: World) -> void:
	world = p_world
	world.chunk_loaded.connect(_on_chunk_loaded)
	world.chunk_unloading.connect(_on_chunk_unloading)
	for ch: Chunk in world.chunks.values():
		_on_chunk_loaded(ch)


static func is_sign(id: int) -> bool:
	return id == Blocks.SIGN_POST or id == Blocks.WALL_SIGN


static func lines_of(be: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(["", "", "", ""])
	var t: Variant = be.get("text", [])
	if t is Array:
		for k in mini((t as Array).size(), LINES):
			out[k] = str(t[k]).substr(0, MAX_CHARS)
	return out


func set_text(p: Vector3i, lines: PackedStringArray) -> void:
	var be := world.get_block_entity(p)
	var arr := []
	for k in LINES:
		arr.append(lines[k].substr(0, MAX_CHARS) if k < lines.size() else "")
	be["text"] = arr
	world.mark_dirty(p)
	refresh(p)


## Создать, обновить или убрать надпись таблички в клетке p.
func refresh(p: Vector3i) -> void:
	var id := world.get_block_v(p)
	var label: Label3D = _labels.get(p)
	if not is_sign(id):
		if label != null:
			label.queue_free()
			_labels.erase(p)
		return
	var be := world.get_block_entity(p, false)
	var text := "\n".join(lines_of(be)).strip_edges()
	if text.is_empty():
		if label != null:
			label.queue_free()
			_labels.erase(p)
		return
	if label == null:
		label = Label3D.new()
		label.font_size = 40
		label.outline_size = 0
		label.pixel_size = 0.0028
		label.modulate = Color(0.08, 0.06, 0.04)
		label.shaded = false
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.line_spacing = -4.0
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(label)
		_labels[p] = label
	label.text = "\n".join(lines_of(be))
	var meta := world.get_meta_v(p)
	var base := Vector3(p)
	var front: Vector3
	var center: Vector3
	if id == Blocks.WALL_SIGN:
		front = Vector3(Blocks.DIR_VEC[meta & 3])
		center = base + Vector3(0.5, 8.5 / 16.0, 0.5) - front * (0.5 - 2.0 / 16.0)
	else:
		# Доска на столбике повёрнута к одной из четырёх сторон (как её рисует мешер).
		@warning_ignore("integer_division")
		var quarter := ((meta + 2) / 4) % 4
		var a := quarter * PI / 2.0
		front = Vector3(-sin(a), 0, cos(a)).round()
		center = base + Vector3(0.5, 12.0 / 16.0, 0.5) + front * (1.0 / 16.0)
	label.position = center + front * 0.012
	label.rotation = Vector3(0, atan2(front.x, front.z), 0)


func _on_chunk_loaded(ch: Chunk) -> void:
	for i: int in ch.block_entities:
		var be: Dictionary = ch.block_entities[i]
		if be.has("text"):
			var lp := Chunk.local_pos(i)
			refresh(Vector3i(ch.key.x * 16 + lp.x, lp.y, ch.key.y * 16 + lp.z))


func _on_chunk_unloading(ch: Chunk) -> void:
	for p: Vector3i in _labels.keys():
		if World.key_of(Vector3(p)) == ch.key:
			(_labels[p] as Node).queue_free()
			_labels.erase(p)


## Раз в полсекунды убираем надписи сломанных табличек.
func update(delta: float) -> void:
	_check += delta
	if _check < 0.5:
		return
	_check = 0.0
	for p: Vector3i in _labels.keys():
		if not is_sign(world.get_block_v(p)):
			refresh(p)
