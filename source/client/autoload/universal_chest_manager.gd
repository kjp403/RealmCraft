extends Node
## Single route for opening EVERY reward container in the game — bag chests,
## dungeon caskets, treasure clues, boss loot boxes, Daily Skilling Chests.
## Autoload (`UniversalChestManager`). No `class_name`: Godot refuses an autoload
## whose singleton name collides with a global class, and every autoload in this
## project follows the same bare-`extends` convention.
##
## WHY THIS EXISTS AS A LAYER
## Before this, every caller did its own `chest.open_item` request and the
## `chest.opened` push was routed through `ClientState.open_menu_requested`, which
## lands in `HUD.display_menu`. display_menu is EXCLUSIVE — it hides every other
## menu — so opening a chest out of the inventory closed the inventory, and
## emptying a stack meant Bank All -> Close -> reopen Inventory -> open the next
## one. The fix is not a flag on display_menu (other menus genuinely should be
## exclusive); it is that a reward readout is not a menu. Opens now go through
## here and surface in ChestRewardWindow, a standalone overlay that display_menu
## does not know about and therefore cannot hide, and which never hides anything
## itself.
##
## OWNS ORCHESTRATION, NOT RULES. Batch sequencing, request retries and the
## running ledger live here. Drop rates, quantities and rarity tiers do not —
## those arrive stamped on the payload from the server ([LootRarity]). Nothing in
## this file or the UI above it may compute what a chest is worth.

## A batch run began. [param requested] is -1 for "open all".
signal batch_started(chest_name: String, requested: int)
## One server chunk landed. [param ledger] is the running merged total so far.
signal batch_progress(opened: int, remaining: int, ledger: Array)
## Emitted once per distinct item the run produced, in arrival order — the hook
## the reward window pops a row on.
signal reward_granted(entry: Dictionary)
## Emitted for entries the SERVER tiered as worth celebrating. Separate from
## [signal reward_granted] so the particle/glow path cannot accidentally fire on
## a stack of copper.
signal rare_granted(entry: Dictionary)
## The run finished (or stopped). Carries the full merged summary.
signal batch_finished(summary: Dictionary)
## Staged loot changed — a claim moved something, or an open staged more.
signal pending_changed(pending: Array, free_slots: int)
## A claim could not place everything. [param note] is the server's own wording.
signal claim_blocked(note: String)

## Sentinel for "every one I hold".
const ALL: int = -1

## Which staging pile the claim buttons act on.
##
## The game has two, and they are not the same kind of thing:
##   PENDING — `pending_chest_loot`. Transient. Filled by OPENING something, has
##             no capacity, and auto-banks at logout.
##   HUNT    — `hunt_chest`. Permanent Guild Hall storage, capped at
##             HuntChest.MAX_STACKS, filled automatically by Boss Hunt kills.
##
## They share a wire shape ([{id, a}]) and a claim gesture, which is why one
## window can serve both. They do NOT share an open verb — see [method open_hunt_chest].
enum Source { PENDING, HUNT }

## Request names per source, so the claim methods stay one code path.
const TAKE_REQUEST: Dictionary[Source, StringName] = {
	Source.PENDING: &"chest.loot_take",
	Source.HUNT: &"hunt_chest.take",
}
const BANK_REQUEST: Dictionary[Source, StringName] = {
	Source.PENDING: &"chest.loot_bank",
	Source.HUNT: &"hunt_chest.bank",
}

## Set while a run is in flight, so a double-click on Open All cannot start two
## interleaved sequences against the same stack.
var _busy: bool = false
var _chest_id: int = 0
var _chest_name: String = ""
## How many the player asked for; ALL means "keep going while any remain".
var _wanted: int = 0
var _opened: int = 0
var _gold: int = 0
## item id -> merged {id, amount, name, rarity}. Insertion-ordered, which is the
## order the window lists them in.
var _ledger: Dictionary[int, Dictionary] = {}
var _pending: Array = []
var _free_slots: int = 0
## Which pile [method claim_all] and friends currently address.
var _source: Source = Source.PENDING
## Set while a claim request is in flight. The SERVER cannot be double-claimed
## (see hunt_chest.take's header), but without this a double-click fires a second
## request whose only possible outcome is a confusing "bag is full" toast for a
## pile the first request already emptied.
var _claiming: bool = false
## Stack cap of the current source, or 0 when it has none. Only the Hunt Chest
## does; pending loot is unbounded.
var _capacity: int = 0


func _ready() -> void:
	# The push covers every open this client did NOT initiate through open():
	# world chests, a boss payout, the Daily Skilling Chest that rides a daily
	# claim. They all deserve the same window, so they all land here.
	Client.subscribe(&"chest.opened", _on_chest_opened)


func is_busy() -> bool:
	return _busy


func pending() -> Array:
	return _pending


func free_slots() -> int:
	return _free_slots


# --- Opening -----------------------------------------------------------------

## Open [param count] of chest [param item_id] ([constant ALL] for the whole
## stack). Safe to call from any UI; it never opens, closes, or hides a menu.
func open(item_id: int, count: int = 1) -> void:
	if _busy or item_id <= 0:
		return
	_busy = true
	_source = Source.PENDING
	_chest_id = item_id
	_chest_name = _name_of(item_id)
	_wanted = count
	_opened = 0
	_gold = 0
	_ledger.clear()
	batch_started.emit(_chest_name, count)
	_pump()


## Present an already-rolled payload (a daily claim's chest, a world chest push)
## through the same window as a bag open, so there is exactly one reward
## presentation in the game.
func present(payload: Dictionary) -> void:
	if payload.is_empty() or not bool(payload.get("ok", true)):
		return
	if _busy:
		# Mid-batch: fold it into the run rather than racing the window.
		_absorb(payload)
		batch_progress.emit(_opened, int(payload.get("remaining", 0)), ledger_rows())
		return
	_source = Source.PENDING
	_chest_id = int(payload.get("chest_id", 0))
	_chest_name = str(payload.get("chest", "Reward"))
	_wanted = 1
	_opened = 0
	_gold = 0
	_ledger.clear()
	batch_started.emit(_chest_name, 1)
	_absorb(payload)
	batch_finished.emit(summary())


## Issue one chunk. The COUNT sent is whatever is still wanted; the server clamps
## it to its own per-request ceiling and reports how many it actually opened, so
## the client never has to know that ceiling.
func _pump() -> void:
	var ask: int = ALL if _wanted == ALL else maxi(0, _wanted - _opened)
	if _wanted != ALL and ask <= 0:
		_finish()
		return
	Client.request_data(
		&"chest.open_batch",
		_on_batch_response,
		{"id": _chest_id, "count": ask},
		_instance_id()
	)


func _on_batch_response(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		# "missing" at the tail of an Open All is the normal way a run ends —
		# the stack ran out. Anything else is worth a word to the player.
		var reason: String = str(response.get("reason", ""))
		if reason != "missing" and _opened == 0:
			Toaster.toast(_reason_text(reason))
		_finish()
		return

	var opened_now: int = int(response.get("opened", 0))
	_absorb(response)
	var remaining: int = int(response.get("remaining", 0))
	batch_progress.emit(_opened, remaining, ledger_rows())

	# Stop on: nothing left, nothing opened this round (guards against a server
	# that keeps saying ok while opening 0, which would spin forever), or the
	# requested count reached.
	var more_wanted: bool = _wanted == ALL or _opened < _wanted
	if remaining > 0 and opened_now > 0 and more_wanted:
		_pump()
		return
	_finish()


func _finish() -> void:
	_busy = false
	batch_finished.emit(summary())


## Fold a payload into the running totals and announce each item once.
func _absorb(payload: Dictionary) -> void:
	_opened += maxi(1, int(payload.get("opened", 1)))
	_gold += int(payload.get("gold", 0))
	if payload.has("pending"):
		_pending = payload.get("pending", []) as Array
		_free_slots = int(payload.get("free_slots", _free_slots))
		pending_changed.emit(_pending, _free_slots)
	for entry_v: Variant in (payload.get("items", []) as Array):
		if entry_v is not Dictionary:
			continue
		var entry: Dictionary = entry_v
		var id: int = int(entry.get("id", 0))
		var amount: int = int(entry.get("amount", 0))
		if id <= 0 or amount <= 0:
			continue
		var rarity: String = str(entry.get("rarity", "common"))
		if not _ledger.has(id):
			_ledger[id] = {"id": id, "amount": 0, "name": str(entry.get("name", "Item")), "rarity": rarity}
		var row: Dictionary = _ledger[id]
		row["amount"] = int(row["amount"]) + amount
		# Keep the loudest tier this item ever arrived at, so one lucky roll in a
		# fifty-chest run still reads as the drop it was.
		if LootRarity.from_name(rarity) > LootRarity.from_name(str(row["rarity"])):
			row["rarity"] = rarity
		reward_granted.emit(row.duplicate())
		if LootRarity.is_celebrated(LootRarity.from_name(rarity)):
			rare_granted.emit(row.duplicate())


# --- Ledger / summary --------------------------------------------------------

## The merged run so far, newest-item-last. A copy: the window sorts and styles
## it, and must not be able to mutate the manager's state doing so.
func ledger_rows() -> Array:
	var out: Array = []
	for id: int in _ledger:
		out.append((_ledger[id] as Dictionary).duplicate())
	return out


func summary() -> Dictionary:
	return {
		"chest": _chest_name,
		"chest_id": _chest_id,
		"opened": _opened,
		"gold": _gold,
		"items": ledger_rows(),
		"pending": _pending,
		"free_slots": _free_slots,
		"source": int(_source),
		"capacity": _capacity,
	}


# --- Claiming ----------------------------------------------------------------

## Open the Boss Hunt stash in the same window every other reward uses.
##
## THERE IS NO "OPEN" HERE, AND THERE SHOULD NOT BE. A Boss Hunt chest is not a
## container you consume — it is persistent Guild Hall storage that fills
## automatically as the party kills ([HuntChest.deposit]). There is no chest
## item to spend and no loot table to roll, so Open 1 / 5 / All has nothing to
## act on and the window hides those buttons for this source. What DOES carry
## over is the half that was always missing here: one claim gesture with the
## bag-then-bank overflow cascade.
func open_hunt_chest() -> void:
	if _busy:
		return
	_source = Source.HUNT
	_chest_id = 0
	_chest_name = "Hunt Chest"
	_opened = 0
	_gold = 0
	_ledger.clear()
	# requested 0 = "nothing was opened": the window shows a claim list, not a
	# reward reveal, and leaves the batch row hidden.
	batch_started.emit(_chest_name, 0)
	var result: Array = await Client.request_data_await(
		&"hunt_chest.get", {}, _instance_id()
	)
	if result[1] != OK or not bool((result[0] as Dictionary).get("ok", false)):
		claim_blocked.emit("Could not read your Hunt Chest.")
		return
	_apply_claim_payload(result[0] as Dictionary)
	batch_finished.emit(summary())


## Take everything into the bag, then send whatever would not fit to the bank in
## the same gesture.
##
## This is the "auto-deposit on overflow" path, and for PENDING loot it is a
## CLAIM-time concern rather than an open-time one: opens stage into
## pending_chest_loot, which has no capacity, so a batch can never fail part-way
## for want of space. Only moving it into the player's own storage can run out of
## room.
##
## The two sources fail differently at the end of the cascade, deliberately:
## pending loot cascades on to the ground server-side rather than be swallowed,
## while Hunt Chest loot that fits nowhere simply stays in the chest — it is
## permanent storage, and dropping someone's stash on the floor to make room
## would be a worse outcome than leaving it where they can come back for it.
func claim_all() -> void:
	var moved: int = await _claim(TAKE_REQUEST[_source], _claim_args())
	if _pending.is_empty():
		return
	# Bag filled with loot still staged — overflow to the bank without making the
	# player close this window, open the bank, and come back.
	var banked: int = await _claim(BANK_REQUEST[_source], _claim_args())
	if moved > 0 and banked > 0:
		Toaster.toast("Bag filled — sent the rest to your bank.")
	elif moved <= 0 and banked <= 0 and not _pending.is_empty():
		claim_blocked.emit(
			"Nowhere to put it — free a bag slot or a bank slot."
			if _source == Source.HUNT
			else "Bag and bank are both full."
		)


func take_all() -> void:
	await _claim(TAKE_REQUEST[_source], _claim_args())


func bank_all() -> void:
	await _claim(BANK_REQUEST[_source], _claim_args())


func take_one(item_id: int) -> void:
	await _claim(TAKE_REQUEST[_source], _claim_args(item_id))


func bank_one(item_id: int) -> void:
	await _claim(BANK_REQUEST[_source], _claim_args(item_id))


## Refresh the current source from the server (window opened cold, or a relog).
func refresh_pending() -> void:
	var request: StringName = (
		&"hunt_chest.get" if _source == Source.HUNT else &"chest.loot_get"
	)
	var result: Array = await Client.request_data_await(request, {}, _instance_id())
	if result[1] != OK or not bool((result[0] as Dictionary).get("ok", false)):
		return
	_apply_claim_payload(result[0] as Dictionary)


## The two families spell their arguments differently — pending loot keys on
## "id", the hunt chest on "item" plus an explicit "all". Translated here so the
## claim methods above stay one code path and the window never learns either.
func _claim_args(item_id: int = 0) -> Dictionary:
	if _source == Source.HUNT:
		return {"item": item_id} if item_id > 0 else {"all": true}
	return {"id": item_id} if item_id > 0 else {}


## Shared claim request. Returns how many items actually moved.
func _claim(request: StringName, args: Dictionary) -> int:
	if _claiming:
		return 0
	_claiming = true
	var result: Array = await Client.request_data_await(request, args, _instance_id())
	_claiming = false
	if result[1] != OK:
		claim_blocked.emit("No response from the server.")
		return 0
	var payload: Dictionary = result[0] as Dictionary
	var moved: int = int(payload.get("moved", 0))
	# The hunt handlers report ok=false for "moved nothing" (a full bag) rather
	# than for a hard failure, and still return the current stacks — so apply the
	# payload either way and let the message speak for itself.
	if not bool(payload.get("ok", false)) and moved <= 0:
		var note: String = str(payload.get("message", ""))
		claim_blocked.emit(
			note if not note.is_empty() else _reason_text(str(payload.get("reason", "")))
		)
		if payload.has("stacks") or payload.has("pending"):
			_apply_claim_payload(payload)
		return 0
	_apply_claim_payload(payload)
	# The server reports where an overflowing bank send actually landed
	# (bank / bag / ground). Surface its wording rather than inventing our own.
	var overflow: String = str(payload.get("overflow_note", ""))
	if not overflow.is_empty() and (
		int(payload.get("bagged", 0)) > 0 or int(payload.get("dropped", 0)) > 0
	):
		claim_blocked.emit(overflow + ".")
	return moved


## Both sources answer with the same two facts under different key names.
func _apply_claim_payload(payload: Dictionary) -> void:
	if payload.has("stacks"):
		_pending = payload.get("stacks", []) as Array
		_capacity = int(payload.get("capacity", 0))
	else:
		_pending = payload.get("pending", []) as Array
		_capacity = 0
	_free_slots = int(payload.get("free_slots", _free_slots))
	pending_changed.emit(_pending, _free_slots)
	ClientState.inventory_changed.emit(payload)


# --- internals ---------------------------------------------------------------

## Server push for an open this client did not drive.
func _on_chest_opened(payload: Dictionary) -> void:
	present(payload)


func _instance_id() -> String:
	return String(InstanceClient.current.name) if InstanceClient.current else ""


func _name_of(item_id: int) -> String:
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	return str(item.item_name) if item != null else "Chest"


## Player-facing wording for a server refusal code. Kept here rather than in the
## window so every entry point says the same thing.
static func _reason_text(reason: String) -> String:
	match reason:
		"missing": return "You don't have any of those left."
		"not_chest": return "That isn't something you can open."
		"dead": return "You can't open that right now."
		"full": return "Your bank is full — buy more slots or withdraw something."
		"inventory_full": return "Bag is full — bank some items or free slots."
		"player": return "Lost track of your character. Try again."
	return "Could not open that."
