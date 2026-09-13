extends CosmeticPreset
## GLOOMY. A small personal rain cloud parked over the wearer's head, raining on
## them and nobody else, with a puddle and splashes at their feet.
##
## PROTOTYPE - unregistered. Halo slot: it lives above the head and loops.
##
## A JOKE COSMETIC HAS TO READ IN ONE GLANCE, so every layer points at the same
## gag: the cloud is grey and slightly droopy, the rain lands exactly on the
## wearer, and the splashes are on THEIR feet. Anything ambient or pretty
## (lightning, a rainbow) would turn it into a weather aura and lose the joke.
##
##   CLOUD    normal-blend puffs, darker underside, a slow sulky bob.
##   RAIN     drawn 1 px streaks falling through the body to the feet.
##   PUDDLE   a dark floor ellipse with splash rings on a clock.

const CLOUD_Y: float = -44.0
const GREY: Color = Color(0.46, 0.48, 0.54)
const UNDER: Color = Color(0.30, 0.32, 0.38)
const TOP: Color = Color(0.68, 0.70, 0.75)
const RAIN: Color = Color(0.62, 0.78, 0.95)
const PUDDLE: Color = Color(0.20, 0.30, 0.42)

## Puffs as (x, y, r) relative to the cloud centre. Hand-placed: a random cluster
## reads as smoke, a flat-bottomed lumpy top reads as a cartoon cloud.
const PUFFS: Array[Vector3] = [
	Vector3(-9.0, 1.0, 4.5), Vector3(-4.0, -3.0, 5.5), Vector3(2.5, -4.0, 6.0),
	Vector3(8.0, -0.5, 4.8), Vector3(0.0, 1.5, 5.0),
]
const RAIN_SPEED: float = 150.0
const DROPS: int = 14
const DROP_LEN: float = 3.0
const SPLASH_PERIOD_S: float = 0.35
const SPLASH_LIFE_S: float = 0.3


func _build() -> void:
	# Puddle under everything, by tree order at z 0.
	_add_draw_layer(_paint_puddle, false, 0)

	# Rain is DRAWN, not emitted: a particle mask at this size is a blob, and rain
	# only reads as rain as thin 1 px streaks. It crosses the body, so it sits
	# over it.
	_add_draw_layer(_paint_rain, false, 2)
	_add_draw_layer(_paint_cloud, false, 3)


func _paint_puddle(layer: VfxDrawLayer) -> void:
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	layer.draw_circle(Vector2.ZERO, 15.0, Color(PUDDLE, 0.35))
	layer.draw_circle(Vector2.ZERO, 11.0, Color(PUDDLE, 0.35))
	for k: int in 3:
		var clock: float = _elapsed + float(k) * SPLASH_PERIOD_S / 3.0
		var phase: float = fposmod(clock, SPLASH_PERIOD_S)
		if phase > SPLASH_LIFE_S:
			continue
		var n: float = floor(clock / SPLASH_PERIOD_S)
		var spot: Vector2 = Vector2(sin(n * 12.9 + float(k) * 3.1) * 9.0, cos(n * 7.3 + float(k)) * 5.0)
		var t: float = phase / SPLASH_LIFE_S
		layer.draw_arc(spot, 1.0 + t * 4.0, 0.0, TAU, 12, Color(RAIN, 0.6 * (1.0 - t)), 1.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_rain(layer: VfxDrawLayer) -> void:
	var top: float = CLOUD_Y + 5.0
	var fall: float = -top
	for i: int in DROPS:
		# Each drop has its own column and phase; it loops cloud -> feet forever.
		var x: float = roundf(fposmod(sin(float(i) * 91.3) * 437.0, 1.0) * 18.0 - 9.0)
		var y: float = top + fposmod(_elapsed * RAIN_SPEED + float(i) * fall * 0.37, fall)
		var fade: float = clampf((y - top) / 4.0, 0.0, 1.0) * clampf(-y / 3.0, 0.0, 1.0)
		layer.draw_line(Vector2(x, roundf(y)), Vector2(x, roundf(y) + DROP_LEN), Color(RAIN, 0.75 * fade), 1.0)


func _paint_cloud(layer: VfxDrawLayer) -> void:
	# A slow, heavy bob, with a slight sideways sag: sulking, not floating.
	var at: Vector2 = Vector2(sin(_elapsed * 0.7) * 1.0, CLOUD_Y + sin(_elapsed * 1.3) * 1.2)
	for p: Vector3 in PUFFS:
		layer.draw_circle(at + Vector2(p.x, p.y + 1.5), p.z, UNDER)
	for p: Vector3 in PUFFS:
		layer.draw_circle(at + Vector2(p.x, p.y), p.z, GREY)
	for p: Vector3 in PUFFS:
		layer.draw_circle(at + Vector2(p.x - 1.0, p.y - p.z * 0.4), p.z * 0.5, Color(TOP, 0.7))
	# Flat bottom edge: a cartoon cloud sits on an invisible shelf.
	layer.draw_rect(Rect2(at + Vector2(-11.0, 3.0), Vector2(21.0, 3.0)), UNDER)
