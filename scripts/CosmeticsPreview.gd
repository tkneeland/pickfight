extends Control
## The cosmetics picker's preview render (#441): a player square in its colour
## with its eyes and hat, drawn by the game's own `PlayerFace.gd` and `Hat.gd`
## so the preview is exactly what the body shows. Scaled to fit this Control.
## Used by both picker layouts (`PadPickerCard.gd`, `OnlineCosmeticsPanel.gd`).
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const HatScript := preload("res://scripts/Hat.gd")
const PlayerFaceScript := preload("res://scripts/PlayerFace.gd")

## The tallest hat above the body's top edge, and the body's half side.
const HEADROOM: float = 41.0
const HALF: float = 24.0
const OUTLINE_PX: float = 4.0
const INK: Color = Color("14181D")

var color: Color = Color.WHITE
var hat_id: String = HatScript.NONE
var eyes_id: String = PlayerFaceScript.EYE_ROUND

var _figure: Node2D
var _body: Polygon2D
var _face: Node2D
var _hat: Node2D

func _init() -> void:
	name = "Preview"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_figure = Node2D.new()
	_figure.name = "Figure"
	add_child(_figure)
	_body = Polygon2D.new()
	_body.polygon = PackedVector2Array([Vector2(-HALF, -HALF), Vector2(HALF, -HALF), Vector2(HALF, HALF), Vector2(-HALF, HALF)])
	_figure.add_child(_body)
	# The ink outline the lobby cards and the Your look popup draw round the square (#547).
	var outline := Line2D.new()
	outline.name = "Outline"
	outline.points = _body.polygon
	outline.closed = true
	outline.width = OUTLINE_PX
	outline.default_color = INK
	outline.joint_mode = Line2D.LINE_JOINT_SHARP
	_figure.add_child(outline)
	_face = PlayerFaceScript.new()
	_figure.add_child(_face)
	_hat = HatScript.new()
	_hat.position = Vector2(0, -HALF)
	_figure.add_child(_hat)
	resized.connect(_fit)

func _ready() -> void:
	_fit()
	_apply()

## Show colour `colour`, hat `hat` and eye style `eyes`.
func set_look(colour: Color, hat: String, eyes: String) -> void:
	color = colour
	hat_id = hat
	eyes_id = eyes
	_apply()

func _apply() -> void:
	_body.color = color
	_hat.set_hat(hat_id)
	_hat.set_tint(color)
	_face.set_eyes(eyes_id)

func _fit() -> void:
	# The ink outline (half of it outside the body) needs room too (#547).
	var tall: float = HEADROOM + HALF * 2.0 + OUTLINE_PX
	var s: float = minf(size.x / (HatScript.HALF_WIDTH * 2.0), size.y / tall)
	if s <= 0.0:
		s = 1.0
	_figure.scale = Vector2(s, s)
	_figure.position = Vector2(size.x * 0.5, (size.y - tall * s) * 0.5 + (HEADROOM + HALF + OUTLINE_PX * 0.5) * s)
