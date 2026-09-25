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
## Wire format host -> phone: one text frame `{"slot":<i>}` sent on bind, and
## a `{"t":"buzz","kind":<kind>}` text frame per `send_buzz()` (issue #34,
## ADR-0013).
##
## Liveness: a phone that screen-locks or leaves Wi-Fi mid-drag stops sending
## without ever closing the socket, and the last frame it sent was non-zero.
## Two defences, because neither alone is enough:
##
##   * WebSocket heartbeat (ping/pong) so a half-open TCP connection is
##     eventually detected by the socket layer.
##   * A per-slot input deadline (`controller_timeout_sec`): no well-formed
##     packet for that long and the controller is treated as gone — the
##     player's vector is zeroed so the weapon eases to rest, and the slot frees.
##
## Sockets that connect and never finish a request (speculative preconnect,
## port scanners, stalled handshakes) are dropped after
## `connection_timeout_sec` rather than being polled forever.
##
## Smoothing (issue #113): Wi-Fi delivers the phone's steady 60 Hz stream in
## clumps -- nothing for a frame, then two or three packets at once -- and
## "latest value wins" turns every clump into a jump, which makes the weapon
## twitch. Each slot's packets therefore set a target that the input vector
## follows with a short exponential ease (`INPUT_SMOOTHING_SEC`), stepped every
## frame. A release (a (0,0) packet) and a deliberate flick (a jump of at least
## `INPUT_FLICK_SNAP`) are passed through at once, never eased. Only packets
## go through this: a direct `Player.set_input_vector()` call is unsmoothed.
##
## Run the host with `-- --log-input` to print every decoded packet, every
## bind/unbind/timeout, and a periodic "weapon steady" line while a bound weapon is
## unchanged; the automated checks assert on those lines.

## A phone claimed `slot` fresh -- not a reconnect to a slot it already held.
## A sound hook (issue #75, ADR-0016); nothing in the game reads it.
signal player_joined(slot: int)

const PAGE_PATH: String = "res://controller/index.html"
const WS_PORT_TOKEN: String = "__WS_PORT__"
const MAX_HEADER_BYTES: int = 8192
const PACKET_SIZE: int = 8
## Every `kind` `send_buzz()` is sent with, strongest first; the controller
## page has a vibration pattern and a flash for each.
const BUZZ_KINDS: PackedStringArray = ["win", "eliminated", "struck", "hit"]
const ANGLE_LOG_EPSILON: float = 0.0005
const LENGTH_LOG_EPSILON: float = 0.05
## Time constant of the ease from the last applied input vector to the newest
## packet (issue #113). About 1.5 frames at 60 Hz: long enough to spread a
## clump of late packets over the frames they should have arrived in, short
## enough that a steady drag lags by only that much.
const INPUT_SMOOTHING_SEC: float = 0.025
## A packet at least this far (unit-disc units) from the current input is a
## deliberate flick and is applied at once rather than eased into.
const INPUT_FLICK_SNAP: float = 0.5
## Within this distance of its target the eased input snaps onto it, so a
## held drag reaches exactly what the phone sends.
const INPUT_SETTLE_EPSILON: float = 0.001
## Physics frames between "weapon steady" lines. Steadiness has to be provable
## from a line that is present, not from the absence of change lines.
const STEADY_LOG_FRAMES: int = 30
## Lower-cased substrings of an adapter's name that mark it as virtual, so its
## address is listed after real ones (see `_join_urls`).
const VIRTUAL_ADAPTER_HINTS: PackedStringArray = [
	"vethernet", "wsl", "hyper-v", "docker", "virtualbox", "vmware", "vbox",
	"tailscale", "zerotier", "wireguard", "openvpn", "tap-", "tun", "utun",
	"bridge", "virbr", "loopback",
]

## 0 on either port asks the OS for a free one; `_ready()` then writes the port
## it got back here, so readers (the join URL, the served page) see the real
## one. The scenario suite does this so parallel runs never collide (#73).
@export var http_port: int = 8080
@export var ws_port: int = 8081
@export var player_paths: Array[NodePath] = []
@export var join_label_path: NodePath
@export var qr_texture_path: NodePath
## No well-formed packet for this long and the bound controller is considered
## gone. Sized above a few dropped frames but well below "a player noticed".
@export var controller_timeout_sec: float = 2.0
## How long a socket may sit without completing an HTTP request or a WebSocket
## handshake before it is dropped.
@export var connection_timeout_sec: float = 5.0
## WebSocket ping interval. `WebSocketPeer` defaults this to 0.0 (no ping/pong
## at all), which is what lets a half-open connection look open forever.
@export var heartbeat_interval_sec: float = 1.0

## One pending HTTP request: the socket, the bytes read so far, and the point
## in time after which an unfinished request is abandoned.
class HttpConn extends RefCounted:
	var tcp: StreamPeerTCP
	var buf: PackedByteArray = PackedByteArray()
	var deadline_msec: int

	func _init(p_tcp: StreamPeerTCP, p_deadline_msec: int) -> void:
		tcp = p_tcp
		deadline_msec = p_deadline_msec

## One WebSocket connection between `accept_stream` and `STATE_OPEN`, with the
## point in time after which an unfinished handshake is abandoned.
class PendingConn extends RefCounted:
	var peer: WebSocketPeer
	var deadline_msec: int

	func _init(p_peer: WebSocketPeer, p_deadline_msec: int) -> void:
		peer = p_peer
		deadline_msec = p_deadline_msec

## One slot's input smoothing (issue #113; see the header). `push()` takes a
## packet, `step()` advances the ease by `delta` seconds and returns the input
## vector to apply. Pure, so a scenario can feed it a jitter pattern directly.
class InputSmoother extends RefCounted:
	var target: Vector2 = Vector2.ZERO
	var value: Vector2 = Vector2.ZERO

	func push(v: Vector2) -> void:
		# A NaN target would poison the ease for good, not just one frame.
		target = v.limit_length(1.0) if is_finite(v.x) and is_finite(v.y) else Vector2.ZERO
		if target == Vector2.ZERO or value.distance_to(target) >= INPUT_FLICK_SNAP:
			value = target

	func step(delta: float) -> Vector2:
		if value.distance_to(target) <= INPUT_SETTLE_EPSILON:
			value = target
		else:
			value = value.lerp(target, 1.0 - exp(-delta / INPUT_SMOOTHING_SEC))
		return value

	func reset() -> void:
		target = Vector2.ZERO
		value = Vector2.ZERO

var _log_input: bool = false

var _http_server: TCPServer = TCPServer.new()
var _ws_server: TCPServer = TCPServer.new()
var _http_clients: Array[HttpConn] = []
var _pending: Array[PendingConn] = []
## A socket that has finished the WebSocket handshake but has not yet sent
## its identifying first frame -- see `_process_websocket`'s second stage.
## Reuses `PendingConn`: the shape (peer, deadline) is the same.
var _awaiting_id: Array[PendingConn] = []

# Untyped on purpose: elements are `Player` nodes and GDScript's analyser
# would reject `set_input_vector` on a statically typed `Node`.
var _players: Array = []
var _slot_peers: Array[WebSocketPeer] = []
var _slot_last_packet_msec: PackedInt64Array = PackedInt64Array()
var _smoothers: Array[InputSmoother] = []
var _last_weapon: PackedVector2Array = PackedVector2Array()
var _steady_frames: PackedInt32Array = PackedInt32Array()
# 1 once a slot has ever held a controller: keeps the startup settle of an
# untouched weapon out of the diagnostics.
var _bound_once: PackedByteArray = PackedByteArray()
## Whether a slot has an open roster entry (ADR-0007): set on first bind,
## cleared only by `expire_disconnected_claims()` at a round boundary --
## never by an ordinary disconnect, which is the whole point. A round loop
## reads `claimed_slots()` to know who is in the roster and calls
## `expire_disconnected_claims()` before every attempt to start a round.
var _slot_claimed: PackedByteArray = PackedByteArray()
## The id that claimed each slot, so a reconnecting phone can be matched back
## to the same slot instead of taking whatever is free. Empty for an
## unclaimed slot.
var _slot_client_id: PackedStringArray = PackedStringArray()

func _ready() -> void:
	_log_input = OS.get_cmdline_user_args().has("--log-input")

	for path in player_paths:
		_players.append(get_node_or_null(path))
	_slot_peers.resize(_players.size())
	_slot_last_packet_msec.resize(_players.size())
	_last_weapon.resize(_players.size())
	_steady_frames.resize(_players.size())
	_bound_once.resize(_players.size())
	_slot_claimed.resize(_players.size())
	_slot_client_id.resize(_players.size())
	for i in _last_weapon.size():
		_last_weapon[i] = Vector2(NAN, NAN)
		_smoothers.append(InputSmoother.new())

	var http_err: int = _http_server.listen(http_port)
	if http_err != OK:
		push_error("ControllerServer: cannot listen on HTTP port %d (error %d)" % [http_port, http_err])
	var ws_err: int = _ws_server.listen(ws_port)
	if ws_err != OK:
		push_error("ControllerServer: cannot listen on WebSocket port %d (error %d)" % [ws_port, ws_err])
	if http_err == OK and http_port == 0:
		http_port = _http_server.get_local_port()
	if ws_err == OK and ws_port == 0:
		ws_port = _ws_server.get_local_port()

	var urls: PackedStringArray = _join_urls()
	if urls.is_empty():
		print("ControllerServer: no non-loopback IPv4 address found; try http://127.0.0.1:%d/" % http_port)
	for url in urls:
		print("Controller page: %s" % url)

	var label: Label = get_node_or_null(join_label_path) as Label
	if label != null:
		# One URL only: the label sits directly above the score line, and every
		# address is already printed to the console for the rare case the
		# first one isn't the room's network.
		label.text = "Join on your phone:\n" + (urls[0] if not urls.is_empty() else "http://127.0.0.1:%d/" % http_port)

	var qr_rect: TextureRect = get_node_or_null(qr_texture_path) as TextureRect
	if qr_rect != null:
		if urls.is_empty():
			qr_rect.visible = false
		else:
			var qr_texture: ImageTexture = _generate_qr_texture(urls[0])
			qr_rect.visible = qr_texture != null
			if qr_texture != null:
				qr_rect.texture = qr_texture

func _process(delta: float) -> void:
	_process_http()
	_process_websocket()
	_apply_smoothed_input(delta)

## Step every bound slot's ease and hand the result to its player (issue #113).
func _apply_smoothed_input(delta: float) -> void:
	for slot in _slot_peers.size():
		if _slot_peers[slot] == null or _players[slot] == null:
			continue
		_players[slot].set_input_vector(_smoothers[slot].step(delta))

## Weapon diagnostics run on the physics tick because that is the rate the weapon is
## actually integrated at, which makes "held steady for N frames" meaningful.
##
## A slot is reported while a controller is bound, and afterwards until its weapon
## has settled back to rest -- otherwise the easing that follows a disconnect
## would happen entirely off the record.
func _physics_process(_delta: float) -> void:
	for slot in _slot_peers.size():
		if _slot_peers[slot] == null and not _weapon_away_from_rest(slot):
			continue
		_log_weapon(slot)

## True while an unbound slot still owes the log an easing line. The last
## reported length counts too, so the frame the weapon actually reaches rest is
## reported before logging stops.
func _weapon_away_from_rest(slot: int) -> bool:
	if _bound_once[slot] == 0:
		return false
	var player: Variant = _players[slot]
	if player == null:
		return false
	var rest: float = player.weapon_min_length + LENGTH_LOG_EPSILON
	if player.weapon_length > rest:
		return true
	return is_finite(_last_weapon[slot].y) and _last_weapon[slot].y > rest

# --- HTTP -------------------------------------------------------------------

## Join URLs, best first: the QR code and the on-screen label only show the
## first one, so it has to be the address a phone on the room's Wi-Fi can
## actually reach.
##
## Link-local `169.254.*` addresses are dropped outright -- a disconnected or
## unconfigured adapter self-assigns one, and no phone can reach it. Adapters
## whose names mark them as virtual (WSL, Hyper-V, Docker, VPNs) are kept but
## sorted last. Deliberately not ranked by address range: a real Wi-Fi network
## can hand out 172.16/12 or 10/8 just as happily as 192.168/16.
func _join_urls() -> PackedStringArray:
	var preferred: PackedStringArray = PackedStringArray()
	var virtual: PackedStringArray = PackedStringArray()
	for iface: Dictionary in IP.get_local_interfaces():
		var adapter: String = (str(iface.get("friendly", "")) + " " + str(iface.get("name", ""))).to_lower()
		var is_virtual: bool = false
		for hint: String in VIRTUAL_ADAPTER_HINTS:
			if adapter.contains(hint):
				is_virtual = true
				break
		for addr: String in iface.get("addresses", []):
			if addr.contains(":") or addr.begins_with("127.") or addr.begins_with("169.254."):
				continue # IPv6, loopback, link-local
			var url: String = "http://%s:%d/" % [addr, http_port]
			if url in preferred or url in virtual:
				continue
			if is_virtual:
				virtual.append(url)
			else:
				preferred.append(url)
	preferred.append_array(virtual)
	return preferred

## Shells out to `qrencode` rather than generating QR modules in GDScript:
## the ISO 18004 module-placement/masking rules are easy to get subtly wrong
## in a way that still looks like a QR code but does not scan, and this
## engine's install has no QR library. `null` on any failure (tool missing,
## nonzero exit, unreadable output) -- the join label's text URL already
## covers that case, so a phone can still join by typing it.
func _generate_qr_texture(text: String) -> ImageTexture:
	var out_path: String = OS.get_user_data_dir() + "/join_qr.png"
	var output: Array = []
	var exit_code: int = OS.execute("qrencode", ["-o", out_path, "-s", "8", "-m", "2", text], output, true)
	if exit_code != 0:
		push_warning("ControllerServer: qrencode unavailable or failed (exit %d) -- put qrencode on PATH (e.g. `brew install qrencode`, `apt install qrencode`, or a Windows build) to show a join QR code" % exit_code)
		return null
	var image: Image = Image.new()
	if image.load(out_path) != OK:
		push_warning("ControllerServer: failed to load generated QR image at %s" % out_path)
		return null
	return ImageTexture.create_from_image(image)

func _process_http() -> void:
	var now: int = Time.get_ticks_msec()
	var idle_deadline: int = now + int(connection_timeout_sec * 1000.0)

	while _http_server.is_connection_available():
		var tcp: StreamPeerTCP = _http_server.take_connection()
		if tcp == null:
			continue
		tcp.set_no_delay(true)
		_http_clients.append(HttpConn.new(tcp, idle_deadline))

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
			# A socket that connects and never finishes a request would
			# otherwise be polled for the rest of the session.
			if now > conn.deadline_msec:
				if _log_input:
					print("http connection dropped: idle %.1fs without a complete request" % connection_timeout_sec)
				conn.tcp.disconnect_from_host()
				_http_clients.erase(conn)
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
	var now: int = Time.get_ticks_msec()

	while _ws_server.is_connection_available():
		var tcp: StreamPeerTCP = _ws_server.take_connection()
		if tcp == null:
			continue
		tcp.set_no_delay(true)
		var peer: WebSocketPeer = WebSocketPeer.new()
		# Defaults to 0.0, i.e. no ping/pong, which is exactly how a dead phone
		# stays STATE_OPEN forever.
		peer.heartbeat_interval = heartbeat_interval_sec
		if peer.accept_stream(tcp) == OK:
			_pending.append(PendingConn.new(peer, now + int(connection_timeout_sec * 1000.0)))

	for conn: PendingConn in _pending.duplicate():
		conn.peer.poll()
		var state: int = conn.peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_pending.erase(conn)
			_awaiting_id.append(PendingConn.new(conn.peer, now + int(connection_timeout_sec * 1000.0)))
		elif state == WebSocketPeer.STATE_CLOSED:
			_pending.erase(conn)
		elif now > conn.deadline_msec:
			if _log_input:
				print("websocket connection dropped: handshake idle %.1fs" % connection_timeout_sec)
			conn.peer.close(1002, "handshake timeout")
			_pending.erase(conn)

	# Second stage: the socket is open, but a slot is not handed out until the
	# controller page has said who it is (ADR-0007's reclaim needs an id to
	# match against). A page that never sends one -- an old cached copy, a
	# stray client -- is not punished for it; it just binds as a new,
	# unmatched roster entry once its own deadline passes.
	for conn: PendingConn in _awaiting_id.duplicate():
		conn.peer.poll()
		var state: int = conn.peer.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			_awaiting_id.erase(conn)
			continue
		if state != WebSocketPeer.STATE_OPEN:
			continue
		var id: Variant = _read_client_id(conn.peer)
		if id != null:
			_awaiting_id.erase(conn)
			_bind_with_id(conn.peer, id)
		elif now > conn.deadline_msec:
			_awaiting_id.erase(conn)
			_bind_with_id(conn.peer, "")

	var timeout_msec: int = int(controller_timeout_sec * 1000.0)
	for slot in _slot_peers.size():
		var peer: WebSocketPeer = _slot_peers[slot]
		if peer == null:
			continue
		peer.poll()
		var state: int = peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_drain(slot, peer)
			var silent_for: int = now - _slot_last_packet_msec[slot]
			if silent_for > timeout_msec:
				# The decisive case: the phone screen-locked or left Wi-Fi
				# mid-drag, so the (0,0) release frame never arrived and the
				# socket still looks open. Treat it as gone.
				if _log_input:
					print("slot %d controller timed out after %d ms without input" % [slot, silent_for])
				peer.close(1001, "input timeout")
				_unbind(slot)
		elif state == WebSocketPeer.STATE_CLOSED:
			_unbind(slot)

## Read the id a controller page sends as its first (and only) text frame --
## `{"id":"<string>"}`. Returns null while nothing usable has arrived yet, so
## the caller can keep waiting up to its own deadline; a stray non-JSON or
## binary packet is skipped rather than treated as a failure, since a client
## that only ever sends binary frames (an old cached page) should still bind.
func _read_client_id(peer: WebSocketPeer) -> Variant:
	while peer.get_available_packet_count() > 0:
		var pkt: PackedByteArray = peer.get_packet()
		if not peer.was_string_packet():
			continue
		var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if parsed is Dictionary and typeof(parsed.get("id")) == TYPE_STRING:
			return parsed["id"]
	return null

## Bind a newly-identified controller (ADR-0007). A non-empty id that matches
## a claimed slot whose controller is currently disconnected reclaims that
## exact slot -- this is the whole reconnect path. Otherwise the lowest
## unclaimed slot is claimed fresh, under this id (which may be empty, for a
## client that never sent one). Refuses the connection once every slot is
## claimed, exactly as before id-matching existed.
func _bind_with_id(peer: WebSocketPeer, id: String) -> void:
	if not id.is_empty():
		for slot in _slot_peers.size():
			if _slot_claimed[slot] == 1 and _slot_peers[slot] == null and _slot_client_id[slot] == id:
				_attach(slot, peer)
				if _log_input:
					print("slot %d reclaimed" % slot)
				return
	for slot in _slot_peers.size():
		if _slot_claimed[slot] == 1:
			continue
		if _players[slot] == null:
			continue
		_slot_claimed[slot] = 1
		_slot_client_id[slot] = id
		_attach(slot, peer)
		player_joined.emit(slot)
		if _log_input:
			print("slot %d claimed" % slot)
		return
	peer.close(1000, "no free player slot")
	if _log_input:
		print("controller refused: no free player slot")

func _attach(slot: int, peer: WebSocketPeer) -> void:
	_slot_peers[slot] = peer
	_slot_last_packet_msec[slot] = Time.get_ticks_msec()
	_last_weapon[slot] = Vector2(NAN, NAN)
	_steady_frames[slot] = 0
	_bound_once[slot] = 1
	_smoothers[slot].reset()
	_players[slot].bind_controller()
	peer.send_text(JSON.stringify({"slot": slot}))

## Free the slot and park its player: zeroing the vector first means the weapon
## eases back to rest over several frames instead of holding the controller's
## last angle forever (or snapping to whatever a debug source would say).
##
## Does not touch `_slot_claimed` / `_slot_client_id`: an ordinary disconnect
## keeps the roster entry open for the rest of the round (ADR-0007). Only
## `expire_disconnected_claims()` clears those, at a round boundary.
func _unbind(slot: int) -> void:
	_slot_peers[slot] = null
	_smoothers[slot].reset()
	_last_weapon[slot] = Vector2(NAN, NAN)
	_steady_frames[slot] = 0
	if _players[slot] != null:
		_players[slot].set_input_vector(Vector2.ZERO)
		_players[slot].unbind_controller()
	if _log_input:
		print("slot %d unbound" % slot)

## The slots with an open roster entry right now, in slot order -- what a
## round loop treats as "in the roster" regardless of whether each one's
## controller is currently connected.
func claimed_slots() -> Array[int]:
	var result: Array[int] = []
	for slot in _slot_claimed.size():
		if _slot_claimed[slot] == 1:
			result.append(slot)
	return result

## Buzz the phone bound to `slot` (issue #34, ADR-0013): one
## `{"t":"buzz","kind":<kind>}` text frame, which the page turns into a
## vibration and a flash in the slot's colour. `kind` is one of `BUZZ_KINDS`.
## A no-op when the slot has no connected controller -- a buzz is feedback,
## not state, so one missed while a phone is away is not replayed.
func send_buzz(slot: int, kind: String) -> void:
	if not slot_has_controller(slot):
		return
	var peer: WebSocketPeer = _slot_peers[slot]
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(JSON.stringify({"t": "buzz", "kind": kind}))
	if _log_input:
		print("slot %d buzz %s" % [slot, kind])

## Whether `slot` has a connected controller right now. A claimed slot can be
## without one mid-round (ADR-0007); the round loop uses this to spot a round
## that no one still in it can finish.
func slot_has_controller(slot: int) -> bool:
	return slot >= 0 and slot < _slot_peers.size() and _slot_peers[slot] != null

## Drop every claimed slot that has no live controller right now. Called by
## the round loop before every attempt to start a round: a roster entry
## survives a disconnect only until the end of the round it disconnected in
## (ADR-0007) -- an entry not reclaimed by then does not carry into the next
## round, and one that dropped while no round was running is not held at all.
func expire_disconnected_claims() -> void:
	for slot in _slot_claimed.size():
		if _slot_claimed[slot] == 1 and _slot_peers[slot] == null:
			_slot_claimed[slot] = 0
			_slot_client_id[slot] = ""

## Latest value wins: drain everything queued this frame and keep only the last
## well-formed packet, so a burst never replays stale input. The packet sets
## the slot's smoothing target; `_apply_smoothed_input` applies it (#113).
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
	_slot_last_packet_msec[slot] = Time.get_ticks_msec()
	var v: Vector2 = Vector2(latest.decode_float(0), latest.decode_float(4))
	_smoothers[slot].push(v)
	if _log_input:
		print("slot=%d v=(%.4f, %.4f)" % [slot, v.x, v.y])

## Report the weapon the host actually commanded, reading only Player's
## public `weapon_angle` / `weapon_length`, so direction/reach/release can be
## observed the way the input pipeline produced them rather than by
## re-deriving them from the packet. These are the setpoints, not the driven
## body's live geometry: a physical weapon under contact jitters, and a
## steadiness log has to be able to say "nothing changed".
##
## Changes print as they happen; an unchanged weapon prints a positive "steady"
## line every `STEADY_LOG_FRAMES` frames, so "it held at rest" is provable from
## a line that exists rather than from silence.
func _log_weapon(slot: int) -> void:
	if not _log_input:
		return
	var player: Variant = _players[slot]
	if player == null:
		return
	var current: Vector2 = Vector2(player.weapon_angle, player.weapon_length)
	var previous: Vector2 = _last_weapon[slot]
	if is_finite(previous.x) and absf(current.x - previous.x) < ANGLE_LOG_EPSILON and absf(current.y - previous.y) < LENGTH_LOG_EPSILON:
		_steady_frames[slot] += 1
		if _steady_frames[slot] % STEADY_LOG_FRAMES == 0:
			print("slot=%d weapon steady angle=%.4f len=%.1f frames=%d" % [slot, previous.x, previous.y, _steady_frames[slot]])
		return
	_last_weapon[slot] = current
	_steady_frames[slot] = 0
	print("slot=%d weapon angle=%.4f len=%.1f" % [slot, current.x, current.y])
