extends Node

## Sends one piece of player feedback to the relay (issue #262). The relay
## holds the GitHub token and files the issue; this client holds no secret. It
## speaks the relay's WebSocket (wss through Fly's TLS) with a single
## `{"t":"feedback"}` message and waits for `{"t":"feedback_result"}`.
##
## `finished(status)` carries the relay's status: 200 filed, 400 empty,
## 429 rate limited, 502 GitHub refused, 503 relay has no token, and 0 when the
## relay could not be reached or did not answer in time.

signal finished(status: int)

const TIMEOUT_MSEC: int = 10000
const MAX_CHARS: int = 2000

var _peer: WebSocketPeer
var _payload: String = ""
var _deadline_msec: int = 0
var _sent: bool = false
var _done: bool = true

## What the player sees for each status.
static func message_for(status: int) -> String:
	match status:
		200:
			return TranslationServer.translate("FEEDBACK_SENT")
		400:
			return TranslationServer.translate("FEEDBACK_EMPTY")
		429:
			return TranslationServer.translate("FEEDBACK_RATE_LIMITED")
		503:
			return TranslationServer.translate("FEEDBACK_OFFLINE")
		_:
			return TranslationServer.translate("FEEDBACK_FAILED")

## Message text with control characters dropped (newlines kept) and capped.
static func clean(text: String) -> String:
	var out: String = ""
	for i in text.length():
		var code: int = text.unicode_at(i)
		if (code < 32 and code != 10) or code == 127:
			continue
		out += String.chr(code)
		if out.length() >= MAX_CHARS:
			break
	return out

func is_busy() -> bool:
	return not _done

func send(text: String, relay_url: String, version: String, os_name: String, stage: String) -> void:
	_payload = JSON.stringify({"t": "feedback", "text": clean(text), "version": version, "os": os_name, "stage": stage})
	_peer = WebSocketPeer.new()
	_sent = false
	_done = false
	_deadline_msec = Time.get_ticks_msec() + TIMEOUT_MSEC
	if _peer.connect_to_url(relay_url) != OK:
		_finish(0)

func _process(_delta: float) -> void:
	if _done:
		return
	_peer.poll()
	var state: int = _peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _sent:
		_peer.send_text(_payload)
		_sent = true
	while state == WebSocketPeer.STATE_OPEN and _peer.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _peer.get_packet()
		var msg: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if msg is Dictionary and msg.get("t") == "feedback_result":
			_finish(int(msg.get("status", 0)))
			return
	if state == WebSocketPeer.STATE_CLOSED or Time.get_ticks_msec() > _deadline_msec:
		_finish(0)

func _finish(status: int) -> void:
	_done = true
	if _peer != null:
		_peer.close()
	finished.emit(status)
