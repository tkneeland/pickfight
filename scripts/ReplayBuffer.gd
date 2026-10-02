extends Node
## Instant replay (#329, ADR-0020): a bounded ring of downscaled viewport
## frames, written out as a PNG sequence when the host presses F9.
##
## Cost: one viewport grab + downscale every `CAPTURE_INTERVAL_SEC` (12 a
## second), so a few ms spread over 5 frames at 60 fps. Memory is capped at
## `MAX_FRAMES` x `FRAME_SIZE` RGB8, about 13 MB, whatever the match does.

const CAPTURE_FPS: int = 12
const CLIP_SECONDS: int = 10
const MAX_FRAMES: int = CAPTURE_FPS * CLIP_SECONDS
const FRAME_SIZE := Vector2i(256, 144)
const CLIPS_DIR := "user://clips"
const TOAST_SEC: float = 3.0

signal clip_saved(path: String)

var _frames: Array[Image] = []
var _accum: float = 0.0
var _toast: Label
var _toast_timer: Timer
## Where clips go; scenarios point it at a scratch directory.
var clips_dir: String = CLIPS_DIR

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	_toast = Label.new()
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.position = Vector2(16, 16)
	_toast.add_theme_font_size_override("font_size", 20)
	layer.add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func() -> void: _toast.visible = false)
	add_child(_toast_timer)

func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_accum += delta
	if _accum < 1.0 / CAPTURE_FPS:
		return
	_accum = 0.0
	var tex := get_viewport().get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img != null:
		push_frame(img)

## Add a frame, shrinking it to FRAME_SIZE, dropping the oldest past the cap.
func push_frame(img: Image) -> void:
	if img == null or img.is_empty():
		return
	var small: Image = img.duplicate()
	small.convert(Image.FORMAT_RGB8)
	if small.get_size() != FRAME_SIZE:
		small.resize(FRAME_SIZE.x, FRAME_SIZE.y, Image.INTERPOLATE_BILINEAR)
	_frames.append(small)
	while _frames.size() > MAX_FRAMES:
		_frames.pop_front()

func frame_count() -> int:
	return _frames.size()

## Worst-case bytes held by the ring.
static func memory_cap_bytes() -> int:
	return MAX_FRAMES * FRAME_SIZE.x * FRAME_SIZE.y * 3

## Write the buffered frames to `<clips_dir>/clip_<stamp>/frame_NNNN.png`,
## oldest first. Returns the directory, or "" if there was nothing to save.
func save_clip(stamp: String = "") -> String:
	if _frames.is_empty():
		return ""
	if stamp.is_empty():
		stamp = Time.get_datetime_string_from_system().replace(":", "-")
	var dir := "%s/clip_%s" % [clips_dir, stamp]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for i in _frames.size():
		_frames[i].save_png("%s/frame_%04d.png" % [dir, i])
	clip_saved.emit(dir)
	return dir

## Save and show a toast with the path (the F9 handler).
func save_and_toast() -> String:
	var dir := save_clip()
	var shown := tr("REPLAY_NOTHING")
	if not dir.is_empty():
		shown = tr("REPLAY_SAVED") % ProjectSettings.globalize_path(dir)
	_toast.text = shown
	_toast.visible = true
	_toast_timer.start(TOAST_SEC)
	return dir

func toast_text() -> String:
	return _toast.text if _toast != null and _toast.visible else ""
