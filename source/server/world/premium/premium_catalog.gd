class_name PremiumCatalog
## What the Vault actually sells, and for how much.
##
## TOKENS, NOT IDS. An item_id on the wire is a [VaultGrants] token -
## "title:gilded", "skin:10001", "cosmetic:5" - because that is already the
## grammar the entitlement list is stored in. One vocabulary end to end means a
## purchase resolves to the exact string that will be written to granted_vfx,
## with no second mapping to drift.
##
## WHAT IS DELIBERATELY NOT FOR SALE:
##   - SupporterTitles / the VIP contributor ladder. Those are donation-tier
##     rewards; selling them for currency makes the ladder meaningless. They are
##     excluded via [method TitleCatalog.is_vip] - flip that one check to sell them.
##   - SkillMasterTitles. Earned at 99. TitleCatalog's own comment says these must
##     never read as premium; they are not in PREMIUM and so never resolve here.
##
## The master re-derives every price from this same file before it charges, so a
## world running an older build cannot set its own prices - it can only be
## refused. That makes this the single source of truth for what anything costs.

const KIND_TITLE: StringName = &"title"
const KIND_SKIN: StringName = &"skin"
const KIND_COSMETIC: StringName = &"cosmetic"

## PRICES ARE IN ARK COINS. The storefront sells 250 for $2.49 and 1000 for
## $9.99, so a coin is worth roughly a penny and every number below is also a
## price in pence - a 250 dye is about GBP 2.49, a 750 aura about GBP 7.49. Keep
## that in mind when editing: these are real-money prices wearing a coin costume.

## One recolour of one body. NOT a dye you own everywhere - see the note on
## [method _skin_entry]; "Obsidian" bought for Scholar Researcher unlocks exactly
## that pairing and nothing else, which is what makes 250 the right number rather
## than a 16-body bundle price.
const COST_DYE: int = 250

const COST_TRAIL: int = 350

## Unchanged - the brief priced dyes, auras and trails, and said nothing about
## titles. Left where it was rather than guessed at.
const COST_TITLE: int = 500

## EVERY COSMETIC, PRICED BY SLUG. [Cosmetics] has slots, not tiers - there is no
## rarity field anywhere on one - so the band has to be spent somewhere explicit,
## and one table is the only place an editor can see all 26 side by side and
## judge them against each other. Nothing derives from this; change a number and
## that is the whole change.
##
## THE SHAPE OF IT:
##   450  one persistent effect, one hue
##   600  one persistent effect, multi-hue or animated palette
##   750  a named set-piece, or something already gated behind endgame content
##   350  a one-shot - a trail, a flourish, a departure
##
## Persistent effects cost more than one-shots because they are what other
## players actually see: an aura is on screen the whole time you are, a departure
## is on screen for half a second when you leave.
const COSMETIC_COSTS: Dictionary = {
	# --- Auras. Single hue, one idea.
	&"aura_gold": 450,
	&"aura_verdant": 450,
	&"aura_toxic": 450,
	&"aura_blood": 450,
	# Multi-hue / animated palette.
	&"aura_galaxy": 600,
	&"aura_emberfrost": 600,
	&"aura_rainbow": 600,
	# The set-pieces.
	&"aura_solar_eclipse": 750,
	&"aura_runebound_titan": 750,

	# --- Trails. Flat, as briefed: a trail only renders while you are moving, so
	# the elaborate ones are not on screen appreciably more than the plain ones.
	&"trail_blood": 350,
	&"trail_chromatic": 350,
	&"trail_chrono_echo": 350,
	&"trail_galaxy": 350,
	&"trail_gold": 350,
	&"trail_infernal_chasm": 350,
	&"trail_rainbow": 350,
	&"trail_storm": 350,
	&"trail_toxic": 350,

	# --- Halos. Persistent and always in frame above the head, so they price like
	# auras rather than like one-shots - and they rhyme with their aura namesakes,
	# which is the point of having a gold and a galaxy of each.
	&"halo_gold": 450,
	&"halo_galaxy": 600,
	&"halo_rainbow": 600,

	# --- Flourishes. A one-shot on an action. Priced with trails: seen often, but
	# only for a moment at a time.
	&"flourish_rainbow": 350,
	&"flourish_void": 350,

	# --- Departures. A one-shot when you go. The rarest MOMENT of any of these -
	# nobody sees it twice in a row - so it prices with the other one-shots rather
	# than with the persistent effects, however good it looks.
	&"departure_galaxy": 350,
	&"departure_gold": 350,

	# --- Weapon. The only one, and it renders on nothing but an Ascended weapon -
	# so it is already gated behind endgame content and is worth the ceiling to
	# the players who can actually show it off.
	&"weapon_ascended_radiance": 750,
}

## SLOTS WITH NO TRIGGER, AND THEREFORE NOTHING TO SELL.
##
## Flourishes and death effects are authored as one-shots, and NOTHING IN THE
## GAME FIRES EITHER OF THEM. Search the tree: the only thing that plays a
## flourish or a departure is [CosmeticVfx]'s replay timer, whose own comment
## says it exists "so staff can actually watch them in the vault". There is no
## ability hook, no death hook, no logout hook.
##
## So a player who bought one would pay real money for something that renders in
## the wardrobe preview and nowhere else, ever. They stay priced above - the
## numbers are right and the moment these get a trigger they should go on sale -
## but they are held out of the roster until something can actually play them.
##
## Remove a slot from here the same day it gets a trigger, not before.
const SLOTS_WITHOUT_A_TRIGGER: Array[StringName] = [&"flourish", &"departure"]

## Fallback by slot, for a cosmetic added later that nobody has priced. Every
## cosmetic that exists TODAY is named above; this only catches new content.
const SLOT_COSTS: Dictionary = {
	&"aura": 450,
	&"trail": 350,
	&"halo": 450,
	&"flourish": 350,
	&"departure": 350,
	&"weapon": 750,
}

## Last-resort price for a cosmetic in a slot nobody has priced - a new slot
## added later, say. Deliberately at the ceiling: a new cosmetic appearing in the
## shop too expensive is a complaint, appearing too cheap is lost revenue nobody
## notices.
const COST_COSMETIC_FALLBACK: int = 750

## Per-token overrides, for a single item that should not sit at its group's
## price. Keyed by the same token grammar as everything else, so an entry here
## reads as "skin:140001 costs X" and beats every rule above.
const COST_OVERRIDES: Dictionary = {}


## Resolve a client-sent token to what it costs and what it grants.
## Returns {} for anything not for sale - which is the security boundary, since
## the only ids that resolve are ones this file put in the roster.
static func resolve(item_id: String) -> Dictionary:
	var token: String = item_id.strip_edges()
	if token.is_empty():
		return {}

	if token.begins_with(VaultGrants.TITLE_PREFIX):
		return _title_entry_by_title(token.substr(VaultGrants.TITLE_PREFIX.length()))
	if token.begins_with(VaultGrants.SKIN_PREFIX):
		return _skin_entry(int(token.substr(VaultGrants.SKIN_PREFIX.length())))
	if token.begins_with(VaultGrants.COSMETIC_PREFIX):
		return _cosmetic_entry(int(token.substr(VaultGrants.COSMETIC_PREFIX.length())))
	return {}


## Everything for sale, for the Vault UI. Costs come from here and never from the
## client, which only ever echoes a token back.
static func roster() -> Array:
	var out: Array = []
	for title_row: Dictionary in TitleCatalog.premium_roster():
		var title_entry: Dictionary = _title_entry_by_slug(str(title_row.get("slug", "")))
		if not title_entry.is_empty():
			out.append(title_entry)
	for skin_row: Dictionary in VaultSkins.roster():
		var skin_entry: Dictionary = _skin_entry(int(skin_row.get("id", 0)))
		if not skin_entry.is_empty():
			out.append(skin_entry)
	for cosmetic_id: int in Cosmetics.ids():
		var cosmetic_entry: Dictionary = _cosmetic_entry(cosmetic_id)
		if not cosmetic_entry.is_empty():
			out.append(cosmetic_entry)
	return out


## Does this character already hold the entitlement? Checked before charging, so
## a double-click or a stale UI cannot bill twice for the same thing.
static func owns(player: PlayerResource, entry: Dictionary) -> bool:
	if player == null or entry.is_empty():
		return false
	match StringName(str(entry.get("kind", ""))):
		KIND_TITLE:
			return VaultGrants.has_title(player, str(entry.get("title", "")))
		KIND_SKIN:
			return VaultGrants.has_skin(player, int(entry.get("vault_id", 0)))
		KIND_COSMETIC:
			return VaultGrants.has_cosmetic(player, int(entry.get("cosmetic_id", 0)))
	return false


## Write the entitlement. Returns false when nothing changed, which the caller
## treats as a paid-for no-op worth logging rather than a silent success.
static func grant(player: PlayerResource, entry: Dictionary) -> bool:
	if player == null or entry.is_empty():
		return false
	match StringName(str(entry.get("kind", ""))):
		KIND_TITLE:
			var title: String = str(entry.get("title", ""))
			# Unlock it as well as granting it: the grant is what survives the
			# strip, titles_unlocked is what the equip path reads.
			var unlocked: PackedStringArray = player.titles_unlocked.duplicate()
			if not unlocked.has(title):
				unlocked.append(title)
				player.titles_unlocked = unlocked
			return VaultGrants.grant_title(player, title)
		KIND_SKIN:
			return VaultGrants.grant_skin(player, int(entry.get("vault_id", 0)))
		KIND_COSMETIC:
			return VaultGrants.grant_cosmetic(player, int(entry.get("cosmetic_id", 0)))
	return false


static func _cost(token: String, fallback: int) -> int:
	return int(COST_OVERRIDES.get(token, fallback))


## By PREMIUM slug ("gilded"), for building the roster.
static func _title_entry_by_slug(slug: String) -> Dictionary:
	var row: Dictionary = TitleCatalog.premium_entry(slug)
	if row.is_empty():
		return {}
	return _build_title_entry(str(row.get("name", "")), str(row.get("blurb", "")))


## By display name, for resolving a token back. Tokens are lower-cased on the way
## in (VaultGrants.title_token), so this has to canonicalise before it can match.
static func _title_entry_by_title(raw_title: String) -> Dictionary:
	var title: String = TitleCatalog.canonical_name(raw_title)
	if title.is_empty() or not TitleCatalog.is_premium_name(title):
		return {}
	var blurb: String = ""
	for row: Dictionary in TitleCatalog.premium_roster():
		if TitleCatalog.canonical_name(str(row.get("name", ""))) == title:
			blurb = str(row.get("blurb", ""))
			break
	return _build_title_entry(title, blurb)


static func _build_title_entry(raw_name: String, blurb: String) -> Dictionary:
	var title: String = TitleCatalog.canonical_name(raw_name)
	if title.is_empty():
		return {}
	# THE DONATION LADDER IS vip_tier, NOT vip. `vip` is a VFX-treatment flag and
	# is true for ordinary shop titles (Starforged, Sovereign, Voidtouched,
	# Eclipse, Wyrmblood) while being FALSE on two real rungs (Silver and Golden
	# Contributor). Keying off it both withheld five sellable titles and put two
	# donation rungs on the shelf. `vip_tier` is the four rungs and nothing else -
	# it is what TitleCatalog.vip_tier_slugs() derives the ladder from.
	if not String(TitleCatalog.vip_tier(title)).is_empty():
		return {} # donation ladder - not sold, see the class docs
	var token: String = VaultGrants.title_token(title)
	return {
		"item_id": token,
		"kind": KIND_TITLE,
		"title": title,
		"label": title,
		"blurb": blurb,
		"cost": _cost(token, COST_TITLE),
	}


## ONE ROW PER (BODY, DYE) PAIR, AND THAT IS THE PRODUCT.
##
## vault_id is `style * VaultSkins.STRIDE + skin_id`, so "Obsidian Scholar
## Researcher" and "Obsidian Goblin" are different ids, different tokens,
## different grants and different purchases. Buying one cannot unlock the other:
## VaultGrants.has_skin() tests the exact packed id, and vault_skins.equip
## re-checks it per equip. That is what keeps 250 a sane price - it buys one
## look, not a dye applied across all 36 bodies.
static func _skin_entry(vault_id: int) -> Dictionary:
	if not VaultSkins.is_valid(vault_id):
		return {}
	var token: String = VaultGrants.skin_token(vault_id)
	return {
		"item_id": token,
		"kind": KIND_SKIN,
		"vault_id": vault_id,
		"label": VaultSkins.display_name(vault_id),
		"blurb": VaultSkins.blurb(vault_id),
		"cost": _cost(token, COST_DYE),
	}


static func _cosmetic_entry(cosmetic_id: int) -> Dictionary:
	# Cosmetics.is_valid(0) is TRUE by design - 0 is how a cosmetic is cleared, so
	# the equip path has to accept it. It is not a thing that can be SOLD, and
	# without this guard "cosmetic:0" resolves to a priced row that nobody can
	# ever own (has_cosmetic short-circuits on 0), so it bills on every click.
	if cosmetic_id <= 0 or not Cosmetics.is_valid(cosmetic_id):
		return {}
	# Checked in resolve() as well as roster(), so a crafted token cannot buy one
	# either - being absent from the shop list is not the same as being refused.
	if SLOTS_WITHOUT_A_TRIGGER.has(Cosmetics.slot_of(cosmetic_id)):
		return {}
	var token: String = VaultGrants.cosmetic_token(cosmetic_id)
	return {
		"item_id": token,
		"kind": KIND_COSMETIC,
		"cosmetic_id": cosmetic_id,
		"slot": String(Cosmetics.slot_of(cosmetic_id)),
		"label": Cosmetics.display_name(cosmetic_id),
		"blurb": "",
		"cost": _cost(token, _cosmetic_base_cost(cosmetic_id)),
	}


## Price before any per-token override: the aura table first (it is per-item),
## then the slot table. Looked up by SLUG rather than by id, because ids come
## from the content registry and shift when content is added - a table keyed by
## id would silently re-price every aura the next time a cosmetic is inserted.
static func _cosmetic_base_cost(cosmetic_id: int) -> int:
	var slug: StringName = Cosmetics.slug(cosmetic_id)
	if COSMETIC_COSTS.has(slug):
		return int(COSMETIC_COSTS[slug])
	var slot: StringName = Cosmetics.slot_of(cosmetic_id)
	return int(SLOT_COSTS.get(slot, COST_COSMETIC_FALLBACK))
