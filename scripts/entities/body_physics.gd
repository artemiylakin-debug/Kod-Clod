class_name BodyPhysics
extends RefCounted
## Движение тела-параллелепипеда (игрок, мобы, предметы) с упором в блоки любой формы.
## Позиция — центр низа тела. Подъём на «ступеньку» до step_height (плиты, ступеньки).

const EPS := 0.001


static func body_box(pos: Vector3, half_w: float, height: float) -> AABB:
	return AABB(pos - Vector3(half_w, 0, half_w), Vector3(half_w * 2.0, height, half_w * 2.0))


static func collides(world: World, pos: Vector3, half_w: float, height: float) -> bool:
	var box := body_box(pos, half_w, height).grow(-EPS)
	return not world.collision_boxes(box).is_empty()


## Сдвигает тело на motion. Результат: {pos, hit_x, hit_y, hit_z, on_ground, stepped}.
## Каждая ось обрабатывается отдельно; при упоре по горизонтали на земле — попытка шагнуть выше.
static func move(world: World, pos: Vector3, half_w: float, height: float, motion: Vector3, step_height: float, on_ground: bool) -> Dictionary:
	var res := {"hit_x": false, "hit_y": false, "hit_z": false, "on_ground": false, "stepped": false}
	var p := pos
	# Вертикаль.
	if motion.y != 0.0:
		var r := _axis(world, p, half_w, height, 1, motion.y)
		p = r[0]
		if r[1]:
			res["hit_y"] = true
			if motion.y < 0.0:
				res["on_ground"] = true
	var grounded: bool = res["on_ground"] or (on_ground and motion.y <= 0.0)
	for axis: int in [0, 2]:
		var amount: float = motion[axis]
		if amount == 0.0:
			continue
		var r := _axis(world, p, half_w, height, axis, amount)
		if r[1] and grounded and step_height > 0.0:
			# Ступенька: поднимаемся, сдвигаемся, опускаемся обратно на опору.
			var up := p + Vector3(0, step_height, 0)
			if not collides(world, up, half_w, height):
				var r2 := _axis(world, up, half_w, height, axis, amount)
				if not r2[1] or absf((r2[0] as Vector3)[axis] - up[axis]) > absf((r[0] as Vector3)[axis] - p[axis]) + EPS:
					var down := _axis(world, r2[0], half_w, height, 1, -step_height - EPS * 2.0)
					p = down[0]
					res["stepped"] = true
					if (r2[1] as bool):
						res["hit_x" if axis == 0 else "hit_z"] = true
					continue
		p = r[0]
		if r[1]:
			res["hit_x" if axis == 0 else "hit_z"] = true
	res["pos"] = p
	return res


## Сдвиг по одной оси с упором: [новая позиция, было ли столкновение].
static func _axis(world: World, pos: Vector3, half_w: float, height: float, axis: int, amount: float) -> Array:
	var p := pos
	p[axis] += amount
	var box := body_box(p, half_w, height).grow(-EPS)
	var hits := world.collision_boxes(box)
	if hits.is_empty():
		return [p, false]
	# Упираемся в ближайшую грань среди пересечённых параллелепипедов.
	var limit: float = p[axis]
	for h in hits:
		if amount > 0.0:
			var edge := h.position[axis]
			var ext := height if axis == 1 else half_w
			limit = minf(limit, edge - ext - EPS)
		else:
			var edge := h.end[axis]
			var ext := 0.0 if axis == 1 else half_w
			limit = maxf(limit, edge + ext + EPS)
	var q := pos
	# Не двигаемся назад дальше исходной позиции (если уже были в блоке).
	if amount > 0.0:
		q[axis] = maxf(minf(limit, p[axis]), pos[axis]) if limit >= pos[axis] else pos[axis]
	else:
		q[axis] = minf(maxf(limit, p[axis]), pos[axis]) if limit <= pos[axis] else pos[axis]
	if collides(world, q, half_w, height) and not collides(world, pos, half_w, height):
		q = pos
	return [q, true]


## Есть ли опора под телом в точке pos (для приседания у края).
static func has_support(world: World, pos: Vector3, half_w: float) -> bool:
	var box := AABB(pos - Vector3(half_w, 0.1, half_w), Vector3(half_w * 2.0, 0.1, half_w * 2.0)).grow(-EPS)
	return not world.collision_boxes(box).is_empty()
