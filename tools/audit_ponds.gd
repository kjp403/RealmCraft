extends Node
## Print the tile grid around the Swamp Hermit so the ponds can be seen as data:
## which layer holds them, which atlas tiles, and whether the tiles are water or
## an edge. Tiles are labelled by the average colour of their atlas region.
##   godot --path . --mode=client res://tools/audit_ponds.tscn

const MAP: String = "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
const CENTRE := Vector2i(150, 21)      # Swamp Hermit, world (4804, 680)
const RADIUS := Vector2i(34, 16)


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node = (load(MAP) as PackedScene).instantiate()
	# Centre on the hermit using the tileset's REAL tile size rather than an
	# assumed 32px — the first pass looked 150 tiles away from the ponds.
	var g: TileMapLayer = root.get_node("Ground") as TileMapLayer
	var tile_size: Vector2i = g.tile_set.tile_size
	var centre: Vector2i = Vector2i(Vector2(4804, 680) / Vector2(tile_size))
	print("tile size %s -> hermit at tile %s" % [tile_size, centre])
	for layer_name: String in ["Ground", "Features", "Decor"]:
		var layer: TileMapLayer = root.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			continue
		var seen: Dictionary = {}
		var grid: PackedStringArray = []
		for y: int in range(centre.y - RADIUS.y, centre.y + RADIUS.y):
			var row: String = ""
			for x: int in range(centre.x - RADIUS.x, centre.x + RADIUS.x):
				var c := Vector2i(x, y)
				var sid: int = layer.get_cell_source_id(c)
				if sid < 0:
					row += "."
					continue
				var key: String = "%d:%s" % [sid, layer.get_cell_atlas_coords(c)]
				if not seen.has(key):
					seen[key] = char(65 + seen.size() % 26)
				row += seen[key]
			grid.append(row)
		print("--- ", layer_name, " around the hermit ---")
		for row: String in grid:
			print(row)
		var legend: PackedStringArray = []
		for key: String in seen:
			legend.append("%s=%s" % [seen[key], key])
		print("legend: ", ", ".join(legend))
	root.free()
	get_tree().quit(0)
