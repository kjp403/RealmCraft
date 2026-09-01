class_name PeddlerAction
extends RefCounted
## Server-only. What USING one Traveling Peddler good does.
##
## One subclass per good with an effect, named on its [member
## PeddlerItemData.action_script]. [code]peddler.use[/code] instantiates it and
## calls [method apply] — instantiated rather than called as a static, for the
## same reason [DataRequestHandler] is: [code]script.new()[/code] type-checks
## against this base, so a stock row pointed at the wrong script fails loudly at
## the use site instead of silently no-opping.
##
## CONTRACT. [method apply] runs AFTER the server has verified the player holds
## the item and is alive, and BEFORE the item is consumed. Returning ok=false
## aborts the use and the item is NOT consumed — so an action that cannot finish
## (bag full, buff already at cap) must fail rather than half-apply.
##
## The return dict rides straight back to the client as the [code]peddler.use[/code]
## reply. Put a "message" in it and the bag dock toasts it.


## Apply this good's effect to [param player]. See the contract above.
func apply(_player: Player, _instance: ServerInstance) -> Dictionary:
	return {"ok": false, "reason": "no_action"}


## True when this good is used up by [method apply]. Overridden to false by a
## good that grants a permanent unlock and wants to stay in the bag; every
## current action consumes.
func consumes() -> bool:
	return true
