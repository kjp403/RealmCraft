class_name HealBolt
extends Projectile
## A bolt that heals the first WOUNDED ALLY it touches instead of damaging
## enemies. Fired by BOTH sides of the fence: a PLAYER's bolt considers players
## (ally = spar teammate while a match runs, else guildmate / groupmate — the
## same definition the team-colored health bars use), a MOB's bolt considers
## mobs (ally = same owner — see CombatHit.are_allied_npcs, THE faction seam).
## Characters on the other side it flies straight through; only walls stop it.
##
## Only overrides the per-hit RESPONSE — the Projectile base owns all detection,
## walls and piercing. Server-authoritative: only the server bolt applies the
## heal (+ broadcasts the green number); client bolts stop where the server's
## would so the flight reads naturally.

var heal_amount: float = 0.0


## CLIENT-side mirror of CombatHit.are_allied for a REMOTE player, reading the same
## peer-id sets the team health-bar tint uses (see Player._apply_team_bar_color).
## player_resource is server-only, so are_allied answers "not allied" for every
## remote player on a client — this is the only allegiance answer a client has.
static func client_is_ally(other: Player) -> bool:
	if other == null:
		return false
	var peer: int = other.name.to_int()
	if Character.spar_opponent_peers.has(peer):
		return false
	if Character.spar_ally_peers.has(peer):
		return true
	if Character.group_peers.has(peer):
		return true
	if Character.party_peers.has(peer):
		return true
	if other.active_guild_id <= 0:
		return false
	return other.active_guild_id == Character.local_viewer_guild_id


## A heal carries no damage, so an Arcane Wall has nothing to absorb — pass through
## it instead of dying on a shield the caster's own team put down.
func _absorbed_by_barrier() -> bool:
	return false


func _resolve_hit(node: Node2D) -> CombatHit.Result:
	var target: Node2D = node
	if node is HurtBox:
		target = (node as HurtBox).character
	if target == null or target is not Character:
		# Only SOLID WORLD geometry (walls, doors) stops a heal. Every other
		# non-character collider the mask can return used to fall into BLOCKED and
		# eat the bolt before it reached the ally it was aimed at: a TerritoryFlag
		# (FLAG layer) and a Deflect bubble (DeflectBubble sits on the HURTBOX
		# layer precisely so it reads as a tiny wall to damage shots) both did.
		# CombatHit.try_damage special-cases flags ahead of its own "not a
		# Character -> BLOCKED" rule for the same reason; the heal path never got
		# that treatment. Layer test, not a type list, so anything new landing on
		# an attackable layer passes a heal through by default.
		var collider: CollisionObject2D = node as CollisionObject2D
		if collider != null and (collider.collision_layer & PhysicsLayers.WORLD) != 0:
			return CombatHit.Result.BLOCKED
		return CombatHit.Result.IGNORED
	if source is HostileNpc:
		return _resolve_mob_heal(target)
	return _resolve_player_heal(target)


## Player-cast bolt (the original rules, unchanged): heal the first allied
## player crossed; pass non-allies; fly past NPCs.
func _resolve_player_heal(target: Node2D) -> CombatHit.Result:
	if target is not Player:
		return CombatHit.Result.IGNORED # non-player character — fly past
	# Client: visual only — stop on the first player; the ally check + heal are the server's call.
	if not multiplayer.is_server():
		return CombatHit.Result.DAMAGED
	if source is not Player:
		return CombatHit.Result.IGNORED
	var ally: Player = target as Player
	if not CombatHit.are_allied(source as Player, ally):
		return CombatHit.Result.IGNORED # fly past non-allies, keep looking for a friend
	ally.apply_heal(heal_amount, source as Character, true)
	return CombatHit.Result.DAMAGED # consumed


## Mob-cast bolt (refactor P3 — the sorcerer): heal the first WOUNDED allied
## mob crossed. Flies past enemies, players, corpses AND topped-off allies —
## a full-HP ally never consumes the heal, so the bolt keeps hunting for the
## wounded one it was aimed at. The wounded check runs on synced HP, so client
## bolts stop where the server's did.
func _resolve_mob_heal(target: Node2D) -> CombatHit.Result:
	if target is not HostileNpc:
		return CombatHit.Result.IGNORED # players / friendly NPCs — fly past
	var ally: HostileNpc = target as HostileNpc
	if ally == source or ally.is_dead \
			or not CombatHit.are_allied_npcs(source as HostileNpc, ally):
		return CombatHit.Result.IGNORED
	var sc: StatsComponent = ally.stats_component
	var hp: float = sc.get_stat(Stat.HEALTH)
	var hp_max: float = sc.get_stat(Stat.HEALTH_MAX)
	if hp >= hp_max:
		return CombatHit.Result.IGNORED # topped off — don't waste the bolt
	if not multiplayer.is_server():
		return CombatHit.Result.DAMAGED # visual stop; the heal is the server's call
	ally.apply_heal(heal_amount, source as Character, false)
	return CombatHit.Result.DAMAGED # consumed


## Green floating "+N" over the healed target, for everyone in the instance — same
## combat.hit path weapon damage and flag repairs use. Naming ServerInstance here is
## safe on client exports thanks to the stub-generating export plugin
## (addons/tinymmo/export_plugin/export_plugin.gd).
func _broadcast_heal(target: Character, healed: float) -> void:
	if WorldServer.curr == null:
		return
	var instance: Node = target.get_parent()
	while instance != null and instance is not ServerInstance:
		instance = instance.get_parent()
	if instance == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"combat.hit", {
			"amount": int(round(healed)),
			"position": target.global_position,
			"heal": true,
		}),
		instance.name
	)
