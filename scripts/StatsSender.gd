extends Node

## Anonymous match telemetry (issue #372). At match end the host sends one
## record to the relay: per-weapon damage, hits and KOs by real players, the
## mode, the stages played, the format and the match length. Nothing that names
## a player, a seat, a device or an account is ever in it; the relay never logs
## or stores an IP.
##
## Transport. The relay (Godot `accept_stream`) cannot serve a plain HTTP POST,
## so, like the feedback button (#262, `FeedbackSender.gd`), the record rides
## the same WebSocket the game already reaches: one `{"t":"stats","record":{}}`
## message, answered by `{"t":"stats_result","status":N}`. Fire and forget: the
## caller ignores `finished`, and any failure is silent (status 0).
##
## `finished(status)`: 200 stored, 400 invalid, 413 too large, 429 rate
## limited, 503 relay cannot store, 0 unreachable or no answer in time.

signal finished(status: int)

const TIMEOUT_MSEC: int = 10000
const SfxScript := preload("res://scripts/Sfx.gd")
const MatchStatsScript := preload("res://scripts/MatchStats.gd")
## The most ping entries a record carries (Relay.STATS_MAX_PING_ENTRIES).
const PING_MAX_ENTRIES: int = 8
## The most any event counter may say (Relay.STATS_MAX_EVENT_COUNT).
const EVENT_COUNT_MAX: int = 100000

var _peer: WebSocketPeer
var _payload: String = ""
var _deadline_msec: int = 0
var _sent: bool = false
var _done: bool = true

## The record for one match, or {} when no real player landed a damaging hit.
## `winner_slots` is the winning player (or team's players), used only to name
## the winner's weapon; no slot appears in the record.
## `completed` false marks a match that ended without a winner (#643): the
## record then has no `winner_weapon`.
static func build_record(stats: RefCounted, mode: String, stages: Array, format: String, length_sec: int, winner_slots: Array, completed: bool = true, rounds_played: int = 0, with_events: bool = true, with_joins: bool = true, live_ctf: Dictionary = {}) -> Dictionary:
	if stats.weapon_damage.is_empty():
		return {}
	var weapons: Dictionary = {}
	for id: String in stats.weapon_damage:
		weapons[id] = {
			"damage": snappedf(float(stats.weapon_damage[id]), 0.1),
			"hits": int(stats.weapon_hits.get(id, 0)),
			"kos": int(stats.weapon_kos.get(id, 0)),
		}
	var names: Array = []
	for stage: Variant in stages:
		names.append(str(stage))
	var record: Dictionary = {
		"mode": mode if mode != "" else "classic",
		"stages": names,
		"format": format,
		"length_sec": maxi(0, length_sec),
		"completed": completed,
		"rounds_played": maxi(0, rounds_played),
		"weapons": weapons,
	}
	if completed:
		record["winner_weapon"] = stats.best_weapon_of(winner_slots)
	# #1195: an Online match's per-seat ping statistics, only for joiners who
	# share stats themselves (D8), at most PING_MAX_ENTRIES (the relay rejects
	# a longer list) with the most samples kept. Never a slot, name or colour.
	var ping_list: Variant = stats.get("ping")
	if ping_list is Array:
		var entries: Array = MatchStatsScript.ping_entries(ping_list, true, PING_MAX_ENTRIES)
		if not entries.is_empty():
			record["ping"] = entries
	if with_events:
		var events: Dictionary = _build_events(stats, with_joins, live_ctf)
		if not events.is_empty():
			record["events"] = events
	return record

## A Couch lobby's record for phones that joined but no match carried (#1271):
## {"kind": "lobby", "events": {"joins": {...}}}, or {} with nothing counted.
static func build_lobby_record(joins: Variant) -> Dictionary:
	var counts: Dictionary = _counts_of(joins, MatchStatsScript.JOIN_EVENT_KEYS)
	if counts.is_empty():
		return {}
	return {"kind": "lobby", "events": {"joins": counts}}

## Whether the notice that lists the events has been acknowledged (#1271).
static func events_allowed(host: RefCounted) -> bool:
	return host.telemetry_notice_current()

## Issue #1271: the optional `events` object for live bug detection. Counts and
## summaries only (no slot, name, colour, device or id); each sub-object is
## left out when it has nothing, and `events` itself when empty.
static func _build_events(stats: RefCounted, with_joins: bool = true, live_ctf: Dictionary = {}) -> Dictionary:
	var events: Dictionary = {}
	# An abandoned match's live round is added to a COPY of the match's counters,
	# never to the stats (the round reports itself when it ends).
	var ctf_source: Dictionary = {}
	var banked: Variant = stats.get("ctf_events")
	for key: String in MatchStatsScript.CTF_EVENT_KEYS:
		ctf_source[key] = (int((banked as Dictionary).get(key, 0)) if banked is Dictionary else 0) + int(live_ctf.get(key, 0))
	var ctf: Dictionary = _counts_of(ctf_source, MatchStatsScript.CTF_EVENT_KEYS)
	if not ctf.is_empty():
		events["ctf"] = ctf
	var joins: Dictionary = _counts_of(stats.get("join_events"), MatchStatsScript.JOIN_EVENT_KEYS) if with_joins else {}
	if not joins.is_empty():
		events["joins"] = joins
	var relay_ping: Variant = stats.get("relay_ping")
	if relay_ping is Array:
		var entries: Array = _relay_ping_entries(relay_ping)
		if not entries.is_empty():
			events["relay_ping"] = entries
	return events

## The relay phones' {avg, p95, max, n} entries as ints clamped to -1..PING_MAX_MSEC,
## at most PING_MAX_ENTRIES, those with the most samples kept.
static func _relay_ping_entries(list: Array) -> Array:
	var out: Array = []
	for entry: Variant in list:
		if not entry is Dictionary:
			continue
		var clean: Dictionary = {}
		for field: String in ["avg", "p95", "max", "n"]:
			var v: Variant = (entry as Dictionary).get(field, -1)
			clean[field] = clampi(int(v), -1, MatchStatsScript.PING_MAX_MSEC) if (v is int or (v is float and is_finite(v))) else -1
		out.append(clean)
	if out.size() > PING_MAX_ENTRIES:
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["n"]) > int(b["n"]))
		out.resize(PING_MAX_ENTRIES)
	return out

## `source`'s `keys` as non-negative ints, {} when every one is zero or missing.
static func _counts_of(source: Variant, keys: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	if not source is Dictionary:
		return out
	var any: bool = false
	for key: String in keys:
		var v: int = clampi(int((source as Dictionary).get(key, 0)), 0, EVENT_COUNT_MAX)
		out[key] = v
		any = any or v > 0
	return out if any else {}

## Whether `tree` is a scripted run: a `-s` script's loop (the scenario runner,
## a probe) or a `--bots` launch. Mirrors the guard that keeps those off the
## owner's settings (`Sfx.is_script_main_loop`).
static func is_scripted(tree: SceneTree, args: PackedStringArray) -> bool:
	if SfxScript.is_script_main_loop(tree):
		return true
	for arg: String in args:
		if arg == "--bots" or arg.begins_with("--bots="):
			return true
	return false

## The one gate: sharing is on, the one-time notice has been seen (#617), and
## the run is not scripted (by `scripted`, or by a `--bots` launch argument).
static func should_send(host: RefCounted, scripted: bool, args: PackedStringArray) -> bool:
	return host.share_stats and host.telemetry_notice_seen and not scripted and not is_scripted(null, args)

func is_busy() -> bool:
	return not _done

func send(record: Dictionary, relay_url: String) -> void:
	add_to_group("telemetry_sender")
	_payload = JSON.stringify({"t": "stats", "record": record})
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
		var msg: Variant = JSON.parse_string(_peer.get_packet().get_string_from_utf8())
		if msg is Dictionary and msg.get("t") == "stats_result":
			_finish(int(msg.get("status", 0)))
			return
	if state == WebSocketPeer.STATE_CLOSED or Time.get_ticks_msec() > _deadline_msec:
		_finish(0)

func _finish(status: int) -> void:
	_done = true
	if _peer != null:
		_peer.close()
	finished.emit(status)
