class_name PeddlerStock
## The daily roll: which three goods the Traveling Peddler is carrying today.
##
## RULE. Exactly one S-tier, one A-tier and one B-tier, every day, the same three
## for every player in the world. There is no per-player randomness anywhere in
## here — "what did you get?" is not a question this feature asks, and a stock
## list that differed between two people standing at the same cart would read as
## a bug however it were explained.
##
## The roll is a pure function of the UTC date string ("2026-08-30"), so it needs
## no stored state, survives a restart mid-window, and gives the same answer on
## the world server, on a verification tool, and on a wiki script. The date
## string is hashed rather than used as a number so that consecutive days do not
## walk the pools in lockstep (2026-08-30 and 2026-08-31 would otherwise pick
## adjacent entries in all three tiers at once).
##
## The SERVER is still the authority. This is shared code so tools can predict
## tomorrow's stock, but a purchase is only ever validated against the server's
## own call to [method for_date].

## Salt mixed into each tier's hash. Without it, three tiers hashed from the same
## date string would use the same value and the three picks would correlate — the
## S row and the A row moving together every day is a visible pattern.
const TIER_SALT: Dictionary[String, String] = {
	PeddlerItemData.TIER_S: "s-tier",
	PeddlerItemData.TIER_A: "a-tier",
	PeddlerItemData.TIER_B: "b-tier",
}


## The three goods for [param date] ("YYYY-MM-DD"), in S, A, B order.
## Shorter than three entries only if a tier's pool is empty, which is an
## authoring error the caller surfaces rather than papering over.
static func for_date(date: String) -> Array:
	var out: Array = []
	for tier: String in PeddlerItemData.TIERS:
		var row: PeddlerItemData = _pick(tier, date)
		if row != null:
			out.append(row)
	return out


## Today's stock (UTC).
static func today() -> Array:
	return for_date(PeddlerSchedule.utc_date())


## True when [param id] is one of the three goods on sale on [param date]. The
## purchase handler's gate — a stock id that is real but not TODAY'S is exactly
## what a replayed request from yesterday looks like.
static func is_stocked(id: String, date: String) -> bool:
	for row: PeddlerItemData in for_date(date):
		if row.id == id:
			return true
	return false


## Deterministic pick of one row from [param tier]'s pool for [param date].
static func _pick(tier: String, date: String) -> PeddlerItemData:
	var pool: Array = PeddlerCatalog.tier_pool(tier)
	if pool.is_empty():
		return null
	return pool[_hash(date, tier) % pool.size()]


## Non-negative hash of a date + tier pair.
##
## String.hash() is FNV-1a on the engine side — stable across platforms and
## across runs, which is the whole requirement. It is signed, so the sign bit is
## masked off rather than abs()'d: abs(-2147483648) is itself in 64-bit int math
## and would hand back a negative index once every four billion days.
static func _hash(date: String, tier: String) -> int:
	var salt: String = TIER_SALT.get(tier, tier)
	return int((date + "|" + salt).hash()) & 0x7FFFFFFF
