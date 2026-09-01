extends CosmeticTrailPreset
## CHRONO ECHO (time distorted). Drops a ghost of the wearer's CURRENT sprite
## frame every 0.12 s while they move, and each one comes apart into pixel blocks
## over the next 0.4 s.
##
## MECHANICAL HOOK: this is the only cosmetic in the set that reads the wearer.
## Every other preset draws its own shapes and knows nothing about who is wearing
## it; this one reaches into Character.animated_sprite, takes whichever frame is
## on screen right now, and stamps it into the world. So the trail is different
## for every skin, shows the actual run cycle mid-stride, faces the way the wearer
## was facing, and needs no art of its own - it inherits all of it.
##
## That coupling is worth being explicit about, because it means this preset
## breaks in a way none of the others can: if the wearer has no sprite, no frames,
## or an animation that has gone missing, there is nothing to echo. Every one of
## those is checked in [method ChronoGhost.adopt] and simply produces no ghost, so
## the failure is an absent trail rather than an error per frame.
##
## The ghosts are cycled through a palette by spawn order, oldest ghost coldest,
## so a run leaves a legible sequence in time rather than a row of identical
## smears - which is what turns "a few transparent copies" into "an echo".

const GHOST_SCRIPT: GDScript = preload("res://source/common/gameplay/cosmetics/presets/chrono_ghost.gd")

## Seconds between after-images. The brief's 0.12 s: any longer and a sprint
## leaves visible gaps between ghosts, any shorter and they overlap into a blur.
const GHOST_INTERVAL_S: float = 0.12
## Seconds for one ghost to dissolve completely.
const GHOST_LIFE_S: float = 0.4

## Cycled by spawn order. Recent ghosts are warm and close to the wearer's own
## colours; older ones have drifted further into the cold end.
const ECHO_TINTS: Array[Color] = [
	Color(0.72, 0.90, 1.00),
	Color(0.55, 0.78, 1.00),
	Color(0.52, 0.60, 1.00),
	Color(0.62, 0.52, 1.00),
]

## Sprite to echo INSTEAD of the wearer's, when one is set.
##
## A deliberate seam for tooling. tools/render_cosmetic_presets.tscn mounts preset
## scripts directly, with no Character to parent them to, and every other preset
## in the set draws its own shapes so that costs them nothing. This one draws the
## wearer, so without a way to hand it a stand-in it would be the single effect in
## the library that can never be screenshotted or eyeballed before shipping.
var sprite_source: AnimatedSprite2D

var _since_ghost: float = 0.0
var _spawned: int = 0


func _tick(delta: float) -> void:
	super(delta)
	_since_ghost += delta
	if _since_ghost < GHOST_INTERVAL_S:
		return
	_since_ghost = 0.0
	# Standing still leaves no echo: an after-image of someone who has not moved
	# lands exactly on top of them and just makes the body look like it is
	# flickering. Off camera, spawning them is pure waste.
	if not is_moving() or not _viewer_in_range():
		return
	_spawn_ghost()


func _spawn_ghost() -> void:
	var source: AnimatedSprite2D = _wearer_sprite()
	if source == null:
		return
	var ghost: ChronoGhost = GHOST_SCRIPT.new()
	ghost.life = GHOST_LIFE_S
	ghost.tint = ECHO_TINTS[_spawned % ECHO_TINTS.size()]
	if not ghost.adopt(source):
		ghost.free() # never entered the tree, so a plain free is correct here
		return
	_spawned += 1
	# top_level BEFORE the transform is set, and the transform set AFTER the node
	# is in the tree - a top_level node's global transform is only meaningful once
	# it has a canvas to be global in.
	ghost.top_level = true
	ghost.scale = source.global_scale
	add_child(ghost)
	ghost.global_position = source.global_position


## The sprite to echo: an explicit [member sprite_source] if one was handed over,
## otherwise the wearer's body. Null when there is nothing to echo at all, which
## is the normal case in the vault preview before a local player exists.
func _wearer_sprite() -> AnimatedSprite2D:
	if is_instance_valid(sprite_source):
		return sprite_source
	if wearer == null or not is_instance_valid(wearer):
		return null
	return wearer.animated_sprite
