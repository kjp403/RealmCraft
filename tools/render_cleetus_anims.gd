extends SceneTree
## Render Cleetus's animation states, driven by the SAME clips, skins and rates the
## game uses, so "is the boss actually animated" can be answered by looking.
##
## Two sets are produced:
##   states/ — every clip on the base skin, including the two stretched casts.
##             rp_play_skin_anim(clip, fill) slows a short clip to cover a long
##             cast; before that existed those panels played for half a second and
##             then stood still for the rest of the spell.
##   phases/ — the base skin above the phase-2 frost skin, same clips, to check
##             the enrage swap reads as the same character rather than a repaint.
##
## Must run WINDOWED (no --headless) — headless has no rasteriser:
##   godot --path . -s tools/render_cleetus_anims.gd

const WARM := "res://source/common/gameplay/characters/sprite_frames/cleetus.tres"
const COLD := "res://source/common/gameplay/characters/sprite_frames/cleetus_frost.tres"
## character.tscn's playback rate for every mob skin.
const BASE_SPEED := 1.5
## Cinder Lash wind-up + sweep, and Killing Frost's channel: the two cast windows.
const SWEEP_S := 2.4
const CAST_S := 3.0
## HostileNpc.SPAWN_FREEZE_S — the hold the emerge clip is authored to fill.
const SPAWN_S := 0.5
const ZOOM := 3
const PANEL_W := 288
const ROW_H := 300
const CAPTURE_S := 3.1
const FPS := 12


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var warm: SpriteFrames = load(WARM) as SpriteFrames
	var cold: SpriteFrames = load(COLD) as SpriteFrames
	if warm == null or cold == null:
		printerr("FAIL: skins missing")
		quit(1)
		return

	# label, skin, clip, stretch-to seconds (0 = authored rate), replay on finish
	await _render_set("states", [[
		["idle", warm, &"idle", 0.0, false],
		["run", warm, &"run", 0.0, false],
		["auto-attack", warm, &"attack", 0.0, true],
		["emerge  (spawn)", warm, &"emerge", SPAWN_S, false],
		["death", warm, &"death", 0.0, false],
		["cast_staff  1.2s", warm, &"cast_staff", 1.2, false],
		["ice cast  3.0s", warm, &"special", CAST_S, false],
	]])
	await _render_set("phases", [[
		["phase 1  idle", warm, &"idle", 0.0, false],
		["phase 1  run", warm, &"run", 0.0, false],
		["phase 1  cast_staff", warm, &"cast_staff", 1.2, false],
	], [
		["phase 2  idle", cold, &"idle", 0.0, false],
		["phase 2  run", cold, &"run", 0.0, false],
		["phase 2  cast_staff", cold, &"cast_staff", 1.2, false],
	]])
	print("RENDER_OK")
	quit()


func _render_set(set_name: String, rows: Array) -> void:
	var dir: String = "user://cleetus_%s" % set_name
	DirAccess.make_dir_recursive_absolute(dir)
	var cols: int = 0
	for row: Array in rows:
		cols = maxi(cols, row.size())
	var w: int = PANEL_W * cols
	var h: int = ROW_H * rows.size()

	var sv := SubViewport.new()
	sv.size = Vector2i(w, h)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.transparent_bg = false
	sv.world_2d = World2D.new()
	root.add_child(sv)

	var stage := Node2D.new()
	sv.add_child(stage)
	var bg := ColorRect.new()
	bg.size = Vector2(w, h)
	bg.color = Color(0.11, 0.11, 0.15)
	bg.z_index = -10
	stage.add_child(bg)
	var cam := Camera2D.new()
	cam.position = Vector2(w, h) * 0.5
	cam.make_current()
	stage.add_child(cam)

	var pending: Array = []
	for r: int in rows.size():
		var row: Array = rows[r]
		var ground: float = float(r) * ROW_H + ROW_H - 40.0
		for i: int in row.size():
			var spec: Array = row[i]
			var cx: float = PANEL_W * (float(i) + 0.5)
			_label(stage, Vector2(cx - 110.0, float(r) * ROW_H + 24.0), String(spec[0]))
			var skin: SpriteFrames = spec[1]
			var clip: StringName = spec[2]
			var fill: float = spec[3]

			var spr := AnimatedSprite2D.new()
			spr.sprite_frames = skin
			spr.centered = true
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2(ZOOM, ZOOM)
			# Frames are baselined with the feet on the LAST row, so offsetting by
			# half a frame puts that row on the shared ground line.
			spr.position = Vector2(cx, ground - 32.0 * ZOOM)
			if fill > 0.0:
				# Mirror rp_play_skin_anim's stretch exactly.
				var natural: float = float(skin.get_frame_count(clip)) \
					/ (skin.get_animation_speed(clip) * BASE_SPEED)
				spr.speed_scale = BASE_SPEED * (natural / fill)
			else:
				spr.speed_scale = BASE_SPEED
			if bool(spec[4]):
				spr.animation_finished.connect(spr.play.bind(clip))
			stage.add_child(spr)
			pending.append([spr, clip])

			var line := ColorRect.new()
			line.size = Vector2(PANEL_W - 40.0, 2.0)
			line.position = Vector2(cx - (PANEL_W - 40.0) * 0.5, ground)
			line.color = Color(0.26, 0.27, 0.34)
			stage.add_child(line)

	# Settle BEFORE starting playback. Building the stage uploads every texture,
	# which can burn a few hundred ms — long enough that a short clip started at
	# construction time is already finished by the first capture, making a working
	# animation look like a frozen one.
	await process_frame
	await process_frame
	for entry: Array in pending:
		(entry[0] as AnimatedSprite2D).play(entry[1] as StringName)

	# Sample against the wall clock: saving a PNG costs tens of ms, so a fixed
	# sleep per frame would drift and the tail of the strip would miss the end of
	# the longest clip.
	var t0: int = Time.get_ticks_msec()
	var step: float = 1.0 / float(FPS)
	var taken: int = 0
	while true:
		await process_frame
		var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
		if elapsed < float(taken) * step:
			continue
		if elapsed > CAPTURE_S:
			break
		sv.get_texture().get_image().save_png("%s/frame_%02d.png" % [dir, taken])
		taken += 1
	print("  %s: %d frames -> %s" % [set_name, taken, ProjectSettings.globalize_path(dir)])
	sv.queue_free()


func _label(parent: Node, at: Vector2, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_color_override(&"font_color", Color(0.85, 0.86, 0.92))
	parent.add_child(l)
