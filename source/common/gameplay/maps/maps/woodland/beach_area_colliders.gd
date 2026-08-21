extends Node2D
## Builds WORLD-layer collisions for a beach/cove scene: water (shoreline),
## solid prop footprints, and an outer rim so players can't walk off the art
## into the black void. Dock + boat pads stay walkable via cutouts.

@export var ground_size: Vector2 = Vector2(832, 512)
## Shoreline samples left→right (local px). Water fills from each sample down to
## ground_size.y. Outliers should already be cleaned when authored.
@export var shoreline: PackedVector2Array = PackedVector2Array()
## Walkable pier corridor cut out of the water collider.
@export var dock_walk: Rect2 = Rect2()
## Walkable pad around the boat teleporter (often just off the pier tip).
@export var boat_pad: Rect2 = Rect2()
## Solid footprints for buildings / palms / umbrellas / chairs / etc.
@export var solid_footprints: Array[Rect2] = []
## Thickness of the outer rim walls (local px).
@export var rim_thickness: float = 24.0
## When false, that side stays open so adjacent beach strips can join.
@export var rim_west: bool = true
@export var rim_east: bool = true
## The north edge used to be unconditionally open, on the assumption every beach
## seams into woodland up there. A standalone beach (Deep Shoals) inherited that
## and had nothing but void above the art to walk into. Default closed; set false
## only where something real is actually joined on.
@export var rim_north: bool = true


func _ready() -> void:
	var body := StaticBody2D.new()
	body.name = "BeachColliders"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	_add_water_colliders(body)
	for footprint: Rect2 in solid_footprints:
		_add_rect(body, footprint)
	_add_rim(body)


func _add_water_colliders(body: StaticBody2D) -> void:
	if shoreline.is_empty():
		return
	var walk := _walkable_union()
	# Vertical strips between shoreline samples. Skip / split any strip that
	# overlaps the dock or boat pad so those stay walkable.
	for i: int in range(shoreline.size() - 1):
		var a: Vector2 = shoreline[i]
		var b: Vector2 = shoreline[i + 1]
		var x0: float = minf(a.x, b.x)
		var x1: float = maxf(a.x, b.x)
		if x1 <= x0:
			continue
		var y_shore: float = maxf(a.y, b.y)
		var strip := Rect2(x0, y_shore, x1 - x0, ground_size.y - y_shore)
		if strip.size.y <= 0.0:
			continue
		for piece: Rect2 in _subtract_rects(strip, walk):
			_add_rect(body, piece)


func _walkable_union() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if dock_walk.size.x > 0.0 and dock_walk.size.y > 0.0:
		out.append(dock_walk)
	if boat_pad.size.x > 0.0 and boat_pad.size.y > 0.0:
		out.append(boat_pad)
	return out


## Subtract axis-aligned cutouts from [param rect]. Returns 0–N leftover rects.
func _subtract_rects(rect: Rect2, cutouts: Array[Rect2]) -> Array[Rect2]:
	var pieces: Array[Rect2] = [rect]
	for cut: Rect2 in cutouts:
		var next: Array[Rect2] = []
		for piece: Rect2 in pieces:
			next.append_array(_subtract_one(piece, cut))
		pieces = next
	return pieces


func _subtract_one(rect: Rect2, cut: Rect2) -> Array[Rect2]:
	var overlap: Rect2 = rect.intersection(cut)
	if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
		return [rect]
	var out: Array[Rect2] = []
	# Top band
	if overlap.position.y > rect.position.y:
		out.append(Rect2(
			rect.position,
			Vector2(rect.size.x, overlap.position.y - rect.position.y)
		))
	# Bottom band
	var overlap_bottom: float = overlap.position.y + overlap.size.y
	var rect_bottom: float = rect.position.y + rect.size.y
	if overlap_bottom < rect_bottom:
		out.append(Rect2(
			Vector2(rect.position.x, overlap_bottom),
			Vector2(rect.size.x, rect_bottom - overlap_bottom)
		))
	# Left band (within overlap's vertical span)
	if overlap.position.x > rect.position.x:
		out.append(Rect2(
			Vector2(rect.position.x, overlap.position.y),
			Vector2(overlap.position.x - rect.position.x, overlap.size.y)
		))
	# Right band
	var overlap_right: float = overlap.position.x + overlap.size.x
	var rect_right: float = rect.position.x + rect.size.x
	if overlap_right < rect_right:
		out.append(Rect2(
			Vector2(overlap_right, overlap.position.y),
			Vector2(rect_right - overlap_right, overlap.size.y)
		))
	return out


func _add_rim(body: StaticBody2D) -> void:
	var t: float = rim_thickness
	var w: float = ground_size.x
	var h: float = ground_size.y
	_add_rect(body, Rect2(0.0, h - t, w, t * 2.0))
	if rim_north:
		_add_rect(body, Rect2(0.0, -t, w, t))
	if rim_west:
		_add_rect(body, Rect2(-t, 0.0, t, h))
	if rim_east:
		_add_rect(body, Rect2(w, 0.0, t, h))


func _add_rect(body: StaticBody2D, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	shape_node.shape = shape
	shape_node.position = rect.position + rect.size * 0.5
	body.add_child(shape_node)
