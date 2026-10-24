extends "res://scripts/ExpandingRing.gd"

## A one-shot pair of rings in the winner's colour that expand and fade where a
## round was won (#909), so the host sees who took the point without reading
## the banner. Drawn by ExpandingRing.gd, as PickupSpawnRing.gd is. Motion only, no flash, so Reduce
## flashes does not apply. Frees itself when done.

const LIFETIME_SEC: float = 0.8
const START_RADIUS: float = 20.0
const END_RADIUS: float = 140.0
const RING_WIDTH: float = 5.0
## The second ring trails the first by this share of the lifetime.
const SECOND_DELAY: float = 0.25

const EffectStreamScript := preload("res://scripts/EffectStream.gd")

func _init() -> void:
	name = "RoundWinRing"
	z_index = -1
	lifetime_sec = LIFETIME_SEC
	start_radius = START_RADIUS
	end_radius = END_RADIUS
	ring_width = RING_WIDTH
	ring_count = 2
	ring_delay = SECOND_DELAY
	segments = 64

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
	var tint: Color = round_manager.call("_slot_color", slot)
	EffectStreamScript.record("win_ring", {"p": player.global_position, "c": tint}, player) # #976
	return spawn_at(parent, player.global_position, tint)

## The rings in `tint` at `at` under `parent`. Shared by the host and the
## Online joiner (#976).
static func spawn_at(parent: Node, at: Vector2, tint: Color) -> Node2D:
	var ring: Node2D = (load("res://scripts/RoundWinRing.gd") as GDScript).new()
	ring.color = tint
	parent.add_child(ring)
	ring.global_position = at
	return ring
