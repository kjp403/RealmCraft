class_name BossStateMachine
extends Node
## THE authority on where the Ossuran encounter is, and the only thing allowed to
## say so. Nine states across the brief's three phases, each one declaring — as
## data, in [constant STATES] — what it means for damage:
##
##   * `phase`      1/2/3, for the HUD and the boss bar tint.
##   * `style`      the combat style the phase demands (UNKNOWN = anything goes).
##   * `immune`     the boss cannot be hurt at all (pad charges, waves, pillars).
##   * `hp_floor`   the fraction this phase is allowed to push the boss down to.
##
## Keeping those four facts in a table rather than scattered across nine `match`
## arms is what makes the fight auditable: you can read the whole damage contract
## of the encounter in twenty lines, and a new state cannot forget to declare one.
##
## The machine OWNS the phase and the gate; it does not own the content. It never
## spawns a pad, a wave or a pillar — it emits [signal state_changed] and
## [OssuranArena] does the staging. That seam is what lets the fight be tested
## state-by-state without a map.
##
## Server-only. Every transition is authoritative here and reaches clients as
## replicated HP plus explicit `ossuran.phase` pushes.

## Emitted on every transition, including into DEFEATED.
signal state_changed(from: State, to: State)
## Emitted only when the 1/2/3 phase number actually changes.
signal phase_changed(phase: int)
## The boss reached this phase's HP floor (0.75, then 0.50). The arena uses it to
## fire the callout and open the next pad.
signal threshold_reached(fraction: float)
## The fight is over.
signal boss_defeated()

enum State {
	## Pre-pull. Ossuran stands armored and inert.
	DORMANT,
	## Phase 1 — the Ember Pad is charging. Boss immune.
	EMBER_PAD,
	## Phase 1 — the group is in the summoning chamber running five waves.
	GAUNTLET,
	## Phase 1 — back at the boss, MELEE ONLY, down to 75%.
	MELEE_TRIAL,
	## Phase 2 — the Storm Pad is charging. Boss immune.
	STORM_PAD,
	## Phase 2 — buffed, dodging, killing the three pillars. Boss immune.
	PILLARS,
	## Phase 2 — the boss is open to everything, down to 50%.
	OPEN_ASSAULT,
	## Phase 3 — frozen, the cold is on, RANGED AND MAGIC ONLY, down to 0.
	FROZEN_END,
	## Dead.
	DEFEATED,
}

## The damage contract for every state. See the class docs. `hp_floor` of -1.0
## means "this state does not end on health" (it ends on a pad, a wave clear or
## a pillar count instead).
const STATES: Dictionary = {
	State.DORMANT: {
		"phase": 1, "styles": [], "immune": true, "hp_floor": -1.0,
		"label": "Dormant",
	},
	State.EMBER_PAD: {
		"phase": 1, "styles": [], "immune": true, "hp_floor": -1.0,
		"label": "Kindle the Ember Pad",
	},
	State.GAUNTLET: {
		"phase": 1, "styles": [], "immune": true, "hp_floor": -1.0,
		"label": "Survive the Summoning",
	},
	State.MELEE_TRIAL: {
		"phase": 1, "styles": [DamageInfo.Style.MELEE], "immune": false, "hp_floor": 0.75,
		"label": "Melee Only",
	},
	State.STORM_PAD: {
		"phase": 2, "styles": [], "immune": true, "hp_floor": -1.0,
		"label": "Conjure the Storm Pad",
	},
	State.PILLARS: {
		"phase": 2, "styles": [], "immune": true, "hp_floor": -1.0,
		"label": "Break the Pillars",
	},
	State.OPEN_ASSAULT: {
		"phase": 2, "styles": [], "immune": false, "hp_floor": 0.50,
		"label": "All Styles",
	},
	## The frozen finale takes ranged AND magic — steel is refused.
	State.FROZEN_END: {
		"phase": 3, "styles": [DamageInfo.Style.MAGIC, DamageInfo.Style.RANGED],
		"immune": false, "hp_floor": 0.0,
		"label": "Ranged and Magic Only",
	},
	State.DEFEATED: {
		"phase": 3, "styles": [], "immune": true, "hp_floor": 0.0,
		"label": "Defeated",
	},
}

## The linear spine of the fight. Every state except DEFEATED has exactly one
## successor, so [method advance] is unambiguous and the arena never has to name
## a destination — it just says "this stage is done".
const NEXT_STATE: Dictionary = {
	State.DORMANT: State.EMBER_PAD,
	State.EMBER_PAD: State.GAUNTLET,
	State.GAUNTLET: State.MELEE_TRIAL,
	State.MELEE_TRIAL: State.STORM_PAD,
	State.STORM_PAD: State.PILLARS,
	State.PILLARS: State.OPEN_ASSAULT,
	State.OPEN_ASSAULT: State.FROZEN_END,
	State.FROZEN_END: State.DEFEATED,
}

## The body being driven. Set by the arena before the first transition.
var boss: HostileNpc = null
## The gate this machine reconfigures on every transition.
var parser: AttackParser = null

var state: State = State.DORMANT
## Starts at 0, not 1: the opening DORMANT -> EMBER_PAD transition is itself
## phase 1, and transition_to() only emits phase_changed when the number moves.
## Seeded at 1, that first emit was skipped and the arena never pushed
## `ossuran.phase` for phase 1 — so the HUD boss bar (which turns on from that
## push) stayed hidden for the whole first phase.
var _phase: int = 0
## Latches so each threshold callout fires exactly once per run.
var _fired_thresholds: Dictionary = {}


func _ready() -> void:
	set_physics_process(false)


## Current phase number (1/2/3).
func phase() -> int:
	return _phase


## Human-readable objective for the current state, for the HUD banner.
func label() -> String:
	return str(STATES[state].get("label", ""))


## Start the encounter. Moves DORMANT → EMBER_PAD.
func begin() -> void:
	if state != State.DORMANT:
		return
	_fired_thresholds.clear()
	transition_to(State.EMBER_PAD)
	set_physics_process(true)


## Move to this state's declared successor. Called by the arena when a stage
## completes (pad charged, waves cleared, pillars down).
func advance() -> void:
	if not NEXT_STATE.has(state):
		return
	transition_to(NEXT_STATE[state])


## THE transition. Applies the new state's damage contract to the parser, clamps
## the boss back up to the phase floor, and announces.
func transition_to(next: State) -> void:
	if next == state:
		return
	var previous: State = state
	state = next

	var spec: Dictionary = STATES[next]
	# The gate is reconfigured in ONE call, so a state can never half-apply
	# (immune without its style, or a style without clearing the last immunity).
	if parser != null:
		parser.set_gate(spec["styles"], bool(spec["immune"]))

	# Entering a gated stage: pull the boss back up to the floor it was allowed
	# to reach. Without this a burst group that overshoots 75% by a big hit
	# carries that damage into phase 2 and the 50% marker arrives early — the
	# thresholds have to mean what the bar says they mean.
	_clamp_to_floor(previous)

	state_changed.emit(previous, next)

	var next_phase: int = int(spec["phase"])
	if next_phase != _phase:
		_phase = next_phase
		phase_changed.emit(_phase)

	if next == State.DEFEATED:
		set_physics_process(false)
		boss_defeated.emit()


## Watch the health floor for the two states that end on damage.
func _physics_process(_delta: float) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var floor_fraction: float = float(STATES[state].get("hp_floor", -1.0))
	if floor_fraction < 0.0:
		return

	var fraction: float = health_fraction()
	if state == State.FROZEN_END:
		# The last stage ends on death, not on a floor — the body dying is what
		# advances it, handled by the arena's died hook.
		return
	if fraction > floor_fraction:
		return

	# Floor reached: latch the callout, then hand over to the next stage.
	if not _fired_thresholds.has(floor_fraction):
		_fired_thresholds[floor_fraction] = true
		threshold_reached.emit(floor_fraction)
	advance()


## Boss health as a 0-1 fraction. 0.0 when there is no body to read.
func health_fraction() -> float:
	if boss == null or not is_instance_valid(boss):
		return 0.0
	var hp_max: float = boss.stats_component.get_stat(Stat.HEALTH_MAX)
	if hp_max <= 0.0:
		return 0.0
	return clampf(boss.stats_component.get_stat(Stat.HEALTH) / hp_max, 0.0, 1.0)


## Restore the boss to the floor of the state we are LEAVING, so overkill in a
## gated stage cannot bank damage against the next one.
func _clamp_to_floor(previous: State) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var floor_fraction: float = float(STATES[previous].get("hp_floor", -1.0))
	if floor_fraction <= 0.0:
		return
	var hp_max: float = boss.stats_component.get_stat(Stat.HEALTH_MAX)
	var target: float = hp_max * floor_fraction
	if boss.stats_component.get_stat(Stat.HEALTH) < target:
		boss.stats_component.set_stat(Stat.HEALTH, target)


## Whether [param style] is accepted by the CURRENT state. The parser owns the
## live gate; this exists so the arena and the verifier can ask the same question
## without reaching into the table themselves.
func style_allows(style: DamageInfo.Style) -> bool:
	var wanted: Array = STATES[state]["styles"]
	return wanted.is_empty() or wanted.has(style)


## Mark the fight won. Called from the arena's `died` hook.
func defeat() -> void:
	transition_to(State.DEFEATED)


## Hard reset back to DORMANT (a wipe, or the instance recycling). Leaves the
## parser fully closed so a stray hit during teardown cannot register.
func reset() -> void:
	set_physics_process(false)
	state = State.DORMANT
	_phase = 1
	_fired_thresholds.clear()
	if parser != null:
		parser.set_gate([], true)
