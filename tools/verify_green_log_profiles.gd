extends SceneTree
## Gate for the ten green-log title profiles.
##
##     godot --headless --path . -s tools/verify_green_log_profiles.gd
##
## Checks:
##  1. Every log names a profile, and that profile .tres loads.
##  2. Budget: <= MAX_LAYERS, <= MAX_AMOUNT per layer, <= BUDGET_TOTAL overall.
##  3. THE ADDITIVE BLACK TRAP — additive blending of a dark colour adds nothing,
##     so the layer ticks, costs frame time and draws NOTHING. Any additive layer
##     whose colours are all dark is a bug, not a subtle effect.
##  4. At least one non-`detail` layer, or the title vanishes at medium LOD
##     instead of thinning out.
##  5. Metal ramps are DISTINCT — from each other, from the four donation tiers,
##     and legible (high must actually be brighter than low).
##  6. The titles resolve through TitleCatalog to their profile, and none of them
##     is premium (which would get them stripped from everyone who earned one).

const LOGS_PATH: String = "res://source/common/gameplay/collection_log/logs/"
## Tighter than VipTitleEffect.MAX_TOTAL_AMOUNT (62) on purpose — the brief for
## these ten asked for under 30 each.
const BUDGET_TOTAL: int = 30
## Two ramps closer than this in summed RGB distance read as the same metal.
const MIN_RAMP_DISTANCE: float = 0.45
## ...but the BODY colour is what a reader actually sees: the crown is a narrow
## band and the base is mostly in shadow, so two titles can pass the whole-ramp
## distance while looking like twins. Golembreaker and Orcsbane shipped that way
## — both near-white over grey — and only a human looking at the render caught
## it. This is that catch, encoded.
const MIN_MID_DISTANCE: float = 0.30
## Below this luminance a colour cannot carry an additive layer.
const DARK_LUMA: float = 0.22

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	var profiles: Dictionary = {}
	for path: String in FileUtils.get_all_file_at(LOGS_PATH, "*.tres"):
		var boss_log: BossCollectionLog = ResourceLoader.load(path) as BossCollectionLog
		if boss_log == null:
			continue
		_checks += 1
		if boss_log.green_log_profile.is_empty():
			_f("%s: no green_log_profile — the title falls back to flat text"
				% boss_log.boss_name)
			continue
		var profile: VipTierProfile = VipTierProfile.for_tier(boss_log.green_log_profile)
		_checks += 1
		if profile == null:
			_f("%s: profile '%s' does not load from titles/profiles/"
				% [boss_log.boss_name, boss_log.green_log_profile])
			continue
		profiles[boss_log.green_log_profile] = profile
		_check_budget(boss_log.boss_name, profile)
		_check_catalog(boss_log)

	_check_distinct(profiles)

	print("")
	if _failures.is_empty():
		print("VERIFY_PASS  (%d checks, %d profiles)" % [_checks, profiles.size()])
	else:
		for line: String in _failures:
			printerr("  FAIL: %s" % line)
		print("VERIFY_FAIL  (%d failures / %d checks)" % [_failures.size(), _checks])
	quit(0 if _failures.is_empty() else 1)


func _check_budget(who: String, profile: VipTierProfile) -> void:
	_checks += 3
	if profile.layers.is_empty():
		_f("%s: profile has no emitter layers" % who)
		return
	if profile.layers.size() > VipTitleEffect.MAX_LAYERS:
		_f("%s: %d layers, cap is %d"
			% [who, profile.layers.size(), VipTitleEffect.MAX_LAYERS])
	var total: int = 0
	var signature: int = 0
	for layer: VipParticleLayer in profile.layers:
		if layer == null:
			continue
		total += layer.amount
		if not layer.detail:
			signature += 1
		_checks += 2
		if layer.amount > VipTitleEffect.MAX_AMOUNT:
			_f("%s/%s: amount %d over the per-layer cap %d"
				% [who, layer.id, layer.amount, VipTitleEffect.MAX_AMOUNT])
		# The trap. Every colour dark AND additive = an invisible layer.
		if layer.additive and _luma(layer.color_in) < DARK_LUMA \
				and _luma(layer.color_mid) < DARK_LUMA \
				and _luma(layer.color_out) < DARK_LUMA:
			_f("%s/%s: additive layer with only dark colours draws NOTHING — "
				% [who, layer.id] + "set additive = false or brighten it")
	if total > BUDGET_TOTAL:
		_f("%s: %d particles total, budget is %d" % [who, total, BUDGET_TOTAL])
	if signature == 0:
		_f("%s: every layer is `detail`, so the title vanishes at medium LOD "
			% who + "rather than thinning out")


## The title must reach its profile through the normal lookup, and must NOT be
## premium — strip_unreleased_vfx deletes premium names from non-staff players.
func _check_catalog(boss_log: BossCollectionLog) -> void:
	var title: String = boss_log.green_log_title_text
	_checks += 3
	if TitleCatalog.is_premium_name(title):
		_f("%s: title '%s' resolves as PREMIUM — it would be stripped from "
			% [boss_log.boss_name, title] + "everyone who earned it")
	if TitleCatalog.vip_tier(title) != boss_log.green_log_profile:
		_f("%s: TitleCatalog resolves '%s' to profile '%s', expected '%s'"
			% [boss_log.boss_name, title, TitleCatalog.vip_tier(title),
			boss_log.green_log_profile])
	if not TitleCatalog.has_vfx(title):
		_f("%s: '%s' has no VFX spec at all" % [boss_log.boss_name, title])


## No two of these may look like each other, or like a donation tier.
func _check_distinct(profiles: Dictionary) -> void:
	var keys: Array = profiles.keys()
	for i: int in keys.size():
		var a: VipTierProfile = profiles[keys[i]]
		_checks += 1
		# A ramp whose crown is not brighter than its base is not a cast metal.
		if _luma(a.metal_high) <= _luma(a.metal_low):
			_f("%s: metal_high is no brighter than metal_low — the ramp reads flat"
				% keys[i])
		for j: int in range(i + 1, keys.size()):
			_checks += 2
			var b: VipTierProfile = profiles[keys[j]]
			var d: float = _ramp_distance(a, b)
			if d < MIN_RAMP_DISTANCE:
				_f("%s and %s share a metal ramp (distance %.2f, min %.2f)"
					% [keys[i], keys[j], d, MIN_RAMP_DISTANCE])
			var dm: float = _body_distance(a, b)
			if dm < MIN_MID_DISTANCE:
				_f("%s and %s share a BODY colour (mid distance %.2f, min %.2f) — "
					% [keys[i], keys[j], dm, MIN_MID_DISTANCE]
					+ "they will read as the same title however different the ramps are")
		# ...and against the four donation tiers.
		for slug: String in TitleCatalog.vip_tier_slugs():
			var tier: StringName = StringName(str(
				(TitleCatalog.PREMIUM[slug] as Dictionary).get("vip_tier", "")))
			var other: VipTierProfile = VipTierProfile.for_tier(tier)
			if other == null:
				continue
			_checks += 2
			if _ramp_distance(a, other) < MIN_RAMP_DISTANCE:
				_f("%s looks like the %s donation tier (distance %.2f)"
					% [keys[i], tier, _ramp_distance(a, other)])
			if _body_distance(a, other) < MIN_MID_DISTANCE:
				_f("%s shares a body colour with the %s donation tier (%.2f)"
					% [keys[i], tier, _body_distance(a, other)])


## Every colour a reader perceives as the body — one for a normal profile, two
## for a split one.
##
## Averaging the two was the obvious move and it is wrong: Emberfrost's orange
## and cyan average to a neutral grey it never displays anywhere, which then
## collides with the silver donation tier for entirely imaginary reasons.
func _bodies(p: VipTierProfile) -> Array[Color]:
	var out: Array[Color] = [p.metal_mid]
	if p.split_amount > 0.001:
		out.append(p.metal_mid.lerp(p.split_color, p.split_amount))
	return out


## How far apart two titles read. Two titles are only confusable when EVERY part
## of one is close to some part of the other, so this takes the widest gap: a
## half that is unmistakably different is enough to tell them apart.
func _body_distance(a: VipTierProfile, b: VipTierProfile) -> float:
	var widest: float = 0.0
	for ca: Color in _bodies(a):
		for cb: Color in _bodies(b):
			widest = maxf(widest, _dist(ca, cb))
	return widest


func _ramp_distance(a: VipTierProfile, b: VipTierProfile) -> float:
	return _dist(a.metal_high, b.metal_high) + _dist(a.metal_mid, b.metal_mid) \
		+ _dist(a.metal_low, b.metal_low)


func _dist(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


func _f(msg: String) -> void:
	_failures.append(msg)
