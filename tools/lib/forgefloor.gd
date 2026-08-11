extends RefCounted
## Floor material system for the three Fire Forge levels.
##
## Every Forge map used to fill Ground with six cells out of the DG Fire bank
## that are, on inspection, flat single-colour fills. Six copies of the same
## solid colour is a solid colour: the floor gave the eye nothing to track, so
## walking read as sliding and the levels were hard to navigate.
##
## This file replaces that with a small material vocabulary taken from
## `assets/sprites/environment/fire_forge/tiles.png` — a sheet the biome already
## shipped and never painted. Source id 4 in `fire_forge_tileset.tres`.
##
## The rules a level uses are deliberately few, because a floor that changes
## material for no reason is worse than a flat one. In order of authority:
##
##   1. SLATE is the ground everywhere. Which of its 21 cells a tile gets is
##      chosen by a *value* field, not by a coin flip — see `paint_slate`.
##   2. PLATE is laid where the foundry built something: roads between chambers,
##      work platforms, arrival aprons. It is regular, crisp-edged and lighter,
##      so a player reads it as "this way" from across the screen.
##   3. POOL and GRATE are single authored features, never scattered.
##
## Nothing here is random for its own sake. `MapKit._pick` breaks ties inside a
## bank; the bank itself is always a decision.

class_name ForgeFloor

## Atlas source of `fire_forge/tiles.png` inside `fire_forge_tileset.tres`.
const SOURCE := 4

# --- SLATE: cut volcanic flagstone, the default floor ------------------------
#
# Rows 7-9 x cols 0-6 of the sheet: 21 fully-opaque cells of the same material,
# each with different chisel marks. Split by measured luminance (34.7 - 49.1)
# into three banks so one material can carry a light-to-dark gradient without
# ever changing what it is made of.

const SLATE_DARK: Array[Vector2i] = [
	Vector2i(5, 8), Vector2i(1, 7), Vector2i(3, 7), Vector2i(1, 9), Vector2i(3, 9),
]
const SLATE_MID: Array[Vector2i] = [
	Vector2i(2, 7), Vector2i(5, 9), Vector2i(1, 8), Vector2i(6, 8),
	Vector2i(3, 8), Vector2i(4, 8), Vector2i(2, 9), Vector2i(5, 7), Vector2i(0, 9),
]
const SLATE_LIGHT: Array[Vector2i] = [
	Vector2i(6, 9), Vector2i(4, 9), Vector2i(4, 7), Vector2i(6, 7),
	Vector2i(0, 7), Vector2i(2, 8), Vector2i(0, 8),
]

# --- PLATE: laid foundry paving ---------------------------------------------
#
# The four plain corners of the workshop panel at cols 4-6 / rows 10-12. Their
# mortar joints only line up when they keep their original 2x2 relationship, so
# `plate` indexes them by cell parity. Picking these at random instead produces
# an L-shaped maze of joints — that was tried, and it looks like a bug.

const PLATE_TL := Vector2i(4, 10)
const PLATE_TR := Vector2i(6, 10)
const PLATE_BL := Vector2i(4, 12)
const PLATE_BR := Vector2i(6, 12)

## The same panel used whole: a 3x3 raised work plate with a dark iron centre.
## Anchored by its top-left cell.
const HEARTH_ORIGIN := Vector2i(4, 10)
const HEARTH_SIZE := Vector2i(3, 3)

# --- MOLD PIT: the framed casting pit at cols 1-3 / rows 10-12 --------------
#
# The sheet's other 3x3 panel. Its centre cell is transparent, which is useless
# on Ground — except that a transparent centre is exactly what a casting pit
# wants: the frame goes down on Ground and the hole is filled with the animated
# pour. That one cell blocks, so a player walks the rim and not the metal.
#
# The sheet's quench-water bank (cols 0-5, rows 14-16) is deliberately unused.
# Its interior is a single flat navy, so any pool big enough to read as water is
# a flat rectangle — the exact problem this whole pass exists to fix.

const MOLD_ORIGIN := Vector2i(1, 10)
const MOLD_HOLE := Vector2i(2, 11)
## Animated lava, source 1 of the Forge tileset. Marked blocking there already.
const POUR_SOURCE := 1
const POUR_TILE := Vector2i(0, 0)

# --- Detail ------------------------------------------------------------------

## Loose stone and slag. Transparent — Overlay only, never Ground.
const RUBBLE: Array[Vector2i] = [
	Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(7, 9),
]

## Borderless iron catwalk mesh. ~35% of each cell is see-through, so this goes
## on Props above a painted Ground: the holes show slate, or lava, correctly.
const GRATE: Array[Vector2i] = [
	Vector2i(11, 6), Vector2i(12, 6), Vector2i(13, 6),
	Vector2i(11, 7), Vector2i(13, 7),
	Vector2i(11, 8), Vector2i(12, 8), Vector2i(13, 8),
]


# --- Value field -------------------------------------------------------------

## Chebyshev distance from each floor cell to the nearest non-floor cell, by
## flood fill. This is what lets the floor darken into the wall foot instead of
## meeting the rim as a hard butt joint, which is the single most obvious tell
## that a tile floor was filled by a loop.
static func depth_field(floor_mask: Dictionary) -> Dictionary:
	var dist: Dictionary = {}
	var queue: Array[Vector2i] = []
	for cell: Vector2i in floor_mask.keys():
		var edge := false
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if not floor_mask.has(cell + Vector2i(ox, oy)):
					edge = true
					break
			if edge:
				break
		if edge:
			dist[cell] = 1
			queue.append(cell)
	var qi: int = 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var n: Vector2i = cur + Vector2i(ox, oy)
				if dist.has(n) or not floor_mask.has(n):
					continue
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
	return dist


## Paint the base floor.
##
## `cfg` keys, all optional:
##   `bias`  float  shifts the whole map lighter (+) or darker (-). The Deeps
##                  run negative, the Gallery positive; that difference is most
##                  of why the three levels do not feel like one texture.
##   `scorch` Dictionary  cells forced toward the dark bank — the ash apron
##                  around lava, where the floor is genuinely burnt.
##   `skip`   Dictionary  cells another material already owns.
static func paint_slate(
	ground: TileMapLayer,
	floor_mask: Dictionary,
	depth: Dictionary,
	seed_value: int,
	cfg: Dictionary = {}
) -> int:
	var bias: float = float(cfg.get("bias", 0.0))
	var scorch: Dictionary = cfg.get("scorch", {})
	var skip: Dictionary = cfg.get("skip", {})
	var n: int = 0
	for cell: Vector2i in floor_mask.keys():
		if skip.has(cell):
			continue
		# Open floor is lighter than the wall foot; four cells in it is fully
		# open. Rounding this to a step of 1 cell would band, so it stays linear.
		var d: float = clampf(float(int(depth.get(cell, 4))) / 4.0, 0.0, 1.0)
		# A slow stain field on top, so the value drifts in blotches the size of
		# a chamber rather than flickering per tile.
		var stain: float = MapKit.fbm(float(cell.x), float(cell.y), 13.0, 3, seed_value)
		var v: float = d * 0.60 + stain * 0.40 + bias
		if scorch.has(cell):
			v -= 0.30
		var bank: Array[Vector2i] = SLATE_MID
		if v < 0.40:
			bank = SLATE_DARK
		elif v > 0.68:
			bank = SLATE_LIGHT
		ground.set_cell(cell, SOURCE, MapKit._pick(bank, cell, seed_value + 1))
		n += 1
	return n


# --- Laid paving -------------------------------------------------------------

## One paving cell. Parity keeps the 2x2 joint pattern continuous across any
## shape, so two roads that meet still look like one floor.
static func plate(ground: TileMapLayer, cell: Vector2i) -> void:
	var quad: Array[Vector2i] = [PLATE_TL, PLATE_TR, PLATE_BL, PLATE_BR]
	ground.set_cell(cell, SOURCE, quad[posmod(cell.x, 2) + 2 * posmod(cell.y, 2)])


## Pave every cell of `region` that is real floor. Returns the cells paved so the
## caller can keep them out of the slate pass.
##
## Two things stop the result reading as a decal pasted over the level:
##   * `wear` punches blotches of bare slate back through the paving, using the
##     same noise the slate pass uses, so the two materials interlock instead of
##     meeting along a clean outline;
##   * paving never reaches the wall. The outermost ring of floor always stays
##     slate, so the laid floor looks like it stops short of the rock — which is
##     what laid floors do — instead of being sliced off by it.
static func pave(
	ground: TileMapLayer,
	region: Dictionary,
	floor_mask: Dictionary,
	depth: Dictionary = {},
	seed_value: int = 0,
	wear: float = 0.0
) -> Dictionary:
	var done: Dictionary = {}
	for cell: Vector2i in region.keys():
		if not floor_mask.has(cell):
			continue
		if int(depth.get(cell, 99)) <= 1:
			continue
		if wear > 0.0 and MapKit.fbm(float(cell.x), float(cell.y), 7.0, 2, seed_value) > 1.0 - wear:
			continue
		plate(ground, cell)
		done[cell] = true
	return done


## A straight paved run between two cells. Roads are straight on purpose: the
## carver's tunnels already wander, and a road that wanders with them stops
## reading as built and stops helping the player orient.
static func road(out: Dictionary, from_cell: Vector2i, to_cell: Vector2i, half_width: int) -> void:
	var steps: int = int(maxf(absf(float(to_cell.x - from_cell.x)), absf(float(to_cell.y - from_cell.y)))) + 1
	for i in steps:
		var t: float = float(i) / float(maxi(steps - 1, 1))
		var p := Vector2(from_cell).lerp(Vector2(to_cell), t)
		var c := Vector2i(int(round(p.x)), int(round(p.y)))
		for oy in range(-half_width, half_width + 1):
			for ox in range(-half_width, half_width + 1):
				out[c + Vector2i(ox, oy)] = true


## A paved apron — the plaza a stair or portal arrives onto.
static func apron(out: Dictionary, centre: Vector2i, radius: int) -> void:
	var r2: int = radius * radius
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			if ox * ox + oy * oy <= r2:
				out[centre + Vector2i(ox, oy)] = true


# --- Features ----------------------------------------------------------------

## A 3x3 casting pit: stone frame on Ground, animated molten pour in the middle.
## The centre blocks, so a caller that placed one must drop that cell from its
## walkable set. Returns every cell taken, empty if the footprint did not fit.
static func mold_pit(ground: TileMapLayer, floor_mask: Dictionary, centre: Vector2i) -> Dictionary:
	var origin := centre - Vector2i(1, 1)
	var covered: Dictionary = {}
	for oy in 3:
		for ox in 3:
			if not floor_mask.has(origin + Vector2i(ox, oy)):
				return covered
	for oy in 3:
		for ox in 3:
			var cell := origin + Vector2i(ox, oy)
			var atlas := MOLD_ORIGIN + Vector2i(ox, oy)
			if atlas == MOLD_HOLE:
				ground.set_cell(cell, POUR_SOURCE, POUR_TILE)
			else:
				ground.set_cell(cell, SOURCE, atlas)
			covered[cell] = true
	return covered


## A 3x3 raised work plate, centred on `centre`. Returns the cells it took.
static func hearth(ground: TileMapLayer, floor_mask: Dictionary, centre: Vector2i) -> Dictionary:
	var origin := centre - Vector2i(1, 1)
	var covered: Dictionary = {}
	for oy in HEARTH_SIZE.y:
		for ox in HEARTH_SIZE.x:
			if not floor_mask.has(origin + Vector2i(ox, oy)):
				return covered
	for oy in HEARTH_SIZE.y:
		for ox in HEARTH_SIZE.x:
			var cell := origin + Vector2i(ox, oy)
			ground.set_cell(cell, SOURCE, HEARTH_ORIGIN + Vector2i(ox, oy))
			covered[cell] = true
	return covered


## Iron catwalk mesh on `layer` (Props), over whatever Ground already holds.
static func catwalk(layer: TileMapLayer, region: Dictionary, floor_mask: Dictionary, seed_value: int) -> int:
	var n: int = 0
	for cell: Vector2i in region.keys():
		if not floor_mask.has(cell):
			continue
		layer.set_cell(cell, SOURCE, MapKit._pick(GRATE, cell, seed_value))
		n += 1
	return n


## Cells within `radius` of anything in `hot`, for the scorched apron around
## lava. Chebyshev, because a square falloff matches how the pools are carved.
static func scorch_of(hot: Dictionary, floor_mask: Dictionary, radius: int) -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in hot.keys():
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				var n: Vector2i = cell + Vector2i(ox, oy)
				if floor_mask.has(n):
					out[n] = true
	return out
