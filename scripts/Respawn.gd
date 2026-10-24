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
## Optional no-go areas (#648): `avoid_rects.call()` is an Array of Rect2, the
## Soccer goals. A spawn inside one is never picked while another is open.
var avoid_rects: Callable
## Optional (#662): `far_from.call()` is a world point (King of the Hill's
## hill); the spawn chosen is the safe one farthest from it, not from players.
var far_from: Callable
## How far below a spawn point a floor still counts as under it.
const GROUND_PROBE: float = 400.0
## A spawn this close to a spike strip or saw is passed over (#982).
const HAZARD_CLEARANCE: float = 120.0
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
	var spot: Vector2 = farthest_spawn(slot)
	player.start_round(spot, false)
	# Issue #1015: a soft chime at the spawn. Host only; online clients hear it
	# through the generic Sfx snapshot trailer. Kicked slots returned above.
	var sfx: Node = round_manager.get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.play(&"respawn", spot, 1.0)
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
	if avoid_rects.is_valid():
		var open: Array[Vector2] = []
		var rects: Array = avoid_rects.call()
		for point: Vector2 in pool:
			var inside: bool = false
			for rect: Rect2 in rects:
				if rect.has_point(point):
					inside = true
			if not inside:
				open.append(point)
		if not open.is_empty():
			pool = open
		else:
			# Every spawn is in a goal: the own-half one nearest the centre.
			var mid: float = float(centre_x.call()) if centre_x.is_valid() else 0.0
			var nearest: Vector2 = pool[0]
			for point: Vector2 in pool:
				if absf(point.x - mid) < absf(nearest.x - mid):
					nearest = point
			return nearest
	var grounded: Array[Vector2] = []
	for point: Vector2 in pool:
		if _has_floor(point):
			grounded.append(point)
	if not grounded.is_empty():
		pool = grounded
	var clear: Array[Vector2] = []
	for point: Vector2 in pool:
		if not _near_hazard(point):
			clear.append(point)
	if not clear.is_empty():
		pool = clear
	var best: Vector2 = pool[0]
	var best_gap: float = -1.0
	for point: Vector2 in pool:
		if far_from.is_valid():
			var away: float = point.distance_to(far_from.call() as Vector2)
			if away > best_gap:
				best_gap = away
				best = point
			continue
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

## Whether `point` is within HAZARD_CLEARANCE of a spike strip (its footprint)
## or a saw (its blade centre, wherever it is now). Host-side only (#982).
func _near_hazard(point: Vector2) -> bool:
	if round_manager == null or not is_instance_valid(round_manager) or not round_manager.is_inside_tree():
		return false
	for hazard: Node in round_manager.get_tree().get_nodes_in_group("damage_hazard"):
		var node: Node2D = hazard as Node2D
		if node == null or not node.is_inside_tree():
			continue
		var gap: float
		if "size" in node:
			var box := Rect2(node.global_position - (node.size as Vector2) / 2.0, node.size as Vector2)
			gap = 0.0 if box.grow(HAZARD_CLEARANCE).has_point(point) else INF
		else:
			gap = point.distance_to(node.global_position)
		if gap <= HAZARD_CLEARANCE:
			return true
	return false

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
