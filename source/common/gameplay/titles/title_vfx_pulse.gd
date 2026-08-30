extends Node
## Drives title-text VFX on a Label or Button every frame. A ShaderMaterial on a
## Label does not animate on its own (the control never redraws), so this node is
## what actually makes any of it move.
##
## It does two different jobs depending on the title family:
##
##   LEGACY (supporter / premium)  animates the label's own colour and outline in
##       script - the pulse and flash you can see on a Gilded or Sovereign title.
##   MASTERY (the eleven level-99 titles)  leaves the colour alone entirely and
##       feeds the shader a clock instead. Those looks paint their own gradients
##       per fragment, so tinting the label on top of them would wash the gradient
##       out - and TIME inside the shader does not advance a control that is not
##       redrawing, which is the whole reason the uniform exists.
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


func configure(p_tint: Color, p_vip: bool, p_style: int, p_mastery_fx: int = -1) -> void:
	tint = p_tint
	vip = p_vip
	style = p_style
	mastery_fx = p_mastery_fx
	set_process(true)
	_apply(0.0)


func _process(_delta: float) -> void:
	_apply(Time.get_ticks_msec() * 0.001)


func _apply(t: float) -> void:
	var host: CanvasItem = get_parent() as CanvasItem
	if host == null:
		return
	if mastery_fx >= 0:
		_apply_mastery(host, t)
		return
	_apply_legacy(host, t)


## Mastery titles: hand the shader the clock and otherwise keep out of its way.
func _apply_mastery(host: CanvasItem, t: float) -> void:
	var mat: ShaderMaterial = host.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(&"t", t)
	# White, so the shader's gradient arrives unmultiplied. Anything else here
	# tints eleven carefully chosen palettes toward one colour.
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
	var size: int = TitleVfx.OUTLINE_SIZE_VIP if vip else TitleVfx.OUTLINE_SIZE
	if host is Label:
		var label: Label = host
		label.add_theme_color_override(&"font_outline_color", TitleVfx.OUTLINE_COLOR)
		label.add_theme_constant_override(&"outline_size", size)
	elif host is Button:
		var btn: Button = host
		btn.add_theme_color_override(&"font_outline_color", TitleVfx.OUTLINE_COLOR)
		btn.add_theme_constant_override(&"outline_size", maxi(1, size - 3))
