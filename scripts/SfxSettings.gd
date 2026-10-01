extends CanvasLayer

## The host screen's settings menu (issues #75 and #118, ADR-0016, ADR-0017).
## A small "Settings" button in the bottom-right corner opens a panel with
## these controls:
##
## - master, SFX and music volume sliders;
## - a mute box;
## - a fullscreen box;
## - a window size for windowed mode, and scrolling lists of stages and
##   pickup weapons to switch on or off (issue #294, `HostSettings`). The last
##   enabled stage or weapon refuses to switch off.
##
## A voice volume slider (#290) goes in the audio rows above, beside music.
##
## Keys: `Esc` opens and closes the panel, `M` toggles mute and `F11` toggles
## fullscreen.
##
## It drives `Sfx` (master, SFX, mute, fullscreen) and `Music` (music volume),
## and they remember each choice. This file holds no settings of its own.
##
## `Sfx` builds it once the game's own scene is running, so no scene file has
## to carry it. The bottom-right corner is free: the join text and scores sit
## top-left, the QR code top-right, and the lobby's how-to-play column keeps
## clear of the open panel (issue #230, `LobbyScreen.SETTINGS_CORNER_RESERVE_PX`).

const MARGIN: float = 12.0
## The open panel's own opaque backdrop (issue #230), so nothing behind it
## shows through its controls.
const PANEL_BACKGROUND: Color = Color(0.1, 0.11, 0.14, 1.0)
const PANEL_PADDING: float = 6.0
const SLIDER_WIDTH: float = 180.0
const HostSettingsScript := preload("res://scripts/HostSettings.gd")
## Height of the scrolling window-size, stage and weapon area.
const LIST_HEIGHT: float = 130.0

var sfx: Node
## The `Music` autoload, or null. Without it the music slider is hidden.
var music: Node

## The host's resolution, stage and weapon choices (#294).
var host: RefCounted = HostSettingsScript.shared()
var _more: CheckBox
var _more_area: ScrollContainer
var _resolution: OptionButton
var _stage_list: VBoxContainer
var _weapon_list: VBoxContainer
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
## Whether this layer took the left press now held down, which was on the
## toggle, so the matching release is its too (issue #216).
var _took_press: bool = false

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
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = PANEL_BACKGROUND
	backdrop.set_corner_radius_all(6)
	backdrop.set_content_margin_all(PANEL_PADDING)
	_panel.add_theme_stylebox_override("panel", backdrop)
	corner.add_child(_panel)
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	_slider = _add_slider(rows, "Volume", "Master volume")
	_sfx_slider = _add_slider(rows, "SfxVolume", "Sound effects")
	_music_slider = _add_slider(rows, "MusicVolume", "Music")
	if music == null:
		_music_slider.get_parent().visible = false
	# Side by side, to give the new rows below their height (issue #294): the
	# lobby's how-to-play column only has so much room above the panel.
	var toggles := HBoxContainer.new()
	toggles.name = "TogglesRow"
	rows.add_child(toggles)
	_mute = _add_box(toggles, "Mute", "Mute (M)")
	_fullscreen = _add_box(toggles, "Fullscreen", "Full (F11)")
	# One scrolling area for the window size and both lists, so the panel
	# grows by LIST_HEIGHT whatever the stage count (24+).
	_more = CheckBox.new()
	_more.name = "MoreOptions"
	_more.text = "More options"
	_more.focus_mode = Control.FOCUS_NONE
	rows.add_child(_more)
	var scroll := ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.visible = false
	_more_area = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(SLIDER_WIDTH + 24.0, LIST_HEIGHT)
	rows.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_resolution = OptionButton.new()
	_resolution.name = "Resolution"
	for size: Vector2i in HostSettingsScript.RESOLUTIONS:
		_resolution.add_item("Window: default" if size == Vector2i.ZERO else "Window: %d x %d" % [size.x, size.y])
	content.add_child(_resolution)
	_stage_list = _add_list(content, "Stages")
	_weapon_list = _add_list(content, "Weapons")

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
	_resolution.item_selected.connect(_on_resolution_selected)
	_more.toggled.connect(func(pressed: bool) -> void: _more_area.visible = pressed)
	apply_resolution()

## A left click on the toggle is taken here, in `_input`, before the GUI
## routes it (issue #216). The owner saw the button do nothing mid-round in
## solo practice while it worked in the lobby. Whatever stood in the way --
## a Control above it catching the mouse, another Control holding the GUI's
## mouse focus, or a release that never reached the button -- `_input` runs
## ahead of all of it, on every layer, paused or not, and the click toggles
## on the press alone. The press and its release are both marked handled, so
## the Button never sees them and cannot toggle a second time.
func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.pressed:
		if not toggle_hit(click.position):
			return
		_took_press = true
		toggle_panel()
	elif _took_press:
		_took_press = false
	else:
		return
	get_viewport().set_input_as_handled()

## Whether a click at `point` (viewport coordinates, as `_input` gets them)
## lands on the visible toggle.
func toggle_hit(point: Vector2) -> bool:
	if not visible or not _toggle.is_visible_in_tree():
		return false
	return _toggle.get_global_rect().has_point(point)

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
	_resolution.select(maxi(HostSettingsScript.RESOLUTIONS.find(host.resolution), 0))
	_rebuild_list(_stage_list, host.known_stages, host.is_stage_enabled, host.set_stage_enabled)
	_rebuild_list(_weapon_list, HostSettingsScript.known_weapons(), host.is_weapon_enabled, host.set_weapon_enabled)

## Esc can close the panel mid-drag, and the slider then never reports the
## drag's end: finish it here and save what it left (issue #196).
func toggle_panel() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		refresh()
	elif _dragging:
		_on_drag_ended(true)

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

## The box that opens the window-size, stage and weapon area, shut by default
## so the lobby's how-to-play column keeps its room above the panel.
func more_box() -> CheckBox:
	return _more

func resolution_button() -> OptionButton:
	return _resolution

## The on/off box for a stage or pickup weapon, by name; null if not listed.
func stage_box(stage_name: String) -> CheckBox:
	return _stage_list.get_node_or_null(stage_name) as CheckBox

func weapon_box(weapon_name: String) -> CheckBox:
	return _weapon_list.get_node_or_null(weapon_name) as CheckBox

## Put the chosen window size into effect: windowed only, never fullscreen,
## never a headless run, and nothing for the default.
func apply_resolution() -> void:
	if host.resolution == Vector2i.ZERO or sfx.fullscreen:
		return
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(host.resolution)

func _add_list(content: VBoxContainer, title: String) -> VBoxContainer:
	var label := Label.new()
	label.text = title + " (untick to skip)"
	content.add_child(label)
	var list := VBoxContainer.new()
	list.name = title
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(list)
	return list

## Rebuild a list's boxes from the store. A box that the store refuses (the
## last one on) snaps back to ticked.
func _rebuild_list(list: VBoxContainer, names: PackedStringArray, is_on: Callable, set_on: Callable) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for item_name: String in names:
		var box := CheckBox.new()
		box.name = item_name
		box.text = item_name.capitalize()
		box.set_pressed_no_signal(is_on.call(item_name))
		box.toggled.connect(func(pressed: bool) -> void:
			if not set_on.call(item_name, pressed):
				box.set_pressed_no_signal(true))
		list.add_child(box)

func _on_resolution_selected(index: int) -> void:
	host.set_resolution(HostSettingsScript.RESOLUTIONS[index])
	apply_resolution()

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

func _add_box(rows: Container, node_name: String, title: String) -> CheckBox:
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
