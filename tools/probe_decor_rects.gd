extends SceneTree
## Ground-truth probe: print the engine's drawn rect for the multi-cell decor
## tiles, so the offline placement tool (tools/lib/tilegeom.py) can be checked
## against real geometry instead of a guessed formula.
##
##   godot --headless --path . -s tools/probe_decor_rects.gd

const MAP_PATH := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"


func _initialize() -> void:
	var map: Node2D = (load(MAP_PATH) as PackedScene).instantiate()
	for layer: Node in map.find_children("*", "TileMapLayer", true, false):
		var tml := layer as TileMapLayer
		var ts := tml.tile_set
		if ts == null:
			continue
		var seen: Dictionary = {}
		for cell: Vector2i in tml.get_used_cells():
			var sid := tml.get_cell_source_id(cell)
			var a := tml.get_cell_atlas_coords(cell)
			var alt := tml.get_cell_alternative_tile(cell)
			var src := ts.get_source(sid) as TileSetAtlasSource
			if src == null:
				continue
			var td := src.get_tile_data(a, alt)
			if td == null:
				continue
			var region := src.get_tile_texture_region(a, alt)
			if region.size == Vector2i(16, 16):
				continue # only the oversized sprites matter for clearance
			var key := "%s:%d:%d:%d" % [tml.name, sid, a.x, a.y]
			if seen.has(key):
				continue
			seen[key] = true
			var centre := tml.map_to_local(cell)
			var rect := Rect2(
				centre - Vector2(region.size) / 2.0 + Vector2(td.texture_origin),
				Vector2(region.size)
			)
			print("PROBE layer=", tml.name, " cell=", cell, " src=", sid, " atlas=", a,
				" size_px=", region.size, " tex_origin=", td.texture_origin,
				" centre=", centre, " rect=", rect)
	map.free()
	quit(0)
