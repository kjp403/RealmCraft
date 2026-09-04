extends RefCounted
class_name WorldSchema


static func ensure_schema(db: SQLite) -> void:
	_create_table_if_missing(db, "meta", {
		"key": {"data_type": "text", "primary_key": true, "not_null": true},
		"value": {"data_type": "text", "not_null": true}
	})

	var version: int = _get_schema_version(db)
	if version < 1:
		_migration_v1(db)
		_set_schema_version(db, 1)
	if version < 2:
		_migration_v2(db)
		_set_schema_version(db, 2)
	if version < 3:
		_migration_v3(db)
		_set_schema_version(db, 3)
	if version < 4:
		_migration_v4(db)
		_set_schema_version(db, 4)
	if version < 5:
		_migration_v5(db)
		_set_schema_version(db, 5)
	if version < 6:
		_migration_v6(db)
		_set_schema_version(db, 6)
	if version < 7:
		_migration_v7(db)
		_set_schema_version(db, 7)
	if version < 8:
		_migration_v8(db)
		_set_schema_version(db, 8)
	if version < 9:
		_migration_v9(db)
		_set_schema_version(db, 9)
	if version < 10:
		_migration_v10(db)
		_set_schema_version(db, 10)
	if version < 11:
		_migration_v11(db)
		_set_schema_version(db, 11)
	if version < 12:
		_migration_v12(db)
		_set_schema_version(db, 12)
	if version < 13:
		_migration_v13(db)
		_set_schema_version(db, 13)
	if version < 14:
		_migration_v14(db)
		_set_schema_version(db, 14)
	if version < 15:
		_migration_v15(db)
		_set_schema_version(db, 15)
	if version < 16:
		_migration_v16(db)
		_set_schema_version(db, 16)
	if version < 17:
		_migration_v17(db)
		_set_schema_version(db, 17)
	if version < 18:
		_migration_v18(db)
		_set_schema_version(db, 18)
	if version < 19:
		_migration_v19(db)
		_set_schema_version(db, 19)
	if version < 20:
		_migration_v20(db)
		_set_schema_version(db, 20)
	if version < 21:
		_migration_v21(db)
		_set_schema_version(db, 21)
	if version < 22:
		_migration_v22(db)
		_set_schema_version(db, 22)
	if version < 23:
		_migration_v23(db)
		_set_schema_version(db, 23)
	if version < 24:
		_migration_v24(db)
		_set_schema_version(db, 24)


static func _migration_v1(db: SQLite) -> void:
	_create_table_if_missing(db, "accounts", {
		"account_name": {"data_type": "text", "primary_key": true, "not_null": true}
	})

	_create_table_if_missing(db, "players", {
		"player_id": {"data_type": "int", "primary_key": true, "not_null": true},
		"account_name": {"data_type": "text", "not_null": true},
		"display_name": {"data_type": "text", "not_null": true},
		"skin_id": {"data_type": "int", "not_null": true},
		"level": {"data_type": "int", "not_null": true},
		"experience": {"data_type": "int", "not_null": true},
		"available_attributes_points": {"data_type": "int", "not_null": true},

		"profile_status": {"data_type": "text", "not_null": true},
		"profile_animation": {"data_type": "text", "not_null": true},

		"attributes_json": {"data_type": "text", "not_null": true},
		"inventory_json": {"data_type": "text", "not_null": true},
		"equipment_json": {"data_type": "text", "not_null": true},
		"skills_json": {"data_type": "text", "not_null": true},
		"quests_json": {"data_type": "text", "not_null": true},

		"friends_json": {"data_type": "text", "not_null": true},
		"server_roles_json": {"data_type": "text", "not_null": true},
		# Free-form per-player stats — currently holds leaderboard counters
		# (pvp/pve kills × day/week/total + bucket timestamps). JSON so adding
		# new metrics later is data-only, no schema migration.
		"stats_json": {"data_type": "text", "not_null": true},
		# Vanity titles: {"unlocked": ["Master Duelist", ...], "display": "..."}.
		# Persisted separately from lb_stats so titles can grow without bloating
		# the leaderboard-counter blob.
		"titles_json": {"data_type": "text", "not_null": true},
		# Daily quest board state: {"quests": [{template_id, count_so_far,
		# claimed}, ...], "refresh_at_ms": unix-ms of next UTC midnight}.
		# Reroll happens lazily on board interaction.
		"dailies_json": {"data_type": "text", "not_null": true},

		# Guild IDs (nullable for players without a guild)
		"active_guild_id": {"data_type": "int", "not_null": false},
		"joined_guild_ids_json": {"data_type": "text", "not_null": true},
		"led_guild_id": {"data_type": "int", "not_null": false}
	})

	_create_table_if_missing(db, "guilds", {
		"guild_id": {"data_type": "int", "primary_key": true, "not_null": true, "auto_increment": true},
		"guild_name": {"data_type": "text", "not_null": true},
		"leader_id": {"data_type": "int", "not_null": true},
		"data_json": {"data_type": "text", "not_null": true}
	})
	db.query("CREATE UNIQUE INDEX IF NOT EXISTS idx_guilds_name ON guilds(guild_name);")

	_create_table_if_missing(db, "guild_members", {
		"guild_id": {"data_type": "int", "not_null": true},
		"player_id": {"data_type": "int", "not_null": true},
		"rank": {"data_type": "int", "not_null": true}
	})
	db.query("CREATE UNIQUE INDEX IF NOT EXISTS idx_guild_members_pk ON guild_members(guild_id, player_id);")

	# Territory flags. owner_guild_id = 0 means unowned. last_capture_ms is the
	# unix timestamp (ms) of the last capture, used to enforce the post-capture
	# grace period. flag_id is a designer-assigned stable id on the placed node.
	_create_table_if_missing(db, "flags", {
		"flag_id": {"data_type": "int", "primary_key": true, "not_null": true},
		"owner_guild_id": {"data_type": "int", "not_null": true},
		"last_capture_ms": {"data_type": "int", "not_null": true}
	})

	_create_table_if_missing(db, "conversations", {
		"conversation_id": {"data_type": "text", "primary_key": true, "not_null": true},
		"type": {"data_type": "text", "not_null": true}, # dm/global/guild
		"meta_json": {"data_type": "text", "not_null": true}
	})

	_create_table_if_missing(db, "messages", {
		"conversation_id": {"data_type": "text", "not_null": true},
		"msg_id": {"data_type": "int", "not_null": true},
		"time_ms": {"data_type": "int", "not_null": true},
		"sender_id": {"data_type": "int", "not_null": true},
		"sender_name": {"data_type": "text", "not_null": true},
		"text": {"data_type": "text", "not_null": true}
	})
	db.query("CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_pk ON messages(conversation_id, msg_id);")
	db.query("CREATE INDEX IF NOT EXISTS idx_messages_sender_time ON messages(sender_id, time_ms);")
	db.query("CREATE INDEX IF NOT EXISTS idx_messages_conv_time ON messages(conversation_id, time_ms);")


## v2: per-player block list. Stored as a JSON-encoded PackedInt64Array in
## the players row, mirroring how friends_json works. Idempotent so it's safe
## if a fresh DB already created the column via a future migration_v1 edit.
static func _migration_v2(db: SQLite) -> void:
	if not _column_exists(db, "players", "blocked_ids_json"):
		db.query("ALTER TABLE players ADD COLUMN blocked_ids_json TEXT NOT NULL DEFAULT '[]';")


## v3: weapon mastery. One JSON blob per player: {"masteries": {category ->
## {"level", "xp", "spent"}}, "loadout": {category -> node_id}}. See
## docs/mastery.md.
static func _migration_v3(db: SQLite) -> void:
	if not _column_exists(db, "players", "mastery_json"):
		db.query("ALTER TABLE players ADD COLUMN mastery_json TEXT NOT NULL DEFAULT '{}';")


## v4: soft dungeon lockout. One JSON blob per player: {dungeon_key -> unix-seconds
## of the last completion reward}. A re-clear inside the dungeon's window grants no
## reward (you can still run it to help). Added via ALTER — no DB wipe needed.
static func _migration_v4(db: SQLite) -> void:
	if not _column_exists(db, "players", "dungeon_lockouts_json"):
		db.query("ALTER TABLE players ADD COLUMN dungeon_lockouts_json TEXT NOT NULL DEFAULT '{}';")


## v5: owned skins for the wardrobe. JSON array of skin ids the player has purchased (the
## equipped one is players.skin_id). Added via ALTER — no DB wipe. Defaults to '[]';
## existing players backfill their current skin_id on load (see _row_to_player).
static func _migration_v5(db: SQLite) -> void:
	if not _column_exists(db, "players", "owned_skins_json"):
		db.query("ALTER TABLE players ADD COLUMN owned_skins_json TEXT NOT NULL DEFAULT '[]';")


## v6: per-character redeemed codes (see docs/redeem_codes.md). JSON array of
## upper-cased code strings the character has already claimed. Added via ALTER —
## no DB wipe. Defaults to '[]'.
static func _migration_v6(db: SQLite) -> void:
	if not _column_exists(db, "players", "redeemed_codes_json"):
		db.query("ALTER TABLE players ADD COLUMN redeemed_codes_json TEXT NOT NULL DEFAULT '[]';")


## v7: mailbox — see docs/mailbox.md. `mail` holds content once (recipient_id = 0
## means broadcast to everyone in this world); `mail_state` holds per-player
## read/claimed/deleted flags, created lazily. Two tables so a broadcast is one
## row with per-player state. Added via _create_table_if_missing — no DB wipe.
static func _migration_v7(db: SQLite) -> void:
	_create_table_if_missing(db, "mail", {
		"mail_id": {"data_type": "int", "primary_key": true, "not_null": true, "auto_increment": true},
		"recipient_id": {"data_type": "int", "not_null": true}, # 0 = broadcast to all in this world
		"sender_name": {"data_type": "text", "not_null": true},
		"subject": {"data_type": "text", "not_null": true},
		"body": {"data_type": "text", "not_null": true},
		"attachments_json": {"data_type": "text", "not_null": true},
		"created_at_ms": {"data_type": "int", "not_null": true}
	})
	db.query("CREATE INDEX IF NOT EXISTS idx_mail_recipient ON mail(recipient_id, created_at_ms DESC);")

	_create_table_if_missing(db, "mail_state", {
		"player_id": {"data_type": "int", "not_null": true},
		"mail_id": {"data_type": "int", "not_null": true},
		"read_at_ms": {"data_type": "int", "not_null": false},
		"claimed_at_ms": {"data_type": "int", "not_null": false},
		"deleted_at_ms": {"data_type": "int", "not_null": false}
	})
	db.query("CREATE UNIQUE INDEX IF NOT EXISTS idx_mail_state_pk ON mail_state(player_id, mail_id);")


## v8: guild event log (see docs/guild.md). One row per guild event (join/leave/
## kick/rank/deposit/upgrade/flag capture...), written by WorldStoreSqlite.
## add_guild_log, which also prunes each guild to its newest rows. Names are
## snapshotted at write time so the log stays a historical record even if a
## player renames. Added via _create_table_if_missing — no DB wipe.
static func _migration_v8(db: SQLite) -> void:
	_create_table_if_missing(db, "guild_log", {
		"log_id": {"data_type": "int", "primary_key": true, "not_null": true, "auto_increment": true},
		"guild_id": {"data_type": "int", "not_null": true},
		"time_ms": {"data_type": "int", "not_null": true},
		"event": {"data_type": "text", "not_null": true},
		"actor_name": {"data_type": "text", "not_null": true},
		"target_name": {"data_type": "text", "not_null": true},
		"data_json": {"data_type": "text", "not_null": true}
	})
	db.query("CREATE INDEX IF NOT EXISTS idx_guild_log_guild_time ON guild_log(guild_id, log_id DESC);")


## v9: wardstones — biome-progression keys (docs/wardstones.md). One JSON array
## of earned wardstone slugs per character ("woodland", "fungus_cave", ...);
## character-wide by design (no account ledger). ADD COLUMN — no DB wipe.
static func _migration_v9(db: SQLite) -> void:
	if not _column_exists(db, "players", "wardstones_json"):
		db.query("ALTER TABLE players ADD COLUMN wardstones_json TEXT NOT NULL DEFAULT '[]';")


## v10: character display names are unique world-wide (case-insensitive). Existing
## collisions keep the lowest player_id; later rows get a numeric suffix so the
## UNIQUE index can be created safely on live DBs that already have dupes.
static func _migration_v10(db: SQLite) -> void:
	db.query("SELECT player_id, display_name FROM players ORDER BY player_id ASC;")
	var rows: Array = db.query_result.duplicate(true)
	var claimed: Dictionary = {}
	for row: Dictionary in rows:
		var pid: int = int(row.get("player_id", 0))
		var name: String = str(row.get("display_name", ""))
		var key: String = name.to_lower()
		if pid <= 0 or name.is_empty():
			continue
		if not claimed.has(key):
			claimed[key] = true
			continue
		var candidate: String = _unique_display_name_candidate(name, claimed)
		claimed[candidate.to_lower()] = true
		db.query_with_bindings(
			"UPDATE players SET display_name=? WHERE player_id=?;",
			[candidate, pid]
		)
	db.query(
		"CREATE UNIQUE INDEX IF NOT EXISTS idx_players_display_name "
		+ "ON players(display_name COLLATE NOCASE);"
	)


## v11: personal item bank vault. Same JSON shape as inventory_json;
## ADD COLUMN — no DB wipe. Capacity arrived later in v14 (bank_slots).
static func _migration_v11(db: SQLite) -> void:
	if not _column_exists(db, "players", "bank_json"):
		db.query("ALTER TABLE players ADD COLUMN bank_json TEXT NOT NULL DEFAULT '{}';")


## v12: Slayer skill state (docs/slayer_skill.md) — current task, points, streak,
## lifetime completions, and blocked task slugs, bundled into one JSON blob the
## same way dailies_json bundles daily_quests + dailies_refresh_at_ms. ADD
## COLUMN — no DB wipe.
static func _migration_v12(db: SQLite) -> void:
	if not _column_exists(db, "players", "slayer_json"):
		db.query("ALTER TABLE players ADD COLUMN slayer_json TEXT NOT NULL DEFAULT '{}';")


## v13: chest-open staging loot (PendingChestLoot). JSON array of
## {id, a} stacks held until the player claims into bag/bank. ADD COLUMN —
## no DB wipe. Defaults to '[]'.
static func _migration_v13(db: SQLite) -> void:
	if not _column_exists(db, "players", "pending_chest_loot_json"):
		db.query("ALTER TABLE players ADD COLUMN pending_chest_loot_json TEXT NOT NULL DEFAULT '[]';")


## v14: personal bank capacity. Starts at 50 slots; banker sells +50 for 5,000G
## with no purchase cap. ADD COLUMN — no DB wipe.
static func _migration_v14(db: SQLite) -> void:
	if not _column_exists(db, "players", "bank_slots"):
		db.query("ALTER TABLE players ADD COLUMN bank_slots INTEGER NOT NULL DEFAULT 50;")


## v15: equipped cosmetic VFX (aura / trail / halo / ...). 0 = none, which is what
## every existing character migrates to. Only the EQUIPPED id is stored — ownership
## is not persisted because cosmetics are unobtainable for now and staff access is
## derived live from rank, so a demoted admin simply stops rendering one.
## ADD COLUMN — no DB wipe.
static func _migration_v15(db: SQLite) -> void:
	if not _column_exists(db, "players", "cosmetic_id"):
		db.query("ALTER TABLE players ADD COLUMN cosmetic_id INTEGER NOT NULL DEFAULT 0;")


## v16: equipped WEAPON cosmetic (the Ascended glow), a second cosmetic slot so a
## player can wear an aura and a weapon effect at once. 0 = none. ADD COLUMN with a
## DEFAULT — no wipe, and older code that omits the column still writes fine.
static func _migration_v16(db: SQLite) -> void:
	if not _column_exists(db, "players", "weapon_cosmetic_id"):
		db.query("ALTER TABLE players ADD COLUMN weapon_cosmetic_id INTEGER NOT NULL DEFAULT 0;")


## v17: story flags for the Hollow Seep campaign (and any later quest-gated
## NPC visibility). JSON object of flag slug -> true. ADD COLUMN — no DB wipe.
static func _migration_v17(db: SQLite) -> void:
	if not _column_exists(db, "players", "character_flags_json"):
		db.query("ALTER TABLE players ADD COLUMN character_flags_json TEXT NOT NULL DEFAULT '{}';")


## v18: equipped prestige vault skin (recolor + body-sprite VFX). 0 = none.
## Staff-only; stripped on spawn if the wearer is no longer admin+. ADD COLUMN.
static func _migration_v18(db: SQLite) -> void:
	if not _column_exists(db, "players", "vault_skin_id"):
		db.query("ALTER TABLE players ADD COLUMN vault_skin_id INTEGER NOT NULL DEFAULT 0;")


## v19: the Hunt Chest (HuntChest) — the persistent Guild Hall stash Boss Hunt
## loot is banked into. JSON array of {id, a} stacks, same shape as
## pending_chest_loot but never auto-flushed. ADD COLUMN — no DB wipe.
static func _migration_v19(db: SQLite) -> void:
	if not _column_exists(db, "players", "hunt_chest_json"):
		db.query("ALTER TABLE players ADD COLUMN hunt_chest_json TEXT NOT NULL DEFAULT '[]';")


## v20: unlocked inventory bag count. Players start at 1; banker sells bags 2 and 3.
## ADD COLUMN with DEFAULT — no DB wipe; existing players get 1 bag.
static func _migration_v20(db: SQLite) -> void:
	if not _column_exists(db, "players", "inventory_bags"):
		db.query("ALTER TABLE players ADD COLUMN inventory_bags INTEGER NOT NULL DEFAULT 1;")


## v21: the player Trading Post (docs in source/common/gameplay/market/market.gd).
## `market_stores` is one row per character (their stall); `market_listings` holds
## the ESCROWED goods — a listed stack has already left the seller's bag, so the
## row itself is the item's only home until it sells, is pulled, or expires. Two
## tables so a store can be renamed / closed without touching its stock.
static func _migration_v21(db: SQLite) -> void:
	_create_table_if_missing(db, "market_stores", {
		"store_id": {"data_type": "int", "primary_key": true, "not_null": true, "auto_increment": true},
		"owner_id": {"data_type": "int", "not_null": true},
		"store_name": {"data_type": "text", "not_null": true},
		"is_open": {"data_type": "int", "not_null": true},
		"updated_at_ms": {"data_type": "int", "not_null": true}
	})
	db.query("CREATE UNIQUE INDEX IF NOT EXISTS idx_market_stores_owner ON market_stores(owner_id);")

	# state: 0 = active (escrowed, buyable), 1 = sold out, 2 = pulled by the seller.
	# amount is decremented in place on a partial buy; a listing flips to state 1
	# only when it hits 0, so one row serves an entire stack.
	_create_table_if_missing(db, "market_listings", {
		"listing_id": {"data_type": "int", "primary_key": true, "not_null": true, "auto_increment": true},
		"store_id": {"data_type": "int", "not_null": true},
		"seller_id": {"data_type": "int", "not_null": true},
		"seller_name": {"data_type": "text", "not_null": true},
		"item_id": {"data_type": "int", "not_null": true},
		"amount": {"data_type": "int", "not_null": true},
		"unit_price": {"data_type": "int", "not_null": true},
		"state": {"data_type": "int", "not_null": true},
		"created_at_ms": {"data_type": "int", "not_null": true}
	})
	db.query("CREATE INDEX IF NOT EXISTS idx_market_listings_store ON market_listings(store_id, state);")
	db.query("CREATE INDEX IF NOT EXISTS idx_market_listings_seller ON market_listings(seller_id, state);")
	db.query("CREATE INDEX IF NOT EXISTS idx_market_listings_item ON market_listings(item_id, state);")


## v22: Trading Post sale history. One row per completed purchase, written inside
## the same transaction as the sale itself, so the ticker can never show a trade
## that was rolled back. This is what gives players a real price signal — a stall
## owner prices against what things ACTUALLY sold for, not against a guess.
## Names are snapshotted at write time, like guild_log, so the history stays a
## historical record if someone renames.
static func _migration_v22(db: SQLite) -> void:
	_create_table_if_missing(db, "market_trades", {
		"trade_id": {"data_type": "int", "primary_key": true, "not_null": true, "auto_increment": true},
		"item_id": {"data_type": "int", "not_null": true},
		"amount": {"data_type": "int", "not_null": true},
		"unit_price": {"data_type": "int", "not_null": true},
		"total": {"data_type": "int", "not_null": true},
		"seller_id": {"data_type": "int", "not_null": true},
		"seller_name": {"data_type": "text", "not_null": true},
		"buyer_id": {"data_type": "int", "not_null": true},
		"buyer_name": {"data_type": "text", "not_null": true},
		"sold_at_ms": {"data_type": "int", "not_null": true}
	})
	db.query("CREATE INDEX IF NOT EXISTS idx_market_trades_item ON market_trades(item_id, trade_id DESC);")
	db.query("CREATE INDEX IF NOT EXISTS idx_market_trades_recent ON market_trades(trade_id DESC);")


static func _unique_display_name_candidate(base: String, claimed: Dictionary) -> String:
	# Prefer base_2, base_3, … truncated to the username max length (20).
	const MAX_LEN: int = 20
	var n: int = 2
	while n < 10000:
		var suffix: String = "_%d" % n
		var stem: String = base
		if stem.length() + suffix.length() > MAX_LEN:
			stem = stem.substr(0, maxi(1, MAX_LEN - suffix.length()))
		var candidate: String = stem + suffix
		if not claimed.has(candidate.to_lower()):
			return candidate
		n += 1
	return "%s_%d" % [base.substr(0, maxi(1, MAX_LEN - 6)), randi() % 100000]


static func _column_exists(db: SQLite, table: String, column: String) -> bool:
	db.query("PRAGMA table_info(%s);" % table)
	for row: Dictionary in db.query_result:
		if str(row.get("name", "")) == column:
			return true
	return false


static func _create_table_if_missing(db: SQLite, table: String, dict: Dictionary) -> void:
	db.query_with_bindings(
		"SELECT name FROM sqlite_master WHERE type='table' AND name=?;",
		[table]
	)

	if db.query_result.is_empty():
		db.create_table(table, dict)


static func _get_schema_version(db: SQLite) -> int:
	db.query_with_bindings("SELECT value FROM meta WHERE key=?;", ["schema_version"])
	if db.query_result.is_empty():
		return 0

	var row: Dictionary = db.query_result[0]
	return int(row.get("value", "0"))


static func _set_schema_version(db: SQLite, v: int) -> void:
	db.query_with_bindings(
		"INSERT OR REPLACE INTO meta(key, value) VALUES(?, ?);",
		["schema_version", str(v)]
	)


## v23: Traveling Peddler state — {"anvil": int, "charm_until_ms": int,
## "purchases": {"day": "YYYY-MM-DD", "bought": {stock_id: true}}}. ONE column
## for all three: they are written and read as a unit, and every extra column is
## another INSERT placeholder to keep aligned. ADD COLUMN — no DB wipe; existing
## players migrate to no charges, no blessing and a fresh daily allowance.
static func _migration_v23(db: SQLite) -> void:
	if not _column_exists(db, "players", "peddler_json"):
		db.query("ALTER TABLE players ADD COLUMN peddler_json TEXT NOT NULL DEFAULT '{}';")


## Per-node gather pools, keyed "<instance name>|<node path>" -> {"c","p","t"}.
## Shape owned by [GatherNodeLedger], not spelled out here, so the writer and
## reader cannot drift. It has to be persisted because a ServerInstance is freed
## ~20s after its last player leaves, and node charges used to die with it —
## relogging refilled every vein, tree and fishing hole the player had drained.
## ADD COLUMN, no wipe; existing rows migrate to an empty ledger, which reads as
## all-full and is exactly what those characters log in to today.
static func _migration_v24(db: SQLite) -> void:
	if not _column_exists(db, "players", "gather_nodes_json"):
		db.query("ALTER TABLE players ADD COLUMN gather_nodes_json TEXT NOT NULL DEFAULT '{}';")
