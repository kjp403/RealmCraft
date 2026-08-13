class_name HitFeedback
## Client-only impact juice for a landed hit: a brief freeze of the struck sprite
## (hitstop) and a camera kick. Driven off the [code]combat.hit[/code] push next to
## the floating damage number.
##
## STRICTLY VISUAL. Nothing here may touch movement, input, physics or
## [member Engine.time_scale] — the server already resolved this hit, and freezing
## local simulation to sell it would desync the player from the world they're
## dodging in (you'd sidestep a boss slam on screen and still eat it). Hitstop
## therefore pauses a sprite's ANIMATION and nothing else.


## Sprite freeze length. Deliberately tiny: boss telegraphs tick as fine as 0.07 s
## and the phase-2 add packs land hits constantly, so anything longer stops reading
## as impact and starts reading as stutter.
const HITSTOP_MS: int = 45
## Camera kick per hit taken, in [method LocalPlayer.shake_camera] trauma units.
## Small — this fires on EVERY incoming hit, not just dramatic ones.
const SHAKE_PER_HIT: float = 0.18
## Only a character within this of the hit position is treated as the one struck.
## The server sends the victim's own global_position, so the match is exact; the
## radius just guards against a stale position echo picking a bystander.
const MATCH_RADIUS: float = 12.0

## Set on a sprite while its hitstop is running, so overlapping hits can't stack
## freezes into a permanent stall — the pack in a boss's phase 2 would otherwise
## hold a victim's animation still indefinitely.
const BUSY_META: StringName = &"_hitstop_until_ms"


## Play the impact feedback for one [code]combat.hit[/code] payload. The camera kick
## fires only when the resolved victim IS the local player — deliberately decided by
## node identity rather than the payload's victim_peer, which is derived from the
## server-only player_resource and reads null on every client.
static func play(map: Node, position: Vector2, local_player: Node) -> void:
	var victim: Node2D = _victim_at(map, position)
	if victim == null:
		return
	if bool(ClientState.settings.get_value(&"combat", &"hitstop") != false):
		_hitstop(victim)
	if victim == local_player and local_player.has_method(&"shake_camera"):
		local_player.call(&"shake_camera", SHAKE_PER_HIT)


## Pause the struck character's sprite for [constant HITSTOP_MS], then resume it.
## Non-stacking: a sprite already frozen is left alone rather than re-frozen.
static func _hitstop(victim: Node2D) -> void:
	var sprite: AnimatedSprite2D = _sprite_of(victim)
	if sprite == null:
		return
	var now: int = Time.get_ticks_msec()
	if now < int(sprite.get_meta(BUSY_META, 0)):
		return
	sprite.set_meta(BUSY_META, now + HITSTOP_MS)
	var restore: float = sprite.speed_scale
	if restore <= 0.0:
		return # already paused by something else — don't fight it
	sprite.speed_scale = 0.0
	var timer: SceneTreeTimer = sprite.get_tree().create_timer(HITSTOP_MS / 1000.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(sprite):
			sprite.speed_scale = restore
	)


static func _sprite_of(victim: Node2D) -> AnimatedSprite2D:
	for child: Node in victim.get_children():
		if child is AnimatedSprite2D:
			return child as AnimatedSprite2D
	return null


## Nearest Character to the hit position. The payload carries a position rather than
## a node reference, so this resolves it back — cheap, and it works for players and
## NPCs alike without widening the network payload.
static func _victim_at(map: Node, position: Vector2) -> Node2D:
	if map == null:
		return null
	var best: Node2D = null
	var best_dist: float = MATCH_RADIUS
	for node: Node in map.get_children():
		best = _closest_in(node, position, best, best_dist)
		if best != null:
			best_dist = position.distance_to(best.global_position)
	return best


## Checks [param node] and, when it's a props container, its children — hostiles live
## one level deeper than players do.
static func _closest_in(node: Node, position: Vector2, best: Node2D, best_dist: float) -> Node2D:
	var found: Node2D = best
	var found_dist: float = best_dist
	var as_char: Character = node as Character
	if as_char != null:
		var d: float = position.distance_to(as_char.global_position)
		if d <= found_dist:
			found = as_char
			found_dist = d
	elif node is ReplicatedPropsContainer:
		for child: Node in node.get_children():
			var npc: Character = child as Character
			if npc == null:
				continue
			var nd: float = position.distance_to(npc.global_position)
			if nd <= found_dist:
				found = npc
				found_dist = nd
	return found
