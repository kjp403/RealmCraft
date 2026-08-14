extends SceneTree
## Candidate VFX treatments for the Arcanist's Magic Bolt (wand_bolt -> bolt.tscn), rendered
## side by side against the CURRENT look so a new bolt can be judged before it ships.
##
## Every candidate is procedural (_draw + web-safe CPUParticles2D) in the SpawnEffect /
## ChannelVisual idiom — no new art, no GPU particles (the project ships GL Compatibility
## and a web client). Tint stays BoltShootAbility's arcane violet so the comparison is
## about SHAPE and MOTION, not colour.
##
## Two views per candidate, because a 16px bolt is judged at two distances:
##   flight_<n>.png          — real 330 px/s across a lane, 1x: the in-game read
##   detail_<style>_<n>.png  — the same bolt with the camera riding it at 3.5x: the art
##
## Must run WINDOWED (no --headless) — headless has no rasteriser:
##   godot --path . -s tools/render_arcane_bolt_previews.gd
##   godot --path . -s tools/render_arcane_bolt_previews.gd -- --outdir=C:/tmp/bolts

const CIRCLE_TEX := "res://assets/sprites/particles/white_circle.png"

## The shared arcane violet — BoltShootAbility.bolt_modulate's default.
const TINT := Color(0.75, 0.55, 1.0)

const LANE_W := 700
const LANE_H := 68
const DETAIL := Vector2i(224, 152)
const DETAIL_ZOOM := 3.5

const BG := Color(0.105, 0.115, 0.155)

const SPEED := 330.0          # wand_bolt.tres speed — the real thing
const X0 := 53.0
const X1 := 647.0
const GAP := 0.4              # beat between shots, so the loop reads as repeat fire
const FPS := 20
const PERIOD := (X1 - X0) / SPEED + GAP   # 1.8 + 0.4 = 2.2s exactly
const FRAMES := int(PERIOD * FPS)         # 44

## Style ids, in lane order. CURRENT is the shipping bolt.
enum { CURRENT, MOTE, RUNE, LANCE, STAR }
const STYLES: Array[int] = [CURRENT, MOTE, RUNE, LANCE, STAR]
const NAMES: Array[String] = ["current", "mote", "rune", "lance", "star"]

var _outdir: String = "user://arcane_bolts"
var _flight: SubViewport
var _details: Array[SubViewport] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			_outdir = arg.substr("--outdir=".length())
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var dir: String = ProjectSettings.globalize_path(_outdir) if _outdir.begins_with("user://") else _outdir
	DirAccess.make_dir_recursive_absolute(dir)

	var tex: Texture2D = load(CIRCLE_TEX) as Texture2D

	# --- the flight strip: every candidate at 1x, one lane each -----------------
	var strip_h: int = LANE_H * STYLES.size()
	_flight = _viewport(Vector2i(LANE_W, strip_h))
	var stage := Node2D.new()
	_flight.add_child(stage)
	_backdrop(stage, Vector2(LANE_W, strip_h))
	var cam := Camera2D.new()
	cam.position = Vector2(LANE_W, strip_h) * 0.5
	stage.add_child(cam)
	cam.make_current()   # AFTER the tree insert — make_current is a no-op outside it
	for i: int in STYLES.size():
		var y: float = LANE_H * (float(i) + 0.5)
		if i > 0:   # hairline between lanes, so a crop is unambiguous
			var rule := ColorRect.new()
			rule.size = Vector2(LANE_W, 1.0)
			rule.position = Vector2(0.0, LANE_H * float(i))
			rule.color = Color(1, 1, 1, 0.05)
			rule.z_index = 10
			stage.add_child(rule)
		var bolt := _bolt(STYLES[i], tex)
		bolt.base_y = y
		bolt.gap = GAP
		stage.add_child(bolt)

	# --- one detail view per candidate: same bolt, camera riding it -------------
	for i: int in STYLES.size():
		var dv: SubViewport = _viewport(DETAIL)
		_details.append(dv)
		var dstage := Node2D.new()
		dv.add_child(dstage)
		_backdrop(dstage, Vector2(X1 - X0 + 800.0, 800.0), Vector2(X0 - 400.0, -400.0))
		var dbolt := _bolt(STYLES[i], tex)
		dbolt.base_y = 0.0
		dbolt.gap = 0.0          # continuous — nothing to see in a gap when the cam rides along
		dstage.add_child(dbolt)
		var dcam := Camera2D.new()
		dcam.zoom = Vector2(DETAIL_ZOOM, DETAIL_ZOOM)
		dbolt.add_child(dcam)    # child of the bolt = follows it for free
		dcam.make_current()

	await process_frame
	await process_frame

	var t0: int = Time.get_ticks_msec()
	var step: float = 1.0 / float(FPS)
	var taken: int = 0
	while taken < FRAMES:
		await process_frame
		var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
		if elapsed < float(taken) * step:
			continue
		_flight.get_texture().get_image().save_png("%s/flight_%02d.png" % [dir, taken])
		for j: int in _details.size():
			_details[j].get_texture().get_image().save_png("%s/detail_%s_%02d.png" % [dir, NAMES[j], taken])
		taken += 1

	print("ARCANE_BOLT_PREVIEW_PASS frames=%d lanes=%s dir=%s" % [taken, ",".join(NAMES), dir])
	quit(0)


func _viewport(size: Vector2i) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = size
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.transparent_bg = false
	sv.world_2d = World2D.new()
	root.add_child(sv)
	return sv


func _backdrop(parent: Node, size: Vector2, at: Vector2 = Vector2.ZERO) -> void:
	var bg := ColorRect.new()
	bg.size = size
	bg.position = at
	bg.color = BG
	bg.z_index = -20
	parent.add_child(bg)


func _bolt(style: int, tex: Texture2D) -> BoltFx:
	var b := BoltFx.new()
	b.style = style
	b.tint = TINT
	b.mote_tex = tex
	b.speed = SPEED
	b.x0 = X0
	b.x1 = X1
	return b


## One candidate bolt: draws itself, trails itself, and flies the lane on a loop.
class BoltFx extends Node2D:
	var style: int = 0
	var tint: Color = Color(0.75, 0.55, 1.0)
	var mote_tex: Texture2D
	var speed: float = 330.0
	var x0: float = 0.0
	var x1: float = 600.0
	var base_y: float = 0.0
	var gap: float = 0.4

	var t: float = 0.0            # age of the current shot
	var _wait: float = 0.0        # time left in the between-shots beat
	var _trail: CPUParticles2D

	func _ready() -> void:
		position = Vector2(x0, base_y)
		if style != CURRENT:
			material = _additive()
		match style:
			CURRENT:
				# The shipping bolt, verbatim: white_circle at 0.5 under the arcane modulate.
				var s := Sprite2D.new()
				s.texture = mote_tex
				s.scale = Vector2(0.5, 0.5)
				s.modulate = tint
				add_child(s)
			MOTE:
				_trail = _make_trail(52, 0.34, 0.0, 7.0, 180.0, 2.6, 0.5)
			RUNE:
				_trail = _make_trail(26, 0.42, 0.0, 5.0, 180.0, 1.5, 0.42)
			LANCE:
				_trail = _make_trail(46, 0.28, 4.0, 14.0, 20.0, 2.1, 0.55)
				if _trail != null:
					_trail.direction = Vector2(-1, 0)   # streaks straight back
			STAR:
				_trail = _make_trail(34, 0.5, 6.0, 22.0, 180.0, 1.4, 0.65)

	func _process(delta: float) -> void:
		if _wait > 0.0:
			_wait -= delta
			if _wait <= 0.0:
				visible = true
				t = 0.0
				position.x = x0
				if _trail != null:
					_trail.restart()   # a world-space trail must not survive the reset
			return
		t += delta
		position.x += speed * delta
		# A little vertical life on the lance, so a straight line is not a dead line.
		position.y = base_y + (sin(t * 21.0) * 1.1 if style == LANCE else 0.0)
		if position.x >= x1:
			if gap <= 0.0:
				position.x = x0
				if _trail != null:
					_trail.restart()
			else:
				visible = false
				_wait = gap
		queue_redraw()

	func _draw() -> void:
		match style:
			MOTE:
				_draw_mote()
			RUNE:
				_draw_rune()
			LANCE:
				_draw_lance()
			STAR:
				_draw_star()

	## A hot white core inside a breathing arcane halo, trailing soft motes. The smallest
	## possible upgrade: same silhouette, but it glows and it leaves a wake.
	func _draw_mote() -> void:
		var pulse: float = 1.0 + 0.13 * sin(t * 17.0)
		draw_circle(Vector2.ZERO, 9.4 * pulse, Color(tint.r, tint.g, tint.b, 0.10))
		draw_circle(Vector2.ZERO, 6.3 * pulse, Color(tint.r, tint.g, tint.b, 0.22))
		draw_circle(Vector2.ZERO, 3.7 * pulse, Color(tint.lerp(Color.WHITE, 0.55), 0.7))
		draw_circle(Vector2.ZERO, 1.9 * pulse, Color(1, 1, 1, 0.95))

	## A spellcaster's sigil in flight: a broken outer ring and an inner glyph counter-spinning
	## around the core, with three motes in orbit. The most "Arcanist" silhouette of the four.
	func _draw_rune() -> void:
		draw_circle(Vector2.ZERO, 5.0, Color(tint.r, tint.g, tint.b, 0.20))
		draw_circle(Vector2.ZERO, 2.2, Color(1, 1, 1, 0.92))
		# Outer ring, three gaps, turning one way.
		var a: float = t * 2.2
		for k: int in 3:
			var s: float = a + float(k) * TAU / 3.0
			draw_arc(Vector2.ZERO, 10.0, s, s + 0.72, 12, Color(tint.r, tint.g, tint.b, 0.75), 1.6, true)
		# Inner glyph, turning the other way.
		var g: float = -t * 3.4
		var tri := PackedVector2Array()
		for k: int in 3:
			var s2: float = g + float(k) * TAU / 3.0
			tri.append(Vector2(cos(s2), sin(s2)) * 6.0)
		tri.append(tri[0])
		draw_polyline(tri, Color(tint.lerp(Color.WHITE, 0.4), 0.7), 1.2, true)
		# Three motes in orbit.
		for k2: int in 3:
			var s3: float = a * 0.7 + float(k2) * TAU / 3.0
			draw_circle(Vector2(cos(s3), sin(s3)) * 12.6, 1.4, Color(tint.lerp(Color.WHITE, 0.6), 0.85))

	## A stretched dart with a hot inner filament — reads as SPEED. The bolt no longer looks
	## like it is hovering; it looks like it was thrown.
	func _draw_lance() -> void:
		var outer := PackedVector2Array([
			Vector2(7.0, 0.0), Vector2(-2.0, -3.6), Vector2(-31.0, -1.0),
			Vector2(-31.0, 1.0), Vector2(-2.0, 3.6),
		])
		draw_colored_polygon(outer, Color(tint.r, tint.g, tint.b, 0.40))
		var inner := PackedVector2Array([
			Vector2(5.6, 0.0), Vector2(-1.0, -2.0), Vector2(-20.0, -0.5),
			Vector2(-20.0, 0.5), Vector2(-1.0, 2.0),
		])
		draw_colored_polygon(inner, Color(tint.lerp(Color.WHITE, 0.65), 0.8))
		draw_circle(Vector2(2.0, 0.0), 4.6, Color(tint.r, tint.g, tint.b, 0.28))
		draw_circle(Vector2(2.0, 0.0), 2.3, Color(1, 1, 1, 0.95))

	## A four-point star flare that twinkles as it turns, shedding sparkles — the classic
	## "magic missile" read, and the one that stays legible on a busy floor.
	func _draw_star() -> void:
		var twinkle: float = 1.0 + 0.2 * sin(t * 10.0)
		var long_r: float = 11.5 * twinkle
		var short_r: float = 3.4
		var spin: float = t * 0.9
		var pts := PackedVector2Array()
		for k: int in 8:
			var ang: float = spin + float(k) * TAU / 8.0
			var r: float = long_r if k % 2 == 0 else short_r
			pts.append(Vector2(cos(ang), sin(ang)) * r)
		draw_circle(Vector2.ZERO, 6.4, Color(tint.r, tint.g, tint.b, 0.16))
		draw_colored_polygon(pts, Color(tint.r, tint.g, tint.b, 0.75))
		draw_circle(Vector2.ZERO, 2.0, Color(1, 1, 1, 0.95))

	## World-space wake (local_coords = false) so the trail stays where it was emitted
	## instead of riding along — the whole point of a trail.
	func _make_trail(amount: int, life: float, vmin: float, vmax: float, spread: float,
			scale_px: float, alpha: float) -> CPUParticles2D:
		var p := CPUParticles2D.new()
		p.texture = mote_tex
		p.local_coords = false
		p.emitting = true
		p.amount = amount
		p.lifetime = life
		p.spread = spread
		p.gravity = Vector2.ZERO
		p.initial_velocity_min = vmin
		p.initial_velocity_max = vmax
		p.scale_amount_min = scale_px * 0.06
		p.scale_amount_max = scale_px * 0.11
		var shrink := Curve.new()
		shrink.add_point(Vector2(0.0, 1.0))
		shrink.add_point(Vector2(1.0, 0.0))
		p.scale_amount_curve = shrink
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		ramp.colors = PackedColorArray([
			Color(tint.lerp(Color.WHITE, 0.5), alpha),
			Color(tint, alpha * 0.8),
			Color(tint, 0.0),
		])
		p.color_ramp = ramp
		p.material = _additive()
		p.z_index = -1
		add_child(p)
		return p

	func _additive() -> CanvasItemMaterial:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		return m
