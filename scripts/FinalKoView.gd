extends RefCounted

## What the final KO looks like on a screen (#328): the camera zooms in on the
## KO point (with Screen shake on) and a white flash covers the screen (with
## Reduce flashes off). The slow motion is the host's (`Engine.time_scale`,
## RoundManager); this is only the picture, shared by the host and the Online
## joiner (#976), each under its own machine's settings. `end()` puts the
## camera back and drops the flash. Preloaded by path, never by `class_name`.

const ZOOM_FACTOR: float = 1.5
const FLASH_ALPHA: float = 0.45
const FLASH_LAYER: int = 50

var camera: Camera2D = null
var flash: CanvasLayer = null
var _zoom_was: Vector2 = Vector2.ONE
var _pos_was: Vector2 = Vector2.ZERO

## Zooms `cam` (may be null) in on `point` and lays the flash under
## `flash_parent`. Safe to call again: the previous look is ended first.
func start(cam: Camera2D, flash_parent: Node, point: Vector2) -> void:
	end()
	var sfx: Node = flash_parent.get_node_or_null("/root/Sfx") if flash_parent != null and flash_parent.is_inside_tree() else null
	if (sfx == null or bool(sfx.get("screen_shake"))) and cam != null:
		camera = cam
		_zoom_was = cam.zoom
		_pos_was = cam.global_position
		cam.zoom = cam.zoom * ZOOM_FACTOR
		cam.global_position = point
	if (sfx == null or not bool(sfx.get("reduce_flash"))) and flash_parent != null:
		flash = CanvasLayer.new()
		flash.name = "FinalKoFlash"
		flash.layer = FLASH_LAYER
		var rect := ColorRect.new()
		rect.color = Color(1, 1, 1, FLASH_ALPHA)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash.add_child(rect)
		flash_parent.add_child(flash)

## Puts the camera back and drops the flash. Safe to call any time.
func end() -> void:
	if is_instance_valid(camera):
		camera.zoom = _zoom_was
		camera.global_position = _pos_was
		camera.reset_smoothing()
	camera = null
	if is_instance_valid(flash):
		flash.queue_free()
	flash = null

## Whether the look is on (a zoomed camera or a flash).
func active() -> bool:
	return is_instance_valid(camera) or is_instance_valid(flash)
