class_name FishingBus
extends RefCounted
## One signal carrier for the Angler services — [BaitBucket] and
## [FishingComboManager]. Those are static services with no object to hang a
## signal on, so each keeps one lazily created instance of this. Same arrangement,
## and the same reasoning, as [SkillingEvents.bus]: a `class_name` with static
## entry points resolves in the headless `-s` tool runs this project gates on,
## where a bare autoload identifier is not a missing node at runtime but
## "Identifier not found" at COMPILE time.
##
## WHY EVERY SIGNAL CARRIES A PlayerResource
## One world process hosts many players at once. `bait_count_changed(count)` with
## no identity is unroutable — the listener cannot tell whose bucket moved, and
## the only recoveries are a global "current player" (wrong the moment two people
## fish on the same tick) or a lookup the emitter already had in hand. Threaded
## through explicitly instead, exactly as [SkillingEvents] documents.
##
## These fire on the SERVER, where PlayerResource exists. Client UI does not
## connect here — the combo rides the existing `mining.gather_result` push (see
## [method MineableNode.register_gather_hit]) and the bucket count comes back on
## the `bait.fill` reply.

## Stored bait moved: a fill, or a cast that spent one. [param count] is the new
## total already clamped to [constant BaitBucket.MAX_STORED].
signal bait_count_changed(player_res: PlayerResource, count: int)

## A catch extended the combo. [param streak] is the new consecutive count and
## [param multiplier] the XP factor it earns, already capped.
signal combo_streak_updated(player_res: PlayerResource, streak: int, multiplier: float)

## The combo broke — the player moved off the spot, switched nodes, worked the
## node out, ran the bucket dry, or let it lapse. Carries [param reason] so the
## HUD can say which, rather than silently blanking a streak the player was
## watching climb.
signal combo_reset(player_res: PlayerResource, reason: StringName)
