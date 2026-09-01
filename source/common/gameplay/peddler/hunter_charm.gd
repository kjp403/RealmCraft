class_name HunterCharm
## Server-only. The Hunter's Charm blessing: a timed nudge to HIGH-TIER boss
## drop rolls.
##
## RULE. While blessed, a drop rolled off a BOSS whose authored chance already
## makes it rare ([method LootRarity.is_celebrated] — RARE or ULTRA) rolls at
## [constant DROP_MULTIPLIER] its chance. Common boss drops are untouched, and
## nothing at all changes on ordinary mobs.
##
## Scoping it to rolls that were ALREADY rare is what keeps the charm from being
## a flat loot multiplier: 15% more of a 1-in-2000 relic is a real, felt
## difference on the drop players actually want, while 15% more bones is noise.
## Reading "rare" off LootRarity rather than a second threshold here means the
## charm and the loot beams can never disagree about what counts as a big drop.
##
## The expiry is a unix-ms stamp on [member PlayerResource.hunter_charm_until_ms],
## so it persists and keeps ticking while the player is offline. That is
## deliberate: it is a two-HOUR consumable bought for 350,000 gold, and a timer
## that paused on logout would make it a "log in only when ready" chore.

## What a qualifying roll's chance is multiplied by.
const DROP_MULTIPLIER: float = 1.15
## Toast pushed to the blessed player when the charm is what landed the drop.
const TOAST_TEXT: String = "Hunter's Blessing Triggered!"


## True when [param resource] is currently blessed.
static func is_active(resource: PlayerResource) -> bool:
	if resource == null:
		return false
	return resource.hunter_charm_until_ms > int(Time.get_unix_time_from_system() * 1000.0)


## Seconds of blessing left (0 when inactive).
static func remaining_s(resource: PlayerResource) -> int:
	if not is_active(resource):
		return 0
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	@warning_ignore("integer_division")
	var seconds: int = (resource.hunter_charm_until_ms - now_ms) / 1000
	return maxi(0, seconds)


## True when the charm applies to a drop of [param chance] off [param is_boss].
static func boosts(resource: PlayerResource, is_boss: bool, chance: float) -> bool:
	if not is_boss or not is_active(resource):
		return false
	return LootRarity.is_celebrated(LootRarity.tier_for(chance))


## The chance [param chance] is actually rolled at for [param resource].
## Clamped to 1.0 so a boosted near-certain drop cannot exceed certainty.
static func adjusted_chance(resource: PlayerResource, is_boss: bool, chance: float) -> float:
	if not boosts(resource, is_boss, chance):
		return chance
	return minf(1.0, chance * DROP_MULTIPLIER)


## True when a roll of [param roll] against [param chance] only succeeded BECAUSE
## of the charm — it beat the boosted chance but would have missed the base one.
## This is what the "Hunter's Blessing Triggered!" toast is gated on: firing it on
## every rare drop while blessed would take credit for drops the charm had no
## hand in, and players would stop believing the toast.
static func was_decisive(
	resource: PlayerResource, is_boss: bool, chance: float, roll: float
) -> bool:
	if not boosts(resource, is_boss, chance):
		return false
	return roll > chance and roll <= adjusted_chance(resource, is_boss, chance)
