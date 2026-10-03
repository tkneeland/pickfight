extends Node

## The Smash-style Sudden Death tiebreaker (issue #554): the players a round
## ended level between play on, one hit to KO (`SuddenDeath.gd`), and after
## `pressure_delay_sec` meteors start raining (the Meteor shower modifier,
## #147) so it cannot stall. A meteor is a hit, so it KOs too.
##
## `RoundManager` starts one when a round ends in a draw (the last players
## going down on the same tick); Stock's timeout tie runs its overtime on one.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const SuddenDeathScript := preload("res://scripts/SuddenDeath.gd")
const RoundModifiersScript := preload("res://scripts/RoundModifiers.gd")

## Every live tiebreaker. A drawn Stock overtime runs a second one, which
## must not start a second shower.
const GROUP: StringName = &"tiebreakers"

## An announcer line (#370); the Announcer listens for it.
signal callout(sound: StringName)

## Seconds of one-hit fighting before the meteors start.
var pressure_delay_sec: float = 10.0
## Whether starting calls "Sudden Death!". Stock's overtime calls "Overtime!"
## itself and turns this off.
var announce_start: bool = true
var round_manager: Node
## Seconds since the tiebreaker began; not reset by a replay.
var elapsed: float = 0.0

var _one_hit: Node = null
var _meteors: RefCounted = null
var _pressure: bool = false
var _slots: Array[int] = []

func setup(manager: Node) -> void:
	round_manager = manager
	add_to_group(GROUP)

## Starts the tiebreaker among `slots`, or re-arms it among them after a
## double KO replay, keeping the clock and any meteors already falling.
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
	if first and announce_start:
		callout.emit(&"announce_sudden_death")

func end_round() -> void:
	if _one_hit != null and is_instance_valid(_one_hit):
		_one_hit.end_round()
		_one_hit.queue_free()
	_one_hit = null
	if _meteors != null:
		_meteors.undo()
	_meteors = null
	_pressure = false
	_slots.clear()
	elapsed = 0.0

func connected_count() -> int:
	return _one_hit.connected_count() if _one_hit != null else 0

## Whether the meteors are falling.
func pressure_on() -> bool:
	return _pressure

func _physics_process(delta: float) -> void:
	if _one_hit == null:
		return
	elapsed += delta
	if not _pressure and elapsed >= pressure_delay_sec:
		_start_pressure()

func _start_pressure() -> void:
	_pressure = true
	# A round already raining meteors needs no second shower.
	if round_manager.has_method("active_modifier_id") \
			and round_manager.active_modifier_id() == RoundModifiersScript.METEOR_SHOWER:
		return
	for other: Node in get_tree().get_nodes_in_group(GROUP):
		if other != self and other.get("_meteors") != null:
			return
	var players: Array = []
	for slot: int in _slots:
		var player: Variant = round_manager._players[slot]
		if player != null and is_instance_valid(player):
			players.append(player)
	_meteors = RoundModifiersScript.create(RoundModifiersScript.METEOR_SHOWER)
	_meteors.apply(round_manager, players, round_manager.get("_current_stage"))
