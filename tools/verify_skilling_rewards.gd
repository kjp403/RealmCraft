@tool
extends SceneTree
## Content + tuning gate for the Daily Skilling Chests and Skilling Outfits.
##
##   godot --headless --path . -s tools/verify_skilling_rewards.gd
##
## Checks the two things that fail SILENTLY in this system: a loot pool naming an
## item that is not in the index (that entry just never drops, and the chest
## quietly pays one stack short), and an outfit set naming a piece that was never
## stamped (the set can never be completed, so the bonus never fires).
##
## Everything here is deliberately reachable without a live Player. Constructing
## one pulls in Character and the client autoloads, which do not exist under `-s`
## — hence [method SkillingOutfitManager.bonus_from_worn] taking a piece count
## rather than a player.

var _fails: PackedStringArray = PackedStringArray()


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_fails.append(label)


func _init() -> void:
	_chest_content()
	_chest_tuning()
	_outfit_content()
	_outfit_tuning()
	_precook()
	print("")
	if _fails.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL (%d)" % _fails.size())
		for f: String in _fails:
			print("  - %s" % f)
	quit(0 if _fails.is_empty() else 1)


# --- Chest content -----------------------------------------------------------

func _chest_content() -> void:
	print("[skilling chest content]")
	var problems: PackedStringArray = SkillingChestRewarder.validate()
	_check(problems.is_empty(), "every pooled slug resolves to a real item%s" % (
		"" if problems.is_empty() else " - " + ", ".join(problems)
	))
	# All nine skilling jobs must have a pool, or a player who picks that skill
	# finishes a Hard daily and opens nothing.
	# Roster read off the manager SCRIPT rather than the autoload identifier —
	# autoload resolution under `-s` is inconsistent, and a roster that silently
	# read as empty would make this check pass by doing nothing.
	var manager: GDScript = load("res://source/common/gameplay/quests/daily_quest_manager.gd")
	var roster: Array = manager.SKILLS if manager != null else []
	_check(roster.size() == 9, "daily skill roster resolved (%d)" % roster.size())
	var missing: PackedStringArray = PackedStringArray()
	for slug: Variant in roster:
		if not SkillingChestRewarder.POOLS.has(StringName(str(slug))):
			missing.append(String(slug))
	_check(missing.is_empty(), "all nine daily skills have a loot pool%s" % (
		"" if missing.is_empty() else " - missing: " + ", ".join(missing)
	))
	# A band a tier draws from must actually have entries, or the draw silently
	# returns fewer stacks than the tier promises.
	var thin: PackedStringArray = PackedStringArray()
	for skill: StringName in SkillingChestRewarder.POOLS:
		var pools: Dictionary = SkillingChestRewarder.POOLS[skill]
		for tier: Dictionary in SkillingChestRewarder.TIERS:
			for band: Variant in (tier["draws"] as Dictionary):
				var want: int = int((tier["draws"] as Dictionary)[band])
				var have: int = (pools.get(band, []) as Array).size()
				if have < want:
					thin.append("%s/%s has %d, needs %d" % [skill, band, have, want])
	_check(thin.is_empty(), "every band holds enough entries for its draw%s" % (
		"" if thin.is_empty() else " - " + ", ".join(thin)
	))


func _chest_tuning() -> void:
	print("[skilling chest tuning]")
	# The rare-roll rates from the design brief. Asserted exactly: these are the
	# numbers shown to players, and a stray edit here is invisible in play.
	var want: Array[float] = [0.001, 0.005, 0.01]
	for tier: int in 3:
		_check(
			is_equal_approx(SkillingChestRewarder.outfit_chance(tier), want[tier]),
			"T%d outfit chance is %.1f%% (%.3f%%)" % [
				tier + 1, want[tier] * 100.0,
				SkillingChestRewarder.outfit_chance(tier) * 100.0
			]
		)
	# A higher tier must be strictly better on every axis, or picking Hard is a
	# trap.
	for tier: int in 2:
		var lo: Dictionary = SkillingChestRewarder.TIERS[tier]
		var hi: Dictionary = SkillingChestRewarder.TIERS[tier + 1]
		_check(
			(hi["gold"] as Vector2i).x > (lo["gold"] as Vector2i).x
				and (hi["gold"] as Vector2i).y > (lo["gold"] as Vector2i).y,
			"T%d gold beats T%d (%s vs %s)" % [tier + 2, tier + 1, hi["gold"], lo["gold"]]
		)
		_check(
			(hi["base_amount"] as Vector2i).y > (lo["base_amount"] as Vector2i).y,
			"T%d quantity beats T%d" % [tier + 2, tier + 1]
		)
		_check(
			float(hi["outfit"]) > float(lo["outfit"]),
			"T%d outfit chance beats T%d" % [tier + 2, tier + 1]
		)
	# A T3 chest must not out-earn the skill it rewards. 180 runite ore would.
	var high_scale: float = float(SkillingChestRewarder.BAND_SCALE["high"])
	_check(
		high_scale < float(SkillingChestRewarder.BAND_SCALE["low"]),
		"high-band drops are scaled down against low-band (%.2f vs %.2f)" % [
			high_scale, float(SkillingChestRewarder.BAND_SCALE["low"])
		]
	)


# --- Outfit content ----------------------------------------------------------

func _outfit_content() -> void:
	print("[skilling outfit content]")
	var problems: PackedStringArray = SkillingOutfitManager.validate()
	_check(problems.is_empty(), "every set resolves its job, pieces and aura%s" % (
		"" if problems.is_empty() else " - " + ", ".join(problems)
	))
	_check(
		SkillingOutfitManager.SETS.size() == 4,
		"four sets authored (%d)" % SkillingOutfitManager.SETS.size()
	)
	# Piece slugs must be unique across sets — a slug in two sets would count
	# toward both and make a 4-piece bonus reachable with fewer than 4 items.
	var seen: Dictionary[StringName, bool] = {}
	var dupes: PackedStringArray = PackedStringArray()
	for slug: StringName in SkillingOutfitManager.all_piece_slugs():
		if seen.has(slug):
			dupes.append(String(slug))
		seen[slug] = true
	_check(dupes.is_empty(), "no piece belongs to two sets%s" % (
		"" if dupes.is_empty() else " - " + ", ".join(dupes)
	))
	_check(
		SkillingOutfitManager.all_piece_slugs().size() == 16,
		"16 pieces across the four sets (%d)" % SkillingOutfitManager.all_piece_slugs().size()
	)
	# Each set must occupy four DISTINCT equipment slots, or it can never be worn
	# in full no matter how many pieces the player collects.
	for set_slug: StringName in SkillingOutfitManager.SETS:
		var slots: Dictionary[StringName, bool] = {}
		for piece: StringName in SkillingOutfitManager.pieces_of(set_slug):
			var item: Resource = ContentRegistryHub.load_by_slug(&"items", piece)
			if item is GearItem and (item as GearItem).slot != null:
				slots[(item as GearItem).slot.key] = true
		_check(
			slots.size() == SkillingOutfitManager.PIECES_PER_SET,
			"%s occupies %d distinct slots" % [set_slug, slots.size()]
		)
	# Every set must map to a skill that actually exists, and no two sets may
	# claim the same skill (set_for_skill returns the first match).
	var skills: Dictionary[StringName, bool] = {}
	var clashes: PackedStringArray = PackedStringArray()
	for set_slug: StringName in SkillingOutfitManager.SETS:
		var skill: StringName = StringName(str(
			(SkillingOutfitManager.SETS[set_slug] as Dictionary)["skill"]
		))
		if skills.has(skill):
			clashes.append(String(skill))
		skills[skill] = true
	_check(clashes.is_empty(), "one set per skill%s" % (
		"" if clashes.is_empty() else " - contested: " + ", ".join(clashes)
	))


func _outfit_tuning() -> void:
	print("[skilling outfit tuning]")
	for set_slug: StringName in SkillingOutfitManager.SETS:
		var def: Dictionary = SkillingOutfitManager.SETS[set_slug]
		for kind: SkillingOutfitManager.Bonus in (def["piece"] as Dictionary):
			var per: float = float((def["piece"] as Dictionary)[kind])
			# The brief calls for 1-2% per piece. Anything outside that is either
			# invisible to the player or quietly better than the set bonus.
			_check(
				per >= 0.01 and per <= 0.02,
				"%s %s is %.1f%% per piece (want 1-2%%)" % [
					set_slug, SkillingOutfitManager.bonus_label(kind), per * 100.0
				]
			)
			# Completing the set must beat collecting a fourth piece for its own
			# sake, or there is no reason to chase the last slot.
			var full: float = float((def["full"] as Dictionary).get(kind, 0.0))
			_check(
				full > per,
				"%s %s set bonus (%.0f%%) beats one more piece (%.1f%%)" % [
					set_slug, SkillingOutfitManager.bonus_label(kind), full * 100.0, per * 100.0
				]
			)
		# The curve itself: 3 pieces must be worth less than 4, and 4 must jump.
		for kind: SkillingOutfitManager.Bonus in (def["full"] as Dictionary):
			var three: float = SkillingOutfitManager.bonus_from_worn(set_slug, 3, kind)
			var four: float = SkillingOutfitManager.bonus_from_worn(set_slug, 4, kind)
			_check(four > three, "%s %s jumps at 4 pieces (%.1f%% -> %.1f%%)" % [
				set_slug, SkillingOutfitManager.bonus_label(kind), three * 100.0, four * 100.0
			])
			# Wearing more than four (impossible today, but pieces_worn clamps and
			# this asserts the clamp) must not keep scaling.
			_check(
				is_equal_approx(SkillingOutfitManager.bonus_from_worn(set_slug, 9, kind), four),
				"%s %s does not scale past 4 pieces" % [
					set_slug, SkillingOutfitManager.bonus_label(kind)
				]
			)
	# Nothing may reach certainty: a 100% durability bypass is an infinite node
	# and a 100% preserve is free potions.
	for kind: SkillingOutfitManager.Bonus in SkillingOutfitManager.CAPS:
		var cap: float = float(SkillingOutfitManager.CAPS[kind])
		_check(cap > 0.0 and cap < 1.0, "%s cap is %.0f%%, under certainty" % [
			SkillingOutfitManager.bonus_label(kind), cap * 100.0
		])
	# Full-set totals should land where the brief asked (~10% set bonus on top of
	# 4-6% of pieces), not somewhere that quietly got capped away.
	var wc_yield: float = SkillingOutfitManager.bonus_from_worn(
		&"woodcutter", 4, SkillingOutfitManager.Bonus.YIELD
	)
	_check(
		wc_yield > 0.10 and wc_yield < 0.25,
		"a full Lumberjack set pays %.0f%% bonus yield" % (wc_yield * 100.0)
	)


func _precook() -> void:
	print("[angler precook]")
	# The Angler set swaps a raw catch for its cooked counterpart. The mapping is
	# inverted from ChestResource's cooked->raw table, so a fish added to one
	# must appear in the other; a miss here means the set silently does nothing
	# for that fish.
	# Checked at the SLUG level, not by loading the item: cooked fish are
	# ConsumableItems, which reach ClientState and therefore load as null under
	# `-s` even though they resolve fine on a live server. The slug mapping plus
	# an index lookup catches the failure that actually matters (a fish renamed
	# or missing from the index) without needing the resource itself.
	var misses: PackedStringArray = PackedStringArray()
	var unindexed: PackedStringArray = PackedStringArray()
	for cooked: Variant in ChestResource.COOKED_FISH_TO_RAW:
		var raw := StringName(str(ChestResource.COOKED_FISH_TO_RAW[cooked]))
		var mapped: StringName = SkillingOutfitManager.precooked_slug_for(raw)
		if mapped == &"":
			misses.append(String(raw))
		elif ContentRegistryHub.id_from_slug(&"items", mapped) <= 0:
			unindexed.append(String(mapped))
	_check(misses.is_empty(), "every cookable fish maps to a cooked form%s" % (
		"" if misses.is_empty() else " - " + ", ".join(misses)
	))
	_check(unindexed.is_empty(), "every cooked form is in the items index%s" % (
		"" if unindexed.is_empty() else " - " + ", ".join(unindexed)
	))
	# The raw fish themselves must be indexed too — that is the side the gather
	# path looks up when deciding whether to swap the catch.
	var raw_missing: PackedStringArray = PackedStringArray()
	for cooked: Variant in ChestResource.COOKED_FISH_TO_RAW:
		var raw2 := StringName(str(ChestResource.COOKED_FISH_TO_RAW[cooked]))
		if ContentRegistryHub.id_from_slug(&"items", raw2) <= 0:
			raw_missing.append(String(raw2))
	_check(raw_missing.is_empty(), "every raw fish is in the items index%s" % (
		"" if raw_missing.is_empty() else " - " + ", ".join(raw_missing)
	))
	# A non-fish must map to nothing rather than handing the player something
	# unrelated out of the water.
	_check(
		SkillingOutfitManager.precooked_slug_for(&"copper_ore") == &"",
		"a non-fish has no precooked form"
	)
	_check(
		SkillingOutfitManager.precooked_slug_for(&"") == &"",
		"an empty slug has no precooked form"
	)
