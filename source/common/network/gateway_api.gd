class_name GatewayAPI

## Shared keys (client + gateway)
const KEY_REQUEST_ID: String = "r-id"
const KEY_TOKEN_ID: String = "t-id"
const KEY_ACCOUNT_ID: String = "a-id"
const KEY_ACCOUNT_USERNAME: String = "a-u"
const KEY_ACCOUNT_PASSWORD: String  = "a-p"
const KEY_WORLD_ID: String = "w-id"
const KEY_CHAR_ID: String = "c-id"
## Client build version (the project's config/version), sent on login so an
## outdated client gets a clear "please update" message instead of failing deeper.
const KEY_CLIENT_VERSION: String = "c-v"


## Auth/gateway error codes (server → client). Kept here so client and server
## agree on the numbers; the client maps them to localized text in GatewayError.
## Anything not listed falls back to a generic "please try again" on the client.
const ERR_GENERIC: int = 1
const ERR_ACCOUNT_CREATE_FAILED: int = 30
const ERR_BAD_CREDENTIALS: int = 50
const ERR_ALREADY_CONNECTED: int = 51
const ERR_RATE_LIMITED: int = 60
## Guest login endpoint is permanently disabled.
const ERR_GUEST_DISABLED: int = 61
## Client build is below the server's min_client_version (or newer than the
## server). The boot handshake (and login) return this so the client can show a
## hard "please update" instead of letting them in.
const ERR_OUTDATED_VERSION: int = 70


## This build's version, from project.godot's application/config/version. Same
## call returns the client's version on the client and the server's on the server.
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Oldest client build the gateway still accepts. Defaults to [method game_version]
## (exact match) when unset. Set application/config/min_client_version when the
## live server must accept the currently published itch build during a release lag.
static func min_client_version() -> String:
	var configured: String = str(
		ProjectSettings.get_setting("application/config/min_client_version", "")
	).strip_edges()
	if configured.is_empty():
		return game_version()
	return configured


## Compare dotted numeric versions (e.g. 0.28.63). Returns -1 / 0 / 1.
static func compare_versions(a: String, b: String) -> int:
	var a_parts: PackedStringArray = a.strip_edges().split(".")
	var b_parts: PackedStringArray = b.strip_edges().split(".")
	var n: int = maxi(a_parts.size(), b_parts.size())
	for i in range(n):
		var av: int = int(a_parts[i]) if i < a_parts.size() else 0
		var bv: int = int(b_parts[i]) if i < b_parts.size() else 0
		if av < bv:
			return -1
		if av > bv:
			return 1
	return 0

const ACTION_LOGIN := "login"
const ACTION_CREATE_ACCOUNT := "create_account"
const ACTION_CREATE_CHARACTER := "create_character"
const ACTION_LIST_CHARACTERS := "list_characters"
const ACTION_ENTER_WORLD := "enter_world"
const ACTION_DISCONNECT := "disconnect"

const ALPHA_CLIENT_CONFIG_FILENAME: String = "arkenelle_client.cfg"

static var _cached_base_url: String = ""


static func base_url() -> String:
	# A command-line override is useful for local diagnostics and automated tests.
	# Keep it ahead of build features so a release client can be redirected without
	# recompiling it.
	var command_line_url: String = str(CmdlineUtils.get_parsed_args().get("api", "")).strip_edges()
	if not command_line_url.is_empty():
		return command_line_url

	# Private-alpha builds read their gateway from a small file beside the EXE.
	# Test hosts can therefore change their Tailscale IP without distributing a
	# new binary. Do not silently fall through to the legacy production service.
	if OS.has_feature("arkenelle_alpha"):
		if not _cached_base_url.is_empty():
			return _cached_base_url
		var config_path: String = OS.get_executable_path().get_base_dir().path_join(
			ALPHA_CLIENT_CONFIG_FILENAME
		)
		var config_file := ConfigFile.new()
		var error: Error = config_file.load(config_path)
		if error == OK:
			var configured_url: String = str(
				config_file.get_value("network", "gateway_url", "")
			).strip_edges().rstrip("/")
			if configured_url.begins_with("http://") or configured_url.begins_with("https://"):
				_cached_base_url = configured_url
				return _cached_base_url
		push_error(
			"Arkenelle Alpha requires [network] gateway_url in %s (http:// or https://)." % config_path
		)
		return "http://127.0.0.1:8088"

	if OS.has_feature("arkenelle") or OS.has_feature("release"):
		return "https://api.arkenelle.com"
	return "http://127.0.0.1:8088"


static func get_endpoint(path: String) -> String:
	return "%s%s" % [base_url().rstrip("/"), path]


# Endpoints
static func login() -> String:
	return get_endpoint("/v1/login")


static func guest() -> String:
	return get_endpoint("/v1/guest")


static func worlds() -> String:
	return get_endpoint("/v1/worlds")


## Lightweight boot healthcheck (no auth): is the gateway reachable + master up, and
## does this build match the server's? Called before the gateway shows any menu.
static func handshake() -> String:
	return get_endpoint("/v1/handshake")


static func account_create() -> String:
	return get_endpoint("/v1/account/create")


static func world_characters() -> String:
	return get_endpoint("/v1/world/characters")


static func world_enter() -> String:
	return get_endpoint("/v1/world/enter")


static func world_create_char() -> String:
	return get_endpoint("/v1/world/character/create")
