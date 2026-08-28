class_name MasteryTreeResource
extends Resource
## A weapon category's full mastery tree. Branch grouping lives on the nodes
## themselves (MasteryNode.branch). One .tres per category in
## res://source/common/gameplay/mastery/trees/ — MasteryService discovers them
## by folder and keys them by [member category].


@export var category: StringName
@export var display_name: String
@export var category_icon: Texture2D
@export var nodes: Array[MasteryNode]

## Mastery points this tree pays out per earned point, i.e. a per-tree multiplier
## on [method MasteryService.point_budget]. 1 = the shared rate (1 point every
## MasteryService.LEVELS_PER_POINT levels; 33 at level 99).
##
## Exists because a tree's TOTAL cost is a design choice per weapon and the
## budget has to follow it. Heavy Weapons carries three full role kits (threat,
## mitigation, group healing) on top of its damage column, so it costs roughly
## double what a single-role tree does; leaving it on the shared rate would not
## have made it a harder choice, it would have made two thirds of the tree
## permanently unreachable. Raise the rate WITH the cost, never instead of it.
@export_range(1, 4) var point_rate: int = 1


func get_node_by_id(node_id: StringName) -> MasteryNode:
	for node: MasteryNode in nodes:
		if node.id == node_id:
			return node
	return null


## Sum of every node's Power/tier cost. Compared against
## [method MasteryService.point_budget] for THIS tree ([member point_rate]): a
## tree should cost comfortably more than its own level-99 budget, so picking a
## column is a real choice rather than a matter of time.
func total_cost() -> int:
	var total: int = 0
	for node: MasteryNode in nodes:
		total += node.tier
	return total
