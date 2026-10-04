extends RefCounted

## The respawn Stock (#354) and Soccer (#402) share: a knocked-out player
## comes back after `respawn_sec` at the stage spawn farthest from everyone
## still standing, with spawn protection (#114), the pickaxe and no damage.
## The owning mode node calls `queue()` when a player goes down and `tick()`
## every physics frame, and `clear()` when its round ends.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const GameClockScript := preload("res://scripts/GameClock.gd")

var respawn_sec: float = 1.5
## Optional own-half filter for team modes (#605): `team_of.call(slot)` is 0
## (left half) or 1, `centre_x.call()` the dividing x. Unset, any spawn is fine.
var team_of: Callable
var centre_x: Callable
## How far below a spawn point a floor still counts as under it.
const GROUND_PROBE: float = 400.0
var round_manager: Node
## slot -> player node; the mode's own dictionary, shared.
var watched: Dictionary = {}
## slot -> seconds until it respawns.
var _pending: Dictionary = {}
## slot -> GameClock msec its spawn protection ends.
var _protected: Dictionary = {}

func _init(manager: Node, players: Dictionary, delay_sec: float = 1.5) -> void:
	round_manager = manager
	watched = players
	respawn_sec = delay_sec

func queue(slot: int) -> void:
	_pending[slot] = respawn_sec

func is_pending(slot: int) -> bool:
	return _pending.has(slot)

func cancel(slot: int) -> void:
	_pending.erase(slot)

func clear() -> void:
	_pending.clear()
	_protected.clear()

func tick(_delta: float) -> void:
	for slot: int in _pending.keys():
		_pending[slot] = float(_pending[slot]) - _delta
		if float(_pending[slot]) <= 0.0:
			respawn_now(slot)
	_tick_protection()

## Back in at the spawn farthest from the others, a pickaxe in hand.
func respawn_now(slot: int) -> void:
	_pending.erase(slot)
	var player: Node2D = watched[slot]
	if not is_instance_valid(player) or not _still_claimed(slot):
		return
	player.start_round(farthest_spawn(slot), false)
	var stats: Variant = round_manager.get("_stats")
	if stats != null:
		stats.resume_round(slot, GameClockScript.now_msec())
	if float(round_manager.spawn_protection_sec) > 0.0:
		player.spawn_protected = true
		_protected[slot] = GameClockScript.now_msec() + int(float(round_manager.spawn_protection_sec) * 1000.0)

## Whether the roster still holds `slot`: one the host kicked while it waited
## is out of the round, so it does not come back. A disconnect keeps its claim
## until the round ends (ADR-0007). True with no roster to ask.
func _still_claimed(slot: int) -> bool:
	var server: Variant = round_manager.get("_controller_server") if round_manager != null else null
	if server == null or not is_instance_valid(server) or not (server as Object).has_method("claimed_slots"):
		return true
	return (server.claimed_slots() as Array).has(slot)

## The stage spawn point whose nearest standing player is farthest away,
## among the safe ones (#605): on the player's own half when a team filter is
## set, and with a floor under it. Falls back to the best of what is left if
## nothing is safe. With nobody else standing, the farthest from where the
## player went down.
func farthest_spawn(slot: int) -> Vector2:
	var points: Array[Vector2] = round_manager._stage_spawn_points
	var here: Vector2 = watched[slot].global_position
	if points.is_empty():
		return here
	var pool: Array[Vector2] = points
	if team_of.is_valid() and centre_x.is_valid():
		var cx: float = float(centre_x.call())
		var left: bool = int(team_of.call(slot)) == 0
		var own: Array[Vector2] = []
		for point: Vector2 in points:
			if (point.x < cx) == left:
				own.append(point)
		if not own.is_empty():
			pool = own
	var grounded: Array[Vector2] = []
	for point: Vector2 in pool:
		if _has_floor(point):
			grounded.append(point)
	if not grounded.is_empty():
		pool = grounded
	var best: Vector2 = pool[0]
	var best_gap: float = -1.0
	for point: Vector2 in pool:
		var gap: float = INF
		for other: int in watched.keys():
			if other != slot and bool(watched[other].alive):
				gap = minf(gap, point.distance_to(watched[other].global_position))
		if is_inf(gap):
			gap = point.distance_to(here)
		if gap > best_gap:
			best_gap = gap
			best = point
	return best

## Whether solid ground lies within GROUND_PROBE below `point`. True when the
## space cannot be asked.
func _has_floor(point: Vector2) -> bool:
	if round_manager == null or not is_instance_valid(round_manager) or not round_manager.is_inside_tree():
		return true
	var world: World2D = round_manager.get_viewport().find_world_2d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(point, point + Vector2(0.0, GROUND_PROBE), 1)
	return not world.direct_space_state.intersect_ray(query).is_empty()

func _tick_protection() -> void:
	var now: int = GameClockScript.now_msec()
	for slot: int in _protected.keys():
		var player: Node2D = watched[slot]
		if not is_instance_valid(player):
			_protected.erase(slot)
		elif now >= int(_protected[slot]):
			player.spawn_protected = false
			player.modulate.a = 1.0
			_protected.erase(slot)
		else:
			var lit: bool = int(float(now) / 1000.0 * 16.0) % 2 == 0
			player.modulate.a = 1.0 if lit else 0.35
