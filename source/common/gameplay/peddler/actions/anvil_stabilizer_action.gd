extends PeddlerAction
## Anvil Stabilizer: bank [constant CHARGES] smelting charges on the user.
##
## While the player holds any charge, a smelting run may reach
## [constant AnvilBoost.BOOSTED_MAX_BARS] bars instead of
## [constant AnvilBoost.BASE_MAX_BARS], and each bar smelted burns one charge —
## so one stabilizer is exactly one long run. See [AnvilBoost].


## Charges one stabilizer grants. Matches the boosted run length on purpose: the
## good's whole promise is "one uninterrupted 50-bar run".
const CHARGES: int = 50


func apply(player: Player, _instance: ServerInstance) -> Dictionary:
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return {"ok": false, "reason": "no_player"}
	resource.anvil_boost_charges += CHARGES
	return {
		"ok": true,
		"charges": resource.anvil_boost_charges,
		"message": "Anvil stabilised — %d smelting charges banked." % resource.anvil_boost_charges,
	}
