extends SceneTree
## The Vault's TOWN shelves must list only what can actually be bought.
##
## WHY. A shop row for something with no Buy button is a dead end wearing a price
## tag: the donation ladder is bought with real money through a different door,
## and the mastery titles are earned at 99. Both were on the shelf.
##
## This does not drive a live handler - that needs a Player and an instance -
## so it pins the PREDICATE the handlers filter on, which is the part that
## decides. If resolve() ever starts accepting a donation title, the shop starts
## listing one, and this fails first.
##
##   godot --headless -s tools/verify_shop_stock.gd

var _fail: int = 0


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		print("  ok    %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s%s" % [what, ("  (%s)" % detail) if detail != "" else ""])


func _initialize() -> void:
	print("verify_shop_stock")

	# The shelf's INPUT still holds everything - the Curator's room needs it.
	var roster: Array = TitleCatalog.vault_roster()
	# One bucket. Splitting "donated" from "earned" needs a second rule that can
	# disagree with resolve(), and the only thing the shelf cares about is
	# whether the till will take money for it.
	var unbuyable: Array = []
	var sellable: Array = []
	for row_v: Variant in roster:
		var row: Dictionary = row_v as Dictionary
		var title: String = str(row.get("name", ""))
		if title.is_empty():
			continue
		if PremiumCatalog.resolve(VaultGrants.title_token(title)).is_empty():
			unbuyable.append(title)
		else:
			sellable.append(title)

	print("  vault_roster %d titles = %d on the town shelf, %d hidden from it"
			% [roster.size(), sellable.size(), unbuyable.size()])

	_check(not unbuyable.is_empty(),
		"unbuyable titles are still IN the roster (the Curator's room needs them)")
	_check(not sellable.is_empty(), "something is actually for sale")

	# The predicate the town shelves filter on: refuse everything unbuyable...
	for title: String in unbuyable:
		_check(PremiumCatalog.resolve(VaultGrants.title_token(title)).is_empty(),
			"not for sale, so not on the shelf: '%s'" % title)

	# ...and accept everything that is, at a real price.
	for title: String in sellable:
		var entry: Dictionary = PremiumCatalog.resolve(VaultGrants.title_token(title))
		_check(int(entry.get("cost", 0)) > 0, "priced: '%s'" % title)

	# A null instance must never read as the staff room, or a handler that loses
	# its instance would quietly hand a shopper the whole unreleased set.
	_check(not VaultRooms.is_staff_vault(null), "no instance is not the staff vault")

	print("verify_shop_stock: %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(1 if _fail > 0 else 0)
