extends Node2D
## One thing the PC client draws from a snapshot (issue #241): a player, a
## projectile or a pickup. A puppet has no physics; RemoteClient moves it every
## frame. Placeholder art, like the rest of the game. No `class_name`:
## consumers preload this by path.

enum Kind { PLAYER, PROJECTILE, PICKUP }

const BODY_RADIUS: float = 24.0
const HEAD_RADIUS: float = 9.0

var kind: int = Kind.PLAYER
var color: Color = Color.WHITE
var label: String = ""
## Player: world offset from the body to the weapon head.
var head_offset: Vector2 = Vector2.ZERO
var body_rotation: float = 0.0
var damage: int = 0
## 0 dead, 1 alive, 2 spawn-protected (SnapshotCapture's STATE_ constants).
var phase: int = 1

func set_pose(position_in: Vector2, rotation_in: float, head_position: Vector2) -> void:
	position = position_in
	body_rotation = rotation_in
	head_offset = head_position - position_in
	queue_redraw()

func _draw() -> void:
	match kind:
		Kind.PLAYER:
			_draw_player()
		Kind.PROJECTILE:
			draw_circle(Vector2.ZERO, 6.0, color)
		Kind.PICKUP:
			var pts := PackedVector2Array([Vector2(0, -16), Vector2(16, 0), Vector2(0, 16), Vector2(-16, 0)])
			draw_colored_polygon(pts, color)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color.BLACK, 2.0)
			_draw_label(Vector2(0, -22))

func _draw_player() -> void:
	var fade: float = 0.25 if phase == 0 else (0.6 if phase == 2 else 1.0)
	var hurt: float = clampf(float(damage) / 200.0, 0.0, 1.0)
	var fill: Color = color.lerp(Color(0.85, 0.1, 0.1), hurt)
	fill.a = fade
	var outline: Color = color
	outline.a = fade
	if head_offset.length() > 1.0:
		draw_line(Vector2.ZERO, head_offset, outline, 5.0)
		draw_circle(head_offset, HEAD_RADIUS, outline)
	draw_circle(Vector2.ZERO, BODY_RADIUS, fill)
	draw_arc(Vector2.ZERO, BODY_RADIUS, 0.0, TAU, 32, Color(0, 0, 0, fade), 3.0)
	draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(body_rotation) * BODY_RADIUS, Color(0, 0, 0, fade), 3.0)
	if phase == 0:
		draw_line(Vector2(-10, -10), Vector2(10, 10), Color.BLACK, 3.0)
		draw_line(Vector2(-10, 10), Vector2(10, -10), Color.BLACK, 3.0)
	_draw_label(Vector2(0, -BODY_RADIUS - 8))

func _draw_label(at: Vector2) -> void:
	if label.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(font, at + Vector2(-size.x * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
