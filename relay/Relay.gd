extends Node
## Room-code relay (issue #238, #212). Joins one host and up to MAX_CLIENTS
## remote clients over WebSocket and forwards binary frames between them. It
## never parses a payload. Not loaded by the game; no `class_name`.
##
## Handshake. `WebSocketPeer.accept_stream` does not expose the HTTP request
## path, so the role is chosen by the FIRST TEXT message after the socket opens
## (the documented fallback to `/host` and `/join?room=CODE`):
##   {"t":"host"}                     -> a new room
##   {"t":"host","room":"ABCD","token":"..."} -> reclaim a room whose host socket
##        dropped within `host_grace_sec` (issue #249); a wrong token, an unknown
##        room or an expired window opens a fresh room instead.
##   {"t":"join","room":"ABCD"}       -> join an existing room
##   {"t":"feedback","text":"...","version":"..","os":"..","stage":".."}
##        -> files a GitHub issue (issue #262) and answers one
##        {"t":"feedback_result","status":N} before closing: 200 filed, 400 empty,
##        429 rate limited, 502 GitHub refused, 503 no GITHUB_FEEDBACK_TOKEN.
##        Godot's `accept_stream` cannot serve a plain HTTP POST, so the
##        endpoint rides the same TLS WebSocket the game already reaches.
##
## Control messages (text JSON):
##   to host:   {"t":"room","code":"ABCD","token":"<16 hex>"} (a reclaim adds
##              "peers":[ids] and is followed by a "joined" per current peer), {"t":"joined","peer":N}, {"t":"left","peer":N}
##   to client: {"t":"welcome","peer":N}, {"t":"error","reason":"bad_room"|"room_full"|"host_left"|"idle_timeout"}
##              (an error is followed by a close)
##
## Payloads (binary frames):
##   client -> host: relay prepends the 1-byte peer id.
##   host -> client: first byte is the target peer id, 0 = broadcast; the relay
##   strips it and forwards the rest.

## Most remote clients one room seats.
const MAX_CLIENTS: int = 8
## Room-code alphabet: no I and no O, which read as 1 and 0.
const CODE_LETTERS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ"
## Room-code length.
const CODE_LENGTH: int = 4
## WebSocket ping interval, seconds.
const HEARTBEAT_SEC: float = 5.0
## How long a fresh socket may take to say host or join, seconds.
const HANDSHAKE_TIMEOUT_SEC: float = 10.0
## How long a refused or closed peer is polled so its last frame flushes, msec.
const CLOSE_GRACE_MSEC: int = 150
## Inbound buffer per peer, bytes.
const INBOUND_BUFFER_BYTES: int = 1 << 18

## How long a room waits for its host to reclaim it after the host's socket
## drops abnormally (no close frame, or any code but 1000), seconds. A host
## that hangs up cleanly (code 1000) still closes the room at once.
@export var host_grace_sec: float = 15.0

## A room with no traffic for this long is closed.
@export var idle_timeout_sec: float = 600.0

## GitHub issue creation endpoint for feedback (issue #262).
const FEEDBACK_URL: String = "https://api.github.com/repos/tkneeland/pickfight/issues"
const FEEDBACK_LABELS: Array = ["needs-triage", "feedback"]
const FEEDBACK_MAX_CHARS: int = 2000
const FEEDBACK_FIELD_MAX_CHARS: int = 80
const FEEDBACK_WINDOW_MSEC: int = 3600 * 1000
## How long a feedback socket may wait for GitHub, msec.
const FEEDBACK_REPLY_MSEC: int = 20000

## Feedback filings allowed per IP per hour.
@export var feedback_limit_per_hour: int = 5

## The GitHub token, from the environment. Never sent to a client. Empty means
## feedback is offline (503).
var feedback_token: String = OS.get_environment("GITHUB_FEEDBACK_TOKEN")

## Makes the GitHub call: (url: String, headers: PackedStringArray, body: String)
## -> HTTP status int. Replaceable so a test captures the request offline.
var feedback_post: Callable = Callable()

var _feedback_times: Dictionary = {} # ip -> Array[int] of msec

## A socket awaiting its hello, or a peer being flushed before it is closed.
class Pending:
	var peer: WebSocketPeer
	var deadline_msec: int
	func _init(p_peer: WebSocketPeer, p_deadline_msec: int) -> void:
		peer = p_peer
		deadline_msec = p_deadline_msec

## One host and its remote clients, keyed by the code the host shows.
class Room:
	var code: String = ""
	var host: WebSocketPeer
	var clients: Dictionary = {} # peer id (int) -> WebSocketPeer
	var last_traffic_msec: int = 0
	var token: String = ""
	## When the host socket was lost, msec; 0 while the host is present.
	var host_gone_msec: int = 0

var _server: TCPServer = null
var _pending: Array[Pending] = []
var _rooms: Dictionary = {} # code -> Room
var _closing: Array[Pending] = [] # refused peers, flushed then closed

## Listens on `port`; returns an Error code (OK on success).
func start(port: int) -> int:
	stop()
	_server = TCPServer.new()
	var err: int = _server.listen(port)
	if err != OK:
		_server = null
	return err

## Closes every room and socket. Queued notices are flushed for up to
## CLOSE_GRACE_MSEC first; no peer is left half-open afterwards.
func stop() -> void:
	for p: Pending in _pending:
		p.peer.close()
	var all: Array[WebSocketPeer] = []
	for p: Pending in _pending:
		all.append(p.peer)
	_pending.clear()
	for room: Room in _rooms.values():
		_close_room(room, "host_left", false)
		all.append(room.host)
	_rooms.clear()
	for c: Pending in _closing:
		all.append(c.peer)
	_closing.clear()
	var deadline: int = Time.get_ticks_msec() + CLOSE_GRACE_MSEC
	while Time.get_ticks_msec() < deadline:
		var open: bool = false
		for peer: WebSocketPeer in all:
			peer.poll()
			if peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
				open = true
		if not open:
			break
		OS.delay_msec(5)
	for peer: WebSocketPeer in all:
		peer.close(4000, "relay stopped")
		peer.poll()
	if _server != null:
		_server.stop()
		_server = null

## Number of open rooms.
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
		if room.host_gone_msec == 0 and room.host.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			if host_grace_sec > 0.0 and room.host.get_close_code() != 1000:
				room.host_gone_msec = now
			else:
				_close_room(room, "host_left", true)
				continue
		if room.host_gone_msec != 0 and now - room.host_gone_msec > int(host_grace_sec * 1000.0):
			_close_room(room, "host_left", true)
		elif now - room.last_traffic_msec > int(idle_timeout_sec * 1000.0):
			_close_room(room, "idle_timeout", true)

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
				if not _reclaim_room(p.peer, msg, now):
					_open_room(p.peer, now)
				return true
			"feedback":
				_start_feedback(p, msg, now)
				return true
			"join":
				_join_room(p.peer, str(msg.get("room", "")).to_upper(), now)
				return true
	return false

## Keeps the peer polled in `_closing` while GitHub answers, then replies.
func _start_feedback(p: Pending, msg: Dictionary, now: int) -> void:
	var closing := Pending.new(p.peer, now + FEEDBACK_REPLY_MSEC)
	_closing.append(closing)
	var ip: String = p.peer.get_connected_host()
	var result: Dictionary = await handle_feedback(ip, msg)
	_send_json(p.peer, {"t": "feedback_result", "status": int(result["status"])})
	closing.deadline_msec = Time.get_ticks_msec() + CLOSE_GRACE_MSEC

## Files one piece of feedback. Returns {"status": int}. Statuses: 503 no token,
## 400 empty after cleaning, 429 over the per-IP limit, 502 GitHub failed, 200 filed.
func handle_feedback(ip: String, msg: Dictionary) -> Dictionary:
	if feedback_token.is_empty():
		return {"status": 503}
	var text: String = clean_feedback_text(str(msg.get("text", "")), FEEDBACK_MAX_CHARS, true)
	if text.strip_edges().is_empty():
		return {"status": 400}
	var now: int = Time.get_ticks_msec()
	var times: Array = _feedback_times.get(ip, [])
	times = times.filter(func(t: int) -> bool: return now - t < FEEDBACK_WINDOW_MSEC)
	if times.size() >= feedback_limit_per_hour:
		_feedback_times[ip] = times
		return {"status": 429}
	times.append(now)
	_feedback_times[ip] = times
	var headers := PackedStringArray([
		"Authorization: Bearer " + feedback_token,
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: pickfight-relay",
		"Content-Type: application/json",
	])
	var status: int = int(await _post(FEEDBACK_URL, headers, JSON.stringify(build_feedback_issue(msg))))
	return {"status": 200 if status >= 200 and status < 300 else 502}

## The GitHub issue body for a feedback message.
func build_feedback_issue(msg: Dictionary) -> Dictionary:
	var text: String = clean_feedback_text(str(msg.get("text", "")), FEEDBACK_MAX_CHARS, true).strip_edges()
	var first_line: String = text.split("\n")[0].strip_edges()
	if first_line.length() > 60:
		first_line = first_line.substr(0, 60) + "..."
	var body: String = "%s\n\n---\nBuild: %s\nOS: %s\nStage: %s\n\n_Sent from the in-game feedback button._" % [
		text,
		clean_feedback_text(str(msg.get("version", "")), FEEDBACK_FIELD_MAX_CHARS, false),
		clean_feedback_text(str(msg.get("os", "")), FEEDBACK_FIELD_MAX_CHARS, false),
		clean_feedback_text(str(msg.get("stage", "")), FEEDBACK_FIELD_MAX_CHARS, false)]
	return {"title": "Feedback: " + first_line, "body": body, "labels": FEEDBACK_LABELS}

## Caps the length and drops control characters; newlines survive when `multiline`.
static func clean_feedback_text(text: String, max_chars: int, multiline: bool) -> String:
	var out: String = ""
	for i in text.length():
		var code: int = text.unicode_at(i)
		var is_newline: bool = code == 10 or code == 13
		if code < 32 or code == 127 or (code >= 0x80 and code < 0xA0):
			if not (multiline and is_newline):
				continue
		out += String.chr(code)
		if out.length() >= max_chars:
			break
	return out

func _post(url: String, headers: PackedStringArray, body: String) -> Variant:
	if feedback_post.is_valid():
		return await feedback_post.call(url, headers, body)
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	if http.request(url, headers, HTTPClient.METHOD_POST, body) != OK:
		http.queue_free()
		return 0
	var result: Array = await http.request_completed
	http.queue_free()
	return result[1] if result[0] == HTTPRequest.RESULT_SUCCESS else 0

func _open_room(peer: WebSocketPeer, now: int) -> void:
	var room := Room.new()
	room.code = _new_code()
	room.host = peer
	room.last_traffic_msec = now
	_rooms[room.code] = room
	room.token = _new_token()
	_send_json(peer, {"t": "room", "code": room.code, "token": room.token})

## Gives the room back to a host that proves it with the room's token. False
## when there is nothing to reclaim (wrong token, unknown room, host present).
func _reclaim_room(peer: WebSocketPeer, msg: Dictionary, now: int) -> bool:
	var room: Room = _rooms.get(str(msg.get("room", "")).to_upper())
	if room == null or room.host_gone_msec == 0 or room.token == "" \
			or str(msg.get("token", "")) != room.token:
		return false
	room.host = peer
	room.host_gone_msec = 0
	room.last_traffic_msec = now
	var ids: Array = room.clients.keys()
	_send_json(peer, {"t": "room", "code": room.code, "token": room.token, "peers": ids})
	for id: int in ids:
		_send_json(peer, {"t": "joined", "peer": id})
	return true

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
		else:
			client.close()
	room.clients.clear()
	if room.host.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if reason == "idle_timeout":
			_refuse(room.host, reason)
		else:
			room.host.close(1000, reason)
	if erase:
		_rooms.erase(room.code)

func _new_token() -> String:
	var token: String = ""
	for i in 8:
		token += "%02x" % (randi() % 256)
	return token

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
