class_name VfxTextures
## Tiny procedural particle textures, built once and shared by every cosmetic
## preset on the client.
##
## Why generate rather than author PNGs: an untextured CPUParticles2D draws hard
## square dots, which is what made the old strip-rendered auras read as "coloured
## pixels" rather than as leaves, coins or droplets. These are 6-16 px white masks
## the emitters TINT through their own colour ramp, so one shape serves every
## palette and the whole set costs a handful of kilobytes of VRAM.
##
## Everything here is white with a shaped alpha on purpose — colour belongs to the
## emitter, never to the mask, or a preset could not recolour a shape it shares.

## name -> ImageTexture. Static so all wearers on screen share one upload per shape.
static var _cache: Dictionary = {}


## Soft round mote — the default for mist, pollen, dust and sparks.
static func dot(size: int = 8) -> ImageTexture:
	return _cached("dot%d" % size, size, func(u: float, v: float) -> float:
		return _falloff(u, v, 2.0)
	)


## Hard-edged round pip for droplets and coins seen face-on.
static func pip(size: int = 6) -> ImageTexture:
	return _cached("pip%d" % size, size, func(u: float, v: float) -> float:
		var d: float = sqrt(u * u + v * v)
		return 1.0 if d <= 1.0 else 0.0
	)


## Four-pointed sparkle. The classic "glint" read: a bright core with thin arms,
## which is what separates a gem shimmer from a generic bright dot.
static func sparkle(size: int = 9) -> ImageTexture:
	return _cached("sparkle%d" % size, size, func(u: float, v: float) -> float:
		var arm: float = maxf(1.0 - absf(u) * 4.0 - absf(v), 1.0 - absf(v) * 4.0 - absf(u))
		var core: float = _falloff(u, v, 3.0)
		return clampf(maxf(arm, core), 0.0, 1.0)
	)


## Diamond / cut-gem silhouette for gold's sparkle layer.
static func diamond(size: int = 7) -> ImageTexture:
	return _cached("diamond%d" % size, size, func(u: float, v: float) -> float:
		return 1.0 if absf(u) + absf(v) <= 1.0 else 0.0
	)


## Teardrop, heavy end DOWN — blood and toxic droplets fall nose-first.
static func droplet(size: int = 8) -> ImageTexture:
	return _cached("droplet%d" % size, size, func(u: float, v: float) -> float:
		# Widen toward the bottom, taper to a point at the top.
		var width: float = 0.45 + 0.55 * clampf((v + 1.0) * 0.5, 0.0, 1.0)
		var d: float = sqrt((u / width) * (u / width) + (v * 0.85) * (v * 0.85))
		return 1.0 if d <= 1.0 else 0.0
	)


## Leaf blade, long axis vertical. Emitters spin it, so one orientation is enough.
static func leaf(size: int = 9) -> ImageTexture:
	return _cached("leaf%d" % size, size, func(u: float, v: float) -> float:
		var width: float = cos(v * PI * 0.5) * 0.75
		if width <= 0.01:
			return 0.0
		return 1.0 if absf(u) <= width else 0.0
	)


## Broad soft cloud for mist / steam / haze — very low alpha, very wide falloff.
static func puff(size: int = 16) -> ImageTexture:
	return _cached("puff%d" % size, size, func(u: float, v: float) -> float:
		return _falloff(u, v, 1.4) * 0.75
	)


## Short vertical shard for rising ice crystals.
static func shard(size: int = 9) -> ImageTexture:
	return _cached("shard%d" % size, size, func(u: float, v: float) -> float:
		var width: float = (1.0 - absf(v)) * 0.55
		return 1.0 if absf(u) <= width else 0.0
	)


static func _falloff(u: float, v: float, power: float) -> float:
	return pow(clampf(1.0 - sqrt(u * u + v * v), 0.0, 1.0), power)


## Build (or fetch) a white RGBA mask by sampling [param mask] over -1..1 in both
## axes. Nearest filtering is applied by the emitters, so no anti-aliasing is baked
## in here — these have to stay crisp against 64 px pixel-art bodies.
static func _cached(key: String, size: int, mask: Callable) -> ImageTexture:
	var hit: ImageTexture = _cache.get(key, null)
	if hit != null:
		return hit
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half: float = size * 0.5
	for y: int in size:
		for x: int in size:
			var u: float = (x + 0.5 - half) / half
			var v: float = (y + 0.5 - half) / half
			var a: float = clampf(float(mask.call(u, v)), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = tex
	return tex
