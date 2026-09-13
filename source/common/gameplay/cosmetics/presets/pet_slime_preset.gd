extends GroundCompanionPreset
## SLIME. A little jelly blob that bounces along behind the wearer, squashing
## flat on every landing, and wobbles contentedly beside them when they stop.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## All of its charm is squash and stretch, which [GroundCompanionPreset] owns;
## this file is the blob: a dark rim, a translucent body you can half see the
## floor through, a highlight, and eyes that blink.

const RIM: Color = Color(0.16, 0.45, 0.25)
const JELLY: Color = Color(0.42, 0.88, 0.50, 0.85)
const SHINE: Color = Color(0.92, 1.0, 0.92)
const EYE: Color = Color(0.06, 0.16, 0.10)
const R: float = 5.5


func _build() -> void:
	add_body_layer(_paint_slime, false, 0)


func _paint_slime(layer: VfxDrawLayer) -> void:
	apply_hop(layer, R + 1.0)
	# A dome on a flat base: a circle raised so its lower part is cut by a band
	# the width of the base. Rim first, one pixel larger all round.
	layer.draw_circle(Vector2(0, -R + 1.0), R + 1.0, RIM)
	layer.draw_rect(Rect2(-R - 1.0, -R + 1.0, R * 2.0 + 2.0, R), RIM)
	layer.draw_circle(Vector2(0, -R + 1.0), R, JELLY)
	layer.draw_rect(Rect2(-R, -R + 1.0, R * 2.0, R - 1.0), JELLY)
	layer.draw_rect(Rect2(-R * 0.55, -R * 1.55, 2.0, 1.0), SHINE)
	layer.draw_rect(Rect2(-R * 0.55 - 1.0, -R * 1.3, 1.0, 1.0), SHINE)
	# Eyes look where it is going; a blink every few seconds.
	var blink: bool = fposmod(_elapsed, 3.4) < 0.12
	var look: float = facing * 1.0
	for side: float in [-1.0, 1.0]:
		var at: Vector2 = Vector2(side * 2.0 + look, -R * 0.75)
		layer.draw_rect(Rect2(at.x - 0.5, at.y + (1.0 if blink else 0.0), 1.0, 1.0 if blink else 2.0), EYE)
