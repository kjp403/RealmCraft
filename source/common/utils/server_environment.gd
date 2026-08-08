class_name ServerEnvironment
## Distinguishes local editor/dev runs from the live VPS.
##
## CRITICAL: the VPS runs the Godot *editor* binary (`godot --headless --path …`),
## so `OS.has_feature("editor")` is TRUE in production. Never use that feature as
## a security or path gate for live servers. Use this helper instead.
##
## Live is selected by `--env=live` (set on systemd unit ExecStart lines).
## Local cloud/dev servers omit that flag and keep the convenient res:// paths.

const ENV_LIVE_ALIASES: PackedStringArray = ["live", "production", "prod"]
const ENV_DEV_ALIASES: PackedStringArray = ["dev", "editor", "local"]

static var _resolved: bool = false
static var _is_live: bool = false


static func is_live() -> bool:
	if not _resolved:
		_is_live = _detect_live()
		_resolved = true
		if _is_live:
			print("ServerEnvironment: LIVE mode (user:// data paths, hardened admin).")
		elif GameMode.is_any_server():
			print("ServerEnvironment: DEV mode (editor/res:// paths). Pass --env=live for production.")
	return _is_live


## True when durable server data must live under user:// (not res://).
static func use_user_data_paths() -> bool:
	# Real exports never have the editor feature.
	if not OS.has_feature("editor"):
		return true
	return is_live()


## Copy a legacy res:// file into user:// once so flipping --env=live does not
## wipe accounts / the world DB that previously lived under the project tree.
static func migrate_file_if_needed(user_path: String, legacy_res_path: String) -> bool:
	if FileAccess.file_exists(user_path):
		return false
	if not FileAccess.file_exists(legacy_res_path):
		return false
	var abs_user_dir: String = ProjectSettings.globalize_path(user_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(abs_user_dir)
	var src: FileAccess = FileAccess.open(legacy_res_path, FileAccess.READ)
	if src == null:
		push_error("ServerEnvironment: failed to read legacy %s" % legacy_res_path)
		return false
	var bytes: PackedByteArray = src.get_buffer(src.get_length())
	src.close()
	var dst: FileAccess = FileAccess.open(user_path, FileAccess.WRITE)
	if dst == null:
		push_error("ServerEnvironment: failed to write %s" % user_path)
		return false
	dst.store_buffer(bytes)
	dst.close()
	print("ServerEnvironment: migrated %s → %s" % [legacy_res_path, user_path])
	return true


## Also migrate SQLite WAL/SHM sidecars when present next to a legacy .db.
static func migrate_sqlite_if_needed(user_db_path: String, legacy_res_db_path: String) -> void:
	migrate_file_if_needed(user_db_path, legacy_res_db_path)
	for suffix: String in ["-wal", "-shm"]:
		migrate_file_if_needed(user_db_path + suffix, legacy_res_db_path + suffix)


static func _detect_live() -> bool:
	var args: Dictionary = CmdlineUtils.get_parsed_args()
	var env: String = str(args.get("env", "")).strip_edges().to_lower()
	if env in ENV_LIVE_ALIASES:
		return true
	if env in ENV_DEV_ALIASES:
		return false
	# Bare `--live` flag (no value).
	if args.has("live") and not args.has("env"):
		return true
	return false
