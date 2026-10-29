extends CanvasLayer
## Play of the round (#704): after a round, the best KO replayed in slow motion
## from the replay buffer's own sharp ring (640x360 at 24 fps, #1128), with the killer's name. It plays only inside
## the existing round-end pause and never changes its length: `RoundManager`
## owns the deadline, trims the clip to the time left (`select_frames`) and
## dismisses the panel the tick the pause ends. This node only picks and shows.

## Kinds of KO, best last. A multi-KO beats a hazard KO beats a ranged KO.
const TIER_PLAIN: int = 1
const TIER_RANGED: int = 2
const TIER_HAZARD: int = 3
const TIER_MULTI: int = 4
## Same killer, KOs this close together (game msec) make a multi-KO.
const MULTI_WINDOW_MSEC: int = 3000
## Killer and victim this far apart (px) at the KO count as a long-range hit.
const RANGED_DISTANCE_PX: float = 600.0
## The clip: ~4 s of play ending half a second after the KO, shown at half speed.
const CLIP_SEC: float = 4.0
const TAIL_MSEC: int = 500
const SLOW_FACTOR: float = 0.5
## Less than this much slow-motion to show and nothing plays.
const MIN_PLAY_SEC: float = 1.5
## Kept free at the end of the pause, so the clip is gone before it is.
const END_MARGIN_MSEC: int = 250
const ReplayBufferScript := preload("res://scripts/ReplayBuffer.gd")
## The sharp ring's capture rate: the clip's frames are its frames.
const CAPTURE_FPS: int = ReplayBufferScript.HI_FPS

signal finished

var _rect: TextureRect
var _caption: Label
## The clip's frames, and the one texture they are shown through: uploading a
## texture per frame up front cost dozens of GPU uploads in one frame.
var _frames: Array[Image] = []
var _texture: ImageTexture = null
var _shown: int = -1
var _elapsed: float = 0.0
var _playing: bool = false

## The best KO in `kos` (each `{t, killer, victim, hazard, ranged}`; `t` is game
## msec), or {} with none. Multi-KO > hazard > ranged > plain; more KOs in the
## streak next; then the latest.
static func best_moment(kos: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_key: Array = []
	for ko: Dictionary in kos:
		var streak: int = 0
		for other: Dictionary in kos:
			if other["killer"] == ko["killer"] and other["t"] <= ko["t"] and ko["t"] - other["t"] <= MULTI_WINDOW_MSEC:
				streak += 1
		var tier: int = TIER_PLAIN
		if streak >= 2:
			tier = TIER_MULTI
		elif ko.get("hazard", false):
			tier = TIER_HAZARD
		elif ko.get("ranged", false):
			tier = TIER_RANGED
		var key: Array = [tier, streak, ko["t"]]
		if best.is_empty() or _key_greater(key, best_key):
			best = ko
			best_key = key
	return best

static func _key_greater(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] > b[i]
	return false

## A grab gap longer than this (host paused, window minimised) is a hole in the
## ring: nothing from before it is ever shown, and a ring that stopped feeding
## before the KO skips cleanly (#1141).
const MAX_GAP_MSEC := 1000

## Which buffered frames to show: `{start, count}`. `stamps` is when each held
## frame was grabbed (`ReplayBuffer.hi_timestamps()`, oldest first, same clock as
## `now_msec`); the KO happened at `ko_msec`; `remaining_msec` is what is left of
## the round-end pause. count 0 = play nothing. Chosen by time, not by index, so
## a host rendering below 24 fps (or hitching, or skipping grabs) still ends the
## clip `TAIL_MSEC` after the KO (#1139). The count is trimmed (from the start of
## the clip) so its slow-motion running time fits in the pause minus a margin.
static func select_frames(stamps: PackedInt64Array, now_msec: int, ko_msec: int, remaining_msec: int) -> Dictionary:
	var none := {"start": 0, "count": 0}
	var total: int = stamps.size()
	if total <= 0:
		return none
	var end_t: int = mini(ko_msec + TAIL_MSEC, now_msec)
	var end_index: int = -1
	for i in range(total - 1, -1, -1):
		if stamps[i] <= end_t:
			end_index = i
			break
	if end_index < 0 or end_t - int(stamps[end_index]) > MAX_GAP_MSEC:
		return none
	var from_t: int = int(stamps[end_index]) - int(CLIP_SEC * 1000.0)
	var start: int = end_index
	while start > 0 and stamps[start - 1] > from_t and stamps[start] - stamps[start - 1] <= MAX_GAP_MSEC:
		start -= 1
	var count: int = end_index - start + 1
	var fit: int = int(floor(float(remaining_msec - END_MARGIN_MSEC) / 1000.0 * CAPTURE_FPS * SLOW_FACTOR))
	count = mini(count, fit)
	if float(count) / (CAPTURE_FPS * SLOW_FACTOR) < MIN_PLAY_SEC:
		return none
	return {"start": end_index - count + 1, "count": count}

func _init() -> void:
	layer = 14
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_rect = TextureRect.new()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.anchor_left = 0.15
	_rect.anchor_right = 0.85
	_rect.anchor_top = 0.15
	_rect.anchor_bottom = 0.85
	_rect.offset_left = 0
	_rect.offset_right = 0
	_rect.offset_top = 0
	_rect.offset_bottom = 0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_rect)
	_caption = Label.new()
	_caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_caption.anchor_left = 0.0
	_caption.anchor_right = 1.0
	_caption.offset_top = 40
	_caption.offset_bottom = 110
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 44)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

func is_playing() -> bool:
	return _playing

func caption_text() -> String:
	return _caption.text

## Shows `frames` (oldest first) at half speed under `caption`. `punch` adds a
## short scale pop on the picture (skipped when Screen shake is off).
func play(frames: Array, caption: String, punch: bool) -> void:
	if frames.is_empty():
		return
	_frames.clear()
	for img: Image in frames:
		_frames.append(img)
	_caption.text = caption
	_shown = -1
	_show_frame(0)
	_elapsed = 0.0
	_playing = true
	visible = true
	if punch:
		_rect.pivot_offset = _rect.size / 2.0
		_rect.scale = Vector2(1.08, 1.08)
		create_tween().tween_property(_rect, "scale", Vector2.ONE, 0.25)
	else:
		_rect.scale = Vector2.ONE

## Hides the panel at once. Safe to call when nothing is playing.
func dismiss() -> void:
	if not _playing:
		return
	_playing = false
	visible = false
	_frames.clear()
	_shown = -1
	_rect.texture = null
	finished.emit()

## Shows `_frames[index]`, uploading it into the one texture only when the
## index changes (a new texture when the size or format differs).
func _show_frame(index: int) -> void:
	if index == _shown:
		return
	_shown = index
	var img: Image = _frames[index]
	if img.get_format() == ReplayBufferScript.HI_FORMAT:
		# The ring packs RGB565 to stay small; one frame at a time back to RGB8.
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_RGB8)
	if _texture != null and _texture.get_size() == Vector2(img.get_size()) \
			and _texture.get_format() == img.get_format() and not img.has_mipmaps():
		_texture.update(img)
	else:
		_texture = ImageTexture.create_from_image(img)
	_rect.texture = _texture

func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	var index: int = int(_elapsed * CAPTURE_FPS * SLOW_FACTOR)
	if index >= _frames.size():
		dismiss()
		return
	_show_frame(index)
