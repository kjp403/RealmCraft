extends GroundCompanionPreset
## CRAB. A little red crab that scuttles after the wearer SIDEWAYS, as crabs do,
## legs pattering. When they stop it waves its claws in the air, snipping away,
## and blows the odd bubble.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## Always drawn face-on - a crab walking left or right is still facing you - so
## no mirroring, and the sideways scuttle reads for free.

const SHELL: Color = Color(0.92, 0.34, 0.24)
const SHELL_DARK: Color = Color(0.64, 0.18, 0.14)
const SHELL_LIGHT: Color = Color(1.0, 0.58, 0.44)
const BUBBLE: Color = Color(0.80, 0.94, 1.0)
const IDLE_AFTER_S: float = 0.8


func _build() -> void:
	hop_peak = 0.0
	hop_rate = 5.0
	add_body_layer(_paint_crab, false, 0)
	var b: CPUParticles2D = add_motes(BUBBLE, 3, VfxTextures.dot(4), Vector2(0, -7))
	b.gravity = Vector2(0, -14.0)
	b.lifetime = 1.2
	b.material = null


func _paint_crab(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 6.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var scuttle: bool = is_hopping()
	var idle: bool = still_for >= IDLE_AFTER_S
	var sway: float = sin(_elapsed * 18.0) * 0.6 if scuttle else 0.0
	# Legs: three a side, pattering in alternation while it scuttles.
	for side: float in [-1.0, 1.0]:
		for i: int in 3:
			var lift: float = 1.0 if scuttle and (int(_elapsed * 16.0) + i) % 2 == 0 else 0.0
			var root: Vector2 = Vector2(side * (2.5 + float(i)), -2.5)
			layer.draw_line(root, root + Vector2(side * 2.0, 2.5 - lift), SHELL_DARK, 1.0)
	# Body.
	var c: Vector2 = Vector2(sway, -4.0)
	layer.draw_circle(c, 4.6, SHELL_DARK)
	layer.draw_circle(c + Vector2(-0.2, -0.3), 4.1, SHELL)
	layer.draw_rect(Rect2(c.x - 2.0, c.y - 3.5, 3.0, 1.0), SHELL_LIGHT)
	# Claws: raised and waving when idle, held forward when scuttling.
	for side: float in [-1.0, 1.0]:
		var wave: float = 0.0
		if idle:
			wave = sin(still_for * 5.0 + (0.0 if side < 0.0 else PI)) * 2.5 - 2.5
		var claw: Vector2 = c + Vector2(side * 6.5, -2.5 + wave)
		layer.draw_line(c + Vector2(side * 3.5, -1.0), claw, SHELL_DARK, 1.0)
		layer.draw_circle(claw, 2.3, SHELL_DARK)
		layer.draw_circle(claw + Vector2(0, -0.2), 1.9, SHELL)
		# The snip: a notch in the top of the claw that opens and shuts.
		var open: bool = fposmod(_elapsed * (6.0 if idle else 2.0), 1.0) < 0.5
		layer.draw_rect(Rect2(roundf(claw.x) - (0.0 if side > 0.0 else 1.0), roundf(claw.y) - (2.0 if open else 1.0), 1.0, 2.0 if open else 1.0), SHELL_DARK)
	# Eyes on stalks, with shine.
	for side: float in [-1.0, 1.0]:
		var tip: Vector2 = c + Vector2(side * 1.8, -6.5 + (sin(_elapsed * 4.0 + side) * 0.5))
		layer.draw_line(c + Vector2(side * 1.5, -3.5), tip, SHELL_DARK, 1.0)
		var e: Vector2 = tip.round()
		if blinking(3.1, 2.4):
			layer.draw_rect(Rect2(e.x - 1.0, e.y, 2.0, 1.0), FACE_DARK)
		else:
			layer.draw_rect(Rect2(e.x - 1.0, e.y - 1.0, 2.0, 2.0), FACE_DARK)
			layer.draw_rect(Rect2(e.x - 1.0, e.y - 1.0, 1.0, 1.0), FACE_SHINE)
	# A little smile.
	layer.draw_rect(Rect2(c.x - 1.0, c.y, 2.0, 1.0), SHELL_DARK)
	draw_blush(layer, c + Vector2(0.0, -1.0), 2.5)
