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
##   --sequence=<name>    direction | reach | release | hold | stall
##   --expect-slot=<n>    fail loudly (exit 4) if the host binds a different
##                        slot, so a two-probe cross-talk check cannot pass by
##                        accident when both probes land on the same player
##
## Sequences:
##   direction  four unit vectors on the four axes: arm angle sweep
##   reach      three lengths on the +Y axis: arm extension sweep. Deliberately
##              on a different axis from `direction` so no vector can appear in
##              both sequences and a cross-talk check stays decisive.
##   release    a held drag then a long run of (0,0): release easing
##   hold       (1,0) forever, never closing -- for killing the probe abruptly
##              (kill -9) to prove the host notices a controller that vanished
##   stall      a few held frames, then silence with the socket still open --
##              the locked-phone case, proving the host's input deadline fires
##
## Two probes run concurrently bind player slots 0 and 1.

## One frame is sent per `_process` tick; the tick rate is capped so each step
## of a sequence spans several host physics frames and is therefore observable.
const PROBE_FPS: int = 20
const CONNECT_TIMEOUT_SEC: float = 5.0
const DEFAULT_PORT: int = 8081
const DEFAULT_SEQUENCE: String = "direction"
## While repeating, print one line per this many sends instead of every send.
const REPEAT_LOG_EVERY: int = 20
## Give up if the host never drops a stalled probe (the deadline is host-side).
const STALL_TIMEOUT_SEC: float = 30.0

## What to do once the frame list runs out.
enum AfterFrames {
	CLOSE,   # clean close, the ordinary end of a sequence
	REPEAT,  # keep resending, never close
	SILENT,  # stop sending but hold the socket open
}

var _peer: WebSocketPeer = WebSocketPeer.new()
var _frames: Array[Vector2] = []
var _index: int = 0
var _sent: int = 0
var _closing: bool = false
var _waited: float = 0.0
var _stalled_for: float = 0.0
var _announced_stall: bool = false
var _port: int = DEFAULT_PORT
var _sequence: String = DEFAULT_SEQUENCE
var _after: AfterFrames = AfterFrames.CLOSE
var _slot: int = -1
var _expect_slot: int = -1

func _initialize() -> void:
	Engine.max_fps = PROBE_FPS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--sequence="):
			_sequence = arg.trim_prefix("--sequence=")
		elif arg.begins_with("--expect-slot="):
			_expect_slot = int(arg.trim_prefix("--expect-slot="))

	_frames = _build_sequence(_sequence)
	_after = _after_frames(_sequence)
	if _frames.is_empty():
		printerr("PROBE: unknown sequence '%s' (expected direction, reach, release, hold or stall)" % _sequence)
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
			quit(5)
			return true
		return false

	if state == WebSocketPeer.STATE_OPEN:
		if not _read_host_frames():
			return true
		return _send_next(delta)

	if state == WebSocketPeer.STATE_CLOSING:
		return false

	print("PROBE %s done frames=%d slot=%d close_code=%d reason='%s'" % [
		_sequence, _sent, _slot, _peer.get_close_code(), _peer.get_close_reason()])
	_check_expected_slot()
	return true

## Returns false when the probe should stop (a slot mismatch is fatal).
func _read_host_frames() -> bool:
	while _peer.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _peer.get_packet()
		if not _peer.was_string_packet():
			continue
		var msg: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(msg) != TYPE_DICTIONARY or not msg.has("slot"):
			continue
		_slot = int(msg["slot"])
		print("PROBE %s bound slot=%d" % [_sequence, _slot])
		if _expect_slot >= 0 and _slot != _expect_slot:
			printerr("PROBE %s FAIL: expected slot %d but the host bound slot %d" % [
				_sequence, _expect_slot, _slot])
			quit(4)
			_peer.close(1000, "wrong slot")
			return false
	return true

func _send_next(delta: float) -> bool:
	if _index < _frames.size():
		_put(_frames[_index])
		print("PROBE %s frame=%d v=(%.4f, %.4f)" % [_sequence, _index, _frames[_index].x, _frames[_index].y])
		_index += 1
		return false

	match _after:
		AfterFrames.REPEAT:
			var v: Vector2 = _frames[_frames.size() - 1]
			_put(v)
			if _sent % REPEAT_LOG_EVERY == 0:
				print("PROBE %s holding sent=%d v=(%.4f, %.4f)" % [_sequence, _sent, v.x, v.y])
			return false
		AfterFrames.SILENT:
			if not _announced_stall:
				_announced_stall = true
				print("PROBE %s stalling: socket stays open, sending nothing" % _sequence)
			_stalled_for += delta
			if _stalled_for > STALL_TIMEOUT_SEC:
				printerr("PROBE %s FAIL: host never dropped a silent controller after %.1fs" % [
					_sequence, _stalled_for])
				quit(6)
				return true
			return false
		_:
			if not _closing:
				_closing = true
				_peer.close(1000, "probe complete")
			return false

func _check_expected_slot() -> void:
	if _expect_slot < 0:
		return
	if _slot == _expect_slot:
		print("PROBE %s slot check OK (slot=%d)" % [_sequence, _slot])
	elif _slot < 0:
		printerr("PROBE %s FAIL: expected slot %d but the host never sent a slot frame" % [
			_sequence, _expect_slot])
		quit(4)

func _put(v: Vector2) -> void:
	_peer.put_packet(_encode(v))
	_sent += 1

func _encode(v: Vector2) -> PackedByteArray:
	var pkt: PackedByteArray = PackedByteArray()
	pkt.resize(8)
	pkt.encode_float(0, v.x)
	pkt.encode_float(4, v.y)
	return pkt

func _after_frames(name: String) -> AfterFrames:
	match name:
		"hold":
			return AfterFrames.REPEAT
		"stall":
			return AfterFrames.SILENT
		_:
			return AfterFrames.CLOSE

func _build_sequence(name: String) -> Array[Vector2]:
	match name:
		"direction":
			return [Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0), Vector2(0, 1)]
		"reach":
			# On +Y, not +X: `direction` owns the X axis, and sharing the vector
			# (1,0) between the two sequences would let a cross-talk check pass
			# while slots were genuinely swapped. Lengths still come out
			# 50 / 80 / 140 via lerp(20, 140, t).
			return [Vector2(0, 0.25), Vector2(0, 0.5), Vector2(0, 1)]
		"release":
			var frames: Array[Vector2] = []
			for i in 30:
				frames.append(Vector2(1, 0))
			for i in 60:
				frames.append(Vector2.ZERO)
			return frames
		"hold":
			return [Vector2(1, 0)]
		"stall":
			var held: Array[Vector2] = []
			for i in 10:
				held.append(Vector2(1, 0))
			return held
		_:
			return []
