extends DataRequestHandler
## RETIRED by the skilling-board overhaul — kept as a graceful stub so an older
## client that still has a Skip button gets a clean refusal instead of the
## generic `unknown_request` error.
##
## Skips existed because the old board rolled kill/collect targets from a level
## band, so it could hand you "Defeat 1 Iron Golem" with no idea where golems
## live. The skilling board cannot produce an unreachable task: every one of the
## nine skills is trainable from level 1, and the player picks the size of the
## commitment themselves. The escape hatch is now "choose Easy".


func data_request_handler(_peer_id: int, _instance: ServerInstance, _args: Dictionary) -> Dictionary:
	return {"ok": false, "reason": "retired"}
