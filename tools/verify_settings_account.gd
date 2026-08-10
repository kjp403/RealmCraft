extends SceneTree
func _initialize() -> void:
	assert(Distribution.DISCORD_URL == "https://discord.gg/kSs3hxByV")
	var packed: PackedScene = load("res://source/client/ui/menus/settings/settings_menu.tscn")
	assert(packed != null)
	var menu: Node = packed.instantiate()
	root.add_child(menu)
	var discord: Button = menu.find_child("DiscordButton", true, false)
	var logout: Button = menu.find_child("LogoutButton", true, false)
	assert(discord != null and logout != null)
	print("SETTINGS_VERIFY_PASS")
	quit(0)
