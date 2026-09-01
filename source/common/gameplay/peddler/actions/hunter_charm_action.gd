extends PeddlerAction
## Hunter's Charm: a [constant DURATION_S] blessing that nudges high-tier boss
## drop rolls up by [constant HunterCharm.DROP_MULTIPLIER].
##
## Using a second charm EXTENDS the blessing rather than refusing — a player who
## banked two of these before a raid night should not have to watch a timer to
## avoid wasting one. The extension is from the later of "now" and the current
## expiry, so it never shortens an active charm either.


const DURATION_S: int = 2 * 60 * 60


func apply(player: Player, _instance: ServerInstance) -> Dictionary:
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return {"ok": false, "reason": "no_player"}
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var base_ms: int = maxi(now_ms, resource.hunter_charm_until_ms)
	resource.hunter_charm_until_ms = base_ms + DURATION_S * 1000
	var remaining_s: int = int((resource.hunter_charm_until_ms - now_ms) / 1000)
	return {
		"ok": true,
		"until_ms": resource.hunter_charm_until_ms,
		"message": "Hunter's Blessing active for %s." % PeddlerSchedule.clock(remaining_s),
	}
