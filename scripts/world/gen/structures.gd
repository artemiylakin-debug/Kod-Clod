class_name Structures
extends RefCounted
## Крупные постройки Обычного мира (MapGenStructure 1.2): заброшенные шахты, крепости и деревни.
## Расположение и план каждой постройки вычисляются из сида; чанк ставит только свою часть.

var gen: WorldGen
var villages: VillageGen
var mineshafts: MineshaftGen
var strongholds: StrongholdGen
## Деревни, которые могут задеть этот чанк (и деревья у его границ).
var _near_villages: Array = []


func _init(p_gen: WorldGen) -> void:
	gen = p_gen
	villages = VillageGen.new(p_gen)
	mineshafts = MineshaftGen.new(p_gen.seed_value)
	strongholds = StrongholdGen.new(p_gen.seed_value)


func begin() -> void:
	_near_villages = villages.villages_near(gen.buf.cx, gen.buf.cz)


func generate() -> void:
	var buf := gen.buf
	for plan: Array in mineshafts.near(buf.cx, buf.cz):
		mineshafts.draw(plan, buf)
	for s: Vector2i in strongholds.start_chunks(gen.biome_src):
		if StrongholdGen.near(s.x, s.y, buf.cx, buf.cz):
			strongholds.draw(strongholds.layout(s.x, s.y), buf)
	for v: Dictionary in _near_villages:
		villages.draw(v, buf)


## Мешает ли постройка дереву в колонке (деревья не растут посреди деревень).
func blocks_tree(x: int, z: int) -> bool:
	for v: Dictionary in _near_villages:
		if VillageGen.blocks_tree(v, x, z):
			return true
	return false
