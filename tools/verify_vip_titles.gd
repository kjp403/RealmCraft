extends SceneTree
## Verify the four-rung VIP donation title ladder end to end.
##   godot --headless --path . -s tools/verify_vip_titles.gd
##
## Everything checked here fails SILENTLY in the game, which is the whole reason
## the tool exists:
##
##   * A tier whose profile .tres is missing renders as an ordinary blue premium
##     title. Nothing errors. It just quietly is not the thing it is meant to be.
##   * A ladder title that leaves TitleCatalog.PREMIUM stops being deleted from
##     non-staff players by CommandPermissions.strip_unreleased_vfx, and the
##     unreleased set is live on player accounts with nothing to announce it. That
##     membership IS the vault gate; nothing else here enforces it.
##   * A layer's span_scale creeping past the cap turns a title into a character
##     aura, which this game deliberately does not have.
##   * A rung GIVEN to a donor without a VaultGrants entitlement is worn until
##     their next zone change and then silently is not - the strip takes it back,
##     nothing is logged, and the only symptom is an angry paying customer.
##   * A smoke or fog layer left additive renders as nothing at all: additive
##     black is invisible. The tier looks like it simply has fewer layers.
##   * An emitter over budget costs frame time only in a crowd, which is exactly
##     where these are worn and exactly where nobody is testing.
##
## Runs under `-s` on purpose - the whole title pipeline lives in common/ and
## touches no autoload, so it can be built and measured without a scene. Expect
## the usual wall of `Identifier not found: ClientState` from unrelated scripts.

## Total checks this tool is expected to run. A GDScript runtime error does not
## stop the script, it abandons the CURRENT FUNCTION and carries on - so a
## section that dies half way through simply prints fewer lines and the tool
## still reports green. Counting is the guard. Same reason
## tools/verify_skill_master_titles.gd counts.
const EXPECTED_CHECKS: int = 48

## An outline has to be dark enough to back bright letters over pale ground.
## Slayer Master's crimson override sits around 0.04; anything past this is not
## a backing any more.
const MAX_OUTLINE_LUMINANCE: float = 0.16

## Below this, a colour is dark enough that additive blending renders it as
## nothing. Anything under it must be a mix-blended layer.
const DARK_LUMINANCE: float = 0.18

var _fail: int = 0
var _ran: int = 0


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), label)
	_ran += 1
	if not ok:
		_fail += 1


func _initialize() -> void:
	_check_ladder()
	_check_profiles()
	_check_emitters()
	_check_pipeline()
	_check_grants()
	if _ran != EXPECTED_CHECKS:
		print("  FAIL  ran %d checks, expected %d - a section aborted early"
			% [_ran, EXPECTED_CHECKS])
		_fail += 1
	print("VIP_TITLES %s failures=%d checks=%d"
		% ["FAIL" if _fail > 0 else "PASS", _fail, _ran])
	quit(1 if _fail > 0 else 0)


func _luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _check_ladder() -> void:
	print("-- ladder --")
	var slugs: PackedStringArray = TitleCatalog.vip_tier_slugs()
	_check(slugs.size() == 4, "four ladder tiers (got %d)" % slugs.size())

	var no_profile: PackedStringArray = []
	var wrong_key: PackedStringArray = []
	var accent_drift: PackedStringArray = []
	var name_drift: PackedStringArray = []
	for slug: String in slugs:
		var entry: Dictionary = TitleCatalog.PREMIUM[slug]
		var tier: StringName = StringName(str(entry.get("vip_tier", "")))
		var profile: VipTierProfile = VipTierProfile.for_tier(tier)
		if profile == null:
			no_profile.append(slug)
			continue
		if profile.tier != tier:
			wrong_key.append("%s -> %s" % [slug, profile.tier])
		# The accent is duplicated: once as a hex in the catalog (what chat and the
		# vault row read) and once as a Color in the profile. They drift the moment
		# somebody retunes one of them, and the symptom is a title whose chat
		# bracket does not match the letters over its own head.
		if not profile.accent.is_equal_approx(Color(str(entry.get("color", "")))):
			accent_drift.append(slug)
		if profile.display_name != str(entry.get("name", "")):
			name_drift.append(slug)
	_check(no_profile.is_empty(), "every tier loads a profile %s" % str(no_profile))
	_check(wrong_key.is_empty(), "profile.tier matches its slug %s" % str(wrong_key))
	_check(accent_drift.is_empty(), "accent matches the catalog colour %s" % str(accent_drift))
	_check(name_drift.is_empty(), "profile name matches the catalog name %s" % str(name_drift))

	# THE VAULT GATE, and the only thing enforcing it.
	#
	# CommandPermissions.strip_unreleased_vfx deletes any title matching
	# is_premium_name from a non-staff player on EVERY instance spawn - display
	# title, unlocked list and pinned trophies alike. That predicate is what keeps
	# the ladder staff-only, so a rung that stops satisfying it is not "slightly
	# less gated", it is released, silently, to whoever already has it.
	var ungated: PackedStringArray = []
	var unresolved: PackedStringArray = []
	var grantable: PackedStringArray = []
	for slug: String in slugs:
		var title: String = str((TitleCatalog.PREMIUM[slug] as Dictionary).get("name", ""))
		if not TitleCatalog.is_premium_name(title):
			ungated.append(title)
		if TitleCatalog.vip_tier(title) == &"":
			unresolved.append(title)
		# ...and the other half of the gate: /supporter resolves SupporterTitles
		# slugs and nothing else, so a rung must not appear there. If one did, a
		# senior_admin could hand it out and the strip above would take it straight
		# back off - a grant that silently undoes itself a zone change later.
		if not SupporterTitles.resolve(title).is_empty():
			grantable.append(title)
	_check(ungated.is_empty(), "every rung is premium, so strip_unreleased_vfx gates it %s"
		% str(ungated))
	_check(unresolved.is_empty(), "TitleCatalog resolves every tier by name %s" % str(unresolved))
	_check(grantable.is_empty(), "no rung is grantable with /supporter %s" % str(grantable))

	# The vault shelf is the ONLY place these are meant to be reachable, and it is
	# served straight from vault_roster() - see titles.state.gd, which is itself
	# staff-gated. A rung missing from the roster is a rung nobody can test.
	var roster: Array = TitleCatalog.vault_roster()
	var in_roster: int = 0
	for row: Variant in roster:
		if TitleCatalog.vip_tier(str((row as Dictionary).get("name", ""))) != &"":
			in_roster += 1
	_check(in_roster == 4, "all four appear on the vault shelf (got %d)" % in_roster)

	_check(
		TitleCatalog.spec("Diamond Donator").get("vip_tier", &"") == &"diamond",
		"the catalog finds a tier by display name"
	)


func _check_profiles() -> void:
	print("-- profiles --")
	var empty: PackedStringArray = []
	var too_many: PackedStringArray = []
	var all_detail: PackedStringArray = []
	var invisible: PackedStringArray = []
	var pale_outline: PackedStringArray = []
	var flat_metal: PackedStringArray = []
	var aura: PackedStringArray = []
	for slug: String in TitleCatalog.vip_tier_slugs():
		var tier: StringName = StringName(str((TitleCatalog.PREMIUM[slug] as Dictionary).get("vip_tier", "")))
		var profile: VipTierProfile = VipTierProfile.for_tier(tier)
		if profile == null:
			continue
		if profile.layers.is_empty():
			empty.append(slug)
			continue
		if profile.layers.size() > VipTitleEffect.MAX_LAYERS:
			too_many.append("%s=%d" % [slug, profile.layers.size()])
		# At medium LOD every `detail` layer stops. A tier made entirely of them
		# would vanish in a crowd rather than thin out.
		var signature: int = 0
		for layer: VipParticleLayer in profile.layers:
			if not layer.detail:
				signature += 1
			# THE ADDITIVE BLACK TRAP. A smoke or fog layer is dark by design and
			# additive blending of a dark colour adds nothing - the layer is built,
			# ticks, costs frame time and draws NOTHING. Silver is the tier this
			# catches; it is also the tier most likely to be retuned.
			if layer.additive and _luminance(layer.color_mid) < DARK_LUMINANCE:
				invisible.append("%s/%s" % [slug, layer.id])
			# THE AURA RULE. Titles in this game are text VFX; a character aura is
			# a different product decision and not one a profile retune gets to
			# make. VipTitleEffect clamps this, but a clamp alone would let a .tres
			# ask for 3.0 and silently render 1.8 - so it fails here instead.
			if layer.span_scale > VipTitleEffect.MAX_SPAN_SCALE:
				aura.append("%s/%s=%.2f" % [slug, layer.id, layer.span_scale])
		if signature == 0:
			all_detail.append(slug)
		if _luminance(profile.outline_color(TitleVfx.OUTLINE_COLOR)) > MAX_OUTLINE_LUMINANCE:
			pale_outline.append(slug)
		# The metal ramp has to actually descend, or the letters read as a flat
		# fill and the whole cast-metal treatment is doing nothing.
		if _luminance(profile.metal_high) <= _luminance(profile.metal_low):
			flat_metal.append(slug)
	_check(empty.is_empty(), "every profile has emitter layers %s" % str(empty))
	_check(too_many.is_empty(), "at most %d layers per tier %s"
		% [VipTitleEffect.MAX_LAYERS, str(too_many)])
	_check(all_detail.is_empty(), "every tier keeps a signature layer at LOD %s" % str(all_detail))
	_check(invisible.is_empty(), "no dark layer is additive (would draw nothing) %s" % str(invisible))
	_check(pale_outline.is_empty(), "outlines stay dark enough to back the letters %s"
		% str(pale_outline))
	_check(flat_metal.is_empty(), "the metal ramp descends %s" % str(flat_metal))
	_check(aura.is_empty(), "no layer emits past span_scale %.1f (title, not aura) %s"
		% [VipTitleEffect.MAX_SPAN_SCALE, str(aura)])


func _check_emitters() -> void:
	print("-- emitters --")
	var gpu: PackedStringArray = []
	var over_budget: PackedStringArray = []
	var over_total: PackedStringArray = []
	var wrong_depth: PackedStringArray = []
	var no_cull: PackedStringArray = []
	var emitters: int = 0
	for slug: String in TitleCatalog.vip_tier_slugs():
		var tier: StringName = StringName(str((TitleCatalog.PREMIUM[slug] as Dictionary).get("vip_tier", "")))
		var layer: VipTitleEffect = VipTitleEffect.new()
		layer.tier = tier
		# build() explicitly rather than parenting and waiting for _ready: a node
		# added during _initialize() does not get _ready until the tree ticks, and
		# this tool quits before that - so every emitter would read as absent.
		layer.build()
		if layer.z_index != VipTitleEffect.NAMEPLATE_Z or layer.z_as_relative:
			wrong_depth.append(slug)
		if layer.get_node_or_null("Cull") == null or layer.get_node_or_null("Lod") == null:
			no_cull.append(slug)
		for child: Node in layer.get_children():
			if child is GPUParticles2D:
				gpu.append(slug)
				continue
			var p: CPUParticles2D = child as CPUParticles2D
			if p == null:
				continue
			emitters += 1
			if p.amount < VipTitleEffect.MIN_AMOUNT or p.amount > VipTitleEffect.MAX_AMOUNT:
				over_budget.append("%s/%s amount=%d" % [slug, p.name, p.amount])
			if p.lifetime < VipTitleEffect.MIN_LIFETIME or p.lifetime > VipTitleEffect.MAX_LIFETIME:
				over_budget.append("%s/%s life=%.2f" % [slug, p.name, p.lifetime])
		if layer.total_amount() > VipTitleEffect.MAX_TOTAL_AMOUNT:
			over_total.append("%s=%d" % [slug, layer.total_amount()])
		layer.free()
	_check(emitters > 0, "every tier builds emitters (got %d)" % emitters)
	_check(gpu.is_empty(), "CPUParticles2D only, web-safe %s" % str(gpu))
	_check(over_budget.is_empty(), "amount %d-%d and life %.1f-%.1fs %s" % [
		VipTitleEffect.MIN_AMOUNT, VipTitleEffect.MAX_AMOUNT,
		VipTitleEffect.MIN_LIFETIME, VipTitleEffect.MAX_LIFETIME, str(over_budget),
	])
	_check(over_total.is_empty(), "at most %d particles per title %s"
		% [VipTitleEffect.MAX_TOTAL_AMOUNT, str(over_total)])
	_check(wrong_depth.is_empty(), "particle layers sit at absolute z %d %s"
		% [VipTitleEffect.NAMEPLATE_Z, str(wrong_depth)])
	_check(no_cull.is_empty(), "every tier builds its cull notifier and LOD timer %s" % str(no_cull))


## The pipeline, against a real Label - the same entry point the nameplate, the
## profile and the vault all call. Checking the parts in isolation would miss the
## thing that actually breaks: a title switching from one family to another and
## leaving the previous family's nodes and overrides behind.
func _check_pipeline() -> void:
	print("-- pipeline --")
	var label: Label = Label.new()
	label.text = "« Diamond Donator »"
	TitleVfx.apply_to_label(label, "Diamond Donator")

	var mat: ShaderMaterial = label.material as ShaderMaterial
	_check(mat != null and mat.shader == TitleVfx.VIP_SHADER, "a ladder title gets vip_title.gdshader")
	var profile: VipTierProfile = VipTierProfile.for_tier(&"diamond")
	var pulse: Node = label.get_node_or_null(TitleVfx.PULSE_NODE)
	var uniform_outline: Variant = mat.get_shader_parameter(&"outline") if mat != null else null
	_check(
		uniform_outline is Color
			and (uniform_outline as Color).is_equal_approx(profile.outline_color(TitleVfx.OUTLINE_COLOR)),
		"the shader is told the same outline the theme override got"
	)
	_check(
		label.get_theme_color(&"font_outline_color").is_equal_approx(
			profile.outline_color(TitleVfx.OUTLINE_COLOR)
		),
		"the theme override carries the resolved outline"
	)
	_check(
		label.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"title text is filtered nearest"
	)

	# The per-tier outline WEIGHT, checked twice on purpose - once as mounted and
	# once after the pulse has ticked. TitleVfxPulse re-asserts the outline every
	# single frame, so a size applied only at mount time is replaced by the shared
	# constant one frame later and the tier silently loses the heavy black border
	# that is most of what it was bought for. Checking only the first would pass
	# with the bug present.
	var want_px: int = profile.outline_size
	_check(
		want_px > 0 and label.get_theme_constant(&"outline_size") == want_px,
		"the tier's outline weight is mounted (want %d, got %d)"
			% [want_px, label.get_theme_constant(&"outline_size")]
	)
	if pulse != null and pulse.has_method(&"_apply"):
		pulse.call(&"_apply", 1.0)
	_check(
		label.get_theme_constant(&"outline_size") == want_px,
		"...and the pulse re-asserts THAT size, not the shared one"
	)

	# EVERY uniform the shader declares must actually be fed. A uniform added to
	# the .gdshader and forgotten in TitleVfx does not error - it renders at its
	# GLSL default, which for a colour is flat white, for `facets` is a smooth
	# ramp, and for `outline` is a tolerance that repaints the dark backing the
	# legibility guarantee depends on. All of those read as "the tier needs
	# retuning" rather than as a missing line of code.
	var unfed: PackedStringArray = []
	for prop: Dictionary in TitleVfx.VIP_SHADER.get_shader_uniform_list():
		var uname: String = str(prop.get("name", ""))
		if mat != null and mat.get_shader_parameter(StringName(uname)) == null:
			unfed.append(uname)
	_check(unfed.is_empty(), "every vip_title.gdshader uniform is fed %s" % str(unfed))
	_check(label.has_theme_color_override(&"font_shadow_color"), "a ladder title gets its drop shadow")
	_check(label.self_modulate.is_equal_approx(Color.WHITE),
		"the label is left white so the metal ramp arrives unmultiplied")

	var fx: Node = label.get_node_or_null(TitleVfx.VIP_NODE)
	_check(fx != null and StringName(fx.get(&"tier")) == &"diamond", "the VIP layer is mounted")
	_check(pulse != null and bool(pulse.get(&"clock_driven")), "the pulse node drives the shader clock")

	# Switching tiers must REBUILD, not reconfigure: the emitter set is built once
	# and is not designed to be mutated.
	TitleVfx.apply_to_label(label, "Silver Contributor")
	var swapped: Node = label.get_node_or_null(TitleVfx.VIP_NODE)
	_check(swapped != null and StringName(swapped.get(&"tier")) == &"silver",
		"switching tiers re-points the layer")

	# ...and switching families has to tear the ladder's nodes and overrides down.
	# A donor who puts on a mastery title must not keep a Diamond emitter stack
	# and a blue drop shadow running over their head for the rest of the session.
	TitleVfx.apply_to_label(label, "Forge Master")
	_check(label.get_node_or_null(TitleVfx.VIP_NODE) == null,
		"a mastery title tears the VIP layer down")
	_check(label.get_node_or_null(TitleVfx.PARTICLES_NODE) != null,
		"a mastery title still mounts its own particle layer")

	TitleVfx.apply_to_label(label, "")
	_check(not label.has_theme_color_override(&"font_shadow_color"),
		"clearing the title drops the drop shadow")
	_check(label.material == null, "clearing the title drops the shader")
	label.free()


## The grant path, against the REAL strip.
##
## strip_unreleased_vfx is what makes the ladder vault-only, and it is also the
## thing most likely to quietly eat a donor's title: it runs on EVERY instance
## spawn, it says nothing when it fires, and the difference between "leak" and
## "gift" is one lookup that a future edit could drop without any test noticing.
## So these checks call the actual function rather than re-implementing its
## predicate - a copy of the rule here would keep passing after the rule changed.
##
## A bare PlayerResource has no server_roles and AdminConfig has no entry for it,
## so effective_priority() returns 0 without ever dereferencing the instance,
## which is why null is a safe argument here.
func _check_grants() -> void:
	print("-- grants --")
	var pr: PlayerResource = PlayerResource.new()
	_check(not VaultGrants.has_title(pr, "Diamond Donator"), "a fresh character has no grants")
	_check(VaultGrants.grant_title(pr, "Diamond Donator"), "granting a title reports the change")
	_check(
		VaultGrants.has_title(pr, "diamond donator"),
		"grants are case-insensitive (admins type in a hurry)"
	)
	_check(
		not VaultGrants.grant_title(pr, "Diamond Donator"),
		"re-granting is a no-op, not a duplicate"
	)
	var packed: int = VaultSkins.pack(PlayerSkins.starter_skin_id(), VaultSkins.STYLE_GOLD)
	VaultGrants.grant_skin(pr, packed)
	_check(VaultGrants.has_skin(pr, packed), "skin grants round-trip through their token")

	# THE WHOLE POINT. Same title, same character, one with the entitlement and
	# one without - the strip must treat them differently.
	var leaked: PlayerResource = PlayerResource.new()
	leaked.display_title = "Diamond Donator"
	leaked.titles_unlocked = PackedStringArray(["Diamond Donator"])
	leaked.vault_skin_id = packed
	CommandPermissions.strip_unreleased_vfx(leaked, null)
	_check(
		leaked.display_title.is_empty() and leaked.titles_unlocked.is_empty(),
		"an UNGRANTED rung is stripped (the vault gate still holds)"
	)
	_check(leaked.vault_skin_id == 0, "an UNGRANTED vault skin is stripped")

	var donor: PlayerResource = PlayerResource.new()
	donor.display_title = "Diamond Donator"
	donor.titles_unlocked = PackedStringArray(["Diamond Donator"])
	donor.vault_skin_id = packed
	VaultGrants.grant_title(donor, "Diamond Donator")
	VaultGrants.grant_skin(donor, packed)
	CommandPermissions.strip_unreleased_vfx(donor, null)
	_check(
		donor.display_title == "Diamond Donator" and donor.titles_unlocked.has("Diamond Donator"),
		"a GRANTED rung survives the strip"
	)
	_check(donor.vault_skin_id == packed, "a GRANTED vault skin survives the strip")
