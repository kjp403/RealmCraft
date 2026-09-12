class_name VaultRooms
## Which room is this Vault menu being opened from?
##
## The same three shelves are carried by two NPCs: the Vault Keeper in the Guild
## House, who sells, and the Curator in the VFX Vault, who is there so staff can
## test unreleased effects. The menu cannot tell them apart - every shelf routes
## to the same &"vault" menu - but the INSTANCE can, and the instance is already
## handed to every data request handler.
##
## WHY IT MATTERS. Without this, staff standing in the shop saw the staff roster,
## which means the only people able to check what the shop looks like were the
## only people who could not see it. Unreleased and unbuyable rows appeared in a
## storefront and nobody reviewing it could tell.


## The staff-only VFX Vault, by the instance_name in its InstanceResource. Not a
## map-path check: the resource name is what the instance collection is keyed by
## and what AdminOnlyInstanceResource gates on, so this agrees with the thing
## that actually decides who may stand here.
const STAFF_VAULT: StringName = &"vfx_vault"


static func is_staff_vault(instance: ServerInstance) -> bool:
	if instance == null or instance.instance_resource == null:
		return false
	return instance.instance_resource.instance_name == STAFF_VAULT
