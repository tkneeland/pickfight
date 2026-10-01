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
const MAX_RESULTS: int = 32

var wielder: RigidBody2D
var _range: float = 0.0
## Signed: positive pulls toward the wielder, negative pushes away.
var _force: float = 0.0
var _mask: int = FALLBACK_LAYER_WORLD | FALLBACK_LAYER_HEAD

func setup(from_wielder: RigidBody2D, stats: Resource) -> void:
	wielder = from_wielder
	_range = maxf(0.0, float(stats.launch_range))
	_force = float(stats.reel_force)
	var constants: Dictionary = wielder.get_script().get_script_constant_map()
	_mask = int(constants.get("LAYER_WORLD", FALLBACK_LAYER_WORLD)) | int(constants.get("LAYER_HEAD", FALLBACK_LAYER_HEAD))

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
	_apply_field(delta)

func _apply_field(delta: float) -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = _range
	query.shape = circle
	query.transform = Transform2D(0.0, wielder.global_position)
	query.collision_mask = _mask
	query.collide_with_areas = false
	var excluded: Array[RID] = [wielder.get_rid()]
	if wielder.has_method("weapon_head_rid"):
		excluded.append(wielder.weapon_head_rid())
	query.exclude = excluded
	var seen: Dictionary = {}
	for result: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, MAX_RESULTS):
		var body: RigidBody2D = result["collider"] as RigidBody2D
		if body == null or not is_instance_valid(body) or seen.has(body.get_instance_id()):
			continue
		seen[body.get_instance_id()] = true
		if not _is_movable(body):
			continue
		var to_wielder: Vector2 = wielder.global_position - body.global_position
		var distance: float = to_wielder.length()
		if distance < MIN_DISTANCE or distance >= _range:
			continue
		var strength: float = _force * (1.0 - distance / _range)
		body.apply_central_impulse(to_wielder / distance * strength * delta)

## A player's body or a weapon head, and not a dead player's.
func _is_movable(body: RigidBody2D) -> bool:
	if body.freeze:
		return false
	if body.has_method("eliminate"):
		return bool(body.get("alive"))
	return body.has_method("mass_blocking")
