extends GroundCompanionPreset
## STARRY CAT. A black cat whose fur is full of tiny twinkling stars, a crescent
## moon charm on its collar. It pads after the wearer with its tail up, and when
## they stop it curls into a loaf beside them, tail flicking, and gives them a
## slow, glowing, contented blink.
##
## DETAILED PASS. Painted on a [PixelCanvas] (walk A, walk B, loaf, loaf with
## the tail flicked): midnight fur in three tones, pointed ears with pink
## insides, whisker pixels, a gold moon charm and a coloured outline. Live on
## top: stars twinkling in the fur at fixed spots, eyes that glow and slow-blink,
## and a faint starlight glow.
##
## REACTS: in a fight it puffs up - standing, back arched, every star in its fur
## flaring at once - while it hides behind its owner. While its owner fishes a
## little thought bubble with a fish in it floats over its head.

## Has reactions of its own beyond the shared hide / cheer / level-up. The Vault
## reads this to shelve the pet under "Reactive Pets" (see cosmetics_menu.gd).
const THEMED_REACTIONS: bool = true

const FUR: Color = Color(0.20, 0.18, 0.32)
const FUR_LIGHT: Color = Color(0.34, 0.31, 0.50)
const EAR_IN: Color = Color(0.86, 0.52, 0.66)
const NOSE: Color = Color(1.0, 0.60, 0.72)
const EYE: Color = Color(0.78, 1.0, 0.50)
const MOON: Color = Color(1.0, 0.86, 0.40)
const STAR: Color = Color(1.0, 0.97, 0.80)
const WHISKER: Color = Color(0.70, 0.68, 0.82)
const LOAF_AFTER_S: float = 0.8

const W: int = 24
const H: int = 17

## Star spots inside the fur, per pose, in canvas pixels.
const STARS_WALK: Array[Vector2] = [Vector2(7, 8), Vector2(11, 10), Vector2(14, 8), Vector2(9, 11)]
const STARS_LOAF: Array[Vector2] = [Vector2(6, 11), Vector2(10, 10), Vector2(8, 13), Vector2(13, 12)]


func _build() -> void:
	hop_peak = 1.0
	hop_rate = 3.2
	add_body_layer(_paint_glow, true, 0)
	add_body_layer(_paint_cat, false, 1)
	add_body_layer(_paint_stars, true, 2)
	# The thought bubble is paint, not light: additive white over the owner's
	# helmet read as a grey smear.
	add_body_layer(_paint_thoughts, false, 3)


static func _frame(pose: String) -> ImageTexture:
	return PixelCanvas.cached("starcat_" + pose, W, H, func(c: PixelCanvas) -> void:
		var loaf: bool = pose.begins_with("loaf")
		var hd: Vector2
		if loaf:
			# Tail wrapped round the front, tip flicking up in the second pose.
			var tip: Vector2 = Vector2(3.0, 12.0) if pose == "loaf_flick" else Vector2(3.5, 14.5)
			c.ball(tip.x, tip.y, 1.5, 1.5, FUR)
			c.ball(6.0, 15.5, 2.2, 1.4, FUR)
			# The loaf: a rounded block with its paws tucked.
			c.ball(10.0, 12.0, 7.0, 4.0, FUR)
			c.rect(13.0, 15.0, 3.0, 1.0, FUR_LIGHT)
			hd = Vector2(16.5, 8.0)
		else:
			var step: float = 1.0 if pose == "walk_a" else -1.0
			# Tail up in a question mark.
			for p: Vector3 in [Vector3(4.5, 9.0, 1.3), Vector3(3.0, 7.0, 1.2), Vector3(2.5, 4.5, 1.2), Vector3(3.5, 2.5, 1.2)]:
				c.ball(p.x, p.y, p.z, p.z, FUR)
			# Slim legs, alternating.
			c.rect(6.0 - step, 11.0, 2.0, 6.0, FUR)
			c.rect(13.0 + step, 11.0, 2.0, 6.0, FUR)
			c.rect(8.0 + step, 11.0, 2.0, 6.0, FUR_LIGHT)
			c.rect(15.0 - step, 11.0, 2.0, 6.0, FUR_LIGHT)
			c.ball(10.5, 9.5, 6.5, 3.2, FUR)
			hd = Vector2(18.0, 6.5)
		# Ears with pink insides.
		c.tri(hd + Vector2(-3.5, -1.5), hd + Vector2(-1.0, -2.5), hd + Vector2(-3.0, -6.5), FUR)
		c.tri(hd + Vector2(0.0, -2.5), hd + Vector2(2.5, -1.5), hd + Vector2(1.5, -6.5), FUR)
		c.ball(hd.x, hd.y, 3.8, 3.4, FUR)
		c.finish(0.22, 0.22, 0.55)
		c.tri(hd + Vector2(-3.0, -2.0), hd + Vector2(-1.8, -2.4), hd + Vector2(-2.8, -5.0), EAR_IN)
		c.tri(hd + Vector2(0.5, -2.4), hd + Vector2(1.8, -2.0), hd + Vector2(1.3, -5.0), EAR_IN)
		# Nose and whiskers.
		c.px(hd.x + 3.5, hd.y + 0.5, NOSE)
		c.px(hd.x + 4.5, hd.y + 1.5, WHISKER)
		c.px(hd.x + 4.5, hd.y - 0.5, WHISKER)
		# Collar and the moon charm.
		c.rect(hd.x - 2.0, hd.y + 3.0, 3.0, 1.0, Color(0.55, 0.18, 0.30))
		c.px(hd.x - 1.0, hd.y + 4.0, MOON)
		c.px(hd.x, hd.y + 4.0, MOON.darkened(0.3))
		c.px(hd.x - 2.0, hd.y + 1.5, Color(1.0, 0.55, 0.70))
	)


func _head(loaf: bool) -> Vector2:
	# Sprite-local position of the head centre (canvas x - 12, canvas y - 17).
	return Vector2(16.5 - 12.0, 8.0 - 17.0) if loaf else Vector2(18.0 - 12.0, 6.5 - 17.0)


func _paint_cat(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 8.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var puffed: bool = activity() == &"combat"
	var loaf: bool = still_for >= LOAF_AFTER_S and not puffed
	var pose: String
	if puffed:
		pose = "walk_a"
	elif loaf:
		pose = "loaf_flick" if fposmod(still_for, 2.6) < 0.35 else "loaf"
	else:
		pose = "walk_a" if hop_phase < 0.5 else "walk_b"
	var feet: Vector2 = Vector2(0.0, -hop_height)
	PixelCanvas.draw_sprite(layer, _frame(pose), feet, facing)
	# Eyes, live, so they can glow and slow-blink. Mirrored with the sprite.
	var hd: Vector2 = _head(loaf)
	var e: Vector2 = feet + Vector2((hd.x + 0.5) * facing, hd.y - 1.0)
	var slow: float = fposmod(still_for, 4.0)
	var closed: bool = loaf and slow > 3.2
	if closed:
		layer.draw_rect(Rect2(roundf(e.x) - 1.0, roundf(e.y) + 1.0, 2.0, 1.0), FUR_LIGHT.darkened(0.5))
	else:
		layer.draw_rect(Rect2(roundf(e.x) - 1.0, roundf(e.y), 2.0, 2.0), EYE)
		layer.draw_rect(Rect2(roundf(e.x) - (0.0 if facing > 0.0 else 1.0), roundf(e.y), 1.0, 2.0), FACE_DARK)


func _paint_stars(layer: VfxDrawLayer) -> void:
	var puffed: bool = activity() == &"combat"
	var loaf: bool = still_for >= LOAF_AFTER_S and not puffed
	var spots: Array[Vector2] = STARS_LOAF if loaf else STARS_WALK
	var feet: Vector2 = Vector2(0.0, -hop_height)
	for i: int in spots.size():
		var tw: float = pow(maxf(0.0, sin(_elapsed * 2.3 + float(i) * 1.9)), 4.0)
		if puffed:
			tw = 1.0
		if tw < 0.05:
			continue
		var p: Vector2 = feet + Vector2((spots[i].x - 12.0 + 0.5) * facing - 0.5, spots[i].y - 17.0)
		layer.draw_rect(Rect2(p.round(), Vector2.ONE), Color(STAR, tw))
		if tw > 0.7:
			layer.draw_rect(Rect2(p.round() + Vector2(-1, 0), Vector2(3, 1)), Color(STAR, tw * 0.4))
			layer.draw_rect(Rect2(p.round() + Vector2(0, -1), Vector2(1, 3)), Color(STAR, tw * 0.4))
	# Eye glow on the slow blink's open half.
	if loaf:
		var hd: Vector2 = _head(true)
		layer.draw_circle(feet + Vector2((hd.x + 0.5) * facing, hd.y), 3.0, Color(EYE, 0.12))


func _paint_thoughts(layer: VfxDrawLayer) -> void:
	if activity() == &"fishing_rod":
		_paint_fish_dream(layer, Vector2(0.0, -hop_height))


## A thought bubble over its head with a fish in it - drifting up and AWAY from
## the owner (behind the cat), so it never sits over the owner's head.
func _paint_fish_dream(layer: VfxDrawLayer, feet: Vector2) -> void:
	var hd: Vector2 = _head(still_for >= LOAF_AFTER_S)
	var base: Vector2 = feet + Vector2(hd.x * facing, hd.y - 5.0)
	var bob: float = roundf(sin(_elapsed * 2.0))
	var back: float = -facing
	var puff: Color = Color(0.96, 0.96, 1.0, 0.9)
	var rim: Color = Color(0.45, 0.45, 0.60, 0.9)
	layer.draw_rect(Rect2((base + Vector2(1.0 * back, 0.0)).round(), Vector2.ONE), puff)
	layer.draw_rect(Rect2((base + Vector2(3.0 * back, -3.0)).round(), Vector2(2, 2)), puff)
	var bubble: Vector2 = (base + Vector2(8.0 * back, -9.0 + bob)).round()
	layer.draw_circle(bubble, 5.0, rim)
	layer.draw_circle(bubble, 4.0, puff)
	var fish: Vector2 = bubble + Vector2(-2.0, -1.0)
	layer.draw_rect(Rect2(fish, Vector2(3, 2)), Color(0.60, 0.80, 1.0))
	layer.draw_rect(Rect2(fish + Vector2(3, 0), Vector2(1, 2)), Color(0.45, 0.62, 0.90))
	layer.draw_rect(Rect2(fish, Vector2(1, 1)), FACE_DARK)


func _paint_glow(layer: VfxDrawLayer) -> void:
	var b: float = 0.8 + 0.2 * sin(_elapsed * 1.5)
	layer.draw_circle(Vector2(0, -7), 13.0, Color(0.55, 0.5, 1.0, 0.06 * b))
