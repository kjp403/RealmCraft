class_name FilletKnifeItem
extends AnglerToolItem
## The Fillet Knife. Right-click Use opens the Fillet panel, which is where the
## actual conversion is chosen and sent; the knife itself does nothing but gate and
## open. It is never consumed — see [FilletService.has_knife].


func action_label() -> String:
	return "Use"


## Opens res://source/client/ui/menus/fillet/fillet_menu.tscn. Hud.display_menu
## resolves the scene from this name by convention, so nothing has to register it.
func client_menu() -> StringName:
	return &"fillet"
