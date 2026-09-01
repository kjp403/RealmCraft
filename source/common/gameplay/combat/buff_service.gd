class_name BuffService
## Timed stat buffs — the minimal seed: a buff is {stat, amount, expires_ms}
## stored on the PlayerResource (runtime-only, so it survives instance changes
## within a session and dies naturally on logout). Applied via modify_stat,
## expired by the instance StatusTick. Potions use it today; campfires,
## fountains, auras and food are the same mechanism later.
##
## Server-side only — all entry points are server handlers / server ticks.


## Grants [param stat] +[param amount] for [param duration_s] seconds.
## Re-applying the SAME stat+amount refreshes the duration instead of stacking
## (drinking a second tonic extends it, never doubles it).
##
## [param exclusive] marks the buff as holding the one COMBAT DRAUGHT slot — the
## same slot a weapon coating takes (see [method exclusive_active]). Everything
## else — gear procs, ability buffs, the campfire — leaves it false and is
## unaffected.
## [param suppress_in_combat] makes the bonus lapse while the holder is fighting
## and come back when they disengage, WITHOUT the timer stopping. That is the
## Hearth Stew's "travel buff": it is worth something on the road and nothing in
## a fight, which is a different thing from a buff that simply ends.
##
## A suppressed buff keeps its seat in the list (so re-drinking still refreshes
## rather than stacking) and carries an "applied" flag saying whether its bonus
## is currently ON the stat block. Every path that reverts a bonus must consult
## that flag — reverting a bonus that was never applied silently drains the stat.
static func apply(
	player: Player,
	stat: StringName,
	amount: float,
	duration_s: float,
	exclusive: bool = false,
	suppress_in_combat: bool = false
) -> void:
	if player == null or player.player_resource == null or amount == 0.0 or duration_s <= 0.0:
		return
	var expires_ms: int = Time.get_ticks_msec() + int(duration_s * 1000.0)
	for buff: Dictionary in player.player_resource.active_buffs:
		if buff["stat"] == stat and is_equal_approx(float(buff["amount"]), amount):
			buff["expires_ms"] = maxi(int(buff["expires_ms"]), expires_ms)
			return
	# A suppressed-on-arrival buff must not be added to the stat block, or the
	# first tick would revert a bonus that was never granted.
	var active_now: bool = not (suppress_in_combat and player.is_in_combat())
	player.player_resource.active_buffs.append({
		"stat": stat,
		"amount": amount,
		"expires_ms": expires_ms,
		"exclusive": exclusive,
		"suppress_in_combat": suppress_in_combat,
		"applied": active_now,
	})
	if active_now:
		player.stats_component.modify_stat(stat, amount)


## True while a buff that holds the one COMBAT DRAUGHT slot is still running.
## That slot is shared with [CoatingService]: a Defense Tonic and a Weapon Ember
## are both "the draught you went in with", and letting them stack would turn a
## real choice into a checklist. Buffs banked before this key existed read as
## non-exclusive, which is correct — nothing granted one back then.
static func exclusive_active(player: Player) -> bool:
	return exclusive_remaining_seconds(player) > 0


## Whole seconds left on the exclusive draught buff, for the status countdown
## and for naming the refusal when a second draught is poured. 0 when the slot
## is free.
static func exclusive_remaining_seconds(player: Player) -> int:
	if player == null or player.player_resource == null:
		return 0
	var now: int = Time.get_ticks_msec()
	var left: int = 0
	for buff: Dictionary in player.player_resource.active_buffs:
		if not bool(buff.get("exclusive", false)):
			continue
		left = maxi(left, ceili((int(buff["expires_ms"]) - now) / 1000.0))
	return maxi(0, left)


## The stat the running exclusive draught raises, or &"" when the slot is free.
static func exclusive_stat(player: Player) -> StringName:
	if player == null or player.player_resource == null:
		return &""
	var now: int = Time.get_ticks_msec()
	for buff: Dictionary in player.player_resource.active_buffs:
		if bool(buff.get("exclusive", false)) and now < int(buff["expires_ms"]):
			return StringName(buff["stat"])
	return &""


## Strips every active buff on [param stat] immediately (reverting its bonus),
## regardless of remaining duration. For buffs that are supposed to belong to
## the weapon that granted them — e.g. sword Berserk's lifesteal — so a swap
## to another weapon mid-buff can't carry it over (Berserk lifesteal has no
## business healing off a Book's Lightning Lash). Server-only, like the rest
## of this service.
static func clear_stat(player: Player, stat: StringName) -> void:
	if player == null or player.player_resource == null:
		return
	var buffs: Array = player.player_resource.active_buffs
	for i: int in range(buffs.size() - 1, -1, -1):
		if StringName(buffs[i]["stat"]) == stat:
			# Only unwind a bonus that is actually on the block — a combat-
			# suppressed buff is sitting at zero and reverting it would subtract
			# an amount nothing ever added.
			if bool(buffs[i].get("applied", true)):
				player.stats_component.modify_stat(stat, -float(buffs[i]["amount"]))
			buffs.remove_at(i)


## Strips EVERY active buff immediately, reverting each one's stat bonus. Death
## calls this, next to [method PrayerService.deactivate_all] and for the same
## reason: what you went into the fight with does not follow you out of it, and a
## buff that survives a corpse is a buff the player cannot see the end of — the
## status strip kept showing icons for effects the respawn had already unwound.
##
## Reverts BEFORE clearing so the stat ledger unwinds against the live stat
## block, exactly like [method clear_stat].
static func clear_all(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	var buffs: Array = player.player_resource.active_buffs
	for i: int in range(buffs.size() - 1, -1, -1):
		if bool(buffs[i].get("applied", true)):
			player.stats_component.modify_stat(
				StringName(buffs[i]["stat"]), -float(buffs[i]["amount"])
			)
	buffs.clear()


## Removes expired buffs (reverting their stat bonus). Called by the instance
## StatusTick once per second per player.
static func tick(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	var buffs: Array = player.player_resource.active_buffs
	var now: int = Time.get_ticks_msec()
	var fighting: bool = player.is_in_combat()
	for i: int in range(buffs.size() - 1, -1, -1):
		var buff: Dictionary = buffs[i]
		var applied: bool = bool(buff.get("applied", true))
		if now >= int(buff["expires_ms"]):
			if applied:
				player.stats_component.modify_stat(
					StringName(buff["stat"]), -float(buff["amount"])
				)
			buffs.remove_at(i)
			continue
		if not bool(buff.get("suppress_in_combat", false)):
			continue
		# Still running, but its bonus should lapse for the duration of a fight
		# and come back after. The timer is untouched either way.
		if fighting and applied:
			player.stats_component.modify_stat(StringName(buff["stat"]), -float(buff["amount"]))
			buff["applied"] = false
		elif not fighting and not applied:
			player.stats_component.modify_stat(StringName(buff["stat"]), float(buff["amount"]))
			buff["applied"] = true


## Puts live buffs back on top of a FRESHLY REBUILT stat block (spawn after an
## instance change rebuilds stats from base + attributes + gear, wiping buff
## bonuses). Drops anything that expired in transit; does NOT revert first —
## the rebuild already started from clean numbers.
static func reapply(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	var buffs: Array = player.player_resource.active_buffs
	var now: int = Time.get_ticks_msec()
	var fighting: bool = player.is_in_combat()
	for i: int in range(buffs.size() - 1, -1, -1):
		var buff: Dictionary = buffs[i]
		if now >= int(buff["expires_ms"]):
			buffs.remove_at(i)
			continue
		# The rebuild wiped every bonus, so "applied" has to be re-derived rather
		# than trusted: a buff suppressed before the instance change must come
		# back suppressed, and one that was live must come back live.
		var active_now: bool = not (
			bool(buff.get("suppress_in_combat", false)) and fighting
		)
		buff["applied"] = active_now
		if active_now:
			player.stats_component.modify_stat(StringName(buff["stat"]), float(buff["amount"]))
