extends StaticBody2D

## Speed strip stage part (issue #891): the mirror of `MudPatch`. A strip of
## solid ground that speeds a player up: while a player's body rests on it,
## the drag on its horizontal speed (along the strip's own X) is partly
## cancelled, so running tops out at about 1.5x its flat-floor pace and gets
## there faster. Leaving the strip stops the boost at once.
##
## A `StaticBody2D`, like `Conveyor`, `IcePatch` and `MudPatch`: ordinary
## terrain on the world layer. A thin `Area2D` band along the top face picks
## candidates, and the body's contact monitor decides who is really standing
## on it, so a player in the air above the strip is unaffected.
##
## **X only, nothing written.** Only the component along the strip's X is
## scaled, so jumping and falling are not boosted, and no body property is
## changed, so nothing needs restoring. The body's weapon (head and haft) gets
## the same factor, as `Conveyor` moves them together.
##
## **Heads are untouched (ADR-0006, ADR-0010).** The detector masks only the
## world layer, which a weapon head is not on, and a head is only sped up as
## part of its own player's weapon while that player stands on the strip.
##
## `_ready()` builds collision, visual and detector from the exports.

## Preloaded by path, never by `class_name` (CLAUDE.md), for `HEAD_GROUP`.
const WeaponHeadType := preload("res://scripts/WeaponHead.gd")

## The strip's collision and visual box, centred on the node.
@export var size: Vector2 = Vector2(160, 8)

## Drag cancelled per second along the strip's X. A body's own linear damping
## is 1.5, and top speed goes as the inverse of the drag, so 1.5 -> 1.0 is 1.5x.
const BOOST_RATE: float = 0.5
## Dark teal base with pale chevrons pointing right.
const STRIP_COLOR: Color = Color(0.1, 0.4, 0.45, 1)
const CHEVRON_COLOR: Color = Color(0.7, 1.0, 0.95, 0.95)
const _DETECTOR_ABOVE: float = 6.0
const _DETECTOR_BELOW: float = 2.0
const _CHEVRON_SPACING: float = 24.0

var _detector: Area2D

func _ready() -> void:
	var half: Vector2 = size / 2.0
	var rect := RectangleShape2D.new()
	rect.size = size
	var collision_shape := CollisionShape2D.new()
	collision_shape.name = "CollisionShape2D"
	collision_shape.shape = rect
	add_child(collision_shape)

	var strip := Polygon2D.new()
	strip.name = "Strip"
	strip.color = STRIP_COLOR
	strip.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	add_child(strip)

	var chevrons := Node2D.new()
	chevrons.name = "Chevrons"
	add_child(chevrons)
	var count: int = maxi(1, int(size.x / _CHEVRON_SPACING))
	for i in count:
		var chevron := Line2D.new()
		chevron.width = 1.5
		chevron.default_color = CHEVRON_COLOR
		var x: float = -half.x + _CHEVRON_SPACING * (float(i) + 0.5)
		chevron.points = PackedVector2Array([
			Vector2(x - 3.0, -half.y * 0.7), Vector2(x + 3.0, 0.0), Vector2(x - 3.0, half.y * 0.7),
		])
		chevrons.add_child(chevron)

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

func _physics_process(delta: float) -> void:
	for body: Node2D in _detector.get_overlapping_bodies():
		if body is RigidBody2D and body.is_in_group("players") and _touching(body):
			_boost(body as RigidBody2D, delta)

func _touching(body: RigidBody2D) -> bool:
	return body.contact_monitor and body.get_colliding_bodies().has(self)

## True while `body` is standing on the strip.
func is_boosting(body: RigidBody2D) -> bool:
	return _detector != null and _detector.get_overlapping_bodies().has(body) and _touching(body)

func _boost(body: RigidBody2D, delta: float) -> void:
	var axis: Vector2 = global_transform.x.normalized()
	var gain: float = exp(BOOST_RATE * delta)
	for part: RigidBody2D in [body] + _weapon_bodies_of(body):
		var along: float = part.linear_velocity.dot(axis)
		part.linear_velocity += axis * along * (gain - 1.0)

## The rigid bodies of `body`'s weapon (head and haft); see `Conveyor`.
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
