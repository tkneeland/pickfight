extends RefCounted

## The host-screen lobby controls (#239), the gamepad host menu (#368) and the
## host PC's own cosmetics picker (#441), split out of `LobbyScreen.gd` (#543).
##
## For a PC-only match with no phone: clickable buttons and keys for the match
## kind (O, Couch or Online, #435), Mode (T), First to (- and =) and Start (Enter).
## Each calls ControllerServer.apply_host_command(), the same function the host
## phone's menu ends up in, so nothing is decided here.
##
## `_screen` is the LobbyScreen: it holds the lobby widgets these controls hang
## off and the ControllerServer (`_server`), and forwards its node callbacks
## (`_input`, `_unhandled_key_input`, `_exit_tree`) here. Read dynamically: this
## script cannot name LobbyScreen without a preload cycle.
##
## A and B belong to the seat (join, ready, un-ready), so the lobby controls get
## their own entry: Y opens the menu and moves focus onto the buttons; the D-pad
## moves between them, A presses, B or Y leaves. While it is open ControllerServer
## ignores A and B (PadMenu). The Settings panel has its own button, View.

const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const PadMenuScript := preload("res://scripts/PadMenu.gd")
const TitleScreenScript := preload("res://scripts/TitleScreen.gd")

const CONTROL_KEYS: Dictionary = {
	"online": KEY_O, "mode": KEY_T, "bots": KEY_B, "target_down": KEY_MINUS,
	"target_up": KEY_EQUAL, "start": KEY_ENTER, "join": KEY_J,
}
const CONTROL_BUTTON_FONT_SIZE: int = 22 # was 26 (#425); still above DECK_MIN_FONT_SIZE
## The online room code, on Go online's own row (#425 playtest): at 64 px under the URL it pushed Start and Join off a 900 px screen.
const ROOM_CODE_FONT_SIZE: int = 26
const REMOTE_CLIENT_SCENE: String = "res://scenes/RemoteClient.tscn"
## #545: Start pressed with the lobby's conditions unmet used to do nothing and
## say nothing. The reason shows in the status line for a few seconds.
const START_NOTICE_MSEC: int = 4000
const PAD_ORDER: Array[String] = ["online", "mode", "bots", "target_down", "target_up", "start", "join"] # focus lands on the match kind first, where Go online was

var _screen # the LobbyScreen
var _controls: Dictionary = {}
var _room_label: Label
var _online_status: Label
var _join_blocked: Label

var start_notice: String = ""
var start_notice_until_msec: int = 0

var _host_picker: Control = null

var _pad_active: bool = false
var _pad_menu_open: bool = false

func _init(screen) -> void:
	_screen = screen

## Builds the controls (once) under the QR and points them at `server`. A
## server without `apply_host_command` (a test stub) gets none.
func attach(server: Object) -> void:
	var lobby_right: VBoxContainer = _screen._lobby_right
	if lobby_right == null or _screen._server != null or server == null or not server.has_method("apply_host_command"):
		return
	_screen._server = server
	var box := VBoxContainer.new()
	box.name = "HostControls"
	box.add_theme_constant_override("separation", 6) # was 8: the Join caption's room (#425 playtest)
	lobby_right.add_child(box)
	# First, not last (#425 playtest): the way into someone else's room code, with why it is off when it is.
	box.add_child(_control_button("join", _screen.tr("HOST_JOIN_ONLINE")))
	_join_blocked = ScreenKitScript.big_label(_screen.tr("HOST_JOIN_BLOCKED"), ScreenKitScript.DECK_MIN_FONT_SIZE, Color(0.8, 0.82, 0.88))
	_join_blocked.name = "JoinBlocked"
	_join_blocked.visible = false
	box.add_child(_join_blocked)
	var online_row := HBoxContainer.new()
	online_row.add_theme_constant_override("separation", 12)
	box.add_child(online_row)
	online_row.add_child(_control_button("online", _screen.tr("HOST_MATCH_KIND_STATE") % _screen.tr("MATCH_COUCH")))
	_online_status = ScreenKitScript.big_label("", 24, Color(0.8, 0.82, 0.88))
	online_row.add_child(_online_status)
	_room_label = ScreenKitScript.big_label("", ROOM_CODE_FONT_SIZE, ScreenKitScript.LOBBY_ACCENT)
	_room_label.name = "RoomCode"
	_room_label.visible = false
	online_row.add_child(_room_label)
	var pad_hint := ScreenKitScript.big_label(_screen.tr("HOST_GAMEPAD_HINT"), 24, Color(0.8, 0.82, 0.88))
	pad_hint.name = "GamepadHint"
	box.add_child(pad_hint)
	_pad_active = not Input.get_connected_joypads().is_empty()
	box.add_child(_control_button("mode", _screen.tr("HOST_MODE")))
	box.add_child(_control_button("bots", _screen.tr("HOST_BOTS_STATE") % 0)) # #445: the one bot counter, Couch and Online
	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 12)
	box.add_child(target_row)
	target_row.add_child(_control_button("target_down", _screen.tr("HOST_FIRST_TO_DOWN")))
	target_row.add_child(_control_button("target_up", "+"))
	# Start shares the First-to row (#425), which buys the room for the mode-card grid and the 340 px QR.
	var start_button: Button = _control_button("start", _screen.tr("HOST_START_MATCH"))
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(start_button)
	_screen._title_screen.build()
	refresh()

func _control_button(id: String, text: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", CONTROL_BUTTON_FONT_SIZE)
	button.pressed.connect(press_control.bind(id))
	_controls[id] = button
	return button

## The control button `id` ("online", "pc_seat", "mode", "bots", "target_down",
## "target_up", "start"), or null.
func control_button(id: String) -> Button:
	return _controls.get(id) as Button

func room_label() -> Label:
	return _room_label

func online_status() -> Label:
	return _online_status

## What a click or key on control `id` does.
func press_control(id: String) -> void:
	var server: Object = _screen._server
	if server == null:
		return
	match id:
		"online":
			# #435: Couch <-> Online (Solo flips to Couch). The room opens with Online.
			server.apply_host_command("kind", "local" if TitleScreenScript.online_kind(server) else "online")
		"mode":
			server.apply_host_command("mode", "ffa" if server.team_mode() else "teams")
		"bots":
			# #445: one more bot, back to none after the last free seat.
			var count: int = server.bot_director.bot_count()
			server.apply_host_command("bots", count + 1 if count < server.bot_capacity() else 0)
		"target_down":
			server.apply_host_command("target", server.mode_target() - 1)
		"target_up":
			server.apply_host_command("target", server.mode_target() + 1)
		"start":
			if server.apply_host_command("start"):
				_note_start_blocked()
		"join":
			# Issue #241: leave this host's lobby for the PC client's join
			# screen. Only while nobody but the host's own seat (and bots) is
			# in it, so a click cannot end a match someone is in. An open
			# room is closed on the way out.
			if _can_join_online():
				if server.online_requested():
					server.apply_host_command("online", false)
				_screen.get_tree().change_scene_to_file(REMOTE_CLIENT_SCENE)
				return
	refresh()

func _note_start_blocked() -> void:
	var server: Object = _screen._server
	var last_args: Array = _screen._last_lobby_args
	var min_players: int = int(last_args[1]) if last_args.size() > 1 else 2
	var claimed: Array[int] = server.claimed_slots()
	var held: int = 0
	for slot: int in claimed:
		if not server.slot_has_controller(slot):
			held += 1
	var notice: String = ""
	if claimed.size() < min_players:
		notice = _screen.tr("LOBBY_START_NEED_PLAYERS") % [claimed.size(), min_players]
	elif held > 0:
		notice = _screen.tr("LOBBY_START_HELD_SEAT") % held
	elif not last_args.is_empty() and bool(last_args[0].get("teams", false)) and not _screen.both_teams_manned(last_args[0]):
		notice = _screen.tr("LOBBY_BOTH_TEAMS_NEED_PLAYER")
	if notice.is_empty():
		return
	start_notice = notice
	start_notice_until_msec = Time.get_ticks_msec() + START_NOTICE_MSEC
	_screen._lobby_status.text = notice

func _can_join_online() -> bool:
	var server: Object = _screen._server
	if server == null or not server.has_method("claimed_slots"):
		return false
	var own: Array[int] = [server.host_pc_slot()]
	if server.has_method("virtual_slots"):
		own.append_array(server.virtual_slots())
	for slot: int in server.claimed_slots():
		if not own.has(slot):
			return false
	return true

## Redraws the controls' captions from the server: the link state and the
## room code beside the toggle, and why Join is off when it is.
func refresh() -> void:
	var server: Object = _screen._server
	if server == null:
		return
	var status: String = server.online_status()
	var code: String = server.online_room_code()
	control_button("online").text = _screen.tr("HOST_MATCH_KIND_STATE") % TitleScreenScript.match_kind_text(server)
	_online_status.text = {"connecting": _screen.tr("ONLINE_CONNECTING"), "online": _screen.tr("ONLINE_ONLINE"), "unreachable": _screen.tr("ONLINE_UNREACHABLE")}.get(status, "")
	_room_label.text = _screen.tr("ONLINE_ROOM") % code
	_room_label.visible = code != "" and not (server.has_method("room_code_hidden") and server.room_code_hidden())
	# The code says "online" already; the status stays for connecting or a blip.
	_online_status.visible = not (_room_label.visible and status == "online")
	_screen._apply_streamer_mode(server)
	_screen._title_screen.refresh_kind_notice()
	control_button("mode").text = _screen.tr("HOST_MODE_STATE") % (_screen.tr("MODE_TEAMS") if server.team_mode() else _screen.tr("MODE_FFA"))
	control_button("bots").text = _screen.tr("HOST_BOTS_STATE") % server.bot_director.bot_count()
	control_button("join").disabled = not _can_join_online()
	_sync_host_picker()
	_join_blocked.visible = control_button("join").disabled
	# No keyboard glyph while a gamepad is the active input (#368).
	control_button("start").text = _screen.tr("HOST_START_MATCH_PAD") if _pad_active else _screen.tr("HOST_START_MATCH")
	if server.has_method("pc_runs_room") and server.pc_runs_room() != _screen._rows_have_kick and not _screen._last_lobby_args.is_empty():
		_screen.refresh_lobby.callv(_screen._last_lobby_args) # Kick on the rows (#458)

func process() -> void:
	var lobby_panel: Control = _screen._lobby_panel
	if _screen._server != null and lobby_panel != null and lobby_panel.visible:
		refresh()
	elif _pad_menu_open:
		set_pad_menu(false) # the lobby went away under the open menu

## Issue #441: the host PC's own seat picks hat, colour and eyes on the same mouse
## panel an Online client gets, in the QR's place (the mode cards give way too). It saves the pick in the
## host's own settings; the server puts it on the seat at claim.
func host_picker() -> Control:
	return _host_picker

func _sync_host_picker() -> void:
	var server: Object = _screen._server
	var seat: int = server.host_pc_slot() if server.has_method("host_pc_slot") else -1
	var show: bool = server.has_method("host_picker_shown") and server.host_picker_shown()
	if show and _host_picker == null:
		_host_picker = preload("res://scripts/OnlineCosmeticsPanel.gd").new()
		_host_picker.name = "HostPicker"
		_screen._lobby_right.add_child(_host_picker) # where the QR is in a Couch lobby
		_screen._lobby_right.move_child(_host_picker, 0)
		_host_picker.set_compact(true)
	if show and _host_picker.own_slot != seat:
		_host_picker.bind_server(server, seat)
		if not _host_picker.picked.is_connected(_save_host_pick):
			_host_picker.picked.connect(_save_host_pick) # after the server has applied the pick
	if _host_picker != null:
		_host_picker.visible = show
		_screen._mode_grid.visible = not show # the room the panel needs; the cards come back with the QR

func _save_host_pick(kind: String, _value: Variant) -> void:
	var server: Object = _screen._server
	var slot: int = server.host_pc_slot()
	var settings: RefCounted = preload("res://scripts/HostSettings.gd").shared()
	# #545: only a colour pick fixes the colour; the seat's automatic one stays automatic.
	var color: int = server.slot_color(slot) if kind == "color" else int(settings.cosmetic_pick.get("color", -1))
	settings.set_cosmetic_pick({"hat": server.slot_hat(slot), "eyes": server.slot_eyes(slot), "color": color})

# --- Gamepad host menu (#368, Steam Deck) ------------------------------------------

## Whether the last input was a gamepad's, which decides the captions' glyphs.
func pad_active() -> bool:
	return _pad_active

func pad_menu_open() -> bool:
	return _pad_menu_open

func input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_pad_active = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_pad_active = false
	var lobby_panel: Control = _screen._lobby_panel
	if _screen._server == null or lobby_panel == null or not lobby_panel.visible or _screen.title_visible():
		return
	if PadMenuScript.pressed(event, JOY_BUTTON_Y):
		set_pad_menu(not _pad_menu_open)
		_screen.get_viewport().set_input_as_handled()
	elif _pad_menu_open and PadMenuScript.pressed(event, JOY_BUTTON_B):
		set_pad_menu(false)
		_screen.get_viewport().set_input_as_handled()

## Explicit D-pad links: down the column, with First-to's minus and plus side
## by side. Geometric neighbours skip the small minus button.
func _chain_pad_focus() -> void:
	var column: Array[String] = ["join", "online", "mode", "bots", "target_down"]
	var buttons: Array[Button] = []
	for id: String in column:
		buttons.append(_controls[id])
	for i in column.size():
		if i > 0:
			buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[i - 1])
		if i < column.size() - 1:
			buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[i + 1])
	var down: Button = _controls["target_down"]
	var up: Button = _controls["target_up"]
	down.focus_neighbor_right = down.get_path_to(up)
	up.focus_neighbor_left = up.get_path_to(down)
	up.focus_neighbor_top = up.get_path_to(_controls["bots"])
	# Start sits right of the plus (#425): left goes back to it, up to Mode.
	# Join heads the column now, so the bottom row has nothing below it.
	var start: Button = _controls["start"]
	up.focus_neighbor_right = up.get_path_to(start)
	start.focus_neighbor_left = start.get_path_to(up)
	start.focus_neighbor_top = start.get_path_to(_controls["bots"])

## Opens or closes the gamepad-driven host menu: the lobby control buttons
## become focusable and take focus (first enabled one), or give it back.
func set_pad_menu(on: bool) -> void:
	if on == _pad_menu_open or _screen._server == null:
		return
	_pad_menu_open = on
	PadMenuScript.set_open("lobby", on)
	for id: String in _controls:
		(_controls[id] as Button).focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	if on:
		_chain_pad_focus()
		for id: String in PAD_ORDER:
			var button: Button = _controls[id]
			if not button.disabled:
				button.grab_focus()
				break
	else:
		var focused: Control = _screen.get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()

## Join swaps Main for the PC client under an open pad menu: let go of
## PadMenu on the way out, or the seat code would ignore A and B from then on.
func exit_tree() -> void:
	if _pad_menu_open:
		_pad_menu_open = false
		PadMenuScript.set_open("lobby", false)
	PadMenuScript.set_open("title", false)

func unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var lobby_panel: Control = _screen._lobby_panel
	if _screen._server == null or key == null or not key.pressed or key.echo or lobby_panel == null or not lobby_panel.visible:
		return
	if _screen.title_visible():
		for kind: String in TitleScreenScript.TITLE_KEYS:
			if key.physical_keycode == TitleScreenScript.TITLE_KEYS[kind]:
				_screen.press_title(kind)
				_screen.get_viewport().set_input_as_handled()
		return
	for id: String in CONTROL_KEYS:
		if key.physical_keycode == CONTROL_KEYS[id] or (id == "start" and key.physical_keycode == KEY_KP_ENTER):
			press_control(id)
			_screen.get_viewport().set_input_as_handled()
			return
