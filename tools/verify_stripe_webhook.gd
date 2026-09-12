extends SceneTree
## Signs a real Stripe-shaped `checkout.session.completed` and posts it at a
## running gateway, then checks the coins actually landed.
##
## WHY SIGNED RATHER THAN MOCKED. The signature is the entire security model of a
## publicly reachable endpoint that adds currency. A test that skips it proves
## the happy path and none of the thing that matters, so this computes a genuine
## HMAC with [StripeSignature.sign_payload] and also fires deliberately bad ones.
##
## Needs master + gateway running, and ARKENELLE_STRIPE_WEBHOOK_SECRET set in
## this process to the same value the gateway has.

const GATEWAY: String = "http://127.0.0.1:8088"
const DASHBOARD: String = "http://127.0.0.1:8080"

var _host: Node
var _failures: int = 0
var _secret: String = ""
var _account: String = "stripeuser"
var _token: String = ""


func _init() -> void:
	_secret = OS.get_environment("ARKENELLE_STRIPE_WEBHOOK_SECRET").strip_edges()
	_token = OS.get_environment("ARKENELLE_DASHBOARD_TOKEN").strip_edges()
	if _secret.is_empty():
		print("ARKENELLE_STRIPE_WEBHOOK_SECRET is not set.")
		quit(1)
		return
	_host = Node.new()
	_host.name = "StripeProbeHost"
	root.add_child(_host)
	_run.call_deferred()


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok    %s" % label)
		return
	_failures += 1
	print("  FAIL  %s  %s" % [label, detail])


func _run() -> void:
	print("account under test: %s" % _account)
	print("")

	print("signature unit checks")
	var body: String = '{"hello":"world"}'
	var now: int = int(Time.get_unix_time_from_system())
	var good: String = StripeSignature.sign_payload("%d.%s" % [now, body], _secret)
	_ok("valid signature passes",
		StripeSignature.verify(body, "t=%d,v1=%s" % [now, good], _secret).is_empty())
	_ok("tampered body fails", not StripeSignature.verify(
		'{"hello":"mars"}', "t=%d,v1=%s" % [now, good], _secret).is_empty())
	_ok("wrong secret fails", not StripeSignature.verify(
		body, "t=%d,v1=%s" % [now, good], "whsec_wrong").is_empty())
	var stale: int = now - 3600
	var stale_sig: String = StripeSignature.sign_payload("%d.%s" % [stale, body], _secret)
	_ok("stale timestamp refused", str(StripeSignature.verify(
		body, "t=%d,v1=%s" % [stale, stale_sig], _secret).get("reason")) == "stale_timestamp")
	_ok("malformed header refused", not StripeSignature.verify(
		body, "garbage", _secret).is_empty())
	# Rotation: Stripe sends every active secret's signature, any one may match.
	_ok("second v1 during rotation passes", StripeSignature.verify(
		body, "t=%d,v1=%s,v1=%s" % [now, "deadbeef", good], _secret).is_empty())

	print("")
	print("package mapping")
	_ok("249c -> 250", StripePackages.coins_for_cents(249) == 250)
	_ok("2499c -> 2500", StripePackages.coins_for_cents(2499) == 2500)
	_ok("unknown amount -> 0", StripePackages.coins_for_cents(1234) == 0)
	_ok("usd accepted", StripePackages.currency_ok("USD"))
	_ok("other currency refused", not StripePackages.currency_ok("jpy"))

	print("")
	print("live webhook")
	var before: int = await _balance()
	print("  balance before = %d" % before)

	var event_id: String = "evt_verify_%d" % int(Time.get_unix_time_from_system())
	var paid: Dictionary = await _post_event(_event(event_id, "cs_test_1", 999, "usd", _account), true)
	_ok("signed webhook accepted", int(paid.get("status")) == 200, str(paid))
	_ok("reports credited 1000", int((paid.get("json", {}) as Dictionary).get("credited", 0)) == 1000, str(paid))
	var after: int = await _balance()
	_ok("balance +1000", after == before + 1000, "before=%d after=%d" % [before, after])

	print("")
	print("replay of the same event id")
	var replay: Dictionary = await _post_event(_event(event_id, "cs_test_1", 999, "usd", _account), true)
	_ok("replay accepted (200, so Stripe stops)", int(replay.get("status")) == 200, str(replay))
	var after_replay: int = await _balance()
	_ok("replay credited nothing", after_replay == after, "after=%d replay=%d" % [after, after_replay])

	print("")
	print("hostile / malformed")
	var unsigned: Dictionary = await _post_event(_event("evt_x", "cs_x", 999, "usd", _account), false)
	_ok("unsigned rejected 400", int(unsigned.get("status")) == 400, str(unsigned))
	var after_unsigned: int = await _balance()
	_ok("unsigned credited nothing", after_unsigned == after)

	var odd: Dictionary = await _post_event(
		_event("evt_odd_%d" % Time.get_ticks_msec(), "cs_odd", 1234, "usd", _account), true)
	_ok("unmapped amount not credited",
		not bool((odd.get("json", {}) as Dictionary).get("ok", true)), str(odd))

	var wrong_ccy: Dictionary = await _post_event(
		_event("evt_ccy_%d" % Time.get_ticks_msec(), "cs_ccy", 999, "jpy", _account), true)
	_ok("wrong currency not credited",
		not bool((wrong_ccy.get("json", {}) as Dictionary).get("ok", true)), str(wrong_ccy))

	var ghost: Dictionary = await _post_event(
		_event("evt_ghost_%d" % Time.get_ticks_msec(), "cs_ghost", 999, "nosuchaccount", _account), true)
	_ok("unknown account answers 200 (no endless retry)",
		int(ghost.get("status")) == 200, str(ghost))

	var final_balance: int = await _balance()
	_ok("balance untouched by every bad case", final_balance == after,
		"expected=%d got=%d" % [after, final_balance])

	print("")
	if _failures == 0:
		print("verify_stripe_webhook: PASS")
	else:
		print("verify_stripe_webhook: FAIL (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


## A minimal but structurally real checkout.session.completed.
func _event(
	event_id: String,
	session_id: String,
	amount_cents: int,
	currency: String,
	account: String
) -> Dictionary:
	return {
		"id": event_id,
		"object": "event",
		"type": "checkout.session.completed",
		"created": int(Time.get_unix_time_from_system()),
		"data": {
			"object": {
				"id": session_id,
				"object": "checkout.session",
				"payment_status": "paid",
				"amount_total": amount_cents,
				"currency": currency,
				"client_reference_id": account,
			}
		},
	}


func _post_event(event: Dictionary, sign: bool) -> Dictionary:
	var body: String = JSON.stringify(event)
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	if sign:
		var now: int = int(Time.get_unix_time_from_system())
		var sig: String = StripeSignature.sign_payload("%d.%s" % [now, body], _secret)
		headers.append("Stripe-Signature: t=%d,v1=%s" % [now, sig])
	else:
		headers.append("Stripe-Signature: t=1,v1=deadbeef")
	return await _request(GATEWAY + "/v1/premium/stripe-webhook", headers, body)


func _balance() -> int:
	var out: Dictionary = await _request(
		"%s/v1/premium?username=%s&token=%s" % [DASHBOARD, _account, _token],
		PackedStringArray(), ""
	)
	return int((out.get("json", {}) as Dictionary).get("balance", -1))


func _request(url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = 15.0
	_host.add_child(request)
	var sink: Array = []
	request.request_completed.connect(
		func(_r: int, code: int, _h: PackedStringArray, raw: PackedByteArray) -> void:
			var text: String = raw.get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(text)
			sink.append({
				"status": code,
				"json": parsed if parsed is Dictionary else {},
				"text": text,
			})
	)
	var method: HTTPClient.Method = HTTPClient.METHOD_POST if not body.is_empty() else HTTPClient.METHOD_GET
	if request.request(url, headers, method, body) != OK:
		request.queue_free()
		return {"status": 0, "json": {}, "text": "request failed to start"}
	var waited: float = 0.0
	while sink.is_empty() and waited < 16.0:
		await process_frame
		waited += 0.016
	request.queue_free()
	if sink.is_empty():
		return {"status": 0, "json": {}, "text": "timeout"}
	return sink[0]
