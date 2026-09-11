class_name AnglerToolItem
extends Item
## Base for the Angler Shop's QoL bag tools — the Fillet Knife and the Bottomless
## Bait Bucket. Both sit in the bag, both have exactly one right-click action of
## their own, and neither is ever consumed by using it.
##
## WHY A SHARED BASE AND NOT TWO UNRELATED Item SUBCLASSES
## The inventory dock decides its context rows by `is`-type checks against a fixed
## list (see compact_menu_host.gd). Every new usable item type otherwise means
## editing that list in three places — the context menu, the double-click filter and
## the primary-action guard — and missing ONE of them is silent: the row appears and
## does nothing, or the item is quietly Drop-only. One base means one branch in each
## of those three places, and a third Angler tool later needs no UI change at all.
##
## The action is described BY THE ITEM rather than looked up by the dock, for the
## same reason [member PeddlerGoodItem.usable] is authored: the bag has to draw the
## row before any server call, and reaching into a catalog for one string would
## couple the inventory UI to a system it otherwise knows nothing about.


func _init() -> void:
	# Tools are bag cargo — never drawn into the hand. Right-click is their action.
	holdable = false
	# Bought with Angler Points, which are account-bound. A tool that could be
	# handed over would make the point cost a cost on ALTS, not on players — the
	# same reasoning PeddlerGoodItem gives for its own can_trade.
	can_trade = false


## Label for the context-menu row ("Use", "Fill"). Subclasses override.
func action_label() -> String:
	return "Use"


## Client-side panel this tool opens, as a [method Hud.display_menu] name, or &""
## when the action is instant. Exactly one of this and [method server_request] is
## non-empty; a tool that sets both would open a panel AND fire the request behind
## it, which reads as a double action.
func client_menu() -> StringName:
	return &""


## Server data-request this tool fires, or &"" when it opens a panel instead.
func server_request() -> StringName:
	return &""


## Usable tools live with the potions — the bag tab answers "where would I look for
## this", and a knife you right-click is closer to a drink than to an ore.
func inventory_tab() -> InventoryTab:
	return InventoryTab.CONSUMABLE


func group_key() -> StringName:
	return &"angler"


func sort_key() -> Array:
	return [String(item_name)]
