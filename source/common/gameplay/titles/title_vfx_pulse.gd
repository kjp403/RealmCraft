extends Node
## Drives title-text VFX on a Label or Button every frame. ShaderMaterial on a
## Label does not animate (the control never redraws), so this is the actual
## visible gem/gold pulse.

var tint: Color = Color(0.49, 0.75, 1.0)
var vip: bool = false
var style: int = 0


func configure(p_tint: Color, p_vip: bool, p_style: int) -> void:
	tint = p_tint
	vip = p_vip
	style = p_style
	set_process(true)
	_apply(0.0)


func _process(_delta: float) -> void:
	_apply(Time.get_ticks_msec() * 0.001)


func _apply(t: float) -> void:
	var host: CanvasItem = get_parent() as CanvasItem
	if host == null:
		return
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
		label.add_theme_color_override(&"font_outline_color", tint.darkened(0.15).lerp(shine, flash * 0.6))
		label.add_theme_constant_override(&"outline_size", 10 if vip else 6)
		label.queue_redraw()
	elif host is Button:
		var btn: Button = host
		btn.add_theme_color_override(&"font_color", lit)
		btn.add_theme_color_override(&"font_disabled_color", lit)
		btn.add_theme_color_override(&"font_hover_color", lit)
		btn.add_theme_color_override(&"font_pressed_color", lit)
		btn.add_theme_color_override(&"font_outline_color", tint.darkened(0.15))
		btn.add_theme_constant_override(&"outline_size", 8 if vip else 5)
		btn.queue_redraw()
	else:
		host.self_modulate = lit
		host.queue_redraw()
