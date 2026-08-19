class_name PrayerService
## Prayer points and the prayers they pay for. Server-side only.
##
## Two pieces of state, both RUNTIME-only on the [PlayerResource] (like
## [member PlayerResource.active_buffs]):
##   • prayer_points — how much is left in the pool
##   • active_prayers — which prayers are switched on
##
## Neither is persisted, and that is deliberate on both counts. Nothing about
## Prayer changes the database: the SKILL itself rides the existing
## `skills_json` blob (a new key in a dict the loader copies verbatim), and the
## pool is recomposed rather than stored. See docs/prayer_skill.md.
##
## The pool size is PRAYER_MAX = your Prayer level (the OSRS rule), which IS a
## composed stat and so is rebuilt on every spawn. The CURRENT value must not
## be, or walking into any building would refill it for free — that is what
## [method reapply] is for.

## Sentinel for "this session has not initialised the pool yet", so a fresh
## login starts full while an instance change carries the pool across.
## A real value is never negative.
const UNINITIALISED: float = -1.0

## How often the drain tick runs, in seconds. Matches the instance status tick
## that calls it; prayers are authored per MINUTE and converted here.
const DRAIN_TICK_S: float = 1.0


## Max points for [param level] — the OSRS rule, one point per Prayer level.
static func max_points_for_level(level: int) -> float:
	return float(maxi(1, level))


## The player's Prayer level, straight off the skills blob.
static func level_of(player: Player) -> int:
	if player == null or player.player_resource == null:
		return 1
	return int(player.player_resource.get_skill(&"prayer").get("level", 1))


static func points(player: Player) -> float:
	if player == null or player.player_resource == null:
		return 0.0
	return maxf(0.0, player.player_resource.prayer_points)


static func max_points(player: Player) -> float:
	if player == null or player.stats_component == null:
		return 0.0
	return player.stats_component.get_stat(Stat.PRAYER_MAX)


static func active_slugs(player: Player) -> Array[StringName]:
	if player == null or player.player_resource == null:
		return []
	return player.player_resource.active_prayers


static func is_active(player: Player, slug: StringName) -> bool:
	return active_slugs(player).has(slug)


## Total points-per-minute currently being burned, after the Conservation perk.
static func drain_per_minute(player: Player) -> float:
	var total: float = 0.0
	for slug: StringName in active_slugs(player):
		var prayer: PrayerResource = PrayerBook.by_slug(slug)
		if prayer != null:
			total += prayer.drain_per_minute
	if total <= 0.0:
		return 0.0
	var perks: JobPerks = JobRegistry.perks_for(&"prayer")
	if perks != null and player.player_resource != null:
		var player_perks: Dictionary = player.player_resource.get_skill(&"prayer").get("perks", {})
		total *= 1.0 - perks.prayer_drain_reduction(player_perks)
	return maxf(0.0, total)


## Switch [param slug] on. Returns a result dict the handler can pass straight
## back to the client: {"ok", "reason", ...}.
##
## Refuses at 0 points rather than switching on and instantly draining off,
## which reads as a broken button.
static func activate(player: Player, slug: StringName) -> Dictionary:
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	var prayer: PrayerResource = PrayerBook.by_slug(slug)
	if prayer == null:
		return {"ok": false, "reason": "unknown_prayer"}
	var level: int = level_of(player)
	if level < prayer.required_level:
		return {
			"ok": false,
			"reason": "prayer_level",
			"required_level": prayer.required_level,
		}
	if is_active(player, slug):
		return {"ok": true, "already": true}
	if points(player) <= 0.0:
		return {"ok": false, "reason": "no_points"}

	# Switch off anything this prayer competes with FIRST, so the stat ledger
	# never briefly holds both rungs of a ladder.
	var turned_off: Array[String] = []
	for other_slug: StringName in active_slugs(player).duplicate():
		var other: PrayerResource = PrayerBook.by_slug(other_slug)
		if other != null and prayer.conflicts_with(other):
			_deactivate_one(player, other_slug)
			turned_off.append(String(other_slug))

	player.player_resource.active_prayers.append(slug)
	_apply_modifiers(player, prayer)
	return {"ok": true, "turned_off": turned_off}


## Switch [param slug] off. Safe to call when it is not on.
static func deactivate(player: Player, slug: StringName) -> Dictionary:
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	_deactivate_one(player, slug)
	return {"ok": true}


## Switch everything off — death, and running dry.
static func deactivate_all(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	for slug: StringName in player.player_resource.active_prayers.duplicate():
		_deactivate_one(player, slug)


## Add [param amount] points, capped at the pool. Returns how much actually went
## in, so a potion can refuse to be drunk when it would do nothing.
static func restore(player: Player, amount: float) -> float:
	if player == null or player.player_resource == null or amount <= 0.0:
		return 0.0
	var cap: float = max_points(player)
	var before: float = points(player)
	if before >= cap:
		return 0.0
	var after: float = minf(cap, before + amount)
	player.player_resource.prayer_points = after
	_push_stat(player)
	return after - before


## Fill the pool. The altar's recharge.
static func restore_full(player: Player) -> float:
	return restore(player, max_points(player))


## Burn one tick's worth of points and switch everything off if the pool empties.
## Called once a second from the instance status tick, beside BuffService.tick.
static func tick(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	if player.player_resource.active_prayers.is_empty():
		return
	var per_minute: float = drain_per_minute(player)
	if per_minute <= 0.0:
		return
	var spent: float = per_minute * (DRAIN_TICK_S / 60.0)
	var left: float = points(player) - spent
	if left <= 0.0:
		player.player_resource.prayer_points = 0.0
		deactivate_all(player)
		_push_stat(player)
		return
	player.player_resource.prayer_points = left
	_push_stat(player)


## Re-seat the pool and re-apply active prayers on top of a FRESHLY REBUILT stat
## block (spawn rebuilds stats from base + attributes + gear, wiping both).
## Mirrors [method BuffService.reapply], and must be called from the same place.
##
## A pool that has never been initialised this session fills; one carried across
## an instance change keeps its value, clamped to the (possibly new) cap.
static func reapply(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	var resource: PlayerResource = player.player_resource
	var cap: float = max_points_for_level(level_of(player))
	player.stats_component.set_stat(Stat.PRAYER_MAX, cap)
	if resource.prayer_points < 0.0:
		resource.prayer_points = cap
	else:
		resource.prayer_points = minf(resource.prayer_points, cap)
	# Drop anything that is no longer legal (a level was reset, a prayer was
	# retired) before re-applying, so the ledger cannot resurrect a dead entry.
	for slug: StringName in resource.active_prayers.duplicate():
		var prayer: PrayerResource = PrayerBook.by_slug(slug)
		if prayer == null or prayer.required_level > level_of(player):
			resource.active_prayers.erase(slug)
	resource.applied_prayer_modifiers.clear()
	for slug: StringName in resource.active_prayers:
		_apply_modifiers(player, PrayerBook.by_slug(slug))
	_push_stat(player)


## Raise the pool cap after a Prayer level-up, without touching what is in it.
static func refresh_max(player: Player) -> void:
	if player == null or player.stats_component == null:
		return
	player.stats_component.set_stat(Stat.PRAYER_MAX, max_points_for_level(level_of(player)))


## The snapshot the client needs to draw the prayer book and the points orb.
static func status(player: Player) -> Dictionary:
	var slugs: Array[String] = []
	for slug: StringName in active_slugs(player):
		slugs.append(String(slug))
	return {
		"points": points(player),
		"max": max_points(player),
		"level": level_of(player),
		"active": slugs,
		"drain": drain_per_minute(player),
	}


# --- internals ---------------------------------------------------------------

## Removes a prayer and reverts exactly the modifier values that were applied
## for it, rather than re-reading the resource — so an edited .tres between
## apply and revert can never leave an orphaned stat bonus behind. Same reason
## the crafting gear ledger exists.
static func _deactivate_one(player: Player, slug: StringName) -> void:
	var resource: PlayerResource = player.player_resource
	if not resource.active_prayers.has(slug):
		return
	resource.active_prayers.erase(slug)
	var ledger: Array[Dictionary] = resource.applied_prayer_modifiers
	for i: int in range(ledger.size() - 1, -1, -1):
		if StringName(str(ledger[i]["prayer"])) != slug:
			continue
		player.stats_component.modify_stat(
			StringName(str(ledger[i]["stat"])), -float(ledger[i]["value"])
		)
		ledger.remove_at(i)


static func _apply_modifiers(player: Player, prayer: PrayerResource) -> void:
	if prayer == null:
		return
	for modifier: StatModifier in prayer.modifiers:
		if modifier == null or is_zero_approx(modifier.value):
			continue
		var stat: StringName = StringName(modifier.stat_name)
		player.stats_component.modify_stat(stat, modifier.value)
		player.player_resource.applied_prayer_modifiers.append({
			"prayer": String(prayer.slug),
			"stat": String(stat),
			"value": modifier.value,
		})


## Mirror the pool onto the synced stat so the client orb tracks it without a
## bespoke push. PRAYER is a normal stat, so it rides the existing sync.
static func _push_stat(player: Player) -> void:
	if player == null or player.stats_component == null:
		return
	player.stats_component.set_stat(Stat.PRAYER, points(player))
