extends Node
## Is the Boss Hunt arena's spawn marker actually inside the fight room?
## Prints the walkable region around the marker and whether a wall covers it.
##   godot --path . --mode=client res://tools/check_boss_arena.tscn

const MAP: String = "res://source/common/gameplay/maps/maps/boss_hunt/boss_hunt_arena.tscn"


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node = (load(MAP) as PackedScene).instantiate()
	var spawn: Marker2D = root.get_node_or_null("Arena/BossSpawn") as Marker2D
	var entrance: Node2D = root.get_node_or_null("Entrance") as Node2D
	print("boss spawn at %s, entrance at %s" % [spawn.position, entrance.position])

	for child: Node in root.get_node("Map_tiles").get_children():
		var layer: TileMapLayer = child as TileMapLayer
		if layer == null:
			continue
		var ts: int = layer.tile_set.tile_size.x
		var cell: Vector2i = Vector2i(spawn.position) / ts
		var covered: bool = layer.get_cell_source_id(cell) >= 0
		print("%-10s tile size %d, used %s, covers the spawn cell %s: %s"
			% [layer.name, ts, layer.get_used_rect(), cell, covered])

	# Walk out from the spawn to see how much room it has before hitting wall.
	var walls: TileMapLayer = root.get_node_or_null("Map_tiles/Walls") as TileMapLayer
	if walls != null:
		var ts: int = walls.tile_set.tile_size.x
		var origin: Vector2i = Vector2i(spawn.position) / ts
		for dir: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var steps: int = 0
			var p: Vector2i = origin
			while steps < 40:
				p += dir
				if walls.get_cell_source_id(p) >= 0:
					break
				steps += 1
			print("  clear %2d tiles toward %s" % [steps, dir])
	# Which wall tiles are actually solid? A wall you can walk through is a wall
	# whose atlas tile has no collision polygon in the tileset.
	if walls != null:
		var solid: int = 0
		var hollow: Dictionary = {}
		for cell: Vector2i in walls.get_used_cells():
			var sid: int = walls.get_cell_source_id(cell)
			var src: TileSetAtlasSource = walls.tile_set.get_source(sid) as TileSetAtlasSource
			if src == null:
				continue
			var data: TileData = src.get_tile_data(walls.get_cell_atlas_coords(cell), 0)
			if data != null and data.get_collision_polygons_count(0) > 0:
				solid += 1
			else:
				var key: String = "%d:%s" % [sid, walls.get_cell_atlas_coords(cell)]
				hollow[key] = int(hollow.get(key, 0)) + 1
		print("wall cells: %d solid, %d with NO collision" % [solid, hollow.values().reduce(func(a, b): return a + b, 0)])
		var keys: Array = hollow.keys()
		keys.sort_custom(func(a, b): return hollow[a] > hollow[b])
		for k: String in keys.slice(0, 8):
			print("    passable wall tile %-14s x%d" % [k, hollow[k]])
	root.free()
	get_tree().quit(0)
