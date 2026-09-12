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
	print("grant (the /arkcoins refund path)")
	var before_grant: int = int((await _balance()).get("data", {}).get("balance", -1))
	var grant_tx: String = "verify-grant-%d" % int(Time.get_unix_time_from_system())
	var granted: Dictionary = await _grant(_account, 7, grant_tx, "verify")
	_ok("grant settles", bool(granted.get("ok")), str(granted))
	_ok(
		"balance rose by 7",
		int((granted.get("data", {}) as Dictionary).get("balance", -1)) == before_grant + 7,
		"before=%d %s" % [before_grant, str(granted)]
	)
	# The same key twice is the double-press case, and it must NOT pay out again.
	var grant_replay: Dictionary = await _grant(_account, 7, grant_tx, "verify")
	_ok("replayed grant refused", not bool(grant_replay.get("ok")), str(grant_replay))
	_ok("replay reason is duplicate", str(grant_replay.get("reason")) == "duplicate", str(grant_replay))
	var after_grant: int = int((await _balance()).get("data", {}).get("balance", -1))
	_ok("replay added nothing", after_grant == before_grant + 7, "got=%d" % after_grant)
	# A typo'd account must be refused rather than minting a wallet nobody owns.
	var ghost_grant: Dictionary = await _grant(
		"nosuchaccount", 7, "verify-ghost-%d" % int(Time.get_unix_time_from_system()), "verify"
	)
	_ok("grant to unknown account refused", not bool(ghost_grant.get("ok")), str(ghost_grant))
	_ok("status is 404", int(ghost_grant.get("status")) == 404, str(ghost_grant))

	print("")
	print("public account check (what the storefront asks before checkout)")
	var real: Dictionary = await _account_check(_account)
	_ok("answers 200", int(real.get("status")) == 200, str(real))
	_ok("known account exists", bool((real.get("json", {}) as Dictionary)
		.get("data", {}).get("exists", false)), str(real))
	var unknown: Dictionary = await _account_check("nosuchaccount")
	_ok("unknown account does not exist", not bool((unknown.get("json", {}) as Dictionary)
		.get("data", {}).get("exists", true)), str(unknown))
	# The whole bug: a character name is a perfectly well-formed account name.
	# The only thing that can tell them apart is this lookup.
	var malformed: Dictionary = await _account_check("!!")
	_ok("malformed name answered without a backend hop",
		int(malformed.get("status")) == 200
		and not bool((malformed.get("json", {}) as Dictionary)
			.get("data", {}).get("exists", true)), str(malformed))

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


func _grant(account: String, amount: int, transaction_id: String, reason: String) -> Dictionary:
	var out: Array = []
	PremiumApi.grant_premium_coins(
		_host, account, amount, transaction_id, reason,
		func(r: Dictionary) -> void: out.append(r)
	)
	return await _await_one(out)


## The account check is PUBLIC and carries no bearer, so it cannot go through
## [PremiumApi] - this posts it the way the website does, with no credentials at
## all. A 401 here would mean the route had been moved behind the premium auth
## and the storefront had silently stopped checking anything.
func _account_check(name: String) -> Dictionary:
	var base: String = OS.get_environment("ARKENELLE_PREMIUM_API_URL").strip_edges().rstrip("/")
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = 15.0
	_host.add_child(request)
	var sink: Array = []
	request.request_completed.connect(
		func(_r: int, code: int, _h: PackedStringArray, raw: PackedByteArray) -> void:
			var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
			sink.append({"status": code, "json": parsed if parsed is Dictionary else {}})
	)
	var error: Error = request.request(
		base + "/v1/account/check",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"name": name})
	)
	if error != OK:
		request.queue_free()
		return {"status": 0, "json": {}}
	var waited: float = 0.0
	while sink.is_empty() and waited < 15.0:
		await process_frame
		waited += 0.016
	request.queue_free()
	return sink[0] if not sink.is_empty() else {"status": 0, "json": {}}


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
