extends SceneTree
## End-to-end probe of the premium endpoints using [PremiumApi] itself - the real
## caller, not curl.
##
## WHY THIS AND NOT A SHELL SCRIPT. The gateway's HTTP addon reassembles a request
## from whatever one poll tick makes available; whether a body survives that
## depends on how the CLIENT writes its bytes. Testing with curl therefore proves
## something about curl. The only client that matters is Godot's HTTPRequest, so
## this drives the exact code path the world server will.
##
## Requires master + gateway already running, and ARKENELLE_PREMIUM_API_URL /
## ARKENELLE_PREMIUM_API_KEY set in this process' environment.

var _host: Node
var _done: int = 0
var _failures: int = 0
var _account: String = ""
var _item: String = "skin:10001"


func _init() -> void:
	_account = OS.get_environment("ARKENELLE_VERIFY_ACCOUNT").strip_edges().to_lower()
	if _account.is_empty():
		_account = "verifyuser"
	_host = Node.new()
	_host.name = "PremiumProbeHost"
	root.add_child(_host)
	_run.call_deferred()


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok    %s" % label)
		return
	_failures += 1
	print("  FAIL  %s  %s" % [label, detail])


func _run() -> void:
	if not PremiumApi.is_configured():
		print("PremiumApi is not configured - set ARKENELLE_PREMIUM_API_URL and _KEY.")
		quit(1)
		return

	print("account under test: %s" % _account)
	print("")

	print("balance")
	var bal: Dictionary = await _balance()
	_ok("call succeeds", bool(bal.get("ok")), str(bal))
	var data: Dictionary = bal.get("data", {}) as Dictionary
	_ok("body carries data.balance", data.has("balance"), str(bal))
	var start_balance: int = int(data.get("balance", -1))
	print("  balance = %d" % start_balance)

	print("")
	print("purchase")
	var tx: String = "verify-%d" % int(Time.get_unix_time_from_system())
	var cost: int = int(PremiumCatalog.resolve(_item).get("cost", 0))
	_ok("catalog resolved a cost", cost > 0, str(cost))

	var buy: Dictionary = await _purchase(_item, cost, tx)
	if start_balance >= cost:
		_ok("purchase settles", bool(buy.get("ok")), str(buy))
		var after: int = int((buy.get("data", {}) as Dictionary).get("balance", -1))
		_ok("balance reduced by cost", after == start_balance - cost, "after=%d" % after)

		print("")
		print("idempotency (same transaction_id)")
		var replay: Dictionary = await _purchase(_item, cost, tx)
		_ok("replay refused", not bool(replay.get("ok")), str(replay))
		_ok("replay reason is duplicate", str(replay.get("reason")) == "duplicate", str(replay))
		_ok("replay status is 409", int(replay.get("status")) == 409, str(replay))
		var still: Dictionary = await _balance()
		_ok(
			"replay charged nothing",
			int((still.get("data", {}) as Dictionary).get("balance", -1)) == after,
			str(still)
		)
	else:
		_ok("purchase refused when broke", not bool(buy.get("ok")), str(buy))
		_ok("reason is insufficient_funds", str(buy.get("reason")) == "insufficient_funds", str(buy))
		_ok("status is 402", int(buy.get("status")) == 402, str(buy))

	print("")
	print("price is re-derived server side")
	var lied: Dictionary = await _purchase(_item, 1, "verify-lie-%d" % int(Time.get_unix_time_from_system()))
	_ok("understated cost refused", not bool(lied.get("ok")), str(lied))
	_ok("reason is price_mismatch", str(lied.get("reason")) == "price_mismatch", str(lied))

	print("")
	print("unknown item")
	var junk: Dictionary = await _purchase("cosmetic:0", 1000, "verify-junk-%d" % int(Time.get_unix_time_from_system()))
	_ok("refused", not bool(junk.get("ok")), str(junk))
	_ok("status is 404", int(junk.get("status")) == 404, str(junk))

	print("")
	if _failures == 0:
		print("verify_premium_live: PASS")
	else:
		print("verify_premium_live: FAIL (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


func _balance() -> Dictionary:
	var out: Array = []
	PremiumApi.fetch_premium_balance(_host, _account, func(r: Dictionary) -> void: out.append(r))
	return await _await_one(out)


func _purchase(item_id: String, cost: int, transaction_id: String) -> Dictionary:
	var out: Array = []
	PremiumApi.execute_vault_purchase(
		_host, _account, item_id, cost, transaction_id,
		func(r: Dictionary) -> void: out.append(r)
	)
	return await _await_one(out)


## PremiumApi answers on a callback, not a signal, so poll the sink. Bounded so a
## hung gateway fails the run instead of hanging it.
func _await_one(sink: Array) -> Dictionary:
	var waited: float = 0.0
	while sink.is_empty() and waited < 15.0:
		await process_frame
		waited += 0.016
	if sink.is_empty():
		return {"ok": false, "reason": "probe_timeout", "status": 0, "data": {}}
	return sink[0]
