extends SceneTree
## Render Cleetus actually casting: the pose clip, the charge in his fist and the
## payload, composited the same way a client composites them — real skin, real
## VFX sheets, real muzzle formula, real cast timings off his .tres.
##
## One row per spell:
##   Static Arc   — cast_storm + storm charge, then the chain leaves the fist.
##   Laser        — cast_beam + charge, then the beam fires down the corridor.
##   Cinder Lash  — cast_beam + charge, then the beam SWEEPS through its arc.
##
## Must run WINDOWED (no --headless) — headless has no rasteriser:
##   godot --path . -s tools/render_cleetus_spells.gd

const SKIN := "res://source/common/gameplay/characters/sprite_frames/cleetus.tres"
const BOSS := "res://source/common/gameplay/characters/npc/types/bosses/cleetus.tres"
const VFX := "res://source/common/gameplay/combat/vfx/"
const OUT_DIR := "user://cleetus_spells"
const BASE_SPEED := 1.5
const ZOOM := 2
const W := 980
const ROW_H := 250
const CAPTURE_S := 3.2
const FPS := 12
## Mirrors HostileNpc.STAFF_MUZZLE_LOCAL — the staff TIP, in unscaled sprite
## units. Every ranged cast fires from here, not from the fist.
const MUZZLE := Vector2(25.0, -23.0)

var _sv: SubViewport
var _stage: Node2D
var _boss: EnemyTypeResource
var _skin: SpriteFrames


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_skin = load(SKIN) as SpriteFrames
	_boss = load(BOSS) as EnemyTypeResource
	if _skin == null or _boss == null:
		printerr("FAIL: skin or boss resource missing")
		quit(1)
		return

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, ROW_H * 3)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.transparent_bg = false
	_sv.world_2d = World2D.new()
	root.add_child(_sv)

	_stage = Node2D.new()
	_sv.add_child(_stage)
	var bg := ColorRect.new()
	bg.size = Vector2(W, ROW_H * 3)
	bg.color = Color(0.11, 0.11, 0.15)
	bg.z_index = -10
	_stage.add_child(bg)
	var cam := Camera2D.new()
	cam.position = Vector2(W, ROW_H * 3) * 0.5
	cam.make_current()
	_stage.add_child(cam)

	# Row origins: the boss's feet. Everything else is measured off these.
	var feet: Array[Vector2] = [
		Vector2(190.0, ROW_H - 60.0),
		Vector2(190.0, ROW_H * 2 - 60.0),
		Vector2(190.0, ROW_H * 3 - 60.0),
	]
	for i: int in 3:
		var line := ColorRect.new()
		line.size = Vector2(W - 60.0, 2.0)
		line.position = Vector2(30.0, feet[i].y)
		line.color = Color(0.24, 0.25, 0.32)
		_stage.add_child(line)
	_label(Vector2(40, ROW_H * 0 + 20), "STATIC ARC   cast_staff  %.1fs windup  -> lightning off the staff"
		% _boss.chain_windup_s)
	_label(Vector2(40, ROW_H * 1 + 20), "LASER   cast_staff  %.1fs windup  -> %dpx beam from the staff"
		% [_boss.laser_windup_s, int(_boss.laser_range)])
	_label(Vector2(40, ROW_H * 2 + 20), "CINDER LASH   cast_staff  %.1fs windup  -> %d deg sweep over %.1fs"
		% [_boss.sweep_windup_s, int(_boss.sweep_arc_deg), _boss.sweep_duration_s])

	var storm: AnimatedSprite2D = _body(feet[0], &"cast_staff", _boss.chain_windup_s)
	var laser: AnimatedSprite2D = _body(feet[1], &"cast_staff", _boss.laser_windup_s)
	var lash: AnimatedSprite2D = _body(feet[2], &"cast_staff",
		_boss.sweep_windup_s + _boss.sweep_duration_s)

	await process_frame
	await process_frame
	storm.play(&"cast_staff")
	laser.play(&"cast_staff")
	lash.play(&"cast_staff")

	# Charges build in the fist for each wind-up (element 2 = storm, 0 = fire).
	_charge(feet[0], 2, _boss.chain_windup_s)
	_charge(feet[1], 0, _boss.laser_windup_s)
	_charge(feet[2], 0, _boss.sweep_windup_s)

	_after(_boss.chain_windup_s, _fire_chain.bind(feet[0]))
	_after(_boss.laser_windup_s, _fire_laser.bind(feet[1]))
	_after(_boss.sweep_windup_s, _fire_sweep.bind(feet[2]))

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
		_sv.get_texture().get_image().save_png("%s/frame_%02d.png" % [OUT_DIR, taken])
		taken += 1
	print("RENDER_OK frames=%d dir=%s" % [taken, ProjectSettings.globalize_path(OUT_DIR)])
	quit()


func _after(delay: float, what: Callable) -> void:
	create_timer(delay).timeout.connect(what, CONNECT_ONE_SHOT)


## The boss at his in-game visual_scale, feet on the row's ground line, with the
## pose clip stretched exactly as rp_play_skin_anim would stretch it.
func _body(feet: Vector2, clip: StringName, fill: float) -> AnimatedSprite2D:
	var s: float = _boss.visual_scale * float(ZOOM)
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = _skin
	spr.centered = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(s, s)
	# character.tscn draws the sprite at offset (0, -30), scaled; the frame's last
	# row is the feet, so this puts the feet on the line.
	spr.position = feet + Vector2(0.0, -30.0) * s
	var natural: float = float(_skin.get_frame_count(clip)) \
		/ (_skin.get_animation_speed(clip) * BASE_SPEED)
	spr.speed_scale = BASE_SPEED * (natural / fill) if fill > natural else BASE_SPEED
	_stage.add_child(spr)
	return spr


func _muzzle(feet: Vector2) -> Vector2:
	return feet + MUZZLE * _boss.visual_scale * float(ZOOM)


func _fx(sheet: String, at: Vector2, opts: Dictionary) -> SpriteEffect:
	var frames: SpriteFrames = load(VFX + sheet + ".tres") as SpriteFrames
	if frames == null:
		return null
	var fx: SpriteEffect = SpriteEffect.spawn(_stage, frames, opts)
	if fx != null:
		fx.position = at
	return fx


func _charge(feet: Vector2, element: int, duration: float) -> void:
	var sheet: String = "static_ring" if element == 2 else "lash_burst"
	var tint: Color = Color(0.78, 0.62, 1.0) if element == 2 else Color(1.0, 0.72, 0.35)
	_fx(sheet, _muzzle(feet), {
		"loop": true, "duration": duration, "scale": Vector2(0.38, 0.38) * ZOOM,
		"z_index": 3, "speed_scale": 1.6, "modulate": tint,
	})


## Lightning leaving the fist and jumping between two stand-in targets.
func _fire_chain(feet: Vector2) -> void:
	var from: Vector2 = _muzzle(feet)
	var marks: Array[Vector2] = [from + Vector2(250, -30), from + Vector2(430, 20)]
	var prev: Vector2 = from
	for m: Vector2 in marks:
		var span: float = prev.distance_to(m)
		var seg: SpriteEffect = _fx("arc_bolt", (prev + m) * 0.5, {
			"scale": Vector2(span / 256.0, 0.42 * ZOOM), "z_index": 3, "speed_scale": 1.4,
		})
		if seg != null:
			seg.rotation = (m - prev).angle()
		_fx("static_ring", m, {"scale": Vector2(0.7, 0.7) * ZOOM, "z_index": 3, "speed_scale": 1.3})
		prev = m


## A straight beam down the corridor, starting at the fist.
func _fire_laser(feet: Vector2) -> void:
	var from: Vector2 = _muzzle(feet)
	var length: float = _boss.laser_range * float(ZOOM) * 0.62  # cropped to the panel
	var mid: Vector2 = from + Vector2(length * 0.5, 0.0)
	var fx: SpriteEffect = _fx("mecha_laser", mid, {
		"scale": Vector2(length / 300.0, 0.55 * ZOOM), "z_index": 3,
		"speed_scale": 1.25,
	})
	if fx != null:
		fx.rotation = 0.0


## The sweeping beam: a pivot at the fist with the beam parked half a length out,
## rotated over the sweep — the same construction rp_sweep_beam uses.
func _fire_sweep(feet: Vector2) -> void:
	var from: Vector2 = _muzzle(feet)
	var length: float = _boss.sweep_range * float(ZOOM) * 0.62
	var half: float = deg_to_rad(_boss.sweep_arc_deg) * 0.5
	var pivot := Node2D.new()
	_stage.add_child(pivot)
	pivot.position = from
	pivot.rotation = -half * 0.55
	var frames: SpriteFrames = load(VFX + "lash_beam.tres") as SpriteFrames
	if frames != null:
		var fx: SpriteEffect = SpriteEffect.spawn(pivot, frames, {
			"loop": true, "duration": _boss.sweep_duration_s + 0.12,
			"scale": Vector2(length / 256.0, 0.7 * ZOOM), "z_index": 3,
			"speed_scale": 1.5, "modulate": Color(1.0, 0.72, 0.35),
		})
		if fx != null:
			fx.position = Vector2(length * 0.5, 0.0)
	var tw: Tween = pivot.create_tween()
	tw.tween_property(pivot, "rotation", half * 0.55, _boss.sweep_duration_s)
	tw.tween_callback(pivot.queue_free)


func _label(at: Vector2, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_color_override(&"font_color", Color(0.85, 0.86, 0.92))
	_stage.add_child(l)
