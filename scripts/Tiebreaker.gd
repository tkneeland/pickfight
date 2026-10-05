extends Node

## The one Sudden Death tiebreaker (issues #554, #556): the players a round
## ended level between play on, one hit to KO (`SuddenDeath.gd`), and the
## stage escalates so a cautious pair cannot stall it. After `RAIN_START_SEC`
## the existing `FallingRock` hazard rains over the stage (announced "Sudden
## Death!"), faster every `RAIN_RAMP_STEP_SEC`; a rock is a one-hit KO like any
## damaging hit, and a hit on a shield or open canopy face is a block (#569).
## At `OVERTIME_BACKSTOP_SEC` a round somehow still tied ends as a draw: nobody
## scores and the announcer says "Draw!".
##
## `RoundManager` starts one when a round ends level in any mode (the last
## players or teams going down on the same tick, `_start_tiebreaker`), and
## Stock's time limit starts one in place when the most lives are tied
## (`begin_overtime`). A double KO inside it replays it among the same players,
## keeping this clock and the rain. The rain and every rock stop at round end.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const SuddenDeathScript := preload("res://scripts/SuddenDeath.gd")
const FallingRockScene: PackedScene = preload("res://scenes/parts/FallingRock.tscn")

## Seconds of tiebreaker before the first rock.
const RAIN_START_SEC: float = 15.0
## Seconds between rocks when the rain starts, and what each ramp step
## multiplies that gap by, down to a floor of `RAIN_MIN_INTERVAL_SEC`.
const RAIN_START_INTERVAL_SEC: float = 2.0
const RAIN_RAMP_STEP_SEC: float = 5.0
const RAIN_RAMP_FACTOR: float = 0.7
const RAIN_MIN_INTERVAL_SEC: float = 0.4
## Seconds of tiebreaker after which a still-tied round ends as a draw.
const OVERTIME_BACKSTOP_SEC: float = 60.0
## Rocks start this far above the stage's view and this far in from its sides.
const RAIN_TOP_MARGIN: float = 40.0
const RAIN_SIDE_MARGIN: float = 80.0

## An announcer line (#370); the Announcer listens for it.
signal callout(sound: StringName)

## Whether starting calls "Sudden Death!". `RoundManager` turns it off and
## announces through its banner (or Stock's "Overtime!") instead.
var announce_start: bool = true
var round_manager: Node
## Seconds since the tiebreaker began; not reset by a replay.
var elapsed: float = 0.0
## Rocks dropped so far.
var rocks_dropped: int = 0
## Whether the backstop ended it as a draw.
var drawn: bool = false

var _one_hit: Node = null
var _rain_on: bool = false
var _rocks: Array = []
var _rain_timer: float = 0.0
var _rain_rng: RandomNumberGenerator
var _slots: Array[int] = []
## slot -> the Callable connected to that player's `eliminated`.
var _handlers: Dictionary = {}

func setup(manager: Node) -> void:
	round_manager = manager

## Starts the tiebreaker among `slots`, or re-arms it among them after a
## double KO replay, keeping the clock and any rocks already falling.
func start_round(slots: Array[int]) -> void:
	if round_manager == null:
		return
	var first: bool = _one_hit == null
	_slots = slots.duplicate()
	if first:
		_one_hit = SuddenDeathScript.new()
		_one_hit.announce_start = false
		add_child(_one_hit)
		_one_hit.setup(round_manager)
	_one_hit.start_round(_slots)
	_watch_eliminations()
	if first and announce_start:
		callout.emit(&"announce_sudden_death")

func end_round() -> void:
	_unwatch_eliminations()
	if _one_hit != null and is_instance_valid(_one_hit):
		_one_hit.end_round()
		_one_hit.queue_free()
	_one_hit = null
	_stop_rain()
	_rain_on = false
	_slots.clear()
	elapsed = 0.0
	drawn = false

func connected_count() -> int:
	return _one_hit.connected_count() if _one_hit != null else 0

## Whether the rocks are falling.
func rain_on() -> bool:
	return _rain_on

func _physics_process(delta: float) -> void:
	if _one_hit == null or drawn:
		return
	elapsed += delta
	if elapsed >= OVERTIME_BACKSTOP_SEC:
		_end_in_draw()
	elif elapsed >= RAIN_START_SEC:
		_tick_rain(delta)

# --- Rain ----------------------------------------------------------------------

## Seconds between rocks `at` seconds into the tiebreaker: the start gap,
## shrunk by `RAIN_RAMP_FACTOR` every `RAIN_RAMP_STEP_SEC`.
func rain_interval(at: float) -> float:
	var steps: int = maxi(int(floor((at - RAIN_START_SEC) / RAIN_RAMP_STEP_SEC)), 0)
	return maxf(RAIN_START_INTERVAL_SEC * pow(RAIN_RAMP_FACTOR, steps), RAIN_MIN_INTERVAL_SEC)

## Rocks still in the air or warning.
func live_rock_count() -> int:
	var live: Array = []
	for rock: Variant in _rocks:
		if is_instance_valid(rock) and not (rock as Node).is_queued_for_deletion():
			live.append(rock)
	_rocks = live
	return _rocks.size()

func _tick_rain(delta: float) -> void:
	if not _rain_on:
		_rain_on = true
		_rain_timer = 0.0
		callout.emit(&"announce_sudden_death")
	_rain_timer -= delta
	if _rain_timer <= 0.0:
		_drop_rock()
		_rain_timer += rain_interval(elapsed)

func _drop_rock() -> void:
	if _rain_rng == null:
		_rain_rng = round_manager.match_rng("sudden_death_rain") if round_manager.has_method("match_rng") \
			else RandomNumberGenerator.new()
	var view := Rect2(-800.0, -450.0, 1600.0, 900.0)
	var stage: Variant = round_manager.get("_current_stage")
	if stage != null and is_instance_valid(stage) and (stage as Object).has_method("get_view_rect"):
		view = stage.get_view_rect()
	var margin: float = minf(RAIN_SIDE_MARGIN, view.size.x * 0.25)
	var x: float = _rain_rng.randf_range(view.position.x + margin, view.end.x - margin)
	var rock: Node2D = FallingRockScene.instantiate()
	rock.set("auto_drop", false)
	rock.set("one_shot", true)
	add_child(rock)
	rock.global_position = Vector2(x, view.position.y - RAIN_TOP_MARGIN)
	if rock.drop_now():
		rocks_dropped += 1
		live_rock_count()
		_rocks.append(rock)
	else:
		rock.queue_free()

## Stops the rain and clears every rock still out (round end, a draw).
func _stop_rain() -> void:
	for rock: Variant in _rocks:
		if is_instance_valid(rock):
			if (rock as Node).get_parent() == self:
				remove_child(rock)
			(rock as Node).queue_free()
	_rocks.clear()
	_rain_on = false
	_rain_timer = 0.0
	rocks_dropped = 0

# --- The backstop --------------------------------------------------------------

## Still tied at the backstop: everyone standing leaves the round without being
## eliminated (no KO is counted), so the round ends with nobody to score.
func _end_in_draw() -> void:
	drawn = true
	_stop_rain()
	for slot: int in _slots:
		var player: Variant = round_manager._players[slot]
		if player != null and is_instance_valid(player):
			player.leave_round()
	var mode: Variant = round_manager.get("_game_mode_node")
	if mode != null and is_instance_valid(mode) and (mode as Object).has_method("tiebreak_drawn"):
		mode.tiebreak_drawn(_slots)
	round_manager.set("_survivor_slot", -1)
	round_manager.set("_survivor_team", -1)
	callout.emit(&"announce_draw")

# --- Shots ---------------------------------------------------------------------

func _watch_eliminations() -> void:
	_unwatch_eliminations()
	for slot: int in _slots:
		var player: Variant = round_manager._players[slot]
		if player == null or not is_instance_valid(player) or not player.has_signal("eliminated"):
			continue
		var handler: Callable = _clear_shots_if_decided
		_handlers[slot] = [player, handler]
		player.eliminated.connect(handler)

func _unwatch_eliminations() -> void:
	for slot: int in _handlers.keys():
		var player: Variant = _handlers[slot][0]
		var handler: Callable = _handlers[slot][1]
		if player != null and is_instance_valid(player) and player.eliminated.is_connected(handler):
			player.eliminated.disconnect(handler)
	_handlers.clear()

## Once at most one of the tied is standing, no bullet still in flight may kill
## them on a later tick than the shooter's own KO, which the same-tick double-KO
## rule would miss and leave the round winnerless (#611).
func _clear_shots_if_decided() -> void:
	var standing: int = 0
	for slot: int in _slots:
		var player: Variant = round_manager._players[slot]
		if player != null and is_instance_valid(player) and bool(player.get("alive")):
			standing += 1
	if standing > 1:
		return
	for shot: Node in get_tree().get_nodes_in_group(&"projectiles"):
		shot.queue_free()
