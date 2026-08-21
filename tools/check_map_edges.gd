extends Node
## Gate for the bug that let players walk off the art into black: a map whose
## painted area has no collision on a side is escapable, and nothing in the
## existing gates looks at map geometry.
##
## The north edge is the one that bites. Both boundary builders in this project —
## beach_area_colliders.gd and woodland_tiles' BeachVoidBounds — were written for
## maps that seam into something up there, so both leave the top open
## unconditionally. Any map that does NOT have a neighbour north of it inherits a
## hole the size of its own width.
##   godot --headless --path . --mode=client res://tools/check_map_edges.tscn

const MAPS: Array[String] = [
	"res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn",
	"res://source/common/gameplay/maps/maps/woodland/deep_shoals.tscn",
	"res://source/common/gameplay/maps/maps/woodland/woodland_beach.tscn",
	"res://source/common/gameplay/maps/maps/woodland/woodland_east_link.tscn",
]

## Maps whose north edge is deliberately open because something real joins on.
const NORTH_OPEN_BY_DESIGN: Array[String] = [
	"woodland_beach.tscn", "woodland_east_link.tscn",
]

## A barrier has to actually span the edge, not just be some prop's footprint.
const MIN_SPAN_PX: float = 400.0

var _failed: bool = false


func _ready() -> void:
	call_deferred(&"_go")


func _bodies(node: Node, out: Array) -> void:
	if node is StaticBody2D:
		out.append(node)
	for c: Node in node.get_children():
		_bodies(c, out)


func _go() -> void:
	for path: String in MAPS:
		var root: Node = (load(path) as PackedScene).instantiate()
		add_child(root)
		await get_tree().process_frame
		var found: Array = []
		_bodies(root, found)
		var north: bool = false
		var shapes: int = 0
		for b: Node in found:
			for c: Node in b.get_children():
				var cs: CollisionShape2D = c as CollisionShape2D
				if cs == null or not (cs.shape is RectangleShape2D):
					continue
				shapes += 1
				var r: RectangleShape2D = cs.shape as RectangleShape2D
				var top: float = (b as Node2D).position.y + cs.position.y - r.size.y * 0.5
				if top <= 0.0 and r.size.x > MIN_SPAN_PX:
					north = true
		var want: bool = not (path.get_file() in NORTH_OPEN_BY_DESIGN)
		if want and not north:
			_failed = true
		print("%-24s bodies=%-2d shapes=%-4d north_barrier=%-3s %s" % [
			path.get_file(), found.size(), shapes, "YES" if north else "NO",
			"OK" if north == want else "FAIL - players can walk off the art"])
		root.queue_free()
	print("RESULT ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
