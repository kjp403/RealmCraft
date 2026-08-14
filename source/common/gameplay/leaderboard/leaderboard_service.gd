class_name LeaderboardService
## Tracks per-player rolling counters (PvP kills, PvE kills) across UTC day,
## UTC week, and lifetime buckets. Buckets roll over lazily — i.e. we check
## "is the stored bucket start still the current bucket?" on every increment.
## Players who never increment after a bucket boundary simply don't appear in
## that bucket's leaderboard until they do.
##
## Top-N queries are computed in GDScript over all player rows. At alpha scale
## (hundreds of rows) this is well under a millisecond per call; if/when the
## roster grows large enough to matter, swap in indexed columns or a cached
## ZSET-style structure.

const DAY_MS: int = 24 * 60 * 60 * 1000
const WEEK_MS: int = 7 * DAY_MS

# --- Server-side: record events ---

## Hook from HostileNpc._reward_killer. Increments PvE counters on the killer.
static func record_pve_kill(killer: Player) -> void:
	if killer == null or killer.player_resource == null:
		return
	_increment(killer.player_resource, "pve_kills")
	if killer.player_resource.active_guild_id > 0:
		BasingService.record_guild_kill(killer.player_resource.active_guild_id)


## Hook from Player.die(killer). Increments PvP counters on the killer, only
## if the killer is a Player (NPC -> player deaths aren't PvP).
static func record_pvp_kill(killer: Character) -> void:
	if killer == null or killer is not Player:
		return
	var killer_player: Player = killer
	if killer_player.player_resource == null:
		return
	_increment(killer_player.player_resource, "pvp_kills")
	if killer_player.player_resource.active_guild_id > 0:
		BasingService.record_guild_kill(killer_player.player_resource.active_guild_id)
		# Glory: a guilded member's PvP kill feeds the 200-kill SG milestone (global, not
		# territory-gated — bases can span several instances, so no Area2D can cover them).
		BasingService.credit_glory_kill(killer_player.player_resource.active_guild_id)


## Record a dungeon clear time (seconds) — keeps the player's BEST (lowest) per
## dungeon in lb_stats["dungeon_best"]. The "dungeon:<name>" board ranks these
## ASCENDING (fastest first). Data-only (lb_stats JSON), no schema change. Called
## for HARD clears only — the fixed hand-designed course is the fair race.
static func record_dungeon_clear(player: Player, dungeon_name: String, seconds: int) -> void:
	if player == null or player.player_resource == null or seconds <= 0:
		return
	var stats: Dictionary = player.player_resource.lb_stats
	var best: Dictionary = stats.get("dungeon_best", {})
	var prev: int = int(best.get(dungeon_name, 0))
	if prev == 0 or seconds < prev:
		best[dungeon_name] = seconds
		stats["dungeon_best"] = best


# --- Server-side: top-N ---

## board ids:
##   pvp_day, pvp_week, pvp_total
##   pve_day, pve_week, pve_total
##   level           (combat level)
##   total_level     (sum of JobRegistry skill levels — Skills panel "Total level")
##   gold            (richest — total gold held in inventory)
##   glory_seasonal, glory_eternal
##
## Returns an Array of {id, name, score, [bonus_field]} entries, ranked.
static func top_n(world_server: Node, board: String, limit: int) -> Array:
	if world_server == null or world_server.database == null:
		return []
	limit = clampi(limit, 1, 100)

	if board.begins_with("glory_"):
		return _top_n_guild(world_server, board, limit)
	if board.begins_with("dungeon:"):
		return _top_n_dungeon(world_server, board.substr(8), limit)
	return _top_n_player(world_server, board, limit)


## Boards the public website / HTTP API publishes. Keep in sync with the in-game
## Leaderboard menu (source/client/ui/menus/leaderboard/leaderboard_menu.gd DOMAINS).
const PUBLIC_BOARDS: Array[String] = [
	"pvp_total",
	"pvp_week",
	"pve_total",
	"pve_week",
	"arena_wins",
	"glory_seasonal",
	"glory_eternal",
	"total_level",
	"level",
	"gold",
	"dungeon:Dungeon",
]
const PUBLIC_LIMIT: int = 20
const PUBLIC_CACHE_TTL_MS: int = 10000
static var _public_cache: Dictionary = {}
static var _public_cache_ms: int = 0


## Sanitized top-N for every public board: { board_id: [ {name, score}, ... ] }.
## No player/guild ids — the website only needs display names. Cached so the
## world's 10s heartbeat does not re-scan the roster every tick.
static func public_snapshot(world_server: Node) -> Dictionary:
	var now: int = Time.get_ticks_msec()
	if not _public_cache.is_empty() and now - _public_cache_ms < PUBLIC_CACHE_TTL_MS:
		return _public_cache
	var boards: Dictionary = {}
	for board: String in PUBLIC_BOARDS:
		var rows: Array = []
		for entry: Dictionary in top_n(world_server, board, PUBLIC_LIMIT):
			rows.append({
				"name": str(entry.get("name", "")),
				"score": int(entry.get("score", 0)),
			})
		boards[board] = rows
	_public_cache = boards
	_public_cache_ms = now
	return boards


# --- internals ---

static func _increment(player: PlayerResource, base_key: String) -> void:
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	_roll_buckets(player.lb_stats, now_ms)
	player.lb_stats[base_key + "_day"] = int(player.lb_stats.get(base_key + "_day", 0)) + 1
	player.lb_stats[base_key + "_week"] = int(player.lb_stats.get(base_key + "_week", 0)) + 1
	player.lb_stats[base_key + "_total"] = int(player.lb_stats.get(base_key + "_total", 0)) + 1
	# Don't save_player here — the existing periodic save / save-on-disconnect
	# captures it. Avoiding per-kill DB writes keeps the kill path cheap.


## Reset any expired day/week counters so they start fresh at the new bucket.
## Stamps the new bucket start so we don't reset again until the next boundary.
static func _roll_buckets(stats: Dictionary, now_ms: int) -> void:
	var day_start: int = _day_start_ms(now_ms)
	if int(stats.get("lb_bucket_day_ms", 0)) != day_start:
		stats["lb_bucket_day_ms"] = day_start
		stats["pvp_kills_day"] = 0
		stats["pve_kills_day"] = 0
	var week_start: int = _week_start_ms(now_ms)
	if int(stats.get("lb_bucket_week_ms", 0)) != week_start:
		stats["lb_bucket_week_ms"] = week_start
		stats["pvp_kills_week"] = 0
		stats["pve_kills_week"] = 0


static func _day_start_ms(now_ms: int) -> int:
	# UTC day boundary.
	@warning_ignore("integer_division")
	return (now_ms / DAY_MS) * DAY_MS


static func _week_start_ms(now_ms: int) -> int:
	# UTC Monday boundary. Godot's WEEKDAY enum starts at SUNDAY=0.
	var day_start: int = _day_start_ms(now_ms)
	@warning_ignore("integer_division")
	var dow: int = Time.get_datetime_dict_from_unix_time(day_start / 1000).weekday
	var days_since_monday: int = (dow + 6) % 7
	return day_start - days_since_monday * DAY_MS


static func _top_n_player(world_server: Node, board: String, limit: int) -> Array:
	var db = world_server.database.store.db
	db.query(
		"SELECT player_id, account_name, display_name, level, experience, "
		+ "stats_json, inventory_json, skills_json, server_roles_json FROM players;"
	)
	var rows: Array = db.query_result.duplicate()
	var gold_id: int = Economy.gold_id()
	var role_definitions: Dictionary = ServerInstance.global_role_definitions

	# Index online players by player_id so live counters override the (stale)
	# DB row. _increment doesn't flush to disk on every kill — saving each kill
	# would cost a DB write per arrow — so without this merge the leaderboard
	# would only reflect what was saved on the player's last disconnect.
	var live_by_player_id: Dictionary = {}
	for peer_id: int in world_server.connected_players:
		var p: PlayerResource = world_server.connected_players[peer_id]
		if p != null:
			live_by_player_id[p.player_id] = p

	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var day_start: int = _day_start_ms(now_ms)
	var week_start: int = _week_start_ms(now_ms)

	var scored: Array = []
	for row: Dictionary in rows:
		var player_id: int = int(row.get("player_id", 0))
		var live: PlayerResource = live_by_player_id.get(player_id)

		var stats: Dictionary
		var level: int
		var display_name: String
		var experience: int
		var skills_dict: Dictionary
		var roles: Dictionary
		if live != null:
			stats = live.lb_stats
			level = live.level
			display_name = live.display_name
			experience = live.experience
			skills_dict = live.skills
			roles = live.server_roles
		else:
			var parsed: Variant = JSON.parse_string(str(row.get("stats_json", "{}")))
			stats = parsed if parsed is Dictionary else {}
			level = int(row.get("level", 1))
			display_name = str(row.get("display_name", "?"))
			experience = int(row.get("experience", 0))
			var skills_parsed: Variant = JSON.parse_string(str(row.get("skills_json", "{}")))
			skills_dict = skills_parsed if skills_parsed is Dictionary else {}
			var roles_parsed: Variant = JSON.parse_string(str(row.get("server_roles_json", "{}")))
			roles = roles_parsed if roles_parsed is Dictionary else {}

		# Hide admin / senior_admin / owner from boards (moderators stay).
		# Character-bound: regular alts on a staff login still appear.
		if CommandPermissions.is_hidden_from_leaderboard(
			roles, role_definitions, display_name, player_id
		):
			continue

		var score: int = 0
		var sub: int = 0
		match board:
			"pvp_day":
				if int(stats.get("lb_bucket_day_ms", 0)) == day_start:
					score = int(stats.get("pvp_kills_day", 0))
			"pvp_week":
				if int(stats.get("lb_bucket_week_ms", 0)) == week_start:
					score = int(stats.get("pvp_kills_week", 0))
			"pvp_total":
				score = int(stats.get("pvp_kills_total", 0))
			"pve_day":
				if int(stats.get("lb_bucket_day_ms", 0)) == day_start:
					score = int(stats.get("pve_kills_day", 0))
			"pve_week":
				if int(stats.get("lb_bucket_week_ms", 0)) == week_start:
					score = int(stats.get("pve_kills_week", 0))
			"pve_total":
				score = int(stats.get("pve_kills_total", 0))
			"arena_wins":
				score = int(stats.get("arena_wins", 0))
			"level":
				score = level
				sub = experience
			"total_level":
				# Skills-panel Total level: sum of every JobRegistry skill (missing = 1).
				# Tie-break on summed skill XP so equal totals still order by grind depth.
				score = total_skill_level_of(skills_dict)
				sub = _total_skill_xp_of(skills_dict)
			"gold":
				# Richest board — total gold held. Live players use their
				# in-memory inventory; offline rows parse the saved JSON.
				var inv: Dictionary
				if live != null:
					inv = live.inventory
				else:
					var inv_parsed: Variant = JSON.parse_string(str(row.get("inventory_json", "{}")))
					inv = inv_parsed if inv_parsed is Dictionary else {}
				score = Inventory.count(inv, gold_id)
			_:
				continue
		if score <= 0 and board != "level" and board != "total_level":
			continue # Zero-score rows clutter the board.
		scored.append({
			"id": player_id,
			"name": display_name,
			"score": score,
			"sub": sub,
		})

	# Sort: primary descending score, secondary descending sub (XP for level boards).
	scored.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["sub"] > b["sub"]
	)
	return scored.slice(0, limit)


## Skill slugs that feed Total Level. Keep in sync with JobRegistry.JOBS — listed here
## as plain StringNames so this service never preload-cycles through JobPerks .tres files.
const TOTAL_LEVEL_SKILLS: Array[StringName] = [
	&"mining",
	&"harvesting",
	&"woodcutting",
	&"fishing",
	&"smithing",
	&"outfitting",
	&"cooking",
	&"herblore",
	&"fletching",
	&"slayer",
]


## Sum of every registered job's skill level. Missing / unstarted skills count as 1 —
## same rule as the Skills panel "Total level" line (skills.get iterates JobRegistry).
## skills_json keys may be String (from JSON) or StringName (live PlayerResource).
static func total_skill_level_of(skills: Dictionary) -> int:
	var total: int = 0
	for job_slug: StringName in TOTAL_LEVEL_SKILLS:
		var entry: Variant = skills.get(job_slug, skills.get(String(job_slug), null))
		if entry is Dictionary:
			total += maxi(1, int((entry as Dictionary).get("level", 1)))
		else:
			total += 1
	return total


## Summed in-progress skill XP across Total Level skills — tie-breaker for total_level.
static func _total_skill_xp_of(skills: Dictionary) -> int:
	var total: int = 0
	for job_slug: StringName in TOTAL_LEVEL_SKILLS:
		var entry: Variant = skills.get(job_slug, skills.get(String(job_slug), null))
		if entry is Dictionary:
			total += maxi(0, int((entry as Dictionary).get("xp", 0)))
	return total


## Fastest-clear board for one dungeon. Score = best clear SECONDS, ranked
## ASCENDING (lower is better) — the inverse of the kill/level boards. Live players
## override their stale DB row, same as _top_n_player.
static func _top_n_dungeon(world_server: Node, dungeon_name: String, limit: int) -> Array:
	var db = world_server.database.store.db
	db.query("SELECT player_id, account_name, display_name, stats_json, server_roles_json FROM players;")
	var rows: Array = db.query_result.duplicate()
	var role_definitions: Dictionary = ServerInstance.global_role_definitions

	var live_by_player_id: Dictionary = {}
	for peer_id: int in world_server.connected_players:
		var p: PlayerResource = world_server.connected_players[peer_id]
		if p != null:
			live_by_player_id[p.player_id] = p

	var scored: Array = []
	for row: Dictionary in rows:
		var player_id: int = int(row.get("player_id", 0))
		var live: PlayerResource = live_by_player_id.get(player_id)
		var stats: Dictionary
		var display_name: String
		var roles: Dictionary
		if live != null:
			stats = live.lb_stats
			display_name = live.display_name
			roles = live.server_roles
		else:
			var parsed: Variant = JSON.parse_string(str(row.get("stats_json", "{}")))
			stats = parsed if parsed is Dictionary else {}
			display_name = str(row.get("display_name", "?"))
			var roles_parsed: Variant = JSON.parse_string(str(row.get("server_roles_json", "{}")))
			roles = roles_parsed if roles_parsed is Dictionary else {}
		if CommandPermissions.is_hidden_from_leaderboard(
			roles, role_definitions, display_name, player_id
		):
			continue
		var best: Variant = stats.get("dungeon_best", {})
		if best is not Dictionary:
			continue
		var seconds: int = int((best as Dictionary).get(dungeon_name, 0))
		if seconds <= 0:
			continue
		scored.append({"id": player_id, "name": display_name, "score": seconds, "sub": 0})
	scored.sort_custom(func(a, b): return a["score"] < b["score"]) # fastest first
	return scored.slice(0, limit)


static func _top_n_guild(world_server: Node, board: String, limit: int) -> Array:
	var db = world_server.database.store.db
	db.query("SELECT guild_id, guild_name, data_json FROM guilds;")
	var rows: Array = db.query_result.duplicate()

	var scored: Array = []
	for row: Dictionary in rows:
		var data: Variant = JSON.parse_string(str(row.get("data_json", "{}")))
		if data is not Dictionary:
			continue
		var score: int = 0
		match board:
			"glory_seasonal":
				score = int(data.get("seasonal_glory", 0))
			"glory_eternal":
				score = int(data.get("eternal_glory", 0))
			_:
				continue
		if score <= 0:
			continue
		scored.append({
			"id": int(row.get("guild_id", 0)),
			"name": str(row.get("guild_name", "?")),
			"score": score,
			"sub": 0,
		})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	return scored.slice(0, limit)


# --- Server-side: in-world champion statues ---

## Boards the plaza statues display. Guild Hall currently showcases Total Level only
## (PvP disabled; PvE podium deferred). Each ChampionStatue picks its board from its
## @export category; this is the set we resolve + cache.
const STATUE_BOARDS: Array[String] = ["total_level"]
## How deep each board's hall of fame goes — a statue's @export rank (1..N) picks its slot, so
## this caps how many ranks can be enshrined per board. Ranking already sorts the whole roster
## either way (top_n), so a bigger N only adds that many skin lookups per board per refresh.
## Guild Hall places ranks 1–3; keep headroom for future podiums.
const STATUE_TOP_N: int = 10
## Cache so a plaza full of players doesn't each re-rank the whole roster + hit the DB for skins.
## Per-process (per-world). All-time champions change rarely, so the TTL is generous — the hall of
## fame may lag a leaderboard change by a few minutes, which is fine for an aspirational board.
const STATUE_CACHE_TTL_MS: int = 300000 # 5 min
static var _statue_cache: Dictionary = {}
static var _statue_cache_ms: int = 0


## Drop the plaza champions cache (e.g. after /reloadadmins so newly hidden
## staff leave the Guild Hall statues immediately).
static func invalidate_champions_cache() -> void:
	_statue_cache.clear()
	_statue_cache_ms = 0
	_public_cache.clear()
	_public_cache_ms = 0


## Top-N of each statue board, best-first, each entry carrying the player's skin:
## { board: [ {id, name, score, skin_id}, ... ] }. The ONLY place skin_id rides with leaderboard
## data — kept off the leaderboard.top menu path on purpose. Cached; pulled by the statue plaza
## on area-enter. Offline-safe. A statue indexes this by its (category -> board, rank).
static func champions(world_server: Node) -> Dictionary:
	var now: int = Time.get_ticks_msec()
	if not _statue_cache.is_empty() and now - _statue_cache_ms < STATUE_CACHE_TTL_MS:
		return _statue_cache
	var out: Dictionary = {}
	for board: String in STATUE_BOARDS:
		var ranked: Array = []
		for entry: Dictionary in top_n(world_server, board, STATUE_TOP_N):
			ranked.append({
				"id": int(entry["id"]), # player_id — for the statue's click-to-profile
				"name": entry["name"],
				"score": entry["score"],
				"skin_id": _skin_id_for(world_server, int(entry["id"])),
			})
		if not ranked.is_empty():
			out[board] = ranked
	_statue_cache = out
	_statue_cache_ms = now
	return out


## A player's equipped skin_id — live in-memory if online, else the persisted players.skin_id
## column (so a champion's statue still shows their look while they're offline).
static func _skin_id_for(world_server: Node, player_id: int) -> int:
	for peer_id: int in world_server.connected_players:
		var p: PlayerResource = world_server.connected_players[peer_id]
		if p != null and p.player_id == player_id:
			return p.skin_id
	if world_server.database == null or world_server.database.store == null:
		return 1
	var db = world_server.database.store.db
	db.query("SELECT skin_id FROM players WHERE player_id = %d;" % player_id)
	var rows: Array = db.query_result
	return int(rows[0].get("skin_id", 1)) if not rows.is_empty() else 1
