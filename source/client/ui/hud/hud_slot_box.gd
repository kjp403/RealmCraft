extends StyleBox
## The HUD keybind tile face — a custom StyleBox rather than a StyleBoxFlat,
## because the shape is the whole point and StyleBoxFlat can only do rounded
## rectangles.
##
## The tile is a plate with two CHAMFERED corners (top-right, bottom-left) and
## two square ones (top-left, bottom-right). The square corners are deliberate:
## they carry the L-brackets that frame the two readouts the player actually
## scans mid-fight — the key letter at top-left and the mana cost at
## bottom-right. The chamfers break the "row of boxes" silhouette so the bar
## reads as instrumentation rather than as UI panels.
##
## Drawn as a StyleBox (not a child Control) so it paints UNDER the button's own
## icon and text, and so each button state gets its own face for free.
## Instances are stateless and shared across every tile — see hud_slot_style.gd.

## Corner cut as a fraction of the tile's short side, so the 44px ability tiles
## and the 32px quick slots keep the same silhouette.
const CHAMFER_RATIO: float = 0.16
const CHAMFER_MIN: float = 3.0
const CHAMFER_MAX: float = 8.0

## Inner hairline that reads as a milled bevel under the frame.
const BEVEL: Color = Color(1.0, 0.94, 0.85, 0.09)

## Vertical plate gradient (lit from above).
var plate_top: Color = Color(0.13, 0.14, 0.17, 0.92)
var plate_bottom: Color = Color(0.04, 0.04, 0.06, 0.92)
## Outer frame stroke.
var frame: Color = Color(0.52, 0.43, 0.32, 0.95)
var frame_width: float = 1.0
## L-brackets on the two square corners.
var bracket: Color = Color(0.82, 0.66, 0.42, 0.85)
var bracket_width: float = 2.0
## Inset halo, used by the live (key-down) face. Fully transparent = no halo.
var halo: Color = Color(0.0, 0.0, 0.0, 0.0)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x <= 2.0 or rect.size.y <= 2.0:
		return
	var cut: float = chamfer_for(rect.size)

	# 1. Plate. Per-vertex colours give the gradient a StyleBoxFlat can't.
	var plate: PackedVector2Array = _outline(rect, cut)
	var shades: PackedColorArray = PackedColorArray()
	for point: Vector2 in plate:
		var down: float = clampf((point.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)
		shades.append(plate_top.lerp(plate_bottom, down))
	RenderingServer.canvas_item_add_polygon(to_canvas_item, plate, shades)

	# 2. Bevel hairline, one pixel in from the frame.
	_stroke(to_canvas_item, _outline(rect.grow(-2.0), cut - 1.0), BEVEL, 1.0)

	# 3. Frame, inset by half its width so the stroke lands fully inside the rect.
	_stroke(to_canvas_item, _outline(rect.grow(-frame_width * 0.5), cut), frame, frame_width)

	# 4. Live halo (key held): a soft second ring inside the frame.
	if halo.a > 0.0:
		_stroke(to_canvas_item, _outline(rect.grow(-frame_width - 1.5), cut - 1.0), halo, 2.0)

	# 5. Corner brackets on the two SQUARE corners. Kept SHORTER than the chamfer
	# so the key letter and the mana cost have clear room inside them. A
	# transparent bracket turns them off — on the 15px resource bars they would
	# be noise rather than framing.
	if bracket.a <= 0.0:
		return
	var arm: float = cut * 0.8
	var inset: float = frame_width + 1.0
	var left: float = rect.position.x + inset
	var top: float = rect.position.y + inset
	var right: float = rect.end.x - inset
	var bottom: float = rect.end.y - inset
	_line(to_canvas_item, PackedVector2Array([
		Vector2(left, top + arm), Vector2(left, top), Vector2(left + arm, top),
	]), bracket, bracket_width)
	_line(to_canvas_item, PackedVector2Array([
		Vector2(right, bottom - arm), Vector2(right, bottom), Vector2(right - arm, bottom),
	]), bracket, bracket_width)


## The corner cut for a control of [param rect_size]. Shared with
## ink_fill.gdshader so the resource bars cut their ends at exactly the same
## angle as the keybind tiles.
static func chamfer_for(rect_size: Vector2) -> float:
	return clampf(
		roundf(minf(rect_size.x, rect_size.y) * CHAMFER_RATIO), CHAMFER_MIN, CHAMFER_MAX
	)


## The tile silhouette, clockwise from the square top-left corner. Chamfers sit
## on the top-right and bottom-left so the bracketed corners stay square.
func _outline(rect: Rect2, cut: float) -> PackedVector2Array:
	var safe: float = clampf(cut, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x - safe, rect.position.y),
		Vector2(rect.end.x, rect.position.y + safe),
		rect.end,
		Vector2(rect.position.x + safe, rect.end.y),
		Vector2(rect.position.x, rect.end.y - safe),
	])


## Closes [param points] and strokes it.
func _stroke(item: RID, points: PackedVector2Array, color: Color, width: float) -> void:
	points.append(points[0])
	_line(item, points, color, width)


func _line(item: RID, points: PackedVector2Array, color: Color, width: float) -> void:
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(points.size())
	colors.fill(color)
	RenderingServer.canvas_item_add_polyline(item, points, colors, width, true)
