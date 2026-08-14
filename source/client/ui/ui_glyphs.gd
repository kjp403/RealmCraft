class_name UiGlyphs
## Symbols the bundled UI font lacks on HTML5 (no OS font fallback). Desktop
## keeps the nicer glyphs; web gets ASCII so Godot does not draw hex tofu boxes.


static func is_web() -> bool:
	return OS.has_feature("web")


static func close() -> String:
	return "x" if is_web() else "✕"


static func back() -> String:
	return "<- " if is_web() else "← "


static func bullet() -> String:
	return "*" if is_web() else "●"


static func hollow_bullet() -> String:
	return "o" if is_web() else "○"


static func diamond() -> String:
	return "+" if is_web() else "◆"


static func check() -> String:
	return "*" if is_web() else "✓"


static func right_arrow() -> String:
	return "->" if is_web() else "→"


## Minimap / compass marker for a world-space direction.
static func compass(direction: Vector2) -> String:
	if direction == Vector2.ZERO:
		return diamond()
	var octant: int = wrapi(roundi(direction.angle() / (PI / 4.0)), 0, 8)
	var fancy := PackedStringArray(["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"])
	var plain := PackedStringArray([">", "\\", "v", "/", "<", "/", "^", "\\"])
	return plain[octant] if is_web() else fancy[octant]
