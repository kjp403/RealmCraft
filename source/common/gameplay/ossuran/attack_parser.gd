class_name AttackParser
extends Node
## THE single damage gate for the Ossuran encounter.
##
## Every hit that lands on the boss is routed through [method damage_factor],
## which returns the multiplier to apply. Three jobs, in this order:
##   1. INVULNERABILITY — during pad charges, the wave run and the pillar phase
##      Ossuran cannot be hurt at all. Returning 0.0 here (instead of letting the
##      state machine flip a flag on the body) keeps "can he be damaged right
##      now" in ONE place, so a phase can never leave the boss permanently immune.
##   2. STYLE GATE — the phase demands a combat style. A hit in the wrong style
##      is reduced to [member wrong_style_mult] (0.01 = the brief's "nearly no
##      damage"), NOT to zero: the player still sees a splat, so the mechanic
##      reads as "my weapon is useless here", not as "the boss is bugged".
##   3. TAUNT — the first wrong-style hit from a given player triggers Ossuran's
##      line through the existing `boss.callout` push. Throttled per player, so a
##      bow user auto-attacking at 2/s gets one taunt, not a wall of them.
##
## Deliberately a NODE and not a static helper: it holds per-player throttle
## state and it is addressed as a child of the arena, so the state machine can
## reconfigure it in one call on every phase change.
##
## Server-only. [method damage_factor] is reached from
## [method HostileNpc.incoming_damage_factor], which only runs where damage is
## resolved; on a client it is never called and this node just idles.

## Multiplier applied to a hit in the WRONG style. The brief's "nearly no
## damage" — a 900-damage magic crit lands for 9. Kept non-zero on purpose (see
## the class docs) and kept as a var so a phase can soften it if needed.
var wrong_style_mult: float = 0.01

## The styles this phase accepts. EMPTY = no gate (every style lands in full),
## which is the correct state for the opening phase and for the pad/wave phases
## where the boss is untouchable anyway.
##
## A SET rather than a single style because the fight genuinely needs two: the
## frozen finale accepts ranged AND magic, and modelling that as "one required
## style plus an exception" put a special case in every consumer.
var allowed_styles: Array = []

## While true, EVERY hit is fully negated regardless of style. Owned by the
## state machine and cleared on the phases where the boss is a valid target.
var invulnerable: bool = false

## Seconds between taunts aimed at the same player. Long enough that a full
## auto-attack chain produces one line, short enough that a player who wanders
## back to the wrong weapon a fight-phase later is told again.
const TAUNT_COOLDOWN_S: float = 8.0

## Ossuran's rejection lines, indexed by the style the phase WANTED. Written so
## each one names the counter without stating it outright — the player is told
## the weapon is wrong and pointed at the answer.
const TAUNT_LINES: Dictionary = {
	DamageInfo.Style.MELEE: [
		"Ossuran: \"Do you think your weak weapons can hurt me?\"",
		"Ossuran laughs. \"Arrows and cantrips. Come and TOUCH me.\"",
		"Ossuran: \"Put down the toys. Bring me steel.\"",
	],
	DamageInfo.Style.MAGIC: [
		"Ossuran: \"Your blade freezes to my hide, little one.\"",
		"Ossuran: \"Steel is brittle in this cold. Is that ALL you carry?\"",
		"Ossuran laughs. \"Swing again. The ice thanks you for the iron.\"",
	],
}

## Per-player taunt throttle, keyed by instance id → next allowed tick (ms).
## Instance id (not peer id) because the parser is reached from the damage path
## where the Character is what we have; entries for freed players are pruned on
## every reset, so a long fight cannot grow this without bound.
var _taunt_next_ms: Dictionary = {}
## Round-robin cursor into TAUNT_LINES so a repeat offender hears a different
## line rather than the same string three times.
var _line_cursor: int = 0

## The boss body, used for the callout's instance lookup. Set by the arena.
var boss: HostileNpc = null


## Configure the gate for a phase. One call per transition — the state machine
## never pokes the fields individually, so a phase can't half-apply.
##
## [param allowed] is the set of styles that land in full; pass an empty array
## for an ungated phase.
func set_gate(allowed: Array, immune: bool) -> void:
	allowed_styles = allowed.duplicate()
	invulnerable = immune
	_taunt_next_ms.clear()


## THE damage multiplier for one incoming hit. Returns 1.0 (lands in full),
## [member wrong_style_mult] (wrong weapon) or 0.0 (phase-immune).
##
## [param from] may be null and [param damage_type] may be any CombatHit type —
## environment ticks and NPC damage parse to UNKNOWN and are passed through
## untouched, so a pillar's own shot is never "the wrong style".
func damage_factor(
	from: Character,
	amount: float,
	damage_type: StringName = CombatHit.DAMAGE_PHYSICAL
) -> float:
	if invulnerable:
		return 0.0
	if allowed_styles.is_empty():
		return 1.0

	var info: DamageInfo = DamageInfo.parse(from, amount, damage_type)
	# Styleless damage (the cold, a hazard, an NPC) is not a player answering the
	# mechanic — it is never punished and never taunted.
	if info.is_styleless():
		return 1.0
	if allowed_styles.has(info.style):
		return 1.0

	_maybe_taunt(from)
	return wrong_style_mult


## Fire Ossuran's line at [param who], at most once per TAUNT_COOLDOWN_S.
func _maybe_taunt(who: Character) -> void:
	if who is not Player:
		return
	var key: int = who.get_instance_id()
	var now: int = Time.get_ticks_msec()
	if int(_taunt_next_ms.get(key, 0)) > now:
		return
	_taunt_next_ms[key] = now + int(TAUNT_COOLDOWN_S * 1000.0)

	# Taunt set is chosen by what the phase WANTS: a melee-gated phase mocks the
	# bow and the wand, a magic/ranged-gated phase mocks the blade.
	var taunt_key: DamageInfo.Style = (
		DamageInfo.Style.MELEE
		if allowed_styles.has(DamageInfo.Style.MELEE)
		else DamageInfo.Style.MAGIC
	)
	var lines: Array = TAUNT_LINES.get(taunt_key, [])
	if lines.is_empty():
		return
	var text: String = str(lines[_line_cursor % lines.size()])
	_line_cursor += 1
	_push_callout(who as Player, text)


## Send one line to ONE player. Deliberately not instance-wide: the taunt is a
## correction aimed at the person holding the wrong weapon, and broadcasting it
## every time an archer plinks the boss would bury the shared mechanic callouts
## the whole group needs to read.
func _push_callout(player: Player, text: String) -> void:
	if WorldServer.curr == null or player.player_resource == null:
		return
	var peer_id: int = int(player.player_resource.current_peer_id)
	if peer_id <= 0:
		return
	WorldServer.curr.data_push.rpc_id(peer_id, &"boss.callout", {"text": text})
