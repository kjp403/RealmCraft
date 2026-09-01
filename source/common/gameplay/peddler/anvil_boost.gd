class_name AnvilBoost
## Server-only. The smelting RUN CAP the Anvil Stabilizer lifts.
##
## RULE. A continuous smelting run is capped at [constant BASE_MAX_BARS] bars.
## While the smith holds an Anvil Stabilizer charge the cap is
## [constant BOOSTED_MAX_BARS], and each bar smelted burns one charge — so one
## stabilizer (50 charges) buys exactly one full-length run.
##
## WHAT COUNTS AS A RUN. Consecutive smelts with no more than
## [constant RUN_IDLE_RESET_MS] between them. Walk away from the furnace for a
## few seconds and the run ends; come back and the cap is fresh. This is the
## definition the cap needs to be enforceable server-side: the server sees one
## craft request at a time, never a "batch", so a batch size handed up by the
## client would be a number the client controls, which is not a cap at all.
##
## The window is what makes an unboosted smith stop and re-start every 10 bars —
## a rhythm interruption, not a wall — while a stabilised one pours 50 straight
## through. That difference IS the good.
##
## STATE IS IN-MEMORY, keyed by player_id: the run is a seconds-scale
## anti-tedium timer, and persisting it
## would mean a schema column and a save_player placeholder for something that
## must not survive a relog anyway. The CHARGES do persist — those are the
## purchased good, and they live on [member PlayerResource.anvil_boost_charges].

## Bars one unboosted run may smelt.
const BASE_MAX_BARS: int = 10
## Bars a stabilised run may smelt.
const BOOSTED_MAX_BARS: int = 50
## Gap that ends a run, in milliseconds.
const RUN_IDLE_RESET_MS: int = 10000

## player_id -> {"count": int, "last_ms": int}. Pruned lazily on read.
static var _runs: Dictionary[int, Dictionary] = {}


## The run cap that applies to [param resource] right now.
static func max_bars(resource: PlayerResource) -> int:
	if resource != null and resource.anvil_boost_charges > 0:
		return BOOSTED_MAX_BARS
	return BASE_MAX_BARS


## Bars already smelted in the player's CURRENT run (0 if the last one aged out).
static func bars_this_run(player_id: int) -> int:
	var run: Dictionary = _runs.get(player_id, {})
	if run.is_empty():
		return 0
	if Time.get_ticks_msec() - int(run.get("last_ms", 0)) > RUN_IDLE_RESET_MS:
		_runs.erase(player_id)
		return 0
	return int(run.get("count", 0))


## Bars left before [param resource]'s current run hits its cap.
static func bars_remaining(resource: PlayerResource) -> int:
	if resource == null:
		return 0
	return maxi(0, max_bars(resource) - bars_this_run(resource.player_id))


## Book ONE smelted bar against [param resource]'s run, spending a stabilizer
## charge if there is one.
##
## Returns {"ok": true, "boosted": bool, "charges": int, "remaining": int} when
## the bar is allowed, or {"ok": false, "reason": "bar_limit", ...} when the run
## is spent. Call this only once the craft is otherwise committed — a refused
## craft must not consume a charge or advance the run.
static func consume_bar(resource: PlayerResource) -> Dictionary:
	if resource == null:
		return {"ok": false, "reason": "no_player"}
	var player_id: int = resource.player_id
	var used: int = bars_this_run(player_id)
	var cap: int = max_bars(resource)
	if used >= cap:
		return {
			"ok": false,
			"reason": "bar_limit",
			"cap": cap,
			"boosted": resource.anvil_boost_charges > 0,
			"cooldown_ms": RUN_IDLE_RESET_MS,
		}

	var boosted: bool = resource.anvil_boost_charges > 0
	if boosted:
		resource.anvil_boost_charges = maxi(0, resource.anvil_boost_charges - 1)
	_runs[player_id] = {"count": used + 1, "last_ms": Time.get_ticks_msec()}
	return {
		"ok": true,
		"boosted": boosted,
		"charges": resource.anvil_boost_charges,
		"cap": cap,
		"remaining": maxi(0, cap - (used + 1)),
	}


## Give back a bar booked by [method consume_bar] — the craft it was booked for
## did not happen after all (a full bag, rolled back atomically). Pass the exact
## dict consume_bar returned; anything else is ignored.
##
## Restores the charge as well as the run slot. Losing 1/50th of a 75,000-gold
## good to a bag-full refusal is the kind of small silent theft players do notice
## and cannot prove.
static func refund_bar(resource: PlayerResource, booked: Dictionary) -> void:
	if resource == null or not booked.get("ok", false):
		return
	if bool(booked.get("boosted", false)):
		resource.anvil_boost_charges += 1
	var player_id: int = resource.player_id
	var run: Dictionary = _runs.get(player_id, {})
	if run.is_empty():
		return
	var count: int = maxi(0, int(run.get("count", 0)) - 1)
	if count == 0:
		_runs.erase(player_id)
	else:
		run["count"] = count
		_runs[player_id] = run


## Drop a player's run (logout). Hygiene only — the idle window would expire it.
static func forget(player_id: int) -> void:
	_runs.erase(player_id)
