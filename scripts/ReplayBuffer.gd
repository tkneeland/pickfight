extends Node
## Instant replay (#329, ADR-0020): a bounded ring of downscaled viewport
## frames, written out as a PNG sequence plus an animated GIF (#502) when the
## host presses F9. The GIF is encoded on a worker thread.
##
## Cost: one viewport grab every 1/`HI_FPS` s (24 a second); every second grab
## is also shrunk into the F9 ring. Memory is capped at `MAX_FRAMES` x
## `FRAME_SIZE` RGB8, about 13 MB, whatever the match does.
##
## Play of the round (#1128, ADR-0020 addendum) reads a second, separate ring:
## the last `HI_SECONDS` s fitted inside `HI_SIZE` at `HI_FPS`, kept as RGB565 (2 bytes a
## pixel), `hi_memory_cap_bytes()` = 55.3 MB at most. Its resize and conversion
## run on the worker thread pool so the main thread only pays for the grab. The
## F9 ring, its PNGs and clip.gif are untouched.

const CAPTURE_FPS: int = 12
## The Play of the round ring (#1128): sharp enough for a full-screen replay.
const HI_FPS: int = 24
const HI_SECONDS: int = 5
const HI_MAX_FRAMES: int = HI_FPS * HI_SECONDS
## The largest Play of the round frame (#1137): a bigger or differently shaped
## window shrinks to fit inside it, keeping its aspect, so a frame never holds
## more pixels than 640x360 (the ADR-0020 byte cap) and is never squashed.
const HI_SIZE := Vector2i(640, 360)
const HI_FORMAT := Image.FORMAT_RGB565
## Resize jobs allowed in flight (#1138). Past this a grab is skipped, never
## waited for, so the main thread does not stall and at most this many
## window-sized sources are alive.
const HI_MAX_PENDING: int = 2
const CLIP_SECONDS: int = 10
const MAX_FRAMES: int = CAPTURE_FPS * CLIP_SECONDS
const FRAME_SIZE := Vector2i(256, 144)
const CLIPS_DIR := "user://clips"
const TOAST_SEC: float = 3.0

const HostSettingsScript := preload("res://scripts/HostSettings.gd")
const GifWriterType := preload("res://scripts/GifWriter.gd")
## 12 fps in hundredths of a second (8 cs, a GIF delay unit).
const GIF_DELAY_CS: int = 8

signal clip_saved(path: String)
## The worker finished: the GIF's path, or "" if it could not be written.
signal gif_saved(path: String)

var _frames: Array[Image] = []
## The Play of the round ring, oldest first: `{img, msec, task}`. `img` is null
## until the pool job `task` (-1 once collected) has filled it.
var _hi: Array[Dictionary] = []
var _grabs: int = 0
var _accum: float = 0.0
var _toast: Label
var _toast_timer: Timer
## Where clips go; scenarios point it at a scratch directory.
var clips_dir: String = CLIPS_DIR
## F9 also encodes clip.gif; scenarios that only count PNGs turn it off.
var encode_gif: bool = true
## The folder the last match-end auto-save wrote, or "" (#795); the victory
## screen shows its "Clip saved" line while this is set.
var autosaved_dir: String = ""
var _gif_thread: Thread
var _gif_dir: String = ""

func _ready() -> void:
	add_to_group("replay_buffer")
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
	if not capture_due(delta):
		return
	_grabs += 1
	var f9_due: bool = _grabs % (HI_FPS / CAPTURE_FPS) == 0
	if not f9_due and not _hi_has_room():
		return # the pool is behind: skip the grab itself (#1138)
	var tex := get_viewport().get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		return
	if f9_due:
		# The F9 ring: shrunk in place on the main thread, so the pool job
		# gets its own copy.
		_keep_hi_async(img.duplicate() as Image)
		_keep_frame(img)
	else:
		_keep_hi_async(img)

## Whether a grab is due after `delta` more seconds (`HI_FPS` a second). The
## time past the interval carries over (at most one interval of it, so a long
## hitch does not bunch captures), or a 50 fps host would grab only 20 a second.
func capture_due(delta: float) -> bool:
	var interval: float = 1.0 / HI_FPS
	_accum += delta
	if _accum < interval:
		return false
	_accum = minf(_accum - interval, interval)
	return true

## Add a frame, shrinking it to FRAME_SIZE, dropping the oldest past the cap.
func push_frame(img: Image) -> void:
	if img == null or img.is_empty():
		return
	_keep_frame(img.duplicate() as Image)
	_keep_hi_now(img)

## `push_frame` on an image nobody else holds: shrunk first, so the format
## conversion only touches FRAME_SIZE pixels.
func _keep_frame(small: Image) -> void:
	if small.get_size() != FRAME_SIZE:
		small.resize(FRAME_SIZE.x, FRAME_SIZE.y, Image.INTERPOLATE_BILINEAR)
	small.convert(Image.FORMAT_RGB8)
	_frames.append(small)
	while _frames.size() > MAX_FRAMES:
		_frames.pop_front()

## Whether the pool can take another source frame (#1138): finished jobs are
## collected (no waiting), and fewer than `HI_MAX_PENDING` may still be running.
func _hi_has_room() -> bool:
	var running: int = 0
	for h: Dictionary in _hi:
		var task: int = int(h["task"])
		if task < 0:
			continue
		if WorkerThreadPool.is_task_completed(task):
			_collect(h)
		else:
			running += 1
	return running < HI_MAX_PENDING

## `img` into the Play of the round ring on the pool: shrunk to fit `HI_SIZE`
## and packed to RGB565 off the main thread. Takes ownership of `img`. When the
## pool is already at `HI_MAX_PENDING` the grab is dropped (returns false): the
## main thread never waits, and the gap shows in `hi_timestamps()`.
func _keep_hi_async(img: Image) -> bool:
	if not _hi_has_room():
		return false
	var box: Array = [null]
	var slot := {"img": null, "box": box, "msec": Time.get_ticks_msec(), "task": -1}
	_hi.append(slot)
	slot["task"] = WorkerThreadPool.add_task(_pack_hi.bind(img, box))
	_trim_hi()
	return true

## The same, inline (scenarios and tools feeding synthetic frames).
func _keep_hi_now(img: Image) -> void:
	var copy: Image = img.duplicate() as Image
	var box: Array = [null]
	_pack_hi(copy, box)
	_hi.append({"img": box[0], "box": box, "msec": Time.get_ticks_msec(), "task": -1})
	_trim_hi()

func _trim_hi() -> void:
	while _hi.size() > HI_MAX_FRAMES:
		_collect(_hi.pop_front())

## The Play of the round frame size for a `src`-sized window (#1137): the
## window shrunk to fit inside `HI_SIZE`, aspect kept; never enlarged.
static func hi_size_for(src: Vector2i) -> Vector2i:
	if src.x <= HI_SIZE.x and src.y <= HI_SIZE.y:
		return src
	var k: float = minf(float(HI_SIZE.x) / src.x, float(HI_SIZE.y) / src.y)
	return Vector2i(clampi(roundi(src.x * k), 1, HI_SIZE.x), clampi(roundi(src.y * k), 1, HI_SIZE.y))

## Runs on a pool thread: only touches `img` and its own result `box`.
func _pack_hi(img: Image, box: Array) -> void:
	# Bigger frames shrink to fit HI_SIZE; smaller ones (synthetic) stay as they
	# are, so the ring never holds more than HI_SIZE per frame.
	var want: Vector2i = hi_size_for(img.get_size())
	if want != img.get_size():
		img.resize(want.x, want.y, Image.INTERPOLATE_BILINEAR)
	img.convert(HI_FORMAT)
	box[0] = img

## Wait for a slot's job (once).
func _collect(slot: Dictionary) -> void:
	var task: int = int(slot["task"])
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)
		slot["task"] = -1
		slot["img"] = (slot["box"] as Array)[0]

func _collect_all() -> void:
	for h: Dictionary in _hi:
		_collect(h)

## Frames held for the Play of the round, at `HI_FPS` (#1128).
func hi_frame_count() -> int:
	return _hi.size()

## A copy of the Play of the round frames `start` .. `start + count - 1`, oldest
## first. They are RGB565; PlayOfRound converts each as it shows it.
func hi_frames_slice(start: int, count: int) -> Array[Image]:
	_collect_all()
	var out: Array[Image] = []
	for i in range(maxi(start, 0), mini(start + count, _hi.size())):
		out.append(_hi[i]["img"])
	return out

## When (msec, `Time.get_ticks_msec`) each Play of the round frame was grabbed.
func hi_timestamps() -> PackedInt64Array:
	var out := PackedInt64Array()
	for h: Dictionary in _hi:
		out.append(int(h["msec"]))
	return out

## Size of the newest Play of the round frame, or (0, 0).
func hi_frame_size() -> Vector2i:
	if _hi.is_empty():
		return Vector2i.ZERO
	_collect(_hi[_hi.size() - 1])
	return (_hi[_hi.size() - 1]["img"] as Image).get_size()

## Worst-case bytes held by the Play of the round ring.
static func hi_memory_cap_bytes() -> int:
	return HI_MAX_FRAMES * HI_SIZE.x * HI_SIZE.y * 2

## Bytes the Play of the round ring holds right now.
func hi_memory_bytes() -> int:
	_collect_all()
	var total: int = 0
	for h: Dictionary in _hi:
		total += (h["img"] as Image).get_data().size()
	return total

func frame_count() -> int:
	return _frames.size()

## A copy of buffered frames `start` .. `start + count - 1`, oldest first (#704).
func frames_slice(start: int, count: int) -> Array[Image]:
	var out: Array[Image] = []
	for i in range(maxi(start, 0), mini(start + count, _frames.size())):
		out.append(_frames[i])
	return out

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
	prune_clips(clips_dir)
	clip_saved.emit(dir)
	return dir

## Keep the newest `keep` `clip_*` folders in `dir` and delete the rest (#609).
## Stamps sort by time, so the name order is the age order.
static func prune_clips(dir: String, keep: int = 20) -> void:
	var da := DirAccess.open(ProjectSettings.globalize_path(dir))
	if da == null:
		return
	var names: Array[String] = []
	for n: String in da.get_directories():
		if n.begins_with("clip_"):
			names.append(n)
	names.sort()
	for i in maxi(names.size() - keep, 0):
		var old := ProjectSettings.globalize_path(dir).path_join(names[i])
		var sub := DirAccess.open(old)
		if sub != null:
			for f: String in sub.get_files():
				sub.remove(f)
		DirAccess.remove_absolute(old)

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

func _notification(what: int) -> void:
	# A buffer freed outside the tree never gets _exit_tree; its pool jobs
	# must still finish before their boxes go (#1138).
	if what == NOTIFICATION_PREDELETE:
		_collect_all()

func _exit_tree() -> void:
	_collect_all()
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

## The match-winning KO is over: save the buffer like F9 (#795), unless the
## host turned it off or nothing is buffered. Quiet: the victory screen says so.
func autosave_match_clip() -> String:
	autosaved_dir = ""
	if not HostSettingsScript.shared().auto_save_clips or _frames.is_empty():
		return ""
	autosaved_dir = save_clip()
	if not autosaved_dir.is_empty() and encode_gif:
		start_gif(autosaved_dir)
	return autosaved_dir

func toast_text() -> String:
	return _toast.text if _toast != null and _toast.visible else ""
