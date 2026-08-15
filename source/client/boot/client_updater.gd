class_name ClientUpdater
## Windows desktop self-update. Exported clients GET latest.json, download the
## portable zip when the remote version is newer, then spawn a cmd that replaces
## files after this process exits. Editor / web / Linux skip this path.

const MANIFEST_TIMEOUT_SEC: float = 15.0
const DOWNLOAD_TIMEOUT_SEC: float = 0.0  # disabled — zip can be ~100MB on a slow link
const STAGE_DIR_NAME: String = "_update"
const ZIP_NAME: String = "_update_download.zip"
const APPLY_SCRIPT_NAME: String = "apply_update.cmd"


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
	var manifest: Dictionary = await _fetch_manifest(host)
	if manifest.is_empty():
		push_warning("ClientUpdater: could not fetch latest.json")
		return _result(false, false, "manifest", false)
	var remote_version: String = str(manifest.get("version", "")).strip_edges()
	var local_version: String = GatewayAPI.game_version()
	if remote_version.is_empty():
		return _result(false, false, "manifest", false)
	var cmp: int = GatewayAPI.compare_versions(local_version, remote_version)
	if cmp >= 0 and not force:
		return _result(true, false, "", false)
	if cmp >= 0 and force:
		return _result(false, false, "already-latest", false)

	var zip_url: String = str(manifest.get("url", Distribution.CLIENT_DOWNLOAD_URL)).strip_edges()
	var expect_sha: String = str(manifest.get("sha256", "")).strip_edges().to_lower()
	if zip_url.is_empty() or expect_sha.is_empty():
		return _result(false, false, "manifest", true)

	var install_dir: String = OS.get_executable_path().get_base_dir()
	var zip_path: String = install_dir.path_join(ZIP_NAME)
	var stage_dir: String = install_dir.path_join(STAGE_DIR_NAME)
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

	if not FileAccess.file_exists(stage_dir.path_join("Arkenelle.exe")) \
			and not FileAccess.file_exists(stage_dir.path_join(OS.get_executable_path().get_file())):
		push_warning("ClientUpdater: staged update is missing Arkenelle.exe")
		_remove_dir(stage_dir)
		return _result(false, false, "extract", true)

	var script_path: String = install_dir.path_join(APPLY_SCRIPT_NAME)
	if not _write_apply_script(script_path):
		_remove_dir(stage_dir)
		return _result(false, false, "script", true)

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
		_remove_dir(stage_dir)
		return _result(false, false, "spawn", true)
	host.get_tree().quit()
	return _result(true, true, "", true)


static func _result(ok: bool, quit: bool, error: String, needed: bool) -> Dictionary:
	return {"ok": ok, "quit": quit, "error": error, "needed": needed}


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
:wait
ping 127.0.0.1 -n 2 >nul
tasklist /FI "PID eq %WAITPID%" 2>nul | findstr /I "%WAITPID%" >nul
if not errorlevel 1 goto wait
robocopy "%STAGE%" "%INSTALL%" /E /IS /IT /NFL /NDL /NJH /NJS /nc /ns /np
if errorlevel 8 exit /b 1
rmdir /S /Q "%STAGE%"
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
