extends DataRequestHandler
## Roster for the Curator's cosmetics menu: every cosmetic id, the caller's equipped one,
## and whether the caller is allowed to use any of them at all.
##
## GATE: cosmetics are NOT obtainable. `allowed` is true only for admin+ (see
## CommandPermissions.STAFF_PROTECT_PRIORITY), and a non-staff caller gets an empty
## roster — not a locked one — so nothing about the unreleased set leaks to players who
## somehow reach the menu. cosmetics.equip re-checks independently; this response is a
## convenience for the UI and is never the security boundary.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var pr: PlayerResource = player.player_resource

	var allowed: bool = CommandPermissions.effective_priority(pr, instance) \
		>= CommandPermissions.STAFF_PROTECT_PRIORITY
	if not allowed:
		return {"ok": true, "allowed": false, "cosmetics": [], "equipped": 0}

	return {
		"ok": true,
		"allowed": true,
		"cosmetics": Cosmetics.ids(),
		"equipped": pr.cosmetic_id,
	}
