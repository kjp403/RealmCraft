extends ChatCommand
## Give a player a recoloured vault skin, permanently.
##
## The vault recolours are unreleased stock, and [CommandPermissions.strip_unreleased_vfx]
## wipes vault_skin_id off any non-staff player on every instance spawn. So this
## does TWO things, and the second is the one that matters: it equips the skin,
## and it records the entitlement in [VaultGrants] so the strip leaves it alone.
## Equipping without granting - which is what the Vault's own equip handler does,
## correctly, for staff testing - produces a skin that vanishes at the next zone
## change with nothing logged.
##
##   /vaultskin <self|Name|#id|@account> <skin> <dye>
##   /vaultskin <target> clear
##
## Does NOT touch skin_id, so the player's real wardrobe look is restored the
## moment the vault skin is cleared.

## admin. Matches CommandPermissions.STAFF_PROTECT_PRIORITY - anyone who can be
## trusted not to be stripped can hand these out.
const ADMIN_PRIORITY: int = 2


func _init() -> void:
	command_name = "vaultskin"
	command_priority = ADMIN_PRIORITY
	command_usage = "/vaultskin <self|Name|#id|@account> <skin> <dye>   |   /vaultskin <target> clear"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 3:
		return "Usage: " + command_usage + "\n" + _usage_lists()

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	# Character-bound, like /grant: an @account grant would land on whichever alt
	# happens to be online, and a cosmetic given to the wrong character is worse
	# than one not given at all.
	if target.by_account:
		return "Target a character (Name or #id), not an @account — vault skins are character-bound."
	if not target.online:
		return "%s must be online." % target.label()

	var res: PlayerResource = target.resource
	var clearing: bool = args[2].strip_edges().to_lower() in ["clear", "none", "off"]
	var packed: int = 0

	if not clearing:
		if args.size() != 4:
			return "Usage: " + command_usage + "\n" + _usage_lists()
		var skin_id: int = _resolve_skin(args[2])
		if skin_id <= 0:
			return "Unknown skin '%s'.\n%s" % [args[2], _skin_list()]
		var style: int = _resolve_dye(args[3])
		if style <= 0:
			return "Unknown dye '%s'.\n%s" % [args[3], _dye_list()]
		packed = VaultSkins.pack(skin_id, style)
		# pack() returns 0 for a bad pair and is_valid() re-checks the whole id
		# against the sprite registry, so a skin that exists but is not wardrobe
		# listed (a monster sprite) is refused here rather than rendering as a
		# recoloured goblin over somebody's head.
		if packed == 0 or not VaultSkins.is_valid(packed):
			return "'%s' cannot be dyed '%s'." % [args[2], args[3]]

	if clearing:
		# Revoke the entitlement as well as unequipping. Leaving the grant behind
		# would mean the strip keeps honouring a skin the admin just took away,
		# and the next thing to set vault_skin_id would silently stick.
		var had: int = res.vault_skin_id
		res.vault_skin_id = 0
		if had != 0:
			VaultGrants.revoke_skin(res, had)
	else:
		VaultGrants.grant_skin(res, packed)
		res.vault_skin_id = packed

	# Push to the live character too, or the change is invisible until relog.
	var pnode: Player = server_instance.players_by_peer_id.get(target.peer_id, null)
	if pnode != null:
		pnode.vault_skin_id = res.vault_skin_id
		pnode.state_synchronizer.set_by_path(^":vault_skin_id", res.vault_skin_id)
	server_instance.world_server.database.save_player(res)

	var ws: WorldServer = server_instance.world_server
	if clearing:
		ws.chat_service.push_system_to_player(
			server_instance, target.player_id, "Your vault skin was removed."
		)
		return "Cleared %s's vault skin." % target.label()

	var shown: String = VaultSkins.display_name(packed)
	ws.chat_service.push_system_to_player(
		server_instance,
		target.player_id,
		"You were given the %s vault skin. It is yours to keep." % shown
	)
	return "Gave '%s' to %s." % [shown, target.label()]


## Skin by slug ("royal_knight"), by display name ("Royal Knight"), or by raw id.
func _resolve_skin(token: String) -> int:
	var clean: String = token.strip_edges()
	if clean.is_int():
		var as_id: int = int(clean)
		return as_id if PlayerSkins.is_horizon_listed(as_id) else 0
	var slug: String = clean.to_lower().replace(" ", "_").replace("-", "_")
	var by_slug: int = ContentRegistryHub.id_from_slug(&"sprites", StringName(slug))
	if by_slug > 0 and PlayerSkins.is_horizon_listed(by_slug):
		return by_slug
	for skin_id: int in PlayerSkins.ids():
		if PlayerSkins.display_name(skin_id).to_lower() == clean.to_lower():
			return skin_id if PlayerSkins.is_horizon_listed(skin_id) else 0
	return 0


## Dye by label ("Gilded"), or by its style number.
func _resolve_dye(token: String) -> int:
	var clean: String = token.strip_edges()
	if clean.is_int():
		var as_style: int = int(clean)
		return as_style if VaultSkins.STYLE_ORDER.has(as_style) else 0
	for style: int in VaultSkins.STYLE_ORDER:
		if str((VaultSkins.STYLE_META[style] as Dictionary).get("label", "")).to_lower() \
				== clean.to_lower():
			return style
	return 0


func _usage_lists() -> String:
	return "%s\n%s" % [_skin_list(), _dye_list()]


func _skin_list() -> String:
	var names: PackedStringArray = PackedStringArray()
	for skin_id: int in PlayerSkins.ids():
		if PlayerSkins.is_horizon_listed(skin_id):
			names.append(PlayerSkins.display_name(skin_id))
	return "Skins: " + ", ".join(names)


func _dye_list() -> String:
	var names: PackedStringArray = PackedStringArray()
	for style: int in VaultSkins.STYLE_ORDER:
		names.append(str((VaultSkins.STYLE_META[style] as Dictionary).get("label", "")))
	return "Dyes: " + ", ".join(names)
