class_name GenPiece
extends RefCounted
## Часть постройки (как StructureComponent в 1.2): ориентированный параллелепипед. Рисуется в
## локальных координатах: x — поперёк, y — вверх, z — «вглубь» (вход со стороны z = 0), а
## facing (0 юг, 1 запад, 2 север, 3 восток) задаёт, куда в мире смотрит локальная ось +z.
## Запись идёт через GenChunk, поэтому часть, пересекающая несколько чанков, в каждом из них
## рисует только своё.

var kind := 0
var facing := 0
var x0 := 0
var y0 := 0
var z0 := 0
var x1 := 0
var y1 := 0
var z1 := 0
var depth := 0
## Вариант и прочие данные части (зависит от вида).
var data := 0
var seed := 0
## Уровень пола (деревни: средняя высота земли под частью; -1 — ещё не вычислен).
var ground := -1


## Часть размера sx×sy×sz, у которой локальная точка (elx, ely, 0) совпадает с мировой (ex, ey, ez).
static func make(p_kind: int, p_facing: int, ex: int, ey: int, ez: int, elx: int, ely: int, sx: int, sy: int, sz: int) -> GenPiece:
	var p := GenPiece.new()
	p.kind = p_kind
	p.facing = p_facing
	p.y0 = ey - ely
	p.y1 = p.y0 + sy - 1
	match p_facing:
		0:
			p.x0 = ex - elx
			p.z0 = ez
			p.x1 = p.x0 + sx - 1
			p.z1 = p.z0 + sz - 1
		2:
			p.x0 = ex - elx
			p.z1 = ez
			p.z0 = ez - sz + 1
			p.x1 = p.x0 + sx - 1
		1:
			p.x1 = ex
			p.x0 = ex - sz + 1
			p.z0 = ez - elx
			p.z1 = p.z0 + sx - 1
		_:
			p.x0 = ex
			p.x1 = ex + sz - 1
			p.z0 = ez - elx
			p.z1 = p.z0 + sx - 1
	return p


func size_x() -> int:
	return (x1 - x0 + 1) if facing == 0 or facing == 2 else (z1 - z0 + 1)


func size_z() -> int:
	return (z1 - z0 + 1) if facing == 0 or facing == 2 else (x1 - x0 + 1)


func wx(lx: int, lz: int) -> int:
	match facing:
		0, 2:
			return x0 + lx
		1:
			return x1 - lz
	return x0 + lz


func wz(lx: int, lz: int) -> int:
	match facing:
		0:
			return z0 + lz
		2:
			return z1 - lz
	return z0 + lx


func wy(ly: int) -> int:
	return y0 + ly


func world(lx: int, ly: int, lz: int) -> Vector3i:
	return Vector3i(wx(lx, lz), y0 + ly, wz(lx, lz))


## Мировое направление (0–3) локального направления d (0 +z, 1 −x, 2 −z, 3 +x).
func dir(d: int) -> int:
	var v: Vector3i = Blocks.DIR_VEC[d & 3]
	var w := Vector3i.ZERO
	match facing:
		0:
			w = Vector3i(v.x, 0, v.z)
		1:
			w = Vector3i(-v.z, 0, v.x)
		2:
			w = Vector3i(v.x, 0, -v.z)
		_:
			w = Vector3i(v.z, 0, v.x)
	return Blocks.DIR_VEC.find(w)


func intersects(buf: GenChunk) -> bool:
	return buf.overlaps(x0, z0, x1, z1)


## Пересечение прямоугольников по x/z (с зазором gap).
func overlaps(o: GenPiece, gap: int = 0) -> bool:
	return x1 + gap >= o.x0 and x0 - gap <= o.x1 and z1 + gap >= o.z0 and z0 - gap <= o.z1


func overlaps_box(ax: int, az: int, bx: int, bz: int) -> bool:
	return x1 >= ax and x0 <= bx and z1 >= az and z0 <= bz


func contains_xz(x: int, z: int, margin: int = 0) -> bool:
	return x >= x0 - margin and x <= x1 + margin and z >= z0 - margin and z <= z1 + margin


func put(buf: GenChunk, lx: int, ly: int, lz: int, id: int, m: int = 0) -> void:
	buf.set_b(wx(lx, lz), y0 + ly, wz(lx, lz), id, m)


func get_b(buf: GenChunk, lx: int, ly: int, lz: int) -> int:
	return buf.get_b(wx(lx, lz), y0 + ly, wz(lx, lz))


## Заливка локального параллелепипеда (включительно).
func fill(buf: GenChunk, ax: int, ay: int, az: int, bx: int, by: int, bz: int, id: int, m: int = 0) -> void:
	var px := wx(ax, az)
	var pz := wz(ax, az)
	var qx := wx(bx, bz)
	var qz := wz(bx, bz)
	buf.fill(mini(px, qx), y0 + ay, mini(pz, qz), maxi(px, qx), y0 + by, maxi(pz, qz), id, m)


## Коробка: стены, пол и потолок из id, внутри — воздух.
func box(buf: GenChunk, ax: int, ay: int, az: int, bx: int, by: int, bz: int, id: int, m: int = 0) -> void:
	fill(buf, ax, ay, az, bx, by, bz, id, m)
	if bx - ax >= 2 and by - ay >= 2 and bz - az >= 2:
		fill(buf, ax + 1, ay + 1, az + 1, bx - 1, by - 1, bz - 1, Blocks.AIR)


## Факел на стене: стена — в локальном направлении wall_dir от клетки.
func torch(buf: GenChunk, lx: int, ly: int, lz: int, wall_dir: int) -> void:
	put(buf, lx, ly, lz, Blocks.TORCH, torch_meta(dir(wall_dir)))


## Данные факела по мировому направлению на опорный блок (1 — опора с запада и т. д.).
static func torch_meta(world_wall_dir: int) -> int:
	match world_wall_dir:
		1:
			return 1
		3:
			return 2
		2:
			return 3
		0:
			return 4
	return 0


## Дверь из двух половин; facing_dir — локальное направление, куда она смотрит.
func door(buf: GenChunk, lx: int, ly: int, lz: int, id: int, facing_dir: int) -> void:
	var d := dir(facing_dir)
	put(buf, lx, ly, lz, id, d)
	put(buf, lx, ly + 1, lz, id, d | 8)


## Детерминированный хеш блока постройки (для случайных деталей, одинаковых во всех чанках).
func rnd(lx: int, ly: int, lz: int, salt: int = 0) -> int:
	return WorldGen.hash3(wx(lx, lz), y0 + ly, wz(lx, lz), seed + salt)


## Заливка вниз до твёрдого грунта (фундамент), начиная с локальной высоты ly.
func foundation(buf: GenChunk, lx: int, ly: int, lz: int, id: int) -> void:
	var x := wx(lx, lz)
	var z := wz(lx, lz)
	if not buf.contains(x, z):
		return
	var y := y0 + ly
	while y > 1:
		var b := buf.get_b(x, y, z)
		if b != Blocks.AIR and not Blocks.is_liquid(b) and b != Blocks.LEAVES and b != Blocks.TALLGRASS and b != Blocks.LOG:
			break
		buf.set_b(x, y, z, id)
		y -= 1


## Очистка столба над частью до высоты ly (деревья и снег над крышей).
func clear_above(buf: GenChunk, lx: int, ly: int, lz: int, height: int) -> void:
	var x := wx(lx, lz)
	var z := wz(lx, lz)
	if not buf.contains(x, z):
		return
	for y in range(y0 + ly, mini(y0 + ly + height, 255)):
		buf.set_b(x, y, z, Blocks.AIR)
