class_name BoxModel
extends RefCounted
## Меш из параллелепипедов с текстурами из атласа (для вагонеток, лодок, картин):
## рисуется материалом предметов (TextureFactory.entity_material), освещение — set_light.

## parts: [[AABB, тайл или массив из 6 тайлов по граням, inside?], …]; inside — грани видны изнутри.
static func build(parts: Array) -> ArrayMesh:
	var surf := ChunkMesher.Surface.new()
	for part: Array in parts:
		var box: AABB = part[0]
		var tiles: Variant = part[1]
		var two_sided: bool = part.size() > 2 and bool(part[2])
		var lo := box.position
		var hi := box.end
		for d in 6:
			var tile: int = (tiles as Array)[d] if tiles is Array else int(tiles)
			if tile < 0:
				continue
			var p := ChunkMesher._box_face(lo, hi, d)
			var uv := []
			for k in 4:
				uv.append(ChunkMesher._face_uv(d, p[k]))
			surf.quad(p, uv, tile, float(ChunkMesher.FACE_SHADE[d]), 0.0, Color.WHITE, two_sided)
	var arr := surf.to_arrays()
	var mesh := ArrayMesh.new()
	if not arr.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Освещение объекта по клетке, где он находится.
static func light(mi: GeometryInstance3D, world: World, pos: Vector3) -> void:
	if world == null:
		return
	var cell := Vector3i(floori(pos.x), floori(pos.y + 0.3), floori(pos.z))
	TextureFactory.set_light(mi, world.get_sky_light(cell) / 15.0, ChunkMesher.block_curve[clampi(world.get_block_light(cell), 0, 15)])
