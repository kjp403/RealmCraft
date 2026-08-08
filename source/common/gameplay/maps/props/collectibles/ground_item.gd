extends Area2D
## A bag stack discarded onto the map. Click / tap to pick it up — does NOT
## auto-loot on walkover (that looped drop→pickup and bloated the loot feed).
## Spawned via ReplicatedPropsContainer.SCENE_GROUND_ITEM with item_id / amount /
## position in the spawn init.


## Seconds before an unclaimed drop despawns (anti-litter).
const LIFETIME_S: float = 300.0
## Max distance (world px) from the player to allow a click-pickup.
const PICKUP_RANGE: float = 96.0

@export var item_id: int = 0
@export var amount: int = 1

var collected: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var amount_label: Label = $AmountLabel


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
		monitoring = false
		monitorable = false
		input_pickable = true
		input_event.connect(_on_input_event)


func _refresh_visual() -> void:
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.item_icon != null and sprite != null:
		sprite.texture = item.item_icon
	if amount_label != null:
		amount_label.visible = amount > 1
		amount_label.text = str(amount)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var clicked: bool = (
		(event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if not clicked or collected:
		return
	if InstanceClient.current == null:
		return
	var prop_id: int = _prop_id()
	if prop_id < 0:
		return
	# Fire-and-forget; server validates range + ownership of the prop.
	Client.request_data(
		&"item.pickup",
		Callable(),
		{"prop_id": prop_id},
		InstanceClient.current.name
	)


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
