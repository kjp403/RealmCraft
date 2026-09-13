extends GroundCompanionPreset
## HEDGEHOG. It does not walk to keep up - it curls into a spiky ball and ROLLS
## after the wearer, tumbling along the ground. When they stop it uncurls with a
## little wobble, an apple still stuck on its spines, and sniffs the air with
## its twitching nose.
##
## DETAILED PASS. Painted on a [PixelCanvas]: the rolled ball in two spike
## rotations, and the uncurled hedgehog (spines in two tones with pale tips, a
## tan face, a twitchy nose and a shiny eye, an apple speared on its back). The
## roll itself is real: the ball frame advances with distance travelled, so it
## turns at the speed it moves.
##
## REACTS: in a fight it curls up into its ball behind its owner and bristles,
## spikes flicking between the two rotations.

## Has reactions of its own beyond the shared hide / cheer / level-up. The Vault
## reads this to shelve the pet under "Reactive Pets" (see cosmetics_menu.gd).
const THEMED_REACTIONS: bool = true

const SPINE: Color = Color(0.46, 0.33, 0.24)
const SPINE_TIP: Color = Color(0.86, 0.78, 0.66)
const FACE: Color = Color(0.96, 0.84, 0.68)
const NOSE: Color = Color(0.16, 0.10, 0.10)
const APPLE: Color = Color(0.90, 0.22, 0.24)
const LEAF: Color = Color(0.40, 0.72, 0.30)
const UNCURL_AFTER_S: float = 0.35

const W: int = 20
const H: int = 16
const BALL_R: float = 6.0

var _roll: float = 0.0
var _roll_last_x: float = 0.0
var _roll_primed: bool = false


func _build() -> void:
	hop_peak = 0.0
	add_body_layer(_paint_hedgehog, false, 0)


func _tick(delta: float) -> void:
	super(delta)
	var x: float = body.global_position.x / maxf(0.001, global_scale.x)
	if _roll_primed:
		_roll += absf(x - _roll_last_x) / BALL_R
	_roll_last_x = x
	_roll_primed = true


static func _ball_frame(turn: int) -> ImageTexture:
	return PixelCanvas.cached("hedgehog_ball_%d" % turn, W, H, func(c: PixelCanvas) -> void:
		var centre: Vector2 = Vector2(10.0, 9.0)
		# Spikes round the rim, rotated a half-step between the two frames.
		for i: int in 12:
			var a: float = (float(i) + 0.5 * float(turn)) * TAU / 12.0
			var d: Vector2 = Vector2(cos(a), sin(a))
			var side: Vector2 = d.orthogonal() * 1.3
			c.tri(centre + d * 5.0 + side, centre + d * 5.0 - side, centre + d * 7.5, SPINE)
		c.ball(centre.x, centre.y, 6.0, 6.0, SPINE)
		c.finish(0.15, 0.25, 0.55)
		# Pale spine tips and a swirl on the ball, turning with the frame.
		for i: int in 6:
			var a: float = (float(i) * 2.0 + float(turn)) * TAU / 12.0
			c.px(centre.x + cos(a) * 4.0, centre.y + sin(a) * 4.0, SPINE_TIP)
		c.px(centre.x, centre.y, FACE.darkened(0.2))
	)


static func _stand_frame(sniff: bool) -> ImageTexture:
	return PixelCanvas.cached("hedgehog_stand_%s" % str(sniff), W, H, func(c: PixelCanvas) -> void:
		# Spine dome with a jagged top edge.
		for i: int in 7:
			var x: float = 3.0 + float(i) * 2.0
			c.tri(Vector2(x - 1.5, 9.0), Vector2(x + 1.5, 9.0), Vector2(x - 1.0, 3.0 + float(i % 2)), SPINE)
		c.ball(9.0, 11.0, 7.0, 4.5, SPINE)
		# Little feet.
		c.rect(6.0, 15.0, 2.0, 1.0, FACE.darkened(0.3))
		c.rect(11.0, 15.0, 2.0, 1.0, FACE.darkened(0.3))
		# Tan face and snout, nose lifted when sniffing.
		c.ball(15.0, 12.0, 3.4, 2.8, FACE)
		c.ball(17.8, 12.0 - (0.8 if sniff else 0.0), 1.8, 1.4, FACE)
		# The apple, speared on its back.
		c.ball(8.0, 3.5, 2.4, 2.4, APPLE)
		c.finish(0.15, 0.24, 0.55)
		# Details.
		for sp: Vector2 in [Vector2(4, 8), Vector2(7, 9), Vector2(10, 8), Vector2(12, 10), Vector2(5, 11)]:
			c.px(sp.x, sp.y, SPINE_TIP)
		c.px(7.0, 2.5, APPLE.lightened(0.45))
		c.px(8.0, 0.0, LEAF)
		c.px(9.0, 0.0, LEAF)
		c.px(8.0, 1.0, SPINE.darkened(0.4))                 # apple stalk
		c.eye(15.5, 10.5, 2, 2)
		c.px(19.5, 11.0 - (1.0 if sniff else 0.0), NOSE)
		c.px(13.5, 13.0, Color(1.0, 0.60, 0.68))
	)


func _paint_hedgehog(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 7.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if activity() == &"combat":
		PixelCanvas.draw_sprite(layer, _ball_frame(int(_elapsed * 18.0) % 2), Vector2.ZERO, facing)
		return
	if still_for < UNCURL_AFTER_S:
		# Two spike rotations, alternated by distance rolled, drawn with a slight
		# bounce as the ball goes over its corners.
		var turn: int = int(floor(_roll * 3.0)) % 2
		var bump: float = roundf(absf(sin(_roll * PI * 3.0)) * 1.0)
		PixelCanvas.draw_sprite(layer, _ball_frame(turn), Vector2(0.0, -bump), facing)
		return
	# Uncurling wobble, then the sniff.
	var wobble: float = 0.0
	var since: float = still_for - UNCURL_AFTER_S
	if since < 0.4:
		wobble = roundf(sin(since * 30.0) * (1.0 - since / 0.4))
	var sniff: bool = fposmod(still_for * 3.0, 1.0) < 0.3 and fposmod(still_for, 2.5) < 1.2
	PixelCanvas.draw_sprite(layer, _stand_frame(sniff), Vector2(wobble, 0.0), facing)
