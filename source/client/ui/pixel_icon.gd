class_name PixelIcon
extends RefCounted
## Crisp pixel-art icons in UI: NEAREST + INTEGER-scale-to-fit + WHOLE-pixel centering — the fix for the
## half-pixel smear that `Button.icon`/`expand_icon` and container centering produce at 1:1 (see the menu
## launcher + inventory icon saga). [method mount] adds one to a host; [method set_art] swaps its art.

## Adds a crisp icon as a child of [param host]: integer-scaled to fit the host, centered on whole GLOBAL
## pixels. [param inset] shrinks the fit box by that many pixels PER SIDE, so the glyph sits inside a
## panel's padding instead of running to its border — pass it whenever the host is itself a framed or
## filled control (see [method PixelUI.hud_icon_button]). Re-fits whenever the host's rect changes — DEFERRED, so it survives async / first-frame layout
## timing (an immediate fit caught freshly-built grids at 0-size, drawing tiny in the corner). Returns the
## TextureRect so callers that change the art later can pass it to [method set_art].
static func mount(host: Control, texture: Texture2D = null, inset: float = 0.0) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	# EXPAND_IGNORE_SIZE IS LOAD-BEARING, NOT TIDINESS. TextureRect defaults to
	# EXPAND_KEEP_SIZE, which reports the TEXTURE size as the control's minimum
	# size — and a Control is clamped up to its minimum. That silently undid every
	# `icon.size = art * factor` below: a 64x64 item icon asked to draw at 24x24
	# was snapped straight back to 64x64 and spilled out over its slot. _fit has
	# been running and being overruled; this is what lets its result stick.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = texture
	host.add_child(icon)
	icon.set_meta(&"_pixel_inset", inset)
	var fit: Callable = func() -> void: _fit(host, icon)
	icon.set_meta(&"_pixel_fit", fit)
	host.item_rect_changed.connect(func() -> void: fit.call_deferred())
	fit.call_deferred()
	return icon


## Swaps the art on an icon created by [method mount] and re-fits (a new art size can change the integer
## scale). Passing null hides it. Safe to call with a null icon.
static func set_art(icon: TextureRect, texture: Texture2D) -> void:
	if icon == null:
		return
	icon.texture = texture
	var fit: Variant = icon.get_meta(&"_pixel_fit", null)
	if fit is Callable:
		(fit as Callable).call_deferred()


## Adopt a Button's editor-assigned icon as a crisp mounted glyph: reads [member Button.icon], mounts it
## via [method mount], then clears the native icon so it's drawn once — crisply. Lets a scene assign the
## glyph in the editor (visible there, nothing loaded in code) while runtime renders it sharp. Returns the
## TextureRect for later [method set_art].
static func from_button(button: Button, inset: float = 0.0) -> TextureRect:
	var tex: Texture2D = button.icon
	button.icon = null
	return mount(button, tex, inset)


static func _fit(host: Control, icon: TextureRect) -> void:
	if not is_instance_valid(host) or not is_instance_valid(icon) or not icon.is_inside_tree():
		return
	if icon.texture == null:
		icon.visible = false
		return
	icon.visible = true
	var art: Vector2 = icon.texture.get_size()
	if art.x <= 0.0 or art.y <= 0.0:
		return
	# The fit box is the host MINUS its inset on both sides. Without this a glyph
	# mounted on a styled button is scaled to the button's outer rect and paints
	# straight over its own border.
	var inset: float = float(icon.get_meta(&"_pixel_inset", 0.0))
	var box: float = minf(host.size.x, host.size.y) - inset * 2.0
	if box <= 0.0:
		return
	var art_max: float = maxf(art.x, art.y)
	# Integer upscale when the host is larger (crisp pixel art). Downscale when the
	# art is larger than the host — 64×64 pack icons must fit loot-feed / compact slots.
	var factor: float = box / art_max
	if factor >= 1.0:
		factor = maxf(1.0, floorf(factor))
	icon.size = art * factor
	icon.global_position = (host.global_position + (host.size - icon.size) * 0.5).round()
