class_name UISound
## Shared UI sound cues for the IN-GAME interface, routed through the AudioManager's polyphonic UI
## player — the same Sound bus + settings-bound volume the gateway uses. Static: call UISound.click()
## etc. from anywhere; the HUD auto-wires button taps/hovers to these. No-ops when audio isn't up (a
## headless / muted test client frees the AudioManager). Cue files live in assets/audio/sfx/ui/.
##
## The in-game UI fires a LOT (every button under the HUD), so each cue is trimmed a few dB under the
## bus volume here — softer than the gateway's deliberate, sparser clicks. Tune the *_DB consts.

const CLICK: String = "res://assets/audio/sfx/ui/ui_click.wav"
const BACK: String = "res://assets/audio/sfx/ui/ui_back.wav"
const HOVER: String = "res://assets/audio/sfx/ui/ui_hover.wav"
const REVEAL: String = "res://assets/audio/sfx/ui/ui_reveal.wav"

# Notification cues (docs/notifications.md audio pass, 2026-07-20 — Sonniss
# GDC bundle picks, owner-auditioned; artist-replaceable in place).
const LEVELUP: String = "res://assets/audio/sfx/ui/ui_levelup.ogg"
const WARDSTONE: String = "res://assets/audio/sfx/ui/ui_wardstone.ogg"
const DISCOVERY: String = "res://assets/audio/sfx/ui/ui_discovery.ogg"
const QUEST_READY: String = "res://assets/audio/sfx/ui/ui_quest_ready.ogg"
const SEALED: String = "res://assets/audio/sfx/ui/ui_sealed.ogg"
const PORTAL_CHARGE: String = "res://assets/audio/sfx/ui/ui_portal_charge.ogg"
const COIN: String = "res://assets/audio/sfx/ui/ui_coin.ogg"

## Per-cue trim (dB under bus volume). Hover fires on every mouse-over, so it's the quietest.
const CLICK_DB: float = -6.0
const BACK_DB: float = -6.0
const HOVER_DB: float = -11.0
const REVEAL_DB: float = -6.0

# --- Reward cues (chest opening + the daily board) --------------------------
# All mapped onto EXISTING streams. A drop cue and a level-up jingle must stay
# distinguishable, which is why LEVELUP is deliberately not reused here.

## ---------------------------------------------------------------------------
## THE ONE LINE TO CHANGE when a dedicated item-drop sample lands.
##
## There is no soft "item lands in a pile" sample in the project yet, so this
## points at the button click, trimmed hard (see DROP_DB) so it reads as a tick
## rather than as a press. That is a stand-in, not the intended sound.
##
## To swap it: drop the .wav into assets/audio/sfx/ui/ and repoint DROP below.
## Nothing else needs touching — reward_drop() and every caller go through it,
## and tools/verify_reward_audio.tscn asserts the new path loads. Retune DROP_DB
## to 0.0 at the same time: the -14 trim exists only because CLICK is a press
## cue being borrowed, and a purpose-made drop sample will not need it.
const DROP: String = CLICK
## ---------------------------------------------------------------------------

## Trim for the drop tick. Only this deep because DROP is currently the borrowed
## CLICK; a dedicated sample should sit near 0.
const DROP_DB: float = -14.0
## Rare tier (gems, high ore). Short chime — 9K, so it can repeat without smearing.
const RARE_DB: float = -4.0
## Ultra tier (Skilling Outfit pieces). The one cue in this set allowed to be
## dramatic; timed with the slot shimmer and the particle burst.
const ULTRA_DB: float = -1.0
## Difficulty locked in for the day. "Sealed" is doing real work here — the choice
## is irreversible, and the cue should say so.
const ACCEPT_DB: float = -4.0
## A daily task reaching its target.
const MILESTONE_DB: float = -3.0
const COIN_DB: float = -6.0

## Default +/- pitch spread for [method play_varied].
const PITCH_JITTER: float = 0.05


## Play [param path] with a randomised pitch.
##
## Repetition is what makes a batch action sound cheap: fifty identical samples
## in a row read as one stuttering sample, not fifty events. A few percent of
## pitch spread is enough to break that up while staying the same cue.
## Lives here rather than at the call sites so every batch in the game jitters by
## the same amount.
static func play_varied(
	path: String, volume_db: float = 0.0, jitter: float = PITCH_JITTER
) -> void:
	play(path, randf_range(1.0 - jitter, 1.0 + jitter), volume_db)


## One item arrived in a reward ledger. Quiet + jittered: this is the tactile
## "something dropped" tick, not an event.
static func reward_drop() -> void:
	play_varied(DROP, DROP_DB)


## A rare item (gem / high-tier ore). Jittered too — a lucky batch can produce
## several, and identical chimes stacking sounds like a glitch.
static func reward_rare() -> void:
	play_varied(DISCOVERY, RARE_DB, 0.03)


## An ultra-rare item — a Skilling Outfit piece. NOT jittered and NOT
## replaceable: this is the once-in-a-thousand moment, and it should sound
## exactly the same every time so it is recognisable.
static func reward_ultra() -> void:
	play(WARDSTONE, 1.0, ULTRA_DB)


## Gold paid into the pouch at the end of an open.
static func reward_gold() -> void:
	play(COIN, 1.0, COIN_DB)


## A daily difficulty was chosen and locked for the day.
static func task_accepted() -> void:
	play(SEALED, 1.0, ACCEPT_DB)


## A daily task hit its target.
static func task_complete() -> void:
	play(QUEST_READY, 1.0, MILESTONE_DB)


static func play(
	path: String,
	pitch: float = 1.0,
	volume_db: float = 0.0,
	replace_same: bool = false,
) -> void:
	if is_instance_valid(Client) and Client.audio_manager != null:
		Client.audio_manager.play_ui_sound(path, pitch, volume_db, replace_same)


## Level-up jingle: cuts itself short if another level-up fires mid-play.
static func play_levelup() -> void:
	play(LEVELUP, 1.0, 0.0, true)


static func click() -> void: play(CLICK, 1.0, CLICK_DB)
static func back() -> void: play(BACK, 1.0, BACK_DB)
static func hover() -> void: play(HOVER, 1.0, HOVER_DB)
static func reveal() -> void: play(REVEAL, 1.0, REVEAL_DB)
