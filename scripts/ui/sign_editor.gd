class_name SignEditor
extends Control
## Ввод текста таблички: четыре строки до 15 символов, как в оригинале.

signal finished(pos: Vector3i, lines: PackedStringArray)

var pos := Vector3i.ZERO
var _edits: Array[LineEdit] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_child(UITheme.dim(0.45))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.62, 0.46, 0.26, 0.97), Color(0.35, 0.24, 0.12), 4, 10.0, 18.0))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(UITheme.label("Текст таблички", 24))
	for k in Signs.LINES:
		var e := LineEdit.new()
		e.max_length = Signs.MAX_CHARS
		e.custom_minimum_size = Vector2(420, 48)
		e.alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.add_theme_font_size_override("font_size", 24)
		e.text_submitted.connect(_on_submitted.bind(k))
		col.add_child(e)
		_edits.append(e)
	var done := UITheme.button("Готово", 0)
	done.pressed.connect(close_editor)
	col.add_child(done)


func open(p: Vector3i, lines: PackedStringArray) -> void:
	pos = p
	for k in _edits.size():
		_edits[k].text = lines[k] if k < lines.size() else ""
	visible = true
	_edits[0].grab_focus()


func _on_submitted(_text: String, k: int) -> void:
	if k + 1 < _edits.size():
		_edits[k + 1].grab_focus()
	else:
		close_editor()


func close_editor() -> void:
	if not visible:
		return
	visible = false
	var lines := PackedStringArray()
	for e in _edits:
		lines.append(e.text)
	finished.emit(pos, lines)
