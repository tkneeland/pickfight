extends Node

## Host-side input transport for phone controllers (ADR-0001, ADR-0002).
##
## Runs two TCP listeners, polled from `_process`:
##
##   * `http_port` (8080) serves `res://controller/index.html` — the controller
##     page a player opens on their phone.
##   * `ws_port` (8081) accepts WebSocket connections from that page and binds
##     each one to a player slot in join order.
##
## Two ports rather than one because `StreamPeerTCP` cannot peek: once bytes
## are read to route an HTTP request they are consumed, and
## `WebSocketPeer.accept_stream` has to read the handshake itself.
##
## Wire format phone -> host: one binary frame per controller frame, exactly
## 8 bytes, `float32 x` then `float32 y`, little-endian, unit-disc normalised.
## Wire format host -> phone: one text frame `{"slot":<i>}` sent on bind.
##
## Run the host with `-- --log-input` to print every decoded packet and every
## bind/unbind; the automated checks assert on those lines.

const PAGE_PATH: String = "res://controller/index.html"
const WS_PORT_TOKEN: String = "__WS_PORT__"
const MAX_HEADER_BYTES: int = 8192
const PACKET_SIZE: int = 8
const ANGLE_LOG_EPSILON: float = 0.0005
const LENGTH_LOG_EPSILON: float = 0.05

@export var http_port: int = 8080
@export var ws_port: int = 8081
@export var players: Array[NodePath] = []
@export var join_label_path: NodePath

## One pending HTTP request: the socket plus the bytes read so far.
class HttpConn extends RefCounted:
	var tcp: StreamPeerTCP
	var buf: PackedByteArray = PackedByteArray()

	func _init(p_tcp: StreamPeerTCP) -> void:
		tcp = p_tcp

var log_input: bool = false

var _http_server: TCPServer = TCPServer.new()
var _ws_server: TCPServer = TCPServer.new()
var _http_clients: Array[HttpConn] = []
var _pending: Array[WebSocketPeer] = []

# Untyped on purpose: elements are `Player` nodes and GDScript's analyser
# would reject `set_input_vector` on a statically typed `Node`.
var _players: Array = []
var _slot_peers: Array[WebSocketPeer] = []
var _last_arm: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	log_input = OS.get_cmdline_user_args().has("--log-input")

	for path in players:
		_players.append(get_node_or_null(path))
	_slot_peers.resize(_players.size())
	_last_arm.resize(_players.size())
	for i in _last_arm.size():
		_last_arm[i] = Vector2(NAN, NAN)

	var http_err: int = _http_server.listen(http_port)
	if http_err != OK:
		push_error("ControllerServer: cannot listen on HTTP port %d (error %d)" % [http_port, http_err])
	var ws_err: int = _ws_server.listen(ws_port)
	if ws_err != OK:
		push_error("ControllerServer: cannot listen on WebSocket port %d (error %d)" % [ws_port, ws_err])

	var urls: PackedStringArray = _join_urls()
	if urls.is_empty():
		print("ControllerServer: no non-loopback IPv4 address found; try http://127.0.0.1:%d/" % http_port)
	for url in urls:
		print("Controller page: %s" % url)

	var label: Label = get_node_or_null(join_label_path) as Label
	if label != null:
		label.text = "Join on your phone:\n" + ("\n".join(urls) if not urls.is_empty() else "http://127.0.0.1:%d/" % http_port)

func _process(_delta: float) -> void:
	_process_http()
	_process_websocket()

# --- HTTP -------------------------------------------------------------------

func _join_urls() -> PackedStringArray:
	var urls: PackedStringArray = PackedStringArray()
	for addr: String in IP.get_local_addresses():
		if addr.contains(":"):
			continue # IPv6
		if addr.begins_with("127."):
			continue # loopback
		urls.append("http://%s:%d/" % [addr, http_port])
	return urls

func _process_http() -> void:
	while _http_server.is_connection_available():
		var tcp: StreamPeerTCP = _http_server.take_connection()
		if tcp == null:
			continue
		tcp.set_no_delay(true)
		_http_clients.append(HttpConn.new(tcp))

	# `Array[T].duplicate()` returns an untyped Array, so the loop variable has
	# to be typed explicitly or type inference inside the body fails to parse.
	for conn: HttpConn in _http_clients.duplicate():
		conn.tcp.poll()
		if conn.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_http_clients.erase(conn)
			continue

		var available: int = conn.tcp.get_available_bytes()
		if available > 0:
			var chunk: Array = conn.tcp.get_data(available)
			if chunk[0] == OK:
				conn.buf.append_array(chunk[1])

		if conn.buf.size() > MAX_HEADER_BYTES:
			conn.tcp.disconnect_from_host()
			_http_clients.erase(conn)
			continue

		var text: String = conn.buf.get_string_from_ascii()
		if not text.contains("\r\n\r\n"):
			continue

		_answer_http(conn, text.get_slice("\r\n", 0))
		conn.tcp.disconnect_from_host()
		_http_clients.erase(conn)

func _answer_http(conn: HttpConn, request_line: String) -> void:
	var parts: PackedStringArray = request_line.split(" ", false)
	var method: String = parts[0] if parts.size() > 0 else ""
	var target: String = parts[1] if parts.size() > 1 else ""
	var path: String = target.get_slice("?", 0)

	if method == "GET" and (path == "/" or path == "/index.html"):
		var page: String = _load_page()
		if page.is_empty():
			_send_http(conn, 500, "Internal Server Error", "text/plain; charset=utf-8", "controller page missing".to_utf8_buffer())
			return
		_send_http(conn, 200, "OK", "text/html; charset=utf-8", page.to_utf8_buffer())
		return

	_send_http(conn, 404, "Not Found", "text/plain; charset=utf-8", "404 Not Found".to_utf8_buffer())

## Read from disk on every request, so the page can be tuned (drag radius, feel)
## without restarting the host.
func _load_page() -> String:
	var file: FileAccess = FileAccess.open(PAGE_PATH, FileAccess.READ)
	if file == null:
		push_error("ControllerServer: cannot open %s" % PAGE_PATH)
		return ""
	var html: String = file.get_as_text()
	file.close()
	return html.replace(WS_PORT_TOKEN, str(ws_port))

func _send_http(conn: HttpConn, code: int, reason: String, content_type: String, body: PackedByteArray) -> void:
	var header: String = "HTTP/1.1 %d %s\r\n" % [code, reason]
	header += "Content-Type: %s\r\n" % content_type
	header += "Content-Length: %d\r\n" % body.size()
	header += "Cache-Control: no-store\r\n"
	header += "Connection: close\r\n\r\n"
	var out: PackedByteArray = header.to_utf8_buffer()
	out.append_array(body)
	conn.tcp.put_data(out)

# --- WebSocket --------------------------------------------------------------

func _process_websocket() -> void:
	while _ws_server.is_connection_available():
		var tcp: StreamPeerTCP = _ws_server.take_connection()
		if tcp == null:
			continue
		tcp.set_no_delay(true)
		var peer: WebSocketPeer = WebSocketPeer.new()
		if peer.accept_stream(tcp) == OK:
			_pending.append(peer)

	for peer: WebSocketPeer in _pending.duplicate():
		peer.poll()
		var state: int = peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_pending.erase(peer)
			_bind(peer)
		elif state == WebSocketPeer.STATE_CLOSED:
			_pending.erase(peer)

	for slot in _slot_peers.size():
		var peer: WebSocketPeer = _slot_peers[slot]
		if peer == null:
			continue
		peer.poll()
		var state: int = peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_drain(slot, peer)
		elif state == WebSocketPeer.STATE_CLOSED:
			_unbind(slot)
			continue
		_log_arm(slot)

## Bind to the lowest free slot; refuse the connection when every player is
## already driven by a controller.
func _bind(peer: WebSocketPeer) -> void:
	for slot in _slot_peers.size():
		if _slot_peers[slot] != null:
			continue
		if _players[slot] == null:
			continue
		_slot_peers[slot] = peer
		_last_arm[slot] = Vector2(NAN, NAN)
		_players[slot].bind_controller()
		peer.send_text(JSON.stringify({"slot": slot}))
		if log_input:
			print("slot %d bound" % slot)
		return
	peer.close(1000, "no free player slot")
	if log_input:
		print("controller refused: no free player slot")

func _unbind(slot: int) -> void:
	_slot_peers[slot] = null
	_last_arm[slot] = Vector2(NAN, NAN)
	if _players[slot] != null:
		_players[slot].unbind_controller()
	if log_input:
		print("slot %d unbound" % slot)

## Latest value wins: drain everything queued this frame and keep only the last
## well-formed packet, so a burst never replays stale input.
func _drain(slot: int, peer: WebSocketPeer) -> void:
	var latest: PackedByteArray = PackedByteArray()
	var got: bool = false
	while peer.get_available_packet_count() > 0:
		var pkt: PackedByteArray = peer.get_packet()
		if pkt.size() != PACKET_SIZE:
			continue
		latest = pkt
		got = true
	if not got:
		return
	var v: Vector2 = Vector2(latest.decode_float(0), latest.decode_float(4))
	_players[slot].set_input_vector(v)
	if log_input:
		print("slot=%d v=(%.4f, %.4f)" % [slot, v.x, v.y])

## Report the arm the host actually produced, so direction/reach/release can be
## observed without reaching into Player's internals.
func _log_arm(slot: int) -> void:
	if not log_input:
		return
	var player: Variant = _players[slot]
	if player == null:
		return
	var current: Vector2 = Vector2(player.arm_angle, player.arm_length)
	var previous: Vector2 = _last_arm[slot]
	if is_finite(previous.x) and absf(current.x - previous.x) < ANGLE_LOG_EPSILON and absf(current.y - previous.y) < LENGTH_LOG_EPSILON:
		return
	_last_arm[slot] = current
	print("slot=%d arm angle=%.4f len=%.1f" % [slot, current.x, current.y])
