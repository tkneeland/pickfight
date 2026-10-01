extends Node2D

## King of the Hill mode: a zone on the stage where a player scores points
## while they are alone in it (issue #276).
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const LAYER_BODY: int = 2

var round_manager: Node
var hill_position: Vector2 = Vector2.ZERO
var hill_radius: float = 100.0
var _in_hill: Array[RigidBody2D] = []

func setup(manager: Node, position: Vector2, radius: float) -> void:
	round_manager = manager
	hill_position = position
	hill_radius = radius

func _physics_process(_delta: float) -> void:
	if round_manager == null:
		return
	_update_hill_occupants()
	_award_points()

func _update_hill_occupants() -> void:
	_in_hill.clear()
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	(query.shape as CircleShape2D).radius = hill_radius
	query.transform = Transform2D(0.0, global_position + hill_position)
	query.collision_mask = 1 << LAYER_BODY
	var results: Array[Dictionary] = space.intersect_shape(query)
	for result: Dictionary in results:
		var body: RigidBody2D = result["collider"] as RigidBody2D
		if body != null and is_instance_valid(body) and body.is_in_group("players"):
			_in_hill.append(body)

func _award_points() -> void:
	if _in_hill.size() != 1:
		return
	var player: RigidBody2D = _in_hill[0]
	if not bool(player.get("alive")):
		return
	for slot: int in range(8):
		if round_manager._players[slot] == player:
			round_manager._scores[slot] += 1
			break
