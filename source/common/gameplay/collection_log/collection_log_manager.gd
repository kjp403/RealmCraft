extends Node
## Autoload. Owns Collection Log progress: which unique boss drops a character
## has been credited, and how many times they have killed each boss.
##
## Registered in project.godot [autoload] as:
##     CollectionLogManager="*res://source/common/gameplay/collection_log/collection_log_manager.gd"
##
## No `class_name`: Godot refuses an autoload whose singleton name collides with
## a global class name, and every autoload here follows the same bare `extends`
## convention. The consequence is that the `CollectionLogManager` identifier only
## resolves in a run that instantiates autoloads, so headless `-s` tools must
## load this script and `.new()` it instead — see tools/verify_collection_logs.gd.
##
## THIS AUTOLOAD HOLDS NO PER-PLAYER STATE.
## One world process serves many players. A cached `log_data` on this node would
## serve whoever killed a boss last, and every read after a second player logged
## in would be someone else's log. All state lives on
## [member PlayerResource.collection_log] — already per-player, already persisted,
## already server-only — and this node owns exactly three things: the log
## catalog, the mutation rules, and the signal wiring.
##
## SERVER IS THE AUTHORITY. Progress is written on the world server, where the
## loot roll happens. Never gate anything on a client-side copy.
##
## PURE DATA + SIGNALS. This node instances no VFX, opens no menu and touches no
## Label. The log menu, the toast feed and the nameplate FX all subscribe. That
## decoupling is what lets it run headless on the world server, where none of
## those UI classes compile.

## A unique drop was newly credited. `total` is the boss's full count, so the UI
## can render "4 / 10" without a second lookup.
signal item_logged(
	player_res: PlayerResource, boss_id: StringName, item_id: StringName,
	unlocked: int, total: int
)

## A boss kill was recorded. Carries the running total for the dry-streak readout.
signal kill_logged(player_res: PlayerResource, boss_id: StringName, kills: int)

## A log hit 100% for the FIRST time. Fires once per character per boss, ever.
## The title and VFX ride the signal so the reward path needs no catalog lookup.
signal log_completed(
	player_res: PlayerResource, boss_id: StringName,
	green_log_title_text: String, green_log_vfx: PackedScene
)

## Where the shipped logs live. Scanned once, cached.
const LOGS_PATH: String = "res://source/common/gameplay/collection_log/logs/"

## Serialized payload keys. Named constants because they are written into the
## save blob — a typo'd literal at one call site and the other silently reads a
## missing key as zero.
const KEY_KILLS: String = "kills"
const KEY_ITEMS: String = "items"
const KEY_COMPLETED: String = "completed"
const KEY_LAST_UNLOCK_KILL: String = "last_unlock_kill"
## Unix seconds, stamped ONCE when the log first goes green. Zero means either
## "not finished" or "finished before this key existed" — the two are told apart
## by KEY_COMPLETED, and the UI shows no date rather than inventing one for a
## character who green-logged before the stamp shipped.
const KEY_COMPLETED_AT: String = "completed_at"
## slug -> how many of that item this boss has ever paid out. Kept ALONGSIDE
## KEY_ITEMS rather than replacing it: the array carries first-seen ORDER and is
## what the green check walks, the dictionary carries quantity. Collapsing the
## two into one dictionary would lose the order the player earned things in.
const KEY_COUNTS: String = "counts"

## boss_id -> BossCollectionLog. Content, not player state — safe to cache here.
static var _by_boss: Dictionary[StringName, BossCollectionLog] = {}
static var _scanned: bool = false


func _ready() -> void:
	_scan()


# --- Catalog -----------------------------------------------------------------

## The log definition for a boss, or null if that boss has none.
static func find_log(boss_id: StringName) -> BossCollectionLog:
	_scan()
	return _by_boss.get(boss_id, null)


## The log key for a live enemy — [b]the one definition of it[/b], used by both
## [RewardService] and tools/verify_collection_logs.gd so the two cannot drift.
##
## It is [member EnemyTypeResource.enemy_type], NOT the resource's registry slug,
## and that distinction is the whole reason this function exists. Registry slugs
## come from the FILE NAME, and every boss ships as a pair:
##
##     cinderborn.tres        -> slug &"cinderborn"        (overworld story dummy)
##     cinderborn_world.tres  -> slug &"cinderborn_world"  (drops the uniques)
##
## Both carry enemy_type = &"cinderborn". Keying on the slug would look correct,
## match the overworld story dummy, and resolve to NOTHING for the Boss Hunt
## variant — which is the only one whose table holds the relics and sets. The
## log would then sit at 0/10 forever with no error anywhere.
static func boss_id_for(enemy_data: EnemyTypeResource) -> StringName:
	return enemy_data.enemy_type if enemy_data != null else &""


## Every shipped log, for the menu's boss list.
static func all_logs() -> Array[BossCollectionLog]:
	_scan()
	var out: Array[BossCollectionLog] = []
	for boss_id: StringName in _by_boss:
		out.append(_by_boss[boss_id])
	return out


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	for file_path: String in FileUtils.get_all_file_at(LOGS_PATH, "*.tres"):
		if not file_path.ends_with(".tres"):
			continue
		# Untyped load, then an `is` check: in exports the custom-class loader may
		# not be registered when this scan first runs, and a "BossCollectionLog"
		# type hint would trip the resource loader. Same reason as the
		# BossHuntCatalog and instance-collection scans.
		var loaded: Resource = ResourceLoader.load(file_path)
		if loaded == null or not (loaded is BossCollectionLog):
			continue
		var boss_log: BossCollectionLog = loaded
		if boss_log.boss_id.is_empty():
			push_warning("BossCollectionLog '%s' has no boss_id — skipped." % file_path)
			continue
		if _by_boss.has(boss_log.boss_id):
			push_warning("Duplicate BossCollectionLog for '%s' — keeping the first."
				% boss_log.boss_id)
			continue
		_by_boss[boss_log.boss_id] = boss_log


# --- Writes ------------------------------------------------------------------

## Credit a unique drop to one character.
##
## [b]CALL THIS FROM THE BOSS LOOT GENERATION PIPELINE ONLY[/b] — that is
## [method RewardService.credit_collection_log], which runs off the dead boss's
## rolled [LootDrop] table and therefore knows which NPC produced the item. It
## must NEVER be called from an inventory change, a pickup, a bank deposit, a
## trade, a mail claim or a chest open.
##
## This is not defensive tidiness; it is the whole integrity model, and the
## shipped data makes the hole concrete. The Fire weapon set is on Vurthek's
## table, but the SAME five items are also in dungeon_reward_v1.tres,
## fungus_reward_hard.tres, salvage_table.tres and the Hollow Seep quest rewards.
## Hooked to inventory, a player fills the Cinderborn log without ever entering
## the foundry — off a dungeon chest, a quest hand-in, or five seconds of holding
## a traded sword. Only the boss's own roll proves the kill.
##
## Idempotent: a second Slagborn Helm is a duplicate, not progress.
func add_item_to_log(
	player_res: PlayerResource, boss_id: StringName, item_id: StringName
) -> void:
	if player_res == null or not _is_authority():
		return
	var boss_log: BossCollectionLog = find_log(boss_id)
	if boss_log == null:
		return # boss has no collection log — nothing to record, not an error
	if not boss_log.owns_item(item_id):
		# Rolled, but not one of this boss's logged uniques (gold, bones, a
		# chest, a shared bar). Normal on most kills.
		return
	var entry: Dictionary = _entry(player_res, boss_id)
	var items: Array[StringName] = entry[KEY_ITEMS]
	# The tally counts EVERY payout, duplicates included — that is the whole
	# point of it. Only the first copy advances the log itself.
	var counts: Dictionary = entry[KEY_COUNTS]
	counts[item_id] = int(counts.get(item_id, 0)) + 1
	if items.has(item_id):
		return # already logged — a duplicate drop, but the tally moved
	items.append(item_id)
	# Stamped before the signal so a listener reading dry_streak() sees 0, not
	# the streak this drop just ended.
	entry[KEY_LAST_UNLOCK_KILL] = int(entry[KEY_KILLS])
	item_logged.emit(player_res, boss_id, item_id, items.size(), boss_log.total_items())
	# Completion is checked here and only here, so the reward fires on the drop
	# that filled the log rather than on the next kill.
	if bool(entry[KEY_COMPLETED]):
		return
	if not check_green_log_status(player_res, boss_id):
		return
	entry[KEY_COMPLETED] = true
	# Stamped here and nowhere else. This is the only moment the transition
	# happens, and re-stamping on a later read would turn "finished in September"
	# into "finished just now" every time the menu opened.
	entry[KEY_COMPLETED_AT] = int(Time.get_unix_time_from_system())
	log_completed.emit(
		player_res, boss_id, boss_log.green_log_title_text, boss_log.green_log_vfx
	)


## Record a boss kill. Drives the dry-streak and rate-per-kill readouts, so it is
## counted for every kill — including ones that dropped nothing logged, and
## including kills after the log is already green.
##
## Called from the same place as [method add_item_to_log], and BEFORE the table's
## drops are credited, so the kill that produced a unique is the kill that ends
## the dry streak rather than the one after it.
func increment_boss_kill(player_res: PlayerResource, boss_id: StringName) -> void:
	if player_res == null or not _is_authority():
		return
	var entry: Dictionary = _entry(player_res, boss_id)
	entry[KEY_KILLS] = int(entry[KEY_KILLS]) + 1
	kill_logged.emit(player_res, boss_id, int(entry[KEY_KILLS]))


# --- Reads -------------------------------------------------------------------

## True when this character holds every item in the boss's log.
##
## Compares CONTENTS, not just length: a length check alone would call the log
## green if a content patch removed an item from log_items while the player's
## stored array still held the old slug — exactly what re-authoring a drop table
## does.
func check_green_log_status(player_res: PlayerResource, boss_id: StringName) -> bool:
	if player_res == null:
		return false
	var boss_log: BossCollectionLog = find_log(boss_id)
	if boss_log == null or boss_log.total_items() == 0:
		return false
	var items: Array[StringName] = _entry(player_res, boss_id)[KEY_ITEMS]
	if items.size() < boss_log.total_items():
		return false
	for required: StringName in boss_log.log_items:
		if not items.has(required):
			return false
	return true


## Unique drops credited for a boss so far.
func unlocked_count(player_res: PlayerResource, boss_id: StringName) -> int:
	if player_res == null:
		return 0
	var items: Array[StringName] = _entry(player_res, boss_id)[KEY_ITEMS]
	return items.size()


## How many of [param item_id] this boss has paid out to this character. 0 when
## it has never dropped. Duplicates count, so this is the "x3" on the log cell.
func item_count(
	player_res: PlayerResource, boss_id: StringName, item_id: StringName
) -> int:
	if player_res == null:
		return 0
	var counts: Dictionary = _entry(player_res, boss_id)[KEY_COUNTS]
	return int(counts.get(item_id, 0))


## Kills recorded for a boss.
func kill_count(player_res: PlayerResource, boss_id: StringName) -> int:
	if player_res == null:
		return 0
	return int(_entry(player_res, boss_id)[KEY_KILLS])


## True once the completion reward has fired for this character and boss.
## Persisted, so this — not [method check_green_log_status] — is the flag to gate
## the title grant on.
## When this character first filled the log, in unix seconds.
##
## 0 means one of two things and the caller must not conflate them: the log is
## not finished, or it was finished on a build that predates the stamp. Pair it
## with [method has_green_log] to tell those apart.
func completed_at(player_res: PlayerResource, boss_id: StringName) -> int:
	if player_res == null:
		return 0
	return int(_entry(player_res, boss_id).get(KEY_COMPLETED_AT, 0))


func has_green_log(player_res: PlayerResource, boss_id: StringName) -> bool:
	if player_res == null:
		return false
	return bool(_entry(player_res, boss_id)[KEY_COMPLETED])


## 0.0 .. 1.0 for the menu's progress bar.
func completion_ratio(player_res: PlayerResource, boss_id: StringName) -> float:
	var boss_log: BossCollectionLog = find_log(boss_id)
	if boss_log == null or boss_log.total_items() == 0:
		return 0.0
	return float(unlocked_count(player_res, boss_id)) / float(boss_log.total_items())


## Kills since this boss last produced a NEW logged unique. Only meaningful while
## the log is unfilled; once green every further kill is dry by definition.
func dry_streak(player_res: PlayerResource, boss_id: StringName) -> int:
	if player_res == null:
		return 0
	var entry: Dictionary = _entry(player_res, boss_id)
	return maxi(0, int(entry[KEY_KILLS]) - int(entry[KEY_LAST_UNLOCK_KILL]))


## Client payload for the log menu: one row per shipped boss, already resolved so
## the UI does nothing but draw. Item slugs the registry cannot resolve are still
## listed — a renamed item must show as an unknown row, not vanish and make a
## green log look incomplete.
func build_payload(player_res: PlayerResource) -> Dictionary:
	if player_res == null:
		return {"logs": []}
	var rows: Array = []
	for boss_log: BossCollectionLog in all_logs():
		var items: Array[StringName] = _entry(player_res, boss_log.boss_id)[KEY_ITEMS]
		var counts: Dictionary = _entry(player_res, boss_log.boss_id)[KEY_COUNTS]
		var entries: Array = []
		for slug: StringName in boss_log.log_items:
			entries.append({
				"slug": String(slug),
				"owned": items.has(slug),
				"count": int(counts.get(slug, 0)),
			})
		rows.append({
			"boss_id": String(boss_log.boss_id),
			"boss_name": boss_log.boss_name,
			"kills": kill_count(player_res, boss_log.boss_id),
			"dry": dry_streak(player_res, boss_log.boss_id),
			"unlocked": items.size(),
			"total": boss_log.total_items(),
			# TWO different questions, and a content patch is what separates them.
			#
			# `title_earned` is the sticky flag: this character green-logged the
			# boss at some point, so they own the title. It is never revoked —
			# taking a title back because a later patch added an item to the log
			# would be indefensible.
			#
			# `completed` is the LIVE check against today's log_items. Add an item
			# to a boss and yesterday's completionist is honestly 9/10 again.
			#
			# Reporting only the sticky flag is what would make the UI lie: a gold
			# frame reading "EARNED TITLE" over a grid with a visibly empty slot.
			"title_earned": has_green_log(player_res, boss_log.boss_id),
			"completed": check_green_log_status(player_res, boss_log.boss_id),
			# Unix seconds, 0 when unfinished or finished before the stamp
			# shipped. Sent raw rather than pre-formatted: the client knows the
			# player's timezone and the server does not.
			"completed_at": completed_at(player_res, boss_log.boss_id),
			"title": boss_log.green_log_title_text,
			# The title's LOOK, so the menu can show what the reward actually
			# renders as rather than just naming it.
			"title_color": boss_log.green_log_title_color.to_html(false),
			"title_style": boss_log.green_log_title_style,
			"title_vfx": boss_log.green_log_vfx.resource_path if boss_log.green_log_vfx else "",
			"items": entries,
		})
	return {"logs": rows}


# --- Serialization -----------------------------------------------------------

## Canonical save shape. The sqlite store writes this under `collection_log_json`;
## keeping the shape here rather than inline in the store means the reader and
## the writer cannot drift apart.
##
## It is ONE column for the whole roster, not a column per boss and not a column
## per counter. Every column on `players` is another placeholder the INSERT has
## to keep aligned, and a column added without its matching `?` makes
## save_player() fail for EVERY field of EVERY player, silently — whole-server
## data loss traded for a cosmetic log.
##
## StringNames are written as Strings: JSON has no StringName, and a round trip
## through JSON.parse_string returns plain Strings, so writing them as-is would
## make the reloaded array fail every `has()` check against a &"slug" literal.
##
## Takes a [PlayerResource] rather than reading node state — see the class header.
func serialize_log_data(player_res: PlayerResource) -> Dictionary:
	if player_res == null:
		return {}
	var out: Dictionary = {}
	for boss_id: Variant in player_res.collection_log:
		var entry: Dictionary = player_res.collection_log[boss_id]
		var items: Array[String] = []
		for item_id: Variant in entry.get(KEY_ITEMS, []):
			items.append(String(item_id))
		var counts: Dictionary = {}
		for slug: Variant in (entry.get(KEY_COUNTS, {}) as Dictionary):
			counts[String(slug)] = int((entry[KEY_COUNTS] as Dictionary)[slug])
		# Carries UNKNOWN keys back out, matching deserialize_log_data. The two
		# halves have to agree: preserving a newer patch's key on load and then
		# dropping it on the next save would leave it alive exactly until the
		# player's first autosave, which is a worse failure than never keeping it
		# at all — it looks like it works.
		var row: Dictionary = (entry as Dictionary).duplicate(true)
		row.merge({
			KEY_KILLS: int(entry.get(KEY_KILLS, 0)),
			KEY_ITEMS: items,
			KEY_COUNTS: counts,
			KEY_COMPLETED: bool(entry.get(KEY_COMPLETED, false)),
			KEY_COMPLETED_AT: int(entry.get(KEY_COMPLETED_AT, 0)),
			KEY_LAST_UNLOCK_KILL: int(entry.get(KEY_LAST_UNLOCK_KILL, 0)),
		}, true)
		out[String(boss_id)] = row
	return out


## Restore from [method serialize_log_data]. Replaces state wholesale, and emits
## nothing — loading a character is not earning a drop, and firing log_completed
## here would re-award the title and replay its toast on every login.
##
## Unknown boss ids and unknown item slugs are KEPT, not dropped. A boss parked
## on a branch, or an item renamed by a later patch, must not cost a player
## progress they already earned; the log UI marks what it cannot resolve.
func deserialize_log_data(player_res: PlayerResource, data: Variant) -> void:
	if player_res == null:
		return
	player_res.collection_log = {}
	if data is not Dictionary:
		return
	for raw_boss_id: Variant in (data as Dictionary):
		var raw: Variant = (data as Dictionary)[raw_boss_id]
		if raw is not Dictionary:
			continue
		var saved: Dictionary = raw
		var items: Array[StringName] = []
		for raw_item: Variant in saved.get(KEY_ITEMS, []):
			var item_id: StringName = StringName(str(raw_item))
			if not items.has(item_id):
				items.append(item_id)
		var counts: Dictionary = {}
		for raw_slug: Variant in (saved.get(KEY_COUNTS, {}) as Dictionary):
			counts[StringName(str(raw_slug))] = int(
				(saved[KEY_COUNTS] as Dictionary)[raw_slug])
		# A blob written before quantities existed has no counts at all. Seed
		# every already-logged item at 1 rather than 0: the player demonstrably
		# owns one, and 0 would render an owned cell as "x0".
		for item_id: StringName in items:
			if not counts.has(item_id):
				counts[item_id] = 1
		var kills: int = int(saved.get(KEY_KILLS, 0))
		# FORWARD compatibility. Start from whatever was on disk and merge the
		# keys this build understands OVER it, rather than building a fresh row
		# from known keys only.
		#
		# The difference shows up when a player moves between builds. A newer
		# patch adds a key; they then log into a world still running this build;
		# a fresh-row read drops the key silently and the next save writes the
		# loss back permanently. Keeping the unknown keys means an older server
		# carries them through untouched instead of destroying them.
		#
		# The merge is `true` (overwrite) so this build's own parsing always
		# wins for the keys it does know — items and counts have been normalised
		# to StringName above, and the raw JSON Strings underneath them must not
		# survive, or every `has(&"slug")` check against them fails.
		var row: Dictionary = saved.duplicate(true)
		row.merge({
			KEY_KILLS: kills,
			KEY_ITEMS: items,
			KEY_COUNTS: counts,
			KEY_COMPLETED: bool(saved.get(KEY_COMPLETED, false)),
			# Deliberately NOT back-filled with "now" for an old completed row.
			# A character who green-logged before this key shipped has no honest
			# date, and stamping today's would tell every one of them they
			# finished on patch day.
			KEY_COMPLETED_AT: int(saved.get(KEY_COMPLETED_AT, 0)),
			# Clamped: a blob written before this key existed reads back as the
			# kill count, not 0, so an old save does not report every kill ever
			# as one enormous dry streak.
			KEY_LAST_UNLOCK_KILL: mini(int(saved.get(KEY_LAST_UNLOCK_KILL, kills)), kills),
		}, true)
		player_res.collection_log[StringName(str(raw_boss_id))] = row


# --- Internals ---------------------------------------------------------------

## The progress row for one character and boss, created empty on first touch so
## every read above can assume the keys exist.
## Is this process allowed to WRITE collection log progress?
##
## Belt and braces over the call-site rule. Nothing on the client can reach these
## writers today — there is no RPC into them and collection_log.state.gd is
## read-only — so this exists to make a FUTURE client-side call fail loudly at
## the door rather than quietly award a log.
##
## A null `multiplayer` counts as authority, and that is deliberate rather than
## lax: in a `-s` headless run — every verifier in tools/ — `Node.multiplayer` is
## null outright, so `multiplayer.is_server()` does not return false, it errors
## on a null instance and takes the whole run with it. Treating null as "no
## networking, therefore no client to spoof from" is what keeps the gates
## executing instead of silently passing a manager that never writes anything.
##
## The real client case is unaffected: a connected client always has a peer, so
## `is_server()` answers honestly there.
func _is_authority() -> bool:
	var api: MultiplayerAPI = multiplayer
	return api == null or api.multiplayer_peer == null or api.is_server()


func _entry(player_res: PlayerResource, boss_id: StringName) -> Dictionary:
	if not player_res.collection_log.has(boss_id):
		var items: Array[StringName] = []
		player_res.collection_log[boss_id] = {
			KEY_KILLS: 0,
			KEY_ITEMS: items,
			KEY_COUNTS: {},
			KEY_COMPLETED: false,
			KEY_COMPLETED_AT: 0,
			KEY_LAST_UNLOCK_KILL: 0,
		}
	return player_res.collection_log[boss_id]
