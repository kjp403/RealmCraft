class_name StripeSignature
## Verifies the `Stripe-Signature` header on an incoming webhook.
##
## THIS IS THE ONLY THING STANDING BETWEEN THE INTERNET AND FREE COINS. The
## webhook endpoint has to be publicly reachable - Stripe calls it from their
## servers - so anyone can POST to it. Without this check, "credit 2500 coins to
## kyle" is a curl command.
##
## Stripe's scheme: the header is `t=<unix>,v1=<hex>,v1=<hex>...`, and each v1 is
## HMAC-SHA256 over the literal string "<t>.<raw body>" keyed with the endpoint's
## signing secret (whsec_...). Multiple v1 values appear while a secret is being
## rotated, so ANY match is a pass.
##
## THE RAW BODY IS LOAD-BEARING. Re-serialising the parsed JSON would not
## reproduce the bytes Stripe signed - key order, whitespace and number
## formatting all differ - so the HTTP addon stamps the body exactly as it
## arrived and this reads that, never the Dictionary.

## How far apart the timestamp and our clock may be. Stripe's own libraries
## default to five minutes. Without this a captured-and-replayed webhook stays
## valid forever, because the signature over a fixed body never expires.
const TOLERANCE_S: int = 300


## Returns {} when the request is authentic, or {"reason": "..."} describing the
## first thing that was wrong. A Dictionary rather than a bool so the caller can
## log WHY a webhook was refused - "bad signature" and "clock skew" need very
## different responses from an operator.
static func verify(
	raw_body: String,
	signature_header: String,
	secret: String,
	now_unix: int = 0
) -> Dictionary:
	if secret.strip_edges().is_empty():
		return {"reason": "not_configured"}
	if raw_body.is_empty():
		return {"reason": "empty_body"}

	var parsed: Dictionary = _parse_header(signature_header)
	var timestamp: int = int(parsed.get("t", 0))
	var candidates: PackedStringArray = parsed.get("v1", PackedStringArray())
	if timestamp <= 0 or candidates.is_empty():
		return {"reason": "malformed_signature"}

	var now: int = now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())
	if absi(now - timestamp) > TOLERANCE_S:
		return {"reason": "stale_timestamp"}

	var expected: String = sign_payload("%d.%s" % [timestamp, raw_body], secret)
	for candidate: String in candidates:
		if _hex_equals(candidate, expected):
			return {}
	return {"reason": "bad_signature"}


## HMAC-SHA256, hex-encoded. Exposed so a test can produce a real signature
## rather than asserting against a hard-coded string that nothing generates.
static func sign_payload(signed_payload: String, secret: String) -> String:
	var hmac: HMACContext = HMACContext.new()
	if hmac.start(HashingContext.HASH_SHA256, secret.to_utf8_buffer()) != OK:
		return ""
	if hmac.update(signed_payload.to_utf8_buffer()) != OK:
		return ""
	return hmac.finish().hex_encode()


## `t=123,v1=abc,v1=def` -> {"t": "123", "v1": ["abc", "def"]}. Unknown schemes
## (v0, and anything Stripe adds later) are ignored rather than rejected, so a
## future header format does not start failing valid webhooks.
static func _parse_header(header: String) -> Dictionary:
	var out: Dictionary = {"t": "", "v1": PackedStringArray()}
	for part: String in header.split(","):
		var pair: PackedStringArray = part.strip_edges().split("=", true, 1)
		if pair.size() != 2:
			continue
		var key: String = pair[0].strip_edges()
		var value: String = pair[1].strip_edges()
		if key == "t":
			out["t"] = value
		elif key == "v1":
			var list: PackedStringArray = out["v1"]
			list.append(value)
			out["v1"] = list
	return out


## Length-checked, full-pass, case-insensitive hex compare. `==` short-circuits
## on the first differing character, which leaks the expected signature one
## character at a time to anything that can time the response.
static func _hex_equals(offered: String, expected: String) -> bool:
	var a: String = offered.strip_edges().to_lower()
	var b: String = expected.strip_edges().to_lower()
	if a.length() != b.length() or a.is_empty():
		return false
	var diff: int = 0
	for i: int in b.length():
		diff |= a.unicode_at(i) ^ b.unicode_at(i)
	return diff == 0
