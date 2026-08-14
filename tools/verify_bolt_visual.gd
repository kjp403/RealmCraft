extends SceneTree
## Gate for the arcane bolt body (BoltVisual in wand/bolt.tscn). Drives the REAL scene, at the
## REAL speed and tint of each ability that fires it, so what it prints and what it renders are
## the shipping thing rather than a mock-up.
##
## Checks, then a strip:
##   * bolt.tscn root is a Projectile carrying a "Visual" child that is a BoltVisual (the node
##     name the Mecha Golem's arm cannon looks up in HostileNpc._spawn_arm_bolt).
##   * the wake is handed to the MAP, not kept on the bolt, and is tinted to match it.
##   * killing a bolt mid-flight leaves the wake behind to burn down instead of popping.
##
## The visual is client-only, so this fakes a CLIENT peer — with the offline peer the other render
## tools use, multiplayer.is_server() is true and BoltVisual correctly frees itself.
##
## Must run WINDOWED (no --headless) — headless has no rasteriser:
##   godot --path . -s tools/verify_bolt_visual.gd
##   godot --path . -s tools/verify_bolt_visual.gd -- --outdir=C:/tmp/bolts

const BOLT := "res://source/common/gameplay/items/weapons/wand/bolt.tscn"
const ABILITY_DIR := "res://source/common/gameplay/combat/ability/ability_collection/bolt_shoot/"

## Every ability that fires bolt.tscn, plus a fourth lane that kills the bolt mid-flight.
const LANES: Array[Dictionary] = [
	{"ability": "wand_bolt.tres", "kill": false},
	{"ability": "ember_bolt.tres", "kill": false},
	{"ability": "overload.tres", "kill": false},
	{"ability": "wand_bolt.tres", "kill": true},
]

const LANE_W := 700
const LANE_H := 68
const BG := Color(0.105, 0.115, 0.155)
const X0 := 53.0
const X1 := 647.0
const GAP := 0.45
const FPS := 20
const FRAMES := 52

var _outdir: String = "user://bolt_visual"
var _sv: SubViewport
var _fails: Array[String] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			_outdir = arg.substr("--outdir=".length())
	call_deferred(&"_go")


func _go() -> void:
	# A CLIENT peer, not the offline one: BoltVisual is client-only by design.
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", 59999)
	root.multiplayer.multiplayer_peer = peer
	if root.multiplayer.is_server():
		_fails.append("harness could not fake a client peer — is_server() is still true")

	var dir: String = ProjectSettings.globalize_path(_outdir) if _outdir.begins_with("user://") else _outdir
	DirAccess.make_dir_recursive_absolute(dir)

	var strip_h: int = LANE_H * LANES.size()
	_sv = SubViewport.new()
	_sv.size = Vector2i(LANE_W, strip_h)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.world_2d = World2D.new()
	root.add_child(_sv)

	var map := Node2D.new()   # stands in for the Map — the node BoltVisual hands its wake to
	_sv.add_child(map)
	var bg := ColorRect.new()
	bg.size = Vector2(LANE_W, strip_h)
	bg.color = BG
	bg.z_index = -20
	map.add_child(bg)
	var cam := Camera2D.new()
	cam.position = Vector2(LANE_W, strip_h) * 0.5
	map.add_child(cam)
	cam.make_current()

	for i: int in LANES.size():
		if i > 0:
			var rule := ColorRect.new()
			rule.size = Vector2(LANE_W, 1.0)
			rule.position = Vector2(0.0, LANE_H * float(i))
			rule.color = Color(1, 1, 1, 0.05)
			rule.z_index = 10
			map.add_child(rule)
		var lane := Lane.new()
		lane.ability = load(ABILITY_DIR + String(LANES[i]["ability"])) as BoltShootAbility
		lane.kill_midway = bool(LANES[i]["kill"])
		lane.base_y = LANE_H * (float(i) + 0.5)
		lane.x0 = X0
		lane.x1 = X1
		lane.gap = GAP
		map.add_child(lane)   # a child of the map, so bolt->lane->map is the real caster depth

	await process_frame
	await process_frame

	await _check_structure()

	var t0: int = Time.get_ticks_msec()
	var step: float = 1.0 / float(FPS)
	var taken: int = 0
	while taken < FRAMES:
		await process_frame
		var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
		if elapsed < float(taken) * step:
			continue
		_sv.get_texture().get_image().save_png("%s/shipped_%02d.png" % [dir, taken])
		taken += 1

	if _fails.is_empty():
		print("VERIFY_PASS bolt_visual frames=%d dir=%s" % [taken, dir])
		quit(0)
		return # quit() only REQUESTS the exit — without this the fail branch prints too
	for f: String in _fails:
		printerr("VERIFY_FAIL: " + f)
	print("VERIFY_FAIL bolt_visual (%d)" % _fails.size())
	quit(1)


## Structural checks against a freshly built bolt, wired the way BoltShootAbility wires one.
func _check_structure() -> void:
	var scene: PackedScene = load(BOLT) as PackedScene
	if scene == null:
		_fails.append("bolt.tscn failed to load")
		return
	var bolt: Node = scene.instantiate()
	if not (bolt is Projectile):
		_fails.append("bolt.tscn root is %s, expected Projectile" % bolt.get_class())

	# The name HostileNpc._spawn_arm_bolt looks up to swap the golem's arm in.
	var visual: Node = bolt.get_node_or_null(^"Visual")
	if visual == null:
		_fails.append("bolt.tscn has no 'Visual' child (the golem arm-cannon override looks it up)")
		bolt.free()
		return
	if not (visual is BoltVisual):
		_fails.append("'Visual' is %s, expected BoltVisual" % visual.get_class())
		bolt.free()
		return

	# An isolated map -> caster -> bolt -> Visual chain, off to one side, so the wake found below
	# is unambiguously this bolt's and not one of the lanes'.
	var probe_map := Node2D.new()
	probe_map.visible = false
	_sv.add_child(probe_map)
	var caster := Node2D.new()
	probe_map.add_child(caster)

	var tint: Color = Color(0.2, 0.9, 0.4)   # a colour no default could produce by accident
	(bolt as CanvasItem).modulate = tint
	caster.add_child(bolt)

	var trail: CPUParticles2D = null
	for child: Node in probe_map.get_children():
		if child is CPUParticles2D:
			trail = child as CPUParticles2D
	if trail == null:
		_fails.append("wake was not handed to the map — it would pop when the bolt frees")
	else:
		if trail.local_coords:
			_fails.append("wake is in local coords — it would ride the bolt instead of trailing it")
		if not trail.modulate.is_equal_approx(tint):
			_fails.append("wake tint %s does not match the bolt's %s" % [trail.modulate, tint])

	# Kill the bolt: the wake must outlive it, stopped rather than deleted.
	bolt.queue_free()
	await process_frame
	await process_frame
	if trail != null:
		if not is_instance_valid(trail) or not trail.is_inside_tree():
			_fails.append("wake died with the bolt instead of burning down")
		elif trail.emitting:
			_fails.append("wake kept emitting after the bolt died")
	probe_map.queue_free()


## One lane: fires the real scene on a loop, using its ability's real speed and tint.
class Lane extends Node2D:
	var ability: BoltShootAbility
	var kill_midway: bool = false
	var base_y: float = 0.0
	var x0: float = 0.0
	var x1: float = 600.0
	var gap: float = 0.45

	var _bolt: Node2D
	var _wait: float = 0.0

	func _ready() -> void:
		_fire()

	func _process(delta: float) -> void:
		if _bolt != null and is_instance_valid(_bolt):
			# The Projectile moves itself in _physics_process; we only watch for the end of the run.
			if kill_midway and _bolt.global_position.x >= (x0 + x1) * 0.5:
				_bolt.queue_free()   # stands in for an impact
			elif _bolt.global_position.x >= x1:
				_bolt.queue_free()
			return
		_wait -= delta
		if _wait <= 0.0:
			_fire()

	func _fire() -> void:
		if ability == null or ability.projectile_scene == null:
			return
		var bolt: Projectile = ability.projectile_scene.instantiate() as Projectile
		bolt.top_level = true
		bolt.direction = Vector2.RIGHT
		bolt.speed = ability.speed
		bolt.lifetime = 60.0            # the lane, not a timer, ends the run
		bolt.modulate = ability.bolt_modulate
		add_child(bolt)
		bolt.global_position = Vector2(x0, base_y)
		_bolt = bolt
		_wait = gap
