extends SceneTree
## Find cells where the map background shows through the tiles.
##
## The Epic RPG World packs draw most of their edge, rim and corner pieces with
## bare canvas around the art, because they are meant to be composited OVER a
## ground tile. Painted onto the ground layer instead they REPLACE the floor
## cell, and the bare part becomes a hole straight through to the map background
## — grey notches on a quay corner, a hairline down a shoreline.
##
## Nothing else catches it. `audit_biome_collision` only asks whether a cell is
## walkable, and a hole is perfectly walkable; the builder's own asserts count
## tiles, and the count is right. So this walks the four layers in draw order,
## accumulates real per-pixel alpha from the atlas images, and reports any cell
## the stack does not fully cover.
##
##   godot --headless --path . -s tools/audit_tile_opacity.gd

## Sample every Nth pixel in each axis. 2 gives 16x16 probes per 32px cell,
## which is fine enough to catch a one-pixel seam and four times cheaper than
## reading all 1024.
const STEP := 2
## Report at most this many example cells per map.
const EXAMPLES := 6

const MAPS: Array[String] = [
	"res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
	"res://source/common/gameplay/maps/maps/sewers/gutterworks.tscn",
	"res://source/common/gameplay/maps/maps/sewers/drowned_cistern.tscn",
]

## coverage["%d:%d,%d" % [source, x, y]] -> PackedByteArray of STEP-sampled alpha
var _mask_cache: Dictionary = {}
var _image_cache: Dictionary = {}
var _full_cache: Dictionary = {}


func _initialize() -> void:
	var failures: int = 0
	for path in MAPS:
		if not _check(path):
			failures += 1
	if failures == 0:
		print("TILE_OPACITY_AUDIT_PASS")
		quit(0)
		return
	print("TILE_OPACITY_AUDIT_FAIL ", failures)
	quit(1)


func _image_for(ts: TileSet, source_id: int) -> Image:
	if _image_cache.has(source_id):
		return _image_cache[source_id]
	var src := ts.get_source(source_id) as TileSetAtlasSource
	var img: Image = null
	if src != null and src.texture != null:
		img = src.texture.get_image()
		if img.is_compressed():
			img.decompress()
	_image_cache[source_id] = img
	return img


## True when every sampled pixel of this tile is opaque — the common case, and
## worth answering without building a mask.
func _is_full(ts: TileSet, source_id: int, coord: Vector2i, tile: int) -> bool:
	var key := "%d:%d,%d" % [source_id, coord.x, coord.y]
	if _full_cache.has(key):
		return _full_cache[key]
	var mask := _mask_for(ts, source_id, coord, tile)
	var full := true
	for b in mask:
		if b == 0:
			full = false
			break
	_full_cache[key] = full
	return full


func _mask_for(ts: TileSet, source_id: int, coord: Vector2i, tile: int) -> PackedByteArray:
	var key := "%d:%d,%d" % [source_id, coord.x, coord.y]
	if _mask_cache.has(key):
		return _mask_cache[key]
	var n: int = tile / STEP
	var mask := PackedByteArray()
	mask.resize(n * n)
	var img := _image_for(ts, source_id)
	if img == null:
		_mask_cache[key] = mask
		return mask
	var ox: int = coord.x * tile
	var oy: int = coord.y * tile
	for j in n:
		for i in n:
			var px: int = ox + i * STEP
			var py: int = oy + j * STEP
			if px >= img.get_width() or py >= img.get_height():
				continue
			mask[j * n + i] = 1 if img.get_pixel(px, py).a > 0.35 else 0
	_mask_cache[key] = mask
	return mask


func _check(path: String) -> bool:
	var scene: PackedScene = load(path)
	if scene == null:
		print("FAIL could not load ", path)
		return false
	var map: Node = scene.instantiate()
	var name := path.get_file()

	var tiles: Node = map.get_node_or_null("Tiles")
	if tiles == null:
		print("FAIL ", name, " has no Tiles node")
		map.free()
		return false
	var layers: Array[TileMapLayer] = []
	for child in tiles.get_children():
		if child is TileMapLayer:
			layers.append(child)
	if layers.is_empty():
		print("FAIL ", name, " has no tile layers")
		map.free()
		return false

	var ts: TileSet = layers[0].tile_set
	var tile: int = ts.tile_size.x
	var n: int = tile / STEP

	# Gather, per cell, the tiles stacked on it across every layer.
	var stack: Dictionary = {}
	for layer: TileMapLayer in layers:
		for cell: Vector2i in layer.get_used_cells():
			var source_id := layer.get_cell_source_id(cell)
			var src := layer.tile_set.get_source(source_id) as TileSetAtlasSource
			var coord := layer.get_cell_atlas_coords(cell)
			if src == null or not src.has_tile(coord):
				continue
			if not stack.has(cell):
				stack[cell] = [] as Array
			(stack[cell] as Array).append([source_id, coord])

	var holed: Array[Vector2i] = []
	var worst: Dictionary = {}
	for cell: Vector2i in stack.keys():
		var entries: Array = stack[cell]
		# Fast path: any fully opaque tile in the stack covers the cell outright.
		var covered := false
		for e: Array in entries:
			if _is_full(ts, int(e[0]), e[1], tile):
				covered = true
				break
		if covered:
			continue
		# Otherwise composite the sampled alpha of the whole stack.
		var acc := PackedByteArray()
		acc.resize(n * n)
		for e: Array in entries:
			var mask := _mask_for(ts, int(e[0]), e[1], tile)
			for i in mask.size():
				if mask[i] != 0:
					acc[i] = 1
		var bare: int = 0
		for b in acc:
			if b == 0:
				bare += 1
		if bare > 0:
			holed.append(cell)
			var label := ""
			for e: Array in entries:
				label += "%d:%d,%d " % [int(e[0]), (e[1] as Vector2i).x, (e[1] as Vector2i).y]
			worst[cell] = "%s(%d%% bare)" % [label, int(round(float(bare) * 100.0 / float(n * n)))]

	var ok := holed.is_empty()
	print(
		("OK   " if ok else "FAIL "), name,
		" cells=", stack.size(), " showing_background=", holed.size()
	)
	if not ok:
		holed.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a.y * 100000 + a.x) < (b.y * 100000 + b.x))
		for i in mini(EXAMPLES, holed.size()):
			print("       ", holed[i], "  ", worst[holed[i]])
	map.free()
	return ok
