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
## Run as a SCENE, not with -s. The encounter's classes reach HostileNpc and
## Character, which reference the Client / ClientState autoloads — under -s those
## do not exist and the whole dependency graph fails to compile before a single
## check runs. Every object built here is still exercised through pure methods
## only: nothing touches WorldServer or a live Map.

const INDEX := "res://source/common/registry/indexes/enemy_types_index.tres"
const BOSS_SLUG := &"ossuran"
const BOSS_PATH := "res://source/common/gameplay/characters/npc/types/bosses/cleetus.tres"
const ARENA_SCENE := "res://source/common/gameplay/maps/maps/ossuran/ossuran_arena.tscn"

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
	"res://source/common/gameplay/ossuran/shaders/forge_to_ice.gdshader",
]

## Visual hooks the pillar brain replicates onto its body. Each one must exist on
## HostileNpc or the pillar telegraphs nothing while still hitting for full.
const PILLAR_RP_HOOKS: Array[String] = [
	"rp_elem_telegraph", "rp_slam_impact", "rp_laser_beam",
]

## The two phase gates, as authored on the boss and as enforced by the machine.
const EXPECTED_THRESHOLDS: Array[float] = [0.75, 0.5]

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
	var freeze: Shader = load(SHADERS[2]) as Shader
	if freeze != null:
		var names: Array = []
		for u: Dictionary in freeze.get_shader_uniform_list():
			names.append(str(u.get("name", "")))
		if not names.has("freeze"):
			_fail("forge_to_ice.gdshader has no 'freeze' uniform")

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
		[arena.ice_layer, "ice_layer"],
		[arena.frost_overlay, "frost_overlay"],
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
	var ground: TileMapLayer = root.get_node_or_null(^"Tiles/Ground")
	var ice: TileMapLayer = root.get_node_or_null(^"Tiles/Ice")
	var frost: CanvasItem = root.get_node_or_null(^"FrostOverlay")
	if ground != null and ice != null and frost != null:
		if not (ground.z_index < ice.z_index and ice.z_index < frost.z_index and frost.z_index < 0):
			_fail("depth order is wrong: ground %d, ice %d, frost %d (all must be < 0 and ascending)" % [
				ground.z_index, ice.z_index, frost.z_index
			])
		if ice.visible or frost.visible:
			_fail("the phase-3 layers start visible — the forge would open frozen")
		# The ice layer must carry NO physics, or fading it in changes what is
		# walkable mid-fight and strands anything pathing across it.
		if ice.tile_set != null and ice.tile_set.get_physics_layers_count() > 0:
			_fail("the ice tileset has a physics layer — the freeze would alter collision")
	else:
		_fail("arena scene is missing Ground / Ice / FrostOverlay")

	if not map.y_sort_enabled:
		_fail("map root is not y-sorted — sprites would draw through each other")

	print("scene : refs resolved, %d pillars, %d fires, %d wave spawns, depth ok" % [
		arena.pillar_markers.size(),
		arena.fire_sources.size(),
		arena.wave_manager.spawn_markers.size() if arena.wave_manager != null else 0,
	])
	root.queue_free()


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


func _finish() -> void:
	if _fails.is_empty():
		print("VERIFY_PASS")
		get_tree().quit(0)
		return
	printerr("VERIFY_FAIL (%d)" % _fails.size())
	get_tree().quit(1)
