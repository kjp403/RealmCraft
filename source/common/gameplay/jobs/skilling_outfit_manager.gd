class_name SkillingOutfitManager
## Skilling Outfits: four themed 4-piece sets that pay SKILL UTILITY, not combat
## stats. Static service (no autoload) for the same reason [SkillingEvents] is —
## the consumers are `mineable_node.gd` and the craft handler, which headless
## `-s` tools load, and an autoload identifier does not resolve there.
##
## WHY NOT JUST PUT THE BONUSES ON THE GEAR'S base_modifiers
## The equipment ledger already applies [StatModifier]s automatically, and
## [Stat] already carries GATHER_YIELD / GATHER_SPEED / GATHER_XP. That path is
## one line of content and zero lines of code — but those stats are GLOBAL. A
## Woodcutter hat authored that way speeds up mining, fishing and herb picking
## too, which is exactly the "generic +4 Move Speed" problem in a new coat. Set
## bonuses are resolved HERE instead, scoped to the acting skill, and the gear
## carries no base_modifiers at all. The legacy `items/gears/skilling/*.tres`
## wardrobe keeps using the global stats — it is unthemed clothing, not a set.
##
## WHY 4 PIECES MEANS helmet/torso/boot/amulet
## This game has three armour slots (helmet, torso, boot) — there is no legs
## slot, unlike the OSRS outfits these are modelled on. A fourth piece therefore
## has to take a jewellery slot, and amulet is the least contested: a player
## gathering is not wearing a combat amulet for the stats, whereas rings and
## relics are upgrade chains people keep equipped permanently. If a legs slot is
## ever added, move the charm to it and nothing else here changes.
##
## SERVER-AUTHORITATIVE. Every read walks the server's equipped_items; a client
## has no business computing its own yield chance.

## The utility a set piece can pay. Deliberately NOT [Stat] entries — these are
## resolved per-skill at the point of use, not summed into a global stat block.
enum Bonus {
	## Extra resource on a successful gather (extra log / double ore / better catch).
	YIELD,
	## Gather cooldown reduction — "faster chop ticks".
	SPEED,
	## Chance a successful gather does NOT spend one of the node's per-player
	## charges. Mining's "durability bypass".
	DURABILITY_BYPASS,
	## Chance a caught fish arrives already cooked.
	PRECOOK,
	## Chance a crafting ingredient survives being consumed. Herblore brewing.
	PRESERVE,
}

## Absolute ceilings, applied after piece + set bonuses. Nothing here may push a
## roll to certainty: a 100% durability bypass is an infinite node, and a 100%
## preserve is free potions. Yield is kept in line with
## [member JobPerks.abs_max_bonus_yield_chance] so outfit + perks + tool together
## cannot exceed what the perk tree alone is allowed to reach.
const CAPS: Dictionary[Bonus, float] = {
	Bonus.YIELD: 0.50,
	Bonus.SPEED: 0.30,
	Bonus.DURABILITY_BYPASS: 0.35,
	Bonus.PRECOOK: 0.25,
	Bonus.PRESERVE: 0.40,
}

## The four sets, keyed by set slug.
##
##   skill   — [JobRegistry] slug this set pays out on. Slug, not display name:
##             Crafting is &"outfitting" and Farming is &"harvesting", and
##             authoring the label gives a set that silently never procs.
##   pieces  — the four item slugs, one per slot. Order is cosmetic only;
##             membership is what counts.
##   aura    — cosmetic registry slug applied while all four are worn.
##   piece   — bonus paid PER PIECE WORN (1-2% each, so 4-6% for a partial set).
##   full    — added ON TOP when all four are worn. This is the reason to chase
##             the last piece rather than stopping at three.
const SETS: Dictionary[StringName, Dictionary] = {
	&"woodcutter": {
		"name": "Lumberjack",
		"skill": &"woodcutting",
		"aura": &"aura_verdant",
		"pieces": [
			&"outfit_woodcutter_hat",
			&"outfit_woodcutter_tunic",
			&"outfit_woodcutter_boots",
			&"outfit_woodcutter_charm",
		],
		"piece": {Bonus.YIELD: 0.015, Bonus.SPEED: 0.010},
		"full": {Bonus.YIELD: 0.10, Bonus.SPEED: 0.05},
	},
	&"miner": {
		"name": "Prospector",
		"skill": &"mining",
		"aura": &"aura_gold",
		"pieces": [
			&"outfit_miner_hat",
			&"outfit_miner_tunic",
			&"outfit_miner_boots",
			&"outfit_miner_charm",
		],
		"piece": {Bonus.YIELD: 0.015, Bonus.DURABILITY_BYPASS: 0.020},
		"full": {Bonus.YIELD: 0.10, Bonus.DURABILITY_BYPASS: 0.10},
	},
	&"fisherman": {
		"name": "Angler",
		"skill": &"fishing",
		"aura": &"aura_emberfrost",
		"pieces": [
			&"outfit_fisher_hat",
			&"outfit_fisher_tunic",
			&"outfit_fisher_boots",
			&"outfit_fisher_charm",
		],
		"piece": {Bonus.YIELD: 0.015, Bonus.PRECOOK: 0.010},
		"full": {Bonus.YIELD: 0.10, Bonus.PRECOOK: 0.06},
	},
	&"alchemist": {
		"name": "Herbalist",
		"skill": &"herblore",
		"aura": &"aura_toxic",
		"pieces": [
			&"outfit_alchemist_hat",
			&"outfit_alchemist_tunic",
			&"outfit_alchemist_boots",
			&"outfit_alchemist_charm",
		],
		"piece": {Bonus.PRESERVE: 0.020},
		"full": {Bonus.PRESERVE: 0.10},
	},
}

const PIECES_PER_SET: int = 4

## slug -> set slug, built once from [constant SETS]. Piece lookups happen on
## every gather, so this avoids re-walking four arrays per swing.
static var _piece_index: Dictionary[StringName, StringName] = {}
## item id -> piece slug, resolved lazily through the content registry. Equipped
## items are known by id; the set table is authored in slugs.
static var _id_to_piece: Dictionary[int, StringName] = {}
static var _index_built: bool = false


# --- Public API --------------------------------------------------------------

## Total bonus of [param kind] for [param skill], as a 0..1 chance/fraction.
## Returns 0.0 when the player wears nothing relevant, so callers can add it
## unconditionally.
##
## Only the set whose `skill` matches contributes — a full Prospector kit pays
## nothing while you are chopping, which is the entire point of these being
## outfits rather than another slab of global gather stats.
static func bonus_for(player: Player, skill: StringName, kind: Bonus) -> float:
	if player == null or skill == &"":
		return 0.0
	var set_slug: StringName = set_for_skill(skill)
	if set_slug == &"":
		return 0.0
	return bonus_from_worn(set_slug, pieces_worn(player, set_slug), kind)


## The bonus curve itself, with no Player involved: [param worn] pieces of
## [param set_slug] pay this much of [param kind].
##
## Split out from [method bonus_for] so the tuning can be tested directly —
## constructing a Player means constructing a Character, which drags in the
## client autoloads and cannot be done in a headless `-s` verify tool.
static func bonus_from_worn(set_slug: StringName, worn: int, kind: Bonus) -> float:
	if not SETS.has(set_slug) or worn <= 0:
		return 0.0
	var def: Dictionary = SETS[set_slug]
	var total: float = float((def["piece"] as Dictionary).get(kind, 0.0)) * float(mini(worn, PIECES_PER_SET))
	if worn >= PIECES_PER_SET:
		total += float((def["full"] as Dictionary).get(kind, 0.0))
	return clampf(total, 0.0, float(CAPS.get(kind, 1.0)))


## Convenience for the common "does this proc?" call. Rolls once against
## [method bonus_for]; a zero bonus never rolls, so this is cheap to call on
## every gather.
static func rolls(player: Player, skill: StringName, kind: Bonus) -> bool:
	var chance: float = bonus_for(player, skill, kind)
	return chance > 0.0 and randf() < chance


## How many pieces of [param set_slug] the player currently has equipped (0-4).
static func pieces_worn(player: Player, set_slug: StringName) -> int:
	if player == null or not SETS.has(set_slug):
		return 0
	var equipped: Dictionary = _equipped_items(player)
	if equipped.is_empty():
		return 0
	_build_index()
	var count: int = 0
	var seen: Dictionary[StringName, bool] = {}
	for slot: Variant in equipped:
		var piece: StringName = _piece_slug_of(equipped[slot])
		if piece == &"" or seen.has(piece):
			continue
		if _piece_index.get(piece, &"") != set_slug:
			continue
		# Dedupe by piece, not by slot: two slots holding the same piece slug must
		# not count twice toward a set bonus.
		seen[piece] = true
		count += 1
	return mini(count, PIECES_PER_SET)


## The set slug that pays out on [param skill], or &"" when that skill has no
## outfit. Five of the nine skilling jobs (smithing, cooking, outfitting,
## fletching, harvesting) have no set authored yet — callers must treat &"" as
## "no outfit content", not as an error.
static func set_for_skill(skill: StringName) -> StringName:
	for set_slug: StringName in SETS:
		if StringName(str((SETS[set_slug] as Dictionary).get("skill", &""))) == skill:
			return set_slug
	return &""


## Every set the player currently wears in full. Usually 0 or 1 — the sets share
## the same four slots, so wearing two complete sets is impossible.
static func completed_sets(player: Player) -> Array[StringName]:
	var out: Array[StringName] = []
	for set_slug: StringName in SETS:
		if pieces_worn(player, set_slug) >= PIECES_PER_SET:
			out.append(set_slug)
	return out


## Cosmetic id of the aura for the player's completed set, or 0 for none.
##
## This is deliberately a SEPARATE channel from [member PlayerResource.cosmetic_id]
## — see Character.skilling_aura_id. Writing a set aura into the normal cosmetic
## slot would silently unequip whatever the player actually chose to wear, and
## cosmetics are the paid VFX line (docs: Horizon Collection), so a free set
## bonus must never overwrite one.
static func aura_id_for(player: Player) -> int:
	var sets: Array[StringName] = completed_sets(player)
	if sets.is_empty():
		return 0
	var slug: StringName = StringName(str((SETS[sets[0]] as Dictionary).get("aura", &"")))
	if slug == &"":
		return 0
	return ContentRegistryHub.id_from_slug(&"cosmetics", slug)


## Refresh the player's set aura after any equipment change. Safe to call on a
## client or for a set that is not complete — both resolve to "no aura".
static func refresh_aura(player: Player) -> void:
	if player == null or player.multiplayer == null or not player.multiplayer.is_server():
		return
	var aura: int = aura_id_for(player)
	if player.skilling_aura_id == aura:
		return
	player.skilling_aura_id = aura
	if player.state_synchronizer != null:
		player.state_synchronizer.set_by_path(^":skilling_aura_id", aura)


## Tooltip / UI lines for one set at [param worn] pieces. Used by the outfit
## panel and the item tooltip so the numbers players read come from the same
## table the gather roll uses, and cannot drift from it.
static func describe(set_slug: StringName, worn: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if not SETS.has(set_slug):
		return out
	var def: Dictionary = SETS[set_slug]
	var complete: bool = worn >= PIECES_PER_SET
	for kind: Bonus in (def["piece"] as Dictionary):
		var per: float = float((def["piece"] as Dictionary)[kind])
		out.append("%s +%.1f%% per piece (%+.1f%% worn)" % [
			bonus_label(kind), per * 100.0, per * float(worn) * 100.0
		])
	for kind: Bonus in (def["full"] as Dictionary):
		var full: float = float((def["full"] as Dictionary)[kind])
		out.append("%s Set: %s +%.0f%%%s" % [
			"[on]" if complete else "[%d/4]" % worn,
			bonus_label(kind), full * 100.0,
			"" if complete else " (locked)",
		])
	return out


static func bonus_label(kind: Bonus) -> String:
	match kind:
		Bonus.YIELD: return "Bonus yield"
		Bonus.SPEED: return "Gather speed"
		Bonus.DURABILITY_BYPASS: return "Node preserved"
		Bonus.PRECOOK: return "Catch arrives cooked"
		Bonus.PRESERVE: return "Ingredient preserved"
	return "?"


## The cooked counterpart of a raw fish, or null when there is none.
##
## Inverts [constant ChestResource.COOKED_FISH_TO_RAW] rather than keeping a
## second table, so the two can never disagree about which fish can be cooked.
##
## ECONOMY NOTE: a catch that arrives cooked skips Cooking XP entirely, which is
## the exact thing that COOKED_FISH_TO_RAW exists to prevent for chest fish. The
## Angler set is therefore capped low (CAPS[PRECOOK]) and only pays on the fish
## the player caught themselves. If Cooking training measurably suffers, the
## intended lever is to also award partial Cooking XP on a precooked catch, NOT
## to raise the cap.
static func precooked_for(raw_slug: StringName) -> Item:
	var cooked_slug: StringName = precooked_slug_for(raw_slug)
	if cooked_slug == &"":
		return null
	return ContentRegistryHub.load_by_slug(&"items", cooked_slug) as Item


## The cooked slug for a raw fish, or &"" when there is none.
##
## Split from [method precooked_for] because cooked fish are [ConsumableItem]s,
## and those reach ClientState — so they load as null in a headless `-s` verify
## run even though they are fine on a real server. Keeping the MAPPING resolvable
## without loading the resource is what makes the fish table testable at all.
static func precooked_slug_for(raw_slug: StringName) -> StringName:
	if raw_slug == &"":
		return &""
	if _raw_to_cooked.is_empty():
		for cooked: Variant in ChestResource.COOKED_FISH_TO_RAW:
			_raw_to_cooked[StringName(str(ChestResource.COOKED_FISH_TO_RAW[cooked]))] = \
				StringName(str(cooked))
	return _raw_to_cooked.get(raw_slug, &"")


## raw slug -> cooked slug, built lazily from ChestResource's table.
static var _raw_to_cooked: Dictionary[StringName, StringName] = {}


## All piece slugs across every set, for the chest rewarder's rare roll and for
## content validation.
static func all_piece_slugs() -> Array[StringName]:
	var out: Array[StringName] = []
	for set_slug: StringName in SETS:
		for slug: Variant in (SETS[set_slug] as Dictionary)["pieces"]:
			out.append(StringName(str(slug)))
	return out


## Piece slugs of one set.
static func pieces_of(set_slug: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if not SETS.has(set_slug):
		return out
	for slug: Variant in (SETS[set_slug] as Dictionary)["pieces"]:
		out.append(StringName(str(slug)))
	return out


# --- Ownership (duplicate protection) ----------------------------------------

## True if [param resource] is STORING [param slug] anywhere the player can get
## it back from: any of the three bags, the personal bank, the Boss Hunt stash,
## or loot still staged in the chest-claim window.
##
## The staged list matters as much as the bag. Two chests opened in one sitting
## must not both roll "you are missing the hat" before either has been claimed,
## or the protection leaks a duplicate anyway.
##
## Takes the resource rather than the Player so the headless verify gate can
## exercise it — constructing a Player pulls in the client autoloads, which do
## not exist under `-s`.
static func stores_piece(resource: PlayerResource, slug: StringName) -> bool:
	if resource == null:
		return false
	var id: int = ContentRegistryHub.id_from_slug(&"items", slug)
	if id <= 0:
		# An unstamped piece can be neither owned nor granted. Reporting it as
		# owned would drop it out of the missing pool and pay a fallback gem
		# forever; validate() is what surfaces that content gap.
		return false
	if Inventory.has_item(resource.inventory, id):
		return true
	if Inventory.has_item(resource.bank, id):
		return true
	if PendingChestLoot.count(resource.pending_chest_loot, id) > 0:
		return true
	return PendingChestLoot.count(resource.hunt_chest, id) > 0


## True if the player is WEARING [param slug] right now. Reads the live
## EquipmentComponent first, like every other read here — the persisted map goes
## stale mid-session, and a stale read is exactly how a worn piece would be
## counted as missing and re-dropped.
static func wears_piece(player: Player, slug: StringName) -> bool:
	if player == null:
		return false
	_build_index()
	var equipped: Dictionary = _equipped_items(player)
	for slot: Variant in equipped:
		if _piece_slug_of(equipped[slot]) == slug:
			return true
	return false


## True if the player holds [param slug] anywhere at all — worn, bagged, banked,
## stashed or staged.
static func owns_piece(player: Player, slug: StringName) -> bool:
	if player == null:
		return false
	return stores_piece(player.player_resource, slug) or wears_piece(player, slug)


## Storage-only view of [method missing_pieces]: the same walk with worn gear
## left out. Public so the verify gate can assert the prioritisation without a
## live Player.
static func missing_pieces_in_storage(
	resource: PlayerResource, set_slug: StringName
) -> Array[StringName]:
	var out: Array[StringName] = []
	for slug: StringName in pieces_of(set_slug):
		if not stores_piece(resource, slug):
			out.append(slug)
	return out


## Pieces of [param set_slug] the player does NOT own. The rare chest roll draws
## from THIS rather than from the full set, so a 1-in-1000 hit is always
## progress: a player holding 2 of 4 is guaranteed one of the other 2.
##
## An empty return means the set is already complete and the caller must pay
## something else rather than a duplicate — see SkillingChestRewarder.
static func missing_pieces(player: Player, set_slug: StringName) -> Array[StringName]:
	if player == null:
		return pieces_of(set_slug)
	var out: Array[StringName] = []
	for slug: StringName in pieces_of(set_slug):
		if not owns_piece(player, slug):
			out.append(slug)
	return out


## True when all four pieces are held somewhere. "Owns", not "wears": a set
## sitting in the bank is still collected, and re-dropping it is still a
## duplicate.
static func owns_full_set(player: Player, set_slug: StringName) -> bool:
	return SETS.has(set_slug) and missing_pieces(player, set_slug).is_empty()


## Boot-time content check: every set names a real job and four resolvable
## items. Reports rather than throws — a missing piece makes that set
## uncompletable, which is a content gap worth seeing in the log, not a crash.
## Returns the list of problems (empty = healthy) so a verify tool can assert it.
static func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	for set_slug: StringName in SETS:
		var def: Dictionary = SETS[set_slug]
		var skill: StringName = StringName(str(def.get("skill", &"")))
		if not JobRegistry.has_job(skill):
			problems.append("%s: '%s' is not a registered job" % [set_slug, skill])
		var pieces: Array = def["pieces"]
		if pieces.size() != PIECES_PER_SET:
			problems.append("%s: %d pieces, expected %d" % [set_slug, pieces.size(), PIECES_PER_SET])
		for slug: Variant in pieces:
			if ContentRegistryHub.id_from_slug(&"items", StringName(str(slug))) <= 0:
				problems.append("%s: piece '%s' is not in the items index" % [set_slug, slug])
		var aura: StringName = StringName(str(def.get("aura", &"")))
		if aura != &"" and ContentRegistryHub.id_from_slug(&"cosmetics", aura) <= 0:
			problems.append("%s: aura '%s' is not in the cosmetics index" % [set_slug, aura])
	return problems


# --- internals ---------------------------------------------------------------

## Equipped items keyed by slot. Prefers the live EquipmentComponent (authoritative
## during play) and falls back to the persisted map, so a call made before the
## component has mounted gear still reads correctly.
static func _equipped_items(player: Player) -> Dictionary:
	if player.equipment_component != null:
		return player.equipment_component.equipped_items
	if player.player_resource != null:
		return player.player_resource.equipment
	return {}


## Piece slug for whatever an equipment slot holds — an [Item] or a bare id.
static func _piece_slug_of(entry: Variant) -> StringName:
	if entry is Item:
		return StringName(str((entry as Item).get_meta(&"slug", &"")))
	var id: int = int(entry) if entry is int or entry is float else 0
	if id <= 0:
		return &""
	if _id_to_piece.has(id):
		return _id_to_piece[id]
	return &""


## Build slug->set and id->slug maps once. The id map is resolved through the
## content registry, so it is only as complete as the items index — a piece that
## has not been stamped yet simply never matches (and [method validate] says so).
static func _build_index() -> void:
	if _index_built:
		return
	_index_built = true
	for set_slug: StringName in SETS:
		for slug_v: Variant in (SETS[set_slug] as Dictionary)["pieces"]:
			var slug := StringName(str(slug_v))
			_piece_index[slug] = set_slug
			var id: int = ContentRegistryHub.id_from_slug(&"items", slug)
			if id > 0:
				_id_to_piece[id] = slug
