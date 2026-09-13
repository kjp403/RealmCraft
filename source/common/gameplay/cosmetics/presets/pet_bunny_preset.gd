extends GroundCompanionPreset
## BUNNY. A fluffy cream bunny that bounds after the wearer in long leaps, ears
## sweeping back mid-air and a cotton tail bobbing. When they stop it sits up
## beside them and nibbles a carrot down to nothing - then a fresh one pops into
## its paws with a sparkle, and it starts again.
##
## DETAILED PASS. Painted on a [PixelCanvas] (crouch, leap, sit): cream fur in
## three tones, long ears with pink insides, a cotton tail, big hind feet and a
## shiny eye. Live on top: the carrot (drawn so it can shrink bite by bite), the
## chewing wiggle, the sparkle, and the leap itself.

const FUR: Color = Color(0.97, 0.93, 0.86)
const FUR_SHADE: Color = Color(0.84, 0.76, 0.70)
const EAR_IN: Color = Color(1.0, 0.70, 0.76)
const NOSE: Color = Color(1.0, 0.55, 0.66)
const CARROT: Color = Color(1.0, 0.56, 0.16)
const CARROT_DARK: Color = Color(0.80, 0.36, 0.08)
const LEAF: Color = Color(0.40, 0.76, 0.30)
const SPARK: Color = Color(1.0, 1.0, 0.80)
const SIT_AFTER_S: float = 0.7
const CARROT_S: float = 5.0

const W: int = 20
const H: int = 20


func _build() -> void:
	hop_peak = 7.0
	hop_rate = 2.4
	add_body_layer(_paint_bunny, false, 0)


static func _frame(pose: String) -> ImageTexture:
	return PixelCanvas.cached("bunny_" + pose, W, H, func(c: PixelCanvas) -> void:
		var hd: Vector2
		match pose:
			"leap":
				# Stretched out: hind legs kicked back, ears swept flat.
				c.ball(2.5, 15.5, 3.0, 1.3, FUR_SHADE)
				c.ball(3.0, 12.0, 2.0, 2.0, FUR)            # cotton tail
				c.ball(9.0, 13.0, 6.5, 3.4, FUR)
				c.rect(15.0, 14.0, 2.0, 3.0, FUR_SHADE)      # front paws reaching
				hd = Vector2(15.5, 9.5)
				c.ball(hd.x - 4.5, hd.y - 2.0, 4.2, 1.2, FUR)
				c.ball(hd.x - 4.0, hd.y - 0.2, 3.8, 1.1, FUR_SHADE)
			"sit":
				# Sat up on its haunches, big foot flat, paws up to hold a carrot.
				c.ball(3.5, 15.0, 2.0, 2.0, FUR)
				c.ball(8.0, 15.0, 5.6, 4.5, FUR)
				c.ball(9.5, 18.8, 3.8, 1.2, FUR_SHADE)
				c.ball(10.5, 10.5, 3.6, 3.8, FUR)
				c.rect(12.0, 11.0, 2.0, 2.0, FUR_SHADE)      # paws
				hd = Vector2(12.0, 6.5)
				c.ball(hd.x - 2.0, hd.y - 5.5, 1.3, 4.2, FUR)
				c.ball(hd.x + 0.5, hd.y - 6.0, 1.3, 4.4, FUR)
			_:
				# Crouched, gathering for the next leap.
				c.ball(3.0, 13.0, 2.0, 2.0, FUR)
				c.ball(8.5, 14.5, 5.8, 4.2, FUR)
				c.ball(9.5, 18.8, 4.0, 1.2, FUR_SHADE)
				hd = Vector2(14.0, 10.5)
				c.ball(hd.x - 2.5, hd.y - 5.0, 1.3, 4.2, FUR)
				c.ball(hd.x, hd.y - 5.5, 1.3, 4.4, FUR)
		c.ball(hd.x, hd.y, 3.8, 3.3, FUR)
		c.finish(0.1, 0.2, 0.55)
		# Ear insides.
		match pose:
			"leap":
				c.line(Vector2(hd.x - 7.5, hd.y - 2.0), Vector2(hd.x - 2.5, hd.y - 2.0), EAR_IN)
			"sit":
				c.line(Vector2(hd.x - 2.0, hd.y - 8.5), Vector2(hd.x - 2.0, hd.y - 3.5), EAR_IN)
				c.line(Vector2(hd.x + 0.5, hd.y - 9.0), Vector2(hd.x + 0.5, hd.y - 3.5), EAR_IN)
			_:
				c.line(Vector2(hd.x - 2.5, hd.y - 8.0), Vector2(hd.x - 2.5, hd.y - 3.0), EAR_IN)
				c.line(Vector2(hd.x, hd.y - 8.5), Vector2(hd.x, hd.y - 3.0), EAR_IN)
		c.eye(hd.x + 0.5, hd.y - 1.0, 2, 2)
		c.px(hd.x + 3.0, hd.y + 0.5, NOSE)
		c.px(hd.x - 1.5, hd.y + 1.0, Color(1.0, 0.60, 0.70))
	)


func _paint_bunny(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 8.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var sitting: bool = still_for >= SIT_AFTER_S
	var pose: String = "sit" if sitting else ("leap" if hop_height > 2.0 else "crouch")
	var feet: Vector2 = Vector2(0.0, -hop_height)
	var chew: float = 0.0
	if sitting:
		chew = roundf(absf(sin(still_for * 11.0)) * 0.8)
	PixelCanvas.draw_sprite(layer, _frame(pose), feet + Vector2(0.0, -chew * 0.0), facing)
	if not sitting:
		return
	# The carrot: held in the paws, eaten from the top down.
	var t: float = fposmod(still_for - SIT_AFTER_S, CARROT_S)
	var left: float = 1.0 - clampf(t / (CARROT_S * 0.85), 0.0, 1.0)
	var f: float = facing
	# Paws at canvas (12..13, 11..12) -> sprite-local (2, -9).
	var base: Vector2 = feet + Vector2(3.0 * f, -8.0)
	var length: float = roundf(6.0 * left)
	if length >= 1.0:
		for i: int in int(length):
			var w: float = 2.0 if i < 3 else 1.0
			layer.draw_rect(Rect2(base.x - (0.0 if f > 0.0 else w - 1.0) + float(i) * 0.0, base.y - float(i) - chew, w, 1.0), CARROT if i % 2 == 0 else CARROT_DARK)
		# Leaves only while the top is still on.
		if left > 0.8:
			var top: Vector2 = base + Vector2(0.0, -length - chew)
			layer.draw_rect(Rect2(top.x - 1.0, top.y - 2.0, 1.0, 2.0), LEAF)
			layer.draw_rect(Rect2(top.x + 1.0, top.y - 2.0, 1.0, 2.0), LEAF)
			layer.draw_rect(Rect2(top.x, top.y - 3.0, 1.0, 3.0), LEAF)
	# A fresh carrot arrives with a sparkle.
	if t < 0.3 and still_for > SIT_AFTER_S + 1.0:
		var k: float = t / 0.3
		var sp: Vector2 = base + Vector2(0, -4)
		layer.draw_rect(Rect2(sp.x - 2.0 - k * 2.0, sp.y, 1.0, 1.0), Color(SPARK, 1.0 - k))
		layer.draw_rect(Rect2(sp.x + 2.0 + k * 2.0, sp.y, 1.0, 1.0), Color(SPARK, 1.0 - k))
		layer.draw_rect(Rect2(sp.x, sp.y - 2.0 - k * 2.0, 1.0, 1.0), Color(SPARK, 1.0 - k))
