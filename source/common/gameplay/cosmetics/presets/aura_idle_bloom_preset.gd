extends CosmeticTrailPreset
## IDLE BLOOM. Stand still and a ring of grass and flowers grows up around your
## feet, one plant after another; take a step and it all wilts back into the
## ground.
##
## PROTOTYPE - unregistered. Aura slot.
##
## WHO IT IS FOR: the player who stands in the bank or at a stall for minutes at
## a time. Every other aura looks the same after ten seconds; this one rewards
## standing still, so the longest-idle player in town has the biggest garden.
##
## Extends the trail base only for its movement reading (is_moving), which is
## sampled from the transform and so works for remote players as well.
##
## Every plant's spot, species and colour is a fixed function of its index, so
## the garden grows back in the SAME arrangement each time - it is your garden,
## not a random scatter.

const PLANTS: int = 18
## Seconds from bare floor to full bloom, and from full bloom back to bare.
const GROW_S: float = 3.5
const WILT_S: float = 0.5
const INNER_R: float = 11.0
const OUTER_R: float = 27.0

const STEM: Color = Color(0.30, 0.62, 0.28)
const GRASS: Color = Color(0.42, 0.72, 0.30)
const CENTRE: Color = Color(1.0, 0.85, 0.30)
const PETALS: Array[Color] = [
	Color(1.0, 0.55, 0.70), Color(1.0, 0.92, 0.45), Color(0.96, 0.96, 1.0),
	Color(0.72, 0.60, 1.0), Color(1.0, 0.62, 0.35),
]

## 0 bare, 1 full bloom.
var _bloom: float = 0.0


func _build() -> void:
	# Plants behind the feet draw under the body, plants in front over it.
	_add_draw_layer(_paint_back, false, 0)
	_add_draw_layer(_paint_front, false, 2)


func _tick(delta: float) -> void:
	super(delta)
	if is_moving():
		_bloom = maxf(0.0, _bloom - delta / WILT_S)
	else:
		_bloom = minf(1.0, _bloom + delta / GROW_S)


func _paint_back(layer: VfxDrawLayer) -> void:
	_paint_plants(layer, false)


func _paint_front(layer: VfxDrawLayer) -> void:
	_paint_plants(layer, true)


## Stable pseudo-random in 0..1 for (plant, salt).
func _hash(i: int, salt: float) -> float:
	return fposmod(sin(float(i) * 127.1 + salt * 311.7) * 43758.5453, 1.0)


func _paint_plants(layer: VfxDrawLayer, front: bool) -> void:
	if _bloom <= 0.0:
		return
	for i: int in PLANTS:
		var angle: float = float(i) * TAU / float(PLANTS) + _hash(i, 1.0) * 0.3
		var radius: float = lerpf(INNER_R, OUTER_R, _hash(i, 2.0))
		var foot: Vector2 = _ground_point(angle, radius)
		if (foot.y > 0.0) != front:
			continue
		# Each plant starts growing at its own point in the bloom, in index order
		# shuffled by the hash, and takes a quarter of the bloom to finish.
		var start: float = _hash(i, 3.0) * 0.75
		var grow: float = clampf((_bloom - start) / 0.25, 0.0, 1.0)
		if grow <= 0.0:
			continue
		var sway: float = sin(_elapsed * 1.8 + float(i)) * 0.8 * grow
		var is_flower: bool = _hash(i, 4.0) > 0.35
		if not is_flower:
			_paint_grass(layer, foot, grow, sway)
			continue
		var height: float = lerpf(4.0, 8.0, _hash(i, 5.0)) * grow
		var head: Vector2 = foot + Vector2(sway, -height)
		layer.draw_line(foot, head, STEM, 1.0)
		# Leaf halfway up once the stem is long enough to hold one.
		if grow > 0.5:
			var side: float = 1.0 if i % 2 == 0 else -1.0
			layer.draw_rect(Rect2(foot + Vector2(side * 1.0 + sway * 0.5, -height * 0.5), Vector2(side * 2.0, 1.0)), STEM)
		# The flower opens over the last third of the grow.
		var open: float = clampf((grow - 0.66) / 0.34, 0.0, 1.0)
		if open <= 0.0:
			layer.draw_circle(head, 0.8, STEM)
			continue
		var petal: Color = PETALS[int(_hash(i, 6.0) * PETALS.size()) % PETALS.size()]
		var spread: float = 1.6 * open
		for k: int in 4:
			var d: Vector2 = Vector2.from_angle(float(k) * TAU / 4.0 + 0.4) * spread
			layer.draw_circle(head + d, 1.1 * open + 0.3, petal)
		layer.draw_circle(head, 0.9, CENTRE)


func _paint_grass(layer: VfxDrawLayer, foot: Vector2, grow: float, sway: float) -> void:
	for k: int in 3:
		var dx: float = float(k - 1) * 1.5
		var h: float = (3.0 + float(k % 2) * 2.0) * grow
		layer.draw_line(foot + Vector2(dx, 0.0), foot + Vector2(dx + sway + float(k - 1) * 0.8, -h), GRASS, 1.0)
