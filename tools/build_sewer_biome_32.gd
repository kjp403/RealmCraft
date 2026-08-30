extends SceneTree
## Build the three sewer maps as OPEN HUNTING BIOMES on the 32px art.
##
## These are field-boss zones, not dungeon crawls, so the geometry is one wide
## cavernous space per map rather than rooms or a corridor grid. Three rules
## follow from that and are enforced here rather than left to authoring:
##
##   1. The interior has no walls at all. Any pocket of void the boundary noise
##      leaves inside the zone is filled back to floor by `_seal_interior`, so
##      the only void is the border-connected outside and the only three-tile
##      walls are on the map's outer edge.
##   2. Sewage is painted as wide continuous rivers with authored banks, not
##      one-tile stripes — broad enough to fight around and to spawn against.
##   3. The boundary undulates from low-frequency noise, which gives broad bays
##      and headlands. It is deliberately NOT carved with tunnel(), whose narrow
##      radius is what produced the stair-stepped edges in the room build.
##
## Replaces the Gutterworks room grid and takes the Cistern and the surface hub
## off `build_biome_levels.gd` / `build_stub_biomes.gd`. The Ossuary is not part
## of this and stays on the 16px tileset.
##
## The surface map carries the hub's whole warper set — entrance 28, the
## overworld portal 128, and the three landing/stair pairs down to the
## sub-levels. Stair 156 to the Ossuary is emitted here because it was
## hand-placed on the old scene and `add_biome_stairs.gd` explicitly refuses to
## manage it; regenerating without it would silently break that round trip.
##
##   godot --headless --path . -s tools/build_sewer_biome_32.gd

const TS := "res://source/common/gameplay/maps/tilesets/rpgw_sewers_tileset.tres"
const MAPS := "res://source/common/gameplay/maps/maps/sewers/"
const INST := "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const OVERWORLD := "res://source/common/gameplay/maps/instance/instance_collection/overworld.tres"
const TYPES := "res://source/common/gameplay/characters/npc/types/"
const NPCS := "res://source/common/gameplay/characters/npc/npcs/"

const TILE := 32
## Minimum length of a straight bank run, in cells.
const RUN := 4

const SRC_TERRAIN := 0
const SRC_WALL := 1
const SRC_SEWAGE := 2
const SRC_PROPS := 3

const FLOOR: Array[Vector2i] = [
	Vector2i(26, 2), Vector2i(27, 2), Vector2i(28, 2),
	Vector2i(26, 3), Vector2i(27, 3), Vector2i(28, 3),
	Vector2i(26, 4), Vector2i(27, 4), Vector2i(28, 4),
]
const DARK: Array[Vector2i] = [Vector2i(28, 37), Vector2i(29, 37), Vector2i(33, 37)]
const VOID: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
const SEWAGE := Vector2i(0, 0)

# --- landmark palette -------------------------------------------------------
# The raised stone slab is the pack's rounded rect at terrain 29..33 x 1..5. Its
# cap rows are inset one cell either side, so the outline is an octagon, and
# `_slab_tile` reproduces that at any size instead of forcing the tiles into a
# square 9-slice — done that way first, and the corner pieces carry the chamfer
# flare, which poked out of each corner of the rectangle as a tab.
const SLAB_NCAP_W := Vector2i(30, 1)
const SLAB_NCAP := Vector2i(31, 1)
const SLAB_NCAP_E := Vector2i(32, 1)
const SLAB_NW_O := Vector2i(29, 2)
const SLAB_NW_I := Vector2i(30, 2)
const SLAB_NE_I := Vector2i(32, 2)
const SLAB_NE_O := Vector2i(33, 2)
const SLAB_W := Vector2i(29, 3)
const SLAB_E := Vector2i(33, 3)
const SLAB_SW_O := Vector2i(29, 4)
const SLAB_SW_I := Vector2i(30, 4)
const SLAB_SE_I := Vector2i(32, 4)
const SLAB_SE_O := Vector2i(33, 4)
const SLAB_SCAP_W := Vector2i(30, 5)
const SLAB_SCAP := Vector2i(31, 5)
const SLAB_SCAP_E := Vector2i(32, 5)
const SLAB_FILL: Array[Vector2i] = [
	Vector2i(31, 2), Vector2i(31, 3), Vector2i(31, 4), Vector2i(30, 3), Vector2i(32, 3),
]
const NO_TILE := Vector2i(-1, -1)
## Smallest slab the octagon can express: below this the cap row has no straight
## section left and the shape collapses into its own corners.
const SLAB_MIN := 5

## Improvised plank bridges. The pack draws them in two orientations and they
## are not interchangeable: the N-S set is one column of planks that repeats
## down, the E-W set is two rows that repeat across.
const PLANK_V_N := Vector2i(1, 36)
const PLANK_V_MID: Array[Vector2i] = [Vector2i(1, 37), Vector2i(1, 38), Vector2i(1, 39)]
const PLANK_V_S := Vector2i(1, 40)
const PLANK_H_W := Vector2i(1, 28)
const PLANK_H_MID: Array[Vector2i] = [Vector2i(2, 28), Vector2i(3, 28), Vector2i(4, 28)]
const PLANK_H_E := Vector2i(5, 28)

## 3x3 round pipe mouth, the drainage outfall.
const OUTFALL := Vector2i(56, 46)
## Short pipe runs with sewage in them, for smaller bank outlets.
const PIPE_SEG: Array[Vector2i] = [
	Vector2i(53, 44), Vector2i(54, 44), Vector2i(53, 45), Vector2i(54, 45),
	Vector2i(37, 46), Vector2i(38, 46),
]
## 2 wide x 3 tall free-standing column. On the wall source, so it collides.
const PILLAR := Vector2i(9, 12)
## 3x3 floor grate.
const GRATE := Vector2i(54, 37)
## 2 wide x 4 tall bottle rack and bench — the closest thing the pack has to an
## alchemy table, and it reads as one once the flasks are set on it.
const ALCHEMY := Vector2i(13, 20)
const FLASKS: Array[Vector2i] = [
	Vector2i(11, 21), Vector2i(11, 22), Vector2i(11, 23),
	Vector2i(12, 21), Vector2i(12, 22), Vector2i(12, 23),
]
## Crates and barrels, as 2x2 rects (x, y, w, h).
const CRATES: Array = [
	[35, 18, 2, 2], [37, 18, 2, 2], [39, 18, 2, 2],
	[35, 20, 2, 2], [37, 20, 2, 2], [39, 20, 2, 2],
	[35, 22, 2, 2], [37, 22, 2, 2], [39, 22, 2, 2],
]
## Skeletons, as 1x2 rects — head on the first row, ribcage and limbs on the
## second. Columns 28, 31 and 34 are deliberately absent: those variants start a
## row lower and a 1x2 taken from row 23 would clip their heads off.
const SKELETONS: Array = [
	[26, 23, 1, 2], [27, 23, 1, 2], [29, 23, 1, 2],
	[30, 23, 1, 2], [32, 23, 1, 2], [33, 23, 1, 2],
]
## Compact cobwebs. The rest of the web band is metres-long strands drawn to
## span a gap between two walls, and a single cell of one reads as a stray line.
const WEBS: Array[Vector2i] = [
	Vector2i(15, 4), Vector2i(15, 5), Vector2i(15, 6),
	Vector2i(16, 6), Vector2i(17, 4), Vector2i(17, 5),
]

var W: int = 0
var H: int = 0
var _bounds := Rect2i()
var _report: Array[String] = []


func _initialize() -> void:
	_build_sewers()
	_build_gutterworks()
	_build_cistern()
	for line in _report:
		print(line)
	print("SEWER_BIOME_32_BUILT")
	quit(0)


# --- shared helpers ---------------------------------------------------------

func _size(w: int, h: int) -> void:
	W = w
	H = h
	_bounds = Rect2i(0, 0, w, h)


func _layer(ts: TileSet) -> TileMapLayer:
	var l := TileMapLayer.new()
	l.tile_set = ts
	return l


func _wall_spec() -> MapKit.WallSpec:
	var spec := MapKit.WallSpec.new()
	spec.source = SRC_WALL
	for x in [0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12]:
		spec.rim.append(Vector2i(x, 9))
		spec.body.append(Vector2i(x, 10))
		spec.base.append(Vector2i(x, 11))
	spec.alcove = [Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5)]
	return spec


func _slime_spec() -> MapKit.BlobSpec:
	var spec := MapKit.BlobSpec.new()
	spec.source = SRC_TERRAIN
	spec.fill = Vector2i(29, 55)
	spec.n = Vector2i(29, 53)
	spec.s = Vector2i(29, 57)
	spec.w = Vector2i(27, 55)
	spec.e = Vector2i(31, 55)
	spec.nw = Vector2i(28, 54)
	spec.ne = Vector2i(30, 54)
	spec.sw = Vector2i(28, 56)
	spec.se = Vector2i(30, 56)
	return spec


## One broad open zone. `wobble` is how far the boundary breathes in and out;
## the noise scale is large so the edge makes bays tens of cells across instead
## of the cell-scale ragged edge a carve would leave.
func _open_zone(inset: int, wobble: float, seed_v: int) -> Dictionary:
	var mask: Dictionary = {}
	var cx := float(W) * 0.5
	var cy := float(H) * 0.5
	var rx := float(W) * 0.5 - float(inset)
	var ry := float(H) * 0.5 - float(inset)
	for y in range(inset, H - inset):
		for x in range(inset, W - inset):
			var nx: float = (float(x) - cx) / rx
			var ny: float = (float(y) - cy) / ry
			# Chebyshev falloff keeps the middle wide open instead of tapering
			# to a circle, which is what makes the space read as a hall.
			var d: float = maxf(absf(nx), absf(ny))
			var n: float = MapKit.value_noise(float(x), float(y), 30.0, seed_v)
			if d < 0.99 - wobble * (n - 0.5):
				mask[Vector2i(x, y)] = true
	return mask


## Fill every void pocket that is not connected to the map border, so the
## interior is guaranteed open and the wall painter can only ever build on the
## outer boundary.
func _seal_interior(mask: Dictionary) -> Dictionary:
	var outside: Dictionary = {}
	var queue: Array[Vector2i] = []
	for x in W:
		for y in [0, H - 1]:
			var c := Vector2i(x, y)
			if not mask.has(c) and not outside.has(c):
				outside[c] = true
				queue.append(c)
	for y in H:
		for x in [0, W - 1]:
			var c := Vector2i(x, y)
			if not mask.has(c) and not outside.has(c):
				outside[c] = true
				queue.append(c)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if not _bounds.has_point(nb) or mask.has(nb) or outside.has(nb):
				continue
			outside[nb] = true
			queue.append(nb)
	var sealed: Dictionary = mask.duplicate()
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if not mask.has(c) and not outside.has(c):
				sealed[c] = true
	return sealed


## A wide meandering river across the zone. Width is in cells either side of the
## centreline, so `half = 5` is an eleven-tile channel.
func _river(out: Dictionary, flow: Dictionary, floor_mask: Dictionary, base_y: float,
		amp: float, freq: float, half: int, seed_v: int) -> void:
	# The centreline is held straight and the shoreline comes from width instead.
	# A sloping centreline steps down one cell at a time, and this pack's banks
	# are a rounded-rect ring whose corners need several cells of run to read —
	# a one-cell step is smaller than the art can express, so it renders as a
	# staircase however the tiles are chosen. Width is quantised to RUN-cell
	# stretches for the same reason: every bank run is long enough to sit flat.
	for x in W:
		var qx: int = (x / RUN) * RUN
		var cy: int = int(round(base_y))
		var hw: int = half + int(round(
			(MapKit.value_noise(float(qx), base_y + 40.0, 7.0, seed_v + 7) - 0.5) * 5.0))
		hw = maxi(2, hw)
		for dy in range(-hw, hw + 1):
			var cell := Vector2i(x, cy + dy)
			if floor_mask.has(cell):
				out[cell] = true
				if absi(dy) <= 1:
					flow[cell] = true


## Vertical counterpart, for a river that crosses the zone the other way.
func _river_v(out: Dictionary, flow: Dictionary, floor_mask: Dictionary, base_x: float,
		amp: float, freq: float, half: int, seed_v: int) -> void:
	for y in H:
		var qy: int = (y / RUN) * RUN
		var cx: int = int(round(base_x))
		var hw: int = half + int(round(
			(MapKit.value_noise(base_x + 40.0, float(qy), 7.0, seed_v + 7) - 0.5) * 5.0))
		hw = maxi(2, hw)
		for dx in range(-hw, hw + 1):
			var cell := Vector2i(cx + dx, y)
			if floor_mask.has(cell):
				out[cell] = true
				if absi(dx) <= 1:
					flow[cell] = true


func _paint_ground(ground: TileMapLayer, floor_mask: Dictionary, void_mask: Dictionary) -> void:
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, SRC_TERRAIN, MapKit._pick(FLOOR, cell, 451))
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, SRC_WALL, MapKit._pick(VOID, cell, 452))


## Paint the sewage with its authored banks, then run the animated tile down the
## interior only — over a bank cell it would cover the edge and reinstate a seam.
##
## The bank ring is lifted onto [param trim], one layer above the ground, for the
## same reason the raised slab's rim is. Only the blob's fill tile is fully
## opaque; each of the eight edge pieces keeps six to ten percent of its cell
## bare so the lip can be composited over whatever the shore happens to be. Left
## on the ground layer they replace the floor cell outright, and that bare margin
## then shows the map background — a hairline of it down every shoreline in the
## zone, running right beside the quays.
func _paint_slime(ground: TileMapLayer, trim: TileMapLayer, slime: Dictionary,
		flow: Dictionary) -> int:
	MapKit.paint_blob(ground, slime, _slime_spec())
	var fill: Vector2i = _slime_spec().fill
	for cell: Vector2i in slime.keys():
		if ground.get_cell_source_id(cell) != SRC_TERRAIN:
			continue
		var tile := ground.get_cell_atlas_coords(cell)
		if tile == fill:
			continue
		# Same seed as `_paint_ground`, so the floor put back underneath is the
		# variant that was there before the blob overwrote it.
		ground.set_cell(cell, SRC_TERRAIN, MapKit._pick(FLOOR, cell, 451))
		trim.set_cell(cell, SRC_TERRAIN, tile)
	var flowing: int = 0
	for cell: Vector2i in flow.keys():
		# Interior only. The animated tile is a different green from the blob
		# fill, so scattering it randomly across a river turned the liquid into a
		# two-tone patchwork of blocks; confined to the centreline it reads as
		# current running down the middle of the channel.
		if not slime.has(cell):
			continue
		if not (slime.has(cell + Vector2i(0, -1)) and slime.has(cell + Vector2i(0, 1))
				and slime.has(cell + Vector2i(-1, 0)) and slime.has(cell + Vector2i(1, 0))):
			continue
		ground.set_cell(cell, SRC_SEWAGE, SEWAGE)
		flowing += 1
	return flowing


func _require(ts: TileSet) -> void:
	var slime := _slime_spec()
	var ws := _wall_spec()
	var checks: Array = [
		[SRC_TERRAIN, FLOOR], [SRC_TERRAIN, DARK], [SRC_WALL, VOID],
		[SRC_SEWAGE, [SEWAGE]], [SRC_WALL, ws.rim + ws.body + ws.base + ws.alcove],
		[SRC_TERRAIN, [slime.fill, slime.n, slime.s, slime.w, slime.e,
			slime.nw, slime.ne, slime.sw, slime.se]],
	]
	for c in checks:
		var src := ts.get_source(int(c[0])) as TileSetAtlasSource
		assert(src != null, "tileset missing source %d" % int(c[0]))
		for coord: Vector2i in c[1]:
			assert(src.has_tile(coord), "source %d has no tile %s" % [int(c[0]), coord])


func _populate(walk: Dictionary, taken: Dictionary, spots: Array, gap: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for wanted: Vector2i in spots:
		var pool: Dictionary = {}
		for cell: Vector2i in walk.keys():
			if not taken.has(cell):
				pool[cell] = true
		if pool.is_empty():
			out.append(wanted)
			continue
		var cell := LevelKit.pick_open(pool, wanted)
		out.append(cell)
		for oy in range(-gap, gap + 1):
			for ox in range(-gap, gap + 1):
				taken[cell + Vector2i(ox, oy)] = true
	return out


## Expand [name, type, spot, count] rows into individual hostiles spread around
## their authored anchor, which is how the surface map's roster is written.
func _mobs(walk: Dictionary, taken: Dictionary, plan: Array, gap: int) -> Array:
	var spots: Array[Vector2i] = []
	var names: Array[String] = []
	var types: Array[String] = []
	for row in plan:
		var count: int = int(row[3])
		for i in count:
			var ring: Vector2i = Vector2i(
				int(round(cos(float(i) * 2.1) * float(gap) * 1.6)),
				int(round(sin(float(i) * 2.1) * float(gap) * 1.6)))
			spots.append(row[2] + ring)
			names.append("%s%d" % [row[0], i + 1] if count > 1 else str(row[0]))
			types.append(row[1])
	var cells := _populate(walk, taken, spots, gap)
	var out: Array = []
	for i in cells.size():
		out.append({
			"name": names[i],
			"type": TYPES + types[i] + ".tres",
			"pos": LevelKit.tile_pos_sized(cells[i], TILE),
		})
	return out


func _lights(name: String, cells: Array[Vector2i], colour: String, energy: float,
		scale: float) -> Array:
	var out: Array = []
	for i in cells.size():
		out.append({
			"name": "%s%d" % [name, i + 1],
			"pos": LevelKit.tile_pos_sized(cells[i], TILE),
			"color": colour,
			"energy": energy,
			"scale": scale,
		})
	return out


# --- landmarks --------------------------------------------------------------

func _slab_tile(i: int, j: int, w: int, h: int) -> Vector2i:
	if j == 0:
		if i == 1:
			return SLAB_NCAP_W
		if i == w - 2:
			return SLAB_NCAP_E
		return SLAB_NCAP if i >= 2 and i <= w - 3 else NO_TILE
	if j == h - 1:
		if i == 1:
			return SLAB_SCAP_W
		if i == w - 2:
			return SLAB_SCAP_E
		return SLAB_SCAP if i >= 2 and i <= w - 3 else NO_TILE
	if j == 1:
		if i == 0:
			return SLAB_NW_O
		if i == 1:
			return SLAB_NW_I
		if i == w - 2:
			return SLAB_NE_I
		if i == w - 1:
			return SLAB_NE_O
	elif j == h - 2:
		if i == 0:
			return SLAB_SW_O
		if i == 1:
			return SLAB_SW_I
		if i == w - 2:
			return SLAB_SE_I
		if i == w - 1:
			return SLAB_SE_O
	else:
		if i == 0:
			return SLAB_W
		if i == w - 1:
			return SLAB_E
	return MapKit._pick(SLAB_FILL, Vector2i(i, j), 9901)


## Paint a raised stone slab with its top-left at [param origin], and return the
## cells it covered. The slab carries no collision, so a boss arena or a quay
## never becomes something the player has to path around.
##
## Two layers, not one, and that split is the whole point of this function.
## Only the five interior tiles of this set are fully opaque. Every cap, edge and
## corner piece is a curve or a lip with bare canvas around it — the outer
## corners cover barely a third of their cell, the long edges about half —
## because the artist drew them to be composited OVER ground. Painted onto the
## ground layer they REPLACE the floor cell, and the bare part of the tile then
## shows the map background: that is where the grey notches on every quay corner
## and the grey stripe down both of its long edges came from.
##
## So the fill becomes the new floor surface on [param ground], and the trim goes
## on [param trim] one layer up with the original floor left untouched beneath
## it. The transparent parts then read as floor meeting stone, which is what the
## curve was drawn to show.
##
## Cells written to [param trim] are also recorded in [param rim_out], so callers
## can keep later scatter passes from stamping a prop through the slab's edge.
##
## Refuses rather than half-paints. A slab clipped by the zone boundary or by a
## river shows a broken rim, and every caller has other anchors to try.
func _slab(ground: TileMapLayer, trim: TileMapLayer, origin: Vector2i,
		size: Vector2i, allowed: Dictionary, rim_out: Dictionary) -> Dictionary:
	if size.x < SLAB_MIN or size.y < SLAB_MIN:
		return {}
	for j in size.y:
		for i in size.x:
			if not allowed.has(origin + Vector2i(i, j)):
				return {}
	var out: Dictionary = {}
	for j in size.y:
		for i in size.x:
			var tile := _slab_tile(i, j, size.x, size.y)
			if tile == NO_TILE:
				continue
			var cell: Vector2i = origin + Vector2i(i, j)
			if SLAB_FILL.has(tile):
				ground.set_cell(cell, SRC_TERRAIN, tile)
			else:
				trim.set_cell(cell, SRC_TERRAIN, tile)
				rim_out[cell] = true
			out[cell] = true
	return out


## Vertical extent of the sewage on column [param x], searched outward from
## [param near]. Returns (-1, -1) when the column is dry within reach.
func _slime_span_v(slime: Dictionary, x: int, near: int) -> Vector2i:
	var at := near
	if not slime.has(Vector2i(x, at)):
		at = -1
		for d in range(1, 20):
			if slime.has(Vector2i(x, near - d)):
				at = near - d
				break
			if slime.has(Vector2i(x, near + d)):
				at = near + d
				break
		if at < 0:
			return NO_TILE
	var top := at
	while slime.has(Vector2i(x, top - 1)):
		top -= 1
	var bottom := at
	while slime.has(Vector2i(x, bottom + 1)):
		bottom += 1
	return Vector2i(top, bottom)


## Horizontal counterpart, for a river running north-south.
func _slime_span_h(slime: Dictionary, y: int, near: int) -> Vector2i:
	var at := near
	if not slime.has(Vector2i(at, y)):
		at = -1
		for d in range(1, 20):
			if slime.has(Vector2i(near - d, y)):
				at = near - d
				break
			if slime.has(Vector2i(near + d, y)):
				at = near + d
				break
		if at < 0:
			return NO_TILE
	var left := at
	while slime.has(Vector2i(left - 1, y)):
		left -= 1
	var right := at
	while slime.has(Vector2i(right + 1, y)):
		right += 1
	return Vector2i(left, right)


## A run of raised quays along one side of an east-west river. [param side] is
## -1 for the north bank, +1 for the south.
##
## Segments rather than one continuous ribbon on purpose. The bank noise moves
## in RUN-cell steps, so a single slab spanning the zone would either float over
## the channel wherever the water bulges in, or leave a widening strip of bare
## floor wherever it falls away. Each segment is placed against the *narrowest*
## point of the stretch it covers, so it clears the water along its whole length.
func _embankment_h(ground: TileMapLayer, trim: TileMapLayer, slime: Dictionary,
		dry: Dictionary, base_y: int, side: int, x_from: int, x_to: int,
		seg: int, gap: int, height: int, rim_out: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var x := x_from
	while x + seg <= x_to:
		var edge: int = 1 << 30 if side < 0 else -(1 << 30)
		var ok := true
		for i in seg:
			var span := _slime_span_v(slime, x + i, base_y)
			if span == NO_TILE:
				ok = false
				break
			edge = mini(edge, span.x) if side < 0 else maxi(edge, span.y)
		if ok:
			var origin := Vector2i(x, edge - height if side < 0 else edge + 1)
			for cell: Vector2i in _slab(ground, trim, origin, Vector2i(seg, height),
					dry, rim_out).keys():
				out[cell] = true
		x += seg + gap
	return out


## Vertical counterpart. [param side] is -1 for the west bank, +1 for the east.
func _embankment_v(ground: TileMapLayer, trim: TileMapLayer, slime: Dictionary,
		dry: Dictionary, base_x: int, side: int, y_from: int, y_to: int,
		seg: int, gap: int, width: int, rim_out: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var y := y_from
	while y + seg <= y_to:
		var edge: int = 1 << 30 if side < 0 else -(1 << 30)
		var ok := true
		for i in seg:
			var span := _slime_span_h(slime, y + i, base_x)
			if span == NO_TILE:
				ok = false
				break
			edge = mini(edge, span.x) if side < 0 else maxi(edge, span.y)
		if ok:
			var origin := Vector2i(edge - width if side < 0 else edge + 1, y)
			for cell: Vector2i in _slab(ground, trim, origin, Vector2i(width, seg),
					dry, rim_out).keys():
				out[cell] = true
		y += seg + gap
	return out


## A plank bridge running north-south, [param width] columns wide, spanning the
## sewage on column [param x] with two cells of landing on each bank.
##
## Painted onto the props layer and deliberately never recorded as solid. The
## sewage underneath is already walkable, so a bridge that blocked would take
## away crossings rather than add them.
## Every cell is recorded in [param taken] — not to block movement, but so the
## shore scatter that runs later cannot stamp a drainage mouth across the deck.
func _bridge_v(props: TileMapLayer, slime: Dictionary, walk: Dictionary,
		taken: Dictionary, x: int, near_y: int, width: int) -> int:
	var span := _slime_span_v(slime, x, near_y)
	if span == NO_TILE:
		return 0
	var y0: int = span.x - 2
	var y1: int = span.y + 2
	for dx in width:
		for y in [y0, y1]:
			if not walk.has(Vector2i(x + dx, y)):
				return 0
	var n := 0
	for dx in width:
		for y in range(y0, y1 + 1):
			var cell := Vector2i(x + dx, y)
			var tile := PLANK_V_N if y == y0 else (
				PLANK_V_S if y == y1 else MapKit._pick(PLANK_V_MID, cell, 9902))
			props.set_cell(cell, SRC_PROPS, tile)
			# A two-cell apron either side, so a prop cannot crowd the landing.
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					taken[cell + Vector2i(ox, oy)] = true
			n += 1
	return n


## East-west counterpart. The art is two rows deep — a cap row of planks and the
## deck below it — so [param height] repeats the deck row to widen the crossing.
func _bridge_h(props: TileMapLayer, slime: Dictionary, walk: Dictionary,
		taken: Dictionary, y: int, near_x: int, height: int) -> int:
	var span := _slime_span_h(slime, y, near_x)
	if span == NO_TILE:
		return 0
	var x0: int = span.x - 2
	var x1: int = span.y + 2
	for dy in height:
		for x in [x0, x1]:
			if not walk.has(Vector2i(x, y + dy)):
				return 0
	var n := 0
	for x in range(x0, x1 + 1):
		var top := PLANK_H_W if x == x0 else (
			PLANK_H_E if x == x1 else MapKit._pick(PLANK_H_MID, Vector2i(x, y), 9903))
		props.set_cell(Vector2i(x, y), SRC_PROPS, top)
		for dy in range(1, height):
			props.set_cell(Vector2i(x, y + dy), SRC_PROPS, top + Vector2i(0, 1))
		for dy in range(-2, height + 2):
			for ox in range(-2, 3):
				taken[Vector2i(x + ox, y + dy)] = true
		n += height
	return n


## Stamp a WxH block of one atlas rect, without recording it as solid. For the
## set dressing that must never become an obstacle: outfalls, grates, benches.
func _stamp(layer: TileMapLayer, source: int, base: Vector2i, origin: Vector2i,
		size: Vector2i, allowed: Dictionary, taken: Dictionary) -> bool:
	for j in size.y:
		for i in size.x:
			var cell: Vector2i = origin + Vector2i(i, j)
			if not allowed.has(cell) or taken.has(cell):
				return false
	for j in size.y:
		for i in size.x:
			var cell: Vector2i = origin + Vector2i(i, j)
			layer.set_cell(cell, source, base + Vector2i(i, j))
			taken[cell] = true
	return true


## A free-standing column, standing on [param foot]. Painted on the wall source,
## so unlike the rest of the dressing this one really does collide — that is the
## point of a pillar. Callers re-derive the walkable region afterwards so a
## cluster can never quietly seal a pocket off.
func _pillar(walls: TileMapLayer, foot: Vector2i, allowed: Dictionary,
		solid: Dictionary) -> bool:
	var origin: Vector2i = foot - Vector2i(0, 2)
	for j in 3:
		for i in 2:
			if not allowed.has(origin + Vector2i(i, j)):
				return false
	for j in 3:
		for i in 2:
			var cell: Vector2i = origin + Vector2i(i, j)
			walls.set_cell(cell, SRC_WALL, PILLAR + Vector2i(i, j))
			solid[cell] = true
			allowed.erase(cell)
	return true


## A stub of ruined wall: the body and base rows of a standard run, without the
## rim, so it reads as a foundation course left behind rather than a wall that
## has been cut off at the top.
func _foundation(walls: TileMapLayer, start: Vector2i, run: int,
		spec: MapKit.WallSpec, allowed: Dictionary, solid: Dictionary) -> bool:
	for i in run:
		for j in [-1, 0]:
			if not allowed.has(start + Vector2i(i, j)):
				return false
	for i in run:
		var top: Vector2i = start + Vector2i(i, -1)
		var bottom: Vector2i = start + Vector2i(i, 0)
		walls.set_cell(top, SRC_WALL, MapKit._pick(spec.body, top, 9904))
		walls.set_cell(bottom, SRC_WALL, MapKit._pick(spec.base, bottom, 9905))
		for cell in [top, bottom]:
			solid[cell] = true
			allowed.erase(cell)
	return true


## Cut a bay northward out of the zone's north boundary and return its centre.
##
## Done on the floor mask before the walls are painted, so `paint_wall3` re-forms
## a three-tile wall around the new edge and the recess reads as a chamber carved
## into the rock. Adding the floor afterwards would leave it as an unexplained
## lobe of open ground with the old wall still standing across its mouth.
func _recess(floor_mask: Dictionary, cx: int, half_w: int, depth: int) -> Vector2i:
	var top := -1
	for y in H:
		if floor_mask.has(Vector2i(cx, y)):
			top = y
			break
	if top < 0:
		return NO_TILE
	# Leave four rows of void above: `paint_wall3` refuses a run unless all three
	# of its rows are void, so a recess cut flush to the edge gets no wall.
	var y0: int = maxi(4, top - depth)
	if y0 >= top:
		return NO_TILE
	for y in range(y0, top + 1):
		for x in range(cx - half_w, cx + half_w + 1):
			if x < 2 or x >= W - 2:
				continue
			floor_mask[Vector2i(x, y)] = true
	return Vector2i(cx, y0 + (top - y0) / 2)


## The Secret Lab set piece. The capsule bank and its liquid are two decos at one
## position rather than one composited sprite: the pack ships the glow as a
## separate eight-frame layer drawn on the same 185x181 canvas, which is what
## lets the capsules pulse and carry their own light.
func _lab_decos(prefix: String, at: Vector2i) -> Array:
	var base := LevelKit.tile_pos_sized(at, TILE)
	return [
		{"name": prefix + "Capsules", "frames": "deco_lab_capsules",
			"pos": base + Vector2(-56, 0)},
		{"name": prefix + "Liquid", "frames": "deco_lab_capsule_liquid",
			"pos": base + Vector2(-56, 0),
			"light": 0.65, "color": "Color(0.38, 1.0, 0.45, 1)"},
		{"name": prefix + "Engine", "frames": "deco_lab_steam_engine",
			"pos": base + Vector2(84, 10),
			"light": 0.40, "color": "Color(1.0, 0.6, 0.25, 1)"},
		{"name": prefix + "Wires", "frames": "deco_lab_wires",
			"pos": base + Vector2(16, -54)},
		# Two single capsules out at the edges of the bay, so the chamber reads as
		# a row of specimens rather than one machine sitting on its own.
		{"name": prefix + "CapsuleW", "frames": "deco_lab_capsule_small",
			"pos": base + Vector2(-176, -18),
			"light": 0.28, "color": "Color(0.38, 1.0, 0.45, 1)"},
		{"name": prefix + "CapsuleE", "frames": "deco_lab_capsule_small",
			"pos": base + Vector2(170, -34),
			"light": 0.28, "color": "Color(0.38, 1.0, 0.45, 1)"},
	]


## Cut the lab recesses out of the north boundary. Must run before the walls are
## painted; `_dress_labs` fills them in once the walkable set exists.
func _lab_recesses(floor_mask: Dictionary, columns: Array, depth: int) -> Array[Vector2i]:
	var centres: Array[Vector2i] = []
	for cx: int in columns:
		var at := _recess(floor_mask, cx, 7, depth)
		if at != NO_TILE:
			centres.append(at)
	return centres


## Fill the recesses: capsule banks, engines and cabling as decos, the bench and
## its glassware as tiles. Returns the decos for the scene config.
##
## Must run BEFORE `_dress_banks` on any zone whose recesses sit near the water.
## The other way round, the shore scatter claims the cells inside the recess
## first and the bench then has nowhere to stand — which is exactly what left the
## Cistern's four chambers with no benches at all.
func _dress_labs(ground: TileMapLayer, props: TileMapLayer, overlay: TileMapLayer,
		centres: Array, walk: Dictionary, taken: Dictionary) -> Array:
	var decos: Array = []
	for i in centres.size():
		var at: Vector2i = centres[i]
		var prefix := "Lab%d" % (i + 1)
		decos.append_array(_lab_decos(prefix, at))
		# Bench to the left of the capsule bank. The glassware goes on the
		# OVERLAY over the bench's own last row — that row is the table top, and
		# the overlay draws above the props layer, so the flasks stand on it
		# rather than having to find a free cell of floor beside it.
		# Several anchors tried in turn rather than one fixed offset. A recess is
		# only as deep as the boundary at that column allowed, so on a shallow one
		# the first anchor can fall on the wall course or on ground a ruin already
		# claimed, and a single attempt silently left chambers with no bench.
		for anchor in [
			at + Vector2i(-6, -1), at + Vector2i(-6, 0), at + Vector2i(5, -1),
			at + Vector2i(5, 0), at + Vector2i(-4, 1), at + Vector2i(3, 1),
		]:
			if not _stamp(props, SRC_PROPS, ALCHEMY, anchor, Vector2i(2, 4), walk, taken):
				continue
			for offset in [Vector2i(0, 3), Vector2i(1, 3), Vector2i(0, 4), Vector2i(1, 4)]:
				var spot: Vector2i = anchor + offset
				if walk.has(spot) and overlay.get_cell_source_id(spot) < 0:
					overlay.set_cell(spot, SRC_PROPS, MapKit._pick(FLASKS, spot, 9906))
			break
		# A grate underfoot, so the chamber drains somewhere. The terrain SOURCE
		# but the trim LAYER: stamping it from the props source wrote a
		# coordinate that source does not have, and stamping it onto the ground
		# layer replaced the floor with a drain cover that is two thirds bare
		# canvas. It is a lid, so it goes over the floor like the rest of the trim.
		var _ok := _stamp(props, SRC_TERRAIN, GRATE, at + Vector2i(2, 3),
			Vector2i(3, 3), walk, taken)
	return decos


## Floor cells within [param reach] of sewage but not sewage themselves — the
## shore strip that every river-side prop wants.
func _bank_cells(walk: Dictionary, slime: Dictionary, reach: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in walk.keys():
		if slime.has(cell):
			continue
		var near := false
		for oy in range(-reach, reach + 1):
			for ox in range(-reach, reach + 1):
				if slime.has(cell + Vector2i(ox, oy)):
					near = true
					break
			if near:
				break
		if near:
			out.append(cell)
	return out


## Shore dressing, shared by all three zones: drainage mouths pouring into the
## channel, crates adrift on it, and webs and bones along the dry strip.
##
## None of it is recorded as solid. This is set dressing, not cover, and the
## collision audit floods the whole zone — a crate that blocked would show up
## there as a hole in the reachable set for no gameplay gain.
func _dress_banks(props: TileMapLayer, overlay: TileMapLayer, walk: Dictionary,
		slime: Dictionary, taken: Dictionary, seed_v: int) -> Dictionary:
	var bank := _bank_cells(walk, slime, 3)
	var counts := {"outfall": 0, "pipe": 0, "crate": 0, "web": 0, "bone": 0}

	# Big 3x3 mouths, set back so the whole ring lands on dry ground. Kept sparse:
	# the mouth is a dark ring nearly a metre across in play, and at any higher
	# density the bank reads as perforated rather than as having drains on it.
	for cell in MapKit.scatter(bank, 0.045, 14, seed_v):
		if _stamp(props, SRC_PROPS, OUTFALL, cell, Vector2i(3, 3), walk, taken):
			counts["outfall"] += 1
	# Smaller outlets between them.
	for cell in MapKit.scatter(bank, 0.10, 6, seed_v + 1):
		if taken.has(cell):
			continue
		props.set_cell(cell, SRC_PROPS, MapKit._pick(PIPE_SEG, cell, 9907))
		taken[cell] = true
		counts["pipe"] += 1

	# Crates adrift. Restricted to sewage that is sewage on every side, so a
	# crate never straddles the bank tiles and breaks the shoreline.
	var afloat: Array[Vector2i] = []
	for cell: Vector2i in slime.keys():
		var inner := true
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				if not slime.has(cell + Vector2i(ox, oy)):
					inner = false
					break
			if not inner:
				break
		if inner:
			afloat.append(cell)
	for cell in MapKit.scatter(afloat, 0.09, 7, seed_v + 2):
		var rect: Array = CRATES[MapKit.hash2(cell.x, cell.y, seed_v + 3) % CRATES.size()]
		if _stamp(props, SRC_PROPS, Vector2i(rect[0], rect[1]), cell,
				Vector2i(rect[2], rect[3]), slime, taken):
			counts["crate"] += 1

	# Bones on the dry strip, webs above them on the overlay.
	for cell in MapKit.scatter(bank, 0.11, 5, seed_v + 4):
		var rect: Array = SKELETONS[MapKit.hash2(cell.x, cell.y, seed_v + 5) % SKELETONS.size()]
		if _stamp(props, SRC_PROPS, Vector2i(rect[0], rect[1]), cell,
				Vector2i(rect[2], rect[3]), walk, taken):
			counts["bone"] += 1
	for cell in MapKit.scatter(bank, 0.13, 4, seed_v + 6):
		if overlay.get_cell_source_id(cell) >= 0:
			continue
		overlay.set_cell(cell, SRC_PROPS, MapKit._pick(WEBS, cell, 9908))
		counts["web"] += 1
	return counts


## Flatten a dressing tally into one reportable line.
func _counts(tally: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in tally.keys():
		parts.append("%s=%d" % [key, int(tally[key])])
	return " ".join(parts)


## Evenly spaced sample of a mask, for dropping lights along a river.
func _sample(mask: Dictionary, step: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	var keys: Array = mask.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a.x * 10000 + a.y) < (b.x * 10000 + b.y))
	for cell: Vector2i in keys:
		var k := Vector2i(cell.x / step, cell.y / step)
		if seen.has(k):
			continue
		seen[k] = true
		out.append(cell)
	return out


# --- The Sewers (surface hub) ------------------------------------------------
# The widest, flattest of the three: a single hall the whole zone across, one
# river bending through it and a shallow branch off the north side. This map is
# the hub, so it carries entrance 28, the overworld portal 128 and the three
# landing/stair pairs down to the sub-levels.

func _build_sewers() -> void:
	_size(140, 105)
	var ts: TileSet = load(TS)
	_require(ts)
	var ground := _layer(ts)
	var walls := _layer(ts)
	var props := _layer(ts)
	var overlay := _layer(ts)

	var floor_mask := _seal_interior(_open_zone(6, 0.16, 7101))
	var slime: Dictionary = {}
	var flow: Dictionary = {}
	_river(slime, flow, floor_mask, float(H) * 0.56, 7.0, 0.055, 5, 7110)
	_river_v(slime, flow, floor_mask, float(W) * 0.30, 5.0, 0.06, 4, 7111)

	# Cut after the rivers, not before: the vertical channel runs the full height
	# of the zone, and a recess opened first at one of its columns would simply
	# fill with sewage. The columns below sit clear of it either way.
	var labs := _lab_recesses(floor_mask, [20, 62, 94, 122], 7)

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	_paint_ground(ground, floor_mask, void_mask)
	var flowing := _paint_slime(ground, props, slime, flow)

	var blocked: Dictionary = {}
	var runs := MapKit.paint_wall3(walls, overlay, floor_mask, void_mask, _wall_spec(),
		_bounds, blocked, 8, 7120)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, Vector2i(W / 2, H - 12))
	walk = MapKit.largest_region(walk, entrance)
	var portal := LevelKit.pick_open(walk, entrance + Vector2i(0, 5))
	# Pulled south off the north wall so the boss arena and the lab recesses are
	# not competing for the same strip of ground, and so there is room to fight
	# all the way around the platform.
	var boss_cell := LevelKit.pick_open(walk, Vector2i(W / 2, 24))

	# The centrepiece: a 12x12 raised slab for the Cistern Sovereign, with a
	# drainage mouth overhanging the middle of each of its four edges.
	var dry: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not slime.has(cell):
			dry[cell] = true
	var arena_origin: Vector2i = boss_cell - Vector2i(6, 6)
	# One dressing set for the whole zone, so the bank scatter and the lab fit-out
	# below can see what the arena already claimed. The slab's trim goes into it
	# too, which is what stops a later prop being stamped through the platform rim.
	var placed: Dictionary = {}
	var arena := _slab(ground, props, arena_origin, Vector2i(12, 12), dry, placed)
	var outfalls: int = 0
	# Clear of the slab rather than overhanging it. The rim now lives on the props
	# layer, and a mouth that overlapped it would either be refused or paint over
	# the platform edge — set just outside, it reads as pouring toward the arena.
	for spot in [
		arena_origin + Vector2i(5, -3), arena_origin + Vector2i(5, 12),
		arena_origin + Vector2i(-3, 5), arena_origin + Vector2i(12, 5),
	]:
		if _stamp(props, SRC_PROPS, OUTFALL, spot, Vector2i(3, 3), walk, placed):
			outfalls += 1

	var free: Dictionary = {}
	var no_build := LevelKit.keepout([entrance, portal], 6)
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell) and not slime.has(cell) and not arena.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 5)
	LevelKit.scatter_props(props, SRC_PROPS, edges, CRATES, 0.22, 3, 7130, free, solid)
	LevelKit.scatter_props(props, SRC_PROPS, inner, SKELETONS, 0.14, 4, 7131, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)
	LevelKit.scatter_flat(overlay, SRC_PROPS, edges, WEBS, 0.10, 4, 7132, solid)

	var decos := _dress_labs(ground, props, overlay, labs, walk, placed)
	var shore := _dress_banks(props, overlay, walk, slime, placed, 7140)

	var taken := LevelKit.keepout([entrance, portal], 9)
	for cell: Vector2i in LevelKit.keepout([boss_cell], 12).keys():
		taken[cell] = true
	# Nothing spawns on top of the dressing, so a crate or a capsule bank never
	# ends up wearing a mob.
	for cell: Vector2i in placed.keys():
		taken[cell] = true
	var hostiles := _mobs(walk, taken, [
		["Slime", "trpg/trpg_slime", Vector2i(int(W * 0.34), int(H * 0.62)), 3],
		["SlimeE", "trpg/trpg_slime", Vector2i(int(W * 0.66), int(H * 0.62)), 3],
		["Bat", "trpg/trpg_bat", Vector2i(int(W * 0.18), int(H * 0.48)), 3],
		["BatE", "trpg/trpg_bat", Vector2i(int(W * 0.82), int(H * 0.48)), 3],
		["SewerSkeleton", "trpg/trpg_sewer_skeleton", Vector2i(W / 2, int(H * 0.44)), 3],
		["AcidOoze", "trpg/trpg_acid_ooze", Vector2i(int(W * 0.24), int(H * 0.26)), 2],
		["AcidOozeE", "trpg/trpg_acid_ooze", Vector2i(int(W * 0.76), int(H * 0.26)), 2],
		["Crawler", "trpg/trpg_carrion_crawler", Vector2i(int(W * 0.32), int(H * 0.38)), 2],
		["CrawlerE", "trpg/trpg_carrion_crawler", Vector2i(int(W * 0.68), int(H * 0.38)), 2],
		["ZombieGiant", "trpg/trpg_zombie_giant", Vector2i(int(W * 0.26), int(H * 0.34)), 2],
		["ZombieGiantE", "trpg/trpg_zombie_giant", Vector2i(int(W * 0.74), int(H * 0.34)), 2],
		["SewerGorgon", "trpg/trpg_sewer_gorgon", Vector2i(int(W * 0.40), int(H * 0.30)), 2],
		["SewerGorgonE", "trpg/trpg_sewer_gorgon", Vector2i(int(W * 0.60), int(H * 0.30)), 2],
		["Devourer", "trpg/trpg_intellect_devourer", Vector2i(W / 2, int(H * 0.34)), 2],
		["CisternHulk", "trpg/trpg_cistern_hulk", Vector2i(W / 2, int(H * 0.24)), 2],
	], 5)
	hostiles.append({
		"name": "BloatedSovereign",
		"type": TYPES + "bosses/cistern_sovereign.tres",
		"pos": LevelKit.tile_pos_sized(boss_cell, TILE),
	})

	# Landing / stair pairs are placed far apart so the two descents never sit on
	# the same wing of the hall, and below the lab recesses so a stairway never
	# opens in the middle of one.
	var gutter_land := LevelKit.pick_open(walk, Vector2i(14, 20))
	var cistern_land := LevelKit.pick_open(walk, Vector2i(W - 14, 20))
	var ossuary_land := LevelKit.pick_open(walk, Vector2i(W / 2 - 4, H - 16))

	var glow := _sample(slime, 26)
	assert(walk.has(entrance) and walk.has(portal), "sewers spawn blocked")
	assert(walk.size() > 4000, "sewers too small: %d" % walk.size())
	assert(not arena.is_empty(), "sewers boss platform did not fit")
	_report.append("  sewers        walk=%d walls=%d runs=%d slime=%d flow=%d mobs=%d" % [
		walk.size(), walls.get_used_cells().size(), runs, slime.size(), flowing, hostiles.size()])
	_report.append("                arena=%d outfalls=%d labs=%d %s" % [
		arena.size(), outfalls, labs.size(), _counts(shore)])

	LevelKit.write_map({
		"root": "sewers",
		"out": MAPS + "sewers.tscn",
		"tileset": TS,
		"bg": "Color(0.015, 0.025, 0.02, 1)",
		"modulate": "Color(0.50, 0.54, 0.50, 1)",
		"music": "res://assets/audio/music/alone.ogg",
		"layers": {
			"Ground": LevelKit.b64(ground), "Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props), "Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * TILE + TILE, "cam_bottom": H * TILE + TILE,
		"lights": _lights("SewerGlow", glow, "Color(0.45, 0.95, 0.5, 1)", 0.20, 1.6),
		"camps": [{"name": "Campfire", "pos": LevelKit.tile_pos_sized(entrance + Vector2i(2, -2), TILE)}],
		"decos": decos,
		"hostiles": hostiles,
		"npcs": [],
		"spawn": LevelKit.tile_pos_sized(entrance, TILE),
		"warpers": [
			{"name": "Entrance", "pos": LevelKit.tile_pos_sized(entrance, TILE), "id": 28},
			{"name": "GutterLanding", "pos": LevelKit.tile_pos_sized(gutter_land, TILE), "id": 52},
			{"name": "CisternLanding", "pos": LevelKit.tile_pos_sized(cistern_land, TILE), "id": 53},
			{"name": "OssuaryLanding", "pos": LevelKit.tile_pos_sized(ossuary_land, TILE), "id": 56},
		],
		"portals": [
			{"name": "Portal", "pos": LevelKit.tile_pos_sized(portal, TILE), "id": 128,
				"target_id": 28, "instance": OVERWORLD, "label": "Castle Garden",
				"color": "Color(0, 0.53, 0.27, 1)"},
			{"name": "GutterStair", "pos": LevelKit.tile_pos_sized(gutter_land + Vector2i(0, 2), TILE),
				"id": 152, "target_id": 42, "instance": INST + "gutterworks.tres",
				"label": "The Gutterworks", "color": "Color(0.45, 0.7, 0.5, 1)"},
			{"name": "CisternStair", "pos": LevelKit.tile_pos_sized(cistern_land + Vector2i(0, 2), TILE),
				"id": 153, "target_id": 43, "instance": INST + "drowned_cistern.tres",
				"label": "The Drowned Cistern", "color": "Color(0.2, 0.5, 0.55, 1)"},
			{"name": "OssuaryStair", "pos": LevelKit.tile_pos_sized(ossuary_land + Vector2i(0, 2), TILE),
				"id": 156, "target_id": 46, "instance": INST + "ossuary.tres",
				"label": "The Ossuary", "color": "Color(0.45, 0.28, 0.7, 1)"},
		],
	})


# --- The Gutterworks --------------------------------------------------------
# The lowest and wettest of the three: two broad rivers converging across an
# open works floor, lit green off the sewage itself.

func _build_gutterworks() -> void:
	_size(200, 150)
	var ts: TileSet = load(TS)
	var ground := _layer(ts)
	var walls := _layer(ts)
	var props := _layer(ts)
	var overlay := _layer(ts)

	var floor_mask := _seal_interior(_open_zone(7, 0.20, 8201))
	var slime: Dictionary = {}
	var flow: Dictionary = {}
	_river(slime, flow, floor_mask, float(H) * 0.34, 9.0, 0.040, 6, 8210)
	_river(slime, flow, floor_mask, float(H) * 0.70, 9.0, 0.035, 6, 8211)
	_river_v(slime, flow, floor_mask, float(W) * 0.52, 7.0, 0.045, 5, 8212)
	var cross_x: int = int(float(W) * 0.52)
	var north_y: int = int(float(H) * 0.34)
	var south_y: int = int(float(H) * 0.70)

	# Columns chosen clear of the vertical channel, which runs the full height of
	# the zone and would otherwise flood a recess opened on top of it.
	var labs := _lab_recesses(floor_mask, [30, 66, 140, 172], 7)

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	_paint_ground(ground, floor_mask, void_mask)
	var flowing := _paint_slime(ground, props, slime, flow)

	var blocked: Dictionary = {}
	var runs := MapKit.paint_wall3(walls, overlay, floor_mask, void_mask, _wall_spec(),
		_bounds, blocked, 8, 8220)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, Vector2i(W / 2, H - 14))
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + Vector2i(0, 6))

	var dry: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not slime.has(cell):
			dry[cell] = true

	# Raised quays down both banks of all three channels. Segments that fall
	# across an intersection of the cross simply fail to fit and are skipped, so
	# the junctions stay open water.
	#
	# `placed` collects the slabs' trim cells as they are painted. Only the trim,
	# not the whole quay: dressing is welcome on the walkway itself, but a crate
	# or a drainage mouth stamped over the curved edge breaks the one silhouette
	# the embankment has.
	var placed: Dictionary = {}
	var quay: Dictionary = {}
	for run: Array in [
		[north_y, -1], [north_y, 1], [south_y, -1], [south_y, 1],
	]:
		for cell: Vector2i in _embankment_h(ground, props, slime, dry,
				int(run[0]), int(run[1]), 16, W - 16, 22, 8, 5, placed).keys():
			quay[cell] = true
	for side in [-1, 1]:
		for cell: Vector2i in _embankment_v(ground, props, slime, dry, cross_x, side,
				16, H - 16, 22, 8, 5, placed).keys():
			quay[cell] = true

	# Plank crossings over the cross itself. Deliberately not recorded as solid:
	# the sewage is already walkable, so a bridge that blocked would remove
	# crossings rather than add them.
	var planks: int = 0
	for x in [40, 150]:
		planks += _bridge_v(props, slime, walk, placed, x, north_y, 3)
	for x in [56, 160]:
		planks += _bridge_v(props, slime, walk, placed, x, south_y, 3)
	for y in [30, 78, 128]:
		planks += _bridge_h(props, slime, walk, placed, y, cross_x, 3)

	var no_build := LevelKit.keepout([entrance, exit_cell], 6)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell) and not slime.has(cell) and not quay.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 5)
	LevelKit.scatter_props(props, SRC_PROPS, edges, CRATES, 0.24, 3, 8230, free, solid)
	LevelKit.scatter_props(props, SRC_PROPS, inner, SKELETONS, 0.15, 4, 8231, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)
	LevelKit.scatter_flat(overlay, SRC_PROPS, edges, WEBS, 0.11, 4, 8233, solid)
	LevelKit.scatter_flat(props, SRC_PROPS, inner, PIPE_SEG, 0.09, 5, 8234, solid)

	var decos := _dress_labs(ground, props, overlay, labs, walk, placed)
	var shore := _dress_banks(props, overlay, walk, slime, placed, 8240)

	var taken := LevelKit.keepout([entrance, exit_cell], 9)
	for cell: Vector2i in placed.keys():
		taken[cell] = true
	var hostiles := _mobs(walk, taken, [
		["Slime", "trpg/trpg_slime", Vector2i(int(W * 0.22), int(H * 0.72)), 5],
		["GutterBat", "trpg/trpg_bat", Vector2i(int(W * 0.78), int(H * 0.30)), 5],
		["AcidOoze", "trpg/trpg_acid_ooze", Vector2i(int(W * 0.24), int(H * 0.26)), 4],
		["Zombie", "trpg/trpg_zombie_giant", Vector2i(int(W * 0.52), int(H * 0.20)), 3],
		["Crawler", "trpg/trpg_carrion_crawler", Vector2i(int(W * 0.72), int(H * 0.58)), 3],
		["Skeleton", "trpg/trpg_sewer_skeleton", Vector2i(int(W * 0.36), int(H * 0.48)), 4],
	], 5)
	var npc_cells := _populate(walk, taken, [
		entrance + Vector2i(-6, -3), entrance + Vector2i(6, -3)], 3)

	var glow := _sample(slime, 24)
	assert(walk.has(entrance) and walk.has(exit_cell), "gutterworks spawn blocked")
	assert(walk.size() > 6000, "gutterworks too small: %d" % walk.size())
	assert(not quay.is_empty(), "gutterworks embankments did not fit")
	assert(planks > 0, "gutterworks has no plank crossings")
	_report.append("  gutterworks   walk=%d walls=%d runs=%d slime=%d flow=%d mobs=%d" % [
		walk.size(), walls.get_used_cells().size(), runs, slime.size(), flowing, hostiles.size()])
	_report.append("                quay=%d planks=%d labs=%d %s" % [
		quay.size(), planks, labs.size(), _counts(shore)])

	LevelKit.write_map({
		"root": "gutterworks",
		"out": MAPS + "gutterworks.tscn",
		"tileset": TS,
		"bg": "Color(0.02, 0.03, 0.02, 1)",
		"modulate": "Color(0.48, 0.53, 0.48, 1)",
		"music": "res://assets/audio/music/alone.ogg",
		"playlist": ["res://assets/audio/music/army_of_darkness.ogg"],
		"layers": {
			"Ground": LevelKit.b64(ground), "Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props), "Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * TILE + TILE, "cam_bottom": H * TILE + TILE,
		"lights": _lights("SlimeGlow", glow, "Color(0.42, 1.0, 0.45, 1)", 0.21, 1.5),
		"camps": [{"name": "CrewBrazier", "pos": LevelKit.tile_pos_sized(entrance + Vector2i(3, -3), TILE)}],
		"decos": decos,
		"hostiles": hostiles,
		"npcs": [
			{"name": "SluiceWardenObry", "resource": NPCS + "sewers/sluice_warden_obry.tres",
				"pos": LevelKit.tile_pos_sized(npc_cells[0], TILE)},
			{"name": "RatcatcherPell", "resource": NPCS + "sewers/ratcatcher_pell.tres",
				"pos": LevelKit.tile_pos_sized(npc_cells[1], TILE)},
		],
		"spawn": LevelKit.tile_pos_sized(entrance, TILE),
		"warpers": [{"name": "Entrance", "pos": LevelKit.tile_pos_sized(entrance, TILE), "id": 42}],
		"portals": [{
			"name": "DescentPortal", "pos": LevelKit.tile_pos_sized(exit_cell, TILE),
			"id": 142, "target_id": 52, "instance": INST + "sewers.tres",
			"label": "The Sewers", "color": "Color(0.35, 0.62, 0.4, 1)",
		}],
	})


# --- The Drowned Cistern ----------------------------------------------------
# The flooded one: a reservoir that is mostly sewage, crossed by stone
# causeways, with the dry ground pushed out to the rim. Cold cyan ambient.

func _build_cistern() -> void:
	_size(220, 165)
	var ts: TileSet = load(TS)
	var ground := _layer(ts)
	var walls := _layer(ts)
	var props := _layer(ts)
	var overlay := _layer(ts)

	var floor_mask := _seal_interior(_open_zone(7, 0.18, 9301))

	# A broad central lake rather than channels, then causeways cut back through
	# it so the space stays crossable and mobs keep dry ground to hold.
	var slime: Dictionary = {}
	var cx := float(W) * 0.5
	var cy := float(H) * 0.5
	for cell: Vector2i in floor_mask.keys():
		var nx: float = (float(cell.x) - cx) / (float(W) * 0.40)
		var ny: float = (float(cell.y) - cy) / (float(H) * 0.40)
		var d: float = sqrt(nx * nx + ny * ny)
		var n: float = MapKit.value_noise(float(cell.x), float(cell.y), 22.0, 9310)
		if d < 0.95 + 0.35 * (n - 0.5):
			slime[cell] = true
	for cell: Vector2i in floor_mask.keys():
		if absi(cell.y - int(cy)) < 4 or absi(cell.x - int(cx)) < 4:
			slime.erase(cell)

	# The lake reaches almost to the north wall, so the recesses are cut shallow
	# and their columns kept out on the dry rim where the causeway meets it.
	var labs := _lab_recesses(floor_mask, [34, 82, 138, 186], 6)

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	_paint_ground(ground, floor_mask, void_mask)
	# A reservoir is still water; no current ribbon runs across it.
	var flowing := _paint_slime(ground, props, slime, {})

	var blocked: Dictionary = {}
	var runs := MapKit.paint_wall3(walls, overlay, floor_mask, void_mask, _wall_spec(),
		_bounds, blocked, 8, 9320)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, Vector2i(W / 2, H - 14))
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + Vector2i(0, 6))

	var no_build := LevelKit.keepout([entrance, exit_cell], 6)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell) and not slime.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 5)
	LevelKit.scatter_props(props, SRC_PROPS, edges, CRATES, 0.20, 3, 9330, free, solid)
	LevelKit.scatter_props(props, SRC_PROPS, inner, SKELETONS, 0.13, 4, 9331, free, solid)

	# Pillar clusters and ruined foundation courses, to break up the dry fields
	# the causeways and the rim leave. Both are painted on the wall source, so
	# unlike the rest of the dressing they genuinely collide — that is what makes
	# them cover rather than decals. They are placed only on cells that are open
	# on every side for six cells, spaced far enough apart that a cluster cannot
	# bridge to its neighbour, and the walkable set is re-derived below; the
	# collision audit then re-floods the zone from the entrance and would catch
	# any pocket this sealed off.
	# The lab recesses are excluded: they are interior enough to qualify, and a
	# foundation course dropped inside one takes the ground the bench needs.
	var lab_keepout := LevelKit.keepout(labs, 12)
	var open_dry: Array[Vector2i] = []
	for cell: Vector2i in MapKit.interior_cells(walk, blocked, 6):
		if free.has(cell) and not slime.has(cell) and not lab_keepout.has(cell):
			open_dry.append(cell)
	# Foundations first. They need a clear run of up to nine cells, where a pillar
	# needs a 2x3 pocket, so laying the pillars down first left the foundations
	# almost nowhere to go — twelve of them against a hundred and twenty pillars.
	var spec := _wall_spec()
	var foundations: int = 0
	for anchor in MapKit.scatter(open_dry, 0.05, 15, 9341):
		var run: int = 4 + MapKit.hash2(anchor.x, anchor.y, 9342) % 6
		if _foundation(walls, anchor, run, spec, free, solid):
			foundations += 1
	var pillars: int = 0
	for anchor in MapKit.scatter(open_dry, 0.05, 15, 9340):
		for offset in [Vector2i(0, 0), Vector2i(4, 1), Vector2i(2, 5), Vector2i(6, 4)]:
			if _pillar(walls, anchor + offset, free, solid):
				pillars += 1

	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)
	LevelKit.scatter_flat(overlay, SRC_PROPS, edges, WEBS, 0.10, 4, 9332, solid)

	var placed: Dictionary = {}
	var decos := _dress_labs(ground, props, overlay, labs, walk, placed)
	var shore := _dress_banks(props, overlay, walk, slime, placed, 9350)

	var taken := LevelKit.keepout([entrance, exit_cell], 9)
	for cell: Vector2i in placed.keys():
		taken[cell] = true
	var hostiles := _mobs(walk, taken, [
		["Crawler", "trpg/trpg_carrion_crawler", Vector2i(int(W * 0.26), int(H * 0.30)), 4],
		["AcidOoze", "trpg/trpg_acid_ooze", Vector2i(int(W * 0.74), int(H * 0.30)), 4],
		["Gorgon", "trpg/trpg_sewer_gorgon", Vector2i(int(W * 0.26), int(H * 0.70)), 4],
		["Devourer", "trpg/trpg_intellect_devourer", Vector2i(int(W * 0.74), int(H * 0.70)), 4],
		["Zombie", "trpg/trpg_zombie_giant", Vector2i(int(W * 0.50), int(H * 0.22)), 4],
		["Hulk", "trpg/trpg_cistern_hulk", Vector2i(int(W * 0.50), int(H * 0.78)), 4],
	], 5)
	var npc_cells := _populate(walk, taken, [entrance + Vector2i(-6, -3)], 3)

	var glow := _sample(slime, 30)
	assert(walk.has(entrance) and walk.has(exit_cell), "cistern spawn blocked")
	assert(walk.size() > 6000, "cistern too small: %d" % walk.size())
	assert(pillars > 0 and foundations > 0, "cistern has no ruins")
	_report.append("  cistern       walk=%d walls=%d runs=%d slime=%d flow=%d mobs=%d" % [
		walk.size(), walls.get_used_cells().size(), runs, slime.size(), flowing, hostiles.size()])
	_report.append("                pillars=%d foundations=%d labs=%d %s" % [
		pillars, foundations, labs.size(), _counts(shore)])

	LevelKit.write_map({
		"root": "drowned_cistern",
		"out": MAPS + "drowned_cistern.tscn",
		"tileset": TS,
		"bg": "Color(0.012, 0.022, 0.024, 1)",
		# Cold and slightly blue, against the Gutterworks' neutral green.
		"modulate": "Color(0.46, 0.53, 0.58, 1)",
		"music": "res://assets/audio/music/alone.ogg",
		"playlist": ["res://assets/audio/music/fungus.ogg"],
		"layers": {
			"Ground": LevelKit.b64(ground), "Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props), "Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * TILE + TILE, "cam_bottom": H * TILE + TILE,
		"lights": _lights("WaterGlow", glow, "Color(0.38, 0.86, 0.92, 1)", 0.22, 1.7),
		"camps": [{"name": "LandingFire", "pos": LevelKit.tile_pos_sized(entrance + Vector2i(3, -3), TILE)}],
		"decos": decos,
		"hostiles": hostiles,
		"npcs": [
			{"name": "DrownedKeeperVess", "resource": NPCS + "sewers/drowned_keeper_vess.tres",
				"pos": LevelKit.tile_pos_sized(npc_cells[0], TILE)},
		],
		"spawn": LevelKit.tile_pos_sized(entrance, TILE),
		"warpers": [{"name": "Entrance", "pos": LevelKit.tile_pos_sized(entrance, TILE), "id": 43}],
		"portals": [{
			"name": "AscentPortal", "pos": LevelKit.tile_pos_sized(exit_cell, TILE),
			"id": 143, "target_id": 53, "instance": INST + "sewers.tres",
			"label": "The Sewers", "color": "Color(0.35, 0.62, 0.68, 1)",
		}],
	})
