extends StaticBody2D

## Conveyor belt stage part (issue #842): a strip of solid ground that carries
## a player's body along it. Running with the belt is faster, against it
## slower, and standing still drifts you along.
##
## A `StaticBody2D`, like `BouncePad`: the strip never moves and its collision
## is ordinary terrain on the world layer. Each physics tick it adds to the
## velocity of every player body resting on its top face a small share of
## `belt_speed`, along the strip's own right (+X); the player's linear damping
## and floor drag turn that steady push into a drift, so nothing is teleported
## and a player's own run adds to or fights it. A rotated strip carries along
## its own local X.
##
## **Who is carried.** Only a player's body (the `players` group) really
## touching the strip, found as `BouncePad` finds it: a thin `Area2D` band
## along the top face picks candidates, the body's contact monitor decides.
##
## **Heads are untouched (ADR-0006, ADR-0010).** The detector masks only the
## world layer, which a weapon head is not on, so a head plants on the belt as
## on any ground. The body's weapon (head and haft) gets the same change of
## velocity as the body, as `BouncePad` does, so the weapon's clamped drive
## has no reach error to haul the body back with.
##
## `_ready()` builds collision, visual and detector from the exports.

## Preloaded by path, never by `class_name` (CLAUDE.md), for `HEAD_GROUP`.
const WeaponHeadType := preload("res://scripts/WeaponHead.gd")

## The strip's collision and visual box, centred on the node.
@export var size: Vector2 = Vector2(400, 12)
## Belt speed in px/s, signed: positive carries along the strip's +X (right
## when unrotated), negative the other way.
@export var belt_speed: float = 140.0

## Steel grey, a shade off the terrain, with amber chevrons for the direction.
const BELT_COLOR: Color = Color(0.3, 0.3, 0.34, 1)
const CHEVRON_COLOR: Color = Color(0.95, 0.7, 0.2, 1)
## How fast the chevrons scroll, as a multiple of the belt's own speed.
const _SCROLL_SCALE: float = 1.0
## Per-second share of `belt_speed` added to a body's velocity.
const _PUSH_RATE: float = 12.0
const _DETECTOR_ABOVE: float = 6.0
const _DETECTOR_BELOW: float = 2.0
const _CHEVRON_SPACING: float = 40.0

var _detector: Area2D
var _chevrons: Node2D
var _scroll: float = 0.0

func _ready() -> void:
	var half: Vector2 = size / 2.0
	var rect := RectangleShape2D.new()
	rect.size = size
	var collision_shape := CollisionShape2D.new()
	collision_shape.name = "CollisionShape2D"
	collision_shape.shape = rect
	add_child(collision_shape)

	var belt := Polygon2D.new()
	belt.name = "Belt"
	belt.color = BELT_COLOR
	belt.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	add_child(belt)

	_chevrons = Node2D.new()
	_chevrons.name = "Chevrons"
	add_child(_chevrons)
	_rebuild_chevrons()

	_detector = Area2D.new()
	_detector.name = "Detector"
	_detector.collision_layer = 0
	_detector.collision_mask = 1  # world layer only: player bodies, not heads
	_detector.position = Vector2(0, -half.y - _DETECTOR_ABOVE / 2.0 + _DETECTOR_BELOW / 2.0)
	var detector_rect := RectangleShape2D.new()
	detector_rect.size = Vector2(size.x, _DETECTOR_ABOVE + _DETECTOR_BELOW)
	var detector_shape := CollisionShape2D.new()
	detector_shape.name = "DetectorShape"
	detector_shape.shape = detector_rect
	_detector.add_child(detector_shape)
	add_child(_detector)

## The world direction a positive `belt_speed` carries along: the strip's +X.
func carry_direction() -> Vector2:
	return global_transform.x.normalized()

func _rebuild_chevrons() -> void:
	for child: Node in _chevrons.get_children():
		child.queue_free()
	var h: float = size.y * 0.35
	var count: int = maxi(1, int(size.x / _CHEVRON_SPACING))
	for i in count:
		var chevron := Line2D.new()
		chevron.width = 2.0
		chevron.default_color = CHEVRON_COLOR
		chevron.points = PackedVector2Array([Vector2(-h, -h), Vector2(h, 0), Vector2(-h, h)])
		chevron.position = Vector2(-size.x / 2.0 + _CHEVRON_SPACING * (float(i) + 0.5), 0)
		_chevrons.add_child(chevron)

func _physics_process(delta: float) -> void:
	for body: Node2D in _detector.get_overlapping_bodies():
		if body is RigidBody2D and body.is_in_group("players") and _touching(body):
			_carry(body as RigidBody2D, delta)
	_animate(delta)

func _touching(body: RigidBody2D) -> bool:
	return body.contact_monitor and body.get_colliding_bodies().has(self)

func _carry(body: RigidBody2D, delta: float) -> void:
	var change: Vector2 = carry_direction() * belt_speed * _PUSH_RATE * delta
	body.linear_velocity += change
	for part: RigidBody2D in _weapon_bodies_of(body):
		part.linear_velocity += change

## Scrolls the chevrons along the belt, wrapping each spacing, and mirrors
## them when the belt runs backwards.
func _animate(delta: float) -> void:
	_scroll = fposmod(_scroll + belt_speed * _SCROLL_SCALE * delta, _CHEVRON_SPACING)
	_chevrons.position.x = _scroll
	_chevrons.scale.x = 1.0 if belt_speed >= 0.0 else -1.0

## The rigid bodies of `body`'s weapon (head and haft); see
## `BouncePad._weapon_bodies_of()` for why they move with the body.
func _weapon_bodies_of(body: RigidBody2D) -> Array[RigidBody2D]:
	var parts: Array[RigidBody2D] = []
	var rid: RID = body.get_rid()
	for head: Node in get_tree().get_nodes_in_group(WeaponHeadType.HEAD_GROUP):
		if head.is_queued_for_deletion() or not (head is RigidBody2D) or not rid in head.sweep_exclude:
			continue
		for child: Node in head.get_parent().get_children():
			if child is RigidBody2D and child != body and not parts.has(child):
				parts.append(child as RigidBody2D)
	return parts
