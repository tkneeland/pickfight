extends Control
## An open seat in the lobby's grid (#547): a dashed outline, "Open seat" and one
## line saying how to take it ("Scan QR or press A"). The hint never wraps: it
## is one line at every resolution, and the label is as wide as the line needs.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")

const DASH_COLOR: Color = Color("5A628C")
const TEXT_COLOR: Color = Color("8F96BD")
const RADIUS: float = 20.0
const LINE_PX: float = 4.0
const DASH_PX: float = 12.0

var _title: Label
var _hint: Label

func _init() -> void:
	name = "OpenSeat"
	custom_minimum_size = Vector2(150, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	_title = ScreenKitScript.themed_label(tr("LOBBY_OPEN_SEAT"), 28, UiThemeScript.HEADING_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_title.name = "Title"
	_title.add_theme_color_override("font_color", TEXT_COLOR)
	box.add_child(_title)
	_hint = ScreenKitScript.themed_label("", 16, &"", HORIZONTAL_ALIGNMENT_CENTER)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hint.add_theme_color_override("font_color", TEXT_COLOR)
	box.add_child(_hint)

func _get_minimum_size() -> Vector2:
	return Vector2(0, 0)

## The one-line hint under "Open seat".
func set_hint(text: String) -> void:
	_hint.text = text

func hint_label() -> Label:
	return _hint

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-LINE_PX * 0.5)
	var rad: float = RADIUS
	var w: float = LINE_PX
	# The four sides dashed, the four corners as arcs.
	draw_dashed_line(Vector2(r.position.x + rad, r.position.y), Vector2(r.end.x - rad, r.position.y), DASH_COLOR, w, DASH_PX)
	draw_dashed_line(Vector2(r.position.x + rad, r.end.y), Vector2(r.end.x - rad, r.end.y), DASH_COLOR, w, DASH_PX)
	draw_dashed_line(Vector2(r.position.x, r.position.y + rad), Vector2(r.position.x, r.end.y - rad), DASH_COLOR, w, DASH_PX)
	draw_dashed_line(Vector2(r.end.x, r.position.y + rad), Vector2(r.end.x, r.end.y - rad), DASH_COLOR, w, DASH_PX)
	draw_arc(Vector2(r.position.x + rad, r.position.y + rad), rad, PI, PI * 1.5, 10, DASH_COLOR, w)
	draw_arc(Vector2(r.end.x - rad, r.position.y + rad), rad, PI * 1.5, TAU, 10, DASH_COLOR, w)
	draw_arc(Vector2(r.end.x - rad, r.end.y - rad), rad, 0.0, PI * 0.5, 10, DASH_COLOR, w)
	draw_arc(Vector2(r.position.x + rad, r.end.y - rad), rad, PI * 0.5, PI, 10, DASH_COLOR, w)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
