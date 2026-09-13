extends GroundCompanionPreset
## PENGUIN. A little penguin that waddles after the wearer flapping its flippers
## to keep up. When they stop it stands beside them - and every so often slips
## over flat on its belly, lies there dizzy with stars going round its head, and
## gets back up.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## The fall is a separate POSE (drawn lying down), not a rotation of the standing
## one: rotating one-pixel eyes and beak smears them into mush.

const INK: Color = Color(0.16, 0.18, 0.30)
const INK_LIGHT: Color = Color(0.30, 0.34, 0.50)
const BELLY: Color = Color(0.97, 0.97, 1.0)
const BEAK: Color = Color(1.0, 0.62, 0.18)
const STAR: Color = Color(1.0, 0.92, 0.40)
const IDLE_AFTER_S: float = 0.8
const SLIP_EVERY_S: float = 5.0
const SLIP_S: float = 1.4


func _build() -> void:
	hop_peak = 1.5
	hop_rate = 3.6
	add_body_layer(_paint_penguin, false, 0)


func _paint_penguin(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 5.0)
	var f: float = facing
	var idle: bool = still_for >= IDLE_AFTER_S
	var t: float = fposmod(still_for - IDLE_AFTER_S, SLIP_EVERY_S)
	if idle and t > SLIP_EVERY_S - SLIP_S:
		_paint_slipped(layer, f, (t - (SLIP_EVERY_S - SLIP_S)) / SLIP_S)
		return
	var rock: float = sin(hop_phase * TAU) * 0.08 if is_hopping() else 0.0
	layer.draw_set_transform(Vector2(0.0, -hop_height), rock, Vector2(squash * f, 1.0 / squash))
	var step: float = sin(hop_phase * TAU) if is_hopping() else 0.0
	layer.draw_rect(Rect2(-3.0, -1.0 - maxf(0.0, step), 2.0, 1.0), BEAK)
	layer.draw_rect(Rect2(1.0, -1.0 - maxf(0.0, -step), 2.0, 1.0), BEAK)
	# Body: a tall egg of ink with a white belly and face.
	layer.draw_circle(Vector2(0.0, -5.0), 4.6, INK)
	layer.draw_circle(Vector2(0.0, -9.0), 3.8, INK)
	layer.draw_rect(Rect2(-3.0, -12.0, 1.0, 2.0), INK_LIGHT)
	layer.draw_circle(Vector2(0.8, -4.5), 3.2, BELLY)
	layer.draw_circle(Vector2(1.2, -9.0), 2.4, BELLY)
	# Flippers: flapping while it hurries.
	var flap: float = absf(sin(_elapsed * 14.0)) * 2.0 if is_hopping() else 0.0
	layer.draw_rect(Rect2(-5.0, -8.0 + flap * 0.5, 1.0, 4.0 - flap * 0.5), INK)
	layer.draw_rect(Rect2(4.0, -8.0 + flap * 0.5, 1.0, 4.0 - flap * 0.5), INK)
	draw_eyes(layer, Vector2(1.2, -10.0), 1.5, Vector2.ZERO, blinking(3.2, 0.6), 2)
	layer.draw_rect(Rect2(2.0, -8.0, 2.0, 1.0), BEAK)
	draw_blush(layer, Vector2(1.2, -8.0), 2.5)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Flat on its belly: slides in, lies dizzy, pushes itself back up.
func _paint_slipped(layer: VfxDrawLayer, f: float, k: float) -> void:
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2(f, 1.0))
	# Lying flat on its belly, head forward, feet kicked up at the back. The dark
	# back is what shows from above; the white is only the face patch and a thin
	# line of belly along the floor - a big white band read as a hockey puck.
	layer.draw_rect(Rect2(-6.0, -3.0, 2.0, 1.0), BEAK)      # feet in the air
	layer.draw_rect(Rect2(-7.0, -5.0, 1.0, 2.0), BEAK)
	layer.draw_circle(Vector2(-1.5, -2.5), 3.2, INK)
	layer.draw_circle(Vector2(1.5, -2.5), 3.0, INK)
	layer.draw_rect(Rect2(-4.0, -1.0, 8.0, 1.0), BELLY)
	layer.draw_rect(Rect2(-2.0, -5.5, 2.0, 1.0), INK_LIGHT)
	# Flippers splayed out flat.
	layer.draw_rect(Rect2(-1.0, 0.0, 3.0, 1.0), INK)
	# Head resting on the floor, face patch forward.
	var head: Vector2 = Vector2(5.0, -3.0)
	layer.draw_circle(head, 2.8, INK)
	layer.draw_circle(head + Vector2(0.8, 0.2), 1.8, BELLY)
	layer.draw_rect(Rect2(head.x + 2.5, head.y, 2.0, 1.0), BEAK)
	# Dizzy X eye.
	var e: Vector2 = (head + Vector2(0.8, -0.5)).round()
	layer.draw_rect(Rect2(e.x - 1.0, e.y - 1.0, 1.0, 1.0), FACE_DARK)
	layer.draw_rect(Rect2(e.x + 1.0, e.y - 1.0, 1.0, 1.0), FACE_DARK)
	layer.draw_rect(Rect2(e.x, e.y, 1.0, 1.0), FACE_DARK)
	layer.draw_rect(Rect2(e.x - 1.0, e.y + 1.0, 1.0, 1.0), FACE_DARK)
	layer.draw_rect(Rect2(e.x + 1.0, e.y + 1.0, 1.0, 1.0), FACE_DARK)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Stars circling above it, in the middle of the lie-down.
	if k > 0.1 and k < 0.85:
		for i: int in 3:
			var a: float = _elapsed * 5.0 + float(i) * TAU / 3.0
			var at: Vector2 = (Vector2(3.0 * f, -9.0) + Vector2(cos(a) * 4.0, sin(a) * 1.5)).round()
			layer.draw_rect(Rect2(at.x - 1.0, at.y, 3.0, 1.0), STAR)
			layer.draw_rect(Rect2(at.x, at.y - 1.0, 1.0, 3.0), STAR)
