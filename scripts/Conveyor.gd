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

## Preloaded by path, never by `class_name` (CLAUDE.md).
const PartKitScript := preload("res://scripts/PartKit.gd")

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

## Issue #976: the chevrons scroll on a clock the Online client keeps in step
## with the host's (NetSync.gd); within a few pixels is in step.
const NET_CLOCKS: Array[String] = ["_scroll"]
const NET_CLOCK_TOLERANCE: float = 4.0
var _detector: Area2D
var _chevrons: Node2D
var _scroll: float = 0.0

func _ready() -> void:
	PartKitScript.add_rect_shape(self, size)

	var belt := Polygon2D.new()
	belt.name = "Belt"
	belt.color = BELT_COLOR
	belt.polygon = PartKitScript.rect_polygon(size)
	add_child(belt)

	_chevrons = Node2D.new()
	_chevrons.name = "Chevrons"
	add_child(_chevrons)
	_rebuild_chevrons()

	# World layer only: player bodies, not heads.
	_detector = PartKitScript.add_top_detector(self, size, _DETECTOR_ABOVE, _DETECTOR_BELOW)

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
		if body is RigidBody2D and body.is_in_group("players") and PartKitScript.touching(self, body):
			_carry(body as RigidBody2D, delta)
	_animate(delta)

## The weapon (head and haft) moves with the body; see `BouncePad`'s note on
## why.
func _carry(body: RigidBody2D, delta: float) -> void:
	var change: Vector2 = carry_direction() * belt_speed * _PUSH_RATE * delta
	body.linear_velocity += change
	for part: RigidBody2D in PartKitScript.weapon_bodies_of(get_tree(), body):
		part.linear_velocity += change

## Scrolls the chevrons along the belt, wrapping each spacing, and mirrors
## them when the belt runs backwards.
func _animate(delta: float) -> void:
	_scroll = fposmod(_scroll + belt_speed * _SCROLL_SCALE * delta, _CHEVRON_SPACING)
	_chevrons.position.x = _scroll
	_chevrons.scale.x = 1.0 if belt_speed >= 0.0 else -1.0
