class_name ChargePad
extends Area2D
## A stand-on-it channel pad. Both of Ossuran's pads are this one script:
## [constant Variant.EMBER] (the red kindling pad that opens the summoning) and
## [constant Variant.STORM] (the blue ward that shields and then buffs).
##
## The pad is a STATIC node in the map scene, which means it exists on the server
## and on every client already — so it needs no spawn replication, only its
## progress. The server computes, pushes `ossuran.pad`, and the client half of
## this same script drives the shader and the fill bar from that number. One
## script, two roles, gated on [method GameMode.is_world_server].
##
## Occupancy uses the HurtBox convention every other area in the codebase uses
## (see [HazardZone]): mask [constant CombatHit.TARGET_MASK], iterate overlapping
## AREAS, resolve each [HurtBox] to its character. Player navigation bodies are
## on a different layer and would not be seen by a body-based check.
##
## DEPTH: a pad is a floor decal. It is deliberately NOT y-sorted and sits at a
## negative z_index so a player standing in the middle of it always draws on top
## — y-sorting a full-width floor quad makes it flicker in front of and behind
## anyone crossing its pivot line.

enum Variant {
	## Red. Ink-in-water fluid, flame and kindled coal. Charging it opens the
	## portal to the summoning chamber.
	EMBER,
	## Blue. Conjured lightning. Shields everyone standing in it while it
	## charges, then grants the phase-2 damage and speed buff.
	STORM,
}

## Fired once when the pad reaches full charge.
signal charged()
## Fired whenever the normalised charge changes (server side), so the arena can
## drive callouts at milestones without polling.
signal progress_changed(value: float)

## Floor decal depth. Below characters (z 0) but above the tilemap.
const PAD_Z_INDEX: int = -2

## Seconds of single-occupant channelling to fill the pad.
@export var charge_seconds: float = 14.0
## Which pad this is.
@export var variant: Variant = Variant.EMBER
## Identifies the pad in the `ossuran.pad` push, so a client with both pads in
## the scene knows which one to update.
@export var pad_id: int = 1
## Charge lost per second while nobody is standing on it. Non-zero so the pad is
## a commitment: walking off to fight resets progress, which is what forces the
## group to defend the channeller instead of soloing it between packs.
@export var decay_per_second: float = 0.06
## Damage multiplier applied to players inside a charging STORM pad. 0.25 is the
## brief's "protecting players inside for 75% of incoming damage".
@export var ward_damage_mult: float = 0.25

## 0-1. Authoritative on the server, mirrored on clients from the push.
var progress: float = 0.0
## Set true once [signal charged] has fired, so it cannot fire twice and the pad
## stops charging.
var complete: bool = false
## Whether the pad is currently accepting a charge. The arena opens exactly one
## pad at a time; a closed pad is inert and invisible.
var active: bool = false

## Players we have applied the STORM ward to, so it is always removed from the
## same set it was added to — never by re-scanning occupancy, which would miss a
## player who died or left the instance while inside.
var _warded: Array[Player] = []
## Cached so the client half can push the number into the shader every frame it
## changes without a node lookup.
var _fill_material: ShaderMaterial = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatHit.TARGET_MASK
	z_index = PAD_Z_INDEX
	y_sort_enabled = false
	monitoring = true
	var visual: Node = get_node_or_null(^"Fill")
	if visual is CanvasItem:
		_fill_material = (visual as CanvasItem).material as ShaderMaterial
	# The server owns charge; a client only renders what it is told.
	set_physics_process(GameMode.is_world_server())
	_apply_visual()
	if not GameMode.is_world_server():
		Client.subscribe(&"ossuran.pad", _on_pad_push)


## Open the pad for charging. Resets progress so a re-run of the phase starts clean.
func open() -> void:
	active = true
	complete = false
	progress = 0.0
	_broadcast()
	_apply_visual()


## Close the pad and drop any ward it was granting. Called when the stage ends,
## the group wipes, or the encounter resets — every exit path, so the 75%
## reduction can never outlive the pad that granted it.
func close() -> void:
	active = false
	_clear_ward()
	_broadcast()
	_apply_visual()


func _physics_process(delta: float) -> void:
	if not active or complete:
		return

	var occupants: Array[Player] = _occupants()
	if variant == Variant.STORM:
		_sync_ward(occupants)

	if occupants.is_empty():
		# Decay, but never below zero.
		if progress > 0.0:
			progress = maxf(0.0, progress - decay_per_second * delta)
			_broadcast()
			progress_changed.emit(progress)
		return

	# More bodies charge it faster, with diminishing returns: a second player is
	# a real help, a fifth is a rounding error. Without the taper a full group
	# trivialises a 14-second channel into three.
	var rate: float = (1.0 + 0.45 * float(occupants.size() - 1)) / maxf(0.5, charge_seconds)
	progress = minf(1.0, progress + rate * delta)
	_broadcast()
	progress_changed.emit(progress)

	if progress >= 1.0:
		complete = true
		active = false
		_clear_ward()
		_apply_visual()
		charged.emit()


## Living players currently standing on the pad.
func _occupants() -> Array[Player]:
	var out: Array[Player] = []
	for area: Area2D in get_overlapping_areas():
		if area is not HurtBox:
			continue
		var who: Character = (area as HurtBox).character
		if who is Player and not who.is_dead:
			out.append(who as Player)
	return out


## Bring the warded set in line with who is actually standing here.
func _sync_ward(occupants: Array[Player]) -> void:
	for player: Player in occupants:
		if not _warded.has(player):
			player.damage_taken_mult = ward_damage_mult
			_warded.append(player)
	for i: int in range(_warded.size() - 1, -1, -1):
		var warded: Player = _warded[i]
		if not is_instance_valid(warded):
			_warded.remove_at(i)
			continue
		if not occupants.has(warded):
			warded.damage_taken_mult = 1.0
			_warded.remove_at(i)


func _clear_ward() -> void:
	for player: Player in _warded:
		if is_instance_valid(player):
			player.damage_taken_mult = 1.0
	_warded.clear()


## Push the pad's state to every client in the instance. Sent on change only —
## _physics_process already rate-limits this to the physics tick, and the
## payload is three fields, so this is cheaper than a per-pad synchronizer.
func _broadcast() -> void:
	if not GameMode.is_world_server() or WorldServer.curr == null:
		return
	var instance: Node = _instance()
	if instance == null:
		return
	for peer_id: int in instance.players_by_peer_id:
		WorldServer.curr.data_push.rpc_id(peer_id, &"ossuran.pad", {
			"id": pad_id,
			"progress": progress,
			"active": active,
			"variant": int(variant),
		})


## CLIENT: adopt the pushed progress for this pad.
func _on_pad_push(payload: Dictionary) -> void:
	if int(payload.get("id", -1)) != pad_id:
		return
	progress = float(payload.get("progress", 0.0))
	active = bool(payload.get("active", false))
	_apply_visual()


## Drive the shader and the pad's own fill bar from [member progress]. Runs on
## both sides: the server keeps its own visual honest for headless previews and
## for any observer tooling.
func _apply_visual() -> void:
	if _fill_material != null:
		_fill_material.set_shader_parameter(&"charge", progress)
		_fill_material.set_shader_parameter(&"active", 1.0 if active or complete else 0.0)
	var bar: Node = get_node_or_null(^"ChargeBar")
	if bar is ProgressBar:
		(bar as ProgressBar).value = progress * 100.0
		(bar as ProgressBar).visible = active and progress > 0.0
	var visual: Node = get_node_or_null(^"Fill")
	if visual is CanvasItem:
		(visual as CanvasItem).visible = active or complete


func _instance() -> Node:
	var map: Map = Map.of(self)
	var owner_node: Node = map.get_parent() if map != null else null
	return owner_node if _is_server_instance(owner_node) else null


## True when [param node] is a live ServerInstance — i.e. it actually carries the
## player roster the encounter iterates.
##
## Guard, not paranoia: a map is only parented to a ServerInstance on the world
## server. Mounted anywhere else (a preview renderer, a test harness, an editor
## scene) its parent is a SubViewport or a plain Node, and every `for peer_id in
## instance.players_by_peer_id` in this file throws on it. Returning null here
## makes all of them no-op instead, which is the correct behaviour off-server.
static func _is_server_instance(node: Node) -> bool:
	return node != null and node.get(&"players_by_peer_id") is Dictionary
