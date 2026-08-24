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
static func apply(player: Player, stat: StringName, amount: float, duration_s: float) -> void:
	if player == null or player.player_resource == null or amount == 0.0 or duration_s <= 0.0:
		return
	var expires_ms: int = Time.get_ticks_msec() + int(duration_s * 1000.0)
	for buff: Dictionary in player.player_resource.active_buffs:
		if buff["stat"] == stat and is_equal_approx(float(buff["amount"]), amount):
			buff["expires_ms"] = maxi(int(buff["expires_ms"]), expires_ms)
			return
	player.player_resource.active_buffs.append(
		{"stat": stat, "amount": amount, "expires_ms": expires_ms}
	)
	player.stats_component.modify_stat(stat, amount)


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
			player.stats_component.modify_stat(stat, -float(buffs[i]["amount"]))
			buffs.remove_at(i)


## Removes expired buffs (reverting their stat bonus). Called by the instance
## StatusTick once per second per player.
static func tick(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	var buffs: Array = player.player_resource.active_buffs
	var now: int = Time.get_ticks_msec()
	for i: int in range(buffs.size() - 1, -1, -1):
		if now >= int(buffs[i]["expires_ms"]):
			player.stats_component.modify_stat(StringName(buffs[i]["stat"]), -float(buffs[i]["amount"]))
			buffs.remove_at(i)


## Puts live buffs back on top of a FRESHLY REBUILT stat block (spawn after an
## instance change rebuilds stats from base + attributes + gear, wiping buff
## bonuses). Drops anything that expired in transit; does NOT revert first —
## the rebuild already started from clean numbers.
static func reapply(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	var buffs: Array = player.player_resource.active_buffs
	var now: int = Time.get_ticks_msec()
	for i: int in range(buffs.size() - 1, -1, -1):
		if now >= int(buffs[i]["expires_ms"]):
			buffs.remove_at(i)
		else:
			player.stats_component.modify_stat(StringName(buffs[i]["stat"]), float(buffs[i]["amount"]))
