extends PeddlerAction
## Anvil Stabilizer: stabilise the user's forge for
## [constant AnvilBoost.DURATION_S] seconds.
##
## While it runs, smelting at the furnace and smithing at the anvil both go at
## [constant AnvilBoost.SPEED_MULTIPLIER] speed. Buying a second one extends the
## clock rather than replacing it. See [AnvilBoost].


func apply(player: Player, _instance: ServerInstance) -> Dictionary:
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return {"ok": false, "reason": "no_player"}
	var until_ms: int = AnvilBoost.extend(resource)
	var remaining_s: int = AnvilBoost.remaining_s(resource)
	return {
		"ok": true,
		"until_ms": until_ms,
		"remaining_s": remaining_s,
		"message": "Forge stabilised — smithing at double speed for %s." % (
			PeddlerSchedule.clock(remaining_s)
		),
	}
