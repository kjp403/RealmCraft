extends SceneTree
## Generate pond tiles the woodland tileset does not have.
##
## water_tiles.png only contains ISLANDS — grass surrounded by water — plus flat
## water. A pond is the inverse (water surrounded by grass) and there is no art
## for it, which is why the ponds read as flat blue rectangles. This composites
## the map's OWN grass and water tiles into a 3x3 pond set plus inner corners,
## so the result matches the palette exactly.
##   godot --headless --path . -s tools/build_pond_tiles.gd

## The SAME water the beaches use, downscaled to the woodland's 16px grid, so a
## pond and the sea read as the same substance.
const WATER: String = "res://assets/sprites/environment/sea/tilesets/water_anim.png"
const OUT: String = "res://assets/sprites/environment/overworld/pond_tiles.png"
const TILE: int = 16
## Flat water and a plain grass tile from the same sheets the map already uses.
const WATER_CELL := Vector2i(0, 0)
const WATER_TILE: int = 32
const GRASS_SRC: String = "res://assets/sprites/environment/overworld/floor_tiles.png"
const GRASS_CELL := Vector2i(1, 10)
## Bank thickness in pixels — how far the grass creeps over the water edge.
const BANK: int = 5


func _init() -> void:
	var water_tex: Texture2D = load(WATER)
	var grass_tex: Texture2D = load(GRASS_SRC)
	if water_tex == null or grass_tex == null:
		push_error("missing source tiles (water=%s grass=%s)" % [water_tex, grass_tex])
		quit(1)
		return
	var water: Image = water_tex.get_image().get_region(
		Rect2i(WATER_CELL * WATER_TILE, Vector2i(WATER_TILE, WATER_TILE)))
	water.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
	var grass: Image = grass_tex.get_image().get_region(
		Rect2i(GRASS_CELL * TILE, Vector2i(TILE, TILE)))
	if water.get_format() != Image.FORMAT_RGBA8:
		water.convert(Image.FORMAT_RGBA8)
	if grass.get_format() != Image.FORMAT_RGBA8:
		grass.convert(Image.FORMAT_RGBA8)

	# 4x3 sheet: row 0 = N edge + corners, row 1 = W/fill/E, row 2 = S edge.
	var sheet := Image.create_empty(TILE * 4, TILE * 3, false, Image.FORMAT_RGBA8)
	var layout: Array = [
		[Vector2i(0, 0), Vector2i(1, 1)], [Vector2i(1, 0), Vector2i(0, 1)],
		[Vector2i(2, 0), Vector2i(-1, 1)], [Vector2i(0, 1), Vector2i(1, 0)],
		[Vector2i(1, 1), Vector2i(0, 0)], [Vector2i(2, 1), Vector2i(-1, 0)],
		[Vector2i(0, 2), Vector2i(1, -1)], [Vector2i(1, 2), Vector2i(0, -1)],
		[Vector2i(2, 2), Vector2i(-1, -1)],
	]
	for entry: Array in layout:
		var at: Vector2i = entry[0]
		var dir: Vector2i = entry[1]
		sheet.blit_rect(_bank(water, grass, dir), Rect2i(Vector2i.ZERO, Vector2i(TILE, TILE)),
			at * TILE)
	# Fourth column: inner corners, where grass juts INTO the pond diagonally.
	var inners: Array = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1)]
	for i: int in inners.size():
		sheet.blit_rect(_inner(water, grass, inners[i]),
			Rect2i(Vector2i.ZERO, Vector2i(TILE, TILE)), Vector2i(3, i) * TILE)

	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("SAVED ", OUT, " ", sheet.get_size())
	quit(0)


## One bank tile: water, with grass covering the side(s) [param dir] points to.
func _bank(water: Image, grass: Image, dir: Vector2i) -> Image:
	var out: Image = water.duplicate()
	for y: int in TILE:
		for x: int in TILE:
			var covered: bool = false
			if dir.x > 0 and x < BANK + _wobble(y):
				covered = true
			if dir.x < 0 and x >= TILE - BANK - _wobble(y):
				covered = true
			if dir.y > 0 and y < BANK + _wobble(x):
				covered = true
			if dir.y < 0 and y >= TILE - BANK - _wobble(x):
				covered = true
			if covered:
				out.set_pixel(x, y, grass.get_pixel(x, y))
	return out


## Diagonal corner: grass only in the quadrant [param dir] points at.
func _inner(water: Image, grass: Image, dir: Vector2i) -> Image:
	var out: Image = water.duplicate()
	for y: int in TILE:
		for x: int in TILE:
			var qx: bool = x < BANK + _wobble(y) if dir.x > 0 else x >= TILE - BANK - _wobble(y)
			var qy: bool = y < BANK + _wobble(x) if dir.y > 0 else y >= TILE - BANK - _wobble(x)
			if qx and qy:
				out.set_pixel(x, y, grass.get_pixel(x, y))
	return out


## A little irregularity so banks are not ruler-straight.
static func _wobble(v: int) -> int:
	return [0, 1, 2, 1, 0, -1, 0, 1, 2, 1, 0, 1, 0, -1, 0, 1][v % 16]
