extends Node
## Live equip/unequip round trip for [CombatSetBonus], on a REAL Player node with
## a REAL EquipmentComponent — not a mock and not the static resolver the other
## verifier covers.
##
##   godot --headless --path . --mode=client res://tools/check_set_bonus_equip.tscn
##
## Runs as a SCENE, not a `-s` tool: player.gd and its components reference the
## Client/ClientState autoloads, which do not exist under `-s`, so the script
## would not compile there.
##
## An OfflineMultiplayerPeer is installed deliberately. Every stat write in
## EquipmentComponent sits behind `character.multiplayer.is_server()`, and the
## offline peer reports true — without it this tool would equip items, apply
## nothing, and pass by doing nothing at all.
##
## WHAT THIS CATCHES that the static verifier cannot: the ledger. Set bonuses are
## applied and stripped through _applied_set_mods, and the failure mode is a
## bonus that does not come off when the armour does — a player permanently
## buffed by gear they are no longer wearing. The final assertion of each case is
## that every stat returns to its EXACT baseline after unequipping.

const PLAYER_SCENE: String = "res://source/common/gameplay/characters/player/player.tscn"

## Stats the three sets touch, plus the raw gear stats, so a leak anywhere shows.
const WATCHED: Array[StringName] = [
	Stat.ARMOR, Stat.MR, Stat.AD, Stat.HEALTH_MAX, Stat.MOVE_SPEED,
	Stat.ABILITY_HASTE, Stat.LIFESTEAL, Stat.HEALTH_REGEN, Stat.MANA_ON_HIT,
	# Kept watched even though no set grants it any more: if one ever does, the
	# leak check should still cover it (the static verifier is what forbids it).
	Stat.DAMAGE_VS_LOW_HP,
]

## set slug -> [slot, piece slug] in the order they get put on.
const CASES: Dictionary = {
	&"ankhemet": [
		[&"helmet", &"ankhemet_mask"],
		[&"torso", &"ankhemet_wrappings"],
		[&"ring", &"ankhemet_signet"],
	],
	&"slagborn": [
		[&"helmet", &"slagborn_helm"],
		[&"boot", &"slagborn_sabatons"],
		[&"torso", &"cindermantle"],
	],
	&"siltbound": [
		[&"helmet", &"siltbound_coronet"],
		[&"torso", &"siltbound_plate"],
	],
}

var _failures: Array[String] = []
var _checks: int = 0
var _player: Node = null
var _equip: EquipmentComponent = null


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	# is_server() must be true or every stat write below is skipped.
	var peer: OfflineMultiplayerPeer = OfflineMultiplayerPeer.new()
	get_tree().get_multiplayer().multiplayer_peer = peer

	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	add_child(_player)
	await get_tree().process_frame

	_equip = _player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent
	if _equip == null:
		_fail("player.tscn has no EquipmentComponent")
		return _report()
	if not _player.multiplayer.is_server():
		_fail("offline peer did not make is_server() true — every write would no-op")
		return _report()

	for set_slug: StringName in CASES:
		await _run_case(set_slug, CASES[set_slug])

	await _run_reapply_case()
	_report()


## Put the set on one piece at a time, checking the bonus tier at each step, then
## take it all off and check every watched stat is back to baseline.
func _run_case(set_slug: StringName, pieces: Array) -> void:
	print("\n--- %s ---" % set_slug)
	var baseline: Dictionary = _snapshot()

	for n: int in pieces.size():
		var slot: StringName = pieces[n][0]
		var slug: StringName = pieces[n][1]
		_set_slot(slot, _id(slug))
		await get_tree().process_frame

		var worn: int = n + 1
		var want: Dictionary = CombatSetBonus.tier_row(set_slug, worn)
		# The set bonus is whatever the live stats hold ABOVE baseline + the raw
		# gear modifiers of what is currently worn. Isolating it that way is the
		# only honest check: it proves the bonus was applied on top of gear,
		# rather than that some number happens to be bigger.
		var gear_only: Dictionary = _gear_sum(pieces, worn)
		for stat: StringName in WATCHED:
			var actual_bonus: float = _stat(stat) - float(baseline[stat]) \
				- float(gear_only.get(stat, 0.0))
			var expected: float = float(want.get(stat, 0.0))
			_checks += 1
			if not is_equal_approx(snappedf(actual_bonus, 0.001), snappedf(expected, 0.001)):
				_fail("%s @%d worn: %s bonus is %.2f, expected %.2f"
					% [set_slug, worn, stat, actual_bonus, expected])
		print("  %d worn -> %s" % [worn, "none" if want.is_empty() else str(want)])

	# Take it all off, in the same order. This is the round trip.
	for n: int in pieces.size():
		_set_slot(pieces[n][0], 0)
		await get_tree().process_frame

	var leaked: Array[String] = []
	for stat: StringName in WATCHED:
		_checks += 1
		if not is_equal_approx(snappedf(_stat(stat), 0.001), snappedf(float(baseline[stat]), 0.001)):
			leaked.append("%s %.2f -> %.2f" % [stat, float(baseline[stat]), _stat(stat)])
	if leaked.is_empty():
		print("  unequipped -> every stat back to baseline")
	else:
		_fail("%s leaked after unequip: %s" % [set_slug, ", ".join(leaked)])

	# ...and again, three more times. One clean cycle does not prove the ledger
	# cannot ACCUMULATE: a strip that under-removes by a rounding step, or a
	# double-apply on re-equip, shows up as drift that only becomes visible once
	# a player has swapped kit a few times — which is every raid night, and never
	# the first thirty seconds of a test.
	for cycle: int in 3:
		for n: int in pieces.size():
			_set_slot(pieces[n][0], _id(pieces[n][1]))
			await get_tree().process_frame
		for n: int in pieces.size():
			_set_slot(pieces[n][0], 0)
			await get_tree().process_frame
	var drifted: Array[String] = []
	for stat: StringName in WATCHED:
		_checks += 1
		if not is_equal_approx(snappedf(_stat(stat), 0.001), snappedf(float(baseline[stat]), 0.001)):
			drifted.append("%s %.3f -> %.3f" % [stat, float(baseline[stat]), _stat(stat)])
	# THE UNRESOLVABLE-ID CASE. A slot can hold an id that no longer loads —
	# a saved character wearing an item a content patch deleted. _on_slot_changed
	# clears the slot and then, until this was fixed, RETURNED without emitting
	# equipment_changed, so the set-bonus ledger never re-evaluated and kept
	# paying a 3-piece bonus to someone now wearing two.
	#
	# Not client-reachable (item.equip.gd validates the id before writing the
	# slot) and it fails in the player's favour, which is exactly why it would
	# never have been reported.
	if pieces.size() >= 3:
		for n: int in pieces.size():
			_set_slot(pieces[n][0], _id(pieces[n][1]))
			await get_tree().process_frame
		# 999999 resolves to nothing.
		_set_slot(pieces[0][0], 999999)
		await get_tree().process_frame
		var two_piece: Dictionary = CombatSetBonus.tier_row(set_slug, 2)
		# The gear still ON the character is pieces[1..] — piece 0 is the one
		# whose slot now holds the unloadable id. Summing "the first two" would
		# subtract the wrong item's modifiers and make a correct result look
		# broken, which is exactly what the first draft of this check did.
		var remaining: Array = pieces.slice(1)
		var gear_left: Dictionary = _gear_sum(remaining, remaining.size())
		var bad: Array[String] = []
		for stat: StringName in WATCHED:
			var got: float = _stat(stat) - float(baseline[stat]) 				- float(gear_left.get(stat, 0.0))
			_checks += 1
			if not is_equal_approx(snappedf(got, 0.001),
					snappedf(float(two_piece.get(stat, 0.0)), 0.001)):
				bad.append("%s %.2f (want %.2f)"
					% [stat, got, float(two_piece.get(stat, 0.0))])
		if bad.is_empty():
			print("  unloadable id in a slot -> bonus correctly drops to 2-piece")
		else:
			_fail("%s: a slot holding an unloadable id left the ledger stale: %s"
				% [set_slug, ", ".join(bad)])
		for n: int in pieces.size():
			_set_slot(pieces[n][0], 0)
			await get_tree().process_frame

	if drifted.is_empty():
		print("  4 full equip/unequip cycles -> still exactly baseline")
	else:
		_fail("%s DRIFTED over repeated cycles: %s" % [set_slug, ", ".join(drifted)])


## reapply_all_gear_stats is the LevelSync restore path: it rewrites stats
## without going through slot_changed, so the set-bonus signal never fires and
## the bonus has to be rebuilt explicitly. Assert it survives.
func _run_reapply_case() -> void:
	print("\n--- reapply_all_gear_stats (LevelSync restore path) ---")
	var pieces: Array = CASES[&"ankhemet"]
	for n: int in pieces.size():
		_set_slot(pieces[n][0], _id(pieces[n][1]))
		await get_tree().process_frame
	var before: Dictionary = _snapshot()

	_equip.reapply_all_gear_stats()
	await get_tree().process_frame

	var drifted: Array[String] = []
	for stat: StringName in WATCHED:
		_checks += 1
		if not is_equal_approx(snappedf(_stat(stat), 0.001), snappedf(float(before[stat]), 0.001)):
			drifted.append("%s %.2f -> %.2f" % [stat, float(before[stat]), _stat(stat)])
	if drifted.is_empty():
		print("  stats identical after reapply — bonus rebuilt, nothing doubled")
	else:
		_fail("reapply_all_gear_stats drifted: %s" % ", ".join(drifted))

	for n: int in pieces.size():
		_set_slot(pieces[n][0], 0)
		await get_tree().process_frame


# --- helpers -----------------------------------------------------------------

## Drives the REAL slot setter, so slot_changed -> _on_slot_changed ->
## _apply_gear_stats -> equipment_changed -> refresh_set_bonuses all run.
func _set_slot(slot: StringName, item_id: int) -> void:
	_equip.slots.set(slot, item_id)


func _id(slug: StringName) -> int:
	return ContentRegistryHub.id_from_slug(&"items", slug)


func _stat(stat: StringName) -> float:
	return _player.stats_component.get_stat(stat)


func _snapshot() -> Dictionary:
	var out: Dictionary = {}
	for stat: StringName in WATCHED:
		out[stat] = _stat(stat)
	return out


## Summed base_modifiers of the first [param worn] pieces — what the gear alone
## contributes, so the set bonus can be isolated from it.
func _gear_sum(pieces: Array, worn: int) -> Dictionary:
	var out: Dictionary = {}
	for n: int in worn:
		var gear: GearItem = ContentRegistryHub.load_by_slug(
			&"items", pieces[n][1]) as GearItem
		if gear == null:
			continue
		for mod: StatModifier in gear.base_modifiers:
			if mod == null:
				continue
			var key: StringName = StringName(mod.stat_name)
			out[key] = float(out.get(key, 0.0)) + float(mod.value)
	return out


func _fail(msg: String) -> void:
	_failures.append(msg)


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("CHECK_PASS  (%d assertions)" % _checks)
	else:
		for line: String in _failures:
			printerr("  FAIL: %s" % line)
		print("CHECK_FAIL  (%d failures / %d assertions)" % [_failures.size(), _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)
