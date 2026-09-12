extends SceneTree
## Verify the eight colour-matched title/aura/dye sets end to end.
##   godot --headless --path . -s tools/verify_cosmetic_themes.gd
##
## Everything checked here fails SILENTLY in the game, which is the whole reason
## the tool exists:
##
##   * A theme whose catalog hex has drifted from its dye renders a title in one
##     colour, an aura in another and a body in a third. Nothing errors. The set
##     simply stops being a set, which is the only thing anyone is paying for.
##   * A themed title that loses its `theme` key falls back to the ordinary
##     premium treatment - a plain coloured name - and looks like a title that
##     merely needs retuning rather than one missing its whole render path.
##   * An aura slug with no registry entry is not for sale and cannot be equipped.
##     The title it pairs with still sells, so the shop offers half a set.
##   * A title priced over the 500-coin cap is a real-money price change nobody
##     approved; PremiumCatalog is the single source the master re-derives from.
##   * A layer left additive with a dark colour draws NOTHING - additive black is
##     invisible - so the aura looks like it is simply missing a layer.
##   * An emitter over budget costs frame time only in a crowd, which is exactly
##     where bought titles are worn and exactly where nobody is testing.
##   * A trail that is missing, or that is the same effect as another theme's in a
##     different tint: the trail is what the rest of the server actually sees,
##     since a title is read from behind a running player far more often than it
##     is read head-on, and eight identical wakes make the set look like one
##     purchase with a colour picker.
##   * A trail flagged `detail` disappears in a crowd - the one place the set is
##     being shown off - and a trail in local space follows the wearer around as a
##     cloud instead of being left behind at all.
##   * The strip generator's copy of the dye hexes drifting from the dye table:
##     the fallback strips are what a roster row shows if a preset is ever pulled.
##
## Runs under `-s`: the whole theme pipeline lives in common/ and touches no
## autoload. Expect the usual wall of `Identifier not found: ClientState` from
## unrelated scripts.

## Total checks this tool is expected to run. A GDScript runtime error does not
## stop the script, it abandons the CURRENT FUNCTION and carries on - so a section
## that dies half way through simply prints fewer lines and the tool still reports
## green. Counting is the guard, the same way tools/verify_vip_titles.gd counts.
const EXPECTED_CHECKS: int = 55

## Below this, a colour is dark enough that additive blending renders it as
## nothing at all. Anything under it must be a mix-blended layer.
const DARK_LUMINANCE: float = 0.18

## The generator's copy of the dye hexes, parsed back out of the Python source.
const GENERATOR: String = "res://tools/gen_cosmetic_vfx.py"

var _fail: int = 0
var _ran: int = 0


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), label)
	_ran += 1
	if not ok:
		_fail += 1


func _initialize() -> void:
	_check_themes()
	_check_titles()
	_check_auras()
	_check_prices()
	_check_emitters()
	_check_trails()
	_check_pipeline()
	_check_swap()
	if _ran != EXPECTED_CHECKS:
		print("  FAIL  ran %d checks, expected %d - a section aborted early"
			% [_ran, EXPECTED_CHECKS])
		_fail += 1
	print("COSMETIC_THEMES %s failures=%d checks=%d"
		% ["FAIL" if _fail > 0 else "PASS", _fail, _ran])
	quit(1 if _fail > 0 else 0)


func _luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# -- themes --------------------------------------------------------------------


func _check_themes() -> void:
	print("-- themes --")
	var keys: Array[StringName] = CosmeticThemes.keys()
	_check(keys.size() == 8, "eight themes (got %d)" % keys.size())

	# A theme naming a dye style that does not exist falls back to white, which is
	# the one colour that reads as "deliberately bright" rather than as broken.
	var no_dye: PackedStringArray = []
	var fx_seen: Dictionary = {}
	var fx_clash: PackedStringArray = []
	var fx_range: PackedStringArray = []
	for key: StringName in keys:
		if VaultSkins.STYLE_META.get(CosmeticThemes.dye_style(key), {}).is_empty():
			no_dye.append(String(key))
		if VaultSkins.STYLE_META.get(CosmeticThemes.accent_style(key), {}).is_empty():
			no_dye.append(String(key) + "/accent")
		var fx: int = CosmeticThemes.fx(key)
		if fx < 0 or fx > 7:
			fx_range.append("%s=%d" % [key, fx])
		if fx_seen.has(fx):
			fx_clash.append("%s+%s=%d" % [fx_seen[fx], key, fx])
		fx_seen[fx] = String(key)
	_check(no_dye.is_empty(), "every theme names a real dye %s" % str(no_dye))
	_check(fx_range.is_empty(), "every fx index is in the shader's range %s" % str(fx_range))
	# Two themes on one branch is two titles that render identically, in different
	# colours - which reads as a palette choice and not as a bug.
	_check(fx_clash.is_empty(), "no two themes share a shader branch %s" % str(fx_clash))

	# pale and deep have to be far enough apart to be worth having: a ramp between
	# two colours that are almost the same is a flat fill wearing a gradient's
	# clothes, and every one of the eight looks is built on that ramp.
	var flat: PackedStringArray = []
	for key: StringName in keys:
		if _luminance(CosmeticThemes.pale(key)) - _luminance(CosmeticThemes.deep(key)) < 0.25:
			flat.append(String(key))
	_check(flat.is_empty(), "pale and deep are a usable ramp apart %s" % str(flat))

	# THE GENERATOR'S COPY. tools/gen_cosmetic_vfx.py is plain Python and cannot
	# read the dye table, so it holds its own hexes and this is what keeps them
	# honest. Drift here is invisible until a preset is pulled and the fallback
	# strip turns out to be the wrong colour.
	var text: String = FileAccess.get_file_as_string(GENERATOR)
	var drift: PackedStringArray = []
	for key: StringName in keys:
		var want: String = "\"%s\": (\"%s\", \"%s\")," % [
			key, CosmeticThemes.hex(key), "#" + CosmeticThemes.accent(key).to_html(false),
		]
		if not text.contains(want):
			drift.append(String(key))
	_check(not text.is_empty(), "the strip generator is readable")
	_check(drift.is_empty(), "the generator's dye hexes match the dye table %s" % str(drift))


# -- titles --------------------------------------------------------------------


func _check_titles() -> void:
	print("-- titles --")
	var slugs: PackedStringArray = TitleCatalog.theme_slugs()
	_check(slugs.size() == 8, "eight themed titles in the catalog (got %d)" % slugs.size())

	var unlinked: PackedStringArray = []
	var colour_drift: PackedStringArray = []
	var not_premium: PackedStringArray = []
	var is_ladder: PackedStringArray = []
	var unresolved: PackedStringArray = []
	for key: StringName in CosmeticThemes.keys():
		var slug: String = CosmeticThemes.title_slug(key)
		var entry: Dictionary = TitleCatalog.premium_entry(slug)
		if entry.is_empty() or StringName(str(entry.get("theme", ""))) != key:
			unlinked.append("%s->%s" % [key, slug])
			continue
		# THE DRIFT CHECK, and the reason this tool exists. The hex is written out
		# in the catalog because chat BBCode and the vault row need a plain string
		# and neither can call a function; this is what stops that copy going stale
		# the day somebody retunes the dye.
		if not Color(str(entry.get("color", ""))).is_equal_approx(CosmeticThemes.core(key)):
			colour_drift.append("%s catalog=%s dye=%s"
				% [slug, str(entry.get("color", "")), CosmeticThemes.hex(key)])
		var title: String = str(entry.get("name", ""))
		# is_premium_name is THE VAULT GATE: CommandPermissions.strip_unreleased_vfx
		# deletes any title matching it from a player without the entitlement, so a
		# title that stops satisfying it is released to whoever already has it.
		if not TitleCatalog.is_premium_name(title):
			not_premium.append(title)
		# ...and it must not be a donation rung, or PremiumCatalog refuses to sell
		# the thing this whole set exists to sell.
		if TitleCatalog.vip_tier(title) != &"":
			is_ladder.append(title)
		if TitleCatalog.theme(title) != key:
			unresolved.append(title)
	_check(unlinked.is_empty(), "every theme has a title pointing back at it %s" % str(unlinked))
	_check(colour_drift.is_empty(), "the catalog colour IS the dye %s" % str(colour_drift))
	_check(not_premium.is_empty(), "every themed title is premium, so the strip gates it %s"
		% str(not_premium))
	_check(is_ladder.is_empty(), "no themed title is a donation rung %s" % str(is_ladder))
	_check(unresolved.is_empty(), "the catalog resolves every theme by display name %s"
		% str(unresolved))


# -- auras ---------------------------------------------------------------------


func _check_auras() -> void:
	print("-- auras --")
	var missing: PackedStringArray = []
	var wrong_slot: PackedStringArray = []
	var no_preset: PackedStringArray = []
	var wrong_theme: PackedStringArray = []
	for key: StringName in CosmeticThemes.keys():
		var slug: StringName = CosmeticThemes.aura_slug(key)
		var id: int = _cosmetic_id(slug)
		if id <= 0:
			# A .tres plus an index entry is what makes a cosmetic exist. Without
			# one the title still sells and the shop offers half a set.
			missing.append(String(slug))
			continue
		if Cosmetics.slot_of(id) != &"aura":
			wrong_slot.append(String(slug))
		# The strips are fallbacks; the real look is the preset. A themed aura
		# without one renders as a flat pre-rendered ring in roughly the right
		# colour, which is exactly the thing these replaced.
		var script: GDScript = CosmeticPresetLibrary.script_for(id)
		if script == null:
			no_preset.append(String(slug))
			continue
		var preset: Object = script.new()
		if not preset.has_method(&"theme") or StringName(preset.call(&"theme")) != key:
			wrong_theme.append(String(slug))
	_check(missing.is_empty(), "every themed aura is in the cosmetics registry %s" % str(missing))
	_check(wrong_slot.is_empty(), "every themed aura is in the aura slot %s" % str(wrong_slot))
	_check(no_preset.is_empty(), "every themed aura has a scripted preset %s" % str(no_preset))
	_check(wrong_theme.is_empty(), "every preset wears the theme that names it %s" % str(wrong_theme))


## Swapping auras must not leak the previous preset's node tree.
##
## A shopper browsing the wardrobe walks the whole aura shelf in a few seconds,
## and every one of these presets is a node tree with emitters and draw layers
## hanging off it. A swap that left the old one parented would pile a full effect
## per click onto the preview - invisible, because the new one draws over it, and
## expensive immediately.
##
## Checked through [CosmeticVfx.apply], the same call the world and the wardrobe
## both make, rather than by re-implementing the swap here.
func _check_swap() -> void:
	print("-- swap --")
	var first: int = _cosmetic_id(CosmeticThemes.aura_slug(CosmeticThemes.CRIMSON))
	var second: int = _cosmetic_id(CosmeticThemes.aura_slug(CosmeticThemes.GLACIAL))
	if first <= 0 or second <= 0:
		return
	var host: CosmeticVfx = CosmeticVfx.new()
	host.preview_mode = true
	host.apply(first)
	var mounted: Node = host.get_node_or_null("Preset")
	_check(mounted != null, "equipping a themed aura mounts its preset")
	host.apply(second)
	_check(mounted != null and mounted.is_queued_for_deletion(),
		"swapping auras frees the previous preset")
	# ...and unparents it the same frame. Without that the replacement joins a
	# parent that still holds the dying node, both draw, and the new one is
	# renamed out from under anyone addressing it by name - which is what this
	# lookup is standing in for.
	var replacement: Node = host.get_node_or_null("Preset")
	_check(replacement != null and replacement != mounted,
		"...and the new one takes its place immediately")
	host.free()


func _cosmetic_id(slug: StringName) -> int:
	for id: int in Cosmetics.ids():
		if Cosmetics.slug(id) == slug:
			return id
	return 0


# -- prices --------------------------------------------------------------------


func _check_prices() -> void:
	print("-- prices --")
	var unsellable: PackedStringArray = []
	var over_cap: PackedStringArray = []
	var title_costs: PackedStringArray = []
	for key: StringName in CosmeticThemes.keys():
		var slug: String = CosmeticThemes.title_slug(key)
		var title: String = str(TitleCatalog.premium_entry(slug).get("name", ""))
		# resolve() is the SECURITY BOUNDARY as well as the price: the only ids
		# that resolve are ones the catalog put in the roster, so a title that
		# does not resolve here cannot be bought however the client asks.
		var entry: Dictionary = PremiumCatalog.resolve(VaultGrants.title_token(title))
		if entry.is_empty():
			unsellable.append(title)
			continue
		var cost: int = int(entry.get("cost", 0))
		if cost > PremiumCatalog.COST_TITLE:
			over_cap.append("%s=%d" % [title, cost])
		var want: int = (
			PremiumCatalog.COST_TITLE
			if key == PremiumCatalog.THEMED_TITLE_AT_CEILING
			else PremiumCatalog.COST_TITLE_THEMED
		)
		if cost != want:
			title_costs.append("%s=%d want %d" % [title, cost, want])
	_check(unsellable.is_empty(), "every themed title resolves to a purchase %s" % str(unsellable))
	_check(over_cap.is_empty(), "no title is over the %d-coin cap %s"
		% [PremiumCatalog.COST_TITLE, str(over_cap)])
	_check(title_costs.is_empty(), "themed titles are priced as designed %s" % str(title_costs))

	var aura_unsellable: PackedStringArray = []
	var aura_band: PackedStringArray = []
	for key: StringName in CosmeticThemes.keys():
		var id: int = _cosmetic_id(CosmeticThemes.aura_slug(key))
		if id <= 0:
			continue
		var entry: Dictionary = PremiumCatalog.resolve(VaultGrants.cosmetic_token(id))
		if entry.is_empty():
			aura_unsellable.append(String(CosmeticThemes.aura_slug(key)))
			continue
		var cost: int = int(entry.get("cost", 0))
		# The brief's band. Outside it, an aura is either undercutting the rest of
		# the shelf or is the most expensive thing in the game by accident.
		if cost < 450 or cost > 750:
			aura_band.append("%s=%d" % [CosmeticThemes.aura_slug(key), cost])
	_check(aura_unsellable.is_empty(), "every themed aura resolves to a purchase %s"
		% str(aura_unsellable))
	_check(aura_band.is_empty(), "themed auras sit in the 450-750 band %s" % str(aura_band))

	# The pairing is the product. If the two halves of a set cannot both be bought
	# for a sensible total, the set is decoration on a price list.
	var worst: int = 0
	for key: StringName in CosmeticThemes.keys():
		var slug: String = CosmeticThemes.title_slug(key)
		var title: String = str(TitleCatalog.premium_entry(slug).get("name", ""))
		var id: int = _cosmetic_id(CosmeticThemes.aura_slug(key))
		var pair: int = (
			int(PremiumCatalog.resolve(VaultGrants.title_token(title)).get("cost", 0))
			+ int(PremiumCatalog.resolve(VaultGrants.cosmetic_token(id)).get("cost", 0))
		)
		worst = maxi(worst, pair)
	_check(worst <= 1250, "a full set stays inside one 1000-coin pack plus change (worst %d)" % worst)


# -- emitters ------------------------------------------------------------------


func _check_emitters() -> void:
	print("-- emitters --")
	var no_profile: PackedStringArray = []
	var too_many: PackedStringArray = []
	var all_conditional: PackedStringArray = []
	var invisible: PackedStringArray = []
	var aura_span: PackedStringArray = []
	for key: StringName in CosmeticThemes.keys():
		var profile: VipTierProfile = TitleThemeFx.profile(key)
		if profile == null or profile.layers.is_empty():
			no_profile.append(String(key))
			continue
		if profile.layers.size() > VipTitleEffect.MAX_LAYERS:
			too_many.append("%s=%d" % [key, profile.layers.size()])
		# At medium LOD every `detail` layer stops, and an `on_move` layer stops
		# whenever the wearer stands still. A title made entirely of those two
		# renders NOTHING in a crowded bank, which is the one place it is worn to
		# be seen.
		var signature: int = 0
		for layer: VipParticleLayer in profile.layers:
			if not layer.detail and not layer.on_move:
				signature += 1
			# THE ADDITIVE BLACK TRAP: additive blending of a dark colour adds
			# nothing, so the layer ticks, costs frame time and draws no pixels.
			if layer.additive and _luminance(layer.color_mid) < DARK_LUMINANCE:
				invisible.append("%s/%s" % [key, layer.id])
			# THE AURA RULE. Titles here are text VFX; a character aura is a
			# different product and is sold separately - see the matching aura.
			if layer.span_scale > VipTitleEffect.MAX_SPAN_SCALE:
				aura_span.append("%s/%s=%.2f" % [key, layer.id, layer.span_scale])
		if signature == 0:
			all_conditional.append(String(key))
	_check(no_profile.is_empty(), "every theme builds an emitter stack %s" % str(no_profile))
	_check(too_many.is_empty(), "at most %d layers per title %s"
		% [VipTitleEffect.MAX_LAYERS, str(too_many)])
	_check(all_conditional.is_empty(), "every theme keeps a layer that always runs %s"
		% str(all_conditional))
	_check(invisible.is_empty(), "no dark layer is additive (would draw nothing) %s" % str(invisible))
	_check(aura_span.is_empty(), "no layer emits past span_scale %.1f (title, not aura) %s"
		% [VipTitleEffect.MAX_SPAN_SCALE, str(aura_span)])

	var gpu: PackedStringArray = []
	var over_budget: PackedStringArray = []
	var over_total: PackedStringArray = []
	var no_cull: PackedStringArray = []
	var emitters: int = 0
	for key: StringName in CosmeticThemes.keys():
		var node: VipTitleEffect = VipTitleEffect.new()
		node.tier = key
		node.profile = TitleThemeFx.profile(key)
		# build() explicitly rather than parenting and waiting for _ready: a node
		# added during _initialize() does not get _ready until the tree ticks, and
		# this tool quits before that - so every emitter would read as absent.
		node.build()
		if node.get_node_or_null("Cull") == null or node.get_node_or_null("Lod") == null:
			no_cull.append(String(key))
		for child: Node in node.get_children():
			if child is GPUParticles2D:
				# CPUParticles2D only: GPU particles are not safe on the web
				# export, which is a shipping target.
				gpu.append(String(key))
				continue
			var p: CPUParticles2D = child as CPUParticles2D
			if p == null:
				continue
			emitters += 1
			if p.amount < VipTitleEffect.MIN_AMOUNT or p.amount > VipTitleEffect.MAX_AMOUNT:
				over_budget.append("%s/%s amount=%d" % [key, p.name, p.amount])
			if p.lifetime < VipTitleEffect.MIN_LIFETIME or p.lifetime > VipTitleEffect.MAX_LIFETIME:
				over_budget.append("%s/%s life=%.2f" % [key, p.name, p.lifetime])
			if p.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
				over_budget.append("%s/%s filtered" % [key, p.name])
		if node.total_amount() > VipTitleEffect.MAX_TOTAL_AMOUNT:
			over_total.append("%s=%d" % [key, node.total_amount()])
		node.free()
	_check(emitters > 0, "every theme builds emitters (got %d)" % emitters)
	_check(gpu.is_empty(), "CPUParticles2D only, web-safe %s" % str(gpu))
	_check(over_budget.is_empty(), "amount %d-%d, life %.1f-%.1fs, nearest filtering %s" % [
		VipTitleEffect.MIN_AMOUNT, VipTitleEffect.MAX_AMOUNT,
		VipTitleEffect.MIN_LIFETIME, VipTitleEffect.MAX_LIFETIME, str(over_budget),
	])
	_check(over_total.is_empty(), "at most %d particles per title %s"
		% [VipTitleEffect.MAX_TOTAL_AMOUNT, str(over_total)])
	_check(no_cull.is_empty(), "every theme builds its cull notifier and LOD timer %s" % str(no_cull))


# -- trails --------------------------------------------------------------------


## Every theme has exactly one movement trail, and no two are the same effect.
##
## "Unique" is a design word, so this checks the mechanical part of it: the shape
## a trail emits, whether it blends as light or as paint, and which way it travels.
## Two trails agreeing on all three are the same effect in two colours, whatever
## the numbers around them say.
func _check_trails() -> void:
	print("-- trails --")
	var missing: PackedStringArray = []
	var extra: PackedStringArray = []
	var culled: PackedStringArray = []
	var bolted: PackedStringArray = []
	var thin: PackedStringArray = []
	var seen: Dictionary = {}
	var clash: PackedStringArray = []
	for key: StringName in CosmeticThemes.keys():
		var profile: VipTierProfile = TitleThemeFx.profile(key)
		if profile == null:
			continue
		var trails: Array[VipParticleLayer] = []
		for layer: VipParticleLayer in profile.layers:
			if layer.on_move:
				trails.append(layer)
		if trails.is_empty():
			missing.append(String(key))
			continue
		if trails.size() > 1:
			extra.append("%s=%d" % [key, trails.size()])
		var trail: VipParticleLayer = trails[0]
		# A trail flagged `detail` stops at medium LOD - in a crowd, which is
		# exactly where somebody is running past to be seen.
		if trail.detail:
			culled.append("%s/%s" % [key, trail.id])
		# ...and a local-space trail is bolted to the label, so it travels WITH
		# the wearer as a cloud rather than being left behind as a wake.
		if trail.local_space or not is_zero_approx(trail.orbit):
			bolted.append("%s/%s" % [key, trail.id])
		# Noticeable, in the only terms a tool can hold: enough particles, and
		# long enough lived to still be on screen behind a moving player.
		#
		# SIXTEEN IS MEASURED, not guessed. The first walking capture ran these at
		# ten-ish and every wake read as a handful of stray specks; the floor is
		# where they started reading as a trail at the speed a player actually
		# moves. tools/render_theme_titles.tscn is the capture in question.
		if trail.amount < 16 or trail.lifetime < 0.6:
			thin.append("%s/%s amount=%d life=%.2f" % [key, trail.id, trail.amount, trail.lifetime])
		var signature: String = "%d/%s/%s" % [
			trail.shape,
			"light" if trail.additive else "paint",
			"down" if trail.direction.y > 0.0 else "up",
		]
		if seen.has(signature):
			clash.append("%s+%s (%s)" % [seen[signature], key, signature])
		seen[signature] = String(key)
	_check(missing.is_empty(), "every theme leaves a trail when the wearer moves %s" % str(missing))
	_check(extra.is_empty(), "one trail layer per theme, not several %s" % str(extra))
	_check(culled.is_empty(), "no trail is flagged detail (would vanish in a crowd) %s" % str(culled))
	_check(bolted.is_empty(), "every trail is world space, so it is left behind %s" % str(bolted))
	_check(thin.is_empty(), "every trail is thick enough and lives long enough %s" % str(thin))
	_check(clash.is_empty(), "no two trails are the same shape, blend and direction %s" % str(clash))


# -- pipeline ------------------------------------------------------------------


## The pipeline against a real Label - the same entry point the nameplate, the
## profile and the vault shelf all call. Checking the parts in isolation would
## miss the thing that actually breaks: a title switching from one family to
## another and leaving the previous family's nodes and overrides behind.
func _check_pipeline() -> void:
	print("-- pipeline --")
	var label: Label = Label.new()
	label.text = "« Iridescent Aspect »"
	TitleVfx.apply_to_label(label, "Iridescent Aspect", true)

	var mat: ShaderMaterial = label.material as ShaderMaterial
	_check(mat != null and mat.shader == TitleVfx.THEME_SHADER,
		"a themed title gets theme_title.gdshader")
	_check(label.self_modulate.is_equal_approx(Color.WHITE),
		"the label is left white so the theme palette arrives unmultiplied")
	_check(label.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"title text is filtered nearest")

	# EVERY uniform the shader declares must actually be fed. One added to the
	# .gdshader and forgotten in TitleVfx does not error - it renders at its GLSL
	# default, which for every colour in that file is flat white, and a themed
	# title that renders white has lost the one thing it was bought for.
	var unfed: PackedStringArray = []
	for prop: Dictionary in TitleVfx.THEME_SHADER.get_shader_uniform_list():
		var uname: String = str(prop.get("name", ""))
		if mat != null and mat.get_shader_parameter(StringName(uname)) == null:
			unfed.append(uname)
	_check(unfed.is_empty(), "every theme_title.gdshader uniform is fed %s" % str(unfed))
	_check(
		mat != null and (mat.get_shader_parameter(&"core") as Color).is_equal_approx(
			CosmeticThemes.core(CosmeticThemes.PRISM)
		),
		"the shader is handed the theme's own dye colour"
	)

	var pulse: Node = label.get_node_or_null(TitleVfx.PULSE_NODE)
	_check(pulse != null and bool(pulse.get(&"clock_driven")),
		"the pulse node drives the shader clock")
	var fx: Node = label.get_node_or_null(TitleVfx.THEME_NODE)
	_check(fx != null and StringName(fx.get(&"tier")) == CosmeticThemes.PRISM,
		"the theme layer is mounted")
	_check(fx != null and bool(fx.get(&"preview")),
		"a shelf mount reaches the layer as a preview, so it is not culled there")

	# Switching themes must REBUILD, not reconfigure: the emitter set is built once
	# and is not designed to be mutated.
	TitleVfx.apply_to_label(label, "Crimson Warlord", true)
	var swapped: Node = label.get_node_or_null(TitleVfx.THEME_NODE)
	_check(swapped != null and StringName(swapped.get(&"tier")) == CosmeticThemes.CRIMSON,
		"switching themes re-points the layer")

	# ...and switching FAMILIES has to tear the theme's nodes down. A shopper
	# cycling the vault shelf walks every family in a few seconds, so a layer left
	# behind here is a leak per browse as well as a wrong-looking title.
	TitleVfx.apply_to_label(label, "Diamond Donator", true)
	_check(label.get_node_or_null(TitleVfx.THEME_NODE) == null,
		"a ladder title tears the theme layer down")
	_check(label.get_node_or_null(TitleVfx.VIP_NODE) != null,
		"...and mounts its own")

	TitleVfx.apply_to_label(label, "Verdant Warden", true)
	_check(label.get_node_or_null(TitleVfx.VIP_NODE) == null,
		"and back the other way: the ladder layer goes")

	TitleVfx.apply_to_label(label, "")
	_check(label.get_node_or_null(TitleVfx.THEME_NODE) == null and label.material == null,
		"clearing the title drops the layer and the shader")
	label.free()
