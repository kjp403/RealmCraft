class_name PeddlerWebExport
extends Node
## Ships the Peddler's live state off the world server so the website can show
## it. Server-only, fire-and-forget, and never allowed to affect the game.
##
## WHY A NODE. [HTTPRequest] has to be in the SceneTree to poll its socket, so
## each POST gets its own request node parented under the caller, and frees
## itself in [signal HTTPRequest.request_completed]. One node per POST rather
## than a long-lived shared one: these fire minutes apart at most, and a shared
## node would need its own queue for the case where a spawn and a stock roll land
## on the same tick.
##
## NOTHING HERE IS ALLOWED TO BLOCK OR THROW. A website widget must never be able
## to stall a spawn or take the world down, so every failure path is a warn-and-
## return. The export is best-effort by design: the next event re-sends the whole
## snapshot, so a dropped POST self-heals within one cycle rather than needing a
## retry queue.
##
## CONFIGURED BY ENVIRONMENT, and disabled unless BOTH variables are set:
##   ARKENELLE_PEDDLER_WEBHOOK_URL  — where to POST (the gateway's
##                                   /v1/peddler/update)
##   ARKENELLE_PEDDLER_WEBHOOK_KEY  — the shared server-to-server secret
##
## The key is never written to the repo, never logged, and never appears in a
## payload — it rides the Authorization header and nowhere else. An unset key
## means the exporter is OFF, which is the correct default for every developer
## machine: a local world must not POST to production, and silence is a safer
## failure than a half-configured request.

const URL_ENV: String = "ARKENELLE_PEDDLER_WEBHOOK_URL"
const KEY_ENV: String = "ARKENELLE_PEDDLER_WEBHOOK_KEY"
## Payload schema version, so the gateway and the site can tell an old world
## server's snapshot from a new one after a field changes.
const SCHEMA: int = 1


## True when both environment variables are present. Read live rather than
## cached so an operator can set the variables and restart the world without a
## code change, and so the reason for silence is always checkable.
static func is_configured() -> bool:
	return not OS.get_environment(URL_ENV).is_empty() \
		and not OS.get_environment(KEY_ENV).is_empty()


## Build the snapshot the website renders. Pure — takes no I/O and no node — so
## the verify gate can assert its shape without standing up a server.
##
## [param biome] is the instance_name the cart is assigned to (&"" when closed),
## and [param active] whether it is actually standing. They are separate because
## a window can be open with the cart not yet placed (its biome is not loaded),
## and the site should say "roaming" rather than name a zone nobody can visit.
static func build_payload(biome: StringName, active: bool) -> Dictionary:
	var now_s: int = PeddlerSchedule.now_s()
	var stock: Array = []
	for row: PeddlerItemData in PeddlerStock.for_date(PeddlerSchedule.utc_date(now_s)):
		stock.append({
			"id": row.id,
			"name": row.item_name,
			"price": row.price_gold,
			"tier": row.tier,
			"description": row.description,
		})
	return {
		"schema": SCHEMA,
		"is_active": active,
		"current_zone": _zone_title(biome) if active else "",
		"time_remaining_seconds": PeddlerSchedule.seconds_remaining(now_s) if active else 0,
		"next_spawn_utc_timestamp": PeddlerSchedule.next_spawn_s(now_s),
		# The site derives its own countdowns from the timestamps above, but it
		# needs to know when THIS snapshot was taken to tell a live reading from
		# a stale cache after a world restart.
		"generated_utc_timestamp": now_s,
		"daily_stock": stock,
	}


## Player-facing zone name for an instance_name ("The Desert (Surface)"), falling
## back to the raw name so an unregistered instance still reads as somewhere.
static func _zone_title(biome: StringName) -> String:
	if biome == &"":
		return ""
	var ws: WorldServer = WorldServer.curr
	if ws == null or ws.instance_manager == null:
		return String(biome)
	var res: InstanceResource = ws.instance_manager.instance_collection.get(String(biome), null)
	if res == null:
		return String(biome)
	var title: String = res.display_title()
	return title if not title.is_empty() else String(biome)


## POST [param payload] to the configured endpoint, parented under [param host].
## Returns false when the exporter is off or the call could not be started —
## never throws, and never makes the caller wait. The HTTP rules (threaded, no
## leak, warn-only) live in [PeddlerHttp], shared with the Discord announcer.
static func post(host: Node, payload: Dictionary) -> bool:
	var url: String = OS.get_environment(URL_ENV)
	var key: String = OS.get_environment(KEY_ENV)
	if url.is_empty() or key.is_empty():
		return false # not configured — the normal state on a dev machine
	return PeddlerHttp.post_json(
		host,
		url,
		payload,
		"Peddler web export",
		# Server-to-server bearer. The ONLY place the secret appears — never in
		# the payload, never in a log line.
		PackedStringArray(["Authorization: Bearer " + key])
	)
