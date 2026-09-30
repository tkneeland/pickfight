extends RefCounted
## The host PC's captured mouse as a phone-drag vector (issue #239). A phone
## drag is (point - anchor) / radius clamped to the unit disc, with the radius
## a fraction of the short screen edge (controller/index.html: `recompute`,
## `DRAG_RADIUS_FRACTION`, and #244's laptop mouse). Captured mouse motion
## arrives as relative pixels, so they are accumulated into the same offset,
## kept inside the disc so reversing direction is immediate, and divided by the
## same radius. No `class_name`: consumers preload this by path.

## Must match DRAG_RADIUS_FRACTION in controller/index.html.
const DRAG_RADIUS_FRACTION: float = 0.35
## Must match MIN_DRAG_RADIUS_PX in controller/index.html.
const MIN_DRAG_RADIUS_PX: float = 1.0

## Mouse pixels per drag pixel, like the page's sensitivity slider.
var sensitivity: float = 1.0

var _offset: Vector2 = Vector2.ZERO

## The drag radius for a window whose short edge is `edge` pixels.
static func drag_radius(edge: float) -> float:
	var radius: float = DRAG_RADIUS_FRACTION * edge
	if not is_finite(radius) or radius < MIN_DRAG_RADIUS_PX:
		return MIN_DRAG_RADIUS_PX
	return radius

## Adds `relative` (one InputEventMouseMotion.relative) and returns the vector.
func move(relative: Vector2, radius: float) -> Vector2:
	var sens: float = sensitivity if is_finite(sensitivity) and sensitivity > 0.0 else 1.0
	var v: Vector2 = (_offset + relative * sens) / radius
	if v.length() > 1.0:
		v = v.normalized()
	_offset = v * radius
	return v

## Back to the anchor: nothing held.
func reset() -> void:
	_offset = Vector2.ZERO
