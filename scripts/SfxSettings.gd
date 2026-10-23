extends CanvasLayer

## The host screen's settings menu (issues #75 and #118, ADR-0016, ADR-0017).
## A small "Settings" button in the bottom-right corner opens a panel with
## these controls:
##
## - master, SFX, voice and music volume sliders (voice is the announcer and
##   the fighters' grunts, under SFX, #824);
## - a mute box;
## - a fullscreen box;
## - a window size for windowed mode, and the comfort and streamer options.
##   (The stage, weapon and round-modifier switches live on the lobby's
##   Stages & Rules screen since #647.)
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
const SLIDER_WIDTH: float = 180.0
const FeedbackSenderScript := preload("res://scripts/FeedbackSender.gd")
const NOTICE_TEXT: String = "Pickfight sends anonymous match stats to help balance the game"
const UiThemeScript := preload("res://scripts/UiTheme.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")
const LanguagesScript := preload("res://scripts/Languages.gd")
const PadMenuScript := preload("res://scripts/PadMenu.gd")
const HostMatchMenuScript := preload("res://scripts/HostMatchMenu.gd")
const QuitGameScript := preload("res://scripts/QuitGame.gd")
const TextScaleScript := preload("res://scripts/TextScale.gd")
const CreditsScreenScript := preload("res://scripts/CreditsScreen.gd")
## Height of the scrolling window-size and options area.
const LIST_HEIGHT: float = 130.0

var sfx: Node
## The `Music` autoload, or null. Without it the music slider is hidden.
var music: Node

## The host's resolution choice (#294). Stages, modifiers and weapons moved to the lobby's Stages & Rules screen (#647).
var host: RefCounted = HostSettingsScript.shared()
var _more: CheckBox
var _more_area: ScrollContainer
var _resolution: OptionButton
## The Language row (#688): Auto (system), then every `Languages.OPTIONS` entry.
var _language: OptionButton
var _toggle: Button
var _panel: PanelContainer
var _slider: HSlider
var _sfx_slider: HSlider
var _voice_slider: HSlider
var _music_slider: HSlider
var _mute: CheckBox
var _fullscreen: CheckBox
var _shake_box: CheckBox
var _flash_box: CheckBox
var _numbers_box: CheckBox
## Anonymous match stats (issue #372): the Settings toggle and the one-time
## first-launch notice with its two buttons.
var _stats_box: CheckBox
var _crash_box: CheckBox
var _replay_box: CheckBox
var _autosave_box: CheckBox
var _focus_box: CheckBox
var _filter_box: CheckBox
var _notice: PanelContainer
var _notice_label: Label
var _notice_off: Button
var _notice_ok: Button
var _hide_code_box: CheckBox
var _kill_feed_box: CheckBox
var _damage_numbers_box: CheckBox
var _edge_arrows_box: CheckBox
var _match_point_plate_box: CheckBox
var _hit_pause_box: CheckBox
var _pickup_callouts_box: CheckBox
var _scale_button: OptionButton
## Text size (#751): Settings > More options.
var _text_size_button: OptionButton
## Stick deadzone (#748): Settings > More options.
var _deadzone_button: OptionButton
## Frame-rate cap and VSync (#774): Settings > More options.
var _fps_button: OptionButton
var _vsync_box: CheckBox
var _host_match: VBoxContainer
## Quit game (#718): the button, and the confirm that replaces it while other humans are seated.
var _credits_button: Button
var _quit_button: Button
var _quit_confirm: VBoxContainer
var _quit_label: Label
var _quit_yes: Button
var _quit_no: Button
var _restore_button: Button
var _restore_confirm: VBoxContainer
var _restore_label: Label
var _restore_yes: Button
var _restore_no: Button
## What Restore defaults resizes the window with; unset, the real window. A scenario sets a recorder.
var window_resizer: Callable = Callable()
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
	# The theme\'s panel look (#549): indigo, ink outline, hard shadow.
	corner.add_child(_panel)
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	# Issue #458: an Online host's Pause, End match and Kick lead the panel mid-match.
	_host_match = HostMatchMenuScript.new()
	rows.add_child(_host_match)
	_slider = _add_slider(rows, "Volume", tr("SETTINGS_MASTER_VOLUME"))
	_sfx_slider = _add_slider(rows, "SfxVolume", tr("SETTINGS_SFX"))
	_voice_slider = _add_slider(rows, "VoiceVolume", tr("SETTINGS_VOICE"))
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
	# One scrolling area for the window size and the options, so the panel
	# grows by LIST_HEIGHT whatever their count.
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
	_language = OptionButton.new()
	_language.name = "Language"
	_fill_language_items()
	content.add_child(_language)
	_refresh_language_popup_font() # its CJK names draw in any locale (#849)
	_resolution = OptionButton.new()
	_resolution.name = "Resolution"
	for size: Vector2i in HostSettingsScript.RESOLUTIONS:
		_resolution.add_item(tr("SETTINGS_WINDOW_DEFAULT") if size == Vector2i.ZERO else tr("SETTINGS_WINDOW_SIZE") % [size.x, size.y])
	content.add_child(_resolution)
	_shake_box = _add_box(content, "ScreenShake", tr("SETTINGS_SCREEN_SHAKE"))
	_hit_pause_box = _add_box(content, "HitPause", tr("SETTINGS_HIT_PAUSE"))
	_flash_box = _add_box(content, "ReduceFlash", tr("SETTINGS_REDUCE_FLASHES"))
	_hide_code_box = _add_box(content, "HideRoomCode", tr("SETTINGS_HIDE_ROOM_CODE"))
	_kill_feed_box = _add_box(content, "KillFeed", tr("SETTINGS_KILL_FEED"))
	_damage_numbers_box = _add_box(content, "DamageNumbers", tr("SETTINGS_DAMAGE_NUMBERS"))
	_edge_arrows_box = _add_box(content, "EdgeArrows", tr("SETTINGS_EDGE_ARROWS"))
	_match_point_plate_box = _add_box(content, "MatchPointPlate", tr("SETTINGS_MATCH_POINT_PLATE"))
	_pickup_callouts_box = _add_box(content, "PickupCallouts", tr("SETTINGS_PICKUP_CALLOUTS"))
	_scale_button = OptionButton.new()
	_scale_button.name = "TagSize"
	for option: float in sfx.UI_SCALES:
		_scale_button.add_item(tr("SETTINGS_NAME_TAGS") % str(option))
	content.add_child(_scale_button)
	_text_size_button = OptionButton.new()
	_text_size_button.name = "TextSize"
	for option: float in sfx.TEXT_SCALES:
		_text_size_button.add_item(_text_size_item(option))
	content.add_child(_text_size_button)
	_deadzone_button = OptionButton.new()
	_deadzone_button.name = "StickDeadzone"
	for option: float in HostSettingsScript.PAD_DEADZONES:
		_deadzone_button.add_item(tr("SETTINGS_STICK_DEADZONE") % ("%.2f" % option))
	content.add_child(_deadzone_button)
	_fps_button = OptionButton.new()
	_fps_button.name = "FrameRate"
	for option: int in HostSettingsScript.FRAME_CAPS:
		_fps_button.add_item(_frame_cap_text(option))
	content.add_child(_fps_button)
	_vsync_box = _add_box(content, "VSync", tr("SETTINGS_VSYNC"))
	_replay_box = _add_box(content, "PlayOfRound", tr("SETTINGS_PLAY_OF_ROUND"))
	_autosave_box = _add_box(content, "AutoSaveClips", tr("SETTINGS_AUTO_SAVE_CLIPS"))
	_focus_box = _add_box(content, "PauseOnFocusLoss", tr("SETTINGS_PAUSE_ON_FOCUS_LOSS"))
	_filter_box = _add_box(content, "FilterNames", tr("SETTINGS_FILTER_NAMES"))
	_numbers_box = _add_box(content, "PlayerNumbers", tr("SETTINGS_PLAYER_NUMBERS"))
	_crash_box = _add_box(content, "SendCrashReports", tr("SETTINGS_SEND_CRASH_REPORTS"))
	# Last in More options, kept quiet (issue #461).
	_stats_box = _add_box(content, "ShareStats", tr("SETTINGS_SHARE_STATS"))
	# Restore defaults (#750), above Credits: one press asks first, Yes resets.
	var restore: Array = _add_confirm(rows, "RestoreDefaults", "Restore", "SETTINGS_RESTORE_DEFAULTS", "RESTORE_CONFIRM_TEXT")
	_restore_button = restore[0]
	_restore_confirm = restore[1]
	_restore_label = restore[2]
	_restore_yes = restore[3]
	_restore_no = restore[4]
	# Credits and licences (#721), above Quit.
	_credits_button = Button.new()
	_credits_button.name = "Credits"
	_credits_button.text = tr("CREDITS_BUTTON")
	_credits_button.focus_mode = Control.FOCUS_NONE
	rows.add_child(_credits_button)
	# Quit game (#718), last in the panel.
	var quit: Array = _add_confirm(rows, "QuitGame", "Quit", "SETTINGS_QUIT_GAME", "QUIT_CONFIRM_TEXT")
	_quit_button = quit[0]
	_quit_confirm = quit[1]
	_quit_label = quit[2]
	_quit_yes = quit[3]
	_quit_no = quit[4]

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
	if TextScaleScript.design_default_size() > 0:
		# The corner button keeps its design size at every Text size: it sits over the lobby's bottom-right line (#751).
		_toggle.add_theme_font_size_override("font_size", TextScaleScript.design_default_size())
		_toggle.set_meta(TextScaleScript.META_SKIP, true)
	corner.add_child(_toggle)

	_build_telemetry_notice()
	refresh()
	_stats_box.toggled.connect(func(pressed: bool) -> void: host.set_share_stats(pressed))
	_replay_box.toggled.connect(func(pressed: bool) -> void: host.set_play_of_round(pressed))
	_autosave_box.toggled.connect(func(pressed: bool) -> void: host.set_auto_save_clips(pressed))
	_focus_box.toggled.connect(func(pressed: bool) -> void: host.set_pause_on_focus_loss(pressed))
	_filter_box.toggled.connect(func(pressed: bool) -> void: host.set_filter_names(pressed))
	_numbers_box.toggled.connect(func(pressed: bool) -> void: host.set_player_numbers(pressed))
	_crash_box.toggled.connect(func(pressed: bool) -> void: host.set_send_crash_reports(pressed))
	_slider.value_changed.connect(_on_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_voice_slider.value_changed.connect(_on_voice_volume_changed)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	for slider: HSlider in [_slider, _sfx_slider, _voice_slider, _music_slider]:
		slider.drag_started.connect(_on_drag_started)
		slider.drag_ended.connect(_on_drag_ended)
	_mute.toggled.connect(_on_mute_toggled)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_toggle.pressed.connect(toggle_panel)
	_credits_button.pressed.connect(open_credits)
	_quit_button.pressed.connect(request_quit)
	_quit_yes.pressed.connect(confirm_quit)
	_quit_no.pressed.connect(cancel_quit)
	_restore_button.pressed.connect(request_restore)
	_restore_yes.pressed.connect(confirm_restore)
	_restore_no.pressed.connect(cancel_restore)
	_resolution.item_selected.connect(_on_resolution_selected)
	_language.item_selected.connect(_on_language_selected)
	_shake_box.toggled.connect(func(pressed: bool) -> void: sfx.set_screen_shake(pressed))
	_hit_pause_box.toggled.connect(func(pressed: bool) -> void: sfx.set_hit_pause(pressed))
	_flash_box.toggled.connect(func(pressed: bool) -> void: sfx.set_reduce_flash(pressed))
	_kill_feed_box.toggled.connect(func(pressed: bool) -> void: sfx.set_kill_feed(pressed))
	_damage_numbers_box.toggled.connect(func(pressed: bool) -> void: sfx.set_damage_numbers(pressed))
	_edge_arrows_box.toggled.connect(func(pressed: bool) -> void: sfx.set_edge_arrows(pressed))
	_match_point_plate_box.toggled.connect(func(pressed: bool) -> void: sfx.set_match_point_plate(pressed))
	_pickup_callouts_box.toggled.connect(func(pressed: bool) -> void: sfx.set_pickup_callouts(pressed))
	_hide_code_box.toggled.connect(func(pressed: bool) -> void: sfx.set_hide_room_code(pressed))
	_scale_button.item_selected.connect(func(index: int) -> void: sfx.set_ui_scale(sfx.UI_SCALES[index]))
	_text_size_button.item_selected.connect(func(index: int) -> void: sfx.set_text_scale(sfx.TEXT_SCALES[index]))
	_deadzone_button.item_selected.connect(func(index: int) -> void: host.set_pad_deadzone(HostSettingsScript.PAD_DEADZONES[index]))
	_fps_button.item_selected.connect(func(index: int) -> void: host.set_frame_cap(HostSettingsScript.FRAME_CAPS[index]))
	_vsync_box.toggled.connect(func(pressed: bool) -> void: host.set_vsync(pressed))
	_more.toggled.connect(func(pressed: bool) -> void:
		_more_area.visible = pressed
		if PadMenuScript.is_open():
			_chain_pad_focus.call_deferred())
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
	# The credits screen (a higher layer) covers the corner: a click there is the credits' own.
	var credits: Node = get_tree().root.get_node_or_null(CreditsScreenScript.NODE_NAME) if is_inside_tree() else null
	if credits != null and credits.is_open():
		return false
	return _toggle.get_global_rect().has_point(point)

func _unhandled_input(event: InputEvent) -> void:
	# Gamepad (#368): View opens the panel, B closes it.
	if PadMenuScript.pressed(event, JOY_BUTTON_BACK):
		pad_toggle()
		get_viewport().set_input_as_handled()
		return
	if PadMenuScript.pressed(event, JOY_BUTTON_B) and _panel.visible:
		if _restore_confirm.visible:
			cancel_restore() # B is No (#750)
		elif _quit_confirm.visible:
			cancel_quit() # B is No (#718)
		elif _feedback_box.visible:
			toggle_feedback()
		else:
			toggle_panel()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_M:
			sfx.toggle_muted()
		KEY_F11:
			sfx.toggle_fullscreen()
		KEY_ESCAPE:
			if _restore_confirm.visible:
				cancel_restore() # Esc is No (#750)
			elif _quit_confirm.visible:
				cancel_quit() # Esc is No (#718)
			else:
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
	_voice_slider.set_value_no_signal(sfx.voice_volume)
	if music != null:
		_music_slider.set_value_no_signal(music.volume)
	_mute.set_pressed_no_signal(sfx.muted)
	_fullscreen.set_pressed_no_signal(sfx.fullscreen)
	_refresh_toggle_text()
	_shake_box.set_pressed_no_signal(sfx.screen_shake)
	_hit_pause_box.set_pressed_no_signal(sfx.hit_pause)
	_flash_box.set_pressed_no_signal(sfx.reduce_flash)
	_stats_box.set_pressed_no_signal(host.share_stats)
	_crash_box.set_pressed_no_signal(host.send_crash_reports)
	_numbers_box.set_pressed_no_signal(host.player_numbers)
	_replay_box.set_pressed_no_signal(host.play_of_round)
	_autosave_box.set_pressed_no_signal(host.auto_save_clips)
	_focus_box.set_pressed_no_signal(host.pause_on_focus_loss)
	_filter_box.set_pressed_no_signal(host.filter_names)
	_refresh_notice()
	_hide_code_box.set_pressed_no_signal(sfx.hide_room_code)
	_kill_feed_box.set_pressed_no_signal(sfx.kill_feed)
	_damage_numbers_box.set_pressed_no_signal(sfx.damage_numbers)
	_edge_arrows_box.set_pressed_no_signal(sfx.edge_arrows)
	_match_point_plate_box.set_pressed_no_signal(sfx.match_point_plate)
	_pickup_callouts_box.set_pressed_no_signal(sfx.pickup_callouts)
	_scale_button.select(maxi(sfx.UI_SCALES.find(sfx.ui_scale), 0))
	_text_size_button.select(maxi(sfx.TEXT_SCALES.find(sfx.text_scale), 0))
	_deadzone_button.select(maxi(HostSettingsScript.PAD_DEADZONES.find(host.pad_deadzone), 0))
	_fps_button.select(maxi(HostSettingsScript.FRAME_CAPS.find(host.frame_cap), 0))
	_vsync_box.set_pressed_no_signal(host.vsync)
	_resolution.select(maxi(HostSettingsScript.RESOLUTIONS.find(host.resolution), 0))
	_language.select(_language_index(host.language))
	_host_match.refresh()
	if PadMenuScript.is_open():
		_chain_pad_focus()

## The corner toggle's caption: all a volume slider's step changes, so a drag does not redo the whole panel.
func _refresh_toggle_text() -> void:
	_toggle.text = tr("SETTINGS_MUTED") if sfx.muted else tr("SETTINGS")

## The host PC's match controls at the top of the panel (issue #458).
func host_match_menu() -> VBoxContainer:
	return _host_match

## Esc can close the panel mid-drag, and the slider then never reports the
## drag's end: finish it here and save what it left (issue #196).
func toggle_panel() -> void:
	_panel.visible = not _panel.visible
	if not _panel.visible:
		_feedback_box.visible = false
		cancel_quit()
		_set_pad_focus(false)
		cancel_restore()
	if _panel.visible:
		refresh()
	elif _dragging:
		_on_drag_ended(true)

## The gamepad's way in (#368): View opens the panel with focus on its first
## slider, or, while the first-launch notice is up, focuses the notice's OK
## first. D-pad moves focus, left and right turn a slider, A presses, B closes.
func pad_toggle() -> void:
	if _notice.visible and not _panel.visible:
		_set_pad_focus(true)
		_notice_ok.grab_focus()
		return
	toggle_panel()
	if _panel.visible:
		_set_pad_focus(true)

## Makes every control in the panel (and the notice) focusable for the gamepad
## and focuses the first, or gives it all back to mouse-only when `on` is
## false. They are FOCUS_NONE otherwise so a stray Enter never presses one
## mid-match.
func _set_pad_focus(on: bool) -> void:
	PadMenuScript.set_open("settings", on)
	var mode: Control.FocusMode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	for node: Node in _panel.find_children("*", "Control", true, false):
		if node is BaseButton or node is Slider:
			(node as Control).focus_mode = mode
	# The notice stays reachable by keys while it is due (#617).
	var notice_mode: Control.FocusMode = Control.FOCUS_ALL if on or _notice_due() else Control.FOCUS_NONE
	_notice_ok.focus_mode = notice_mode
	_notice_off.focus_mode = notice_mode
	if on:
		_chain_pad_focus()
		_slider.grab_focus()
	elif is_inside_tree():
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()

## Godot's own focus neighbours are geometric and lose controls inside the
## scrolling lists, so the panel's controls are chained top to bottom in
## their tree order (the visual order). Left and right keep the geometric
## default so the Mute / Fullscreen / Feedback row and sliders still work.
func _chain_pad_focus() -> void:
	var items: Array[Control] = []
	for node: Node in _panel.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not (control is BaseButton or control is Slider):
			continue
		if control.focus_mode == Control.FOCUS_NONE or not control.is_visible_in_tree():
			continue
		if control is BaseButton and (control as BaseButton).disabled:
			continue
		items.append(control)
	for i in items.size():
		if i > 0:
			items[i].focus_neighbor_top = items[i].get_path_to(items[i - 1])
		if i < items.size() - 1:
			items[i].focus_neighbor_bottom = items[i].get_path_to(items[i + 1])

## Quit game (#718): straight out when nobody but the host and bots is seated (Solo, a lone Online
## host, a PC client); otherwise the panel asks first, with No as the default focus.
func request_quit() -> void:
	var server: Node = _host_match.server() if _host_match != null else null
	if QuitGameScript.others_seated(server):
		_quit_button.visible = false
		_quit_confirm.visible = true
		if PadMenuScript.is_open():
			_chain_pad_focus()
			_quit_no.grab_focus()
		return
	QuitGameScript.quit_game(get_tree(), server)

func confirm_quit() -> void:
	var server: Node = _host_match.server() if _host_match != null else null
	cancel_quit()
	QuitGameScript.quit_game(get_tree(), server)

func cancel_quit() -> void:
	_quit_confirm.visible = false
	_quit_button.visible = true

## Restore defaults (#750): the first press asks, with No as the default focus.
func request_restore() -> void:
	_restore_button.visible = false
	_restore_confirm.visible = true
	if PadMenuScript.is_open():
		_chain_pad_focus()
		_restore_no.grab_focus()

## Yes: every setting but Language and the crash-report choice goes back to its default.
func confirm_restore() -> void:
	cancel_restore()
	sfx.restore_defaults()
	if music != null:
		music.restore_defaults()
	host.restore_defaults()
	_restore_window_size()
	refresh()

## Restore defaults puts a windowed host back to the project's own window size (owner decision):
## the Default size is ZERO, which `apply_resolution()` leaves alone. A headless run never resizes.
func _restore_window_size() -> void:
	if host.resolution != Vector2i.ZERO or sfx.fullscreen:
		return
	var size := Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))
	if window_resizer.is_valid():
		window_resizer.call(size) # a scenario's recorder
		return
	if DisplayServer.get_name() == "headless" or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	DisplayServer.window_set_size(fit_resolution(size, DisplayServer.screen_get_size()))

func cancel_restore() -> void:
	_restore_confirm.visible = false
	_restore_button.visible = true

func restore_button() -> Button:
	return _restore_button

func restore_confirm_box() -> Control:
	return _restore_confirm

func restore_yes_button() -> Button:
	return _restore_yes

func restore_no_button() -> Button:
	return _restore_no
## The credits and licences screen (#721).
func open_credits() -> void:
	CreditsScreenScript.open(get_tree())

func credits_button() -> Button:
	return _credits_button

func quit_button() -> Button:
	return _quit_button

func quit_confirm_box() -> Control:
	return _quit_confirm

func quit_yes_button() -> Button:
	return _quit_yes

func quit_no_button() -> Button:
	return _quit_no

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
	# The theme\'s panel look (#549): indigo, ink outline, hard shadow.
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
	_attach_pad_keyboard(_feedback_edit) # #711
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

func voice_slider() -> HSlider:
	return _voice_slider

func music_slider() -> HSlider:
	return _music_slider

func mute_box() -> CheckBox:
	return _mute

func fullscreen_box() -> CheckBox:
	return _fullscreen

## The box that opens the window-size and options area, shut by default
## so the lobby's how-to-play column keeps its room above the panel.
func more_box() -> CheckBox:
	return _more

func kill_feed_box() -> CheckBox:
	return _kill_feed_box

func damage_numbers_box() -> CheckBox:
	return _damage_numbers_box

func edge_arrows_box() -> CheckBox:
	return _edge_arrows_box

func match_point_plate_box() -> CheckBox:
	return _match_point_plate_box

func hit_pause_box() -> CheckBox:
	return _hit_pause_box

func pickup_callouts_box() -> CheckBox:
	return _pickup_callouts_box

func shake_box() -> CheckBox:
	return _shake_box

func stats_box() -> CheckBox:
	return _stats_box

func replay_box() -> CheckBox:
	return _replay_box

func crash_box() -> CheckBox:
	return _crash_box

## The one-time disclosure (#617): due until it has been dismissed, and only on
## the title or in the lobby, never mid-round.
func _notice_due() -> bool:
	if host.telemetry_notice_seen:
		return false
	if not is_inside_tree():
		return true
	var scene: Node = get_tree().current_scene
	var rounds: Node = scene.get_node_or_null(^"RoundManager") if scene != null else null
	if rounds != null and rounds.has_method("lobby_phase"):
		return rounds.lobby_phase() == "lobby"
	return true

func _refresh_notice() -> void:
	var due: bool = _notice_due()
	if due == _notice.visible:
		return
	_notice.visible = due
	if due:
		_notice_ok.focus_mode = Control.FOCUS_ALL
		_notice_off.focus_mode = Control.FOCUS_ALL
		if is_inside_tree() and not _panel.visible:
			_notice_ok.grab_focus()
	elif not PadMenuScript.is_open():
		_notice_ok.focus_mode = Control.FOCUS_NONE
		_notice_off.focus_mode = Control.FOCUS_NONE

## The notice follows the round state: it appears back in the lobby and hides
## the moment a round starts.
func _process(_delta: float) -> void:
	_refresh_notice()

func telemetry_notice() -> Control:
	return _notice

func telemetry_notice_label() -> Label:
	return _notice_label

func telemetry_turn_off_button() -> Button:
	return _notice_off

func telemetry_dismiss_button() -> Button:
	return _notice_ok

## The one-time telemetry notice (#372, #617), top centre of the host screen in
## the shared theme. "Got it" and "Turn off" both mark it seen for good; "Turn
## off" also switches sharing off.
func _build_telemetry_notice() -> void:
	_notice = PanelContainer.new()
	_notice.name = "TelemetryNotice"
	_notice.theme_type_variation = UiThemeScript.CARD_PANEL
	_notice.anchor_left = 0.5
	_notice.anchor_right = 0.5
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.offset_top = MARGIN
	add_child(_notice)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_notice.add_child(column)
	_notice_label = Label.new()
	_notice_label.text = tr("TELEMETRY_NOTICE") + " " + tr("TELEMETRY_NOTICE_CRASH")
	_notice_label.theme_type_variation = UiThemeScript.INK_BOLD_LABEL
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_label.custom_minimum_size = Vector2(620.0, 0.0)
	column.add_child(_notice_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	_notice_off = Button.new()
	_notice_off.name = "TurnOff"
	_notice_off.text = tr("TELEMETRY_TURN_OFF")
	_notice_off.theme_type_variation = UiThemeScript.SKY_BUTTON
	_notice_off.focus_mode = Control.FOCUS_NONE
	row.add_child(_notice_off)
	_notice_ok = Button.new()
	_notice_ok.name = "Dismiss"
	_notice_ok.text = tr("TELEMETRY_OK")
	_notice_ok.theme_type_variation = UiThemeScript.YELLOW_BUTTON
	_notice_ok.focus_mode = Control.FOCUS_NONE
	row.add_child(_notice_ok)
	_notice_off.pressed.connect(func() -> void:
		host.set_share_stats(false)
		host.mark_telemetry_notice_seen()
		refresh()
		if not _panel.visible:
			_set_pad_focus(false))
	_notice_ok.pressed.connect(func() -> void:
		host.mark_telemetry_notice_seen()
		refresh()
		if not _panel.visible:
			_set_pad_focus(false))

func numbers_box() -> CheckBox:
	return _numbers_box

func flash_box() -> CheckBox:
	return _flash_box

## One Text size choice, e.g. "Text size: Large" (#751).
func _text_size_item(scale: float) -> String:
	var names: Array[String] = [tr("TEXT_SIZE_NORMAL"), tr("TEXT_SIZE_LARGE"), tr("TEXT_SIZE_LARGER")]
	return tr("SETTINGS_TEXT_SIZE") % names[maxi(sfx.TEXT_SCALES.find(scale), 0)]

func text_size_button() -> OptionButton:
	return _text_size_button

func tag_size_button() -> OptionButton:
	return _scale_button

func frame_rate_button() -> OptionButton:
	return _fps_button

func vsync_box() -> CheckBox:
	return _vsync_box

func _frame_cap_text(cap: int) -> String:
	return tr("SETTINGS_FRAME_RATE") % (tr("SETTINGS_FRAME_RATE_UNLIMITED") if cap == 0 else str(cap))

func deadzone_button() -> OptionButton:
	return _deadzone_button

func resolution_button() -> OptionButton:
	return _resolution

## Put the chosen window size into effect: windowed only, never fullscreen,
## never a headless run, and nothing for the default.
func apply_resolution() -> void:
	if host.resolution == Vector2i.ZERO or sfx.fullscreen:
		return
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(fit_resolution(host.resolution, DisplayServer.screen_get_size()))

## A saved window size kept inside `screen` (#609); a degenerate one is ZERO.
static func fit_resolution(size: Vector2i, screen: Vector2i) -> Vector2i:
	if size.x < 1 or size.y < 1:
		return Vector2i.ZERO
	return Vector2i(mini(size.x, maxi(screen.x, 1)), mini(size.y, maxi(screen.y, 1)))

func _on_resolution_selected(index: int) -> void:
	host.set_resolution(HostSettingsScript.RESOLUTIONS[index])
	apply_resolution()

## The language picker: Auto first (translated), then each language in its
## own name, in `Languages.OPTIONS` order.
func _fill_language_items() -> void:
	_language.clear()
	_language.add_item(tr("LANGUAGE_AUTO"))
	for option: Dictionary in LanguagesScript.OPTIONS:
		_language.add_item(str(option["name"]))

func _language_index(setting: String) -> int:
	return LanguagesScript.codes().find(setting) + 1  # Auto (or unknown) is 0

func language_button() -> OptionButton:
	return _language

## Rebuilt when the language changes so it follows the live chain (#849).
func _refresh_language_popup_font() -> void:
	_language.get_popup().add_theme_font_override("font", LanguagesScript.picker_font(_language.get_theme_font("font"), TranslationServer.get_locale()))

func _on_language_selected(index: int) -> void:
	var setting: String = LanguagesScript.AUTO if index <= 0 else str(LanguagesScript.OPTIONS[index - 1]["code"])
	host.set_language(setting)
	_retranslate()

## Re-words the panel in the language just chosen. The controls were given
## `tr()`'d text when built, which Godot does not redo on a locale change.
func _retranslate() -> void:
	for slider: HSlider in [_slider, _sfx_slider, _voice_slider, _music_slider]:
		var title := slider.get_parent().get_child(0) as Label
		title.text = tr({_slider: "SETTINGS_MASTER_VOLUME", _sfx_slider: "SETTINGS_SFX", _voice_slider: "SETTINGS_VOICE", _music_slider: "SETTINGS_MUSIC"}[slider])
	_mute.text = tr("SETTINGS_MUTE")
	_fullscreen.text = tr("SETTINGS_FULLSCREEN")
	_more.text = tr("SETTINGS_MORE_OPTIONS")
	_shake_box.text = tr("SETTINGS_SCREEN_SHAKE")
	_hit_pause_box.text = tr("SETTINGS_HIT_PAUSE")
	_flash_box.text = tr("SETTINGS_REDUCE_FLASHES")
	_numbers_box.text = tr("SETTINGS_PLAYER_NUMBERS")
	_hide_code_box.text = tr("SETTINGS_HIDE_ROOM_CODE")
	_kill_feed_box.text = tr("SETTINGS_KILL_FEED")
	_damage_numbers_box.text = tr("SETTINGS_DAMAGE_NUMBERS")
	_edge_arrows_box.text = tr("SETTINGS_EDGE_ARROWS")
	_match_point_plate_box.text = tr("SETTINGS_MATCH_POINT_PLATE")
	_pickup_callouts_box.text = tr("SETTINGS_PICKUP_CALLOUTS")
	_stats_box.text = tr("SETTINGS_SHARE_STATS")
	_crash_box.text = tr("SETTINGS_SEND_CRASH_REPORTS")
	_replay_box.text = tr("SETTINGS_PLAY_OF_ROUND")
	_autosave_box.text = tr("SETTINGS_AUTO_SAVE_CLIPS")
	_filter_box.text = tr("SETTINGS_FILTER_NAMES")
	_focus_box.text = tr("SETTINGS_PAUSE_ON_FOCUS_LOSS")
	_vsync_box.text = tr("SETTINGS_VSYNC")
	_feedback_button.text = tr("SETTINGS_FEEDBACK")
	_credits_button.text = tr("CREDITS_BUTTON")
	_quit_button.text = tr("SETTINGS_QUIT_GAME")
	_quit_label.text = tr("QUIT_CONFIRM_TEXT")
	_quit_yes.text = tr("QUIT_YES")
	_quit_no.text = tr("QUIT_NO")
	_restore_button.text = tr("SETTINGS_RESTORE_DEFAULTS")
	_restore_label.text = tr("RESTORE_CONFIRM_TEXT")
	_restore_yes.text = tr("QUIT_YES")
	_restore_no.text = tr("QUIT_NO")
	_feedback_send.text = tr("FEEDBACK_SEND")
	_feedback_edit.placeholder_text = tr("FEEDBACK_PLACEHOLDER")
	((_feedback_send.get_parent() as Node).get_child(0) as Label).text = tr("FEEDBACK_TITLE")
	_notice_label.text = tr("TELEMETRY_NOTICE") + " " + tr("TELEMETRY_NOTICE_CRASH")
	_notice_off.text = tr("TELEMETRY_TURN_OFF")
	_notice_ok.text = tr("TELEMETRY_OK")
	for i in HostSettingsScript.RESOLUTIONS.size():
		var size: Vector2i = HostSettingsScript.RESOLUTIONS[i]
		_resolution.set_item_text(i, tr("SETTINGS_WINDOW_DEFAULT") if size == Vector2i.ZERO else tr("SETTINGS_WINDOW_SIZE") % [size.x, size.y])
	for i in sfx.UI_SCALES.size():
		_scale_button.set_item_text(i, tr("SETTINGS_NAME_TAGS") % str(sfx.UI_SCALES[i]))
	for i in sfx.TEXT_SCALES.size():
		_text_size_button.set_item_text(i, _text_size_item(sfx.TEXT_SCALES[i]))
	for i in HostSettingsScript.PAD_DEADZONES.size():
		_deadzone_button.set_item_text(i, tr("SETTINGS_STICK_DEADZONE") % ("%.2f" % HostSettingsScript.PAD_DEADZONES[i]))
	for i in HostSettingsScript.FRAME_CAPS.size():
		_fps_button.set_item_text(i, _frame_cap_text(HostSettingsScript.FRAME_CAPS[i]))
	_language.set_item_text(0, tr("LANGUAGE_AUTO"))
	_refresh_language_popup_font()
	refresh()

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

## A settings button and the Yes / No confirm that replaces it while it asks (#718, #750), added
## to `rows`: the button `button_name`, then "<prefix>Confirm" (hidden) holding the question and
## "<prefix>Yes" / "<prefix>No". Returns [button, confirm, question label, yes, no].
func _add_confirm(rows: VBoxContainer, button_name: String, prefix: String, button_key: String, text_key: String) -> Array:
	var button := Button.new()
	button.name = button_name
	button.text = tr(button_key)
	button.focus_mode = Control.FOCUS_NONE
	rows.add_child(button)
	var confirm := VBoxContainer.new()
	confirm.name = prefix + "Confirm"
	confirm.visible = false
	rows.add_child(confirm)
	var label := Label.new()
	label.text = tr(text_key)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(SLIDER_WIDTH + 24.0, 0.0)
	confirm.add_child(label)
	var row := HBoxContainer.new()
	confirm.add_child(row)
	var out: Array = [button, confirm, label]
	for answer: String in ["Yes", "No"]:
		var choice := Button.new()
		choice.name = prefix + answer
		choice.text = tr("QUIT_YES" if answer == "Yes" else "QUIT_NO")
		choice.focus_mode = Control.FOCUS_NONE
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(choice)
		out.append(choice)
	return out
func _add_box(rows: Container, node_name: String, title: String) -> CheckBox:
	var box := CheckBox.new()
	box.name = node_name
	box.text = title
	box.focus_mode = Control.FOCUS_NONE
	rows.add_child(box)
	return box

func _on_volume_changed(value: float) -> void:
	sfx.set_master_volume(value, not _dragging)
	_refresh_toggle_text()

func _on_sfx_volume_changed(value: float) -> void:
	sfx.set_sfx_volume(value, not _dragging)
	_refresh_toggle_text()

func _on_voice_volume_changed(value: float) -> void:
	sfx.set_voice_volume(value, not _dragging)
	_refresh_toggle_text()

func _on_music_volume_changed(value: float) -> void:
	if music != null:
		music.set_volume(value, not _dragging)
	_refresh_toggle_text()

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

## #711: Steam's floating gamepad keyboard for a text field, through the autoload
## by path; a build or test tree without it does nothing.
func _attach_pad_keyboard(edit: Control) -> void:
	var steam: Node = get_node_or_null(^"/root/SteamPlatform")
	if steam != null:
		steam.call("attach_text_input", edit)
