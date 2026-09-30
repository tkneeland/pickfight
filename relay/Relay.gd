extends Node
## Room-code relay (issue #238, #212). Joins one host and up to MAX_CLIENTS
## remote clients over WebSocket and forwards binary frames between them. It
## never parses a payload. Not loaded by the game; no `class_name`.
##
## Handshake. `WebSocketPeer.accept_stream` does not expose the HTTP request
## path, so the role is chosen by the FIRST TEXT message after the socket opens
## (the documented fallback to `/host` and `/join?room=CODE`):
##   {"t":"host"}                     -> a new room
##   {"t":"join","room":"ABCD"}       -> join an existing room
##
## Control messages (text JSON):
##   to host:   {"t":"room","code":"ABCD"}, {"t":"joined","peer":N}, {"t":"left","peer":N}
##   to client: {"t":"welcome","peer":N}, {"t":"error","reason":"bad_room"|"room_full"|"host_left"}
##              (an error is followed by a close)
##
## Payloads (binary frames):
##   client -> host: relay prepends the 1-byte peer id.
##   host -> client: first byte is the target peer id, 0 = broadcast; the relay
##   strips it and forwards the rest.

const MAX_CLIENTS: int = 8
const CODE_LETTERS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ" # no I, no O
const CODE_LENGTH: int = 4
const HEARTBEAT_SEC: float = 5.0
const HANDSHAKE_TIMEOUT_SEC: float = 10.0
const CLOSE_GRACE_MSEC: int = 150
const INBOUND_BUFFER_BYTES: int = 1 << 18

## A room with no traffic for this long is closed.
var idle_timeout_sec: float = 600.0

class Pending:
	var peer: WebSocketPeer
	var deadline_msec: int
	func _init(p: WebSocketPeer, d: int) -> void:
		peer = p
		deadline_msec = d

class Room:
	var code: String = ""
	var host: WebSocketPeer
	var clients: Dictionary = {} # peer id (int) -> WebSocketPeer
	var last_traffic_msec: int = 0

var _server: TCPServer = null
var _pending: Array[Pending] = []
var _rooms: Dictionary = {} # code -> Room
var _closing: Array[Pending] = [] # refused peers, flushed then closed

func start(port: int) -> int:
	stop()
	_server = TCPServer.new()
	var err: int = _server.listen(port)
	if err != OK:
		_server = null
	return err

func stop() -> void:
	for p: Pending in _pending:
		p.peer.close()
	_pending.clear()
	for c: Pending in _closing:
		c.peer.close()
	_closing.clear()
	for room: Room in _rooms.values():
		_close_room(room, "host_left", false)
	_rooms.clear()
	if _server != null:
		_server.stop()
		_server = null

func room_count() -> int:
	return _rooms.size()

func _process(_delta: float) -> void:
	if _server == null:
		return
	var now: int = Time.get_ticks_msec()
	while _server.is_connection_available():
		var tcp: StreamPeerTCP = _server.take_connection()
		if tcp == null:
			continue
		tcp.set_no_delay(true)
		var peer := WebSocketPeer.new()
		peer.heartbeat_interval = HEARTBEAT_SEC
		peer.inbound_buffer_size = INBOUND_BUFFER_BYTES
		if peer.accept_stream(tcp) == OK:
			_pending.append(Pending.new(peer, now + int(HANDSHAKE_TIMEOUT_SEC * 1000.0)))

	for p: Pending in _pending.duplicate():
		p.peer.poll()
		var state: int = p.peer.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			_pending.erase(p)
		elif now > p.deadline_msec:
			p.peer.close(1002, "handshake timeout")
			_pending.erase(p)
		elif state == WebSocketPeer.STATE_OPEN and _read_hello(p, now):
			_pending.erase(p)

	for c: Pending in _closing.duplicate():
		c.peer.poll()
		if now > c.deadline_msec or c.peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			c.peer.close(4000, "refused")
			_closing.erase(c)

	for room: Room in _rooms.values():
		_pump_room(room, now)
	for room: Room in _rooms.values():
		if room.host.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_close_room(room, "host_left", true)
		elif now - room.last_traffic_msec > int(idle_timeout_sec * 1000.0):
			_close_room(room, "host_left", true)

## True once the pending peer has said who it is (and has been placed or refused).
func _read_hello(p: Pending, now: int) -> bool:
	while p.peer.get_available_packet_count() > 0:
		var pkt: PackedByteArray = p.peer.get_packet()
		if not p.peer.was_string_packet():
			continue
		var msg: Variant = _parse_json(pkt.get_string_from_utf8())
		if not (msg is Dictionary):
			continue
		match str(msg.get("t", "")):
			"host":
				_open_room(p.peer, now)
				return true
			"join":
				_join_room(p.peer, str(msg.get("room", "")).to_upper(), now)
				return true
	return false

func _open_room(peer: WebSocketPeer, now: int) -> void:
	var room := Room.new()
	room.code = _new_code()
	room.host = peer
	room.last_traffic_msec = now
	_rooms[room.code] = room
	_send_json(peer, {"t": "room", "code": room.code})

func _join_room(peer: WebSocketPeer, code: String, now: int) -> void:
	var room: Room = _rooms.get(code)
	if room == null:
		_refuse(peer, "bad_room")
		return
	if room.clients.size() >= MAX_CLIENTS:
		_refuse(peer, "room_full")
		return
	var id: int = 1
	while room.clients.has(id):
		id += 1
	room.clients[id] = peer
	room.last_traffic_msec = now
	_send_json(peer, {"t": "welcome", "peer": id})
	_send_json(room.host, {"t": "joined", "peer": id})

func _refuse(peer: WebSocketPeer, reason: String) -> void:
	# close() straight after send_text() can drop the text; keep polling the
	# peer for a moment so the error reaches it, then close (see _process).
	_send_json(peer, {"t": "error", "reason": reason})
	_closing.append(Pending.new(peer, Time.get_ticks_msec() + CLOSE_GRACE_MSEC))

func _pump_room(room: Room, now: int) -> void:
	room.host.poll()
	if room.host.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while room.host.get_available_packet_count() > 0:
			var pkt: PackedByteArray = room.host.get_packet()
			if room.host.was_string_packet() or pkt.size() < 1:
				continue
			room.last_traffic_msec = now
			var target: int = pkt[0]
			var body: PackedByteArray = pkt.slice(1)
			if target == 0:
				for client: WebSocketPeer in room.clients.values():
					_send_binary(client, body)
			elif room.clients.has(target):
				_send_binary(room.clients[target], body)
	for id: int in room.clients.keys():
		var client: WebSocketPeer = room.clients[id]
		client.poll()
		var state: int = client.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while client.get_available_packet_count() > 0:
				var pkt: PackedByteArray = client.get_packet()
				if client.was_string_packet():
					continue
				room.last_traffic_msec = now
				var framed := PackedByteArray([id])
				framed.append_array(pkt)
				_send_binary(room.host, framed)
		elif state == WebSocketPeer.STATE_CLOSED:
			room.clients.erase(id)
			_send_json(room.host, {"t": "left", "peer": id})

func _close_room(room: Room, reason: String, erase: bool) -> void:
	for client: WebSocketPeer in room.clients.values():
		if client.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_refuse(client, reason)
	room.clients.clear()
	if room.host.get_ready_state() == WebSocketPeer.STATE_OPEN:
		room.host.close(1000, reason)
	if erase:
		_rooms.erase(room.code)

func _new_code() -> String:
	while true:
		var code: String = ""
		for i in CODE_LENGTH:
			code += CODE_LETTERS[randi() % CODE_LETTERS.length()]
		if not _rooms.has(code):
			return code
	return ""

static func _send_json(peer: WebSocketPeer, data: Dictionary) -> void:
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(JSON.stringify(data))

static func _send_binary(peer: WebSocketPeer, data: PackedByteArray) -> void:
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send(data)

static func _parse_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
