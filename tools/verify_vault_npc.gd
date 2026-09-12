extends SceneTree
## Prove the Vault Keeper is actually standing in the Guild House, wired to the
## three Vault shelves, and not on top of anything.
##
## WHY A TOOL AND NOT AN EYEBALL. A .tres that parses and a node that loads both
## look fine while pointing at the wrong interactions, and the failure mode is a
## player walking up to a shop NPC with no shop. Everything below is read off the
## real scene, not off the diff.
##
##   godot --headless -s tools/verify_vault_npc.gd

const MAP := "res://source/common/gameplay/maps/maps/guild_house/inside_map.tscn"
const NPC := "res://source/common/gameplay/characters/npc/npcs/vault_keeper.tres"

var _fail: int = 0


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		print("  ok    %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s%s" % [what, ("  (%s)" % detail) if detail != "" else ""])


func _initialize() -> void:
	print("verify_vault_npc")

	var npc: Resource = ResourceLoader.load(NPC)
	_check(npc != null, "vault_keeper.tres loads")
	if npc == null:
		_done()
		return
	_check(str(npc.get("npc_name")) != "", "has a name", str(npc.get("npc_name")))

	var menus: Array[StringName] = []
	for entry_v: Variant in (npc.get("interactions") as Array):
		var made: Dictionary = (entry_v as Resource).call("menu_entry", null)
		var menu: StringName = StringName(str(made.get("menu", "")))
		if menu != &"":
			menus.append(menu)
		var label: String = str(made.get("label", ""))
		_check(not label.to_lower().contains("staff"),
			"label is player-facing: '%s'" % label)
	# All three shelves route to the same &"vault" menu with a different arg, so
	# the count is what proves none of them went missing.
	var vault_entries: int = menus.count(&"vault")
	_check(vault_entries == 3, "three vault shelves wired", "got %d" % vault_entries)

	var packed: PackedScene = ResourceLoader.load(MAP)
	_check(packed != null, "guild house scene loads")
	if packed == null:
		_done()
		return
	var state: SceneState = packed.get_state()
	var found: int = -1
	for i: int in state.get_node_count():
		if state.get_node_name(i) == "VaultKeeper":
			found = i
			break
	_check(found != -1, "VaultKeeper node is in the scene")
	if found == -1:
		_done()
		return

	var pos: Vector2 = Vector2.ZERO
	var res_path: String = ""
	for p: int in state.get_node_property_count(found):
		var prop: String = state.get_node_property_name(found, p)
		var value: Variant = state.get_node_property_value(found, p)
		if prop == "position":
			pos = value
		elif prop == "npc_resource" and value is Resource:
			res_path = (value as Resource).resource_path
	_check(res_path == NPC, "points at vault_keeper.tres", res_path)

	# Same row as the Trading Post pair, which is the whole point of the spot.
	_check(int(pos.y) == -536, "stands on the trading post row", "y=%d" % int(pos.y))
	var others: Array[Vector2] = []
	for i: int in state.get_node_count():
		if i == found:
			continue
		for p: int in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == "position":
				others.append(state.get_node_property_value(i, p))
	var nearest: float = INF
	for other: Vector2 in others:
		nearest = minf(nearest, pos.distance_to(other))
	_check(nearest >= 16.0, "not standing on another node", "nearest=%.1fpx" % nearest)

	_done()


func _done() -> void:
	print("verify_vault_npc: %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(1 if _fail > 0 else 0)
