extends ChatCommand
## Read or credit an account's Ark Coin balance from in game.
##
## THE REFUND DESK. Coins enter the game in exactly two ways: a Stripe payment
## the webhook credits, and this. The webhook refuses any payment whose account
## name does not exist — which is what happens every time a buyer types their
## CHARACTER name into the storefront — so those payments sit in the server log
## as real money that reached nobody. Before this command the only way to settle
## one was an SSH session and the master's loopback dashboard.
##
## TARGETS RESOLVE THROUGH [CommandTarget], and that is the point rather than a
## convenience: the name staff are handed by a confused player is their CHARACTER
## name, and the coins belong to an ACCOUNT. `/arkcoins sMiguel 1000` looks the
## character up in the database, reads the account off it, and credits that —
## online or not. `@account` and `#id` work too.
##
## TWO-PHASE, LIKE EVERY OTHER PREMIUM CALL. [ChatCommand.execute] must return a
## String, so it cannot await the backend; the return value is the "sent" line
## and the outcome arrives later as a system message. See [PremiumApi] for why
## nothing in this tree awaits.


## Fat-finger guard, not a policy limit. The largest package sold is 2500, so a
## legitimate refund never approaches this; a stray digit does.
const MAX_GRANT: int = 100_000


func _init() -> void:
	command_name = "arkcoins"
	command_alias = PackedStringArray(["coins"])
	command_priority = 100 # senior_admin — this moves paid currency
	command_usage = "/arkcoins <self|Name|#id|@account> [amount] [reason]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return (
			"Usage: " + command_usage
			+ "\nWith no amount it reads the balance. The target may be a character"
			+ " name — the coins go to the account that owns it."
		)
	if not PremiumApi.is_configured():
		return "The premium backend is not configured on this world; no coins can move."

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	var account: String = target.account_name.strip_edges().to_lower()
	if account.is_empty():
		return "No account on record for %s." % target.label()

	var caller_id: int = _player_id_of(peer_id, server_instance)
	if args.size() == 2:
		PremiumApi.fetch_premium_balance(
			WorldServer.curr,
			account,
			func(result: Dictionary) -> void:
				_settle_balance(caller_id, account, result)
		)
		return "Reading @%s's Ark Coin balance…" % account

	if not args[2].is_valid_int():
		return "Amount must be a whole number of coins."
	var amount: int = args[2].to_int()
	if amount <= 0:
		# Deliberately one-way. The backend's credit path has no negative branch,
		# and taking currency back is a decision that should leave a support
		# trail rather than a chat line.
		return "Amount must be 1 or more; this command only adds coins."
	if amount > MAX_GRANT:
		return "That is over the %d coin cap — grant it in smaller pieces if you meant it." % MAX_GRANT

	var reason: String = " ".join(args.slice(3)).strip_edges() if args.size() > 3 else ""
	if reason.is_empty():
		reason = "staff grant"

	# Idempotency key. Second-granularity: the same command fired twice by a
	# double-press settles once, while a deliberate repeat a moment later is a
	# new grant — which is what staff issuing two refunds in a row expect.
	var transaction_id: String = "admin-%s-%s-%d-%d" % [
		_account_of(peer_id, server_instance),
		account,
		amount,
		int(Time.get_unix_time_from_system()),
	]

	PremiumApi.grant_premium_coins(
		WorldServer.curr,
		account,
		amount,
		transaction_id,
		reason,
		func(result: Dictionary) -> void:
			_settle_grant(caller_id, account, amount, reason, result)
	)
	return "Crediting %d Ark Coins to @%s (%s)…" % [amount, account, reason]


func _settle_balance(caller_id: int, account: String, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_tell(caller_id, "Could not read @%s's balance: %s." % [
			account, _explain(str(result.get("reason", "rejected")))
		])
		return
	var data: Dictionary = result.get("data", {}) as Dictionary
	_tell(caller_id, "@%s has %d Ark Coins." % [account, int(data.get("balance", 0))])


func _settle_grant(
	caller_id: int,
	account: String,
	amount: int,
	reason: String,
	result: Dictionary
) -> void:
	var data: Dictionary = result.get("data", {}) as Dictionary
	if not bool(result.get("ok", false)):
		var why: String = str(result.get("reason", "rejected"))
		if why == "duplicate":
			# Same key, so nothing was added — say so plainly rather than let the
			# "crediting…" line stand as the last word.
			_tell(caller_id, "Already applied — @%s still has %d Ark Coins." % [
				account, int(data.get("balance", 0))
			])
			return
		_tell(caller_id, "Grant to @%s failed: %s. Nothing was added." % [
			account, _explain(why)
		])
		return

	var balance: int = int(data.get("balance", 0))
	_tell(caller_id, "Credited %d Ark Coins to @%s (%s). Balance now %d." % [
		amount, account, reason, balance
	])
	ServerLog.info("Ark Coins: staff granted %d to %s (%s); balance now %d." % [
		amount, account, reason, balance
	])
	_tell_recipient(account, amount, balance)


## Tell the credited player, if they are logged in, and refresh what their
## inventory header shows. The push is the same one vault.balance answers with,
## so the count updates without them opening anything.
func _tell_recipient(account: String, amount: int, balance: int) -> void:
	var ws: WorldServer = WorldServer.curr
	if ws == null:
		return
	for target_peer: int in ws.connected_players:
		var res: PlayerResource = ws.connected_players[target_peer]
		if res == null or res.account_name.to_lower() != account:
			continue
		ws.chat_service.push_system_to_player(
			null,
			res.player_id,
			"%d Ark Coins were added to your account. You now have %d." % [amount, balance]
		)
		ws.data_push.rpc_id(target_peer, &"vault.balance.result", {
			"ok": true,
			"reason": "",
			"balance": balance,
		})


func _tell(player_id: int, text: String) -> void:
	if player_id <= 0 or WorldServer.curr == null:
		return
	WorldServer.curr.chat_service.push_system_to_player(null, player_id, text)


func _player_id_of(peer_id: int, server_instance: ServerInstance) -> int:
	var res: PlayerResource = server_instance.world_server.connected_players.get(peer_id)
	return res.player_id if res != null else 0


func _account_of(peer_id: int, server_instance: ServerInstance) -> String:
	var res: PlayerResource = server_instance.world_server.connected_players.get(peer_id)
	return res.account_name.to_lower() if res != null else "console"


## Backend reason -> something staff can act on. Anything unmapped comes through
## as itself rather than as "failed", because the raw reason is what the server
## log will also say.
func _explain(reason: String) -> String:
	match reason:
		"unknown_account":
			return "no account called that (check /chars, or the spelling)"
		"not_configured":
			return "the premium backend is not configured"
		"unauthorized":
			return "the world's premium key is wrong or missing"
		"timeout", "network":
			return "the backend did not answer — check the balance before retrying"
		"rate_limited":
			return "rate limited; wait a minute"
	return reason
