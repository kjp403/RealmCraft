class_name ClickMoveMarker
extends Node2D
## Green "×" that flashes on the ground at a left-click / minimap move target.
## Mirrors the minimap click marker so world clicks read the same.


const COLOR: Color = Color(0.65, 1.0, 0.72, 1.0)
const OUTLINE: Color = Color(0.05, 0.12, 0.08, 0.95)
const FADE_S: float = 0.55
const ARM: float = 6.0

var _tween: Tween


func _ready() -> void:
	# Stay world-anchored even while parented under the moving local player.
	top_level = true
	z_index = 20
	modulate.a = 0.0
	hide()


func _draw() -> void:
	# Dark outline first, then the green X — matches the minimap glyph.
	for width: float in [3.0, 1.5]:
		var color: Color = OUTLINE if width > 2.0 else COLOR
		draw_line(Vector2(-ARM, -ARM), Vector2(ARM, ARM), color, width, true)
		draw_line(Vector2(ARM, -ARM), Vector2(-ARM, ARM), color, width, true)


func flash_at(world_position: Vector2) -> void:
	global_position = world_position
	show()
	modulate.a = 1.0
	queue_redraw()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", 0.0, FADE_S)
	_tween.tween_callback(hide)
