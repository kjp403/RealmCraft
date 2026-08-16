class_name TitleVfx
## Title-text VFX (profile, vault preview, nameplate, chat « Title »).
## Looks up [TitleCatalog] (supporter + premium). Never equips auras.

const SHADER: Shader = preload("res://source/common/gameplay/titles/title_vfx.gdshader")
const PULSE_SCRIPT: GDScript = preload("res://source/common/gameplay/titles/title_vfx_pulse.gd")
const FALLBACK_CHAT_COLOR: String = "#c8b977"
const PULSE_NODE := "TitleVfxPulse"


static func apply_to_label(label: Label, title: String) -> void:
	if label == null:
		return
	_apply_to_canvas(label, title)


static func apply_to_button(button: Button, title: String) -> void:
	if button == null:
		return
	_apply_to_canvas(button, title)


static func _apply_to_canvas(host: CanvasItem, title: String) -> void:
	var entry: Dictionary = TitleCatalog.spec(title)
	var existing: Node = host.get_node_or_null(PULSE_NODE)
	if entry.is_empty():
		if existing != null:
			existing.queue_free()
		_clear_canvas(host)
		return
	var hex: String = str(entry.get("color", ""))
	var tint: Color = Color(hex) if not hex.is_empty() else Color(1, 0.85, 0.45)
	var vip: bool = bool(entry.get("vip", false))
	var style: int = int(entry.get("style", 0))
	if host is Label:
		var label: Label = host
		label.self_modulate = tint
		label.add_theme_color_override(&"font_color", Color.WHITE)
		label.add_theme_color_override(&"font_outline_color", tint.darkened(0.2))
		label.add_theme_constant_override(&"outline_size", 10 if vip else 6)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter(&"glow_color", tint)
		mat.set_shader_parameter(&"vip", 1.0 if vip else 0.0)
		mat.set_shader_parameter(&"gold", 1.0 if style == 1 or hex == SupporterTitles.COLOR_CUSTOM else 0.0)
		mat.set_shader_parameter(&"style", float(style))
		label.material = mat
	if existing == null:
		existing = PULSE_SCRIPT.new()
		existing.name = PULSE_NODE
		host.add_child(existing)
	if existing.has_method(&"configure"):
		existing.configure(tint, vip, style)


static func _clear_canvas(host: CanvasItem) -> void:
	if host is Label:
		var label: Label = host
		label.material = null
		label.self_modulate = Color(1, 0.85, 0.45, 1)
		label.remove_theme_color_override(&"font_outline_color")
		label.remove_theme_constant_override(&"outline_size")
	elif host is Button:
		var btn: Button = host
		btn.remove_theme_color_override(&"font_color")
		btn.remove_theme_color_override(&"font_disabled_color")
		btn.remove_theme_color_override(&"font_outline_color")
		btn.remove_theme_constant_override(&"outline_size")


static func _clear_label(label: Label) -> void:
	_clear_canvas(label)


static func chat_bbcode(title: String) -> String:
	var entry: Dictionary = TitleCatalog.spec(title)
	if entry.is_empty():
		return "[color=%s]« %s »[/color]" % [FALLBACK_CHAT_COLOR, title]
	var hex: String = str(entry.get("color", FALLBACK_CHAT_COLOR))
	var vip: int = 1 if bool(entry.get("vip", false)) else 0
	var style: int = int(entry.get("style", 0))
	return "[titlefx vip=%d style=%d][color=%s]« %s »[/color][/titlefx]" % [
		vip, style, hex, title
	]


static func install_on(rtl: RichTextLabel) -> TitleFxEffect:
	if rtl == null:
		return null
	rtl.bbcode_enabled = true
	var fx := TitleFxEffect.new()
	rtl.install_effect(fx)
	return fx
