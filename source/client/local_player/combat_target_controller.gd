class_name CombatTargetController
extends Node
## Right-click Attack: walk into range of a hostile and keep swinging the
## primary weapon until the target dies, you cancel (WASD / ground click), or
## you open a menu. Mirrors [HarvestController]'s click-to-act loop.
##
## Bows (and other [ChargeAbility] primaries) need an explicit release phase —
## press alone only draws. This controller auto-releases at full charge.


const MELEE_ENGAGE_RANGE: float = 72.0
const RANGED_ENGAGE_RANGE: float = 220.0


var _player: LocalPlayer
var _target: HostileNpc
var _active: bool = false
## True after we locally began a charge-shot draw for this Attack loop.
var _charge_held: bool = false


func setup(player: LocalPlayer) -> void:
	_player = player


func is_active() -> bool:
	return _active and _target != null and is_instance_valid(_target) and not _target_is_dead(_target)


func start(npc: HostileNpc) -> void:
	if _player == null or npc == null or not is_instance_valid(npc) or _target_is_dead(npc):
		return
	_target = npc
	_active = true
	_charge_held = false
	_player._follow_peer_id = 0


func cancel() -> void:
	_active = false
	_target = null
	_charge_held = false


## Called from [method LocalPlayer.process_input]. Returns true when it handled
## look/attack this frame (caller should skip hold-to-attack).
func tick() -> bool:
	if not is_active():
		cancel()
		return false
	if _player._dead or ClientState.menu_open or _player._has_gui_focus():
		cancel()
		return false
	if not _player.is_armed():
		Toaster.toast("Equip a weapon to attack.")
		cancel()
		return false

	var to_target: Vector2 = _target.global_position - _player.global_position
	var dist: float = to_target.length()
	if to_target != Vector2.ZERO:
		_player.look_direction = to_target.normalized()

	if dist > _engage_range():
		_player._click_navigation.request_move(_target.global_position)
		return true

	_player._click_navigation.cancel()
	_perform_attack()
	return true


## Clients never receive [member Character.is_dead] for hostiles — death is
## replicated via enemy_state + HEALTH. Treat any of those as "stop attacking".
func _target_is_dead(npc: HostileNpc) -> bool:
	if npc == null or not is_instance_valid(npc):
		return true
	if npc.is_dead:
		return true
	if npc.enemy_state == HostileNpc.EnemyState.DEAD \
			or npc.enemy_state == HostileNpc.EnemyState.REVIVING:
		return true
	if npc.stats_component != null and npc.stats_component.get_stat(Stat.HEALTH) <= 0.0:
		return true
	return false


func _engage_range() -> float:
	var weapon_item: WeaponItem = (
		_player.equipment_component.equipped_items.get(&"weapon", null) as WeaponItem
	)
	if weapon_item == null:
		return MELEE_ENGAGE_RANGE
	match weapon_item.category:
		&"bow", &"wand", &"book":
			return RANGED_ENGAGE_RANGE
		_:
			return MELEE_ENGAGE_RANGE


func _primary_ability() -> AbilityResource:
	var weapon: Weapon = _player.equipment_component.mounted_nodes.get(&"weapon", null) as Weapon
	if weapon == null or weapon.abilities.is_empty():
		return null
	return weapon.abilities[0]


func _perform_attack() -> void:
	if InstanceClient.current == null:
		return
	var primary: AbilityResource = _primary_ability()
	if primary != null and primary.has_release:
		_tick_charge_attack(primary)
		return
	if _player.equipment_component.can_use(&"weapon", 0):
		Client.request_data(
			&"action.perform",
			Callable(),
			{"d": _player.look_direction, "i": 0},
			InstanceClient.current.name
		)


## Press to draw, auto-release at full charge, then loop. Mirrors the predictive
## press/release path in [method Weapon._handle_slot_input] so the local charge
## flag quiets can_use while we wait.
func _tick_charge_attack(ability: AbilityResource) -> void:
	var charge: ChargeAbility = ability as ChargeAbility
	# Release echoes (and interrupts) clear ChargeAbility.charging while our
	# local _charge_held may still be true — sync so we can start the next draw.
	if _charge_held and charge != null and not charge.charging:
		_charge_held = false
		return

	if not _charge_held:
		if not _player.equipment_component.can_use(&"weapon", 0):
			return
		# Predictive press — same as Weapon, so hold-to-attack stays quiet.
		ability.use_ability(_player, Vector2.ZERO)
		_charge_held = true
		Client.request_data(
			&"action.perform",
			Callable(),
			{"d": _player.look_direction, "i": 0},
			InstanceClient.current.name
		)
		return

	var ready: bool = false
	if charge != null:
		ready = charge.is_fully_charged()
	elif _player.equipment_component.can_use(&"weapon", 0, true):
		ready = true
	if not ready:
		return
	if not _player.equipment_component.can_use(&"weapon", 0, true):
		return
	ability.predict_release()
	_charge_held = false
	Client.request_data(
		&"action.perform",
		Callable(),
		{"d": _player.look_direction, "i": 0, "r": true},
		InstanceClient.current.name
	)
