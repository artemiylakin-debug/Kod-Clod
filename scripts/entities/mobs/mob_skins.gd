class_name MobSkins
extends RefCounted
## Процедурные скины существ (развёртка как в Minecraft: области граней каждого параллелепипеда
## модели — см. MobModel). Никаких внешних ассетов: всё рисуется при первом обращении.
## Альфа 1 — обычный пиксель, 0 — прозрачный, 0.75 — светящийся (глаза паука, эндермена, магма).

const GLOW := 0.75

static var _cache: Dictionary = {}
static var _rng := RandomNumberGenerator.new()


static func get_skin(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	_rng.seed = hash(key)
	var img := _paint(key)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func clear() -> void:
	_cache.clear()


# --- Помощники ---------------------------------------------------------------

static func _img(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


static func _vary(c: Color, amt: float) -> Color:
	var k := 1.0 + _rng.randf_range(-amt, amt)
	return Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1), c.a)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color, amt := 0.06) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, _vary(c, amt))


## Все грани параллелепипеда (u, v, ширина, высота, глубина) одним цветом с шумом.
static func _box(img: Image, u: int, v: int, w: int, h: int, d: int, c: Color, amt := 0.06) -> void:
	_rect(img, u + d, v, w * 2, d, c, amt)
	_rect(img, u, v + d, (w + d) * 2, h, c, amt)


## Область грани: front, back, right, left, top, bottom.
static func _face(u: int, v: int, w: int, h: int, d: int, f: String) -> Rect2i:
	match f:
		"front":
			return Rect2i(u + d, v + d, w, h)
		"back":
			return Rect2i(u + d + w + d, v + d, w, h)
		"right":
			return Rect2i(u, v + d, d, h)
		"left":
			return Rect2i(u + d + w, v + d, d, h)
		"top":
			return Rect2i(u + d, v, w, d)
		"bottom":
			return Rect2i(u + d + w, v, w, d)
	return Rect2i()


## Пятнистая заливка из палитры (крипер, оцелот).
static func _speckle_box(img: Image, u: int, v: int, w: int, h: int, d: int, palette: Array, weights: Array) -> void:
	var total := 0.0
	for wt: float in weights:
		total += wt
	var fill := func(x0: int, y0: int, ww: int, hh: int) -> void:
		for y in range(y0, y0 + hh):
			for x in range(x0, x0 + ww):
				var r := _rng.randf() * total
				var k := 0
				while k < weights.size() - 1 and r > float(weights[k]):
					r -= float(weights[k])
					k += 1
				_px(img, x, y, palette[k])
	fill.call(u + d, v, w * 2, d)
	fill.call(u, v + d, (w + d) * 2, h)


static func _glow(c: Color) -> Color:
	return Color(c.r, c.g, c.b, GLOW)


## Строки-шаблоны: символ → цвет (пробел/точка — не рисовать).
static func _pattern(img: Image, x0: int, y0: int, rows: Array, colors: Dictionary) -> void:
	for j in rows.size():
		var row: String = rows[j]
		for i in row.length():
			var ch := row[i]
			if colors.has(ch):
				_px(img, x0 + i, y0 + j, colors[ch])


# --- Скины --------------------------------------------------------------------

static func _paint(key: String) -> Image:
	match key:
		"zombie":
			return _zombie()
		"pigman":
			return _pigman()
		"skeleton":
			return _skeleton()
		"creeper":
			return _creeper()
		"spider":
			return _spider(Color(0.21, 0.17, 0.15), Color(0.33, 0.27, 0.22))
		"cave_spider":
			return _spider(Color(0.06, 0.2, 0.24), Color(0.12, 0.33, 0.36))
		"enderman":
			return _enderman()
		"pig":
			return _pig()
		"pig_saddle":
			return _pig_saddle()
		"cow":
			return _cow(Color(0.27, 0.2, 0.14), Color(0.9, 0.9, 0.88))
		"mooshroom":
			return _cow(Color(0.62, 0.07, 0.07), Color(0.82, 0.8, 0.8))
		"sheep":
			return _sheep()
		"sheep_wool":
			return _sheep_wool()
		"chicken":
			return _chicken()
		"squid":
			return _squid()
		"wolf":
			return _wolf(0)
		"wolf_tame":
			return _wolf(1)
		"wolf_angry":
			return _wolf(2)
		"ocelot":
			return _ocelot(0)
		"cat_black":
			return _ocelot(1)
		"cat_red":
			return _ocelot(2)
		"cat_siamese":
			return _ocelot(3)
		"iron_golem":
			return _iron_golem()
		"snow_golem":
			return _snow_golem()
		"slime":
			return _slime()
		"magma_cube":
			return _magma_cube()
		"ghast":
			return _ghast(false)
		"ghast_fire":
			return _ghast(true)
		"blaze":
			return _blaze()
		"silverfish":
			return _silverfish()
		"end_crystal":
			return _end_crystal()
		"dragon":
			return _dragon()
	if key.begins_with("villager_"):
		return _villager(int(key.substr(9)))
	return _pig()


static func _zombie() -> Image:
	var img := _img(64, 32)
	var skin := Color(0.33, 0.55, 0.27)
	var shirt := Color(0.0, 0.62, 0.62)
	var pants := Color(0.24, 0.22, 0.58)
	_box(img, 0, 0, 8, 8, 8, skin, 0.08)
	var dark := Color(0.2, 0.36, 0.17)
	_rect(img, 8, 0, 8, 8, dark, 0.1)
	_rect(img, 8, 8, 8, 2, dark, 0.1)
	_rect(img, 0, 8, 8, 2, dark, 0.1)
	_rect(img, 16, 8, 16, 2, dark, 0.1)
	_pattern(img, 8, 8, ["", "", "", "", ".KK..KK.", "...nn...", "..mmmm..", ""],
		{"K": Color(0.05, 0.08, 0.05), "n": Color(0.22, 0.4, 0.18), "m": Color(0.18, 0.3, 0.14)})
	_box(img, 16, 16, 8, 12, 4, shirt, 0.07)
	_rect(img, 20, 30, 8, 2, Color(0.0, 0.48, 0.48), 0.05)
	_box(img, 40, 16, 4, 12, 4, skin, 0.08)
	_rect(img, 40, 20, 16, 3, shirt, 0.06)
	_rect(img, 44, 16, 4, 4, shirt, 0.06)
	_box(img, 0, 16, 4, 12, 4, pants, 0.07)
	_rect(img, 0, 30, 16, 2, Color(0.28, 0.28, 0.3), 0.06)
	return img


static func _pigman() -> Image:
	var img := _img(64, 32)
	var pink := Color(0.91, 0.6, 0.58)
	var rot := Color(0.38, 0.58, 0.3)
	var bone := Color(0.85, 0.83, 0.75)
	_box(img, 0, 0, 8, 8, 8, pink, 0.07)
	# Правая половина головы — гниль и кость.
	_rect(img, 0, 8, 8, 8, rot, 0.12)
	_rect(img, 8, 8, 3, 8, rot, 0.12)
	_rect(img, 0, 10, 3, 3, bone, 0.04)
	_pattern(img, 8, 8, ["", "", "", "WK..KW..", "", "..pPPp..", "..pqqp..", ".mmmmmm."],
		{"W": Color(0.95, 0.95, 0.95), "K": Color(0.1, 0.05, 0.05), "p": Color(0.96, 0.7, 0.68),
			"P": Color(0.98, 0.76, 0.74), "q": Color(0.55, 0.3, 0.3), "m": Color(0.45, 0.22, 0.2)})
	_box(img, 16, 16, 8, 12, 4, pink, 0.07)
	# Рёбра и гниль на груди, набедренная повязка.
	for r in [1, 3, 5]:
		_rect(img, 21, 20 + r, 3, 1, bone, 0.03)
	_rect(img, 24, 20, 4, 6, rot, 0.12)
	_rect(img, 16, 28, 24, 4, Color(0.45, 0.3, 0.16), 0.08)
	_box(img, 40, 16, 4, 12, 4, pink, 0.07)
	_rect(img, 40, 24, 8, 4, rot, 0.12)
	_box(img, 0, 16, 4, 12, 4, pink, 0.07)
	_rect(img, 0, 20, 16, 3, Color(0.45, 0.3, 0.16), 0.08)
	_rect(img, 4, 24, 4, 5, rot, 0.12)
	return img


static func _skeleton() -> Image:
	var img := _img(64, 32)
	var bone := Color(0.76, 0.76, 0.74)
	var dark := Color(0.28, 0.28, 0.28)
	_box(img, 0, 0, 8, 8, 8, bone, 0.06)
	_pattern(img, 8, 8, ["", "", "", ".KK..KK.", ".KK..KK.", "...kk...", ".kKkKkK.", ""],
		{"K": Color(0.12, 0.12, 0.12), "k": Color(0.4, 0.4, 0.4)})
	# Грудная клетка: позвоночник и рёбра на тёмном фоне.
	_box(img, 16, 16, 8, 12, 4, dark, 0.08)
	for r in [1, 3, 5, 7]:
		_rect(img, 16, 20 + r, 24, 1, bone, 0.04)
	_rect(img, 23, 20, 2, 12, bone, 0.04)
	_rect(img, 35, 20, 2, 12, bone, 0.04)
	_rect(img, 16, 30, 24, 2, bone, 0.04)
	_box(img, 40, 16, 2, 12, 2, bone, 0.06)
	_rect(img, 40, 24, 8, 1, Color(0.6, 0.6, 0.58), 0.03)
	_box(img, 0, 16, 2, 12, 2, bone, 0.06)
	_rect(img, 0, 24, 8, 1, Color(0.6, 0.6, 0.58), 0.03)
	return img


static func _creeper() -> Image:
	var img := _img(64, 32)
	var pal := [Color(0.33, 0.69, 0.24), Color(0.5, 0.84, 0.43), Color(0.2, 0.5, 0.15), Color(0.72, 0.9, 0.68),
		Color(0.42, 0.6, 0.4), Color(0.12, 0.38, 0.1)]
	var wts := [5.0, 3.0, 2.5, 0.8, 1.2, 0.6]
	_speckle_box(img, 0, 0, 8, 8, 8, pal, wts)
	_speckle_box(img, 16, 16, 8, 12, 4, pal, wts)
	_speckle_box(img, 0, 16, 4, 6, 4, pal, wts)
	_rect(img, 0, 25, 16, 1, Color(0.15, 0.4, 0.12), 0.1)
	var k := Color(0.02, 0.02, 0.02)
	var g := Color(0.12, 0.22, 0.1)
	_pattern(img, 8, 8, ["", "", ".KK..KK.", ".KK..KK.", "...gg...", "..KKKK..", "..KKKK..", "..K..K.."], {"K": k, "g": g})
	_pattern(img, 8, 8, ["", "", "", "", "...KK...", "", "", ""], {"K": k})
	return img


static func _spider(base: Color, light: Color) -> Image:
	var img := _img(64, 32)
	var pal := [base, light, base.darkened(0.35), Color(0.12, 0.1, 0.09)]
	var wts := [5.0, 2.0, 2.0, 1.0]
	_speckle_box(img, 0, 12, 10, 8, 12, pal, wts)
	# Узор на брюшке.
	var top := _face(0, 12, 10, 8, 12, "top")
	for i in 4:
		_rect(img, top.position.x + 3, top.position.y + 2 + i * 3, 4, 1, light.lightened(0.15), 0.05)
	_speckle_box(img, 0, 0, 6, 6, 6, pal, wts)
	_speckle_box(img, 32, 4, 8, 8, 8, pal, wts)
	_speckle_box(img, 18, 0, 16, 2, 2, pal, wts)
	for x in [24, 30, 36, 42]:
		_rect(img, x, 2, 1, 2, light.lightened(0.2), 0.05)
	var r := _glow(Color(0.95, 0.12, 0.1))
	var r2 := _glow(Color(0.7, 0.05, 0.05))
	_pattern(img, 40, 12, ["", "", "..r..r..", ".RR..RR.", ".RR..RR.", "..r..r..", "", ""], {"R": r, "r": r2})
	return img


static func _enderman() -> Image:
	var img := _img(64, 32)
	var black := Color(0.07, 0.06, 0.08)
	_box(img, 0, 0, 8, 8, 8, black, 0.25)
	_box(img, 0, 16, 8, 8, 8, black, 0.25)
	_box(img, 32, 16, 8, 12, 4, black, 0.25)
	_box(img, 56, 0, 2, 30, 2, black, 0.25)
	var outer := _glow(Color(0.8, 0.25, 0.92))
	var inner := _glow(Color(0.97, 0.75, 1.0))
	_pattern(img, 8, 8, ["", "", "", "", "oio..oio", "", "", ""], {"o": outer, "i": inner})
	# Те же глаза на нижней челюсти (видны, когда пасть раскрыта).
	_pattern(img, 8, 24, ["", "", "", "", "oio..oio", "", "", ""], {"o": outer, "i": inner})
	return img


static func _pig() -> Image:
	var img := _img(64, 32)
	var pink := Color(0.94, 0.65, 0.63)
	_box(img, 0, 0, 8, 8, 8, pink, 0.05)
	_pattern(img, 8, 8, ["", "", "", "WK....KW", "", "", "", ""], {"W": Color(1, 1, 1), "K": Color(0.08, 0.05, 0.05)})
	_box(img, 16, 16, 4, 3, 1, Color(0.98, 0.76, 0.74), 0.03)
	_pattern(img, 17, 17, ["....", "q..q", "...."], {"q": Color(0.6, 0.33, 0.34)})
	_box(img, 28, 8, 10, 16, 8, pink, 0.05)
	_rect(img, 36, 8, 10, 8, Color(0.97, 0.7, 0.68), 0.04)
	_box(img, 0, 16, 4, 6, 4, pink, 0.05)
	_rect(img, 0, 25, 16, 1, Color(0.7, 0.42, 0.42), 0.05)
	return img


## Свинья с седлом: седло и ремни на спине (грань «зад» туловища смотрит вверх).
static func _pig_saddle() -> Image:
	var img := _pig()
	var leather := Color(0.45, 0.27, 0.12)
	var back := _face(28, 8, 10, 16, 8, "back")
	_rect(img, back.position.x, back.position.y + 5, 10, 6, leather, 0.08)
	_rect(img, back.position.x + 2, back.position.y + 6, 6, 4, leather.lightened(0.15), 0.06)
	for f in ["right", "left"]:
		var r := _face(28, 8, 10, 16, 8, f)
		_rect(img, r.position.x, r.position.y + 6, r.size.x, 2, Color(0.3, 0.18, 0.08), 0.06)
		_rect(img, r.position.x + 3, r.position.y + 6, 2, 2, Color(0.7, 0.7, 0.72), 0.04)
	return img


static func _cow(base: Color, patch: Color) -> Image:
	var img := _img(64, 32)
	_box(img, 0, 0, 8, 8, 6, base, 0.08)
	# Белые пятна на голове и морде.
	_rect(img, 9, 6, 6, 8, patch, 0.04)
	_rect(img, 6, 0, 8, 6, base, 0.08)
	_pattern(img, 6, 6, ["", "", "", "WK....KW", "", "", "nnnnnnnn", "nqnnnnqn"],
		{"W": Color(1, 1, 1), "K": Color(0.05, 0.05, 0.05), "n": Color(0.78, 0.72, 0.68), "q": Color(0.3, 0.25, 0.22)})
	_box(img, 22, 0, 1, 3, 1, Color(0.85, 0.82, 0.74), 0.04)
	_box(img, 52, 0, 4, 6, 1, Color(0.95, 0.68, 0.68), 0.04)
	_box(img, 18, 4, 12, 18, 10, base, 0.08)
	# Пятна на туловище.
	for i in 7:
		var px := 18 + _rng.randi_range(0, 38)
		var py := 6 + _rng.randi_range(0, 20)
		_rect(img, px, py, _rng.randi_range(3, 7), _rng.randi_range(2, 5), patch, 0.04)
	_box(img, 0, 16, 4, 12, 4, base, 0.08)
	_rect(img, 0, 22, 16, 4, patch, 0.04)
	_rect(img, 0, 30, 16, 2, Color(0.3, 0.27, 0.25), 0.05)
	return img


static func _sheep() -> Image:
	var img := _img(64, 32)
	var skin := Color(0.84, 0.74, 0.68)
	var face := Color(0.86, 0.8, 0.72)
	_box(img, 0, 0, 6, 6, 8, face, 0.04)
	_pattern(img, 8, 8, ["", "WK..KW", "", "..qq..", "..pp..", ""],
		{"W": Color(1, 1, 1), "K": Color(0.08, 0.06, 0.06), "q": Color(0.65, 0.55, 0.5), "p": Color(0.9, 0.62, 0.62)})
	_box(img, 28, 8, 8, 16, 6, skin, 0.05)
	_box(img, 0, 16, 4, 12, 4, skin, 0.05)
	_rect(img, 0, 30, 16, 2, Color(0.45, 0.4, 0.36), 0.05)
	return img


static func _sheep_wool() -> Image:
	var img := _img(64, 32)
	var w := Color(0.97, 0.96, 0.94)
	_box(img, 0, 0, 6, 6, 6, w, 0.07)
	_box(img, 28, 8, 8, 16, 6, w, 0.07)
	_box(img, 0, 16, 4, 6, 4, w, 0.07)
	# Завитки шерсти.
	for i in 140:
		_px(img, _rng.randi_range(0, 63), _rng.randi_range(0, 31), Color(0.86, 0.85, 0.83))
	var clean := _img(64, 32)
	for rect: Rect2i in [Rect2i(6, 0, 12, 6), Rect2i(0, 6, 24, 6), Rect2i(34, 8, 16, 6), Rect2i(28, 14, 28, 16),
			Rect2i(4, 16, 8, 4), Rect2i(0, 20, 16, 6)]:
		clean.blit_rect(img, rect, rect.position)
	return clean


static func _chicken() -> Image:
	var img := _img(64, 32)
	var white := Color(0.97, 0.97, 0.96)
	_box(img, 0, 0, 4, 6, 3, white, 0.03)
	_pattern(img, 3, 3, ["", "", "K..K", "", "", ""], {"K": Color(0.05, 0.05, 0.05)})
	_box(img, 14, 0, 4, 2, 2, Color(0.96, 0.72, 0.18), 0.05)
	_box(img, 14, 4, 2, 2, 2, Color(0.86, 0.1, 0.08), 0.05)
	_box(img, 0, 9, 6, 8, 6, white, 0.04)
	_box(img, 26, 0, 3, 5, 3, Color(0.95, 0.66, 0.18), 0.05)
	_box(img, 24, 13, 1, 4, 6, Color(0.93, 0.93, 0.92), 0.04)
	return img


static func _squid() -> Image:
	var img := _img(64, 32)
	var c := Color(0.2, 0.31, 0.42)
	_box(img, 0, 0, 12, 16, 12, c, 0.1)
	var f := _face(0, 0, 12, 16, 12, "front")
	_rect(img, f.position.x, f.position.y + 8, 12, 8, Color(0.3, 0.42, 0.52), 0.08)
	_pattern(img, f.position.x, f.position.y + 9, ["..WW....WW..", "..WK....KW.."],
		{"W": Color(0.85, 0.88, 0.85), "K": Color(0.05, 0.1, 0.08)})
	_box(img, 48, 0, 2, 18, 2, c, 0.1)
	_rect(img, 48, 16, 8, 4, Color(0.3, 0.4, 0.5), 0.08)
	return img


## Волк: 0 — дикий, 1 — приручённый (красный ошейник), 2 — злой (красные глаза).
static func _wolf(kind: int) -> Image:
	var img := _img(64, 32)
	var fur := Color(0.84, 0.82, 0.79)
	var back := Color(0.62, 0.6, 0.57)
	_box(img, 0, 0, 6, 6, 4, fur, 0.05)
	_rect(img, 4, 0, 6, 4, back, 0.06)
	var eye := Color(0.08, 0.07, 0.07)
	if kind == 2:
		eye = _glow(Color(0.9, 0.1, 0.1))
	_pattern(img, 4, 4, ["......", "......", "WK..KW", "......", "", ""], {"W": Color(0.95, 0.95, 0.95) if kind != 2 else eye, "K": eye})
	if kind == 2:
		_pattern(img, 4, 4, ["......", "KK..KK", "", "", "", ""], {"K": Color(0.25, 0.22, 0.2)})
	_box(img, 16, 14, 2, 2, 1, back, 0.05)
	_box(img, 0, 10, 3, 3, 4, Color(0.9, 0.88, 0.85), 0.04)
	_rect(img, 4, 14, 3, 1, Color(0.08, 0.07, 0.07), 0.05)
	_box(img, 18, 14, 6, 9, 6, fur, 0.05)
	_rect(img, 24, 14, 6, 6, back, 0.06)
	_box(img, 21, 0, 8, 6, 7, fur, 0.05)
	_rect(img, 28, 0, 8, 7, back, 0.06)
	if kind == 1:
		_rect(img, 21, 7, 30, 2, Color(0.75, 0.08, 0.08), 0.05)
		_rect(img, 28, 0, 8, 2, Color(0.75, 0.08, 0.08), 0.05)
	_box(img, 0, 18, 2, 8, 2, fur, 0.05)
	_box(img, 9, 18, 2, 8, 2, fur, 0.05)
	_rect(img, 9, 20, 8, 2, back, 0.05)
	return img


## Оцелот и кошки: 0 — оцелот, 1 — чёрная, 2 — рыжая, 3 — сиамская.
static func _ocelot(kind: int) -> Image:
	var img := _img(64, 32)
	var base: Color = [Color(0.92, 0.79, 0.42), Color(0.1, 0.1, 0.12), Color(0.9, 0.55, 0.2), Color(0.93, 0.87, 0.76)][kind]
	var spot: Color = [Color(0.45, 0.3, 0.14), Color(0.16, 0.16, 0.19), Color(0.72, 0.36, 0.1), Color(0.33, 0.22, 0.16)][kind]
	var eye: Color = [Color(0.35, 0.8, 0.2), Color(0.85, 0.8, 0.15), Color(0.3, 0.75, 0.2), Color(0.25, 0.55, 0.95)][kind]
	# Голова, нос, уши.
	_box(img, 0, 0, 5, 4, 5, base, 0.05)
	_box(img, 0, 24, 3, 2, 2, base.lightened(0.15), 0.04)
	_px(img, 3, 26, Color(0.85, 0.5, 0.5) if kind != 1 else Color(0.3, 0.2, 0.2))
	_box(img, 0, 10, 1, 1, 2, base, 0.05)
	_box(img, 6, 10, 1, 1, 2, base, 0.05)
	_pattern(img, 5, 5, ["", "e...e", "", ""], {"e": eye})
	# Тело, хвост, лапы.
	_box(img, 20, 0, 4, 16, 6, base, 0.05)
	_box(img, 0, 15, 1, 8, 1, base, 0.05)
	_box(img, 4, 15, 1, 8, 1, base, 0.05)
	_box(img, 8, 13, 2, 6, 2, base, 0.05)
	_box(img, 40, 0, 2, 10, 2, base, 0.05)
	match kind:
		0, 2:
			# Пятна или полосы.
			for i in 26:
				_rect(img, 20 + _rng.randi_range(0, 18), _rng.randi_range(0, 21), 2 if kind == 0 else 3, 1, spot, 0.05)
			for i in 6:
				_px(img, _rng.randi_range(0, 19), _rng.randi_range(0, 8), spot)
			_rect(img, 0, 18, 8, 1, spot, 0.05)
			_rect(img, 0, 21, 8, 1, spot, 0.05)
		1:
			_rect(img, 40, 10, 8, 2, Color(0.85, 0.85, 0.85), 0.05)
			_rect(img, 8, 19, 8, 2, Color(0.85, 0.85, 0.85), 0.05)
		3:
			# Тёмные «маска», уши, лапы и хвост.
			_rect(img, 5, 5, 5, 4, spot, 0.06)
			_pattern(img, 5, 5, ["", "e...e", "", ""], {"e": eye})
			_box(img, 0, 10, 1, 1, 2, spot, 0.05)
			_box(img, 6, 10, 1, 1, 2, spot, 0.05)
			_box(img, 4, 15, 1, 8, 1, spot, 0.05)
			_rect(img, 40, 7, 8, 5, spot, 0.05)
			_rect(img, 8, 17, 8, 4, spot, 0.05)
	return img


## Житель 1.2: 0 фермер, 1 библиотекарь, 2 священник, 3 кузнец, 4 мясник.
static func _villager(prof: int) -> Image:
	var img := _img(64, 64)
	var skin := Color(0.74, 0.55, 0.43)
	var robe: Color = [Color(0.45, 0.3, 0.19), Color(0.9, 0.9, 0.87), Color(0.52, 0.18, 0.58), Color(0.2, 0.2, 0.2),
		Color(0.9, 0.9, 0.87)][clampi(prof, 0, 4)]
	var under: Color = [Color(0.45, 0.3, 0.19), Color(0.9, 0.9, 0.87), Color(0.52, 0.18, 0.58), Color(0.42, 0.4, 0.38),
		Color(0.55, 0.53, 0.5)][clampi(prof, 0, 4)]
	_box(img, 0, 0, 8, 10, 8, skin, 0.05)
	_pattern(img, 8, 8, ["", "", "", ".bbbbbb.", ".WG..GW.", "", "", "", "..mmmm..", ""],
		{"b": Color(0.3, 0.2, 0.14), "W": Color(0.95, 0.95, 0.95), "G": Color(0.1, 0.5, 0.15), "m": Color(0.45, 0.28, 0.22)})
	_box(img, 24, 0, 2, 4, 2, Color(0.7, 0.5, 0.38), 0.04)
	_box(img, 16, 20, 8, 12, 6, under, 0.05)
	_box(img, 0, 38, 8, 18, 6, robe, 0.06)
	_box(img, 44, 22, 4, 8, 4, under, 0.05)
	_box(img, 40, 38, 8, 4, 4, skin, 0.05)
	_box(img, 0, 22, 4, 12, 4, robe.darkened(0.2), 0.05)
	match prof:
		0:
			_rect(img, 6, 44, 8, 2, Color(0.35, 0.22, 0.13), 0.05)
		1:
			_rect(img, 6, 44, 8, 1, Color(0.6, 0.55, 0.3), 0.05)
		2:
			_rect(img, 9, 44, 2, 8, Color(0.85, 0.75, 0.2), 0.05)
			_rect(img, 7, 46, 6, 2, Color(0.85, 0.75, 0.2), 0.05)
		3, 4:
			# Фартук.
			var apron: Color = Color(0.15, 0.15, 0.15) if prof == 3 else Color(0.97, 0.97, 0.95)
			_rect(img, 6, 44, 8, 14, apron, 0.04)
			_rect(img, 22, 26, 8, 12, apron, 0.04)
			if prof == 4:
				for i in 5:
					_px(img, 7 + _rng.randi_range(0, 6), 46 + _rng.randi_range(0, 10), Color(0.7, 0.15, 0.12))
	return img


static func _iron_golem() -> Image:
	var img := _img(128, 128)
	var iron := Color(0.84, 0.81, 0.77)
	_box(img, 0, 0, 8, 10, 8, iron, 0.06)
	_pattern(img, 8, 8, ["", "", "", ".bbbbbb.", ".RK..KR.", "", "", "", "", ""],
		{"b": Color(0.45, 0.42, 0.38), "R": Color(0.6, 0.08, 0.05), "K": Color(0.25, 0.05, 0.03)})
	_box(img, 24, 0, 2, 4, 2, iron.darkened(0.1), 0.05)
	_box(img, 0, 40, 18, 12, 11, iron, 0.06)
	_box(img, 0, 70, 9, 5, 6, iron.darkened(0.08), 0.06)
	_box(img, 60, 21, 4, 30, 6, iron, 0.06)
	_box(img, 60, 58, 4, 30, 6, iron, 0.06)
	_box(img, 37, 0, 6, 16, 5, iron, 0.06)
	_box(img, 60, 0, 6, 16, 5, iron, 0.06)
	# Трещины и ржавчина.
	for i in 120:
		var x := _rng.randi_range(0, 85)
		var y := _rng.randi_range(0, 95)
		if img.get_pixel(x, y).a > 0.5:
			_px(img, x, y, Color(0.55, 0.52, 0.48) if i % 3 != 0 else Color(0.6, 0.38, 0.22))
	# Лианы на теле.
	var vine := Color(0.22, 0.48, 0.14)
	for i in 5:
		var x0 := 11 + _rng.randi_range(0, 17)
		var y := 51
		while y < 63:
			_px(img, x0, y, vine)
			if _rng.randi_range(0, 2) == 0:
				_px(img, x0 + 1, y, vine.lightened(0.15))
			x0 += _rng.randi_range(-1, 1)
			y += 1
	for i in 30:
		_px(img, _rng.randi_range(0, 57), _rng.randi_range(51, 62), vine)
	_rect(img, 60, 51, 20, 6, iron.darkened(0.25), 0.05)
	_rect(img, 60, 88, 20, 6, iron.darkened(0.25), 0.05)
	return img


static func _snow_golem() -> Image:
	var img := _img(64, 64)
	var orange := Color(0.86, 0.5, 0.1)
	_box(img, 0, 0, 8, 8, 8, orange, 0.05)
	for x in range(0, 32, 3):
		_rect(img, x, 8, 1, 8, orange.darkened(0.2), 0.04)
	_rect(img, 10, 2, 3, 3, Color(0.4, 0.3, 0.12), 0.05)
	_rect(img, 8, 8, 8, 8, orange, 0.05)
	_pattern(img, 8, 8, ["", ".KK..KK.", ".KK..KK.", "", ".KKKKKK.", "..K..K..", "", ""],
		{"K": Color(0.18, 0.09, 0.02)})
	_box(img, 32, 0, 12, 2, 2, Color(0.4, 0.27, 0.13), 0.06)
	var snow := Color(0.95, 0.97, 0.99)
	_box(img, 0, 16, 10, 10, 10, snow, 0.025)
	_box(img, 0, 36, 12, 12, 12, snow, 0.025)
	return img


static func _slime() -> Image:
	var img := _img(64, 32)
	var outer := Color(0.47, 0.78, 0.37, 0.55)
	_box(img, 0, 0, 8, 8, 8, outer, 0.05)
	for f in ["front", "back", "left", "right", "top", "bottom"]:
		var r := _face(0, 0, 8, 8, 8, f)
		for i in r.size.x:
			_px(img, r.position.x + i, r.position.y, Color(0.55, 0.85, 0.45, 0.8))
			_px(img, r.position.x + i, r.end.y - 1, Color(0.4, 0.7, 0.32, 0.8))
		for j in r.size.y:
			_px(img, r.position.x, r.position.y + j, Color(0.55, 0.85, 0.45, 0.8))
			_px(img, r.end.x - 1, r.position.y + j, Color(0.4, 0.7, 0.32, 0.8))
	_box(img, 0, 16, 6, 6, 6, Color(0.36, 0.66, 0.28), 0.06)
	_box(img, 32, 0, 2, 2, 2, Color(0.08, 0.14, 0.06), 0.05)
	_box(img, 32, 4, 2, 2, 2, Color(0.08, 0.14, 0.06), 0.05)
	_box(img, 32, 8, 1, 1, 1, Color(0.1, 0.18, 0.08), 0.05)
	return img


static func _magma_cube() -> Image:
	var img := _img(64, 64)
	var dark := Color(0.24, 0.05, 0.03)
	for i in 8:
		var u := 0 if i < 4 else 32
		var v := (i % 4) * 9
		_box(img, u, v, 8, 1, 8, dark, 0.2)
		var f := _face(u, v, 8, 1, 8, "front")
		for k in 6:
			var x := u + _rng.randi_range(0, 31)
			var y := v + 8
			_px(img, x, y, _glow(Color(1.0, 0.55 + _rng.randf() * 0.3, 0.1)))
		for k in 10:
			_px(img, u + 8 + _rng.randi_range(0, 7), v + _rng.randi_range(0, 7), _glow(Color(0.95, 0.45, 0.05)))
		if i == 2 or i == 3:
			_px(img, f.position.x + 1, f.position.y, _glow(Color(1.0, 0.85, 0.2)))
			_px(img, f.position.x + 2, f.position.y, _glow(Color(1.0, 0.85, 0.2)))
			_px(img, f.position.x + 5, f.position.y, _glow(Color(1.0, 0.85, 0.2)))
			_px(img, f.position.x + 6, f.position.y, _glow(Color(1.0, 0.85, 0.2)))
	_box(img, 0, 40, 4, 4, 4, _glow(Color(1.0, 0.6, 0.12)), 0.1)
	return img


static func _ghast(fire: bool) -> Image:
	var img := _img(64, 32)
	_box(img, 0, 0, 16, 16, 16, Color(0.94, 0.94, 0.94), 0.03)
	_rect(img, 0, 0, 16, 16, Color(0.9, 0.9, 0.9), 0.04)
	for i in 40:
		_px(img, _rng.randi_range(0, 63), _rng.randi_range(0, 31), Color(0.82, 0.82, 0.82))
	var k := Color(0.1, 0.1, 0.1)
	var g := Color(0.62, 0.62, 0.62)
	if fire:
		var r := Color(0.75, 0.1, 0.1)
		_pattern(img, 16, 16, ["", "", "", "", "..KKK....KKK....", "..KrK....KrK....", "..KKK....KKK....", "",
			"", "", "....KKKKKK......", "....KKKKKK......", "....KKKKKK......", "", "", ""], {"K": k, "r": r})
	else:
		_pattern(img, 16, 16, ["", "", "", "", "", "..KKK....KKK....", "...g......g.....", "...g......g.....",
			"...g......g.....", "", "", ".....KKKK.......", "", "", "", ""], {"K": k, "g": g})
	return img


static func _blaze() -> Image:
	var img := _img(64, 32)
	var y := _glow(Color(0.98, 0.78, 0.22))
	var o := _glow(Color(0.92, 0.5, 0.08))
	_box(img, 0, 0, 8, 8, 8, y, 0.08)
	for i in 40:
		_px(img, _rng.randi_range(0, 31), _rng.randi_range(0, 15), o)
	_pattern(img, 8, 8, ["", "", ".KK..KK.", ".kk..kk.", "", "..KKKK..", "", ""],
		{"K": _glow(Color(0.2, 0.08, 0.02)), "k": _glow(Color(0.45, 0.2, 0.05))})
	_box(img, 0, 16, 2, 8, 2, y, 0.1)
	for i in 12:
		_px(img, _rng.randi_range(0, 7), 16 + _rng.randi_range(0, 9), o)
	return img


static func _silverfish() -> Image:
	var img := _img(64, 32)
	var c := Color(0.55, 0.56, 0.6)
	_rect(img, 0, 0, 46, 27, c, 0.1)
	for y in range(0, 27, 3):
		_rect(img, 0, y, 46, 1, c.darkened(0.25), 0.05)
	_pattern(img, 2, 2, ["K.K"], {"K": Color(0.08, 0.08, 0.1)})
	return img


static func _end_crystal() -> Image:
	var img := _img(64, 32)
	for f in ["front", "back", "left", "right", "top", "bottom"]:
		var r := _face(0, 0, 8, 8, 8, f)
		for i in r.size.x:
			_px(img, r.position.x + i, r.position.y, Color(0.85, 0.9, 0.95))
			_px(img, r.position.x + i, r.end.y - 1, Color(0.75, 0.8, 0.9))
		for j in r.size.y:
			_px(img, r.position.x, r.position.y + j, Color(0.85, 0.9, 0.95))
			_px(img, r.end.x - 1, r.position.y + j, Color(0.75, 0.8, 0.9))
	_box(img, 32, 0, 6, 6, 6, _glow(Color(0.86, 0.45, 0.9)), 0.15)
	for i in 30:
		_px(img, 32 + _rng.randi_range(0, 23), _rng.randi_range(0, 11), _glow(Color(1.0, 0.8, 1.0)))
	_box(img, 0, 16, 12, 4, 12, Color(0.32, 0.32, 0.32), 0.3)
	return img


static func _dragon() -> Image:
	var img := _img(256, 256)
	var scale := Color(0.1, 0.1, 0.11)
	img.fill(scale)
	for i in 5000:
		_px(img, _rng.randi_range(0, 255), _rng.randi_range(0, 255), _vary(scale, 0.45))
	for i in 900:
		_px(img, _rng.randi_range(0, 255), _rng.randi_range(0, 255), Color(0.18, 0.17, 0.2))
	# Перепонки крыльев: серые с прожилками.
	for r: Rect2i in [Rect2i(56, 136, 112, 56), Rect2i(56, 192, 112, 56)]:
		_rect(img, r.position.x, r.position.y, r.size.x, r.size.y, Color(0.3, 0.28, 0.33), 0.12)
		for k in 6:
			var x := r.position.x + k * 9 + 3
			for y in range(r.position.y, r.end.y):
				var dx := 1 if y % 3 == 2 else 0
				_px(img, x + dx, y, Color(0.18, 0.17, 0.2))
				_px(img, x + 56 + dx, y, Color(0.18, 0.17, 0.2))
	# Шипы светлее.
	_rect(img, 176, 0, 28, 18, Color(0.36, 0.35, 0.38), 0.1)
	_rect(img, 204, 0, 16, 10, Color(0.36, 0.35, 0.38), 0.1)
	_rect(img, 176, 18, 16, 10, Color(0.36, 0.35, 0.38), 0.1)
	# Глаза: спереди и по бокам головы (у самой морды).
	var eye := _glow(Color(0.82, 0.32, 0.95))
	var eye2 := _glow(Color(0.98, 0.78, 1.0))
	_pattern(img, 16, 104, ["", "", "", "eEEe........eEEe", "eeee........eeee"], {"e": eye, "E": eye2})
	_pattern(img, 0, 104, ["", "", "", "............eeEe", "............eeee"], {"e": eye, "E": eye2})
	_pattern(img, 32, 104, ["", "", "", "eEee", "eeee"], {"e": eye, "E": eye2})
	# Ноздри и зубы.
	_rect(img, 192, 18, 12, 6, Color(0.05, 0.05, 0.05), 0.05)
	return img
