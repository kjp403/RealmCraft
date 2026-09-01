extends PeddlerAction
## Portable Deposit Box: set a personal bank vault down at your feet for
## [constant PortableDepositBox.LIFETIME_S].
##
## Everything that can fail is checked before the box is consumed: the player has
## to be alive, out of combat, and standing somewhere the map can host a dynamic
## prop. The out-of-combat gate is the one with teeth — banking mid-fight is a
## way to dodge a death's item risk, and a bank you can open while being hit is
## a different (much stronger) item than the one being sold.
##
## Only ONE box per player at a time. A second would not stack any benefit, and
## two boxes at different points on the map is just litter with a two-minute
## lifetime.

## player_id -> the box they currently have standing. Server-only and in-memory:
## the box itself lives for two minutes and dies with the instance, so persisting
## the fact that one exists would outlive the thing it describes.
static var _boxes: Dictionary[int, PortableDepositBox] = {}


func apply(player: Player, instance: ServerInstance) -> Dictionary:
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return {"ok": false, "reason": "no_player"}
	if player.is_in_combat():
		return {"ok": false, "reason": "in_combat"}

	var player_id: int = int(resource.player_id)
	var standing: PortableDepositBox = _boxes.get(player_id, null)
	if standing != null and is_instance_valid(standing):
		return {"ok": false, "reason": "already_placed"}
	_boxes.erase(player_id)

	var box: PortableDepositBox = PortableDepositBox.place_for(player, instance)
	if box == null:
		# The map has no props container, or the spawn was refused. Never consume
		# on a failed placement.
		return {"ok": false, "reason": "no_room"}
	_boxes[player_id] = box

	return {
		"ok": true,
		"message": "Deposit box set down — %d seconds." % int(PortableDepositBox.LIFETIME_S),
	}
