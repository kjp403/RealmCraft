class_name TitleVfx
## Title-text VFX (profile, vault preview, nameplate, chat « Title »).
## Looks up [TitleCatalog] (supporter + earned mastery + premium). Never equips
## auras.
##
## TWO FAMILIES, ONE PIPELINE. A supporter or premium title is one colour that
## this script animates; a level-99 [SkillMasterTitles] title paints its own
## gradient in skill_master_title.gdshader and carries a particle layer. The only
## branch between them is whether the catalog spec has an `fx` key.
##
## Every title, both families, gets the same near-black outline - see
## [constant OUTLINE_COLOR].

const SHADER: Shader = preload("res://source/common/gameplay/titles/title_vfx.gdshader")
const MASTERY_SHADER: Shader = preload("res://source/common/gameplay/titles/skill_master_title.gdshader")
const PULSE_SCRIPT: GDScript = preload("res://source/common/gameplay/titles/title_vfx_pulse.gd")
const PARTICLES_SCRIPT: GDScript = preload("res://source/common/gameplay/titles/title_particles.gd")
const FALLBACK_CHAT_COLOR: String = "#c8b977"
const PULSE_NODE := "TitleVfxPulse"
const PARTICLES_NODE := "TitleParticles"

## The dark backing every title outline uses.
##
## Title shaders are bright by design and map tiles are not reliably dark - a
## snow field, a desert, a lit forge floor. Tinting the outline with the title's
## own colour (what this used to do) means the brightest titles have the LEAST
## contrast exactly where they need the most, and a white-gold title over pale
## sand becomes unreadable. A fixed near-black backing is the only thing that
## holds on every background, and it costs nothing.
const OUTLINE_COLOR: Color = Color("#0b0b10")
## Outline thickness. Godot's outline_size is in the label's own units and these
## labels are drawn scaled down hard on nameplates, so these are large numbers
## that land as roughly 1-2 px on screen.
const OUTLINE_SIZE: int = 8
const OUTLINE_SIZE_VIP: int = 12


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
		_apply_particles(host, -1)
		_clear_canvas(host)
		return
	var hex: String = str(entry.get("color", ""))
	var tint: Color = Color(hex) if not hex.is_empty() else Color(1, 0.85, 0.45)
	var vip: bool = bool(entry.get("vip", false))
	var style: int = int(entry.get("style", 0))
	# A mastery title carries an `fx` index; everything else does not. That one
	# key is the whole branch - the two title families share this entire pipeline.
	var mastery_fx: int = int(entry.get("fx", -1))
	# Optional per-title outline. Only Slayer Master sets one; everything else
	# falls back to the shared near-black. Whatever it resolves to has to reach
	# BOTH the theme override and the shader uniform, or the shader stops
	# recognising the outline and repaints it with the gradient.
	var outline_hex: String = str(entry.get("outline", ""))
	var outline_col: Color = Color(outline_hex) if not outline_hex.is_empty() else OUTLINE_COLOR
	if host is Label:
		var label: Label = host
		label.self_modulate = tint if mastery_fx < 0 else Color.WHITE
		label.add_theme_color_override(&"font_color", Color.WHITE)
		label.add_theme_color_override(&"font_outline_color", outline_col)
		label.add_theme_constant_override(
			&"outline_size", OUTLINE_SIZE_VIP if vip else OUTLINE_SIZE
		)
		var mat := ShaderMaterial.new()
		if mastery_fx >= 0:
			# Mastery looks paint their own gradient, so the label is left white
			# above and the shader multiplies its palette in from `base`.
			mat.shader = MASTERY_SHADER
			mat.set_shader_parameter(&"fx", mastery_fx)
			mat.set_shader_parameter(&"base", tint)
			mat.set_shader_parameter(&"outline", outline_col)
		else:
			mat.shader = SHADER
			mat.set_shader_parameter(&"glow_color", tint)
			mat.set_shader_parameter(&"vip", 1.0 if vip else 0.0)
			mat.set_shader_parameter(&"gold", 1.0 if style == 1 or hex == SupporterTitles.COLOR_CUSTOM else 0.0)
			mat.set_shader_parameter(&"style", float(style))
			mat.set_shader_parameter(&"outline", outline_col)
		label.material = mat
	if existing == null:
		existing = PULSE_SCRIPT.new()
		existing.name = PULSE_NODE
		host.add_child(existing)
	if existing.has_method(&"configure"):
		existing.configure(tint, vip, style, mastery_fx, outline_col)
	_apply_particles(host, mastery_fx)


## Mount, re-point or tear down the particle layer for a title.
##
## Only the eleven mastery titles have one. Everything else - supporter, premium,
## quest titles - clears it, which matters because a player switching from a
## mastery title to a plain one must not leave an orphaned emitter running over
## their head for the rest of the session.
##
## The layer is a child of the label, so it inherits the nameplate's heavy
## downscale - which is correct: the emitters are sized in label space by fit_to,
## and shrinking them with the text keeps the effect in proportion at any zoom.
static func _apply_particles(host: CanvasItem, mastery_fx: int) -> void:
	var existing: Node = host.get_node_or_null(PARTICLES_NODE)
	if mastery_fx < 0:
		if existing != null:
			existing.queue_free()
		return
	var control: Control = host as Control
	if control == null:
		return
	if existing != null and int(existing.get(&"fx")) != mastery_fx:
		# Different title: rebuild rather than reconfigure. The emitter set is
		# constructed in _ready and is not designed to be mutated afterwards.
		existing.queue_free()
		existing = null
	if existing == null:
		var layer: Node2D = PARTICLES_SCRIPT.new()
		layer.name = PARTICLES_NODE
		layer.fx = mastery_fx
		control.add_child(layer)
		existing = layer
	# Centre on the label and match its laid-out size. reset_size() first: a
	# Label that has just had its text set still reports the previous size until
	# it re-fits, which would size the emitters to the title before this one.
	control.reset_size()
	existing.position = control.size * 0.5
	if existing.has_method(&"fit_to"):
		existing.fit_to(control.size)


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
