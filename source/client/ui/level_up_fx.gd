class_name LevelUpFx
## Shared level-up ceremony: fireworks above the character, the level-up jingle,
## and "Your [skill] level has achieved [#]". Call from any client path that
## detects a character / profession level gain.


const FIREWORKS_TEX: Texture2D = preload("res://assets/sprites/vfx/level_up/fireworks.png")
const FRAME_W: int = 240
const FRAME_H: int = 331
const COLS: int = 6
const FRAME_COUNT: int = 36
## Seconds per frame (~1.8s total at 36 frames).
const FRAME_DURATION: float = 0.05

static var _frames: SpriteFrames


## Celebrate a level-up on [param player]. [param skill_label] is the display
## name ("Mining", "Combat", "Crafting", ...). [param level] is the new level.
## VFX plays for any visible player; jingle + banner only fire for the local one.
static func celebrate(player: Player, skill_label: String, level: int) -> void:
	if not GameMode.is_client() or player == null or not is_instance_valid(player):
		return
	var frames: SpriteFrames = _fireworks_frames()
	if frames != null:
		SpriteEffect.spawn(player, frames, {
			"scale": Vector2(0.55, 0.55),
			"offset": Vector2(0.0, -56.0),
			"z_index": 8,
			"speed_scale": 1.0,
		})
	if player is LocalPlayer:
		var label: String = skill_label.strip_edges()
		if label.is_empty():
			label = "skill"
		var msg: String = "Your %s level has achieved %d" % [label, level]
		Announcer.announce(msg, "", {"sfx": UISound.LEVELUP, "duration": 3.2})
		if player.has_method("shake_camera"):
			(player as LocalPlayer).shake_camera(0.25)


## Convenience for profession / job slugs (&"mining" → "Mining").
static func celebrate_skill(player: Player, skill_slug: StringName, level: int) -> void:
	var label: String = JobRegistry.display_name(skill_slug)
	if label.is_empty():
		label = String(skill_slug).capitalize()
	celebrate(player, label, level)


static func _fireworks_frames() -> SpriteFrames:
	if _frames != null:
		return _frames
	if FIREWORKS_TEX == null:
		return null
	var frames: SpriteFrames = SpriteFrames.new()
	frames.add_animation(&"default")
	frames.set_animation_loop(&"default", false)
	for i: int in FRAME_COUNT:
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = FIREWORKS_TEX
		atlas.region = Rect2((i % COLS) * FRAME_W, int(i / COLS) * FRAME_H, FRAME_W, FRAME_H)
		frames.add_frame(&"default", atlas, FRAME_DURATION)
	_frames = frames
	return _frames
