extends SceneTree
## Build the Epic RPG World Sewers TileSet (32x32) from Rafael Matos's pack.
##
## Deliberately a NEW resource rather than an edit of `sewers_tileset.tres`:
## that one is 16x16 and shared by all four sewer maps including the Ossuary,
## which is not part of this overhaul and must keep rendering.
##
## `Tileset-Terrain.png` is a documentation sheet, not a dense atlas — it carries
## baked-in caption text ("water tiles to be used around Wall 2" sits on row 50)
## and large empty gutters between banks. Adding all 65x65 cells would import
## label glyphs as paintable tiles, so only regions verified against the author's
## own example maps are taken. The region list below was derived by decoding
## `TiledMap Editor Example - Sewers.tmx` / `SampleScene.tmx` and ranking which
## tile ids he actually paints.
##
##   godot --headless --path . --import
##   godot --headless --path . -s tools/build_rpgw_sewers_tileset.gd

const PACK := "res://assets/sprites/environment/rpgw_sewers/EPIC RPG World - Sewers V1.5/"
const OUT := "res://source/common/gameplay/maps/tilesets/rpgw_sewers_tileset.tres"

const TERRAIN := PACK + "Tilesets/Tileset-Terrain.png"
const WALL1 := PACK + "Tilesets/wall-1-water.png"
const SEWAGE := PACK + "Tilesets/Animated sewage water tiles (full tile).png"
const PROPS := PACK + "Props/atlas-props.png"

## Curated bands of Tileset-Terrain.png. Rows 44 and 50 are caption text and are
## skipped by construction. Rect2i is (col, row, cols, rows).
const TERRAIN_REGIONS: Array[Rect2i] = [
	Rect2i(25, 1, 8, 6),    # cobble floor bank + curved stone edges
	Rect2i(0, 45, 6, 5),    # slime edge / spur pieces
	Rect2i(0, 51, 6, 1),    # solid slime fill
	Rect2i(26, 54, 8, 4),   # slime-on-stone channel blob (rounded corners)
	Rect2i(0, 58, 6, 5),    # deep slime + shore variants
	Rect2i(52, 37, 7, 4),   # grates / drain covers
]

## `atlas-props.png` is the same kind of documentation sheet: captions like
## "wooden planks as improvised bridge" and "frame 1 frame 2 ... frame 8" sit
## directly on the grid. Importing the whole 59x53 atlas pulled those glyphs in
## as paintable tiles — they were legible in the first sample render — so props
## are curated the same way the terrain is.
const PROPS_REGIONS: Array[Rect2i] = [
	Rect2i(0, 3, 31, 9),    # spider webs, corner + vertical variants
	Rect2i(11, 20, 4, 4),   # bottles / potions
	Rect2i(26, 23, 10, 3),  # bones and skeleton remains
	Rect2i(35, 16, 7, 16),  # crates, barrels and stacked boxes
	Rect2i(0, 28, 16, 13),  # wooden planks (improvised bridges)
	Rect2i(37, 40, 22, 11), # pipe networks and junctions
]

var _report: Array[String] = []
var _captions: int = 0


func _initialize() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	# Matches rpgw_caves_tileset: walls sit on collision layer 2 and mask nothing.
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 0)

	_add_regions(ts, 0, TERRAIN, TERRAIN_REGIONS, false)
	_add_full(ts, 1, WALL1, true)
	_add_animated_strip(ts, 2, SEWAGE, 8)
	_add_regions(ts, 3, PROPS, PROPS_REGIONS, false)

	var err := ResourceSaver.save(ts, OUT)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return
	for line in _report:
		print(line)
	print("  caption cells rejected: ", _captions)
	print("RPGW_SEWERS_TILESET_BUILT ", OUT)
	quit(0)


## Skip cells that are effectively empty so the atlas has no invisible tiles a
## builder could paint by accident.
func _opaque(img: Image, cx: int, cy: int) -> bool:
	var solid: int = 0
	for y in range(cy * 32, cy * 32 + 32, 2):
		for x in range(cx * 32, cx * 32 + 32, 2):
			if x >= img.get_width() or y >= img.get_height():
				continue
			if img.get_pixel(x, y).a > 0.4:
				solid += 1
	return solid >= 12


## Reject caption glyphs. Every label in this pack is pure white with a hard
## black outline and no hue at all, while the art is green stone, blue pipework
## or brown timber. A cell whose opaque pixels are essentially colourless and
## mostly near-white is text, not a tile.
func _is_caption(img: Image, cx: int, cy: int) -> bool:
	var opaque: int = 0
	var pale: int = 0
	var sat_sum: float = 0.0
	for y in range(cy * 32, cy * 32 + 32, 2):
		for x in range(cx * 32, cx * 32 + 32, 2):
			if x >= img.get_width() or y >= img.get_height():
				continue
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.4:
				continue
			opaque += 1
			sat_sum += c.s
			if c.v > 0.85:
				pale += 1
	if opaque < 6:
		return false
	return (sat_sum / float(opaque)) < 0.08 and float(pale) / float(opaque) > 0.45


func _atlas(ts: TileSet, source_id: int, path: String) -> TileSetAtlasSource:
	var tex: Texture2D = load(path)
	assert(tex != null, "missing texture %s" % path)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(32, 32)
	ts.add_source(src, source_id)
	return src


## Full-cell square collision, which is what every wall tile in this pack wants —
## the art is a solid masonry block, and the map builder decides which rows go on
## a colliding layer versus the decorative overhang layer.
func _collide(src: TileSetAtlasSource, coord: Vector2i) -> void:
	var data: TileData = src.get_tile_data(coord, 0)
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)
	]))


func _add_regions(ts: TileSet, source_id: int, path: String, regions: Array[Rect2i], collide: bool) -> void:
	var src := _atlas(ts, source_id, path)
	var img: Image = src.texture.get_image()
	var added: int = 0
	for r: Rect2i in regions:
		for oy in r.size.y:
			for ox in r.size.x:
				var coord := Vector2i(r.position.x + ox, r.position.y + oy)
				if coord.x * 32 >= img.get_width() or coord.y * 32 >= img.get_height():
					continue
				if not _opaque(img, coord.x, coord.y):
					continue
				if _is_caption(img, coord.x, coord.y):
					_captions += 1
					continue
				src.create_tile(coord)
				if collide:
					_collide(src, coord)
				added += 1
	_report.append("  source %d %-28s %4d tiles (%d regions)" % [
		source_id, path.get_file(), added, regions.size()])


func _add_full(ts: TileSet, source_id: int, path: String, collide: bool) -> void:
	var src := _atlas(ts, source_id, path)
	var img: Image = src.texture.get_image()
	var cols: int = img.get_width() / 32
	var rows: int = img.get_height() / 32
	var added: int = 0
	for cy in rows:
		for cx in cols:
			if not _opaque(img, cx, cy):
				continue
			if _is_caption(img, cx, cy):
				_captions += 1
				continue
			src.create_tile(Vector2i(cx, cy))
			if collide:
				_collide(src, Vector2i(cx, cy))
			added += 1
	_report.append("  source %d %-28s %4d tiles (%dx%d grid)" % [
		source_id, path.get_file(), added, cols, rows])


## The sewage sheet is one tile animated across N horizontal frames. Godot's
## atlas animation consumes the frames to the right of the origin, so only the
## first cell becomes a tile and the rest are its frames.
func _add_animated_strip(ts: TileSet, source_id: int, path: String, frames: int) -> void:
	var src := _atlas(ts, source_id, path)
	src.create_tile(Vector2i.ZERO)
	src.set_tile_animation_frames_count(Vector2i.ZERO, frames)
	for f in frames:
		src.set_tile_animation_frame_duration(Vector2i.ZERO, f, 0.14)
	_report.append("  source %d %-28s   1 animated tile (%d frames)" % [
		source_id, path.get_file(), frames])
