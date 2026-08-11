extends SceneTree
## DISABLED — the old 5× stripe east fill is banned.
## Use: godot --headless --path . -s tools/build_woodland_east_contiguous.gd

func _initialize() -> void:
	push_error("expand_woodland_east.gd is disabled. Use build_woodland_east_contiguous.gd")
	quit(1)
