extends Node2D

## King of the Hill (issue #276): a zone on the stage; a player alone inside it
## banks hold time, and the first to `seconds_to_win` takes the round by
## eliminating everyone else. The mode keeps its own `hold_time`; it never
## touches `RoundManager._scores`, the match tally.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

var round_manager: Node
## Where the hill is, in world space. Left at ZERO, `start_round()` puts it at
## the centre of the stage's spawn points.
var hill_position: Vector2 = Vector2.ZERO
var hill_radius: float = 110.0
## Seconds alone in the hill that win the round.
var seconds_to_win: float = 10.0
## slot -> seconds held alone this round.
var hold_time: Dictionary = {}
## The slot that reached `seconds_to_win`, or -1.
var winner_slot: int = -1
## Teams (issue #352): team -> seconds the team held the hill this round. Any
## number of teammates inside hold it together; a mix of colours contests it
## and freezes everyone's clock.
var team_hold: Dictionary = {}
## The team that reached `seconds_to_win`, or -1.
var winner_team: int = -1
## Moving hill (#377): on a stage with `hill_moves`, the hill hops to the next
## of the stage's hill spots every `hill_move_interval` seconds, and
## `hill_warning` is true for the last `hill_warn_sec` before it does, with a
## ring drawn on the spot it is heading for.
var hill_move_interval: float = 30.0
var hill_warn_sec: float = 3.0
var hill_warning: bool = false
var hill_spots: Array[Vector2] = []
var hill_moves: bool = false
var _spot_index: int = 0
var _since_move: float = 0.0
var _won: bool = false
var _slots: Array[int] = []
var _active: bool = false

func setup(manager: Node) -> void:
	round_manager = manager

func start_round(slots: Array[int]) -> void:
	_slots = slots.duplicate()
	hold_time.clear()
	winner_slot = -1
	winner_team = -1
	_won = false
	team_hold.clear()
	for slot: int in _slots:
		hold_time[slot] = 0.0
	_load_stage_hill()
	if hill_position == Vector2.ZERO and round_manager != null:
		var points: Array[Vector2] = round_manager._stage_spawn_points
		if not points.is_empty():
			var sum := Vector2.ZERO
			for p: Vector2 in points:
				sum += p
			hill_position = sum / float(points.size())
	_active = true
	queue_redraw()

## Reads the stage's hill spots (#377): the hill starts on the first. A stage
## with none leaves `hill_position` to the spawn-centre fallback.
func _load_stage_hill() -> void:
	hill_spots.clear()
	hill_moves = false
	hill_warning = false
	_spot_index = 0
	_since_move = 0.0
	var stage: Variant = round_manager.get("_current_stage") if round_manager != null else null
	if stage == null or not is_instance_valid(stage) or not (stage as Object).has_method("get_hill_spots"):
		return
	hill_spots = stage.get_hill_spots()
	hill_moves = bool(stage.hill_moves) and hill_spots.size() > 1
	if hill_position == Vector2.ZERO and not hill_spots.is_empty():
		hill_position = hill_spots[0]

## The spot the hill hops to next, or `hill_position` if it does not move.
func next_hill_position() -> Vector2:
	if not hill_moves:
		return hill_position
	return hill_spots[(_spot_index + 1) % hill_spots.size()]

func _tick_moving_hill(delta: float) -> void:
	_since_move += delta
	if _since_move >= hill_move_interval:
		_spot_index = (_spot_index + 1) % hill_spots.size()
		hill_position = hill_spots[_spot_index]
		_since_move = 0.0
		hill_warning = false
		queue_redraw()
	elif _since_move >= hill_move_interval - hill_warn_sec:
		hill_warning = true
		queue_redraw()

func end_round() -> void:
	_active = false
	_slots.clear()

func team_hold_of(team: int) -> float:
	return float(team_hold.get(team, 0.0))

## Whether the round being played is a Teams round.
func _teams_round() -> bool:
	return round_manager != null and round_manager.has_method("team_mode") and bool(round_manager.team_mode())

func hold_of(slot: int) -> float:
	return float(hold_time.get(slot, 0.0))

## The players alive and inside the hill right now.
func occupants() -> Array[int]:
	var inside: Array[int] = []
	if round_manager == null:
		return inside
	for slot: int in _slots:
		var player: Variant = _player(slot)
		if player != null and bool(player.alive) \
				and (player as Node2D).global_position.distance_to(hill_position) <= hill_radius:
			inside.append(slot)
	return inside

func _player(slot: int) -> Variant:
	if slot < 0 or slot >= round_manager._players.size():
		return null
	var player: Variant = round_manager._players[slot]
	return player if player != null and is_instance_valid(player) else null

func _physics_process(delta: float) -> void:
	if not _active or round_manager == null or _won:
		return
	if hill_moves:
		_tick_moving_hill(delta)
	var inside: Array[int] = occupants()
	if _teams_round():
		_tick_teams(inside, delta)
		return
	if inside.size() != 1:
		return
	var slot: int = inside[0]
	hold_time[slot] = hold_of(slot) + delta
	if hold_time[slot] >= seconds_to_win:
		winner_slot = slot
		_won = true
		for other: int in _slots:
			var player: Variant = _player(other)
			if other != slot and player != null:
				player.eliminate()

## Teams: the team alone inside the hill banks the time; at the target every
## player not on it is eliminated.
func _tick_teams(inside: Array[int], delta: float) -> void:
	var team: int = -2
	for slot: int in inside:
		var t: int = int(round_manager.team_of(slot))
		if team == -2:
			team = t
		elif t != team:
			return
	if team < 0:
		return
	team_hold[team] = team_hold_of(team) + delta
	if team_hold[team] >= seconds_to_win:
		winner_team = team
		_won = true
		for other: int in _slots:
			var player: Variant = _player(other)
			if player != null and int(round_manager.team_of(other)) != team:
				player.eliminate()

func _draw() -> void:
	var colour := Color(1.0, 0.85, 0.2)
	draw_circle(to_local(hill_position), hill_radius, Color(colour, 0.15))
	draw_arc(to_local(hill_position), hill_radius, 0.0, TAU, 48, Color(colour, 0.8), 3.0)
	if hill_warning:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		var warn := Color(1.0, 0.35, 0.2)
		draw_arc(to_local(next_hill_position()), hill_radius, 0.0, TAU, 48, Color(warn, 0.4 + 0.5 * pulse), 4.0)
