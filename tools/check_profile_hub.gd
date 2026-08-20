extends Node
## Parse/instantiate gate for the Profile hub rework: loads the menus the
## three-dots overlay now hands off to and quits. Scene, not `-s` — these
## scripts need the client autoloads to compile.

func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var failed: bool = false
	for path: String in [
		"res://source/client/ui/hud/menu_overlay.gd",
		"res://source/client/ui/menus/player_profile/player_profile_menu.tscn",
		"res://source/client/ui/menus/character/character_menu.tscn",
		"res://source/client/ui/menus/cosmetics/cosmetics_menu.tscn",
		"res://source/client/ui/menus/guild/guild_menu.tscn",
		"res://source/client/ui/hud/hud.tscn",
	]:
		var res: Resource = load(path)
		if res == null:
			push_error("FAILED to load %s" % path)
			failed = true
			continue
		if res is PackedScene:
			var node: Node = (res as PackedScene).instantiate()
			if node == null:
				push_error("FAILED to instantiate %s" % path)
				failed = true
				continue
			node.queue_free()
		print("OK ", path)
	print("RESULT ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
