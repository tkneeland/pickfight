extends Node2D

## A bullet (issue #55, ADR-0014): what a firing weapon -- the boomstick --
## shoots every `WeaponStats.fire_interval`. `Player._fire()` builds one from
## `scenes/Projectile.tscn` and hands it the shooter, where it starts, which
## way it flies and the weapon's numbers.
##
## It flies in a straight line at a constant speed, with no gravity, and it
## hits **once**: the first player body or piece of terrain in its path,
## whichever it reaches first. A player it hits takes `projectile_damage` and
## is shoved along the line of flight. Weapon heads do not block it (#92,
## reversing #61). Either way the bullet is gone.
##
## **Swept, never discretely collided.** At the boomstick's 900 px/s a bullet
## covers 15 px a tick, more than a weapon head's barrel or blade is thick
## (and a faster weapon could outrun a 24 px platform), so a collision shape
## that the engine checked at each tick's end would skip straight through
## them -- the tunnelling `WeaponHead` exists to undo for the head
## (ADR-0006). A bullet has no joints dragging it, so it needs none of the
## head's machinery: each tick it shape-casts its own circle along exactly
## the motion it is about to make, against terrain and player bodies, and
## stops at the first contact. It is a
## plain `Node2D`, not a physics body, so the engine never moves it any other
## way.
##
## **Never its own shooter.** A bullet leaves from the head's anchor, and at
## rest reach that anchor is inside the shooter's own body. The shooter's
## body is excluded from every cast, and so is the shooter's own head -- read
## afresh each tick, so it is whichever head the shooter holds now -- which
## the bullet leaves through: it spawns at the head's anchor and flies down
## the barrel. Since #92 no head stops a bullet, so the exclusion only
## matters if heads go back into the cast.
##
## **Outlives its shooter's elimination (#570).** A bullet already fired keeps
## flying and can still hit, credited to the shooter. Round end and a kick
## (`Player.clear_shots()`) and the shooter node leaving the tree still free it.

## Player.LAYER_WORLD and Player.LAYER_HEAD, repeated rather than read so
## this script need not preload the player: terrain and player bodies, and
## weapon heads. Areas (pickups, kill zones) are on neither, and hafts collide
## with nothing.
const LAYER_WORLD: int = 1
const LAYER_HEAD: int = 2
## How far a bullet flies before it gives up, in pixels. Wider than any stage,
## so it only ends a bullet that has already left the stage behind.
const MAX_TRAVEL: float = 4000.0
## Every live bullet is in this group, which is how scenarios find them.
const GROUP: StringName = &"projectiles"
## Drawn: a streak behind the bullet this many radii long, and the colours.
const TRAIL_RADII: float = 5.0
const CORE_COLOR: Color = Color(1.0, 0.95, 0.7, 1.0)
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.8)

## The bullet met `collider` (terrain, a head, a player, or null) at `point`
## and is about to go. A sound hook (issue #75, ADR-0016); gameplay ignores it.
signal impacted(collider: Object, point: Vector2)

## Who fired it. Read by scenarios; never hit by the bullet itself.
var shooter: Node2D
## Issue #516: the weapon that fired this bullet (file basename), kept for
## credit after the shooter swaps weapons mid-flight.
var weapon_id: String = ""
## Unit vector the bullet flies along.
var direction: Vector2 = Vector2.RIGHT
var speed: float = 0.0
var damage: float = 0.0
var knockback: float = 0.0
var radius: float = 3.0
## Pixels flown so far.
var travelled: float = 0.0

var _origin: Vector2 = Vector2.ZERO
var _shape: CircleShape2D
## The shooter's body, excluded from every cast. The shooter's head is added
## to it each tick in `_exclusions()`.
var _exclude: Array[RID] = []
var _colour: Color = Color.WHITE

## Everything a bullet needs, handed over before it enters the tree. `stats`
## is the shooter's `WeaponStats`; only its projectile fields are read.
func setup(from_shooter: Node2D, origin: Vector2, flight: Vector2, stats: Resource) -> void:
	shooter = from_shooter
	_origin = origin
	direction = flight.normalized() if flight != Vector2.ZERO else Vector2.RIGHT
	speed = stats.projectile_speed
	damage = stats.projectile_damage
	knockback = stats.projectile_knockback
	radius = maxf(0.5, stats.projectile_radius)
	if from_shooter is CollisionObject2D:
		_exclude = [(from_shooter as CollisionObject2D).get_rid()]
	var identity: Variant = from_shooter.get("identity_color") if from_shooter != null else null
	_colour = identity if identity is Color else Color.WHITE

func _ready() -> void:
	add_to_group(GROUP)
	z_index = 50
	global_position = _origin
	# Placed after entering the tree: a spawn, not motion (issue #108).
	reset_physics_interpolation()
	_shape = CircleShape2D.new()
	_shape.radius = radius

func _physics_process(delta: float) -> void:
	if not is_instance_valid(shooter):
		queue_free()
		return
	var motion: Vector2 = direction * speed * delta
	var blocker: Node = _shield_holder_blocking(global_position, global_position + motion, radius)
	if blocker != null:
		impacted.emit(blocker, global_position)
		queue_free()
		return
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0.0, global_position)
	query.motion = motion
	# One cast against everything that can stop a bullet, so whichever of
	# terrain or a player is nearest along the path is what it meets. Weapon
	# heads are left out: bullets fly through them (#92, reversing #61).
	query.collision_mask = LAYER_WORLD
	query.exclude = _exclusions()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var fractions: PackedFloat32Array = space.cast_motion(query)
	var unsafe: float = fractions[1] if fractions.size() >= 2 else 1.0
	if unsafe >= 1.0:
		global_position += motion
		travelled += motion.length()
		if travelled >= MAX_TRAVEL:
			queue_free()
		return
	# Something is in the way. Move to the first touching position and ask
	# what it is -- the cast only says when, not what.
	global_position += motion * unsafe
	travelled += motion.length() * unsafe
	query.transform = Transform2D(0.0, global_position)
	query.motion = Vector2.ZERO
	var collider: Object = null
	var point: Vector2 = global_position + direction * radius
	var rest: Dictionary = space.get_rest_info(query)
	if not rest.is_empty():
		collider = instance_from_id(rest["collider_id"])
		point = rest["point"]
	else:
		var overlaps: Array[Dictionary] = space.intersect_shape(query, 1)
		if not overlaps.is_empty():
			collider = overlaps[0]["collider"]
	_hit(collider, point)

## The bullet's one hit. A live player other than the shooter is shoved and
## takes the bullet's damage -- through the shooter, so it is reported as the
## shooter's `strike_landed` like any strike and reaches the hitmarker and the
## phones' buzz (#33, #34). Anything else -- terrain, or an opposing head,
## which is not in the players group -- takes nothing and is not pushed,
## except a breakable wall, which takes the bullet's damage (#53).
## Whatever it hit, the bullet is spent.
func _hit(collider: Object, point: Vector2) -> void:
	impacted.emit(collider, point)
	var victim: Node = collider as Node
	if victim != null and victim != shooter and victim.is_in_group("players") and victim.alive:
		if victim is RigidBody2D:
			(victim as RigidBody2D).apply_central_impulse(direction * knockback)
		if shooter != null and shooter.has_method("land_projectile_hit"):
			shooter.land_projectile_hit(victim, damage, point, weapon_id)
		else:
			victim.take_damage(damage)
	elif victim != null and victim.has_method("take_projectile_hit"):
		victim.take_projectile_hit(damage)
	queue_free()

## The shooter's body and, when it has a live rig, its current head. Read
## every tick rather than once at `setup()`: a pickup mid-flight swaps the
## shooter's head for a new body the bullet must also ignore.
func _exclusions() -> Array[RID]:
	var rids: Array[RID] = _exclude.duplicate()
	if shooter != null and shooter.has_method("weapon_head_rid"):
		var head: RID = shooter.weapon_head_rid()
		if head.is_valid():
			rids.append(head)
	return rids

## Issue #631, ADR-0024: the player, other than the shooter, whose shield's
## face turns a shot flying `from` -> `to`, or null.
func _shield_holder_blocking(from: Vector2, to: Vector2, radius: float) -> Node:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node != shooter and node.has_method("shield_face_blocks") \
				and node.shield_face_blocks(from, to, radius):
			return node
	return null

func _shooter_in_play() -> bool:
	return is_instance_valid(shooter) and bool(shooter.get("alive"))

func _draw() -> void:
	var tail: Vector2 = -direction * radius * TRAIL_RADII
	draw_line(tail, Vector2.ZERO, Color(_colour, 0.55), radius * 1.4)
	draw_circle(Vector2.ZERO, radius + 1.5, OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, radius, _colour)
	draw_circle(Vector2.ZERO, radius * 0.5, CORE_COLOR)
