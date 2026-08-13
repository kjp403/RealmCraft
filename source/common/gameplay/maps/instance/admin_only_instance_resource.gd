class_name AdminOnlyInstanceResource
extends InstanceResource
## An instance that ONLY admin+ may enter. Used by the VFX Vault, the staff room where
## unreleased cosmetics are tested on the live server.
##
## This is the hard gate. [method InstanceManager.transfer_player] and the warper path in
## [ServerInstance] both consult can_join_instance before moving anyone, so a player who
## learns the instance name, forges a warp request, or is dragged in by a bug still gets
## refused server-side. The vault also has no portal anywhere in the world and is not
## load_at_startup — the only documented way in is /vault, itself admin-gated — but
## obscurity is not the control; this method is.
##
## Rank is re-derived on every entry, so revoking someone's admin locks them out
## immediately rather than at next restart.


func can_join_instance(player: Player, index: int = -1) -> bool:
	if not super.can_join_instance(player, index):
		return false
	if player == null or player.player_resource == null:
		return false
	return CommandPermissions.effective_priority_global(player.player_resource) \
		>= CommandPermissions.STAFF_PROTECT_PRIORITY
