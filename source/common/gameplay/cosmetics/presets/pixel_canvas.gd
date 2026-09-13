class_name PixelCanvas
extends RefCounted
## A tiny paint program for companion sprites: rasterise shapes at NATIVE pixel
## resolution, then run the two passes a pixel artist does by hand - edge
## shading and a coloured outline - and hand back a crisp ImageTexture.
##
## WHY NOT DRAW WITH draw_circle LIKE THE FIRST COMPANIONS. Vector shapes at
## this size come out as flat blobs: no outline, one tone per shape, soft edges
## that do not match the pixel-art bodies they stand next to. A canvas pass gets
## the look of hand-shaded sprites for free: every shape gets a lit top-left
## rim, a shaded bottom-right rim, and a 1 px "sel-out" outline in a darker
## shade of whatever it borders - which is most of what makes pixel art read as
## detailed.
##
## Order of work for a sprite: base shapes -> [method finish] (shade + outline)
## -> detail pixels (eyes, shine, markings) with [method px] -> [method texture].
## Details go AFTER finish so the shading pass never darkens an eye highlight.
##
## Everything is cached by key in [method cached], so each frame of each sprite
## is built once per client, not once per wearer or per frame.

const MARGIN: int = 1

## key -> ImageTexture.
static var _cache: Dictionary = {}

var width: int
var height: int
var image: Image


func _init(w: int, h: int) -> void:
	width = w
	height = h
	# One pixel of margin all round, so the outline pass has room.
	image = Image.create(w + MARGIN * 2, h + MARGIN * 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))


## Build-once cache: [param build] is called with a fresh canvas only on a miss.
static func cached(key: String, w: int, h: int, build: Callable) -> ImageTexture:
	if _cache.has(key):
		return _cache[key]
	var canvas: PixelCanvas = PixelCanvas.new(w, h)
	build.call(canvas)
	var tex: ImageTexture = canvas.texture()
	_cache[key] = tex
	return tex


func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func px(x: float, y: float, c: Color) -> void:
	var ix: int = int(floor(x))
	var iy: int = int(floor(y))
	if _in(ix, iy):
		image.set_pixel(ix + MARGIN, iy + MARGIN, c)


func get_px(x: int, y: int) -> Color:
	if not _in(x, y):
		return Color(0, 0, 0, 0)
	return image.get_pixel(x + MARGIN, y + MARGIN)


func rect(x: float, y: float, w: float, h: float, c: Color) -> void:
	for iy: int in range(int(floor(y)), int(floor(y + h))):
		for ix: int in range(int(floor(x)), int(floor(x + w))):
			px(ix, iy, c)


## Filled ellipse, tested at pixel centres.
func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for iy: int in range(int(floor(cy - ry)) - 1, int(ceil(cy + ry)) + 1):
		for ix: int in range(int(floor(cx - rx)) - 1, int(ceil(cx + rx)) + 1):
			var dx: float = (float(ix) + 0.5 - cx) / maxf(rx, 0.01)
			var dy: float = (float(iy) + 0.5 - cy) / maxf(ry, 0.01)
			if dx * dx + dy * dy <= 1.0:
				px(ix, iy, c)


## A shaded ellipse: a dark crescent low-right, the base colour, and a small
## highlight high-left - three tones of volume per shape. [method finish] only
## shades the OUTER silhouette; this is what gives a white chest on an orange
## body a form of its own instead of reading as a flat sticker.
func ball(cx: float, cy: float, rx: float, ry: float, c: Color, shade: float = 0.26, hi: float = 0.22) -> void:
	ellipse(cx, cy, rx, ry, c.darkened(shade))
	ellipse(cx - rx * 0.12, cy - ry * 0.14, rx * 0.86, ry * 0.84, c)
	if rx >= 2.0 and ry >= 2.0:
		ellipse(cx - rx * 0.36, cy - ry * 0.42, rx * 0.34, ry * 0.3, c.lightened(hi))


## Filled triangle, tested at pixel centres.
func tri(a: Vector2, b: Vector2, d: Vector2, c: Color) -> void:
	var lo: Vector2 = Vector2(minf(a.x, minf(b.x, d.x)), minf(a.y, minf(b.y, d.y)))
	var hi: Vector2 = Vector2(maxf(a.x, maxf(b.x, d.x)), maxf(a.y, maxf(b.y, d.y)))
	for iy: int in range(int(floor(lo.y)), int(ceil(hi.y)) + 1):
		for ix: int in range(int(floor(lo.x)), int(ceil(hi.x)) + 1):
			var p: Vector2 = Vector2(float(ix) + 0.5, float(iy) + 0.5)
			var d1: float = (p - b).cross(a - b)
			var d2: float = (p - d).cross(b - d)
			var d3: float = (p - a).cross(d - a)
			var neg: bool = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
			var pos: bool = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
			if not (neg and pos):
				px(ix, iy, c)


func line(a: Vector2, b: Vector2, c: Color) -> void:
	var steps: int = int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i: int in steps + 1:
		var p: Vector2 = a.lerp(b, float(i) / float(maxi(1, steps)))
		px(floor(p.x), floor(p.y), c)


## The pixel artist's two passes, in order.
##
## SHADE: an opaque pixel with empty space below or to the right sits on a
## shadow edge and is darkened; one with empty space above or to the left
## catches the light and is lightened. Tested against the ORIGINAL mask, so the
## pass never feeds on its own output.
##
## OUTLINE: every empty pixel touching an opaque one becomes a much darker
## shade of that neighbour - a coloured outline ("sel-out"), which reads far
## softer and richer than flat black.
func finish(light: float = 0.16, shadow: float = 0.24, outline_dark: float = 0.62) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var src: Image = image.duplicate()
	var solid: Callable = func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h and src.get_pixel(x, y).a > 0.5
	for y: int in h:
		for x: int in w:
			if not solid.call(x, y):
				continue
			var c: Color = src.get_pixel(x, y)
			if not solid.call(x + 1, y) or not solid.call(x, y + 1):
				c = c.darkened(shadow)
			elif not solid.call(x - 1, y) or not solid.call(x, y - 1):
				c = c.lightened(light)
			image.set_pixel(x, y, c)
	for y: int in h:
		for x: int in w:
			if solid.call(x, y):
				continue
			for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if solid.call(x + n.x, y + n.y):
					var base: Color = src.get_pixel(x + n.x, y + n.y)
					image.set_pixel(x, y, Color(base.darkened(outline_dark), 1.0))
					break


## A shiny eye: dark pupil block with a one-pixel highlight, top-left.
func eye(x: float, y: float, w: int = 2, h: int = 2, dark: Color = Color(0.08, 0.06, 0.12)) -> void:
	rect(x, y, w, h, dark)
	px(x, y, Color.WHITE)


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(image)


## Draw [param tex] with its bottom-centre on [param feet], mirrored when
## [param facing] is negative. The canvas margin is accounted for.
static func draw_sprite(layer: CanvasItem, tex: Texture2D, feet: Vector2, facing: float = 1.0, modulate: Color = Color.WHITE) -> void:
	var size: Vector2 = tex.get_size()
	layer.draw_set_transform(feet, 0.0, Vector2(signf(facing) if facing != 0.0 else 1.0, 1.0))
	# floor(): a half-pixel offset on an odd-width sprite blurs every column.
	layer.draw_texture(tex, Vector2(-floor(size.x * 0.5), -size.y + float(MARGIN)), modulate)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
