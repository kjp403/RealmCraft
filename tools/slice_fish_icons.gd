extends SceneTree
## Cut item icons out of the fishing pack's fish_all.png (10x10 grid of 16px
## cells, indexed by the pack's "fish list.txt" order) and write them at the
## 32x32 the item icons use. Cooked variants are derived from the raw icon with
## a warm grill tint — placeholder art until a cooked sheet exists.
##   godot --headless --path . -s tools/slice_fish_icons.gd

const SHEET: String = "res://assets/sprites/items/icons/_src_fish_all.png"
const OUT_DIR: String = "res://assets/sprites/items/icons"
const CELL: int = 16
const COLS: int = 10
const SCALE: int = 2

## slug -> 1-based index in the pack's fish list.
const PICKS: Dictionary = {
	"halibut": 22,
	"stingray": 24,
	"wolffish": 25,
	"blue_lobster": 51,
}


func _init() -> void:
	var tex: Texture2D = load(SHEET)
	if tex == null:
		push_error("missing %s" % SHEET)
		quit(1)
		return
	var sheet: Image = tex.get_image()
	var out_abs: String = ProjectSettings.globalize_path(OUT_DIR)
	for slug: String in PICKS:
		var index: int = int(PICKS[slug]) - 1
		var cell := Rect2i((index % COLS) * CELL, (index / COLS) * CELL, CELL, CELL)
		var raw: Image = sheet.get_region(cell)
		raw.resize(CELL * SCALE, CELL * SCALE, Image.INTERPOLATE_NEAREST)
		raw.save_png(out_abs.path_join("fish_%s.png" % slug))

		var cooked: Image = raw.duplicate()
		for y: int in cooked.get_height():
			for x: int in cooked.get_width():
				var c: Color = cooked.get_pixel(x, y)
				if c.a <= 0.0:
					continue
				# Grill it: pull toward a warm brown and knock the saturation back.
				var grey: float = c.r * 0.3 + c.g * 0.6 + c.b * 0.1
				var warm := Color(
					clampf(grey * 1.15 + 0.22, 0.0, 1.0),
					clampf(grey * 0.85 + 0.10, 0.0, 1.0),
					clampf(grey * 0.55, 0.0, 1.0),
					c.a
				)
				cooked.set_pixel(x, y, c.lerp(warm, 0.78))
		cooked.save_png(out_abs.path_join("fish_%s_cooked.png" % slug))
		print("wrote fish_%s.png + cooked (cell %d)" % [slug, index])
	quit(0)
