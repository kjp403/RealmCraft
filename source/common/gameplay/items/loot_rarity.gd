class_name LootRarity
## How loud a reward should land, decided SERVER-SIDE from the roll that actually
## produced it.
##
## The UI has no business knowing drop rates. Without this the reward window would
## need its own copy of "an outfit piece is 1-in-1000", which is a second source of
## truth that silently rots the first time a rate is retuned — and a client that
## knows the rates is also a client that can be read for them. The granting code
## already holds the real probability at the moment it rolls, so it stamps a TIER
## on the ledger entry and the window just switches on the name.
##
## Stamped only where a genuine independent probability exists: the Skilling
## Outfit roll, the chest gem bonus, and [member ChestResource.exclusive_loot].
## The main chest pool is a weighted draw WITHOUT replacement across several
## picks, so its per-entry weight is not a probability and tiering it would be
## inventing a number. Those entries carry no rarity and read as COMMON, which is
## honest: you were always going to get some of them.

enum Tier { COMMON, UNCOMMON, RARE, ULTRA }

## Upper bound of each tier, walked low-to-high. A drop at or under the bound
## takes that tier. ULTRA is everything rarer than RARE's bound.
##
## The 1.2% RARE bound is deliberately just above the 1% T3 Skilling Outfit roll,
## so the best outfit chance in the game still reads as ULTRA. If outfit rates
## ever climb past this, move the bound rather than special-casing the item.
const ULTRA_MAX: float = 0.012
const RARE_MAX: float = 0.05
const UNCOMMON_MAX: float = 0.25

## Wire keys. Strings, not the enum ordinal, so a reordered enum cannot silently
## repaint every reward in the game.
const NAMES: Dictionary[Tier, String] = {
	Tier.COMMON: "common",
	Tier.UNCOMMON: "uncommon",
	Tier.RARE: "rare",
	Tier.ULTRA: "ultra",
}


## Tier for a drop that had [param chance] (0..1) of happening. A non-positive
## chance means "not rolled for" and reads as COMMON.
static func tier_for(chance: float) -> Tier:
	if chance <= 0.0:
		return Tier.COMMON
	if chance <= ULTRA_MAX:
		return Tier.ULTRA
	if chance <= RARE_MAX:
		return Tier.RARE
	if chance <= UNCOMMON_MAX:
		return Tier.UNCOMMON
	return Tier.COMMON


## Wire name for a drop that had [param chance] of happening. This is what goes
## on a ledger entry's "rarity" key.
static func name_for(chance: float) -> String:
	return NAMES[tier_for(chance)]


## Parse a wire name back to a tier. Unknown / missing reads as COMMON, so an
## older client and a newer server disagree by under-celebrating rather than by
## erroring.
static func from_name(value: String) -> Tier:
	for tier: Tier in NAMES:
		if NAMES[tier] == value:
			return tier
	return Tier.COMMON


## True when a drop deserves the full treatment — particles, glow, a held beat in
## the reward window. One place decides it so the window and any future killfeed
## agree on what "rare enough to stop for" means.
static func is_celebrated(tier: Tier) -> bool:
	return tier == Tier.RARE or tier == Tier.ULTRA
