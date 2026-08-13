class_name Cosmetics
## Thin facade over the `cosmetics` ContentRegistry — the equippable VFX cosmetics
## (auras, trails, halos, flourishes, death effects) sold in the Horizon Collection.
##
## Mirrors [PlayerSkins]: drop a SpriteFrames into cosmetics/frames, rebuild the index
## with tools/build_cosmetic_frames.py, and it is offered everywhere at once with NO
## hardcoded list. The slug prefix carries the slot (&"aura_rainbow" -> &"aura").
##
## OBTAINABILITY (2026-08-12): nothing here is for sale yet. The only way to equip a
## cosmetic is the admin-gated cosmetics.equip handler, which requires admin+ priority
## on EVERY call — see CommandPermissions.STAFF_PROTECT_PRIORITY. There is deliberately
## no price table and no purchase path; when the shop ships, add them here rather than
## loosening the handler gate.


## Slot order is display order in the curator menu, and doubles as the valid-slot set.
const SLOTS: Array[StringName] = [&"aura", &"trail", &"halo", &"flourish", &"departure"]

## Slots that play continuously while equipped. The rest are event effects — the
## preview node replays them on a cycle so they can still be inspected.
const LOOPING_SLOTS: Array[StringName] = [&"aura", &"trail", &"halo"]


## All cosmetic ids, sorted ascending. Empty when the registry is missing (dedicated
## master/gateway servers skip loading it — see ContentRegistryHub._static_init).
static func ids() -> Array[int]:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"cosmetics")
	if registry == null:
		return []
	var out: Array[int] = registry.all_ids()
	out.sort()
	return out


## True when [param cosmetic_id] resolves to a real cosmetic. Server-side anti-cheat:
## stops a client equipping an id that does not exist. 0 means "nothing equipped" and
## is always valid — that is how a cosmetic is cleared.
static func is_valid(cosmetic_id: int) -> bool:
	if cosmetic_id == 0:
		return true
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"cosmetics")
	return registry != null and registry.has_id(cosmetic_id)


## Registry slug (&"aura_rainbow"), or &"" when unknown.
static func slug(cosmetic_id: int) -> StringName:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"cosmetics")
	if registry == null:
		return &""
	return registry.slug_from_id(cosmetic_id)


## Slot for an id, taken from the slug prefix (&"aura_rainbow" -> &"aura").
static func slot_of(cosmetic_id: int) -> StringName:
	var s: String = String(slug(cosmetic_id))
	if s.is_empty():
		return &""
	return StringName(s.get_slice("_", 0))


## True when this cosmetic should play forever while equipped.
static func is_looping(cosmetic_id: int) -> bool:
	return LOOPING_SLOTS.has(slot_of(cosmetic_id))


## Readable name for a cosmetic id ("aura_rainbow" -> "Rainbow"). The slot is shown
## separately in the menu, so it is stripped from the label rather than repeated.
static func display_name(cosmetic_id: int) -> String:
	var s: String = String(slug(cosmetic_id))
	if s.is_empty():
		return ""
	var parts: PackedStringArray = s.split("_", false, 1)
	if parts.size() < 2:
		return s.capitalize()
	return parts[1].capitalize()


## Ids belonging to one slot, ascending.
static func ids_in_slot(slot: StringName) -> Array[int]:
	var out: Array[int] = []
	for id: int in ids():
		if slot_of(id) == slot:
			out.append(id)
	return out


## The SpriteFrames for a cosmetic (null when missing / on a data-only server).
static func frames(cosmetic_id: int) -> SpriteFrames:
	if cosmetic_id == 0:
		return null
	return ContentRegistryHub.load_by_id(&"cosmetics", cosmetic_id) as SpriteFrames
