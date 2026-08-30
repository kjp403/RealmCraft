class_name SkillingEvents
extends RefCounted
## Global event bus for SUCCESSFUL skilling actions.
##
## WHY THIS IS A class_name AND NOT AN AUTOLOAD
## An autoload name only resolves in a run that instantiates autoloads. The
## headless `-s` tool runs this project gates on (tools/verify_progression_pass.gd
## and friends) do NOT, and a bare autoload identifier there is not a missing
## node at runtime — it is "Identifier not found" at COMPILE time, which fails the
## whole script and everything that references it. Emitters live in
## mineable_node.gd and the craft/salvage handlers, i.e. squarely in the code
## those tools load. A `class_name` with static entry points resolves in every
## run mode, and matches how the rest of this project ships gameplay services
## (QuestService, RewardService, SlayerTaskService are all static too).
##
## The signals still need an object to live on, so the bus is one lazily-created
## instance behind [method bus] — one per process, held in a static var.
##
## SERVER-AUTHORITATIVE. Every emitter is server-side gameplay code that has
## already committed the action (item in the bag, XP granted). The client never
## emits; it is told about progress through the `daily.progress` push. A client
## that could emit here could complete a daily by sending packets.
##
## WHY EVERY SIGNAL CARRIES A PlayerResource
## A single world process hosts many players at once. A bus signal shaped
## `item_gathered(skill, item_id, amount)` — no player — is unroutable: the
## listener cannot tell whose counter to bump, and the only recoveries are a
## global "current player" (wrong the moment two people mine on the same tick) or
## a peer lookup the emitter already had in hand. The identity is threaded
## through explicitly instead. [PlayerResource] is also server-only state that is
## always null on a client, which is a second reason emission is server-side.
##
## WHY StringName SLUGS AND NOT A SkillType ENUM
## [JobRegistry] is already the single source of truth for which skills exist,
## and every XP grant in the game is keyed by its slug. A parallel enum would be
## a second roster to keep in sync, and the failure mode when the two drift is
## silent — a task that simply never progresses. The nine skilling slugs are
## listed on DailyQuestManager.SKILLS.
##
## Emit through the static helpers, never `bus().signal.emit()` directly: the
## helpers hold the validation (unknown slug, non-positive amount, missing
## player) that keeps a bad call site from quietly corrupting daily progress.

## A gathering action paid off — ore mined, tree cut, fish caught, herb picked.
## [param item_id] is the item registry id that entered the bag.
signal item_gathered(player_res: PlayerResource, skill: StringName, item_id: int, amount: int)

## A production action paid off — smithed, cooked, brewed, fletched, crafted,
## salvaged. [param item_id] is the OUTPUT item (0 when an action yields several)
## and [param amount] the units produced: a batch recipe that makes 10 arrows
## reports 10, not 1.
signal item_crafted(player_res: PlayerResource, skill: StringName, item_id: int, amount: int)

## Every one of the above, fanned into one stream. Progress trackers listen HERE
## rather than to the specific signals: an emission kind added later is then
## tracked automatically instead of silently bypassing the daily board, which is
## the exact bug class that lets one gathering path stop counting without anyone
## noticing for a release.
signal skill_action(player_res: PlayerResource, skill: StringName, item_id: int, amount: int)

## The process-wide bus. Listeners connect here; emitters should use the static
## helpers below.
static var _bus: SkillingEvents

## Slugs already warned about, so a bad call site in a per-swing code path cannot
## flood the server log.
static var _warned_slugs: Dictionary[StringName, bool] = {}


## The one bus instance for this process, created on first use.
static func bus() -> SkillingEvents:
	if _bus == null:
		_bus = SkillingEvents.new()
	return _bus


## Report a successful gather. Safe to call from anywhere on the server; invalid
## calls are dropped rather than raised, because a gather must never fail because
## a daily-board concern rejected it.
static func emit_gathered(
	player_res: PlayerResource, skill: StringName, item_id: int, amount: int
) -> void:
	if not _valid(player_res, skill, amount):
		return
	var b: SkillingEvents = bus()
	b.item_gathered.emit(player_res, skill, item_id, amount)
	b.skill_action.emit(player_res, skill, item_id, amount)


## Report a successful craft / cook / smith / brew / fletch / salvage.
static func emit_crafted(
	player_res: PlayerResource, skill: StringName, item_id: int, amount: int
) -> void:
	if not _valid(player_res, skill, amount):
		return
	var b: SkillingEvents = bus()
	b.item_crafted.emit(player_res, skill, item_id, amount)
	b.skill_action.emit(player_res, skill, item_id, amount)


## Shared gate. An unregistered slug is warned about once per slug — it means a
## call site is passing a display name ("Crafting") or a typo where a job slug
## (&"outfitting") belongs, and the symptom otherwise is just a daily that never
## moves.
static func _valid(player_res: PlayerResource, skill: StringName, amount: int) -> bool:
	if player_res == null or amount <= 0 or skill == &"":
		return false
	if not JobRegistry.has_job(skill):
		if not _warned_slugs.has(skill):
			_warned_slugs[skill] = true
			push_warning("SkillingEvents: unknown job slug '%s' — the call site should pass a JobRegistry slug, not a display name." % skill)
		return false
	return true
