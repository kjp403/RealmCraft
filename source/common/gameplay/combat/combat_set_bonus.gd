class_name CombatSetBonus
## Combat set bonuses for the boss collection-log sets.
##
## The point of these is that a collection-log set should stay worth wearing for
## a while after its raw stats have been out-scaled, WITHOUT the stats themselves
## being inflated into endgame territory. The pieces sit on the ordinary crafted
## curve at their boss's own tier; the set bonus is the reason to keep the pair
## on rather than mixing best-in-slot.
##
## NOT the same system as [SkillingOutfitManager], and deliberately so. That one
## pays per-SKILL gathering bonuses resolved at gather time and never touches
## stats_component. These are combat stats, so they go through the same
## [StatsComponent.modify_stat] path gear already uses — which means every
## consumer (melee arcs, lifesteal, ability haste, the character sheet) picks
## them up with no further wiring.
##
## HIGHEST MATCHING TIER WINS; TIERS DO NOT STACK. Wearing three pieces pays the
## 3-piece row only, not 2-piece plus 3-piece. Cumulative tiers read fine in a
## table and then quietly double-count the moment someone authors a set whose
## rows overlap, and the bug looks like "this set is oddly strong" rather than
## like a bug.
##
## Server-only, exactly like gear modifiers: [EquipmentComponent] applies these
## behind an is_server() gate and clients receive the resulting stats through the
## normal sync. Nothing here may run on a client.

## set slug -> {name, pieces, tiers}
##
##   pieces — item registry SLUGS (metadata/slug). Membership is what counts;
##            order is cosmetic. Slugs, not display names — a table written
##            against names silently never procs.
##   tiers  — pieces-worn threshold -> {Stat: amount}. Read highest-first, so a
##            set can pay at 2 and again (differently) at 3.
##
## Amounts are in each stat's OWN units, which are not uniform:
##   LIFESTEAL          percent (Berserk grants 25.0 for 25%)
##   DAMAGE_VS_LOW_HP   percent, applied below 35% target HP (hammer tree: 8-9/node)
##   HEALTH_REGEN       HP per second, on a 0.5 base
##   ABILITY_HASTE      flat haste points
##   ARMOR / MR / AD    flat, same units as gear
const SETS: Dictionary[StringName, Dictionary] = {
	# Vurthek, the Cinderborn — tier 30. Cindermantle is the torso of this set:
	# it drops from the same boss, and after its re-tier it sits on the same
	# curve, so the three pieces finally read as one kit.
	# Fantasy: the heat never banks, so neither do you.
	&"slagborn": {
		"name": "Slagborn",
		"pieces": [&"slagborn_helm", &"slagborn_sabatons", &"cindermantle"],
		"tiers": {
			2: {Stat.LIFESTEAL: 3.0, Stat.HEALTH_REGEN: 0.3},
			3: {Stat.LIFESTEAL: 5.0, Stat.HEALTH_REGEN: 0.5, Stat.AD: 8.0},
		},
	},
	# The Bloated Sovereign — tier 15, and the earliest set a player can chase.
	# Two pieces only, so the whole bonus lands at 2.
	# Fantasy: the silt sets into you as a second skin.
	&"siltbound": {
		"name": "Siltbound",
		"pieces": [&"siltbound_coronet", &"siltbound_plate"],
		"tiers": {
			2: {Stat.ARMOR: 10.0, Stat.MR: 12.0, Stat.HEALTH_REGEN: 0.4},
		},
	},
	# Ankhemet, the Sand King — tier 25. The signet is the third piece, and the
	# 3-piece row is where the ring earns its 1/50 rarity.
	# Fantasy: the promise the dunes were made under is still being kept.
	#
	# Identity is ABILITY UPTIME, and the two stats are a pair on purpose: haste
	# makes specials come back sooner, mana-on-hit pays for them. Mana is the real
	# gate on a 50 pool regenerating 0.5/s against 12-40 cost abilities, so haste
	# alone just moves the bottleneck rather than removing it.
	#
	# This row used to carry DAMAGE_VS_LOW_HP and that was a mistake: the stat is
	# read ONLY in melee_arc.gd, so it paid nothing at all to a bow, wand or book
	# user — half the builds farming a 30,000g, level-72 contract got a dead stat.
	# Both stats here are read in Character.take_damage / Ability.effective_cooldown,
	# which every attack type goes through. See MELEE_ONLY_STATS.
	&"ankhemet": {
		"name": "Ankhemet",
		"pieces": [&"ankhemet_mask", &"ankhemet_wrappings", &"ankhemet_signet"],
		"tiers": {
			2: {Stat.ABILITY_HASTE: 6.0},
			3: {Stat.ABILITY_HASTE: 12.0, Stat.MANA_ON_HIT: 2.0},
		},
	},
}

## Stats that only SOME attack types ever read. A set bonus must never be built
## from one of these: it silently pays nothing to the builds that cannot trigger
## it, and the set reads as under-rewarding rather than as broken.
##
##   DAMAGE_VS_LOW_HP  read only in melee_arc.gd — melee swings, nothing else.
##   CRIT_CHANCE       declared in Stat and referenced by the tooltip category
##   CRIT_DAMAGE       map, but read by NO combat code at all. Authoring either
##                     onto gear or a set does exactly nothing today.
##
## tools/verify_combat_set_bonus.gd fails on any set that uses one.
const MELEE_ONLY_STATS: Array[StringName] = [
	Stat.DAMAGE_VS_LOW_HP, Stat.CRIT_CHANCE, Stat.CRIT_DAMAGE,
]

## piece slug -> set slug. Built once; equipment changes ask this on every swap.
static var _piece_index: Dictionary[StringName, StringName] = {}
static var _indexed: bool = false


## The set a piece belongs to, or &"" — the cheap early-out for the 99% of items
## that are in no set at all.
static func set_of(piece_slug: StringName) -> StringName:
	_build_index()
	return _piece_index.get(piece_slug, &"")


## How many pieces of each set are present in [param items], keyed set -> count.
## Takes the live equipped_items map so the caller does not have to know how a
## piece is identified.
static func worn_counts(items: Dictionary) -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	var seen: Dictionary[StringName, bool] = {}
	for slot: Variant in items:
		var item: Item = items[slot] as Item
		if item == null:
			continue
		var slug: StringName = StringName(str(item.get_meta(&"slug", &"")))
		if slug.is_empty():
			continue
		# One slug counts once. Two rings of the same kind must not pay twice —
		# and nothing stops a future slot layout from allowing that.
		if seen.has(slug):
			continue
		seen[slug] = true
		var set_slug: StringName = set_of(slug)
		if set_slug.is_empty():
			continue
		counts[set_slug] = int(counts.get(set_slug, 0)) + 1
	return counts


## Every stat bonus earned by [param items], flattened to Stat -> amount and
## ready to hand to modify_stat. Empty when nothing qualifies, which is the
## overwhelmingly common case.
static func bonuses_for(items: Dictionary) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	for set_slug: StringName in worn_counts(items):
		var row: Dictionary = tier_row(set_slug, int(worn_counts(items)[set_slug]))
		for stat: Variant in row:
			var key: StringName = StringName(str(stat))
			out[key] = float(out.get(key, 0.0)) + float(row[stat])
	return out


## The single tier row earned at [param worn] pieces — the HIGHEST threshold met,
## never a sum of rows. Empty when the set pays nothing at that count.
static func tier_row(set_slug: StringName, worn: int) -> Dictionary:
	if not SETS.has(set_slug) or worn <= 0:
		return {}
	var tiers: Dictionary = (SETS[set_slug] as Dictionary)["tiers"]
	var best: int = 0
	for threshold: Variant in tiers:
		var t: int = int(threshold)
		if worn >= t and t > best:
			best = t
	return tiers.get(best, {}) if best > 0 else {}


## Display name for a set slug, for tooltips and the collection log.
static func display_name(set_slug: StringName) -> String:
	if not SETS.has(set_slug):
		return ""
	return str((SETS[set_slug] as Dictionary).get("name", ""))


## Total pieces in a set, for "2 / 3 worn" readouts.
static func piece_count(set_slug: StringName) -> int:
	if not SETS.has(set_slug):
		return 0
	return (((SETS[set_slug] as Dictionary)["pieces"]) as Array).size()


static func _build_index() -> void:
	if _indexed:
		return
	_indexed = true
	for set_slug: StringName in SETS:
		for piece: Variant in ((SETS[set_slug] as Dictionary)["pieces"] as Array):
			_piece_index[StringName(str(piece))] = set_slug
