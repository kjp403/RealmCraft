class_name LevelUpFx
## Shared level-up ceremony: fireworks above the character, the level-up jingle,
## and "Your [skill] level has achieved [#]". Call from any client path that
## detects a character / profession level gain.


const FIREWORKS_TEX: Texture2D = preload("res://assets/sprites/vfx/level_up/fireworks.png")
## Cropped fireworks-only atlas (character / ground stripped from the source GIF).
const FRAME_W: int = 195
const FRAME_H: int = 170
const COLS: int = 8
const FRAME_COUNT: int = 40
## Seconds per frame (~2.0s total at 40 frames).
const FRAME_DURATION: float = 0.05
## Center-screen banner dwell — long enough to read while gathering.
const BANNER_DURATION: float = 8.0
## Corner toast dwell (backup lane if the banner is missed).
const TOAST_DURATION: float = 6.0

static var _frames: SpriteFrames


## Celebrate a level-up on [param player]. [param skill_label] is the display
## name ("Mining", "Combat", "Crafting", ...). [param level] is the new level.
## VFX plays for any visible player; jingle + banner only fire for the local one.
static func celebrate(player: Player, skill_label: String, level: int) -> void:
	if not GameMode.is_client() or player == null or not is_instance_valid(player):
		return
	var frames: SpriteFrames = _fireworks_frames()
	if frames != null:
		# Cropped sheet is already fireworks-only; sit the burst just above the head.
		SpriteEffect.spawn(player, frames, {
			"scale": Vector2(0.75, 0.75),
			"offset": Vector2(0.0, -52.0),
			"z_index": 8,
			"speed_scale": 1.0,
		})
	if player is LocalPlayer:
		var label: String = skill_label.strip_edges()
		if label.is_empty():
			label = "skill"
		var msg: String = "Your %s level has achieved %d" % [label, level]
		# Cut any still-playing level-up jingle, then restart — rapid multi-levels
		# must not stack the audio. Keyed banner replaces itself so the text
		# refreshes to the newest skill/level instead of queuing.
		UISound.play_levelup()
		Announcer.announce(
			"Level up!",
			msg,
			{"sfx": "", "sound": false, "duration": BANNER_DURATION, "key": "level_up"},
		)
		Toaster.toast(msg, TOAST_DURATION)
		_echo_game_message(msg)
		if player.has_method("shake_camera"):
			(player as LocalPlayer).shake_camera(0.25)


## Convenience for profession / job slugs (&"mining" → "Mining").
static func celebrate_skill(player: Player, skill_slug: StringName, level: int) -> void:
	var label: String = JobRegistry.display_name(skill_slug)
	if label.is_empty():
		label = String(skill_slug).capitalize()
	celebrate(player, label, level)


static func _echo_game_message(text: String) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var found: Array[Node] = tree.root.find_children("*", "ChatMenu", true, false)
	if found.is_empty():
		return
	var chat: ChatMenu = found[0] as ChatMenu
	if chat != null:
		chat.echo_system(text)


static func _fireworks_frames() -> SpriteFrames:
	if _frames != null and _frames.get_frame_count(&"default") == FRAME_COUNT:
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
