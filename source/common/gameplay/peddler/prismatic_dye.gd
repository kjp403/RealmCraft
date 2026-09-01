class_name PrismaticDye
## The Prismatic Dye's palette and its expiry rules.
##
## A dye is a TIMED COSMETIC: two hours of a recoloured body, visible to everyone
## in the zone, then it lapses. It reuses the prestige vault-skin shader rather
## than adding a second recolour path — that shader already tints a character
## body while keeping flesh tones, which is exactly what a cloth dye should do,
## and one material slot on the sprite means the two can never fight over it.
##
## PRECEDENCE. A vault skin wins. It is staff-only prestige with its own sprite
## swap, and a 20,000-gold dye must not be able to paint over it; the dye simply
## does not render while one is worn, and reappears when it comes off. See
## [method Character._refresh_body_visual].
##
## The dye id is BROADCAST, not derived: [member PlayerResource.prismatic_dye_id]
## is pushed on the character's synced [code]:prismatic_dye_id[/code] path, the
## same channel cosmetics use, so every client in the zone paints the same body.
## Deriving it client-side from an expiry stamp would mean shipping every
## player's timer to every other player for a purely visual effect.

## How long one dye lasts.
const DURATION_S: int = 2 * 60 * 60

## The dyes, by id. Id 0 is "no dye" and is not in here.
##
## Named rather than generated so a dye a player got yesterday is the same colour
## today, and so the roll can never land on something that reads as a vault skin
## or as a Skilling Outfit aura.
const DYES: Dictionary[int, Dictionary] = {
	1: {"name": "Verdant", "tint": Color(0.35, 0.78, 0.42)},
	2: {"name": "Cerulean", "tint": Color(0.30, 0.58, 0.95)},
	3: {"name": "Amaranth", "tint": Color(0.92, 0.31, 0.55)},
	4: {"name": "Saffron", "tint": Color(0.98, 0.76, 0.24)},
	5: {"name": "Amethyst", "tint": Color(0.66, 0.40, 0.94)},
	6: {"name": "Vermilion", "tint": Color(0.95, 0.38, 0.22)},
	7: {"name": "Glacier", "tint": Color(0.62, 0.90, 0.95)},
	8: {"name": "Obsidian", "tint": Color(0.28, 0.26, 0.34)},
}


## True when [param id] names a real dye.
static func is_valid(id: int) -> bool:
	return DYES.has(id)


## Display name for [param id], or "" when it is not a dye.
static func dye_name(id: int) -> String:
	return str(DYES.get(id, {}).get("name", ""))


## Shader tint for [param id]. Falls back to a neutral grey rather than to black,
## which would render as a silhouette.
static func tint_of(id: int) -> Color:
	return DYES.get(id, {}).get("tint", Color(0.7, 0.7, 0.7))


## Every dye id, ascending. For the roll and for the verify gate.
static func all_ids() -> Array:
	var ids: Array = DYES.keys()
	ids.sort()
	return ids


## A dye id at random. "Prismatic" is the point: the player buys a recolour, not
## a specific colour, so the shop row does not have to become a colour picker.
static func roll() -> int:
	var ids: Array = all_ids()
	return ids[randi() % ids.size()] if not ids.is_empty() else 0


## True while [param resource]'s dye is still running.
static func is_active(resource: PlayerResource) -> bool:
	if resource == null or resource.prismatic_dye_id <= 0:
		return false
	return resource.prismatic_dye_until_ms > int(Time.get_unix_time_from_system() * 1000.0)


## Seconds of dye left (0 when none).
static func remaining_s(resource: PlayerResource) -> int:
	if not is_active(resource):
		return 0
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	@warning_ignore("integer_division")
	var seconds: int = (resource.prismatic_dye_until_ms - now_ms) / 1000
	return maxi(0, seconds)


## The dye id that should be RENDERED for [param resource] right now — 0 once it
## has lapsed. Always read through this rather than off the field directly, so an
## expired dye can never paint a body just because the stamp is still stored.
static func visible_id(resource: PlayerResource) -> int:
	return resource.prismatic_dye_id if is_active(resource) else 0


## Server: stamp a fresh dye on [param resource] and return the id chosen.
## Re-dyeing REROLLS the colour and restarts the clock — the good is a recolour,
## and getting the same shade twice with a longer timer would read as a dud.
static func apply(resource: PlayerResource) -> int:
	if resource == null:
		return 0
	var id: int = roll()
	if id <= 0:
		return 0
	resource.prismatic_dye_id = id
	resource.prismatic_dye_until_ms = (
		int(Time.get_unix_time_from_system() * 1000.0) + DURATION_S * 1000
	)
	return id


## Server: clear a lapsed dye off [param resource]. Returns true if anything
## changed, so the caller knows whether it has to re-broadcast.
static func clear_if_expired(resource: PlayerResource) -> bool:
	if resource == null or resource.prismatic_dye_id <= 0 or is_active(resource):
		return false
	resource.prismatic_dye_id = 0
	resource.prismatic_dye_until_ms = 0
	return true
