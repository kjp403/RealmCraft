extends Node
## Generate the tile data for the Ossuran encounter map and print it as base64,
## so ossuran_arena.tscn can be patched as TEXT.
##
##   godot --path . --mode=client res://tools/build_ossuran_arena.tscn
##
## Same approach as build_boss_arena.gd, and for the same reasons:
##
##   * The tiles are LEARNED from a room that already exists and is built from
##     the same tileset (fire_forge.tscn), rather than picked by index. The forge
##     wall tiles are DIRECTIONAL — a top-edge tile only reads as a wall along the
##     top — so choosing a variant at random scatters loose masonry around the
##     border instead of drawing a room. Each wall cell's ROLE is the bitmask of
##     which of its four neighbours are also wall, and every cell with the same
##     role gets the tile the reference room most often uses for that role.
##   * Only the tile_map_data blobs come out of here. The scene is never re-packed
##     with PackedScene.pack(): packing a live scene rewrites nodes and drops
##     properties that happen to match their defaults.
##   * Run as a SCENE, not with -s. Loading fire_forge.tscn pulls NPC scenes,
##     which reach the Client / ClientState autoloads that -s does not provide.
##
## TWO SEALED ROOMS, one map. The arena and the summoning chamber are separate
## walled rectangles with no corridor between them, parked far apart on the same
## tilemap. Movement between them is only ever the encounter's own teleport, so
## there is deliberately nothing to walk down — and because they are one map they
## are one instance, with one state machine and one player list (see the note at
## the top of OssuranArena).

const REFERENCE: String = "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn"

## Arena: 48x34 tiles at 16px = 768x544. Big enough to kite a 132px slam, run
## between two pads and three pillars, and still see the walls.
const ARENA := Rect2i(0, 0, 48, 34)
## Chamber: 34x26 = 544x416. Tighter on purpose — five waves in a big room is a
## kiting exercise, and the gauntlet is supposed to be a fight.
const CHAMBER := Rect2i(64, 4, 34, 26)
const WALL_THICKNESS: int = 2
## How many of the forge's floor tiles to mix. 3 is enough to kill the "one tile
## repeated 2500 times" flatness; more starts to read as rubble.
const FLOOR_VARIANTS: int = 3

## Interior of the arena, which the decorative ice layer covers in phase 3.
var _arena_floor: Rect2i = Rect2i(
	ARENA.position + Vector2i(WALL_THICKNESS, WALL_THICKNESS),
	ARENA.size - Vector2i(WALL_THICKNESS, WALL_THICKNESS) * 2
)


func _ready() -> void:
	var packed: PackedScene = load(REFERENCE)
	if packed == null:
		printerr("could not load ", REFERENCE)
		get_tree().quit(1)
		return
	var root: Node = packed.instantiate()
	# Maps disagree on the tile parent's name ("Tiles" in the biome maps,
	# "Map_tiles" in the hand-built boss rooms), so resolve by layer NAME rather
	# than by a fixed path — otherwise this silently finds nothing.
	var ground_ref: TileMapLayer = _find_layer(root, &"Ground")
	var walls_ref: TileMapLayer = _find_layer(root, &"Walls")
	if ground_ref == null or walls_ref == null:
		printerr("reference room has no Ground/Walls layer")
		root.free()
		get_tree().quit(1)
		return

	var floor_tiles: Array = _most_common_floor(ground_ref, walls_ref)
	var wall_by_role: Dictionary = _learn_wall_roles(walls_ref)
	if floor_tiles.is_empty() or wall_by_role.is_empty():
		printerr("could not sample the forge tiles")
		root.free()
		get_tree().quit(1)
		return
	print("floor variants: %d" % floor_tiles.size())
	print("learned %d wall roles" % wall_by_role.size())

	var tile_set: TileSet = ground_ref.tile_set

	# --- Ground: both rooms, floor everywhere including under the walls, so a
	# wall tile with transparent pixels never shows the void behind it.
	var ground := TileMapLayer.new()
	ground.tile_set = tile_set
	for room: Rect2i in [ARENA, CHAMBER]:
		for y: int in range(room.position.y, room.end.y):
			for x: int in range(room.position.x, room.end.x):
				var pick: Array = floor_tiles[_floor_variant(x, y, floor_tiles.size())]
				ground.set_cell(Vector2i(x, y), pick[0], pick[1])

	# --- Walls: the enclosing ring of each room, tiled by role.
	var walls := TileMapLayer.new()
	walls.tile_set = tile_set
	for room: Rect2i in [ARENA, CHAMBER]:
		for y: int in range(room.position.y, room.end.y):
			for x: int in range(room.position.x, room.end.x):
				if not _is_wall(x, y):
					continue
				var role: int = _role_at(x, y)
				if not wall_by_role.has(role):
					role = 15  # fully enclosed interior — always learned
				var w: Array = wall_by_role[role]
				walls.set_cell(Vector2i(x, y), w[0], w[1])

	# --- Deco: architecture and floor detail, on its own tileset so the biome
	# tileset regen can never clobber it (and so the props that must BLOCK can
	# carry collision — source 4 of the shared forge tileset has none at all).
	var deco_set: TileSet = load(
		"res://source/common/gameplay/maps/tilesets/ossuran_props_tileset.tres"
	)
	var deco := TileMapLayer.new()
	deco.tile_set = deco_set
	if deco_set != null:
		_decorate_arena(deco)
		_decorate_chamber(deco)

	for layer: TileMapLayer in [ground, walls, deco]:
		# The serialised blob lags set_cell until internals refresh; nothing
		# pumps that in a tool run, so ask explicitly or you export the OLD data.
		layer.update_internals()

	print("cells: ground=%d walls=%d deco=%d" % [
		ground.get_used_cells().size(),
		walls.get_used_cells().size(),
		deco.get_used_cells().size(),
	])
	print("LAYER Ground = %s" % Marshalls.raw_to_base64(ground.tile_map_data))
	print("LAYER Walls = %s" % Marshalls.raw_to_base64(walls.tile_map_data))
	print("LAYER Deco = %s" % Marshalls.raw_to_base64(deco.tile_map_data))

	# Where the portal INTO the encounter goes. Searched rather than eyeballed:
	# the forge is 3000px wide and a coordinate picked off a screenshot lands
	# inside a wall as often as not, which is a portal nobody can reach.
	_find_portal_spot(ground_ref, walls_ref, _find_layer(root, &"Props"))

	ground.free()
	walls.free()
	deco.free()
	root.free()
	get_tree().quit(0)


## The forge's UPPER level, in tile coords. The two existing stairs sit at
## y≈470-570px (rows ~29-35) while the hub entrance is down at y≈2300px, so
## "upper" is the low-y band. Searched inside this box only.
const UPPER_BAND := Rect2i(20, 20, 160, 30)
## Anchor to search outward from: between the Gallery stair (584, 536) and the
## Deeps stair (2968, 472), so the new portal joins the same rank of doors
## instead of being tucked in a corner.
const PORTAL_ANCHOR := Vector2i(111, 31)
## Clear cells required around the spot, so the portal and its landing both have
## room and a player is never dropped against a wall.
const CLEARANCE: int = 2


## Print a walkable cell for the encounter portal: Ground present, no Wall, no
## Prop, and CLEARANCE clear cells on every side. Spirals out from the anchor and
## takes the first spot that satisfies all of it.
func _find_portal_spot(
	ground: TileMapLayer, walls: TileMapLayer, props: TileMapLayer
) -> void:
	for radius: int in range(0, 60):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				# Only test the ring at this radius; the inside was already done.
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := PORTAL_ANCHOR + Vector2i(dx, dy)
				if not UPPER_BAND.has_point(cell):
					continue
				if not _is_clear(ground, walls, props, cell):
					continue
				# The landing goes one cell below the portal, so it must be clear too.
				if not _is_clear(ground, walls, props, cell + Vector2i(0, 2)):
					continue
				var px := Vector2i(cell.x * 16 + 8, cell.y * 16 + 8)
				print("PORTAL cell=%s px=Vector2(%d, %d) landing_px=Vector2(%d, %d)" % [
					cell, px.x, px.y, px.x, px.y + 32
				])
				return
	printerr("no clear portal spot found in the upper band")


## A cell is usable when the floor is painted and nothing solid sits on it, with
## CLEARANCE clear cells all around.
func _is_clear(
	ground: TileMapLayer, walls: TileMapLayer, props: TileMapLayer, cell: Vector2i
) -> bool:
	for dy: int in range(-CLEARANCE, CLEARANCE + 1):
		for dx: int in range(-CLEARANCE, CLEARANCE + 1):
			var at := cell + Vector2i(dx, dy)
			if ground.get_cell_source_id(at) < 0:
				return false
			if walls.get_cell_source_id(at) >= 0:
				return false
			if props != null and props.get_cell_source_id(at) >= 0:
				return false
	return true


## Depth-first search for a TileMapLayer by node name.
func _find_layer(node: Node, wanted: StringName) -> TileMapLayer:
	if node is TileMapLayer and node.name == wanted:
		return node as TileMapLayer
	for child: Node in node.get_children():
		var found: TileMapLayer = _find_layer(child, wanted)
		if found != null:
			return found
	return null


## Which floor variant a cell gets. HASHED, not derived from x+y: indexing
## variants by position parity draws a visible diagonal stripe across the room
## (the failure build_boss_arena.gd hit, which is why it dropped to a single
## tile). A hash scatters them with no structure at all, so the floor gets its
## texture back without gaining a pattern.
##
## The dominant tile is weighted to roughly three quarters of the floor by giving
## it the whole bottom half of the hash range; the rest split what is left. An
## even split reads as noise rather than as a worn floor.
func _floor_variant(x: int, y: int, count: int) -> int:
	if count <= 1:
		return 0
	var h: float = fmod(abs(sin(float(x) * 127.1 + float(y) * 311.7) * 43758.5453), 1.0)
	if h < 0.74:
		return 0
	return 1 + int(floor((h - 0.74) / 0.26 * float(count - 1))) % (count - 1)


## The reference room's most-used floor tiles, ignoring cells that also carry a
## wall. Returns up to FLOOR_VARIANTS of them, most common first.
func _most_common_floor(ground: TileMapLayer, walls: TileMapLayer) -> Array:
	var counts: Dictionary = {}
	for cell: Vector2i in ground.get_used_cells():
		if walls.get_cell_source_id(cell) >= 0:
			continue
		var key: String = "%d|%d|%d" % [
			ground.get_cell_source_id(cell),
			ground.get_cell_atlas_coords(cell).x,
			ground.get_cell_atlas_coords(cell).y,
		]
		counts[key] = int(counts.get(key, 0)) + 1
	if counts.is_empty():
		return []
	var ranked: Array = counts.keys()
	ranked.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
	var out: Array = []
	for key: String in ranked.slice(0, FLOOR_VARIANTS):
		var parts: PackedStringArray = str(key).split("|")
		out.append([int(parts[0]), Vector2i(int(parts[1]), int(parts[2]))])
	return out


## For each wall ROLE, the tile the reference room most commonly uses for it.
## That room was placed by hand, so its choices are correct by construction.
func _learn_wall_roles(walls: TileMapLayer) -> Dictionary:
	var tally: Dictionary = {}
	var used: Dictionary = {}
	for cell: Vector2i in walls.get_used_cells():
		used[cell] = true
	for cell: Vector2i in used:
		var role: int = 0
		if used.has(cell + Vector2i(0, -1)):
			role |= 1
		if used.has(cell + Vector2i(0, 1)):
			role |= 2
		if used.has(cell + Vector2i(-1, 0)):
			role |= 4
		if used.has(cell + Vector2i(1, 0)):
			role |= 8
		var key: String = "%d|%d|%d" % [
			walls.get_cell_source_id(cell),
			walls.get_cell_atlas_coords(cell).x,
			walls.get_cell_atlas_coords(cell).y,
		]
		if not tally.has(role):
			tally[role] = {}
		tally[role][key] = int(tally[role].get(key, 0)) + 1

	var out: Dictionary = {}
	for role: int in tally:
		var counts: Dictionary = tally[role]
		var ranked: Array = counts.keys()
		ranked.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
		var parts: PackedStringArray = str(ranked[0]).split("|")
		out[role] = [int(parts[0]), Vector2i(int(parts[1]), int(parts[2]))]
	return out


## A wall cell's role: which of its four neighbours are also wall, as a bitmask
## (1 N, 2 S, 4 W, 8 E).
func _role_at(x: int, y: int) -> int:
	var role: int = 0
	if _is_wall(x, y - 1):
		role |= 1
	if _is_wall(x, y + 1):
		role |= 2
	if _is_wall(x - 1, y):
		role |= 4
	if _is_wall(x + 1, y):
		role |= 8
	return role


## True when this cell is part of either room's enclosing wall ring.
func _is_wall(x: int, y: int) -> bool:
	for room: Rect2i in [ARENA, CHAMBER]:
		if not room.has_point(Vector2i(x, y)):
			continue
		return (
			x < room.position.x + WALL_THICKNESS
			or y < room.position.y + WALL_THICKNESS
			or x >= room.end.x - WALL_THICKNESS
			or y >= room.end.y - WALL_THICKNESS
		)
	return false


# --- Decoration ---------------------------------------------------------------
#
# All coordinates below are cells in `ossuran_props_tileset` (fire_forge/tiles.png,
# 25x25). Multi-cell props are STAMPED as whole rectangles: these are compositions,
# and painting one cell of a 3x5 arch in isolation draws a fragment of masonry
# floating in a room.
#
# THE PLACEMENT RULE that keeps this honest: anything that reads as a solid object
# is placed IN OR AGAINST THE WALL BAND, never out in the open floor. Two reasons.
# The encounter's geometry is tuned (a 132px slam, three pillars, a kite path) and
# obstacles in the middle of it would change the fight, not decorate it. And a prop
# standing in open floor that the player walks through is exactly the visual bug
# this pass exists to remove — against the wall, the wall's own collision means the
# question never comes up.

## Column: shaft + base, 1x4. Source rows 1..4 of the arch's left leg.
const S_COLUMN := Vector2i(14, 1)
## Hanging chevron banner, 1x5. Flat cloth — deliberately NOT solid, so players
## walk under it the way you would under a hanging standard.
const S_BANNER := Vector2i(18, 0)
## Stone idol furnace, 2x4, glowing mouth.
const S_FURNACE := Vector2i(12, 9)
## Anvil on a lit base, 2x3.
const S_ANVIL := Vector2i(14, 10)
## Crucible, 2x2.
const S_CRUCIBLE := Vector2i(14, 13)
## Ore carts, 2x4.
const S_CART := Vector2i(15, 5)
## Full archway, 3x5 — legs solid, centre column open.
const S_ARCH := Vector2i(14, 0)
## Solid molten fill, a single column of 3 rows.
const S_LAVA := Vector2i(22, 13)
## Iron grate (1x2) and railing (1x2) — flat wall furniture, never solid.
const S_GRATE := Vector2i(13, 2)
const S_RAILING := Vector2i(12, 15)
## Glowing pipe frame, 3x3. Flat floor detail / summoning platform.
const S_FRAME := Vector2i(8, 9)

## Hazard chevrons — the dais edging. Eight interchangeable variants.
const HAZARD: Array[Vector2i] = [
	Vector2i(11, 6), Vector2i(12, 6), Vector2i(13, 6),
	Vector2i(11, 7), Vector2i(13, 7),
	Vector2i(11, 8), Vector2i(12, 8), Vector2i(13, 8),
]
## Small slag / debris, flat.
const DEBRIS: Array[Vector2i] = [
	Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(7, 7),
]
## Dark cracked slab, for the chamber floor overlay.
const CRACKED: Array[Vector2i] = [
	Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(0, 8),
]
## Brick facing, used to give the chamber a different border than the arena.
const BRICK: Array[Vector2i] = [
	Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1), Vector2i(5, 2), Vector2i(6, 2),
]

## Cells the scatter must leave alone: the pads, the boss, the pillar pedestals,
## the braziers, both landing points and the two doors. Debris under a charge pad
## fights the pad shader; debris on a spawn point reads as the mob having broken
## the floor on arrival.
const KEEP_CLEAR_CELLS: Array[Vector2i] = [
	Vector2i(9, 17), Vector2i(39, 17),                       # pads
	Vector2i(24, 11), Vector2i(24, 26), Vector2i(24, 30),    # boss, return, entrance
	Vector2i(15, 8), Vector2i(33, 8), Vector2i(24, 28),      # pillar pedestals
	Vector2i(6, 6), Vector2i(41, 6), Vector2i(6, 27), Vector2i(41, 27),  # braziers
	Vector2i(20, 30),                                        # exit portal
	Vector2i(81, 25),                                        # chamber landing
]


## Paint a rectangular prop with its top-left at [param at].
func _stamp(layer: TileMapLayer, at: Vector2i, src: Vector2i, w: int, h: int) -> void:
	for dy: int in h:
		for dx: int in w:
			layer.set_cell(at + Vector2i(dx, dy), 0, src + Vector2i(dx, dy))


func _decorate_arena(deco: TileMapLayer) -> void:
	var x0: int = ARENA.position.x
	var y0: int = ARENA.position.y
	var x1: int = ARENA.end.x - 1
	var y1: int = ARENA.end.y - 1
	var inner_top: int = y0 + WALL_THICKNESS - 1     # last wall row at the top
	var inner_bottom: int = y1 - WALL_THICKNESS + 1  # first wall row at the bottom

	# MOLTEN CHANNELS north and south, painted ON the inner wall row. The wall
	# beneath already blocks movement, so the lava is unreachable by construction
	# — no new collision, no shrunk arena, and nobody can stand in it.
	for x: int in range(x0 + WALL_THICKNESS, x1 - WALL_THICKNESS + 1):
		deco.set_cell(Vector2i(x, inner_top), 0, S_LAVA + Vector2i(0, x % 3))
		deco.set_cell(Vector2i(x, inner_bottom), 0, S_LAVA + Vector2i(0, (x + 1) % 3))

	# IRON GRATING east and west, running the FULL height of the inner wall column.
	#
	# Continuous, not spaced at intervals, because of what the wall vocabulary
	# underneath actually is: the forge ring is two cells thick and only one of
	# those rows carries collision, and on the west wall it is the OUTER one — so
	# the inner column is open floor that a player can stand in. Spacing the grates
	# out left twenty such cells between them. Running the grating the whole way
	# down seals the column (these tiles are solid) and gives the east/west walls
	# their own material, against the molten channel north and south.
	for y: int in range(y0 + WALL_THICKNESS, y1 - WALL_THICKNESS + 1):
		deco.set_cell(Vector2i(x0 + 1, y), 0, S_GRATE + Vector2i(0, y % 2))
		deco.set_cell(Vector2i(x1 - 1, y), 0, S_RAILING + Vector2i(0, (y + 1) % 2))

	# COLUMNS along the top, breaking the straight run of wall. Their bases stand
	# two cells proud of it, which is what gives the perimeter a silhouette.
	for x: int in [7, 14, 21, 28, 35, 41]:
		_stamp(deco, Vector2i(x, y0), S_COLUMN, 1, 4)
	# BANNERS hang between them, starting BELOW the molten channel.
	#
	# They used to start at the wall's top row, which overwrote the channel — and
	# because a banner is flat cloth (deliberately not solid) while the top wall's
	# INNER row carries no collision of its own, each banner punched a walk-in
	# pocket in the perimeter. Hanging them from the first interior row keeps the
	# channel unbroken and solid the whole way across, and reads better anyway:
	# the standards hang from under the molten sill.
	for x: int in [10, 17, 24, 31, 38]:
		_stamp(deco, Vector2i(x, y0 + 2), S_BANNER + Vector2i(0, 1), 1, 4)

	# FURNACE IDOLS watching from the top corners.
	_stamp(deco, Vector2i(x0 + 3, y0), S_FURNACE, 2, 4)
	_stamp(deco, Vector2i(x1 - 4, y0), S_FURNACE, 2, 4)

	# WORKSHOP CLUTTER along the bottom wall, so the south edge reads as a foundry
	# floor rather than a blank line.
	_stamp(deco, Vector2i(x0 + 8, inner_bottom - 2), S_ANVIL, 2, 3)
	_stamp(deco, Vector2i(x1 - 10, inner_bottom - 2), S_ANVIL, 2, 3)
	_stamp(deco, Vector2i(x0 + 16, inner_bottom - 1), S_CRUCIBLE, 2, 2)
	_stamp(deco, Vector2i(x1 - 17, inner_bottom - 1), S_CRUCIBLE, 2, 2)
	_stamp(deco, Vector2i(x0 + 12, inner_bottom - 3), S_CART, 2, 4)

	# RAISED DAIS under each pad: a hazard-chevron ring one cell thick, four cells
	# out from the pad centre. It marks the standable zone before the pad has any
	# charge on it, which is the only cue a player gets that the pad is a PLACE.
	for centre: Vector2i in [Vector2i(9, 17), Vector2i(39, 17)]:
		_ring(deco, centre, 4, HAZARD)

	# Scattered slag across the floor, avoiding everything that matters.
	_scatter(deco, _arena_floor, DEBRIS, 0.035, 5)


func _decorate_chamber(deco: TileMapLayer) -> void:
	var x0: int = CHAMBER.position.x
	var y0: int = CHAMBER.position.y
	var x1: int = CHAMBER.end.x - 1
	var y1: int = CHAMBER.end.y - 1

	# A DIFFERENT BORDER. Both rooms are cut from one tilemap and share a wall
	# tileset, so the way to make the chamber read as somewhere else is to face its
	# inner ring in brick and give it no molten channel at all: cold masonry, not a
	# working foundry.
	for x: int in range(x0 + 1, x1):
		deco.set_cell(Vector2i(x, y0 + 1), 0, BRICK[x % BRICK.size()])
		deco.set_cell(Vector2i(x, y1 - 1), 0, BRICK[(x + 2) % BRICK.size()])
	for y: int in range(y0 + 2, y1 - 1):
		deco.set_cell(Vector2i(x0 + 1, y), 0, BRICK[y % BRICK.size()])
		deco.set_cell(Vector2i(x1 - 1, y), 0, BRICK[(y + 3) % BRICK.size()])

	# THE SUMMONING GATE — the chamber's one landmark, centred on the north wall.
	# The arena deliberately gets no arch, so the two rooms cannot be confused.
	_stamp(deco, Vector2i(x0 + 15, y0), S_ARCH, 3, 5)

	# CRACKED FLOOR, heavier than the arena's slag: this room has had five waves
	# torn out of it.
	_scatter(deco, Rect2i(
		Vector2i(x0 + 2, y0 + 2),
		Vector2i(CHAMBER.size.x - 4, CHAMBER.size.y - 4)
	), CRACKED, 0.10, 7)

	# SUMMONING PLATFORMS under the six wave spawn markers: a glowing pipe frame on
	# the floor, so a player can see WHERE the next wave arrives before it does.
	# Coordinates mirror WAVE_SPAWNS in build_ossuran_scene.py.
	for px: Vector2i in [
		Vector2i(1120, 140), Vector2i(1296, 128), Vector2i(1472, 140),
		Vector2i(1100, 300), Vector2i(1492, 300), Vector2i(1296, 200),
	]:
		var cell := Vector2i(px.x / 16, px.y / 16)
		_stamp(deco, cell - Vector2i(1, 1), S_FRAME, 3, 3)


## A one-cell-thick square ring of [param tiles] at [param radius] around
## [param centre].
func _ring(layer: TileMapLayer, centre: Vector2i, radius: int, tiles: Array[Vector2i]) -> void:
	var i: int = 0
	for d: int in range(-radius, radius + 1):
		for cell: Vector2i in [
			centre + Vector2i(d, -radius), centre + Vector2i(d, radius),
			centre + Vector2i(-radius, d), centre + Vector2i(radius, d),
		]:
			layer.set_cell(cell, 0, tiles[i % tiles.size()])
			i += 1


## Sprinkle flat detail across [param area] at [param chance], skipping anything
## within [param keep_clear] cells of a functional fixture. Hash-driven, so the
## result is identical on every rebuild — a scatter that moves between runs makes
## the map diff unreadable.
func _scatter(
	layer: TileMapLayer, area: Rect2i, tiles: Array[Vector2i],
	chance: float, keep_clear: int
) -> void:
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if layer.get_cell_source_id(cell) >= 0:
				continue  # never paint over an existing prop
			if _too_close(cell, keep_clear):
				continue
			var h: float = fmod(absf(sin(float(x) * 91.7 + float(y) * 47.3) * 28657.0), 1.0)
			if h > chance:
				continue
			var pick: float = fmod(absf(sin(float(x) * 12.9 + float(y) * 78.2) * 43758.5), 1.0)
			layer.set_cell(cell, 0, tiles[mini(int(pick * float(tiles.size())), tiles.size() - 1)])


func _too_close(cell: Vector2i, keep_clear: int) -> bool:
	for fixture: Vector2i in KEEP_CLEAR_CELLS:
		if absi(cell.x - fixture.x) <= keep_clear and absi(cell.y - fixture.y) <= keep_clear:
			return true
	return false
