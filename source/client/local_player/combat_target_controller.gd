class_name CombatTargetController
extends Node
## Right-click Attack: walk into range of a hostile and keep swinging the
## primary weapon until the target dies, you cancel (WASD / ground click), or
## you open a menu. Mirrors [HarvestController]'s click-to-act loop.
##
## Death is detected via synced HEALTH (client never sees server [member Character.is_dead]).


## Melee basics only reach ~32px; stop closer than that so swings land.
const MELEE_ENGAGE_RANGE: float = 36.0
## Bows/wands: engage once a projectile can reasonably connect.
const RANGED_ENGAGE_RANGE: float = 200.0
## How often to rebuild the chase path while the target moves.
const REPATH_MS: int = 200


var _player: LocalPlayer
var _target: HostileNpc
var _active: bool = false
var _repath_at_ms: int = 0


func setup(player: LocalPlayer) -> void:
	_player = player


func is_active() -> bool:
	return _active and npc_is_alive(_target)


func start(npc: HostileNpc) -> void:
	if _player == null or not npc_is_alive(npc):
		return
	_target = npc
	_active = true
	_repath_at_ms = 0
	_player._follow_peer_id = 0


func cancel() -> void:
	_active = false
	_target = null
	_repath_at_ms = 0


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

	var engage: float = _engage_range()
	if dist > engage:
		var now: int = Time.get_ticks_msec()
		if now >= _repath_at_ms:
			_repath_at_ms = now + REPATH_MS
			# Path toward a stand point just inside engage range so we don't
			# require standing on the mob's origin (pathing often ends short).
			var approach: Vector2 = _target.global_position
			if dist > 1.0:
				approach = _target.global_position - to_target.normalized() * (engage * 0.55)
			_player._click_navigation.request_move(approach)
		return true

	_player._click_navigation.cancel()
	if _player.equipment_component.can_use(&"weapon", 0) and InstanceClient.current != null:
		Client.request_data(
			&"action.perform",
			Callable(),
			{"d": _player.look_direction, "i": 0},
			InstanceClient.current.name
		)
	return true


func _engage_range() -> float:
	if _player == null:
		return MELEE_ENGAGE_RANGE
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


## Clients don't sync [member Character.is_dead] — HEALTH <= 0 is the death signal.
static func npc_is_alive(npc: HostileNpc) -> bool:
	if npc == null or not is_instance_valid(npc):
		return false
	if npc.is_dead:
		return false
	if npc.stats_component == null:
		return false
	return npc.stats_component.get_stat(Stat.HEALTH) > 0.0
