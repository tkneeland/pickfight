extends RefCounted

## The host-screen lobby controls (#239), the gamepad host menu (#368) and the
## host PC's own cosmetics picker (#441), split out of `LobbyScreen.gd` (#543).
##
## For a PC-only match with no phone: clickable buttons and keys for the match
## kind (C, O and S: the Couch / Online / Solo switch in the top bar, #435), the
## Host panel (the mode's target with - and = , Bots with B, Teams with T), Join
## someone's game (J, Online only), How to play, Your look and Start (Enter) (#547).
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
const UiThemeScript := preload("res://scripts/UiTheme.gd")

const CONTROL_KEYS: Dictionary = {
	"local": KEY_C, "online": KEY_O, "solo": KEY_S, "mode": KEY_T, "bots": KEY_B, "target_down": KEY_MINUS,
	"target_up": KEY_EQUAL, "start": KEY_ENTER, "join": KEY_J,
}
const KIND_IDS: Array[String] = ["local", "online", "solo"] # the switch's cells, left to right
const CONTROL_BUTTON_FONT_SIZE: int = 22 # was 26 (#425); still above DECK_MIN_FONT_SIZE
## The big online room code on the join card (the mockup's 96 px, outlined).
const ROOM_CODE_FONT_SIZE: int = 96
const STEP_BUTTON_PX: float = 44.0
const REMOTE_CLIENT_SCENE: String = "res://scenes/RemoteClient.tscn"
## #545: Start pressed with the lobby's conditions unmet used to do nothing and
## say nothing. The reason shows in the status line for a few seconds.
const START_NOTICE_MSEC: int = 4000
const PAD_ORDER: Array[String] = ["online", "local", "solo", "mode", "bots", "target_down", "target_up", "start", "join"] # focus lands on the match kind first, where Go online was

var _screen # the LobbyScreen
var _controls: Dictionary = {}
var _room_label: Label
var _online_status: Label
var _join_blocked: Label

var start_notice: String = ""
var start_notice_until_msec: int = 0

var _host_picker: Control = null
var _mode_buttons: Dictionary = {} # game mode id -> the card's flat click Button
var _target_label: Label
var _target_value: Label
var _target_kind: String = "first_to"
var _target_number: int = 5
var _start_ready: bool = false
var _kind_cells: Dictionary = {} # "local" / "online" / "solo" -> Button
var _focus_signature: String = ""

var _pad_active: bool = false
var _pad_menu_open: bool = false

func _init(screen) -> void:
	_screen = screen

## Builds the controls (once) and points them at `server`. A server without
## `apply_host_command` (a test stub) gets none.
func attach(server: Object) -> void:
	var lobby_right: VBoxContainer = _screen._lobby_right
	if lobby_right == null or _screen._server != null or server == null or not server.has_method("apply_host_command"):
		return
	_screen._server = server
	_build_kind_switch()
	_build_room_widgets()
	_build_host_panel(lobby_right)
	var look: Button = _action_button("look", _screen.tr("PICKER_TITLE"), UiThemeScript.SKY_BUTTON)
	lobby_right.add_child(look)
	lobby_right.add_child(_action_button("how_to_play", _screen.tr("HOW_TO_PLAY_BUTTON"), UiThemeScript.PINK_BUTTON))
	# Stages & Rules (#647): the host's own button and the summary above it, in the pad menu too.
	var stages: Button = _screen._stages_button
	stages.visible = true
	stages.pressed.connect(press_control.bind("stages_rules"))
	_controls["stages_rules"] = stages
	lobby_right.move_child(_screen._stages_box, lobby_right.get_child_count() - 1)
	# The way into someone else's room code (Online only), with why it is off when it is.
	lobby_right.add_child(_action_button("join", _screen.tr("HOST_JOIN_ONLINE"), UiThemeScript.ACTION_BUTTON))
	_join_blocked = ScreenKitScript.themed_label(_screen.tr("HOST_JOIN_BLOCKED"), ScreenKitScript.DECK_MIN_FONT_SIZE, UiThemeScript.MUTED_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_join_blocked.name = "JoinBlocked"
	_join_blocked.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_blocked.visible = false
	lobby_right.add_child(_join_blocked)
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lobby_right.add_child(spacer)
	var start_button: Button = ScreenKitScript.themed_button(_screen.tr("HOST_START_MATCH"), UiThemeScript.START_BUTTON_OFF, "start")
	start_button.pressed.connect(press_control.bind("start"))
	_controls["start"] = start_button
	lobby_right.add_child(start_button)
	lobby_right.move_child(_screen._lobby_status, lobby_right.get_child_count() - 1) # the hint under START
	var pad_hint := ScreenKitScript.themed_label(_screen.tr("HOST_GAMEPAD_HINT"), ScreenKitScript.DECK_MIN_FONT_SIZE, &"", HORIZONTAL_ALIGNMENT_CENTER)
	pad_hint.name = "GamepadHint"
	pad_hint.add_theme_color_override("font_color", Color("8F96BD"))
	pad_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	pad_hint.offset_top = -30.0
	pad_hint.offset_bottom = -8.0
	_screen._lobby_panel.add_child(pad_hint)
	_pad_active = not Input.get_connected_joypads().is_empty()
	_screen._title_screen.build()
	_place_kind_notice()
	refresh()

## The top-left Couch / Online / Solo switch (#435): one cream frame, three cells
## split by ink rules, the picked one yellow. C, O and S press them too.
func _build_kind_switch() -> void:
	var frame := PanelContainer.new()
	frame.name = "KindSwitch"
	frame.theme_type_variation = UiThemeScript.SWITCH_FRAME
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_screen._top_left.add_child(frame)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 0)
	frame.add_child(cells)
	var labels: Dictionary = {"local": "MATCH_COUCH", "online": "MATCH_ONLINE", "solo": "MATCH_SOLO"}
	for i in KIND_IDS.size():
		var id: String = KIND_IDS[i]
		if i > 0:
			var rule := ColorRect.new()
			rule.color = UiThemeScript.INK
			rule.custom_minimum_size = Vector2(4, 0)
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cells.add_child(rule)
		var cell: Button = ScreenKitScript.themed_button(_screen.tr(labels[id]), UiThemeScript.SEG_BUTTON, id)
		cell.pressed.connect(press_control.bind(id))
		_controls[id] = cell
		_kind_cells[id] = cell
		cells.add_child(cell)

## The big room code and its link status, on the join card (Online).
func _build_room_widgets() -> void:
	var box: VBoxContainer = _screen._join_box
	_room_label = ScreenKitScript.themed_label("", ROOM_CODE_FONT_SIZE, UiThemeScript.HEADING_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_room_label.name = "RoomCode"
	_room_label.add_theme_color_override("font_color", UiThemeScript.BLUE)
	_room_label.add_theme_color_override("font_outline_color", UiThemeScript.INK)
	_room_label.add_theme_constant_override("outline_size", 12)
	_room_label.visible = false
	box.add_child(_room_label)
	_online_status = ScreenKitScript.themed_label("", 22, UiThemeScript.INK_BOLD_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_online_status.name = "OnlineStatus"
	box.add_child(_online_status)
	box.move_child(_room_label, _screen._join_note.get_index())
	box.move_child(_online_status, _screen._join_note.get_index())

## The Host panel: the mode's target (First to / Lives / Goals to win / Captures
## to win), Bots and Teams, each a stepper or a switch (#547).
func _build_host_panel(parent: Control) -> void:
	var card := PanelContainer.new()
	card.name = "HostPanel"
	card.theme_type_variation = UiThemeScript.CARD_PANEL
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	box.add_child(ScreenKitScript.themed_label(_screen.tr("LOBBY_HOST_TITLE"), 28, UiThemeScript.INK_HEADING_LABEL))
	_target_label = ScreenKitScript.themed_label(_screen.tr("LOBBY_ROW_FIRST_TO"), 22, UiThemeScript.INK_BOLD_LABEL)
	_target_label.name = "TargetLabel"
	_target_value = ScreenKitScript.themed_label("5", 34, UiThemeScript.INK_HEADING_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_target_value.name = "TargetValue"
	_target_value.custom_minimum_size.x = 40.0
	box.add_child(_stepper_row(_target_label, _step_button("target_down", "-"), _target_value, _step_button("target_up", "+")))
	var bots_count: Button = ScreenKitScript.themed_button("0", UiThemeScript.VALUE_BUTTON, "bots")
	bots_count.custom_minimum_size = Vector2(40, STEP_BUTTON_PX)
	bots_count.pressed.connect(press_control.bind("bots"))
	_controls["bots"] = bots_count
	box.add_child(_stepper_row(ScreenKitScript.themed_label(_screen.tr("LOBBY_ROW_BOTS"), 22, UiThemeScript.INK_BOLD_LABEL),
		_step_button("bots_down", "-"), bots_count, _step_button("bots_up", "+")))
	var teams_row := HBoxContainer.new()
	teams_row.add_theme_constant_override("separation", 10)
	var teams_label: Label = ScreenKitScript.themed_label(_screen.tr("LOBBY_ROW_TEAMS"), 22, UiThemeScript.INK_BOLD_LABEL)
	teams_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teams_row.add_child(teams_label)
	var teams: Button = ScreenKitScript.themed_button(_screen.tr("LOBBY_OFF"), UiThemeScript.SWITCH_BUTTON, "mode")
	teams.custom_minimum_size.x = 84.0
	teams.pressed.connect(press_control.bind("mode"))
	_controls["mode"] = teams
	teams_row.add_child(teams)
	box.add_child(teams_row)

func _step_button(id: String, text: String) -> Button:
	var button: Button = ScreenKitScript.themed_button(text, UiThemeScript.STEP_BUTTON, id)
	button.custom_minimum_size = Vector2(STEP_BUTTON_PX, STEP_BUTTON_PX)
	button.pressed.connect(press_control.bind(id))
	_controls[id] = button
	return button

func _stepper_row(label: Label, less: Button, value: Control, more: Button) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	row.add_child(less)
	row.add_child(value)
	row.add_child(more)
	return row

func _action_button(id: String, text: String, variation: StringName) -> Button:
	var button: Button = ScreenKitScript.themed_button(text, variation, id)
	button.pressed.connect(press_control.bind(id))
	_controls[id] = button
	return button

## The "N players left" notice the title screen owns sits under the top bar now,
## not over the wordmark.
func _place_kind_notice() -> void:
	var notice: Node = _screen._lobby_panel.find_child("KindNotice", true, false)
	if notice is Control:
		(notice as Control).offset_top = 112.0

## A mode card's flat click Button, so the gamepad menu can focus it.
func register_mode_button(id: String, button: Button) -> void:
	_mode_buttons[id] = button
	_controls["mode_" + (id if id != "" else "classic")] = button

## What a click on a game mode card does: pick the mode, switching Teams on or
## off first when the mode only plays in the other format.
func press_game_mode(id: String) -> void:
	var server: Object = _screen._server
	if server == null or not server.has_method("game_mode") or id == "\u0001":
		return
	if not preload("res://scripts/GameModes.gd").fits_format(id, server.team_mode()):
		server.apply_host_command("mode", "ffa" if server.team_mode() else "teams")
	server.apply_host_command("gamemode", id)
	refresh()

## The Host panel's target row follows the mode: its label and value.
func set_target(kind: String, value: int) -> void:
	_target_kind = kind
	_target_number = value
	if _target_label != null:
		_target_label.text = _screen.tr(preload("res://scripts/GameModes.gd").target_row_key(kind))
		_target_value.text = str(value)

## Whether START is lit: every human ready and the lobby able to start.
func set_start_ready(on: bool) -> void:
	_start_ready = on

## The control button `id` ("local", "online", "solo", "mode", "bots", "bots_down",
## "bots_up", "target_down", "target_up", "look", "how_to_play", "join", "start"), or null.
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
		"local", "online", "solo":
			# #435: Couch, Online or Solo. Online opens the room; Solo stays off the relay (#522).
			if _kind_of(server) != id:
				server.apply_host_command("kind", id)
		"mode":
			server.apply_host_command("mode", "ffa" if server.team_mode() else "teams")
		"bots":
			# #445: one more bot, back to none after the last free seat.
			var count: int = server.bot_director.bot_count()
			server.apply_host_command("bots", count + 1 if count < server.bot_capacity() else 0)
		"bots_down":
			server.apply_host_command("bots", maxi(0, server.bot_director.bot_count() - 1))
		"bots_up":
			server.apply_host_command("bots", mini(server.bot_capacity(), server.bot_director.bot_count() + 1))
		"target_down":
			server.apply_host_command("target", server.mode_target() - 1)
		"target_up":
			server.apply_host_command("target", server.mode_target() + 1)
		"start":
			if server.apply_host_command("start"):
				_note_start_blocked()
		"look":
			if server.has_method("host_picker_shown") and server.host_picker_shown():
				_popup_opener = id
				_screen.set_popup("look")
		"stages_rules":
			_popup_opener = id
			_screen.open_stages_rules()
		"how_to_play":
			_popup_opener = id
			_screen.set_popup("help")
		"join":
			# Issue #241: leave this host's lobby for the PC client's join
			# screen. Online only (#547), and only while nobody but the host's
			# own seat (and bots) is in it, so a click cannot end a match
			# someone is in. An open room is closed on the way out.
			if _kind_of(server) == "online" and _can_join_online():
				if server.online_requested():
					server.apply_host_command("online", false)
				_screen.get_tree().change_scene_to_file(REMOTE_CLIENT_SCENE)
				return
	refresh()

## The match kind as the switch reads it: "local" until the host picks one.
func _kind_of(server: Object) -> String:
	var kind: String = server.match_kind() if server.has_method("match_kind") else ""
	return "local" if kind == "" else kind

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
	var kind: String = _kind_of(server)
	for id: String in KIND_IDS:
		_set_variation(_kind_cells[id], UiThemeScript.SEG_BUTTON_ON if id == kind else UiThemeScript.SEG_BUTTON)
	_online_status.text = {"connecting": _screen.tr("ONLINE_CONNECTING"), "unreachable": _screen.tr("ONLINE_UNREACHABLE")}.get(status, "")
	_room_label.text = code
	_room_label.visible = code != "" and not (server.has_method("room_code_hidden") and server.room_code_hidden())
	# The code says "online" already; the status stays for connecting or a blip.
	_online_status.visible = _online_status.text != "" and kind == "online"
	_screen._apply_streamer_mode(server)
	_screen._title_screen.refresh_kind_notice()
	var teams_on: bool = server.team_mode()
	control_button("mode").text = _screen.tr("LOBBY_ON") if teams_on else _screen.tr("LOBBY_OFF")
	_set_variation(control_button("mode"), UiThemeScript.SWITCH_BUTTON_ON if teams_on else UiThemeScript.SWITCH_BUTTON)
	control_button("bots").text = str(server.bot_director.bot_count())
	var join: Button = control_button("join")
	join.disabled = not _can_join_online()
	join.visible = kind == "online"
	_sync_host_picker()
	_join_blocked.visible = join.visible and join.disabled
	var start: Button = control_button("start")
	# No keyboard glyph while a gamepad is the active input (#368).
	start.text = _screen.tr("HOST_START_MATCH") if _start_ready else _screen.tr("HOST_START_WAITING")
	join.text = _screen.tr("HOST_JOIN_ONLINE_PAD") if _pad_active else _screen.tr("HOST_JOIN_ONLINE")
	_set_variation(start, UiThemeScript.START_BUTTON if _start_ready else UiThemeScript.START_BUTTON_OFF)
	if _pad_menu_open:
		_chain_pad_focus()
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
		_host_picker = _screen._popups.look_panel() # the Your look popup's panel (#547)
	if show and _host_picker.own_slot != seat:
		_host_picker.bind_server(server, seat)
		if not _host_picker.picked.is_connected(_save_host_pick):
			_host_picker.picked.connect(_save_host_pick) # after the server has applied the pick
	if _host_picker != null:
		_host_picker.visible = show
	control_button("look").visible = show
	if not show and _screen.popup_open() == "look":
		_screen.set_popup("")

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
	var popup: String = _screen.popup_open()
	var key := event as InputEventKey
	if popup == "stages" and key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		# Esc closes just this screen, never the Settings panel behind it; it stays up with a mode on no stage (#647)
		if _screen.request_close_popup():
			_restore_focus_after_popup()
		_screen.get_viewport().set_input_as_handled()
	elif popup == "stages" and _screen.stages_rules().handle_pad(event):
		_screen.get_viewport().set_input_as_handled() # LB / RB step the tabs
	elif PadMenuScript.pressed(event, JOY_BUTTON_B) and popup != "":
		if _screen.request_close_popup(): # B leaves a popup first, then the menu
			_restore_focus_after_popup()
		_screen.get_viewport().set_input_as_handled()
	elif PadMenuScript.pressed(event, JOY_BUTTON_Y) and popup == "":
		set_pad_menu(not _pad_menu_open)
		_screen.get_viewport().set_input_as_handled()
	elif _pad_menu_open and PadMenuScript.pressed(event, JOY_BUTTON_B):
		set_pad_menu(false)
		_screen.get_viewport().set_input_as_handled()

## Explicit D-pad links (#368, #547). The Host panel and the buttons under it
## are rows: left and right along a row, up and down between rows. The switch
## runs along the top, and the mode cards form a 2-column grid; the right edge of
## the top bar and of the cards leads into the Host panel, so every control is
## reachable. Hidden controls (Join outside Online) are skipped.
func _chain_pad_focus() -> void:
	var rows: Array = []
	for ids: Array in [["target_down", "target_up"], ["bots_down", "bots", "bots_up"], ["mode"], ["look"], ["how_to_play"], ["stages_rules"], ["join"], ["start"]]:
		var row: Array[Button] = []
		for id: String in ids:
			var button: Button = _controls[id]
			if button.is_visible_in_tree():
				row.append(button)
		if not row.is_empty():
			rows.append(row)
	var signature: String = ""
	for row: Array in rows:
		for button: Button in row:
			signature += str(button.name) + ","
		signature += "|"
	if signature == _focus_signature:
		return
	_focus_signature = signature
	for r in rows.size():
		var row: Array = rows[r]
		for c in row.size():
			var button: Button = row[c]
			_link(button, SIDE_LEFT, row[c - 1] if c > 0 else null)
			_link(button, SIDE_RIGHT, row[c + 1] if c < row.size() - 1 else null)
			_link(button, SIDE_TOP, rows[r - 1][mini(c, rows[r - 1].size() - 1)] if r > 0 else null)
			_link(button, SIDE_BOTTOM, rows[r + 1][mini(c, rows[r + 1].size() - 1)] if r < rows.size() - 1 else null)
	# The top bar's switch: along, down to the mode cards, and over into the Host panel.
	var cards: Array[Button] = []
	for row_dict: Dictionary in preload("res://scripts/GameModes.gd").picker_rows():
		cards.append(_mode_buttons[str(row_dict["id"])])
	var first_target: Button = rows[0][0] if not rows.is_empty() else null
	for i in KIND_IDS.size():
		var cell: Button = _kind_cells[KIND_IDS[i]]
		_link(cell, SIDE_LEFT, _kind_cells[KIND_IDS[i - 1]] if i > 0 else null)
		_link(cell, SIDE_RIGHT, _kind_cells[KIND_IDS[i + 1]] if i < KIND_IDS.size() - 1 else first_target)
		_link(cell, SIDE_BOTTOM, cards[mini(i, cards.size() - 1)] if not cards.is_empty() else null)
	for i in cards.size():
		_link(cards[i], SIDE_LEFT, cards[i - 1] if i % 2 == 1 else null)
		_link(cards[i], SIDE_RIGHT, cards[i + 1] if i % 2 == 0 and i + 1 < cards.size() else first_target)
		_link(cards[i], SIDE_TOP, cards[i - 2] if i >= 2 else _kind_cells[KIND_IDS[mini(i, KIND_IDS.size() - 1)]])
		_link(cards[i], SIDE_BOTTOM, cards[i + 2] if i + 2 < cards.size() else null)
	if first_target != null and not cards.is_empty():
		_link(first_target, SIDE_LEFT, cards[0])

## Points `button`'s focus neighbour on `side` at `target`, or back to Godot's own search for null.
func _link(button: Button, side: Side, target: Control) -> void:
	var path: NodePath = button.get_path_to(target) if target != null else NodePath()
	match side:
		SIDE_LEFT:
			button.focus_neighbor_left = path
		SIDE_RIGHT:
			button.focus_neighbor_right = path
		SIDE_TOP:
			button.focus_neighbor_top = path
		SIDE_BOTTOM:
			button.focus_neighbor_bottom = path

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
		_focus_signature = ""
		_chain_pad_focus()
		var first: String = _kind_of(_screen._server)
		for id: String in [first] + PAD_ORDER:
			var button: Button = _controls[id]
			if not button.disabled and button.is_visible_in_tree():
				button.grab_focus()
				break
	else:
		var focused: Control = _screen.get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()

## Sets a button's theme variation only when it changes (it costs a theme lookup).
static func _set_variation(button: Control, variation: StringName) -> void:
	if button.theme_type_variation != variation:
		button.theme_type_variation = variation

## After a popup closes under an open gamepad menu, focus goes back to the control that opened it.
func _restore_focus_after_popup() -> void:
	if not _pad_menu_open:
		return
	var back: Button = _controls.get(_popup_opener) as Button
	if back != null and back.is_visible_in_tree():
		back.grab_focus()

var _popup_opener: String = "how_to_play"

## Join swaps Main for the PC client under an open pad menu: let go of
## PadMenu on the way out, or the seat code would ignore A and B from then on.
func exit_tree() -> void:
	if _pad_menu_open:
		_pad_menu_open = false
		PadMenuScript.set_open("lobby", false)
	PadMenuScript.set_open("title", false)
	PadMenuScript.set_open("lobby_popup", false)

func unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var lobby_panel: Control = _screen._lobby_panel
	if _screen._server == null or key == null or not key.pressed or key.echo or lobby_panel == null or not lobby_panel.visible:
		return
	if _screen.popup_open() != "":
		return # a popup is up: the lobby's keys wait
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
