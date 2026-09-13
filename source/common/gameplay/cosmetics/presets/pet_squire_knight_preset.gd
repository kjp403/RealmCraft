extends GroundCompanionPreset
## SQUIRE KNIGHT. A tiny knight in an oversized helmet with a red plume, a
## tabard, a round shield and a little sword, marching after the wearer on
## stubby legs. When they stop it stands to attention beside them - and every
## few seconds snaps its sword up in a proud salute.
##
## DETAILED PASS. Painted on a [PixelCanvas] (march A, march B, stand, salute):
## a steel helmet in three tones with a visor slit and glinting eyes, a plume,
## a red tabard with a gold stripe, a blue shield with a gold boss, and a sword
## with a gold hilt. Live on top: the plume bouncing and the salute timing.

const STEEL: Color = Color(0.74, 0.78, 0.86)
const STEEL_DARK: Color = Color(0.46, 0.50, 0.60)
const PLUME: Color = Color(0.90, 0.24, 0.26)
const TABARD: Color = Color(0.78, 0.20, 0.24)
const GOLD: Color = Color(1.0, 0.82, 0.32)
const SHIELD: Color = Color(0.30, 0.46, 0.82)
const VISOR: Color = Color(0.10, 0.10, 0.14)
const SALUTE_EVERY_S: float = 3.5
const SALUTE_S: float = 1.0
const STAND_AFTER_S: float = 0.6

const W: int = 18
const H: int = 23


func _build() -> void:
	hop_peak = 1.5
	hop_rate = 4.0
	add_body_layer(_paint_knight, false, 0)


static func _frame(pose: String) -> ImageTexture:
	return PixelCanvas.cached("squire_" + pose, W, H, func(c: PixelCanvas) -> void:
		var step: float = 0.0
		if pose == "march_a":
			step = 1.0
		elif pose == "march_b":
			step = -1.0
		# Sword held back in the far hand (or raised in front for the salute).
		if pose != "salute":
			c.rect(3.0, 10.0, 1.0, 7.0, STEEL)
			c.rect(2.0, 16.0, 3.0, 1.0, GOLD)
		# Legs and boots.
		c.rect(6.0 - step, 18.0, 2.0, 5.0, STEEL_DARK)
		c.rect(9.0 + step, 18.0, 2.0, 5.0, STEEL)
		# Tabard over a mail body.
		c.ball(8.5, 15.0, 3.8, 4.2, TABARD)
		# Helmet: much too big, which is the charm.
		c.ball(8.5, 8.5, 5.0, 5.0, STEEL)
		# Plume sweeping back off the crest.
		c.ball(6.0, 3.0, 2.8, 1.6, PLUME)
		c.ball(3.8, 4.0, 1.8, 1.3, PLUME)
		# Shield on the near arm.
		c.ball(12.5, 15.0, 3.2, 3.6, SHIELD)
		if pose == "salute":
			c.rect(14.0, 1.0, 1.0, 10.0, STEEL)
			c.rect(13.0, 10.0, 3.0, 1.0, GOLD)
		c.finish(0.2, 0.26, 0.6)
		# Details.
		c.rect(6.0, 8.0, 7.0, 1.0, VISOR)                  # visor slit
		c.px(9.0, 8.0, Color.WHITE)                         # eyes glinting inside
		c.px(11.0, 8.0, Color.WHITE)
		c.line(Vector2(8.5, 11.0), Vector2(8.5, 12.0), STEEL_DARK)   # helmet ridge
		c.px(8.0, 4.5, STEEL.lightened(0.4))
		c.rect(8.0, 13.0, 1.0, 5.0, GOLD)                   # tabard stripe
		c.px(12.0, 15.0, GOLD)                              # shield boss
		c.px(12.0, 14.0, GOLD.lightened(0.4))
	)


func _paint_knight(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 7.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var pose: String
	if still_for >= STAND_AFTER_S:
		var t: float = fposmod(still_for, SALUTE_EVERY_S)
		pose = "salute" if t > SALUTE_EVERY_S - SALUTE_S else "stand"
	else:
		pose = "march_a" if hop_phase < 0.5 else "march_b"
	PixelCanvas.draw_sprite(layer, _frame(pose), Vector2(0.0, -hop_height), facing)
	# The plume tip bounces a beat behind the march.
	var bounce: float = roundf(sin(hop_phase * TAU + 1.2) * 1.0) if is_hopping() else 0.0
	var tip: Vector2 = Vector2((3.0 - 9.0 + 0.0) * facing, 4.0 - 23.0 - hop_height + bounce)
	layer.draw_rect(Rect2(tip.x - (1.0 if facing > 0.0 else 0.0), tip.y, 1.0, 1.0), PLUME.darkened(0.2))
