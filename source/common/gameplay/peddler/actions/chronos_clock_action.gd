extends PeddlerAction
## Chronos Clock: push the party's live Boss Contract deadline out by
## [constant EXTENSION_S].
##
## Extends the CONTRACT, not the holder — everyone on the party gets the extra
## time, and the clock is spent by whoever owns it. A per-player extension would
## be meaningless: the arena ends for the group or for nobody.

const EXTENSION_S: float = 10.0 * 60.0


func apply(player: Player, _instance: ServerInstance) -> Dictionary:
	# Gate BEFORE anything is spent: no live contract, no extension, and the
	# clock stays in the bag. This is the whole validation the good needs — the
	# service refuses an expired or mid-eject contract too, so a player cannot
	# burn a 250,000-gold item on a fight that is already over.
	var group_id: int = BossHuntService.live_contract_of(player)
	if group_id == 0:
		return {"ok": false, "reason": "no_contract"}

	var result: Dictionary = BossHuntService.extend_contract(group_id, EXTENSION_S)
	if result.is_empty():
		# The contract lapsed between the two calls (the deadline is a wall
		# clock, not a lock). Refuse rather than consume.
		return {"ok": false, "reason": "no_contract"}

	var minutes: int = int(EXTENSION_S / 60.0)
	return {
		"ok": true,
		"remaining_s": int(result.get("remaining_s", 0.0)),
		"message": "The contract runs %d minutes longer." % minutes,
	}
