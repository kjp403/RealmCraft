extends SceneTree
## The MASTER re-derives every premium price before it charges, so the master's
## copy of PremiumCatalog must resolve exactly what the world's does.
##
## WHY THIS EXISTS. It did not, and every dye and every cosmetic in the shop was
## refused with "That is not for sale" while titles sold fine. ContentRegistryHub
## skipped loading its indexes on master and gateway as "pure waste" - true while
## the master only moved rows around, and false the moment it became the price
## authority. PlayerSkins.price and Cosmetics.is_valid both read a registry, so
## on the master they answered "no such thing" for real, purchasable content.
##
## Run under --mode=master-server, which is the whole point: the same assertions
## pass trivially in world mode.
##
##   godot --headless --mode=master-server -s tools/verify_premium_master_catalog.gd

var _fail: int = 0


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		print("  ok    %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s%s" % [what, ("  (%s)" % detail) if detail != "" else ""])


func _initialize() -> void:
	print("verify_premium_master_catalog  (mode: master=%s)"
			% str(GameMode.is_master_server()))
	_check(GameMode.is_master_server(),
		"running as master - otherwise this proves nothing",
		"pass --mode=master-server")

	# One of each kind the shop sells. A skin and a cosmetic both need a content
	# registry to validate; a title does not, which is exactly why titles kept
	# working and hid the fault.
	for token: String in ["title:gilded", "skin:60030", "cosmetic:5"]:
		var entry: Dictionary = PremiumCatalog.resolve(token)
		_check(not entry.is_empty(), "master resolves %s" % token)
		if not entry.is_empty():
			_check(int(entry.get("cost", 0)) > 0,
				"master prices %s" % token, "cost=%d" % int(entry.get("cost", 0)))

	# Junk must still be refused - the fix must not turn resolve into a rubber stamp.
	for junk: String in ["skin:0", "skin:999999", "cosmetic:0", "title:nope", ""]:
		_check(PremiumCatalog.resolve(junk).is_empty(), "master refuses '%s'" % junk)

	print("verify_premium_master_catalog: %s"
			% ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(1 if _fail > 0 else 0)
