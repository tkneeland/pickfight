extends CanvasLayer

## The host screen's settings menu (issues #75 and #118, ADR-0016, ADR-0017).
## A small "Settings" button in the bottom-right corner opens a panel with
## these controls:
##
## - master, SFX and music volume sliders;
## - a mute box;
## - a fullscreen box.
##
## Keys: `Esc` opens and closes the panel, `M` toggles mute and `F11` toggles
## fullscreen.
##
## It drives `Sfx` (master, SFX, mute, fullscreen) and `Music` (music volume),
## and they remember each choice. This file holds no settings of its own.
##
## `Sfx` builds it once the game's own scene is running, so no scene file has
## to carry it. The bottom-right corner is free: the join text and scores sit
## top-left, the QR code top-right.

const MARGIN: float = 12.0
const SLIDER_WIDTH: float = 180.0

var sfx: Node
## The `Music` autoload, or null. Without it the music slider is hidden.
var music: Node

var _toggle: Button
var _panel: PanelContainer
var _slider: HSlider
var _sfx_slider: HSlider
var _music_slider: HSlider
var _mute: CheckBox
var _fullscreen: CheckBox
## Whether a slider is being dragged. A drag applies every step live and
## saves once, when it ends (issue #167).
var _dragging: bool = false

func _ready() -> void:
	layer = 20
	var corner := VBoxContainer.new()
	corner.name = "Corner"
	corner.anchor_left = 1.0
	corner.anchor_top = 1.0
	corner.anchor_right = 1.0
	corner.anchor_bottom = 1.0
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.offset_left = -MARGIN
	corner.offset_top = -MARGIN
	corner.offset_right = -MARGIN
	corner.offset_bottom = -MARGIN
	corner.alignment = BoxContainer.ALIGNMENT_END
	add_child(corner)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.visible = false
	corner.add_child(_panel)
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	_slider = _add_slider(rows, "Volume", "Master volume")
	_sfx_slider = _add_slider(rows, "SfxVolume", "Sound effects")
	_music_slider = _add_slider(rows, "MusicVolume", "Music")
	if music == null:
		_music_slider.get_parent().visible = false
	_mute = _add_box(rows, "Mute", "Mute (M)")
	_fullscreen = _add_box(rows, "Fullscreen", "Fullscreen (F11)")

	_toggle = Button.new()
	_toggle.name = "Toggle"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	corner.add_child(_toggle)

	refresh()
	_slider.value_changed.connect(_on_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	for slider: HSlider in [_slider, _sfx_slider, _music_slider]:
		slider.drag_started.connect(_on_drag_started)
		slider.drag_ended.connect(_on_drag_ended)
	_mute.toggled.connect(_on_mute_toggled)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_toggle.pressed.connect(toggle_panel)

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_M:
			sfx.toggle_muted()
		KEY_F11:
			sfx.toggle_fullscreen()
		KEY_ESCAPE:
			toggle_panel()
		_:
			return
	refresh()
	get_viewport().set_input_as_handled()

## Show the current settings, without echoing them back. Fullscreen is read
## from the real window first, which the OS may have changed (issue #167).
func refresh() -> void:
	sfx.sync_fullscreen()
	_slider.set_value_no_signal(sfx.master_volume)
	_sfx_slider.set_value_no_signal(sfx.sfx_volume)
	if music != null:
		_music_slider.set_value_no_signal(music.volume)
	_mute.set_pressed_no_signal(sfx.muted)
	_fullscreen.set_pressed_no_signal(sfx.fullscreen)
	_toggle.text = "Settings (muted)" if sfx.muted else "Settings"

func toggle_panel() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		refresh()

func is_open() -> bool:
	return _panel.visible

func volume_slider() -> HSlider:
	return _slider

func sfx_slider() -> HSlider:
	return _sfx_slider

func music_slider() -> HSlider:
	return _music_slider

func mute_box() -> CheckBox:
	return _mute

func fullscreen_box() -> CheckBox:
	return _fullscreen

func _add_slider(rows: VBoxContainer, node_name: String, title: String) -> HSlider:
	var group := VBoxContainer.new()
	group.name = node_name + "Row"
	rows.add_child(group)
	var label := Label.new()
	label.text = title
	group.add_child(label)
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 0.0)
	slider.focus_mode = Control.FOCUS_NONE
	group.add_child(slider)
	return slider

func _add_box(rows: VBoxContainer, node_name: String, title: String) -> CheckBox:
	var box := CheckBox.new()
	box.name = node_name
	box.text = title
	box.focus_mode = Control.FOCUS_NONE
	rows.add_child(box)
	return box

func _on_volume_changed(value: float) -> void:
	sfx.set_master_volume(value, not _dragging)
	refresh()

func _on_sfx_volume_changed(value: float) -> void:
	sfx.set_sfx_volume(value, not _dragging)
	refresh()

func _on_music_volume_changed(value: float) -> void:
	if music != null:
		music.set_volume(value, not _dragging)
	refresh()

func _on_drag_started() -> void:
	_dragging = true

## The drag is over: save what it left, once. `Sfx` and `Music` share the
## file, and each keeps the other's section.
func _on_drag_ended(value_changed: bool) -> void:
	_dragging = false
	if not value_changed:
		return
	sfx.save_settings()
	if music != null:
		music.save_settings()

func _on_mute_toggled(pressed: bool) -> void:
	sfx.set_muted(pressed)
	refresh()

func _on_fullscreen_toggled(pressed: bool) -> void:
	sfx.set_fullscreen(pressed)
	refresh()
