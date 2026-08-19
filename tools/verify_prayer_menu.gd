extends Node
## Opens the prayer book the way the HUD dock icon does — show() with NO
## argument — and asserts it is escapable IMMEDIATELY, before any server reply.
##
## The freeze this guards against: hud.display_menu only calls open() for menus
## opened WITH an argument, so a menu that builds solely in open() comes up as
## an empty full-rect Control that eats every click and has no Close button.

const MENU: String = "res://source/client/ui/menus/prayer/prayer_menu.tscn"

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	await get_tree().process_frame

	var scene: PackedScene = load(MENU) as PackedScene
	_check(scene != null, "prayer_menu.tscn loads")
	if scene == null:
		return _finish()

	var menu: Control = scene.instantiate() as Control
	_check(menu != null, "instantiates as a Control")
	if menu == null:
		return _finish()

	# A Control with a script that failed to compile reports no script at all —
	# that alone produces the invisible full-screen blocker.
	_check(menu.get_script() != null, "script attached (compiled)")
	_check(menu.has_method(&"open"), "has open()")

	# Reproduce display_menu's FIRST-open path exactly: add the freshly
	# instantiated menu to the tree, then show() it. The scene root ships
	# visible = true, so that show() is a no-op and visibility_changed never
	# fires — open() is not called either (no argument). If the menu only
	# builds in one of those two hooks, this is where it comes up empty.
	_check(menu.visible, "scene root ships visible = true (show() will no-op)")
	add_child(menu)
	menu.show()
	await get_tree().process_frame

	var buttons: Array[Button] = []
	_collect_buttons(menu, buttons)
	_check(not buttons.is_empty(), "renders at least one button before server reply")

	var has_close: bool = false
	for b: Button in buttons:
		if b.text.strip_edges().to_lower() == "close":
			has_close = true
			break
	_check(has_close, "renders a working Close button (cannot trap the player)")

	# PrayerBook must resolve or _build() dies partway and leaves a blocker.
	_check(PrayerBook.PRAYERS.size() > 0, "PrayerBook.PRAYERS populated")
	var missing_icons: int = 0
	for p: PrayerResource in PrayerBook.PRAYERS:
		if p == null or p.icon == null:
			missing_icons += 1
	_check(missing_icons == 0, "every prayer resolves its icon (%d missing)" % missing_icons)

	_finish()


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	if node is Button:
		out.append(node as Button)
	for child: Node in node.get_children():
		_collect_buttons(child, out)


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  ok    %s" % label)
	else:
		_fail += 1
		printerr("  FAIL  %s" % label)


func _finish() -> void:
	print("\nPASS %d  FAIL %d" % [_pass, _fail])
	print("VERIFY_PASS" if _fail == 0 else "VERIFY_FAIL")
	get_tree().quit(0 if _fail == 0 else 1)
