class_name AudioManager
extends Node
## Handles music, UI sounds and spatial sound effects playback.

@export var music_player: AudioStreamPlayer
@export var ui_player: AudioStreamPlayer
@export var sfx_player: SfxPool

@export_range(0.0, 1.0, 0.001) var music_volume: float = 1.0:
	set(value): set_music_volume(value)

@export_range(0.0, 1.0, 0.001) var sound_volume: float = 1.0:
	set(value): set_sfx_volume(value)

# Music fades IN from this floor, not true silence (-80 dB). Anything below ~-40 dB
# is inaudible, so fading from -80 wastes the first chunk of a long fade crawling
# through silence ("the music starts 10 s late"). -30 dB is a faint-but-audible
# start that rises smoothly across the whole duration.
const MUSIC_FADE_IN_FLOOR_DB: float = -30.0

## Crossfade used when a playlist rotates to its next track.
const PLAYLIST_FADE_S: float = 3.0
## How long before a track's natural end the rotation starts crossing over. The old
## track loops (every music .ogg imports with loop=true) rather than falling silent,
## so it just fades out over the top of its own loop point.
const PLAYLIST_FADE_LEAD_S: float = 3.0
## Floor on the rotation timer, so a stub-length or unreadable stream can't spin the
## playlist at frame rate.
const PLAYLIST_MIN_HOLD_S: float = 5.0

var _tweens: Dictionary[AudioStreamPlayer, Tween]
var _cached_sounds: Dictionary[String, AudioStream]
var _pending_music: PendingMusic
## Area playlist: the tracks themselves, plus a shuffled play order over their indices
## and how far into that order we are. Empty when a single track owns the music player.
var _playlist: Array[AudioStream]
var _playlist_order: PackedInt32Array
var _playlist_pos: int = -1
## Bumped on every track change and on _clear_playlist; a pending rotation timer that
## no longer matches is a leftover from music that has already been replaced.
var _playlist_gen: int = 0
## Polyphonic stream id of the last UI cue that requested replace-on-replay
## (level-up jingles cut themselves short when another fires mid-play).
var _replaceable_ui_stream_id: int = -1
var _replaceable_ui_path: String = ""


func _ready() -> void:
	if not GameMode.is_client():
		queue_free()
		return
	assert(is_instance_valid(music_player), "No valid music player.")
	assert(is_instance_valid(ui_player), "No valid ui player.")
	assert(is_instance_valid(sfx_player), "No valid sfx player.")

	# Multi-instance testing: silence the extra editor clients so sounds don't stack
	# (set per-instance args in Debug ▸ Customize Run Instances). --mute = everything;
	# --no-sfx = UI + spatial SFX only (music kept). Matches the --id arg convention.
	var args: Dictionary = CmdlineUtils.get_parsed_args()
	if args.has("mute"):
		AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), true)
	elif args.has("no-sfx"):
		AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Sound"), true)

	ui_player.play()
	ClientState.settings.setting_changed.connect(_on_setting_changed)
	_apply_default_settings()


func _on_setting_changed(section: StringName, property: StringName, value: Variant) -> void:
	match property:
		&"music_volume": music_volume = clampf(value, 0.0, 1.0)
		&"sound_volume": sound_volume = clampf(value, 0.0, 1.0)

#region Music

## Sets music volume.
func set_music_volume(volume_linear: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(&"Music")
	AudioServer.set_bus_volume_linear(bus_index, clampf(volume_linear, 0.0, 1.0))


## Load and play music from the given path.
## If the resource was previously loaded, it will be retrieved from cache. [br]
## [volume] - Override the bus volume. leave at 0.0 to use the audio bus volume.[br]
## [at_position] - Play music at the given time.[br]
## [fade_duration] - Fade in/out duration.
func play_music(music_path: String, volume: float = 0.0, at_position: float = 0.0, fade_duration: float = 1.0) -> bool:
	return play_music_stream(_get_sound(music_path), volume, at_position, fade_duration)


## Play music using the given [AudioStream].[br]
## [volume] - Override the bus volume. leave at 0.0 to use the audio bus volume.[br]
## [at_position] - Play music at the given time.[br]
## [fade_duration] - Fade in/out duration.
func play_music_stream(music: AudioStream, volume: float = 0.0, at_position: float = 0.0, fade_duration: float = 1.0) -> bool:
	# A single explicit track owns the music player outright — it ends any rotation,
	# so a boss track can't be shoved aside by the area playlist's next tick.
	_clear_playlist()
	return _queue_music(music, volume, at_position, fade_duration)


## Path-based [method play_music_playlist]. Streams come from the same cache as
## [method play_music]; paths that don't resolve are skipped.
func play_music_paths(music_paths: Array[String], fade_duration: float = 1.0) -> bool:
	var streams: Array[AudioStream] = []
	for path: String in music_paths:
		streams.append(_get_sound(path))
	return play_music_playlist(streams, fade_duration)


## Rotate through [param tracks] in shuffled order, crossfading into the next one just
## before the current track would loop. This is what keeps an area from wearing a single
## loop into the ground; a one-track list is just ordinary looping playback.
## Re-requesting the playlist that is already running is a no-op, so walking between two
## maps that share a rotation doesn't restart it.
func play_music_playlist(tracks: Array[AudioStream], fade_duration: float = 1.0) -> bool:
	var unique: Array[AudioStream] = []
	for track: AudioStream in tracks:
		if track != null and not unique.has(track):
			unique.append(track)

	if unique.is_empty(): return false
	if unique.size() == 1:
		return play_music_stream(unique[0], 0.0, 0.0, fade_duration)
	if music_player.playing and _playlist == unique: return true

	_clear_playlist()
	_playlist = unique
	_shuffle_playlist(-1)
	return _play_next_in_playlist(fade_duration)


## Stop the current playing music.
func stop_music(fade_out_duration: float = 1.0) -> void:
	if music_player.playing:
		fade_volume(music_player, -80, clampf(fade_out_duration, 0.0, 10.0))


func _queue_music(music: AudioStream, volume: float, at_position: float, fade_duration: float) -> bool:
	if not music: return false
	if music_player.playing and music_player.stream == music: return true

	_pending_music = PendingMusic.new()
	_pending_music.stream = music
	_pending_music.volume = volume
	_pending_music.at_position = at_position
	_pending_music.fade_duration = fade_duration

	if music_player.playing:
		stop_music(fade_duration)
	else:
		_start_music()

	return true


## Start the next track in the shuffled order and arm the timer for the one after it.
func _play_next_in_playlist(fade_duration: float) -> bool:
	if _playlist.size() < 2: return false

	_playlist_pos += 1
	if _playlist_pos >= _playlist_order.size():
		# Reshuffle for the next pass, keeping the track we just finished off the front
		# so a wrap-around never plays the same thing twice in a row.
		_shuffle_playlist(_playlist_order[_playlist_order.size() - 1])
		_playlist_pos = 0

	var track: AudioStream = _playlist[_playlist_order[_playlist_pos]]
	_playlist_gen += 1
	if not _queue_music(track, 0.0, 0.0, fade_duration):
		return false

	# The fade-out of this track has to start before its end, so the rotation is armed
	# for (length - lead) rather than for the full length.
	var hold: float = maxf(track.get_length() - PLAYLIST_FADE_LEAD_S, PLAYLIST_MIN_HOLD_S)
	_rotate_playlist_after(hold, _playlist_gen)
	return true


func _rotate_playlist_after(delay: float, gen: int) -> void:
	# process_always so the rotation keeps ticking while the tree is paused (the
	# disconnect overlay pauses everything, and music shouldn't stall behind it).
	await get_tree().create_timer(delay, true).timeout
	if gen != _playlist_gen: return
	_play_next_in_playlist(PLAYLIST_FADE_S)


## Rebuild the shuffled order over the playlist indices. [param avoid_first] is the index
## that must not land in slot 0 (pass -1 when nothing was playing).
func _shuffle_playlist(avoid_first: int) -> void:
	_playlist_order.resize(_playlist.size())
	for i: int in _playlist.size():
		_playlist_order[i] = i

	# PackedInt32Array has no shuffle(); Fisher-Yates over it directly.
	for i: int in range(_playlist_order.size() - 1, 0, -1):
		var j: int = randi_range(0, i)
		var tmp: int = _playlist_order[i]
		_playlist_order[i] = _playlist_order[j]
		_playlist_order[j] = tmp

	if _playlist_order.size() > 1 and _playlist_order[0] == avoid_first:
		_playlist_order[0] = _playlist_order[1]
		_playlist_order[1] = avoid_first

	_playlist_pos = -1


func _clear_playlist() -> void:
	_playlist_gen += 1 # orphans any armed rotation timer
	_playlist.clear()
	_playlist_order.clear()
	_playlist_pos = -1

#endregion

#region UI Sound

## Load and play sound from the given path.
## If the resource was previously loaded, it will be retrieved from cache.
## [param replace_same]: when true, cuts any still-playing cue from the same
## path before starting this one (level-up jingles).
func play_ui_sound(
	sound_path: String,
	pitch: float = 1.0,
	volume_db: float = 0.0,
	replace_same: bool = false,
) -> bool:
	return play_ui_sound_stream(_get_sound(sound_path), pitch, volume_db, sound_path if replace_same else "")


## Play sound using the given [AudioStream]. [volume_db] trims THIS cue under the bus volume
## (e.g. -6 for a softer click) without touching the player/settings volume.
## [param replace_path]: non-empty = stop the previous replaceable cue for this path first.
func play_ui_sound_stream(
	sound: AudioStream,
	pitch: float = 1.0,
	volume_db: float = 0.0,
	replace_path: String = "",
) -> bool:
	if not sound: return false
	var playback: AudioStreamPlaybackPolyphonic = ui_player.get_stream_playback()
	if not replace_path.is_empty() and replace_path == _replaceable_ui_path and _replaceable_ui_stream_id >= 0:
		playback.stop_stream(_replaceable_ui_stream_id)
		_replaceable_ui_stream_id = -1
	var stream_id: int = playback.play_stream(sound, 0, volume_db, pitch)
	if not replace_path.is_empty():
		_replaceable_ui_path = replace_path
		_replaceable_ui_stream_id = stream_id
	return true

#endregion

#region Sound Effect

## Sets all sound effects volume. UI and spatial sound effects.
func set_sfx_volume(volume_linear: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(&"Sound")
	AudioServer.set_bus_volume_linear(bus_index, clampf(volume_linear, 0.0, 1.0))


## Load and play a spatial sound from the given path.
## If the resource was previously loaded, it will be retrieved from cache. [br]
## [position] - The 2D world position that the sound will play from.[br]
## [override_max_distance] - Overrides the default max distance. leave at 0.0 to use default distance.
func play_sfx(sound_path: String, position: Vector2, override_max_distance: int = 0, pitch: float = 1.0) -> bool:
	var sound: AudioStream = _get_sound(sound_path)
	return sfx_player.play_stream(sound, position, override_max_distance, pitch)


## Play a spatial sound using the given [AudioStream].[br]
## [position] - The 2D world position that the sound will play from.[br]
## [override_max_distance] - Overrides the default max distance. leave at 0.0 to use default distance.
func play_sfx_stream(sound: AudioStream, position: Vector2, override_max_distance: int = 0, pitch: float = 1.0) -> bool:
	return sfx_player.play_stream(sound, position, override_max_distance, pitch)

#endregion

#region Helpers

## Fade the given [AudioStreamPlayer] volume.
func fade_volume(player: AudioStreamPlayer, to_volume: float, duration: float = 1.0) -> void:
	_remove_tween(player)

	var tween = create_tween()
	var is_fading_out: bool = player.volume_db > to_volume
	tween.tween_property(
		player, 
		"volume_db",
		to_volume,
		duration
	# Fade IN linearly so a long fade rises evenly the whole way; fade OUT keeps the
	# gentle sine curve.
	).set_trans(Tween.TRANS_SINE if is_fading_out else Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN if is_fading_out else Tween.EASE_OUT)

	tween.finished.connect(_on_fade_finished.bind(player, is_fading_out), CONNECT_ONE_SHOT)
	_tweens[player] = tween


func _start_music() -> void:
	if not _pending_music: return

	music_player.stream = _pending_music.stream
	music_player.volume_db = MUSIC_FADE_IN_FLOOR_DB
	music_player.play(_pending_music.at_position)
	fade_volume(music_player, _pending_music.volume, _pending_music.fade_duration)
	_pending_music = null


func _remove_tween(player: AudioStreamPlayer) -> void:
	if not _tweens.has(player): return
	var tween: Tween = _tweens.get(player)
	tween.kill()
	_tweens.erase(player)


func _on_fade_finished(player: AudioStreamPlayer, was_fading_out: bool) -> void:
	_remove_tween(player)
	if was_fading_out:
		player.stop()

	if _pending_music:
		_start_music()


func _get_sound(sound_path: String) -> AudioStream:
	if _cached_sounds.has(sound_path):
		return _cached_sounds[sound_path]
	
	if not ResourceLoader.exists(sound_path): return null

	var sound: Resource = ResourceLoader.load(sound_path, "AudioStream")
	if not sound is AudioStream: return null

	_cached_sounds[sound_path] = sound
	return sound


func _apply_default_settings() -> void:
	var settings: Dictionary = ClientState.settings.data
	for property in settings[&"general"]:
		var value: Variant = settings[&"general"][property]
		_on_setting_changed(&"general", property, value)

#endregion

class PendingMusic:
	var stream: AudioStream
	var volume: float
	var at_position: float
	var fade_duration: float
