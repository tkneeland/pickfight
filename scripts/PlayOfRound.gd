extends CanvasLayer
## Play of the round (#704): after a round, the best KO replayed in slow motion
## from the F9 replay buffer (#502), with the killer's name. It plays only inside
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
const CAPTURE_FPS: int = 12

signal finished

var _rect: TextureRect
var _caption: Label
var _textures: Array[Texture2D] = []
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

## Which buffered frames to show: `{start, count}`. `total` frames are held, the
## newest is `now`; the KO happened `now_msec - ko_msec` ago; `remaining_msec` is
## what is left of the round-end pause. count 0 = play nothing. The count is
## trimmed (from the start of the clip) so its slow-motion running time fits in
## the pause minus a margin.
static func select_frames(total: int, now_msec: int, ko_msec: int, remaining_msec: int) -> Dictionary:
	var none := {"start": 0, "count": 0}
	if total <= 0:
		return none
	var end_age_msec: int = maxi(0, now_msec - (ko_msec + TAIL_MSEC))
	var end_index: int = total - 1 - int(end_age_msec * CAPTURE_FPS / 1000.0)
	if end_index < 0:
		return none
	var count: int = mini(int(CLIP_SEC * CAPTURE_FPS), end_index + 1)
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
	_textures.clear()
	for img: Image in frames:
		_textures.append(ImageTexture.create_from_image(img))
	_caption.text = caption
	_rect.texture = _textures[0]
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
	_textures.clear()
	_rect.texture = null
	finished.emit()

func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	var index: int = int(_elapsed * CAPTURE_FPS * SLOW_FACTOR)
	if index >= _textures.size():
		dismiss()
		return
	_rect.texture = _textures[index]
