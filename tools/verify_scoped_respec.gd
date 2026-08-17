@tool
extends Node
## Gate for the SCOPED re-spec: refunding one job / one mastery tree must leave
## every other one untouched. The old handlers were all-or-nothing, so a single
## bad Mining pick cost you Smithing, and redoing Bow wiped Sword.
##
## Run: godot --headless --path . tools/verify_scoped_respec.tscn

const PERK_RESET: String = "res://source/server/world/components/data_request_handlers/skill.perk.reset.gd"

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_check_skill_scope()
	_check_mastery_scope()
	_finish()


## Clearing Mining's perks must not touch Smithing's.
func _check_skill_scope() -> void:
	var handler: GDScript = load(PERK_RESET) as GDScript
	if handler == null:
		_check(false, "skill.perk.reset.gd loads")
		return

	var pr: PlayerResource = PlayerResource.new()
	pr.skills[&"mining"] = {"level": 50, "xp": 0, "perks": {&"prospector": 3, &"frugal": 1}}
	pr.skills[&"smithing"] = {"level": 40, "xp": 0, "perks": {&"apprentice": 2}}

	_check(handler.call(&"_spent_ranks", pr, &"mining") == 4, "counts Mining's 4 ranks")
	_check(handler.call(&"_spent_ranks", pr, &"smithing") == 2, "counts Smithing's 2 ranks")
	_check(
		handler.call(&"_spent_ranks", pr, &"fishing") == 0,
		"an untouched job counts 0 (so a scoped respec there is refused, not charged)"
	)

	handler.call(&"_clear_perks", pr, &"mining")
	_check(handler.call(&"_spent_ranks", pr, &"mining") == 0, "Mining is refunded")
	_check(
		handler.call(&"_spent_ranks", pr, &"smithing") == 2,
		"Smithing SURVIVES a Mining respec"
	)

	# Saves written at different times key skills as String or StringName; a
	# scoped reset that only matched one of them would silently refund nothing.
	var mixed: PlayerResource = PlayerResource.new()
	mixed.skills["woodcutting"] = {"level": 30, "xp": 0, "perks": {&"lumberjack": 2}}
	_check(
		handler.call(&"_spent_ranks", mixed, &"woodcutting") == 2,
		"a String-keyed skill still matches a StringName scope"
	)


## Clearing Bow must not touch Sword — nodes OR the other tree's Q/E picks.
func _check_mastery_scope() -> void:
	var pr: PlayerResource = PlayerResource.new()
	pr.masteries[&"bow"] = {"level": 40, "spent": {"bow_multishot": true, "bow_lightstep": true}}
	pr.masteries[&"sword"] = {"level": 40, "spent": {"sword_cleave": true}}
	pr.ability_loadout["bow"] = ["bow_multishot"]
	pr.ability_loadout["sword"] = ["sword_cleave"]

	var result: Dictionary = MasteryService.reset(pr, &"bow")
	_check(bool(result.get("ok", false)), "a scoped mastery reset reports ok")

	var bow_spent: Dictionary = (pr.masteries[&"bow"] as Dictionary).get("spent", {})
	var sword_spent: Dictionary = (pr.masteries[&"sword"] as Dictionary).get("spent", {})
	_check(bow_spent.is_empty(), "Bow's nodes are refunded")
	_check(sword_spent.size() == 1, "Sword's nodes SURVIVE a Bow respec")
	_check(not pr.ability_loadout.has("bow"), "Bow's Q/E picks are cleared with its nodes")
	_check(pr.ability_loadout.has("sword"), "Sword's Q/E picks SURVIVE a Bow respec")

	_check(
		not MasteryService.reset(pr, &"axe").get("ok", false),
		"a category the player never trained is refused (not charged)"
	)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_PASS")
	else:
		for f: String in _failures:
			printerr("FAIL: %s" % f)
		printerr("VERIFY_FAIL (%d)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
