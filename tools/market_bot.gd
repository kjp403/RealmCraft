extends Node
## Headless bot client for end-to-end Trading Post testing against a LOCAL stack.
##
## Connects to a world server exactly the way the real client does — same
## Client.connect_to_server, same WebSocket, same data-request RPC — then drives
## the market.* / mail.* handlers and prints what came back. Nothing here reaches
## into the server's memory or its database: if a step passes, it passed through
## the shipping code path.
##
## The gateway HTTP dance (account -> login -> character -> enter) happens outside
## this script; pass the resulting connection details in:
##
##   godot --path . --mode=client res://tools/market_bot.tscn -- \
##       --address=127.0.0.1 --port=8087 --token=<auth-token> --act=sell \
##       --item=60 --amount=10 --price=250
##
## Acts:
##   sell  — open a stall and list --amount of --item at --price each
##   buy   — browse the board and buy --amount off the cheapest listing of --item
##   price — re-price my listing of --item to --price, stall staying open
##   pull  — take --amount (or everything) off my stall; stock returns by mailbox
##   watch — sit on the board for --seconds and report every live market.changed
##           push, proving other players' trades reach an open panel with no
##           action of your own
##   claim — list the mailbox, claim everything with an attachment
##   show  — print the board, my stall and my mailbox, and change nothing

## The world can take a moment to stream in the map before data requests resolve.
const CONNECT_TIMEOUT_S: float = 30.0

var _args: Dictionary = {}
var _failed: bool = false


func _ready() -> void:
	_args = CmdlineUtils.get_parsed_args()
	call_deferred(&"_go")


func _go() -> void:
	var address: String = str(_args.get("address", "127.0.0.1"))
	var port: int = int(str(_args.get("port", "8087")))
	var token: String = str(_args.get("token", ""))
	if token.is_empty():
		_die("no --token: get one from POST /v1/world/enter")
		return

	print("[bot] connecting to %s:%d" % [address, port])
	Client.connect_to_server(address, port, token)

	var ready_player: Variant = await _await_signal(ClientState.local_player_ready, CONNECT_TIMEOUT_S)
	if ready_player == null:
		_die("world never finished loading (no local_player_ready in %ds)" % int(CONNECT_TIMEOUT_S))
		return
	print("[bot] in world as %s (instance %s)" % [
		ClientState.local_player.display_name if ClientState.local_player != null else "?",
		_instance(),
	])

	match str(_args.get("act", "show")):
		"sell":
			await _act_sell()
		"buy":
			await _act_buy()
		"price":
			await _act_reprice()
		"pull":
			await _act_pull()
		"watch":
			await _act_watch()
		"claim":
			await _act_claim()
		_:
			await _act_show()

	print("BOT_FAIL" if _failed else "BOT_OK")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1 if _failed else 0)


# --- Acts --------------------------------------------------------------------


func _act_sell() -> void:
	var item_id: int = int(str(_args.get("item", "0")))
	var amount: int = int(str(_args.get("amount", "1")))
	var price: int = int(str(_args.get("price", "1")))

	var opened: Dictionary = await _request(&"market.set_store", {
		"name": str(_args.get("stall", "")), "open": true,
	})
	_check(bool(opened.get("ok", false)), "opened stall '%s'" % str(opened.get("store_name", "")))

	# Resolve the bag slot holding the item — market.list takes a slot uid, the
	# same way the real menu's picker does.
	var mine: Dictionary = await _request(&"market.mine", {})
	if not bool(mine.get("ok", false)):
		_die("market.mine failed")
		return
	# Pick the BIGGEST stack of the item, not the first: a character can hold the
	# same item in several slots (starter kit + a seeded pile), and the first one
	# found is often the 5-unit leftover.
	var uid: int = -1
	var best: int = 0
	var inventory: Dictionary = Inventory.normalize(mine.get("inventory", {}))
	for slot_uid: Variant in inventory:
		if int(inventory[slot_uid].get("id", 0)) != item_id:
			continue
		var held: int = int(inventory[slot_uid].get("a", 0))
		if held > best:
			best = held
			uid = int(slot_uid)
	if uid < 0:
		_die("no bag slot holding item %d" % item_id)
		return

	var before: int = Inventory.count(inventory, item_id)
	print("[bot] using bag slot %d (%d held there, %d across the bag)" % [uid, best, before])
	var listed: Dictionary = await _request(&"market.list", {
		"uid": uid, "amount": amount, "unit_price": price,
	})
	if not _check(bool(listed.get("ok", false)), "listed %dx item %d at %d each" % [amount, item_id, price]):
		print("[bot]   reason: %s" % str(listed.get("reason", "?")))
		return
	var after: int = Inventory.count(Inventory.normalize(listed.get("inventory", {})), item_id)
	_check(after == before - amount, "bag went %d -> %d (escrowed, not copied)" % [before, after])
	_check(int(listed.get("amount", 0)) == amount, "the listing holds all %d" % amount)


func _act_buy() -> void:
	var item_id: int = int(str(_args.get("item", "0")))
	var amount: int = int(str(_args.get("amount", "1")))

	var board: Dictionary = await _request(&"market.browse", {})
	if not _check(bool(board.get("ok", false)), "read the board"):
		return
	var gold_before: int = int(board.get("gold", 0))
	print("[bot] %d stall(s), %d listing(s), my gold %d" % [
		(board.get("stores", []) as Array).size(),
		(board.get("listings", []) as Array).size(),
		gold_before,
	])

	var pick: Dictionary = {}
	for listing: Dictionary in (board.get("listings", []) as Array):
		if int(listing.get("item_id", 0)) != item_id:
			continue
		if pick.is_empty() or int(listing.get("unit_price", 0)) < int(pick.get("unit_price", 0)):
			pick = listing
	if pick.is_empty():
		_die("nothing on the board is selling item %d" % item_id)
		return
	print("[bot] buying %dx from '%s' (%s) at %d each" % [
		amount, str(pick.get("store_name", "")), str(pick.get("seller_name", "")),
		int(pick.get("unit_price", 0)),
	])

	var expected: int = int(pick.get("unit_price", 0)) * amount
	var bought: Dictionary = await _request(&"market.buy", {
		"listing_id": int(pick.get("listing_id", 0)), "amount": amount,
	})
	if not _check(bool(bought.get("ok", false)), "market.buy accepted"):
		print("[bot]   reason: %s" % str(bought.get("reason", "?")))
		return
	_check(int(bought.get("total", 0)) == expected, "charged %d (expected %d)" % [int(bought.get("total", 0)), expected])
	_check(
		int(bought.get("gold", -1)) == gold_before - expected,
		"gold %d -> %d" % [gold_before, int(bought.get("gold", -1))]
	)

	# Buying the same listing twice with the whole stock must fail, not duplicate.
	var replay: Dictionary = await _request(&"market.buy", {
		"listing_id": int(pick.get("listing_id", 0)), "amount": int(pick.get("amount", 0)),
	})
	_check(
		not bool(replay.get("ok", false)),
		"replaying the buy for the full stack is refused (%s)" % str(replay.get("reason", "?"))
	)


## Re-price a live listing. The point of the test is the two things that must NOT
## happen: the stall closing, and the stock moving.
func _act_reprice() -> void:
	var item_id: int = int(str(_args.get("item", "0")))
	var price: int = int(str(_args.get("price", "0")))

	var mine: Dictionary = await _request(&"market.mine", {})
	var open_before: bool = bool(mine.get("is_open", false))
	var target: Dictionary = {}
	for listing: Dictionary in (mine.get("listings", []) as Array):
		if int(listing.get("item_id", 0)) == item_id:
			target = listing
			break
	if target.is_empty():
		_die("no listing of item %d on my stall" % item_id)
		return
	var stock_before: int = int(target.get("amount", 0))
	print("[bot] re-pricing listing #%d: %d -> %d" % [
		int(target.get("listing_id", 0)), int(target.get("unit_price", 0)), price,
	])

	var result: Dictionary = await _request(&"market.reprice", {
		"listing_id": int(target.get("listing_id", 0)), "unit_price": price,
	})
	if not _check(bool(result.get("ok", false)), "market.reprice accepted"):
		print("[bot]   reason: %s" % str(result.get("reason", "?")))
		return

	var after: Dictionary = await _request(&"market.mine", {})
	_check(bool(after.get("is_open", false)) == open_before, "the stall never closed")
	for listing: Dictionary in (after.get("listings", []) as Array):
		if int(listing.get("listing_id", 0)) != int(target.get("listing_id", 0)):
			continue
		_check(int(listing.get("unit_price", 0)) == price, "the new ask is live on the board")
		_check(int(listing.get("amount", 0)) == stock_before, "stock is untouched (%d)" % stock_before)
		return
	_check(false, "the listing survived the re-price")


func _act_pull() -> void:
	var amount: int = int(str(_args.get("amount", "0")))
	var before: Dictionary = await _request(&"market.mine", {})
	var listed: int = (before.get("listings", []) as Array).size()
	_check(listed > 0, "stall has %d listing(s) to pull" % listed)

	if amount > 0:
		# Partial pull: trim one listing, leave the rest of its stock selling.
		var target: Dictionary = (before.get("listings", []) as Array)[0]
		var stock_before: int = int(target.get("amount", 0))
		var listing_id: int = int(target.get("listing_id", 0))
		var trimmed: Dictionary = await _request(
			&"market.unlist", {"listing_id": listing_id, "amount": amount}
		)
		if not _check(bool(trimmed.get("ok", false)), "partial pull of %d accepted" % amount):
			print("[bot]   reason: %s" % str(trimmed.get("reason", "?")))
			return
		var after_partial: Dictionary = await _request(&"market.mine", {})
		for listing: Dictionary in (after_partial.get("listings", []) as Array):
			if int(listing.get("listing_id", 0)) == listing_id:
				_check(
					int(listing.get("amount", 0)) == stock_before - amount,
					"listing left with %d of %d" % [stock_before - amount, stock_before]
				)
				return
		_check(false, "the trimmed listing is still on sale")
		return

	var pulled: Dictionary = await _request(&"market.unlist", {"all": true})
	if not _check(bool(pulled.get("ok", false)), "market.unlist accepted"):
		print("[bot]   reason: %s" % str(pulled.get("reason", "?")))
		return
	_check((pulled.get("pulled", []) as Array).size() == listed, "pulled all %d" % listed)

	var after: Dictionary = await _request(&"market.mine", {})
	_check((after.get("listings", []) as Array).is_empty(), "stall is now empty")

	# Pulling the same stock again must find nothing — the stock is in the mailbox
	# now, and a second pull that "succeeded" would be a duplication.
	var replay: Dictionary = await _request(&"market.unlist", {"all": true})
	_check(not bool(replay.get("ok", false)), "a second pull returns nothing (%s)" % str(replay.get("reason", "?")))


## Sit on the board and report live pushes. This is the "no delay" requirement
## under test: a second client changes the market, and this one hears about it
## without asking.
func _act_watch() -> void:
	var seconds: float = float(str(_args.get("seconds", "20")))
	var pushes: Array = []
	Client.subscribe(&"market.changed", func(payload: Dictionary) -> void:
		pushes.append(payload)
		print("[bot] PUSH market.changed reason=%s listing=%d" % [
			str(payload.get("reason", "?")), int(payload.get("listing_id", 0)),
		]))

	var before: Dictionary = await _request(&"market.browse", {})
	var stock_before: Dictionary = _stock_by_listing(before)
	print("[bot] watching for %.0fs — %d listing(s) on the board" % [seconds, stock_before.size()])

	var waited: float = 0.0
	while waited < seconds:
		await get_tree().process_frame
		waited += get_process_delta_time()

	_check(not pushes.is_empty(), "received %d live push(es) while idle" % pushes.size())
	var after: Dictionary = await _request(&"market.browse", {})
	var stock_after: Dictionary = _stock_by_listing(after)
	for listing_id: int in stock_before:
		var was: int = int(stock_before[listing_id])
		var now: int = int(stock_after.get(listing_id, 0))
		if was != now:
			print("[bot] listing #%d stock %d -> %d" % [listing_id, was, now])


func _stock_by_listing(board: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for listing: Dictionary in (board.get("listings", []) as Array):
		out[int(listing.get("listing_id", 0))] = int(listing.get("amount", 0))
	return out


func _act_claim() -> void:
	var inbox: Dictionary = await _request(&"mail.list", {})
	if not _check(bool(inbox.get("ok", false)), "read the mailbox"):
		return
	var mails: Array = inbox.get("mails", [])
	print("[bot] %d mail(s)" % mails.size())
	for mail: Dictionary in mails:
		var rewards: Array = mail.get("rewards", [])
		print("[bot]   #%d  from %-16s  %s" % [
			int(mail.get("mail_id", 0)), str(mail.get("sender_name", "")), str(mail.get("subject", "")),
		])
		if not str(mail.get("body", "")).is_empty():
			print("[bot]        %s" % str(mail.get("body", "")).replace("\n\n", " | ").replace("\n", " "))
		if rewards.is_empty() or bool(mail.get("claimed", false)):
			continue
		var claimed: Dictionary = await _request(&"mail.claim", {"mail_id": int(mail.get("mail_id", 0))})
		if not _check(bool(claimed.get("ok", false)), "claimed mail #%d" % int(mail.get("mail_id", 0))):
			print("[bot]   reason: %s" % str(claimed.get("reason", "?")))
			continue
		for reward: Variant in (claimed.get("rewards", []) as Array):
			var r: Dictionary = reward
			print("[bot]        + %d x %s" % [int(r.get("amount", 0)), str(r.get("name", ""))])
		# A claim is one-shot: the SQL guard has to refuse the replay.
		var replay: Dictionary = await _request(&"mail.claim", {"mail_id": int(mail.get("mail_id", 0))})
		_check(
			not bool(replay.get("ok", false)),
			"re-claiming mail #%d is refused (%s)" % [int(mail.get("mail_id", 0)), str(replay.get("reason", "?"))]
		)


func _act_show() -> void:
	var board: Dictionary = await _request(&"market.browse", {})
	print("[bot] board ok=%s stalls=%d listings=%d gold=%d" % [
		bool(board.get("ok", false)),
		(board.get("stores", []) as Array).size(),
		(board.get("listings", []) as Array).size(),
		int(board.get("gold", 0)),
	])
	for store: Dictionary in (board.get("stores", []) as Array):
		print("[bot]   stall '%s' — %d listing(s), from %d gold" % [
			str(store.get("store_name", "")), int(store.get("listing_count", 0)), int(store.get("cheapest", 0)),
		])
	for listing: Dictionary in (board.get("listings", []) as Array):
		print("[bot]   %-20s x%-5d %8d ea  %s" % [
			_item_name(int(listing.get("item_id", 0))), int(listing.get("amount", 0)),
			int(listing.get("unit_price", 0)), str(listing.get("seller_name", "")),
		])
	var mine: Dictionary = await _request(&"market.mine", {})
	print("[bot] my stall: open=%s listings=%d" % [
		bool(mine.get("is_open", false)), (mine.get("listings", []) as Array).size(),
	])
	var bag: Dictionary = Inventory.normalize(mine.get("inventory", {}))
	print("[bot] my bag: %d gold, %d iron bars" % [
		Inventory.count(bag, Economy.gold_id()),
		Inventory.count(bag, ContentRegistryHub.id_from_slug(&"items", &"iron_bar")),
	])
	await _act_claim()


# --- Plumbing ----------------------------------------------------------------


func _instance() -> String:
	return String(InstanceClient.current.name) if InstanceClient.current != null else ""


func _request(type: StringName, args: Dictionary) -> Dictionary:
	var result: Array = await Client.request_data_await(type, args, _instance())
	if result[1] != OK:
		_die("%s transport error %d" % [type, result[1]])
		return {}
	return result[0] as Dictionary


## await with a deadline, so a stuck connect ends the run instead of hanging a
## CI-style invocation forever. Returns null on timeout.
func _await_signal(sig: Signal, timeout_s: float) -> Variant:
	var box: Array = [null, false]
	var handler: Callable = func(value: Variant = null) -> void:
		box[0] = value
		box[1] = true
	sig.connect(handler, CONNECT_ONE_SHOT)
	var waited: float = 0.0
	while not box[1] and waited < timeout_s:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return box[0] if box[1] else null


func _item_name(item_id: int) -> String:
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	return String(item.item_name) if item != null else "item #%d" % item_id


func _check(condition: bool, label: String) -> bool:
	if condition:
		print("  ok    %s" % label)
	else:
		_failed = true
		printerr("  FAIL  %s" % label)
	return condition


func _die(reason: String) -> void:
	_failed = true
	printerr("  FAIL  %s" % reason)
	print("BOT_FAIL")
	get_tree().quit(1)
