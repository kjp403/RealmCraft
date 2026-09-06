class_name CollectionLogTitleService
## Grants the green-log titles and tells the player about it.
##
## SERVER-SIDE ONLY. It works on [PlayerResource], which is null on the client,
## so every entry point here is called from the world server.
##
## TWO GRANT PATHS, mirroring [SkillMasterTitleService] deliberately — this is
## the same kind of reward (earned, permanent, not for sale) and it fails the
## same ways:
##
##   RETROACTIVE  [method sync] sweeps every completed log at login. Covers
##                characters who green-logged before this grant existed, and any
##                path that ever bypasses the live hook. Idempotent.
##   LIVE         [method attach] connects [signal CollectionLogManager.log_completed]
##                so the title lands on the drop that fills the log, no re-log.
##
## The retroactive sweep is not a migration to delete. Keeping both means a bug
## in the live hook degrades to "the title appears next login" rather than "the
## title never appears" — for a reward behind a 1/1000 relic, that is the
## difference between a rough edge and a lost grind.
##
## NOT PREMIUM. [CommandPermissions.strip_unreleased_vfx] deletes any title
## matching [method TitleCatalog.is_premium_name] from a non-staff player on every
## instance spawn. Green-log titles are earned and must survive it, so they are
## defined on the [BossCollectionLog] resources and are deliberately absent from
## TitleCatalog.PREMIUM. Adding one there would silently strip it from everyone
## who earned it, on their next zone change, with no error anywhere.

## Push topic the client listens on to raise the unlock banner. Shared with the
## mastery titles so the client has one banner path, not two.
const UNLOCK_PUSH: StringName = &"title.unlocked"

const _ATTACHED_META: StringName = &"collection_log_titles_attached"
const _PENDING_META: StringName = &"collection_log_titles_pending"


## Wire the live grant for this character's session. Idempotent — a second call
## on the same resource does nothing, so a reconnect cannot double-connect and
## grant twice.
static func attach(player_res: PlayerResource) -> void:
	if player_res == null or player_res.has_meta(_ATTACHED_META):
		return
	player_res.set_meta(_ATTACHED_META, true)
	if not CollectionLogManager.log_completed.is_connected(_on_log_completed):
		CollectionLogManager.log_completed.connect(_on_log_completed)


## Grant every green-log title this character has earned but does not hold.
## Returns the titles newly granted; empty when there is nothing to do, which is
## the overwhelmingly common case.
##
## Does NOT save and does NOT notify — the caller owns both, matching
## SkillMasterTitleService.sync: at login there is no instance yet to raise a
## banner in, so grants are queued for [method flush_notifications].
static func sync(player_res: PlayerResource) -> PackedStringArray:
	var granted: PackedStringArray = PackedStringArray()
	if player_res == null:
		return granted
	for boss_log: BossCollectionLog in CollectionLogManager.all_logs():
		# has_green_log reads the PERSISTED completion latch, not a recount — a
		# content patch that adds an item to a filled log must not revoke a title
		# somebody already earned.
		if not CollectionLogManager.has_green_log(player_res, boss_log.boss_id):
			continue
		if _grant(player_res, boss_log.green_log_title_text):
			granted.append(boss_log.green_log_title_text)
	if not granted.is_empty():
		_queue(player_res, granted)
	return granted


## Live path: the drop that filled the log just landed.
static func _on_log_completed(
	player_res: PlayerResource, boss_id: StringName, title: String, _vfx: PackedScene
) -> void:
	if not _grant(player_res, title):
		return
	notify(player_res, title, boss_id)
	# Saved here rather than left to the next autosave: this is the payoff for a
	# very long grind, and a crash between the grant and the next save would take
	# the title while leaving the log green — so the retroactive sweep would fix
	# it silently at next login, but only after the player had seen it vanish.
	if WorldServer.curr != null and WorldServer.curr.database != null:
		WorldServer.curr.database.save_player(player_res)


## Raise the unlock banner on the earning player's client. Targeted at their peer:
## a personal milestone, not a room announcement.
static func notify(player_res: PlayerResource, title: String, boss_id: StringName) -> void:
	if player_res == null or title.is_empty():
		return
	var peer_id: int = int(player_res.current_peer_id)
	if peer_id <= 0:
		return # offline grant
	var ws: WorldServer = WorldServer.curr
	if ws == null:
		return
	var boss_log: BossCollectionLog = CollectionLogManager.find_log(boss_id)
	ws.data_push.rpc_id.call_deferred(peer_id, UNLOCK_PUSH, {
		"title": title,
		"source": "collection_log",
		"boss": boss_log.boss_name if boss_log != null else String(boss_id),
	})


## Raise banners queued during login, once the player has an instance to see them
## in. Called from the same place SkillMasterTitleService.flush_notifications is.
static func flush_notifications(player_res: PlayerResource) -> void:
	if player_res == null or not player_res.has_meta(_PENDING_META):
		return
	var pending: PackedStringArray = player_res.get_meta(_PENDING_META)
	player_res.remove_meta(_PENDING_META)
	for title: String in pending:
		notify(player_res, title, _boss_for_title(title))


## True when the resource already holds [param title].
static func holds(player_res: PlayerResource, title: String) -> bool:
	return player_res != null and player_res.titles_unlocked.has(title)


## Append to titles_unlocked and wear it if nothing is worn. Returns false when
## the title was already held, so callers can skip the notify.
##
## Duplicate-then-reassign rather than appending in place. [SkillMasterTitleService._add]
## and titles.equip both do this and describe the direct append as a silent
## no-op; measured on Godot 4.7, a direct append to this plain script property
## actually DOES stick, so treat this as belt-and-braces matching house style
## rather than as a workaround for a live bug. It stays because the form is free
## and stops mattering the day the property grows a setter — at which point the
## direct append really would start discarding writes.
static func _grant(player_res: PlayerResource, title: String) -> bool:
	if player_res == null or title.strip_edges().is_empty():
		return false
	if holds(player_res, title):
		return false
	var unlocked: PackedStringArray = player_res.titles_unlocked.duplicate()
	unlocked.append(title)
	player_res.titles_unlocked = unlocked
	# Auto-wear only when bare. Overwriting a title the player deliberately chose
	# would be the reward taking their nameplate away from them.
	if player_res.display_title.strip_edges().is_empty():
		player_res.display_title = title
	return true


static func _queue(player_res: PlayerResource, titles: PackedStringArray) -> void:
	var pending: PackedStringArray = PackedStringArray()
	if player_res.has_meta(_PENDING_META):
		pending = player_res.get_meta(_PENDING_META)
	pending.append_array(titles)
	player_res.set_meta(_PENDING_META, pending)


## Which boss awards [param title], for the banner text. &"" if none does.
static func _boss_for_title(title: String) -> StringName:
	for boss_log: BossCollectionLog in CollectionLogManager.all_logs():
		if boss_log.green_log_title_text == title:
			return boss_log.boss_id
	return &""
