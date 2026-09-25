extends Node2D

## A bullet (issue #55, ADR-0014): what a firing weapon -- the boomstick --
## shoots every `WeaponStats.fire_interval`. `Player._fire()` builds one from
## `scenes/Projectile.tscn` and hands it the shooter, where it starts, which
## way it flies and the weapon's numbers.
##
## It flies in a straight line at a constant speed, with no gravity, and it
## hits **once**: the first player body, piece of terrain or opposing weapon
## head in its path, whichever it reaches first. A player it hits takes
## `projectile_damage` and is shoved along the line of flight. A head it hits
## blocks it (issue #61): no damage, no shove. Either way the bullet is gone.
##
## **Swept, never discretely collided.** At the boomstick's 900 px/s a bullet
## covers 15 px a tick, more than a weapon head's barrel or blade is thick
## (and a faster weapon could outrun a 24 px platform), so a collision shape
## that the engine checked at each tick's end would skip straight through
## them -- the tunnelling `WeaponHead` exists to undo for the head
## (ADR-0006). A bullet has no joints dragging it, so it needs none of the
## head's machinery: each tick it shape-casts its own circle along exactly
## the motion it is about to make, against terrain, player bodies and heads
## alike, and stops at the first contact. It is a
## plain `Node2D`, not a physics body, so the engine never moves it any other
## way.
##
## **Never its own shooter.** A bullet leaves from the head's anchor, and at
## rest reach that anchor is inside the shooter's own body. The shooter's
## body is excluded from every cast, and so is the shooter's own head -- read
## afresh each tick, so it is whichever head the shooter holds now -- which
## the bullet leaves through: it spawns at the head's anchor and flies down
## the barrel. Every other player's head stops it (issue #61, ADR-0014).
##
## **Gone when its shooter leaves play.** Elimination and the end of a round
## both put the shooter through `Player._go_inert()`, which frees every
## bullet it has in flight. Each bullet also checks its shooter every tick
## before it moves, so none can land a hit for a player who is out of the
## round.

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

## Who fired it. Read by scenarios; never hit by the bullet itself.
var shooter: Node2D
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
	_shape = CircleShape2D.new()
	_shape.radius = radius

func _physics_process(delta: float) -> void:
	if not _shooter_in_play():
		queue_free()
		return
	var motion: Vector2 = direction * speed * delta
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0.0, global_position)
	query.motion = motion
	# One cast against everything that can stop a bullet, so whichever of a
	# head, terrain or a player is nearest along the path is what it meets.
	query.collision_mask = LAYER_WORLD | LAYER_HEAD
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
## which is not in the players group -- takes nothing and is not pushed.
## Whatever it hit, the bullet is spent.
func _hit(collider: Object, point: Vector2) -> void:
	var victim: Node = collider as Node
	if victim != null and victim != shooter and victim.is_in_group("players") and victim.alive:
		if victim is RigidBody2D:
			(victim as RigidBody2D).apply_central_impulse(direction * knockback)
		if shooter != null and shooter.has_method("land_projectile_hit"):
			shooter.land_projectile_hit(victim, damage, point)
		else:
			victim.take_damage(damage)
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

func _shooter_in_play() -> bool:
	return is_instance_valid(shooter) and bool(shooter.get("alive"))

func _draw() -> void:
	var tail: Vector2 = -direction * radius * TRAIL_RADII
	draw_line(tail, Vector2.ZERO, Color(_colour, 0.55), radius * 1.4)
	draw_circle(Vector2.ZERO, radius + 1.5, OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, radius, _colour)
	draw_circle(Vector2.ZERO, radius * 0.5, CORE_COLOR)
