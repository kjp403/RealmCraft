extends Area2D
## A bag stack discarded onto the map. Server-authoritative: walk over it to pick
## it back up. Spawned via ReplicatedPropsContainer.SCENE_GROUND_ITEM with
## item_id / amount / position in the spawn init.


## Seconds before an unclaimed drop despawns (anti-litter).
const LIFETIME_S: float = 300.0

@export var item_id: int = 0
@export var amount: int = 1

var collected: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var amount_label: Label = $AmountLabel


func _ready() -> void:
	_refresh_visual()
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
		var timer: Timer = Timer.new()
		timer.wait_time = LIFETIME_S
		timer.one_shot = true
		timer.timeout.connect(_expire)
		add_child(timer)
		timer.start()


func _refresh_visual() -> void:
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.item_icon != null and sprite != null:
		sprite.texture = item.item_icon
	if amount_label != null:
		amount_label.visible = amount > 1
		amount_label.text = str(amount)


func _on_body_entered(body: Node2D) -> void:
	if collected or not body is Player:
		return
	var player: Player = body as Player
	if player.player_resource == null or item_id <= 0 or amount <= 0:
		return

	collected = true
	Inventory.add_item(player.player_resource.inventory, item_id, amount)

	var peer: int = int(player.player_resource.current_peer_id)
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	var display_name: String = String(item.item_name) if item != null else "item"
	if peer > 0 and WorldServer.curr != null:
		WorldServer.curr.data_push.rpc_id(peer, &"item.picked_up", {
			"id": item_id,
			"amount": amount,
			"name": display_name,
		})

	_despawn()


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
