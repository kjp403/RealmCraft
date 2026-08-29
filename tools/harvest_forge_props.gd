extends Node
## Dump every PROP tile the hand-authored Fire Forge maps actually use, with a
## count and a role guess, so the Ossuran arena can be decorated from a proven
## vocabulary instead of from coordinates guessed off a screenshot of the atlas.
##
##   godot --path . --mode=client res://tools/harvest_forge_props.tscn
##
## Why harvest rather than pick: `fire_forge/tiles.png` is a 25x25 atlas of
## masonry, grates, anvils, casting pits, hazard stripes and lava. Reading a cell
## coordinate off a zoomed PNG and trusting it is exactly how you end up painting
## the top half of an arch in the middle of a floor. The three Forge maps were
## placed by hand, so every tile they use on Props is a cell somebody already
## confirmed reads correctly at 16px — that is the set worth stealing.
##
## Prints one line per distinct tile:
##   PROP source=<id> coords=(x, y) count=<n> maps=<n>
## and a WALLTILE block for the wall vocabulary, so the chamber can be given a
## different border than the arena rather than the same ring twice.

const MAPS: Array[String] = [
	"res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
	"res://source/common/gameplay/maps/maps/fire_forge/bellows_gallery.tscn",
	"res://source/common/gameplay/maps/maps/fire_forge/cinder_deeps.tscn",
]


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var props: Dictionary = {}
	var walls: Dictionary = {}
	var grounds: Dictionary = {}
	for path: String in MAPS:
		var packed: PackedScene = load(path)
		if packed == null:
			printerr("could not load ", path)
			continue
		var root: Node = packed.instantiate()
		_tally(_find_layer(root, &"Props"), props, path)
		_tally(_find_layer(root, &"Walls"), walls, path)
		_tally(_find_layer(root, &"Ground"), grounds, path)
		root.free()

	_report("PROP", props)
	_report("WALLTILE", walls)
	_report("GROUNDTILE", grounds)
	get_tree().quit(0)


func _tally(layer: TileMapLayer, into: Dictionary, from_map: String) -> void:
	if layer == null:
		return
	for cell: Vector2i in layer.get_used_cells():
		var source_id: int = layer.get_cell_source_id(cell)
		var coords: Vector2i = layer.get_cell_atlas_coords(cell)
		var key: String = "%d|%d|%d" % [source_id, coords.x, coords.y]
		if not into.has(key):
			into[key] = {"count": 0, "maps": {}}
		into[key]["count"] = int(into[key]["count"]) + 1
		into[key]["maps"][from_map] = true


## Most-used first — a tile the maps lean on is a tile that reads.
func _report(tag: String, tally: Dictionary) -> void:
	var keys: Array = tally.keys()
	keys.sort_custom(
		func(a: String, b: String) -> bool:
			return int(tally[a]["count"]) > int(tally[b]["count"])
	)
	print("%s_TOTAL %d" % [tag, keys.size()])
	for key: String in keys:
		var parts: PackedStringArray = key.split("|")
		print("%s source=%s coords=(%s, %s) count=%d maps=%d" % [
			tag, parts[0], parts[1], parts[2],
			int(tally[key]["count"]), int(tally[key]["maps"].size()),
		])


func _find_layer(node: Node, wanted: StringName) -> TileMapLayer:
	if node is TileMapLayer and node.name == wanted:
		return node as TileMapLayer
	for child: Node in node.get_children():
		var found: TileMapLayer = _find_layer(child, wanted)
		if found != null:
			return found
	return null
