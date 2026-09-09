@tool
extends Node
## Gate for the reward / daily-board audio wiring.
##
##   godot --headless --path . tools/verify_reward_audio.tscn
##
## SCENE mode, not `-s`: UISound reaches the Client autoload, which does not
## exist under `-s`, so the class would fail to COMPILE and this would report
## nothing while exiting 0 (see tools/run_verify.sh).
##
## WHY AUDIO NEEDS A GATE AT ALL
## Every cue here is a STRING PATH resolved at play time, and UISound.play is a
## deliberate no-op when audio is down. A typo'd path is therefore not an error —
## it is silence, forever, on a cue nobody notices is missing until a player asks
## why the 1-in-1000 drop made no sound. Nothing else in the pipeline catches it.

var _fails: PackedStringArray = PackedStringArray()


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_fails.append(label)


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_cue_paths()
	_bus_routing()
	_pitch_jitter()
	_rarity_coverage()
	print("")
	if _fails.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL (%d)" % _fails.size())
		for f: String in _fails:
			print("  - %s" % f)
	get_tree().quit(0 if _fails.is_empty() else 1)


## Every cue constant must resolve to a real, loadable AudioStream.
func _cue_paths() -> void:
	print("[cue paths]")
	var cues: Dictionary[String, String] = {
		"CLICK": UISound.CLICK,
		"BACK": UISound.BACK,
		"HOVER": UISound.HOVER,
		"REVEAL": UISound.REVEAL,
		"LEVELUP": UISound.LEVELUP,
		"WARDSTONE": UISound.WARDSTONE,
		"DISCOVERY": UISound.DISCOVERY,
		"QUEST_READY": UISound.QUEST_READY,
		"SEALED": UISound.SEALED,
		"COIN": UISound.COIN,
	}
	for name: String in cues:
		var path: String = cues[name]
		if not ResourceLoader.exists(path):
			_check(false, "%s: no file at %s" % [name, path])
			continue
		var stream: AudioStream = load(path) as AudioStream
		_check(stream != null, "%s loads as an AudioStream (%s)" % [name, path.get_file()])


## The Sound slider has to actually reach the UI cues.
##
## UI cues are mixed by AudioStreamPlaybackPolyphonic.play_stream, whose `bus`
## parameter DEFAULTS TO &"Master" — not to the bus of the player that owns the
## playback. Omitting it sent every UI cue straight into Master, past Ui/Sound
## and past the settings slider, so the slider appeared to do nothing until it
## hit zero (the mute guard) and the level-up jingle stayed at full volume at the
## lowest audible setting. Nothing errors when that happens.
##
## Ui also SENDS INTO Sound, so the slider gain belongs on Sound alone; applying
## it to both multiplied it in twice and left UI cues at a quarter volume at 50%.
func _bus_routing() -> void:
	print("[bus routing]")
	var ui_idx: int = AudioServer.get_bus_index(&"Ui")
	var sound_idx: int = AudioServer.get_bus_index(&"Sound")
	_check(ui_idx >= 0 and sound_idx >= 0, "Ui and Sound buses both exist")
	if ui_idx < 0 or sound_idx < 0:
		return
	_check(
		AudioServer.get_bus_send(ui_idx) == &"Sound",
		"Ui sends into Sound, so Sound alone carries the slider gain"
	)

	var manager: AudioManager = _audio_manager()
	if manager == null:
		print("  ..   no AudioManager in this context - gain split not exercised")
		return

	manager.set_sfx_volume(0.5)
	_check(
		is_equal_approx(snappedf(AudioServer.get_bus_volume_linear(sound_idx), 0.001), 0.5),
		"Sound carries the slider gain (%.3f at 50%%)"
			% AudioServer.get_bus_volume_linear(sound_idx)
	)
	_check(
		is_equal_approx(snappedf(AudioServer.get_bus_volume_linear(ui_idx), 0.001), 1.0)
			and not AudioServer.is_bus_mute(ui_idx),
		"Ui stays at unity and unmuted (%.3f) - gain is not applied twice"
			% AudioServer.get_bus_volume_linear(ui_idx)
	)

	manager.set_sfx_volume(0.0)
	_check(
		AudioServer.is_bus_mute(ui_idx) and AudioServer.is_bus_mute(sound_idx),
		"a zeroed slider mutes both buses"
	)
	manager.set_sfx_volume(1.0)


func _audio_manager() -> AudioManager:
	if not is_instance_valid(Client):
		return null
	return Client.audio_manager


## The jitter has to actually vary, and has to stay inside a band that reads as
## the same cue rather than as a different one.
func _pitch_jitter() -> void:
	print("[pitch jitter]")
	_check(
		UISound.PITCH_JITTER > 0.0 and UISound.PITCH_JITTER <= 0.12,
		"jitter is %.2f — audible but still the same sound" % UISound.PITCH_JITTER
	)
	# Sample the same range play_varied draws from and confirm it both varies and
	# stays in band. A jitter that silently collapsed to a constant would sound
	# exactly like the repetition it exists to break up.
	var lo: float = 1.0 - UISound.PITCH_JITTER
	var hi: float = 1.0 + UISound.PITCH_JITTER
	var seen: Dictionary[float, bool] = {}
	var out_of_band: int = 0
	for _i: int in 200:
		var pitch: float = randf_range(lo, hi)
		seen[snappedf(pitch, 0.001)] = true
		if pitch < lo or pitch > hi:
			out_of_band += 1
	_check(out_of_band == 0, "every sampled pitch stays within +/-%.0f%%" % (UISound.PITCH_JITTER * 100.0))
	_check(seen.size() > 20, "pitch actually varies (%d distinct values in 200)" % seen.size())


## Every rarity tier the SERVER can stamp must have a cue decided for it. A tier
## added to LootRarity without a cue here would drop silently.
func _rarity_coverage() -> void:
	print("[rarity coverage]")
	var uncued: PackedStringArray = PackedStringArray()
	for tier: LootRarity.Tier in LootRarity.NAMES:
		var tier_name: String = LootRarity.NAMES[tier]
		# common / uncommon -> reward_drop, rare -> reward_rare, ultra ->
		# reward_ultra. The window switches on is_celebrated, so the only way a
		# tier goes uncued is if it is neither celebrated nor ordinary, which
		# cannot happen — this asserts the enum stays that shape.
		var celebrated: bool = LootRarity.is_celebrated(tier)
		var round_trip: LootRarity.Tier = LootRarity.from_name(tier_name)
		if round_trip != tier:
			uncued.append("%s does not round-trip through from_name" % tier_name)
		print("  ..   %s -> %s" % [tier_name, "rare/ultra sting" if celebrated else "drop tick"])
	_check(uncued.is_empty(), "every rarity tier round-trips%s" % (
		"" if uncued.is_empty() else " - " + ", ".join(uncued)
	))
	_check(
		LootRarity.is_celebrated(LootRarity.Tier.ULTRA)
			and LootRarity.is_celebrated(LootRarity.Tier.RARE),
		"rare and ultra both take the celebrated path"
	)
	_check(
		not LootRarity.is_celebrated(LootRarity.Tier.COMMON)
			and not LootRarity.is_celebrated(LootRarity.Tier.UNCOMMON),
		"common and uncommon take the quiet drop tick"
	)
