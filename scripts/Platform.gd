extends StaticBody2D

## Plain platform stage part (`scenes/parts/Platform.tscn`): a solid box of
## ordinary terrain, the `StaticBody2D` + `CollisionShape2D` + `Polygon2D`
## every stage used to write out by hand (ADR-0008). `size` is the one source
## of truth: the collision rectangle and the visual's four corners are both
## built from it, so the two can never disagree.
##
## **Same nodes as a hand-written platform.** The body stays a `StaticBody2D`
## on the default world layer (override `collision_layer`/`collision_mask` on
## the instance where a stage needs to), and its two children are named after
## it -- `<Name>Shape` and `<Name>Visual` -- exactly as the stages named them,
## so lookups by name, `find_child("*Visual")`, snapshot capture and bot
## footing rays all see the same tree. The children are built in `_init()`
## and kept in step by the setters, so they exist as soon as the stage is
## instanced, before it enters the tree.
##
## **Tinting.** `Stage._tint_bodies` gives every part with a
## `set_platform_color()` the stage mood's platform colour; this is that
## method, so a platform is tinted exactly as the hand-written ones are.

## The collision box and the visual, centred on the node.
@export var size: Vector2 = Vector2(240, 24):
	set(value):
		size = value
		_rebuild()

## The visual's fill before `Stage` applies its mood: the grey-blue every
## stage draws its terrain in.
@export var color: Color = Color(0.35, 0.35, 0.4, 1):
	set(value):
		color = value
		if _visual != null:
			_visual.color = color

## Whether the collision box only blocks from above, like a drop-through
## ledge (`CollisionShape2D.one_way_collision`).
@export var one_way: bool = false:
	set(value):
		one_way = value
		if _shape != null:
			_shape.one_way_collision = one_way

var _shape: CollisionShape2D
var _visual: Polygon2D

func _init() -> void:
	_shape = CollisionShape2D.new()
	_shape.shape = RectangleShape2D.new()
	_shape.one_way_collision = one_way
	add_child(_shape)
	_visual = Polygon2D.new()
	_visual.color = color
	add_child(_visual)
	_name_children()
	_rebuild()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_PATH_RENAMED:
		_name_children()

## Takes the stage mood's platform colour, as `Stage._tint_bodies` hands it to
## every part that has this method.
func set_platform_color(value: Color) -> void:
	color = value

## The collision rectangle's size, read back off the shape.
func shape_size() -> Vector2:
	return (_shape.shape as RectangleShape2D).size

func _rebuild() -> void:
	if _shape == null:
		return
	(_shape.shape as RectangleShape2D).size = size
	var half: Vector2 = size / 2.0
	_visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])

func _name_children() -> void:
	if _shape == null:
		return
	_shape.name = String(name) + "Shape"
	_visual.name = String(name) + "Visual"
