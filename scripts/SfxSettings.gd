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
const FeedbackSenderScript := preload("res://scripts/FeedbackSender.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")
const GameModesScript := preload("res://scripts/GameModes.gd")
const RoundModifiersScript := preload("res://scripts/RoundModifiers.gd")
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
var _rules_mode: OptionButton
var _rules_list: VBoxContainer
## The game mode ids the Rules selector offers, by item index ("" is Classic).
var _rules_mode_ids: PackedStringArray = []
var _toggle: Button
var _panel: PanelContainer
var _slider: HSlider
var _sfx_slider: HSlider
var _music_slider: HSlider
var _mute: CheckBox
var _fullscreen: CheckBox
var _shake_box: CheckBox
var _flash_box: CheckBox
var _hide_code_box: CheckBox
var _scale_button: OptionButton
## Whether a slider is being dragged. A drag applies every step live and
## saves once, when it ends (issue #167).
var _dragging: bool = false
## Whether this layer took the left press now held down, which was on the
## toggle, so the matching release is its too (issue #216).
var _took_press: bool = false

## Feedback (issue #262): a button in the panel opens a text box whose text goes
## to the relay, which files a GitHub issue. Empty `feedback_relay_url` means
## the game's configured relay.
var feedback_relay_url: String = ""
var _feedback_button: Button
var _feedback_box: PanelContainer
var _feedback_edit: TextEdit
var _feedback_send: Button
var _feedback_status: Label
var _feedback_sender: Node

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
	_slider = _add_slider(rows, "Volume", tr("SETTINGS_MASTER_VOLUME"))
	_sfx_slider = _add_slider(rows, "SfxVolume", tr("SETTINGS_SFX"))
	_music_slider = _add_slider(rows, "MusicVolume", tr("SETTINGS_MUSIC"))
	if music == null:
		_music_slider.get_parent().visible = false
	# Side by side, to give the new rows below their height (issue #294): the
	# lobby's how-to-play column only has so much room above the panel.
	var toggles := HBoxContainer.new()
	toggles.name = "TogglesRow"
	rows.add_child(toggles)
	_mute = _add_box(toggles, "Mute", tr("SETTINGS_MUTE"))
	_fullscreen = _add_box(toggles, "Fullscreen", tr("SETTINGS_FULLSCREEN"))
	# One scrolling area for the window size and both lists, so the panel
	# grows by LIST_HEIGHT whatever the stage count (24+).
	_more = CheckBox.new()
	_more.name = "MoreOptions"
	_more.text = tr("SETTINGS_MORE_OPTIONS")
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
		_resolution.add_item(tr("SETTINGS_WINDOW_DEFAULT") if size == Vector2i.ZERO else tr("SETTINGS_WINDOW_SIZE") % [size.x, size.y])
	content.add_child(_resolution)
	_shake_box = _add_box(content, "ScreenShake", tr("SETTINGS_SCREEN_SHAKE"))
	_flash_box = _add_box(content, "ReduceFlash", tr("SETTINGS_REDUCE_FLASHES"))
	_hide_code_box = _add_box(content, "HideRoomCode", tr("SETTINGS_HIDE_ROOM_CODE"))
	_scale_button = OptionButton.new()
	_scale_button.name = "TagSize"
	for option: float in sfx.UI_SCALES:
		_scale_button.add_item(tr("SETTINGS_NAME_TAGS") % str(option))
	content.add_child(_scale_button)
	_stage_list = _add_list(content, "Stages")
	_weapon_list = _add_list(content, "Weapons")
	_build_rules(content)

	_feedback_button = Button.new()
	_feedback_button.name = "Feedback"
	_feedback_button.text = tr("SETTINGS_FEEDBACK")
	_feedback_button.focus_mode = Control.FOCUS_NONE
	toggles.add_child(_feedback_button)
	_feedback_button.pressed.connect(toggle_feedback)
	_build_feedback_box(corner)

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
	_shake_box.toggled.connect(func(pressed: bool) -> void: sfx.set_screen_shake(pressed))
	_flash_box.toggled.connect(func(pressed: bool) -> void: sfx.set_reduce_flash(pressed))
	_hide_code_box.toggled.connect(func(pressed: bool) -> void: sfx.set_hide_room_code(pressed))
	_scale_button.item_selected.connect(func(index: int) -> void: sfx.set_ui_scale(sfx.UI_SCALES[index]))
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
	_toggle.text = tr("SETTINGS_MUTED") if sfx.muted else tr("SETTINGS")
	_shake_box.set_pressed_no_signal(sfx.screen_shake)
	_flash_box.set_pressed_no_signal(sfx.reduce_flash)
	_hide_code_box.set_pressed_no_signal(sfx.hide_room_code)
	_scale_button.select(maxi(sfx.UI_SCALES.find(sfx.ui_scale), 0))
	_resolution.select(maxi(HostSettingsScript.RESOLUTIONS.find(host.resolution), 0))
	_rebuild_list(_stage_list, host.known_stages, host.is_stage_enabled, host.set_stage_enabled)
	_rebuild_list(_weapon_list, HostSettingsScript.known_weapons(), host.is_weapon_enabled, host.set_weapon_enabled)
	_rebuild_rules()

## Esc can close the panel mid-drag, and the slider then never reports the
## drag's end: finish it here and save what it left (issue #196).
func toggle_panel() -> void:
	_panel.visible = not _panel.visible
	if not _panel.visible:
		_feedback_box.visible = false
	if _panel.visible:
		refresh()
	elif _dragging:
		_on_drag_ended(true)

func toggle_feedback() -> void:
	_feedback_box.visible = not _feedback_box.visible
	if _feedback_box.visible:
		_feedback_status.text = ""
		_feedback_edit.grab_focus()

func feedback_open() -> bool:
	return _feedback_box.visible

func feedback_button() -> Button:
	return _feedback_button

func feedback_edit() -> TextEdit:
	return _feedback_edit

func feedback_send_button() -> Button:
	return _feedback_send

func feedback_status() -> Label:
	return _feedback_status

## Sends the typed message to the relay. Nothing happens for an empty message
## or while a send is still in flight. `FeedbackSender.finished` shows the result.
func submit_feedback() -> void:
	if _feedback_edit.text.strip_edges().is_empty():
		_feedback_status.text = FeedbackSenderScript.message_for(400)
		return
	if _feedback_sender != null and _feedback_sender.is_busy():
		return
	if _feedback_sender == null:
		_feedback_sender = FeedbackSenderScript.new()
		_feedback_sender.finished.connect(_on_feedback_finished)
		add_child(_feedback_sender)
	var url: String = feedback_relay_url
	if url.is_empty():
		url = preload("res://scripts/ControllerServer.gd").resolve_relay_url(OS.get_cmdline_user_args())
	var stage: String = ""
	var scene: Node = get_tree().current_scene
	var rounds: Node = scene.get_node_or_null(^"RoundManager") if scene != null else null
	if rounds != null and rounds.has_method("current_stage_name"):
		stage = rounds.current_stage_name()
	var version: String = str(ProjectSettings.get_setting("application/config/version", "dev"))
	_feedback_status.text = tr("FEEDBACK_SENDING")
	_feedback_send.disabled = true
	_feedback_sender.send(_feedback_edit.text, url, version, OS.get_name(), stage if not stage.is_empty() else "lobby")

func _on_feedback_finished(status: int) -> void:
	_feedback_status.text = FeedbackSenderScript.message_for(status)
	_feedback_send.disabled = _feedback_edit.text.strip_edges().is_empty()
	if status == 200:
		_feedback_edit.text = ""
		_feedback_send.disabled = true

func _on_feedback_text_changed() -> void:
	_feedback_send.disabled = _feedback_edit.text.strip_edges().is_empty() \
			or (_feedback_sender != null and _feedback_sender.is_busy())

func _build_feedback_box(corner: VBoxContainer) -> void:
	_feedback_box = PanelContainer.new()
	_feedback_box.name = "FeedbackBox"
	_feedback_box.visible = false
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = PANEL_BACKGROUND
	backdrop.set_corner_radius_all(6)
	backdrop.set_content_margin_all(PANEL_PADDING)
	_feedback_box.add_theme_stylebox_override("panel", backdrop)
	corner.add_child(_feedback_box)
	var col := VBoxContainer.new()
	_feedback_box.add_child(col)
	var title := Label.new()
	title.text = tr("FEEDBACK_TITLE")
	col.add_child(title)
	_feedback_edit = TextEdit.new()
	_feedback_edit.name = "Text"
	_feedback_edit.placeholder_text = tr("FEEDBACK_PLACEHOLDER")
	_feedback_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_feedback_edit.custom_minimum_size = Vector2(320.0, 110.0)
	col.add_child(_feedback_edit)
	_feedback_status = Label.new()
	_feedback_status.name = "Status"
	col.add_child(_feedback_status)
	_feedback_send = Button.new()
	_feedback_send.name = "Send"
	_feedback_send.text = tr("FEEDBACK_SEND")
	_feedback_send.disabled = true
	_feedback_send.focus_mode = Control.FOCUS_NONE
	col.add_child(_feedback_send)
	_feedback_edit.text_changed.connect(_on_feedback_text_changed)
	_feedback_send.pressed.connect(submit_feedback)

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

func shake_box() -> CheckBox:
	return _shake_box

func flash_box() -> CheckBox:
	return _flash_box

func tag_size_button() -> OptionButton:
	return _scale_button

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

## The Rules section (#378): a mode selector and one box per round modifier.
func _build_rules(content: VBoxContainer) -> void:
	var label := Label.new()
	label.text = "Rules: modifiers that can roll (untick to skip)"
	content.add_child(label)
	_rules_mode = OptionButton.new()
	_rules_mode.name = "RulesMode"
	_rules_mode_ids = PackedStringArray([GameModesScript.CLASSIC])
	_rules_mode.add_item("Classic")
	for row: Dictionary in GameModesScript.picker_rows():
		_rules_mode_ids.append(str(row["id"]))
		_rules_mode.add_item(str(row["name"]))
	content.add_child(_rules_mode)
	_rules_list = VBoxContainer.new()
	_rules_list.name = "Rules"
	_rules_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_rules_list)
	_rules_mode.item_selected.connect(func(_index: int) -> void: _rebuild_rules())

func _rebuild_rules() -> void:
	var mode_id: String = _rules_mode_ids[maxi(_rules_mode.selected, 0)]
	for child in _rules_list.get_children():
		_rules_list.remove_child(child)
		child.queue_free()
	for id: String in RoundModifiersScript.IDS:
		var box := CheckBox.new()
		box.name = id
		box.text = RoundModifiersScript.title_of(id)
		var banned: bool = GameModesScript.bans_modifier(mode_id, id)
		box.set_pressed_no_signal(host.is_modifier_enabled(mode_id, id))
		if banned:
			box.disabled = true  # the mode's table bans it: locked off
			box.text += " (banned in this mode)"
		box.toggled.connect(func(pressed: bool) -> void:
			if not host.set_modifier_enabled(mode_id, id, pressed):
				box.set_pressed_no_signal(false))
		_rules_list.add_child(box)

## The mode selector and the modifier box for `modifier_id` in the Rules section.
func rules_mode_button() -> OptionButton:
	return _rules_mode

func rules_box(modifier_id: String) -> CheckBox:
	return _rules_list.get_node_or_null(modifier_id) as CheckBox

func _add_list(content: VBoxContainer, title: String) -> VBoxContainer:
	var label := Label.new()
	label.text = tr("SETTINGS_%s_LIST" % title.to_upper())
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
