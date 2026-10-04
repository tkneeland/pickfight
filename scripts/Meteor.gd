extends Node2D

## One meteor of the Meteor shower round modifier (issue #147,
## `RoundModifiers.gd`). Used by that modifier only; nothing else spawns it.
##
## It flies in a straight line at a fixed velocity from above the stage and is
## gone the moment it touches anything solid. A player it touches takes a flat
## `damage` and is knocked away from it, down the same hit path a falling rock
## (`FallingRock.gd`, issue #53) takes: `take_damage()` on the victim, then the
## victim's own `strike_landed` reporting it -- the victim as its own attacker,
## since a meteor has no owner -- so the hitmarker, damage number and phone buzz
## all treat it as they treat a rock.
##
## Like the rock it is not a physics body: this script moves it and asks the
## physics server what it overlaps each tick, on the world layer only (terrain
## and player bodies), so weapon heads neither block nor bat it about. Its step
## per tick stays well under its own diameter plus the thinnest platform, so it
## cannot pass through a platform or a player between two ticks.
##
## Preloaded by path, never named by `class_name` (CLAUDE.md).

## Mirrors `Player.LAYER_WORLD`, as `FallingRock` does.
const _WORLD_LAYER: int = 1
const _PLAYERS_GROUP: StringName = &"players"
## Hot core and a darker rim, so it reads as a burning rock and not a pickup.
const CORE_COLOR: Color = Color(1.0, 0.62, 0.15, 1.0)
const RIM_COLOR: Color = Color(0.55, 0.2, 0.05, 1.0)
const TRAIL_COLOR: Color = Color(1.0, 0.5, 0.1, 0.45)
## How long the drawn trail is, as seconds of flight behind the meteor.
const TRAIL_SEC: float = 0.08
## Where the knock's lift comes from: its direction is (away-from-meteor
## sideways, -KNOCK_LIFT) normalised, so ground friction does not eat it.
const KNOCK_LIFT: float = 0.5

var velocity: Vector2 = Vector2(0.0, 900.0)
var radius: float = 16.0
var damage: float = 12.0
var knock_speed: float = 650.0
## World y past which a meteor that met nothing is dropped: it has left the
## stage through a pit.
var lowest_y: float = 4000.0

var _query: PhysicsShapeQueryParameters2D
var _hits: int = 0
var _done: bool = false

## Sets the meteor up before it is added to the tree.
func setup(from: Vector2, flight_velocity: Vector2, hit_damage: float, knock: float, meteor_radius: float, floor_y: float) -> void:
	position = from
	velocity = flight_velocity
	damage = hit_damage
	knock_speed = knock
	radius = meteor_radius
	lowest_y = floor_y

func _ready() -> void:
	z_index = 5
	var circle := CircleShape2D.new()
	circle.radius = radius
	_query = PhysicsShapeQueryParameters2D.new()
	_query.shape = circle
	_query.collision_mask = _WORLD_LAYER
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	queue_redraw()

## Players this meteor has hit (0 or 1): a scenario seam.
func hit_count() -> int:
	return _hits

func _draw() -> void:
	draw_line(Vector2.ZERO, -velocity * TRAIL_SEC, TRAIL_COLOR, radius * 1.4)
	draw_circle(Vector2.ZERO, radius, RIM_COLOR)
	draw_circle(Vector2.ZERO, radius * 0.7, CORE_COLOR)

func _physics_process(delta: float) -> void:
	if _done:
		return
	global_position += velocity * delta
	_query.transform = Transform2D(0.0, global_position)
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var struck_player: Node = null
	var struck_ground: bool = false
	for hit: Dictionary in space.intersect_shape(_query, 8):
		var body: Object = hit.get("collider")
		if body == null:
			continue
		if body is Node and (body as Node).is_in_group(_PLAYERS_GROUP):
			if struck_player == null and body.get("alive") == true:
				struck_player = body
		else:
			struck_ground = true
	if struck_player != null:
		_strike(struck_player)
		_impact()
	elif struck_ground:
		_impact()
	elif global_position.y > lowest_y:
		_done = true
		queue_free()

func _strike(victim: Node) -> void:
	_hits += 1
	var victim_body := victim as Node2D
	var away: Vector2 = (victim_body.global_position - global_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.UP
	var point: Vector2 = global_position + away * radius
	# Report what the hit actually took off (issue #162): a spawn-protected
	# player takes nothing, and a report of the full damage would put a
	# phantom number on screen and buzz their phone. Nothing dealt, nothing
	# reported; the knock still lands.
	var before: Variant = victim.get("damage")
	victim.take_damage(damage, point)
	var after: Variant = victim.get("damage")
	var dealt: float = damage
	if before != null and after != null:
		dealt = float(after) - float(before)
	if dealt > 0.0 and victim.has_signal("strike_landed"):
		victim.emit_signal("strike_landed", victim, dealt, point, not victim.alive)
	if not victim.alive:
		return
	# Sideways away from where the meteor came down, with some lift: a meteor
	# landing square on a player's crown would otherwise drive them into the
	# floor, which reads as nothing happening.
	var side: float = signf(victim_body.global_position.x - global_position.x)
	if side == 0.0:
		side = signf(velocity.x) if velocity.x != 0.0 else 1.0
	var direction: Vector2 = Vector2(side, -KNOCK_LIFT).normalized()
	var body := victim as RigidBody2D
	if body != null:
		body.apply_central_impulse(direction * knock_speed * body.mass)

func _impact() -> void:
	_done = true
	var sfx: Node = get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.play(&"rock_impact", global_position, 0.6)
	queue_free()
