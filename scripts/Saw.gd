extends "res://scripts/DamageHazard.gd"

## Saw stage part (issue #282): a spinning blade that can travel back and
## forth along a path. A touch deals `damage` and throws the player away from
## the blade's centre; see `DamageHazard.gd`. Travel works as on
## `MovingPlatform.gd`: `travel` is the offset to the far end, `one_way_sec`
## the time for one leg, and a zero `travel` leaves the saw spinning in place.
## Not solid, so it never carries or blocks anyone.

@export var radius: float = 28.0
@export var spin_deg_per_sec: float = 360.0
@export var travel: Vector2 = Vector2.ZERO
@export var one_way_sec: float = 2.0

var _visual: Polygon2D
var _origin: Vector2
var _elapsed: float = 0.0

func _ready() -> void:
	_origin = position
	var circle := CircleShape2D.new()
	circle.radius = radius
	var shape := CollisionShape2D.new()
	shape.name = "SawShape"
	shape.shape = circle
	add_child(shape)

	_visual = Polygon2D.new()
	_visual.name = "SawVisual"
	_visual.color = DEFAULT_COLOR
	var points := PackedVector2Array()
	# Hooked teeth (#687): each rises slowly and drops sharply, so the blade
	# reads as cutting in its spin direction.
	var teeth: int = 12
	for i in teeth:
		var a: float = TAU * float(i) / float(teeth)
		var step: float = TAU / float(teeth)
		points.append(Vector2(cos(a), sin(a)) * radius * 0.72)
		points.append(Vector2(cos(a + step * 0.75), sin(a + step * 0.75)) * radius)
	_visual.polygon = points
	add_child(_visual)
	# Spins with the blade: a lit disc, a dark hub and a bright axle.
	_visual.add_child(_disc("SawFace", radius * 0.6, Color(1, 1, 1, 0.16)))
	_visual.add_child(_disc("SawHub", radius * 0.3, Color(0, 0, 0, 0.55)))
	_visual.add_child(_disc("SawAxle", radius * 0.1, Color(1, 1, 1, 0.6)))

func _disc(node_name: String, r: float, colour: Color) -> Polygon2D:
	var disc := Polygon2D.new()
	disc.name = node_name
	disc.color = colour
	var ring := PackedVector2Array()
	for i in 16:
		ring.append(Vector2.RIGHT.rotated(TAU * float(i) / 16.0) * r)
	disc.polygon = ring
	return disc

func set_hazard_color(colour: Color) -> void:
	if _visual != null:
		_visual.color = colour

func hazard_color() -> Color:
	return _visual.color

## The blade's current spin, in radians. Observable, for scenarios.
func blade_rotation() -> float:
	return _visual.rotation

func _physics_process(delta: float) -> void:
	_visual.rotation += deg_to_rad(spin_deg_per_sec) * delta
	if travel != Vector2.ZERO:
		_elapsed += delta
		var leg: float = maxf(one_way_sec, 0.001)
		var phase: float = fposmod(_elapsed, leg * 2.0) / leg
		var t: float = phase if phase <= 1.0 else 2.0 - phase
		position = _origin + travel * t
	super._physics_process(delta)
