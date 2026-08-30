class_name SkillMasterTitleService
## Grants the eleven [SkillMasterTitles] and tells the player about it.
##
## SERVER-SIDE ONLY. It works on [PlayerResource], which is null on the client,
## so every entry point here is called from the world server.
##
## TWO GRANT PATHS, and both are needed:
##
##   RETROACTIVE  [method sync] sweeps every skill on the resource at login. This
##                covers accounts that hit 99 before this system existed, and it
##                is the safety net for any XP path that ever bypasses the signal
##                below. Idempotent, so running it every login costs one
##                dictionary walk and grants nothing on the second pass.
##   LIVE         [method attach] connects [signal PlayerResource.skill_leveled],
##                so the title lands the instant the level does, with no re-log.
##
## The retroactive sweep is not a migration to delete once accounts are caught
## up. Keeping both means a bug in the live hook degrades to "the title appears
## next login" rather than "the title never appears", which for an earned reward
## is the difference between a rough edge and a support ticket.
##
## NOT PREMIUM. [CommandPermissions.strip_unreleased_vfx] deletes any title
## matching [method TitleCatalog.is_premium_name] from a non-staff player on
## every instance spawn — that is what keeps the unreleased shop set from
## leaking. Mastery titles are earned and must survive it, so they live in their
## own table and are deliberately absent from TitleCatalog.PREMIUM. Moving one
## into PREMIUM would silently strip it from every player who earned it, on their
## next zone change, with no error; tools/verify_skill_master_titles.gd asserts
## against exactly that.

## Push topic the client listens on to raise the unlock banner.
const UNLOCK_PUSH: StringName = &"title.unlocked"

## Marks a resource whose live signal is already wired. See [method attach].
const _ATTACHED_META: StringName = &"skill_master_titles_attached"
## Titles granted before the player had an instance to be notified in.
const _PENDING_META: StringName = &"skill_master_titles_pending"


## Grant every mastery title this resource has earned but does not hold.
## Returns the titles newly granted; empty when there was nothing to do, which is
## the overwhelmingly common case.
##
## Does NOT save and does NOT notify — the caller owns both, because this runs at
## login alongside other backfills (one save beats three) and because at login
## there is no instance yet to raise a banner in. Newly granted titles are queued
## for [method flush_notifications] instead.
static func sync(player_res: PlayerResource) -> PackedStringArray:
	var granted: PackedStringArray = PackedStringArray()
	if player_res == null:
		return granted
	for job: StringName in SkillMasterTitles.BY_JOB:
		# Read the stored dictionary directly rather than through get_skill():
		# get_skill() CREATES a level-1 entry for anything missing, so calling it
		# for all eleven here would quietly write eleven skill rows onto every
		# account that has never touched a profession.
		var entry: Dictionary = player_res.skills.get(job, {})
		if entry.is_empty():
			continue
		if not SkillMasterTitles.qualifies(int(entry.get("level", 1))):
			continue
		var title: String = SkillMasterTitles.title_for(job)
		if _holds(player_res, title):
			continue
		_add(player_res, title)
		granted.append(title)
	if not granted.is_empty():
		_queue(player_res, granted)
	return granted


## Wire up the live grant for one player.
##
## Idempotent via a meta flag rather than is_connected(): the handler is a BOUND
## callable, bound-callable identity is not something to bet a duplicate banner
## on, and PlayerResource instances survive a reconnect takeover
## (WorldServer._takeover_or_load_player hands the SAME object to the new peer),
## so a blind connect would stack a second handler on every reconnect.
static func attach(player_res: PlayerResource) -> void:
	if player_res == null or player_res.has_meta(_ATTACHED_META):
		return
	player_res.set_meta(_ATTACHED_META, true)
	player_res.skill_leveled.connect(_on_skill_leveled.bind(player_res))


## Live path: a skill just gained a level.
static func _on_skill_leveled(skill_name: StringName, level: int, player_res: PlayerResource) -> void:
	if not SkillMasterTitles.qualifies(level):
		return
	var title: String = SkillMasterTitles.title_for(skill_name)
	if title.is_empty() or _holds(player_res, title):
		return
	_add(player_res, title)
	# Saved immediately, unlike the login sweep. A title earned mid-session and
	# lost to a crash before the next periodic save is exactly the kind of loss
	# that costs trust in a 99 grind, and this fires at most eleven times in an
	# account's entire life.
	var ws: WorldServer = WorldServer.curr
	if ws != null and ws.database != null:
		ws.database.save_player(player_res)
	notify(player_res, title, skill_name)


## Raise any banners queued by [method sync]. Called once the player is actually
## in an instance — at login the client has not subscribed to pushes yet, so a
## banner fired then is sent into the void.
static func flush_notifications(player_res: PlayerResource) -> void:
	if player_res == null or not player_res.has_meta(_PENDING_META):
		return
	var pending: PackedStringArray = player_res.get_meta(_PENDING_META)
	player_res.remove_meta(_PENDING_META)
	for title: String in pending:
		notify(player_res, title, SkillMasterTitles.job_for_title(title))


## Raise the unlock banner on the earning player's client.
##
## Targeted at their peer rather than propagated to the instance: this is a
## personal milestone, and the whole room does not need a banner every time
## somebody caps a skill. Deferred for the same reason every other login-adjacent
## push in WorldServer is — the RPC must not go out mid-setup.
static func notify(player_res: PlayerResource, title: String, job_slug: StringName) -> void:
	if player_res == null or title.is_empty():
		return
	var peer_id: int = int(player_res.current_peer_id)
	if peer_id <= 0:
		return # offline grant (an admin XP command against a logged-out row)
	var ws: WorldServer = WorldServer.curr
	if ws == null:
		return
	ws.data_push.rpc_id.call_deferred(peer_id, UNLOCK_PUSH, {
		"title": title,
		"skill": String(job_slug),
		"skill_name": JobRegistry.display_name(job_slug),
	})


static func _queue(player_res: PlayerResource, titles: PackedStringArray) -> void:
	var pending: PackedStringArray = PackedStringArray()
	if player_res.has_meta(_PENDING_META):
		pending = player_res.get_meta(_PENDING_META)
	pending.append_array(titles)
	player_res.set_meta(_PENDING_META, pending)


## True when the resource already holds [param title].
static func _holds(player_res: PlayerResource, title: String) -> bool:
	return player_res.titles_unlocked.has(title)


## Append to titles_unlocked, and wear it if nothing is worn.
##
## The array is duplicated and reassigned rather than appended in place: it is an
## exported PackedStringArray, so the getter hands back a COPY and appending to
## that copy is a silent no-op — the grant would look successful and persist
## nothing. titles.equip already works around the same trap.
static func _add(player_res: PlayerResource, title: String) -> void:
	var unlocked: PackedStringArray = player_res.titles_unlocked.duplicate()
	unlocked.append(title)
	player_res.titles_unlocked = unlocked
	# Auto-wear only when bare. Overwriting a title the player deliberately chose
	# would be the reward taking their nameplate away from them.
	if player_res.display_title.strip_edges().is_empty():
		player_res.display_title = title
