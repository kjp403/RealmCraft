extends Node
## Regression gate for the two rules that decide where the Traveling Peddler may
## stand: FLOOR PAINT (which tile layer vouches for a square) and FIT (whether
## the cart's body has room on it).
##
## Both rules were tightened after the cart kept being reported standing on the
## boundary wall of the_hollow, and a tightening can fail in either direction
## without anything erroring:
##
##   TOO LOOSE — a wall top passes and the cart parks out of bounds. Measured
##     here as "cells the OLD rule accepted that carry structural paint", broken
##     out for the ring around the map edge.
##
##   TOO TIGHT — every square in a map is rejected, so pick_spot falls back to
##     the home spawn on every cycle. The cart still appears, just always on the
##     spawn pad, in every biome, forever. Measured here as "cycles that landed
##     on the anchor". This half is not hypothetical: vetoing Props (a decoration
##     layer painted over walkable floor in this project) collapsed fungus_cave
##     and gutterworks to one cell each, and only this number said so.
##
## And a third, between them: a square whose CENTRE is on floor but which the
## cart's body does not fit on. Measured as "squares the old ring offered that
## are too tight" — 191 of the_hollow's 2262, where the wall tiles are properly
## solid and the paint rule alone changes nothing.
##
## Runs the OLD rules alongside the live ones, so one pass reports both sides
## without anything being reverted.
##   godot --headless --path . --mode=client res://tools/audit_peddler_ground_rule.tscn

const BIOMES_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const CYCLES: int = 200
## The lattice PeddlerSites walks on, so a cell here is a cell there.
const STEP: float = 16.0
const FILL_CELL_CAP: int = 60000
## How far in from the painted rect's edge still counts as "the boundary ring".
## Two 32px tiles: wide enough to cover a wall run and the tile behind it.
const EDGE_BAND: float = 64.0
## The ring the OLD fit test probed on, kept so the before/after is a real
## comparison rather than the new rule measured twice.
const OLD_CLEARANCE: float = 20.0
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

var _failures: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	print("--- Peddler ground rule ---")
	_check_pool()
	for file_name: String in ResourceLoader.list_directory(BIOMES_DIR):
		if file_name.ends_with(".tres"):
			await _audit(BIOMES_DIR + file_name)
	print("--- %s ---" % ("PASS" if _failures == 0 else "%d FAILURES" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _fail(text: String) -> void:
	_failures += 1
	print("  FAIL: %s" % text)


## The rotation itself: every arena barred, every ordinary zone still in.
func _check_pool() -> void:
	var pool: Array[StringName] = PeddlerSites.biome_names()
	for barred: String in PeddlerSites.EXCLUDED_BIOMES:
		for name: StringName in pool:
			if String(name).to_lower() == barred:
				_fail("'%s' is barred but still in the rotation" % barred)
	if not PeddlerSites.is_excluded(&"the_hollow"):
		_fail("the_hollow is not excluded")
	if PeddlerSites.is_excluded(&"sewers"):
		_fail("sewers is excluded, but it is an ordinary zone")
	# The rotation is walked when a biome cannot host the cart, so it has to stay
	# long enough to have somewhere to walk to.
	if pool.size() < 2:
		_fail("the rotation is down to %d biomes" % pool.size())
	print("rotation: %d biomes, barred [%s]" % [
		pool.size(), ", ".join(PeddlerSites.EXCLUDED_BIOMES)
	])


func _audit(res_path: String) -> void:
	var biome: InstanceResource = ResourceLoader.load(res_path) as InstanceResource
	if biome == null:
		return
	var packed: PackedScene = load(biome.map_path) as PackedScene
	if packed == null:
		return
	var node: Node = packed.instantiate()
	add_child(node)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var map: Map = node as Map
	if map == null:
		node.queue_free()
		return

	var excluded: bool = (
		PeddlerSites.is_excluded(biome.instance_name)
		or PeddlerSites.is_excluded(StringName(res_path.get_file().get_basename()))
	)
	print("%s%s" % [biome.instance_name, "   [BARRED FROM THE ROTATION]" if excluded else ""])
	print("  layers: floor=[%s]  other=[%s]" % [
		", ".join(_names(PeddlerSites.ground_layers(map))),
		", ".join(_names(_other_layers(map))),
	])

	var home: Vector2 = map.get_spawn_position(0)
	var space: PhysicsDirectSpaceState2D = map.get_world_2d().direct_space_state
	var layers: Array[TileMapLayer] = _all_layers(map)
	var rect: Rect2 = PeddlerSites.playable_rect(map)

	# The two pools, on the same lattice from the same origin.
	var old_pool: Dictionary = _old_fill(space, layers, home, rect)
	var new_pool: Dictionary = PeddlerSites.walkable_cells(map, home)

	# Of the cells the old rule let the walk through, which carry wall paint —
	# and how many of those are up against the edge of the map, which is the
	# shape of every sighting that got reported.
	var walled: int = 0
	var walled_on_edge: int = 0
	var still_walled: int = 0
	for cell: Vector2i in old_pool:
		var point: Vector2 = _centre(cell)
		if not _painted_by_wall(layers, point):
			continue
		walled += 1
		if _on_edge(rect, point):
			walled_on_edge += 1
		if new_pool.has(cell):
			still_walled += 1
	print("  cells: old=%d new=%d   wall-painted cells the old walk accepted: %d (%d on the map edge)" % [
		old_pool.size(), new_pool.size(), walled, walled_on_edge
	])
	if still_walled > 0:
		_fail("%d wall-painted cells are STILL in the walkable pool" % still_walled)

	# The other half of the tightening: squares the old ring called clear that the
	# cart's actual body does not fit on. A cart on one of these is not out of
	# bounds — its centre is on real floor — it is jammed against the wall it is
	# standing next to, which is what "in the wall" looks like to a player, since
	# the sprite is four times the size of the collision box.
	var tight: int = 0
	for cell: Vector2i in new_pool:
		var point: Vector2 = _centre(cell)
		if _old_fits(space, point) and not PeddlerSites.is_valid_spot(map, point):
			tight += 1
	print("  fit: %d squares the old ring offered are too tight for the cart's body" % tight)

	# And the placements themselves. An anchor on every cycle means the rules got
	# tight enough to reject the whole map — the cart still spawns, always on the
	# spawn pad, which no error would ever tell us about.
	var anchor: Vector2 = PeddlerSites.failsafe_anchor(map)
	var on_anchor: int = 0
	var bad: int = 0
	for c: int in CYCLES:
		var spot: Vector2 = PeddlerSites.pick_spot(map, c)["peddler"]
		if spot == anchor:
			on_anchor += 1
			continue
		if not PeddlerSites.is_valid_spot(map, spot) or _painted_by_wall(layers, spot):
			bad += 1
			if bad < 4:
				print("    cycle %d placed at (%d,%d), not on painted floor" % [c, spot.x, spot.y])
	print("  placements: %d/%d real squares, %d on the anchor" % [
		CYCLES - on_anchor, CYCLES, on_anchor
	])
	if bad > 0:
		_fail("%d of %d placements are not on painted floor" % [bad, CYCLES])
	# deep_shoals has no tile layers at all and is anchor-only BY DESIGN; every
	# other map has floor, so it must be able to offer a square.
	if on_anchor == CYCLES and not PeddlerSites.ground_layers(map).is_empty():
		_fail("every cycle fell back to the anchor — the rules reject this whole map")

	node.queue_free()
	await get_tree().process_frame


# --- The OLD rules, kept verbatim so the comparison is a real one ---

## "Does ANY layer paint a tile here" — the rule #413 shipped.
static func _old_has_paint(layers: Array[TileMapLayer], point: Vector2) -> bool:
	for layer: TileMapLayer in layers:
		if layer.get_cell_source_id(layer.local_to_map(layer.to_local(point))) != -1:
			return true
	return false


func _old_fill(
	space: PhysicsDirectSpaceState2D, layers: Array[TileMapLayer], origin: Vector2, rect: Rect2
) -> Dictionary:
	var cells: Dictionary = {}
	var bounded: bool = rect.has_area() and rect.has_point(origin)
	var check_paint: bool = not layers.is_empty()
	var start: Vector2i = _key(origin)
	cells[start] = true
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size() and cells.size() < FILL_CELL_CAP:
		var cell: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in _NEIGHBOURS:
			var next: Vector2i = cell + offset
			if cells.has(next):
				continue
			var point: Vector2 = _centre(next)
			if bounded and not rect.has_point(point):
				continue
			if not _clear(space, point):
				continue
			if check_paint and not _old_has_paint(layers, point):
				continue
			cells[next] = true
			queue.append(next)
	return cells


## The old fit test: the point plus eight samples on a 20px ring.
func _old_fits(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	if not _clear(space, point):
		return false
	for i: int in 8:
		if not _clear(space, point + Vector2.from_angle(float(i) * TAU / 8.0) * OLD_CLEARANCE):
			return false
	return true


func _clear(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = PhysicsLayers.SOLID_GROUND_MASK
	query.collide_with_areas = false
	return space.intersect_point(query, 1).is_empty()


# --- Helpers ---

## True when a wall / roof / prop layer paints [param point] — i.e. the square is
## a wall top, whatever else may be painted underneath it.
static func _painted_by_wall(layers: Array[TileMapLayer], point: Vector2) -> bool:
	for layer: TileMapLayer in layers:
		if layer.get_cell_source_id(layer.local_to_map(layer.to_local(point))) == -1:
			continue
		var lower: String = String(layer.name).to_lower()
		for hint: String in PeddlerSites.BLOCKING_LAYERS:
			if lower.contains(hint):
				return true
	return false


static func _on_edge(rect: Rect2, point: Vector2) -> bool:
	if not rect.has_area():
		return false
	return (
		point.x - rect.position.x < EDGE_BAND
		or point.y - rect.position.y < EDGE_BAND
		or rect.end.x - point.x < EDGE_BAND
		or rect.end.y - point.y < EDGE_BAND
	)


static func _all_layers(node: Node, out: Array[TileMapLayer] = []) -> Array[TileMapLayer]:
	for child: Node in node.get_children():
		if child is TileMapLayer:
			out.append(child as TileMapLayer)
		_all_layers(child, out)
	return out


static func _other_layers(map: Map) -> Array[TileMapLayer]:
	var floors: Array[TileMapLayer] = PeddlerSites.ground_layers(map)
	var out: Array[TileMapLayer] = []
	for layer: TileMapLayer in _all_layers(map):
		if not floors.has(layer):
			out.append(layer)
	return out


static func _names(layers: Array[TileMapLayer]) -> PackedStringArray:
	var out: PackedStringArray = []
	for layer: TileMapLayer in layers:
		out.append(String(layer.name))
	return out


static func _key(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / STEP), floori(point.y / STEP))


static func _centre(cell: Vector2i) -> Vector2:
	return Vector2(cell) * STEP + Vector2.ONE * (STEP * 0.5)
