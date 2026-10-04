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
##   {"t":"stats","record":{...}}
##        -> appends one anonymous match record (issue #372) to a JSONL file
##        and answers {"t":"stats_result","status":N}: 200 stored, 400 invalid,
##        413 over STATS_MAX_BYTES, 429 rate limited, 503 cannot write. The
##        record is rebuilt from known fields only; the IP is never stored or
##        logged (the rate limiter keys on a salted hash that dies with the
##        process); the timestamp is rounded down to the hour.
##
## Control messages (text JSON):
##   to host:   {"t":"room","code":"ABCD","token":"<16 hex>"} (a reclaim adds
##              "peers":[ids] and is followed by a "joined" per current peer), {"t":"joined","peer":N}, {"t":"left","peer":N}
##   to client: {"t":"welcome","peer":N}, {"t":"error","reason":"bad_room"|"room_full"|"host_left"|"idle_timeout"}
##              (an error is followed by a close)
##   from host: {"t":"drop","peer":N} (issue #580) closes client N's relay socket
##              after anything the host already sent it is flushed, frees its
##              slot and answers {"t":"left","peer":N}. An old relay ignores host
##              text frames (it only counts them as traffic), so a new host on an
##              old relay just keeps today's behaviour; an old host never sends it.
##
## Hardening (issue #580): a client frame over CLIENT_FRAME_MAX_BYTES is dropped
## (the host's inbound buffer is the same size as the relay's); a valid reclaim
## token wins even while the old host socket still looks open (the old socket is
## closed); one IP may hold at most `join_cap_per_ip` client seats when the real
## IP is known; and the feedback/stats rate limits key on the real client IP.
## Godot cannot read the WebSocket handshake headers server-side, so the real IP
## comes from the PROXY protocol (v1) header Fly prepends when fly.toml enables
## the `proxy_proto` handler and PICKFIGHT_PROXY_PROTO=1 is set (`proxy_protocol`).
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
## Largest client frame the relay forwards to the host, bytes (issue #580). Real
## frames are an 8-byte input or a short JSON text envelope.
const CLIENT_FRAME_MAX_BYTES: int = 4096
## Longest PROXY protocol v1 line, bytes (the spec's own limit).
const PROXY_LINE_MAX_BYTES: int = 108

## Whether each connection starts with a PROXY protocol v1 line from the front
## proxy (Fly's `proxy_proto` handler), which carries the real client IP. Off by
## default so a relay behind no proxy, and the local dev relay, work unchanged.
@export var proxy_protocol: bool = OS.get_environment("PICKFIGHT_PROXY_PROTO") == "1"
## Most client seats one IP may hold across all rooms. Only enforced when the IP
## is the real one (`ip_cap_enabled`): behind a proxy without PROXY protocol every
## caller shares one address and a cap would throttle everybody together.
@export var join_cap_per_ip: int = 12
var ip_cap_enabled: bool = proxy_protocol

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

## Match telemetry (issue #372).
const STATS_MAX_BYTES: int = 8192
const STATS_FORMATS: PackedStringArray = ["ffa", "teams"]
const STATS_MAX_STAGES: int = 60
const STATS_MAX_WEAPONS: int = 40
const STATS_MAX_NAME_CHARS: int = 40
const STATS_MAX_LENGTH_SEC: int = 86400
## Records allowed per IP per hour.
@export var stats_limit_per_hour: int = 30
## Where records are appended. Set PICKFIGHT_STATS_PATH to a file on a mounted
## volume (see fly.toml) for them to survive a deploy.
var stats_path: String = _default_stats_path()
var _stats_times: Dictionary = {} # salted hash of the caller (int) -> Array[int] of msec
var _stats_salt: String = str(randi()) + str(Time.get_ticks_usec())

static func _default_stats_path() -> String:
	var configured: String = OS.get_environment("PICKFIGHT_STATS_PATH")
	return configured if not configured.is_empty() else "user://match_stats.jsonl"

## A socket awaiting its hello, or a peer being flushed before it is closed.
class Pending:
	var peer: WebSocketPeer
	var deadline_msec: int
	## The caller's IP (the real one behind PROXY protocol), for rate limits.
	var ip: String = ""
	func _init(p_peer: WebSocketPeer, p_deadline_msec: int) -> void:
		peer = p_peer
		deadline_msec = p_deadline_msec

## One host and its remote clients, keyed by the code the host shows.
class Room:
	var code: String = ""
	var host: WebSocketPeer
	var clients: Dictionary = {} # peer id (int) -> WebSocketPeer
	var client_ips: Dictionary = {} # peer id (int) -> IP String
	var last_traffic_msec: int = 0
	var token: String = ""
	## When the host socket was lost, msec; 0 while the host is present.
	var host_gone_msec: int = 0

var _server: TCPServer = null
var _pending: Array[Pending] = []
var _rooms: Dictionary = {} # code -> Room
var _closing: Array[Pending] = [] # refused peers, flushed then closed
var _proxy_pending: Array = [] # [StreamPeerTCP, PackedByteArray line, deadline msec]

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
	for entry: Array in _proxy_pending:
		(entry[0] as StreamPeerTCP).disconnect_from_host()
	_proxy_pending.clear()
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
		if proxy_protocol:
			_proxy_pending.append([tcp, PackedByteArray(), now + int(HANDSHAKE_TIMEOUT_SEC * 1000.0)])
		else:
			_accept(tcp, tcp.get_connected_host(), now)
	for entry: Array in _proxy_pending.duplicate():
		_read_proxy_line(entry, now)

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

func _accept(tcp: StreamPeerTCP, ip: String, now: int) -> void:
	var peer := WebSocketPeer.new()
	peer.heartbeat_interval = HEARTBEAT_SEC
	peer.inbound_buffer_size = INBOUND_BUFFER_BYTES
	if peer.accept_stream(tcp) == OK:
		var pending := Pending.new(peer, now + int(HANDSHAKE_TIMEOUT_SEC * 1000.0))
		pending.ip = ip
		_pending.append(pending)

## Reads a connection's PROXY protocol line one byte at a time, so the bytes
## after it (the WebSocket upgrade) stay in the stream for `accept_stream`. A
## connection that sends something else, too long a line, or nothing in time is
## closed: with the proxy enabled every real connection starts with the line.
func _read_proxy_line(entry: Array, now: int) -> void:
	var tcp: StreamPeerTCP = entry[0]
	var line: PackedByteArray = entry[1]
	tcp.poll()
	var status: int = tcp.get_status()
	if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE \
			or now > int(entry[2]):
		_proxy_pending.erase(entry)
		tcp.disconnect_from_host()
		return
	while tcp.get_available_bytes() > 0:
		var got: Array = tcp.get_partial_data(1)
		if int(got[0]) != OK or (got[1] as PackedByteArray).is_empty():
			break
		line.append((got[1] as PackedByteArray)[0])
		if line[line.size() - 1] == 10:
			_proxy_pending.erase(entry)
			var ip: String = parse_proxy_line(line.get_string_from_ascii())
			if ip.is_empty():
				tcp.disconnect_from_host()
			else:
				_accept(tcp, tcp.get_connected_host() if ip == "unknown" else ip, now)
			return
		if line.size() > PROXY_LINE_MAX_BYTES:
			_proxy_pending.erase(entry)
			tcp.disconnect_from_host()
			return
	entry[1] = line

## The source address of a PROXY protocol v1 line ("PROXY TCP4 src dst sport
## dport\r\n"), "unknown" for "PROXY UNKNOWN" (the proxy had no address), or ""
## when the line is not a PROXY line at all.
static func parse_proxy_line(line: String) -> String:
	var parts: PackedStringArray = line.strip_edges().split(" ", false)
	if parts.size() < 2 or parts[0] != "PROXY":
		return ""
	if parts[1] == "UNKNOWN":
		return "unknown"
	if (parts[1] == "TCP4" or parts[1] == "TCP6") and parts.size() == 6 and parts[2].length() <= 45:
		return parts[2]
	return ""

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
			"stats":
				var status: int = int(handle_stats(p.ip, msg)["status"])
				_send_json(p.peer, {"t": "stats_result", "status": status})
				_closing.append(Pending.new(p.peer, now + CLOSE_GRACE_MSEC))
				return true
			"join":
				_join_room(p.peer, str(msg.get("room", "")).to_upper(), now, p.ip)
				return true
	return false

## Stores one anonymous match record. Returns {"status": int}: 413 too large,
## 400 bad shape, 429 over the per-caller limit, 503 cannot write, 200 stored.
## `ip` is used only to rate-limit, as a salted hash, and is never written.
func handle_stats(ip: String, msg: Dictionary) -> Dictionary:
	if JSON.stringify(msg).to_utf8_buffer().size() > STATS_MAX_BYTES:
		return {"status": 413}
	var record: Dictionary = clean_stats_record(msg.get("record"))
	if record.is_empty():
		return {"status": 400}
	var now: int = Time.get_ticks_msec()
	var caller: int = (_stats_salt + ip).hash()
	var times: Array = _stats_times.get(caller, [])
	times = times.filter(func(t: int) -> bool: return now - t < FEEDBACK_WINDOW_MSEC)
	if times.size() >= stats_limit_per_hour:
		_stats_times[caller] = times
		return {"status": 429}
	times.append(now)
	_stats_times[caller] = times
	var hour: int = int(Time.get_unix_time_from_system())
	record["t"] = hour - hour % 3600
	return {"status": 200 if _append_line(stats_path, JSON.stringify(record)) else 503}

## The record rebuilt from known fields only, or {} when its shape is wrong.
## Unknown keys are dropped, so nothing identifying can ride along.
static func clean_stats_record(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var rec: Dictionary = raw
	if not (rec.get("mode") is String) or (rec["mode"] as String).length() > STATS_MAX_NAME_CHARS:
		return {}
	if not (rec.get("format") is String) or not STATS_FORMATS.has(rec["format"]):
		return {}
	var length: Variant = rec.get("length_sec")
	if not (length is int or length is float) or float(length) < 0.0 or float(length) > STATS_MAX_LENGTH_SEC:
		return {}
	if not (rec.get("stages") is Array) or (rec["stages"] as Array).size() > STATS_MAX_STAGES:
		return {}
	var stages: Array = []
	for stage: Variant in rec["stages"]:
		if not (stage is String) or (stage as String).length() > STATS_MAX_NAME_CHARS:
			return {}
		stages.append(clean_feedback_text(stage, STATS_MAX_NAME_CHARS, false))
	if not (rec.get("weapons") is Dictionary) or (rec["weapons"] as Dictionary).is_empty() or (rec["weapons"] as Dictionary).size() > STATS_MAX_WEAPONS:
		return {}
	var weapons: Dictionary = {}
	for id: Variant in rec["weapons"]:
		var row: Variant = rec["weapons"][id]
		if not (id is String) or (id as String).length() > STATS_MAX_NAME_CHARS or not (row is Dictionary):
			return {}
		var clean_row: Dictionary = {}
		for field: String in ["damage", "hits", "kos"]:
			var value: Variant = row.get(field)
			if not (value is int or value is float) or float(value) < 0.0 or float(value) > 1.0e7:
				return {}
			clean_row[field] = float(value) if field == "damage" else int(value)
		weapons[clean_feedback_text(id, STATS_MAX_NAME_CHARS, false)] = clean_row
	var winner: Variant = rec.get("winner_weapon", "")
	if not (winner is String) or (winner as String).length() > STATS_MAX_NAME_CHARS:
		return {}
	return {
		"mode": clean_feedback_text(rec["mode"], STATS_MAX_NAME_CHARS, false),
		"format": rec["format"],
		"length_sec": int(length),
		"stages": stages,
		"winner_weapon": clean_feedback_text(winner, STATS_MAX_NAME_CHARS, false),
		"weapons": weapons,
	}

static func _append_line(path: String, line: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		return false
	file.seek_end()
	file.store_line(line)
	file.close()
	return true

## Keeps the peer polled in `_closing` while GitHub answers, then replies.
func _start_feedback(p: Pending, msg: Dictionary, now: int) -> void:
	var closing := Pending.new(p.peer, now + FEEDBACK_REPLY_MSEC)
	_closing.append(closing)
	var ip: String = p.ip
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
	if room == null or room.token == "" or str(msg.get("token", "")) != room.token:
		return false
	# A valid token wins even while the old socket still looks open (a half-dead
	# link after a network change, #580): the old socket is closed, not kept.
	if room.host != peer:
		room.host.close(4002, "replaced")
		_closing.append(Pending.new(room.host, now + CLOSE_GRACE_MSEC))
	room.host = peer
	room.host_gone_msec = 0
	room.last_traffic_msec = now
	var ids: Array = room.clients.keys()
	_send_json(peer, {"t": "room", "code": room.code, "token": room.token, "peers": ids})
	for id: int in ids:
		_send_json(peer, {"t": "joined", "peer": id})
	return true

func _join_room(peer: WebSocketPeer, code: String, now: int, ip: String = "") -> void:
	var room: Room = _rooms.get(code)
	if room == null:
		_refuse(peer, "bad_room")
		return
	if room.clients.size() >= MAX_CLIENTS:
		_refuse(peer, "room_full")
		return
	# Reuses "room_full" so an older client shows a known reason (#580).
	if ip_cap_enabled and not ip.is_empty() and _seats_held_by(ip) >= join_cap_per_ip:
		_refuse(peer, "room_full")
		return
	var id: int = 1
	while room.clients.has(id):
		id += 1
	room.clients[id] = peer
	room.client_ips[id] = ip
	room.last_traffic_msec = now
	_send_json(peer, {"t": "welcome", "peer": id})
	_send_json(room.host, {"t": "joined", "peer": id})

## Client seats the IP holds across every room.
func _seats_held_by(ip: String) -> int:
	var held: int = 0
	for room: Room in _rooms.values():
		for id: int in room.clients.keys():
			if room.client_ips.get(id, "") == ip:
				held += 1
	return held

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
			if room.host.was_string_packet():
				# Text/control frames count as traffic too (#519).
				room.last_traffic_msec = now
				_host_control(room, pkt.get_string_from_utf8(), now)
				continue
			if pkt.size() < 1:
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
				room.last_traffic_msec = now
				if client.was_string_packet():
					continue
				if pkt.size() > CLIENT_FRAME_MAX_BYTES:
					continue # #580: never forward what could overflow the host's buffer
				var framed := PackedByteArray([id])
				framed.append_array(pkt)
				_send_binary(room.host, framed)
		elif state == WebSocketPeer.STATE_CLOSED:
			room.clients.erase(id)
			room.client_ips.erase(id)
			_send_json(room.host, {"t": "left", "peer": id})

## A host control message (issue #580). Only {"t":"drop","peer":N} exists.
func _host_control(room: Room, text: String, now: int) -> void:
	var msg: Variant = _parse_json(text)
	if not (msg is Dictionary) or str(msg.get("t", "")) != "drop":
		return
	var id: int = int(msg.get("peer", 0))
	if not room.clients.has(id):
		return
	var client: WebSocketPeer = room.clients[id]
	room.clients.erase(id)
	room.client_ips.erase(id)
	# Closed through _closing so what the host sent it first (the "closed" notice)
	# is flushed before the socket goes.
	_closing.append(Pending.new(client, now + CLOSE_GRACE_MSEC))
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
