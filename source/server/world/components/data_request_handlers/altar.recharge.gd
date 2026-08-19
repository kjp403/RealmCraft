extends DataRequestHandler
## Refill prayer points at the church altar. Free, but you have to walk there —
## that is the whole trade against carrying prayer potions.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}
	if not Altar.player_in_range(player):
		return {"ok": false, "reason": "too_far"}

	var restored: float = PrayerService.restore_full(player)
	if restored <= 0.0:
		return {"ok": false, "reason": "already_full"}
	return {"ok": true, "restored": restored, "prayer": PrayerService.status(player)}
