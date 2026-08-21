extends SceneTree
## Blow up old_demon.png frame by frame with indices, so an idle pose can be
## picked from the walk cycle rather than guessed.
##   godot --headless --path . -s tools/render_demon_frames.gd

const SHEET: String = "res://assets/sprites/characters/hell/old_demon.png"
const FW: int = 56
const FH: int = 64
const SCALE: int = 4


func _init() -> void:
	var tex: Texture2D = load(SHEET)
	var src: Image = tex.get_image()
	var cols: int = src.get_width() / FW
	var out := Image.create_empty(cols * FW * SCALE, FH * SCALE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.12, 0.12, 0.16))
	for i: int in cols:
		var frame: Image = src.get_region(Rect2i(i * FW, 0, FW, FH))
		frame.resize(FW * SCALE, FH * SCALE, Image.INTERPOLATE_NEAREST)
		out.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(i * FW * SCALE, 0))
	var dest: String = ProjectSettings.globalize_path("res://previews").path_join("demon-frames.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://previews"))
	out.save_png(dest)
	print("SAVED ", dest, " cols=", cols)
	quit(0)
