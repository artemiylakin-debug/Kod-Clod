extends SceneTree
## Контактный лист всех тайлов TexturePainter для визуальной проверки.
## Запуск:
##   godot --headless --path . -s res://tools/texture_sheet.gd -- <out.png> [плиток_в_ряду] [масштаб]
## Рядом с out.png сохраняются части листа out_partN.png (по 48 тайлов, крупнее) для детального просмотра.
## Оттеночные тайлы показываются умноженными на зелёный цвет травы. Автозагрузки в режиме -s не грузятся,
## поэтому скрипт зависит только от Tex и TexturePainter.

const GAP := 2
const GRASS := Color(0.47, 0.75, 0.35)
const PART_TILES := 48
const PART_COLS := 12
const PART_SCALE := 6
## Тайлы, обязанные быть серыми (окрашиваются при отрисовке).
const GRAY_EXTRA := ["REDSTONE_DUST_CROSS", "REDSTONE_DUST_LINE", "POTION_OVERLAY", "SPAWN_EGG", "SPAWN_EGG_OVERLAY"]
## Единственные тайлы с полупрозрачностью (кроме трещин); у остальных альфа строго 0 или 1.
const TRANSLUCENT := ["WATER", "ICE", "PORTAL"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://texture_sheet.png"
	var per_row: int = int(args[1]) if args.size() > 1 else 24
	var scale: int = int(args[2]) if args.size() > 2 else 4
	var names := _tile_names()

	var t0 := Time.get_ticks_usec()
	var tiles := TexturePainter.paint_all()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var errors := PackedStringArray()

	if tiles.size() != Tex.COUNT:
		errors.append("тайлов %d, ожидалось %d" % [tiles.size(), Tex.COUNT])
	var gray_ids: Array = Tex.TINTED.duplicate()
	for n: String in GRAY_EXTRA:
		gray_ids.append(names.find(n))
	for i in tiles.size():
		var img := tiles[i]
		var nm: String = names[i] if i < names.size() else str(i)
		if img == null:
			errors.append("%s: null" % nm)
			continue
		if img.get_width() != 16 or img.get_height() != 16 or img.get_format() != Image.FORMAT_RGBA8 or img.has_mipmaps():
			errors.append("%s: размер %dx%d формат %d мипмапы %s" % [nm, img.get_width(), img.get_height(),
					img.get_format(), img.has_mipmaps()])
			continue
		var opaque := 0
		var non_gray := 0
		var partial := 0
		for y in 16:
			for x in 16:
				var c := img.get_pixel(x, y)
				if c.a > 0.01 and c.a < 0.99:
					partial += 1
				if c.a > 0.01:
					opaque += 1
					if absf(c.r - c.g) > 0.01 or absf(c.g - c.b) > 0.01:
						non_gray += 1
				elif i in gray_ids and (absf(c.r - c.g) > 0.01 or absf(c.g - c.b) > 0.01):
					non_gray += 1
		if opaque == 0:
			errors.append("%s: пустой" % nm)
		if i in gray_ids and non_gray > 0:
			errors.append("%s: не серый (%d пикс.)" % [nm, non_gray])
		if partial > 0 and not (nm in TRANSLUCENT or nm.begins_with("CRACK_")):
			errors.append("%s: частичная альфа у %d пикс." % [nm, partial])

	# Детерминизм: второй прогон должен совпасть побайтно.
	var again := TexturePainter.paint_all()
	for i in mini(tiles.size(), again.size()):
		if tiles[i] != null and again[i] != null and tiles[i].get_data() != again[i].get_data():
			errors.append("%s: результат не детерминирован" % names[i])

	var all_ids := range(tiles.size())
	_save_sheet(tiles, all_ids, 0, tiles.size(), per_row, scale, out_path)
	var base := out_path.get_basename()
	# Необязательный 4-й аргумент: имена тайлов через запятую — крупный лист <out>_focus.png.
	if args.size() > 3:
		var picked: Array[Image] = []
		var picked_ids: Array = []
		for nm in args[3].split(","):
			var idx := names.find(nm.strip_edges())
			if idx >= 0:
				picked.append(tiles[idx])
				picked_ids.append(idx)
			else:
				print("Нет тайла: ", nm)
		_save_sheet(picked, picked_ids, 0, picked.size(), mini(picked.size(), 6), 16, "%s_focus.png" % base)
	var part := 0
	for start in range(0, tiles.size(), PART_TILES):
		_save_sheet(tiles, all_ids, start, mini(start + PART_TILES, tiles.size()), PART_COLS, PART_SCALE,
				"%s_part%d.png" % [base, part])
		var listing := PackedStringArray()
		var end := mini(start + PART_TILES, tiles.size())
		for r in range(start, end, PART_COLS):
			listing.append("  ряд %d: %s" % [floori((r - start) / float(PART_COLS)), ", ".join(names.slice(r, mini(r + PART_COLS, end)))])
		print("часть %d:\n%s" % [part, "\n".join(listing)])
		part += 1

	print("Тайлов: %d (Tex.COUNT = %d), время рисования: %.1f мс" % [tiles.size(), Tex.COUNT, ms])
	print("Лист: %s" % out_path)
	if errors.is_empty():
		print("Проверки пройдены")
	else:
		print("ОШИБКИ (%d):\n  %s" % [errors.size(), "\n  ".join(errors)])
	quit(0 if errors.is_empty() else 1)


func _tile_names() -> PackedStringArray:
	var names := PackedStringArray()
	names.resize(Tex.COUNT)
	var consts: Dictionary = (Tex as Script).get_script_constant_map()
	for key: String in consts:
		var v: Variant = consts[key]
		if typeof(v) == TYPE_INT and key != "COUNT" and key != "FIRST_ITEM" and v >= 0 and v < Tex.COUNT:
			names[v] = key
	return names


## ids[i] — номер в Tex для tiles[i] (нужен, чтобы окрасить оттеночные тайлы).
func _save_sheet(tiles: Array[Image], ids: Array, from: int, to: int, per_row: int, scale: int,
		path: String) -> void:
	var cell := 16 * scale
	var count := to - from
	var rows := ceili(count / float(per_row))
	var w := per_row * (cell + GAP) + GAP
	var h := rows * (cell + GAP) + GAP
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.16, 0.17, 0.2))
	for k in count:
		var i := from + k
		var src := tiles[i]
		if src == null:
			continue
		var img := src.duplicate() as Image
		if ids[i] in Tex.TINTED:
			for y in 16:
				for x in 16:
					var c := img.get_pixel(x, y)
					img.set_pixel(x, y, Color(c.r * GRASS.r, c.g * GRASS.g, c.b * GRASS.b, c.a))
		img.resize(cell, cell, Image.INTERPOLATE_NEAREST)
		var ox := GAP + (k % per_row) * (cell + GAP)
		var oy := GAP + floori(k / float(per_row)) * (cell + GAP)
		# Шахматка под прозрачностью.
		for y in cell:
			for x in cell:
				var check := (floori(x / (scale * 2.0)) + floori(y / (scale * 2.0))) % 2 == 0
				var bg := Color(0.62, 0.62, 0.66) if check else Color(0.5, 0.5, 0.54)
				var c := img.get_pixel(x, y)
				sheet.set_pixel(ox + x, oy + y, bg.lerp(Color(c.r, c.g, c.b), c.a))
	sheet.save_png(path)
