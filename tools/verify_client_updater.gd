extends SceneTree
## Source checks for the self-hosted Windows client updater.
## Run: godot --headless --path . -s tools/verify_client_updater.gd
## Expect: VERIFY_PASS

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	var dist: String = FileAccess.get_file_as_string(
		"res://source/common/network/distribution.gd"
	)
	if dist.find("CLIENT_DOWNLOAD_URL") < 0:
		failures.append("Distribution missing CLIENT_DOWNLOAD_URL")
	if dist.find("CLIENT_MANIFEST_URL") < 0:
		failures.append("Distribution missing CLIENT_MANIFEST_URL")
	if dist.find("play.arkenelle.com/desktop/") < 0:
		failures.append("desktop URLs must live on play.arkenelle.com/desktop/")

	# The updater is 100% static, so a `tr()` (an Object method) anywhere inside it
	# is a parse error that drops the whole class from the build. The client still
	# boots, the boot-time check silently no-ops, and players hand-download the zip
	# forever. String checks alone never caught that — actually load the script.
	var updater_path: String = "res://source/client/boot/client_updater.gd"
	if load(updater_path) == null:
		failures.append("client_updater.gd does not compile (see parse errors above)")
	var updater: String = FileAccess.get_file_as_string(updater_path)
	for i: int in updater.split("
").size():
		var line: String = updater.split("
")[i]
		if line.strip_edges().begins_with("#"):
			continue
		if line.contains(" tr(") or line.contains("	tr(") or line.contains("(tr("):
			failures.append(
				"client_updater.gd:%d calls tr() — static-only class, use _t()" % (i + 1)
			)
	if updater.find("class_name ClientUpdater") < 0:
		failures.append("ClientUpdater class missing")
	if updater.find("apply_if_needed") < 0:
		failures.append("ClientUpdater missing apply_if_needed")
	if updater.find("apply_update.cmd") < 0:
		failures.append("ClientUpdater must spawn apply_update.cmd")
	if updater.find("skip-update") < 0:
		failures.append("ClientUpdater must honor --skip-update")
	if updater.find("\"needed\"") < 0:
		failures.append("ClientUpdater must report whether an update was needed")
	if updater.find("accept_gzip = false") < 0:
		failures.append("ClientUpdater must disable gzip on the zip download")
	if updater.find("\"/min\"") < 0:
		failures.append("ClientUpdater must detach apply_update.cmd via start /min")
	if updater.find("get_temp_dir") < 0:
		failures.append("ClientUpdater must stage the zip in OS.get_temp_dir() (not OneDrive)")
	if updater.find("taskkill") < 0:
		failures.append("apply_update.cmd must taskkill a relaunched EXE before robocopy")
	if updater.find("apply_update.log") < 0:
		failures.append("apply_update.cmd must write apply_update.log on failure")
	if updater.find("_existing_stage") < 0:
		failures.append("ClientUpdater must resume a staged extract instead of re-downloading")

	var gateway: String = FileAccess.get_file_as_string(
		"res://source/client/gateway/gateway.gd"
	)
	if gateway.find("ClientUpdater.apply_if_needed") < 0:
		failures.append("gateway boot must call ClientUpdater")
	if gateway.find("UPDATE_FAILED") < 0:
		failures.append("gateway must surface updater failures instead of ignoring them")
	if gateway.find("Distribution.CLIENT_DOWNLOAD_URL") < 0:
		failures.append("outdated-client fallback must be CLIENT_DOWNLOAD_URL")
	if gateway.find("ITCH_APP_URL") >= 0:
		failures.append("gateway Update must not open itch://")

	var caddy: String = FileAccess.get_file_as_string("res://deploy/Caddyfile")
	if caddy.find("handle_path /desktop/*") < 0:
		failures.append("Caddy must serve /desktop/ from client-windows")

	var release_path: String = ProjectSettings.globalize_path("res://").path_join(
		".github/workflows/release.yml"
	)
	var release: String = FileAccess.get_file_as_string(release_path)
	if release.find("arkenelle-windows-client.tar.gz") < 0:
		failures.append("release.yml must pack the Windows zip for the VPS")
	if release.find("publish-windows-client.sh") < 0:
		failures.append("release.yml must publish via publish-windows-client.sh")

	if failures.is_empty():
		print("VERIFY_PASS")
		quit(0)
	else:
		for f: String in failures:
			push_error(f)
			print("FAIL: ", f)
		print("VERIFY_FAIL")
		quit(1)
