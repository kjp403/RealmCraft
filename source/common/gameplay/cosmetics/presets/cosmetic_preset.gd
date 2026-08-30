class_name CosmeticPreset
extends Node2D
## Base for the SCRIPTED cosmetic VFX — the layered, multi-node replacements for
## the flat pre-rendered strips in assets/sprites/vfx/cosmetics.
##
## The strips (tools/gen_cosmetic_vfx.py) are a single 128x128 AnimatedSprite2D
## looping ~12 frames. That ceiling is why every aura was a ring and every trail a
## streak: one sprite cannot hold a floor shader, a particle system and a
## world-space decal at once, and a 12-frame loop cannot react to whether the
## wearer is standing still or sprinting. A preset is a real node tree instead, so
## each effect is built from the layers the look actually needs:
##
##   FLOOR    a shader quad or a _draw() pass on the ground plane, under the body.
##   AIR      CPUParticles2D emitters — never GPUParticles2D, the web export is a
##            shipping target and GPU particles are not safe there (same call the
##            slam debris and channel motes already make).
##   WORLD    top_level nodes dropped at a world position and left behind, which
##            is the only way a trail can mark the floor the wearer walked over.
##
## Presets are CLIENT-ONLY and mounted by [CosmeticVfx], which keeps the strip
## path alive for every slug without one. Adding a preset is one script plus one
## line in [CosmeticPresetLibrary] — no registry, index or art rebuild.

## Vertical squash of the ground plane. Matches [SanctuaryRing] / [GuardAura] so a
## cosmetic ring and a gameplay ring read as lying on the SAME floor — a cosmetic
## that sits at a different tilt makes the gameplay ring look wrong, not the aura.
const GROUND_SQUASH: float = 0.5

## Default aura footprint in pixels, sized just wider than a 64 px body's feet.
## Deliberately close to GuardAura's 24 px: an aura that swallows the body reads as
## a boss telegraph, and players have to be able to see each other.
const BASE_RADIUS: float = 26.0

## Approximate body landmarks in local space (origin is at the feet, +y is down).
const KNEE_Y: float = -13.0
const CHEST_Y: float = -26.0
const HEAD_Y: float = -38.0

## The wearer, for movement and for the "is this me?" checks a screen-space layer
## needs. Assigned by [CosmeticVfx.apply] before the node enters the tree.
var wearer: Character

## True when this preset is mounted in the wardrobe rather than on a live
## character. Set by [CosmeticPresetLibrary.build] before the node enters the
## tree; see the two gates below for what it changes.
var is_preview: bool = false

## Seconds since this preset was mounted. Every animated value is a function of
## this rather than of engine time, so two wearers on screen are not locked in
## phase and the effect always starts at the beginning of its cycle.
var _elapsed: float = 0.0


func _ready() -> void:
	# Under the body, above the floor. The parent CosmeticVfx already sits at -1;
	# staying at the parent's depth keeps a preset and a strip interchangeable.
	z_index = 0
	_build()


## Override to construct the layers. Called once, from _ready.
func _build() -> void:
	pass


func _process(delta: float) -> void:
	_elapsed += delta
	_tick(delta)
	queue_redraw()
	for layer: Node2D in _draw_layers:
		layer.queue_redraw()


## Override for per-frame work beyond redrawing (movement sampling, retiming).
func _tick(_delta: float) -> void:
	pass


## Called when the wearer turns. Radial effects ignore it; directional ones use it.
func set_facing(_flipped: bool) -> void:
	pass


# --- Ground-plane helpers ----------------------------------------------------

## A point on the squashed ground ellipse, in local space.
func _ground_point(angle: float, radius: float) -> Vector2:
	return Vector2(cos(angle) * radius, sin(angle) * radius * GROUND_SQUASH)


## Put _draw() into the ground plane. Everything drawn after this is squashed, so
## draw_circle / draw_arc produce floor ellipses instead of standing discs.
func _use_ground_plane() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))


## Undo [method _use_ground_plane] for anything that stands upright (vines, stars,
## crystals) — those must NOT be squashed or they look like they are lying down.
func _use_upright_plane() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Layer construction ------------------------------------------------------

## A CPUParticles2D with the defaults every cosmetic layer wants: emitting, nearest
## filtering (crisp against pixel-art bodies) and a shaped mask instead of the
## engine's default square. Callers set direction / gravity / ramp afterward.
func _add_emitter(amount: int, lifetime: float, texture: Texture2D) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.texture = texture
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.emitting = true
	add_child(p)
	return p


## A repeating BURST: every [param lifetime] seconds the whole batch spawns at
## once, then dies together.
##
## explosiveness 1.0 on a looping emitter is the trick that gives a periodic pop
## with no timer and no node churn — which matters because these auras are worn
## permanently by every player on screen, so spawning a one-shot emitter per pop
## (the [SlamImpact] pattern, correct for a single hit) would allocate forever.
func _add_burst(amount: int, lifetime: float, texture: Texture2D) -> CPUParticles2D:
	var p: CPUParticles2D = _add_emitter(amount, lifetime, texture)
	p.explosiveness = 1.0
	return p


## Two-stop fade-out ramp: full colour at birth, transparent at death.
func _fade_ramp(tint: Color, peak_alpha: float = 1.0) -> Gradient:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(tint, peak_alpha), Color(tint, 0.0)])
	return g


## Three-stop ramp that fades IN then out — what a rising mote wants, so it
## materialises out of the floor instead of popping into existence at full alpha.
func _swell_ramp(birth: Color, peak: Color, peak_at: float = 0.35) -> Gradient:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, peak_at, 1.0])
	g.colors = PackedColorArray([Color(birth, 0.0), peak, Color(peak, 0.0)])
	return g


## A child layer that draws with its OWN blend mode by calling back into this
## preset. Returns the layer; [param painter] is handed the layer as its only
## argument so the callback can use its draw_* methods.
##
## A CanvasItem gets exactly one blend mode, so a preset that needs both solid
## geometry and additive light out of _draw() - carved stone under glowing runes -
## physically cannot do it in one node. The alternatives were worse: making the
## whole node additive turns the stone into a lamp, and leaving it mixed makes the
## runes look painted on.
##
## [param layer_z] is RELATIVE to this preset, so a negative value stays under the
## preset's own drawing and everything remains below the wearer.
func _add_draw_layer(painter: Callable, additive: bool = false, layer_z: int = 0) -> Node2D:
	var layer: DrawLayer = DrawLayer.new()
	layer.painter = painter
	layer.z_index = layer_z
	if additive:
		layer.material = _additive()
	add_child(layer)
	_draw_layers.append(layer)
	return layer


## Layers built by [method _add_draw_layer], redrawn with this preset.
var _draw_layers: Array[Node2D] = []


## Host for [method _add_draw_layer]. Owns no state of its own - it exists purely
## to be a second CanvasItem with a different material.
class DrawLayer extends Node2D:
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


## Additive blending, for anything that should read as LIGHT rather than as paint
## (gold bloom, star cores, electric arcs). Never use it on the dark effects —
## additive on a blood pool turns it pink.
func _additive() -> CanvasItemMaterial:
	var m: CanvasItemMaterial = CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


## A shader quad laid flat on the ground under the wearer, sized in pixels and
## already squashed. Returns the ColorRect so the caller can hold its material.
##
## The quad is a plain ColorRect rather than a Sprite2D because these shaders paint
## every pixel themselves from UV — there is no texture to sample, so a texture
## node would only add an upload.
func _add_floor_shader(shader: Shader, diameter: float) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	rect.size = Vector2(diameter, diameter)
	# Centre it on the feet, then squash the whole quad so a circle authored in UV
	# space lands as a floor ellipse without every shader needing to know about it.
	rect.position = Vector2(-diameter * 0.5, -diameter * 0.5 * GROUND_SQUASH)
	rect.scale = Vector2(1.0, GROUND_SQUASH)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


## True when this preset is worn by the player at the keyboard. Screen-space
## layers MUST gate on this: a full-screen overlay driven by a stranger's cosmetic
## would let anyone tint another player's screen.
func _is_local_wearer() -> bool:
	# A wardrobe preview borrows the local player as its wearer so the effect has
	# a real body to work from, which would otherwise make every preview count as
	# owner-worn and mount a second screen overlay on top of the equipped one.
	if is_preview or wearer == null or not is_instance_valid(ClientState):
		return false
	return ClientState.local_player == wearer


## Roughly a screen and a half at the game's zoom. Past this a wearer is off
## camera for any realistic viewport, so producing for them is pure waste.
const CULL_RADIUS_PX: float = 420.0


## True when the local player is close enough to this wearer that expensive
## layers are worth producing. The same distance test [SfxPool] uses to drop
## out-of-earshot sounds.
##
## This gates PRODUCTION, never visibility. Hiding the preset would take its
## world-space children with it - visibility is hierarchical even for top_level
## nodes - so a player walking away would blink out the fissures and after-images
## they already left on the floor behind them. Stopping the source instead lets
## everything already in the world finish its own life normally.
##
## Fails OPEN when there is no local player: that is the vault preview and the
## first frames after a map load, where rendering nothing would be the bug.
func _viewer_in_range(radius_px: float = CULL_RADIUS_PX) -> bool:
	# A preview sits in UI space, where its global_position is a screen coordinate
	# and the distance to the local player is meaningless - and enormous, so the
	# test would cull the whole wardrobe.
	if is_preview:
		return true
	if not is_instance_valid(ClientState):
		return true
	var viewer: Node2D = ClientState.local_player
	if not is_instance_valid(viewer):
		return true
	return viewer.global_position.distance_squared_to(global_position) <= radius_px * radius_px


## Emission points spread along an arc of the ground ellipse, for emitters that
## must rise OUT OF the ring rather than out of a sphere around the wearer.
##
## CPUParticles2D has no ellipse emission shape, and the sphere shape it does have
## puts as many particles in the middle as at the edge — which is why a naive
## "rising motes" layer always looks like a column through the body instead of a
## ring around it. Feeding explicit points is the fix, and it is also the only way
## to emit from HALF a ring (see [AuraEmberfrostPreset]).
func _arc_points(count: int, radius: float, from_angle: float, to_angle: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var steps: int = maxi(1, count)
	for i: int in steps:
		var k: float = float(i) / float(steps)
		out.append(_ground_point(lerpf(from_angle, to_angle, k), radius))
	return out


## Emission points all the way around the ground ellipse.
func _ring_points(count: int, radius: float) -> PackedVector2Array:
	return _arc_points(count, radius, 0.0, TAU * (1.0 - 1.0 / float(maxi(1, count))))
