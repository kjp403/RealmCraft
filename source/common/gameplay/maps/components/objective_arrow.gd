@tool
extends Node2D
## A big bobbing arrow pointing DOWN at whatever it is parented to — "this one,
## talk to this one". Used in the Charter Intake, where players were walking past
## the Charter Clerk and out of the room before anyone had explained anything.
##
## Deliberately louder than InteractableMarker: that marker says "this is
## talkable", this says "this is the one you are looking for". It removes itself
## once the local player opens the parent NPC's dialogue, so it never nags after
## the job is done.
##
## Client-only visual. Drawn rather than textured because the emote sheet has no
## arrow, and one more PNG for one room is not worth the import.

## Fallback when the parent is not an NPC (a prop, a door). Empty = never
## auto-hide; the arrow stays until the node is freed.
@export var npc_key_override: StringName = &""
@export var arrow_color: Color = Color(1.0, 0.84, 0.35)
@export var outline_color: Color = Color(0.15, 0.11, 0.03, 0.85)
## Full bob cycle in seconds (down + up).
@export var bob_period: float = 1.2
@export var bob_amplitude: float = 3.0
## Gap in pixels between the parent's head and the arrow's tip. Only used when
## the parent is a Character we can measure — a hand-placed arrow keeps the
## position authored in the scene.
@export var head_clearance: float = 4.0

## Group every arrow joins, so an NPC can tell it is already being pointed at.
const GROUP: StringName = &"objective_arrow"

const WIDTH: float = 11.0
const HEAD_HEIGHT: float = 8.0
const SHAFT_WIDTH: float = 4.0
const SHAFT_HEIGHT: float = 7.0


func _ready() -> void:
	# The NPC checks this group and skips its generic "talkable" dots, so the two
	# glyphs never stack over one head.
	add_to_group(GROUP)
	z_index = 210 # above the InteractableMarker glyph (200)
	if Engine.is_editor_hint():
		return
	# Servers carry no visuals; a marker there is pure overhead. GameMode, not
	# multiplayer.is_server(): a client whose peer is not up yet reads as a server
	# and would silently skip its own marker.
	if GameMode.is_any_server():
		hide()
		return
	ClientState.npc_talked.connect(_on_npc_talked)
	# Deferred, and in this order: children are ready BEFORE their parent, so the
	# NPC's @onready animated_sprite is still null right now — and the bob tween
	# has to capture its rest position AFTER the placement, or it animates back
	# to the authored offset every frame.
	_setup_placement.call_deferred()


func _setup_placement() -> void:
	_sit_above_head()
	_start_bob()


## The point of the arrow is to survive exactly until it is obeyed.
func _on_npc_talked(giver_key: StringName) -> void:
	var mine: StringName = _target_key()
	if mine.is_empty() or giver_key != mine:
		return
	queue_free()


func _target_key() -> StringName:
	if not npc_key_override.is_empty():
		return npc_key_override
	var parent: Node = get_parent()
	if parent != null and parent.has_method(&"giver_key"):
		return parent.call(&"giver_key")
	return &""


## Park the tip just over the parent's head.
##
## Measured from the frame's OPAQUE pixels, not its size: these character frames
## carry a lot of empty padding, so sizing off the texture (which is what
## InteractableMarker does) floats the arrow a body-length above the head.
func _sit_above_head() -> void:
	var parent: Node = get_parent()
	if parent == null or not ("animated_sprite" in parent):
		return
	var sprite: AnimatedSprite2D = parent.get(&"animated_sprite") as AnimatedSprite2D
	if sprite == null:
		return
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null or not frames.has_animation(sprite.animation):
		return
	var tex: Texture2D = frames.get_frame_texture(sprite.animation, 0)
	if tex == null:
		return
	# Frame top in the sprite's own space, honouring centering AND the sprite's
	# offset (character frames are drawn low in a 64x64 cell and shifted up).
	var top: float = sprite.offset.y
	if sprite.centered:
		top -= tex.get_size().y * 0.5
	var image: Image = tex.get_image()
	if image != null:
		var used: Rect2i = image.get_used_rect()
		if used.size.y > 0:
			top += float(used.position.y) # skip the frame's empty padding
	position = Vector2(0.0, sprite.position.y + top - head_clearance)


func _draw() -> void:
	var half: float = WIDTH * 0.5
	var half_shaft: float = SHAFT_WIDTH * 0.5
	# Origin sits at the arrow's TIP, so placing the node is "point at this spot".
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(-half, -HEAD_HEIGHT),
		Vector2(-half_shaft, -HEAD_HEIGHT),
		Vector2(-half_shaft, -HEAD_HEIGHT - SHAFT_HEIGHT),
		Vector2(half_shaft, -HEAD_HEIGHT - SHAFT_HEIGHT),
		Vector2(half_shaft, -HEAD_HEIGHT),
		Vector2(half, -HEAD_HEIGHT),
	])
	draw_colored_polygon(points, arrow_color)
	# Closed outline so the shape reads against a light floor as well as a dark one.
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, outline_color, 1.5)


func _start_bob() -> void:
	if bob_amplitude <= 0.0:
		return
	var base_y: float = position.y
	var tween: Tween = create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, ^"position:y", base_y - bob_amplitude, bob_period * 0.5)
	tween.tween_property(self, ^"position:y", base_y, bob_period * 0.5)
