extends Node
## Prove every Teleporter pad in the game lands its traveller CLEAR of the pad they
## arrive on. Landing dead-centre on a pad parks the player inside a live trigger
## pointing back the way they came, and the next entry event throws them there --
## the "walk into the next room, get shoved back" report from Fire and Flames.
##   godot --path . --mode=client res://tools/audit_teleporter_landings.tscn

## Every map that instances teleporter.tscn.
const MAPS: Array[String] = [
	"res://source/common/gameplay/maps/maps/hell_dungeon/hell_dungeon.tscn",
	"res://source/common/gameplay/maps/maps/dungeon/dungeon.tscn",
	"res://source/common/gameplay/maps/maps/fungus_cave/fungus_dungeon.tscn",
	"res://source/common/gameplay/maps/maps/fungus_cave/fungus_cave.tscn",
	"res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn",
	"res://source/common/gameplay/maps/maps/woodland/woodland_beach.tscn",
	"res://source/common/gameplay/maps/maps/woodland/woodland_deep_cove.tscn",
	"res://source/common/gameplay/maps/maps/guild_outpost_base/inside_map.tscn",
	"res://source/common/gameplay/maps/maps/spar_house/inside_map.tscn",
]

var _failures: int = 0
var _checked: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	for map_path: String in MAPS:
		if not ResourceLoader.exists(map_path):
			continue
		var scene: PackedScene = load(map_path) as PackedScene
		if scene == null:
			continue
		var root: Node = scene.instantiate()
		add_child(root)
		# Runtime state, not authored state: every one of these pads sits past a room
		# seal, so a player can only ever reach it with that seal OPEN. Auditing with
		# the doors shut would judge landings against walls that are not there.
		for door: Node in root.find_children("*", "ActivableDoor", true, false):
			(door as ActivableDoor).set_open(true, false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		print("\n=== %s ===" % map_path.get_file())
		for pad: Node in root.find_children("*", "Teleporter", true, false):
			_check(pad as Teleporter)
		root.queue_free()
		await get_tree().process_frame
	print("\n%d pads checked, %d failures" % [_checked, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(pad: Teleporter) -> void:
	if pad.target == null:
		print("  %-22s no target (plain arrival spot)" % pad.name)
		return
	_checked += 1
	var destination: Teleporter = pad.target
	var landing: Vector2 = destination.arrival_point_from(pad)
	# The whole point: the landing spot must NOT overlap the pad it arrived on, or the
	# next entry event bounces the player straight back. Ask the runtime's own rule so
	# this audit cannot drift from what the server actually does.
	var clear: bool = destination.clears_pad(landing)
	var moved: float = landing.distance_to(destination.global_position)
	var status: String = "OK"
	if not clear:
		status = "FAIL lands ON its own pad"
		_failures += 1
	print("  %-22s -> %-22s land %s (%.0fpx from pad centre) %s" % [
		pad.name, destination.name, landing, moved, status
	])
