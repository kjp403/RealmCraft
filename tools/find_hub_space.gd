@tool
extends Node
## Where can a new building go in the hub WITHOUT blocking anything?
##
## Placing a building by eyeballing coordinates is how you wall off a path and
## only find out when a player reports it. This loads hub.tscn for real and
## reports, for a grid of candidate spots, whether the Ground layer has floor
## there, whether the Walls layer is clear, and how far the nearest existing
## node sits — so the placement is chosen from data, not guessed.
##
## Run: godot --headless --path . --mode=client res://tools/find_hub_space.tscn

const HUB: String = "res://source/common/gameplay/maps/maps/hub.tscn"
## Half-extent of the footprint a building + its warper needs, in pixels.
const FOOTPRINT: float = 120.0
## How far a candidate must sit from anything already placed.
const CLEARANCE: float = 190.0


func _ready() -> void:
	var scene: PackedScene = load(HUB)
	var hub: Node2D = scene.instantiate()
	add_child(hub)

	# Hub keeps its layers under a Tiles node, not at the root.
	var ground: TileMapLayer = hub.get_node_or_null(^"Tiles/Ground") as TileMapLayer
	var walls: TileMapLayer = hub.get_node_or_null(^"Tiles/Walls") as TileMapLayer
	var props: TileMapLayer = hub.get_node_or_null(^"Tiles/Props") as TileMapLayer
	if ground == null:
		printerr("hub has no Ground layer")
		get_tree().quit(1)
		return

	var occupied: Array[Vector2] = []
	for node: Node in hub.get_children():
		if node is Node2D and node.name != "Tiles":
			_collect(node as Node2D, occupied)

	print("ground cells=", ground.get_used_cells().size(),
		"  occupied markers=", occupied.size())

	# Rank every clear spot by how much elbow room it has, rather than demanding
	# a threshold — the hub is dense, so "the roomiest options" is the useful
	# answer, and the caller can judge whether the best one is good enough.
	var ranked: Array[Dictionary] = []
	for gy: int in range(-8, 11):
		for gx: int in range(-13, 14):
			var pos := Vector2(gx * 64.0, gy * 64.0)
			if not _is_clear(ground, walls, props, pos):
				continue
			var nearest: float = INF
			for other: Vector2 in occupied:
				nearest = minf(nearest, pos.distance_to(other))
			ranked.append({"pos": pos, "clear": nearest})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["clear"]) > float(b["clear"]))
	if ranked.is_empty():
		print("  no clear spot at footprint ", FOOTPRINT)
		get_tree().quit(0)
		return
	for i: int in mini(12, ranked.size()):
		print("  CLEAR  %s   nearest node %.0fpx" % [ranked[i]["pos"], ranked[i]["clear"]])
	get_tree().quit(0)


func _collect(node: Node2D, out: Array[Vector2]) -> void:
	out.append(node.global_position)
	for child: Node in node.get_children():
		if child is Node2D:
			_collect(child as Node2D, out)


## Floor everywhere under the footprint, and no wall tile anywhere in it.
func _is_clear(ground: TileMapLayer, walls: TileMapLayer, props: TileMapLayer, centre: Vector2) -> bool:
	for oy: float in [-FOOTPRINT, 0.0, FOOTPRINT]:
		for ox: float in [-FOOTPRINT, 0.0, FOOTPRINT]:
			var probe := centre + Vector2(ox, oy)
			var cell: Vector2i = ground.local_to_map(ground.to_local(probe))
			if ground.get_cell_source_id(cell) == -1:
				return false
			for blocker: TileMapLayer in [walls, props]:
				if blocker == null:
					continue
				var bcell: Vector2i = blocker.local_to_map(blocker.to_local(probe))
				if blocker.get_cell_source_id(bcell) != -1:
					return false
	return true
