extends DataRequestHandler
## Roster for the Vault Titles shelf.
##
## Staff see the whole shelf. Everyone else sees what is for sale plus whatever
## they already hold, which is what keeps the two kinds of title that are NOT for
## sale off a shopper's list while still letting the people who have them wear
## them: the donation ladder (bought with money, through a different door) and
## the mastery titles (earned at 99, and never premium). PremiumCatalog.resolve
## refuses both, so neither needs naming here.
##
## `allowed` means "may wear anything" - staff. A player's right to one title
## comes from `owned`. titles.equip re-checks independently.


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

	var visible: Array = []
	var owned: Array = []
	for row_v: Variant in TitleCatalog.vault_roster():
		var row: Dictionary = row_v as Dictionary
		var title: String = str(row.get("name", row.get("title", "")))
		if title.is_empty():
			continue
		var is_owned: bool = VaultGrants.has_title(pr, title)
		if is_owned:
			owned.append(title)
		if staff or is_owned \
				or not PremiumCatalog.resolve(VaultGrants.title_token(title)).is_empty():
			visible.append(row)

	return {
		"ok": true,
		"allowed": staff,
		"owned": owned,
		"titles": visible,
		"equipped": pr.display_title,
	}
