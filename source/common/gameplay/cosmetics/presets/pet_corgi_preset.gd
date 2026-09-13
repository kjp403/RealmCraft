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
##
## REACTS TO ITS OWNER (see [CompanionPreset.owner_swung]):
##   mining (pickaxe)       digs beside you, dirt flying
##   woodcutting (axe)      sits proudly holding a stick
##   fishing (rod)          sits with a tiny rod in its mouth, bobber bobbing
##   harvesting (sickle)    sits holding a flower
##   fighting               hides behind you, trembling, with a sweat drop
##   fight over             a victory hop with hearts
##   level-up               spins round in the air with confetti

const FUR: Color = Color(0.93, 0.56, 0.24)
const FUR_DEEP: Color = Color(0.78, 0.40, 0.14)
const WHITE: Color = Color(1.0, 0.97, 0.92)
const EAR_IN: Color = Color(0.96, 0.66, 0.60)
const NOSE: Color = Color(0.12, 0.08, 0.08)
const TONGUE: Color = Color(1.0, 0.46, 0.56)
const BLUSH: Color = Color(1.0, 0.55, 0.62)
const HEART: Color = Color(1.0, 0.40, 0.58)
const DUST: Color = Color(0.80, 0.74, 0.62)
const DIRT: Color = Color(0.52, 0.38, 0.24)
const STICK: Color = Color(0.56, 0.38, 0.22)
const ROD: Color = Color(0.70, 0.52, 0.30)
const LINE: Color = Color(0.90, 0.92, 0.96, 0.8)
const BOBBER: Color = Color(0.95, 0.25, 0.25)
const STEM: Color = Color(0.36, 0.66, 0.30)
const PETAL: Color = Color(1.0, 0.72, 0.86)
const SWEAT: Color = Color(0.62, 0.84, 1.0)
const CONFETTI: Array[Color] = [Color(1.0, 0.45, 0.55), Color(1.0, 0.86, 0.35), Color(0.45, 0.85, 1.0), Color(0.60, 0.95, 0.55)]
## Sprite-local mouth position in the sit pose (canvas (20, 8) - (12, 18)).
const MOUTH_SIT: Vector2 = Vector2(8.0, -10.0)
const SIT_AFTER_S: float = 0.7
const HAPPY_EVERY_S: float = 4.2

const W: int = 24
const H: int = 18

var _dust: CPUParticles2D
var _dirt: CPUParticles2D


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
	# Dirt kicked up behind it while it digs.
	var dirt: CPUParticles2D = CPUParticles2D.new()
	dirt.amount = 10
	dirt.lifetime = 0.45
	dirt.local_coords = false
	dirt.texture = VfxTextures.pip(2)
	dirt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dirt.direction = Vector2(-1, -1.4)
	dirt.spread = 25.0
	dirt.gravity = Vector2(0, 220.0)
	dirt.initial_velocity_min = 30.0
	dirt.initial_velocity_max = 55.0
	dirt.color = DIRT
	dirt.emitting = false
	body.add_child(dirt)
	_dirt = dirt


func _tick(delta: float) -> void:
	super(delta)
	_dust.emitting = is_hopping() and activity() != &"combat"
	_dirt.emitting = activity() == &"pickaxe"
	# Out from under its front paws, thrown back past its tail.
	_dirt.position = Vector2(4.0 * facing, -3.0)
	_dirt.direction = Vector2(-facing, -1.4)


## Fighting: tuck in right behind the owner, on the far side from where they
## face, and slightly further from the camera so their body hides it.
func target_local(delta: float) -> Vector2:
	if activity() == &"combat":
		var away: float = -signf(_heading.x) if absf(_heading.x) > 0.1 else -1.0
		return Vector2(7.0 * away, -3.0)
	return super(delta)


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
			var stride: float = 1.0 if pose == "trot_a" or pose == "dig_a" else -1.0
			var dig: bool = pose.begins_with("dig")
			c.ball(3.5, 7.0 if dig else 8.5, 2.4, 1.8, FUR)
			# Long low body - the whole point of a corgi.
			c.ball(10.0, 10.5, 7.6, 4.0, FUR)
			# Four stubby legs, near pair lighter, far pair deeper; they swap on stride.
			c.rect(5.0 - stride, 12.0, 2.0, 6.0, FUR_DEEP)
			c.rect(14.0 + stride, 12.0, 2.0, 6.0, FUR_DEEP)
			c.rect(7.0 + stride, 12.0, 2.0, 6.0, FUR)
			c.rect(15.5 - stride, 12.0, 2.0, 6.0, FUR)
			for lx: float in [5.0 - stride, 14.0 + stride, 7.0 + stride, 15.5 - stride]:
				c.rect(lx, 16.0, 2.0, 2.0, WHITE)
			if dig:
				# One front paw raised and scooping, alternating between the frames.
				c.rect(16.0 + stride, 12.0, 2.0, 3.0, FUR)
				c.rect(16.0 + stride, 12.0, 2.0, 1.0, WHITE)
		# White chest and belly fluff.
		var chest: Vector2 = Vector2(15.0, 12.0) if not sit else Vector2(14.0, 11.5)
		c.ball(chest.x, chest.y, 3.0, 2.8, WHITE, 0.14, 0.05)
		c.ball(10.0 if not sit else 10.0, 13.5, 4.0, 1.6, WHITE, 0.14, 0.05)
		# Head.
		var hd: Vector2 = Vector2(18.5, 7.0) if not sit else Vector2(17.0, 5.5)
		if pose.begins_with("dig"):
			hd = Vector2(19.0, 10.0)      # nose down to the dirt
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
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var act: StringName = activity()
	var f: float = facing

	# --- Celebrations outrank everything.
	if celebrating():
		var t: float = celebration_t()
		# Spins in the air: facing flips fast while it hops.
		var spin_f: float = 1.0 if int(t * 14.0) % 2 == 0 else -1.0
		var spin_lift: float = absf(sin(t * PI * 3.0)) * 7.0
		PixelCanvas.draw_sprite(layer, _frame("sit_wag"), Vector2(0.0, -spin_lift), spin_f)
		_confetti(layer, t)
		return
	if cheering():
		var t: float = celebration_t()
		var cheer_lift: float = absf(sin(t * PI * 2.0)) * 5.0
		PixelCanvas.draw_sprite(layer, _frame("sit_wag" if int(t * 10.0) % 2 == 0 else "sit"), Vector2(0.0, -cheer_lift), f)
		_heart(layer, Vector2(6.0 * f, -22.0 - t * 8.0), 1.0 - t)
		return

	match act:
		&"combat":
			# Cowering: low, trembling, a sweat drop.
			var shake: float = 1.0 if fposmod(_elapsed * 30.0, 1.0) < 0.5 else -1.0
			PixelCanvas.draw_sprite(layer, _frame("sit"), Vector2(shake, 1.0), f)
			var drop: Vector2 = Vector2(2.0 * f, -24.0 + fposmod(_elapsed * 2.0, 1.0) * 3.0).round()
			layer.draw_rect(Rect2(drop, Vector2(1, 2)), SWEAT)
			return
		&"pickaxe":
			var dig_frame: String = "dig_a" if fposmod(_elapsed * 8.0, 1.0) < 0.5 else "dig_b"
			PixelCanvas.draw_sprite(layer, _frame(dig_frame), Vector2.ZERO, f)
			return
		&"axe", &"fishing_rod", &"sickle":
			PixelCanvas.draw_sprite(layer, _frame("sit_wag" if fposmod(_elapsed * 5.0, 1.0) < 0.5 else "sit"), Vector2.ZERO, f)
			_held_item(layer, act, f)
			return

	# --- Ordinary following and sitting.
	var sitting: bool = still_for >= SIT_AFTER_S
	var pose: String
	var lift: float = hop_height
	if sitting:
		pose = "sit_wag" if fposmod(_elapsed * 7.0, 1.0) < 0.5 else "sit"
		var happy_t: float = fposmod(still_for, HAPPY_EVERY_S)
		if happy_t < 0.35:
			lift = sin(happy_t / 0.35 * PI) * 4.0
	else:
		pose = "trot_a" if hop_phase < 0.5 else "trot_b"
	PixelCanvas.draw_sprite(layer, _frame(pose), Vector2(0.0, -lift), f)
	if sitting:
		var heart_t: float = fposmod(still_for, HAPPY_EVERY_S)
		if heart_t < 1.3:
			_heart(layer, Vector2(6.0 * f, -22.0 - (heart_t / 1.3) * 8.0), 1.0 - heart_t / 1.3)


## What it holds in its mouth while the owner works a skill.
func _held_item(layer: VfxDrawLayer, act: StringName, f: float) -> void:
	var mouth: Vector2 = Vector2(MOUTH_SIT.x * f, MOUTH_SIT.y)
	match act:
		&"axe":
			# A stick, carried crosswise, very pleased with itself.
			# Two pixels thick with a dark underside: one pixel thick it vanished
			# against the owner's legs.
			var a: Vector2 = (mouth + Vector2(-4.0 * f, 0.0)).round()
			for i: int in 11:
				var x: float = a.x + float(i) * f - (1.0 if f < 0.0 else 0.0)
				var y: float = a.y - roundf(float(i) * 0.2)
				layer.draw_rect(Rect2(x, y, 1.0, 1.0), STICK.lightened(0.15))
				layer.draw_rect(Rect2(x, y + 1.0, 1.0, 1.0), STICK.darkened(0.35))
			# A twig and a leaf still on it.
			layer.draw_rect(Rect2(a.x + 7.0 * f, a.y - 3.0, 1.0, 2.0), STICK)
			layer.draw_rect(Rect2(a.x + 7.0 * f, a.y - 4.0, 1.0, 1.0), STEM)
		&"fishing_rod":
			# A tiny rod angled up and out, line down to a bobber that bobs and,
			# now and then, dunks.
			var tip: Vector2 = (mouth + Vector2(6.0 * f, -6.0)).round()
			layer.draw_line(mouth.round(), tip, ROD, 1.0)
			var dunk: float = 2.0 if fposmod(_elapsed, 2.6) < 0.25 else 0.0
			var bob: Vector2 = (tip + Vector2(2.0 * f, 12.0 + sin(_elapsed * 3.0) * 1.0 + dunk)).round()
			layer.draw_line(tip, bob, LINE, 1.0)
			layer.draw_rect(Rect2(bob.x - 1.0, bob.y, 2.0, 1.0), BOBBER)
			layer.draw_rect(Rect2(bob.x - 1.0, bob.y + 1.0, 2.0, 1.0), Color.WHITE)
		&"sickle":
			# A flower held by the stem.
			var head: Vector2 = (mouth + Vector2(3.0 * f, -4.0)).round()
			layer.draw_line(mouth.round(), head, STEM, 1.0)
			for d: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				layer.draw_rect(Rect2(head + d, Vector2.ONE), PETAL)
			layer.draw_rect(Rect2(head, Vector2.ONE), Color(1.0, 0.9, 0.4))


func _heart(layer: VfxDrawLayer, at_v: Vector2, alpha: float) -> void:
	var at: Vector2 = at_v.round()
	var col: Color = Color(HEART, clampf(alpha, 0.0, 1.0))
	layer.draw_rect(Rect2(at.x - 2.0, at.y, 2.0, 1.0), col)
	layer.draw_rect(Rect2(at.x + 1.0, at.y, 2.0, 1.0), col)
	layer.draw_rect(Rect2(at.x - 2.0, at.y + 1.0, 5.0, 1.0), col)
	layer.draw_rect(Rect2(at.x - 1.0, at.y + 2.0, 3.0, 1.0), col)
	layer.draw_rect(Rect2(at.x, at.y + 3.0, 1.0, 1.0), col)


## Confetti bursting up and fluttering down over a level-up.
func _confetti(layer: VfxDrawLayer, t: float) -> void:
	for i: int in 14:
		var a: float = float(i) * 2.399
		var spread: float = 6.0 + fposmod(float(i) * 7.1, 9.0)
		var up: float = sin(minf(t * 2.0, 1.0) * PI * 0.5) * (18.0 + fposmod(float(i) * 3.7, 8.0))
		var fall: float = maxf(0.0, t - 0.4) * 22.0
		var at: Vector2 = Vector2(cos(a) * spread, -12.0 - up + fall).round()
		var flip: bool = fposmod(_elapsed * 10.0 + float(i), 1.0) < 0.5
		layer.draw_rect(Rect2(at, Vector2(1.0 if flip else 2.0, 1.0)), Color(CONFETTI[i % CONFETTI.size()], 1.0 - maxf(0.0, t - 0.7) / 0.3))
