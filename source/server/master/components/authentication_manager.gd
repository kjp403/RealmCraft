class_name AuthenticationManager
extends Node


const LEGACY_ACCOUNT_COLLECTION: String = "res://source/server/master/account_collection.tres"
const USER_ACCOUNT_COLLECTION: String = "user://master/account_collection.tres"

var account_collection: AccountResourceCollection
## Durable account store. Live/export → user://master/ (survives git deploys).
## Local editor/dev without --env=live → res:// for convenience.
## NEVER key this off OS.has_feature("editor") alone — the VPS uses the editor binary.
var account_collection_path: String:
	get:
		if ServerEnvironment.use_user_data_paths():
			return USER_ACCOUNT_COLLECTION
		return LEGACY_ACCOUNT_COLLECTION
var active_accounts: Dictionary[StringName, AccountResource]


func _ready() -> void:
	tree_exiting.connect(save_account_collection)
	load_account_collection()


# Cryptographically-secure random token (256 bits, hex-encoded → 64 chars). Used
# for world-handoff auth tokens and guest passwords; both need to be unguessable.
func generate_random_token() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()


func create_account(username: String, password: String, is_guest: bool) -> AccountResource:
	# Guest login is permanently disabled — guestN names previously matched
	# server_admins.cfg entries and granted free senior_admin.
	if is_guest:
		push_warning("Guest account creation is disabled.")
		return null
	# Account names are case-insensitive (like Discord) so "John" and "john"
	# can't both exist. Normalize to lowercase before any lookup / storage.
	username = username.strip_edges().to_lower()
	if username_exists(username):
		return null
	# Refuse guest* usernames even via normal registration — they used to be
	# auto-admin via a bad server_admins.cfg entry.
	if username.begins_with("guest") and username.substr(5).is_valid_int():
		push_warning("Refusing reserved guest* account name: %s" % username)
		return null
	var account_id: int = account_collection.get_new_account_id()
	# Store only a salted, key-stretched hash — never the plaintext password.
	var new_account: AccountResource = AccountResource.new()
	new_account.init(account_id, username, PasswordHasher.hash_password(password))
	account_collection.collection[username] = new_account
	# Save on disk should only occur at specific times.
	# Temporary work around for debug purpose.
	save_account_collection()
	return new_account


func load_account_collection() -> void:
	if ServerEnvironment.use_user_data_paths():
		ServerEnvironment.migrate_file_if_needed(USER_ACCOUNT_COLLECTION, LEGACY_ACCOUNT_COLLECTION)
	if ResourceLoader.exists(account_collection_path):
		account_collection = ResourceLoader.load(account_collection_path)
	else:
		account_collection = AccountResourceCollection.new()


func save_account_collection() -> void:
	if ServerEnvironment.use_user_data_paths():
		DirAccess.make_dir_recursive_absolute("user://master")
	ResourceSaver.save(account_collection, account_collection_path)


func username_exists(username: String) -> bool:
	return account_collection.collection.has(username.strip_edges().to_lower())


func validate_credentials(username: String, password: String) -> AccountResource:
	# Case-insensitive lookup to match create_account's lowercase normalization.
	username = username.strip_edges().to_lower()
	var account: AccountResource = null
	if account_collection.collection.has(username):
		account = account_collection.collection[username]
		if PasswordHasher.verify(password, account.password):
			return account
	return null
