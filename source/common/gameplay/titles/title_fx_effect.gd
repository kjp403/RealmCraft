class_name TitleFxEffect
extends RichTextEffect
## Chat-side title VFX. Animates the « Title » glyphs (pulse / shimmer)
## without touching character cosmetics.
## Tag: [titlefx vip=0|1 style=0]...[/titlefx]

var bbcode: String = "titlefx"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var vip: float = float(char_fx.env.get("vip", 0.0))
	var style: float = float(char_fx.env.get("style", 0.0))
	var t: float = char_fx.elapsed_time
	var i: float = float(char_fx.relative_index)
	var speed: float = 1.8 if vip < 0.5 else 2.8
	if style > 1.5 and style < 3.5:
		speed = 1.4
	elif style > 4.5:
		speed = 1.6
	var wave: float = sin(t * speed + i * 0.42)
	var pulse: float = 0.88 + (0.08 if vip < 0.5 else 0.14) * wave
	char_fx.color = Color(
		minf(1.0, char_fx.color.r * pulse + (0.03 if vip < 0.5 else 0.08)),
		minf(1.0, char_fx.color.g * pulse + (0.02 if vip < 0.5 else 0.06)),
		minf(1.0, char_fx.color.b * pulse),
		char_fx.color.a
	)
	if vip >= 0.5:
		char_fx.offset = Vector2(0.0, sin(t * 4.2 + i * 0.7) * 0.35)
	return true
