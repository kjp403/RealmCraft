class_name GatewayManagerServer
extends BaseMultiplayerEndpoint


@export var world_manager: WorldManagerServer
@export var authentication_manager: AuthenticationManager
## Premium currency wallet + ledger. Same scene, so this resolves - an
## exported node path that pointed outside this scene would silently be null
## on instance and every purchase would answer "unavailable".
@export var premium_database: PremiumDatabase


func _ready() -> void:
	var configuration: Dictionary = ConfigFileUtils.load_section(
		"gateway-manager-server",
		CmdlineUtils.get_parsed_args().get("config", "res://data/config/master_config.cfg")
	)
	create(Role.SERVER, configuration.bind_address, configuration.port)


func _connect_multiplayer_api_signals(api: SceneMultiplayer) -> void:
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	print("Gateway: %d is connected to GatewayManager." % peer_id)
	update_worlds_info.rpc_id(peer_id, world_manager.get_public_worlds())


func _on_peer_disconnected(peer_id: int) -> void:
	print("Gateway: %d is disconnected from GatewayManager." % peer_id)


@rpc("any_peer", "call_remote")
func gateway_request(request_id: int, request: Dictionary) -> void:
	var gateway_id: int = multiplayer.get_remote_sender_id()
	if not request.has("action"):
		return
	var action: String = request.get("action", "")
	match action:
		"login":
			gateway_response.rpc_id(
				gateway_id,
				request_id,
				login_request(
					request[GatewayAPI.KEY_ACCOUNT_USERNAME],
					request[GatewayAPI.KEY_ACCOUNT_PASSWORD]
				)
			)
		"guest":
			# Guest creation is permanently disabled (see AuthenticationManager).
			gateway_response.rpc_id(
				gateway_id,
				request_id,
				{"error": GatewayAPI.ERR_GUEST_DISABLED, "msg": "Guest login disabled."}
			)
		"create_account":
			gateway_response.rpc_id(
				gateway_id,
				request_id,
				create_account_request(request[GatewayAPI.KEY_ACCOUNT_USERNAME], request[GatewayAPI.KEY_ACCOUNT_PASSWORD], false)
			)
		"create_character":
			create_player_character_request(
				gateway_id,
				request_id,
				request[GatewayAPI.KEY_ACCOUNT_USERNAME],
				request["data"],
				request[GatewayAPI.KEY_WORLD_ID],
				str(request.get("__ip__", "")),
			)
		"get_characters":
			request_player_characters(
				gateway_id,
				request_id,
				request[GatewayAPI.KEY_ACCOUNT_USERNAME],
				request[GatewayAPI.KEY_WORLD_ID]
			)
		"enter_world":
			request_enter_world(
				gateway_id,
				request_id,
				request[GatewayAPI.KEY_ACCOUNT_USERNAME],
				request[GatewayAPI.KEY_WORLD_ID],
				request[GatewayAPI.KEY_CHAR_ID],
				str(request.get("__ip__", "")),
			)
		"public_leaderboards":
			gateway_response.rpc_id(
				gateway_id,
				request_id,
				world_manager.public_leaderboards()
			)
		"premium_balance":
			gateway_response.rpc_id(
				gateway_id,
				request_id,
				premium_balance_request(str(request.get("user_id", "")))
			)
		"premium_purchase":
			gateway_response.rpc_id(
				gateway_id,
				request_id,
				premium_purchase_request(request)
			)
		"premium_credit":
			gateway_response.rpc_id(
				gateway_id,
				request_id,
				premium_credit_request(request)
			)
		"account_exists":
			gateway_response.rpc_id(
				gateway_id,
				request_id,
				account_exists_request(str(request.get("user_id", "")))
			)
		"resolve_character":
			# Answers on the world's reply, not here - see the function.
			resolve_character_request(
				gateway_id,
				request_id,
				str(request.get("name", ""))
			)


@rpc("authority", "call_remote")
func gateway_response(request_id: int, response: Dictionary) -> void:
	pass


@rpc("authority")
func update_worlds_info(_worlds_info: Dictionary) -> void:
	pass


func login_request(username: String, password: String) -> Dictionary:
	var account: AccountResource = authentication_manager.validate_credentials(
		username, password
	)

	if not account:
		return {"error": GatewayAPI.ERR_BAD_CREDENTIALS}
	elif account.peer_id:
		# Last-login-wins. peer_id marks the account connected, but the ONLY thing
		# that clears it is a world-side game-peer disconnect (player_disconnected).
		# A drop during the world handoff (token issued, client never reached the
		# world) or a world crash leaves no peer to disconnect, orphaning the flag —
		# every later login is then refused forever (the reported permanent lockout).
		# So don't refuse: boot any still-live session on the player's last world
		# (character ids are per-world, so resolve the world by name first), then
		# free the account and let this fresh login proceed.
		var prev_world_id: int = world_manager.world_id_by_name(account.last_world_name)
		if prev_world_id != 0:
			world_manager.tell_world_to_kick(prev_world_id, account.last_character_id)
		account.peer_id = 0
		authentication_manager.active_accounts.erase(account.username)

	authentication_manager.active_accounts[account.username] = account

	# Check if latest world is online (needs rework)
	var last_connected_world_online: bool = false
	for world_id: int in world_manager.connected_worlds:
		if world_manager.connected_worlds.get(world_id, {}).get("info", {}).get("name", "") == account.last_world_name:
			last_connected_world_online = true
	if not last_connected_world_online:
		account.last_world_name = ""

	return {
		"name": account.username,
		"id": account.id,
		"world_name": account.last_world_name,
		"character_id": account.last_character_id,
		"w": world_manager.get_public_worlds()
	}


func create_account_request(username: String, password: String, is_guest: bool) -> Dictionary:
	var result_code: int
	var return_data: Dictionary
	var result: AccountResource = authentication_manager.create_account(username, password, is_guest)
	if result == null:
		result_code = GatewayAPI.ERR_ACCOUNT_CREATE_FAILED
		return_data = {"error": result_code, "msg": "Couldn't create account."}
	else:
		return_data = {
			"name": result.username,
			"id": result.id,
			"w": world_manager.get_public_worlds()
		}
	return return_data


func create_player_character_request(
	gateway_id: int,
	request_id: int,
	username: String,
	character_data: Dictionary,
	world_id: int,
	client_ip: String = ""
) -> void:
	var account: AccountResource = authentication_manager.account_collection.collection.get(username)
	if not account:
		gateway_response.rpc_id(gateway_id, request_id, {"error": GatewayAPI.ERR_BAD_CREDENTIALS, "msg": "account not found."})
		return
	if not world_manager.connected_worlds.has(world_id):
		gateway_response.rpc_id(gateway_id, request_id, {"error": GatewayAPI.ERR_BAD_CREDENTIALS, "msg": "world not found."})
		return
	world_manager.create_player_character_request.rpc_id(
		world_id, gateway_id, request_id, account.username, character_data, client_ip
	)


func request_player_characters(gateway_id: int, request_id: int, username: String, world_id: int) -> void:
	if (
		world_manager.connected_worlds.has(world_id)
		and authentication_manager.account_collection.collection.has(username)
	):
		var account: AccountResource = authentication_manager.account_collection.collection[username]
		world_manager.request_player_characters.rpc_id(
			world_id,
			gateway_id,
			request_id,
			username,
		)
	else:
		gateway_response.rpc_id(gateway_id, request_id, {"error": GatewayAPI.ERR_BAD_CREDENTIALS, "msg": "account not found or world."})


func request_enter_world(
	gateway_id: int,
	request_id: int,
	username: String,
	world_id: int,
	character_id: int,
	client_ip: String = ""
) -> void:
	var account: AccountResource = authentication_manager.account_collection.collection.get(username)

	if not world_manager.connected_worlds.has(world_id):
		return

	account.last_world_name = world_manager.connected_worlds[world_id].get("info", {}).get("name", "")
	account.last_character_id = character_id
	# Persist on every world-enter, not just debug — release builds must keep the
	# "continue on last world" metadata too. (Was gated on "debug".)
	authentication_manager.save_account_collection()

	world_manager.request_login.rpc_id(
		world_id,
		gateway_id,
		request_id,
		username,
		character_id,
		client_ip
	)


#region Premium currency
## Which account owns the character called [param name]?
##
## ANSWERS LATER, NOT HERE. Characters live in the world's database, not this
## one, so this forwards to a world and the world replies straight back through
## [MasterWorldServer.receive_account_for_character] using the same request_id.
## The only reply this function sends itself is the failure one, for when there
## is no world to ask.
##
## ANY connected world will do. Character names are unique inside a world
## database and there is one world; if that ever stops being true this picks the
## first, and the fix is to ask the world the buyer plays on rather than to make
## this smarter.
func resolve_character_request(gateway_id: int, request_id: int, name: String) -> void:
	var display_name: String = name.strip_edges()
	if display_name.is_empty():
		gateway_response.rpc_id(gateway_id, request_id, {"ok": false, "reason": "bad_args"})
		return
	for world_id: int in world_manager.connected_worlds:
		world_manager.request_account_for_character.rpc_id(
			world_id, gateway_id, request_id, display_name
		)
		return
	# No world is up. NOT "no such character" - the caller gates a payment on
	# this and must be able to tell the two apart.
	gateway_response.rpc_id(gateway_id, request_id, {"ok": false, "reason": "no_world"})


## Does this account name exist? Asked by the PUBLIC /v1/account/check route,
## which the storefront uses to refuse a payment aimed at a name nobody can log
## into - the mistake that strands money and needs a human to unpick.
##
## Deliberately narrower than [method AuthenticationManager.username_exists] is
## capable of: a bool and nothing else. No character list, no balance, no
## "exists but banned" - the caller is an anonymous web page, and every extra
## field would be a fact about somebody else's account given away for free.
func account_exists_request(user_id: String) -> Dictionary:
	if authentication_manager == null:
		return {"ok": false, "reason": "unavailable"}
	var account: String = user_id.strip_edges().to_lower()
	if account.is_empty():
		return {"ok": false, "reason": "bad_args"}
	return {"ok": true, "exists": authentication_manager.username_exists(account)}


## Balance for an account. Unknown account is NOT an error - a name that has
## never bought anything and a name that does not exist both have nothing, and
## telling the caller which is which would turn this into an account oracle.
func premium_balance_request(user_id: String) -> Dictionary:
	if premium_database == null or premium_database.store == null:
		return {"ok": false, "reason": "unavailable"}
	var account: String = user_id.strip_edges().to_lower()
	if account.is_empty():
		return {"ok": false, "reason": "bad_args"}
	return {"ok": true, "balance": premium_database.store.balance_of(account)}


## Settle a purchase. THE PRICE IS RE-DERIVED HERE, NOT TRUSTED.
##
## The world sends what it believes the item costs, and this re-resolves the same
## token through [PremiumCatalog] and compares. A world running an older build,
## or a compromised one, therefore cannot set its own prices - the worst it can
## do is be refused. That check is the entire reason this endpoint takes a `cost`
## at all rather than silently charging whatever the catalog says: a mismatch is
## a real disagreement worth surfacing, not something to paper over.
func premium_purchase_request(request: Dictionary) -> Dictionary:
	if premium_database == null or premium_database.store == null:
		return {"ok": false, "reason": "unavailable"}

	var account: String = str(request.get("user_id", "")).strip_edges().to_lower()
	var item_id: String = str(request.get("item_id", "")).strip_edges()
	var transaction_id: String = str(request.get("transaction_id", "")).strip_edges()
	var claimed_cost: int = int(request.get("cost", 0))
	if account.is_empty() or item_id.is_empty() or transaction_id.is_empty():
		return {"ok": false, "reason": "bad_args"}

	# The account must exist. Unlike the balance read, a purchase against an
	# unknown name is a real fault - it means the world handed us something that
	# is not one of our accounts - and silently minting a wallet for it would
	# hide that.
	if authentication_manager == null or not authentication_manager.username_exists(account):
		return {"ok": false, "reason": "unknown_account"}

	var entry: Dictionary = PremiumCatalog.resolve(item_id)
	if entry.is_empty():
		return {"ok": false, "reason": "unknown_item"}
	var true_cost: int = int(entry.get("cost", 0))
	if true_cost <= 0:
		return {"ok": false, "reason": "unknown_item"}
	if claimed_cost != true_cost:
		ServerLog.warn(
			"Premium purchase %s for '%s' claimed cost %d, catalog says %d - refusing."
				% [transaction_id, item_id, claimed_cost, true_cost]
		)
		return {"ok": false, "reason": "price_mismatch", "cost": true_cost}

	var result: Dictionary = premium_database.store.debit(
		account, item_id, true_cost, transaction_id
	)
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"reason": str(result.get("reason", "rejected")),
			"balance": int(result.get("balance", 0)),
		}
	if bool(result.get("duplicate", false)):
		# Already settled. Reported up so the HTTP layer can answer 409 while
		# still handing back the real balance - a replay must not look like a
		# second charge OR like a fresh success.
		return {
			"ok": true,
			"duplicate": true,
			"balance": int(result.get("balance", 0)),
		}

	ServerLog.info(
		"Premium: %s spent %d on '%s' (tx %s), balance now %d."
			% [account, true_cost, item_id, transaction_id, int(result.get("balance", 0))]
	)
	return {"ok": true, "duplicate": false, "balance": int(result.get("balance", 0))}

## Add coins to an account. The caller is the gateway, having already verified a
## Stripe signature - this does not re-check that, because it cannot: the raw
## body does not survive the RPC hop and re-signing it here would prove nothing.
## What it DOES enforce is that the account exists and that the credit is
## idempotent on transaction_id (the Stripe event id), so a re-delivered webhook
## adds nothing the second time.
func premium_credit_request(request: Dictionary) -> Dictionary:
	if premium_database == null or premium_database.store == null:
		return {"ok": false, "reason": "unavailable"}

	var account: String = str(request.get("user_id", "")).strip_edges().to_lower()
	var amount: int = int(request.get("amount", 0))
	var transaction_id: String = str(request.get("transaction_id", "")).strip_edges()
	var reason: String = str(request.get("reason", "stripe")).strip_edges()
	if account.is_empty() or transaction_id.is_empty() or amount <= 0:
		return {"ok": false, "reason": "bad_args"}

	# A payment naming an account that does not exist is a typo in a checkout
	# field. Minting a wallet for it would hide the problem and strand the money
	# somewhere nobody can log in to.
	if authentication_manager == null or not authentication_manager.username_exists(account):
		return {"ok": false, "reason": "unknown_account"}

	var result: Dictionary = premium_database.store.credit(
		account, amount, transaction_id, reason
	)
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason": str(result.get("reason", "failed"))}
	if not bool(result.get("duplicate", false)):
		ServerLog.info(
			"Premium: credited %d to %s (%s, tx %s); balance now %d."
				% [amount, account, reason, transaction_id, int(result.get("balance", 0))]
		)
	return {
		"ok": true,
		"duplicate": bool(result.get("duplicate", false)),
		"balance": int(result.get("balance", 0)),
	}
#endregion
