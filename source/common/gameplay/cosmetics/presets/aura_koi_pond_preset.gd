extends CosmeticPreset
## KOI POND. A small still pool under the wearer's feet with two koi circling in
## it and the wearer's own reflection wobbling on the surface.
##
## PROTOTYPE - not registered yet; judged in the showcase GIF first.
##
## The reflection is the hook, and it is the Chrono Echo trick again: it reads
## the wearer's CURRENT sprite frame, so every skin, dye and run cycle is
## reflected with no art of its own. It is a real second Sprite2D flipped
## vertically, NOT a screen read - hint_screen_texture paints black in 2D here.
##
##   WATER       two normal-blend ellipses, deep then surface.
##   REFLECTION  flipped wearer frame, clipped to the pool (pool_reflection.gdshader).
##   KOI         drawn fish swimming the rim, tails flicking.
##   RIPPLES     rings from a fish rising, and from the feet at each step.

const SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/pool_reflection.gdshader")

const POOL_R: float = 27.0
const DEEP: Color = Color(0.07, 0.22, 0.28)
const SURFACE: Color = Color(0.20, 0.50, 0.58)
const SHINE: Color = Color(0.78, 0.95, 1.0)
const KOI_A: Color = Color(1.0, 0.52, 0.18)
const KOI_B: Color = Color(0.97, 0.95, 0.90)
const KOI_PERIOD_S: float = 7.0
const RIPPLE_PERIOD_S: float = 1.7
const RIPPLE_LIFE_S: float = 1.2

var _reflection: Sprite2D
var _material: ShaderMaterial
var _light: VfxDrawLayer

## Render-tool seam, as on [TrailChronoEchoPreset].
var sprite_source: AnimatedSprite2D


func _build() -> void:
	_reflection = Sprite2D.new()
	_reflection.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_reflection.flip_v = true
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"water", SURFACE)
	_material.set_shader_parameter(&"alpha", 0.6)
	_material.set_shader_parameter(&"pool_radius", Vector2(POOL_R, POOL_R))
	_material.set_shader_parameter(&"pool_centre", Vector2(0.0, 2.0))
	_reflection.material = _material
	# Squashed onto the floor like everything else on the ground plane.
	_reflection.scale = Vector2(1.0, GROUND_SQUASH)
	add_child(_reflection)
	# Koi over the reflection, light over both - by TREE ORDER, all at z 0, so
	# the whole pond stays under the wearer. A raised z put the fish over the feet.
	_add_draw_layer(_paint_koi, false, 0)
	_light = _add_draw_layer(_paint_light, true, 0)


func _tick(_delta: float) -> void:
	var source: AnimatedSprite2D = _source()
	if source == null or source.sprite_frames == null:
		_reflection.visible = false
		return
	_reflection.visible = true
	_reflection.texture = source.sprite_frames.get_frame_texture(source.animation, source.frame)
	_reflection.flip_h = source.flip_h
	# Body offset is (0,-30) with feet on the origin; flipped, the feet stay on
	# the origin and the head hangs below them.
	_reflection.offset = Vector2(source.offset.x, -source.offset.y)


func _source() -> AnimatedSprite2D:
	if is_instance_valid(sprite_source):
		return sprite_source
	if wearer == null or not is_instance_valid(wearer):
		return null
	return wearer.animated_sprite


func _draw() -> void:
	_use_ground_plane()
	draw_circle(Vector2.ZERO, POOL_R + 2.0, Color(DEEP, 0.35))
	draw_circle(Vector2.ZERO, POOL_R, Color(DEEP, 0.75))
	draw_circle(Vector2.ZERO, POOL_R * 0.8, Color(SURFACE, 0.35))


func _paint_koi(layer: VfxDrawLayer) -> void:
	for f: int in 2:
		var dir: float = 1.0 if f == 0 else -1.0
		var a: float = dir * _elapsed * TAU / (KOI_PERIOD_S + float(f) * 1.3) + float(f) * PI
		var r: float = POOL_R * (0.62 if f == 0 else 0.45)
		# Spine: head first, each segment a little further back round the circle.
		for s: int in range(5, -1, -1):
			var back: float = a - dir * float(s) * 0.11
			var wig: float = sin(_elapsed * 9.0 - float(s) * 0.9) * 0.9 * float(s) / 5.0
			var at: Vector2 = Vector2(cos(back) * (r + wig), sin(back) * (r + wig) * GROUND_SQUASH)
			var size: float = [1.5, 1.6, 1.35, 1.05, 0.75, 1.2][s]
			var col: Color = KOI_A if (s + f) % 3 != 1 else KOI_B
			if s == 5:
				col = Color(KOI_A, 0.8)   # tail fin
			layer.draw_circle(at, size, Color(col, 0.92))


func _paint_light(layer: VfxDrawLayer) -> void:
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	# Rim highlight on the far edge, where a real pool catches the sky.
	layer.draw_arc(Vector2.ZERO, POOL_R - 1.0, PI * 1.1, PI * 1.9, 24, Color(SHINE, 0.35), 1.0)
	# Rings: a fish rising somewhere on the pool, on a slow clock.
	for k: int in 2:
		var phase: float = fposmod(_elapsed + float(k) * RIPPLE_PERIOD_S * 0.5, RIPPLE_PERIOD_S)
		if phase > RIPPLE_LIFE_S:
			continue
		var n: float = floor((_elapsed + float(k) * RIPPLE_PERIOD_S * 0.5) / RIPPLE_PERIOD_S)
		var spot: Vector2 = Vector2(sin(n * 12.3 + float(k)), cos(n * 7.7 + float(k))) * POOL_R * 0.5
		var t: float = phase / RIPPLE_LIFE_S
		layer.draw_arc(spot, 2.0 + t * 9.0, 0.0, TAU, 20, Color(SHINE, 0.45 * (1.0 - t)), 1.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
