extends SceneTree
## Contact sheet of the new fish icons, raw above cooked, so the slice indices
## and the derived cooked tint can be eyeballed before they ship.
##   godot --headless --path . -s tools/render_fish_icon_sheet.gd

const SLUGS: Array[String] = ["halibut", "stingray", "wolffish", "blue_lobster"]
const SIZE: int = 32
const SCALE: int = 3
const PAD: int = 8


func _init() -> void:
	var w: int = SLUGS.size() * (SIZE * SCALE + PAD) + PAD
	var h: int = 2 * (SIZE * SCALE + PAD) + PAD
	var sheet := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.10, 0.11, 0.14))
	for i: int in SLUGS.size():
		for row: int in 2:
			var suffix: String = "" if row == 0 else "_cooked"
			var path: String = "res://assets/sprites/items/icons/fish_%s%s.png" % [SLUGS[i], suffix]
			var tex: Texture2D = load(path)
			if tex == null:
				continue
			var img: Image = tex.get_image()
			img.resize(SIZE * SCALE, SIZE * SCALE, Image.INTERPOLATE_NEAREST)
			if img.get_format() != sheet.get_format():
				img.convert(sheet.get_format())
			sheet.blend_rect(
				img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i(PAD + i * (SIZE * SCALE + PAD), PAD + row * (SIZE * SCALE + PAD))
			)
	var dest: String = ProjectSettings.globalize_path("res://previews").path_join("fish-icons.png")
	sheet.save_png(dest)
	print("SAVED ", dest)
	quit(0)
