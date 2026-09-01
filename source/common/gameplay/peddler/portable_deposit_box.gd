class_name PortableDepositBox
extends Node2D
## The Portable Deposit Box: a bank vault the player sets down in the field for
## [constant LIFETIME_S], then it is gone.
##
## VISIBLE TO EVERYONE, USABLE BY ONE. It is a replicated prop, so the whole zone
## sees the case thump down — that is most of what the good is FOR, and a box only
## its owner could see would be a menu button with extra steps. But the vault
## behind it is one character's, so [method try_open] refuses anyone else. The
## split is deliberate: the visual is shared state, the contents never are.
##
## [member owner_player_id] is the character id, NOT a peer id. A peer id is a
## session; the box has to keep belonging to the same person across a reconnect
## inside its two minutes.

## How long the box stands before it packs itself up.
const LIFETIME_S: float = 120.0
const OPEN_RANGE: float = 96.0
const CLICK_SIZE: Vector2 = Vector2(36, 34)

## Character id of the person who set it down. 0 = nobody (never usable).
## Rides the spawn init, so both ends agree on who owns it.
var owner_player_id: int = 0
## Name shown to a passer-by who clicks it. Also spawn init, for the same reason.
var owner_name: String = ""

## Client-only: true while the cursor is over the click area.
var _interactable_hovered: bool = false


func _ready() -> void:
	z_index = 1
	if multiplayer.is_server():
		var timer: Timer = Timer.new()
		timer.wait_time = LIFETIME_S
		timer.one_shot = true
		timer.timeout.connect(_despawn)
		add_child(timer)
		timer.start()
		return
	_spawn_click_area()


## Drawn rather than sprited, for the reason [PeddlerVaultChest] documents — and
## NOT gated on [code]multiplayer.is_server()[/code], which a render tool's
## OfflineMultiplayerPeer also satisfies. A headless server never calls _draw.
func _draw() -> void:
	# A strapped travel case: dark leather body, banded lid, brass catch.
	var body: Rect2 = Rect2(-14, -12, 28, 20)
	draw_rect(body, Color(0.24, 0.17, 0.12))
	draw_rect(body, Color(0.52, 0.38, 0.22), false, 2.0)
	draw_line(Vector2(-14, -5), Vector2(14, -5), Color(0.52, 0.38, 0.22), 2.0)
	# Two straps, so it reads as portable rather than as a chest.
	draw_line(Vector2(-7, -12), Vector2(-7, 8), Color(0.36, 0.26, 0.16), 2.0)
	draw_line(Vector2(7, -12), Vector2(7, 8), Color(0.36, 0.26, 0.16), 2.0)
	draw_rect(Rect2(-3, -7, 6, 5), Color(0.85, 0.72, 0.36))


func _spawn_click_area() -> void:
	var area: ClickableArea = ClickableArea.new()
	var collision: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = CLICK_SIZE
	collision.shape = rect
	area.add_child(collision)
	add_child(area)
	area.clicked.connect(_on_clicked)
	area.mouse_entered.connect(_set_interactable_hover.bind(true))
	area.mouse_exited.connect(_set_interactable_hover.bind(false))
	area.tree_exiting.connect(_set_interactable_hover.bind(false))


func _set_interactable_hover(on: bool) -> void:
	if not GameMode.is_client() or on == _interactable_hovered:
		return
	_interactable_hovered = on
	ClientState.world_interactables_hovered += 1 if on else -1


func _on_clicked() -> void:
	if not GameMode.is_client() or ClientState.local_player == null:
		return
	var prop_id: int = _prop_id()
	if prop_id < 0:
		return
	# Walk up first, then ask — the same path a ground pickup takes. The server
	# still range-checks; this is what makes an out-of-range click walk instead
	# of failing.
	ClientState.local_player.start_auto_pickup(self, prop_id, &"deposit_box.open")


func _prop_id() -> int:
	var container: ReplicatedPropsContainer = get_meta(&"rp_container", null) as ReplicatedPropsContainer
	if container == null:
		container = get_parent() as ReplicatedPropsContainer
	if container == null:
		return -1
	return container.child_id_of_node(self)


## Server: may [param player] open this box? Returns {} when they may, or a
## refusal dict. Separated from the payload build so the handler reads as
## gate-then-serve and the gate can be exercised on its own.
func refusal_for(player: Player) -> Dictionary:
	if player == null or player.player_resource == null or player.is_dead:
		return {"ok": false, "reason": "missing"}
	if owner_player_id <= 0:
		return {"ok": false, "reason": "not_owner"}
	if int(player.player_resource.player_id) != owner_player_id:
		# Named rather than generic: someone else's box on the ground is a thing
		# a player will click, and "that is not yours" is the honest answer.
		return {"ok": false, "reason": "not_owner", "owner": owner_name}
	if player.global_position.distance_to(global_position) > OPEN_RANGE:
		return {"ok": false, "reason": "too_far"}
	return {}


func _despawn() -> void:
	var container: ReplicatedPropsContainer = get_meta(&"rp_container", null) as ReplicatedPropsContainer
	if container == null:
		container = get_parent() as ReplicatedPropsContainer
	if container == null:
		queue_free()
		return
	var prop_id: int = container.child_id_of_node(self)
	if prop_id < 0:
		queue_free()
		return
	container.despawn_dynamic(prop_id)


## Server: set a box down for [param player], on the nearest square that will
## actually take one. Returns the live node, or null when the map cannot host a
## dynamic prop — the caller must treat null as a failure and not consume.
static func place_for(player: Player, instance: ServerInstance) -> PortableDepositBox:
	if player == null or player.player_resource == null or instance == null:
		return null
	if instance.instance_map == null:
		return null
	var container: ReplicatedPropsContainer = instance.instance_map.replicated_props_container
	if container == null:
		return null
	# Same standable + reachable probe the Peddler's cart is placed with, so a
	# box dropped against a wall slides to the nearest real floor instead of
	# ending up inside the geometry.
	var spot: Vector2 = PeddlerSites.nearest_standable(
		instance.instance_map, player.global_position
	)
	var node: Node = container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_DEPOSIT_BOX,
		container.to_local(spot),
		{
			"owner_player_id": int(player.player_resource.player_id),
			"owner_name": String(player.player_resource.display_name),
		}
	)
	return node as PortableDepositBox
