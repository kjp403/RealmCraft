extends Node
## Walk the woodland beach the way a player does, in real physics.
##
## The beach's collision is not authored: beach_area_colliders.gd builds it at
## _ready from `shoreline` + `solid_footprints`. Those footprints are supposed to
## be DERIVED from the prop positions by tools/build_beach_layout.py, so hand-
## moving a prop in the .tscn leaves its collider behind on the old spot — a wall
## with no art on it, which is exactly what "invisible barriers on the beach"
## turned out to be. Nothing in the existing gates walks the resulting geometry.
##
## Beach and Deep Cove are instanced side by side under woodland_tiles, so this
## tool rebuilds that pairing and floods from the Woodlands seam along the beach's
## open north edge. It asserts the things a player actually goes there to do:
## every fishing hole is standable-next-to, the station/banker are reachable, and
## the two zones connect on foot — the last one being what makes the removed boat
## ferry redundant rather than missed.
##
## It also gates the desync itself: every entry in `solid_footprints` must sit
## directly under a prop that is actually drawn. That is the invariant hand-editing
## breaks, and it is the one a walk test alone will not catch — the stale colliders
## were free-standing walls in open sand, so everything stayed *reachable* while the
## beach was full of things to bump into.
##   godot --headless --path . --mode=client res://tools/verify_beach_walkable.tscn

## Offsets copied from woodland_tiles.tscn, so the seam between them is real.
const BEACH: Vector2 = Vector2(900.0, 1520.0)
const COVE: Vector2 = Vector2(1732.0, 1540.0)

## Matches character.tscn's CollisionShape2D — the body that has to fit through.
const BODY_SIZE: Vector2 = Vector2(12.0, 8.0)
const BODY_OFFSET: Vector2 = Vector2(0.0, -3.0)
## mineable_node.tscn's trigger: 32x32 at (0, -8).
const HOLE_BOX: Vector2 = Vector2(32.0, 32.0)
const HOLE_OFFSET: Vector2 = Vector2(0.0, -8.0)
## You gather by SWINGING at a node, not by standing on it: PickSwingAbility puts a
## PickArc at user + dir * spawn_offset (18), and pick_arc.tscn's circle sits a
## further 16 along that dir with radius 28. So the tool reaches this far from the
## player's origin — which is why a hole sitting out in the water is still fishable
## from dry sand, and why testing for body overlap would fail every one of them.
const GATHER_REACH: float = 18.0 + 16.0 + 28.0
## How far a footprint may sit from its prop's base before it counts as orphaned.
## Generated rects land exactly on it; a few hand-authored ones (Deep Cove's torch)
## are a pixel or two out. Real desyncs are off by 90-500px, so this separates them
## without re-flagging authored colliders every run.
const ALIGN_TOLERANCE_PX: float = 4.0
const STEP: float = 4.0

## Spots that must be reachable on foot from the Woodlands, in BEACH-local px.
const BEACH_TARGETS: Dictionary = {
	"ShrimpHole": Vector2(110, 298), "HerringHole": Vector2(280, 300),
	"TroutHole": Vector2(470, 392), "TunaHole": Vector2(690, 426),
	"CookingStation": Vector2(615, 265), "Banker": Vector2(560, 260),
}
## Same, in COVE-local px: proves the beach->cove seam is walkable with no ferry.
## All four holes, not a sample — the cove's props were given their collision late
## (they had none but a torch), and AccentRock is a 110x54 block sitting right on
## the Lionfish frontage.
const COVE_TARGETS: Dictionary = {
	"LionfishHole": Vector2(96, 279), "CrabHole": Vector2(192, 209),
	"ParrotHole": Vector2(480, 194), "AnglerHole": Vector2(608, 282),
}

var _failed: bool = false
var _walkable: Dictionary = {}
var _space: PhysicsDirectSpaceState2D
var _query: PhysicsShapeQueryParameters2D
var _min: Vector2
var _max: Vector2


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var world := Node2D.new()
	add_child(world)
	for path: String in [
		"res://source/common/gameplay/maps/maps/woodland/woodland_beach.tscn",
		"res://source/common/gameplay/maps/maps/woodland/woodland_deep_cove.tscn",
	]:
		var node: Node2D = (load(path) as PackedScene).instantiate() as Node2D
		node.position = BEACH if path.contains("beach") else COVE
		world.add_child(node)
	# Two physics frames: one to let _ready add the bodies, one to let the server
	# register their shapes before we start querying.
	await get_tree().physics_frame
	await get_tree().physics_frame

	_space = world.get_world_2d().direct_space_state
	var box := RectangleShape2D.new()
	box.size = BODY_SIZE
	_query = PhysicsShapeQueryParameters2D.new()
	_query.shape = box
	_query.collision_mask = PhysicsLayers.SOLID_GROUND_MASK
	_query.collide_with_bodies = true
	_query.collide_with_areas = false

	# Cover both grounds plus the seam between them.
	_min = Vector2(BEACH.x, BEACH.y)
	_max = Vector2(COVE.x + 704.0, maxf(BEACH.y + 512.0, COVE.y + 480.0))
	_flood()

	print("shapes=%d walkable cells=%d (%.0fpx lattice)" % [
		_count_shapes(world), _walkable.size(), STEP])
	for name: String in BEACH_TARGETS:
		_check(name, BEACH + BEACH_TARGETS[name], name.ends_with("Hole"))
	for name: String in COVE_TARGETS:
		_check(name, COVE + COVE_TARGETS[name], true)
	_check_seam()
	for child: Node in world.get_children():
		_check_footprints_have_art(child as Node2D, child, child.name)
	# Awaited: this one loads more scenes, and an un-awaited call would report its
	# failures after the exit code had already been decided.
	await _check_standalone_footprints()
	print("RESULT ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)


## Flood the standable lattice from the beach's open north edge — the Woodlands seam.
func _flood() -> void:
	var frontier: Array[Vector2i] = []
	var y0: int = int(_min.y + 16.0)
	var x: float = _min.x
	while x < _min.x + 832.0:
		var cell := _cell(Vector2(x, float(y0)))
		if not _walkable.has(cell) and _fits(_point(cell)):
			_walkable[cell] = true
			frontier.append(cell)
		x += STEP
	if frontier.is_empty():
		print("FAIL  nothing standable along the Woodlands seam")
		_failed = true
		return
	const NEIGHBOURS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for d: Vector2i in NEIGHBOURS:
			var next: Vector2i = cell + d
			if _walkable.has(next):
				continue
			var p: Vector2 = _point(next)
			if p.x < _min.x or p.y < _min.y or p.x > _max.x or p.y > _max.y:
				continue
			if not _fits(p):
				continue
			_walkable[next] = true
			frontier.append(next)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / STEP), roundi(p.y / STEP))


func _point(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x) * STEP, float(cell.y) * STEP)


## True when a character body standing at [param p] clears every solid.
func _fits(p: Vector2) -> bool:
	_query.transform = Transform2D(0.0, p + BODY_OFFSET)
	return _space.intersect_shape(_query, 1).is_empty()


## A fishing hole is usable when a REACHABLE standing spot overlaps its trigger;
## anything else just needs a reachable spot within arm's reach.
func _check(label: String, target: Vector2, is_hole: bool) -> void:
	var box := Rect2(target + HOLE_OFFSET - HOLE_BOX * 0.5, HOLE_BOX)
	var best: Vector2 = Vector2.INF
	for cell: Vector2i in _walkable:
		var p: Vector2 = _point(cell)
		var hit: bool
		if is_hole:
			hit = _box_distance(box, p) <= GATHER_REACH
		else:
			hit = p.distance_to(target) <= 24.0
		if hit and (best == Vector2.INF or p.distance_to(target) < best.distance_to(target)):
			best = p
	if best == Vector2.INF:
		_failed = true
		print("FAIL  %-16s no reachable standing spot" % label)
	else:
		print("ok    %-16s stand at (%d, %d)" % [label, best.x, best.y])


## The whole point of dropping the ferry: you can walk there instead.
func _check_seam() -> void:
	for cell: Vector2i in _walkable:
		if _point(cell).x >= COVE.x + 32.0:
			print("ok    %-16s walkable from the beach (no boat needed)" % "Deep Cove")
			return
	_failed = true
	print("FAIL  %-16s unreachable on foot - removing the ferry strands it" % "Deep Cove")


## Maps that are not part of the beach/cove pair, so they get the footprint gate but
## not the walk: same generator, same way of going stale.
const FOOTPRINT_ONLY: Array[String] = [
	"res://source/common/gameplay/maps/maps/woodland/deep_shoals.tscn",
]


func _check_standalone_footprints() -> void:
	for path: String in FOOTPRINT_ONLY:
		var root: Node = (load(path) as PackedScene).instantiate()
		add_child(root)
		await get_tree().process_frame
		for node: Node in root.find_children("*", "Node2D", true, false):
			if node.get("solid_footprints") != null:
				_check_footprints_have_art(node as Node2D, root, path.get_file())
		root.queue_free()


## Every solid footprint must line up with a prop that is actually drawn there.
##
## build_beach_layout.py derives each rect from its sprite: same centre x, and the
## rect's bottom IS the sprite's bottom (the prop's base). So a footprint whose art
## has been moved or deleted no longer lines up with anything, which is precisely
## the invisible wall. Checked against drawn nodes rather than against the
## generator's own tables, so the two cannot drift apart.
func _check_footprints_have_art(owner: Node2D, art_root: Node, label: String) -> void:
	var rects: Array[Rect2] = owner.get("solid_footprints")
	if rects == null:
		return
	var bases: Array[Vector2] = []
	# Footprints are authored in the collider node's OWN space, so measure the art
	# there too — these scenes sit at a world offset under woodland_tiles.
	_collect_bases(owner, art_root, bases)
	var orphans: int = 0
	for rect: Rect2 in rects:
		var centre_x: float = rect.position.x + rect.size.x * 0.5
		var found: bool = false
		for base: Vector2 in bases:
			if absf(base.x - centre_x) <= ALIGN_TOLERANCE_PX 					and absf(base.y - rect.end.y) <= ALIGN_TOLERANCE_PX:
				found = true
				break
		if found:
			continue
		orphans += 1
		_failed = true
		print("FAIL  %-16s footprint Rect2%s has no art on it" % [label, rect])
	if orphans == 0:
		print("ok    %-16s all %d footprints sit under real props" % [label, rects.size()])


## Base points (centre x, bottom y) of everything that can own a footprint: drawn
## props, and the cooking station, whose rect the generator hangs 14px below its
## node rather than off a sprite.
func _collect_bases(map: Node2D, node: Node, out: Array[Vector2]) -> void:
	var sprite := node as Sprite2D
	if sprite != null and sprite.texture != null:
		# `offset` shifts the drawn pixels without moving the node, so the base a
		# footprint is measured from moves with it (the beach torches sit on -8).
		var local: Vector2 = map.to_local(sprite.global_position) + sprite.offset
		var h: float = float(sprite.texture.get_height())
		var bottom: float = local.y + (h if not sprite.centered else h - floorf(h * 0.5))
		out.append(Vector2(local.x, bottom))
	elif node is Node2D and node.name.contains("Station"):
		var at: Vector2 = map.to_local((node as Node2D).global_position)
		out.append(Vector2(at.x, at.y + 14.0))
	for c: Node in node.get_children():
		_collect_bases(map, c, out)


## Shortest distance from [param p] to [param box], zero when inside it.
func _box_distance(box: Rect2, p: Vector2) -> float:
	var dx: float = maxf(maxf(box.position.x - p.x, 0.0), p.x - box.end.x)
	var dy: float = maxf(maxf(box.position.y - p.y, 0.0), p.y - box.end.y)
	return Vector2(dx, dy).length()


func _count_shapes(node: Node) -> int:
	var n: int = 1 if node is CollisionShape2D else 0
	for c: Node in node.get_children():
		n += _count_shapes(c)
	return n
