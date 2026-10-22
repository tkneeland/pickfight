extends Node2D

## A one-shot pair of rings in the winner's colour that expand and fade where a
## round was won (#909), so the host sees who took the point without reading
## the banner. Modelled on PickupSpawnRing.gd. Motion only, no flash, so Reduce
## flashes does not apply. Frees itself when done.

const LIFETIME_SEC: float = 0.8
const START_RADIUS: float = 20.0
const END_RADIUS: float = 140.0
const RING_WIDTH: float = 5.0
## The second ring trails the first by this share of the lifetime.
const SECOND_DELAY: float = 0.25

var color: Color = Color.WHITE
var _age: float = 0.0

func _init() -> void:
	name = "RoundWinRing"
	z_index = -1

## Spawns a ring at `slot`'s fighter, unless the round has no single winner or
## this round wins the match (the KO slow-motion and podium cover that, #328).
static func spawn_for(round_manager: Node, slot: int) -> Node2D:
	var players: Array = round_manager.get("_players")
	if slot < 0 or slot >= players.size() or not is_instance_valid(players[slot]):
		return null
	if bool(round_manager.get("lobby_enabled")):
		var target: int = int(round_manager.get("_match_target"))
		var score: int = 0
		if bool(round_manager.get("_team_mode")):
			var teams: Dictionary = round_manager.get("_teams")
			var team_scores: PackedInt32Array = round_manager.get("_team_scores")
			var team: int = int(teams.get(slot, -1))
			score = team_scores[team] if team >= 0 and team < team_scores.size() else 0
		else:
			var scores: PackedInt32Array = round_manager.get("_scores")
			score = scores[slot] if slot < scores.size() else 0
		if score >= target:
			return null
	var player: Node2D = players[slot]
	var parent: Node = player.get_parent()
	if parent == null:
		return null
	var ring: Node2D = (load("res://scripts/RoundWinRing.gd") as GDScript).new()
	ring.color = round_manager.call("_slot_color", slot)
	parent.add_child(ring)
	ring.global_position = player.global_position
	return ring

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME_SEC:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	for i in 2:
		var t: float = clampf((_age - float(i) * SECOND_DELAY * LIFETIME_SEC) / (LIFETIME_SEC * (1.0 - SECOND_DELAY)), 0.0, 1.0)
		if t <= 0.0 or t >= 1.0:
			continue
		var eased: float = 1.0 - (1.0 - t) * (1.0 - t)
		var c := color
		c.a = 1.0 - t
		draw_arc(Vector2.ZERO, lerpf(START_RADIUS, END_RADIUS, eased), 0.0, TAU, 64, c, RING_WIDTH, true)
