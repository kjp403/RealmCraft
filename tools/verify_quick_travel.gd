extends Node
## Headless gate for the Wayfarer quick-travel system. Prints VERIFY_PASS only if
## every check below holds. Run:
##   godot --headless --path . --mode=client res://tools/verify_quick_travel.tscn
##
## Runs as a SCENE, not a `-s` tool, for the reason render_bank_previews.gd
## documents: `-s` starts a bare SceneTree with no autoloads, and npc.gd
## references ClientState -- under `-s` it fails to COMPILE, so an instantiated
## Wayfarer comes back as a plain Node and this file reports a placement failure
## that is purely an artefact of the harness.
##
## Covers the parts that fail SILENTLY in this project: a .tres whose script
## reference did not resolve, an interaction the handlers cannot find, a map that
## lost its NPC, and the surge arithmetic (which no one can eyeball from a
## running server without burning 50k gold a ride).

const WAYFARER: String = "res://source/common/gameplay/characters/npc/npcs/wayfarer.tres"
const HANDLERS: Array[String] = [
	"res://source/server/world/components/data_request_handlers/travel.quote.gd",
	"res://source/server/world/components/data_request_handlers/travel.quick.gd",
]
const HUBS: Dictionary = {
	"res://source/common/gameplay/maps/maps/guild_house/inside_map.tscn": Vector2(-6, -320),
	"res://source/common/gameplay/maps/maps/smith_house/inside_map.tscn": Vector2(50, 336),
}
## Destination order + base fares the design calls for.
const EXPECTED: Array = [
	["Guild Hall", 15000, &"GuildHouse"],
	["Smith House", 15000, &"SmithHouse"],
	["The Sewers", 25000, &"sewers"],
	["The Desert", 35000, &"desert"],
	["Fire Forge", 50000, &"fire_forge"],
]
## Price ceiling from the brief: no destination is authored above it, and no
## fare may be CHARGED above it either, surge included.
const FEE_CAP: int = 50000

var _failures: PackedStringArray = []


func _ready() -> void:
	_check_handlers()
	var desk: QuickTravelInteraction = _check_resource()
	_check_maps()
	_check_surge()
	print("")
	if _failures.is_empty():
		print("VERIFY_PASS (%d destinations)" % (desk.destinations.size() if desk else 0))
	else:
		print("VERIFY_FAIL")
		for f: String in _failures:
			print("  - %s" % f)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _ok(label: String, detail: String = "") -> void:
	print("  ok  %s%s" % [label, ("  %s" % detail) if not detail.is_empty() else ""])


## Compiling a handler proves its type references resolve — the usual cause of a
## request that answers "handler_load_failed" at runtime and nowhere else.
func _check_handlers() -> void:
	print("[handlers]")
	for path: String in HANDLERS:
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			_fail("handler will not compile: %s" % path)
			continue
		_ok(path.get_file())


func _check_resource() -> QuickTravelInteraction:
	print("[wayfarer.tres]")
	var npc_res: NPCResource = load(WAYFARER) as NPCResource
	if npc_res == null:
		_fail("wayfarer.tres did not load as an NPCResource")
		return null
	_ok("npc_name", npc_res.npc_name)

	if npc_res.skin == null:
		_fail("wayfarer has no skin")
	# The pink recolor is the whole point of this NPC being distinguishable.
	var mat: ShaderMaterial = npc_res.skin_material as ShaderMaterial
	if mat == null or mat.shader == null:
		_fail("wayfarer skin_material is not a ShaderMaterial with a shader")
	else:
		_ok("recolor material", mat.shader.resource_path.get_file())

	var desk: QuickTravelInteraction = null
	for inter: NPCInteraction in npc_res.interactions:
		if inter is QuickTravelInteraction:
			desk = inter as QuickTravelInteraction
	if desk == null:
		_fail("wayfarer has no QuickTravelInteraction (handlers would find no desk)")
		return null

	if desk.destinations.size() != EXPECTED.size():
		_fail("expected %d destinations, found %d" % [EXPECTED.size(), desk.destinations.size()])
		return desk

	for i: int in EXPECTED.size():
		var want: Array = EXPECTED[i]
		var dest: QuickTravelDestination = desk.destinations[i]
		if dest == null:
			_fail("destination %d is an empty slot" % i)
			continue
		if dest.display_label() != want[0]:
			_fail("destination %d label: expected '%s', got '%s'" % [i, want[0], dest.display_label()])
		if dest.fee != want[1]:
			_fail("destination %d fee: expected %d, got %d" % [i, want[1], dest.fee])
		if dest.fee > FEE_CAP:
			_fail("destination %d base fare %d exceeds the %d cap" % [i, dest.fee, FEE_CAP])
		if dest.target_instance == null:
			_fail("destination %d has no target_instance" % i)
		elif dest.target_instance.instance_name != want[2]:
			_fail("destination %d instance: expected %s, got %s" % [
				i, want[2], dest.target_instance.instance_name
			])
		else:
			_ok("%-12s %6d G" % [want[0], dest.fee], "-> %s" % dest.target_instance.instance_name)
	return desk


## The NPC must actually exist in both hubs, carry the Wayfarer resource, and sit
## where the placement probe said the floor was clear.
func _check_maps() -> void:
	print("[hub placement]")
	for path: String in HUBS:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			_fail("hub map failed to load: %s" % path)
			continue
		var root: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		var found: Node = root.find_child("Wayfarer", true, false)
		if found == null:
			_fail("no Wayfarer node in %s" % path.get_file())
		elif not (found is NPC):
			_fail("Wayfarer in %s is not an NPC node" % path.get_file())
		else:
			var npc: NPC = found as NPC
			if npc.npc_resource == null or npc.npc_resource.npc_name != "Wayfarer":
				_fail("Wayfarer in %s carries the wrong npc_resource" % path.get_file())
			elif (npc as Node2D).position != HUBS[path]:
				_fail("Wayfarer in %s at %s, expected %s" % [
					path.get_file(), (npc as Node2D).position, HUBS[path]
				])
			else:
				_ok(path.get_file().get_basename() + " / " + path.get_base_dir().get_file(),
					"Wayfarer @ %s" % (npc as Node2D).position)
		root.free()


## Surge is the one piece of arithmetic here with an off-by-one worth guarding:
## the FOURTH ride in a window is the first surged one.
func _check_surge() -> void:
	print("[frequency surge]")
	var pid: int = 987654321
	QuickTravelService.forget(pid)
	# ride number -> expected multiplier on the fare paid for THAT ride. The
	# multiplier itself is unbounded; the CAP is applied to the fare, not here.
	var expected: Array = [1.0, 1.0, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5]
	for i: int in expected.size():
		var ride_no: int = i + 1
		var got: float = QuickTravelService.multiplier(pid)
		if not is_equal_approx(got, expected[i]):
			_fail("ride #%d multiplier: expected %.1fx, got %.1fx" % [ride_no, expected[i], got])
		QuickTravelService.record_ride(pid)
	_ok("multiplier curve", "1.0x x3, then +0.5x per ride, uncapped")

	# THE price rule: at 4.5x surge, every stop -- cheapest to dearest -- must
	# still charge at most the ceiling, and the top tier must not have moved at all.
	for base: int in [15000, 25000, 35000, 50000]:
		var charged: int = QuickTravelService.fee_for(pid, base)
		if charged > FEE_CAP:
			_fail("a %d G stop charges %d G at full surge, over the %d G cap" % [
				base, charged, FEE_CAP
			])
	if QuickTravelService.fee_for(pid, FEE_CAP) != FEE_CAP:
		_fail("the top-tier fare moved off the %d G cap" % FEE_CAP)
	else:
		_ok("fare ceiling", "every stop charges at most %d G, surge included" % FEE_CAP)

	if QuickTravelService.rides_in_window(pid) != expected.size():
		_fail("ride history did not record every ride")
	# A player with no history must be at base fare (the "10 minutes quiet" state).
	QuickTravelService.forget(pid)
	if not is_equal_approx(QuickTravelService.multiplier(pid), 1.0):
		_fail("surge did not reset once the window emptied")
	else:
		_ok("window reset", "cleared history -> 1.0x")
