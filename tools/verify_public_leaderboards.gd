extends SceneTree
## Source checks for the public website leaderboard API.
## Run: godot --headless --path . -s tools/verify_public_leaderboards.gd
## Expect: VERIFY_PASS

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	var svc: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/leaderboard/leaderboard_service.gd"
	)
	if svc.find("PUBLIC_BOARDS") < 0:
		failures.append("LeaderboardService missing PUBLIC_BOARDS")
	if svc.find("static func public_snapshot") < 0:
		failures.append("LeaderboardService missing public_snapshot")
	if svc.find('"dungeon:Dungeon"') < 0:
		failures.append("PUBLIC_BOARDS must include dungeon:Dungeon")
	if svc.find('"name": str(entry.get("name", ""))') < 0:
		failures.append("public_snapshot must publish display names")
	if svc.find('"id":') >= 0 and svc.find("public_snapshot") >= 0:
		var snap_at: int = svc.find("static func public_snapshot")
		var snap_body: String = svc.substr(snap_at, 900)
		if snap_body.find('"id"') >= 0:
			failures.append("public_snapshot must not publish player/guild ids")

	var world: String = FileAccess.get_file_as_string(
		"res://source/server/world/components/world_manager_client.gd"
	)
	if world.find('"leaderboards": leaderboards') < 0:
		failures.append("world heartbeat must include leaderboards")

	var master: String = FileAccess.get_file_as_string(
		"res://source/server/master/components/master_world_server/master_world_server.gd"
	)
	if master.find("func public_leaderboards()") < 0:
		failures.append("master missing public_leaderboards()")

	var gateway_master: String = FileAccess.get_file_as_string(
		"res://source/server/master/components/master_gateway_server/master_gateway_server.gd"
	)
	if gateway_master.find('"public_leaderboards"') < 0:
		failures.append("gateway manager missing public_leaderboards action")

	var http: String = FileAccess.get_file_as_string(
		"res://source/server/gateway/http_server.gd"
	)
	if http.find("&\"/v1/leaderboards\"") < 0:
		failures.append("gateway HTTP missing GET /v1/leaderboards")
	if http.find("func handle_leaderboards") < 0:
		failures.append("gateway HTTP missing handle_leaderboards")

	var api: String = FileAccess.get_file_as_string(
		"res://source/common/network/gateway_api.gd"
	)
	if api.find("/v1/leaderboards") < 0:
		failures.append("GatewayAPI missing leaderboards endpoint")

	if failures.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL")
		for line: String in failures:
			print("  - " + line)
		quit(1)
		return
	quit(0)
