extends PeddlerAction
## Prismatic Dye: recolour the drinker's body for
## [constant PrismaticDye.DURATION_S], visible to the whole zone.
##
## The colour is ROLLED, not chosen — that is what "prismatic" buys, and it keeps
## the 20,000-gold shop row from having to become a colour picker. Re-dyeing
## rerolls and restarts the clock (see [method PrismaticDye.apply]).
##
## The id is BROADCAST on the character's synced :prismatic_dye_id path — the
## same channel cosmetics use — so every client already in the zone repaints the
## body immediately, and anyone who arrives later gets it from the spawn sync in
## instance_server. Without the broadcast the dye would only exist on the wearer's
## own screen, which is the opposite of what a cosmetic is for.


func apply(player: Player, _instance: ServerInstance) -> Dictionary:
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return {"ok": false, "reason": "no_player"}

	var dye_id: int = PrismaticDye.apply(resource)
	if dye_id <= 0:
		# An empty palette. A content error, not a player error — do not consume.
		return {"ok": false, "reason": "no_dye"}

	if player.state_synchronizer != null:
		player.state_synchronizer.set_by_path(^":prismatic_dye_id", dye_id)

	return {
		"ok": true,
		"dye_id": dye_id,
		"message": "%s dye — %d hours." % [
			PrismaticDye.dye_name(dye_id), int(PrismaticDye.DURATION_S / 3600.0)
		],
	}
