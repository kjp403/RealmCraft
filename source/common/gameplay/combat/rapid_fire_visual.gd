class_name RapidFireVisual
extends Node2D
## Rapid Fire's channel VFX: fires a real-looking arrow sprite along the caster's
## LIVE aim every tick, exactly like [LashVisual] tracks the cursor for Lightning
## Lash's beam — so the ability finally reads as "you're shooting arrows where you
## point" instead of the leftover default heal-aura ring. Client-side, purely
## cosmetic (the server's own hit-scan in RapidFireAbility.channel_tick is the real
## damage); a child of the caster named "ChannelVisual" so channel.end frees it.

const ARROW_TEXTURE: Texture2D = preload("res://assets/sprites/items/weapons/wood/wood.png")
const ARROW_REGION: Rect2 = Rect2(32, 0, 16, 16)
const FLIGHT_SPEED: float = 700.0
const FLIGHT_RANGE_PX: float = 260.0

var tick_interval_s: float = 0.35
var _elapsed_s: float = 0.0


func _process(delta: float) -> void:
	var c: Character = get_parent() as Character
	if c == null or c.hand_pivot == null:
		return
	_elapsed_s += delta
	if _elapsed_s < tick_interval_s:
		return
	_elapsed_s = 0.0
	# Local player's hand_pivot is updated every frame directly (no sync lag);
	# remotes read it off the pivot sync — same tradeoff LashVisual makes.
	var aim: Vector2 = Vector2.from_angle(c.hand_pivot.rotation)
	if c.flipped:
		aim.x = -aim.x
	_spawn_arrow(c, aim)


func _spawn_arrow(caster: Character, aim: Vector2) -> void:
	var shot: Node2D = Node2D.new()
	shot.top_level = true
	shot.global_position = caster.global_position + aim * 12.0
	shot.rotation = aim.angle()
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = ARROW_TEXTURE
	sprite.region_enabled = true
	sprite.region_rect = ARROW_REGION
	sprite.z_index = 1
	shot.add_child(sprite)
	caster.add_child(shot)
	var tween: Tween = shot.create_tween()
	tween.tween_property(
		shot, "position", aim * FLIGHT_RANGE_PX, FLIGHT_RANGE_PX / FLIGHT_SPEED
	).as_relative()
	tween.tween_callback(shot.queue_free)
