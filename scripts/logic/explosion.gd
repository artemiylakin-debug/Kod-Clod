class_name Explosion
extends RefCounted
## Взрыв как в оригинале: лучи из центра теряют силу на каждом блоке (по взрывоустойчивости);
## разрушенные блоки выпадают с шансом 1/сила, существа получают урон и отбрасывание.


static func explode(logic: BlockLogic, center: Vector3, power: float, fire: bool, source: Node = null) -> void:
	var world := logic.world
	var rng := logic.rng
	var destroyed: Dictionary = {}
	var steps := 16
	for i in steps:
		for j in steps:
			for k in steps:
				if i != 0 and i != steps - 1 and j != 0 and j != steps - 1 and k != 0 and k != steps - 1:
					continue
				var dir := Vector3(i / (steps - 1.0) * 2.0 - 1.0, j / (steps - 1.0) * 2.0 - 1.0, k / (steps - 1.0) * 2.0 - 1.0).normalized()
				var intensity := power * (0.7 + rng.randf() * 0.6)
				var pos := center
				while intensity > 0.0:
					var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
					var b := world.get_block_v(cell)
					if b != Blocks.AIR:
						intensity -= (Blocks.blast_table[b] / 5.0 + 0.3) * 0.3
						if intensity > 0.0 and not Blocks.is_liquid(b) and Blocks.hardness(b) >= 0.0:
							destroyed[cell] = b
					pos += dir * 0.3
					intensity -= 0.3 * 0.75
	# Разрушение блоков (динамит рядом взрывается цепочкой).
	for cell: Vector3i in destroyed:
		var b := world.get_block_v(cell)
		if b == Blocks.AIR:
			continue
		if b == Blocks.TNT:
			logic.ignite_tnt(cell, rng.randf_range(0.5, 1.5))
			continue
		var meta := world.get_meta_v(cell)
		world.set_block(cell.x, cell.y, cell.z, Blocks.AIR, 0)
		if rng.randf() < 1.0 / power:
			logic.drop_block_items(cell, b, meta, Blocks.TOOL_PICKAXE, 3)
	if fire:
		for cell: Vector3i in destroyed:
			if world.get_block_v(cell) == Blocks.AIR and rng.randi_range(0, 2) == 0 \
					and Blocks.is_opaque(world.get_block_v(cell + Vector3i(0, -1, 0))):
				world.set_block(cell.x, cell.y, cell.z, Blocks.FIRE)
	# Урон существам и игроку.
	var game := logic.game
	if game != null and game.has_method("explosion_damage"):
		game.call("explosion_damage", center, power, source)
