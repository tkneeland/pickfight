extends Node

## Weapon pickups (issue #14, ADR-0009), split out of RoundManager (#175).
##
## One pickup lies on the stage when a round starts; another arrives every
## `pickup_spawn_interval_sec` while fewer than the cap are on it; any left
## when the round ends are cleared. Pickups are parented to the active stage
## instance, so a stage swap can never strand one either. With a crowd
## (`crowded_roster` players or more, #152) they come sooner and the cap
## rises to one per player.
##
## The settings stay exports on the RoundManager that owns this node, read
## live from it every time, as do the roster (`_controller_server`) and the
## active stage (`_current_stage`, `_stage_spawn_points`). RoundManager calls
## `start()`, `tick()` and `clear()` at the points in the round it always
## did; this node has no `_process` of its own.

const PickupWeaponsScript := preload("res://scripts/PickupWeapons.gd")
## Game time (#182), not wall clock: the interval stops for a pause and runs
## at `Engine.time_scale`.
const GameClockScript := preload("res://scripts/GameClock.gd")
## Where a pickup lands on a stage that declares no `PickupSpawn*` markers,
## relative to the stage's origin: above its centre (user story 17).
const FALLBACK_PICKUP_OFFSET: Vector2 = Vector2(0.0, -200.0)
## Two pickups within this of each other are on the same spot.
const PICKUP_SPOT_EPSILON: float = 8.0
## A pickup spot this close to a player spawn is skipped (#111, owner
## playtest: players spawned on a drop and took it before moving). About a
## body width plus the largest pickup's trigger, with room to spare, so a
## player standing on their spawn cannot touch a pickup.
const PICKUP_CLEAR_OF_SPAWN_RADIUS: float = 120.0

## The RoundManager this directs pickups for.
var _rm: Node
var _pickups: Array[Node2D] = []
var _next_pickup_msec: int = 0
## Every draw this node makes -- which weapon, which spot (issue #187). The
## RoundManager hands it a stream derived from the match seed; until then (a
## director driven by hand) it is an unseeded one of its own.
var rng := RandomNumberGenerator.new()

func _init(round_manager: Node = null) -> void:
	name = "PickupDirector"
	_rm = round_manager
	rng.randomize()

## Round start: clear anything left over, put the first pickup down, and
## start the interval from now.
func start() -> void:
	clear()
	_spawn_pickup()
	_next_pickup_msec = GameClockScript.now_msec() + int(interval_sec() * 1000.0)

## Each tick of an active round: free any pickup the lava has risen over
## (#200), then, once the interval is up, add one if the stage is below the
## cap, and start the next interval either way.
func tick() -> void:
	clear_submerged()
	var now: int = GameClockScript.now_msec()
	if now < _next_pickup_msec:
		return
	_next_pickup_msec = now + int(interval_sec() * 1000.0)
	if _live_pickups().size() < cap():
		_spawn_pickup()

## Most pickups the stage holds at once right now: one fewer than the players
## on the roster, and never under `max_pickups` -- 2 for two or three players,
## 3 for four (#36, amending ADR-0009's "at most two"); one per player from
## `crowded_roster` up (#152).
func cap() -> int:
	var server: Variant = _rm._controller_server
	var roster: int = server.claimed_slots().size() if server != null else 0
	if roster >= _rm.crowded_roster:
		return maxi(_rm.max_pickups, roster)
	return maxi(_rm.max_pickups, roster - 1)

## Seconds until the next pickup: `pickup_spawn_interval_sec`, shortened by
## `crowded_interval_scale` from `crowded_roster` players up (#152).
func interval_sec() -> float:
	var server: Variant = _rm._controller_server
	var roster: int = server.claimed_slots().size() if server != null else 0
	if roster >= _rm.crowded_roster:
		return _rm.pickup_spawn_interval_sec * _rm.crowded_interval_scale
	return _rm.pickup_spawn_interval_sec

## Frees every pickup at or below the floor kill zone's surface (#200). A
## pickup is an Area2D, which the zone never eliminates, so without this one
## the lava rose over would sit out of reach and hold its place in `cap()`.
func clear_submerged() -> void:
	var lava: float = lava_surface_y()
	if lava == INF:
		return
	for pickup: Node2D in _live_pickups():
		if pickup.global_position.y >= lava:
			pickup.queue_free()
	_live_pickups()

## The global y of the active stage's floor kill zone surface, or INF on a
## stage without one.
func lava_surface_y() -> float:
	if _rm == null or not _rm.has_method("_floor_kill_zone"):
		return INF
	var zone: Node2D = _rm._floor_kill_zone()
	if zone == null or not zone.has_method("surface_y"):
		return INF
	return zone.surface_y()

func clear() -> void:
	for pickup: Node2D in _live_pickups():
		pickup.queue_free()
	_pickups.clear()

## Pickups still on the stage: collected ones free themselves, so anything
## freed or on its way out is dropped from the list here.
func _live_pickups() -> Array[Node2D]:
	var live: Array[Node2D] = []
	for pickup: Node2D in _pickups:
		if is_instance_valid(pickup) and not pickup.is_queued_for_deletion():
			live.append(pickup)
	_pickups = live
	return live

func _spawn_pickup() -> void:
	var scene: PackedScene = _rm.pickup_scene
	if scene == null or _live_pickups().size() >= cap():
		return
	var stage: Variant = _rm._current_stage
	var parent: Node = stage if stage != null else _rm.get_node_or_null(_rm.arena_container_path)
	if parent == null:
		return
	var spot: Variant = free_spot()
	if spot == null:
		return
	var weapons: Array[Resource] = _rm.pickup_weapons
	var offered: Array[Resource] = weapons if not weapons.is_empty() else PickupWeaponsScript.available_weapons()
	var weapon: Resource = PickupWeaponsScript.choose(offered, rng)
	if weapon == null:
		return
	var pickup: Node2D = scene.instantiate() as Node2D
	pickup.set_weapon(weapon)
	parent.add_child(pickup)
	pickup.global_position = spot
	# Placed after entering the tree: a spawn, not motion (issue #108).
	pickup.reset_physics_interpolation()
	_pickups.append(pickup)

## A random declared spot with no pickup already on it, or the fallback above
## the stage's centre when the stage declares none. Null when every spot is
## taken. Spots within PICKUP_CLEAR_OF_SPAWN_RADIUS of a player spawn are
## skipped while any other free spot remains; if every free spot is near a
## spawn, the one furthest from all spawns is used, so a stage still gets
## its pickups (#111). A spot at or below the floor kill zone's surface is
## never used (#200).
func free_spot() -> Variant:
	var stage: Variant = _rm._current_stage
	var spots: Array[Vector2] = []
	if stage != null and stage.has_method("get_pickup_spawn_points"):
		spots = stage.get_pickup_spawn_points()
	if spots.is_empty():
		var origin: Vector2 = stage.global_position if stage != null else Vector2.ZERO
		spots = [origin + FALLBACK_PICKUP_OFFSET]
	var free: Array[Vector2] = []
	var lava: float = lava_surface_y()
	for spot: Vector2 in spots:
		if spot.y >= lava:
			continue
		var taken: bool = false
		for pickup: Node2D in _live_pickups():
			if pickup.global_position.distance_to(spot) < PICKUP_SPOT_EPSILON:
				taken = true
				break
		if not taken:
			free.append(spot)
	if free.is_empty():
		return null
	var clear_spots: Array[Vector2] = []
	for spot: Vector2 in free:
		if _distance_to_nearest_spawn(spot) >= PICKUP_CLEAR_OF_SPAWN_RADIUS:
			clear_spots.append(spot)
	if not clear_spots.is_empty():
		return clear_spots[rng.randi() % clear_spots.size()]
	var best: Vector2 = free[0]
	for spot: Vector2 in free:
		if _distance_to_nearest_spawn(spot) > _distance_to_nearest_spawn(best):
			best = spot
	return best

## How far `spot` is from the nearest player spawn on the current stage; INF
## when the stage declares none.
func _distance_to_nearest_spawn(spot: Vector2) -> float:
	var nearest: float = INF
	for spawn: Vector2 in _rm._stage_spawn_points:
		nearest = minf(nearest, spot.distance_to(spawn))
	return nearest
