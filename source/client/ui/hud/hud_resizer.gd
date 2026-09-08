class_name HudResizer
extends Control
## Drag-to-resize for one HUD panel. Add it to the panel and forget it:
##
##   HudResizer.attach(quest_tracker, &"quest_tracker", HudResizer.AXIS_X,
##       HudResizer.SizeMode.MODE_MIN_SIZE, Vector2(160, 0), Vector2(360, 0))
##
## It follows HudLayout.locked on its own, restores the player's stored size on
## attach, and writes it back once per drag.
##
## WHY A CHILD WITH top_level, NOT A PARENT WRAPPER
## Wrapping the panels was the obvious shape and it does not survive contact with
## this HUD: hud.tscn addresses QuestTracker by a unique node path, Hud holds an
## @onready reference to it, and Hud._place_right_rail writes its offsets every
## time the right rail re-stacks. Re-parenting breaks all three. So the resizer
## goes INSIDE the panel and sets top_level, which does two things that matter:
## Container.sort_children skips top_level children (a PanelContainer will not
## try to lay it out as content) and so does the container's minimum-size
## calculation (it cannot inflate the panel it is measuring). The node is still
## owned by the host, so it frees with it and hides with it.
##
## WHY TWO SIZE MODES
## The four HUD surfaces are not the same kind of Control, and pretending they
## are is what makes a "universal" resizer silently no-op on three of them:
##   MODE_OFFSETS  - the panel's rect comes from its anchor offsets (the chat
##                   box: anchored bottom-left, an explicit 260x340). Resizing
##                   means writing offsets, and BOTH axes are real.
##   MODE_MIN_SIZE - the panel is a shrink-to-content PanelContainer whose height
##                   IS its content (the quest tracker, the party roster). Its
##                   height cannot be dragged in any honest sense; writing
##                   custom_minimum_size is what widening means, and the panel
##                   grows along its own grow_horizontal direction.
## Handing a content-driven panel a vertical handle would give the player a grip
## that visibly does nothing, so [member axes] exists to say which are real.

## Bitmask for [member axes].
const AXIS_X: int = 1
const AXIS_Y: int = 2
const AXIS_BOTH: int = AXIS_X | AXIS_Y

enum SizeMode {
	MODE_OFFSETS,  ## Rect comes from anchor offsets - write them.
	MODE_MIN_SIZE, ## Shrink-to-content panel - write custom_minimum_size.
}

## How close to an edge counts as a grab, in pixels. Generous on purpose: these
## panels are small and the alternative is a 1px target on a 12px-text UI.
const GRAB: float = 7.0
## Longest a grip bar gets drawn.
const GRIP_LENGTH: float = 14.0

## Edit-mode chrome. Deliberately quiet - this is a mode indicator, not a widget.
const EDIT_BORDER: Color = Color(0.58, 0.82, 0.98, 0.55)
const EDIT_FILL: Color = Color(0.58, 0.82, 0.98, 0.05)
const GRIP: Color = Color(0.58, 0.82, 0.98, 0.85)
const GRIP_HOT: Color = Color(1.0, 0.86, 0.50, 1.0)

const EDGE_LEFT: int = 1
const EDGE_RIGHT: int = 2
const EDGE_TOP: int = 4
const EDGE_BOTTOM: int = 8

## Emitted after the host has been resized, during the drag as well as at the
## end. Panels whose text must re-wrap connect here - see QuestTracker.
signal size_changed(new_size: Vector2)

var host: Control
var setting_key: StringName = &""
var axes: int = AXIS_BOTH
var mode: SizeMode = SizeMode.MODE_OFFSETS
var min_size: Vector2 = Vector2(80, 40)
## Zero on an axis means "no ceiling from us".
var max_size: Vector2 = Vector2.ZERO

# Which edges actually MOVE when the host grows. A panel pinned to the right of
# the screen grows leftward, so its right edge is not draggable - offering a
# handle there would be a lie. Derived from the host's grow direction in _ready.
var _free_left: bool = false
var _free_right: bool = false
var _free_top: bool = false
var _free_bottom: bool = false

# The geometry the SCENE authored, captured before any stored size is applied.
# This is what "Reset HUD layout" puts back, so it has to be sampled in _ready
# ahead of _restore() - once a stored size has been written there is nothing left
# on the host to recover the original from.
var _authored_min_size: Vector2 = Vector2.ZERO
var _authored_offsets: Array[float] = []

var _drag_edges: int = 0 # bitmask of EDGE_* currently being dragged
var _hover_edges: int = 0
var _drag_from: Vector2 = Vector2.ZERO
var _size_at_grab: Vector2 = Vector2.ZERO


## Build a resizer, wire it to [param target] and return it. The only entry point
## callers should use.
static func attach(
	target: Control,
	key: StringName,
	resize_axes: int = AXIS_BOTH,
	size_mode: SizeMode = SizeMode.MODE_OFFSETS,
	minimum: Vector2 = Vector2(80, 40),
	maximum: Vector2 = Vector2.ZERO
) -> HudResizer:
	var resizer: HudResizer = HudResizer.new()
	resizer.name = "HudResizer"
	resizer.host = target
	resizer.setting_key = key
	resizer.axes = resize_axes
	resizer.mode = size_mode
	resizer.min_size = minimum
	resizer.max_size = maximum
	target.add_child(resizer)
	return resizer


func _ready() -> void:
	if host == null:
		host = get_parent() as Control
	if host == null:
		push_warning("HudResizer needs a Control host; disabling.")
		return

	# Exempt from the host's layout AND from its minimum-size maths. Without this
	# a PanelContainer host would lay this node out as content.
	top_level = true
	# Painted above the panel's own content so the grips are never buried under a
	# label; the host still owns the paint order relative to the rest of the HUD.
	z_index = 1
	focus_mode = Control.FOCUS_NONE

	_derive_free_edges()
	_capture_authored()
	_restore()

	host.item_rect_changed.connect(_follow_host)
	HudLayout.lock_changed.connect(_apply_lock)
	HudLayout.layout_reset.connect(_revert_to_authored)
	_follow_host()
	_apply_lock(HudLayout.locked)


## A panel grows away from the edge it is pinned to, and only the far edge moves.
## GROW_DIRECTION_BOTH is the centred case, where both edges move - _commit works
## in sizes rather than edge positions, so it handles that without a special case.
##
## RE-DERIVED ON EVERY RECT CHANGE, not once at _ready. A host's layout is not
## necessarily final when its children enter the tree: Hud._ready() re-anchors
## QuestTracker into the right rail AFTER hud.tscn has instanced it, and
## Hud._place_right_rail rewrites its offsets whenever the rail re-stacks. A
## resizer that sampled grow_horizontal once could latch onto the pre-anchor
## value and then offer a handle on the edge that is actually pinned - a grip the
## player can drag that moves nothing.
func _derive_free_edges() -> void:
	match host.grow_horizontal:
		Control.GROW_DIRECTION_BEGIN:
			_free_left = true
		Control.GROW_DIRECTION_END:
			_free_right = true
		_:
			_free_left = true
			_free_right = true
	match host.grow_vertical:
		Control.GROW_DIRECTION_BEGIN:
			_free_top = true
		Control.GROW_DIRECTION_END:
			_free_bottom = true
		_:
			_free_top = true
			_free_bottom = true
	if not (axes & AXIS_X):
		_free_left = false
		_free_right = false
	if not (axes & AXIS_Y):
		_free_top = false
		_free_bottom = false


# --- Geometry ----------------------------------------------------------------

## Mirror the host's on-screen rect. top_level means our position is global, so
## this is a straight copy rather than a parent-relative conversion.
func _follow_host() -> void:
	if not is_instance_valid(host):
		return
	global_position = host.global_position
	size = host.size
	_derive_free_edges()
	queue_redraw()


## Sample the host's shipped geometry. Must run BEFORE _restore().
func _capture_authored() -> void:
	_authored_min_size = host.custom_minimum_size
	_authored_offsets = [
		host.offset_left, host.offset_top, host.offset_right, host.offset_bottom
	]


## Put the host back as the scene authored it, restoring ONLY the mechanism this
## resizer writes.
##
## Reverting both would be over-reach with real consequences. A MODE_MIN_SIZE
## resizer never touches offsets, but other systems do continuously —
## Hud._place_right_rail rewrites the quest tracker's offset_top/offset_bottom
## every time the right rail re-stacks. Restoring an offset captured at _ready
## would hand that panel stale geometry owned by something else, which is a
## reset button reaching outside its own blast radius.
func _revert_to_authored() -> void:
	if not is_instance_valid(host):
		return
	match mode:
		SizeMode.MODE_MIN_SIZE:
			host.custom_minimum_size = _authored_min_size
		SizeMode.MODE_OFFSETS:
			if _authored_offsets.size() == 4:
				host.offset_left = _authored_offsets[0]
				host.offset_top = _authored_offsets[1]
				host.offset_right = _authored_offsets[2]
				host.offset_bottom = _authored_offsets[3]
	# Panels that re-wrap text (the quest tracker) need the same nudge a drag
	# gives them, or they keep the line breaks of the size just discarded. Pass
	# the AUTHORED size rather than host.size: the host has not been laid out yet
	# at this point, so reading its size back would hand the listener the size we
	# are in the middle of discarding.
	size_changed.emit(_authored_size())


## The size the scene authored, from whichever mechanism actually expressed it -
## a min size, an offset span, or both (the larger wins, which is what Control
## itself does).
func _authored_size() -> Vector2:
	if _authored_offsets.size() != 4:
		return _authored_min_size
	var span: Vector2 = Vector2(
		_authored_offsets[2] - _authored_offsets[0],
		_authored_offsets[3] - _authored_offsets[1]
	)
	return Vector2(maxf(_authored_min_size.x, span.x), maxf(_authored_min_size.y, span.y))


## Re-apply the player's stored size, if they have one. ZERO means untouched -
## honouring it as a size would collapse every panel on a fresh install.
func _restore() -> void:
	if setting_key.is_empty():
		return
	var stored: Vector2 = HudLayout.size_for(setting_key)
	if stored == Vector2.ZERO:
		return
	_commit(stored)


## Write a new size onto the host through whichever mechanism actually drives its
## rect, clamped, and only on the axes this resizer owns.
func _commit(wanted: Vector2) -> void:
	if not is_instance_valid(host):
		return
	var target: Vector2 = host.size
	if axes & AXIS_X:
		target.x = maxf(wanted.x, min_size.x)
		if max_size.x > 0.0:
			target.x = minf(target.x, max_size.x)
	if axes & AXIS_Y:
		target.y = maxf(wanted.y, min_size.y)
		if max_size.y > 0.0:
			target.y = minf(target.y, max_size.y)

	match mode:
		SizeMode.MODE_MIN_SIZE:
			# The panel is shrink-to-content: custom_minimum_size is the only
			# lever that widens it, and the content floor still wins, so a player
			# can never drag a panel narrower than the text inside it.
			var minimum: Vector2 = host.custom_minimum_size
			if axes & AXIS_X:
				minimum.x = target.x
			if axes & AXIS_Y:
				minimum.y = target.y
			host.custom_minimum_size = minimum
		SizeMode.MODE_OFFSETS:
			# Move only the FREE edge, so the panel stays pinned where it was
			# authored instead of walking across the screen as it is resized.
			if axes & AXIS_X:
				if _free_left and not _free_right:
					host.offset_left = host.offset_right - target.x
				elif _free_right and not _free_left:
					host.offset_right = host.offset_left + target.x
				else:
					var grow_x: float = (target.x - host.size.x) * 0.5
					host.offset_left -= grow_x
					host.offset_right += grow_x
			if axes & AXIS_Y:
				if _free_top and not _free_bottom:
					host.offset_top = host.offset_bottom - target.y
				elif _free_bottom and not _free_top:
					host.offset_bottom = host.offset_top + target.y
				else:
					var grow_y: float = (target.y - host.size.y) * 0.5
					host.offset_top -= grow_y
					host.offset_bottom += grow_y

	size_changed.emit(target)


# --- Lock state ---------------------------------------------------------------

## The whole safety story in four lines.
##
## MOUSE_FILTER_IGNORE is what keeps this node out of the player's way while
## locked: a full-rect Control sitting over a HUD panel that STOPPED mouse input
## would eat every click in that rectangle - during combat, over the world.
## Hidden as well as ignoring, so _draw never runs and there is no edit chrome.
##
## Note this never touches the HOST's mouse_filter. PartyHud is deliberately
## MOUSE_FILTER_STOP (it owns its Leave button) and QuestTracker is deliberately
## MOUSE_FILTER_IGNORE (click-through by design); a resizer that reached in and
## rewrote those would break one of them whichever value it chose.
func _apply_lock(is_locked: bool) -> void:
	visible = not is_locked
	mouse_filter = Control.MOUSE_FILTER_IGNORE if is_locked else Control.MOUSE_FILTER_STOP
	if is_locked:
		_drag_edges = 0
		_hover_edges = 0
	queue_redraw()


# --- Input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if HudLayout.locked:
		return

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			var edges: int = _edges_at(button.position)
			if edges == 0:
				return # not on a handle - let the click fall through untouched
			_drag_edges = edges
			_drag_from = button.global_position
			_size_at_grab = host.size
			accept_event()
		elif _drag_edges != 0:
			_drag_edges = 0
			# ONE write per drag, here. set_value() rewrites the settings file on
			# every call, so persisting per motion event would put a file write
			# inside the drag loop.
			if not setting_key.is_empty():
				HudLayout.store_size(setting_key, host.size)
			queue_redraw()
			accept_event()
		return

	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if _drag_edges == 0:
			var hover: int = _edges_at(motion.position)
			if hover != _hover_edges:
				_hover_edges = hover
				queue_redraw()
			return
		var delta: Vector2 = motion.global_position - _drag_from
		var wanted: Vector2 = _size_at_grab
		# A LEFT/TOP edge grows the panel when dragged AWAY from the origin, so
		# its delta is inverted relative to a RIGHT/BOTTOM edge.
		if _drag_edges & EDGE_LEFT:
			wanted.x = _size_at_grab.x - delta.x
		elif _drag_edges & EDGE_RIGHT:
			wanted.x = _size_at_grab.x + delta.x
		if _drag_edges & EDGE_TOP:
			wanted.y = _size_at_grab.y - delta.y
		elif _drag_edges & EDGE_BOTTOM:
			wanted.y = _size_at_grab.y + delta.y
		_commit(wanted)
		accept_event()


## Which draggable edges [param at] is within GRAB of. Only edges that actually
## move are ever returned, so a pinned edge cannot be grabbed.
func _edges_at(at: Vector2) -> int:
	var edges: int = 0
	if _free_left and at.x <= GRAB:
		edges |= EDGE_LEFT
	if _free_right and at.x >= size.x - GRAB:
		edges |= EDGE_RIGHT
	if _free_top and at.y <= GRAB:
		edges |= EDGE_TOP
	if _free_bottom and at.y >= size.y - GRAB:
		edges |= EDGE_BOTTOM
	return edges


func _get_cursor_shape(at_position: Vector2 = Vector2.ZERO) -> CursorShape:
	if HudLayout.locked:
		return Control.CURSOR_ARROW
	var edges: int = _drag_edges if _drag_edges != 0 else _edges_at(at_position)
	var horizontal: bool = bool(edges & (EDGE_LEFT | EDGE_RIGHT))
	var vertical: bool = bool(edges & (EDGE_TOP | EDGE_BOTTOM))
	if horizontal and vertical:
		# BDIAG runs bottom-left to top-right; that is the corner where the
		# vertical and horizontal edges are on OPPOSITE ends of the rect.
		var bdiag: bool = bool(edges & EDGE_TOP) == bool(edges & EDGE_RIGHT)
		return Control.CURSOR_BDIAGSIZE if bdiag else Control.CURSOR_FDIAGSIZE
	if horizontal:
		return Control.CURSOR_HSIZE
	if vertical:
		return Control.CURSOR_VSIZE
	return Control.CURSOR_ARROW


# --- Edit chrome --------------------------------------------------------------

## Drawn only while unlocked (the node is hidden otherwise). A hairline box in the
## theme accent plus a grip on each draggable edge - enough to read as "this is
## editable" without competing with the panel's own content.
func _draw() -> void:
	if HudLayout.locked:
		return
	draw_rect(Rect2(Vector2.ZERO, size), EDIT_FILL, true)
	draw_rect(Rect2(Vector2.ZERO, size), EDIT_BORDER, false, 1.0)

	var lit: int = _drag_edges if _drag_edges != 0 else _hover_edges
	for edge: int in [EDGE_LEFT, EDGE_RIGHT, EDGE_TOP, EDGE_BOTTOM]:
		if not _is_free(edge):
			continue
		draw_rect(_grip_rect(edge), GRIP_HOT if (lit & edge) else GRIP, true)


func _is_free(edge: int) -> bool:
	match edge:
		EDGE_LEFT:
			return _free_left
		EDGE_RIGHT:
			return _free_right
		EDGE_TOP:
			return _free_top
		EDGE_BOTTOM:
			return _free_bottom
	return false


## A short bar centred on the draggable edge - the grab affordance.
func _grip_rect(edge: int) -> Rect2:
	var thickness: float = 3.0
	match edge:
		EDGE_LEFT:
			var l: float = minf(GRIP_LENGTH, size.y * 0.5)
			return Rect2(0.0, (size.y - l) * 0.5, thickness, l)
		EDGE_RIGHT:
			var r: float = minf(GRIP_LENGTH, size.y * 0.5)
			return Rect2(size.x - thickness, (size.y - r) * 0.5, thickness, r)
		EDGE_TOP:
			var t: float = minf(GRIP_LENGTH, size.x * 0.5)
			return Rect2((size.x - t) * 0.5, 0.0, t, thickness)
		EDGE_BOTTOM:
			var b: float = minf(GRIP_LENGTH, size.x * 0.5)
			return Rect2((size.x - b) * 0.5, size.y - thickness, b, thickness)
	return Rect2()
