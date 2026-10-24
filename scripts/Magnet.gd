extends Node2D

## The magnet weapon: a field around the wielder that pulls nearby players and
## weapon heads toward them (issue #274), or pushes them away when the
## weapon's `reel_force` is negative. Hangs off the player and, every physics
## tick, nudges what is inside `launch_range` with an impulse that fades with
## distance. It deals no damage of its own: it moves people into (or out of)
## trouble.
##
## What it moves, and what it leaves alone:
##  - other living players' bodies, and other players' weapon heads;
##  - never the wielder's own body or head, never a dead (inert) player;
##  - not pickups (areas, which a body query skips) and not bullets or
##    thrown hooks and boomerangs (not physics bodies). Left alone on
##    purpose: a field strong enough to bend a bullet would make the
##    boomstick useless against a magnet, which is not what the issue asks.
##
## The strength at distance `d` is `reel_force * (1 - d / launch_range)`
## applied as an impulse of `strength * delta`, so it does not depend on the
## physics tick rate and is zero at the field's edge.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md). The
## collision layers are read off the wielder's own script constants rather
## than preloading Player.gd, which preloads this file.

## Fallbacks for `Player.LAYER_WORLD` / `Player.LAYER_HEAD` (bit values, not
## bit indices): bodies are on layer value 1, weapon heads on layer value 2.
const FALLBACK_LAYER_WORLD: int = 1
const FALLBACK_LAYER_HEAD: int = 2
## Closer than this to the wielder the direction is too noisy to use.
const MIN_DISTANCE: float = 8.0
## Most colliders one field query reports. Stage terrain on the world layer
## inside the field counts toward it as well as players and heads.
const MAX_RESULTS: int = 32
## Least time between two pull sounds while the field keeps affecting someone
## (#978). The first sound plays on the tick the field starts affecting a body.
const SOUND_INTERVAL_SEC: float = 1.5

var wielder: RigidBody2D
var _range: float = 0.0
## Signed: positive pulls toward the wielder, negative pushes away.
var _force: float = 0.0
var _mask: int = FALLBACK_LAYER_WORLD | FALLBACK_LAYER_HEAD
## The field's shape query, built on the first tick that needs it.
var _query: PhysicsShapeQueryParameters2D = null
var _circle: CircleShape2D = null
## The line-of-sight ray, built once and reused for every body each tick.
var _ray: PhysicsRayQueryParameters2D = null
var _world_mask: int = FALLBACK_LAYER_WORLD
## Seconds until the pull sound may play again; counts down every tick.
var _sound_cooldown: float = 0.0

func setup(from_wielder: RigidBody2D, stats: Resource) -> void:
	wielder = from_wielder
	_range = maxf(0.0, float(stats.launch_range))
	_force = float(stats.reel_force)
	var constants: Dictionary = wielder.get_script().get_script_constant_map()
	_world_mask = int(constants.get("LAYER_WORLD", FALLBACK_LAYER_WORLD))
	_mask = _world_mask | int(constants.get("LAYER_HEAD", FALLBACK_LAYER_HEAD))

## Stops the field the moment the weapon is dropped; the node itself goes at
## end of frame, and until then must not act.
func retire() -> void:
	set_physics_process(false)
	queue_free()

func _exit_tree() -> void:
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if _range <= 0.0 or _force == 0.0:
		return
	if not is_instance_valid(wielder) or not bool(wielder.get("alive")):
		return
	_sound_cooldown = maxf(0.0, _sound_cooldown - delta)
	if _apply_field(delta) and _sound_cooldown <= 0.0:
		_sound_cooldown = SOUND_INTERVAL_SEC
		var sfx: Node = get_node_or_null(^"/root/Sfx")
		if sfx != null:
			sfx.play(&"magnet_pull", wielder.global_position, 1.0)

## True when the field moved at least one body this tick.
func _apply_field(delta: float) -> bool:
	# Made once and reused every tick; the radius and the rest are set each call.
	if _query == null:
		_query = PhysicsShapeQueryParameters2D.new()
		_circle = CircleShape2D.new()
		_query.shape = _circle
	var query: PhysicsShapeQueryParameters2D = _query
	_circle.radius = _range
	query.shape = _circle
	query.transform = Transform2D(0.0, wielder.global_position)
	query.collision_mask = _mask
	query.collide_with_areas = false
	var excluded: Array[RID] = [wielder.get_rid()]
	if wielder.has_method("weapon_head_rid"):
		excluded.append(wielder.weapon_head_rid())
	query.exclude = excluded
	if _ray == null:
		_ray = PhysicsRayQueryParameters2D.new()
		_ray.collide_with_areas = false
		_ray.collision_mask = _world_mask
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var seen: Dictionary = {}
	var affected: bool = false
	# A protected fighter's weapon head is dragged by the field too, and the haft
	# takes the fighter with it, so the head is skipped as well (#1056).
	var protected_heads: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.get("spawn_protected") == true and node.has_method("weapon_head_rid"):
			protected_heads[node.weapon_head_rid()] = true
	for result: Dictionary in space.intersect_shape(query, MAX_RESULTS):
		var body: RigidBody2D = result["collider"] as RigidBody2D
		if body == null or not is_instance_valid(body) or seen.has(body.get_instance_id()):
			continue
		seen[body.get_instance_id()] = true
		if not _is_movable(body):
			continue
		if body.get("spawn_protected") == true or protected_heads.has(body.get_rid()):
			continue  # just respawned: not hauled off its ledge (#1056)
		var to_wielder: Vector2 = wielder.global_position - body.global_position
		var distance: float = to_wielder.length()
		if distance < MIN_DISTANCE or distance >= _range:
			continue
		if _terrain_between(space, body, excluded):
			continue
		var strength: float = _force * (1.0 - distance / _range)
		body.apply_central_impulse(to_wielder / distance * strength * delta)
		affected = true
	return affected

## A player's body or a weapon head, and not a dead player's.
func _is_movable(body: RigidBody2D) -> bool:
	if body.freeze:
		return false
	if body.has_method("eliminate"):
		return bool(body.get("alive"))
	return body.has_method("mass_blocking")

## True when solid terrain (a world-layer collider that is not a physics body,
## so not another fighter) lies on the line from the wielder to `body`
## (issue #933). Fighters share the world layer, so a fighter in the way is
## stepped past rather than treated as a wall; the re-cast is capped at 3.
func _terrain_between(space: PhysicsDirectSpaceState2D, body: RigidBody2D, base_excluded: Array[RID]) -> bool:
	_ray.from = wielder.global_position
	_ray.to = body.global_position
	var skip: Array[RID] = base_excluded.duplicate()
	skip.append(body.get_rid())
	for _i in 3:
		_ray.exclude = skip
		var hit: Dictionary = space.intersect_ray(_ray)
		if hit.is_empty():
			return false
		if not (hit["collider"] is RigidBody2D):
			return true
		skip.append(hit["rid"])
	return false
