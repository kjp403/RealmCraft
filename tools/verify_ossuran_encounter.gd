extends Node
## Headless gate for the Ossuran encounter.
##
##   godot --path . --mode=client res://tools/verify_ossuran_encounter.tscn
##   -> must print VERIFY_PASS
##
## What it is actually protecting against, in the order the checks run:
##
##  CONTENT  A wave or a pillar spawns BY SLUG through the content index. A .tres
##           that exists on disk but was never indexed spawns absolutely nothing,
##           silently, and the fight softlocks on an empty room — no error, no
##           log line. So every slug the code can ask for is resolved here.
##
##  GATES    The whole encounter is a damage contract (which style lands, when
##           the boss is immune, which health floor ends a stage). That contract
##           is walked state by state and asserted against the parser, because a
##           single wrong entry in the STATES table is a fight that either cannot
##           be damaged at all or skips two phases.
##
##  DRIFT    DamageInfo classifies by WEAPON CATEGORY, so a sixth category added
##           to PlayerResource and not to DamageInfo would parse as UNKNOWN and
##           silently ignore every style ward. That is asserted directly.
##
##  VISUALS  Shaders and rp_ hooks fail SILENTLY in a live fight: the server
##           still deals the damage while the client draws nothing.
##
##  RECOVERY The encounter's bodies must not heal themselves back to full when a
##           phase sends the group away from them. One dropped flag on a spawn
##           path erases a group's whole run, and nothing logs it.
##
##  PLACING  Killing Frost's safe circle is the only ground worth standing on
##           while it lands, so the picker is driven against the real arena
##           colliders from every cell the boss can stand on: a circle inside
##           the wall is an unanswerable 85% of everyone's health.
##
## Run as a SCENE, not with -s. The encounter's classes reach HostileNpc and
## Character, which reference the Client / ClientState autoloads — under -s those
## do not exist and the whole dependency graph fails to compile before a single
## check runs. Nothing here touches WorldServer: the checks are pure methods over
## loaded resources, plus the arena scene instanced into this tool's own tree for
## the floor and physics passes at the end.

const INDEX := "res://source/common/registry/indexes/enemy_types_index.tres"
const BOSS_SLUG := &"ossuran"
const BOSS_PATH := "res://source/common/gameplay/characters/npc/types/bosses/cleetus.tres"
const ARENA_SCENE := "res://source/common/gameplay/maps/maps/ossuran/ossuran_arena.tscn"
const ARENA_SCRIPT := "res://source/common/gameplay/ossuran/ossuran_arena.gd"
const NPC_SCRIPT := "res://source/common/gameplay/characters/npc/hostile_npc.gd"

## The support roster this encounter adds. The boss is NOT here: it already
## shipped, and this encounter spawns the existing body.
const SUPPORT_SLUGS: Array[StringName] = [
	&"ossuran_bonepicker", &"ossuran_emberling", &"ossuran_cinder_archer",
	&"ossuran_marrow_knight",
	&"ossuran_pillar_ember", &"ossuran_pillar_thorn", &"ossuran_pillar_hex",
]

const SHADERS: Array[String] = [
	"res://source/common/gameplay/ossuran/shaders/ember_pad.gdshader",
	"res://source/common/gameplay/ossuran/shaders/storm_pad.gdshader",
	"res://source/common/gameplay/ossuran/shaders/floor_freeze.gdshader",
	"res://source/common/gameplay/ossuran/shaders/pad_decal.gdshader",
]

## Visual hooks the pillar brain replicates onto its body. Each one must exist on
## HostileNpc or the pillar telegraphs nothing while still hitting for full.
const PILLAR_RP_HOOKS: Array[String] = [
	"rp_elem_telegraph", "rp_slam_impact", "rp_laser_beam",
]

## The two phase gates, as authored on the boss and as enforced by the machine.
const EXPECTED_THRESHOLDS: Array[float] = [0.75, 0.5]

## The arena room in tile cells (the chamber is checked implicitly — its wave
## platforms are flat and it has no solid props of its own).
const ARENA_RECT := Rect2i(0, 0, 48, 34)
## Matches build_ossuran_arena.gd.
const WALL_THICKNESS: int = 2
## The arena door — where a group walks in, and so the cell every floor check
## floods out from.
const ARENA_ENTRANCE := Vector2i(24, 30)
## Killing Frost casts sampled per boss position. The picker starts from a random
## angle, so more than one draw per cell is what stops a lucky direction reading
## as a pass.
const FROST_PICKS_PER_CELL: int = 3
## Every cell a body must be able to STAND on, with the name to report if it
## cannot. Derived from the placements in build_ossuran_scene.py.
const ARENA_FIXTURES: Array = [
	[Vector2i(9, 17), "the Ember Pad"],
	[Vector2i(39, 17), "the Storm Pad"],
	[Vector2i(24, 11), "the boss spawn"],
	[Vector2i(24, 26), "the arena return point"],
	[Vector2i(15, 8), "pillar pedestal 1"],
	[Vector2i(33, 8), "pillar pedestal 2"],
	[Vector2i(24, 28), "pillar pedestal 3"],
	[Vector2i(6, 6), "brazier 1"],
	[Vector2i(41, 6), "brazier 2"],
	[Vector2i(6, 27), "brazier 3"],
	[Vector2i(41, 27), "brazier 4"],
]

var _fails: Array[String] = []


func _fail(msg: String) -> void:
	_fails.append(msg)
	printerr("FAIL: ", msg)


func _ready() -> void:
	_check_boss()
	_check_support_roster()
	_check_wave_table()
	_check_style_drift()
	_check_damage_parse()
	_check_state_chain()
	_check_damage_contract()
	_check_visuals()
	_check_scene()
	_check_portals()
	_check_reachability()
	_check_no_regen()
	await _check_frost_placement()
	_finish()


# --- CONTENT -----------------------------------------------------------------


func _check_boss() -> void:
	var boss: EnemyTypeResource = load(BOSS_PATH) as EnemyTypeResource
	if boss == null:
		_fail("could not load the boss at %s" % BOSS_PATH)
		return
	if boss.enemy_type != BOSS_SLUG:
		_fail("boss enemy_type %s != %s" % [boss.enemy_type, BOSS_SLUG])
	if not boss.is_boss:
		_fail("boss is_boss is false — no BossController, so no kit and no enrage")

	# The notches on the bar and the machine's floors must be the same numbers,
	# or the bar promises a gate the fight does not have.
	if boss.hp_thresholds.size() != EXPECTED_THRESHOLDS.size():
		_fail("boss hp_thresholds %s != %s" % [boss.hp_thresholds, EXPECTED_THRESHOLDS])
	else:
		for i: int in EXPECTED_THRESHOLDS.size():
			if not is_equal_approx(boss.hp_thresholds[i], EXPECTED_THRESHOLDS[i]):
				_fail("boss hp_thresholds %s != %s" % [
					boss.hp_thresholds, EXPECTED_THRESHOLDS
				])
				break

	# The VISUAL enrage (skin swap, speed, telegraph tint) is driven by
	# BossController off this number; the MECHANICAL phase 3 (ice, cold, style
	# gate) is driven by the state machine's FROZEN_END floor. If they disagree
	# the boss turns to ice at a different moment than the room does.
	var frozen: Dictionary = BossStateMachine.STATES[BossStateMachine.State.OPEN_ASSAULT]
	if not is_equal_approx(boss.enrage_health_fraction, float(frozen["hp_floor"])):
		_fail("enrage_health_fraction %.2f != the OPEN_ASSAULT floor %.2f — the skin swap and the freeze would land at different health" % [
			boss.enrage_health_fraction, float(frozen["hp_floor"])
		])

	if boss.phase2_skin.is_empty():
		_fail("boss has no phase2_skin — nothing to swap to when he freezes")
	elif load(boss.phase2_skin) == null:
		_fail("boss phase2_skin does not load: %s" % boss.phase2_skin)
	print("boss : %s  lv%d  %.0f hp  enrage %.2f  gates %s" % [
		boss.display_name, boss.combat_level, boss.max_health,
		boss.enrage_health_fraction, str(boss.hp_thresholds),
	])


## Every support slug must resolve THROUGH THE INDEX, because that is how
## spawn_dynamic resolves it at runtime.
func _check_support_roster() -> void:
	var index: ContentIndex = load(INDEX) as ContentIndex
	if index == null:
		_fail("could not load the enemy index")
		return
	var by_slug: Dictionary = {}
	for entry: Dictionary in index.entries:
		by_slug[StringName(entry.get(&"slug", &""))] = entry

	for slug: StringName in SUPPORT_SLUGS:
		if not by_slug.has(slug):
			_fail("slug '%s' is not in the enemy index — it will spawn NOTHING" % slug)
			continue
		var path: String = str(by_slug[slug][&"path"])
		var type: EnemyTypeResource = load(path) as EnemyTypeResource
		if type == null:
			_fail("'%s' does not load as an EnemyTypeResource (%s)" % [slug, path])
			continue
		if type.enemy_type != slug:
			_fail("'%s' enemy_type is %s" % [slug, type.enemy_type])
		if type.skin == null:
			_fail("'%s' has no skin — it spawns invisible" % slug)
		if type.max_health <= 0.0:
			_fail("'%s' has a degenerate stat block" % slug)
		# The wave manager advances on tree_exited, which for a single-life mob
		# only fires after respawn_delay. A respawning wave mob never leaves.
		if type.respawns:
			_fail("'%s' respawns — the wave would never clear" % slug)
	print("roster: %d support types resolved" % SUPPORT_SLUGS.size())


## Every slug the wave table names must be one we just verified, and the shape of
## the gauntlet must match what the brief asks for.
func _check_wave_table() -> void:
	var waves: Array = MinionWaveManager.WAVES
	if waves.size() != 5:
		_fail("MinionWaveManager has %d waves, expected 5" % waves.size())
	var total: int = 0
	for i: int in waves.size():
		var wave: Array = waves[i]
		if wave.is_empty():
			_fail("wave %d is empty — it would clear instantly" % (i + 1))
		for entry: Array in wave:
			var slug: StringName = entry[0]
			var count: int = int(entry[1])
			if not SUPPORT_SLUGS.has(slug):
				_fail("wave %d spawns unverified slug '%s'" % [i + 1, slug])
			if count <= 0:
				_fail("wave %d asks for %d of '%s'" % [i + 1, count, slug])
			total += count
	print("waves: 5 waves, %d bodies total" % total)


# --- LOGIC -------------------------------------------------------------------


## THE drift guard. DamageInfo decides melee-vs-ranged by weapon CATEGORY (it has
## to: a bow's arrows travel as `physical`, exactly like a sword's swing). If a
## sixth category is ever added to PlayerResource and not here, every player
## holding it parses UNKNOWN and walks through every style ward in the game.
func _check_style_drift() -> void:
	var known: Array[StringName] = []
	known.append_array(DamageInfo.MELEE_CATEGORIES)
	known.append_array(DamageInfo.RANGED_CATEGORIES)
	known.append_array(DamageInfo.MAGIC_CATEGORIES)
	for category: StringName in PlayerResource.COMBAT_STYLE_CATEGORIES:
		var hits: int = 0
		for k: StringName in known:
			if k == category:
				hits += 1
		if hits == 0:
			_fail("weapon category '%s' is not classified by DamageInfo — it would ignore every style ward" % category)
		elif hits > 1:
			_fail("weapon category '%s' is claimed by more than one style list" % category)
	print("styles: all %d weapon categories classified" % PlayerResource.COMBAT_STYLE_CATEGORIES.size())


## The non-player branch of the parser (environment / NPC damage), which is the
## part reachable without a live PlayerResource.
func _check_damage_parse() -> void:
	var cases: Array = [
		[CombatHit.DAMAGE_PHYSICAL, DamageInfo.Style.MELEE],
		[CombatHit.DAMAGE_RANGED, DamageInfo.Style.RANGED],
		[CombatHit.DAMAGE_MAGIC, DamageInfo.Style.MAGIC],
	]
	for case: Array in cases:
		var info: DamageInfo = DamageInfo.parse(null, 10.0, case[0])
		if info.style != case[1]:
			_fail("DamageInfo.parse(%s) gave %s, expected %s" % [
				case[0], info.style_name(), DamageInfo.STYLE_NAMES[case[1]]
			])


## The linear spine must actually reach the end, and every state must declare a
## complete contract.
func _check_state_chain() -> void:
	var required: Array[String] = ["phase", "styles", "immune", "hp_floor", "label"]
	for state: int in BossStateMachine.State.values():
		if not BossStateMachine.STATES.has(state):
			_fail("state %d has no STATES entry" % state)
			continue
		for key: String in required:
			if not BossStateMachine.STATES[state].has(key):
				_fail("state %d is missing '%s'" % [state, key])

	# Walk DORMANT -> DEFEATED. A missing or looping link is a fight that can
	# never finish.
	var state: int = BossStateMachine.State.DORMANT
	var steps: int = 0
	var seen: Dictionary = {}
	while state != BossStateMachine.State.DEFEATED:
		if seen.has(state):
			_fail("NEXT_STATE loops at state %d" % state)
			return
		seen[state] = true
		if not BossStateMachine.NEXT_STATE.has(state):
			_fail("state %d has no successor — the fight would stall here" % state)
			return
		state = BossStateMachine.NEXT_STATE[state]
		steps += 1
		if steps > 32:
			_fail("NEXT_STATE did not terminate")
			return
	if steps != 8:
		_fail("the chain reaches DEFEATED in %d steps, expected 8" % steps)

	# Floors must only ever descend: 0.75 then 0.50 then 0.0.
	var last: float = 1.0
	for s: int in [
		BossStateMachine.State.MELEE_TRIAL,
		BossStateMachine.State.OPEN_ASSAULT,
		BossStateMachine.State.FROZEN_END,
	]:
		var floor_fraction: float = float(BossStateMachine.STATES[s]["hp_floor"])
		if floor_fraction > last:
			_fail("hp_floor %.2f on state %d rises above the previous %.2f" % [
				floor_fraction, s, last
			])
		last = floor_fraction
	print("states: chain reaches DEFEATED in %d steps" % steps)


## Walk every state and assert what the parser actually does with each style.
## This is the check that would have caught a phase gated on the wrong weapon.
func _check_damage_contract() -> void:
	var parser: AttackParser = AttackParser.new()
	var machine: BossStateMachine = BossStateMachine.new()
	machine.parser = parser

	var probes: Array = [
		[CombatHit.DAMAGE_PHYSICAL, DamageInfo.Style.MELEE, "melee"],
		[CombatHit.DAMAGE_RANGED, DamageInfo.Style.RANGED, "ranged"],
		[CombatHit.DAMAGE_MAGIC, DamageInfo.Style.MAGIC, "magic"],
	]

	for state: int in BossStateMachine.State.values():
		var spec: Dictionary = BossStateMachine.STATES[state]
		parser.set_gate(spec["styles"], bool(spec["immune"]))
		var allowed: Array = spec["styles"]

		for probe: Array in probes:
			var factor: float = parser.damage_factor(null, 100.0, probe[0])
			var expected: float
			if bool(spec["immune"]):
				expected = 0.0
			elif allowed.is_empty() or allowed.has(probe[1]):
				expected = 1.0
			else:
				expected = parser.wrong_style_mult
			if not is_equal_approx(factor, expected):
				_fail("state %s: %s damage factor %.3f, expected %.3f" % [
					str(spec["label"]), probe[2], factor, expected
				])

	# The two headline rules from the brief, asserted by name so a regression
	# says WHICH rule broke rather than which table row.
	var melee_spec: Dictionary = BossStateMachine.STATES[BossStateMachine.State.MELEE_TRIAL]
	parser.set_gate(melee_spec["styles"], false)
	if not is_equal_approx(parser.damage_factor(null, 100.0, CombatHit.DAMAGE_RANGED), 0.01):
		_fail("phase 1: ranged is not reduced to 0.01")
	if not is_equal_approx(parser.damage_factor(null, 100.0, CombatHit.DAMAGE_PHYSICAL), 1.0):
		_fail("phase 1: melee does not land in full")

	var frozen_spec: Dictionary = BossStateMachine.STATES[BossStateMachine.State.FROZEN_END]
	parser.set_gate(frozen_spec["styles"], false)
	if not is_equal_approx(parser.damage_factor(null, 100.0, CombatHit.DAMAGE_PHYSICAL), 0.01):
		_fail("phase 3: melee is not reduced")
	for wire: StringName in [CombatHit.DAMAGE_MAGIC, CombatHit.DAMAGE_RANGED]:
		if not is_equal_approx(parser.damage_factor(null, 100.0, wire), 1.0):
			_fail("phase 3: %s does not land in full" % wire)

	# An immune phase must refuse EVERYTHING, including styleless environment
	# damage — otherwise a lingering hazard chips the boss through a pad charge.
	parser.set_gate([], true)
	if not is_equal_approx(parser.damage_factor(null, 100.0, CombatHit.DAMAGE_MAGIC), 0.0):
		_fail("an immune phase still takes damage")

	machine.free()
	parser.free()
	print("gates: damage contract holds for all %d states" % BossStateMachine.State.values().size())


# --- VISUALS -----------------------------------------------------------------


func _check_visuals() -> void:
	for path: String in SHADERS:
		var shader: Shader = load(path) as Shader
		if shader == null:
			_fail("shader failed to load: %s" % path)
	# The pads drive these by name; a rename here is a pad that never fills.
	for uniform: String in ["charge", "active"]:
		for path: String in SHADERS.slice(0, 2):
			var shader: Shader = load(path) as Shader
			if shader == null:
				continue
			var names: Array = []
			for u: Dictionary in shader.get_shader_uniform_list():
				names.append(str(u.get("name", "")))
			if not names.has(uniform):
				_fail("%s has no '%s' uniform" % [path.get_file(), uniform])
	# The floor shader is driven by name from EnvironmentTransitionManager, and
	# its room mask must travel with it or the chamber freezes alongside the arena.
	var freeze: Shader = load(SHADERS[2]) as Shader
	if freeze != null:
		var names: Array = []
		for u: Dictionary in freeze.get_shader_uniform_list():
			names.append(str(u.get("name", "")))
		for needed: String in [
			String(EnvironmentTransitionManager.PROGRESS_UNIFORM), "arena_rect"
		]:
			if not names.has(needed):
				_fail("floor_freeze.gdshader has no '%s' uniform" % needed)

	# The EARTH element the green pillar telegraphs with must exist AND be
	# painted, or its wind-up draws in whatever colour index 0 happens to be.
	if ElementalTelegraph.Element.size() <= 3:
		_fail("ElementalTelegraph has no EARTH element for the Thorn pillar")
	elif not ElementalTelegraph.PALETTE.has(ElementalTelegraph.Element.EARTH):
		_fail("ElementalTelegraph.EARTH has no palette entry")

	# rp_ hooks fail silently: server damage lands, client draws nothing.
	var source: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/characters/npc/hostile_npc.gd"
	)
	for hook: String in PILLAR_RP_HOOKS:
		if not source.contains("func %s(" % hook):
			_fail("HostileNpc has no %s — the pillar would hit with no telegraph" % hook)
	print("visual: %d shaders, EARTH element, %d rp_ hooks" % [
		SHADERS.size(), PILLAR_RP_HOOKS.size()
	])


# --- SCENE -------------------------------------------------------------------


## Load the map and assert it wires itself up. OssuranArena fills its @exports
## from conventional child names in _ready, so this is the check that the SCENE
## and that convention still agree — a renamed node is otherwise a null that only
## surfaces as a stage which quietly does nothing, halfway through a live fight.
func _check_scene() -> void:
	var packed: PackedScene = load(ARENA_SCENE) as PackedScene
	if packed == null:
		_fail("could not load %s" % ARENA_SCENE)
		return
	var root: Node = packed.instantiate()
	if root == null:
		_fail("arena scene did not instantiate")
		return
	# _ready (and therefore the name-based resolution) only runs inside a tree.
	add_child(root)

	var map: Map = root as Map
	if map == null:
		_fail("arena root is not a Map")
	elif map.replicated_props_container == null:
		_fail("arena has no ReplicatedPropsContainer — nothing can spawn")

	var arena: OssuranArena = root.get_node_or_null(^"Encounter") as OssuranArena
	if arena == null:
		_fail("arena scene has no Encounter/OssuranArena node")
		root.queue_free()
		return

	for spec: Array in [
		[arena.boss_spawn, "boss_spawn"],
		[arena.arena_return, "arena_return"],
		[arena.chamber_spawn, "chamber_spawn"],
		[arena.ember_pad, "ember_pad"],
		[arena.storm_pad, "storm_pad"],
		[arena.wave_manager, "wave_manager"],
		[arena.environment, "environment"],
	]:
		if spec[0] == null:
			_fail("OssuranArena.%s did not resolve from the scene" % spec[1])

	if arena.pillar_markers.size() != 3:
		_fail("expected 3 pillar markers, resolved %d" % arena.pillar_markers.size())
	if arena.fire_sources.size() < 2:
		_fail("only %d fire sources — phase 3 needs somewhere to warm up" % arena.fire_sources.size())
	if arena.wave_manager != null and arena.wave_manager.spawn_markers.is_empty():
		_fail("wave manager resolved no spawn markers — waves would stack on one point")

	# The pads drive a ShaderMaterial by name; without it they charge invisibly.
	for pad: ChargePad in [arena.ember_pad, arena.storm_pad]:
		if pad == null:
			continue
		var fill: Node = pad.get_node_or_null(^"Fill")
		if fill == null or (fill as CanvasItem) == null:
			_fail("%s has no Fill CanvasItem" % pad.name)
		elif (fill as CanvasItem).material as ShaderMaterial == null:
			_fail("%s/Fill has no ShaderMaterial" % pad.name)
		if pad.get_node_or_null(^"CollisionShape2D") == null:
			_fail("%s has no CollisionShape2D — it can never detect a player" % pad.name)

	# Depth. A floor decal drawn ABOVE a character reads as the player standing
	# under the floor, and y-sorting a full-width quad makes it flicker.
	# The freeze is a material on the floor layers, not a layer stacked over them.
	# Both must carry it, or the props stay summer-warm on an iced floor.
	var ground: TileMapLayer = root.get_node_or_null(^"Tiles/Ground")
	var deco_layer: TileMapLayer = root.get_node_or_null(^"Tiles/Deco")
	for layer: TileMapLayer in [ground, deco_layer]:
		if layer == null:
			_fail("arena scene is missing a floor layer for the freeze material")
			continue
		var mat: ShaderMaterial = layer.material as ShaderMaterial
		if mat == null or mat.shader == null:
			_fail("%s has no freeze ShaderMaterial" % layer.name)
			continue
		# It must OPEN unfrozen. A scene saved mid-tween would hand every group a
		# forge that is already dead.
		var at_start: Variant = mat.get_shader_parameter(
			EnvironmentTransitionManager.PROGRESS_UNIFORM
		)
		if at_start != null and float(at_start) > 0.001:
			_fail("%s starts at transition_progress %.2f — the forge opens frozen" % [
				layer.name, float(at_start)
			])
	if ground != null and ground.z_index >= 0:
		_fail("the ground layer is not behind characters (z %d)" % ground.z_index)

	var env: EnvironmentTransitionManager = root.get_node_or_null(
		^"Environment"
	) as EnvironmentTransitionManager
	if env == null:
		_fail("arena scene has no Environment manager — the freeze would never replicate")
	elif env.floor_layers.is_empty():
		_fail("the Environment manager resolved no floor layers")

	if not map.y_sort_enabled:
		_fail("map root is not y-sorted — sprites would draw through each other")

	print("scene : refs resolved, %d pillars, %d fires, %d wave spawns, %d frost layers" % [
		arena.pillar_markers.size(),
		arena.fire_sources.size(),
		arena.wave_manager.spawn_markers.size() if arena.wave_manager != null else 0,
		env.floor_layers.size() if env != null else 0,
	])
	root.queue_free()

	# Each pad needs its ground scar, or it goes back to reading as a sticker.
	for pad: ChargePad in [arena.ember_pad, arena.storm_pad]:
		if pad == null:
			continue
		var scar: Node = pad.get_node_or_null(^"Decal")
		if scar == null or (scar as CanvasItem) == null:
			_fail("%s has no Decal — the pad would sit on the floor unblended" % pad.name)
			continue
		if (scar as CanvasItem).material as ShaderMaterial == null:
			_fail("%s/Decal has no ShaderMaterial" % pad.name)
		# The scar has to be WIDER than the pad; that overhang is the whole
		# transition from pad art to bare floor.
		var fill: Control = pad.get_node_or_null(^"Fill") as Control
		var scar_ctrl: Control = scar as Control
		if fill != null and scar_ctrl != null and scar_ctrl.size.x <= fill.size.x:
			_fail("%s/Decal (%.0fpx) is not wider than its Fill (%.0fpx)" % [
				pad.name, scar_ctrl.size.x, fill.size.x
			])

	if not map.y_sort_enabled:
		_fail("map root is not y-sorted — sprites would draw through each other")



## The door in and the door back out.
##
## A warper pair only works when the portal's `target_id` names a landing that
## actually exists in the destination map. Nothing validates that at load time:
## a typo is a portal that drops the player at the destination's DEFAULT spawn,
## or nowhere at all, and it is only ever found by walking into it. Both
## directions are checked here by reading the two scenes as text, because that is
## where the ids live.
func _check_portals() -> void:
	var forge: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn"
	)
	var arena: String = FileAccess.get_file_as_string(ARENA_SCENE)
	if forge.is_empty() or arena.is_empty():
		_fail("could not read one of the portal scenes as text")
		return

	# Forge -> arena: portal 157 targets landing 58, which the arena must have.
	if not forge.contains("warper_id = 157"):
		_fail("fire_forge has no OssuranPortal (warper_id 157)")
	if not forge.contains("target_id = 58"):
		_fail("the forge portal does not target the arena landing (58)")
	if not forge.contains("instance_collection/ossuran_arena.tres"):
		_fail("the forge portal does not point at the ossuran_arena instance")
	if not arena.contains("warper_id = 58"):
		_fail("the arena has no landing 58 for the forge portal to arrive on")

	# Arena -> forge: portal 158 targets landing 57, which the forge must have.
	if not arena.contains("warper_id = 158"):
		_fail("the arena has no ExitPortal (warper_id 158)")
	if not arena.contains("target_id = 57"):
		_fail("the arena exit does not target the forge landing (57)")
	if not forge.contains("warper_id = 57"):
		_fail("fire_forge has no OssuranLanding (57) for the exit to arrive on")

	# A death in the arena ejects to the forge, and must land on the same door.
	var instance: InstanceResource = load(
		"res://source/common/gameplay/maps/instance/instance_collection/ossuran_arena.tres"
	) as InstanceResource
	if instance == null:
		_fail("the ossuran_arena instance resource does not load")
	else:
		if instance.death_return_instance == null:
			_fail("arena instance has no death_return_instance — a death would strand the player")
		if instance.death_return_warper_id != 57:
			_fail("death return lands on warper %d, not the forge door (57)" % instance.death_return_warper_id)
	print("doors : forge 157->58, arena 158->57, death return 57")



# --- REACHABILITY -------------------------------------------------------------


## Flood-fill the arena floor and assert every fixture is still walkable.
##
## The decoration pass added REAL collision — stone columns whose bases stand two
## cells proud of the north wall, anvils and carts along the south, furnace idols
## in the corners. Any of those could wall a player off from a pad, and none of it
## would show up in a screenshot: a room can look perfect and still have a pad you
## cannot walk onto. So this walks the floor the way a player would and checks
## that every place the encounter needs a body to stand is connected to the door.
func _check_reachability() -> void:
	var packed: PackedScene = load(ARENA_SCENE) as PackedScene
	if packed == null:
		return
	var root: Node = packed.instantiate()
	add_child(root)

	var walls: TileMapLayer = root.get_node_or_null(^"Tiles/Walls")
	var deco: TileMapLayer = root.get_node_or_null(^"Tiles/Deco")
	if walls == null or deco == null:
		_fail("arena scene is missing Walls / Deco for the reachability check")
		root.queue_free()
		return

	var layers: Array[TileMapLayer] = [walls, deco]
	var blocked: Dictionary = _blocked_cells(layers)
	if blocked.has(ARENA_ENTRANCE):
		_fail("the arena entrance cell %s is blocked" % ARENA_ENTRANCE)
		root.queue_free()
		return
	# Flood from the arena door, UNCLAMPED. Clamping the fill to the room is what
	# hides the two failures that actually matter: a hole in the perimeter (the
	# fill would simply stop at the clamp and look fine) and a walk-in pocket
	# inside the wall band.
	var seen: Dictionary = _flood_from(ARENA_ENTRANCE, blocked)
	var escaped: bool = _fill_escaped(seen)

	if escaped:
		_fail("the arena perimeter leaks — a player can walk out of the room")

	# Nothing walkable may lie inside the wall band. The forge wall ring is two
	# cells thick and only ONE of those rows carries collision, so any prop
	# painted on the open row that is not itself solid opens a pocket a player
	# can stand in — inside the wall, outside the fight.
	var pockets: int = 0
	for cell: Vector2i in seen:
		if not ARENA_RECT.has_point(cell):
			continue
		var in_band: bool = (
			cell.x < ARENA_RECT.position.x + WALL_THICKNESS
			or cell.y < ARENA_RECT.position.y + WALL_THICKNESS
			or cell.x >= ARENA_RECT.end.x - WALL_THICKNESS
			or cell.y >= ARENA_RECT.end.y - WALL_THICKNESS
		)
		if in_band:
			pockets += 1
	if pockets > 0:
		_fail("%d walkable cells sit inside the arena wall band (walk-in pockets)" % pockets)

	for entry: Array in ARENA_FIXTURES:
		var cell: Vector2i = entry[0]
		if blocked.has(cell):
			_fail("%s sits inside a solid prop at %s" % [entry[1], cell])
		elif not seen.has(cell):
			_fail("%s at %s is walled off from the entrance" % [entry[1], cell])

	print("reach : %d floor cells, sealed=%s, %d wall pockets, all fixtures reachable" % [
		seen.size(), not escaped, pockets,
	])
	root.queue_free()


## Every body the encounter spawns must have the out-of-combat heal switched off.
## The stock rule reads ten quiet seconds as a disengage and refills the bar,
## which inside a staged fight is a phase working as designed — the frozen phase
## sends the group to a brazier while Ossuran, rooted mid-cast, does not follow —
## and it costs the group the entire run with no message and no combat log entry.
##
## Asserted against the SOURCE because the alternative is standing up a live
## instance: this is a one-line flag on a spawn path, and a refactor that drops
## it brings the bug back silently, which is exactly what this file is for.
func _check_no_regen() -> void:
	var src: String = FileAccess.get_file_as_string(ARENA_SCRIPT)
	if src.is_empty():
		_fail("could not read %s" % ARENA_SCRIPT)
		return
	var clears: int = src.count("regenerates_out_of_combat = false")
	if clears < 2:
		_fail("OssuranArena clears regenerates_out_of_combat %d times — the boss AND the pillars need it" % clears)
	var npc_src: String = FileAccess.get_file_as_string(NPC_SCRIPT)
	if not npc_src.contains("if not regenerates_out_of_combat:"):
		_fail("HostileNpc._can_out_of_combat_regen no longer honours the opt-out flag")
	print("regen : encounter bodies opt out of the out-of-combat heal (%d spawn paths)" % clears)


## KILLING FROST lands the only safe ground on the field, so a circle a player
## cannot stand in is not a hard mechanic, it is 85% of everyone's health with no
## answer. The old placement was `boss + random angle * offset`, which puts that
## circle inside the forge wall (or in the void behind it) every time Ossuran is
## pushed to an edge — and he is pushed to an edge constantly, by his own charge
## and by a melee group's positioning.
##
## This drives the SHIPPING picker (BossController.pick_frost_spot) against the
## REAL arena colliders, from every walkable cell that has a wall for a
## neighbour — the whole set of positions the bug needed — and asserts the circle
## always lands on floor the flood-fill above can reach from the door.
##
## Runs last because it is the only check that needs live physics: tile
## collision only exists once the scene is in the tree and a physics frame has
## been stepped.
func _check_frost_placement() -> void:
	var packed: PackedScene = load(ARENA_SCENE) as PackedScene
	if packed == null:
		return
	var root: Node = packed.instantiate()
	add_child(root)

	var walls: TileMapLayer = root.get_node_or_null(^"Tiles/Walls")
	var deco: TileMapLayer = root.get_node_or_null(^"Tiles/Deco")
	if walls == null or deco == null:
		_fail("arena scene is missing Walls / Deco for the frost placement check")
		root.queue_free()
		return

	var layers: Array[TileMapLayer] = [walls, deco]
	var blocked: Dictionary = _blocked_cells(layers)
	var floor_cells: Dictionary = _flood_from(ARENA_ENTRANCE, blocked)

	# Physics is not live until the tree has stepped. Without this the queries
	# below hit an empty space and every candidate looks open — the check would
	# pass on a build with no collision at all.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState2D = walls.get_world_2d().direct_space_state
	if space == null:
		_fail("no physics space — the frost placement check cannot run")
		root.queue_free()
		return

	# Control probe: the cells the tile data calls solid must READ as solid
	# through the physics mask the picker uses. If they do not — a tileset whose
	# physics layer moved off PhysicsLayers.WORLD, or collision that never
	# registered — every assertion below passes vacuously.
	var probe := PhysicsPointQueryParameters2D.new()
	probe.collision_mask = PhysicsLayers.SOLID_GROUND_MASK
	probe.collide_with_areas = false
	var solid_reads: int = 0
	for cell: Vector2i in blocked:
		probe.position = _cell_to_world(walls, cell)
		if not space.intersect_point(probe, 1).is_empty():
			solid_reads += 1
	print("probe : %d/%d blocked cells read solid" % [solid_reads, blocked.size()])
	if solid_reads * 2 < blocked.size():
		_fail("only %d of %d solid cells read solid through the physics mask" % [
			solid_reads, blocked.size()
		])
		root.queue_free()
		return

	var boss_res: EnemyTypeResource = load(BOSS_PATH) as EnemyTypeResource
	var brain := BossController.new()
	if boss_res != null:
		brain.frost_offset_px = boss_res.frost_offset_px

	# EVERY cell the boss can stand on, not just the ones with their back to a
	# wall: the whole floor costs about a second here, and "which positions are
	# safe to cast from" is exactly the judgement call that let this ship broken.
	var origins: Array[Vector2i] = _room_cells(floor_cells)
	if origins.size() < 500:
		_fail("only %d arena floor cells to cast frost from — the sweep is not covering the room" % origins.size())

	var pulled_in: int = 0
	var bad: int = 0
	for cell: Vector2i in origins:
		var origin: Vector2 = _cell_to_world(walls, cell)
		for _attempt: int in FROST_PICKS_PER_CELL:
			var at: Vector2 = brain.pick_frost_spot(space, origin, [])
			var landed: Vector2i = walls.local_to_map(walls.to_local(at))
			if not floor_cells.has(landed):
				bad += 1
				if bad <= 5:
					_fail("Killing Frost circle at %s (cell %s) is off the walkable floor, cast from %s" % [
						at, landed, cell
					])
			if not is_equal_approx(origin.distance_to(at), brain.frost_offset_px):
				pulled_in += 1

	brain.free()
	print("frost : %d floor origins x %d picks, %d circles pulled in, %d unreachable" % [
		origins.size(), FROST_PICKS_PER_CELL, pulled_in, bad,
	])
	root.queue_free()


## Cells carrying real collision on any of [param layers]. A tile only blocks if
## it actually has a collision polygon — banners, grates and floor slag share a
## layer with the columns and must not count as walls.
func _blocked_cells(layers: Array[TileMapLayer]) -> Dictionary:
	var blocked: Dictionary = {}
	for layer: TileMapLayer in layers:
		for cell: Vector2i in layer.get_used_cells():
			var data: TileData = layer.get_cell_tile_data(cell)
			if data != null and data.get_collision_polygons_count(0) > 0:
				blocked[cell] = true
	return blocked


## True when the fill reached well outside the room — the perimeter leaks, so a
## player can walk out of the fight.
func _fill_escaped(seen: Dictionary) -> bool:
	for cell: Vector2i in seen:
		if cell.x < -6 or cell.x > ARENA_RECT.size.x + 6 				or cell.y < -6 or cell.y > ARENA_RECT.size.y + 6:
			return true
	return false


## Four-way flood of open cells from [param start]. UNCLAMPED on purpose — see
## [method _check_reachability]; a fill that escapes the room is itself a finding.
func _flood_from(start: Vector2i, blocked: Dictionary) -> Dictionary:
	var seen: Dictionary = {start: true}
	if blocked.has(start):
		return seen
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		if at.x < -6 or at.x > ARENA_RECT.size.x + 6 				or at.y < -6 or at.y > ARENA_RECT.size.y + 6:
			continue
		for step: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
		]:
			var next: Vector2i = at + step
			if seen.has(next) or blocked.has(next):
				continue
			seen[next] = true
			queue.append(next)
	return seen


## The walkable cells that are actually in the arena room — the fill also covers
## the corridor and the chamber, which the boss never stands in.
func _room_cells(floor_cells: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in floor_cells:
		if ARENA_RECT.has_point(cell):
			out.append(cell)
	return out


## Centre of [param cell] in world space.
func _cell_to_world(layer: TileMapLayer, cell: Vector2i) -> Vector2:
	return layer.to_global(layer.map_to_local(cell))


func _finish() -> void:
	if _fails.is_empty():
		print("VERIFY_PASS")
		get_tree().quit(0)
		return
	printerr("VERIFY_FAIL (%d)" % _fails.size())
	get_tree().quit(1)
