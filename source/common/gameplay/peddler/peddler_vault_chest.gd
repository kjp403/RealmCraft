class_name PeddlerVaultChest
extends Node2D
## The strongbox that stands beside the Traveling Peddler. Locked; only a
## Peddler's Vault Key opens it, and the key is consumed doing so.
##
## Not a [LootChest] subclass on purpose. A loot chest rolls a table, belongs to
## whoever earned it, and vanishes when opened; this one has a FIXED payout, is
## open to every key-holder for the whole window, and only despawns when the
## Peddler does. Sharing the class would have meant a flag on LootChest for each
## of those, and a "chest" that behaved like neither.
##
## The payout lands in [member PlayerResource.pending_chest_loot] rather than the
## bag, and reports itself through the existing [code]chest.opened[/code] push —
## so it uses the reward window players already know, and a nearly-full bag
## cannot silently eat 30 potions.

const OPEN_RANGE: float = 96.0
const CLICK_SIZE: Vector2 = Vector2(44, 40)
## Registry slug of the key that opens it.
const KEY_SLUG: StringName = &"peddler_vault_key"
## What one key buys, as {slug: amount}. Fixed — this is a strongbox, not a
## gamble; the key costs 500,000 gold and the player is entitled to know exactly
## what it opens before they buy it.
const PAYOUT: Array[Dictionary] = [
	{"slug": &"boss_contract_key", "amount": 3},
	{"slug": &"greater_health_potion", "amount": 30},
]
const DISPLAY_NAME: String = "Peddler's Vault"

## Client-only: true while the cursor is over the click area.
var _interactable_hovered: bool = false


func _ready() -> void:
	z_index = 1
	if multiplayer.is_server():
		return
	_spawn_click_area()


## Deliberately NOT gated on [code]multiplayer.is_server()[/code]. A headless
## world server never calls _draw at all, so the guard buys nothing there — but
## a render tool mounts an OfflineMultiplayerPeer, which reads as a server, so
## the guard's only real effect was an invisible vault in every preview.
func _draw() -> void:
	# Drawn rather than sprited: the vault is a one-window prop and a bespoke
	# 32x28 chest sheet would be one more asset to keep in sync with a feature
	# whose art direction is not settled. Reads as a banded strongbox at
	# gameplay zoom.
	var body: Rect2 = Rect2(-16, -14, 32, 24)
	draw_rect(body, Color(0.20, 0.16, 0.11))
	draw_rect(body, Color(0.86, 0.72, 0.34), false, 2.0)
	draw_line(Vector2(-16, -4), Vector2(16, -4), Color(0.86, 0.72, 0.34), 2.0)
	draw_rect(Rect2(-4, -8, 8, 9), Color(0.95, 0.83, 0.45))
	draw_circle(Vector2(0, -3), 2.0, Color(0.20, 0.16, 0.11))


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
	ClientState.local_player.start_auto_pickup(self, prop_id, &"peddler.vault")


func _prop_id() -> int:
	var container: ReplicatedPropsContainer = get_meta(&"rp_container", null) as ReplicatedPropsContainer
	if container == null:
		container = get_parent() as ReplicatedPropsContainer
	if container == null:
		return -1
	return container.child_id_of_node(self)


## Server: spend one Vault Key from [param player] and stage the payout.
##
## ORDER MATTERS. Range, key possession and a resolvable payout are all checked
## before the key is removed, so a refused open never eats a 500,000-gold key.
func try_open(player: Player) -> Dictionary:
	if player == null or player.player_resource == null or player.is_dead:
		return {"ok": false, "reason": "missing"}
	if player.global_position.distance_to(global_position) > OPEN_RANGE:
		return {"ok": false, "reason": "too_far"}

	var resource: PlayerResource = player.player_resource
	var key_id: int = ContentRegistryHub.id_from_slug(&"items", KEY_SLUG)
	if key_id <= 0:
		# The key item is not indexed. Say so rather than telling a player who is
		# holding one that they have no key.
		return {"ok": false, "reason": "no_key_item"}
	if not Inventory.has_item(resource.inventory, key_id):
		return {"ok": false, "reason": "no_key"}

	var granted: Array = _resolve_payout()
	if granted.is_empty():
		return {"ok": false, "reason": "no_payout"}

	if not Inventory.remove_amount_by_id(resource.inventory, key_id, 1):
		return {"ok": false, "reason": "no_key"}

	for entry: Dictionary in granted:
		PendingChestLoot.add(
			resource.pending_chest_loot, int(entry["id"]), int(entry["amount"])
		)

	var payload: Dictionary = {
		"chest": DISPLAY_NAME,
		"gold": 0,
		"items": granted,
		"pending": PendingChestLoot.to_payload(resource.pending_chest_loot),
		"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
	}
	var peer: int = int(resource.current_peer_id)
	if peer > 0 and WorldServer.curr != null:
		if WorldServer.curr.database != null:
			WorldServer.curr.database.save_player(resource)
		WorldServer.curr.data_push.rpc_id(peer, &"chest.opened", payload)

	# The vault stays standing — one key, one open, but the next key-holder in
	# the crowd gets their turn too.
	payload["ok"] = true
	return payload


## [constant PAYOUT] resolved against the live items registry. An unresolvable
## slug is skipped; an entirely unresolvable payout refuses the open above rather
## than consuming the key for nothing.
static func _resolve_payout() -> Array:
	var out: Array = []
	for entry: Dictionary in PAYOUT:
		var item_id: int = ContentRegistryHub.id_from_slug(&"items", entry["slug"])
		if item_id <= 0:
			push_error("PeddlerVaultChest: payout slug '%s' is not indexed." % entry["slug"])
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item == null:
			continue
		out.append({
			"id": item_id,
			"amount": int(entry["amount"]),
			"name": String(item.item_name),
			# Fixed payout, not a roll — no probability to tier, so it reads as
			# common in the reward window. See LootRarity's header.
			"rarity": LootRarity.NAMES[LootRarity.Tier.COMMON],
		})
	return out
