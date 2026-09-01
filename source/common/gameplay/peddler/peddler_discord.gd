class_name PeddlerDiscord
## Announces the Traveling Peddler's arrival to a Discord webhook.
##
## SPAWN ONLY. Not the despawn, not the midnight stock roll. "The Peddler has
## left" is a notification nobody can act on, and a channel that pings six times
## a day for things you cannot do anything about is a channel people mute — at
## which point the one message that mattered is muted too.
##
## THE ZONE IS ANNOUNCED, and that is a design decision rather than an oversight.
## The hunt worth keeping is finding the cart inside a biome; the hunt worth
## removing is guessing which of nineteen maps to search with a 30-minute clock
## running. Naming the zone spends the part of the mystery that was only ever
## frustration and keeps the part that is a game.
##
## THE CLOCK IS A DISCORD TIMESTAMP, not text. `<t:1234567890:R>` renders as a
## LIVE "in 24 minutes" that counts down in every reader's client, in their own
## timezone, and keeps being right long after the message was posted. A baked
## "30 minutes left" string is a lie to everyone who opens Discord ten minutes
## later — which is exactly the person most at risk of arriving to an empty spot.
## One message that stays accurate beats a second ping near the end.
##
## CONFIGURED BY ENVIRONMENT, and off unless the webhook is set:
##   ARKENELLE_PEDDLER_DISCORD_WEBHOOK — the full webhook URL
##   ARKENELLE_PEDDLER_DISCORD_ROLE_ID — optional numeric role id to ping
##
## The webhook URL IS a credential: anyone holding it can post into that channel
## as the bot. It is read from the environment, never committed, and never
## written to a log — see [PeddlerHttp].

const WEBHOOK_ENV: String = "ARKENELLE_PEDDLER_DISCORD_WEBHOOK"
const ROLE_ENV: String = "ARKENELLE_PEDDLER_DISCORD_ROLE_ID"

## Embed accent, matching the S-tier gold the shop window and the website use.
const EMBED_COLOR: int = 0xFFD640
## Tier marks for the stock lines. Plain letters, not emoji: a custom emoji would
## be per-server and render as raw `:name:` text in anyone else's client.
const TIER_MARK: Dictionary[String, String] = {"S": "S", "A": "A", "B": "B"}


## True when a webhook is configured. Read live so an operator can set it and
## restart without a code change.
static func is_configured() -> bool:
	return not OS.get_environment(WEBHOOK_ENV).is_empty()


## Build the Discord message for a spawn snapshot (the same dictionary
## [method PeddlerWebExport.build_payload] produces).
##
## Pure, so the verify gate can assert the exact JSON without a webhook, a
## network, or a running world.
static func build_message(payload: Dictionary, role_id: String = "") -> Dictionary:
	var zone: String = str(payload.get("current_zone", ""))
	if zone.is_empty():
		zone = "an unknown corner of the world"
	# Only build a live timestamp when there is genuinely time left. A snapshot
	# with 0 seconds remaining would otherwise render as "packs up just now" —
	# worse than saying nothing, because it reads as "do not bother going".
	var remaining: int = int(payload.get("time_remaining_seconds", 0))
	var generated: int = int(payload.get("generated_utc_timestamp", 0))
	var leaves_at: int = (generated + remaining) if (remaining > 0 and generated > 0) else 0

	var fields: Array = []
	for row: Variant in (payload.get("daily_stock", []) as Array):
		var entry: Dictionary = row as Dictionary
		var tier: String = str(entry.get("tier", "")).to_upper()
		fields.append({
			"name": "%s  ·  %s-tier" % [str(entry.get("name", "?")), TIER_MARK.get(tier, tier)],
			"value": "**%s gold**" % _commas(int(entry.get("price", 0))),
			"inline": true,
		})

	var message: Dictionary = {
		# allowed_mentions is a WHITELIST. Without it a stock item named with an
		# @ could ping a real user or role; with it, the ONLY thing this webhook
		# can ever ping is the opt-in role below, no matter what the payload says.
		"allowed_mentions": {"parse": [], "roles": [role_id] if not role_id.is_empty() else []},
		"embeds": [{
			"title": "The Traveling Peddler has arrived",
			"description": "**%s**\nPacks up %s." % [
				zone,
				("<t:%d:R>" % leaves_at) if leaves_at > 0 else "within the half hour",
			],
			"color": EMBED_COLOR,
			"fields": fields,
			"footer": {"text": "One of each, per account, per day."},
		}],
	}
	if not role_id.is_empty():
		message["content"] = "<@&%s>" % role_id
	return message


## Announce a spawn. No-op when unconfigured. Never throws, never waits.
static func announce(host: Node, payload: Dictionary) -> bool:
	var url: String = OS.get_environment(WEBHOOK_ENV)
	if url.is_empty():
		return false
	# A snapshot with nothing standing has nothing to announce. Guards the case
	# where a spawn export races a despawn.
	if not bool(payload.get("is_active", false)):
		return false
	return PeddlerHttp.post_json(
		host,
		url,
		build_message(payload, OS.get_environment(ROLE_ENV).strip_edges()),
		"Peddler Discord announce"
	)


## 12345 -> "12,345".
static func _commas(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	var i: int = digits.length()
	while i > 0:
		var start: int = maxi(0, i - 3)
		if not out.is_empty():
			out = "," + out
		out = digits.substr(start, i - start) + out
		i = start
	return out
