class_name AnvilBoost
## Server-only. The Anvil Stabilizer: a timed SMITHING SPEED buff.
##
## RULE. While [member PlayerResource.anvil_boost_until_ms] is in the future,
## every craft at a [constant PROFESSION] station is paced at
## [constant SPEED_MULTIPLIER] times normal speed — the furnace's bars AND the
## anvil's equipment. That is the whole effect. There is no run cap, no charge
## to spend and no cooldown: a smith with ore may smelt all of it, stabilised or
## not, and the stabilizer buys the same work done in half the sitting.
##
## SCOPED BY PROFESSION, not by station id, so the furnace and the anvil are
## both covered by the one rule and a third smithing station added later is fast
## for free. Cooking, fletching, herblore and the outfitting benches are
## untouched — this is a smith's good.
##
## THE PACING NUMBERS LIVE WITH CRAFTING, not here: the client loop owns
## [constant CraftController.CRAFT_INTERVAL] and the server owns its own
## authoritative floor. This class only answers "how much faster than that", so
## a change to the base craft speed does not have to be mirrored in the shop.
##
## The expiry is a unix-MILLISECONDS wall-clock stamp, like
## [member PlayerResource.hunter_charm_until_ms], so it survives a relog and a
## server restart rather than resetting into free time. It rides the peddler_json
## column with the rest of the peddler state — see [PlayerResource].

## How long one stabilizer runs, in seconds.
const DURATION_S: int = 600
## How much faster a stabilised smith crafts. 2.0 = twice the speed, i.e. half
## the interval between crafts.
const SPEED_MULTIPLIER: float = 2.0
## The one profession the stabilizer speeds up: the furnace and the anvil.
const PROFESSION: StringName = &"smithing"
## Status-strip id, so the HUD can show the buff ticking down.
const STATUS_ID: StringName = &"anvil_stabilizer"


## True while [param resource] is stabilised.
static func is_active(resource: PlayerResource) -> bool:
	if resource == null:
		return false
	return resource.anvil_boost_until_ms > _now_ms()


## Seconds of stabilizer left (0 when inactive).
static func remaining_s(resource: PlayerResource) -> int:
	if not is_active(resource):
		return 0
	@warning_ignore("integer_division")
	var seconds: int = (resource.anvil_boost_until_ms - _now_ms()) / 1000
	return maxi(0, seconds)


## The craft-speed multiplier that applies to [param profession] right now.
## 1.0 for everything the stabilizer does not touch, so callers can divide their
## own interval by this unconditionally.
static func speed_multiplier(resource: PlayerResource, profession: StringName) -> float:
	if profession != PROFESSION or not is_active(resource):
		return 1.0
	return SPEED_MULTIPLIER


## Start (or extend) the buff on [param resource], returning the new expiry.
## Buying a second stabilizer while one is running ADDS ten minutes rather than
## restarting the clock — the good is time, and time already paid for must not
## be thrown away by a purchase.
static func extend(resource: PlayerResource) -> int:
	if resource == null:
		return 0
	var base_ms: int = maxi(_now_ms(), resource.anvil_boost_until_ms)
	resource.anvil_boost_until_ms = base_ms + DURATION_S * 1000
	return resource.anvil_boost_until_ms


## Drop a lapsed stamp so a long-expired timer is not carried around forever.
## Cosmetic hygiene only — [method is_active] already reads it as inactive.
static func clear_if_expired(resource: PlayerResource) -> void:
	if resource == null or resource.anvil_boost_until_ms == 0:
		return
	if resource.anvil_boost_until_ms <= _now_ms():
		resource.anvil_boost_until_ms = 0


static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
