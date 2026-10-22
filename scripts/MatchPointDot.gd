extends Control

## The small gold dot on a match-point fighter's name tag (issue #825). A child
## of the tag's label, drawn beside its right edge, it frees itself when the
## round ends (the round manager leaves the playing phase or starts another).
## Built by `MatchPointPlate.gd`. Preloaded by path, never by `class_name`.

const GOLD: Color = Color("F2B705")
const INK: Color = Color("14181D")
const RADIUS: float = 7.0

var round_manager: Node = null
var round_number: int = 0

func _ready() -> void:
	add_to_group(&"match_point_dots")
	name = "MatchPointDot"
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if round_manager == null or not is_instance_valid(round_manager) \
			or round_manager.lobby_phase() != "playing" \
			or int(round_manager.get("_round_number")) != round_number:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var parent: Control = get_parent() as Control
	var size_hint: Vector2 = parent.size if parent != null else Vector2.ZERO
	var at := Vector2(size_hint.x + RADIUS + 2.0, size_hint.y * 0.5)
	draw_circle(at, RADIUS + 2.0, INK)
	draw_circle(at, RADIUS, GOLD)
