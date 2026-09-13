extends GroundCompanionPreset
## HONEY BEAR. A round brown bear cub that waddles after the wearer. When they
## stop it plops down on its bottom with a pot of honey between its feet, dips
## a paw in and licks it, over and over - while two little bees buzz round the
## pot trying to get their honey back.
##
## DETAILED PASS. Painted on a [PixelCanvas] (waddle A, waddle B, sit, sit with
## paw up): brown fur in three tones, a lighter tummy and muzzle, round ears
## with inner patches, a shiny eye, a clay honey pot with a dark rim and gold
## honey. Live on top: honey dripping off the pot, and the two bees.
##
## REACTS: while its owner fishes, it fishes too - every couple of seconds a fish
## leaps out of the water in front of it, it swipes a paw, and catches it.

const FUR: Color = Color(0.62, 0.42, 0.26)
const FUR_LIGHT: Color = Color(0.84, 0.66, 0.46)
const EAR_IN: Color = Color(0.86, 0.62, 0.52)
const NOSE: Color = Color(0.14, 0.09, 0.07)
const POT: Color = Color(0.82, 0.52, 0.24)
const HONEY: Color = Color(1.0, 0.78, 0.22)
const BEE: Color = Color(1.0, 0.86, 0.20)
const SIT_AFTER_S: float = 0.7
const FISH: Color = Color(0.70, 0.84, 0.96)
const CATCH_EVERY_S: float = 2.2

const W: int = 24
const H: int = 21


func _build() -> void:
	hop_peak = 1.5
	hop_rate = 3.0
	add_body_layer(_paint_bear, false, 0)


static func _frame(pose: String) -> ImageTexture:
	return PixelCanvas.cached("honeybear_" + pose, W, H, func(c: PixelCanvas) -> void:
		var hd: Vector2
		if pose.begins_with("sit"):
			var paw_up: bool = pose == "sit_lick"
			# Honey pot between the feet.
			c.ball(15.5, 18.0, 3.4, 3.0, POT)
			# Round sitting body, legs out front.
			c.ball(9.5, 14.5, 6.0, 5.4, FUR)
			c.ball(10.5, 16.0, 3.8, 3.2, FUR_LIGHT, 0.15, 0.1)
			c.ball(12.5, 19.5, 2.2, 1.4, FUR)
			hd = Vector2(11.0, 6.5)
			if paw_up:
				c.ball(15.0, 10.0, 1.8, 1.8, FUR)
			else:
				c.ball(14.5, 14.5, 1.8, 1.8, FUR)
		else:
			var step: float = 1.0 if pose == "waddle_a" else -1.0
			c.rect(6.0 - step, 16.0, 3.0, 5.0, FUR)
			c.rect(13.0 + step, 16.0, 3.0, 5.0, FUR)
			c.ball(10.5, 13.0, 7.0, 5.0, FUR)
			c.ball(12.0, 15.0, 4.0, 2.6, FUR_LIGHT, 0.15, 0.1)
			hd = Vector2(17.0, 8.0)
		# Round ears.
		c.ball(hd.x - 3.2, hd.y - 3.2, 1.8, 1.8, FUR)
		c.ball(hd.x + 2.6, hd.y - 3.4, 1.8, 1.8, FUR)
		c.ball(hd.x, hd.y, 4.4, 4.0, FUR)
		c.ball(hd.x + 2.4, hd.y + 1.6, 2.2, 1.7, FUR_LIGHT, 0.12, 0.05)
		c.finish(0.18, 0.24, 0.58)
		# Details.
		c.px(hd.x - 3.2, hd.y - 3.2, EAR_IN)
		c.px(hd.x + 2.6, hd.y - 3.4, EAR_IN)
		c.eye(hd.x + 0.5, hd.y - 1.5, 2, 2)
		c.rect(hd.x + 3.5, hd.y + 0.5, 2.0, 1.0, NOSE)
		c.px(hd.x - 1.5, hd.y + 1.5, Color(1.0, 0.60, 0.62))
		if pose.begins_with("sit"):
			c.rect(12.5, 15.5, 6.0, 1.0, POT.darkened(0.45))   # pot rim
			c.rect(13.5, 15.0, 4.0, 1.0, HONEY)                 # honey in the pot
			if pose == "sit_lick":
				c.px(15.0, 9.0, HONEY)                          # honey on the paw
				c.px(hd.x + 3.5, hd.y + 2.5, Color(1.0, 0.50, 0.56))   # tongue
	)


## A fish leaping from the water in front of the bear into its raised paw, then
## gone (eaten) with a sparkle.
func _paint_fish_catch(layer: VfxDrawLayer, feet: Vector2, f: float, t: float) -> void:
	if t > 0.5:
		if t < 0.62:
			var sp: Vector2 = feet + Vector2(3.0 * f, -14.0)
			layer.draw_rect(Rect2(sp.round() + Vector2(-2, 0), Vector2(1, 1)), Color(1, 1, 0.8, 0.9))
			layer.draw_rect(Rect2(sp.round() + Vector2(2, -1), Vector2(1, 1)), Color(1, 1, 0.8, 0.9))
		return
	var k: float = t / 0.5
	# Paw up at canvas (15, 10) -> local (3, -11).
	var from: Vector2 = feet + Vector2(11.0 * f, 1.0)
	var to: Vector2 = feet + Vector2(3.0 * f, -12.0)
	var at: Vector2 = (from.lerp(to, k) + Vector2(0.0, -sin(k * PI) * 6.0)).round()
	layer.draw_rect(Rect2(at, Vector2(3, 2)), FISH)
	layer.draw_rect(Rect2(at + Vector2(3.0 if f > 0.0 else -1.0, 0.0), Vector2(1, 2)), FISH.darkened(0.3))
	layer.draw_rect(Rect2(at + Vector2(0.0 if f > 0.0 else 2.0, 0.0), Vector2(1, 1)), FACE_DARK)
	# A splash ring where it jumped from.
	if k < 0.3:
		layer.draw_rect(Rect2((from + Vector2(-2, 1)).round(), Vector2(5, 1)), Color(FISH, 0.8 * (1.0 - k / 0.3)))


func _paint_bear(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 9.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var sitting: bool = still_for >= SIT_AFTER_S
	var pose: String
	var fishing: bool = activity() == &"fishing_rod"
	var catch_t: float = fposmod(_elapsed, CATCH_EVERY_S) / CATCH_EVERY_S
	if sitting and fishing:
		# Paw up just as the fish reaches it.
		pose = "sit_lick" if catch_t > 0.25 and catch_t < 0.55 else "sit"
	elif sitting:
		pose = "sit_lick" if fposmod(still_for, 1.6) < 0.7 else "sit"
	else:
		pose = "waddle_a" if hop_phase < 0.5 else "waddle_b"
	var feet: Vector2 = Vector2(0.0, -hop_height)
	PixelCanvas.draw_sprite(layer, _frame(pose), feet, facing)
	if not sitting:
		return
	var f: float = facing
	if fishing:
		_paint_fish_catch(layer, feet, f, catch_t)
	# Pot at canvas (15.5, 18) -> sprite-local (3.5, -3).
	var pot: Vector2 = feet + Vector2(3.5 * f, -3.0)
	# A drip of honey sliding down the side of the pot.
	var drip: float = fposmod(still_for * 0.8, 1.0)
	layer.draw_rect(Rect2(roundf(pot.x + 2.0 * f), roundf(pot.y - 2.0 + drip * 4.0), 1.0, 1.0 + roundf(drip)), HONEY)
	# Two bees circling the pot.
	for i: int in 2:
		var a: float = _elapsed * (3.0 + float(i)) + float(i) * PI
		var at: Vector2 = pot + Vector2(cos(a) * 7.0, -6.0 + sin(a * 2.0) * 2.5)
		var p: Vector2 = at.round()
		layer.draw_rect(Rect2(p, Vector2(2, 1)), BEE)
		layer.draw_rect(Rect2(p + Vector2(1, 0), Vector2(1, 1)), NOSE)
		if fposmod(_elapsed * 20.0, 1.0) < 0.5:
			layer.draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 1)), Color(1, 1, 1, 0.8))
