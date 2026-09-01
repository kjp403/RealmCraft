extends PeddlerAction
## Biome Recall Scroll: open the Wayfarer's board wherever the reader is standing.
##
## DOES NOT CONSUME HERE. Using the scroll only opens the board — the RIDE is what
## spends it, over in [code]travel.quick[/code]. Consuming on open would eat a
## 25,000-gold scroll every time someone looked at the routes and closed the
## window, which is the one outcome a player would never forgive.
##
## That is why this is the first action to override [method PeddlerAction.consumes]:
## every other good finishes inside [method apply], so the consume gate in
## [code]peddler.use[/code] is exactly right for them and exactly wrong for this.
##
## NO GATES HERE EITHER. Wardstone, already-here and dead are decided by
## [method QuickTravelDesk.lock_reason] and re-run at booking time, where they are
## authoritative. Checking them again here would be a second copy to drift, and it
## would refuse to even show a board the player is entitled to read.


func apply(player: Player, _instance: ServerInstance) -> Dictionary:
	if player.player_resource == null:
		return {"ok": false, "reason": "no_player"}
	# The client opens the board from this reply. The scroll flag is a REQUEST,
	# not a grant: travel.quote and travel.quick both re-check that the player is
	# actually holding a scroll before quoting or charging nothing for a ride.
	return {
		"ok": true,
		"open_menu": "quick_travel",
		"menu_arg": {"scroll": true},
		"message": "You unfold the road-map.",
	}


## The ride spends the scroll, not the reading. See the class note.
func consumes() -> bool:
	return false
