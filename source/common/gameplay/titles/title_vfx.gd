class_name TitleVfx
## Title-text VFX (profile, vault preview, nameplate, chat « Title »).
## Looks up [TitleCatalog] (supporter + earned mastery + premium). Never equips
## auras.
##
## THREE FAMILIES, ONE PIPELINE. A supporter or premium title is one colour that
## this script animates; a level-99 [SkillMasterTitles] title paints its own
## gradient in skill_master_title.gdshader and carries a particle layer; a VIP
## donation-ladder title is cast metal from vip_title.gdshader with a
## [VipTitleEffect] emitter stack loaded from its [VipTierProfile]. The whole
## branch between the three is which key the catalog spec carries: `fx` for
## mastery, `vip_tier` for the ladder, neither for everything else.
##
## Every title, all three families, gets the same near-black outline - see
## [constant OUTLINE_COLOR].

const SHADER: Shader = preload("res://source/common/gameplay/titles/title_vfx.gdshader")
const MASTERY_SHADER: Shader = preload("res://source/common/gameplay/titles/skill_master_title.gdshader")
const VIP_SHADER: Shader = preload("res://source/common/gameplay/titles/vip_title.gdshader")
const PULSE_SCRIPT: GDScript = preload("res://source/common/gameplay/titles/title_vfx_pulse.gd")
const PARTICLES_SCRIPT: GDScript = preload("res://source/common/gameplay/titles/title_particles.gd")
const VIP_EFFECT_SCRIPT: GDScript = preload("res://source/common/gameplay/titles/vip_title_effect.gd")
const FALLBACK_CHAT_COLOR: String = "#c8b977"
const PULSE_NODE := "TitleVfxPulse"
const PARTICLES_NODE := "TitleParticles"
const VIP_NODE := "VipTitleFx"

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

## How close a fragment must be to [constant OUTLINE_COLOR] for a title shader to
## treat it as outline and pass it through untouched, rather than repainting it.
##
## Fed to vip_title.gdshader rather than left at that file's own default, so the
## number lives in one place with the colour it goes with. The other two title
## shaders still carry their own copy of it; they should be brought onto this
## constant next time either is opened, which is a change to how eleven live
## mastery titles and twenty supporter/premium ones render and so is not worth
## bundling into an unrelated edit.
const OUTLINE_TOLERANCE: float = 0.22


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
			_drop_layer(existing)
		_apply_particles(host, -1)
		_apply_vip_effect(host, &"")
		_clear_canvas(host)
		return
	var hex: String = str(entry.get("color", ""))
	var tint: Color = Color(hex) if not hex.is_empty() else Color(1, 0.85, 0.45)
	var vip: bool = bool(entry.get("vip", false))
	var style: int = int(entry.get("style", 0))
	# A mastery title carries an `fx` index; everything else does not. That one
	# key is the whole branch - the title families share this entire pipeline.
	var mastery_fx: int = int(entry.get("fx", -1))
	# ...and a ladder title carries a `vip_tier`. Resolved to a PROFILE here
	# rather than trusted as a key, because a tier naming a profile that is not on
	# disk has to degrade to the plain supporter look - a donor seeing an ordinary
	# blue title is a bug worth fixing on Monday, a donor seeing NO title is a
	# refund. tools/verify_vip_titles.gd is what makes that disagreement loud.
	var tier: StringName = TitleCatalog.vip_tier(title)
	var profile: VipTierProfile = VipTierProfile.for_tier(tier)
	if profile == null:
		tier = &""
	# Optional per-title outline. Slayer Master sets one in the catalog and a VIP
	# tier may set one in its profile; everything else falls back to the shared
	# near-black. Whatever it resolves to has to reach BOTH the theme override and
	# the shader uniform, or the shader stops recognising the outline and repaints
	# it with the gradient.
	var outline_hex: String = str(entry.get("outline", ""))
	var outline_col: Color = Color(outline_hex) if not outline_hex.is_empty() else OUTLINE_COLOR
	var outline_px: int = OUTLINE_SIZE_VIP if vip else OUTLINE_SIZE
	if profile != null:
		outline_col = profile.outline_color(outline_col)
		if profile.outline_size > 0:
			outline_px = profile.outline_size
	if host is Label:
		var label: Label = host
		# Both shader families paint their own colour per fragment, so the label
		# under them is left white - tinting it would multiply a chosen palette
		# toward one colour.
		label.self_modulate = tint if (mastery_fx < 0 and profile == null) else Color.WHITE
		label.add_theme_color_override(&"font_color", Color.WHITE)
		label.add_theme_color_override(&"font_outline_color", outline_col)
		label.add_theme_constant_override(&"outline_size", outline_px)
		# Pixel-crisp glyphs. The project already defaults canvas textures to
		# nearest, so this is an assertion rather than a change: these labels are
		# built in code and handed between the nameplate, the profile and the
		# vault, and any one of those could sit under a parent that set filtering
		# for its own art. The title is the one place it must not be inherited.
		label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var mat := ShaderMaterial.new()
		if profile != null:
			mat.shader = VIP_SHADER
			_apply_vip_uniforms(mat, profile, outline_col)
			_apply_vip_shadow(label, profile)
		elif mastery_fx >= 0:
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
		# Title shaders work in LABEL SPACE rather than in UV, because a Label's UV
		# is a font-atlas coordinate and says nothing about where a fragment sits in
		# the word. So the size is fed here once, outside the branch, rather than by
		# each arm - a per-arm copy is how one shader gets left on atlas coordinates
		# while its neighbours are fixed, which is exactly what happened here.
		# Feeding it unconditionally also means a shader that does not declare
		# `rect_size` simply ignores it, so this cannot be forgotten for a new one.
		#
		# reset_size() first: a Label that has just had its text set still reports
		# the PREVIOUS size, which would normalise this title against the last one.
		# TitleVfxPulse re-feeds it every frame; this is only the first value.
		label.reset_size()
		mat.set_shader_parameter(&"rect_size", label.size)
		if profile == null:
			_clear_vip_shadow(label)
		label.material = mat
	if existing == null:
		existing = PULSE_SCRIPT.new()
		existing.name = PULSE_NODE
		host.add_child(existing)
	if existing.has_method(&"configure"):
		# A VIP title is clock-driven exactly like a mastery one: its shader owns
		# the colour and only needs `t` fed to it, because a Label that is not
		# redrawing does not advance TIME.
		#
		# ...but only on a LABEL. The metal shader is mounted in the `host is Label`
		# branch above, so a Button host - the trophy chips on the player profile -
		# has no shader to drive, and clock-driving it anyway would leave the chip
		# blank white with nothing animating it. Falling through to the legacy path
		# instead gives the chip the tier's accent colour, which is the right
		# degradation for a control that cannot carry the full look.
		var clock_driven: bool = profile != null and host is Label
		existing.configure(tint, vip, style, mastery_fx, outline_col, clock_driven, outline_px)
	_apply_particles(host, mastery_fx)
	_apply_vip_effect(host, tier)


## Every uniform vip_title.gdshader takes, fed from the tier's profile. One
## function so the shader has exactly one caller - a uniform added there and
## forgotten here silently renders at its GLSL default, which for a colour is
## flat white and for the outline is a tolerance that repaints the dark backing.
static func _apply_vip_uniforms(
	mat: ShaderMaterial, profile: VipTierProfile, outline_col: Color
) -> void:
	mat.set_shader_parameter(&"metal_high", profile.metal_high)
	mat.set_shader_parameter(&"metal_mid", profile.metal_mid)
	mat.set_shader_parameter(&"metal_low", profile.metal_low)
	mat.set_shader_parameter(&"sheen", profile.sheen)
	mat.set_shader_parameter(&"outline", outline_col)
	mat.set_shader_parameter(&"outline_tolerance", OUTLINE_TOLERANCE)
	mat.set_shader_parameter(&"sweep_speed", profile.sweep_speed)
	mat.set_shader_parameter(&"sweep_width", profile.sweep_width)
	mat.set_shader_parameter(&"sheen_amount", profile.sheen_amount)
	mat.set_shader_parameter(&"pulse_amount", profile.pulse_amount)
	mat.set_shader_parameter(&"pulse_speed", profile.pulse_speed)
	mat.set_shader_parameter(&"grain", profile.grain)
	mat.set_shader_parameter(&"prism", profile.prism)
	mat.set_shader_parameter(&"facets", profile.facets)
	mat.set_shader_parameter(&"fire", profile.fire)
	mat.set_shader_parameter(&"sweep_speed2", profile.sweep_speed2)


## Drop shadow under a ladder title. A theme override rather than part of the
## shader, because Godot draws the shadow as its own pass BEHIND both the glyph
## and the outline - a shader cannot put anything back there, and faking one by
## offsetting inside the fragment would land it on top of the dark backing that
## the outline exists to be.
static func _apply_vip_shadow(label: Label, profile: VipTierProfile) -> void:
	label.add_theme_color_override(&"font_shadow_color", profile.shadow)
	label.add_theme_constant_override(&"shadow_offset_x", profile.shadow_offset.x)
	label.add_theme_constant_override(&"shadow_offset_y", profile.shadow_offset.y)


static func _clear_vip_shadow(label: Label) -> void:
	label.remove_theme_color_override(&"font_shadow_color")
	label.remove_theme_constant_override(&"shadow_offset_x")
	label.remove_theme_constant_override(&"shadow_offset_y")


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
			_drop_layer(existing)
		return
	var control: Control = host as Control
	if control == null:
		return
	if existing != null and int(existing.get(&"fx")) != mastery_fx:
		# Different title: rebuild rather than reconfigure. The emitter set is
		# constructed in _ready and is not designed to be mutated afterwards.
		_drop_layer(existing)
		existing = null
	if existing == null:
		var layer: Node2D = PARTICLES_SCRIPT.new()
		layer.name = PARTICLES_NODE
		layer.fx = mastery_fx
		control.add_child(layer)
		existing = layer
	_place_layer(control, existing)


## Mount, re-point or tear down the VIP ladder's particle layer.
##
## Deliberately a SEPARATE node from the mastery layer rather than one layer that
## can be either. The two are built from different data, rebuild on different
## keys, and a player can only ever wear one title - so a single node would need
## to know which family built it in order to decide whether it needs replacing,
## which is exactly the state the two-node version does not have to keep.
##
## The teardown half is the one that matters: a donor who switches from Diamond
## to a quest title must not leave an emitter stack running over their head for
## the rest of the session.
static func _apply_vip_effect(host: CanvasItem, tier: StringName) -> void:
	var existing: Node = host.get_node_or_null(VIP_NODE)
	if tier == &"":
		if existing != null:
			_drop_layer(existing)
		return
	var control: Control = host as Control
	if control == null:
		return
	if existing != null and StringName(existing.get(&"tier")) != tier:
		_drop_layer(existing)
		existing = null
	if existing == null:
		var layer: Node2D = VIP_EFFECT_SCRIPT.new()
		layer.name = VIP_NODE
		layer.tier = tier
		control.add_child(layer)
		existing = layer
	_place_layer(control, existing)


## Centre a particle layer on its label and match its laid-out size.
##
## reset_size() first: a Label that has just had its text set still reports the
## PREVIOUS size until it re-fits, so without it the emitters are sized to the
## title before this one - which is invisible on a rename between two titles of
## similar length and glaring on a switch from "Gilded" to "Platinum
## Contributor".
## Unparent a particle layer, THEN queue it for deletion.
##
## queue_free() alone leaves the node a child until the end of the frame, and
## get_node_or_null() keeps finding it there. Anything that re-applies a title
## twice in one frame - a nameplate rebuilding while a display_title sync lands,
## the vault redrawing a row - then finds the dying layer, decides it matches,
## keeps it, and watches it disappear at frame end. Removing it first makes the
## teardown observable immediately, which is both the correct behaviour and what
## lets tools/verify_vip_titles.gd assert it at all.
static func _drop_layer(layer: Node) -> void:
	var parent: Node = layer.get_parent()
	if parent != null:
		parent.remove_child(layer)
	layer.queue_free()


static func _place_layer(control: Control, layer: Node) -> void:
	control.reset_size()
	layer.set(&"position", control.size * 0.5)
	if layer.has_method(&"fit_to"):
		layer.call(&"fit_to", control.size)


static func _clear_canvas(host: CanvasItem) -> void:
	if host is Label:
		var label: Label = host
		label.material = null
		label.self_modulate = Color(1, 0.85, 0.45, 1)
		label.remove_theme_color_override(&"font_outline_color")
		label.remove_theme_constant_override(&"outline_size")
		# The shadow is a theme override, so it survives the material being
		# cleared. Left behind, a player switching off a ladder title keeps its
		# coloured drop shadow under an ordinary one for the rest of the session.
		_clear_vip_shadow(label)
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
