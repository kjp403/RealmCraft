@tool
extends SceneTree
## Gate on the Starfall meteor: the shared pool must actually be shared, the
## level curve must favour better gems as Mining rises, and the vein must be
## placed on ground in the grove.
##
##   godot --headless --path . -s tools/verify_meteor_vein.gd

const VEIN: String = "res://source/common/gameplay/maps/components/mineable_nodes/starfall_meteor.tres"
const GROVE: String = "res://source/common/gameplay/maps/maps/starfall_grove/starfall_grove.tscn"


func _init() -> void:
	var bad: int = 0

	var res: MineableNodeResource = ResourceLoader.load(VEIN) as MineableNodeResource
	if res == null:
		printerr("VEIN MISSING"); bad += 1
	else:
		if not res.shared_pool:
			printerr("VEIN not shared_pool"); bad += 1
		if res.required_level > 0:
			printerr("VEIN gated by level — everyone should be able to join"); bad += 1
		if res.required_tool != &"pickaxe":
			printerr("VEIN wrong tool: ", res.required_tool); bad += 1

	# Every rung of the ladder has to resolve, or a swing pays nothing.
	for slug: StringName in MeteorVeinPool.LADDER:
		if ContentRegistryHub.load_by_slug(&"items", slug) == null:
			printerr("LADDER slug unresolved: ", slug); bad += 1

	# The pool is shared: two different miners draw the SAME counter down.
	var before: int = MeteorVeinPool.remaining()
	if before != MeteorVeinPool.pool_size():
		printerr("POOL did not start full: ", before); bad += 1
	MeteorVeinPool.take()
	MeteorVeinPool.take()
	if MeteorVeinPool.remaining() != before - 2:
		printerr("POOL not shared — expected ", before - 2, " got ",
			MeteorVeinPool.remaining())
		bad += 1

	# Better gems must get MORE likely as Mining rises, at every rung above the
	# sapphire floor. This is the whole point of the level weighting.
	var lo: Array[float] = MeteorVeinPool.weights_for(10)
	var hi: Array[float] = MeteorVeinPool.weights_for(99)
	for i: int in range(1, MeteorVeinPool.LADDER.size()):
		if hi[i] <= lo[i]:
			printerr("CURVE flat/inverted at ", MeteorVeinPool.LADDER[i]); bad += 1
	if MeteorVeinPool.weights_for(1)[3] <= 0.0:
		printerr("CURVE hard-gates diamond at low level"); bad += 1

	# Placed, and standing on painted ground rather than in the void.
	var scene: PackedScene = ResourceLoader.load(GROVE) as PackedScene
	var root: Node = scene.instantiate() if scene != null else null
	var found: Node = null
	if root != null:
		for child: Node in root.find_children("*", "", true, false):
			if child.name == &"StarfallMeteor":
				found = child
				break
	if found == null:
		printerr("VEIN not placed in starfall_grove"); bad += 1
	else:
		var ground: TileMapLayer = root.get_node_or_null("Tiles/Ground") as TileMapLayer
		var cell: Vector2i = ground.local_to_map((found as Node2D).position)
		if ground.get_cell_source_id(cell) == -1:
			printerr("VEIN standing in the void at cell ", cell); bad += 1
		else:
			print("vein at cell %s — ground painted" % cell)
	if root != null:
		root.queue_free()

	print("meteor checks — problems: %d" % bad)
	quit(1 if bad else 0)
