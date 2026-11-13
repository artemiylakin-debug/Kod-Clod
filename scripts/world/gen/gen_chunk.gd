class_name GenChunk
extends RefCounted
## Буфер генерируемого чанка: блоки, данные (meta), контейнеры и существа. Запись — в мировых
## координатах с отсечением по границам чанка: постройки, пересекающие несколько чанков,
## рассчитываются целиком, но каждый чанк записывает только свою часть.

const CS := 16
const LAYER := 256
const HEIGHT := 256

var ox := 0
var oz := 0
var cx := 0
var cz := 0
var blocks := PackedByteArray()
var meta := PackedByteArray()
var block_entities: Dictionary = {}
var entities: Array = []
## Родники (индексы блоков чанка): начинают течь после загрузки чанка и его соседей.
var springs := PackedInt32Array()


func setup(p_cx: int, p_cz: int) -> void:
	cx = p_cx
	cz = p_cz
	ox = p_cx * CS
	oz = p_cz * CS
	blocks = PackedByteArray()
	blocks.resize(LAYER * HEIGHT)
	meta = PackedByteArray()
	meta.resize(LAYER * HEIGHT)
	block_entities = {}
	entities = []


func contains(wx: int, wz: int) -> bool:
	return wx >= ox and wx < ox + CS and wz >= oz and wz < oz + CS


## Пересекается ли прямоугольник [x0..x1]×[z0..z1] (включительно) с чанком.
func overlaps(x0: int, z0: int, x1: int, z1: int) -> bool:
	return x1 >= ox and x0 < ox + CS and z1 >= oz and z0 < oz + CS


func get_b(wx: int, y: int, wz: int) -> int:
	var lx := wx - ox
	var lz := wz - oz
	if lx < 0 or lx >= CS or lz < 0 or lz >= CS or y < 0 or y >= HEIGHT:
		return -1
	return blocks[lx + (lz << 4) + (y << 8)]


func get_m(wx: int, y: int, wz: int) -> int:
	var lx := wx - ox
	var lz := wz - oz
	if lx < 0 or lx >= CS or lz < 0 or lz >= CS or y < 0 or y >= HEIGHT:
		return 0
	return meta[lx + (lz << 4) + (y << 8)]


func set_b(wx: int, y: int, wz: int, id: int, m: int = 0) -> void:
	var lx := wx - ox
	var lz := wz - oz
	if lx < 0 or lx >= CS or lz < 0 or lz >= CS or y < 0 or y >= HEIGHT:
		return
	var i := lx + (lz << 4) + (y << 8)
	blocks[i] = id
	meta[i] = m
	if not block_entities.is_empty() and block_entities.has(i):
		block_entities.erase(i)


## Ставит блок только в пустоту (или в заменяемые растения/снег).
func set_if_air(wx: int, y: int, wz: int, id: int, m: int = 0) -> void:
	var lx := wx - ox
	var lz := wz - oz
	if lx < 0 or lx >= CS or lz < 0 or lz >= CS or y < 0 or y >= HEIGHT:
		return
	var i := lx + (lz << 4) + (y << 8)
	var cur := blocks[i]
	if cur == Blocks.AIR or cur == Blocks.TALLGRASS or cur == Blocks.SNOW_LAYER:
		blocks[i] = id
		meta[i] = m


## Заливка параллелепипеда (мировые координаты, включительно), обрезанного по чанку.
func fill(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, id: int, m: int = 0) -> void:
	var ax := maxi(mini(x0, x1), ox)
	var bx := mini(maxi(x0, x1), ox + CS - 1)
	var az := maxi(mini(z0, z1), oz)
	var bz := mini(maxi(z0, z1), oz + CS - 1)
	var ay := maxi(mini(y0, y1), 0)
	var by := mini(maxi(y0, y1), HEIGHT - 1)
	if ax > bx or az > bz or ay > by:
		return
	var b := blocks
	var mt := meta
	for y in range(ay, by + 1):
		for z in range(az, bz + 1):
			var row := ((z - oz) << 4) + (y << 8) - ox
			for x in range(ax, bx + 1):
				b[row + x] = id
				mt[row + x] = m


func add_chest(wx: int, y: int, wz: int, facing: int, items: Array) -> void:
	if not contains(wx, wz) or y < 0 or y >= HEIGHT:
		return
	set_b(wx, y, wz, Blocks.CHEST, facing & 3)
	block_entities[(wx - ox) + ((wz - oz) << 4) + (y << 8)] = {"items": items}


func add_spawner(wx: int, y: int, wz: int, mob: int) -> void:
	if not contains(wx, wz) or y < 0 or y >= HEIGHT:
		return
	set_b(wx, y, wz, Blocks.SPAWNER, 0)
	block_entities[(wx - ox) + ((wz - oz) << 4) + (y << 8)] = {"mob": mob}


## Существо в мировых координатах (добавляется, только если точка в этом чанке).
func add_mob(type: int, x: float, y: float, z: float) -> void:
	if not contains(floori(x), floori(z)):
		return
	entities.append({"kind": "mob", "type": type, "pos": [x, y, z]})


## Верхний слой (y), в котором есть хоть один непустой блок, начиная с from_y и ниже.
func top_layer(from_y: int) -> int:
	var y := mini(from_y, HEIGHT - 1)
	while y > 0 and blocks.slice(y << 8, (y + 1) << 8).count(Blocks.AIR) == LAYER:
		y -= 1
	return y


## Верхний непустой блок колонки (или -1).
func top_y(wx: int, wz: int, from_y: int = HEIGHT - 1) -> int:
	var lx := wx - ox
	var lz := wz - oz
	if lx < 0 or lx >= CS or lz < 0 or lz >= CS:
		return -1
	var col := lx + (lz << 4)
	var y := mini(from_y, HEIGHT - 1)
	while y > 0 and blocks[col + (y << 8)] == Blocks.AIR:
		y -= 1
	return y
