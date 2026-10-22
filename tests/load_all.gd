extends Node
## Загружает все скрипты проекта — быстрый поиск ошибок компиляции.
## Запуск: godot --headless --path . res://tests/load_all.tscn


func _ready() -> void:
	var failed := 0
	for path in _scripts("res://scripts"):
		var s: Script = load(path)
		if s == null or not s.can_instantiate():
			failed += 1
			print("FAILED: ", path)
	print("load_all: ", failed, " failed")
	get_tree().quit(1 if failed > 0 else 0)


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	return out
