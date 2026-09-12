extends DataRequestHandler
## Buy a Vault entitlement with premium currency. Server-authoritative end to end:
## the client sends a token and nothing else - no price, no item metadata, no
## balance.
##
## TWO PHASES, AND WHY. Everything that can be checked without leaving the process
## is checked synchronously and the client is acked inside its 5s request timeout.
## The web call then runs on its own and the outcome arrives as a
## `vault.purchase.result` push. A handler that awaited would return a Signal into
## `_data_response(... data: Dictionary)` and break the response entirely.
##
## ORDER OF OPERATIONS IS THE WHOLE SAFETY ARGUMENT:
##   1. validate + prove ownership is absent  (free to get wrong - nothing charged)
##   2. take the in-flight slot               (closes the double-click window)
##   3. charge the backend                    (money moves)
##   4. grant + save                          (only on 200 OK)
## Granting before step 3 would hand out entitlements for free. Charging before
## step 1 would bill for things the player already owns.
##
## THE ONE HOLE, STATED PLAINLY: if the player logs out between 3 and 4, the funds
## are gone and the grant lands nowhere. That is logged at error with the
## transaction id for reconciliation. Closing it properly means the backend
## holding an undelivered grant and replaying it on the next balance fetch -
## worth doing, deliberately not in this change.

const MAX_ATTEMPTS: int = 5
const WINDOW_MS: int = 60_000

## player_id -> transaction_id. Lives on the handler instance, which world_server
## caches for the life of the process, so it is genuinely one guard per world.
## Keyed by player_id rather than peer_id so a reconnect mid-flight cannot buy the
## same thing twice.
var _in_flight: Dictionary[int, String] = {}

static var _sequence: int = 0


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	if not RateLimiter.check(peer_id, &"vault.purchase", MAX_ATTEMPTS, WINDOW_MS):
		return {"ok": false, "reason": "rate_limited"}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}
	var pr: PlayerResource = player.player_resource

	var account: String = pr.account_name.strip_edges()
	if account.is_empty():
		return {"ok": false, "reason": "no_account"}
	if not PremiumApi.is_configured():
		return {"ok": false, "reason": "not_configured"}

	# The token is the ONLY thing taken from the client, and it is only ever
	# looked up - never parsed into a price or a display name.
	var entry: Dictionary = PremiumCatalog.resolve(str(args.get("item_id", "")))
	if entry.is_empty():
		return {"ok": false, "reason": "unknown_item"}
	if PremiumCatalog.owns(pr, entry):
		return {"ok": false, "reason": "already_owned"}

	if _in_flight.has(pr.player_id):
		return {"ok": false, "reason": "in_flight"}

	var player_id: int = pr.player_id
	var transaction_id: String = _mint(player_id)
	_in_flight[player_id] = transaction_id

	var started: bool = PremiumApi.execute_vault_purchase(
		WorldServer.curr,
		account,
		str(entry.get("item_id", "")),
		int(entry.get("cost", 0)),
		transaction_id,
		func(result: Dictionary) -> void:
			_on_settled(player_id, entry, transaction_id, result)
	)
	if not started:
		# PremiumApi already settled the callback with the failure, which cleared
		# the slot. Nothing to unwind here - just don't tell the client to wait.
		return {"ok": false, "reason": "network"}

	return {
		"ok": true,
		"state": "pending",
		"transaction_id": transaction_id,
		"item_id": str(entry.get("item_id", "")),
		"cost": int(entry.get("cost", 0)),
	}


## Settlement. Runs on the HTTP completion signal, so it re-resolves everything -
## the player may have moved instance, reconnected, or gone.
func _on_settled(
	player_id: int,
	entry: Dictionary,
	transaction_id: String,
	result: Dictionary
) -> void:
	# Release the slot first and unconditionally: a guard that outlives its
	# transaction locks the player out of ever buying again this session.
	if _in_flight.get(player_id, "") == transaction_id:
		_in_flight.erase(player_id)

	var ws: WorldServer = WorldServer.curr
	if ws == null:
		return
	var target_peer: int = int(ws.player_id_to_peer_id.get(player_id, 0))
	var item_id: String = str(entry.get("item_id", ""))

	if not bool(result.get("ok", false)):
		if target_peer != 0:
			ws.data_push.rpc_id(target_peer, &"vault.purchase.result", {
				"ok": false,
				"reason": str(result.get("reason", "rejected")),
				"item_id": item_id,
				"transaction_id": transaction_id,
			})
		return

	# Paid. From here the entitlement MUST land or be logged loudly - a silent
	# failure past this line is a player charged for nothing.
	var pr: PlayerResource = null
	if target_peer != 0:
		pr = ws.connected_players.get(target_peer, null)
	if pr == null:
		ServerLog.error(
			"Premium purchase %s settled for player #%d but they are offline; entitlement '%s' NOT granted and needs reconciliation."
				% [transaction_id, player_id, item_id]
		)
		return

	if not PremiumCatalog.grant(pr, entry):
		# Paid for something already held. Not fatal - the entitlement is present
		# either way - but it means a pre-check was raced and is worth seeing.
		ServerLog.warn(
			"Premium purchase %s granted nothing new ('%s') for player #%d."
				% [transaction_id, item_id, player_id]
		)
	ws.database.save_player(pr)
	ServerLog.info(
		"Player #%d (%s) bought '%s' for %d premium (tx %s)."
			% [
				player_id,
				pr.display_name,
				item_id,
				int(entry.get("cost", 0)),
				transaction_id,
			]
	)

	var data: Dictionary = result.get("data", {}) as Dictionary
	ws.data_push.rpc_id(target_peer, &"vault.purchase.result", {
		"ok": true,
		"item_id": item_id,
		"label": str(entry.get("label", "")),
		"transaction_id": transaction_id,
		"balance": int(data.get("balance", 0)),
	})


## Unique per world process: player, clock, and a counter, because two purchases
## inside the same second must not share an idempotency key.
static func _mint(player_id: int) -> String:
	_sequence += 1
	return "%d-%d-%d" % [player_id, int(Time.get_unix_time_from_system()), _sequence]
