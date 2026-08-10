class_name SettingsAccountActions
extends RefCounted
## Shared Settings actions: open Discord, log out to the login screen.


static func open_discord() -> void:
	OS.shell_open(Distribution.DISCORD_URL)


## Forget saved credentials and return to the login screen (disconnects if in-world).
static func logout_to_login() -> void:
	_clear_saved_session()
	Transition.return_to_login()


static func _clear_saved_session() -> void:
	var local_id: String = str(CmdlineUtils.get_parsed_args().get("id", ""))
	var file_path: String = "user://%ssession.dat" % local_id
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
