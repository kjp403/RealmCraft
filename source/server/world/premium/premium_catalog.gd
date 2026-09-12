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
## PRICES ARE PLACEHOLDERS. The numbers below are structure, not economy - they
## need real values before this ships. The backend is expected to re-validate the
## cost it is sent and reject a mismatch rather than trust us.

const KIND_TITLE: StringName = &"title"
const KIND_SKIN: StringName = &"skin"
const KIND_COSMETIC: StringName = &"cosmetic"

const COST_TITLE: int = 500
const COST_SKIN: int = 750
const COST_COSMETIC: int = 1000

## Per-token overrides for anything that should not sit at its kind's default.
## Keyed by the same token grammar as everything else.
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
		"cost": _cost(token, COST_SKIN),
	}


static func _cosmetic_entry(cosmetic_id: int) -> Dictionary:
	# Cosmetics.is_valid(0) is TRUE by design - 0 is how a cosmetic is cleared, so
	# the equip path has to accept it. It is not a thing that can be SOLD, and
	# without this guard "cosmetic:0" resolves to a priced row that nobody can
	# ever own (has_cosmetic short-circuits on 0), so it bills on every click.
	if cosmetic_id <= 0 or not Cosmetics.is_valid(cosmetic_id):
		return {}
	var token: String = VaultGrants.cosmetic_token(cosmetic_id)
	return {
		"item_id": token,
		"kind": KIND_COSMETIC,
		"cosmetic_id": cosmetic_id,
		"label": Cosmetics.display_name(cosmetic_id),
		"blurb": "",
		"cost": _cost(token, COST_COSMETIC),
	}
