class_name WorldStorage
extends RefCounted
## Сохранение миров: meta.json (сид, режим, игрок, время) и сжатые файлы изменённых чанков.
## Формат чанка 2: блоки, данные блоков, биомы, контейнеры и существа. Чанки формата 1
## (высота 128, старые номера блоков) читаются и преобразуются.

const ROOT := "user://worlds"
const CHUNK_MAGIC_V1 := 0x424B4331 # "BKC1"
const CHUNK_MAGIC := 0x424B4332 # "BKC2"
const V1_HEIGHT := 128
## Старые номера блоков (до версии с полным набором 1.2) → номера Minecraft.
const V1_IDS := [0, 2, 3, 1, 4, 17, 18, 5, 12, 20, 7, 9, 16, 15, 45, 80, 13, 98, 47]


static func world_dir(id: String) -> String:
	return ROOT.path_join(id)


static func chunk_path(dir: String, key: Vector2i) -> String:
	return dir.path_join("chunks").path_join("c_%d_%d.bin" % [key.x, key.y])


## chunk — словарь {blocks, meta, biomes, block_entities, entities}.
static func save_chunk(dir: String, key: Vector2i, chunk: Dictionary) -> bool:
	if dir.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(dir.path_join("chunks"))
	var path := chunk_path(dir, key)
	var tmp := path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("Не удалось записать чанк %s: %s" % [path, FileAccess.get_open_error()])
		return false
	var blocks: PackedByteArray = chunk["blocks"]
	var meta: PackedByteArray = chunk.get("meta", PackedByteArray())
	if meta.size() != blocks.size():
		meta = PackedByteArray()
		meta.resize(blocks.size())
	var biomes: PackedByteArray = chunk.get("biomes", PackedByteArray())
	f.store_32(CHUNK_MAGIC)
	f.store_32(blocks.size())
	f.store_buffer(blocks)
	f.store_buffer(meta)
	f.store_32(biomes.size())
	f.store_buffer(biomes)
	var extra := JSON.stringify({"be": _keys_to_str(chunk.get("block_entities", {})), "ent": chunk.get("entities", [])})
	var bytes := extra.to_utf8_buffer()
	f.store_32(bytes.size())
	f.store_buffer(bytes)
	f.close()
	# Запись во временный файл и переименование защищают от битых файлов при внезапном закрытии.
	return DirAccess.rename_absolute(tmp, path) == OK


## Возвращает пустой словарь, если чанк не сохранялся или файл повреждён.
static func load_chunk(dir: String, key: Vector2i) -> Dictionary:
	if dir.is_empty():
		return {}
	var path := chunk_path(dir, key)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var magic := f.get_32()
	if magic == CHUNK_MAGIC_V1:
		return _load_v1(f)
	if magic != CHUNK_MAGIC:
		return {}
	var size := f.get_32()
	if size != WorldGen.VOLUME:
		return {}
	var blocks := f.get_buffer(size)
	var meta := f.get_buffer(size)
	if blocks.size() != size or meta.size() != size:
		return {}
	var bsize := f.get_32()
	var biomes := f.get_buffer(bsize)
	var block_entities := {}
	var entities := []
	var esize := f.get_32()
	if esize > 0 and esize < 1 << 26:
		var parsed: Variant = JSON.parse_string(f.get_buffer(esize).get_string_from_utf8())
		if parsed is Dictionary:
			block_entities = _keys_to_int(parsed.get("be", {}))
			var e: Variant = parsed.get("ent", [])
			if e is Array:
				entities = e
	if biomes.size() != WorldGen.LAYER:
		biomes = PackedByteArray()
		biomes.resize(WorldGen.LAYER)
		biomes.fill(Biomes.PLAINS)
	return {"blocks": blocks, "meta": meta, "biomes": biomes, "block_entities": block_entities, "entities": entities}


## Чанк старого формата: 16×128×16, старые номера блоков.
static func _load_v1(f: FileAccess) -> Dictionary:
	var size := f.get_32()
	if size != WorldGen.LAYER * V1_HEIGHT:
		return {}
	var old := f.get_buffer(size)
	if old.size() != size:
		return {}
	var blocks := PackedByteArray()
	blocks.resize(WorldGen.VOLUME)
	for i in size:
		var b := old[i]
		blocks[i] = V1_IDS[b] if b < V1_IDS.size() else Blocks.STONE
	var meta := PackedByteArray()
	meta.resize(WorldGen.VOLUME)
	var biomes := PackedByteArray()
	biomes.resize(WorldGen.LAYER)
	biomes.fill(Biomes.PLAINS)
	return {"blocks": blocks, "meta": meta, "biomes": biomes, "block_entities": {}, "entities": []}


static func _keys_to_str(d: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in d:
		out[str(k)] = d[k]
	return out


static func _keys_to_int(d: Variant) -> Dictionary:
	var out := {}
	if d is Dictionary:
		for k: Variant in d:
			out[int(str(k))] = d[k]
	return out


static func save_meta(dir: String, meta: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("meta.json")
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось записать %s" % path)
		return false
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK


static func load_meta(dir: String) -> Dictionary:
	var path := dir.path_join("meta.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}


## Список миров, отсортированный по времени последней игры (новые сверху).
static func list_worlds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(ROOT)
	if d == null:
		return out
	for id in d.get_directories():
		var meta := load_meta(world_dir(id))
		if meta.is_empty():
			continue
		meta["id"] = id
		out.append(meta)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("last_played", 0)) > float(b.get("last_played", 0)))
	return out


static func delete_world(id: String) -> void:
	if id.is_empty() or id.contains("/") or id.contains(".."):
		return
	_remove_recursive(world_dir(id))


static func _remove_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_remove_recursive(path.path_join(sub))
	for file in d.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
