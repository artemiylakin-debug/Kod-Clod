class_name WorldStorage
extends RefCounted
## Сохранение миров: meta.json (сид, режим, игрок, время) и сжатые файлы изменённых чанков.

const ROOT := "user://worlds"
const CHUNK_MAGIC := 0x424B4331 # "BKC1"


static func world_dir(id: String) -> String:
	return ROOT.path_join(id)


static func chunk_path(dir: String, key: Vector2i) -> String:
	return dir.path_join("chunks").path_join("c_%d_%d.bin" % [key.x, key.y])


static func save_chunk(dir: String, key: Vector2i, data: PackedByteArray) -> bool:
	if dir.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(dir.path_join("chunks"))
	var path := chunk_path(dir, key)
	var tmp := path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("Не удалось записать чанк %s: %s" % [path, FileAccess.get_open_error()])
		return false
	f.store_32(CHUNK_MAGIC)
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	# Запись во временный файл и переименование защищают от битых файлов при внезапном закрытии.
	return DirAccess.rename_absolute(tmp, path) == OK


## Возвращает пустой массив, если чанк не сохранялся или файл повреждён.
static func load_chunk(dir: String, key: Vector2i) -> PackedByteArray:
	if dir.is_empty():
		return PackedByteArray()
	var path := chunk_path(dir, key)
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return PackedByteArray()
	if f.get_32() != CHUNK_MAGIC:
		return PackedByteArray()
	var size := f.get_32()
	if size != WorldGen.VOLUME:
		return PackedByteArray()
	var data := f.get_buffer(size)
	if data.size() != size:
		return PackedByteArray()
	return data


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
