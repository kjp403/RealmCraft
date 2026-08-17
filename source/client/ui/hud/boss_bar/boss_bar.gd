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


func _ready() -> void:
	modulate.a = 0.0
	hide()
	set_process(true)
	Client.subscribe(&"boss.ward", _on_ward)


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


## The current combat target, if it is a living boss. Null for anything else.
func _resolve_target() -> HostileNpc:
	var id: int = Character.combat_target_instance_id
	if id == 0:
		return null
	var obj: Object = instance_from_id(id)
	var npc: HostileNpc = obj as HostileNpc
	if npc == null or not is_instance_valid(npc) or npc.is_dead:
		return null
	if npc.enemy_data == null or not npc.enemy_data.is_boss:
		return null
	return npc


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
	if _ward_label.is_empty():
		name_label.text = "%s   (Lv %d)" % [base, data.resolved_combat_level()]
	else:
		name_label.text = "%s   (Lv %d)  ·  %s" % [base, data.resolved_combat_level(), _ward_label]
