extends DataRequestHandler
## Premium balance for the caller. Two-phase, for the same reason vault.purchase
## is: the handler cannot await, so this acks immediately and the real number
## arrives on a `vault.balance.result` push.
##
## The balance is NEVER stored on the character. The web backend is the only
## authority; caching it here would create a second truth that drifts the moment
## a purchase happens on the website.

const MAX_ATTEMPTS: int = 10
const WINDOW_MS: int = 60_000


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	if not RateLimiter.check(peer_id, &"vault.balance", MAX_ATTEMPTS, WINDOW_MS):
		return {"ok": false, "reason": "rate_limited"}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}
	var account: String = player.player_resource.account_name.strip_edges()
	if account.is_empty():
		return {"ok": false, "reason": "no_account"}
	if not PremiumApi.is_configured():
		return {"ok": false, "reason": "not_configured"}

	# Bound to player_id, not peer_id: a reconnect between ack and settle hands
	# the character a new peer, and the push has to follow the character.
	var player_id: int = player.player_resource.player_id
	PremiumApi.fetch_premium_balance(
		WorldServer.curr,
		account,
		func(result: Dictionary) -> void:
			_push_balance(player_id, result)
	)
	return {"ok": true, "state": "pending"}


func _push_balance(player_id: int, result: Dictionary) -> void:
	var ws: WorldServer = WorldServer.curr
	if ws == null:
		return
	var target_peer: int = int(ws.player_id_to_peer_id.get(player_id, 0))
	if target_peer == 0:
		return # logged out while we waited; nothing was charged, nothing to say
	var data: Dictionary = result.get("data", {}) as Dictionary
	ws.data_push.rpc_id(target_peer, &"vault.balance.result", {
		"ok": bool(result.get("ok", false)),
		"reason": str(result.get("reason", "")),
		"balance": int(data.get("balance", 0)),
	})
