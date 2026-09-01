class_name PeddlerSchedule
## The Traveling Peddler's clock: WHEN it is standing somewhere, and which UTC
## day the stock is rolled for.
##
## Everything here is derived from the wall-clock UTC second, never from server
## uptime. A world that restarts at 03:58 must not restart the 00:00 window at
## 03:58 — players coordinate on "the four-o'clock peddler", and a schedule
## anchored to process start makes that promise unkeepable. The cost is that
## this is the ONE place in the peddler that trusts the system clock; a machine
## with a wrong clock shows the wrong window, which is a visible, fixable
## operator problem rather than a silent drift.

## Seconds between spawns. 4 hours -> windows open at 00:00, 04:00, 08:00,
## 12:00, 16:00 and 20:00 UTC.
const CYCLE_S: int = 4 * 60 * 60
## How long the Peddler (and its Vault Chest) stay standing, in seconds.
const ACTIVE_S: int = 30 * 60
const DAY_S: int = 24 * 60 * 60


## Current UTC unix second. Wrapped so tests and the verify tool can reason about
## one call site rather than scattering Time lookups through the manager.
static func now_s() -> int:
	return int(Time.get_unix_time_from_system())


## Index of the cycle [param at_s] falls in, counted from the unix epoch. This
## is the stable id every server, and every player's client, agrees on for one
## particular appearance.
@warning_ignore("integer_division")
static func cycle_index(at_s: int = -1) -> int:
	var t: int = at_s if at_s >= 0 else now_s()
	return t / CYCLE_S


## Unix second cycle [param index] opens at.
static func cycle_start_s(index: int) -> int:
	return index * CYCLE_S


## Unix second cycle [param index] closes at (start + [constant ACTIVE_S]).
static func cycle_end_s(index: int) -> int:
	return cycle_start_s(index) + ACTIVE_S


## True when [param at_s] falls inside the ACTIVE half-hour of its own cycle.
## Between windows this is false and there is no Peddler anywhere.
static func is_active(at_s: int = -1) -> bool:
	var t: int = at_s if at_s >= 0 else now_s()
	return t - cycle_start_s(cycle_index(t)) < ACTIVE_S


## Seconds until the current window closes, or 0 when nothing is open.
static func seconds_remaining(at_s: int = -1) -> int:
	var t: int = at_s if at_s >= 0 else now_s()
	if not is_active(t):
		return 0
	return maxi(0, cycle_end_s(cycle_index(t)) - t)


## Seconds until the NEXT window opens. 0 while one is already open.
static func seconds_until_next(at_s: int = -1) -> int:
	var t: int = at_s if at_s >= 0 else now_s()
	if is_active(t):
		return 0
	return maxi(0, cycle_start_s(cycle_index(t) + 1) - t)


## The UTC date the stock is rolled for, as "YYYY-MM-DD".
##
## This is the string that gets hashed, so it is also the thing that decides when
## the daily purchase allowance resets. Deliberately the UTC calendar date and
## not "cycle_index / 6": a leap second or a schedule retune must not be able to
## slide the stock day off the date players read off a clock.
static func utc_date(at_s: int = -1) -> String:
	var t: int = at_s if at_s >= 0 else now_s()
	var parts: Dictionary = Time.get_datetime_dict_from_unix_time(t)
	return "%04d-%02d-%02d" % [
		int(parts.get("year", 1970)),
		int(parts.get("month", 1)),
		int(parts.get("day", 1)),
	]


## Unix second the NEXT window opens at. While one is open this is the START of
## the following cycle, not "now" — a web tracker counting down to the next
## appearance must not show 0 for the whole half hour a cart is standing.
static func next_spawn_s(at_s: int = -1) -> int:
	var t: int = at_s if at_s >= 0 else now_s()
	return cycle_start_s(cycle_index(t) + 1)


## Human-readable "in 12:34" style clock for a seconds count.
static func clock(seconds: int) -> String:
	var s: int = maxi(0, seconds)
	@warning_ignore("integer_division")
	var minutes: int = s / 60
	if minutes >= 60:
		@warning_ignore("integer_division")
		var hours: int = minutes / 60
		return "%dh %02dm" % [hours, minutes % 60]
	return "%d:%02d" % [minutes, s % 60]
