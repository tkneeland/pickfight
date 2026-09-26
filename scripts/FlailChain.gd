extends RefCounted

## The flail's chain and ball (issue #150): a ball hanging off the weapon's
## head on a chain of real jointed links. `Player` builds one into the rig of
## any weapon whose `WeaponStats.special` is `&"flail"`, and frees it with the
## rest of the rig.
##
##   head --PinJoint2D--> link --PinJoint2D--> link ... --PinJoint2D--> ball
##
## Nothing drives the chain or the ball. The arm swings the head, the joints
## drag the links after it, and the ball trails and whips round on the end:
## its speed is whatever the swing gave it, which is why the flail is hard to
## aim and why its big hits come from momentum. The ball scores its strikes
## on its own speed against `WeaponStats.ball_damage`, on the same scale as
## any head (`Player._land_ball_strike`).
##
## **The links collide with nothing**, like the haft: they are there to carry
## the chain's weight and its lag, and to be drawn. **The ball is a real
## weapon head** (`WeaponHead.gd`, on the head layer): it strikes players,
## blocks and is blocked by other heads, and it gets the head's own sweep, so
## a whipped ball is stopped at a thin platform's surface rather than carried
## through it by the joints (ADR-0006, the same reason every head has it). It
## passes through its own player's body and through the head it hangs from:
## the pair skips each other in the head-against-head correction
## (`WeaponHead.pair_exclude`) as well as in the solver.
##
## **The ball never owns a clash correction.** Its `drive_force` is 0, so in
## the one correction a pair of heads gets, the ball is always the one that
## gives way: nothing drives it, and a driven head is what a clash is decided
## by (ADR-0006).
##
## All of the rig's bodies are children of the rig itself, not of this node,
## so the bounce pad's launch (which hands the same velocity to every body in
## a launched player's rig) carries the chain and the ball as well.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const WeaponHeadType := preload("res://scripts/WeaponHead.gd")

## Player.LAYER_WORLD and Player.LAYER_HEAD, repeated so this script need not
## preload the player.
const LAYER_WORLD: int = 1
const LAYER_HEAD: int = 2

## Damping on the links and the ball. Well under the 1.5 the body and the arm
## carry: a ball that lost its speed to the air as fast as the arm does would
## never whip.
const LINK_DAMP: float = 0.3
const BALL_DAMP: float = 0.3
## How far past its length the chain may be pulled before the ball's outward
## speed is taken off it. A chain of pin joints stretches under load -- the
## ball is ten times a link's mass -- and this is the stop behind the joints,
## not the thing that holds the ball: at ordinary swings they hold it well
## inside this.
const CHAIN_STRETCH_LIMIT: float = 1.12
## Links are point masses on the end of a joint; a body with no shape has no
## inertia of its own, so each gets this small one.
const LINK_INERTIA_FRACTION: float = 0.25

## Drawn: each link as a small ring, the ball as `WeaponStats.ball_art`.
const LINK_DRAW_RADIUS: float = 3.2
const LINK_DRAW_SEGMENTS: int = 8
const LINK_COLOR: Color = Color(0.62, 0.62, 0.66, 1.0)
const LINK_EDGE_COLOR: Color = Color(0.2, 0.2, 0.22, 1.0)

## Seconds the drag must stay released with terrain between the head and the
## ball before the ball phases, and its alpha while it is: Player's
## gridlock rule (issue #115), applied to the ball, so a ball caught behind a
## platform wider than the player can swing round never tethers them there.
const PHASE_DELAY: float = 1.5
const PHASED_ALPHA: float = 0.4
const RAY_MAX_SKIPS: int = 4

var player: RigidBody2D
var head: RigidBody2D
var links: Array[RigidBody2D] = []
var ball: WeaponHeadType
var ball_shape: CollisionShape2D
var ball_visual: Polygon2D
## The chain's full length, head anchor to ball centre.
var length: float = 0.0
## The ball's velocity going into this tick's step, read by `Player` for a
## slow contact the solver reported: see `Player._head_velocity`.
var ball_velocity: Vector2 = Vector2.ZERO

## Builds the chain and the ball into `rig`, hanging straight out from `from_head`
## along `axis`. `stats` is the rig's effective `WeaponStats`.
func build(owner_player: RigidBody2D, rig: Node2D, from_head: RigidBody2D, stats: Resource,
		axis: Vector2, colour: Color) -> void:
	player = owner_player
	head = from_head
	var count: int = maxi(0, int(stats.chain_links))
	length = maxf(1.0, float(stats.chain_length))
	var segment: float = length / float(count + 1)
	var previous: RigidBody2D = head
	var at: Vector2 = head.global_position
	for i in count:
		at += axis * segment
		var link := RigidBody2D.new()
		link.name = "FlailLink%d" % i
		link.mass = maxf(0.005, float(stats.chain_link_mass))
		link.inertia = link.mass * segment * segment * LINK_INERTIA_FRACTION
		link.gravity_scale = player.gravity_scale
		link.linear_damp = LINK_DAMP
		link.angular_damp = 1.0
		link.collision_layer = 0
		link.collision_mask = 0
		link.add_child(_ring())
		rig.add_child(link)
		link.global_position = at
		_pin(rig, previous, link, previous.global_position)
		links.append(link)
		previous = link

	at += axis * segment
	ball = WeaponHeadType.new()
	ball.name = "FlailBall"
	# How a breakable wall knows to score it on `ball_damage`.
	ball.set_meta(&"flail_ball", true)
	ball.mass = maxf(0.01, float(stats.ball_mass))
	var radius: float = maxf(1.0, float(stats.ball_radius))
	ball.inertia = ball.mass * radius * radius * 0.5
	ball.gravity_scale = player.gravity_scale
	ball.linear_damp = BALL_DAMP
	ball.angular_damp = 1.0
	ball.collision_layer = LAYER_HEAD
	ball.collision_mask = LAYER_WORLD | LAYER_HEAD
	ball.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	var circle := CircleShape2D.new()
	circle.radius = radius
	ball_shape = CollisionShape2D.new()
	ball_shape.name = "BallCircle"
	ball_shape.shape = circle
	ball.add_child(ball_shape)
	ball.sweep_shapes = [ball_shape]
	ball.sweep_mask = LAYER_WORLD
	ball.sweep_exclude = [player.get_rid()]
	ball.drive_force = 0.0
	ball.contact_monitor = true
	ball.max_contacts_reported = 4
	ball_visual = Polygon2D.new()
	ball_visual.name = "BallVisual"
	var art: PackedVector2Array = stats.ball_art
	ball_visual.polygon = art if art.size() >= 3 else _circle(radius, 12)
	ball_visual.color = colour
	ball.add_child(ball_visual)
	rig.add_child(ball)
	ball.global_position = at
	ball.add_collision_exception_with(player)
	ball.add_collision_exception_with(head)
	ball.pair_exclude = [head]
	var head_excludes: Array[Node] = head.get("pair_exclude")
	head_excludes.append(ball)
	_pin(rig, previous, ball, previous.global_position)

## Every body the chain adds to the rig: the links, then the ball.
func bodies() -> Array[RigidBody2D]:
	var all: Array[RigidBody2D] = links.duplicate()
	if ball != null:
		all.append(ball)
	return all

## Once a tick, before the step, from `Player._physics_process`.
## `release_time` is how long the drag has stayed released.
func tick(release_time: float) -> void:
	if ball == null or not ball.is_inside_tree():
		return
	_limit_stretch()
	_update_phase(release_time)
	ball_velocity = ball.linear_velocity

## Out of play: stop the ball colliding now, since the rig it lives in is only
## freed at the end of the frame (`Player._clear_rig`).
func retire() -> void:
	if ball != null:
		ball.collision_layer = 0
		ball.collision_mask = 0

func set_colour(colour: Color) -> void:
	if ball_visual != null:
		ball_visual.color = colour

## The ball's collision circle where the physics has it: `{centre, radius}`,
## or empty without a ball.
func ball_circle_world() -> Dictionary:
	if ball_shape == null or not ball_shape.is_inside_tree():
		return {}
	return {"centre": ball_shape.global_position, "radius": (ball_shape.shape as CircleShape2D).radius}

func _limit_stretch() -> void:
	var span: Vector2 = ball.global_position - head.global_position
	var distance: float = span.length()
	if distance <= length * CHAIN_STRETCH_LIMIT or distance == 0.0:
		return
	var out: Vector2 = span / distance
	var away: float = (ball.linear_velocity - head.linear_velocity).dot(out)
	if away > 0.0:
		ball.linear_velocity -= out * away

func _update_phase(release_time: float) -> void:
	var cut_off: bool = _terrain_between(head.global_position, ball.global_position)
	if ball.phased:
		if not cut_off and not ball.overlaps_world():
			ball.set_phased(false)
	elif release_time >= PHASE_DELAY and cut_off:
		ball.set_phased(true)
	var alpha: float = PHASED_ALPHA if ball.phased else 1.0
	if ball_visual != null and not is_equal_approx(ball_visual.modulate.a, alpha):
		ball_visual.modulate.a = alpha

## Whether terrain lies on the straight line between two points. Players'
## bodies share the terrain layer and are stepped past.
func _terrain_between(from: Vector2, to: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = ball.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, LAYER_WORLD,
		[player.get_rid(), ball.get_rid(), head.get_rid()])
	query.collide_with_areas = false
	for i in RAY_MAX_SKIPS:
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider: Object = hit["collider"]
		if not (collider is Node and (collider as Node).is_in_group("players")):
			return true
		var exclude: Array[RID] = query.exclude
		exclude.append(hit["rid"])
		query.exclude = exclude
	return false

func _pin(rig: Node2D, a: RigidBody2D, b: RigidBody2D, at: Vector2) -> void:
	var joint := PinJoint2D.new()
	joint.name = "Chain%s" % b.name
	rig.add_child(joint)
	joint.global_position = at
	joint.disable_collision = true
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)

func _ring() -> Polygon2D:
	var ring := Polygon2D.new()
	ring.name = "LinkVisual"
	ring.polygon = _circle(LINK_DRAW_RADIUS, LINK_DRAW_SEGMENTS)
	ring.color = LINK_COLOR
	var edge := Line2D.new()
	var pts: PackedVector2Array = ring.polygon.duplicate()
	pts.append(pts[0])
	edge.points = pts
	edge.width = 1.2
	edge.default_color = LINK_EDGE_COLOR
	ring.add_child(edge)
	return ring

func _circle(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points
