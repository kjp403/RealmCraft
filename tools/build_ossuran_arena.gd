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

	# --- Ice: the phase-3 overlay. Its own tileset, which carries NO physics
	# layer and NO navigation, so fading it in cannot disturb a single path.
	var ice_set: TileSet = load(
		"res://source/common/gameplay/maps/tilesets/ossuran_ice_tileset.tres"
	)
	var ice := TileMapLayer.new()
	ice.tile_set = ice_set
	if ice_set != null:
		for y: int in range(_arena_floor.position.y, _arena_floor.end.y):
			for x: int in range(_arena_floor.position.x, _arena_floor.end.x):
				# Two smooth ice-slab variants, alternated on a coarse checker so
				# the sheet has some grain without looking like a repeating tile.
				var variant: int = ((x / 2) + (y / 2)) % 2
				ice.set_cell(Vector2i(x, y), 0, Vector2i(variant, 0))

	for layer: TileMapLayer in [ground, walls, ice]:
		# The serialised blob lags set_cell until internals refresh; nothing
		# pumps that in a tool run, so ask explicitly or you export the OLD data.
		layer.update_internals()

	print("cells: ground=%d walls=%d ice=%d" % [
		ground.get_used_cells().size(),
		walls.get_used_cells().size(),
		ice.get_used_cells().size(),
	])
	print("LAYER Ground = %s" % Marshalls.raw_to_base64(ground.tile_map_data))
	print("LAYER Walls = %s" % Marshalls.raw_to_base64(walls.tile_map_data))
	print("LAYER Ice = %s" % Marshalls.raw_to_base64(ice.tile_map_data))

	# Where the portal INTO the encounter goes. Searched rather than eyeballed:
	# the forge is 3000px wide and a coordinate picked off a screenshot lands
	# inside a wall as often as not, which is a portal nobody can reach.
	_find_portal_spot(ground_ref, walls_ref, _find_layer(root, &"Props"))

	ground.free()
	walls.free()
	ice.free()
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
