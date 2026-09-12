extends DataRequestHandler
## Roster for the Vault cosmetics shelf: what this caller may see, what they own,
## and what they have equipped.
##
## WHO SEES WHAT. Staff see every cosmetic, including the ones with no gameplay
## trigger - but only while standing in the VFX Vault, the room that exists for
## testing them. In the town shop staff see the shop, so what staff look at is
## what players get. Everyone else, everywhere, sees what is actually FOR SALE
## plus anything they already own.
##
## That last clause matters more than it looks, and it is why this shelf differs
## from the titles one: a slot can be pulled from sale after somebody has bought
## from it, and a cosmetic has no home outside this menu - no profile dropdown,
## no chat command - so dropping it would stop them wearing what they paid for.
##
## PremiumCatalog.resolve is the filter rather than a list kept here, so "can be
## seen in the shop" and "can be bought" are the same question asked once. The
## four triggerless cosmetics fall out of both for free.
##
## `allowed` means "may equip ANYTHING" - a staff power. A player's right to wear
## one particular cosmetic comes from `owned`. cosmetics.equip re-checks both
## independently; this response is a convenience for the UI and is never the
## security boundary.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var pr: PlayerResource = player.player_resource

	var staff: bool = CommandPermissions.effective_priority(pr, instance) \
		>= CommandPermissions.STAFF_PROTECT_PRIORITY
	var testing: bool = staff and VaultRooms.is_staff_vault(instance)

	var visible: Array[int] = []
	var owned: Array[int] = []
	for cosmetic_id: int in Cosmetics.ids():
		var is_owned: bool = VaultGrants.has_cosmetic(pr, cosmetic_id)
		if is_owned:
			owned.append(cosmetic_id)
		if testing or is_owned \
				or not PremiumCatalog.resolve(VaultGrants.cosmetic_token(cosmetic_id)).is_empty():
			visible.append(cosmetic_id)

	# Two equipped slots: the body effect (aura/trail/halo/...) and the weapon glow.
	# The client tabs by Cosmetics.slot_of, so the roster stays one flat list.
	return {
		"ok": true,
		"allowed": staff,
		"owned": owned,
		"cosmetics": visible,
		"equipped": pr.cosmetic_id,
		"equipped_weapon": pr.weapon_cosmetic_id,
	}
