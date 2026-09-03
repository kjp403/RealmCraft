class_name StatusService
## Pushes a player their own status snapshot (timed buffs, damage-over-time
## debuffs, in-combat flag) for the HUD status strip. Server-side only, called
## once per second from the instance StatusTick — 1 Hz is plenty for icons
## that only ever show whole-second countdowns.
##
## Durations cross the wire as REMAINING SECONDS, never absolute timestamps:
## client and server run separate clocks (Time.get_ticks_msec is per-process),
## so an expires_ms would be meaningless on the other side.


static func sync(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	var peer_id: int = int(player.player_resource.current_peer_id)
	if peer_id <= 0 or WorldServer.curr == null:
		return

	var now: int = Time.get_ticks_msec()

	var buffs: Array = []
	var debuffs: Array = []
	# A timed stat buff with a NEGATIVE amount is a debuff (Crippling Strike's
	# move_speed slow) — route it to the debuff strip with a friendly id so the
	# HUD shows it red/down, not green/up.
	# ONE ENTRY PER ID. Two live buffs on the same stat with different amounts —
	# a Rally +22 AD landing on top of a Berserk +40 AD, say — are two rows in
	# active_buffs but ONE icon: the strip has no way to draw them apart, and
	# sending both made the HUD build two tiles under one key and lose track of
	# the first, which is how a fight ended with a row of buff icons that no
	# longer expired and survived death. Merged here, at the source, so the wire
	# format itself cannot express the ambiguity. The longest remaining wins —
	# the icon is gone when the LAST of them is.
	var seen: Dictionary = {}
	for buff: Dictionary in player.player_resource.active_buffs:
		var stat: String = String(buff["stat"])
		var remaining: int = int(ceil((int(buff["expires_ms"]) - now) / 1000.0))
		var negative: bool = float(buff["amount"]) < 0.0
		var id: String = stat
		if negative:
			id = "slow" if stat == String(Stat.MOVE_SPEED) else stat
		var bucket: Array = debuffs if negative else buffs
		var key: String = ("d:" if negative else "b:") + id
		if seen.has(key):
			var row: Dictionary = seen[key]
			row["remaining"] = maxi(int(row["remaining"]), remaining)
			continue
		var entry: Dictionary = {"id": id, "remaining": remaining}
		seen[key] = entry
		bucket.append(entry)

	# A weapon coating is a buff on YOU (your hits do something extra), not a
	# debuff — it rides the buff strip even when its kind names a harmful effect.
	# The id is prefixed so "coating_poison" on your strip cannot be confused
	# with "poison" on a victim's.
	var coating_left: int = CoatingService.remaining_seconds(player)
	if coating_left > 0:
		buffs.append({
			"id": CoatingService.status_id(CoatingService.active_kind(player)),
			"remaining": coating_left,
		})

	# The Anvil Stabilizer. A bought, timed buff with no other tell — peddler
	# state is server-only, so this strip is the one place a smith can see the
	# ten minutes they paid for running down.
	var anvil_left: int = AnvilBoost.remaining_s(player.player_resource)
	if anvil_left > 0:
		buffs.append({"id": String(AnvilBoost.STATUS_ID), "remaining": anvil_left})

	for child: Node in player.get_children():
		if child is DamageOverTime:
			# A source-keyed DoT (StatusEffectManager.apply_source_dot) carries its
			# applier's instance id after a "#" so two players' venoms can coexist
			# on one victim. The STRIP must not: the player being poisoned does not
			# care who by, and an id of "venom#137" would miss its icon and its
			# tooltip and show a raw instance number under a generic arrow.
			var kind: String = String((child as DamageOverTime).kind)
			var hash_at: int = kind.find("#")
			if hash_at > 0:
				kind = kind.substr(0, hash_at)
			# ONE ENTRY PER ID, same rule and same reason as the buff merge above.
			# Stripping the source key means two players' venoms both arrive here as
			# "venom"; sending both would put two tiles under one HUD key. The
			# longest remaining wins — the icon is gone when the LAST of them is.
			var dot_left: int = (child as DamageOverTime).remaining_seconds()
			var dot_key: String = "d:" + kind
			if seen.has(dot_key):
				var row: Dictionary = seen[dot_key]
				row["remaining"] = maxi(int(row["remaining"]), dot_left)
				continue
			var dot_entry: Dictionary = {"id": kind, "remaining": dot_left}
			seen[dot_key] = dot_entry
			debuffs.append(dot_entry)

	# Effects owned by StatusEffectManager — the drinker's auras (Cinder-Guard,
	# Shadowveil, Provocation) on the buff strip, and any stacking debuff riding
	# the player on the other. The manager is absent on a player who has never
	# carried one of these, which is most of them, so this costs a node lookup.
	var manager: StatusEffectManager = StatusEffectManager.find(player)
	if manager != null:
		buffs.append_array(manager.status_rows(false))
		debuffs.append_array(manager.status_rows(true))

	WorldServer.curr.data_push.rpc_id(peer_id, &"status.sync", {
		"buffs": buffs,
		"debuffs": debuffs,
		"in_combat": player.is_in_combat(),
	})
