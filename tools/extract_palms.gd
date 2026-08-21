extends SceneTree
## Cut whole palm trees out of the animated sheets. The per-frame files shipped
## in atlas-props-sprites are FOLIAGE ONLY — using them put fronds in the air
## with no trunk under them and cropped the crown.
##   godot --headless --path . -s tools/extract_palms.gd

const SRC: String = "res://assets/sprites/environment/sea/_src/palm_sheet_%d.png"
const OUT: String = "res://assets/sprites/environment/sea/props/palm_%d.png"
const FRAME := Vector2i(156, 215)


func _init() -> void:
	for i: int in [1, 2, 3]:
		var tex: Texture2D = load(SRC % i)
		if tex == null:
			push_error("missing palm sheet %d" % i)
			continue
		var sheet: Image = tex.get_image()
		# Frame 0 is the rest pose; the rest of the row is the sway animation.
		var frame: Image = sheet.get_region(Rect2i(Vector2i.ZERO, FRAME))
		# Trim the transparent margin so the sprite's centre is the tree itself,
		# which is what the placement maths assumes.
		var used: Rect2i = frame.get_used_rect()
		if used.size.x > 0:
			frame = frame.get_region(used)
		frame.save_png(ProjectSettings.globalize_path(OUT % i))
		print("palm %d -> %dx%d" % [i, frame.get_width(), frame.get_height()])
	quit(0)
