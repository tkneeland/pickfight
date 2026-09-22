extends SceneTree

## Headless WebSocket probe used as the real-dependency fixture for the
## controller transport. It speaks the same 8-byte little-endian float32 wire
## format the phone page does, so the host under test is exercised through its
## real network seam rather than through a stub.
##
##   godot --headless --path . -s tools/ws_probe_client.gd -- --sequence=direction
##
## Arguments (after `--`):
##   --port=8081          WebSocket port of the host under test
##   --sequence=<name>    direction | reach | release
##
## Two probes run concurrently bind player slots 0 and 1.

## One frame is sent per `_process` tick; the tick rate is capped so each step
## of a sequence spans several host physics frames and is therefore observable.
const PROBE_FPS: int = 20
const CONNECT_TIMEOUT_SEC: float = 5.0
const DEFAULT_PORT: int = 8081
const DEFAULT_SEQUENCE: String = "direction"

var _peer: WebSocketPeer = WebSocketPeer.new()
var _frames: Array[Vector2] = []
var _index: int = 0
var _closing: bool = false
var _waited: float = 0.0
var _port: int = DEFAULT_PORT
var _sequence: String = DEFAULT_SEQUENCE

func _initialize() -> void:
	Engine.max_fps = PROBE_FPS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--sequence="):
			_sequence = arg.trim_prefix("--sequence=")

	_frames = _build_sequence(_sequence)
	if _frames.is_empty():
		printerr("PROBE: unknown sequence '%s' (expected direction, reach or release)" % _sequence)
		quit(2)
		return

	# `put_packet` always writes a binary frame in Godot 4.6 (text frames go
	# through `send_text`), so there is no write mode to select.
	var url: String = "ws://127.0.0.1:%d" % _port
	var err: int = _peer.connect_to_url(url)
	if err != OK:
		printerr("PROBE: connect_to_url(%s) failed with error %d" % [url, err])
		quit(3)
		return
	print("PROBE %s connecting to %s (%d frames)" % [_sequence, url, _frames.size()])

func _process(delta: float) -> bool:
	_peer.poll()
	var state: int = _peer.get_ready_state()

	if state == WebSocketPeer.STATE_CONNECTING:
		_waited += delta
		if _waited > CONNECT_TIMEOUT_SEC:
			printerr("PROBE: timed out waiting for the host to accept the handshake")
			return true
		return false

	if state == WebSocketPeer.STATE_OPEN:
		if _index < _frames.size():
			var v: Vector2 = _frames[_index]
			_peer.put_packet(_encode(v))
			print("PROBE %s frame=%d v=(%.4f, %.4f)" % [_sequence, _index, v.x, v.y])
			_index += 1
		elif not _closing:
			_closing = true
			_peer.close(1000, "probe complete")
		return false

	if state == WebSocketPeer.STATE_CLOSING:
		return false

	print("PROBE %s done frames=%d close_code=%d" % [_sequence, _index, _peer.get_close_code()])
	return true

func _encode(v: Vector2) -> PackedByteArray:
	var pkt: PackedByteArray = PackedByteArray()
	pkt.resize(8)
	pkt.encode_float(0, v.x)
	pkt.encode_float(4, v.y)
	return pkt

func _build_sequence(name: String) -> Array[Vector2]:
	match name:
		"direction":
			return [Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0), Vector2(0, 1)]
		"reach":
			return [Vector2(0.25, 0), Vector2(0.5, 0), Vector2(1, 0)]
		"release":
			var frames: Array[Vector2] = []
			for i in 30:
				frames.append(Vector2(1, 0))
			for i in 60:
				frames.append(Vector2.ZERO)
			return frames
		_:
			return []
