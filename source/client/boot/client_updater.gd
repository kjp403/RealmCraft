class_name ClientUpdater
## Windows desktop self-update. Exported clients GET latest.json, download the
## portable zip when the remote version is newer, then spawn a cmd that replaces
## files after this process exits. Editor / web / Linux skip this path.
##
## The zip is extracted to %TEMP% — never next to the EXE — so OneDrive/Dropbox
## cannot lock the staged files mid-copy. apply_update.cmd retries robocopy and
## kills a relaunched EXE (quit() looks like a crash; people click the icon again).
##
## Every failure path must end with a client running. quit() hands the only live
## process to apply_update.cmd, so a copy that gives up without relaunching leaves
## the player staring at nothing — and the next launch re-stages and quits again,
## which reads as "the game opens for a second and closes" forever.

const MANIFEST_TIMEOUT_SEC: float = 15.0
const DOWNLOAD_TIMEOUT_SEC: float = 0.0  # disabled — zip can be ~100MB on a slow link
const STAGE_DIR_NAME: String = "_update"
const ZIP_NAME: String = "_update_download.zip"
const APPLY_SCRIPT_NAME: String = "apply_update.cmd"
## Written next to the EXE before quit(), cleared once a boot sees the new build.
## Finding it on startup means the copy lost, so it doubles as the retry counter.
const APPLY_MARKER_NAME: String = "update_pending.json"
## Stamped into a stage dir so a later run can tell which build it holds.
const STAGE_META_NAME: String = "arkenelle_stage.json"
## Applies to attempt before giving up and showing the player a real error.
const MAX_APPLY_TRIES: int = 3


static func should_run() -> bool:
	if OS.has_feature("editor"):
		return false
	if OS.has_feature("web"):
		return false
	if not OS.has_feature("windows"):
		return false
	var args: Dictionary = CmdlineUtils.get_parsed_args()
	if args.has("skip-update"):
		return false
	return true


## Returns {ok, quit, error, needed}. needed=true means latest.json is newer than
## this EXE (or force=true). quit=true means this process is exiting for apply_update.cmd.
static func apply_if_needed(host: Node, status: Callable = Callable(), force: bool = false) -> Dictionary:
	if not should_run():
		return _result(true, false, "", false)
	_status(status, _t(&"CHECKING_UPDATE"))
	var install_dir: String = OS.get_executable_path().get_base_dir()
	var manifest: Dictionary = await _fetch_manifest(host)
	if manifest.is_empty():
		push_warning("ClientUpdater: could not fetch latest.json")
		return _result(false, false, "manifest", false)
	var remote_version: String = str(manifest.get("version", "")).strip_edges()
	var local_version: String = GatewayAPI.game_version()
	if remote_version.is_empty():
		return _result(false, false, "manifest", false)
	var cmp: int = GatewayAPI.compare_versions(local_version, remote_version)
	# Windows only downloads when latest.json's version is *strictly newer*.
	# Rebuilding the zip at the same config/version (workflow_dispatch without a
	# bump) leaves existing EXEs on the old .pck forever — the browser still
	# picks up new WASM because it is not version-gated this way.
	if cmp >= 0 and not force:
		if cmp == 0:
			push_warning(
				"ClientUpdater: local %s == remote %s — skip (bump config/version to ship)"
				% [local_version, remote_version]
			)
		_cleanup_install_leftovers(install_dir)
		return _result(true, false, "", false)
	if cmp >= 0 and force:
		return _result(false, false, "already-latest", false)

	var zip_url: String = str(manifest.get("url", Distribution.CLIENT_DOWNLOAD_URL)).strip_edges()
	var expect_sha: String = str(manifest.get("sha256", "")).strip_edges().to_lower()
	if zip_url.is_empty() or expect_sha.is_empty():
		return _result(false, false, "manifest", true)

	# The marker survived, so a previous apply_update.cmd ran and we booted the
	# OLD build anyway — robocopy lost. Re-staging would just quit() again, so
	# bound it and hand the player a popup with the manual download instead.
	var tries: int = _apply_tries(install_dir)
	if tries >= MAX_APPLY_TRIES:
		push_warning("ClientUpdater: apply failed %d times — surfacing to the player" % tries)
		_clear_apply_marker(install_dir)
		_discard_stages(install_dir)
		return _result(false, false, "apply", true)

	# Finish a previous extract instead of downloading again and quit()-looping —
	# but only when the stage carries THIS manifest's build. A stage left from an
	# earlier release would otherwise install unverified (the sha256 check only
	# covers a fresh download), and a same-version republish pins them there.
	var stage_dir: String = _existing_stage(install_dir, remote_version, expect_sha)
	if stage_dir.is_empty():
		var zip_path: String = _temp_zip_path()
		stage_dir = _temp_stage_dir()
		_status(status, _t(&"DOWNLOADING_UPDATE"))
		var dl_ok: bool = await _download_file(host, zip_url, zip_path, status)
		if not dl_ok:
			_cleanup_path(zip_path)
			push_warning("ClientUpdater: download failed")
			return _result(false, false, "download", true)

		var got_sha: String = _sha256_file(zip_path)
		if got_sha != expect_sha:
			push_warning("ClientUpdater: sha256 mismatch (got %s want %s)" % [got_sha, expect_sha])
			_cleanup_path(zip_path)
			return _result(false, false, "checksum", true)

		_status(status, _t(&"INSTALLING_UPDATE"))
		_remove_dir(stage_dir)
		if not _extract_zip(zip_path, stage_dir):
			_cleanup_path(zip_path)
			_remove_dir(stage_dir)
			return _result(false, false, "extract", true)
		_cleanup_path(zip_path)

		if not _stage_has_exe(stage_dir):
			push_warning("ClientUpdater: staged update is missing Arkenelle.exe")
			_remove_dir(stage_dir)
			return _result(false, false, "extract", true)
		_write_stage_meta(stage_dir, remote_version, expect_sha)
	else:
		_status(status, _t(&"INSTALLING_UPDATE"))

	return _spawn_apply(host, install_dir, stage_dir, tries + 1)


static func _spawn_apply(
	host: Node, install_dir: String, stage_dir: String, tries: int
) -> Dictionary:
	var script_path: String = install_dir.path_join(APPLY_SCRIPT_NAME)
	if not _write_apply_script(script_path):
		return _result(false, false, "script", true)
	# Must be on disk before quit(): once this process is gone the marker is the
	# only way the next boot can tell a failed apply from a first attempt.
	_write_apply_marker(install_dir, tries)

	var exe_name: String = OS.get_executable_path().get_file()
	var pid: int = OS.get_process_id()
	# `start ""` detaches apply_update.cmd so it survives this process exiting.
	var err: int = OS.create_process(
		"cmd.exe",
		PackedStringArray([
			"/c",
			"start",
			"",
			"/min",
			_win_path(script_path),
			_win_path(install_dir),
			_win_path(stage_dir),
			str(pid),
			exe_name,
		])
	)
	if err < 0:
		push_warning("ClientUpdater: failed to spawn apply_update.cmd")
		_clear_apply_marker(install_dir)
		return _result(false, false, "spawn", true)
	host.get_tree().quit()
	return _result(true, true, "", true)


static func _result(ok: bool, quit: bool, error: String, needed: bool) -> Dictionary:
	return {"ok": ok, "quit": quit, "error": error, "needed": needed}


static func _temp_root() -> String:
	return OS.get_temp_dir().rstrip("/\\")


static func _temp_stage_dir() -> String:
	return _temp_root().path_join("arkenelle_update")


static func _temp_zip_path() -> String:
	return _temp_root().path_join("arkenelle_update.zip")


static func _stage_has_exe(stage_dir: String) -> bool:
	if FileAccess.file_exists(stage_dir.path_join("Arkenelle.exe")):
		return true
	var exe_name: String = OS.get_executable_path().get_file()
	return not exe_name.is_empty() and FileAccess.file_exists(stage_dir.path_join(exe_name))


static func _write_stage_meta(stage_dir: String, version: String, sha: String) -> void:
	var file: FileAccess = FileAccess.open(stage_dir.path_join(STAGE_META_NAME), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"version": version, "sha256": sha}))
	file.close()


## A stage is only reusable when it was extracted from the zip this manifest is
## advertising. Without the stamp there is nothing to compare — the sha256 check
## happens on the downloaded zip, which is deleted right after extraction.
static func _stage_matches(stage_dir: String, version: String, sha: String) -> bool:
	var meta_path: String = stage_dir.path_join(STAGE_META_NAME)
	if not FileAccess.file_exists(meta_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not (parsed is Dictionary):
		return false
	var meta: Dictionary = parsed as Dictionary
	if str(meta.get("version", "")).strip_edges() != version:
		return false
	return str(meta.get("sha256", "")).strip_edges().to_lower() == sha


static func _existing_stage(install_dir: String, version: String, sha: String) -> String:
	for candidate: String in [install_dir.path_join(STAGE_DIR_NAME), _temp_stage_dir()]:
		if not _stage_has_exe(candidate):
			continue
		if _stage_matches(candidate, version, sha):
			return candidate
		# Wrong build (or a pre-stamp stage from an older client) — drop it so the
		# next pass downloads and checksums a fresh zip instead of installing this.
		_remove_dir(candidate)
	return ""


static func _discard_stages(install_dir: String) -> void:
	_remove_dir(install_dir.path_join(STAGE_DIR_NAME))
	_remove_dir(_temp_stage_dir())


static func _apply_tries(install_dir: String) -> int:
	var marker_path: String = install_dir.path_join(APPLY_MARKER_NAME)
	if not FileAccess.file_exists(marker_path):
		return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker_path))
	if parsed is Dictionary:
		return int((parsed as Dictionary).get("tries", 0))
	return 0


static func _write_apply_marker(install_dir: String, tries: int) -> void:
	var file: FileAccess = FileAccess.open(install_dir.path_join(APPLY_MARKER_NAME), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"tries": tries}))
	file.close()


static func _clear_apply_marker(install_dir: String) -> void:
	_cleanup_path(install_dir.path_join(APPLY_MARKER_NAME))


static func _cleanup_install_leftovers(install_dir: String) -> void:
	_cleanup_path(install_dir.path_join(APPLY_SCRIPT_NAME))
	_cleanup_path(install_dir.path_join(ZIP_NAME))
	# Reaching here means this boot IS the advertised build, so the apply worked.
	_clear_apply_marker(install_dir)
	_discard_stages(install_dir)


## Localized text for a static context. `tr()` is an Object method, so calling it
## from a `static func` is a parse error that takes this entire class out of the
## build — the boot update check then silently no-ops and players keep hand-
## downloading the zip. Everything here is static, so always translate via this.
static func _t(key: StringName) -> String:
	return String(TranslationServer.translate(key))


static func _status(status: Callable, text: String) -> void:
	if status.is_valid():
		status.call(text)


static func _manifest_url() -> String:
	var override_url: String = str(CmdlineUtils.get_parsed_args().get("update-manifest", "")).strip_edges()
	if not override_url.is_empty():
		return override_url
	return Distribution.CLIENT_MANIFEST_URL


static func _fetch_manifest(host: Node) -> Dictionary:
	var http: HTTPRequest = _make_http(host)
	http.timeout = MANIFEST_TIMEOUT_SEC
	var err: Error = http.request(_manifest_url())
	if err != OK:
		http.queue_free()
		return {}
	var completed: Array = await http.request_completed
	http.queue_free()
	var result: int = int(completed[0])
	var code: int = int(completed[1])
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return {}
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed
	return {}


static func _download_file(host: Node, url: String, dest: String, status: Callable) -> bool:
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	var http: HTTPRequest = _make_http(host)
	http.timeout = DOWNLOAD_TIMEOUT_SEC
	http.download_file = dest
	http.download_chunk_size = 65536
	var done: Array = [false, -1]
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			done[0] = true
			done[1] = result if result != HTTPRequest.RESULT_SUCCESS else code
	)
	var err: Error = http.request(url)
	if err != OK:
		http.queue_free()
		return false
	while not bool(done[0]):
		var got: int = http.get_downloaded_bytes()
		var total: int = http.get_body_size()
		if total > 0:
			var pct: int = clampi(int((float(got) / float(total)) * 100.0), 0, 99)
			_status(status, _t(&"DOWNLOADING_UPDATE") + " %d%%" % pct)
		await host.get_tree().process_frame
	http.queue_free()
	var outcome: int = int(done[1])
	return outcome == 200 and FileAccess.file_exists(dest)


static func _make_http(host: Node) -> HTTPRequest:
	var http: HTTPRequest = HTTPRequest.new()
	http.use_threads = true
	http.accept_gzip = false
	http.body_size_limit = -1
	host.add_child(http)
	return http


static func _sha256_file(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var remaining: int = f.get_length()
	while remaining > 0:
		var n: int = mini(remaining, 1024 * 1024)
		ctx.update(f.get_buffer(n))
		remaining -= n
	f.close()
	return ctx.finish().hex_encode()


static func _extract_zip(zip_path: String, dest_dir: String) -> bool:
	var zip: ZIPReader = ZIPReader.new()
	if zip.open(zip_path) != OK:
		return false
	var names: PackedStringArray = zip.get_files()
	var prefix: String = _common_dir_prefix(names)
	DirAccess.make_dir_recursive_absolute(dest_dir)
	for raw_name: String in names:
		var name: String = raw_name.replace("\\", "/")
		if name.ends_with("/"):
			continue
		if name.contains(".."):
			continue
		var rel: String = name
		if not prefix.is_empty() and rel.begins_with(prefix):
			rel = rel.substr(prefix.length())
		if rel.is_empty():
			continue
		var base: String = rel.get_file()
		if base == APPLY_SCRIPT_NAME or rel.begins_with("_update"):
			continue
		var out_path: String = dest_dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var bytes: PackedByteArray = zip.read_file(raw_name)
		var out: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		if out == null:
			zip.close()
			return false
		out.store_buffer(bytes)
		out.close()
	zip.close()
	return true


static func _common_dir_prefix(names: PackedStringArray) -> String:
	var first_dirs: Dictionary = {}
	for raw_name: String in names:
		var name: String = raw_name.replace("\\", "/")
		if name.ends_with("/") or name.is_empty():
			continue
		if not name.contains("/"):
			return ""
		first_dirs[name.get_slice("/", 0)] = true
	if first_dirs.size() != 1:
		return ""
	return str(first_dirs.keys()[0]) + "/"


static func _write_apply_script(path: String) -> bool:
	var body: String = """@echo off
setlocal EnableExtensions
set "INSTALL=%~1"
set "STAGE=%~2"
set "WAITPID=%~3"
set "EXENAME=%~4"
set "LOG=%INSTALL%\\apply_update.log"
echo %DATE% %TIME% start pid=%WAITPID% > "%LOG%"
echo install=%INSTALL%>> "%LOG%"
echo stage=%STAGE%>> "%LOG%"
:wait
ping 127.0.0.1 -n 2 >nul
tasklist /FI "PID eq %WAITPID%" 2>nul | findstr /I "%WAITPID%" >nul
if not errorlevel 1 goto wait
echo %TIME% pid gone>> "%LOG%"
rem quit() looks like a crash; a relaunch locks Arkenelle.exe and robocopy fails.
taskkill /F /IM "%EXENAME%" >nul 2>&1
ping 127.0.0.1 -n 3 >nul
set /a TRIES=0
:retry
set /a TRIES+=1
echo %TIME% robocopy try %TRIES%>> "%LOG%"
robocopy "%STAGE%" "%INSTALL%" /E /IS /IT /R:8 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np
set "RC=%ERRORLEVEL%"
echo %TIME% robocopy exit %RC%>> "%LOG%"
if %RC% GEQ 8 (
  if %TRIES% LSS 10 (
    ping 127.0.0.1 -n 4 >nul
    goto retry
  )
  echo FAIL>> "%LOG%"
  rem Never leave the player with no game. The old build boots, finds its
  rem update_pending.json marker still there, and reports the failure.
  start "" "%INSTALL%\\%EXENAME%"
  endlocal
  exit /b 1
)
rmdir /S /Q "%STAGE%"
echo %TIME% launching>> "%LOG%"
start "" "%INSTALL%\\%EXENAME%"
endlocal
del "%~f0"
"""
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(body)
	f.close()
	return true


static func _win_path(path: String) -> String:
	return path.replace("/", "\\")


static func _cleanup_path(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _remove_dir(path: String) -> void:
	if path.is_empty():
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var child: String = path.path_join(name)
		if dir.current_is_dir():
			_remove_dir(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
