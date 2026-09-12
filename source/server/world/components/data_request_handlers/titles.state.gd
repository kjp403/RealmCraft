extends DataRequestHandler
## Roster for the Vault Titles shelf.
##
## THE SHELF LISTS STOCK. Only what PremiumCatalog.resolve will actually sell -
## so not the donation ladder, which is bought with real money through a
## different door, and not the mastery titles, which are earned at 99. Neither is
## named here; resolve refuses both, so the shelf and the till cannot disagree
## about what is on offer.
##
## AND NOT EVEN THE ONES YOU OWN, unlike the cosmetics shelf. The asymmetry is
## deliberate: every title a character holds - donated, earned or bought - lands
## in titles_unlocked, and the PROFILE title dropdown reads exactly that. An
## unlisted title is still wearable, from the screen that exists for wearing
## titles. A cosmetic has no such second home.
##
## STAFF SEE EVERYTHING, BUT ONLY IN THE VFX VAULT. That room is for testing the
## whole set; in the town shop staff see the shop, so what staff look at is what
## players get.
##
## `allowed` means "may wear anything" - a staff power, anywhere. A player's right
## to one title comes from `owned`. titles.equip re-checks independently.


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

	var visible: Array = []
	var owned: Array = []
	for row_v: Variant in TitleCatalog.vault_roster():
		var row: Dictionary = row_v as Dictionary
		var title: String = str(row.get("name", row.get("title", "")))
		if title.is_empty():
			continue
		if VaultGrants.has_title(pr, title):
			owned.append(title)
		if testing \
				or not PremiumCatalog.resolve(VaultGrants.title_token(title)).is_empty():
			visible.append(row)

	return {
		"ok": true,
		"allowed": staff,
		"owned": owned,
		"titles": visible,
		"equipped": pr.display_title,
	}
