extends Node
## Gate for the Boss Hunt shared-lives pass.
##
##   godot --path . --mode=client res://tools/verify_boss_hunt_lives.tscn
##
## Scene mode, not `-s`: BossHuntService reaches WorldServer/GroupService and
## Player pulls in half the client tree, so a headless script run with no
## autoloads cannot compile either one and every check below would "fail"
## against code that is fine.
##
## Prints VERIFY_PASS only when:
##   * boss_hunt_service.gd, player.gd and boss_hunt_hud.gd all COMPILE — the
##     three files the pass touched on the server, the death path and the HUD,
##   * the pool is a flat 3 shared by the party, not a per-member count,
##   * the death hooks exist with the shape Player.die calls them by, and the
##     read-only twin has_life_left is there for the unstick path,
##   * a life-spending death does NOT recall to the Guild Hall (return_home is
##     gated on it) — the whole point of the change,
##   * the client subscribes to the boss_hunt.failed push _fail_hunt sends.
##
## Behaviour under a real party is NOT covered here: that needs a live
## WorldServer, a GroupService group and a loaded arena instance. Run a contract
## in the local stack and die three times.

const SERVICE := "res://source/common/gameplay/boss_hunt/boss_hunt_service.gd"
const PLAYER := "res://source/common/gameplay/characters/player/player.gd"
const HUD := "res://source/client/ui/hud/boss_hunt_hud.gd"
const LOCAL_PLAYER := "res://source/client/local_player/local_player.gd"
const MENU := "res://source/client/ui/menus/boss_hunt/boss_hunt_menu.gd"

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_check_compiles()
	_check_pool()
	_check_wiring()
	_check_client()
	_check_eject_roster()
	if _failures.is_empty():
		print("VERIFY_PASS")
		get_tree().quit(0)
		return
	for line: String in _failures:
		printerr("FAIL: %s" % line)
	print("VERIFY_FAIL (%d)" % _failures.size())
	get_tree().quit(1)


func _fail(line: String) -> void:
	_failures.append(line)


func _source(path: String) -> String:
	var script: GDScript = load(path) as GDScript
	if script == null:
		_fail("%s will not load" % path)
		return ""
	return script.source_code


func _check_compiles() -> void:
	for path: String in [SERVICE, PLAYER, HUD, LOCAL_PLAYER, MENU]:
		var script: GDScript = load(path) as GDScript
		if script == null:
			_fail("%s will not load" % path)
		elif not script.can_instantiate() and script.get_instance_base_type() == &"":
			_fail("%s loaded but did not compile" % path)
	print("compiled: 5 touched scripts")


func _check_pool() -> void:
	var script: GDScript = load(SERVICE) as GDScript
	if script == null:
		return
	var consts: Dictionary = script.get_script_constant_map()
	if not consts.has(&"CONTRACT_LIVES"):
		_fail("BossHuntService has no CONTRACT_LIVES")
		return
	var lives: int = int(consts[&"CONTRACT_LIVES"])
	if lives != 3:
		_fail("CONTRACT_LIVES is %d, expected 3" % lives)
	if not consts.has(&"FAIL_EJECT_DELAY_S"):
		_fail("BossHuntService has no FAIL_EJECT_DELAY_S")
	# The pool must not be sized off the party — "3 per contract regardless of
	# group size" is the whole point, so a members.size() near the pool is a bug.
	var src: String = script.source_code
	var at: int = src.find("_lives[group_id] = CONTRACT_LIVES")
	if at < 0:
		_fail("the pool is not seeded from CONTRACT_LIVES in start_hunt")
	elif src.substr(maxi(0, at - 200), 200).contains("members.size()"):
		_fail("the pool looks sized by party size — it must be flat")
	print("pool: %d shared lives, flat across party size" % lives)


func _check_wiring() -> void:
	var service: String = _source(SERVICE)
	for needed: String in ["func register_hunt_death", "func has_life_left", "func _fail_hunt"]:
		if not service.contains(needed):
			_fail("BossHuntService is missing %s" % needed)
	if not service.contains("&\"boss_hunt.failed\""):
		_fail("_fail_hunt never pushes boss_hunt.failed")
	if not service.contains("\"lives\": _lives.get(group_id"):
		_fail("the HUD payload does not carry the lives count")

	var player: String = _source(PLAYER)
	if not player.contains("BossHuntService.register_hunt_death(self)"):
		_fail("Player.die never spends a contract life")
	# The life only means something if the hunter stays in the arena: a recall
	# drops them from the group and ends their contract early.
	if not player.contains("not sparring_death and not hunt_respawn"):
		_fail("a life-spending death still returns home — the life buys nothing")
	if not player.contains("BossHuntService.has_life_left(self)"):
		_fail("_should_return_home does not honour a live contract")
	print("wiring: die() spends a life and stays in the arena")


## Stand-in for a ServerInstance: BossHuntService.eject_roster only reads
## `players_by_peer_id` off it, which is the arena's authoritative "who is
## physically in this room" map.
class FakeArena extends Node:
	var players_by_peer_id: Dictionary[int, Node] = {}


## The teardown must move EVERY hunter out, at every party size. GroupService is
## dependency-free static state, so a real group can be formed here and handed to
## the real eject_roster — this exercises the shipping function, not a copy.
func _check_eject_roster() -> void:
	for size: int in [1, 2, 3, 4]:
		var peers: Array = []
		for i: int in size:
			peers.append(9000 + size * 10 + i)
		var group_id: int = GroupService.create_group(peers, peers[0])

		# Everyone in the arena and on the roster: all of them get recalled.
		var arena := FakeArena.new()
		for peer: int in peers:
			arena.players_by_peer_id[peer] = arena
		var roster: Array[int] = BossHuntService.eject_roster(group_id, arena)
		for peer: int in peers:
			if not roster.has(peer):
				_fail("%d-man: peer %d would be left in the arena" % [size, peer])
		if roster.size() != size:
			_fail("%d-man: eject roster is %d peers, expected %d — a recall would
					be issued twice" % [size, roster.size(), size])

		# A hunter whose GroupService seat desynced is still in the ROOM, so the
		# room sweep has to catch them or they are stranded in a dead arena.
		var stray: int = 9500 + size
		arena.players_by_peer_id[stray] = arena
		roster = BossHuntService.eject_roster(group_id, arena)
		if not roster.has(stray):
			_fail("%d-man: a hunter missing from the roster is not swept from the room" % size)

		# ...and one still on the roster but no longer in the room must be
		# recalled too, or their group seat never clears and the lobby locks them
		# out of every future contract and dungeon.
		arena.players_by_peer_id.erase(peers[0])
		roster = BossHuntService.eject_roster(group_id, arena)
		if not roster.has(peers[0]):
			_fail("%d-man: a hunter absent from the room is dropped from the eject" % size)

		# The contract must end with nobody holding a group seat.
		GroupService.dissolve(group_id)
		for peer: int in peers:
			if GroupService.group_of(peer) != 0:
				_fail("%d-man: peer %d still holds a group seat after dissolve" % [size, peer])
		if not GroupService.members_of(group_id).is_empty():
			_fail("%d-man: group %d survived dissolve" % [size, group_id])
		arena.free()
		print("eject: %d-man clears the arena and the roster" % size)


func _check_client() -> void:
	if not _source(LOCAL_PLAYER).contains("&\"boss_hunt.failed\""):
		_fail("the client never subscribes to boss_hunt.failed")
	var hud: String = _source(HUD)
	if not hud.contains("payload.get(\"lives\""):
		_fail("BossHuntHud ignores the lives field")
	print("client: failed banner subscribed, HUD reads lives")
