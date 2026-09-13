extends CosmeticPreset
## THUNDERHEAD CROWN. The Storm set's halo: a ring of storm cloud circling above
## the head, lit from inside by lightning that jumps from puff to puff.
##
## THE FIRST HALO WITH DEPTH. The strip halos are one flat sprite under the body,
## so a ring meant to circle the head is either entirely behind it or entirely in
## front. This preset draws the ring twice: the FAR half on a layer under the body
## and the NEAR half on a layer above it, so the crown passes behind the head and
## comes round in front of it.
##
## THE LIGHTNING STAYS IN THE CLOUD. It jumps sideways along the ring and never
## down at the head - a bolt into the wearer's skull reads as taking damage,
## which is the one thing a cosmetic above a player must never look like.
##
## Colour comes from [CosmeticThemes] (Storm), like every piece of the set.

const THEME: StringName = CosmeticThemes.STORM

## Ring centre above the feet, and its size. Measured on the starter body, whose
## helmet tops out 26 px above the feet (HEAD_Y is an older, taller estimate).
## The near puffs clear the helmet by a couple of pixels: first render sat the
## ring ON the head with fat puffs, and it read as a mushroom cap, not a crown.
## A visible hole in the middle is what says "halo". The nameplate is under the
## feet, so nothing competes up here.
const CROWN_Y: float = -33.0
const RING_RX: float = 14.0
const RING_SQUASH: float = 0.4
const PUFFS: int = 12
const SPIN_PERIOD_S: float = 11.0

## Two strike clocks at unrelated periods, so the flashes never settle into a beat.
const STRIKE_PERIODS: Array[float] = [0.95, 1.55]
const STRIKE_VISIBLE: float = 0.18
## How many puffs a bolt jumps across.
const STRIKE_SPAN: int = 3

## A storm grey pulled toward the theme. Pure `deep` alone is navy and vanishes
## over dark tiles; a grey base keeps the cloud a silhouette on any floor.
const CLOUD_GREY: Color = Color(0.36, 0.39, 0.46)


func _build() -> void:
	# Far half under the body, near half over it (z relative to this preset).
	_add_draw_layer(_paint_far, false, 0)
	_add_draw_layer(_paint_near, false, 2)
	_add_draw_layer(_paint_bolts, true, 3)

	var drift: CPUParticles2D = _add_emitter(6, 1.1, VfxTextures.dot(4))
	drift.position = Vector2(0, CROWN_Y)
	drift.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	drift.emission_rect_extents = Vector2(RING_RX, 3.0)
	drift.direction = Vector2(0, -1)
	drift.spread = 40.0
	drift.gravity = Vector2(0, -6.0)
	drift.initial_velocity_min = 3.0
	drift.initial_velocity_max = 9.0
	drift.scale_amount_min = 0.35
	drift.scale_amount_max = 0.6
	drift.color_ramp = _fade_ramp(CosmeticThemes.pale(THEME), 0.8)
	drift.material = _additive()
	drift.z_index = 3


func _spin() -> float:
	return _elapsed * TAU / SPIN_PERIOD_S


func _puff_angle(i: int) -> float:
	return _spin() + float(i) * TAU / float(PUFFS)


func _puff_pos(angle: float) -> Vector2:
	return Vector2(cos(angle) * RING_RX, CROWN_Y + sin(angle) * RING_RX * RING_SQUASH)


## Light on each puff from any bolt currently up: 0 dark, 1 fully lit.
func _lit(i: int) -> float:
	var best: float = 0.0
	for c: int in STRIKE_PERIODS.size():
		var flash: float = _strike_flash(c)
		if flash <= 0.0:
			continue
		var start: int = _strike_start(c)
		for s: int in STRIKE_SPAN + 1:
			if (start + s) % PUFFS == i:
				best = maxf(best, flash)
	return best


func _strike_phase(clock: int) -> float:
	return fposmod(_elapsed / STRIKE_PERIODS[clock] + float(clock) * 0.37, 1.0)


func _strike_flash(clock: int) -> float:
	var phase: float = _strike_phase(clock)
	if phase > STRIKE_VISIBLE:
		return 0.0
	return pow(1.0 - phase / STRIKE_VISIBLE, 1.4)


## Which puff a strike leaves from. Changes per strike, frozen while it is up.
func _strike_start(clock: int) -> int:
	var n: float = floor(_elapsed / STRIKE_PERIODS[clock] + float(clock) * 0.37)
	return int(absf(sin(n * 91.7 + float(clock) * 3.3)) * 1000.0) % PUFFS


func _paint_far(layer: VfxDrawLayer) -> void:
	# A faint glow BAND under the puffs, so the cloud sits in light of its own.
	# A band, never a filled disc: the disc filled the hole in the ring, and the
	# hole is the whole difference between a crown and a hat.
	layer.draw_set_transform(Vector2(0, CROWN_Y), 0.0, Vector2(1.0, RING_SQUASH))
	layer.draw_arc(Vector2.ZERO, RING_RX, 0.0, TAU, 32, Color(CosmeticThemes.core(THEME), 0.22), 7.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_paint_puffs(layer, false)


func _paint_near(layer: VfxDrawLayer) -> void:
	_paint_puffs(layer, true)


## Puffs on one half of the ring, back to front. sin(angle) > 0 is the half
## nearer the camera (screen y is down).
func _paint_puffs(layer: VfxDrawLayer, near: bool) -> void:
	var order: Array[int] = []
	for i: int in PUFFS:
		if (sin(_puff_angle(i)) > 0.0) == near:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return sin(_puff_angle(a)) < sin(_puff_angle(b))
	)
	var base: Color = CLOUD_GREY.lerp(CosmeticThemes.deep(THEME), 0.35)
	var pale: Color = CosmeticThemes.pale(THEME)
	for i: int in order:
		var angle: float = _puff_angle(i)
		var at: Vector2 = _puff_pos(angle)
		var depth: float = 0.5 + 0.5 * sin(angle)   # 0 far, 1 near
		# Alternate puff sizes so the ring has a lumpy cloud edge, not a bead chain.
		var r: float = (2.4 if i % 2 == 0 else 1.8) * lerpf(0.8, 1.15, depth)
		var lit: float = _lit(i)
		var body: Color = base.lerp(pale, lit * 0.75).darkened(0.25 * (1.0 - depth))
		layer.draw_circle(at, r, Color(body, 0.95))
		# Rim light along the top, always a little there, blazing when struck.
		layer.draw_circle(at + Vector2(-0.6, -r * 0.35), r * 0.55, Color(pale, 0.32 + 0.6 * lit))


func _paint_bolts(layer: VfxDrawLayer) -> void:
	var core: Color = CosmeticThemes.core(THEME)
	var pale: Color = CosmeticThemes.pale(THEME)
	for c: int in STRIKE_PERIODS.size():
		var flash: float = _strike_flash(c)
		if flash <= 0.0:
			continue
		var start: int = _strike_start(c)
		var points: PackedVector2Array = PackedVector2Array()
		var steps: int = STRIKE_SPAN * 2
		var a0: float = _puff_angle(start)
		for s: int in steps + 1:
			var k: float = float(s) / float(steps)
			var at: Vector2 = _puff_pos(a0 + k * float(STRIKE_SPAN) * TAU / float(PUFFS))
			if s != 0 and s != steps:
				at.y += sin(float(s) * 12.9898 + float(start) * 7.1) * 2.5
			points.append(at)
		layer.draw_polyline(points, Color(core, 0.7 * flash), 3.0)
		layer.draw_polyline(points, Color(pale, flash), 1.0)
		# The whole crown lights for the instant of the strike.
		layer.draw_set_transform(Vector2(0, CROWN_Y), 0.0, Vector2(1.0, RING_SQUASH))
		layer.draw_arc(Vector2.ZERO, RING_RX, 0.0, TAU, 32, Color(core, 0.35 * flash), 4.0)
		layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
