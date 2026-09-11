class_name MeteorVeinPool
## The Starfall meteor vein's SHARED yield pool, and the level-weighted gem it
## hands out.
##
## WHY THIS IS SHARED, AND WHY IT LIVES HERE
## Every other gathering node in the game gives each player their own pool
## ([GatherNodeLedger]) precisely so one miner cannot empty a vein for everyone.
## The meteor is the deliberate opposite: one pile everyone draws down together,
## so a crowd clears it faster and arriving late means less left. That is the
## whole point of it as a community fixture.
##
## Shared state is WORLD state, so neither place node state normally lives will
## hold it:
##   * not PlayerResource — that is per-player by definition;
##   * not the node — `InstanceManager.unload_unused_instances` frees any
##     instance with no peers every 20 seconds, so a half-mined vein would
##     refill itself the moment the grove emptied. That is the same relog-for-a-
##     free-respawn hole GatherNodeLedger was built to close.
##
## A STATIC SERVICE, not an autoload and not a database row. Every instance runs
## inside one `WorldMain` process, so a static is shared across all of them and
## outlives any single instance — which is exactly the lifetime this needs. It
## avoids an autoload (which does not resolve under a headless `-s` run, and is
## a `project.godot` edit) and avoids a new column, which is how `save_player()`
## breaks silently. Same reasoning as [SkillingChestRewarder].
##
## The trade is that a SERVER RESTART refills the pool early. Players cannot
## trigger a restart and they happen during downtime, so that is an occasional
## generosity rather than an exploit — cheap next to persisting world state.

## Wall clock, not uptime: the window has to survive a restart landing mid-cycle,
## the same reason [PeddlerSchedule] is wall clock.
const PERIOD_S: int = 3 * 60 * 60

## Yields the whole server shares per window.
##
## Sized off the real mining rate, not a guess. At 18 extraction HP and the
## node's 5s post-yield cooldown a miner pulls ~660 gems an hour before bank
## trips, so 1,000 is about 90 minutes of solo work — comfortably emptiable,
## and a group clears it in minutes. That is the race that makes turning up
## early worth something, and the empty vein is what tells everyone to go do
## something else.
##
## Two corrections got it here. The first pass at 150 was a garnish: 13 minutes
## of mining. The second overshot at 2,000, anchored on "a solo miner can JUST
## empty one window" — the most generous anchor available. 1,000 is the middle,
## and still ~7x the original.
##
## READ THIS BEFORE RETUNING. The ~52,000-gem figure this was originally sized
## against was for the WHOLE line — cut the stone, then set it into jewellery,
## two Crafting actions per gem at a combined ~125 xp. Only the CUT shipped, and
## a cut alone tops out at 70 xp, so the real numbers today are:
##
##   * 60→99 on the meteor's own level-weighted mix (~39.6 xp/gem at 99 Mining)
##     wants ~322,000 gems and ~179 hours of cutting;
##   * all-diamond, which means buying them rather than mining them, is ~182,000
##     gems and ~101 hours.
##
## So the pool is NOT the binding constraint and making it bigger will not fix
## the pace — the missing setting recipes are roughly half the intended xp per
## gem. Size those first, then revisit this number, or the line stays about 2x
## Smithing's 248h.
##
## Bag space throttles it too — 30 slots per bag, gems stack 10, so a one-bag
## miner banks every ~300 gems.
const POOL: int = 1000

## Gem ladder, rarest last. Sapphire is the floor every miner can pull.
const LADDER: Array[StringName] = [
	&"uncut_sapphire", &"uncut_emerald", &"uncut_ruby", &"uncut_diamond",
]
## Weight of each rung at level L: `scale * (L / 99) ^ curve`, sapphire pinned
## at 1.0. Deliberately soft — a low-level miner CAN pull a diamond, just
## rarely. Hard gates would make the meteor feel like a wall, and the whole
## draw of it is that anything can come out.
##
## Note this is gated by the PLAYER, unlike the ore veins, which are gated by
## the vein's own tier. A level 99 miner at a copper vein still only gets
## sapphire; here they get the full spread. That is what gives a maxed miner a
## reason to turn up instead of staying on astralite.
const CURVE: Array[float] = [0.0, 1.2, 1.8, 2.6]
const SCALE: Array[float] = [1.0, 1.10, 1.00, 0.85]

static var _window: int = -1
static var _consumed: int = 0


## Which refill window wall-clock now falls in.
static func window_now() -> int:
	return int(Time.get_unix_time_from_system()) / PERIOD_S


## Roll the window forward if the clock has moved on. Called by every reader so
## the pool refills lazily — nothing has to tick while the grove is empty.
static func _sync() -> void:
	var now: int = window_now()
	if now != _window:
		_window = now
		_consumed = 0


static func remaining() -> int:
	_sync()
	return maxi(0, POOL - _consumed)


static func pool_size() -> int:
	return POOL


## Spend one yield. False when the window is already mined out, which the node
## turns into its normal "depleted" response and depleted sprite.
static func take() -> bool:
	_sync()
	if _consumed >= POOL:
		return false
	_consumed += 1
	return true


static func seconds_until_refill() -> int:
	_sync()
	return maxi(0, (_window + 1) * PERIOD_S - int(Time.get_unix_time_from_system()))


## Relative weights for [param mining_level], parallel to [constant LADDER].
static func weights_for(mining_level: int) -> Array[float]:
	var t: float = clampf(float(mining_level) / 99.0, 0.0, 1.0)
	var out: Array[float] = []
	for i: int in LADDER.size():
		out.append(SCALE[i] if CURVE[i] <= 0.0 else pow(t, CURVE[i]) * SCALE[i])
	return out


## An uncut gem slug for a miner of [param mining_level]. Weighted, never gated.
static func roll_slug(mining_level: int) -> StringName:
	var w: Array[float] = weights_for(mining_level)
	var total: float = 0.0
	for v: float in w:
		total += v
	if total <= 0.0:
		return LADDER[0]
	var roll: float = randf() * total
	for i: int in LADDER.size():
		roll -= w[i]
		if roll <= 0.0:
			return LADDER[i]
	return LADDER[0]


## The gem item itself, resolved through the registry so a renamed slug degrades
## to "no bonus gem" rather than crashing a swing.
static func roll_gem(mining_level: int) -> Item:
	return ContentRegistryHub.load_by_slug(&"items", roll_slug(mining_level)) as Item
