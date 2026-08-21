extends Node
## Assert the Mining Cave's high-ore veins are minable: on open floor, not
## inside the rock, with room to stand, and far enough apart that a click can
## only resolve to one of them.
##   godot --path . --mode=client res://tools/check_ore_alcove.tscn

const SCENE: String = "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"
const TILE: int = 32
## HarvestController.GATHER_RANGE
const GATHER_RANGE: float = 48.0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node = (load(SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var walls: TileMapLayer = root.get_node("Tiles/Walls") as TileMapLayer
	var veins: Array[Node] = []
	for node: Node in root.get_node("MineableNodes").get_children():
		if String(node.name).begins_with("Adamant") or String(node.name).begins_with("Runite"):
			veins.append(node)

	var bad: int = 0
	for node: Node in veins:
		var pos: Vector2 = (node as Node2D).position
		var cell := Vector2i(int(pos.x) / TILE, int(pos.y) / TILE)
		if walls.get_cell_source_id(cell) >= 0:
			print("  IN ROCK: %s at %s" % [node.name, cell])
			bad += 1
			continue
		var free: int = 0
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if walls.get_cell_source_id(cell + step) < 0:
				free += 1
		if free < 3:
			print("  ONLY %d SIDES OPEN: %s at %s" % [free, node.name, cell])
			bad += 1

	var closest: float = 1e9
	var pair: String = ""
	for i: int in veins.size():
		for j: int in range(i + 1, veins.size()):
			var d: float = (veins[i] as Node2D).position.distance_to((veins[j] as Node2D).position)
			if d < closest:
				closest = d
				pair = "%s <-> %s" % [veins[i].name, veins[j].name]
	print("%d veins, %d unminable" % [veins.size(), bad])
	print("closest pair: %.0fpx (%s), gather range %.0fpx" % [closest, pair, GATHER_RANGE])
	if bad > 0 or closest <= GATHER_RANGE * 1.5:
		push_error("ore alcove check FAILED")
	else:
		print("ore alcove OK")
	root.free()
	get_tree().quit(0)
