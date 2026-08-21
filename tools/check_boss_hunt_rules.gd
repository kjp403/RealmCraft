extends Node
## Two rules the Boss Hunt depends on, asserted rather than assumed:
## the arena must send the dead OUT (so death ends the contract), and the
## client must warn before the fee is spent.
##   godot --path . --mode=client res://tools/check_boss_hunt_rules.tscn

const ARENA: String = "res://source/common/gameplay/maps/instance/instance_collection/boss_hunt_arena.tres"
const MENU: String = "res://source/client/ui/menus/boss_hunt/boss_hunt_menu.gd"

var _failed: bool = false


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var arena: InstanceResource = load(ARENA) as InstanceResource
	if arena == null:
		_fail("arena instance resource failed to load")
	elif arena.death_return_instance == null:
		_fail("arena has no death_return_instance — dying respawns you in the room")
	else:
		print("death returns to: ", arena.death_return_instance.instance_name)

	var src: String = FileAccess.get_file_as_string(MENU)
	if not src.contains("ConfirmationDialog"):
		_fail("contract purchase has no confirmation step")
	for phrase: String in ["die", "not refunded"]:
		if not src.to_lower().contains(phrase):
			_fail("purchase warning does not mention '%s'" % phrase)
	print("purchase confirm present and warns about death and the fee")

	print("RESULT ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true
