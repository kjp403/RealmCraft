class_name QuickTravelInteraction
extends NPCInteraction
## NPC capability: a paid quick-travel desk (the Wayfarer). Selecting it opens
## the [code]quick_travel[/code] window, which quotes live fares from the server
## and then books one with [code]travel.quick[/code].
##
## Differs from [WarpInteraction] in three ways, which is why it is its own
## capability rather than a flag on that one:
##   - MANY destinations behind one option, not one warp per menu row.
##   - Each ride costs gold, charged server-side, with a frequency surge on top
##     ([QuickTravelService]).
##   - The client is never told the price by this resource. Fares depend on the
##     player's surge state, so the window asks the server for a quote; this
##     array is the authoritative ROUTE list that both sides index into.
##
## Like [WarpInteraction] there is nothing to register: the handlers resolve this
## interaction straight off the NPC node they were given.

## The stops this desk sells, in display order. The index into this array is the
## ticket id the client books with, so reordering it reorders the UI too.
@export var destinations: Array[QuickTravelDestination] = []


func menu_entry(npc: Node) -> Dictionary:
	if destinations.is_empty():
		return {}
	return {
		"label": _label_or("Quick travel"),
		"icon": _icon_or(""),
		"menu": &"quick_travel",
		# The window needs the NPC's node name so its requests can be range-checked
		# against the desk the player is actually standing at.
		"arg": {"npc": String(npc.name)},
	}


## The quick-travel desk on [param npc], or null. Shared by the quote and booking
## handlers so both read the same route list off the same resource.
static func of(npc: Node) -> QuickTravelInteraction:
	var resource: NPCResource = npc.get(&"npc_resource") as NPCResource
	if resource == null:
		return null
	for interaction: NPCInteraction in resource.interactions:
		if interaction is QuickTravelInteraction:
			return interaction as QuickTravelInteraction
	return null


## Bounds-checked lookup — an out-of-range ticket id from a client returns null
## rather than crashing the handler.
func destination_at(index: int) -> QuickTravelDestination:
	if index < 0 or index >= destinations.size():
		return null
	return destinations[index]
