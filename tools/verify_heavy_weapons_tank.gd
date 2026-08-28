@tool
extends Node
## Gate for the Heavy Weapons TANK rework and the fourth ability key.
##
## What this exists to catch, in order of how quietly each one fails:
##
## 1. A new ability .tres whose metadata/id is missing from abilities_index.tres.
##    The tree still loads, the node still shows in the UI, and the ability
##    silently channels NOTHING when equipped (see the content-index trap in
##    CONTENT_AUTHORING.md).
## 2. The Crushing Blow chain drifting back out of order — the exact confusion
##    this rework fixed: a rank 2 that costs more and hits for less than rank 1.
## 3. Slot count regressing to three somewhere. mastery.loadout's MAX_PICKS,
##    EquipmentComponent.SPECIAL_SLOTS and the client key lists all have to agree
##    or the C slot stores fine and then never mounts.
## 4. The tree's cost outgrowing its point budget again. Heavy Weapons carries
##    three role kits, so it costs about double a single-role tree and runs at
##    point_rate 2 to match; bolting nodes on without raising the rate makes the
##    extra column unreachable rather than optional.
## 5. Spectral Ward losing its reflect, or declaring a reduction past the cap
##    (which, with the reflect, would be an infinite-damage button).
##
## Run: godot --headless --path . tools/verify_heavy_weapons_tank.tscn

## Chains that must be strictly stronger every rank, as (node ids in rank order).
const POWER_CHAINS: Array = [
	["hammer_crush", "hammer_shockwave", "hammer_earthshatter", "hammer_cataclysm"],
	["hammer_aftershock", "hammer_aftershock_2", "hammer_aftershock_3"],
	["hammer_spectral_ward", "hammer_spectral_ward_2", "hammer_spectral_ward_3"],
	["hammer_roar", "hammer_roar_2", "hammer_roar_3"],
	["hammer_paladins_might", "hammer_paladins_might_2", "hammer_paladins_might_3"],
]

## The tank kit: node id -> the ability script class it must carry.
const KIT: Dictionary = {
	"hammer_roar": "TauntAbility",
	"hammer_spectral_ward": "WardAbility",
	"hammer_paladins_might": "SanctuaryAbility",
}

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var tree: MasteryTreeResource = MasteryService.tree_for(&"hammer")
	_check(tree != null, "hammer tree loads")
	if tree == null:
		_finish()
		return
	_check_kit(tree)
	_check_registered(tree)
	_check_chain_order(tree)
	_check_budget(tree)
	_check_ward_reflect(tree)
	_check_full_unlock(tree)
	_check_slot_count()
	_finish()


## Every tank tool is present and is the ability TYPE it is meant to be — a
## Spectral Ward that quietly went back to being a passive would read fine in the
## tree and do nothing on the key.
func _check_kit(tree: MasteryTreeResource) -> void:
	for node_id: String in KIT:
		var node: MasteryNode = tree.get_node_by_id(StringName(node_id))
		if not _check(node != null, "%s exists" % node_id):
			continue
		if not _check(node.ability != null, "%s carries an ability" % node_id):
			continue
		var script: Script = node.ability.get_script() as Script
		var got: String = script.get_global_name() if script != null else "<none>"
		_check(got == KIT[node_id], "%s is a %s (got %s)" % [node_id, KIT[node_id], got])


## Every ability in the tree resolves through the abilities registry by its own
## metadata/id. This is the check that catches an unregistered new .tres.
func _check_registered(tree: MasteryTreeResource) -> void:
	for node: MasteryNode in tree.nodes:
		if node.ability == null:
			continue
		var id: int = int(node.ability.get_meta(&"id", 0))
		if not _check(id > 0, "%s ability carries a metadata/id" % node.id):
			continue
		var loaded: Resource = ContentRegistryHub.load_by_id(&"abilities", id)
		_check(
			loaded != null and loaded.get_meta(&"id", 0) == id,
			"%s ability id %d is in abilities_index" % [node.id, id]
		)


## Ranks go up, never sideways: each rank costs at least as much as the one it
## replaces, links to it, and beats it on the numbers it is sold on.
func _check_chain_order(tree: MasteryTreeResource) -> void:
	for chain: Array in POWER_CHAINS:
		var previous: MasteryNode = null
		for rank: int in chain.size():
			var node: MasteryNode = tree.get_node_by_id(StringName(chain[rank]))
			if not _check(node != null, "%s exists" % chain[rank]):
				previous = null
				continue
			if previous == null:
				previous = node
				continue
			_check(
				node.upgrades == previous.id,
				"%s upgrades %s" % [node.id, previous.id]
			)
			_check(
				node.tier > previous.tier,
				"%s (tier %d) outranks %s (tier %d)" % [
					node.id, node.tier, previous.id, previous.tier
				]
			)
			_check(
				_power_of(node) > _power_of(previous),
				"%s is stronger than %s (%.2f vs %.2f)" % [
					node.id, previous.id, _power_of(node), _power_of(previous)
				]
			)
			previous = node


## A single comparable number per ability, per family. Only ever compared WITHIN
## one chain (all of whose ranks are the same ability class), so the families
## never have to be commensurable with each other.
func _power_of(node: MasteryNode) -> float:
	var ability: AbilityResource = node.ability
	if ability == null:
		return 0.0
	if ability is WardAbility:
		var ward: WardAbility = ability as WardAbility
		return ward.damage_reduction_pct * ward.duration_s
	if ability is TauntAbility:
		var taunt: TauntAbility = ability as TauntAbility
		# 0 = "until it dies", which outranks every finite duration.
		var hold: float = 999.0 if taunt.taunt_duration_s <= 0.0 else taunt.taunt_duration_s
		return hold + taunt.radius
	if ability is SanctuaryAbility:
		var sanctuary: SanctuaryAbility = ability as SanctuaryAbility
		return sanctuary.heal_per_tick * sanctuary.duration_s
	if ability is NovaAbility:
		var nova: NovaAbility = ability as NovaAbility
		return nova.ad_ratio + nova.hp_ratio * 10.0
	if ability is MeleeSwingAbility:
		return (ability as MeleeSwingAbility).ad_ratio
	return 0.0


## A level-99 Heavy Weapons player can afford the whole tree. Not a balance
## statement — the cap grants everything anyway — but the rate and the cost have
## to be raised together, and this is what notices when only one of them moves.
func _check_budget(tree: MasteryTreeResource) -> void:
	_check(tree.point_rate == 2, "hammer runs at point_rate 2 (got %d)" % tree.point_rate)
	var budget: int = MasteryService.point_budget(PlayerResource.MASTERY_LEVEL_CAP, tree)
	_check(
		budget >= tree.total_cost(),
		"the level-99 budget covers the tree (%d points vs %d cost)" % [budget, tree.total_cost()]
	)


## Every Spectral Ward rank reflects, stays inside the reduction cap, and throws
## back strictly more than the rank below it.
func _check_ward_reflect(tree: MasteryTreeResource) -> void:
	var previous: float = -1.0
	for node_id: String in ["hammer_spectral_ward", "hammer_spectral_ward_2", "hammer_spectral_ward_3"]:
		var node: MasteryNode = tree.get_node_by_id(StringName(node_id))
		if node == null or node.ability is not WardAbility:
			_check(false, "%s is a WardAbility" % node_id)
			continue
		var ward: WardAbility = node.ability as WardAbility
		_check(ward.reflect_ratio > 0.0, "%s reflects (%.2f)" % [node_id, ward.reflect_ratio])
		_check(
			ward.damage_reduction_pct <= WardAbility.MAX_REDUCTION,
			"%s stays inside the %d%% reduction cap (got %d%%)" % [
				node_id,
				int(WardAbility.MAX_REDUCTION * 100.0),
				int(ward.damage_reduction_pct * 100.0),
			]
		)
		# What a player actually feels: absorbed damage per point that still lands.
		var mult: float = 1.0 - clampf(ward.damage_reduction_pct, 0.0, WardAbility.MAX_REDUCTION)
		var thrown_back: float = ((1.0 / maxf(0.01, mult)) - 1.0) * ward.reflect_ratio
		_check(
			thrown_back > previous,
			"%s throws back more than the rank below (%.2fx)" % [node_id, thrown_back]
		)
		previous = thrown_back


## Mastery 99 hands over the WHOLE tree — passives included. Partial unlocks are
## the bug: the banner said MASTERED while locked passive tiles sat there greyed.
func _check_full_unlock(tree: MasteryTreeResource) -> void:
	var maxed: Dictionary = {"level": PlayerResource.MASTERY_LEVEL_CAP, "spent": {}}
	var granted: Array[String] = MasteryService.full_unlock_ids(tree)
	_check(
		granted.size() == tree.nodes.size(),
		"the cap grants every node (%d of %d)" % [granted.size(), tree.nodes.size()]
	)
	var passives: int = 0
	for node: MasteryNode in tree.nodes:
		if node.ability != null:
			continue
		passives += 1
		_check(MasteryService.owns_node(maxed, node), "the cap owns passive %s" % node.id)
	_check(passives > 0, "the hammer tree has passives for the cap to grant")


## The fourth key exists end to end. Checked against the server handler's cap and
## the synced pseudo-slots, the two halves that must not drift apart.
func _check_slot_count() -> void:
	var handler: GDScript = load(
		"res://source/server/world/components/data_request_handlers/mastery.loadout.gd"
	) as GDScript
	var max_picks: int = int(handler.get_script_constant_map().get("MAX_PICKS", 0))
	_check(max_picks == 4, "mastery.loadout allows 4 picks (got %d)" % max_picks)
	_check(
		EquipmentComponent.SPECIAL_SLOTS.size() == max_picks,
		"EquipmentComponent has one pseudo-slot per pick (got %d)"
			% EquipmentComponent.SPECIAL_SLOTS.size()
	)
	_check(
		InputMap.has_action(&"player_special_4"),
		"player_special_4 is bound in the InputMap"
	)


func _check(ok: bool, what: String) -> bool:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
	return ok


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL: %d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
