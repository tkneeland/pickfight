extends RefCounted

## Per-source repeat guard for the event hooks (`SfxHooks`, `Juice`): a head
## grinding in a corner, or a body bouncing on two touching tiles, is one
## sound or one puff, not one a tick. Counts physics frames. Reached by path,
## never by `class_name`; `VelocityTracker` below is the landing half both
## hooks share.

## Past this many remembered sources, the ones long gone quiet are forgotten
## (heads are rebuilt every round).
const PRUNE_AT: int = 256
const PRUNE_AFTER_FRAMES: int = 600

## key -> the physics frame that source last fired on.
var _last_frame: Dictionary = {}

## Whether `source` may fire now, having last fired at least `frames` physics
## frames ago; if so it is marked as firing now. A separate `channel` keeps one
## kind of event (a grunt) from muting a source's others.
func ready(source: Object, frames: int, channel: String = "") -> bool:
	var id: int = source.get_instance_id() if channel == "" else hash([source.get_instance_id(), channel])
	var now: int = Engine.get_physics_frames()
	if _last_frame.has(id) and now - int(_last_frame[id]) < frames:
		return false
	if _last_frame.size() > PRUNE_AT:
		for key: int in _last_frame.keys():
			if now - int(_last_frame[key]) > PRUNE_AFTER_FRAMES:
				_last_frame.erase(key)
	_last_frame[id] = now
	return true

## Each tracked player's linear velocity at the start of the physics step, so
## a landing is judged on the speed it arrived with: by the time the contact is
## reported, the solver has already stopped the body. The owner calls `step()`
## from a `_physics_process` that runs before the game's (priority -100).
##
## A player stays tracked while its instance is valid, even out of the tree
## (a persistent player between stages), and is only dropped once freed.
class VelocityTracker extends RefCounted:
	## Tracked players, in the order first seen.
	var players: Array[Node] = []
	## instance id -> linear velocity at the start of this physics step.
	var _before: Dictionary = {}

	func track(player: Node) -> void:
		players.append(player)

	func step() -> void:
		if _before.size() > players.size() * 4 + 16:
			_before.clear()
		var i: int = players.size() - 1
		while i >= 0:
			var player: Node = players[i]
			if is_instance_valid(player) and player.is_inside_tree():
				var velocity: Variant = player.get("linear_velocity")
				_before[player.get_instance_id()] = velocity if velocity is Vector2 else Vector2.ZERO
			elif not is_instance_valid(player):
				players.remove_at(i)
			i -= 1

	## The downward speed `player` arrived at `other` with, when that contact
	## is a landing: `other` is not a player, `player` is alive, and it was
	## moving down at `min_speed` or more. -1.0 otherwise.
	func landing_speed(other: Node, player: Node, min_speed: float) -> float:
		if other.is_in_group("players") or not bool(player.get("alive")):
			return -1.0
		var before: Vector2 = _before.get(player.get_instance_id(), Vector2.ZERO)
		return before.y if before.y >= min_speed else -1.0
