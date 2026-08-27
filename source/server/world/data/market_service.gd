class_name MarketService
extends RefCounted
## Server-side glue between the Trading Post and the mailbox. Every market payout
## — sale gold to the seller, bought goods to the buyer, pulled stock back to its
## owner — leaves through here, so there is exactly one delivery path to audit.
##
## WHY MAIL: a bag can be full, and a direct grant into a full bag either fails
## (item lost, gold already taken) or overflows it. A mail row is written to
## SQLite before the transaction returns and cannot bounce, so nothing a player
## paid for can evaporate. See [Market] for the escrow model.

const SENDER_MARKET: String = "Trading Post"


static func _mail_store(instance: ServerInstance) -> MailStore:
	return instance.world_server.database.mail_store


## Writes one mail with reward attachments. Returns the new mail_id, or -1 when
## the row could not be written — callers MUST treat -1 as a failed delivery and
## roll their transaction back.
static func deliver(
	instance: ServerInstance,
	recipient_id: int,
	sender_name: String,
	subject: String,
	body: String,
	grants: Array
) -> int:
	if recipient_id <= 0 or grants.is_empty():
		return -1
	if not RedeemCodes.validate_grants(grants):
		ServerLog.error("MarketService.deliver refused invalid grants: %s" % JSON.stringify(grants))
		return -1
	return _mail_store(instance).send(
		recipient_id, sender_name, subject, body, JSON.stringify(grants)
	)


## Mails escrowed stock back to its owner (listing pulled, or stall closed out).
static func return_stock(
	instance: ServerInstance,
	owner_id: int,
	item_id: int,
	amount: int,
	reason: String
) -> int:
	var label: String = item_label(item_id, amount)
	return deliver(
		instance,
		owner_id,
		SENDER_MARKET,
		"Returned: %s" % label,
		"%s\n\nYour %s came off the market stall and is waiting here. Claim it to put it back in your bag."
			% [reason, label],
		[{"type": "item", "id": item_id, "amount": amount}]
	)


## Human label for a stack ("5 x Iron Bar"). Falls back to the raw id so a mail
## about an unindexed item is still readable instead of blank.
static func item_label(item_id: int, amount: int) -> String:
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	var name: String = String(item.item_name) if item != null else "Item #%d" % item_id
	if amount <= 1:
		return name
	return "%d x %s" % [amount, name]


## 1234567 -> "1,234,567". Prices in mail bodies are read at a glance; raw digits
## are where a 100,000 vs 1,000,000 misread happens.
static func format_gold(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	var count: int = 0
	for i: int in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if amount < 0 else "") + out


## Live "you just sold something" nudge for a seller who happens to be online.
## Purely cosmetic — the mail is the real notification, so a miss costs nothing.
static func notify_seller(instance: ServerInstance, seller_id: int, text: String) -> void:
	for peer_id: int in instance.world_server.connected_players:
		var pr: PlayerResource = instance.world_server.connected_players[peer_id]
		if pr != null and pr.player_id == seller_id:
			WorldServer.curr.data_push.rpc_id(peer_id, &"market.sold", {"text": text})
			return


## Tells every connected client the board moved, so an open Trading Post redraws
## immediately instead of showing stock that is already gone. This is what makes
## "1000 potions, someone buys 600, everyone sees 400" true for onlookers and not
## just for the buyer who happened to make the request.
##
## The payload is a hint, not the new state: clients re-read the board through the
## normal handlers, so there is exactly one source of truth and a dropped push
## costs a stale panel until the next action, never a wrong transaction.
## Broadcast because a stall is public — anyone browsing is affected by any sale.
static func broadcast_change(reason: StringName, listing_id: int = 0) -> void:
	if WorldServer.curr == null:
		return
	WorldServer.curr.data_push.rpc(&"market.changed", {
		"reason": String(reason),
		"listing_id": listing_id,
	})
