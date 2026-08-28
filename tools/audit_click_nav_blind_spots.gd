extends Node
## Count the cells click-to-move used to call WALKABLE but the player's body
## cannot actually enter — i.e. everything on the SCENERY layer, which the grid
## was blind to because it sampled WORLD only. Those cells are where a route was
## planned straight through a rock / vein / tree and the body then ground along
## it (the "players get stuck on all the objects and ore veins" report).
##   godot --path . --mode=client res://tools/audit_click_nav_blind_spots.tscn

const MAPS: Array[String] = [
	"res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn",
	"res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn",
	"res://source/common/gameplay/maps/maps/forest/forest.tscn",
	"res://source/common/gameplay/maps/maps/dungeon/dungeon.tscn",
	"res://source/common/gameplay/maps/maps/hell_dungeon/hell_dungeon.tscn",
]

## Mirrors ClickNavigation exactly, so the numbers below are the grid's own.
const CELL_SIZE: float = 16.0
const PLAYER_CLEARANCE: Vector2 = Vector2(13.0, 9.0)
const PLAYER_SHAPE_OFFSET: Vector2 = Vector2(0.0, -3.0)
const OLD_MASK: int = 2 # WORLD only — what the grid used to sample


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	print("\ncells the OLD grid called walkable but the body cannot enter:")
	for map_path: String in MAPS:
		if not ResourceLoader.exists(map_path):
			continue
		var scene: PackedScene = load(map_path) as PackedScene
		if scene == null:
			continue
		var root: Node = scene.instantiate()
		add_child(root)
		await get_tree().physics_frame
		await get_tree().physics_frame
		await _report(map_path, root)
		root.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _report(map_path: String, root: Node) -> void:
	var bounds: Rect2 = _bounds(root)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		print("  %-24s (no bounds)" % map_path.get_file())
		return
	var space: PhysicsDirectSpaceState2D = get_viewport().world_2d.direct_space_state
	var box := RectangleShape2D.new()
	box.size = PLAYER_CLEARANCE
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = box
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var walkable_cells: int = 0
	var blind_cells: int = 0
	var y: float = bounds.position.y
	while y < bounds.end.y:
		var x: float = bounds.position.x
		while x < bounds.end.x:
			query.transform = Transform2D(0.0, Vector2(x, y) + PLAYER_SHAPE_OFFSET)
			query.collision_mask = OLD_MASK
			if space.intersect_shape(query, 1).is_empty():
				walkable_cells += 1
				query.collision_mask = PhysicsLayers.SOLID_GROUND_MASK
				if not space.intersect_shape(query, 1).is_empty():
					blind_cells += 1
			x += CELL_SIZE
		y += CELL_SIZE
		await get_tree().process_frame

	var pct: float = 100.0 * float(blind_cells) / maxf(1.0, float(walkable_cells))
	print("  %-24s %6d of %7d 'walkable' cells were solid scenery (%.1f%%)" % [
		map_path.get_file(), blind_cells, walkable_cells, pct
	])


func _bounds(root: Node) -> Rect2:
	var combined := Rect2()
	var has_bounds: bool = false
	for node: Node in root.find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		var used: Rect2i = layer.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		var first: Vector2 = layer.to_global(layer.map_to_local(used.position))
		var last: Vector2 = layer.to_global(layer.map_to_local(used.end - Vector2i.ONE))
		var half_tile: Vector2 = Vector2(layer.tile_set.tile_size) * 0.5
		var layer_bounds := Rect2(
			Vector2(minf(first.x, last.x), minf(first.y, last.y)) - half_tile,
			Vector2(absf(last.x - first.x), absf(last.y - first.y))
				+ Vector2(layer.tile_set.tile_size)
		)
		if not has_bounds:
			combined = layer_bounds
			has_bounds = true
		else:
			combined = combined.merge(layer_bounds)
	return combined
