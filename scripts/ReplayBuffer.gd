extends Node
## Instant replay (#329, ADR-0020): a bounded ring of downscaled viewport
## frames, written out as a PNG sequence plus an animated GIF (#502) when the
## host presses F9. The GIF is encoded on a worker thread.
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

const GifWriterType := preload("res://scripts/GifWriter.gd")
## 12 fps in hundredths of a second (8 cs, a GIF delay unit).
const GIF_DELAY_CS: int = 8

signal clip_saved(path: String)
## The worker finished: the GIF's path, or "" if it could not be written.
signal gif_saved(path: String)

var _frames: Array[Image] = []
var _accum: float = 0.0
var _toast: Label
var _toast_timer: Timer
## Where clips go; scenarios point it at a scratch directory.
var clips_dir: String = CLIPS_DIR
## F9 also encodes clip.gif; scenarios that only count PNGs turn it off.
var encode_gif: bool = true
var _gif_thread: Thread
var _gif_dir: String = ""

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

## Encode the buffered frames to `<dir>/clip.gif` on a worker thread;
## `gif_saved` fires on the main thread when it is done. Returns false if a
## previous encode is still running or there is nothing to encode.
func start_gif(dir: String) -> bool:
	if _frames.is_empty() or (_gif_thread != null and _gif_thread.is_alive()):
		return false
	if _gif_thread != null:
		_gif_thread.wait_to_finish()
	_gif_dir = dir
	var copy: Array = _frames.duplicate()
	var path := ProjectSettings.globalize_path(dir + "/clip.gif")
	_gif_thread = Thread.new()
	_gif_thread.start(_encode_gif.bind(copy, path))
	return true

func _encode_gif(frames: Array, path: String) -> void:
	var bytes: PackedByteArray = GifWriterType.encode(frames, GIF_DELAY_CS)
	var f := FileAccess.open(path, FileAccess.WRITE)
	var ok := f != null
	if ok:
		f.store_buffer(bytes)
		f.close()
	_gif_done.call_deferred(path if ok else "")

func _gif_done(path: String) -> void:
	if _gif_thread != null:
		_gif_thread.wait_to_finish()
		_gif_thread = null
	if not path.is_empty() and _toast != null:
		_toast.text = tr("REPLAY_GIF_SAVED") % path
		_toast.visible = true
		_toast_timer.start(TOAST_SEC)
	gif_saved.emit(path)

func _exit_tree() -> void:
	if _gif_thread != null:
		_gif_thread.wait_to_finish()
		_gif_thread = null

## Save and show a toast with the path (the F9 handler).
func save_and_toast() -> String:
	var dir := save_clip()
	var shown := tr("REPLAY_NOTHING")
	if not dir.is_empty():
		shown = tr("REPLAY_SAVED") % ProjectSettings.globalize_path(dir)
		if encode_gif and start_gif(dir):
			shown = tr("REPLAY_GIF_ENCODING") % ProjectSettings.globalize_path(dir + "/clip.gif")
	_toast.text = shown
	_toast.visible = true
	_toast_timer.start(TOAST_SEC)
	return dir

func toast_text() -> String:
	return _toast.text if _toast != null and _toast.visible else ""
