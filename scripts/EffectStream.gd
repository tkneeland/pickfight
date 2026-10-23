extends RefCounted

## The host's one-shot effects, recorded for the Online joiner (issue #976).
##
## Everything the host draws that is not a persistent world object -- a KO
## burst, a hitmarker, a screen shake, a pickup callout, a kill-feed line, the
## stage title card, MATCH POINT, the final-KO zoom, Play of the Round --
## happens on the host from a local event the snapshot cannot carry. The host
## script that plays the effect records it here (`record()`), right where it
## decides to play it and before any per-machine display setting is consulted,
## so the joiner applies its own Reduce flashes, Screen shake and the rest.
## `ControllerServer` turns recording on only while a remote seat is bound and
## drains the queue into each streamed frame's trailer (`SnapshotCapture`'s
## sound trailer, which carries `encode()`'s bytes after the music track). The
## joiner's `RemoteEffects.gd` plays every event with the SAME host script.
##
## Each event is a Dictionary of plain values ("k" names its kind); the bytes
## are `var_to_bytes()`, decoded with `bytes_to_var()`, which never builds an
## object. Preloaded by path; never referenced by a `class_name` (CLAUDE.md).

## Events kept between two streamed frames (30 Hz): more than any real frame
## holds, and a cap on a runaway.
const MAX_EVENTS: int = 48
## The encoded block's byte cap: the trailer's size field is a u16 and the
## rest of the trailer (sounds, track) needs room under it.
const MAX_BYTES: int = 16000
## `HowToPlayDemo.DEMO_VIEWPORT_META`, repeated (not preloaded) to keep this
## script free of the demo's dependencies: the lobby's demo fighters (#219)
## make no effects for a joiner.
const DEMO_VIEWPORT_META: StringName = &"howto_demo"

## Whether `record()` keeps anything: on while a remote seat is bound.
static var recording: bool = false
static var _events: Array = []

## Turns recording on or off; off drops anything queued.
static func set_recording(on: bool) -> void:
	recording = on
	if not on:
		_events.clear()

## Queues one effect of `kind` with its `data` (plain values only). `source`,
## when given, is the node it came from: one inside the lobby's how-to-play
## demo records nothing.
static func record(kind: String, data: Dictionary = {}, source: Node = null) -> void:
	if not recording or _events.size() >= MAX_EVENTS:
		return
	if source != null and source.is_inside_tree():
		var viewport: Viewport = source.get_viewport()
		if viewport != null and viewport.has_meta(DEMO_VIEWPORT_META):
			return
	var ev: Dictionary = data.duplicate(true)
	ev["k"] = kind
	_events.append(ev)

## The events queued since the last call, oldest first; the queue empties.
static func take() -> Array:
	var out: Array = _events
	_events = []
	return out

## The events queued and not yet taken (for scenarios).
static func pending() -> Array:
	return _events.duplicate(true)

## `events` as bytes for the trailer; empty for none. Over MAX_BYTES, the
## oldest half is kept until it fits (one frame never holds that many).
static func encode(events: Array) -> PackedByteArray:
	if events.is_empty():
		return PackedByteArray()
	var kept: Array = events.slice(0, MAX_EVENTS)
	var bytes: PackedByteArray = var_to_bytes(kept)
	while bytes.size() > MAX_BYTES and kept.size() > 1:
		kept = kept.slice(0, kept.size() / 2)
		bytes = var_to_bytes(kept)
	return bytes if bytes.size() <= MAX_BYTES else PackedByteArray()

## `encode()`'s bytes back as events; anything that is not an Array of
## Dictionaries with a String "k" is dropped.
static func decode(bytes: PackedByteArray) -> Array:
	var out: Array = []
	if bytes.size() < 4:
		return out
	var value: Variant = bytes_to_var(bytes)
	if not value is Array:
		return out
	for ev: Variant in value:
		if ev is Dictionary and (ev as Dictionary).get("k") is String:
			out.append(ev)
	return out
