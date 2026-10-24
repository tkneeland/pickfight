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
const WeaponThemesScript := preload("res://scripts/WeaponThemes.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")
const PickupSpawnRingScript := preload("res://scripts/PickupSpawnRing.gd")
const EffectStreamScript := preload("res://scripts/EffectStream.gd")

## Which pickup weapons the host switched off (#294); a scenario hands in its own.
var settings: RefCounted = HostSettingsScript.shared()
## Game time (#182), not wall clock: the interval stops for a pause and runs
## at `Engine.time_scale`.
const GameClockScript := preload("res://scripts/GameClock.gd")
## Where a pickup lands on a stage that declares no `PickupSpawn*` markers,
## relative to the stage's origin: above its centre (user story 17).
const FALLBACK_PICKUP_OFFSET: Vector2 = Vector2(0.0, -200.0)
## Two pickups within this of each other are on the same spot.
const PICKUP_SPOT_EPSILON: float = 8.0
## A spot is occupied while a living player's body is within this of it: the
## pickup's largest touch radius (25) plus a body's reach plus a margin (#333).
const PICKUP_OCCUPIED_RADIUS: float = 60.0
## A pickup spot this close to a player spawn is skipped (#111, owner
## playtest: players spawned on a drop and took it before moving). About a
## body width plus the largest pickup's trigger, with room to spare, so a
## player standing on their spawn cannot touch a pickup.
const PICKUP_CLEAR_OF_SPAWN_RADIUS: float = 120.0
## A new pickup pops in (#816): scales up from this to 1x over `POP_SEC` with
## a small overshoot, under an expanding ring. Motion only; it stays
## collectable from the first frame.
const POP_START_SCALE: float = 0.2
const POP_SEC: float = 0.3

## Multiplies the spawn interval (round modifier Pickup rush, #841); 1.0 is as
## authored. A modifier sets it for a round and puts it back on undo.
var interval_scale: float = 1.0

## The RoundManager this directs pickups for.
var _rm: Node
var _pickups: Array[Node2D] = []
var _next_pickup_msec: int = 0
## Every draw this node makes -- which weapon, which spot (issue #187). The
## RoundManager hands it a stream derived from the match seed; until then (a
## director driven by hand) it is an unseeded one of its own.
var rng := RandomNumberGenerator.new()
## Weapons still to come out before the draw repeats one (`draw_weapon`).
var _bag: Array[Resource] = []
## The weapon `draw_weapon` last returned (#1042), so a fresh bag never opens
## with the weapon that closed the last one. Reset with the bag at round start.
var _last_drawn: Resource = null

func _init(round_manager: Node = null) -> void:
	name = "PickupDirector"
	_rm = round_manager
	rng.randomize()

## Round start: clear anything left over, put the first pickup down, and
## start the interval from now.
func start() -> void:
	clear()
	# The bag is dealt per stage (#310): a new stage has a new theme.
	_bag.clear()
	_last_drawn = null
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
## `crowded_interval_scale` from `crowded_roster` players up (#152), times
## `interval_scale`.
func interval_sec() -> float:
	var server: Variant = _rm._controller_server
	var roster: int = server.claimed_slots().size() if server != null else 0
	if roster >= _rm.crowded_roster:
		return _rm.pickup_spawn_interval_sec * _rm.crowded_interval_scale * interval_scale
	return _rm.pickup_spawn_interval_sec * interval_scale

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
	offered = _switched_on(offered)
	var weapon: Resource = draw_weapon(offered)
	if weapon == null:
		return
	var pickup: Node2D = scene.instantiate() as Node2D
	pickup.set_weapon(weapon)
	parent.add_child(pickup)
	pickup.global_position = spot
	# Placed after entering the tree: a spawn, not motion (issue #108).
	pickup.reset_physics_interpolation()
	_pickups.append(pickup)
	_pop_in(pickup, parent, spot)

## The spawn cue (#816): the pickup scales up with an overshoot and a one-shot
## ring expands from its spot. Added here so Pickup.gd is untouched.
func _pop_in(pickup: Node2D, parent: Node, spot: Vector2) -> void:
	pop_scale(pickup)
	PickupSpawnRingScript.spawn_at(parent, spot)
	# Issue #976: the joiner plays the same ring and pop on its pickup puppet
	# (the id is the snapshot's `pickup_id`).
	EffectStreamScript.record("pickup_ring", {"p": spot, "id": pickup.get_instance_id() & 0xFFFF}, pickup)
	# Issue #998: a soft cue at the spot; online clients hear it through the
	# generic Sfx snapshot trailer.
	var sfx: Node = pickup.get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.play(&"pickup_spawn", spot, 1.0)

## The pop-in scale (#816) on `node`, shared with the Online joiner's pickup
## puppet (#976).
static func pop_scale(node: Node2D) -> void:
	node.scale = Vector2.ONE * POP_START_SCALE
	var tween: Tween = node.create_tween()
	tween.tween_property(node, "scale", Vector2.ONE, POP_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## `offered` without the weapons the host switched off (#294). Left whole if
## that would leave nothing, which the settings do not allow anyway.
func _switched_on(offered: Array[Resource]) -> Array[Resource]:
	var kept: Array[Resource] = []
	for stats: Resource in offered:
		if stats != null and settings.is_weapon_enabled(HostSettingsScript.name_of(stats.resource_path)):
			kept.append(stats)
	return kept if not kept.is_empty() else offered

## The next weapon from a shuffled bag of everything offered, refilled once
## it runs dry: every weapon comes out before the bag is dealt again.
## Playtest 2026-09-27: with a uniform draw over eight weapons and a handful
## of pickups a session, the boomerang never turned up. The stage's theme
## (#310, WeaponThemes) puts extra copies of the weapons that suit it in the
## bag, but every offered weapon keeps at least one. A weapon no longer
## offered is skipped, and the pickaxe never goes in. Shuffled from `rng`, so
## a seeded match still draws the same sequence.
func draw_weapon(offered: Array[Resource]) -> Resource:
	# #1038: a weapon already lying on the stage is passed over (and kept for
	# a later draw) while any other offered weapon is not. When every offered
	# weapon is lying there, nothing is skipped.
	var live: Array[String] = _live_weapon_paths()
	var skip_live: bool = false
	for stats: Resource in offered:
		if not live.has(stats.resource_path):
			skip_live = true
			break
	var deferred: Array[Resource] = []
	var drawn: Resource = null
	while drawn == null:
		if _bag.is_empty():
			if not _refill_bag(offered):
				break
		var next: Resource = _bag.pop_back()
		if not offered.has(next):
			continue
		if skip_live and live.has(next.resource_path):
			deferred.append(next)
			continue
		drawn = next
	# Put the passed-over weapons back at the bottom of the bag, so they come
	# out after the rest of it.
	for stats: Resource in deferred:
		_bag.push_front(stats)
	if drawn != null:
		_last_drawn = drawn
	return drawn

## Deals a fresh shuffled bag of `offered`, themed copies included. False when
## that leaves it empty. Shuffled off our own stream: Array.shuffle() uses the
## global RNG.
func _refill_bag(offered: Array[Resource]) -> bool:
	var stage: Variant = _rm._current_stage if _rm != null else null
	var copies: Dictionary = WeaponThemesScript.copies_for(stage, offered)
	for stats: Resource in offered:
		if copies.has(stats):
			for i in int(copies[stats]):
				_bag.append(stats)
	for i in range(_bag.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var swap: Resource = _bag[i]
		_bag[i] = _bag[j]
		_bag[j] = swap
	# #1042: the next pop must not repeat the weapon that closed the last bag.
	# Swap it with a different entry, picked off our own stream; a bag of one
	# weapon repeats as before.
	if not _bag.is_empty() and _last_drawn != null and _bag.back() == _last_drawn:
		var others: Array[int] = []
		for i in _bag.size():
			if _bag[i] != _last_drawn:
				others.append(i)
		if not others.is_empty():
			var k: int = others[rng.randi() % others.size()]
			var top: Resource = _bag.back()
			_bag[_bag.size() - 1] = _bag[k]
			_bag[k] = top
	return not _bag.is_empty()

## Resource paths of the weapons of the pickups on the stage now (#1038).
func _live_weapon_paths() -> Array[String]:
	var paths: Array[String] = []
	for pickup: Node2D in _live_pickups():
		var stats: Variant = pickup.get("weapon_stats")
		if stats != null:
			paths.append((stats as Resource).resource_path)
	return paths

## A random declared spot with no pickup already on it, or the fallback above
## the stage's centre when the stage declares none. Null when every spot is
## taken. Spots within PICKUP_CLEAR_OF_SPAWN_RADIUS of a player spawn are
## skipped while any other free spot remains; if every free spot is near a
## spawn, the one furthest from all spawns is used, so a stage still gets
## its pickups (#111). A spot at or below the floor kill zone's surface is
## never used (#200). A spot a living player is standing on is skipped too, so
## a weapon is not swapped out from under its holder; null when all are (#333).
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
	var live: Array[Node2D] = _live_pickups()
	for spot: Vector2 in spots:
		if spot.y >= lava:
			continue
		var taken: bool = false
		for pickup: Node2D in live:
			if pickup.global_position.distance_to(spot) < PICKUP_SPOT_EPSILON:
				taken = true
				break
		if not taken and _player_on(spot):
			taken = true
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
	var best_distance: float = _distance_to_nearest_spawn(best)
	for spot: Vector2 in free:
		var distance: float = _distance_to_nearest_spawn(spot)
		if distance > best_distance:
			best = spot
			best_distance = distance
	return best

## Whether a living player stands on or hovers over `spot`, close enough that
## a pickup spawned there would swap their weapon under them (#333). Only the
## body triggers a swap (ADR-0009), so only bodies count.
func _player_on(spot: Vector2) -> bool:
	for player: Variant in _rm._players:
		if player == null or not is_instance_valid(player):
			continue
		if player.get("alive") == false:
			continue
		if (player as Node2D).global_position.distance_to(spot) < PICKUP_OCCUPIED_RADIUS:
			return true
	return false

## How far `spot` is from the nearest player spawn on the current stage; INF
## when the stage declares none.
func _distance_to_nearest_spawn(spot: Vector2) -> float:
	var nearest: float = INF
	for spawn: Vector2 in _rm._stage_spawn_points:
		nearest = minf(nearest, spot.distance_to(spawn))
	return nearest
