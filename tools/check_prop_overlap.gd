extends Node
## Do any two props actually intersect ON SCREEN?
##
## Bounding boxes are useless here: these sprites carry big transparent margins,
## so box tests either miss a palm drawn inside a hull or flag a shell lying on
## open sand. This walks the OPAQUE PIXELS of each overlapping pair and reports
## the real intersection, which is what a player sees.
##   godot --path . --mode=client res://tools/check_prop_overlap.tscn

const MAPS: Array[String] = [
	"res://source/common/gameplay/maps/maps/woodland/deep_shoals.tscn",
	"res://source/common/gameplay/maps/maps/woodland/woodland_beach.tscn",
	"res://source/common/gameplay/maps/maps/woodland/woodland_east_link.tscn",
]
## Props meant to share ground: the lighthouse cabin stands on its base.
const STACKS: Array[String] = ["LighthouseCabin|LighthouseBase"]
## Pixels of genuine overlap tolerated — sprite edges may kiss.
const TOLERANCE: int = 120
## Sample step: every 2nd pixel is plenty to catch a tree inside a ship.
const STEP: int = 2

var _failed: bool = false


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	for map_path: String in MAPS:
		_check(map_path)
	print("RESULT ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)


func _check(map_path: String) -> void:
	var packed: PackedScene = load(map_path) as PackedScene
	if packed == null:
		push_error("could not load %s" % map_path)
		_failed = true
		return
	var root: Node = packed.instantiate()
	var scenery: Node = root.get_node_or_null("Scenery")
	if scenery == null:
		root.free()
		return

	var props: Array = []
	for child: Node in scenery.get_children():
		var sprite: Sprite2D = child as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var img: Image = sprite.texture.get_image()
		var size: Vector2i = img.get_size()
		props.append({
			"name": String(sprite.name),
			"img": img,
			"rect": Rect2i(Vector2i(sprite.position) - size / 2, size),
		})

	var clashes: int = 0
	for i: int in props.size():
		for j: int in range(i + 1, props.size()):
			var a: Dictionary = props[i]
			var b: Dictionary = props[j]
			if ("%s|%s" % [a.name, b.name]) in STACKS or ("%s|%s" % [b.name, a.name]) in STACKS:
				continue
			var box: Rect2i = (a.rect as Rect2i).intersection(b.rect)
			if box.size.x <= 0 or box.size.y <= 0:
				continue
			var solid: int = 0
			var y: int = box.position.y
			while y < box.end.y:
				var x: int = box.position.x
				while x < box.end.x:
					var pa: Vector2i = Vector2i(x, y) - (a.rect as Rect2i).position
					var pb: Vector2i = Vector2i(x, y) - (b.rect as Rect2i).position
					if (a.img as Image).get_pixelv(pa).a > 0.35 \
							and (b.img as Image).get_pixelv(pb).a > 0.35:
						solid += STEP * STEP
					x += STEP
				y += STEP
			if solid > TOLERANCE:
				print("  %-18s x %-18s %d px of overlap" % [a.name, b.name, solid])
				clashes += 1
	print("%s: %d props, %d real overlaps" % [map_path.get_file(), props.size(), clashes])
	if clashes > 0:
		_failed = true
	root.free()
