extends "res://scripts/DamageHazard.gd"

## Spikes stage part (issue #282): a static row of points. A touch deals
## `damage` and throws the player up and away; see `DamageHazard.gd`. The
## spikes are not solid, so a player falls onto them and is hurt rather than
## standing on them. Place the part with its base on the floor; the points
## face the node's local up.

## The footprint, centred on the node: width of the row by the points' height.
@export var size: Vector2 = Vector2(96, 28)

var _visual: Polygon2D

func _ready() -> void:
	var rect := RectangleShape2D.new()
	rect.size = size
	var shape := CollisionShape2D.new()
	shape.name = "SpikesShape"
	shape.shape = rect
	add_child(shape)

	var half: Vector2 = size / 2.0
	var teeth: int = maxi(1, int(round(size.x / 24.0)))
	var points := PackedVector2Array([Vector2(-half.x, half.y)])
	for i in teeth:
		var x0: float = -half.x + size.x * float(i) / float(teeth)
		var x1: float = -half.x + size.x * float(i + 1) / float(teeth)
		points.append(Vector2((x0 + x1) / 2.0, -half.y))
		points.append(Vector2(x1, half.y))
	_visual = Polygon2D.new()
	_visual.name = "SpikesVisual"
	_visual.color = DEFAULT_COLOR
	_visual.polygon = points
	add_child(_visual)
	# Readable silhouette (#687): a lit left face on every tooth and a dark base bar.
	var lit := PackedVector2Array()
	var faces: Array = []
	for i in teeth:
		var x0: float = -half.x + size.x * float(i) / float(teeth)
		var x1: float = -half.x + size.x * float(i + 1) / float(teeth)
		var k: int = lit.size()
		lit.append(Vector2(x0, half.y))
		lit.append(Vector2((x0 + x1) / 2.0, -half.y))
		lit.append(Vector2((x0 + x1) / 2.0, half.y))
		faces.append(PackedInt32Array([k, k + 1, k + 2]))
	var shine := Polygon2D.new()
	shine.name = "SpikesShine"
	shine.color = Color(1, 1, 1, 0.28)
	shine.polygon = lit
	shine.polygons = faces
	_visual.add_child(shine)
	var base := Polygon2D.new()
	base.name = "SpikesBase"
	base.color = Color(0, 0, 0, 0.4)
	base.polygon = PackedVector2Array([Vector2(-half.x, half.y - 6.0), Vector2(half.x, half.y - 6.0), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	_visual.add_child(base)

func set_hazard_color(colour: Color) -> void:
	if _visual != null:
		_visual.color = colour

func hazard_color() -> Color:
	return _visual.color

## Up and away: mostly along the node's up, tilted toward the side the player
## is on, so spikes read as launching you off them.
func knockback_direction(body: Node2D) -> Vector2:
	var up: Vector2 = -global_transform.y.normalized()
	var side: float = clampf((body.global_position - global_position).dot(global_transform.x.normalized()) / maxf(size.x / 2.0, 1.0), -1.0, 1.0)
	return (up + global_transform.x.normalized() * side * 0.6).normalized()
