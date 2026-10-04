extends Control
## The deep indigo ground with faint diagonal stripes behind the lobby (#547,
## #507 decision 1). One draw, no children. Preloaded by path, never by
## `class_name`.

const BASE: Color = Color("232A4A")
const STRIPE: Color = Color(1, 1, 1, 0.035)
## Stripe width and period along the 135 degree gradient (28 / 56 px in the mockup).
const BAND_PX: float = 28.0
const PERIOD_PX: float = 56.0

func _init() -> void:
	name = "Ground"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BASE)
	var band: float = BAND_PX * sqrt(2.0)
	var period: float = PERIOD_PX * sqrt(2.0)
	var h: float = size.y
	var c: float = 0.0
	while c < size.x + h:
		draw_colored_polygon(PackedVector2Array([Vector2(c, 0), Vector2(c + band, 0), Vector2(c + band - h, h), Vector2(c - h, h)]), STRIPE)
		c += period
