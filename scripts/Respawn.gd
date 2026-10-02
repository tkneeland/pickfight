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
	if not is_instance_valid(player):
		return
	player.start_round(farthest_spawn(slot), false)
	if float(round_manager.spawn_protection_sec) > 0.0:
		player.spawn_protected = true
		_protected[slot] = GameClockScript.now_msec() + int(float(round_manager.spawn_protection_sec) * 1000.0)

## The stage spawn point whose nearest standing player is farthest away.
func farthest_spawn(slot: int) -> Vector2:
	var points: Array[Vector2] = round_manager._stage_spawn_points
	var here: Vector2 = watched[slot].global_position
	if points.is_empty():
		return here
	var best: Vector2 = points[0]
	var best_gap: float = -1.0
	for point: Vector2 in points:
		var gap: float = INF
		for other: int in watched.keys():
			if other != slot and bool(watched[other].alive):
				gap = minf(gap, point.distance_to(watched[other].global_position))
		if gap > best_gap:
			best_gap = gap
			best = point
	return best

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
