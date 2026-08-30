extends Control
## Top-of-screen health bar for the boss the local player is fighting.
##
## A boss's over-head bar is the wrong instrument for a boss: it is 56px wide,
## it sits inside a sprite that can be wider than the player is tall, and it is
## the first thing to leave the screen when the camera pushes in. This is the
## same damage-chip treatment as the player's own bar (health_bar.gd) at
## encounter scale, with the name, the combat level and a phase tint.
##
## Entirely CLIENT-SIDE and read-only. It binds to the boss's replicated
## stats_component — the same stream that already drives the over-head bar — so
## it needs no new replication, no server hook and no BossController change.
##
## What it binds to is [member Character.combat_target_instance_id], the static
## the target controller already sets on Right-click → Attack and that aim assist
## and the nameplate colour both read. "The boss I am fighting" is therefore
## exactly "the boss I have targeted", with no new notion of aggro to keep in
## sync with the server's.

const FILL_TIME: float = 0.22
const CHIP_DELAY: float = 0.35
const CHIP_DRAIN: float = 0.5
const FADE_S: float = 0.25
## Kept up briefly after the target clears so swapping targets mid-fight (or a
## stray click) does not strobe the bar.
const LINGER_S: float = 1.2
## Telegraph tints, matching EnemyTypeResource.telegraph_element (0/1/2). The bar
## adopts the boss's enraged element once it crosses the enrage threshold, so the
## phase change is legible from the HUD and not only from the floor markers.
const ELEMENT_FILL: Array[Color] = [
	Color(0.85, 0.33, 0.16),  # fire
	Color(0.42, 0.72, 0.92),  # frost
	Color(0.63, 0.45, 0.95),  # storm
]

@onready var chip_bar: ProgressBar = $Panel/ChipBar
@onready var main_bar: ProgressBar = $Panel/MainBar
@onready var hp_label: Label = $Panel/MainBar/HpLabel
@onready var name_label: Label = $Panel/NameLabel
## Phase-gate notches (Ossuran's 75% / 50%). See boss_threshold_markers.gd.
@onready var thresholds: Control = $Panel/Thresholds
## Phase-3 freezing meter (Ossuran). Blank whenever the cold is not on you.
@onready var chill_label: Label = $Panel/ChillLabel

var _boss: HostileNpc = null
var _main_tween: Tween
var _chip_tween: Tween
var _fade_tween: Tween
var _linger_left: float = 0.0
var _enraged: bool = false
## The over-head bar we suppressed while showing this boss up here, so two bars
## do not compete. Restored on unbind — never left hidden on a body we let go of.
var _hid_overhead: bool = false
var _ward_label: String = ""
## A scripted encounter (Ossuran) is running in this instance. While true the bar
## STAYS UP whether or not the boss is the player's current target: a fight whose
## structure is drawn on the bar has to keep that bar visible through the stages
## where nobody is hitting the boss at all — the wave chamber, the pad charges,
## the pillar run — or the phase markers vanish exactly when they are the only
## explanation of what is happening.
var _encounter_active: bool = false
## The enemy_type the running encounter is about, from its own phase push. The
## targetless scan below is keyed to THIS slug and nothing else.
##
## Without it the scan takes the first body in `boss_bodies` that happens to be a
## boss — which, once a stale `_encounter_active` survived the fight, meant the
## bar latching onto whatever boss the player walked past next and dressing it in
## Ossuran's name plate and objective ("Vurthek, the Cinderborn · Ranged and
## Magic Only"). A scripted encounter knows which body it is about; say so.
var _encounter_slug: StringName = &""
## Current objective text from the server ("Melee Only"), shown beside the name.
var _phase_label: String = ""
## Throttle for the encounter-boss scan (see _resolve_target).
var _scan_at_ms: int = 0
## The local player is dead and has not stood back up. See [method _local_is_down].
var _down: bool = false


func _ready() -> void:
	modulate.a = 0.0
	hide()
	set_process(true)
	Client.subscribe(&"boss.ward", _on_ward)
	Client.subscribe(&"ossuran.phase", _on_phase)
	Client.subscribe(&"ossuran.chill", _on_chill)
	# Dying drops the bar. You are on a respawn timer, about to be somewhere else
	# entirely, and a boss health bar pinned over the death screen is the clearest
	# possible statement that the HUD has lost track of the fight. If the corpse
	# stands back up inside the same encounter, the next frame's scan re-binds it.
	Client.subscribe(&"player.died", _on_local_death)
	# Leaving the instance ends any encounter this client believed it was in —
	# the belt to the phase-0 push's braces. A client that misses the stand-down
	# (disconnect, party leave, a wipe that recycled the instance) would otherwise
	# carry `_encounter_active` for the rest of the session.
	if Client.instance_manager != null:
		Client.instance_manager.instance_changed.connect(_on_instance_changed)


## Everything the running encounter told us, forgotten. The bar goes back to
## being a plain "the boss I am fighting" readout.
func _clear_encounter() -> void:
	_encounter_active = false
	_encounter_slug = &""
	_phase_label = ""
	if chill_label != null:
		chill_label.text = ""


## Is [param npc] the body the running encounter is about?
func _is_encounter_boss(npc: HostileNpc) -> bool:
	return _encounter_active and _encounter_slug != &"" \
		and npc != null and is_instance_valid(npc) and npc.enemy_type == _encounter_slug


func _on_instance_changed(_instance: Object) -> void:
	_clear_encounter()
	_unbind()


func _on_local_death(_payload: Dictionary) -> void:
	_down = true
	_unbind()


## True while the local player is a corpse. Latched by the `player.died` push and
## released by their own replicated health coming back off zero — the push alone
## is not enough (unbinding on it just lets the very next frame re-resolve the
## still-targeted boss and put the bar straight back up), and health alone can
## lag the push by a tick.
func _local_is_down() -> bool:
	if not _down:
		return false
	var local: Character = ClientState.local_player if is_instance_valid(ClientState) else null
	if local != null and local.stats_component != null \
			and local.stats_component.get_stat(Stat.HEALTH) > 0.0 and not local.is_dead:
		_down = false
	return _down


func _process(delta: float) -> void:
	var target: HostileNpc = _resolve_target()
	if target != null and target != _boss:
		_bind(target)
		return
	if _boss == null:
		return
	if not is_instance_valid(_boss) or _boss.is_dead:
		_unbind()
		return
	if target == null:
		# Do not drop instantly — LINGER_S rides out a retarget.
		_linger_left -= delta
		if _linger_left <= 0.0:
			_unbind()
	else:
		_linger_left = LINGER_S


## The current combat target, if it is a living boss — falling back, during a
## scripted encounter, to the encounter's boss regardless of targeting.
func _resolve_target() -> HostileNpc:
	if _local_is_down():
		return null
	var id: int = Character.combat_target_instance_id
	if id != 0:
		var obj: Object = instance_from_id(id)
		var npc: HostileNpc = obj as HostileNpc
		if npc != null and is_instance_valid(npc) and not npc.is_dead \
				and npc.enemy_data != null and npc.enemy_data.is_boss:
			return npc
	if not _encounter_active:
		return null
	# Keep the already-bound body rather than re-scanning every frame — but only
	# if it is THIS encounter's boss. Pinning is a privilege the encounter grants
	# to its own body; extending it to whatever else the player happened to click
	# is what left an unrelated boss's bar welded to the top of the screen.
	if _is_encounter_boss(_boss) and not _boss.is_dead:
		return _boss
	return _scan_for_encounter_boss()


## Find the instance's boss body without a target. Only reached while a scripted
## encounter is active, and throttled — a tree walk is cheap but it is not free,
## and the body may legitimately be absent (the group is in the wave chamber and
## the boss has not spawned yet, or it just died).
func _scan_for_encounter_boss() -> HostileNpc:
	var now: int = Time.get_ticks_msec()
	if now < _scan_at_ms:
		return null
	_scan_at_ms = now + 500
	if _encounter_slug == &"":
		return null
	for node: Node in get_tree().get_nodes_in_group(&"boss_bodies"):
		var npc: HostileNpc = node as HostileNpc
		if npc != null and is_instance_valid(npc) and not npc.is_dead \
				and npc.enemy_type == _encounter_slug \
				and npc.enemy_data != null and npc.enemy_data.is_boss:
			return npc
	return null


func _bind(npc: HostileNpc) -> void:
	_unbind()
	_boss = npc
	_linger_left = LINGER_S
	_enraged = false
	_ward_label = ""

	var data: EnemyTypeResource = npc.enemy_data
	_refresh_name()
	_set_fill(ELEMENT_FILL[clampi(data.telegraph_element, 0, ELEMENT_FILL.size() - 1)])

	var stats: Object = npc.stats_component.stats
	if not stats.stat_changed.is_connected(_on_stat_changed):
		stats.stat_changed.connect(_on_stat_changed)
	# Snap to the current values rather than tweening up from zero — the fight is
	# already in progress by the time a player targets in.
	var hp_max: float = npc.stats_component.get_stat(Stat.HEALTH_MAX)
	var hp: float = npc.stats_component.get_stat(Stat.HEALTH)
	chip_bar.max_value = hp_max
	main_bar.max_value = hp_max
	chip_bar.value = hp
	main_bar.value = hp
	_update_label(hp)
	_check_phase(hp)
	# Phase gates are declared on the type, so any boss that wants notches gets
	# them by filling in hp_thresholds and touching no code here.
	if thresholds != null:
		thresholds.set_thresholds(data.hp_thresholds)
		thresholds.set_fill_fraction(hp / hp_max if hp_max > 0.0 else 1.0)

	# One bar per boss: mute the over-head one while this is up.
	if npc.progress_bar != null and npc.progress_bar.visible:
		npc.progress_bar.hide()
		_hid_overhead = true

	show()
	_fade_to(1.0)


func _unbind() -> void:
	if _boss != null and is_instance_valid(_boss):
		var stats: Object = _boss.stats_component.stats
		if stats.stat_changed.is_connected(_on_stat_changed):
			stats.stat_changed.disconnect(_on_stat_changed)
		if _hid_overhead and _boss.progress_bar != null:
			_boss.progress_bar.show()
	_hid_overhead = false
	_boss = null
	# The bar is going away — nothing on it should survive to the next boss.
	if chill_label != null:
		chill_label.text = ""
	_fade_to(0.0, true)


func _fade_to(alpha: float, hide_after: bool = false) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, ^"modulate:a", alpha, FADE_S)
	if hide_after:
		_fade_tween.tween_callback(hide)


func _on_stat_changed(stat_name: StringName, value: float) -> void:
	if stat_name == Stat.HEALTH_MAX:
		chip_bar.max_value = value
		main_bar.max_value = value
		_update_label(main_bar.value)
		return
	if stat_name != Stat.HEALTH:
		return

	var old: float = main_bar.value
	if _main_tween != null and _main_tween.is_valid():
		_main_tween.kill()
	_main_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_main_tween.tween_property(main_bar, ^"value", value, FILL_TIME)

	if _chip_tween != null and _chip_tween.is_valid():
		_chip_tween.kill()
	if value < old:
		# Damage — hold the red chunk a beat, then drain it to the new value.
		_chip_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_chip_tween.tween_interval(CHIP_DELAY)
		_chip_tween.tween_property(chip_bar, ^"value", value, CHIP_DRAIN)
	else:
		_chip_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_chip_tween.tween_property(chip_bar, ^"value", value, FILL_TIME)

	_update_label(value)
	_check_phase(value)
	if thresholds != null and main_bar.max_value > 0.0:
		thresholds.set_fill_fraction(value / main_bar.max_value)


## Recolour to the enraged element when the boss crosses its own threshold.
## Derived from replicated HP against the type's authored fraction, so phase two
## shows up here without BossController having to announce it.
func _check_phase(hp: float) -> void:
	if _boss == null or _enraged or main_bar.max_value <= 0.0:
		return
	var data: EnemyTypeResource = _boss.enemy_data
	if data == null or data.enraged_telegraph_element < 0:
		return
	if hp / main_bar.max_value > data.enrage_health_fraction:
		return
	_enraged = true
	_set_fill(ELEMENT_FILL[clampi(data.enraged_telegraph_element, 0, ELEMENT_FILL.size() - 1)])


func _set_fill(color: Color) -> void:
	var box: StyleBoxFlat = main_bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	if box == null:
		return
	var next: StyleBoxFlat = box.duplicate()
	next.bg_color = color
	main_bar.add_theme_stylebox_override(&"fill", next)


func _update_label(value: float) -> void:
	hp_label.text = "%d / %d" % [maxi(0, int(ceil(value))), int(main_bar.max_value)]


## Ossuran phase push: keeps the bar pinned up for the whole encounter and shows
## the current objective. A phase of 0 (or the DEFEATED push) stands it down.
func _on_phase(payload: Dictionary) -> void:
	var phase: int = int(payload.get("phase", 0))
	if phase <= 0:
		# The encounter is over (killed, wiped, reset). Everything it put on this
		# bar goes with it — the pin, the objective, the chill meter and the slug
		# the scan hunts by — or the next boss this client meets inherits them.
		_clear_encounter()
		_unbind()
		return
	_encounter_active = true
	_encounter_slug = StringName(str(payload.get("boss", "")))
	_phase_label = str(payload.get("label", ""))
	# The cold only exists in phase 3; leaving it must clear the meter, or the
	# last pushed value sits on the bar for the rest of the session.
	if phase != 3 and chill_label != null:
		chill_label.text = ""
	_refresh_name()


## Ossuran phase 3: the freezing meter. Pushed every half second per player by
## ColdDebuffController, so this needs no state of its own and a client that
## joined late or reconnected is correct within one tick.
##
## Three readings, because the mechanic has three states and only one of them is
## an emergency: warming (you are at a fire and shedding stacks), chilling (the
## clock is running, no damage yet), and freezing (it is hurting you now).
func _on_chill(payload: Dictionary) -> void:
	if chill_label == null:
		return
	var stacks: int = int(payload.get("stacks", 0))
	if stacks <= 0:
		chill_label.text = ""
		return
	var maximum: int = maxi(1, int(payload.get("max", 10)))
	var warm: bool = bool(payload.get("warm", false))
	var hurting: bool = bool(payload.get("hurting", false))

	var color: Color
	var lead: String
	if warm:
		color = Color(0.55, 0.85, 1.0)
		lead = "Warming"
	elif hurting:
		color = Color(1.0, 0.45, 0.45)
		lead = "FREEZING — get to a fire"
	else:
		color = Color(0.70, 0.90, 1.0)
		lead = "The cold is setting in"
	chill_label.add_theme_color_override(&"font_color", color)
	chill_label.text = "%s   %d/%d" % [lead, stacks, maximum]


func _on_ward(payload: Dictionary) -> void:
	var ward: String = str(payload.get("ward", "")).strip_edges()
	if ward.is_empty():
		return
	_ward_label = "Physical Ward" if ward == "physical" else "Arcane Ward"
	_refresh_name()


func _refresh_name() -> void:
	if _boss == null or not is_instance_valid(_boss) or _boss.enemy_data == null:
		return
	var data: EnemyTypeResource = _boss.enemy_data
	var base: String = data.display_name if not data.display_name.is_empty() else str(_boss.enemy_type)
	# The objective (a scripted encounter's current demand — "Melee Only") takes
	# the suffix when there is one: during Ossuran it is the single most
	# actionable thing on screen, and it is what stops a player wondering why
	# their damage stopped working.
	# The objective belongs to the ENCOUNTER's boss, never to whatever body the
	# bar happens to be bound to — a stray target during an Ossuran fight must
	# not wear "Ranged and Magic Only", and neither must the next boss after it.
	var objective: String = _phase_label if _is_encounter_boss(_boss) else ""
	var suffix: String = objective if not objective.is_empty() else _ward_label
	if suffix.is_empty():
		name_label.text = "%s   (Lv %d)" % [base, data.resolved_combat_level()]
	else:
		name_label.text = "%s   (Lv %d)  ·  %s" % [base, data.resolved_combat_level(), suffix]
