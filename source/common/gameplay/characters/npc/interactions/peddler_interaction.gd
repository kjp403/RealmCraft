class_name PeddlerInteraction
extends NPCInteraction
## NPC capability: the Traveling Peddler's cart. Selecting it opens the
## [code]peddler[/code] window, which quotes today's three goods from the server
## and buys one with [code]peddler.buy[/code].
##
## Carries no stock of its own — unlike a [ShopInteraction], whose catalog IS its
## resource. The Peddler's catalog is rolled from the UTC date ([PeddlerStock]),
## so putting a list here would be a second, wrong source of truth. This exists
## purely to say "this NPC is the Peddler" and to hand the window the node name
## it needs for the server's range check.
##
## Like [QuickTravelInteraction] there is nothing to register: the handlers
## resolve this interaction straight off the NPC node they were given.


func menu_entry(npc: Node) -> Dictionary:
	return {
		"label": _label_or("Browse the cart"),
		"icon": _icon_or(""),
		"menu": &"peddler",
		"arg": {"npc": String(npc.name)},
	}


## The peddler capability on [param npc], or null. Shared by the stock and buy
## handlers so both read the same NPC.
static func of(npc: Node) -> PeddlerInteraction:
	var resource: NPCResource = npc.get(&"npc_resource") as NPCResource
	if resource == null:
		return null
	for interaction: NPCInteraction in resource.interactions:
		if interaction is PeddlerInteraction:
			return interaction as PeddlerInteraction
	return null
