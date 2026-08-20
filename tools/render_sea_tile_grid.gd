extends SceneTree
## Draw a numbered 32px grid over a Sea Adventures sheet so tile indices can be
## read off precisely instead of guessed. Region + sheet are set by args:
##   godot --headless --path . -s tools/render_sea_tile_grid.gd -- beach_foam 0 0 20 8

const DIR: String = ""
const TILE: int = 16
const SCALE: int = 2
const GRID: Color = Color(1, 0, 0.6, 0.55)
const LABEL_BG: Color = Color(0, 0, 0, 0.65)


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var sheet: String = args[0] if args.size() > 0 else "beach_foam"
	var cx: int = int(args[1]) if args.size() > 1 else 0
	var cy: int = int(args[2]) if args.size() > 2 else 0
	var cw: int = int(args[3]) if args.size() > 3 else 20
	var ch: int = int(args[4]) if args.size() > 4 else 8

	var tex: Texture2D = load(sheet)
	if tex == null:
		push_error("no sheet %s" % sheet)
		quit(1)
		return
	var src: Image = tex.get_image()
	var region := Rect2i(cx * TILE, cy * TILE, cw * TILE, ch * TILE)
	region = region.intersection(Rect2i(Vector2i.ZERO, src.get_size()))
	var cut: Image = src.get_region(region)
	cut.resize(region.size.x * SCALE, region.size.y * SCALE, Image.INTERPOLATE_NEAREST)
	if cut.get_format() != Image.FORMAT_RGBA8:
		cut.convert(Image.FORMAT_RGBA8)

	var step: int = TILE * SCALE
	for gx: int in range(0, cut.get_width(), step):
		for y: int in cut.get_height():
			cut.set_pixel(gx, y, GRID)
	for gy: int in range(0, cut.get_height(), step):
		for x: int in cut.get_width():
			cut.set_pixel(x, gy, GRID)
	# Corner ticks double as a coordinate readout: every cell gets a dark patch
	# whose width encodes the column and height the row, in 3px units.
	for ty: int in ch:
		for tx: int in cw:
			var ox: int = tx * step
			var oy: int = ty * step
			for px: int in mini(step - 2, 3 + (cx + tx) * 3):
				cut.set_pixel(ox + 1 + px, oy + 1, LABEL_BG)
			for py: int in mini(step - 2, 3 + (cy + ty) * 3):
				cut.set_pixel(ox + 1, oy + 1 + py, LABEL_BG)

	var out: String = ProjectSettings.globalize_path("res://previews/sea").path_join(
		"grid_src_%d_%d.png" % [cx, cy]
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://previews/sea"))
	cut.save_png(out)
	print("SAVED ", out, " region=", region)
	quit(0)
