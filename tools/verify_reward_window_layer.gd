@tool
extends Node
## Gate for the chest reward window's stacking.
##
##   godot --headless --path . tools/verify_reward_window_layer.tscn
##
## SCENE mode, not `-s`: this mounts the real client UI, whose scripts reach the
## Client / ClientState autoloads. Under `-s` they would not COMPILE and the gate
## would report nothing while exiting 0 (see tools/run_verify.sh).
##
## WHAT WENT WRONG, AND WHY A z_index GATE WOULD NOT HAVE CAUGHT IT
## The window used to be a HUD child at z_index 110, one above sub_menu's 100.
## Measured on z alone that is correct, and it paints correctly — which is why
## the bug survived review. Godot picks GUI input by walking the tree in REVERSE
## order and ignores z_index entirely, and HUD and Submenu are siblings under one
## CanvasLayer with Submenu SECOND. So a MenuShell menu's full-rect dim backdrop
## (MOUSE_FILTER_STOP) was always offered the click first: with the Daily
## Skilling Board open, the reward window rendered on top of the board while
## every press on Claim All / Bank All / X went to the board behind it.
##
## Canvas LAYERS are the one ordering Godot applies to both paint AND picking, so
## that is what this asserts — the window is on its own layer, above the UI layer
## and below the notification layers, and NOT parented anywhere under Submenu.
## Anyone who "simplifies" it back to a z_index fails here.

const UI_SCENE: String = "res://source/client/ui/ui.tscn"
const HUD_SCRIPT: String = "res://source/client/ui/hud/hud.gd"
const BOARD_SCRIPT: String = "res://source/client/ui/menus/daily_board/daily_board_ui.gd"

## Notification layers the reward window must stay UNDER, by autoload file name.
const ABOVE: Array[String] = ["loot_feed", "announcer", "toaster", "transition"]

var _reward_layer: int = 0
var _fails: PackedStringArray = PackedStringArray()


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_fails.append(label)


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_reward_layer = _reward_layer_in_source()
	_check(_reward_layer > 0, "hud.gd declares REWARD_LAYER (%d)" % _reward_layer)
	_check_stacking()
	await _check_live_tree()
	_check_wiring()

	print("")
	if _fails.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL (%d)" % _fails.size())
		for f: String in _fails:
			print("  - %s" % f)
	get_tree().quit(0)


## The layer numbers, read out of the other layers' own source rather than
## hard-coded here, so moving one of them shows up as a failure instead of as
## silent drift.
##
## FROM SOURCE AND NOT FROM THE LIVE AUTOLOADS, deliberately. Every one of these
## autoloads opens `_ready` with `if not GameMode.is_client(): queue_free()`, and
## a headless tool run is not a client — so they free themselves and their
## `layer` reads back as the default 1. Asserting against that would pass this
## gate no matter what anyone did to the numbers.
func _check_stacking() -> void:
	print("[layers]")
	var reward: int = _reward_layer
	var ui_layer: int = _layer_in(UI_SCENE)
	_check(ui_layer > 0, "read the UI CanvasLayer's layer (%d)" % ui_layer)
	_check(reward > ui_layer, "reward layer (%d) is above the UI layer (%d)" % [reward, ui_layer])
	for autoload_name: String in ABOVE:
		# This window raises toasts of its own ("Bag filled — sent the rest to
		# your bank"), so covering the notification layers would hide the answer
		# to the question it just made the player ask.
		var other: int = _layer_in("res://source/client/autoload/%s.gd" % autoload_name)
		_check(other > 0, "read %s's layer (%d)" % [autoload_name, other])
		_check(
			reward < other,
			"reward layer (%d) is below %s (%d)" % [reward, autoload_name, other]
		)


## REWARD_LAYER, read out of hud.gd's SOURCE rather than as `HUD.REWARD_LAYER`.
##
## A hard reference would make it a COMPILE-time dependency, and that fails in
## the worst possible way: delete the constant and this script stops parsing,
## the tool scene comes up with no script at all, nothing ever calls quit(), and
## the run HANGS instead of failing. Parsing it means the same edit reports a
## plain VERIFY_FAIL and the suite moves on.
func _reward_layer_in_source() -> int:
	var re := RegEx.new()
	re.compile("(?m)^const REWARD_LAYER[^=]*= *([0-9]+)")
	var m: RegExMatch = re.search(FileAccess.get_file_as_string(HUD_SCRIPT))
	return int(m.get_string(1)) if m != null else 0


## First `layer = <int>` assignment in a script or scene file, or 0.
func _layer_in(path: String) -> int:
	var re := RegEx.new()
	# Character classes, not \s / \d: GDScript string literals reject those escapes.
	re.compile("(?m)^[ \t]*layer[ \t]*=[ \t]*([0-9]+)")
	var m: RegExMatch = re.search(FileAccess.get_file_as_string(path))
	return int(m.get_string(1)) if m != null else 0


## Mount the real UI and read back where the window actually landed.
func _check_live_tree() -> void:
	print("[live tree]")
	var ui: Node = load(UI_SCENE).instantiate()
	get_tree().root.add_child(ui)
	await get_tree().process_frame

	var hud: Control = ui.get_node_or_null("HUD") as Control
	var submenu: Node = ui.get_node_or_null("Submenu")
	if hud == null or submenu == null:
		_check(false, "ui.tscn still has a HUD and a Submenu")
		ui.free()
		return

	var window: Control = hud.get("chest_reward_window") as Control
	if window == null or not is_instance_valid(window):
		_check(false, "HUD mounted a chest reward window")
		ui.free()
		return

	var host: Node = window.get_parent()
	_check(host is CanvasLayer, "window's parent is a CanvasLayer, not a Control")
	if host is CanvasLayer:
		_check(
			(host as CanvasLayer).layer == _reward_layer,
			"window's CanvasLayer is at REWARD_LAYER (%d)" % _reward_layer
		)
	_check(not submenu.is_ancestor_of(window), "window is NOT under Submenu")
	# The window now sits above every menu. If its ROOT took input it would
	# blanket the whole screen and make the game unclickable — the root spans the
	# viewport only so the panel can anchor against it.
	_check(
		window.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"window root is MOUSE_FILTER_IGNORE (raised layer stays click-through)"
	)
	var panel: Control = null
	for child: Node in window.get_children():
		if child is PanelContainer:
			panel = child as Control
			break
	_check(panel != null, "window has a panel")
	if panel != null:
		_check(
			panel.mouse_filter == Control.MOUSE_FILTER_STOP,
			"window panel is MOUSE_FILTER_STOP (its own buttons take the click)"
		)
	# A CanvasLayer is not a Control, so it breaks theme inheritance: without the
	# explicit hand-off the window would silently fall back to the project master
	# theme and ignore the player's palette.
	_check(
		window.theme == hud.theme,
		"window carries the HUD's theme across the CanvasLayer break"
	)
	ui.free()


## Source-level: exercising the board's stand-down for real needs a server to
## answer quest.board.claim, but the ORDER of the two lines is the whole
## behaviour, and that is readable without one.
func _check_wiring() -> void:
	print("[wiring]")
	var board: String = FileAccess.get_file_as_string(BOARD_SCRIPT)
	var present_at: int = board.find("UniversalChestManager.present")
	var hide_at: int = board.find("\t\thide()")
	_check(present_at > 0, "daily board still presents the claim's chest")
	_check(
		hide_at > 0 and hide_at < present_at,
		"daily board hides itself BEFORE presenting the chest"
	)
