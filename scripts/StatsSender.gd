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
static func build_record(stats: RefCounted, mode: String, stages: Array, format: String, length_sec: int, winner_slots: Array, completed: bool = true, rounds_played: int = 0) -> Dictionary:
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
	return record

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
