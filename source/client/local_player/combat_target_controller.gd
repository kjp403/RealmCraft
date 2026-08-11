class_name CombatTargetController
extends Node
## Right-click / Spacebar Attack: walk into range of a hostile and keep swinging
## the primary weapon until the target dies, you cancel (WASD / ground click), or
## you open a menu. Mirrors [HarvestController]'s click-to-act loop.
##
## Spacebar acquires a lock (remembered target after a move cancel, else nearest).
## Bows (and other [ChargeAbility] primaries) need an explicit release phase —
## press alone only draws. This controller auto-releases at full charge.


## Must sit inside the melee hit arc (~32 px from origin for sword swings).
## 72 left players stopping short and swinging into empty air.
const MELEE_ENGAGE_RANGE: float = 36.0
const RANGED_ENGAGE_RANGE: float = 220.0
## How far Spacebar will snag a hostile (or re-acquire the remembered target).
const SPACEBAR_ACQUIRE_RANGE: float = 320.0


var _player: LocalPlayer
var _target: HostileNpc
var _active: bool = false
## Survives WASD / ground-click cancel so the next Spacebar re-locks the same NPC.
var _last_target: HostileNpc
## True after we locally began a charge-shot draw for this Attack loop.
var _charge_held: bool = false


func setup(player: LocalPlayer) -> void:
	_player = player


func is_active() -> bool:
	return _active and _target != null and is_instance_valid(_target) and not _target_is_dead(_target)


func start(npc: HostileNpc) -> void:
	if _player == null or npc == null or not is_instance_valid(npc) or _target_is_dead(npc):
		return
	_clear_target_nameplate()
	_target = npc
	_last_target = npc
	_active = true
	_charge_held = false
	_player._follow_peer_id = 0
	Character.combat_target_instance_id = npc.get_instance_id()
	npc.refresh_nameplate_color()


func cancel() -> void:
	if _target != null and is_instance_valid(_target) and not _target_is_dead(_target):
		_last_target = _target
	_clear_target_nameplate()
	_active = false
	_target = null
	_charge_held = false


## Drop the lock once the target dies, and forget it as the remembered target.
## Called every frame from [method LocalPlayer.process_input] rather than from
## [method tick], which stops being called the moment [method is_active] goes
## false. Without it the kill left a live lock pointing at the corpse: hostiles
## respawn into the SAME node, so the player could stand still and be re-engaged
## with no input — and the next Spacebar would re-acquire the old NPC instead of
## whatever they'd since started fighting.
func release_if_target_dead() -> void:
	if _target != null and _target_is_dead(_target):
		cancel()
	if _last_target != null and _target_is_dead(_last_target):
		_last_target = null


## Spacebar: prefer the remembered fight target, else the nearest living hostile.
## Returns null when nothing is in [constant SPACEBAR_ACQUIRE_RANGE] (free-aim).
func acquire_for_spacebar() -> HostileNpc:
	if _player == null:
		return null
	if _is_valid_acquire_target(_last_target):
		return _last_target
	return find_nearest_hostile(_player.global_position, SPACEBAR_ACQUIRE_RANGE)


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
		Toaster.toast("Can't attack right now.")
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


func _is_valid_acquire_target(npc: HostileNpc) -> bool:
	if _target_is_dead(npc) or _player == null:
		return false
	return _player.global_position.distance_to(npc.global_position) <= SPACEBAR_ACQUIRE_RANGE


func _clear_target_nameplate() -> void:
	Character.combat_target_instance_id = 0
	if _target != null and is_instance_valid(_target):
		_target.refresh_nameplate_color()


func _engage_range() -> float:
	var weapon_item: WeaponItem = (
		_player.equipment_component.equipped_items.get(&"weapon", null) as WeaponItem
	)
	var base: float = MELEE_ENGAGE_RANGE
	if weapon_item != null:
		match weapon_item.category:
			&"bow", &"wand", &"book":
				base = RANGED_ENGAGE_RANGE
			_:
				base = MELEE_ENGAGE_RANGE
	# Oversized bosses: stop near the hurtbox edge, not the tiny origin.
	return base + _target_reach_bonus()


func _target_reach_bonus() -> float:
	if _target == null or _target.enemy_data == null:
		return 0.0
	var vs: float = maxf(1.0, _target.enemy_data.visual_scale)
	return maxf(0.0, (vs - 1.0) * 40.0)


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
	# Release echoes clear ChargeAbility.charging while our local _charge_held
	# may still be true — sync so the next draw can start cleanly.
	if _charge_held and charge != null and not charge.charging:
		_charge_held = false
		return

	if not _charge_held:
		if not _player.equipment_component.can_use(&"weapon", 0):
			return
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


## Nearest living HostileNpc under the current map's ReplicatedPropsContainer.
static func find_nearest_hostile(origin: Vector2, max_range: float) -> HostileNpc:
	if InstanceClient.current == null or InstanceClient.current.instance_map == null:
		return null
	var map: Map = InstanceClient.current.instance_map as Map
	if map == null or map.replicated_props_container == null:
		return null
	var container: ReplicatedPropsContainer = map.replicated_props_container
	var best: HostileNpc = null
	var best_dist: float = max_range
	for node: Node in container.get_children():
		var npc: HostileNpc = node as HostileNpc
		if npc == null or not is_instance_valid(npc):
			continue
		if npc.is_dead or npc.enemy_state == HostileNpc.EnemyState.DEAD \
				or npc.enemy_state == HostileNpc.EnemyState.REVIVING:
			continue
		if npc.stats_component != null and npc.stats_component.get_stat(Stat.HEALTH) <= 0.0:
			continue
		var dist: float = origin.distance_to(npc.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = npc
	for child_id: Variant in container.dynamic_nodes.keys():
		var dyn: Node = container.dynamic_nodes[child_id] as Node
		var npc2: HostileNpc = dyn as HostileNpc
		if npc2 == null or not is_instance_valid(npc2):
			continue
		if npc2.is_dead or npc2.enemy_state == HostileNpc.EnemyState.DEAD \
				or npc2.enemy_state == HostileNpc.EnemyState.REVIVING:
			continue
		if npc2.stats_component != null and npc2.stats_component.get_stat(Stat.HEALTH) <= 0.0:
			continue
		var dist2: float = origin.distance_to(npc2.global_position)
		if dist2 <= best_dist:
			best_dist = dist2
			best = npc2
	return best
