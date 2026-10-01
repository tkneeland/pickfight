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

## Connects to the relay at `url` (ws://host:port); returns an Error code.
## Online once the relay answers with the room code.
func go_online(url: String) -> int:
	go_offline()
	var socket := WebSocketPeer.new()
	socket.inbound_buffer_size = 1 << 18
	var err: int = socket.connect_to_url(url)
	if err != OK:
		_set_state(STATE_ERROR)
		return err
	_socket = socket
	_sent_host = false
	_set_state(STATE_CONNECTING)
	return OK

## Hangs up; every remote client is reported gone.
func go_offline() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
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
	if _socket == null:
		return
	_socket.poll()
	var ready_state: int = _socket.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN:
		if not _sent_host:
			_sent_host = true
			_socket.send_text(JSON.stringify({"t": "host"}))
		while _socket != null and _socket.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _socket.get_packet()
			if _socket.was_string_packet():
				_handle_control(pkt.get_string_from_utf8())
			else:
				_handle_frame(pkt)
	elif ready_state == WebSocketPeer.STATE_CLOSED:
		_socket = null
		_drop_room()
		_set_state(STATE_ERROR)

func _handle_control(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return
	var msg: Dictionary = json.data
	match str(msg.get("t", "")):
		"room":
			_room_code = str(msg.get("code", ""))
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
