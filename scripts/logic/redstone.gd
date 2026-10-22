class_name Redstone
extends RefCounted
## Красная пыль и механизмы Minecraft 1.2 (вызывается из BlockLogic, 20 игровых тиков в секунду):
## провода (заряд 0–15 в meta), красные факелы-инверторы с перегоранием, повторители
## (задержка 1–4, однонаправленные, без блокировки — её нет в 1.2), рычаги, кнопки, нажимные
## плиты, лампы (1.2: включаются сразу, гаснут через 4 тика), поршни (см. Pistons), двери, люки,
## калитки, динамит, раздатчики, нотные блоки и энергорельсы.
##
## Сигнал, как в 1.2:
## - «слабый» — компонент питает соседнюю клетку (механизм рядом, провод рядом);
## - «сильный» — компонент запитывает непрозрачный блок (рычаг — блок, на котором висит; факел —
##   блок над собой; провод — блок под собой и блок, в который «смотрит»; повторитель — блок
##   перед собой; плита — блок под собой), и этот блок питает всех своих соседей. Блок,
##   запитанный только проводом, не питает другие провода.
##
## Обработка без рекурсии: изменения ставят позиции в очередь, а сеть проводов пересчитывается
## целиком одним обходом в ширину (заряд = 15 − расстояние до источника). Заряды проводов
## пишутся в мир без уведомлений, затем пересчитываются механизмы рядом с изменившимися проводами.

## Роль блока в схемах.
enum {
	K_NONE, K_WIRE, K_TORCH_ON, K_TORCH_OFF, K_REPEATER_OFF, K_REPEATER_ON, K_LEVER, K_BUTTON, K_PLATE,
	K_LAMP_OFF, K_LAMP_ON, K_PISTON, K_PISTON_HEAD, K_DOOR, K_TRAPDOOR, K_GATE, K_TNT, K_DISPENSER,
	K_NOTE, K_POWERED_RAIL, K_DETECTOR_RAIL,
}

## Задержки в игровых тиках.
const TORCH_DELAY := 2
const LAMP_OFF_DELAY := 4
const BUTTON_TICKS := 20
const PLATE_TICKS := 20
const DISPENSER_DELAY := 4
## Перегорание факела: столько выключений за окно (в тиках) — и факел гаснет на время.
const BURNOUT_COUNT := 8
const BURNOUT_WINDOW := 60
## Энергорельсы передают питание по цепочке не дальше стольких рельсов.
const RAIL_CHAIN := 8
## Предохранитель от бесконечных цепочек в одном тике: остаток переносится на следующий.
const MAX_STEPS := 20000

const UP := Vector3i(0, 1, 0)
const DOWN := Vector3i(0, -1, 0)
## Грань (0 +X, 1 −X, 2 +Y, 3 −Y, 4 +Z, 5 −Z) → горизонтальное направление 0–3 (−1 — вертикаль).
const FACE_DIR := [3, 1, -1, -1, 0, 2]

static var kinds := PackedByteArray()
## 1 — пересчитывается при изменениях рядом (механизм, факел, повторитель…), 2 — провод.
static var _eval := PackedByteArray()
## К чему тянется провод: 1 — всегда, 2 — повторитель (только вдоль его оси).
static var _link := PackedByteArray()
## Смещения клеток на расстоянии до 2 шагов по граням (25 клеток): соседи и соседи соседей.
static var _region: Array[Vector3i] = []
## Те же смещения как разница индексов в массиве блоков чанка.
static var _region_index := PackedInt32Array()
static var _faces: Array[Vector3i] = []
## Смещение индекса в массиве блоков чанка для каждой грани и горизонтального направления.
static var _face_index := PackedInt32Array()
static var _dir_index := PackedInt32Array()
## Источники сигнала (без проводов и с проводами) — быстрый отсев перед проверкой правил.
static var _src_nowire := PackedByteArray()
static var _src_all := PackedByteArray()
static var _dirs: Array[Vector3i] = []

var logic: BlockLogic
var world: World
var pistons: Pistons

## Очередь позиций на пересчёт (без дублей) и провода, чьи сети нужно пересчитать.
var _queue: Array[Vector3i] = []
var _head := 0
var _queued: Dictionary = {}
var _wire_dirty: Dictionary = {}
var _carry: Array[Vector3i] = []
var _busy := false
## Механизмы, срабатывающие по фронту сигнала (двери, люки, калитки): позиция → true, пока запитаны.
var _last_power: Dictionary = {}
## Выключения факелов за последние BURNOUT_WINDOW тиков: позиция → PackedInt32Array тиков.
var _burnout: Dictionary = {}
## Нажимные плиты в загруженных чанках и тик, до которого плита остаётся нажатой.
var _plates: Dictionary = {}
var _plate_until: Dictionary = {}
var _plates_box := AABB()
var _plates_box_dirty := true
## Компоненты чанков, загруженных с диска: ключ чанка → позиции (проверяются, когда загрузятся соседи).
var _revalidate: Dictionary = {}


static func _static_init() -> void:
	kinds.resize(Blocks.COUNT)
	_eval.resize(Blocks.COUNT)
	_link.resize(Blocks.COUNT)
	var table := {
		Blocks.REDSTONE_WIRE: K_WIRE, Blocks.REDSTONE_TORCH: K_TORCH_ON, Blocks.REDSTONE_TORCH_OFF: K_TORCH_OFF,
		Blocks.REPEATER_OFF: K_REPEATER_OFF, Blocks.REPEATER_ON: K_REPEATER_ON, Blocks.LEVER: K_LEVER,
		Blocks.STONE_BUTTON: K_BUTTON, Blocks.STONE_PLATE: K_PLATE, Blocks.WOODEN_PLATE: K_PLATE,
		Blocks.REDSTONE_LAMP: K_LAMP_OFF, Blocks.LIT_REDSTONE_LAMP: K_LAMP_ON, Blocks.PISTON: K_PISTON,
		Blocks.STICKY_PISTON: K_PISTON, Blocks.PISTON_HEAD: K_PISTON_HEAD, Blocks.WOODEN_DOOR: K_DOOR,
		Blocks.IRON_DOOR: K_DOOR, Blocks.TRAPDOOR: K_TRAPDOOR, Blocks.FENCE_GATE: K_GATE, Blocks.TNT: K_TNT,
		Blocks.DISPENSER: K_DISPENSER, Blocks.NOTE_BLOCK: K_NOTE, Blocks.POWERED_RAIL: K_POWERED_RAIL,
		Blocks.DETECTOR_RAIL: K_DETECTOR_RAIL,
	}
	for id: int in table:
		var k: int = table[id]
		kinds[id] = k
		if k == K_WIRE:
			_eval[id] = 2
		elif k not in [K_LEVER, K_BUTTON, K_PLATE, K_PISTON_HEAD, K_DETECTOR_RAIL]:
			_eval[id] = 1
	for id: int in [Blocks.REDSTONE_WIRE, Blocks.REDSTONE_TORCH, Blocks.REDSTONE_TORCH_OFF, Blocks.LEVER,
			Blocks.STONE_BUTTON, Blocks.STONE_PLATE, Blocks.WOODEN_PLATE, Blocks.DETECTOR_RAIL]:
		_link[id] = 1
	_link[Blocks.REPEATER_OFF] = 2
	_link[Blocks.REPEATER_ON] = 2
	for f in 6:
		var v: Vector3i = Blocks.FACE_VEC[f]
		_faces.append(v)
		_face_index.append(v.x + v.z * WorldGen.CHUNK_SIZE + v.y * WorldGen.LAYER)
	for d in 4:
		var v: Vector3i = Blocks.DIR_VEC[d]
		_dirs.append(v)
		_dir_index.append(v.x + v.z * WorldGen.CHUNK_SIZE)
	_src_nowire.resize(Blocks.COUNT)
	_src_all.resize(Blocks.COUNT)
	for id: int in [Blocks.LEVER, Blocks.STONE_BUTTON, Blocks.STONE_PLATE, Blocks.WOODEN_PLATE, Blocks.REDSTONE_TORCH,
			Blocks.REPEATER_ON]:
		_src_nowire[id] = 1
		_src_all[id] = 1
	_src_all[Blocks.REDSTONE_WIRE] = 1
	for dy in range(-2, 3):
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if absi(dx) + absi(dy) + absi(dz) <= 2:
					_region.append(Vector3i(dx, dy, dz))
					_region_index.append(dx + dz * WorldGen.CHUNK_SIZE + dy * WorldGen.LAYER)


func _init(p_logic: BlockLogic) -> void:
	logic = p_logic
	world = logic.world
	pistons = Pistons.new(self)
	if world != null:
		world.chunk_loaded.connect(_on_chunk_loaded)
		world.chunk_unloading.connect(_on_chunk_unloading)
		# Чанки, загруженные до создания (тесты): только реестр плит.
		for ch: Chunk in world.chunks.values():
			_scan_chunk(ch, false)


# --- Вызовы из BlockLogic --------------------------------------------------

func on_tick() -> void:
	_busy = true
	pistons.on_tick()
	if not _carry.is_empty():
		for p in _carry:
			_enqueue(p)
		_carry.clear()
	if not _plates.is_empty():
		_tick_plates()
	if not _revalidate.is_empty():
		_tick_revalidate()
	if logic.tick % 200 == 0 and not _burnout.is_empty():
		_prune_burnout()
	_busy = false
	_flush()


func on_block_changed(p: Vector3i, old: int, old_meta: int, id: int, meta: int) -> void:
	var ko := kinds[old]
	var kn := kinds[id]
	# Изменение, не затрагивающее ни компонентов, ни проводимости (вода, растения…), пропускаем.
	if ko == K_NONE and kn == K_NONE and Blocks.is_opaque(old) == Blocks.is_opaque(id):
		return
	if not pistons.moving:
		if ko == K_PISTON_HEAD and kn != K_PISTON_HEAD:
			pistons.head_removed(p, old_meta)
		elif ko == K_PISTON and old_meta & 8 and id != old:
			pistons.base_removed(p, old_meta)
	if ko == K_PLATE and kn != K_PLATE:
		_plates.erase(p)
		_plate_until.erase(p)
		_plates_box_dirty = true
	elif kn == K_PLATE and ko != K_PLATE:
		_plates[p] = true
		_plates_box_dirty = true
	# Нажатая плита держится не меньше секунды (даже если нажата не существом).
	if kn == K_PLATE and meta & 1 and not (ko == K_PLATE and old_meta & 1):
		_plate_until[p] = maxi(int(_plate_until.get(p, 0)), logic.tick + PLATE_TICKS)
	if kn == K_NONE:
		_last_power.erase(p)
	if (ko == K_TORCH_ON or ko == K_TORCH_OFF) and kn != K_TORCH_ON and kn != K_TORCH_OFF:
		_burnout.erase(p)
	if kn == K_BUTTON and meta & 8 and not (ko == K_BUTTON and old_meta & 8):
		logic.schedule(p, BUTTON_TICKS)
	_notify_region(p, true)
	_flush()


## Соседи изменившегося блока уже учтены в on_block_changed (окрестность в 2 клетки).
func on_neighbor_changed(_p: Vector3i, _from: Vector3i) -> void:
	pass


func on_scheduled(p: Vector3i, id: int) -> void:
	_busy = true
	_scheduled(p, id)
	_busy = false
	_flush()


## Получает ли блок в p заряд (от рычага, кнопки, плиты, факела, повторителя, провода или
## запитанного блока рядом) — как World.isBlockIndirectlyGettingPowered в 1.2.
func is_powered(p: Vector3i) -> bool:
	return _powered(p, true)


## Сильно запитан ли (непрозрачный) блок в p — от него питаются все соседи.
func is_strongly_powered(p: Vector3i) -> bool:
	return _strongly_powered(p, true)


## Заряд провода в p (0–15) или 0, если там не провод.
func wire_power(p: Vector3i) -> int:
	return world.get_meta_v(p) if world.get_block_v(p) == Blocks.REDSTONE_WIRE else 0


# --- Очередь ---------------------------------------------------------------

func _enqueue(p: Vector3i) -> void:
	if _queued.has(p):
		return
	_queued[p] = true
	_queue.append(p)


## Ставит в очередь компоненты в окрестности p (до 2 шагов по граням): так учитываются и блоки,
## запитанные через соседний непрозрачный блок. wires — помечать ли провода для пересчёта сетей.
func _notify_region(p: Vector3i, wires: bool) -> void:
	var lx := p.x & 15
	var lz := p.z & 15
	if lx >= 2 and lx <= 13 and lz >= 2 and lz <= 13 and p.y >= 2 and p.y < World.CH - 2:
		# Вся окрестность в одном чанке: читаем массив блоков напрямую (самый частый случай).
		var ch: Chunk = world.chunks.get(Vector2i(p.x >> 4, p.z >> 4))
		if ch == null:
			return
		var blocks := ch.blocks
		var base := Chunk.index_of(lx, p.y, lz)
		for k in _region.size():
			var e := _eval[blocks[base + _region_index[k]]]
			if e == 0:
				continue
			if e == 1:
				_enqueue(p + _region[k])
			elif wires:
				_wire_dirty[p + _region[k]] = true
		return
	for o in _region:
		var q := p + o
		var e := _eval[world.get_block_v(q)]
		if e == 1:
			_enqueue(q)
		elif e == 2 and wires:
			_wire_dirty[q] = true


func _flush() -> void:
	if _busy:
		return
	_busy = true
	var steps := 0
	while true:
		if not _wire_dirty.is_empty():
			_update_wires()
			continue
		if _head >= _queue.size():
			break
		var p := _queue[_head]
		_head += 1
		_queued.erase(p)
		steps += 1
		if steps > MAX_STEPS:
			_carry.append(p)
			continue
		_update(p)
	_queue.clear()
	_queued.clear()
	_head = 0
	_busy = false


## Пересчёт компонента в p после изменений рядом.
func _update(p: Vector3i) -> void:
	var id := world.get_block_v(p)
	match kinds[id]:
		K_WIRE:
			_wire_dirty[p] = true
		K_TORCH_ON, K_TORCH_OFF:
			var want_on := not _torch_input(p)
			if want_on != (id == Blocks.REDSTONE_TORCH):
				logic.schedule(p, TORCH_DELAY)
		K_REPEATER_OFF, K_REPEATER_ON:
			var m := world.get_meta_v(p)
			if _repeater_input(p, m) != (id == Blocks.REPEATER_ON):
				logic.schedule(p, repeater_delay(m))
		K_LAMP_OFF:
			if _powered(p, true):
				world.set_block_v(p, Blocks.LIT_REDSTONE_LAMP, 0)
		K_LAMP_ON:
			if not _powered(p, true):
				logic.schedule(p, LAMP_OFF_DELAY)
		K_PISTON:
			pistons.update(p)
		K_DOOR:
			_update_door(p, id)
		K_TRAPDOOR, K_GATE:
			var powered := _powered(p, true)
			if _edge(p, powered):
				var m := world.get_meta_v(p)
				if (m & 4 != 0) != powered:
					world.set_block_v(p, id, m ^ 4)
		K_TNT:
			if _powered(p, true):
				logic.ignite_tnt(p)
		K_DISPENSER:
			var be := world.get_block_entity(p)
			var powered := _powered(p, true) or _powered(p + UP, true)
			if bool(be.get("powered", false)) != powered:
				be["powered"] = powered
				world.mark_dirty(p)
				if powered:
					logic.schedule(p, DISPENSER_DELAY)
		K_NOTE:
			var be := world.get_block_entity(p)
			var powered := _powered(p, true)
			if bool(be.get("powered", false)) != powered:
				be["powered"] = powered
				world.mark_dirty(p)
				if powered and logic.game != null and logic.game.has_method("play_note"):
					logic.game.call("play_note", p, int(be.get("note", 0)))
		K_POWERED_RAIL:
			_update_rail(p)


func _scheduled(p: Vector3i, id: int) -> void:
	var meta := world.get_meta_v(p)
	match id:
		Blocks.STONE_BUTTON:
			if meta & 8:
				world.set_block_v(p, id, meta & 7)
		Blocks.REDSTONE_TORCH:
			if _torch_input(p):
				world.set_block_v(p, Blocks.REDSTONE_TORCH_OFF, meta)
				if _record_turn_off(p):
					# Перегорел: попробуем зажечься, когда история выключений устареет.
					logic.schedule(p, BURNOUT_WINDOW + 1)
		Blocks.REDSTONE_TORCH_OFF:
			if not _torch_input(p):
				if _burnt_out(p):
					logic.schedule(p, BURNOUT_WINDOW + 1)
				else:
					world.set_block_v(p, Blocks.REDSTONE_TORCH, meta)
		Blocks.REPEATER_OFF:
			# Как в 1.2: включается в любом случае (короткий импульс удлиняется до задержки),
			# а если вход уже пропал — выключится ещё через задержку.
			world.set_block_v(p, Blocks.REPEATER_ON, meta)
			if not _repeater_input(p, meta):
				logic.schedule(p, repeater_delay(meta))
		Blocks.REPEATER_ON:
			if not _repeater_input(p, meta):
				world.set_block_v(p, Blocks.REPEATER_OFF, meta)
		Blocks.LIT_REDSTONE_LAMP:
			if not _powered(p, true):
				world.set_block_v(p, Blocks.REDSTONE_LAMP, 0)
		Blocks.DISPENSER:
			if _powered(p, true) or _powered(p + UP, true):
				logic.containers.dispense(p)
		Blocks.PISTON, Blocks.STICKY_PISTON:
			pistons.update(p)


# --- Сигнал ----------------------------------------------------------------

## Блок, к которому прикреплён рычаг, кнопка или факел (как в BlockLogic.is_supported).
static func attached_pos(p: Vector3i, meta: int) -> Vector3i:
	return p + Blocks.attach_offset(meta & 7)


## Сильный сигнал: компонент (id, meta) в q запитывает блок q + FACE_VEC[f].
func _strong_from(q: Vector3i, id: int, m: int, f: int, wires: bool) -> bool:
	match kinds[id]:
		K_LEVER, K_BUTTON:
			return m & 8 != 0 and Blocks.attach_offset(m & 7) == _faces[f]
		K_PLATE:
			return f == 3 and m & 1 != 0
		K_TORCH_ON:
			return f == 2 and Blocks.attach_offset(m & 7) != UP
		K_REPEATER_ON:
			return _dirs[m & 3] == _faces[f]
		K_WIRE:
			return wires and _wire_powers(q, m, f)
	return false


## Слабый сигнал: компонент (id, meta) в q питает соседнюю клетку q + FACE_VEC[f].
func _weak_from(q: Vector3i, id: int, m: int, f: int, wires: bool) -> bool:
	match kinds[id]:
		K_LEVER, K_BUTTON:
			return m & 8 != 0
		K_PLATE:
			return m & 1 != 0
		K_TORCH_ON:
			return Blocks.attach_offset(m & 7) != _faces[f]
		K_REPEATER_ON:
			return _dirs[m & 3] == _faces[f]
		K_WIRE:
			return wires and _wire_powers(q, m, f)
	return false


func _weak(q: Vector3i, id: int, f: int, wires: bool) -> bool:
	return _weak_from(q, id, world.get_meta_v(q), f, wires)


## Запитан ли непрозрачный блок b сильным сигналом от соседнего компонента.
func _strongly_powered(b: Vector3i, wires: bool) -> bool:
	for f in 6:
		var q := b + _faces[f]
		var id := world.get_block_v(q)
		if kinds[id] != K_NONE and _strong_from(q, id, world.get_meta_v(q), Blocks.OPPOSITE_FACE[f], wires):
			return true
	return false


## Даёт ли клетка q сигнал в соседнюю q + FACE_VEC[f]: непрозрачный блок — если сам сильно
## запитан, компонент — своим слабым сигналом.
func _provides(q: Vector3i, f: int, wires: bool) -> bool:
	var id := world.get_block_v(q)
	if Blocks.is_opaque(id):
		return _strongly_powered(q, wires)
	return kinds[id] != K_NONE and _weak(q, id, f, wires)


## Получает ли клетка p сигнал от любого соседа. wires = false — без учёта проводов
## (так провод ищет «внешние» источники).
func _powered(p: Vector3i, wires: bool) -> bool:
	var lx := p.x & 15
	var lz := p.z & 15
	if lx >= 2 and lx <= 13 and lz >= 2 and lz <= 13 and p.y >= 2 and p.y < World.CH - 2:
		# Окрестность в одном чанке: блоки и данные читаются из массивов чанка напрямую.
		var ch: Chunk = world.chunks.get(Vector2i(p.x >> 4, p.z >> 4))
		if ch == null:
			return false
		var blocks := ch.blocks
		var metas := ch.meta
		var opq := Blocks.opaque_flags
		var src := _src_all if wires else _src_nowire
		var base := Chunk.index_of(lx, p.y, lz)
		for f in 6:
			var qi := base + _face_index[f]
			var id := blocks[qi]
			if opq[id] == 1:
				for g in 6:
					var ri := qi + _face_index[g]
					var rid := blocks[ri]
					if src[rid] == 1 and _strong_from(p + _faces[f] + _faces[g], rid, metas[ri], Blocks.OPPOSITE_FACE[g], wires):
						return true
			elif src[id] == 1 and _weak_from(p + _faces[f], id, metas[qi], Blocks.OPPOSITE_FACE[f], wires):
				return true
		return false
	for f in 6:
		if _provides(p + _faces[f], Blocks.OPPOSITE_FACE[f], wires):
			return true
	return false


## Питание поршня: все стороны, кроме лицевой, и (как в 1.2) клетка над поршнем.
func piston_powered(p: Vector3i, dir: int) -> bool:
	var front := Blocks.piston_face(dir)
	for f in 6:
		if f != front and _provides(p + _faces[f], Blocks.OPPOSITE_FACE[f], true):
			return true
	return _powered(p + UP, true)


# --- Провода ---------------------------------------------------------------

## Маска соединений провода (бит d — направление DIR_VEC[d]), как в 1.2: соседний провод или
## компонент, повторитель вдоль оси, провод ступенькой выше (если над проводом не непрозрачный
## блок) или ниже (если сбоку не непрозрачный блок).
func wire_connections(q: Vector3i) -> int:
	var conn := 0
	var up_open := not Blocks.is_opaque(world.get_block_v(q + UP))
	for d in 4:
		var n := q + _dirs[d]
		var nb := world.get_block_v(n)
		var l := _link[nb]
		if l == 1 or (l == 2 and (world.get_meta_v(n) & 1) == (d & 1)):
			conn |= 1 << d
		elif Blocks.is_opaque(nb):
			if up_open and world.get_block_v(n + UP) == Blocks.REDSTONE_WIRE:
				conn |= 1 << d
		elif world.get_block_v(n + DOWN) == Blocks.REDSTONE_WIRE:
			conn |= 1 << d
	return conn


## Питает ли провод в q с зарядом meta клетку q + FACE_VEC[f]: блок под собой всегда, а сбоку —
## если провод без соединений («точка») или линия, идущая в эту сторону.
func _wire_powers(q: Vector3i, meta: int, f: int) -> bool:
	if meta <= 0 or f == 2:
		return false
	if f == 3:
		return true
	var d: int = FACE_DIR[f]
	var conn := wire_connections(q)
	if conn == 0:
		return true
	var side := (1 << ((d + 1) & 3)) | (1 << ((d + 3) & 3))
	return conn & (1 << ((d + 2) & 3)) != 0 and conn & side == 0


## Пересчёт всех помеченных сетей проводов.
func _update_wires() -> void:
	var starts := _wire_dirty.keys()
	_wire_dirty.clear()
	var done: Dictionary = {}
	for s: Vector3i in starts:
		if not done.has(s) and world.get_block_v(s) == Blocks.REDSTONE_WIRE:
			_solve_network(s, done)
	# Провода рядом с изменением могли сменить направление (новое соединение) при том же заряде.
	for s: Vector3i in starts:
		if world.get_block_v(s) == Blocks.REDSTONE_WIRE:
			_notify_region(s, false)


## Сеть проводов, связанную с s: обход в ширину, затем заряды от источников (15 − расстояние).
## Связь направленная, как в 1.2: провод читает заряд соседа на том же уровне, провода
## ступенькой выше (через непрозрачный блок, если над ним самим не непрозрачный) и ниже (если сбоку
## не непрозрачный блок) — поэтому по прозрачным блокам сигнал идёт вверх, но не вниз.
func _solve_network(s: Vector3i, done: Dictionary) -> void:
	var opq := Blocks.opaque_flags
	var nodes: Array[Vector3i] = [s]
	var index: Dictionary = {s: 0}
	var reads: Array[PackedInt32Array] = []
	var head := 0
	while head < nodes.size():
		var w := nodes[head]
		head += 1
		var r := PackedInt32Array()
		# Внутри чанка (не у края) блоки читаются из массива напрямую.
		var lx := w.x & 15
		var lz := w.z & 15
		var ch: Chunk = world.chunks.get(Vector2i(w.x >> 4, w.z >> 4))
		var fast := ch != null and lx >= 1 and lx <= 14 and lz >= 1 and lz <= 14 and w.y >= 1 and w.y < World.CH - 1
		var blocks: PackedByteArray = ch.blocks if fast else PackedByteArray()
		var bi := Chunk.index_of(lx, w.y, lz)
		var up_id: int = blocks[bi + WorldGen.LAYER] if fast else world.get_block_v(w + UP)
		var up_open := opq[up_id] == 0
		for d in 4:
			var n := w + _dirs[d]
			var ni := bi + _dir_index[d]
			var nb: int = blocks[ni] if fast else world.get_block_v(n)
			if nb == Blocks.REDSTONE_WIRE:
				r.append(_node(n, nodes, index))
				continue
			var n_opaque := opq[nb] == 1
			if up_open:
				var ub: int = blocks[ni + WorldGen.LAYER] if fast else world.get_block_v(n + UP)
				if ub == Blocks.REDSTONE_WIRE:
					# Провод выше: он читает нас всегда (над нами открыто), мы его — через непрозрачный блок.
					var iu := _node(n + UP, nodes, index)
					if n_opaque:
						r.append(iu)
			if not n_opaque:
				var vb: int = blocks[ni - WorldGen.LAYER] if fast else world.get_block_v(n + DOWN)
				if vb == Blocks.REDSTONE_WIRE:
					r.append(_node(n + DOWN, nodes, index))
		reads.append(r)
	# Обратные связи «кто читает узел j» в плоском виде: outs[start[j] .. start[j + 1]).
	var count := nodes.size()
	var start := PackedInt32Array()
	start.resize(count + 1)
	for i in count:
		for j in reads[i]:
			start[j + 1] += 1
	for i in count:
		start[i + 1] += start[i]
	var fill := start.duplicate()
	var outs := PackedInt32Array()
	outs.resize(start[count])
	for i in count:
		for j in reads[i]:
			outs[fill[j]] = i
			fill[j] += 1
	var power := PackedInt32Array()
	power.resize(count)
	var q := PackedInt32Array()
	for i in count:
		done[nodes[i]] = true
		if _powered(nodes[i], false):
			power[i] = 15
			q.append(i)
	head = 0
	while head < q.size():
		var i := q[head]
		head += 1
		var pw := power[i] - 1
		if pw <= 0:
			continue
		for k in range(start[i], start[i + 1]):
			var o := outs[k]
			if power[o] < pw:
				power[o] = pw
				q.append(o)
	for i in count:
		var w := nodes[i]
		if world.get_meta_v(w) != power[i]:
			world.set_meta_at(w.x, w.y, w.z, power[i], false)
			_notify_wire(w)


## Провод в w сменил заряд: пересчитать механизмы в клетках, которые он питает (под ним и
## по сторонам), и рядом с ними, если это непрозрачные блоки (их питает провод).
func _notify_wire(w: Vector3i) -> void:
	var opq := Blocks.opaque_flags
	for t in 5:
		var c := w + (DOWN if t == 4 else _dirs[t])
		var id := world.get_block_v(c)
		if _eval[id] == 1:
			_enqueue(c)
		if opq[id] == 1:
			for f in 6:
				var n := c + _faces[f]
				if _eval[world.get_block_v(n)] == 1:
					_enqueue(n)


func _node(p: Vector3i, nodes: Array[Vector3i], index: Dictionary) -> int:
	var i: Variant = index.get(p)
	if i != null:
		return int(i)
	var n := nodes.size()
	index[p] = n
	nodes.append(p)
	return n


# --- Факелы и повторители --------------------------------------------------

## Запитан ли блок, на котором висит факел (тогда факел гаснет).
func _torch_input(p: Vector3i) -> bool:
	var a := attached_pos(p, world.get_meta_v(p))
	var aid := world.get_block_v(a)
	if Blocks.is_opaque(aid):
		return _strongly_powered(a, true)
	return false


## Тик выключения факела; true — факел перегорел.
func _record_turn_off(p: Vector3i) -> bool:
	var list: PackedInt32Array = _burnout.get(p, PackedInt32Array())
	list = _fresh(list)
	list.append(logic.tick)
	_burnout[p] = list
	return list.size() >= BURNOUT_COUNT


func _burnt_out(p: Vector3i) -> bool:
	if not _burnout.has(p):
		return false
	var list := _fresh(_burnout[p])
	if list.is_empty():
		_burnout.erase(p)
	else:
		_burnout[p] = list
	return list.size() >= BURNOUT_COUNT


func _fresh(list: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for t in list:
		if logic.tick - t < BURNOUT_WINDOW:
			out.append(t)
	return out


func _prune_burnout() -> void:
	for p: Vector3i in _burnout.keys():
		var list := _fresh(_burnout[p])
		if list.is_empty():
			_burnout.erase(p)
		else:
			_burnout[p] = list


## Задержка повторителя в игровых тиках: (1–4) × 2.
static func repeater_delay(meta: int) -> int:
	return (((meta >> 2) & 3) + 1) * 2


## Выход повторителя — в сторону DIR_VEC[meta & 3] (куда смотрел игрок при установке), вход — сзади.
static func repeater_output(p: Vector3i, meta: int) -> Vector3i:
	return p + Blocks.DIR_VEC[meta & 3]


func _repeater_input(p: Vector3i, meta: int) -> bool:
	var d := meta & 3
	var b := p - _dirs[d]
	var id := world.get_block_v(b)
	if id == Blocks.REDSTONE_WIRE:
		return world.get_meta_v(b) > 0
	if Blocks.is_opaque(id):
		return _strongly_powered(b, true)
	return kinds[id] != K_NONE and _weak(b, id, Blocks.DIR_FACE[d], true)


# --- Механизмы -------------------------------------------------------------

## Фронт сигнала для механизма с ключом key: true — состояние питания изменилось.
func _edge(key: Vector3i, powered: bool) -> bool:
	if _last_power.has(key) == powered:
		return false
	if powered:
		_last_power[key] = true
	else:
		_last_power.erase(key)
	return true


## Дверь (обе половины): открывается при появлении сигнала, закрывается при пропадании;
## открытую рукой дверь без изменения сигнала не трогаем.
func _update_door(p: Vector3i, id: int) -> void:
	var m := world.get_meta_v(p)
	var lower := p + DOWN if m & 8 else p
	if world.get_block_v(lower) != id:
		return
	var upper := lower + UP
	var has_upper := world.get_block_v(upper) == id
	var powered := _powered(lower, true) or (has_upper and _powered(upper, true))
	if not _edge(lower, powered):
		return
	var lm := world.get_meta_v(lower)
	if (lm & 4 != 0) == powered:
		return
	var nm := (lm & 3) | (4 if powered else 0)
	world.set_block_v(lower, id, nm)
	if has_upper:
		world.set_block_v(upper, id, nm | 8)


## Энергорельсы: запитаны напрямую (клетка или клетка над ней) или по цепочке до 8 рельсов.
func _update_rail(p: Vector3i) -> void:
	var meta := world.get_meta_v(p)
	var shape := meta & 7
	var powered := _rail_direct(p) or _rail_chain(p, shape, true) or _rail_chain(p, shape, false)
	if powered != (meta & 8 != 0):
		world.set_block_v(p, Blocks.POWERED_RAIL, shape | (8 if powered else 0))


func _rail_direct(p: Vector3i) -> bool:
	return _powered(p, true) or _powered(p + UP, true)


## Форма рельсов: 0 север–юг, 1 запад–восток, 2–5 подъём на восток/запад/север/юг.
static func _rail_axis_x(shape: int) -> bool:
	return shape == 1 or shape == 2 or shape == 3


func _rail_chain(p: Vector3i, shape: int, forward: bool) -> bool:
	var q := p
	var sh := shape
	for i in RAIL_CHAIN:
		var next: Variant = _rail_next(q, sh, forward)
		if next == null:
			return false
		q = next
		sh = world.get_meta_v(q) & 7
		if _rail_direct(q):
			return true
	return false


## Следующий энергорельс по линии (с учётом подъёмов) или null.
func _rail_next(q: Vector3i, shape: int, forward: bool) -> Variant:
	var axis_x := _rail_axis_x(shape)
	var a := Vector3i(1, 0, 0) if axis_x else Vector3i(0, 0, 1)
	if not forward:
		a = -a
	var c := q + a
	# Подъём в сторону движения.
	if (shape == 2 and a.x > 0) or (shape == 3 and a.x < 0) or (shape == 4 and a.z < 0) or (shape == 5 and a.z > 0):
		c += UP
	for cand: Vector3i in [c, c + DOWN]:
		if world.get_block_v(cand) == Blocks.POWERED_RAIL and _rail_axis_x(world.get_meta_v(cand) & 7) == axis_x:
			return cand
	return null


# --- Нажимные плиты --------------------------------------------------------

## Плиты нажимаются существами на них: деревянная — любым (игрок, предметы, стрелы, мобы),
## каменная — только игроком и мобами. Отпускаются через секунду после того, как плиту покинули.
## Проверка — только для существ рядом с плитами (по габаритам области с плитами).
func _tick_plates() -> void:
	if _plates_box_dirty:
		_rebuild_plates_box()
	var occupied: Dictionary = {}
	var game := logic.game
	if game != null:
		var pl: Variant = game.get("player")
		if pl is Node3D and is_instance_valid(pl):
			var pn := pl as Node3D
			var box: AABB = pn.call("body_box") if pn.has_method("body_box") \
				else AABB(pn.position - Vector3(0.3, 0, 0.3), Vector3(0.6, 1.8, 0.6))
			if _plates_box.intersects(box):
				_mark_plates(box, 1, occupied)
		var ents: Variant = game.get("entities")
		if ents is Node and is_instance_valid(ents):
			for n in (ents as Node).get_children():
				if n is Node3D and n.has_method("update_entity") and not n.is_queued_for_deletion():
					var pos := (n as Node3D).position
					if _plates_box.has_point(pos):
						_mark_plates(AABB(pos - Vector3(0.125, 0, 0.125), Vector3(0.25, 0.25, 0.25)), 2, occupied)
			var mobs: Variant = (ents as Node).get("mobs")
			if mobs is Object and is_instance_valid(mobs) and (mobs as Object).has_method("in_radius"):
				var center := _plates_box.get_center()
				var list: Variant = (mobs as Object).call("in_radius", center, _plates_box.size.length() * 0.5 + 1.0)
				if list is Array:
					for m: Variant in list:
						if m is Node3D and is_instance_valid(m):
							var mp := (m as Node3D).global_position if (m as Node3D).is_inside_tree() else (m as Node3D).position
							_mark_plates(AABB(mp - Vector3(0.3, 0, 0.3), Vector3(0.6, 1.0, 0.6)), 1, occupied)
	for p: Vector3i in _plates.keys():
		var id := world.get_block_v(p)
		if kinds[id] != K_PLATE:
			_plates.erase(p)
			_plate_until.erase(p)
			_plates_box_dirty = true
			continue
		var occ: int = occupied.get(p, 0)
		var hit := occ & 1 != 0 or (id == Blocks.WOODEN_PLATE and occ != 0)
		var meta := world.get_meta_v(p)
		if hit:
			_plate_until[p] = logic.tick + PLATE_TICKS
			if meta & 1 == 0:
				world.set_block_v(p, id, 1)
		elif meta & 1 and logic.tick >= int(_plate_until.get(p, 0)):
			_plate_until.erase(p)
			world.set_block_v(p, id, 0)


## Отмечает плиты, которых касается параллелепипед box (зона срабатывания плиты — как в 1.2:
## 2/16 от краёв клетки, высота 1/4 блока).
func _mark_plates(box: AABB, flag: int, occupied: Dictionary) -> void:
	var lo := box.position
	var hi := box.end
	for y in range(floori(lo.y - 0.24), floori(lo.y + 0.24) + 1):
		for z in range(floori(lo.z + 0.125), floori(hi.z - 0.125) + 1):
			for x in range(floori(lo.x + 0.125), floori(hi.x - 0.125) + 1):
				var c := Vector3i(x, y, z)
				if _plates.has(c):
					occupied[c] = int(occupied.get(c, 0)) | flag


func _rebuild_plates_box() -> void:
	_plates_box_dirty = false
	var first := true
	for p: Vector3i in _plates:
		var b := AABB(Vector3(p), Vector3.ONE)
		if first:
			_plates_box = b
			first = false
		else:
			_plates_box = _plates_box.merge(b)
	_plates_box = _plates_box.grow(1.0)


# --- Загрузка чанков -------------------------------------------------------

const _SCAN_IDS := [Blocks.STONE_PLATE, Blocks.WOODEN_PLATE, Blocks.REDSTONE_TORCH, Blocks.REDSTONE_TORCH_OFF,
	Blocks.REPEATER_OFF, Blocks.REPEATER_ON, Blocks.REDSTONE_LAMP, Blocks.LIT_REDSTONE_LAMP, Blocks.STONE_BUTTON]


func _on_chunk_loaded(ch: Chunk) -> void:
	_scan_chunk(ch, true)


## Плиты — в реестр; факелы, повторители, лампы и нажатые кнопки — на проверку (отложенные тики
## не сохраняются, поэтому тактовые генераторы и кнопки после загрузки запускаются заново).
func _scan_chunk(ch: Chunk, revalidate: bool) -> void:
	var ox := ch.key.x * 16
	var oz := ch.key.y * 16
	var found: Array[Vector3i] = []
	for id: int in _SCAN_IDS:
		var i := ch.blocks.find(id)
		while i >= 0:
			var lp := Chunk.local_pos(i)
			var p := Vector3i(ox + lp.x, lp.y, oz + lp.z)
			if kinds[id] == K_PLATE:
				_plates[p] = true
				_plates_box_dirty = true
			elif revalidate:
				found.append(p)
			i = ch.blocks.find(id, i + 1)
	if not found.is_empty():
		_revalidate[ch.key] = found


func _on_chunk_unloading(ch: Chunk) -> void:
	_revalidate.erase(ch.key)
	for dict: Dictionary in [_plates, _plate_until, _last_power, _burnout]:
		for p: Vector3i in dict.keys():
			if p.x >> 4 == ch.key.x and p.z >> 4 == ch.key.y:
				dict.erase(p)
	_plates_box_dirty = true


func _tick_revalidate() -> void:
	for key: Vector2i in _revalidate.keys():
		if not world.chunks.has(key):
			_revalidate.erase(key)
			continue
		var ready := true
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if not world.chunks.has(key + Vector2i(dx, dz)):
					ready = false
		if not ready:
			continue
		for p: Vector3i in _revalidate[key]:
			if world.get_block_v(p) == Blocks.STONE_BUTTON:
				if world.get_meta_v(p) & 8:
					logic.schedule(p, BUTTON_TICKS)
			else:
				_enqueue(p)
		_revalidate.erase(key)
