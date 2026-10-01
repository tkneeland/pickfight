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
var _slots: Array[int] = []
var _active: bool = false

func setup(manager: Node) -> void:
	round_manager = manager

func start_round(slots: Array[int]) -> void:
	_slots = slots.duplicate()
	hold_time.clear()
	winner_slot = -1
	for slot: int in _slots:
		hold_time[slot] = 0.0
	if hill_position == Vector2.ZERO and round_manager != null:
		var points: Array[Vector2] = round_manager._stage_spawn_points
		if not points.is_empty():
			var sum := Vector2.ZERO
			for p: Vector2 in points:
				sum += p
			hill_position = sum / float(points.size())
	_active = true
	queue_redraw()

func end_round() -> void:
	_active = false
	_slots.clear()

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
	if not _active or round_manager == null or winner_slot != -1:
		return
	var inside: Array[int] = occupants()
	if inside.size() != 1:
		return
	var slot: int = inside[0]
	hold_time[slot] = hold_of(slot) + delta
	if hold_time[slot] >= seconds_to_win:
		winner_slot = slot
		for other: int in _slots:
			var player: Variant = _player(other)
			if other != slot and player != null:
				player.eliminate()

func _draw() -> void:
	var colour := Color(1.0, 0.85, 0.2)
	draw_circle(to_local(hill_position), hill_radius, Color(colour, 0.15))
	draw_arc(to_local(hill_position), hill_radius, 0.0, TAU, 48, Color(colour, 0.8), 3.0)
