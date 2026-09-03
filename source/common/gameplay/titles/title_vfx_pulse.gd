extends Node
## Drives title-text VFX on a Label or Button every frame. A ShaderMaterial on a
## Label does not animate on its own (the control never redraws), so this node is
## what actually makes any of it move.
##
## It does two different jobs depending on the title family:
##
##   LEGACY (supporter / premium)  animates the label's own colour and outline in
##       script - the pulse and flash you can see on a Gilded or Sovereign title.
##   SHADER-DRIVEN (the eleven level-99 mastery titles, and the four VIP donation
##       tiers)  leaves the colour alone entirely and feeds the shader a clock
##       instead. Those looks paint their own gradients per fragment, so tinting
##       the label on top of them would wash the gradient out - and TIME inside
##       the shader does not advance a control that is not redrawing, which is the
##       whole reason the uniform exists.
##
## The two shader families are one case here on purpose. They need exactly the
## same thing from this node - `t`, a white modulate and the outline pinned - and
## splitting them would mean a third branch that differs in nothing.
##
## In BOTH cases the outline stays [constant TitleVfx.OUTLINE_COLOR]. That is the
## load-bearing legibility fix: this script used to re-tint the outline with the
## title's own colour every single frame, which silently undid any dark outline
## set elsewhere and left the brightest titles with the least contrast against
## bright ground. Nothing here may write font_outline_color any other colour.

var tint: Color = Color(0.49, 0.75, 1.0)
var vip: bool = false
var style: int = 0
## Mastery style index, or -1 for the legacy families.
var mastery_fx: int = -1
## Set for a VIP ladder title. Same treatment as a mastery one - see the header -
## but there is no index to carry, because vip_title.gdshader has no branches:
## a tier is a set of uniforms, applied once by TitleVfx.
var clock_driven: bool = false
## Resolved outline colour for this title — the shared near-black unless the
## catalog entry overrode it. Re-asserted every frame like the size is.
var outline_color: Color = TitleVfx.OUTLINE_COLOR
## Resolved outline WEIGHT for this title. 0 falls back to the shared pair, which
## is what every title without a VipTierProfile override gets. Carried here for
## the same reason the colour is: this node re-asserts the outline every frame,
## so whatever it believes wins over whatever was set at mount time.
var outline_size: int = 0


func configure(
	p_tint: Color, p_vip: bool, p_style: int, p_mastery_fx: int = -1,
	p_outline: Color = TitleVfx.OUTLINE_COLOR, p_clock_driven: bool = false,
	p_outline_size: int = 0
) -> void:
	tint = p_tint
	vip = p_vip
	style = p_style
	mastery_fx = p_mastery_fx
	outline_color = p_outline
	clock_driven = p_clock_driven
	outline_size = p_outline_size
	set_process(true)
	_apply(0.0)


func _process(_delta: float) -> void:
	_apply(Time.get_ticks_msec() * 0.001)


func _apply(t: float) -> void:
	var host: CanvasItem = get_parent() as CanvasItem
	if host == null:
		return
	_feed_rect_size(host)
	if mastery_fx >= 0 or clock_driven:
		_apply_shader_clock(host, t)
		return
	_apply_legacy(host, t)


## Tell whichever title shader is mounted how big its label is.
##
## ALL THREE shaders work in LABEL space, not in UV, because a Label's UV is a
## font-atlas coordinate and is useless as a position in the word - see any of
## their headers. Label space needs the label's size to normalise against, and
## only GDScript knows it, so it has to arrive as a uniform.
##
## Hoisted above the family branch rather than repeated inside each one: this is
## the piece the legacy shine band was missing when the other two were fixed, and
## a per-branch copy is exactly how that happens again. Every title shader wants
## it, so every title gets it.
##
## Refreshed every frame rather than set once because a Label resizes whenever its
## text changes, and the nameplate re-fits on every display_name or title sync. A
## stale size does not fail loudly - the gradient just slides off the letters,
## which reads as a tuning problem rather than as a bug.
func _feed_rect_size(host: CanvasItem) -> void:
	var mat: ShaderMaterial = host.material as ShaderMaterial
	var control: Control = host as Control
	if mat == null or control == null:
		return
	mat.set_shader_parameter(&"rect_size", control.size)


## Mastery and VIP titles: hand the shader the clock and otherwise keep out of
## its way.
func _apply_shader_clock(host: CanvasItem, t: float) -> void:
	var mat: ShaderMaterial = host.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(&"t", t)
	# White, so the shader's gradient arrives unmultiplied. Anything else here
	# tints eleven mastery palettes and four tier metals toward one colour.
	host.self_modulate = Color.WHITE
	_enforce_outline(host)
	host.queue_redraw()


func _apply_legacy(host: CanvasItem, t: float) -> void:
	var speed: float = 3.4 if vip else 2.2
	var pulse: float = 0.72 + (0.38 if vip else 0.26) * (0.5 + 0.5 * sin(t * speed))
	var flash: float = 0.0
	var flash_spd: float = 0.55 if vip else 0.35
	var sweep: float = fposmod(t * flash_spd, 1.0)
	if sweep < 0.18:
		flash = (1.0 - sweep / 0.18) * (0.85 if vip else 0.55)
	var shine: Color = Color(1.0, 0.97, 0.92)
	if style == 1:
		shine = Color(1.0, 0.92, 0.45)
	elif style == 2:
		shine = Color(1.0, 0.55, 0.28)
	elif style == 3:
		shine = Color(0.78, 0.62, 1.0)
	var lit: Color = tint * pulse
	lit = lit.lerp(shine, flash)
	lit.a = 1.0
	if host is Label:
		var label: Label = host
		label.self_modulate = lit
	elif host is Button:
		var btn: Button = host
		btn.add_theme_color_override(&"font_color", lit)
		btn.add_theme_color_override(&"font_disabled_color", lit)
		btn.add_theme_color_override(&"font_hover_color", lit)
		btn.add_theme_color_override(&"font_pressed_color", lit)
	else:
		host.self_modulate = lit
	_enforce_outline(host)
	host.queue_redraw()


## Re-assert the dark outline every frame.
##
## Re-asserting rather than setting once looks redundant and is not: theme
## overrides on these labels are also written by the nameplate, the profile and
## the vault row as they rebuild, and whichever of them runs last would otherwise
## decide the outline. Pinning it here means the contrast guarantee holds no
## matter what else touched the label.
func _enforce_outline(host: CanvasItem) -> void:
	var size: int = outline_size
	if size <= 0:
		size = TitleVfx.OUTLINE_SIZE_VIP if vip else TitleVfx.OUTLINE_SIZE
	if host is Label:
		var label: Label = host
		label.add_theme_color_override(&"font_outline_color", outline_color)
		label.add_theme_constant_override(&"outline_size", size)
	elif host is Button:
		var btn: Button = host
		btn.add_theme_color_override(&"font_outline_color", outline_color)
		btn.add_theme_constant_override(&"outline_size", maxi(1, size - 3))
