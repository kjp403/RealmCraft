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

	var updater: String = FileAccess.get_file_as_string(
		"res://source/client/boot/client_updater.gd"
	)
	if updater.find("class_name ClientUpdater") < 0:
		failures.append("ClientUpdater class missing")
	if updater.find("apply_if_needed") < 0:
		failures.append("ClientUpdater missing apply_if_needed")
	if updater.find("apply_update.cmd") < 0:
		failures.append("ClientUpdater must spawn apply_update.cmd")
	if updater.find("skip-update") < 0:
		failures.append("ClientUpdater must honor --skip-update")

	var gateway: String = FileAccess.get_file_as_string(
		"res://source/client/gateway/gateway.gd"
	)
	if gateway.find("ClientUpdater.apply_if_needed") < 0:
		failures.append("gateway boot must call ClientUpdater")
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
