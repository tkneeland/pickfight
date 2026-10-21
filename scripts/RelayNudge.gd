extends RefCounted
## The Couch lobby's "Not connecting? Join over the internet" nudge (#727).
##
## LAN stays the default. Once the join QR has been on screen for `delay_msec`
## with no phone seated, the lobby shows a one-line button under it that opens
## the #683 relay room. It hides for good, for this lobby, the moment a phone
## sits or internet join is on. Nothing here opens a room by itself.

const DELAY_MSEC: int = 30000

var delay_msec: int = DELAY_MSEC
var _qr_since_msec: int = 0
var _qr_on: bool = false
var _done: bool = false

## A fresh lobby: the clock and the latch start over.
func reset() -> void:
	_qr_on = false
	_done = false

## Backdates the QR's first showing so the delay has passed (scenarios).
func expire(now_msec: int) -> void:
	_qr_since_msec = now_msec - delay_msec
	_qr_on = true

## Whether the nudge shows at `now_msec`. `qr_showing` is a Couch join QR on
## screen; `phone_seated` a phone holds a seat; `internet_on` the relay room is open.
func update(now_msec: int, qr_showing: bool, phone_seated: bool, internet_on: bool) -> bool:
	if _done:
		return false
	if phone_seated or internet_on:
		_done = true
		return false
	if not qr_showing:
		_qr_on = false
		return false
	if not _qr_on:
		_qr_on = true
		_qr_since_msec = now_msec
	return now_msec - _qr_since_msec >= delay_msec
