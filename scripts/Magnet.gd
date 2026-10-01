extends Node2D

## The magnet weapon: pulls nearby players and weapon heads toward the wielder
## (issue #274). Hangs off the arm and continuously applies pull forces to
## nearby bodies based on proximity.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const LAYER_WORLD: int = 1
const LAYER_BODY: int = 2

var wielder: RigidBody2D
var _stats: Resource
var _range: float = 0.0
var _pull_force: float = 0.0

func setup(from_wielder: RigidBody2D, stats: Resource) -> void:
	wielder = from_wielder
	_stats = stats
	_range = maxf(0.0, float(stats.launch_range))
	_pull_force = maxf(0.0, float(stats.reel_force))

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(wielder) or not bool(wielder.get("alive")):
		return
	_apply_forces()

func _apply_forces() -> void:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	(query.shape as CircleShape2D).radius = _range
	query.transform = Transform2D(0.0, wielder.global_position)
	query.collision_mask = 1 << LAYER_BODY
	query.exclude = [wielder.get_rid()]
	var results: Array[Dictionary] = space.intersect_shape(query)
	for result: Dictionary in results:
		var body: RigidBody2D = result["collider"] as RigidBody2D
		if body == null or not is_instance_valid(body):
			continue
		var to_body: Vector2 = body.global_position - wielder.global_position
		var distance: float = to_body.length()
		if distance <= 0.01:
			continue
		var toward: Vector2 = -to_body.normalized()
		body.apply_central_force(toward * _pull_force)
