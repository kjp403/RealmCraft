extends SceneTree
## Loads every server-side script in the premium Vault purchase path and exercises
## the pure parts of the catalog.
##
## WHY THIS EXISTS. Data request handlers are load()ed lazily on the FIRST request
## for their type, so a parse or type error in one of them is invisible until a
## player clicks the button - and then it answers "handler_load_failed" with
## nothing in the log explaining why. This turns that into a build-time failure.
##
## Client scripts are deliberately NOT loaded here: a `-s` run has no autoloads,
## so anything referencing Client / ClientState fails for reasons that have
## nothing to do with this change. The import pass covers those.

const SCRIPTS: PackedStringArray = [
	"res://source/server/world/premium/premium_api.gd",
	"res://source/server/world/premium/premium_catalog.gd",
	"res://source/server/world/components/data_request_handlers/vault.catalog.gd",
	"res://source/server/world/components/data_request_handlers/vault.balance.gd",
	"res://source/server/world/components/data_request_handlers/vault.purchase.gd",
	"res://source/server/world/components/data_request_handlers/titles.equip.gd",
	"res://source/server/world/components/data_request_handlers/vault_skins.equip.gd",
	"res://source/server/world/components/data_request_handlers/cosmetics.equip.gd",
	"res://source/server/world/components/chat_command/command_permissions.gd",
	"res://source/common/gameplay/characters/player/vault_grants.gd",
]


func _init() -> void:
	var failures: int = 0

	for path: String in SCRIPTS:
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate() and not script.has_source_code():
			push_error("FAILED TO LOAD %s" % path)
			failures += 1
			continue
		print("  ok  ", path)

	print("")
	failures += _check_tokens()
	failures += _check_catalog()

	print("")
	if failures == 0:
		print("verify_premium_vault: PASS")
	else:
		print("verify_premium_vault: FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)


## The token grammar is the contract between the catalog, the grant list and the
## strip. A prefix collision here silently mis-grants.
func _check_tokens() -> int:
	var failures: int = 0
	var title_token: String = VaultGrants.title_token("Gilded")
	var skin_token: String = VaultGrants.skin_token(10001)
	var cosmetic_token: String = VaultGrants.cosmetic_token(5)
	print("tokens: %s | %s | %s" % [title_token, skin_token, cosmetic_token])

	if title_token != "title:gilded":
		push_error("title_token wrong: %s" % title_token)
		failures += 1
	if skin_token != "skin:10001":
		push_error("skin_token wrong: %s" % skin_token)
		failures += 1
	if cosmetic_token != "cosmetic:5":
		push_error("cosmetic_token wrong: %s" % cosmetic_token)
		failures += 1

	# No prefix may be a prefix of another, or resolve() routes to the wrong kind.
	var prefixes: PackedStringArray = [
		VaultGrants.TITLE_PREFIX, VaultGrants.SKIN_PREFIX, VaultGrants.COSMETIC_PREFIX
	]
	for a: String in prefixes:
		for b: String in prefixes:
			if a != b and a.begins_with(b):
				push_error("prefix collision: '%s' starts with '%s'" % [a, b])
				failures += 1
	return failures


## Every roster row must resolve back to itself, and nothing on the donation
## ladder may appear at all.
func _check_catalog() -> int:
	var failures: int = 0
	var roster: Array = PremiumCatalog.roster()
	var titles: int = 0
	var skins: int = 0
	var cosmetics: int = 0

	for entry: Dictionary in roster:
		var item_id: String = str(entry.get("item_id", ""))
		var round_trip: Dictionary = PremiumCatalog.resolve(item_id)
		if round_trip.is_empty():
			push_error("roster row does not resolve: %s" % item_id)
			failures += 1
			continue
		if str(round_trip.get("item_id", "")) != item_id:
			push_error("round trip changed id: %s -> %s" % [item_id, round_trip.get("item_id", "")])
			failures += 1
		if int(entry.get("cost", 0)) <= 0:
			push_error("row has no cost: %s" % item_id)
			failures += 1
		match StringName(str(entry.get("kind", ""))):
			PremiumCatalog.KIND_TITLE:
				titles += 1
				# vip_tier, not is_vip - see the note in PremiumCatalog. is_vip is
				# a VFX flag that is true for shop titles and false for two of the
				# four real rungs, so asserting on it tests the wrong thing.
				if not String(TitleCatalog.vip_tier(str(entry.get("title", "")))).is_empty():
					push_error("donation-ladder title is for sale: %s" % item_id)
					failures += 1
			PremiumCatalog.KIND_SKIN:
				skins += 1
			PremiumCatalog.KIND_COSMETIC:
				cosmetics += 1

	print("roster: %d rows (%d titles, %d skins, %d cosmetics)"
			% [roster.size(), titles, skins, cosmetics])

	# Junk must resolve to nothing rather than to a free or mispriced entitlement.
	# "cosmetic:0" is the one that actually bit: Cosmetics.is_valid(0) is true
	# because 0 is how a cosmetic is CLEARED, so it priced a row nobody can own.
	for junk: String in ["", "title:", "skin:0", "skin:-1", "cosmetic:0", "nonsense", "title:nope"]:
		if not PremiumCatalog.resolve(junk).is_empty():
			push_error("junk token resolved: '%s'" % junk)
			failures += 1

	# Every rung of the donation ladder must be unreachable by token, not merely
	# absent from the roster - resolve() is what a crafted request hits.
	for slug: String in TitleCatalog.vip_tier_slugs():
		var name: String = TitleCatalog.canonical_name(slug)
		if not PremiumCatalog.resolve(VaultGrants.title_token(name)).is_empty():
			push_error("donation rung is buyable by token: %s" % name)
			failures += 1

	if roster.is_empty():
		push_error("roster is empty - nothing is for sale")
		failures += 1
	return failures
