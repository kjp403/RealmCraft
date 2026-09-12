extends Node
#class_name HTTPServer


const HttpRouter: GDScript = preload("res://addons/httpserver/http_router.gd")

const DEFAULT_BIND_ADDRESS: String = "127.0.0.1"
const MAX_REQUEST_BYTES: int = 1024 * 1024 # 1 MiB safety cap

var server: TCPServer
var router: HttpRouter

var current_connections: Array[StreamPeerTCP]

## Partial requests, keyed by connection instance id.
##
## WHY THIS EXISTS. A poll tick reads whatever bytes have arrived, and TCP
## makes no promise that a request is one of them. The old code took that one
## read, and if it did not already contain a complete request it returned -
## having ALREADY CONSUMED the bytes. The next tick then saw the remainder
## with no request line, and the body was gone for good. Small requests from
## Godot's own HTTPRequest happened to arrive whole, which is why this was
## never noticed; anything larger, or any client that writes headers and body
## separately, silently lost its body and read as an empty payload.
##
## That is survivable for a peddler snapshot. It is not survivable for a
## payment webhook, where a dropped body means a player paid and got nothing.
var _buffers: Dictionary[int, PackedByteArray] = {}


func _ready() -> void:
	server = TCPServer.new()
	router = HttpRouter.new()


func _physics_process(delta: float) -> void:
	if server.is_connection_available():
		var connection: StreamPeerTCP = server.take_connection()
		current_connections.append(connection)
	for connection: StreamPeerTCP in current_connections:
		handle_connection(connection)


func listen(port: int, bind_address: String = "*") -> void:
	server.listen(port, bind_address)


func close_connection(connection: StreamPeerTCP) -> void:
	_buffers.erase(connection.get_instance_id())
	connection.disconnect_from_host()
	current_connections.erase(connection)


func handle_connection(connection: StreamPeerTCP) -> void:
	# Update status
	connection.poll()
	# Get and Check status
	var status: StreamPeerTCP.Status = connection.get_status()
	if status == StreamPeerTCP.Status.STATUS_NONE or status == StreamPeerTCP.Status.STATUS_ERROR:
		_buffers.erase(connection.get_instance_id())
		current_connections.erase(connection)
		return
	if status == StreamPeerTCP.Status.STATUS_CONNECTING:
		return

	# Append whatever arrived to this connection's buffer, then decide whether a
	# COMPLETE request is in hand. Bytes are never dropped on an incomplete read.
	var key: int = connection.get_instance_id()
	var available_bytes: int = connection.get_available_bytes()
	if available_bytes > 0:
		var chunk: Array = connection.get_data(available_bytes)
		if int(chunk[0]) == OK:
			var buffered: PackedByteArray = _buffers.get(key, PackedByteArray())
			buffered.append_array(chunk[1] as PackedByteArray)
			_buffers[key] = buffered

	var raw: PackedByteArray = _buffers.get(key, PackedByteArray())
	if raw.is_empty():
		return
	if raw.size() > MAX_REQUEST_BYTES:
		close_connection(connection)
		return

	# Split on the header terminator in BYTES, not in a decoded string: a body cut
	# mid-UTF-8 decodes to something that is not the bytes that were sent, and a
	# webhook signature is computed over the bytes.
	var split_at: int = _find_header_end(raw)
	if split_at == -1:
		return # headers still arriving

	var headers: String = raw.slice(0, split_at).get_string_from_utf8()
	if headers.is_empty():
		close_connection(connection)
		return
	var body_bytes: PackedByteArray = raw.slice(split_at + 4)
	var expected_body: int = _content_length(headers)
	if body_bytes.size() < expected_body:
		return # body still arriving - wait for the rest rather than eating it

	# Complete. The buffer is no longer needed and must go before any early return
	# below, or a malformed request pins its bytes for the life of the process.
	_buffers.erase(key)
	var as_string: String = headers

	var header: PackedStringArray = headers.get_slice("\r\n", 0).split(" ")

	var method_str: String = header[0]
	var method: HTTPClient.Method = HTTPClient.Method.METHOD_GET

	match method_str:
		"GET":
			method = HTTPClient.Method.METHOD_GET
		"HEAD":
			method = HTTPClient.Method.METHOD_HEAD
		"POST":
			method = HTTPClient.Method.METHOD_POST
		"PUT":
			method = HTTPClient.Method.METHOD_PUT
		"DELETE":
			method = HTTPClient.Method.METHOD_DELETE
		"OPTIONS":
			method = HTTPClient.Method.METHOD_OPTIONS
	
	# Hardcoded CORS handler
	if method == HTTPClient.Method.METHOD_OPTIONS:
		http_send(connection, {}, HTTPClient.ResponseCode.RESPONSE_OK)
		close_connection(connection)
		return

	# Split URL into path + query string. The browser sends ?token=...&other=...
	# on GETs; we feed both query string and JSON body into the same payload so
	# handlers don't have to care which transport carried each field.
	var raw_url: String = header[1]
	var path: String = raw_url.get_slice("?", 0)
	var query_string: String = raw_url.get_slice("?", 1) if raw_url.contains("?") else ""

	var payload: Dictionary = {}

	# Body (JSON) first — typical for POST/PUT.
	var body: String = body_bytes.get_string_from_utf8()
	if body.strip_edges() != "":
		var parsed: Variant = JSON.parse_string(body)
		if typeof(parsed) == TYPE_DICTIONARY:
			payload = parsed

	# Query string layered on top so ?token=abc reaches the handler. Body
	# values win on collision because body is the more explicit channel.
	if not query_string.is_empty():
		for pair: String in query_string.split("&"):
			var kv: PackedStringArray = pair.split("=", true, 1)
			if kv.is_empty() or kv[0].is_empty():
				continue
			var k: String = kv[0].uri_decode()
			var v: String = kv[1].uri_decode() if kv.size() == 2 else ""
			if not payload.has(k):
				payload[k] = v

	payload["__path__"] = path
	# Client IP for per-IP rate-limiting (AuthRateLimiter). Behind the reverse proxy
	# the socket host is always the proxy (loopback), so prefer the X-Real-IP header
	# Caddy stamps with the real client (header_up overwrites any client-sent value,
	# so it can't be spoofed). Falls back to the socket host for direct / local dev.
	payload["__ip__"] = _header_value(headers, "x-real-ip", connection.get_connected_host())
	# Authorization header, for routes that authenticate a SERVER rather than a
	# player session (the world server posting its peddler snapshot). Stamped the
	# same way as __ip__ so a handler never has to parse the raw request, and
	# under a reserved key so a client cannot forge it through the body or the
	# query string — those are merged above, this is written after.
	payload["__auth__"] = _header_value(headers, "authorization", "")
	# Idempotency-Key, stamped the same way and under the same kind of reserved
	# key, for routes that must settle a retried request exactly once. Written
	# after the body/query merge so a client cannot forge it through either.
	payload["__idempotency_key__"] = _header_value(headers, "idempotency-key", "")
	# The body EXACTLY as it arrived. A webhook signature is an HMAC over these
	# bytes, so re-serialising the parsed Dictionary would not reproduce it -
	# key order, spacing and number formatting would all differ. Only routes
	# that verify a signature should read this.
	payload["__raw_body__"] = body
	# The whole header block, for routes that need a header this server does not
	# stamp individually (a webhook signature, say). Handlers read it with
	# header_of(); parsing it here for every request would cost every route for
	# the benefit of one.
	payload["__headers__"] = headers

	# Try a registered route first. Static fallback only fires when no route
	# matched, so API paths can use any prefix without colliding with the
	# static handler (the old hard-coded "/v1/" carve-out is gone).
	var handler: Callable = router.find_route_handler(method, path)
	if handler.is_valid():
		var result: Dictionary = await handler.call(payload)
		if result.get("__raw__", false):
			var code: int = result.get("code", 200)
			var ct: String = result.get("content_type", "text/plain; charset=utf-8")
			var _body: PackedByteArray = result.get("body", PackedByteArray())
			http_send_bytes(connection, _body, code, ct)
		else:
			http_send(connection, result, HTTPClient.ResponseCode.RESPONSE_OK)
		close_connection(connection)
		return

	# No route matched — try static (GET only).
	if _try_serve_static(connection, method, path):
		close_connection(connection)
		return

	# Nothing matched.
	http_send(connection, {"ok": false, "error": "not_found"}, HTTPClient.ResponseCode.RESPONSE_NOT_FOUND)
	close_connection(connection)


## Byte offset of the CRLFCRLF that ends the header block, or -1 while it is
## still arriving.
func _find_header_end(raw: PackedByteArray) -> int:
	for i: int in range(0, maxi(0, raw.size() - 3)):
		if raw[i] == 13 and raw[i + 1] == 10 and raw[i + 2] == 13 and raw[i + 3] == 10:
			return i
	return -1


## Declared body length, or 0 when the header is absent or unparseable. A
## request with no Content-Length is treated as having no body, which is
## correct for the GETs this serves; chunked encoding is not supported and
## nothing that talks to this server uses it.
func _content_length(header_block: String) -> int:
	var raw_value: String = _header_value(header_block, "content-length", "")
	if not raw_value.is_valid_int():
		return 0
	return maxi(0, raw_value.to_int())


## Case-insensitive lookup of a request header value in the raw header block (the
## text before the blank line), or `fallback` if the header is absent / empty.
## `lower_name` must already be lower-case (e.g. "x-real-ip").
func _header_value(header_block: String, lower_name: String, fallback: String) -> String:
	for line: String in header_block.split("\r\n"):
		var colon: int = line.find(":")
		if colon != -1 and line.substr(0, colon).strip_edges().to_lower() == lower_name:
			var value: String = line.substr(colon + 1).strip_edges()
			if not value.is_empty():
				return value
	return fallback


func http_send(
	connection: StreamPeerTCP,
	payload: Dictionary,
	code: HTTPClient.ResponseCode
) -> void:
	## to_utf8_buffer for more support
	var body_buffer: PackedByteArray = JSON.stringify(payload).to_ascii_buffer()
	var headers: Dictionary = {
		"Content-Type": "application/json",
		"Content-Length": body_buffer.size(),
		"Connection": "close",

		# CORS
		"Access-Control-Allow-Origin": "*",
		"Access-Control-Allow-Methods": "POST, GET, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type"
	}
	var header_to_buffer: String = "HTTP/1.1 %d OK\r\n" % code
	
	for header: String in headers:
		header_to_buffer += "%s: %s\r\n" % [header, str(headers[header])]
	header_to_buffer += "\r\n"
	
	# Header block
	connection.put_data(header_to_buffer.to_ascii_buffer())
	# Content/Body block
	connection.put_data(body_buffer)


func http_send_bytes(
	connection: StreamPeerTCP,
	body: PackedByteArray,
	code: int,
	content_type: String
) -> void:
	var headers: Dictionary = {
		"Content-Type": content_type,
		"Content-Length": body.size(),
		"Connection": "close",

		# CORS (optional)
		"Access-Control-Allow-Origin": "*",
		"Access-Control-Allow-Methods": "POST, GET, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type"
	}

	var header_to_buffer := "HTTP/1.1 %d OK\r\n" % code
	for header in headers.keys():
		header_to_buffer += "%s: %s\r\n" % [header, str(headers[header])]
	header_to_buffer += "\r\n"

	connection.put_data(header_to_buffer.to_ascii_buffer())
	connection.put_data(body)


func _mime_for(file_path: String) -> String:
	var ext: String = file_path.get_extension().to_lower()
	match ext:
		"html": return "text/html; charset=utf-8"
		"css": return "text/css; charset=utf-8"
		"js": return "application/javascript; charset=utf-8"
		"json": return "application/json; charset=utf-8"
		"png": return "image/png"
		"jpg", "jpeg": return "image/jpeg"
		"svg": return "image/svg+xml"
		"ico": return "image/x-icon"
		"woff": return "font/woff"
		"woff2": return "font/woff2"
		"ttf": return "font/ttf"
		_: return "application/octet-stream"


func _is_bad_path(req_path: String) -> bool:
	return req_path.contains("..") or req_path.contains("\\") or req_path.contains(":")


func _try_serve_static(connection: StreamPeerTCP, method: HTTPClient.Method, path: String) -> bool:
	if method != HTTPClient.Method.METHOD_GET:
		return false

	# Static is now a true fallback — routes are tried first in handle_connection,
	# so API paths under any prefix coexist with static-mounted directories
	# without an addon-level path carve-out.

	var best_prefix: String
	var best_mount: Dictionary

	for mount in router.static_mounts:
		var prefix: String = mount.get("prefix", "")
		if path.begins_with(prefix) and prefix.length() > best_prefix.length():
			best_prefix = prefix
			best_mount = mount

	if best_mount.is_empty():
		return false

	var rel_path: String
	if best_prefix == "/":
		rel_path = path
	else:
		# Remove the mount prefix; keep the remainder as a path
		rel_path = path.trim_prefix(best_prefix)

	if rel_path.is_empty() or rel_path == "/":
		rel_path = "/" + String(best_mount.get("index", "index.html"))

	if not rel_path.begins_with("/"):
		rel_path = "/" + rel_path

	if _is_bad_path(rel_path):
		http_send_bytes(connection, "Bad path".to_utf8_buffer(), 400, "text/plain; charset=utf-8")
		return true

	var base_dir: String = String(best_mount.get("dir", "")).trim_suffix("/")
	var file_path: String = base_dir.path_join(rel_path.trim_prefix("/"))

	if not FileAccess.file_exists(file_path):
		http_send_bytes(connection, "Not found".to_utf8_buffer(), 404, "text/plain; charset=utf-8")
		return true

	http_send_bytes(connection, FileAccess.get_file_as_bytes(file_path), 200, _mime_for(file_path))
	return true
