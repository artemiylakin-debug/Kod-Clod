class_name FlatGen
extends WorldGen
## Суперплоский мир 1.2 (ChunkProviderFlat): коренная порода, два слоя земли и трава (верх — y=3),
## всюду равнины. Из построек — только деревни, и только если генерация построек включена.
## Ни деревьев, ни пещер, ни руды, как в оригинале.

const SURFACE := 3

var _villages: VillageGen
var _near: Array = []


func _init(p_seed: int) -> void:
	super(p_seed)
	# Моря нет: деревня встаёт прямо на траву.
	sea_level = 0


func get_height(_wx: int, _wz: int) -> int:
	return SURFACE


func biome_at(_wx: int, _wz: int) -> int:
	return Biomes.PLAINS


func local_biome(_lx: int, _lz: int) -> int:
	return Biomes.PLAINS


func soil_depth(_wx: int, _wz: int) -> int:
	return 2


func surface_block(_wx: int, _wz: int, _h: int) -> int:
	return Blocks.GRASS


func find_spawn_column() -> Vector2i:
	return Vector2i.ZERO


func begin_chunk(cx: int, cz: int) -> void:
	buf = GenChunk.new()
	buf.setup(cx, cz)
	heights = PackedInt32Array()
	heights.resize(LAYER)
	heights.fill(SURFACE)
	min_surface = SURFACE
	max_surface = SURFACE
	var data := buf.blocks
	for col in LAYER:
		data[col] = Blocks.BEDROCK
		data[col + 256] = Blocks.DIRT
		data[col + 512] = Blocks.DIRT
		data[col + 768] = Blocks.GRASS
	_near = []
	if WorldGen.structures_enabled:
		_villages = VillageGen.new(self)
		_near = _villages.villages_near(cx, cz)


## Все этапы, кроме первого, пустые: деревни ставятся за один шаг.
func fill_rows(z0: int, z1: int) -> void:
	if z0 <= 0 and z1 > 0:
		for v: Dictionary in _near:
			_villages.draw(v, buf)


func finish_chunk() -> Dictionary:
	var biomes := PackedByteArray()
	biomes.resize(LAYER)
	biomes.fill(Biomes.PLAINS)
	var out := {"blocks": buf.blocks, "meta": buf.meta, "biomes": biomes, "block_entities": buf.block_entities,
		"entities": buf.entities}
	buf = null
	_near = []
	return out


func structure_blocks_tree(_wx: int, _wz: int) -> bool:
	return false


## Крепостей в суперплоском мире нет — око Края некуда отправить.
func stronghold_positions() -> Array[Vector2i]:
	return []


func village_center(rx: int, rz: int) -> Vector2i:
	if not WorldGen.structures_enabled:
		return Vector2i(1 << 30, 0)
	return VillageGen.new(self).village_center(rx, rz)
