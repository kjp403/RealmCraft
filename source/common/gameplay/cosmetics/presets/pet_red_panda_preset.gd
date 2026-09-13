extends GroundCompanionPreset
## RED PANDA. A red panda that bounds after the wearer, big ringed tail bouncing
## behind it. When they stop it sits up on its haunches beside them, paws tucked,
## tail curled round - and every so often rears up on its back legs and throws
## its arms up in the famous red-panda "surprise" pose.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## DETAILED PASS. Painted on a [PixelCanvas] (bound A, bound B, sit, surprise):
## russet fur in three tones, black legs and belly, cream face markings with the
## tear-stripes, rounded white-tipped ears, a shiny eye, and a thick tail with
## dark rings. Motion on top is procedural: the bound, the landing squash, the
## sit/surprise timing.

const FUR: Color = Color(0.80, 0.34, 0.16)
const FUR_LIGHT: Color = Color(0.94, 0.52, 0.26)
const DARK: Color = Color(0.22, 0.12, 0.10)
const CREAM: Color = Color(1.0, 0.94, 0.82)
const RING: Color = Color(0.56, 0.22, 0.10)
const NOSE: Color = Color(0.10, 0.06, 0.06)
const BLUSH: Color = Color(1.0, 0.55, 0.60)
const SIT_AFTER_S: float = 0.7
const SURPRISE_EVERY_S: float = 5.0
const SURPRISE_S: float = 1.0

const W: int = 24
const H: int = 22


func _build() -> void:
	hop_peak = 3.5
	hop_rate = 3.4
	add_body_layer(_paint_panda, false, 0)


static func _frame(pose: String) -> ImageTexture:
	return PixelCanvas.cached("redpanda_" + pose, W, H, func(c: PixelCanvas) -> void:
		var sit: bool = pose == "sit" or pose == "surprise"
		# --- Tail: thick, curving, with dark rings.
		var tail_pts: Array[Vector2]
		if sit:
			tail_pts = [Vector2(7.0, 18.0), Vector2(4.0, 17.0), Vector2(2.5, 14.0), Vector2(3.0, 11.0)]
		else:
			var lift: float = -2.0 if pose == "bound_a" else 1.0
			tail_pts = [Vector2(7.0, 14.0), Vector2(4.0, 13.0 + lift), Vector2(2.0, 11.0 + lift * 1.5), Vector2(1.5, 8.5 + lift * 2.0)]
		for i: int in tail_pts.size():
			c.ball(tail_pts[i].x, tail_pts[i].y, 2.6, 2.4, RING if i % 2 == 1 else FUR)
		if pose == "surprise":
			# Up on its back legs, arms thrown up.
			c.rect(8.0, 16.0, 2.0, 6.0, DARK)
			c.rect(12.0, 16.0, 2.0, 6.0, DARK)
			c.ball(11.0, 12.5, 4.2, 5.0, FUR)
			c.ball(11.5, 13.5, 2.4, 3.2, DARK, 0.2, 0.1)
			c.rect(6.0, 5.0, 2.0, 6.0, DARK)
			c.rect(15.0, 5.0, 2.0, 6.0, DARK)
		elif sit:
			c.ball(10.0, 17.5, 4.6, 3.4, FUR)
			c.ball(11.5, 13.0, 4.0, 4.4, FUR)
			c.ball(12.5, 14.5, 2.2, 2.6, DARK, 0.2, 0.1)
			c.rect(12.0, 18.0, 2.0, 4.0, DARK)
			c.rect(15.0, 18.0, 2.0, 4.0, DARK)
		else:
			# Short legs under a low body - the first pass had seven-pixel legs and
			# the panda read as a coffee table.
			var stride: float = 1.5 if pose == "bound_a" else -1.5
			c.rect(6.0 - stride, 17.0, 2.0, 5.0, DARK)
			c.rect(15.0 + stride, 17.0, 2.0, 5.0, DARK)
			c.rect(8.5 + stride, 17.0, 2.0, 5.0, DARK.lightened(0.12))
			c.rect(17.0 - stride, 17.0, 2.0, 5.0, DARK.lightened(0.12))
			c.ball(11.0, 15.5, 7.0, 4.0, FUR)
			c.ellipse(11.5, 18.0, 5.0, 1.2, DARK)
		# --- Head.
		var hd: Vector2 = Vector2(17.5, 11.0) if not sit else Vector2(14.5, 7.0)
		if pose == "surprise":
			hd = Vector2(11.5, 5.5)
		# Rounded ears, dark behind with white rims.
		c.ball(hd.x - 3.8, hd.y - 3.2, 2.0, 2.0, CREAM)
		c.ball(hd.x + 2.8, hd.y - 3.6, 2.0, 2.0, CREAM)
		c.ellipse(hd.x - 3.6, hd.y - 2.8, 1.1, 1.1, DARK)
		c.ellipse(hd.x + 2.6, hd.y - 3.2, 1.1, 1.1, DARK)
		c.ball(hd.x, hd.y, 4.6, 4.0, FUR_LIGHT)
		# Cream muzzle and eyebrow patches.
		c.ball(hd.x + 1.5, hd.y + 1.8, 2.8, 1.8, CREAM, 0.1, 0.05)
		c.ellipse(hd.x - 1.8, hd.y - 1.8, 1.2, 0.8, CREAM)
		c.ellipse(hd.x + 2.2, hd.y - 2.0, 1.2, 0.8, CREAM)
		c.finish(0.18, 0.26, 0.6)
		# --- Details.
		var front: bool = pose == "surprise"
		if front:
			c.eye(hd.x - 2.5, hd.y - 1.0, 2, 2)
			c.eye(hd.x + 1.5, hd.y - 1.0, 2, 2)
			c.rect(hd.x - 0.5, hd.y + 1.5, 2.0, 1.0, NOSE)
			c.rect(hd.x, hd.y + 3.0, 1.0, 1.0, NOSE)    # little open mouth
		else:
			c.eye(hd.x + 0.5, hd.y - 1.0, 2, 2)
			c.rect(hd.x + 4.0, hd.y + 1.0, 2.0, 1.0, NOSE)
		# Tear stripes running down from the eyes.
		c.px(hd.x - 0.5 if not front else hd.x - 2.5, hd.y + 1.5, RING)
		c.px(hd.x - 0.5 if not front else hd.x - 2.5, hd.y + 2.5, RING)
		c.px(hd.x - 2.0, hd.y + 1.0, BLUSH)
		# Tail tip highlight.
		c.px(tail_pts[3].x - 1.0, tail_pts[3].y - 1.5, FUR_LIGHT)
	)


func _paint_panda(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 9.0)
	var pose: String
	var f: float = facing
	if still_for >= SIT_AFTER_S:
		var t: float = fposmod(still_for - SIT_AFTER_S, SURPRISE_EVERY_S)
		pose = "surprise" if t > SURPRISE_EVERY_S - SURPRISE_S else "sit"
	else:
		pose = "bound_a" if hop_phase < 0.5 else "bound_b"
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	PixelCanvas.draw_sprite(layer, _frame(pose), Vector2(0.0, -hop_height), f if pose != "surprise" else 1.0)
