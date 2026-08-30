class_name SkillingChestRewarder
## Rolls the Daily Skilling Chest paid out when a daily task is claimed.
##
## One chest per completed task, tiered off the difficulty the player chose:
## T1 Easy / T2 Medium / T3 Hard ([enum DailyTaskResource.Difficulty] maps
## straight onto it). The package MATCHES THE SKILL — a Hard Fishing task pays
## high-tier fish, not a generic pile of ore.
##
## Static service, not an autoload: the daily claim handler and the headless
## verify tools both reach it, and an autoload identifier does not resolve under
## `-s`. Same call this project already makes for QuestService / RewardService.
##
## WHY A CODE TABLE AND NOT 27 ChestResource .tres FILES
## [ChestResource] is the right shape for a hand-authored world chest, where each
## table is a bespoke design object. This is the opposite: nine skills times
## three tiers of the SAME curve, where the interesting content is "which
## resources belong to this skill" and the tier maths is shared. Authored as
## .tres that would be 27 files to keep in sync, and retuning the curve would
## mean editing all of them. The per-skill pools below are the only thing a
## designer needs to touch; the tier maths lives in [constant TIERS] once.
##
## Everything is resolved by SLUG through the content registry, so adding a
## resource to a pool is a one-line edit and a missing slug degrades to "that
## entry is skipped" (warned once) rather than a crash mid-claim.

## Loot pools per [JobRegistry] skill slug. Slugs, not display names — Crafting
## is &"outfitting" and Farming is &"harvesting".
##
##   low / mid / high — the skill's own resource ladder. Which bands a tier draws
##                      from is what makes a T3 chest feel different from a T1.
##   support          — adjacent-skill material that makes the haul usable
##                      (bars for a miner, arrowheads for a fletcher). T3 only.
const POOLS: Dictionary[StringName, Dictionary] = {
	&"mining": {
		"low": [&"copper_ore", &"tin_ore"],
		"mid": [&"iron_ore", &"coal_ore", &"silver_ore"],
		"high": [&"gold_ore", &"mithril_ore", &"adamant_ore", &"runite_ore"],
		"support": [&"bronze_bar", &"iron_bar", &"steel_bar", &"mithril_bar"],
	},
	&"woodcutting": {
		"low": [&"logs", &"oak_log"],
		"mid": [&"willow_log", &"maple_log"],
		"high": [&"yew_log", &"rosewood_log", &"wispwood_log"],
		"support": [&"headless_arrow"],
	},
	&"fishing": {
		"low": [&"shrimp", &"herring"],
		"mid": [&"trout", &"salmon", &"cod", &"crab"],
		"high": [&"lobster", &"tuna", &"turtle", &"anglerfish"],
		# Cooking feed — a fisher's haul should be worth taking to a range. The
		# "high-tier bait" from the design brief has no item in the game yet; add
		# the slugs here when it lands and no code changes.
		"support": [&"lionfish", &"parrot_fish"],
	},
	&"smithing": {
		"low": [&"bronze_bar", &"iron_bar"],
		"mid": [&"steel_bar", &"silver_bar"],
		"high": [&"mithril_bar", &"adamant_bar", &"runite_bar", &"gold_bar"],
		"support": [&"coal_ore", &"iron_ore"],
	},
	&"cooking": {
		"low": [&"shrimp", &"herring"],
		"mid": [&"trout", &"salmon", &"cod"],
		"high": [&"lobster", &"tuna", &"anglerfish"],
		"support": [&"crab", &"turtle"],
	},
	&"outfitting": {
		"low": [&"cloth_forest", &"leather_forest"],
		"mid": [&"cloth_cave", &"leather_cave", &"cloth_bandit"],
		"high": [&"leather_bandit", &"cloth_sewer", &"leather_sewer"],
		"support": [&"hide_forest", &"hide_cave"],
	},
	&"fletching": {
		"low": [&"logs", &"oak_log"],
		"mid": [&"willow_log", &"maple_log", &"headless_arrow"],
		"high": [&"yew_log", &"bronze_arrowheads", &"iron_arrowheads"],
		"support": [&"steel_arrowheads", &"mithril_arrowheads"],
	},
	&"harvesting": {
		"low": [&"healing_herb", &"cloth_forest"],
		"mid": [&"frostpetal", &"sunwort"],
		"high": [&"moonbloom", &"bloodcap", &"starblossom", &"grimshade"],
		"support": [&"vial_of_water"],
	},
	&"herblore": {
		"low": [&"healing_herb", &"vial_of_water"],
		"mid": [&"frostpetal", &"sunwort", &"ember_ash"],
		"high": [&"moonbloom", &"bloodcap", &"starblossom", &"venom_sac"],
		"support": [&"fairy_dust", &"blightspore"],
	},
}

## Per-tier shape. Indexed by [enum DailyTaskResource.Difficulty] (0/1/2).
##
##   draws       — how many DISTINCT entries to pull from each band.
##   base_amount — quantity range before the per-band scale below.
##   gold        — flat gold, paid straight to the pouch like a world chest.
##   gem         — chance of one cut gem on top (the "nice surprise" roll).
##   outfit      — chance of a Skilling Outfit piece. 0.1% / 0.5% / 1% per the
##                 design brief. Rolled ONCE per chest, independent of the rest.
const TIERS: Array[Dictionary] = [
	{
		"name": "Lesser Skilling Chest",
		"draws": {"low": 2, "mid": 1},
		"base_amount": Vector2i(15, 30),
		"gold": Vector2i(500, 1_200),
		"gem": 0.02,
		"outfit": 0.001,
	},
	{
		"name": "Skilling Chest",
		"draws": {"low": 1, "mid": 2, "high": 1},
		"base_amount": Vector2i(40, 80),
		"gold": Vector2i(2_000, 4_000),
		"gem": 0.06,
		"outfit": 0.005,
	},
	{
		"name": "Greater Skilling Chest",
		"draws": {"mid": 2, "high": 3, "support": 1},
		"base_amount": Vector2i(100, 180),
		"gold": Vector2i(6_000, 12_000),
		"gem": 0.15,
		"outfit": 0.01,
	},
]

## Quantity multiplier per band. A high-tier drop has to be rarer BY VOLUME too —
## 180 runite ore would out-earn a week of mining it, so the same draw that pays
## 180 copper pays ~54 runite.
const BAND_SCALE: Dictionary[String, float] = {
	"low": 1.0,
	"mid": 0.6,
	"high": 0.3,
	"support": 0.4,
}

## Cut gems, the tier-agnostic bonus roll. Deliberately the generic attribute
## gems rather than the boss-set gems: those are drop-table identity for their
## bosses and should not leak out of a skilling chest.
const GEM_POOL: Array[StringName] = [
	&"gem_vital_low", &"gem_vital_medium", &"gem_vital_high",
	&"gem_agile_low", &"gem_agile_medium", &"gem_agile_high",
	&"gem_focus_low", &"gem_focus_medium", &"gem_focus_high",
	&"gem_guard_low", &"gem_guard_medium", &"gem_guard_high",
]

## Gem grade paid by the outfit fallback, indexed by chest tier: a T1 chest
## consoles with a low gem, T3 with a high one. Matched by slug suffix against
## [constant GEM_POOL] so adding a fifth attribute line needs no change here.
const GEM_GRADES: Array[String] = ["_low", "_medium", "_high"]

## Slugs already warned about, so a missing item cannot flood the log on every
## claim of every player.
static var _warned_slugs: Dictionary[StringName, bool] = {}


# --- Public API --------------------------------------------------------------

## Roll and grant a chest for finishing [param skill] at [param difficulty].
##
## Gold goes straight to the pouch; items stage in
## [member PlayerResource.pending_chest_loot] exactly like a world chest, so a
## full bag never voids the reward and the existing claim UI handles it with no
## new client work.
##
## Returns the same payload shape as [method ChestResource.roll_and_grant], plus
## `tier` and an `outfit` entry when the rare roll hit.
static func grant(player: Player, skill: StringName, difficulty: int) -> Dictionary:
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}
	if not POOLS.has(skill):
		# Not an error: a skill with no authored pool simply pays no chest. The
		# daily's gold/XP reward is granted separately by the claim handler.
		return {"ok": false, "reason": "no_pool", "skill": String(skill)}
	var tier: int = clampi(difficulty, 0, TIERS.size() - 1)
	var spec: Dictionary = TIERS[tier]
	var resource: PlayerResource = player.player_resource

	# --- Gold ---
	var gold_band: Vector2i = spec["gold"]
	var gold: int = randi_range(gold_band.x, gold_band.y)
	if gold > 0 and Economy.gold_id() > 0:
		Inventory.add_item(
			resource.inventory, Economy.gold_id(), gold,
			false, resource.active_inventory_bag, resource.inventory_bags
		)

	# --- Resources ---
	var items: Array = []
	var pools: Dictionary = POOLS[skill]
	var base: Vector2i = spec["base_amount"]
	for band: String in (spec["draws"] as Dictionary):
		var count: int = int((spec["draws"] as Dictionary)[band])
		var scale: float = float(BAND_SCALE.get(band, 1.0))
		for slug: StringName in _draw_distinct(pools.get(band, []), count):
			var amount: int = maxi(1, roundi(float(randi_range(base.x, base.y)) * scale))
			# No rarity: a banded draw is guaranteed, not a lucky roll.
			_stage(resource, slug, amount, items)

	# --- Gem bonus ---
	if randf() < float(spec["gem"]) and not GEM_POOL.is_empty():
		_stage(resource, GEM_POOL[randi() % GEM_POOL.size()], 1, items, float(spec["gem"]))

	# --- Rare: Skilling Outfit piece ---
	var outfit: Dictionary = _roll_outfit(player, skill, tier, float(spec["outfit"]), items)

	return {
		"ok": true,
		"tier": tier + 1,
		"chest": str(spec["name"]),
		"skill": String(skill),
		"gold": gold,
		"items": items,
		"outfit": outfit,
		"pending": PendingChestLoot.to_payload(resource.pending_chest_loot),
		"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
	}


## Chance of an outfit piece at [param difficulty], for tooltips and the board UI
## so the number players are shown comes from the same table the roll uses.
static func outfit_chance(difficulty: int) -> float:
	return float(TIERS[clampi(difficulty, 0, TIERS.size() - 1)]["outfit"])


## Boot-time content check: every pooled slug resolves to a real item. Returns
## the problems (empty = healthy) so a verify tool can assert on it, rather than
## discovering a typo the first time a player claims that skill's chest.
static func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	for skill: StringName in POOLS:
		if not JobRegistry.has_job(skill):
			problems.append("pool '%s' is not a registered job" % skill)
		for band: Variant in (POOLS[skill] as Dictionary):
			for slug: Variant in ((POOLS[skill] as Dictionary)[band] as Array):
				if _resolve_id(StringName(str(slug))) <= 0:
					problems.append("%s/%s: unknown item '%s'" % [skill, band, slug])
	for slug: StringName in GEM_POOL:
		if _resolve_id(slug) <= 0:
			problems.append("gem pool: unknown item '%s'" % slug)
	return problems


# --- internals ---------------------------------------------------------------

## Roll for a Skilling Outfit piece and stage it if it hits.
##
## DUPLICATE PROTECTION. At a 1-in-1000 to 1-in-100 roll, handing back the hat
## the player is already wearing is the difference between a memorable drop and
## a dead one. The draw is therefore taken ONLY from the pieces
## [SkillingOutfitManager] reports as missing — bag, bank, Boss Hunt stash,
## staged claim loot and worn gear all count as owned — so a player holding 2 of
## 4 is guaranteed one of the other 2.
##
## When there is nothing left to grant the roll pays a tier-appropriate gem
## instead of a duplicate. A duplicate has vendor value, but it reads as the
## game failing to notice what you already own; the gem reads as a reward and is
## worth more at the tiers that roll it most often.
static func _roll_outfit(
	player: Player, skill: StringName, tier: int, chance: float, items: Array
) -> Dictionary:
	if chance <= 0.0 or randf() >= chance:
		return {}
	var set_slug: StringName = SkillingOutfitManager.set_for_skill(skill)
	if set_slug == &"":
		# Five of the nine skills have no set authored yet. Rather than silently
		# eat the rare roll, pay a gem so the lucky roll is still worth something.
		return _gem_fallback(player, tier, chance, items, "no_set")

	var missing: Array[StringName] = SkillingOutfitManager.missing_pieces(player, set_slug)
	if missing.is_empty():
		return _gem_fallback(player, tier, chance, items, "set_complete", set_slug)
	var pick: StringName = missing[randi() % missing.size()]
	if not _stage(player.player_resource, pick, 1, items, chance):
		# The piece is not stamped in the items index, so staging it pays
		# nothing at all. Spend the roll on a gem rather than on silence — and
		# SkillingOutfitManager.validate() is what reports the content gap.
		return _gem_fallback(player, tier, chance, items, "unresolved_piece", set_slug)
	return {
		"set": String(set_slug),
		"slug": String(pick),
		"remaining": missing.size() - 1,
		"duplicate": false,
	}


## Pay a rare roll out as a gem when no outfit piece can be granted.
## [param reason] rides along in the payload so the reward window — and anyone
## reading a bug report — can say WHY a 1-in-100 roll paid a gem.
static func _gem_fallback(
	player: Player, tier: int, chance: float, items: Array, reason: String,
	set_slug: StringName = &""
) -> Dictionary:
	var slug: StringName = fallback_gem_for_tier(tier)
	if slug == &"" or not _stage(player.player_resource, slug, 1, items, chance):
		return {}
	return {
		"set": String(set_slug),
		"slug": String(slug),
		"fallback": reason,
		"duplicate": false,
	}


## A gem of the grade matching [param tier]. The attribute line (vital / agile /
## focus / guard) stays random — the GRADE is what makes the consolation feel
## tier-appropriate rather than a flat trinket.
##
## Public so the board UI can name what a completed set now pays, and so the
## verify gate can assert the tier mapping without rolling anything.
static func fallback_gem_for_tier(tier: int) -> StringName:
	if GEM_POOL.is_empty():
		return &""
	var grade: String = GEM_GRADES[clampi(tier, 0, GEM_GRADES.size() - 1)]
	var candidates: Array[StringName] = []
	for slug: StringName in GEM_POOL:
		if String(slug).ends_with(grade):
			candidates.append(slug)
	if candidates.is_empty():
		# The grade suffixes changed under us. Any gem beats eating the roll.
		return GEM_POOL[randi() % GEM_POOL.size()]
	return candidates[randi() % candidates.size()]


## Pick [param count] distinct slugs from [param pool] without replacement.
## Uniform, unlike ChestResource's weighted draw: these pools are already banded
## by tier, so a second weight axis inside a band would just be two knobs
## fighting over the same feeling.
static func _draw_distinct(pool: Variant, count: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if pool is not Array:
		return out
	var candidates: Array[StringName] = []
	for slug: Variant in (pool as Array):
		candidates.append(StringName(str(slug)))
	for _i: int in mini(count, candidates.size()):
		var index: int = randi() % candidates.size()
		out.append(candidates[index])
		candidates.remove_at(index)
	return out


## Stage one stack into pending chest loot. Returns false (and warns once) for a
## slug that does not resolve, so a content typo costs that one entry rather than
## the whole claim.
## [param roll_chance] is the independent probability that produced this entry,
## or 0.0 for a guaranteed banded draw. It only decides how loudly the reward
## window presents it — see [LootRarity].
static func _stage(
	resource: PlayerResource, slug: StringName, amount: int, items: Array,
	roll_chance: float = 0.0
) -> bool:
	if amount <= 0:
		return false
	var id: int = _resolve_id(slug)
	if id <= 0:
		return false
	PendingChestLoot.add(resource.pending_chest_loot, id, amount)
	var item: Resource = ContentRegistryHub.load_by_slug(&"items", slug)
	items.append({
		"id": id,
		"amount": amount,
		"name": str((item as Item).item_name) if item is Item else String(slug),
		"rarity": LootRarity.name_for(roll_chance),
	})
	return true


## Item registry id for a slug, or 0. Warns once per unknown slug — the symptom
## otherwise is a chest that quietly pays one stack less than it should.
static func _resolve_id(slug: StringName) -> int:
	var id: int = ContentRegistryHub.id_from_slug(&"items", slug)
	if id <= 0 and not _warned_slugs.has(slug):
		_warned_slugs[slug] = true
		push_warning("SkillingChestRewarder: no item indexed for slug '%s' — that entry will be skipped." % slug)
	return id
