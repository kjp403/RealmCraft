extends Node
## Behaviour check for HudResizer + HudLayout against the REAL HUD panels.
##
## Runs as a SCENE, not a `-s` tool, and windowed:
##   godot --path . --mode=client res://tools/audit_hud_resizer.tscn
##
## `-s` has no autoloads and HudLayout IS one, so under `-s` there is no lock
## state to test against and every panel script fails to compile besides.
##
## This drives synthetic InputEventMouse* through the resizers exactly as the
## viewport would, because the things most likely to break are not "does it
## compile" but the four behaviours below, none of which a parse check sees:
##   1. locked  -> mouse_filter IGNORE + hidden (does not eat world clicks)
##   2. drag    -> host actually resizes, on the free edge, in the right direction
##   3. clamps  -> min/max hold at both ends
##   4. reflow  -> quest tracker re-breaks its lines at the new width

const QUEST_TRACKER: GDScript = preload("res://source/client/ui/hud/quest_tracker.gd")
const PARTY_HUD: GDScript = preload("res://source/client/ui/hud/party_hud.gd")

var _failures: int = 0


func _ready() -> void:
	call_deferred(&"_go")


## The developer's own saved HUD layout, put back in _finish. This tool drags
## real panels and those drags PERSIST — without this, running the audit would
## silently overwrite whatever sizes the person running it had chosen, and the
## run itself would start from the previous run's leftovers instead of from the
## shipped defaults (which is exactly how the first version of this file "failed"
## against a panel that was already sitting at its maximum).
var _saved_layout: Dictionary = {}


func _go() -> void:
	_saved_layout = (ClientState.settings.data.get(
		HudLayout.SETTING_SECTION, {}
	) as Dictionary).duplicate(true)
	HudLayout.reset()

	var root: Control = Control.new()
	root.size = Vector2(960, 540)
	add_child(root)

	# Every property below is authored in hud.tscn, so ALL of them are set before
	# the node enters the tree — a scene applies them at instantiation, ahead of
	# _ready. The resizer samples the host's shipped geometry in its own _ready,
	# so a harness that configured the panel afterwards would hand it a blank
	# "authored" state and make the reset check measure nothing real.
	var tracker: PanelContainer = QUEST_TRACKER.new()
	tracker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tracker.anchor_left = 1.0
	tracker.anchor_right = 1.0
	tracker.offset_left = -224.0
	tracker.offset_right = -8.0
	tracker.offset_top = 196.0
	tracker.offset_bottom = 224.0
	tracker.custom_minimum_size = Vector2(216, 0)
	root.add_child(tracker)
	# Hud._ready re-anchors it into the right rail afterwards; mirror that too.
	tracker.offset_top = 128.0
	tracker.call(&"_display", {
		"name": "The Forgemaster's Errand",
		"complete": false,
		"completion": 0,
		"objectives": [
			{"desc": "Speak with Forgemaster Helka · Fire Forge, at the entrance",
			 "count": 0, "required": 1, "countable": true},
		],
	})
	tracker.show()

	var party: PanelContainer = PARTY_HUD.new()
	root.add_child(party)
	party.call(&"_on_roster", {
		"leader": 1,
		"names": [{"id": 1, "name": "Kaelen", "leader": true}],
	})

	await get_tree().process_frame
	await get_tree().process_frame

	var tracker_resizer: HudResizer = tracker.get_node_or_null("HudResizer") as HudResizer
	var party_resizer: HudResizer = party.get_node_or_null("HudResizer") as HudResizer
	var loot_resizer: HudResizer = LootFeed.get_child(0).get_node_or_null("HudResizer") as HudResizer

	_check("quest tracker has a resizer", tracker_resizer != null)
	_check("party hud has a resizer", party_resizer != null)
	_check("loot lane has a resizer", loot_resizer != null)
	if tracker_resizer == null or party_resizer == null or loot_resizer == null:
		_finish()
		return

	# --- 1. Locked is the default and is inert ------------------------------
	HudLayout.set_locked(true)
	await get_tree().process_frame
	_check("locked: resizer hidden", not tracker_resizer.visible)
	_check(
		"locked: resizer ignores the mouse (world clicks pass through)",
		tracker_resizer.mouse_filter == Control.MOUSE_FILTER_IGNORE
	)
	_check(
		"locked: host mouse_filter untouched (party still STOP)",
		party.mouse_filter == Control.MOUSE_FILTER_STOP
	)
	_check(
		"locked: host mouse_filter untouched (tracker still IGNORE)",
		tracker.mouse_filter == Control.MOUSE_FILTER_IGNORE
	)

	# --- 2. Unlocked shows handles and accepts input -------------------------
	HudLayout.set_locked(false)
	await get_tree().process_frame
	_check("unlocked: resizer visible", tracker_resizer.visible)
	_check(
		"unlocked: resizer takes the mouse",
		tracker_resizer.mouse_filter == Control.MOUSE_FILTER_STOP
	)

	# --- 3. Drag the quest tracker WIDER ------------------------------------
	# It is pinned to the right edge (GROW_DIRECTION_BEGIN), so the free edge is
	# LEFT and dragging left must make it wider.
	var before: float = tracker.size.x
	var wrap_before: float = _first_label_wrap(tracker)
	await _drag(tracker_resizer, Vector2(3.0, 30.0), Vector2(-60.0, 0.0))
	_check(
		"tracker: dragging the LEFT edge left widens it (%.0f -> %.0f)" % [before, tracker.size.x],
		tracker.size.x > before + 40.0
	)
	_check(
		"tracker: text re-wrapped to the new width (%.0f -> %.0f)"
			% [wrap_before, _first_label_wrap(tracker)],
		_first_label_wrap(tracker) > wrap_before + 40.0
	)
	_check(
		"tracker: right edge is pinned, so it grew leftward",
		is_equal_approx(tracker.offset_right, -8.0)
	)

	# --- 4. Clamps ----------------------------------------------------------
	await _drag(tracker_resizer, Vector2(3.0, 30.0), Vector2(-900.0, 0.0))
	_check(
		"tracker: max width clamp holds (%.0f <= %.0f)" % [tracker.size.x, QuestTracker.MAX_WIDTH],
		tracker.size.x <= QuestTracker.MAX_WIDTH + 0.5
	)
	await _drag(tracker_resizer, Vector2(3.0, 30.0), Vector2(900.0, 0.0))
	_check(
		"tracker: min width clamp holds (%.0f >= %.0f)" % [tracker.size.x, QuestTracker.MIN_WIDTH],
		tracker.size.x >= QuestTracker.MIN_WIDTH - 0.5
	)

	# --- 5. Party grows the OTHER way ---------------------------------------
	var party_before: float = party.size.x
	await _drag(party_resizer, Vector2(party.size.x - 3.0, 20.0), Vector2(50.0, 0.0))
	_check(
		"party: dragging the RIGHT edge right widens it (%.0f -> %.0f)"
			% [party_before, party.size.x],
		party.size.x > party_before + 30.0
	)
	_check("party: left edge is pinned", is_equal_approx(party.offset_left, 58.0))

	# --- 6. Loot lane maps height to a row count -----------------------------
	var rows_before: int = LootFeed.max_rows
	await _drag(
		loot_resizer,
		Vector2(20.0, loot_resizer.size.y - 3.0),
		Vector2(0.0, -LootFeed.ROW_PITCH * 3.0)
	)
	_check(
		"loot: dragging the lane shorter drops the row count (%d -> %d)"
			% [rows_before, LootFeed.max_rows],
		LootFeed.max_rows < rows_before
	)
	_check(
		"loot: row count respects its floor",
		LootFeed.max_rows >= LootFeed.MIN_ROWS
	)

	# --- 7. Persistence, and only on release ---------------------------------
	_check(
		"stored size survives the drag",
		HudLayout.size_for(&"party_hud").x > 0.0
	)

	# --- 8. Reset puts the authored sizes back -------------------------------
	# Drag the tracker off its default FIRST. An earlier version of this block
	# happened to run with the tracker already sitting at 216 (the min-clamp step
	# above had walked it back there), so "reset restores 216" passed without
	# reverting anything at all.
	await _drag(tracker_resizer, Vector2(3.0, 30.0), Vector2(-70.0, 0.0))
	var tracker_dragged: float = tracker.size.x
	var party_dragged: float = party.size.x
	_check("reset precondition: tracker is away from its default (%.0f)" % tracker_dragged,
		not is_equal_approx(tracker_dragged, 216.0))
	_check("reset precondition: party is away from its default (%.0f)" % party_dragged,
		not is_equal_approx(party_dragged, 148.0))
	var wrap_dragged: float = _first_label_wrap(tracker)

	HudLayout.reset()
	await get_tree().process_frame
	await get_tree().process_frame

	_check(
		"reset: quest tracker back to its authored width (%.0f -> %.0f)"
			% [tracker_dragged, tracker.size.x],
		is_equal_approx(tracker.size.x, 216.0)
	)
	_check(
		"reset: party roster back to its authored width (%.0f -> %.0f)"
			% [party_dragged, party.size.x],
		is_equal_approx(party.size.x, 148.0)
	)
	_check(
		"reset: tracker text re-wrapped to the authored width (%.0f -> %.0f)"
			% [wrap_dragged, _first_label_wrap(tracker)],
		is_equal_approx(_first_label_wrap(tracker), 200.0)
	)
	_check("reset: stored sizes are gone", HudLayout.size_for(&"party_hud") == Vector2.ZERO)
	_check("reset: HUD is locked again", HudLayout.locked)

	# --- 9. Re-locking puts everything back ----------------------------------
	HudLayout.set_locked(false)
	await get_tree().process_frame
	HudLayout.set_locked(true)
	await get_tree().process_frame
	_check(
		"re-locked: every resizer is inert again",
		tracker_resizer.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and party_resizer.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and loot_resizer.mouse_filter == Control.MOUSE_FILTER_IGNORE
	)

	_finish()


## Press at [param local] inside the resizer, move by [param delta], release.
## Feeds _gui_input directly: the point is to test the resizer's own handling,
## not the viewport's hit routing.
func _drag(resizer: HudResizer, local: Vector2, delta: Vector2) -> void:
	var origin: Vector2 = resizer.global_position + local

	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = local
	press.global_position = origin
	resizer._gui_input(press)

	# Two steps, so a resizer that only reacts to the final position is caught.
	for step: float in [0.5, 1.0]:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = local + delta * step
		motion.global_position = origin + delta * step
		resizer._gui_input(motion)
		await get_tree().process_frame

	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = local + delta
	release.global_position = origin + delta
	resizer._gui_input(release)
	await get_tree().process_frame


## The wrap width the tracker handed its first label — the reflow signal.
func _first_label_wrap(tracker: Control) -> float:
	for child: Node in tracker.get_children():
		if child is VBoxContainer:
			for line: Node in child.get_children():
				if line is Label:
					return (line as Label).custom_minimum_size.x
	return 0.0


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print(("  PASS  " if ok else "  FAIL  ") + what)


func _finish() -> void:
	ClientState.settings.data[HudLayout.SETTING_SECTION] = _saved_layout
	ClientState.settings.save()
	print("--- %s ---" % ("ALL PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
