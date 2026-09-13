extends GroundCompanionPreset
## CORGI. A fluffy corgi that trots after the wearer on its stubby legs, ears up,
## kicking up little puffs of dust. When they stop it sits down beside them,
## tongue out, tail wagging - and every so often gives a happy little hop with a
## heart.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## DETAILED PASS. Painted on a [PixelCanvas] at native resolution: three-tone
## fur on every shape, a coloured outline, the white blaze, muzzle, chest and
## socks, inner ears, a shiny eye and a pink tongue - built once per frame
## (trot A, trot B, sit, sit-wag) and cached. Motion on top is procedural:
## trot bounce, a squash on landing, the wag, dust and hearts.

const FUR: Color = Color(0.93, 0.56, 0.24)
const FUR_DEEP: Color = Color(0.78, 0.40, 0.14)
const WHITE: Color = Color(1.0, 0.97, 0.92)
const EAR_IN: Color = Color(0.96, 0.66, 0.60)
const NOSE: Color = Color(0.12, 0.08, 0.08)
const TONGUE: Color = Color(1.0, 0.46, 0.56)
const BLUSH: Color = Color(1.0, 0.55, 0.62)
const HEART: Color = Color(1.0, 0.40, 0.58)
const DUST: Color = Color(0.80, 0.74, 0.62)
const SIT_AFTER_S: float = 0.7
const HAPPY_EVERY_S: float = 4.2

const W: int = 24
const H: int = 18

var _dust: CPUParticles2D


func _build() -> void:
	hop_peak = 2.0
	hop_rate = 4.2
	add_body_layer(_paint_corgi, false, 0)
	var d: CPUParticles2D = CPUParticles2D.new()
	d.amount = 8
	d.lifetime = 0.5
	d.local_coords = false
	d.texture = VfxTextures.puff(8)
	d.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	d.direction = Vector2(0, -1)
	d.spread = 70.0
	d.gravity = Vector2(0, -8.0)
	d.initial_velocity_min = 4.0
	d.initial_velocity_max = 10.0
	d.scale_amount_min = 0.4
	d.scale_amount_max = 0.7
	d.color_ramp = _fade_ramp(DUST, 0.55)
	body.add_child(d)
	_dust = d


func _tick(delta: float) -> void:
	super(delta)
	_dust.emitting = is_hopping()


## One frame of the corgi, facing right, feet on the bottom row.
static func _frame(pose: String) -> ImageTexture:
	return PixelCanvas.cached("corgi_" + pose, W, H, func(c: PixelCanvas) -> void:
		var sit: bool = pose.begins_with("sit")
		var wag: float = 1.0 if pose == "sit_wag" else 0.0
		# --- Silhouette, back to front.
		if sit:
			# Tail: a fluffy stub low behind, wagging between two positions.
			c.ball(4.5, 12.0 - wag * 2.0, 2.4, 1.8, FUR)
			# Haunch folded under, body upright-ish.
			c.ball(8.5, 13.0, 5.0, 3.6, FUR)
			c.ball(11.0, 10.0, 4.6, 4.2, FUR)
			# Front legs straight down, white socks.
			c.rect(12.0, 12.0, 2.0, 6.0, FUR_DEEP)
			c.rect(14.5, 12.0, 2.0, 6.0, FUR)
			c.rect(12.0, 16.0, 2.0, 2.0, WHITE)
			c.rect(14.5, 16.0, 2.0, 2.0, WHITE)
			c.rect(5.0, 16.0, 6.0, 2.0, FUR_DEEP)
		else:
			var stride: float = 1.0 if pose == "trot_a" else -1.0
			c.ball(3.5, 8.5, 2.4, 1.8, FUR)
			# Long low body - the whole point of a corgi.
			c.ball(10.0, 10.5, 7.6, 4.0, FUR)
			# Four stubby legs, near pair lighter, far pair deeper; they swap on stride.
			c.rect(5.0 - stride, 12.0, 2.0, 6.0, FUR_DEEP)
			c.rect(14.0 + stride, 12.0, 2.0, 6.0, FUR_DEEP)
			c.rect(7.0 + stride, 12.0, 2.0, 6.0, FUR)
			c.rect(15.5 - stride, 12.0, 2.0, 6.0, FUR)
			for lx: float in [5.0 - stride, 14.0 + stride, 7.0 + stride, 15.5 - stride]:
				c.rect(lx, 16.0, 2.0, 2.0, WHITE)
		# White chest and belly fluff.
		var chest: Vector2 = Vector2(15.0, 12.0) if not sit else Vector2(14.0, 11.5)
		c.ball(chest.x, chest.y, 3.0, 2.8, WHITE, 0.14, 0.05)
		c.ball(10.0 if not sit else 10.0, 13.5, 4.0, 1.6, WHITE, 0.14, 0.05)
		# Head.
		var hd: Vector2 = Vector2(18.5, 7.0) if not sit else Vector2(17.0, 5.5)
		# Big upright ears.
		c.tri(hd + Vector2(-4.5, -1.5), hd + Vector2(-1.5, -2.5), hd + Vector2(-3.5, -7.0), FUR_DEEP)
		c.tri(hd + Vector2(-0.5, -2.5), hd + Vector2(2.5, -1.5), hd + Vector2(0.5, -7.0), FUR)
		c.ball(hd.x, hd.y, 4.4, 3.8, FUR)
		# White blaze up the face and the muzzle.
		c.rect(hd.x - 0.5, hd.y - 3.5, 1.0, 3.0, WHITE)
		c.ball(hd.x + 2.5, hd.y + 1.6, 2.8, 2.0, WHITE, 0.12, 0.05)
		c.finish()
		# --- Details after shading.
		c.tri(hd + Vector2(-3.8, -2.2), hd + Vector2(-2.2, -2.6), hd + Vector2(-3.3, -5.5), EAR_IN)
		c.tri(hd + Vector2(0.0, -2.6), hd + Vector2(1.6, -2.2), hd + Vector2(0.5, -5.5), EAR_IN)
		c.eye(hd.x + 0.5, hd.y - 1.5, 2, 2)
		c.rect(hd.x + 4.5, hd.y + 0.5, 2.0, 1.0, NOSE)
		c.px(hd.x + 4.5, hd.y + 0.5, Color(0.5, 0.45, 0.5))
		c.rect(hd.x + 2.0, hd.y + 2.5, 2.0, 1.0, FUR_DEEP.darkened(0.4))   # smile line
		c.px(hd.x - 1.5, hd.y + 1.0, BLUSH)
		c.px(hd.x - 0.5, hd.y + 1.0, BLUSH)
		if sit:
			# Tongue out: happy panting.
			c.rect(hd.x + 2.5, hd.y + 3.0, 2.0, 2.0, TONGUE)
			c.px(hd.x + 2.5, hd.y + 4.0, TONGUE.darkened(0.2))
	)


func _paint_corgi(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 9.0)
	var sitting: bool = still_for >= SIT_AFTER_S
	var pose: String
	var lift: float = hop_height
	if sitting:
		pose = "sit_wag" if fposmod(_elapsed * 7.0, 1.0) < 0.5 else "sit"
		# The happy hop.
		var t: float = fposmod(still_for, HAPPY_EVERY_S)
		if t < 0.35:
			lift = sin(t / 0.35 * PI) * 4.0
	else:
		pose = "trot_a" if hop_phase < 0.5 else "trot_b"
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	PixelCanvas.draw_sprite(layer, _frame(pose), Vector2(0.0, -lift), facing)
	# A heart after each happy hop.
	if sitting:
		var t: float = fposmod(still_for, HAPPY_EVERY_S)
		if t < 1.3:
			var k: float = t / 1.3
			var at: Vector2 = Vector2(6.0 * facing, -22.0 - k * 8.0).round()
			var col: Color = Color(HEART, 1.0 - k)
			layer.draw_rect(Rect2(at.x - 2.0, at.y, 2.0, 1.0), col)
			layer.draw_rect(Rect2(at.x + 1.0, at.y, 2.0, 1.0), col)
			layer.draw_rect(Rect2(at.x - 2.0, at.y + 1.0, 5.0, 1.0), col)
			layer.draw_rect(Rect2(at.x - 1.0, at.y + 2.0, 3.0, 1.0), col)
			layer.draw_rect(Rect2(at.x, at.y + 3.0, 1.0, 1.0), col)
