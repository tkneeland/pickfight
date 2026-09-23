extends Node

## Round/session loop (ADR-0004), built on top of `ControllerServer`'s roster
## (ADR-0007). The session itself is endless -- this node just keeps starting
## a new elimination round each time the current one is down to one player
## standing, for as long as enough of the roster is present to play.
##
## "The roster" means claimed slots (`ControllerServer.claimed_slots()`):
## someone whose controller drops mid-round keeps their slot for the rest of
## that round -- their `Player` just sits wherever the last input left it,
## drifting to rest, exactly as an unplugged controller always has -- and is
## only dropped from the roster between rounds, when
## `expire_disconnected_claims()` runs.

@export var player_paths: Array[NodePath] = []
## Spawn position for each slot, in `player_paths` order.
@export var spawn_points: Array[Vector2] = []
@export var controller_server_path: NodePath
@export var score_label_path: NodePath
## Shown while waiting on roster size, since a WAITING round leaves every
## Player invisible (Player._ready()) -- without this the shared screen looks
## broken (blank arena, no players) instead of "needs one more phone".
@export var waiting_label_path: NodePath
## Shown for round_end_pause_sec once a round resolves. Without this, the
## winner is put through leave_round() the same tick the loser is put through
## eliminate() -- both go inert via the same _go_inert(), so every player
## vanishes at once and the shared screen shows nothing happened.
@export var round_end_label_path: NodePath
## A round will not start with fewer roster entries than this -- one player
## cannot be "eliminated down to one survivor".
@export var min_players_to_start: int = 2
## Pause after a round resolves, so the shared screen has a moment where a
## win is visible before the next round's players pop back in.
@export var round_end_pause_sec: float = 2.0

enum State { WAITING, ROUND_ACTIVE, ROUND_END }

var _state: int = State.WAITING
var _pause_until_msec: int = 0
var _players: Array = []
var _scores: PackedInt32Array = PackedInt32Array()
var _controller_server: Node
var _waiting_label: Label
var _round_end_label: Label

func _ready() -> void:
	for path in player_paths:
		_players.append(get_node_or_null(path))
	_scores.resize(_players.size())
	_controller_server = get_node_or_null(controller_server_path)
	_waiting_label = get_node_or_null(waiting_label_path) as Label
	_round_end_label = get_node_or_null(round_end_label_path) as Label
	if _round_end_label != null:
		_round_end_label.visible = false
	_update_score_label()
	_set_waiting_text(0)

func _process(_delta: float) -> void:
	match _state:
		State.WAITING:
			_try_start_round()
		State.ROUND_ACTIVE:
			_check_round_end()
		State.ROUND_END:
			if Time.get_ticks_msec() >= _pause_until_msec:
				if _controller_server != null:
					_controller_server.expire_disconnected_claims()
				_state = State.WAITING
				_try_start_round()

## Enough of the roster present and idle: bring every claimed player into
## the arena. Slots nobody has claimed stay exactly as `Player._ready()`
## (or the previous round's `leave_round()`) left them -- inert and hidden.
func _try_start_round() -> void:
	if _controller_server == null:
		return
	var roster: Array[int] = _controller_server.claimed_slots()
	if roster.size() < min_players_to_start:
		_set_waiting_text(roster.size())
		return
	if _waiting_label != null:
		_waiting_label.visible = false
	if _round_end_label != null:
		_round_end_label.visible = false
	for slot in roster:
		if slot < 0 or slot >= _players.size() or _players[slot] == null:
			continue
		var spawn: Vector2 = spawn_points[slot] if slot < spawn_points.size() else Vector2.ZERO
		_players[slot].start_round(spawn)
	_state = State.ROUND_ACTIVE

func _set_waiting_text(connected: int) -> void:
	if _waiting_label == null:
		return
	_waiting_label.visible = true
	_waiting_label.text = "Waiting for players: %d / %d connected" % [connected, min_players_to_start]

## A round ends the instant one or zero players are still standing --
## whichever came from a ring-out or the last hit that crossed DEATH_DAMAGE.
## The lone survivor (if any) scores the round and is returned to the same
## inert state a loser ends up in, via `leave_round()` rather than
## `eliminate()`, since finishing a round alive is not a death.
func _check_round_end() -> void:
	var alive_slots: Array[int] = []
	for slot in _players.size():
		var player: Variant = _players[slot]
		if player != null and player.alive:
			alive_slots.append(slot)
	if alive_slots.size() > 1:
		return
	if alive_slots.size() == 1:
		var winner_slot: int = alive_slots[0]
		_scores[winner_slot] += 1
		_players[winner_slot].leave_round()
		_update_score_label()
		_set_round_end_text("P%d wins the round!" % (winner_slot + 1))
	else:
		_set_round_end_text("No survivors -- round over!")
	_state = State.ROUND_END
	_pause_until_msec = Time.get_ticks_msec() + int(round_end_pause_sec * 1000.0)

func _set_round_end_text(text: String) -> void:
	if _round_end_label == null:
		return
	_round_end_label.visible = true
	_round_end_label.text = text

func _update_score_label() -> void:
	var label: Label = get_node_or_null(score_label_path) as Label
	if label == null:
		return
	var parts: PackedStringArray = PackedStringArray()
	for slot in _scores.size():
		parts.append("P%d: %d" % [slot + 1, _scores[slot]])
	label.text = "  ".join(parts)
