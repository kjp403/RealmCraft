class_name CosmeticVfx
extends AnimatedSprite2D
## Client-only visual for a character's equipped cosmetic (aura / trail / halo / ...).
##
## Attached lazily by [method Character._set_cosmetic_id] — characters with nothing
## equipped never build one. The server drives it purely through the synced
## :cosmetic_id path, exactly like :skin_id, so remote players see each other's
## cosmetics with no extra RPC.
##
## Anchoring: the strips are authored in a 128x128 cell with the wearer's FEET at
## cell (64, 84) — 20 px below the cell centre. Character origin already sits at the
## feet (the body sprite carries offset (0,-30) on 64 px art), so offsetting this
## sprite up by 20 px lands the effect's feet on the character's feet.
const FEET_OFFSET: Vector2 = Vector2(0, -20)

## Event effects (flourish / departure) are authored as one-shots. While equipped we
## replay them on this cadence so staff can actually watch them in the vault.
const REPLAY_DELAY_S: float = 1.6

var _cosmetic_id: int = 0
var _replay_timer: Timer


func _init() -> void:
	# Below the body but above the ground: an aura should pool around the feet, not
	# paint over the character. Trails read correctly at the same depth.
	z_index = -1
	offset = FEET_OFFSET
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # crisp pixels, same as the body
	# The wearer's own flip must NOT mirror a radial aura, and directional trails are
	# authored facing right — Character drives flip_h explicitly for those only.
	centered = true


## Swap to a new cosmetic. 0 hides the node (kept alive: equipping is cheap to toggle
## and staff flip through the roster fast).
func apply(cosmetic_id: int) -> void:
	_cosmetic_id = cosmetic_id
	if cosmetic_id == 0:
		visible = false
		_stop_replay()
		return

	var new_frames: SpriteFrames = Cosmetics.frames(cosmetic_id)
	if new_frames == null:
		visible = false
		return
	sprite_frames = new_frames
	visible = true
	_play()

	if Cosmetics.is_looping(cosmetic_id):
		_stop_replay()
	else:
		_start_replay()


func _play() -> void:
	if sprite_frames != null and sprite_frames.has_animation(&"loop"):
		play(&"loop")


func _start_replay() -> void:
	if _replay_timer == null:
		_replay_timer = Timer.new()
		_replay_timer.one_shot = false
		_replay_timer.wait_time = REPLAY_DELAY_S
		_replay_timer.timeout.connect(_play)
		add_child(_replay_timer)
	_replay_timer.start()


func _stop_replay() -> void:
	if _replay_timer != null:
		_replay_timer.stop()


## Trails are drawn streaming to the LEFT (wearer running right), so they mirror with
## the body. Radial effects must never mirror — flipping a ring just jitters it.
func set_facing(flipped: bool) -> void:
	if Cosmetics.slot_of(_cosmetic_id) == &"trail":
		flip_h = flipped
