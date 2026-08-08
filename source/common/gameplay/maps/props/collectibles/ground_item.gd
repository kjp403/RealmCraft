extends Area2D
## A bag stack discarded onto the map. Click / tap to pick it up — does NOT
## auto-loot on walkover (that looped drop→pickup and bloated the loot feed).
## Spawned via ReplicatedPropsContainer.SCENE_GROUND_ITEM with item_id / amount /
## position in the spawn init.
##
## Client clicks use [ClickableArea] (same path as gather nodes / NPCs) so hover
## suppresses click-move and combat, then [PickupController] walks into range
## before requesting [code]item.pickup[/code].


## Seconds before an unclaimed drop despawns (anti-litter).
const LIFETIME_S: float = 300.0
## Max distance (world px) from the player to allow a click-pickup (server).
const PICKUP_RANGE: float = 96.0
## Client click target size — larger than the old 14px physics circle so drops
## are easy to hit.
const CLICK_SIZE: Vector2 = Vector2(36, 36)

@export var item_id: int = 0
@export var amount: int = 1

var collected: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var amount_label: Label = $AmountLabel

## Client-only: true while the cursor is over this drop's click area.
var _interactable_hovered: bool = false


func _ready() -> void:
	_refresh_visual()
	if multiplayer.is_server():
		# Server does not click — lifetime only. Pickup is authorized via item.pickup.
		monitoring = false
		monitorable = false
		input_pickable = false
		var timer: Timer = Timer.new()
		timer.wait_time = LIFETIME_S
		timer.one_shot = true
		timer.timeout.connect(_expire)
		add_child(timer)
		timer.start()
	else:
		# Click lives on a separate ClickableArea (not this Area2D) so we don't
		# fight physics layers the way gather nodes avoid.
		monitoring = false
		monitorable = false
		input_pickable = false
		_spawn_click_area()


func _refresh_visual() -> void:
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.item_icon != null and sprite != null:
		sprite.texture = item.item_icon
	if amount_label != null:
		amount_label.visible = amount > 1
		amount_label.text = str(amount)


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
	if not GameMode.is_client() or collected:
		return
	if ClientState.local_player == null:
		return
	var prop_id: int = _prop_id()
	if prop_id < 0:
		return
	ClientState.local_player.start_auto_pickup(self, prop_id)


func _prop_id() -> int:
	var container: ReplicatedPropsContainer = get_meta(&"rp_container", null) as ReplicatedPropsContainer
	if container == null:
		container = get_parent() as ReplicatedPropsContainer
	if container == null:
		return -1
	return container.child_id_of_node(self)


## Server: grant the stack to [param player] and despawn. Returns a payload for
## the data-request response (and optional client push).
func try_pickup(player: Player) -> Dictionary:
	if collected or player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	if item_id <= 0 or amount <= 0:
		return {"ok": false, "reason": "missing"}
	if player.global_position.distance_to(global_position) > PICKUP_RANGE:
		return {"ok": false, "reason": "too_far"}

	collected = true
	Inventory.add_item(player.player_resource.inventory, item_id, amount)

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	var display_name: String = String(item.item_name) if item != null else "item"
	var peer: int = int(player.player_resource.current_peer_id)
	if peer > 0 and WorldServer.curr != null:
		# inventory_changed only — do NOT ride LootFeed (drop→pickup loops looked
		# like massive "obtained" totals).
		WorldServer.curr.data_push.rpc_id(peer, &"item.picked_up", {
			"id": item_id,
			"amount": amount,
			"name": display_name,
			"quiet": true,
		})

	_despawn()
	return {"ok": true, "id": item_id, "amount": amount, "name": display_name}


func _expire() -> void:
	if collected:
		return
	collected = true
	_despawn()


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
