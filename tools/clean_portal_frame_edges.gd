extends SceneTree
## Clear a 2px border on every 64x64 frame so swirl sparks never form a square outline.
const TEX_PATH := "res://assets/sprites/vfx/portal/portal.png"
const FRAME := 64
const BORDER := 2

func _initialize() -> void:
	var abs_path := ProjectSettings.globalize_path(TEX_PATH)
	var img := Image.new()
	if img.load(abs_path) != OK:
		push_error("load failed"); quit(1); return
	var cleared := 0
	var cols := img.get_width() / FRAME
	var rows := img.get_height() / FRAME
	for r in rows:
		for c in cols:
			for y in FRAME:
				for x in FRAME:
					if mini(mini(x, y), mini(FRAME - 1 - x, FRAME - 1 - y)) >= BORDER:
						continue
					var px := c * FRAME + x
					var py := r * FRAME + y
					var col := img.get_pixel(px, py)
					if col.a > 0.0:
						col.a = 0.0
						img.set_pixel(px, py, col)
						cleared += 1
	img.save_png(abs_path)
	print("cleared_border_pixels=", cleared)
	quit(0)
