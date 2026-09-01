class_name QuickTravelService
## Server-only. The Wayfarer's "frequent flyer" surge: a rolling-window toll that
## makes rapid instance-hopping progressively expensive without ever blocking it.
##
## RULE. The first [constant SURGE_AFTER_TRIPS] rides inside a
## [constant WINDOW_S] window are base fare. Every ride past that adds
## [constant SURGE_STEP] (+50%) to the multiplier:
##
##     ride #1-3 -> 1.0x    #4 -> 1.5x    #5 -> 2.0x    #6 -> 2.5x  ...
##
## No fare may ever exceed [constant FARE_CAP], the quick-travel price ceiling.
## The surge raises a fare toward that ceiling and stops there, so the top tier
## (Fire Forge, already at the cap) is priced the same however often it is used
## and the surge bites hardest on the cheap hops it is aimed at.
##
## "Reset after 10 minutes of inactivity" falls out of the rolling window for
## free: timestamps older than WINDOW_S are pruned before every read, so ten
## quiet minutes empty the list and the next ride is base fare again.
##
## STATE IS IN-MEMORY and keyed by player_id. It deliberately does NOT touch
## PlayerResource: adding a persisted column means a schema + save_player
## placeholder change, which is a silent-failure trap for a purely anti-abuse
## timer. The cost is that a relog clears the surge; the sink still does its job
## against the behaviour it targets (hopping in one sitting), and the state is
## dropped on logout anyway via [method forget].

## Length of the rolling window, in seconds.
const WINDOW_S: float = 600.0
## Rides inside the window that stay at base fare. The (n+1)-th is the first
## surged one.
const SURGE_AFTER_TRIPS: int = 3
## Added to the multiplier per ride past [constant SURGE_AFTER_TRIPS].
const SURGE_STEP: float = 0.5
## Hard ceiling on any quick-travel fare, surge included. This is the price cap
## the destination tiers are authored against (Fire Forge sits exactly on it), so
## it caps the charge rather than the multiplier: a surged fare climbs until it
## reaches this and then stays.
const FARE_CAP: int = 50000

## player_id -> Array[float] of monotonic seconds, one per completed ride.
## Monotonic (Time.get_ticks_msec), so a wall-clock/NTP jump can't hand out free
## rides or freeze someone at max surge.
static var _rides: Dictionary = {}


static func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## Rides still inside the window, pruning anything that has aged out.
static func _recent(player_id: int) -> Array:
	var stamps: Array = _rides.get(player_id, [])
	var cutoff: float = _now() - WINDOW_S
	var kept: Array = []
	for t: float in stamps:
		if t > cutoff:
			kept.append(t)
	if kept.is_empty():
		_rides.erase(player_id)
	else:
		_rides[player_id] = kept
	return kept


## How many rides this player has taken inside the current window.
static func rides_in_window(player_id: int) -> int:
	return _recent(player_id).size()


## Fare multiplier the player's NEXT ride is charged at. Uncapped -- the cap
## lives on the fare itself, in [method fee_for], not on this number.
static func multiplier(player_id: int) -> float:
	var prior: int = rides_in_window(player_id)
	# Buying ride #k means `prior` == k - 1, and we want ride #4 (prior == 3) to
	# be the first surged one at 1.5x -- hence the -1 on the threshold.
	var steps: int = maxi(0, prior - (SURGE_AFTER_TRIPS - 1))
	return 1.0 + SURGE_STEP * float(steps)


## What [param base_fee] actually costs this player right now: the surge applied,
## then clamped to [constant FARE_CAP].
static func fee_for(player_id: int, base_fee: int) -> int:
	return mini(uncapped_fee_for(player_id, base_fee), FARE_CAP)


## The surged fare BEFORE the cap. Only for telling a player their fare is at the
## ceiling — never charge this.
static func uncapped_fee_for(player_id: int, base_fee: int) -> int:
	return int(ceil(float(maxi(base_fee, 0)) * multiplier(player_id)))


## Seconds until the surge drops a step (the oldest ride ages out), or 0 when
## the player is not currently surged. Drives the "cools down in N:NN" hint.
static func seconds_until_step_down(player_id: int) -> int:
	var stamps: Array = _recent(player_id)
	if stamps.size() < SURGE_AFTER_TRIPS:
		return 0
	var oldest: float = stamps[0]
	for t: float in stamps:
		oldest = minf(oldest, t)
	return maxi(0, int(ceil(oldest + WINDOW_S - _now())))


## Record a COMPLETED ride. Call only after the fare is paid and the transfer is
## committed, so a refused or failed teleport never pushes the player up a tier.
static func record_ride(player_id: int) -> void:
	var stamps: Array = _recent(player_id)
	stamps.append(_now())
	_rides[player_id] = stamps


## Drop a player's history (logout). Purely hygiene — the window would expire it
## anyway; this keeps the table from growing with every account seen this uptime.
static func forget(player_id: int) -> void:
	_rides.erase(player_id)
