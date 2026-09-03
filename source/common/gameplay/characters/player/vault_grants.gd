class_name VaultGrants
## Staff-issued entitlements to vault cosmetics, and the only thing that survives
## [CommandPermissions.strip_unreleased_vfx].
##
## THE PROBLEM THIS SOLVES. Vault cosmetics - the premium title ladder, the
## sixteen recolours - are unreleased stock, and the strip is what keeps them
## that way: it wipes vault_skin_id and every premium title off any non-staff
## player on EVERY instance spawn. That is correct for a leak and catastrophic
## for a gift. A donor handed a Diamond Donator title wears it until their next
## zone change and then silently does not, with nothing logged and nothing to
## explain it - the grant undoes itself and the only visible symptom is an angry
## message from someone who paid.
##
## So the strip needs to tell a LEAK from a GIFT, and nothing on the character
## could: `titles_unlocked` holds both, and `vault_skin_id` is just an int. This
## list is that discriminator. It is written by admin-gated commands and by
## nothing else, so "is it in here" means "a human with admin decided this".
##
## STORED IN THE EXISTING titles_json BLOB, under a "granted" key - not in a new
## players column. Adding a column means adding a matching placeholder to the
## save_player INSERT, and getting that pair out of step makes EVERY save fail
## silently for every player. A new key in a JSON blob that is already read and
## written cannot do that, and old rows simply parse as no grants.
##
## Tokens are prefixed strings rather than two typed lists because they share one
## JSON key and one round trip; the prefix is what keeps a title named "12345"
## from ever colliding with a packed skin id.

## Prefixes. Changing either orphans every grant already in the database, so
## they are constants rather than inline literals.
const TITLE_PREFIX: String = "title:"
const SKIN_PREFIX: String = "skin:"


static func title_token(title: String) -> String:
	# Lower-cased on the way in. Titles arrive from chat commands, the vault UI
	# and the database, and "Diamond Donator" must not be a different entitlement
	# from "diamond donator" typed by an admin in a hurry.
	return TITLE_PREFIX + title.strip_edges().to_lower()


static func skin_token(vault_id: int) -> String:
	return SKIN_PREFIX + str(vault_id)


static func has_title(player: PlayerResource, title: String) -> bool:
	if player == null or title.strip_edges().is_empty():
		return false
	return player.granted_vfx.has(title_token(title))


static func has_skin(player: PlayerResource, vault_id: int) -> bool:
	if player == null or vault_id == 0:
		return false
	return player.granted_vfx.has(skin_token(vault_id))


## True when this actually added something, so a caller can tell a fresh grant
## from a re-grant without checking first.
static func grant_title(player: PlayerResource, title: String) -> bool:
	return _add(player, title_token(title))


static func grant_skin(player: PlayerResource, vault_id: int) -> bool:
	return _add(player, skin_token(vault_id))


static func revoke_title(player: PlayerResource, title: String) -> bool:
	return _remove(player, title_token(title))


static func revoke_skin(player: PlayerResource, vault_id: int) -> bool:
	return _remove(player, skin_token(vault_id))


## Every granted title, as the tokens were stored (lower case). For /vaultgrants
## and for anything auditing who was given what.
static func granted_titles(player: PlayerResource) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if player == null:
		return out
	for token: String in player.granted_vfx:
		if token.begins_with(TITLE_PREFIX):
			out.append(token.substr(TITLE_PREFIX.length()))
	return out


static func granted_skins(player: PlayerResource) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	if player == null:
		return out
	for token: String in player.granted_vfx:
		if token.begins_with(SKIN_PREFIX):
			out.append(int(token.substr(SKIN_PREFIX.length())))
	return out


static func _add(player: PlayerResource, token: String) -> bool:
	if player == null:
		return false
	if player.granted_vfx.has(token):
		return false
	# Reassigned rather than appended in place: PackedStringArray is a value type
	# on an @export, and mutating the getter's copy is a no-op that looks exactly
	# like a successful grant.
	var next: PackedStringArray = player.granted_vfx.duplicate()
	next.append(token)
	player.granted_vfx = next
	return true


static func _remove(player: PlayerResource, token: String) -> bool:
	if player == null:
		return false
	var next: PackedStringArray = PackedStringArray()
	var dropped: bool = false
	for existing: String in player.granted_vfx:
		if existing == token:
			dropped = true
			continue
		next.append(existing)
	if dropped:
		player.granted_vfx = next
	return dropped
