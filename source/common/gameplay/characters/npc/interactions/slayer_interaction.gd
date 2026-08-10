class_name SlayerInteraction
extends NPCInteraction
## NPC capability: acts as a Slayer master. Resolved server-side via
## Map.get_slayer_master(master_key) — the owning NPC's NPCResource filename slug
## is the master key, exactly mirroring how QuestInteraction resolves quest givers
## and ShopInteraction resolves shops by the same owning-NPC slug.

@export var master: SlayerMasterResource

## Owning NPC, stored on register() so handlers can read the master's display name
## + greeting off this source without a second copy. Server-side only.
var _owner: NPC


func menu_entry(npc: Node) -> Dictionary:
	var owner: NPC = npc as NPC
	if master == null or owner == null:
		return {}
	return {
		"label": _label_or("Slayer Tasks"),
		"icon": _icon_or(""),
		"menu": &"slayer",
		"arg": String(owner.giver_key()),
	}


func register(map: Map, npc: Node) -> void:
	_owner = npc as NPC
	if _owner != null:
		map.register_keyed(map.slayer_masters, _owner.giver_key(), self, "slayer master")


## Slayer-source fields read by the slayer.* handlers (duck-typed with
## QuestInteraction.giver_name).
var master_name: String:
	get:
		return _owner.display_name if _owner != null else ""
