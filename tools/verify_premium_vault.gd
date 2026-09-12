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
	failures += _check_prices()

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


## Phase 1 pricing. Asserted rather than eyeballed because these are real-money
## prices: a dye that silently costs 750 is a GBP 5 overcharge on every sale.
func _check_prices() -> int:
	var failures: int = 0
	var by_kind: Dictionary = {}
	for entry: Dictionary in PremiumCatalog.roster():
		var kind: String = str(entry.get("kind", ""))
		if not by_kind.has(kind):
			by_kind[kind] = []
		(by_kind[kind] as Array).append(entry)

	# Every dye is 250, and there are no exceptions hiding in the 576.
	for entry: Dictionary in by_kind.get("skin", []):
		if int(entry.get("cost", 0)) != PremiumCatalog.COST_DYE:
			push_error("dye not %d: %s = %d" % [
				PremiumCatalog.COST_DYE, entry.get("item_id"), entry.get("cost")
			])
			failures += 1
			break

	var auras: int = 0
	var trails: int = 0
	for entry: Dictionary in by_kind.get("cosmetic", []):
		var slot: String = str(entry.get("slot", ""))
		var cost: int = int(entry.get("cost", 0))
		if slot == "aura":
			auras += 1
			if cost < 450 or cost > 750:
				push_error("aura outside 450-750: %s = %d" % [entry.get("label"), cost])
				failures += 1
		elif slot == "trail":
			trails += 1
			if cost != PremiumCatalog.COST_TRAIL:
				push_error("trail not %d: %s = %d" % [
					PremiumCatalog.COST_TRAIL, entry.get("label"), cost
				])
				failures += 1
		if cost <= 0:
			push_error("cosmetic has no price: %s" % entry.get("item_id"))
			failures += 1

	print("prices: %d dyes @ %d, %d auras 450-750, %d trails @ %d" % [
		(by_kind.get("skin", []) as Array).size(), PremiumCatalog.COST_DYE,
		auras, trails, PremiumCatalog.COST_TRAIL
	])

	# Every entry in the table must exist, or a rename silently drops that
	# cosmetic back to the fallback price with nothing to notice it.
	for slug: StringName in PremiumCatalog.COSMETIC_COSTS:
		if ContentRegistryHub.id_from_slug(&"cosmetics", slug) <= 0:
			push_error("COSMETIC_COSTS names a cosmetic that does not exist: %s" % slug)
			failures += 1

	# And the reverse: every cosmetic in the game must be NAMED, not silently
	# inheriting a slot fallback. The fallback exists for content added later; a
	# gap today means something shipped at a price nobody actually chose.
	for cosmetic_id: int in Cosmetics.ids():
		var cosmetic_slug: StringName = Cosmetics.slug(cosmetic_id)
		if not PremiumCatalog.COSMETIC_COSTS.has(cosmetic_slug):
			push_error("cosmetic has no explicit price: %s" % cosmetic_slug)
			failures += 1

	# Dyes are per (body, dye) pair. Buying one must not imply another - this is
	# the property that makes 250 a fair price rather than a 16-body bundle.
	var probe: PlayerResource = PlayerResource.new()
	var a: int = VaultSkins.pack(VaultSkins.base_skin_id(10001), VaultSkins.STYLE_OBSIDIAN)
	var b: int = VaultSkins.pack(VaultSkins.base_skin_id(10001), VaultSkins.STYLE_GOLD)
	VaultGrants.grant_skin(probe, a)
	if not VaultGrants.has_skin(probe, a):
		push_error("granted dye not held")
		failures += 1
	if VaultGrants.has_skin(probe, b):
		push_error("buying one dye unlocked another - dyes are NOT skin-specific")
		failures += 1
	return failures
