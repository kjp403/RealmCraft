class_name TauntAbility
extends AbilityResource
## MIGHTY ROAR — the Heavy Weapons tank's aggro tool. Every hostile in
## [member radius] drops whatever it was chasing and commits to the caster for
## [member taunt_duration_s] (0 = until one of them dies).
##
## Why an ABILITY and not "whoever stands closest gets aggro": proximity aggro
## punishes exactly the players it is supposed to help. Melee DPS and a
## rooted-channel healer both have to stand near the boss to do their jobs, so a
## proximity rule hands them the boss for doing their role correctly, and gives the
## tank no way to take it back except out-standing them. A cast makes threat an
## action with a cooldown the whole group can see and plan around — the tank chose
## to hold it, and the DPS can read when it is about to lapse.
##
## The lock itself lives on [HostileNpc] ([method HostileNpc.apply_taunt]) because
## every path that could steal aggro back — the pack ally-call, retaliation on
## damage, the leash, target loss — is over there and each one has to defer to it.
## A taunt that only SET the target would be undone by the next sword swing from a
## DPS, which is the one thing it exists to prevent.


## Roar reach. Generous on purpose — a taunt you have to be in melee range of is
## a taunt you cannot use to peel a boss off a healer who is already in trouble.
@export var radius: float = 180.0
## Seconds the aggro lock holds. 0 = until the mob dies or the caster does (the
## capstone rank). See [constant HostileNpc.TAUNT_UNTIL_DEATH].
@export var taunt_duration_s: float = 8.0
## Cap on how many hostiles one roar can lock. Keeps a pull in a packed dungeon
## room from parking thirty bodies on one player at once.
@export var max_targets: int = 8
## Flat ARMOR granted to the caster for [member self_buff_duration_s] — you just
## volunteered to eat everything in the room, so the roar braces for it.
@export var armor_bonus: float = 0.0
@export var mr_bonus: float = 0.0
@export var self_buff_duration_s: float = 4.0
## Ring VFX flashed on the caster (sent by path in the push so clients load it).
@export var vfx: SpriteFrames
@export var vfx_color: Color = Color(1.0, 0.78, 0.42, 0.95)
## The VFX sheet's frame WIDTH in px — the scale math sizes the art to ~the roar
## diameter. 128 for the ring packs, 256 for the wide sheets.
@export var vfx_frame_px: float = 128.0


func use_ability(user: Entity, _direction: Vector2) -> void:
	if not GameMode.is_world_server() or user is not Player:
		return
	var caster: Player = user as Player
	if caster.is_dead:
		return
	var taunted: int = 0
	for npc: HostileNpc in _hostiles_in_range(caster):
		npc.apply_taunt(caster, taunt_duration_s)
		taunted += 1
		if taunted >= max_targets:
			break
	if armor_bonus > 0.0:
		BuffService.apply(caster, Stat.ARMOR, armor_bonus, self_buff_duration_s)
	if mr_bonus > 0.0:
		BuffService.apply(caster, Stat.MR, mr_bonus, self_buff_duration_s)
	_broadcast_ring(caster)


## Living hostiles within [member radius], NEAREST FIRST. The sort is what makes
## [member max_targets] behave: an arbitrary child order would let a distant straggler
## eat the budget while the boss the tank is standing on goes un-taunted.
## Walks both buckets hostiles live in — static children AND dynamic_nodes — the
## same pair [RapidFireAbility] does, because dungeon and boss-summoned mobs are
## only ever in the second one.
func _hostiles_in_range(caster: Player) -> Array[HostileNpc]:
	var out: Array[HostileNpc] = []
	var map: Node = caster.get_parent()
	if map is not Map:
		return out
	var container: ReplicatedPropsContainer = (map as Map).replicated_props_container
	if container == null:
		return out
	var candidates: Array = container.get_children()
	candidates.append_array(container.dynamic_nodes.values())
	for node: Variant in candidates:
		var npc: HostileNpc = node as HostileNpc
		if npc == null or not is_instance_valid(npc) or npc.is_dead:
			continue
		if caster.global_position.distance_to(npc.global_position) > radius:
			continue
		out.append(npc)
	out.sort_custom(
		func(a: HostileNpc, b: HostileNpc) -> bool:
			return (
				caster.global_position.distance_squared_to(a.global_position)
				< caster.global_position.distance_squared_to(b.global_position)
			)
	)
	return out


## Shows the roar ring on every client via the shared guard.cast push. aura:false
## because a roar is a MOMENT, not a stance — the lasting part of it is on the
## mobs, not on the caster.
func _broadcast_ring(caster: Player) -> void:
	if vfx == null or WorldServer.curr == null or caster.player_resource == null:
		return
	var map: Node = caster.get_parent()
	if map == null or map.get_parent() == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"guard.cast", {
			"p": int(caster.player_resource.current_peer_id),
			"fx": vfx.resource_path,
			"sc": (radius * 2.0) / maxf(1.0, vfx_frame_px),
			"mod": vfx_color,
			"aura": false,
		}),
		map.get_parent().name
	)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if taunt_duration_s <= 0.0:
		lines.append("holds until it dies")
	else:
		lines.append("%ss taunt" % fmt_num(taunt_duration_s))
	lines.append("up to %d enemies" % max_targets)
	if armor_bonus > 0.0:
		lines.append("+%s armor for %ss" % [fmt_num(armor_bonus), fmt_num(self_buff_duration_s)])
	lines.append("%dpx radius" % int(radius))
	return lines
