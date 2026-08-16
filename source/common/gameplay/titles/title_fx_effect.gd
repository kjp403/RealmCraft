class_name TitleFxEffect
extends RichTextEffect
## Chat-side title VFX. Animates the « Title » glyphs.
## Tag: [titlefx vip=0|1 style=0]...[/titlefx]

var bbcode: String = "titlefx"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var vip: float = float(char_fx.env.get("vip", 0.0))
	var style: float = float(char_fx.env.get("style", 0.0))
	var t: float = char_fx.elapsed_time
	var i: float = float(char_fx.relative_index)
	var speed: float = 2.6 if vip < 0.5 else 4.0
	if style > 1.5 and style < 3.5:
		speed = 2.0
	var wave: float = sin(t * speed + i * 0.55)
	var pulse: float = 0.62 + (0.48 if vip < 0.5 else 0.72) * (0.5 + 0.5 * wave)
	var flash: float = 0.5 + 0.5 * sin(t * (1.8 if vip < 0.5 else 2.8) - i * 0.9)
	var shine: Color = Color(1.0, 0.97, 0.92)
	if style > 0.5 and style < 1.5:
		shine = Color(1.0, 0.92, 0.42)
	var base: Color = char_fx.color
	char_fx.color = Color(
		minf(1.0, base.r * pulse + shine.r * flash * 0.35),
		minf(1.0, base.g * pulse + shine.g * flash * 0.35),
		minf(1.0, base.b * pulse + shine.b * flash * 0.28),
		base.a
	)
	char_fx.offset = Vector2(0.0, sin(t * 5.0 + i * 0.8) * (1.15 if vip >= 0.5 else 0.55))
	return true
