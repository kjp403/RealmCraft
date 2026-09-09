class_name FishingComboManager
## Rewards working ONE fishing spot with bait instead of hopping between them.
## Each baited catch at the same node extends a streak; the streak buys a Fishing
## XP multiplier. Moving off, switching nodes, running the bucket dry or simply
## stopping all break it.
##
## WHY THE STATE IS NOT PERSISTED
## A combo is deliberately session-shaped: it should not survive a relog, a hop
## between world instances, or the ~20 seconds after which a ServerInstance is
## swept. So it lives here, in a static map keyed by player_id, and is dropped on
## disconnect. Everything durable this module touches — the bait itself — lives on
## PlayerResource via [BaitBucket]. (Contrast [GatherNodeLedger], whose charge pools
## MUST persist and therefore live on the character.)
##
## WHY MOVEMENT IS DETECTED BY POSITION, NOT VELOCITY
## The natural rule is `player.velocity.length() > 0`. It cannot work on this
## server. Movement here is client-authoritative: LocalPlayer integrates velocity
## locally and syncs only `:position` (see local_player.gd's fid_position). Nothing
## writes `:velocity` on a remote Player, so a server-side read of it is ALWAYS
## Vector2.ZERO — the check would compile, run, and never once fire, leaving the
## combo unbreakable by walking. Position does arrive, so the anchor below is
## sampled when the streak starts and compared on every catch.
##
## SERVER-AUTHORITATIVE. Called from [method MineableNode.register_gather_hit],
## which has already committed the catch.

## Fraction added to the XP multiplier per consecutive catch.
const STEP: float = 0.02

## Ceiling on the multiplier — +40% at 20 consecutive catches.
const MAX_MULTIPLIER: float = 1.40

## How far the player may drift from where the streak started before it breaks, in
## pixels. Generous enough to absorb the small shuffle a click-to-move cast leaves
## behind, tight enough that walking to the next spot always breaks it.
const MOVE_TOLERANCE_PX: float = 48.0

## A streak lapses after this long without a catch. Without it, a player could
## bank, run a dungeon, come back and resume a capped multiplier — the streak is
## supposed to reward staying, and staying is a thing you stop doing.
const LAPSE_MS: int = 45_000

## Safety valve on the state map. A world process that somehow never sees a
## disconnect must not accumulate entries forever.
const MAX_TRACKED: int = 4096

## player_id -> {"node": String, "streak": int, "anchor": Vector2, "last_ms": int}
static var _state: Dictionary[int, Dictionary] = {}

static var _bus: FishingBus


static func bus() -> FishingBus:
	if _bus == null:
		_bus = FishingBus.new()
	return _bus


# ---------------------------------------------------------------------------
# Catch hook
# ---------------------------------------------------------------------------

## A fish was landed at [param node_key]. Advances or breaks the streak and returns
## the Fishing XP multiplier THIS catch earns (1.0 when there is no bonus).
##
## [param node_key] must be the stable
## [method GatherNodeLedger.node_key] identity, not the node's name: a name is
## unique only within one live Map, so two instances of the same biome would share
## a key and a player hopping between them would keep a streak they should have
## lost. [param position] is the player's world position, used as the movement
## anchor — see the class docs for why velocity cannot be used here.
##
## Bait is spent only when the streak actually ADVANCES. A catch that starts a
## streak, or one that breaks it, costs nothing.
static func register_catch(
	resource: PlayerResource, player_id: int, node_key: String, position: Vector2
) -> float:
	if resource == null or player_id <= 0 or node_key.is_empty():
		return 1.0

	var now: int = Time.get_ticks_msec()
	var entry: Dictionary = _state.get(player_id, {})

	# --- Break conditions, cheapest first ---------------------------------
	if not entry.is_empty():
		var reason: StringName = _break_reason(entry, node_key, position, now)
		if reason != &"":
			_reset(resource, player_id, reason)
			entry = {}

	# --- Start a fresh streak --------------------------------------------
	# The catch that begins a streak pays no bonus and costs no bait: there is
	# nothing consecutive about a first cast.
	if entry.is_empty():
		_prune(now)
		_state[player_id] = {
			"node": node_key,
			"streak": 0,
			"anchor": position,
			"last_ms": now,
		}
		bus().combo_streak_updated.emit(resource, 0, 1.0)
		return 1.0

	# --- Extend, if the bucket can pay ------------------------------------
	# Running dry BREAKS the streak rather than freezing it. A frozen streak would
	# let a player climb to the +40% cap on twenty bait and then farm the cap
	# forever without spending another one, which would leave the Bottomless Bucket
	# with no sink to be bottomless for. Flip this branch to `return current
	# multiplier` if the softer reading is wanted.
	if not BaitBucket.consume_bait(resource, 1):
		_reset(resource, player_id, &"out_of_bait")
		return 1.0

	var streak: int = int(entry.get("streak", 0)) + 1
	entry["streak"] = streak
	entry["last_ms"] = now
	# The anchor deliberately is NOT re-sampled here. Re-anchoring on every catch
	# would let a player walk the whole map at MOVE_TOLERANCE_PX per catch and
	# never trip the movement break.
	_state[player_id] = entry

	var multiplier: float = multiplier_for(streak)
	bus().combo_streak_updated.emit(resource, streak, multiplier)
	return multiplier


## The XP multiplier a [param streak] of consecutive catches earns.
static func multiplier_for(streak: int) -> float:
	if streak <= 0:
		return 1.0
	return minf(1.0 + (float(streak) * STEP), MAX_MULTIPLIER)


## Why [param entry] should break for this catch, or &"" to keep it going.
static func _break_reason(
	entry: Dictionary, node_key: String, position: Vector2, now: int
) -> StringName:
	if str(entry.get("node", "")) != node_key:
		return &"node_changed"
	if now - int(entry.get("last_ms", 0)) > LAPSE_MS:
		return &"lapsed"
	var anchor: Vector2 = entry.get("anchor", position) as Vector2
	if anchor.distance_to(position) > MOVE_TOLERANCE_PX:
		return &"moved"
	return &""


# ---------------------------------------------------------------------------
# Resets
# ---------------------------------------------------------------------------

## Break the streak for [param player_id]. Safe to call when there is none — it
## stays quiet rather than emitting a reset for a combo that never existed, so the
## HUD does not flash on every unbaited catch.
static func reset(
	resource: PlayerResource, player_id: int, reason: StringName = &"manual"
) -> void:
	if _state.has(player_id):
		_reset(resource, player_id, reason)


## Drop a player's tracking entirely. Call on disconnect and on instance change —
## a streak must not survive either.
static func clear(player_id: int) -> void:
	_state.erase(player_id)


## Current streak for [param player_id], 0 when none. For the HUD tracker.
static func streak_of(player_id: int) -> int:
	return int((_state.get(player_id, {}) as Dictionary).get("streak", 0))


static func _reset(resource: PlayerResource, player_id: int, reason: StringName) -> void:
	_state.erase(player_id)
	bus().combo_reset.emit(resource, reason)


## Drop entries that have already lapsed. Runs only when a new streak starts, so
## the cost lands on a rare path rather than on every catch.
static func _prune(now: int) -> void:
	if _state.size() < MAX_TRACKED:
		return
	for player_id: int in _state.keys():
		if now - int((_state[player_id] as Dictionary).get("last_ms", 0)) > LAPSE_MS:
			_state.erase(player_id)


## What the combo HUD renders.
static func status_payload(player_id: int) -> Dictionary:
	var streak: int = streak_of(player_id)
	return {
		"streak": streak,
		"multiplier": multiplier_for(streak),
		"max_multiplier": MAX_MULTIPLIER,
	}
