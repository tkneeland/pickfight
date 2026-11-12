extends StaticBody2D

## Edge catch stage part (`scenes/parts/EdgeCatch.tscn`, #1202): the ledge and
## the end post a stage with an open floor end carries, as ONE body so every
## stage that needs them places one node per end instead of copying a shelf
## and a post (the block four stages had written out by hand).
##
## The node sits at the floor's END corner (x of the last floor edge, y of the
## floor top) and `side` says which way the sky is (-1 left, +1 right). Two
## boxes hang off it:
##  - the ledge: `ledge_width` wide going outward, its top `ledge_drop` px
##    under the floor top, 16 px thick, so a fighter who walks or is knocked
##    just off the end lands on it and climbs back;
##  - the post: 16 px wide at the ledge's outer end, `post_height` px above the
##    floor top, so a fighter who runs along the ledge stops instead of leaving
##    the screen. A launch or a hard shove at spawn height still clears a low
##    post, which keeps the ring-out.
## The whole part has to sit inside the view (x within the 1600 px width, ledge
## top a body radius above the bottom edge); the `stage_safety_ledges_on_screen_1202`
## scenario checks it from the exported values.
##
## Same children shape as `Platform`: a `CollisionShape2D` + `Polygon2D` per
## box, named `<Name>Ledge...` / `<Name>Post...`, built in `_init()` and kept in
## step by the setters, and it takes the stage mood's platform colour.

const THICKNESS: float = 16.0
const POST_WIDTH: float = 16.0

## -1: the sky is to the left of the node; +1: to the right.
@export_enum("Left:-1", "Right:1") var side: int = 1:
	set(value):
		side = value
		_rebuild()
## How far the ledge reaches out from the floor end.
@export var ledge_width: float = 80.0:
	set(value):
		ledge_width = value
		_rebuild()
## How far the ledge's top sits under the floor top.
@export var ledge_drop: float = 40.0:
	set(value):
		ledge_drop = value
		_rebuild()
## How far the post's top rises over the floor top.
@export var post_height: float = 30.0:
	set(value):
		post_height = value
		_rebuild()
@export var color: Color = Color(0.35, 0.35, 0.4, 1):
	set(value):
		color = value
		for visual: Polygon2D in _visuals:
			visual.color = color

var _shapes: Array[CollisionShape2D] = []
var _visuals: Array[Polygon2D] = []

func _init() -> void:
	for _i in 2:
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		add_child(shape)
		_shapes.append(shape)
		var visual := Polygon2D.new()
		visual.color = color
		add_child(visual)
		_visuals.append(visual)
	_name_children()
	_rebuild()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_PATH_RENAMED:
		_name_children()

func set_platform_color(value: Color) -> void:
	color = value

## The two boxes as local rects: [ledge, post].
func boxes() -> Array[Rect2]:
	var dir: float = float(side)
	var ledge_x0: float = 0.0 if dir > 0.0 else -ledge_width
	var post_x0: float = (ledge_width - POST_WIDTH) if dir > 0.0 else -ledge_width
	return [
		Rect2(ledge_x0, ledge_drop, ledge_width, THICKNESS),
		Rect2(post_x0, -post_height, POST_WIDTH, post_height + ledge_drop + THICKNESS),
	]

func _rebuild() -> void:
	if _shapes.is_empty():
		return
	var rects: Array[Rect2] = boxes()
	for i in 2:
		var r: Rect2 = rects[i]
		(_shapes[i].shape as RectangleShape2D).size = r.size
		_shapes[i].position = r.get_center()
		_visuals[i].polygon = PackedVector2Array([
			r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])

func _name_children() -> void:
	if _shapes.is_empty():
		return
	var names: Array[String] = ["Ledge", "Post"]
	for i in 2:
		_shapes[i].name = String(name) + names[i] + "Shape"
		_visuals[i].name = String(name) + names[i] + "Visual"
