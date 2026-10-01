extends Node
## The host's side of the room-code relay (issue #239, #212; protocol in the
## header of relay/Relay.gd). Connects out to the relay, announces itself as a
## host, learns its room code, and tracks the remote clients the relay reports
## with `joined` / `left`. Payloads are never interpreted here beyond the
## envelope: the first byte after the relay's peer id is a kind (KIND_INPUT, a
## phone's 8-byte input frame, or KIND_TEXT, a phone's UTF-8 JSON text frame),
## and ControllerServer feeds both to its existing phone paths.
## No `class_name`: consumers preload this by path.

## Envelope kinds (the first payload byte).
const KIND_INPUT: int = 0
const KIND_TEXT: int = 1
## Link states, as `link_state_changed` reports them.
const STATE_OFFLINE: String = "offline"
const STATE_CONNECTING: String = "connecting"
const STATE_ONLINE: String = "online"
const STATE_ERROR: String = "error"
## The socket dropped and the host is reclaiming its room (issue #249).
const STATE_RECONNECTING: String = "reconnecting"
## Seconds between reclaim attempts; the last repeats until the window ends.
const RECONNECT_BACKOFF_SEC: Array[float] = [0.5, 1.0, 2.0, 4.0]

## The relay gave the host a (new) room code; "" when the room is gone.
signal room_code_changed(code: String)
## The link is now "offline", "connecting", "online" or "error".
signal link_state_changed(state: String)
## A remote client entered / left the room.
signal peer_joined(peer: int)
signal peer_left(peer: int)
## A remote client sent an envelope: `kind` and its `payload` bytes.
signal frame_received(peer: int, kind: int, payload: PackedByteArray)

var _socket: WebSocketPeer = null
var _state: String = STATE_OFFLINE
var _room_code: String = ""
var _peers: Dictionary = {} # relay peer id (int) -> true
var _sent_host: bool = false
var _url: String = ""
## The secret the relay gave with the room; proves this host may reclaim it.
var _token: String = ""
## How long the host keeps trying to reclaim; matches the relay's host_grace_sec.
var host_grace_sec: float = 15.0
var _reconnect_deadline_msec: int = 0
var _next_attempt_msec: int = 0
var _attempt: int = 0

## Connects to the relay at `url` (ws://host:port); returns an Error code.
## Online once the relay answers with the room code.
func go_online(url: String) -> int:
	go_offline()
	_url = url
	var err: int = _open_socket()
	if err != OK:
		_set_state(STATE_ERROR)
		return err
	_set_state(STATE_CONNECTING)
	return OK

func _open_socket() -> int:
	var socket := WebSocketPeer.new()
	socket.inbound_buffer_size = 1 << 18
	var err: int = socket.connect_to_url(_url)
	if err != OK:
		return err
	_socket = socket
	_sent_host = false
	return OK

## Test hook: kills only this host's socket, as a network blip would.
func drop_socket_for_test() -> void:
	if _socket != null:
		_socket.close(4001, "test drop")

## Hangs up; every remote client is reported gone.
func go_offline() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	_token = ""
	_drop_room()
	_set_state(STATE_OFFLINE)

## The room code the relay gave this host, or "" when there is no room.
func room_code() -> String:
	return _room_code

## "offline", "connecting", "online" or "error" (the STATE_ constants).
func link_state() -> String:
	return _state

## The relay peer ids currently in the room.
func peers() -> Array[int]:
	var out: Array[int] = []
	for id: int in _peers.keys():
		out.append(id)
	return out

## Sends `payload` to relay peer `peer` (0 broadcasts) under envelope `kind`.
func send_to(peer: int, kind: int, payload: PackedByteArray) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var frame := PackedByteArray([peer, kind])
	frame.append_array(payload)
	_socket.send(frame, WebSocketPeer.WRITE_MODE_BINARY)

## Sends `text` to relay peer `peer` as a KIND_TEXT envelope.
func send_text_to(peer: int, text: String) -> void:
	send_to(peer, KIND_TEXT, text.to_utf8_buffer())

func _process(_delta: float) -> void:
	if _state == STATE_RECONNECTING:
		var now: int = Time.get_ticks_msec()
		if now > _reconnect_deadline_msec:
			_give_up()
			return
		if _socket == null and now >= _next_attempt_msec:
			if _open_socket() != OK:
				_schedule_attempt()
	if _socket == null:
		return
	_socket.poll()
	var ready_state: int = _socket.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN:
		if not _sent_host:
			_sent_host = true
			var hello: Dictionary = {"t": "host"}
			if _state == STATE_RECONNECTING:
				hello["room"] = _room_code
				hello["token"] = _token
			_socket.send_text(JSON.stringify(hello))
		while _socket != null and _socket.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _socket.get_packet()
			if _socket.was_string_packet():
				_handle_control(pkt.get_string_from_utf8())
			else:
				_handle_frame(pkt)
	elif ready_state == WebSocketPeer.STATE_CLOSED:
		_socket = null
		if _state == STATE_ONLINE and _token != "":
			_state_reconnecting()
		elif _state == STATE_RECONNECTING:
			_schedule_attempt()
		else:
			_drop_room()
			_set_state(STATE_ERROR)

func _state_reconnecting() -> void:
	_reconnect_deadline_msec = Time.get_ticks_msec() + int(host_grace_sec * 1000.0)
	_attempt = -1
	_set_state(STATE_RECONNECTING)
	_schedule_attempt()

func _schedule_attempt() -> void:
	_attempt += 1
	var delay: float = RECONNECT_BACKOFF_SEC[mini(_attempt, RECONNECT_BACKOFF_SEC.size() - 1)]
	_next_attempt_msec = Time.get_ticks_msec() + int(delay * 1000.0)

## The grace window ran out: today's behaviour, the room is gone.
func _give_up() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	_token = ""
	_drop_room()
	_set_state(STATE_ERROR)

func _handle_control(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return
	var msg: Dictionary = json.data
	match str(msg.get("t", "")):
		"room":
			var code: String = str(msg.get("code", ""))
			_token = str(msg.get("token", ""))
			if _state == STATE_RECONNECTING and code == _room_code:
				# Reclaimed: keep the peers the relay still lists, drop the rest.
				var still: Array = msg.get("peers", [])
				for id: int in _peers.keys():
					if not still.has(id) and not still.has(float(id)):
						_peers.erase(id)
						peer_left.emit(id)
			else:
				if _state == STATE_RECONNECTING:
					# A fresh room: the old one is gone with everyone in it.
					for id: int in _peers.keys():
						peer_left.emit(id)
					_peers.clear()
				_room_code = code
				room_code_changed.emit(_room_code)
			_set_state(STATE_ONLINE)
		"joined":
			var id: int = int(msg.get("peer", 0))
			if id > 0 and not _peers.has(id):
				_peers[id] = true
				peer_joined.emit(id)
		"left":
			var id: int = int(msg.get("peer", 0))
			if _peers.erase(id):
				peer_left.emit(id)
		"error":
			if _socket != null:
				_socket.close()
				_socket = null
			_token = ""
			_drop_room()
			_set_state(STATE_ERROR)

func _handle_frame(pkt: PackedByteArray) -> void:
	if pkt.size() < 2:
		return
	var id: int = pkt[0]
	if not _peers.has(id):
		return
	frame_received.emit(id, pkt[1], pkt.slice(2))

func _drop_room() -> void:
	for id: int in _peers.keys():
		peer_left.emit(id)
	_peers.clear()
	if _room_code != "":
		_room_code = ""
		room_code_changed.emit("")

func _set_state(state: String) -> void:
	if state != _state:
		_state = state
		link_state_changed.emit(state)
