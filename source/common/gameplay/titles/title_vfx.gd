class_name TitleVfx
## Title-text VFX (profile label + chat « Title »). Looks up [TitleCatalog]
## (supporter + premium). Never equips auras, halos, trails, or vault cosmetics.

const SHADER: Shader = preload("res://source/common/gameplay/titles/title_vfx.gdshader")
const FALLBACK_CHAT_COLOR: String = "#c8b977"


static func apply_to_label(label: Label, title: String) -> void:
	if label == null:
		return
	var entry: Dictionary = TitleCatalog.spec(title)
	if entry.is_empty():
		_clear_label(label)
		return
	var hex: String = str(entry.get("color", ""))
	var tint: Color = Color(hex) if not hex.is_empty() else Color(1, 0.85, 0.45)
	var vip: bool = bool(entry.get("vip", false))
	var style: float = float(entry.get("style", 0.0))
	var gold: bool = hex == SupporterTitles.COLOR_CUSTOM or is_equal_approx(style, 1.0)
	label.self_modulate = tint
	label.add_theme_color_override(&"font_outline_color", tint.darkened(0.28))
	label.add_theme_constant_override(&"outline_size", 6 if vip else 3)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"glow_color", tint)
	mat.set_shader_parameter(&"vip", 1.0 if vip else 0.0)
	mat.set_shader_parameter(&"gold", 1.0 if gold else 0.0)
	mat.set_shader_parameter(&"style", style)
	label.material = mat


static func _clear_label(label: Label) -> void:
	label.material = null
	label.self_modulate = Color(1, 0.85, 0.45, 1)
	label.remove_theme_color_override(&"font_outline_color")
	label.remove_theme_constant_override(&"outline_size")


static func chat_bbcode(title: String) -> String:
	var entry: Dictionary = TitleCatalog.spec(title)
	if entry.is_empty():
		return "[color=%s]« %s »[/color]" % [FALLBACK_CHAT_COLOR, title]
	var hex: String = str(entry.get("color", FALLBACK_CHAT_COLOR))
	var vip: int = 1 if bool(entry.get("vip", false)) else 0
	var style: int = int(entry.get("style", 0))
	return "[color=%s][titlefx vip=%d style=%d]« %s »[/titlefx][/color]" % [
		hex, vip, style, title
	]


static func install_on(rtl: RichTextLabel) -> TitleFxEffect:
	if rtl == null:
		return null
	var fx := TitleFxEffect.new()
	rtl.install_effect(fx)
	return fx
