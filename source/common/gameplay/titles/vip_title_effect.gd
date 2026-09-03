class_name VipTitleEffect
extends Node2D
## The particle layer for a VIP donation title, parented to the title Label and
## sized to it. One node per wearer; the look comes entirely from the wearer's
## [VipTierProfile].
##
## SAME CONTRACT AS [TitleParticles], deliberately. Same absolute z, same
## build()/fit_to() pair, same CPU-only emitters, same clamp-don't-trust approach
## to the budget. The nameplate mounts whichever of the two a title calls for and
## does not care which it got, and a future reader comparing them should find
## them boringly similar.
##
## WHAT IS DIFFERENT is that these are BOUGHT, so they are worn constantly by
## exactly the players most likely to stand together in a bank, and the crowd
## case is the design case rather than the edge case. Hence the LOD half of this
## file, which [TitleParticles] has no equivalent of.
##
## CPUParticles2D ONLY. GPUParticles2D is not safe on the web export - the same
## call every other VFX system in this project makes - and
## tools/verify_vip_titles.gd fails the build if one appears here.
##
## vip_title_effect.tscn next door wraps this for anyone who wants to drop one
## into a scene by hand. The RUNTIME path does not use it: [TitleVfx] has to set
## [member tier] before the node enters the tree, and instancing a scene only to
## overwrite its one property immediately afterwards buys nothing.

## Emitter budget, per layer. Tighter than [TitleParticles]'s because a VIP title
## runs up to [constant MAX_LAYERS] emitters at once and the mastery titles run
## two.
const MIN_AMOUNT: int = 4
## Matches [constant TitleParticles.MAX_AMOUNT] plus one step. A signature layer
## has to be able to carry a tier on its own - Diamond's dust field IS the tier -
## and at the old 22 it read as a sprinkle rather than as a thing you paid for.
const MAX_AMOUNT: int = 26
const MIN_LIFETIME: float = 0.3
## Longer than the mastery ceiling by 0.2 s, and only because rolling fog has to
## outlive a glint to read as fog at all. Nothing else here goes near it.
const MAX_LIFETIME: float = 1.4
const MAX_LAYERS: int = 3
## Particles alive at once across a whole title, summed over its layers. This is
## the number that actually matters in a bank - a tier can spend it on three thin
## layers or two thick ones, but it cannot spend more than this.
##
## Above the mastery family's effective ceiling (two emitters x
## [constant TitleParticles.MAX_AMOUNT] = 50), and paid for by the LOD half of
## this file, which the mastery titles have no equivalent of. These are the only
## titles that stop emitting off screen and shed their detail layers in a crowd,
## so the number that matters in a bank is not this one: Diamond peaks at 60 and
## settles to 44 the moment a seventh VIP title walks into frame, which is below
## what a Slayer Master costs standing next to it.
const MAX_TOTAL_AMOUNT: int = 62

## Ceiling on [member VipParticleLayer.span_scale]. See that property: titles here
## are text VFX and never character auras, and this is where that rule is
## enforced rather than merely stated.
const MAX_SPAN_SCALE: float = 1.8

## Above the player sprite and world props. Absolute, so the depth does not drift
## with whatever the label is parented under. Shared with [TitleParticles] so the
## two title families cannot end up at different depths on one nameplate.
const NAMEPLATE_Z: int = TitleParticles.NAMEPLATE_Z

## Emitters are built against this and rescaled by [method fit_to], because a
## nameplate label's size is known only after it lays out. Half-width, half-height.
const REF_EXTENT: Vector2 = TitleParticles.REF_EXTENT

## World-space radius, from the camera centre, inside which a title runs all its
## layers. Past it the layers flagged [member VipParticleLayer.detail] stop.
##
## SIXTY-FOUR PIXELS IS MOST OF THE SCREEN. The camera is at zoom 3 over a
## 960x540 viewport, so the visible world is 320x180 units and the far corner is
## only ~184 away. That is why there is one distance band and not three: there is
## no room on screen for a third, and a ladder of thresholds tuned as though this
## were a 1:1 camera would put every band outside the view and never fire.
const RICH_RADIUS: float = 64.0

## How many VIP titles may run their full layer set on screen at once. Past this,
## EVERY on-screen title drops to its signature layers - uniformly, rather than
## by rank. Ranking would mean sorting every wearer against every other one on
## each tick, and would also mean the same two titles in a crowd keep their
## sparkle while everyone else visibly loses theirs, which reads as favouritism
## toward whoever happens to be nearest the camera.
const CROWD_RICH_LIMIT: int = 6

## Seconds between LOD re-evaluations. Not per frame: the whole point is that
## thirty of these cost nothing, and a distance check running at frame rate on
## thirty nodes is exactly the cost being avoided. The first tick is randomised
## per wearer so a bank full of them does not recompute on the same frame.
const LOD_INTERVAL: float = 0.25

## Grow the cull rect past the label by this factor, so particles that travel
## outside the text are not clipped away a frame before the label is.
const CULL_MARGIN: float = 1.6

## Ray-fan length, as a fraction of the label's half-width, before the cap below.
## Matches [constant TitleParticles.RAY_SCALE] so Diamond's fan and High Priest's
## are the same burst at the same size - they are meant to read as the same
## effect in two colours.
const RAY_SCALE: float = TitleParticles.RAY_SCALE
## Triangles in the fan.
const RAY_COUNT: int = 7

## Additive blending, shared by every additive emitter of every wearer on screen.
## One material rather than one per emitter: a CanvasItemMaterial is a resource
## and thirty players x three layers is ninety identical ones otherwise.
static var _additive: CanvasItemMaterial = null

## VIP titles currently inside the view. Drives [constant CROWD_RICH_LIMIT].
## Maintained by the notifier signals, so it costs nothing per frame.
static var _on_screen: int = 0

## The tier key, matching [member VipTierProfile.tier]. Set BEFORE the node
## enters the tree; [method build] reads it once and the emitter set is not
## designed to be mutated afterwards.
var tier: StringName = &""

var _profile: VipTierProfile = null
var _extent: Vector2 = REF_EXTENT
var _built: bool = false
## Emitters flagged [member VipParticleLayer.detail], in build order.
var _detail: Array[CPUParticles2D] = []
var _all: Array[CPUParticles2D] = []
## Widest span_scale any layer asked for, so the cull rect can cover the whole
## drifting field rather than just the text it hangs off.
var _span_reach: float = 1.0
## Ray fan, or null for a tier without one. The ONLY thing here that costs a
## _process call, which is why it gates one - see [method build].
var _rays: VfxDrawLayer = null
var _notifier: VisibleOnScreenNotifier2D = null
var _lod_timer: Timer = null
## Starts TRUE and is only ever lowered by the notifier. Fail-visible on purpose:
## if the notifier never reports for some reason the title keeps sparkling, which
## costs a little frame time, rather than a paid accolade silently not rendering.
var _visible: bool = true
## Whether this wearer is currently counted in [member _on_screen]. Tracked
## separately from [member _visible] because the two go out of step - the node
## starts visible but uncounted, and it can leave the tree without the notifier
## ever reporting an exit.
var _counted: bool = false
var _rich: bool = true


func _ready() -> void:
	build()
	_start_lod()


## Construct the emitter set. Idempotent, and callable WITHOUT the node being in
## a tree - a node added during a tool's _initialize() does not get _ready until
## the tree ticks, so a verifier would otherwise be measuring empty nodes and
## reporting them as fine. Same reason [method TitleParticles.build] is public.
func build() -> void:
	if _built:
		return
	_built = true
	z_as_relative = false
	z_index = NAMEPLATE_Z
	_profile = VipTierProfile.for_tier(tier)
	if _profile == null:
		return
	var layers: Array[VipParticleLayer] = _profile.layers
	for i: int in mini(layers.size(), MAX_LAYERS):
		var layer: VipParticleLayer = layers[i]
		if layer != null:
			_span_reach = maxf(_span_reach, _clamped_span(layer))
			_emitter(layer)
	_build_rays()
	_build_lod()
	# A tier without a fan is a pure emitter set and must not pay for a _process
	# call over every head in a busy town. Same gate TitleParticles uses.
	set_process(_rays != null)


## Resize to the label this hangs off. Called after the label lays out, and again
## whenever the text changes - "Diamond Donator" and "Silver Contributor" are not
## the same width, and an emitter sized for one looks wrong on the other.
func fit_to(label_size: Vector2) -> void:
	if label_size.x <= 1.0:
		return
	_extent = label_size * 0.5
	for p: CPUParticles2D in _all:
		_apply_span(p, int(p.get_meta(&"span_mode", 0)), float(p.get_meta(&"span_scale", 1.0)))
	_fit_cull_rect()


## The cull rect has to cover the widest layer's field, not the text. Diamond's
## dust drifts well outside the letters, and a rect sized to the label alone would
## cull the whole title while half its dust was still on screen - which reads as
## the effect switching itself off at the edge of the view.
func _fit_cull_rect() -> void:
	if _notifier == null:
		return
	var reach: Vector2 = _extent * maxf(CULL_MARGIN, _span_reach + 0.3)
	_notifier.rect = Rect2(-reach, reach * 2.0)


## Total particles this title can have alive at once. The verifier's headline
## number, and the one worth reading first when a tier is retuned.
func total_amount() -> int:
	var sum: int = 0
	for p: CPUParticles2D in _all:
		sum += p.amount
	return sum


func _emitter(layer: VipParticleLayer) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.name = String(layer.id) if layer.id != &"" else "Layer%d" % _all.size()
	# Clamped rather than trusted. The .tres files are hand-edited and are meant
	# to be, so a fat-fingered amount has to cost a dull emitter and not a frame
	# spike over thirty heads.
	p.amount = clampi(layer.amount, MIN_AMOUNT, MAX_AMOUNT)
	p.lifetime = clampf(layer.lifetime, MIN_LIFETIME, MAX_LIFETIME)
	p.explosiveness = layer.explosiveness
	p.texture = layer.texture()
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.direction = layer.direction
	p.spread = layer.spread
	p.gravity = layer.gravity
	p.initial_velocity_min = layer.velocity_min
	p.initial_velocity_max = layer.velocity_max
	p.damping_min = layer.damping
	p.damping_max = layer.damping
	p.scale_amount_min = layer.scale_min
	p.scale_amount_max = layer.scale_max
	if not is_equal_approx(layer.scale_start, layer.scale_end):
		var curve: Curve = Curve.new()
		curve.add_point(Vector2(0.0, layer.scale_start))
		curve.add_point(Vector2(1.0, layer.scale_end))
		p.scale_amount_curve = curve
	if layer.angular_velocity > 0.0:
		p.angular_velocity_min = -layer.angular_velocity
		p.angular_velocity_max = layer.angular_velocity
	p.color_ramp = layer.ramp()
	# GLOBAL space, so particles stay where they were born while the nameplate
	# walks on and the layer reads as a trail rather than as a rigid halo bolted
	# to the letters. This is the engine default in 4.x and is set explicitly
	# anyway: it is a look decision, not an inherited one, and a future default
	# flip would turn every tier into a halo with nothing here to explain why.
	p.local_coords = false
	if layer.additive:
		p.material = _shared_additive()
	p.emitting = true
	p.set_meta(&"span_mode", int(layer.span))
	p.set_meta(&"span_scale", _clamped_span(layer))
	add_child(p)
	_apply_span(p, int(layer.span), _clamped_span(layer))
	_all.append(p)
	if layer.detail:
		_detail.append(p)
	return p


## [member VipParticleLayer.span_scale], clamped. Clamped rather than trusted for
## the same reason the amounts are - the .tres are hand-edited by design - but
## this one is a product rule and not a budget, so the verifier fails on it
## instead of letting the clamp quietly correct the file.
func _clamped_span(layer: VipParticleLayer) -> float:
	return clampf(layer.span_scale, 1.0, MAX_SPAN_SCALE)


## Where along the label an emitter draws from. Mirrors [TitleParticles]'s span
## modes exactly, including the flat-box approximation of the two ends - an
## emission rect cannot be a ring, and particles land mostly at the extremes
## because that is where its area is once the glyphs cover the middle.
##
## [param scale] widens the box past the label. The edge strips keep their
## one-pixel height and stay pinned to the label's own edge whatever it is: a TOP
## layer that drifted off the top of the text would stop reading as coming OFF the
## letters, which is the only thing making it part of the title.
func _apply_span(p: CPUParticles2D, mode: int, scale: float = 1.0) -> void:
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var box: Vector2 = _extent * scale
	match mode:
		VipParticleLayer.Span.TOP:
			p.emission_rect_extents = Vector2(box.x, 1.0)
			p.position = Vector2(0.0, -_extent.y)
		VipParticleLayer.Span.BOTTOM:
			p.emission_rect_extents = Vector2(box.x, 1.0)
			p.position = Vector2(0.0, _extent.y)
		VipParticleLayer.Span.ENDS:
			p.emission_rect_extents = Vector2(box.x * 1.08, box.y * 0.9)
			p.position = Vector2.ZERO
		_:
			p.emission_rect_extents = box
			p.position = Vector2.ZERO


## The fan sits BEHIND the glyphs but still above the world, so it gets its own
## layer one step under the nameplate depth rather than being drawn by this node
## (which is above the label, where it would wash the text out).
func _build_rays() -> void:
	if _profile == null or _profile.ray_color.a <= 0.0:
		return
	_rays = VfxDrawLayer.new()
	_rays.name = "Rays"
	_rays.painter = _paint_rays
	_rays.z_as_relative = false
	_rays.z_index = NAMEPLATE_Z - 1
	_rays.material = _shared_additive()
	add_child(_rays)


func _process(_delta: float) -> void:
	if _rays != null:
		_rays.queue_redraw()


## Seven triangles fanning up from the centre of the title, breathing slowly.
##
## Reach is scaled to [constant RAY_SCALE] and then CAPPED AT THE HALF-HEIGHT, so
## the fan is strictly bounded by the title's own line rather than spraying out to
## the label's full width. That cap is what keeps this a title effect and not a
## character aura, and it is the reason a fan is allowed here at all.
func _paint_rays(layer: Node2D) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	var tint: Color = _profile.ray_color
	for i: int in RAY_COUNT:
		var k: float = float(i) / float(RAY_COUNT - 1)
		var angle: float = lerpf(-2.5, -0.65, k) + sin(t * 0.5) * 0.05
		var reach: float = minf(
			_extent.x * (0.75 + 0.35 * sin(t * 0.9 + k * 3.0)) * RAY_SCALE, _extent.y
		)
		var half: float = 0.09
		var alpha: float = tint.a * (0.72 + 0.28 * sin(t * 1.6 + k * 2.2))
		layer.draw_colored_polygon(
			PackedVector2Array([
				Vector2.ZERO,
				Vector2.from_angle(angle - half) * reach,
				Vector2.from_angle(angle + half) * reach,
			]),
			Color(tint.r, tint.g, tint.b, alpha)
		)


static func _shared_additive() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


# -- LOD -----------------------------------------------------------------------
#
# Two mechanisms, answering different questions.
#
#   THE NOTIFIER answers "is this title in frame at all", and is the only one of
#   the two that may stop every layer, because a title nobody can see is the only
#   case where cutting the signature layer is free.
#
#   THE TIMER answers "is it worth its full layer set", from distance and from
#   how many other VIP titles share the view. It never stops a signature layer: a
#   paid accolade that visibly degrades while you are looking at it is worse than
#   the frame time it saves.
#
# Emitters are stopped with `emitting`, not by lowering `amount`. CPUParticles2D
# has no amount_ratio (checked against 4.7 - it is a GPUParticles2D property),
# and writing `amount` restarts the system, which pops. Clearing `emitting`
# simply stops new particles and lets the ones already alive finish their
# sub-second lives, so the transition is invisible in both directions.


func _build_lod() -> void:
	if _all.is_empty():
		return
	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.name = "Cull"
	_notifier.screen_entered.connect(_on_screen_entered)
	_notifier.screen_exited.connect(_on_screen_exited)
	add_child(_notifier)
	_fit_cull_rect()

	_lod_timer = Timer.new()
	_lod_timer.name = "Lod"
	_lod_timer.wait_time = LOD_INTERVAL
	_lod_timer.timeout.connect(_tick_lod)
	add_child(_lod_timer)


## Staggered start, so a bank full of wearers spreads its checks across the
## interval instead of spiking one frame in four.
##
## Separate from [method _build_lod] because Timer.start() errors when the node
## is not in a tree, and build() is deliberately callable outside one so
## tools/verify_vip_titles.gd can measure the emitters without ticking a scene.
func _start_lod() -> void:
	if _lod_timer == null or not is_inside_tree():
		return
	_lod_timer.start(randf_range(LOD_INTERVAL * 0.25, LOD_INTERVAL))


func _exit_tree() -> void:
	# A player walking out of range is freed, not culled, so the notifier may
	# never report an exit for them and the static counter would drift up until
	# every VIP title in the world was permanently lean.
	_release_count()


func _on_screen_entered() -> void:
	_visible = true
	if not _counted:
		_counted = true
		_on_screen += 1
	_start_lod()
	set_process(_rays != null)
	_tick_lod()


func _on_screen_exited() -> void:
	_visible = false
	_release_count()
	if _lod_timer != null:
		_lod_timer.stop()
	for p: CPUParticles2D in _all:
		p.emitting = false
	# The fan redraws every frame, so culling it matters more than culling an
	# emitter that has merely stopped spawning.
	set_process(false)


func _release_count() -> void:
	if not _counted:
		return
	_counted = false
	_on_screen = maxi(0, _on_screen - 1)


func _tick_lod() -> void:
	if not _visible:
		return
	var rich: bool = _on_screen <= CROWD_RICH_LIMIT and _near_camera()
	# Restart anything the cull stopped. Guarded rather than assigned blind:
	# writing `emitting` is not free on CPUParticles2D and this runs four times a
	# second per wearer.
	for p: CPUParticles2D in _all:
		if not p.emitting and (rich or not _detail.has(p)):
			p.emitting = true
	if rich == _rich:
		return
	_rich = rich
	for p: CPUParticles2D in _detail:
		p.emitting = rich


## True when the camera is close enough for the ambient layers to be worth
## drawing. No camera (a tool run, a headless verify, a SubViewport without one)
## counts as close: those are the cases where the effect is being INSPECTED, and
## quietly showing a stripped-down version there would make every proof capture
## and every screenshot lie about what ships.
func _near_camera() -> bool:
	if not is_inside_tree():
		return true
	var view: Viewport = get_viewport()
	if view == null:
		return true
	var cam: Camera2D = view.get_camera_2d()
	if cam == null:
		return true
	return global_position.distance_to(cam.get_screen_center_position()) <= RICH_RADIUS
