class_name BaitBucket
## The Bottomless Bait Bucket's charge, and the only sanctioned way to move bait in
## or out of it. Static functions over a [PlayerResource], like every other service
## in this project (SlayerTaskService, QuestService, FilletService).
##
## WHY THE CHARGE IS NOT ON THE ITEM
## The obvious shape — `stored_bait` as an @export on a BaitBucketItem — is broken
## here, in two independent ways, and both fail silently:
##
##  1. Item .tres files are loaded ONCE per process and handed out by reference
##     (ContentRegistryHub.load_by_id uses CACHE_MODE_REUSE). Every player on the
##     world server would share the same bucket object, so one player's fill would
##     top up everyone's and one player's cast would drain everyone's.
##  2. Per-slot storage does not survive either: [method Inventory.normalize] hard
##     rebuilds every slot as {id, a, bag, p} and drops any other key, so a
##     `stored_bait` written onto the slot is erased the next time the inventory is
##     normalized — with no error anywhere.
##
## So the charge lives on the player, one bucket per character. That also matches
## what the item actually is: "bottomless" means you own the concept, not a
## stack of buckets to juggle.
##
## SERVER-AUTHORITATIVE. PlayerResource is server-only (always null on a client),
## so a client that fabricates a fill packet is refused by the handler, not by this
## file. The client renders [method status_payload] and asks.
##
## The bucket is bought for GOLD at the Beach Tackle shop alongside the rods, so
## the combo is reachable at Fishing 1. Bait itself is never sold — it only comes
## from filleting your own catch, which is what makes the combo a trade (fish for
## XP) rather than a gold sink.

## Hard ceiling on stored bait. Every write clamps to it, so no path — fill,
## refund, admin grant — can push the stored count past it.
const MAX_STORED: int = 10000

## Item slug of the bait this bucket holds. Resolved through the registry rather
## than hardcoding an id: a hand-written id that drifts from items_index silently
## resolves to nothing and the bucket would refuse every fill.
const BAIT_SLUG: StringName = &"fish_bait"

## Item slug of the bucket itself, used for the ownership check.
const BUCKET_SLUG: StringName = &"bottomless_bait_bucket"

# ---------------------------------------------------------------------------
# Registry lookups
# ---------------------------------------------------------------------------

## Registry id of the Fish Bait item, or 0 before the items index is built.
## 0 is always treated as "unavailable", never as a wildcard.
static func bait_id() -> int:
	if ContentRegistryHub.registry_of(&"items") == null:
		return 0
	return ContentRegistryHub.id_from_slug(&"items", BAIT_SLUG)


## Registry id of the Bottomless Bait Bucket item, or 0 if unindexed.
static func bucket_id() -> int:
	if ContentRegistryHub.registry_of(&"items") == null:
		return 0
	return ContentRegistryHub.id_from_slug(&"items", BUCKET_SLUG)


## True when the player is actually carrying a bucket. The stored charge persists
## whether or not they hold one (dropping the bucket must not delete the bait), but
## every spend path checks this first — bait is only reachable through the item.
static func has_bucket(resource: PlayerResource) -> bool:
	if resource == null:
		return false
	var id: int = bucket_id()
	return id > 0 and Inventory.has_item(resource.inventory, id)


# ---------------------------------------------------------------------------
# Reads — the helpers Module 3 asks for
# ---------------------------------------------------------------------------

## Bait currently in the bucket, clamped defensively in case an older save row
## carried a value from before [constant MAX_STORED] existed.
static func stored(resource: PlayerResource) -> int:
	if resource == null:
		return 0
	return clampi(resource.stored_bait, 0, MAX_STORED)


## True when there is at least one bait AND the player is carrying the bucket to
## reach it. Callers use this as the single "can I bait this cast?" question, so
## the two conditions can never be checked apart.
static func has_bait(resource: PlayerResource) -> bool:
	return has_bucket(resource) and stored(resource) > 0


## Everything a client needs to draw the bucket, in ONE shape.
##
## Three surfaces read this — the bag tooltip, the fishing combo chip and the
## Fill reply — and they used to be three different dictionaries. One shape means
## the hover card and the HUD cannot disagree about how much bait is left, which
## is the only thing either of them is for.
##
## `has_bucket` is carried rather than inferred from `stored > 0`: the charge
## survives dropping the bucket, so a player with 400 bait and no bucket is a
## real state, and it is exactly the one where the tooltip must not promise a
## combo the next cast cannot pay for.
static func status_payload(resource: PlayerResource) -> Dictionary:
	return {
		"stored": stored(resource),
		"max": MAX_STORED,
		"has_bucket": has_bucket(resource),
	}


# ---------------------------------------------------------------------------
# Writes
# ---------------------------------------------------------------------------

## Spend [param amount] bait. All-or-nothing: returns false and changes nothing
## when the bucket is missing or short, so a caller can use it directly as the gate
## for a bonus rather than checking first and spending second (which would race
## itself if the two ever drifted apart).
static func consume_bait(resource: PlayerResource, amount: int = 1) -> bool:
	if resource == null or amount <= 0:
		return false
	if not has_bucket(resource):
		return false
	var have: int = stored(resource)
	if have < amount:
		return false
	_set_stored(resource, have - amount)
	return true


## Move every loose Fish Bait stack out of the bags and into the bucket. Returns
## {"ok": bool, "moved": int, "stored": int, "capped": bool}.
##
## `capped` is reported rather than silently truncating: a player who fills at 9,990
## stored needs to be told the rest stayed in their bags, not left to wonder where
## it went.
static func fill_from_inventory(resource: PlayerResource) -> Dictionary:
	if resource == null:
		return {"ok": false, "reason": "no_player"}
	if not has_bucket(resource):
		return {"ok": false, "reason": "no_bucket"}

	var id: int = bait_id()
	if id <= 0:
		return {"ok": false, "reason": "no_bait_item"}

	var loose: int = Inventory.count(resource.inventory, id)
	if loose <= 0:
		return {"ok": false, "reason": "no_bait", "stored": stored(resource)}

	var room: int = MAX_STORED - stored(resource)
	if room <= 0:
		return {"ok": false, "reason": "bucket_full", "stored": stored(resource)}

	var moved: int = mini(loose, room)
	# Remove first. remove_amount_by_id is all-or-nothing, so a failure here leaves
	# both the bag and the bucket untouched rather than crediting bait that was
	# never taken.
	if not Inventory.remove_amount_by_id(resource.inventory, id, moved):
		return {"ok": false, "reason": "no_bait", "stored": stored(resource)}

	_set_stored(resource, stored(resource) + moved)
	return {
		"ok": true,
		"moved": moved,
		"stored": stored(resource),
		"capped": moved < loose,
	}


## The single write point. Every mutation clamps here, so no path can set an
## out-of-range count.
static func _set_stored(resource: PlayerResource, value: int) -> void:
	var clamped: int = clampi(value, 0, MAX_STORED)
	if resource.stored_bait == clamped:
		return
	resource.stored_bait = clamped
