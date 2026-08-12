class_name LootChest
extends Area2D
## Click-to-open loot chest. Spawned via [code]ReplicatedPropsContainer.SCENE_LOOT_CHEST[/code]
## with [member chest_slug] (and optional ownership) in the spawn init. Grants rolled
## gold + items to the opener's bag, then despawns.
##
## Client clicks use [ClickableArea] (same path as ground drops); walks into range
## via [PickupController] then requests [code]chest.open[/code].


const LIFETIME_S: float = 300.0
const OPEN_RANGE: float = 96.0
const EXCLUSIVE_S: float = 60.0
const CLICK_SIZE: Vector2 = Vector2(40, 40)
## Pixel-art chests are 16×16 — scale up to read clearly in-world.
const SPRITE_SCALE: float = 2.0

## Content slug under [code]combat/chests/[/code] (e.g. &"wood_silver_small").
## Applied before add_child on both sides so [_ready] sees the table.
var chest_slug: StringName = &"":
	set(value):
		chest_slug = value
		if value != &"":
			var data: ChestResource = ChestResource.load_by_slug(value)
			if data != null:
				chest = data

@export var chest: ChestResource
## Peer that earned this chest (0 = unowned / free for all).
@export var owner_peer_id: int = 0
## Server clock (msec) until which only [member owner_peer_id] may open.
@export var exclusive_until_ms: int = 0

var opened: bool = false

@onready var sprite: Sprite2D = $Sprite2D

## Client-only: true while the cursor is over this chest's click area.
var _interactable_hovered: bool = false


func _ready() -> void:
	_refresh_visual()
	if multiplayer.is_server():
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
		input_pickable = false
		_spawn_click_area()


func _refresh_visual() -> void:
	if sprite == null:
		return
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	if chest != null and chest.icon != null:
		sprite.texture = chest.icon


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
	if not GameMode.is_client() or opened:
		return
	if ClientState.local_player == null:
		return
	var prop_id: int = _prop_id()
	if prop_id < 0:
		return
	ClientState.local_player.start_auto_pickup(self, prop_id, &"chest.open")


func _prop_id() -> int:
	var container: ReplicatedPropsContainer = get_meta(&"rp_container", null) as ReplicatedPropsContainer
	if container == null:
		container = get_parent() as ReplicatedPropsContainer
	if container == null:
		return -1
	return container.child_id_of_node(self)


## Server: roll the chest table into pending loot staging and despawn.
func try_open(player: Player) -> Dictionary:
	if opened or player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	if chest == null and chest_slug != &"":
		chest = ChestResource.load_by_slug(chest_slug)
	if chest == null:
		return {"ok": false, "reason": "missing"}
	if player.global_position.distance_to(global_position) > OPEN_RANGE:
		return {"ok": false, "reason": "too_far"}
	var opener: int = int(player.player_resource.current_peer_id)
	if (
		owner_peer_id > 0
		and opener != owner_peer_id
		and Time.get_ticks_msec() < exclusive_until_ms
	):
		return {"ok": false, "reason": "reserved"}

	opened = true
	var payout: Dictionary = chest.roll_and_grant(player)
	var gold: int = int(payout.get("gold", 0))
	var items: Array = payout.get("items", []) as Array

	var peer: int = opener
	if peer > 0 and WorldServer.curr != null:
		if WorldServer.curr.database != null:
			WorldServer.curr.database.save_player(player.player_resource)
		WorldServer.curr.data_push.rpc_id(peer, &"chest.opened", {
			"chest": String(chest.display_name),
			"gold": gold,
			"items": items,
			"pending": payout.get("pending", []),
			"free_slots": int(payout.get("free_slots", 0)),
		})

	_despawn()
	return {
		"ok": true,
		"chest": String(chest.display_name),
		"gold": gold,
		"items": items,
		"pending": payout.get("pending", []),
		"free_slots": int(payout.get("free_slots", 0)),
	}


func _expire() -> void:
	if opened:
		return
	opened = true
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


## Server helper: spawn a chest near [param global_pos] reserved to [param owner_peer].
static func spawn_at(
	container: ReplicatedPropsContainer,
	slug: StringName,
	global_pos: Vector2,
	owner_peer: int = 0,
	exclusive_ms: int = -1
) -> LootChest:
	if container == null or slug == &"":
		return null
	if ChestResource.load_by_slug(slug) == null:
		push_error("LootChest.spawn_at: unknown chest slug '%s'" % String(slug))
		return null
	var exclusive_until: int = 0
	if owner_peer > 0:
		var window: int = exclusive_ms if exclusive_ms >= 0 else int(EXCLUSIVE_S * 1000.0)
		exclusive_until = Time.get_ticks_msec() + window
	var local_pos: Vector2 = container.to_local(global_pos)
	var node: Node = container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_LOOT_CHEST,
		local_pos,
		{
			"chest_slug": slug,
			"position": local_pos,
			"owner_peer_id": owner_peer,
			"exclusive_until_ms": exclusive_until,
		}
	)
	return node as LootChest
