extends GroundCompanionPreset
## TREASURE GOBLIN. A grinning little goblin scurrying after the wearer with a
## bulging sack of loot over its shoulder, gold coins bouncing out of the top as
## it runs. When they stop it plonks the sack down, sits on it, and flips a coin
## over and over, catching it every time.
##
## DETAILED PASS. Painted on a [PixelCanvas] (run A, run B, sit): green skin in
## three tones, big pointed ears, a brown tunic, a burlap sack with a rope tie
## and gold glinting out of the neck, a toothy grin and a shiny eye. Live on
## top: coins jostled out of the sack while it runs (world particles) and the
## coin flip when it sits.
##
## REACTS: in a fight it dives into its own sack (hidden behind its owner, eyes
## peeking out of the neck, trembling). While its owner mines, gold coins arc
## out of the rock face and drop into its sack.

const SKIN: Color = Color(0.52, 0.76, 0.34)
const SKIN_DARK: Color = Color(0.36, 0.56, 0.22)
const TUNIC: Color = Color(0.54, 0.36, 0.22)
const SACK: Color = Color(0.80, 0.68, 0.46)
const ROPE: Color = Color(0.54, 0.40, 0.24)
const GOLD: Color = Color(1.0, 0.82, 0.30)
const TOOTH: Color = Color(1.0, 0.98, 0.90)
const BOOT: Color = Color(0.30, 0.20, 0.14)
const SIT_AFTER_S: float = 0.7
const FLIP_S: float = 0.9

const W: int = 24
const H: int = 22

var _coins: CPUParticles2D


func _build() -> void:
	hop_peak = 2.0
	hop_rate = 4.4
	add_body_layer(_paint_goblin, false, 0)
	var p: CPUParticles2D = CPUParticles2D.new()
	# A few small coins, not a spray: at 3 px and five at a time they read as
	# debris flying off the goblin rather than loot slipping out of a sack.
	p.amount = 3
	p.lifetime = 0.5
	p.local_coords = false
	p.texture = VfxTextures.pip(2)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.position = Vector2(-5, -17)
	p.direction = Vector2(0, -1)
	p.spread = 50.0
	p.gravity = Vector2(0, 160.0)
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 26.0
	p.color = GOLD
	body.add_child(p)
	_coins = p


func _tick(delta: float) -> void:
	super(delta)
	_coins.emitting = is_hopping() and activity() != &"combat"
	# Out of the sack's neck, which is behind the goblin whichever way it faces.
	_coins.position = Vector2(-5.0 * facing, -17.0)


static func _frame(pose: String) -> ImageTexture:
	return PixelCanvas.cached("goblin_" + pose, W, H, func(c: PixelCanvas) -> void:
		if pose == "hide":
			# Only the sack, with ear tips poking out of the neck.
			c.tri(Vector2(9.0, 9.0), Vector2(11.0, 8.5), Vector2(5.0, 4.0), SKIN_DARK)
			c.tri(Vector2(13.0, 8.5), Vector2(15.0, 9.0), Vector2(19.0, 4.0), SKIN)
			c.ball(12.0, 15.5, 7.0, 6.2, SACK)
			c.ball(12.0, 9.5, 3.0, 1.6, SACK)
			c.finish(0.18, 0.24, 0.58)
			c.rect(9.0, 10.5, 6.0, 1.0, ROPE)
			c.rect(10.0, 9.0, 4.0, 1.0, BOOT)              # dark gap in the neck
			c.px(10.0, 9.0, GOLD)                          # eyes peeking out
			c.px(13.0, 9.0, GOLD)
			c.rect(7.0, 14.0, 2.0, 2.0, SACK.darkened(0.2))
			return
		var hd: Vector2
		if pose == "sit":
			# The sack on the ground, the goblin perched on top of it.
			c.ball(9.0, 17.0, 6.0, 4.8, SACK)
			c.rect(7.0, 11.5, 4.0, 1.0, ROPE)
			c.ball(9.0, 11.0, 2.0, 1.2, SACK)
			c.rect(14.0, 17.0, 5.0, 2.0, SKIN_DARK)     # legs forward
			c.rect(18.0, 17.0, 2.0, 3.0, BOOT)
			c.ball(14.0, 13.0, 3.6, 3.6, TUNIC)
			hd = Vector2(15.5, 7.5)
		else:
			var step: float = 1.5 if pose == "run_a" else -1.5
			c.rect(10.0 - step, 17.0, 2.0, 4.0, SKIN_DARK)
			c.rect(14.0 + step, 17.0, 2.0, 4.0, SKIN)
			c.rect(9.0 - step, 20.0, 3.0, 2.0, BOOT)
			c.rect(14.0 + step, 20.0, 3.0, 2.0, BOOT)
			c.ball(12.5, 14.5, 3.8, 4.0, TUNIC)
			# The sack slung over the back, bigger than the goblin's head.
			c.ball(6.5, 9.5, 5.4, 5.2, SACK)
			c.ball(8.0, 4.5, 2.0, 1.2, SACK)
			c.line(Vector2(9.0, 6.0), Vector2(14.0, 12.0), ROPE)      # strap
			hd = Vector2(16.0, 8.0)
		# Ears: long and pointed, back one darker.
		c.tri(hd + Vector2(-2.0, -1.0), hd + Vector2(-1.5, 1.5), hd + Vector2(-7.5, -3.5), SKIN_DARK)
		c.tri(hd + Vector2(2.5, -1.0), hd + Vector2(2.5, 1.5), hd + Vector2(8.0, -4.0), SKIN)
		c.ball(hd.x, hd.y, 4.0, 3.6, SKIN)
		# Big nose.
		c.ball(hd.x + 3.5, hd.y + 0.8, 1.4, 1.2, SKIN)
		c.finish(0.18, 0.24, 0.58)
		# Gold glinting out of the sack's neck.
		if pose == "sit":
			c.px(8.0, 10.0, GOLD)
			c.px(10.0, 10.0, GOLD.lightened(0.4))
		else:
			c.px(7.0, 3.0, GOLD)
			c.px(9.0, 3.0, GOLD.lightened(0.4))
			c.px(8.0, 2.0, GOLD)
		# Patches on the sack.
		c.rect(4.0 if pose != "sit" else 6.0, 10.0 if pose != "sit" else 17.0, 2.0, 2.0, SACK.darkened(0.2))
		# Face: shiny eye, grin with teeth, a tuft of hair.
		c.eye(hd.x + 0.5, hd.y - 1.5, 2, 2)
		c.rect(hd.x - 0.5, hd.y + 2.0, 3.0, 1.0, SKIN_DARK.darkened(0.4))
		c.px(hd.x, hd.y + 2.0, TOOTH)
		c.px(hd.x + 1.0, hd.y + 2.0, TOOTH)
		c.px(hd.x - 1.0, hd.y - 4.0, BOOT)
		c.px(hd.x, hd.y - 4.5, BOOT)
	)


func _paint_goblin(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 8.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if activity() == &"combat":
		PixelCanvas.draw_sprite(layer, _frame("hide"), Vector2.ZERO, facing)
		return
	var sitting: bool = still_for >= SIT_AFTER_S
	var pose: String = "sit" if sitting else ("run_a" if hop_phase < 0.5 else "run_b")
	var feet: Vector2 = Vector2(0.0, -hop_height)
	PixelCanvas.draw_sprite(layer, _frame(pose), feet, facing)
	if not sitting:
		return
	if activity() == &"pickaxe":
		_paint_mining_coins(layer, feet)
		return
	_paint_coin_flip(layer, feet)


## Coins arcing from the owner's side into the sack's neck, three at a time.
func _paint_mining_coins(layer: VfxDrawLayer, feet: Vector2) -> void:
	var s: float = maxf(0.001, global_scale.x)
	var owner_x: float = (global_position.x - body.global_position.x) / s
	# Sack neck in the sit pose: canvas (9, 11) -> local (-3, -11), mirrored.
	var sack: Vector2 = feet + Vector2(-3.0 * facing, -11.0)
	var from: Vector2 = Vector2(owner_x, -14.0)
	for i: int in 3:
		var k: float = fposmod(_elapsed * 1.2 + float(i) / 3.0, 1.0)
		var at: Vector2 = from.lerp(sack, k) + Vector2(0.0, -sin(k * PI) * 10.0)
		var w: float = 1.0 + roundf(absf(cos(k * TAU * 1.5)) * 1.0)
		layer.draw_rect(Rect2(roundf(at.x), roundf(at.y), w, 2.0), GOLD)


func _paint_coin_flip(layer: VfxDrawLayer, feet: Vector2) -> void:
	# The coin flip: up from its hand, spinning, and caught again.
	var t: float = fposmod(still_for, FLIP_S) / FLIP_S
	var hand: Vector2 = feet + Vector2(5.0 * facing, -10.0)
	var at: Vector2 = hand + Vector2(0.0, -sin(t * PI) * 10.0)
	var w: float = 1.0 + roundf(absf(cos(t * TAU * 2.0)) * 2.0)
	layer.draw_rect(Rect2(roundf(at.x - w * 0.5), roundf(at.y), w, 2.0), GOLD)
	if absf(cos(t * TAU * 2.0)) > 0.9:
		layer.draw_rect(Rect2(roundf(at.x), roundf(at.y), 1.0, 1.0), Color.WHITE)
