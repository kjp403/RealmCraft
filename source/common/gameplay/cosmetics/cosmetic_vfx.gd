class_name CosmeticVfx
extends AnimatedSprite2D
## Client-only visual for a character's equipped cosmetic (aura / trail / halo / ...).
##
## Attached lazily by [method Character._set_cosmetic_id] — characters with nothing
## equipped never build one. The server drives it purely through the synced
## :cosmetic_id path, exactly like :skin_id, so remote players see each other's
## cosmetics with no extra RPC.
##
## TWO RENDER PATHS. A cosmetic listed in [CosmeticPresetLibrary] mounts a scripted
## [CosmeticPreset] — a layered tree of floor shaders, particle emitters and
## world-space marks — and this sprite draws nothing. Everything else keeps
## playing its pre-rendered 128x128 strip exactly as before. The two are chosen
## per slug, so a preset can be added or pulled for one cosmetic without touching
## the rest of the roster.
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
## The mounted scripted preset, or null when this cosmetic renders as a strip.
var _preset: CosmeticPreset

## Wardrobe use only. Set once by the Curator menu to mark this as a preview
## mount: screen-space layers are suppressed and the viewer-distance cull is
## bypassed, because a preview lives in UI space where a world distance test is
## meaningless — see [CosmeticPresetLibrary.build].
##
## Deliberately independent of [member preview_wearer]: a preview with no
## character to borrow is still a preview, and tying the two together would make
## the whole wardrobe cull itself whenever the local player was not ready yet.
var preview_mode: bool = false

## Wardrobe use only: the character a preset reads from when this node is NOT
## parented to one. Chrono Echo stamps the wearer's live sprite frame, so with
## nothing to read it previews as an empty box. Refreshed on every browse, since
## the local player may not exist yet when the menu is first built.
var preview_wearer: Character


func _init() -> void:
	# Below the body but above the ground: an aura should pool around the feet, not
	# paint over the character. Trails read correctly at the same depth.
	z_index = -1
	offset = FEET_OFFSET
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # crisp pixels, same as the body
	# The wearer's own flip must NOT mirror a radial aura, and directional trails are
	# authored facing right — Character drives flip_h explicitly for those only.
	centered = true


## Play an EVENT cosmetic once on [param host], then clean up after itself.
##
## Flourishes and departures are authored as one-shots and are not worn: nothing
## syncs them and no channel holds them, so the id arrives with the event that
## fires them (a level-up broadcast, a death broadcast) and this mounts a
## throwaway node to play it.
##
## NO REPLAY TIMER. [method apply] starts one for any non-looping cosmetic, which
## is right in the wardrobe - staff need to watch it more than once - and wrong
## here, where it would leave a flourish pulsing on a character forever.
##
## Freed on the animation, not on a fixed delay: strips differ in length, and a
## timer picked to fit the longest would leave the short ones lingering as an
## invisible node on every character that ever died.
static func play_once(host: Node2D, cosmetic_id: int) -> CosmeticVfx:
	if host == null or not is_instance_valid(host) or cosmetic_id <= 0:
		return null
	var vfx: CosmeticVfx = CosmeticVfx.new()
	host.add_child(vfx)
	vfx.apply(cosmetic_id)
	vfx._stop_replay()
	# A scripted preset runs on its own clock and has no animation to finish, so
	# it gets a bounded lifetime instead of one that may never arrive.
	if vfx.sprite_frames == null:
		vfx.get_tree().create_timer(PRESET_ONE_SHOT_S).timeout.connect(
			func() -> void:
				if is_instance_valid(vfx):
					vfx.queue_free()
		)
		return vfx
	vfx.animation_finished.connect(
		func() -> void:
			if is_instance_valid(vfx):
				vfx.queue_free()
	)
	return vfx


## How long a scripted preset gets when it is played as a one-shot. Presets have
## no animation_finished to wait on; this is the wardrobe replay cadence rounded
## up, so nothing is cut off mid-sweep.
const PRESET_ONE_SHOT_S: float = 2.0


## Swap to a new cosmetic. 0 hides the node (kept alive: equipping is cheap to toggle
## and staff flip through the roster fast).
func apply(cosmetic_id: int) -> void:
	_cosmetic_id = cosmetic_id
	_clear_preset()
	if cosmetic_id == 0:
		visible = false
		_stop_replay()
		return

	# Scripted preset first: it replaces the strip entirely rather than layering
	# over it, so a wearer never pays for both.
	var host: Character = preview_wearer if preview_wearer != null else get_parent() as Character
	_preset = CosmeticPresetLibrary.build(cosmetic_id, host, preview_mode)
	if _preset != null:
		# Nothing for this sprite to draw — but it must stay VISIBLE, because
		# hiding a parent hides the preset hanging off it too.
		sprite_frames = null
		stop()
		_stop_replay()
		visible = true
		add_child(_preset)
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


## Tear down a mounted preset. queue_free rather than free: a preset may be
## mid-frame in its own _process when a player swaps cosmetics from the vault.
##
## UNPARENTED FIRST, THEN QUEUED. queue_free() alone leaves the node a child until
## the end of the frame, so the replacement mounted a line later joins a parent
## that still holds the old one - both draw for that frame, and the new one is
## silently renamed (Godot will not allow two children called "Preset"), which
## means anything addressing it by name for the rest of the frame finds the dying
## one instead. Same fix, same reason, as [method TitleVfx._drop_layer].
func _clear_preset() -> void:
	if _preset == null:
		return
	remove_child(_preset)
	_preset.queue_free()
	_preset = null


## Trails are drawn streaming to the LEFT (wearer running right), so they mirror with
## the body. Radial effects must never mirror — flipping a ring just jitters it.
func set_facing(flipped: bool) -> void:
	# A preset trail reads its direction from real movement, so it neither needs
	# nor wants the mirror — flipping one would fight the path it just sampled.
	if _preset != null:
		_preset.set_facing(flipped)
		return
	if Cosmetics.slot_of(_cosmetic_id) == &"trail":
		flip_h = flipped
