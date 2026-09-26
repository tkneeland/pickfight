extends Node

## Scenario helper for issue #135: works out, every rendered frame, where the
## renderer draws each watched player's haft tip and weapon head, and how far
## apart the two are.
##
## Headless runs draw nothing, so this reconstructs what 2D physics
## interpolation (issue #108) would draw. The renderer blends each canvas
## item's transform between two snapshots: the one it takes at the very start
## of a physics tick -- which is what the previous tick left, since the
## physics server only writes the last step's result into the bodies after
## that snapshot -- and the current one. Both players and heads are
## interpolated that way, so for each:
##
##   drawn = (transform the previous tick ended on)
##           .interpolate_with(transform now, physics interpolation fraction)
##
## The haft tip is the Line2D's last point, carried by the player's drawn
## transform; the head is its anchor, where the haft holds it.
##
## Its physics step runs after every player's (a high
## `process_physics_priority`) so it records what the tick really ended on,
## and its frame step after every player's `_process` (a high
## `process_priority`) so it reads the line the player has just redrawn.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

## The players watched; set by the scenario before adding this to the tree.
var players: Array[RigidBody2D] = []
## Frames are only measured while this is true, so a scenario can leave out
## its own setup (teleports, rig builds), which reset interpolation.
var measuring: bool = false

## Per player (same index as `players`): the largest drawn gap seen, the
## fraction and frame it was seen at, and how many measured frames fell well
## between two ticks -- the frames where a lag shows.
var max_gap: PackedFloat32Array = []
var max_gap_fraction: PackedFloat32Array = []
var between_frames: PackedInt32Array = []
var frames: PackedInt32Array = []
## Per player: measured frames in which its head was phased (issue #115),
## and the largest gap among those.
var phased_frames: PackedInt32Array = []
var max_phased_gap: PackedFloat32Array = []

## Per player: the head node the snapshots below belong to, and the player's
## and head's global transforms at the end of the last two ticks.
var _heads: Array[Node] = []
var _player_prev: Array[Transform2D] = []
var _player_last: Array[Transform2D] = []
var _head_prev: Array[Transform2D] = []
var _head_last: Array[Transform2D] = []
## Ticks recorded for the current head; a frame needs two behind it.
var _ticks: PackedInt32Array = []

## A frame is "well between" two ticks when its fraction is in this range.
const BETWEEN_MIN: float = 0.2
const BETWEEN_MAX: float = 0.8

func _ready() -> void:
	process_physics_priority = 100000
	process_priority = 100000
	var n: int = players.size()
	max_gap.resize(n)
	max_gap_fraction.resize(n)
	between_frames.resize(n)
	frames.resize(n)
	phased_frames.resize(n)
	max_phased_gap.resize(n)
	_heads.resize(n)
	_ticks.resize(n)
	for i in n:
		_player_prev.append(Transform2D())
		_player_last.append(Transform2D())
		_head_prev.append(Transform2D())
		_head_last.append(Transform2D())

func _physics_process(_delta: float) -> void:
	for i in players.size():
		var player: RigidBody2D = players[i]
		var head: Node2D = player.get("_head")
		if head == null or not head.is_inside_tree():
			_heads[i] = null
			_ticks[i] = 0
			continue
		if head != _heads[i]:
			_heads[i] = head
			_ticks[i] = 0
		_player_prev[i] = _player_last[i]
		_head_prev[i] = _head_last[i]
		_player_last[i] = player.global_transform
		_head_last[i] = head.global_transform
		_ticks[i] += 1

func _process(_delta: float) -> void:
	if not measuring:
		return
	var f: float = Engine.get_physics_interpolation_fraction()
	for i in players.size():
		if _ticks[i] < 2:
			continue
		var player: RigidBody2D = players[i]
		var head: Node2D = _heads[i]
		var line: Line2D = player.weapon_line
		var drawn_player: Transform2D = _player_prev[i].interpolate_with(player.global_transform, f)
		var drawn_head: Vector2 = _head_prev[i].interpolate_with(head.global_transform, f).origin
		var drawn_tip: Vector2 = drawn_player * (line.transform * line.points[line.points.size() - 1])
		var gap: float = drawn_tip.distance_to(drawn_head)
		frames[i] += 1
		if f >= BETWEEN_MIN and f <= BETWEEN_MAX:
			between_frames[i] += 1
		if player.is_head_phased():
			phased_frames[i] += 1
			max_phased_gap[i] = maxf(max_phased_gap[i], gap)
		if gap > max_gap[i]:
			max_gap[i] = gap
			max_gap_fraction[i] = f
