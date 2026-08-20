extends Node
## Redraw the ponds around the Swamp Hermit with real banks.
##
## The map's water source only has island art, so ponds were painted as flat
## water with island edges — blue rectangles. This registers the generated
## pond atlas as a new source and re-lays every water cell in the wing by its
## neighbourhood: fill inside, bank tiles on the sides, inner corners on the
## diagonals.
##   godot --path . --mode=client res://tools/retile_ponds.tscn

const MAP: String = "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
const POND_ART: String = "res://assets/sprites/environment/overworld/pond_tiles.png"
const WATER_SOURCE: int = 8
const TILE: int = 16
## Atlas coords in pond_tiles.png, by which sides have LAND.
const FILL := Vector2i(1, 1)
const EDGE := {
	"N": Vector2i(1, 0), "S": Vector2i(1, 2), "W": Vector2i(0, 1), "E": Vector2i(2, 1),
	"NW": Vector2i(0, 0), "NE": Vector2i(2, 0), "SW": Vector2i(0, 2), "SE": Vector2i(2, 2),
}


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node = (load(MAP) as PackedScene).instantiate()
	var features: TileMapLayer = root.get_node("Features") as TileMapLayer
	var tile_set: TileSet = features.tile_set

	# Register the pond atlas, or reuse it if this has already run.
	var pond_id: int = -1
	for i: int in tile_set.get_source_count():
		var sid: int = tile_set.get_source_id(i)
		var src: TileSetAtlasSource = tile_set.get_source(sid) as TileSetAtlasSource
		if src != null and src.texture != null and src.texture.resource_path == POND_ART:
			pond_id = sid
			break
	if pond_id < 0:
		var atlas := TileSetAtlasSource.new()
		atlas.texture = load(POND_ART)
		atlas.texture_region_size = Vector2i(TILE, TILE)
		for ty: int in 3:
			for tx: int in 4:
				atlas.create_tile(Vector2i(tx, ty))
		pond_id = tile_set.add_source(atlas)
		print("registered pond atlas as source ", pond_id)

	var water: Dictionary = {}
	for cell: Vector2i in features.get_used_cells():
		if features.get_cell_source_id(cell) == WATER_SOURCE:
			water[cell] = true
	print("water cells found: ", water.size())

	var changed: int = 0
	for cell: Vector2i in water:
		var n: bool = not water.has(cell + Vector2i(0, -1))
		var s: bool = not water.has(cell + Vector2i(0, 1))
		var w: bool = not water.has(cell + Vector2i(-1, 0))
		var e: bool = not water.has(cell + Vector2i(1, 0))
		var coords: Vector2i = FILL
		if n and w:
			coords = EDGE["NW"]
		elif n and e:
			coords = EDGE["NE"]
		elif s and w:
			coords = EDGE["SW"]
		elif s and e:
			coords = EDGE["SE"]
		elif n:
			coords = EDGE["N"]
		elif s:
			coords = EDGE["S"]
		elif w:
			coords = EDGE["W"]
		elif e:
			coords = EDGE["E"]
		else:
			# Interior: only the diagonals can still be land.
			var dnw: bool = not water.has(cell + Vector2i(-1, -1))
			var dne: bool = not water.has(cell + Vector2i(1, -1))
			var dsw: bool = not water.has(cell + Vector2i(-1, 1))
			if dnw:
				coords = Vector2i(3, 0)
			elif dne:
				coords = Vector2i(3, 1)
			elif dsw:
				coords = Vector2i(3, 2)
		features.set_cell(cell, pond_id, coords)
		changed += 1
	print("retiled %d pond cells" % changed)

	var packed := PackedScene.new()
	packed.pack(root)
	print("saved: ", ResourceSaver.save(packed, MAP) == OK)
	get_tree().quit(0)
