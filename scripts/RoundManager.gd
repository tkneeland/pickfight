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
## Stages to rotate through, in order (ADR-0008). Swapped once per round, in
## `_swap_stage()`. Spawn points come from the active stage's
## `get_spawn_points()`, not from an export here.
@export var stage_scenes: Array[PackedScene] = []
## Node the active stage instance is added to and removed from.
@export var arena_container_path: NodePath
@export var controller_server_path: NodePath
@export var score_label_path: NodePath
## Shown while waiting on roster size, since a WAITING round leaves every
## Player invisible (Player._ready()) -- without this the shared screen looks
## broken (blank arena, no players) instead of "needs one more phone".
@export var waiting_label_path: NodePath
## Shown for round_end_pause_sec once a round resolves. Without this, the
## winner is put through leave_round() the same tick the loser is put through
## eliminate() -- both go inert via the same _go_inert(), so every player
## vanishes at once and the shared screen shows nothing happened. Holds one
## icon+score entry per player slot (see scenes/Main.tscn), refreshed from
## each Player's identity_color and this node's own _scores.
@export var scoreboard_path: NodePath
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
var _scoreboard: Control
## Stage rotation state (ADR-0008). `_stage_index` starts at -1 so the first
## `_swap_stage()` call lands on index 0 rather than 1.
var _stage_index: int = -1
var _current_stage: Node2D
var _stage_spawn_points: Array[Vector2] = []

func _ready() -> void:
	for path in player_paths:
		_players.append(get_node_or_null(path))
	_scores.resize(_players.size())
	_controller_server = get_node_or_null(controller_server_path)
	_waiting_label = get_node_or_null(waiting_label_path) as Label
	_scoreboard = get_node_or_null(scoreboard_path) as Control
	if _scoreboard != null:
		_scoreboard.visible = false
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
		# Drop the last round's scoreboard too, so it can't sit over the
		# centred waiting text when a player left during the round.
		if _scoreboard != null:
			_scoreboard.visible = false
		_set_waiting_text(roster.size())
		return
	if _waiting_label != null:
		_waiting_label.visible = false
	if _scoreboard != null:
		_scoreboard.visible = false
	_swap_stage()
	for slot in roster:
		if slot < 0 or slot >= _players.size() or _players[slot] == null:
			continue
		var spawn: Vector2 = _stage_spawn_points[slot] if slot < _stage_spawn_points.size() else Vector2.ZERO
		_players[slot].start_round(spawn)
	_state = State.ROUND_ACTIVE

## Rotates to the next stage (ADR-0008): frees the outgoing instance, wraps
## `_stage_index` through `stage_scenes`, and caches the new stage's spawn
## points so `_try_start_round()`'s loop above can read them per slot. A no-op
## with an empty `stage_scenes`, leaving `_stage_spawn_points` as it was.
func _swap_stage() -> void:
	if stage_scenes.is_empty():
		return
	var container: Node = get_node_or_null(arena_container_path)
	if container == null:
		return
	if _current_stage != null:
		_current_stage.queue_free()
	_stage_index = (_stage_index + 1) % stage_scenes.size()
	_current_stage = stage_scenes[_stage_index].instantiate()
	container.add_child(_current_stage)
	_stage_spawn_points = _current_stage.get_spawn_points()

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
	_show_scoreboard()
	_state = State.ROUND_END
	_pause_until_msec = Time.get_ticks_msec() + int(round_end_pause_sec * 1000.0)

## Refreshes and reveals the round-end scoreboard: one icon+score entry per
## player slot, read from that slot's Scoreboard/SlotN child (Icon then
## Score, per scenes/Main.tscn) and this node's own _players/_scores.
func _show_scoreboard() -> void:
	if _scoreboard == null:
		return
	for slot in _players.size():
		if slot >= _scoreboard.get_child_count():
			continue
		var entry: Node = _scoreboard.get_child(slot)
		if entry.get_child_count() < 2:
			continue
		var icon: ColorRect = entry.get_child(0) as ColorRect
		var score_label: Label = entry.get_child(1) as Label
		var player: Variant = _players[slot]
		if icon != null and player != null:
			icon.color = player.identity_outline_color()
		if score_label != null:
			score_label.text = str(_scores[slot]) if slot < _scores.size() else "0"
	_scoreboard.visible = true

func _update_score_label() -> void:
	var label: Label = get_node_or_null(score_label_path) as Label
	if label == null:
		return
	var parts: PackedStringArray = PackedStringArray()
	for slot in _scores.size():
		parts.append("P%d: %d" % [slot + 1, _scores[slot]])
	label.text = "  ".join(parts)
