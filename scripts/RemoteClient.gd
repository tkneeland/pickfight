extends Node2D
## The PC client (issue #241, #212): joins a host's match through the room-code
## relay, drives its arm with the captured mouse, and draws the host's match from
## the snapshot stream. The host is the only simulation (ADR-0001); this never
## runs gameplay physics, only draws puppets.
##
## Wire (relay/Relay.gd, ControllerServer.gd, issue #239):
##   - the first TEXT frame is {"t":"join","room":CODE}; the relay answers a TEXT
##     {"t":"welcome","peer":N} or {"t":"error","reason":...} and then closes;
##   - every frame after that is BINARY, `[kind byte][payload]`: KIND_INPUT is a
##     phone's 8-byte input frame (float32 x, float32 y, little-endian), KIND_TEXT
##     a UTF-8 JSON message (the relay drops a client's TEXT frames, so the hello
##     and every message go as KIND_TEXT binary), KIND_SNAPSHOT (host to client)
##     a `Snapshot.encode()` frame plus a sound trailer (SnapshotCapture.gd);
##   - after the welcome the client sends {"id":<client id>,"proto":1}; the host
##     answers {"slot":N,"id":...}, then lobby messages, or {"t":"error",
##     "reason":"version"} / {"t":"closed",...} and drops the seat.
## Input is the mouse as a phone-drag vector (ADR-0003, HostMouse.gd), sent every
## physics tick, (0,0) included, or the host times the seat out.
## No `class_name`: consumers preload this by path.

const SnapshotScript: GDScript = preload("res://scripts/Snapshot.gd")
const SnapshotCaptureScript: GDScript = preload("res://scripts/SnapshotCapture.gd")
const HostMouseScript: GDScript = preload("res://scripts/HostMouse.gd")
const CareerScript: GDScript = preload("res://scripts/Career.gd")
const RelayLinkScript: GDScript = preload("res://scripts/RelayLink.gd")
const ControllerServerScript: GDScript = preload("res://scripts/ControllerServer.gd")
const PuppetScript: GDScript = preload("res://scripts/RemotePuppet.gd")
const PaletteScript: GDScript = preload("res://scripts/Palette.gd")
const PickupWeaponsScript: GDScript = preload("res://scripts/PickupWeapons.gd")
const TeamsScript: GDScript = preload("res://scripts/Teams.gd")
const StageScript: GDScript = preload("res://scripts/Stage.gd")
const CosmeticsPickerScript: GDScript = preload("res://scripts/CosmeticsPicker.gd")
const CosmeticsPanelScript: GDScript = preload("res://scripts/OnlineCosmeticsPanel.gd")
const UiThemeScript: GDScript = preload("res://scripts/UiTheme.gd")
const CopyCodeScript: GDScript = preload("res://scripts/CopyCode.gd")
const DemoBuildScript := preload("res://scripts/DemoBuild.gd")
const NetSyncScript: GDScript = preload("res://scripts/NetSync.gd")
## Issue #976: the host's effects, screens and HUD, drawn by the host's scripts.
const RemoteEffectsScript: GDScript = preload("res://scripts/RemoteEffects.gd")
const PickupDirectorScript := preload("res://scripts/PickupDirector.gd")
const RemoteHudScript: GDScript = preload("res://scripts/RemoteHud.gd")
const UiMirrorScript: GDScript = preload("res://scripts/UiMirror.gd")
const ModifierBannerScript: GDScript = preload("res://scripts/ModifierBanner.gd")
const HostHudScene: PackedScene = preload("res://scenes/HostHud.tscn")

const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"
## Room-code alphabet and length: Relay.CODE_LETTERS (no I and no O) / CODE_LENGTH.
const CODE_LETTERS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ"
const CODE_LENGTH: int = 4
const NAME_MAX_LENGTH: int = ControllerServerScript.MAX_NAME_LENGTH
## How long a join may take before the client gives up, msec.
const JOIN_TIMEOUT_MSEC: int = 8000
## How far behind the newest snapshot the puppets are drawn, msec.
const INTERP_MSEC: int = 100
const SAMPLE_KEEP_MSEC: int = 1500
const MAX_SAMPLES: int = 90
const DEFAULT_SETTINGS_PATH: String = "user://remote_client.cfg"
const SECTION: String = "remote_client"
## Round phases the snapshot carries (RoundManager.State) that show the stage.
const PHASE_ROUND_ACTIVE: int = 1
const PHASE_ROUND_END: int = 2

enum State { JOIN, CONNECTING, PLAYING }
enum Phase { OPENING, JOINING, HELLO }

signal state_changed(state: int)
## Cancel or Esc on the idle join screen: the host heads back to the title (#506).
signal back_requested

const MAIN_SCENE: String = "res://scenes/Main.tscn"

var state: int = State.JOIN
var relay_url: String = ""
## "" keeps the name and sensitivity in memory only (scenarios do this).
var settings_path: String = DEFAULT_SETTINGS_PATH
## Lifetime stats (#503). Defaults to `user://career.cfg` unless `settings_path`
## was emptied (scenarios, screenshot tools), which keeps these in memory too.
var career_path: String = ""
var career: Dictionary = {}
var _career_open: bool = false
var join_timeout_msec: int = JOIN_TIMEOUT_MSEC
var client_id: String = ""
var player_name: String = ""
## Sent in the hello; a scenario sets another to see a version mismatch refused.
var protocol_version: int = ControllerServerScript.PROTOCOL_VERSION
## Sent in the hello (#447): the host refuses a build that is not its own.
## A scenario sets it to try the other build against the same host.
var demo_build: bool = DemoBuildScript.is_active()
var room_code: String = ""
## #907: the last room this client got a seat in ("" when none, or once it was found dead).
var last_room_code: String = ""
var slot: int = -1
var peer_id: int = 0
var menu_open: bool = false
var mouse_captured: bool = false
var status_text: String = ""
var itch_url: String = ""
## The last TEXT message of each kind the host sent (lobby, looks).
var lobby: Dictionary = {}
## The host's last `hud` frame (issue #436): round result, board, mode HUD.
var hud: Dictionary = {}
## Snapshot frames applied since the page opened (full and delta).
var frames_applied: int = 0
var full_frames_applied: int = 0
## Sound events played from the stream, newest last (a scenario reads it).
var sounds_played: Array[String] = []
var last_track: String = ""
## The drag vector the next input frame carries.
var input_vector: Vector2 = Vector2.ZERO
var input_frames_sent: int = 0
## Issue #441: this player's hat, eyes and colour, saved in their own copy and
## sent on join ({"hat", "eyes", "color"}, see CosmeticsPicker.clean_pick).
var saved_pick: Dictionary = CosmeticsPickerScript.clean_pick({})
## Issue #441: the host's last full `looks` frame (palette, hats, eyes, looks).
var looks: Dictionary = {}
var _cosmetics_panel: Control

var _socket: WebSocketPeer = null
var _phase: int = Phase.OPENING
var _deadline_msec: int = 0
var _mouse: RefCounted = HostMouseScript.new()
var _world: Dictionary = {}
var _samples: Array[Dictionary] = []
var _stage_id: int = -1
var _stage: Node = null
var _puppets: Dictionary = {} # key (String) -> RemotePuppet
## Issue #976: stage part id -> node, and the state each was last given;
## the part ids the host named that the last walk of the stage did not find,
## and whether the stage gained nodes since (only then is it walked again);
## host prop id -> the client's copy.
var _part_nodes: Dictionary = {}
var _part_shown: Dictionary = {}
var _part_missing: Dictionary = {}
var _parts_dirty: bool = false
## How many times the stage was walked for its parts (scenarios).
var part_walks: int = 0
var _prop_nodes: Dictionary = {}
var _hud_signature: String = ""
## Issue #459: after a dropped connection mid-match the client rejoins by
## itself, every REJOIN_RETRY_MSEC, until the host's seat hold would have run
## out (wall clock here; the host counts it in game time). 0 when not rejoining.
const REJOIN_RETRY_MSEC: int = 1500
var _rejoin_until_msec: int = 0
var _rejoin_next_msec: int = 0
## Issue #579: a client with no snapshot for this long assumes the host's room is
## gone (a frozen world, its own input keeping the relay awake) and rejoins.
const SNAPSHOT_WATCHDOG_MSEC: int = 5000
var _last_snapshot_msec: int = 0

var _camera: Camera2D
var _world_root: Node2D
var _stage_holder: Node2D
var _puppet_holder: Node2D
var _prop_holder: Node2D
var _ui: CanvasLayer
var _join_panel: Control
var _room_edit: LineEdit
var _paste_button: Button
var _last_room_button: Button
var _code_hint: Label
## The clipboard read, a seam so the scenarios never touch the real clipboard (#906).
var clipboard_getter: Callable = func() -> String: return DisplayServer.clipboard_get()
var _name_edit: LineEdit
var _status_label: Label
var _join_button: Button
var _cancel_button: Button
var _update_link: LinkButton
var _hud: Control
## Issue #976: the host's own HUD scene (scores, scoreboard, join corner, kill
## feed), its modifier banner, and the effects player with its screens.
var _host_hud: CanvasLayer
var _modifier_label: Label
var effects: Node2D
var _last_round_phase: int = 0
var _ui_text: String = ""
var _stage_night: bool = false
## Pickup snapshot ids the host just popped in -> give-up time (msec).
var _pending_pops: Dictionary = {}
const POP_WAIT_MSEC: int = 1000
const NIGHT_PLAYER_GROUP: StringName = &"remote_players"
const NIGHT_PICKUP_GROUP: StringName = &"remote_pickups"
var _screens: Dictionary = {}
var _victory_text: String = ""
var _leave_button: Button
var _wait_label: Label
var _lobby_panel: Control
var _lobby_title: Label
var _career_button: Button
var _lobby_list: VBoxContainer
var _ready_button: Button
var _copy_button: Button # #1033: the joiner's Copy code, shared logic with the host's (#863)
var _copied_until_msec: int = 0
## The clipboard write, a seam so scenarios never touch the real clipboard.
var clipboard_setter: Callable = func(text: String) -> void: DisplayServer.clipboard_set(text)
var _ready_want: int = -1 # the clicked Ready (0/1) awaiting the host's echo, else -1 (#550)
var _ready_want_msec: int = 0
var _host_row: HBoxContainer
var _mode_button: Button
var _target_label: Label
var _menu_panel: Control
var _sens_slider: HSlider
var _pause_button: Button

# --- Pure helpers (scenarios and the join screen use these) --------------------

## `text` as a room code: upper case, only the relay's alphabet, at most
## CODE_LENGTH letters.
static func normalize_code(text: String) -> String:
	var out: String = ""
	for ch: String in text.to_upper():
		if CODE_LETTERS.contains(ch) and out.length() < CODE_LENGTH:
			out += ch
	return out

## #922: whether typing `text` into the room field dropped a character the
## player meant as part of the code (I, O, a digit, punctuation). Case, spaces
## and dashes are fine, and so is running past CODE_LENGTH letters.
static func code_text_drops_a_letter(text: String) -> bool:
	for ch: String in text.to_upper():
		if ch == " " or ch == "-":
			continue
		if not CODE_LETTERS.contains(ch):
			return true
	return false

## #906: the room code inside pasted `text` ("" when there is none). Takes the
## first whole word that is exactly CODE_LENGTH letters of the relay alphabet
## (any case, so "Join with code: abcd" works); failing that, a short text whose
## spaces or dashes only split the code ("ab cd") collapses to it.
static func code_from_text(text: String) -> String:
	var word: String = ""
	for ch: String in text.to_upper() + " ":
		if ch >= "A" and ch <= "Z":
			word += ch
			continue
		if word.length() == CODE_LENGTH and normalize_code(word) == word:
			return word
		word = ""
	var squeezed: String = text.strip_edges().replace(" ", "").replace("-", "").to_upper()
	if code_is_complete(squeezed):
		return squeezed
	return ""

static func code_is_complete(text: String) -> bool:
	return text.length() == CODE_LENGTH and normalize_code(text) == text

## The stage scenes' paths in the host's rotation order (stage_id indexes this),
## read off Main.tscn's RoundManager without instancing it.
static var _stage_paths: PackedStringArray = PackedStringArray()
static func stage_paths() -> PackedStringArray:
	if not _stage_paths.is_empty():
		return _stage_paths
	var main: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if main == null:
		return _stage_paths
	var scene_state: SceneState = main.get_state()
	for n in scene_state.get_node_count():
		for p in scene_state.get_node_property_count(n):
			if scene_state.get_node_property_name(n, p) == &"stage_scenes":
				for scene: Variant in scene_state.get_node_property_value(n, p):
					if scene is PackedScene:
						_stage_paths.append((scene as PackedScene).resource_path)
				return _stage_paths
	return _stage_paths

## A relay or host reason as a sentence for the join screen.
static func reason_text(reason: String) -> String:
	match reason:
		"bad_room":
			return TranslationServer.translate("JOIN_ERR_BAD_ROOM")
		"room_full":
			return TranslationServer.translate("JOIN_ERR_ROOM_FULL")
		"host_left":
			return TranslationServer.translate("JOIN_ERR_HOST_LEFT")
		"idle_timeout":
			return TranslationServer.translate("JOIN_ERR_IDLE")
		"version":
			return TranslationServer.translate("JOIN_ERR_VERSION")
		"full_only":
			return TranslationServer.translate("JOIN_ERR_FULL_ONLY")
		"demo_only":
			return TranslationServer.translate("JOIN_ERR_DEMO_ONLY")
		"removed by the host":
			return TranslationServer.translate("JOIN_ERR_REMOVED")
		"opened somewhere else":
			return TranslationServer.translate("JOIN_ERR_ELSEWHERE")
		"no free player slot":
			return TranslationServer.translate("JOIN_ERR_NO_SLOT")
		"no hello":
			return TranslationServer.translate("JOIN_ERR_NO_HELLO")
		"couch match", "room closed": # #435: ControllerServer.COUCH_MATCH_REASON, ROOM_CLOSED_REASON
			return TranslationServer.translate("JOIN_ERR_COUCH" if reason == "couch match" else "JOIN_ERR_ROOM_CLOSED")
	return TranslationServer.translate("JOIN_ERR_DISCONNECTED") % reason.left(60)

# --- Lifecycle -------------------------------------------------------------------

func _ready() -> void:
	if relay_url.is_empty():
		relay_url = ControllerServerScript.resolve_relay_url(OS.get_cmdline_user_args())
	itch_url = str(ProjectSettings.get_setting("pickfight/itch_url", ""))
	_load_settings()
	if career_path.is_empty() and settings_path == DEFAULT_SETTINGS_PATH:
		career_path = CareerScript.DEFAULT_PATH
	career = CareerScript.load_totals(career_path)
	if client_id.is_empty():
		client_id = _random_id()
		_save_settings()
	_build_world()
	_build_ui()
	_show_join_screen()
	get_viewport().size_changed.connect(_fit_camera)
	_listen_for_steam_invites()

## #298: a Steam friend's Join Game (launch arg or runtime) goes into the same
## join as a typed code. SteamPlatform has already validated the code.
func _listen_for_steam_invites() -> void:
	var steam: Node = get_node_or_null(^"/root/SteamPlatform")
	if steam == null:
		return
	steam.connect("join_requested", _on_steam_join_requested)
	var pending: String = str(steam.call("take_pending_join_code"))
	if not pending.is_empty():
		_on_steam_join_requested(pending)

func _on_steam_join_requested(code: String) -> void:
	if _room_edit != null:
		_room_edit.text = code
	join(code, _name_edit.text if _name_edit != null else player_name)

func _exit_tree() -> void:
	var steam: Node = get_node_or_null(^"/root/SteamPlatform")
	if steam != null and steam.is_connected("join_requested", _on_steam_join_requested):
		steam.disconnect("join_requested", _on_steam_join_requested)
	if _socket != null:
		_socket.close()
		_socket = null
	_set_captured(false)
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)

func _process(_delta: float) -> void:
	if _socket != null:
		_poll_socket()
	_tick_rejoin()
	_watch_snapshots()
	if state == State.PLAYING:
		_render()
		_track_heads()

func _physics_process(_delta: float) -> void:
	if state == State.PLAYING:
		_pad_input()
		_send_input()

## #435: a gamepad's right stick drives the arm too, as a gamepad seat's does on
## the host (#261). While the stick is out it sets the vector; let go, and the
## arm rests until the stick or the mouse moves again.
var test_pad_left_stick: Vector2 = Vector2.ZERO # #600: the left stick's stand-in
var test_pad_stick: Variant = null # a Vector2 here stands in for a real pad (headless has none)
var _pad_driving: bool = false
## Mouse px since the last input frame, for a KO'd seat's ghost (#660).
var _mouse_px_pending: Vector2 = Vector2.ZERO

func _pad_input() -> void:
	var stick := Vector2.ZERO
	if test_pad_stick is Vector2:
		stick = ControllerServerScript.pad_stick(test_pad_stick, test_pad_left_stick, ControllerServerScript.pad_deadzone())
	else:
		for device: int in Input.get_connected_joypads():
			stick = ControllerServerScript.pad_stick(Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)), Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)), ControllerServerScript.pad_deadzone())
			if stick != Vector2.ZERO:
				break
	if stick != Vector2.ZERO:
		input_vector = stick
		_pad_driving = true
	elif _pad_driving:
		_pad_driving = false
		_mouse.reset()
		input_vector = Vector2.ZERO

## Issue #463, ADR-0022: a mouse never lifts, so Space (tap) and the pad's stick
## clicks toggle "released" and a held shoulder button holds it. Sent as one
## extra byte on the input frame while set; the host clears the toggle at each
## respawn (`{"t":"release","v":false}`).
## Issue #481: action presses go out as byte 9 of the input frame: the low 7
## bits a wrapping count, bit 7 set when the latest press was a shoulder (a
## hold, which can throw the boomerang but never toggles release). The host
## decides whether a press throws the boomerang or toggles release.
## Issue #485: the count is of TAPS, and the client decides tap vs hold itself
## on key-up (down and up within TAP_MAX_SEC). A hold is not counted; instead
## byte 8 (the held flag) is set while a shoulder is down, or while Space / L3 /
## R3 has been down longer than TAP_MAX_SEC. Bit 7 marks a shoulder tap.
const TAP_MAX_SEC: float = 0.25
const GameClockScript: GDScript = preload("res://scripts/GameClock.gd")
var action_presses: int = 0
var _action_was_hold: bool = false
## Game-clock msec each non-shoulder action button (keycode or joypad button) went down.
var _action_down: Dictionary = {}
var _shoulder_down_msec: int = -1
var _pad_shoulder_held: bool = false

func _action_press(hold: bool) -> void:
	action_presses = (action_presses + 1) & 0x7F
	_action_was_hold = hold

func _tapped(down_msec: int) -> bool:
	return float(GameClockScript.now_msec() - down_msec) <= TAP_MAX_SEC * 1000.0

func input_released() -> bool:
	if _pad_shoulder_held:
		return true
	for down: int in _action_down.values():
		if not _tapped(down):
			return true
	return false

func _input(event: InputEvent) -> void:
	if state != State.PLAYING:
		var back := event as InputEventKey
		if back != null and back.pressed and not back.echo and back.physical_keycode == KEY_ESCAPE and _join_panel != null and _join_panel.is_visible_in_tree():
			var idle: bool = state == State.JOIN and not rejoining()
			cancel() # Esc does what the Cancel button does (#506)
			if not idle: # an idle back swaps the scene; do not starve a host sharing this tree of its Esc
				get_viewport().set_input_as_handled()
		return
	if _victory_input(event) or _replay_input(event):
		get_viewport().set_input_as_handled()
		return
	var pad_button := event as InputEventJoypadButton
	if pad_button != null and pad_button.pressed and not menu_open and (pad_button.button_index == JOY_BUTTON_A or pad_button.button_index == JOY_BUTTON_START) and _ready_button != null and _ready_button.is_visible_in_tree() \
			and not (pad_button.button_index == JOY_BUTTON_A and _copy_button != null and _copy_button.has_focus()):
		_ready_button.button_pressed = not _ready_button.button_pressed # A or Start readies in the lobby (#518)
		get_viewport().set_input_as_handled() # else a focused Ready also takes it as ui_accept and flips back (#550)
		return
	if pad_button != null and not menu_open:
		if pad_button.button_index == JOY_BUTTON_LEFT_SHOULDER or pad_button.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_pad_shoulder_held = pad_button.pressed
			if pad_button.pressed:
				_shoulder_down_msec = GameClockScript.now_msec()
			else:
				if _shoulder_down_msec != -1 and _tapped(_shoulder_down_msec):
					_action_press(true)
				_shoulder_down_msec = -1
		elif pad_button.button_index == JOY_BUTTON_LEFT_STICK or pad_button.button_index == JOY_BUTTON_RIGHT_STICK:
			_action_edge(pad_button.button_index, pad_button.pressed)
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if mouse_captured and not menu_open:
			mouse_motion(motion.relative)
		return
	var key := event as InputEventKey
	if key != null and key.physical_keycode == KEY_SPACE and not key.echo and (not key.pressed or not menu_open):
		_action_edge(-KEY_SPACE, key.pressed)
		if _ready_button != null and _ready_button.is_visible_in_tree() and _ready_button.has_focus():
			get_viewport().set_input_as_handled() # Space is the action key, not Ready's accept (#550)
		return
	# Issue #640: a left click is Space's second binding (tap on release); only
	# while the mouse is captured, so a click on Ready or a menu button is not.
	var action_click := event as InputEventMouseButton
	if action_click != null and action_click.button_index == MOUSE_BUTTON_LEFT \
			and (not action_click.pressed or (mouse_captured and not menu_open and get_viewport().gui_get_hovered_control() == null)):
		_action_edge(-MOUSE_BUTTON_LEFT, action_click.pressed)
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		toggle_menu()
		get_viewport().set_input_as_handled()

## Issue #976: on the host's victory screen, Space, A or a left click is
## Continue, as on the host (#337, #640): this seat's Ready.
func _victory_input(event: InputEvent) -> bool:
	if menu_open or not victory_visible():
		return false
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	var click := event as InputEventMouseButton
	var go: bool = (key != null and key.pressed and not key.echo and key.physical_keycode == KEY_SPACE) \
		or (pad != null and pad.pressed and pad.button_index == JOY_BUTTON_A) \
		or (click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT)
	if go:
		_send_json({"t": "ready", "v": true})
	return go

## F9 saves this screen's last ~10 s as a clip, as on the host (#329, #976).
func _replay_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if effects == null or key == null or not key.pressed or key.echo or key.physical_keycode != KEY_F9:
		return false
	effects.replay.save_and_toast()
	return true

## A non-shoulder action button went down or came up: a tap counts on key-up.
func _action_edge(id: int, pressed: bool) -> void:
	if pressed:
		_action_down[id] = GameClockScript.now_msec()
	elif _action_down.has(id):
		var down: int = _action_down[id]
		_action_down.erase(id)
		if _tapped(down):
			_action_press(false)

# --- Joining ----------------------------------------------------------------------

## Starts joining `code` as `display_name`. One join at a time: false, and
## nothing started, while already connecting or playing, or when the code is
## malformed (the join screen says why).
func join(code: String, display_name: String) -> bool:
	if state != State.JOIN:
		return false
	_code_hint.visible = false # #922
	code = normalize_code(code)
	if not code_is_complete(code):
		_set_status(tr("JOIN_ENTER_CODE") % CODE_LENGTH)
		return false
	room_code = code
	player_name = ControllerServerScript.clean_name(display_name)
	if player_name.is_empty():
		player_name = "Player"
	_save_settings()
	var socket := WebSocketPeer.new()
	socket.inbound_buffer_size = 1 << 20
	if socket.connect_to_url(relay_url) != OK:
		_set_status(tr("JOIN_RELAY_UNREACHABLE") % relay_url)
		return false
	_socket = socket
	_phase = Phase.OPENING
	_deadline_msec = Time.get_ticks_msec() + join_timeout_msec
	_world.clear()
	_set_state(State.CONNECTING)
	_set_status(tr("JOIN_CONNECTING"))
	return true

## Gives up a join in progress, or the retries after a drop, and goes back to
## the join screen; from the idle join screen it goes back to the title
## instead (#506). The scene only changes when this client is the running
## scene, so a client embedded in a test stays put.
func cancel() -> void:
	if state == State.CONNECTING or rejoining():
		_return_to_join("")
	elif state == State.JOIN:
		back_requested.emit()
		if is_inside_tree() and get_tree().current_scene == self:
			get_tree().change_scene_to_file(MAIN_SCENE)

## Hangs up and goes back to the join screen.
func leave() -> void:
	if state != State.JOIN:
		_return_to_join("")

func _poll_socket() -> void:
	_socket.poll()
	var ready_state: int = _socket.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN:
		if _phase == Phase.OPENING:
			_phase = Phase.JOINING
			_set_status(tr("JOIN_JOINING_ROOM") % room_code)
			_socket.send_text(JSON.stringify({"t": "join", "room": room_code}))
		while _socket != null and _socket.get_available_packet_count() > 0:
			var packet: PackedByteArray = _socket.get_packet()
			var is_text: bool = _socket.was_string_packet()
			if packet.is_empty():
				continue
			if is_text:
				_on_relay_text(packet.get_string_from_utf8())
			else:
				_on_envelope(packet)
	elif ready_state == WebSocketPeer.STATE_CLOSED:
		_on_socket_closed()
		return
	if _socket != null and state == State.CONNECTING and Time.get_ticks_msec() > _deadline_msec:
		var until: int = _rejoin_until_msec
		if _phase == Phase.OPENING:
			_return_to_join(tr("JOIN_RELAY_NO_ANSWER") % relay_url)
		else:
			_return_to_join(tr("JOIN_TIMEOUT"))
		_keep_rejoining(until)

func _on_socket_closed() -> void:
	if state == State.PLAYING:
		_return_to_join(tr("JOIN_LOST"))
		_keep_rejoining(Time.get_ticks_msec() + ControllerServerScript.REMOTE_SEAT_HOLD_MSEC)
		return
	var until: int = _rejoin_until_msec
	if _phase == Phase.OPENING:
		_return_to_join(tr("JOIN_RELAY_UNREACHABLE") % relay_url)
	else:
		_return_to_join(tr("JOIN_CLOSED_EARLY"))
	_keep_rejoining(until)

## The relay's own TEXT messages: welcome or error.
func _on_relay_text(text: String) -> void:
	var msg: Dictionary = _parse_object(text)
	match str(msg.get("t", "")):
		"welcome":
			if _phase != Phase.JOINING:
				return
			peer_id = int(msg.get("peer", 0))
			_phase = Phase.HELLO
			_set_status(tr("JOIN_WAITING_HOST") % room_code)
			_send_json({"id": client_id, "proto": protocol_version, "demo": demo_build})
		"error":
			_forget_dead_room(str(msg.get("reason", "")))
			_return_to_join(reason_text(str(msg.get("reason", "unknown"))), str(msg.get("reason", "")) == "version")

## A binary frame: `[kind][payload]`.
func _on_envelope(packet: PackedByteArray) -> void:
	if packet.size() < 2:
		return
	var payload: PackedByteArray = packet.slice(1)
	match int(packet[0]):
		RelayLinkScript.KIND_TEXT:
			_on_host_text(payload.get_string_from_utf8())
		RelayLinkScript.KIND_SNAPSHOT:
			if state == State.PLAYING:
				receive_snapshot_packet(payload)

## The host's TEXT messages.
func _on_host_text(text: String) -> void:
	var msg: Dictionary = _parse_object(text)
	if msg.has("slot") and msg.get("slot") is float and state == State.CONNECTING:
		slot = int(msg["slot"])
		_rejoin_until_msec = 0
		_remember_room(room_code) # #907
		_set_state(State.PLAYING)
		_send_json({"t": "name", "v": player_name})
		for pick: Dictionary in CosmeticsPickerScript.pick_messages(saved_pick):
			_send_json(pick) # issue #441: the saved look goes on at join
		_set_captured(false) # the lobby message below decides (#518)
		_show_playing()
		return
	match str(msg.get("t", "")):
		"lobby":
			lobby = msg
			_refresh_lobby()
		"hud":
			hud = msg
			_refresh_extras()
		"career":
			_on_career(msg)
		"achievement":
			_on_achievement(msg)
		"looks":
			_on_looks(msg)
		"ping":
			_send_json({"t": "pong", "n": msg.get("n", 0)})
		"release":
			pass # the host owns the toggle now (#481)
		"closed":
			var closed_reason: String = str(msg.get("reason", "closed"))
			_return_to_join(reason_text(closed_reason))
			if closed_reason == "input timeout": # #579: the host holds the seat; come back
				_keep_rejoining(Time.get_ticks_msec() + ControllerServerScript.REMOTE_SEAT_HOLD_MSEC)
		"error":
			var reason: String = str(msg.get("reason", "unknown"))
			_forget_dead_room(reason)
			_return_to_join(reason_text(reason), reason == "version")

static func _parse_object(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	return json.data

func _return_to_join(message: String, show_update_link: bool = false) -> void:
	_rejoin_until_msec = 0
	if _socket != null:
		_socket.close()
		_socket = null
	slot = -1
	peer_id = 0
	lobby = {}
	menu_open = false
	action_presses = 0
	_pad_shoulder_held = false
	_action_down.clear()
	_shoulder_down_msec = -1
	_mouse.reset()
	input_vector = Vector2.ZERO
	_set_captured(false)
	_clear_world()
	_set_state(State.JOIN)
	_show_join_screen()
	_set_status(message)
	_update_link.uri = itch_url
	_update_link.visible = show_update_link and not itch_url.is_empty()

# --- Sending ------------------------------------------------------------------------

func _send_envelope(kind: int, payload: PackedByteArray) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var frame := PackedByteArray([kind])
	frame.append_array(payload)
	_socket.send(frame, WebSocketPeer.WRITE_MODE_BINARY)

func _send_json(data: Dictionary) -> void:
	_send_envelope(RelayLinkScript.KIND_TEXT, JSON.stringify(data).to_utf8_buffer())

## One input frame: the phone format, float32 x then y, little-endian.
func _send_input() -> void:
	var v: Vector2 = Vector2.ZERO if menu_open else input_vector
	var released: bool = input_released() and not menu_open
	var body := PackedByteArray()
	# Issue #660: raw mouse motion rides along (two int16 px) for a KO'd seat's ghost.
	var px := Vector2i(clampi(roundi(_mouse_px_pending.x), -32768, 32767), clampi(roundi(_mouse_px_pending.y), -32768, 32767))
	_mouse_px_pending = Vector2.ZERO
	body.resize(14 if px != Vector2i.ZERO else 10)
	if px != Vector2i.ZERO:
		body.encode_s16(10, px.x)
		body.encode_s16(12, px.y)
	body.encode_float(0, v.x)
	body.encode_float(4, v.y)
	body[8] = 1 if released else 0
	body[9] = action_presses | (0x80 if _action_was_hold else 0)
	_send_envelope(RelayLinkScript.KIND_INPUT, body)
	input_frames_sent += 1

## The mouse moved by `relative` pixels while captured (what `_input` calls).
func mouse_motion(relative: Vector2) -> void:
	_mouse_px_pending += relative
	var edge: float = minf(get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y)
	input_vector = _mouse.move(relative, HostMouseScript.drag_radius(edge))

func set_sensitivity(value: float) -> void:
	_mouse.sensitivity = clampf(value, 0.1, 5.0)
	if _sens_slider != null and not is_equal_approx(_sens_slider.value, _mouse.sensitivity):
		_sens_slider.value = _mouse.sensitivity
	_save_settings()

func sensitivity() -> float:
	return _mouse.sensitivity

# --- Esc menu -----------------------------------------------------------------------

func _let_go_held() -> void:
	_pad_shoulder_held = false
	_shoulder_down_msec = -1
	_action_down.clear()

func toggle_menu() -> void:
	if state != State.PLAYING:
		return
	if menu_open:
		resume()
		return
	menu_open = true
	_let_go_held() # a button-up while the menu is open is never seen (#599)
	_mouse.reset()
	input_vector = Vector2.ZERO
	_set_captured(false)
	_menu_panel.visible = true
	_refresh_lobby()

func resume() -> void:
	if state != State.PLAYING:
		return
	menu_open = false
	_let_go_held()
	_menu_panel.visible = false
	_mouse.reset()
	_sync_capture()

## The mouse is captured only while a round is on screen, never over the lobby or
## the podium where Ready must be clickable (#518).
func _sync_capture() -> void:
	var phase: String = str(lobby.get("phase", ""))
	_set_captured(state == State.PLAYING and not menu_open and (phase == "playing" or phase == "round_end"))

func _set_captured(on: bool) -> void:
	mouse_captured = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

# --- Snapshots ------------------------------------------------------------------------

## One KIND_SNAPSHOT payload (without the kind byte): sound trailer split off,
## the rest decoded and applied, the sounds played.
func receive_snapshot_packet(payload: PackedByteArray) -> void:
	if payload.size() < 2:
		return
	var split: Dictionary = SnapshotCaptureScript.split_sound_trailer(payload)
	var bytes: PackedByteArray = split["snapshot"]
	if bytes.is_empty():
		return
	var decoded: Variant = SnapshotScript.decode(bytes)
	if decoded is Dictionary and not (decoded as Dictionary).is_empty():
		apply_snapshot(decoded)
	_play_sounds(split.get("events", []), str(split.get("track", "")))
	if effects != null:
		effects.queue(split.get("effects", []))

## Applies a decoded snapshot: a full one becomes the new world (and snaps the
## puppets only when a round starts or the stage changes; mid-round fulls, which
## arrive about once a second and whenever something disappears, blend in like a
## delta), a delta is merged onto the last full one. A delta with no full
## snapshot before it is dropped.
func apply_snapshot(snap: Dictionary) -> void:
	if snap.get("is_full_snapshot", false):
		var restage: bool = _world.is_empty() or not _round_shown() or snap.get("stage_id") != _world.get("stage_id")
		_world = snap.duplicate(true)
		if restage:
			_samples.clear()
		full_frames_applied += 1
		_sync_stage()
		_sync_part_clocks()
	else:
		if _world.is_empty():
			return
		_apply_delta(snap.get("delta_entities", []))
	frames_applied += 1
	_last_snapshot_msec = Time.get_ticks_msec()
	_push_sample()
	_refresh_hud()

func world() -> Dictionary:
	return _world

static func _find_by(list: Array, key: String, id: int) -> Dictionary:
	for entry: Variant in list:
		if entry is Dictionary and int(entry.get(key, -1)) == id:
			return entry
	return {}

## Merges a delta frame onto the world through `Snapshot.apply_delta`, the
## codec's own merge (issue #976: every field the host sends, flails, ghosts,
## meteors, stage parts and props included). Kill-feed lines arrive in full
## snapshots only, so delta feed entries are not appended here.
func _apply_delta(entities: Array) -> void:
	var kept: Array = []
	for ent: Variant in entities:
		if ent is Dictionary and int((ent as Dictionary).get("type", 0)) != SnapshotScript.TYPE_KILL_FEED:
			kept.append(ent)
	if not kept.is_empty():
		_world = SnapshotScript.apply_delta(_world, {"delta_entities": kept})

func _push_sample() -> void:
	var sample: Dictionary = {"t": Time.get_ticks_msec(), "players": {}, "things": {}, "parts": {}, "props": {}}
	for p: Variant in _world.get("players", []):
		if p is Dictionary:
			var body: Dictionary = p.get("body", {})
			var weapon: Dictionary = p.get("weapon", {})
			sample["players"][int(p.get("player_id", 0))] = [body.get("position", Vector2.ZERO),
				body.get("rotation", 0.0), weapon.get("head_position", Vector2.ZERO),
				weapon.get("head_rotation", 0.0)]
	for p: Variant in _world.get("projectiles", []):
		if p is Dictionary:
			sample["things"]["proj%d" % int(p.get("projectile_id", 0))] = [p.get("position", Vector2.ZERO), float(p.get("rotation", 0.0))]
	for p: Variant in _world.get("pickups", []):
		if p is Dictionary:
			sample["things"]["pick%d" % int(p.get("pickup_id", 0))] = [p.get("position", Vector2.ZERO), 0.0]
	for f: Variant in _world.get("flails", []):
		if f is Dictionary:
			sample["things"]["flail%d" % int(f.get("owner", 0))] = [f.get("ball_position", Vector2.ZERO),
				float(f.get("ball_rotation", 0.0)), f.get("links", [])]
	for g: Variant in _world.get("ghosts", []):
		if g is Dictionary:
			sample["things"]["ghost%d" % int(g.get("owner", 0))] = [g.get("position", Vector2.ZERO), 0.0]
	for m: Variant in _world.get("meteors", []):
		if m is Dictionary:
			sample["things"]["meteor%d" % int(m.get("meteor_id", 0))] = [m.get("position", Vector2.ZERO), 0.0]
	for part: Variant in _world.get("parts", []):
		if part is Dictionary:
			sample["parts"][int(part.get("part_id", 0))] = part.get("state", [])
	for prop: Variant in _world.get("props", []):
		if prop is Dictionary:
			sample["props"][int(prop.get("prop_id", 0))] = [int(prop.get("kind", 0)), prop.get("state", [])]
	_samples.append(sample)
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()

# --- Sound ------------------------------------------------------------------------------

func _play_sounds(events: Array, track: String) -> void:
	var sfx: Node = get_node_or_null("/root/Sfx")
	for ev: Variant in events:
		if not ev is Dictionary:
			continue
		var ev_name: String = str(ev.get("name", ""))
		sounds_played.append(ev_name)
		if sounds_played.size() > 64:
			sounds_played.pop_front()
		if sfx != null and sfx.has_sound(ev_name):
			sfx.play(StringName(ev_name), ev.get("position"), float(ev.get("strength", 1.0)))
	if track == last_track:
		return
	last_track = track
	var music: Node = get_node_or_null("/root/Music")
	if music == null:
		return
	if track.is_empty():
		music.stop()
	elif track == "lobby":
		music.play_lobby()
	else:
		music.call("_switch_to", track)

# --- Stage and puppets -----------------------------------------------------------------

func _round_shown() -> bool:
	var phase: int = int(_world.get("round_phase", 0))
	return phase == PHASE_ROUND_ACTIVE or phase == PHASE_ROUND_END

## Loads the host's stage by id (and as its night variant when the host's is)
## when a round is on screen and frees it when not.
func _sync_stage() -> void:
	var want: int = int(_world.get("stage_id", 0)) if _round_shown() else -1
	var night: bool = want >= 0 and _night_in(_world)
	if want == _stage_id and night == _stage_night:
		return
	_stage_night = night
	if _stage != null:
		_stage_holder.remove_child(_stage)
		_stage.queue_free()
		_stage = null
	_part_nodes.clear()
	_part_shown.clear()
	_part_missing.clear()
	_stage_id = want
	_stage_night = night
	if want < 0:
		return
	var paths: PackedStringArray = stage_paths()
	if want >= paths.size():
		return
	var scene: PackedScene = load(paths[want]) as PackedScene
	if scene == null:
		return
	_stage = scene.instantiate()
	_stage.set("stage_index", want)
	# Issue #976: the host's night variant (#332), lighting the puppets.
	_stage.set("night", night)
	_stage.set("night_light_groups", PackedStringArray([String(NIGHT_PLAYER_GROUP), String(NIGHT_PICKUP_GROUP)]))
	_stage_holder.add_child(_stage)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	_map_parts()
	_fit_camera()

## Issue #976: every stage part whose look the host sends, by the id both
## sides give it, with its own logic stopped where the host's state drives it.
func _map_parts() -> void:
	_part_nodes.clear()
	_parts_dirty = false
	if _stage == null:
		return
	part_walks += 1
	for node: Node in NetSyncScript.parts_of(_stage):
		_part_nodes[NetSyncScript.part_id(_stage, node)] = node
		NetSyncScript.freeze_part(node)

## Walks the stage for its parts again only when the host names a part id
## this client has not looked for yet, or the stage gained nodes since the
## last walk (a part one of its states builds, the rising lava's art): a part
## the client cannot find is remembered, not looked for again while the stage
## is unchanged.
func _ensure_parts(ids: Array) -> void:
	if _stage == null:
		return
	var look: bool = false
	for id: Variant in ids:
		var node: Variant = _part_nodes.get(id)
		if node != null and is_instance_valid(node):
			continue
		if _parts_dirty or not _part_missing.has(id):
			look = true
			break
	if not look:
		return
	_map_parts()
	for id: Variant in ids:
		if not _part_nodes.has(id):
			_part_missing[id] = true

func _on_node_added(node: Node) -> void:
	if not _parts_dirty and _stage != null and _stage.is_ancestor_of(node):
		_parts_dirty = true

## Whether the host's stage in `world` is its night variant (#332): the
## snapshot's "night" modifier entry (`SnapshotCapture.NIGHT_MODIFIER_ID`).
static func _night_in(world: Dictionary) -> bool:
	for mod: Variant in world.get("modifiers", []):
		if mod is Dictionary and int(mod.get("modifier_id", 0)) == SnapshotCaptureScript.NIGHT_MODIFIER_ID and str(mod.get("name", "")) == "night":
			return true
	return false

## Whether the stage on screen is its night variant (scenarios).
func stage_is_night() -> bool:
	return _stage != null and _stage.get("night") == true

func _fit_camera() -> void:
	if _camera == null:
		return
	var view := Rect2(-StageScript.DEFAULT_VIEW_SIZE * 0.5, StageScript.DEFAULT_VIEW_SIZE)
	if _stage != null and _stage.has_method("get_view_rect"):
		view = _stage.get_view_rect()
	var window: Vector2 = get_viewport().get_visible_rect().size
	var fit: float = minf(window.x / view.size.x, window.y / view.size.y)
	_camera.zoom = Vector2(fit, fit)
	_camera.global_position = view.get_center()

func _clear_world() -> void:
	_world.clear()
	_samples.clear()
	_sync_stage()
	for key: String in _puppets.keys():
		_puppets[key].queue_free()
	_puppets.clear()
	_clear_props()
	_hud_signature = ""
	hud = {}
	_last_round_phase = 0
	_ui_text = ""
	_screens = {}
	_pending_pops.clear()
	_victory_text = ""
	if effects != null:
		effects.round_left()
		effects.show_victory({})
		effects.apply_mode_hud("", {})
	if _host_hud != null:
		_host_hud.visible = false
	if _modifier_label != null:
		_modifier_label.visible = false
	if _puppet_holder != null:
		for child in _puppet_holder.get_children():
			_puppet_holder.remove_child(child)
			child.queue_free()

## The puppet of player `slot_id`, or null.
func player_puppet(slot_id: int) -> Node2D:
	return _puppets.get("player%d" % slot_id) as Node2D

## The puppet drawn under `key` ("proj12", "pick3", "flail0", "ghost2",
## "meteor7"), or null.
func thing_puppet(key: String) -> Node2D:
	return _puppets.get(key) as Node2D

func puppet_count(kind: int) -> int:
	var n: int = 0
	for puppet: Node in _puppets.values():
		if puppet.kind == kind:
			n += 1
	return n

## The client's copy of the host's prop `prop_id` (issue #976), or null.
func prop_node(prop_id: int) -> Node2D:
	return _prop_nodes.get(prop_id) as Node2D

func prop_count() -> int:
	return _prop_nodes.size()

## The stage part the host's `part_id` names, or null.
func part_node(part_id: int) -> Node:
	return _part_nodes.get(part_id)

func has_stage() -> bool:
	return _stage != null

func stage_id() -> int:
	return _stage_id

func stage_node() -> Node:
	return _stage

func _puppet(key: String, kind: int) -> Node2D:
	var puppet: Node2D = _puppets.get(key)
	if puppet == null:
		puppet = PuppetScript.new()
		puppet.kind = kind
		# In the night lighting's groups before it enters the tree (#976).
		if kind == PuppetScript.Kind.PLAYER:
			puppet.add_to_group(NIGHT_PLAYER_GROUP)
		elif kind == PuppetScript.Kind.PICKUP:
			puppet.add_to_group(NIGHT_PICKUP_GROUP)
		_puppet_holder.add_child(puppet)
		_puppets[key] = puppet
	return puppet

## The round's modifier id ("" for none), which changes how some weapons look
## (not the night stage's entry, SnapshotCapture.NIGHT_MODIFIER_ID).
func _modifier_id() -> String:
	for m: Variant in _world.get("modifiers", []):
		if m is Dictionary and int(m.get("modifier_id", 0)) != SnapshotCaptureScript.NIGHT_MODIFIER_ID:
			return str(m.get("name", ""))
	return ""

## Draws the newest state INTERP_MSEC late, blending the two samples around that
## moment so the 30 Hz stream moves smoothly.
func _render() -> void:
	if _samples.is_empty() or not _round_shown():
		_hide_puppets_except({})
		_clear_props()
		return
	var render_at: int = Time.get_ticks_msec() - INTERP_MSEC
	var after: int = -1
	for i in _samples.size():
		if _samples[i]["t"] >= render_at:
			after = i
			break
	var a: Dictionary
	var b: Dictionary
	if after == -1:
		a = _samples[_samples.size() - 1]
		b = a
	elif after == 0:
		a = _samples[0]
		b = a
	else:
		a = _samples[after - 1]
		b = _samples[after]
		for _i in after - 1:
			_samples.pop_front()
	var span: int = int(b["t"]) - int(a["t"])
	var alpha: float = clampf(float(render_at - int(a["t"])) / float(span), 0.0, 1.0) if span > 0 else 1.0
	var live: Dictionary = {}
	var modifier: String = _modifier_id()
	# The stage mood's ink is on every face and head outline, as on the host (#255).
	var ink: Variant = (_stage.get("mood") as Dictionary).get("ink") if _stage != null and _stage.get("mood") is Dictionary else null
	for p: Variant in _world.get("players", []):
		if not p is Dictionary:
			continue
		var id: int = int(p.get("player_id", 0))
		var key: String = "player%d" % id
		live[key] = true
		var puppet: Node2D = _puppet(key, PuppetScript.Kind.PLAYER)
		var from_pose: Array = a["players"].get(id, b["players"].get(id, []))
		var to_pose: Array = b["players"].get(id, from_pose)
		if from_pose.is_empty():
			continue
		puppet.color = PaletteScript.PLAYERS[int(p.get("color", id)) % PaletteScript.PLAYERS.size()]
		var look: Dictionary = _look_of(id)
		if look.has("color"):
			puppet.color = look["color"]
		puppet.weapon_index = int((p.get("weapon", {}) as Dictionary).get("head_shape_index", 0))
		puppet.loaded = bool((p.get("weapon", {}) as Dictionary).get("loaded", false))
		puppet.set_look(str(look.get("hat", "none")), str(look.get("eyes", "round")), puppet.color)
		puppet.damage = int(p.get("damage", 0))
		puppet.phase = int(p.get("state", 1))
		puppet.flags = int(p.get("flags", 0))
		puppet.hat_spin = int(p.get("hat_spin", 0))
		puppet.squash = int(p.get("squash", SnapshotScript.SQUASH_REST))
		puppet.linear_velocity = (p.get("body", {}) as Dictionary).get("linear_velocity", Vector2.ZERO)
		puppet.modifier = modifier
		if ink is Color:
			puppet.set_ink(ink)
		puppet.set_pose((from_pose[0] as Vector2).lerp(to_pose[0], alpha),
			lerp_angle(from_pose[1], to_pose[1], alpha),
			(from_pose[2] as Vector2).lerp(to_pose[2], alpha),
			lerp_angle(from_pose[3] if from_pose.size() > 3 else 0.0, to_pose[3] if to_pose.size() > 3 else 0.0, alpha))
	for p: Variant in _world.get("projectiles", []):
		if not p is Dictionary:
			continue
		var shot: Node2D = _place_thing("proj%d" % int(p.get("projectile_id", 0)), PuppetScript.Kind.PROJECTILE, a, b, alpha, live)
		if shot == null:
			continue
		var owner: Node2D = player_puppet(int(p.get("owner", -1)))
		shot.owner_puppet = owner
		shot.color = owner.color if owner != null else Color.WHITE
		shot.weapon_index = int(p.get("weapon_type", 0))
		shot.modifier = modifier
		shot.velocity = p.get("velocity", Vector2.ZERO)
		shot.shot_flags = int(p.get("flags", 0))
		shot.shot_rotation = _thing_rotation("proj%d" % int(p.get("projectile_id", 0)), a, b, alpha)
		shot.refresh_shot()
		shot.queue_redraw()
	for p: Variant in _world.get("pickups", []):
		if not p is Dictionary:
			continue
		var key: String = "pick%d" % int(p.get("pickup_id", 0))
		var pickup: Node2D = _place_thing(key, PuppetScript.Kind.PICKUP, a, b, alpha, live)
		if pickup == null:
			continue
		pickup.weapon_index = int(p.get("weapon_type", 0))
		pickup.halo = int(p.get("halo", 0))
		pickup.show_pickup()
	for f: Variant in _world.get("flails", []):
		if not f is Dictionary:
			continue
		var key: String = "flail%d" % int(f.get("owner", 0))
		var to_f: Variant = b["things"].get(key)
		if to_f == null or not _samples.back()["things"].has(key):
			continue
		var from_f: Array = a["things"].get(key, to_f)
		live[key] = true
		var flail: Node2D = _puppet(key, PuppetScript.Kind.FLAIL)
		var owner: Node2D = player_puppet(int(f.get("owner", -1)))
		flail.color = owner.color if owner != null else Color.WHITE
		flail.weapon_index = _flail_index()
		flail.modifier = modifier
		flail.show_flail((from_f[0] as Vector2).lerp(to_f[0], alpha), lerp_angle(from_f[1], to_f[1], alpha),
			_lerp_links(from_f[2], to_f[2], alpha), int(f.get("flags", 0)) & SnapshotScript.FLAIL_PHASED != 0)
	for g: Variant in _world.get("ghosts", []):
		if not g is Dictionary:
			continue
		var ghost: Node2D = _place_thing("ghost%d" % int(g.get("owner", 0)), PuppetScript.Kind.GHOST, a, b, alpha, live)
		if ghost == null:
			continue
		var owner: Node2D = player_puppet(int(g.get("owner", -1)))
		ghost.color = owner.color if owner != null else Color.WHITE
		ghost.ghost_alpha = float(g.get("alpha", 0.0))
		ghost.puff = float(g.get("puff", 1.0))
		ghost.queue_redraw()
	for m: Variant in _world.get("meteors", []):
		if not m is Dictionary:
			continue
		var meteor: Node2D = _place_thing("meteor%d" % int(m.get("meteor_id", 0)), PuppetScript.Kind.METEOR, a, b, alpha, live)
		if meteor == null:
			continue
		meteor.velocity = m.get("velocity", Vector2.ZERO)
		meteor.radius = float(m.get("radius", 0))
		meteor.queue_redraw()
	_hide_puppets_except(live)
	_render_parts(a, b, alpha)
	_render_props(a, b, alpha)

## Places the puppet for `key` between samples `a` and `b`; null when the
## newest snapshot no longer holds it.
func _place_thing(key: String, kind: int, a: Dictionary, b: Dictionary, alpha: float, live: Dictionary) -> Node2D:
	var to_pos: Variant = b["things"].get(key)
	# Issue #429: a thing the newest snapshot no longer holds is gone now, not
	# when the interpolation window moves past its last sample.
	if to_pos == null or not _samples.back()["things"].has(key):
		return null
	var from_pos: Variant = a["things"].get(key, to_pos)
	live[key] = true
	var puppet: Node2D = _puppet(key, kind)
	puppet.position = (from_pos[0] as Vector2).lerp(to_pos[0], alpha)
	return puppet

func _thing_rotation(key: String, a: Dictionary, b: Dictionary, alpha: float) -> float:
	var to_pos: Array = b["things"].get(key, [Vector2.ZERO, 0.0])
	var from_pos: Array = a["things"].get(key, to_pos)
	return lerp_angle(float(from_pos[1]), float(to_pos[1]), alpha)

static func _lerp_links(from_links: Variant, to_links: Variant, alpha: float) -> Array:
	var to_list: Array = to_links if to_links is Array else []
	var from_list: Array = from_links if from_links is Array and (from_links as Array).size() == to_list.size() else to_list
	var out: Array = []
	for i in to_list.size():
		var f: Dictionary = from_list[i] if from_list[i] is Dictionary else {}
		var t: Dictionary = to_list[i] if to_list[i] is Dictionary else {}
		out.append({"position": (f.get("position", Vector2.ZERO) as Vector2).lerp(t.get("position", Vector2.ZERO), alpha),
			"rotation": lerp_angle(float(f.get("rotation", 0.0)), float(t.get("rotation", 0.0)), alpha)})
	return out

## The snapshot weapon index of the flail (its ball and links are drawn from it).
static func _flail_index() -> int:
	for i in PickupWeaponsScript.WEAPON_PATHS.size():
		if PickupWeaponsScript.WEAPON_PATHS[i].get_file().get_basename() == "flail":
			return i + 1
	return 0

## Issue #976: every stage part takes the host's look, blended between
## samples; its clocks are re-set on full snapshots only (`_sync_part_clocks`).
func _render_parts(a: Dictionary, b: Dictionary, alpha: float) -> void:
	if _stage == null:
		return
	_ensure_parts(b["parts"].keys())
	for id: int in b["parts"]:
		var node: Node = _part_nodes.get(id)
		if node == null or not is_instance_valid(node):
			continue
		var to_state: Array = b["parts"][id]
		var from_state: Array = a["parts"].get(id, to_state)
		var paths: Array = NetSyncScript.vars_of(node) + NetSyncScript.clocks_of(node)
		var state: Array = NetSyncScript.lerp_state(paths, from_state, to_state, alpha)
		if _part_shown.get(id) == state:
			continue
		_part_shown[id] = state
		NetSyncScript.apply_part(node, state, false)

func _sync_part_clocks() -> void:
	# A part built by an earlier state (the rising lava's art) is mapped
	# before its clock is set.
	var ids: Array = []
	for part: Variant in _world.get("parts", []):
		if part is Dictionary:
			ids.append(int(part.get("part_id", 0)))
	_ensure_parts(ids)
	for part: Variant in _world.get("parts", []):
		if not part is Dictionary:
			continue
		var node: Node = _part_nodes.get(int(part.get("part_id", 0)))
		if node != null and is_instance_valid(node) and not NetSyncScript.clocks_of(node).is_empty():
			NetSyncScript.apply_part(node, part.get("state", []), true)

## Issue #976: the host's runtime props (soccer ball, CTF flags, the hill,
## tiebreaker rocks, the gale), each built by the host's own builder.
func _render_props(a: Dictionary, b: Dictionary, alpha: float) -> void:
	var newest: Dictionary = _samples.back()["props"]
	for id: int in _prop_nodes.keys():
		if not newest.has(id):
			_free_prop(id)
	for id: int in b["props"]:
		if not newest.has(id):
			continue
		var to_entry: Array = b["props"][id]
		var kind: int = int(to_entry[0])
		var to_state: Array = to_entry[1]
		var from_entry: Array = a["props"].get(id, to_entry)
		var from_state: Array = from_entry[1] if int(from_entry[0]) == kind else to_state
		var node: Node2D = _prop_nodes.get(id)
		if node != null and NetSyncScript.prop_kind(node) != kind:
			_free_prop(id)
			node = null
		if node == null:
			node = NetSyncScript.build_prop(kind, to_state)
			if node == null:
				continue
			_prop_holder.add_child(node)
			NetSyncScript.settle_prop(node)
			_prop_nodes[id] = node
		NetSyncScript.apply_prop(node, NetSyncScript.lerp_state(NetSyncScript.prop_paths(kind), from_state, to_state, alpha))

func _free_prop(id: int) -> void:
	var node: Node = _prop_nodes.get(id)
	_prop_nodes.erase(id)
	if node != null and is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.queue_free()

func _clear_props() -> void:
	for id: int in _prop_nodes.keys():
		_free_prop(id)

func _hide_puppets_except(live: Dictionary) -> void:
	for key: String in _puppets.keys():
		if not live.has(key):
			_puppets[key].queue_free()
			_puppets.erase(key)

## The hat, eyes and colour the host's `looks` frame gives seat `slot`, as
## {"hat", "eyes", "color"}; empty before the frame arrives (issue #930).
func _look_of(slot: int) -> Dictionary:
	var palette: Array = looks.get("palette", [])
	for entry: Variant in looks.get("looks", []):
		if entry is Dictionary and int(entry.get("slot", -1)) == slot:
			var out: Dictionary = {"hat": str(entry.get("hat", "none")), "eyes": str(entry.get("eyes", "round"))}
			var at: int = int(entry.get("color", -1))
			if at >= 0 and at < palette.size() and str(palette[at]).begins_with("#"):
				out["color"] = Color.html(str(palette[at]))
			return out
	return {}

# --- Settings -----------------------------------------------------------------------------

func _load_settings() -> void:
	if settings_path.is_empty():
		return
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		player_name = _steam_default_name()
		return
	# #538: a name never saved defaults to the Steam persona name; any saved
	# name (even one that reads empty) is the player's and wins.
	if not config.has_section_key(SECTION, "name"):
		player_name = _steam_default_name()
	# #460: a hand-edited or junk saved name reads as empty; the join falls back to "Player".
	else:
		player_name = ControllerServerScript.clean_name(str(config.get_value(SECTION, "name", "")))
	saved_pick = CosmeticsPickerScript.read_pick(config, SECTION)
	client_id = str(config.get_value(SECTION, "id", ""))
	var last: String = normalize_code(str(config.get_value(SECTION, "last_room", "")))
	last_room_code = last if code_is_complete(last) else ""
	var sens: Variant = config.get_value(SECTION, "sensitivity", 1.0)
	if (sens is float or sens is int) and is_finite(float(sens)):
		_mouse.sensitivity = clampf(float(sens), 0.1, 5.0)

## #538: the Steam persona name, cleaned and capped like any typed name; ""
## without Steam.
func _steam_default_name() -> String:
	var steam: Node = get_node_or_null(^"/root/SteamPlatform")
	if steam == null:
		return ""
	return ControllerServerScript.clean_name(str(steam.call("persona_name"))).left(NAME_MAX_LENGTH)

func _save_settings() -> void:
	if settings_path.is_empty():
		return
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value(SECTION, "name", player_name)
	config.set_value(SECTION, "id", client_id)
	config.set_value(SECTION, "last_room", last_room_code)
	config.set_value(SECTION, "sensitivity", _mouse.sensitivity)
	CosmeticsPickerScript.write_pick(config, SECTION, saved_pick)
	config.save(settings_path)

static func _random_id() -> String:
	return Crypto.new().generate_random_bytes(8).hex_encode()

# --- UI ---------------------------------------------------------------------------------------

func _build_world() -> void:
	_world_root = Node2D.new()
	_world_root.name = "World"
	add_child(_world_root)
	_stage_holder = Node2D.new()
	_stage_holder.name = "Stage"
	_world_root.add_child(_stage_holder)
	# Puppets and parts move in _process from the host's samples, so the
	# engine's physics interpolation (project-wide) must not smooth them again.
	_world_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_prop_holder = Node2D.new()
	_prop_holder.name = "Props"
	_world_root.add_child(_prop_holder)
	_puppet_holder = Node2D.new()
	_puppet_holder.name = "Puppets"
	_world_root.add_child(_puppet_holder)
	effects = RemoteEffectsScript.new()
	effects.delay_msec = INTERP_MSEC
	_world_root.add_child(effects)
	_camera = Camera2D.new()
	_camera.name = "Camera"
	add_child(_camera)
	_camera.make_current()
	effects.camera = _camera
	effects.round_playing = func() -> bool: return int(_world.get("round_phase", 0)) == PHASE_ROUND_ACTIVE
	effects.name_tag_of = _name_tag
	effects.lives_of = _lives_of
	effects.pop_pickup = _pop_pickup
	effects.screen.pad_check = func() -> bool: return _pad_driving
	_fit_camera()

## The joiner's name tag Label for `slot`, or null (MATCH POINT dots, #976).
func _name_tag(slot: int) -> Label:
	return effects.name_tags.name_tag(slot) if effects != null and effects.name_tags != null else null

## Stock lives for the name tags' pips (#354), from the host's `hud` frame; -1
## outside a Stock round.
func _lives_of(slot: int) -> int:
	var m: Variant = hud.get("m")
	if str(hud.get("mode", "")) != "stock" or not m is Dictionary or not (m as Dictionary).get("lives") is Dictionary:
		return -1
	var lives: Dictionary = m["lives"]
	return int(lives.get(str(slot), lives.get(slot, -1)))

## The host popped pickup `id` in (#816): the puppet pops the same way, now or
## as soon as it shows up.
func _pop_pickup(id: int) -> void:
	_pending_pops[id] = Time.get_ticks_msec() + POP_WAIT_MSEC

func _apply_pops() -> void:
	if _pending_pops.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	for id: int in _pending_pops.keys():
		var puppet: Node2D = _puppets.get("pick%d" % id)
		if puppet != null:
			PickupDirectorScript.pop_scale(puppet)
			_pending_pops.erase(id)
		elif now > int(_pending_pops[id]):
			_pending_pops.erase(id)

## Issue #976: head trails follow each shown player puppet's weapon head.
func _track_heads() -> void:
	if effects == null:
		return
	var players: Array = []
	for puppet: Node in _puppets.values():
		if puppet.kind == PuppetScript.Kind.PLAYER:
			players.append(puppet)
	effects.track_heads(players)
	_apply_pops()
	# The host's edge arrows follow each fighter as the snapshot has it.
	var placed: Dictionary = {}
	if _round_shown():
		for p: Variant in _world.get("players", []):
			if p is Dictionary:
				var id: int = int(p.get("player_id", 0))
				var puppet: Node2D = player_puppet(id)
				placed[id] = true
				effects.place_fighter(id, puppet, int(p.get("state", 1)) != SnapshotCaptureScript.STATE_DEAD,
					int(p.get("team", -1)), puppet.color if puppet != null else Color.WHITE,
					str(p.get("name", "")), int((p.get("weapon", {}) as Dictionary).get("head_shape_index", 0)) if p.get("weapon") is Dictionary else 0)
	for id in RemoteEffectsScript.MAX_SLOTS:
		if not placed.has(id):
			effects.place_fighter(id, null, false, -1, Color.WHITE)

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	# Over the host's screens (#976: HUD 1, victory 5, cards 10-12, flash 50):
	# the joiner's own lobby, menu and join panels stay on top.
	_ui.layer = 60
	add_child(_ui)
	_build_hud()
	_build_lobby_panel()
	_build_menu_panel()
	_build_join_panel()

## `variation` is a UiTheme type variation ("" keeps the theme's plain Label,
## cream text for the dark ground); a colour of WHITE leaves the variation's own.
func _label(text: String, size: int = 20, color: Color = Color.WHITE, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", size)
	if color != Color.WHITE:
		label.add_theme_color_override("font_color", color)
	return label

func _centered_panel(parent: Control, min_width: float, panel_variation: StringName = UiThemeScript.CREAM_PANEL) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = panel_variation
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(min_width, 0)
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	return box

func _build_join_panel() -> void:
	_join_panel = Control.new()
	_join_panel.name = "JoinScreen"
	_join_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = UiThemeScript.INDIGO
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_join_panel.add_child(shade)
	_ui.add_child(_join_panel)
	var box: VBoxContainer = _centered_panel(_join_panel, 360)
	box.add_child(_label(tr("JOIN_TITLE"), 30, Color.WHITE, UiThemeScript.INK_HEADING_LABEL))
	box.add_child(_label(tr("JOIN_ROOM_CODE_LABEL"), 20, Color.WHITE, UiThemeScript.INK_LABEL))
	_room_edit = LineEdit.new()
	_room_edit.name = "RoomCode"
	_room_edit.placeholder_text = "ABCD"
	_room_edit.max_length = CODE_LENGTH
	_attach_pad_keyboard(_room_edit) # #711
	_room_edit.text_changed.connect(_on_room_text_changed)
	_room_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	_room_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var room_row := HBoxContainer.new()
	room_row.add_theme_constant_override("separation", 10)
	box.add_child(room_row)
	room_row.add_child(_room_edit)
	_paste_button = Button.new() # #906: fills the field from the clipboard; joins nothing
	_paste_button.name = "Paste"
	_paste_button.text = tr("JOIN_PASTE")
	_paste_button.pressed.connect(_on_paste_pressed)
	room_row.add_child(_paste_button)
	_last_room_button = Button.new() # #907: one tap puts the last joined room's code in the field; joins nothing
	_last_room_button.name = "LastRoom"
	_last_room_button.pressed.connect(_on_last_room_pressed)
	box.add_child(_last_room_button)
	_code_hint = _label(tr("JOIN_CODE_HINT"), 16, UiThemeScript.VERMILION, UiThemeScript.INK_LABEL) # #922
	_code_hint.name = "CodeHint"
	_code_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_code_hint.visible = false
	box.add_child(_code_hint)
	box.add_child(_label(tr("JOIN_YOUR_NAME"), 20, Color.WHITE, UiThemeScript.INK_LABEL))
	_name_edit = LineEdit.new()
	_name_edit.name = "PlayerName"
	_name_edit.placeholder_text = tr("JOIN_NAME_PLACEHOLDER")
	_name_edit.max_length = NAME_MAX_LENGTH
	_name_edit.text = player_name
	_attach_pad_keyboard(_name_edit) # #711
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	box.add_child(_name_edit)
	_status_label = _label("", 18, UiThemeScript.VERMILION, UiThemeScript.INK_LABEL)
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_join_button = Button.new()
	_join_button.name = "Join"
	_join_button.text = tr("JOIN_BUTTON")
	_join_button.pressed.connect(_on_join_pressed)
	row.add_child(_join_button)
	_cancel_button = Button.new()
	_cancel_button.name = "Cancel"
	_cancel_button.text = tr("JOIN_CANCEL")
	_cancel_button.pressed.connect(cancel)
	row.add_child(_cancel_button) # always shown: idle, it backs out to the title
	_update_link = LinkButton.new()
	_update_link.name = "UpdateLink"
	_update_link.text = tr("JOIN_UPDATE_LINK")
	_update_link.uri = itch_url
	_update_link.visible = false
	box.add_child(_update_link)

func _on_room_text_changed(text: String) -> void:
	_code_hint.visible = code_text_drops_a_letter(text) # #922: say why a typed letter did not stay; any edit re-decides
	var cleaned: String = normalize_code(text)
	if cleaned != text:
		_room_edit.text = cleaned
		_room_edit.caret_column = cleaned.length()

## #906: Paste fills the room field with the code on the clipboard; with none
## the field stays as it is and the status line says so.
func _on_paste_pressed() -> void:
	var code: String = code_from_text(str(clipboard_getter.call()))
	if code.is_empty():
		_set_status(tr("JOIN_NO_CODE_ON_CLIPBOARD"))
		return
	_room_edit.text = code
	_room_edit.caret_column = code.length()
	_code_hint.visible = false
	_set_status("")

## #907: a seat was granted in `code`: keep it for next time.
func _remember_room(code: String) -> void:
	if not code_is_complete(code) or code == last_room_code:
		return
	last_room_code = code
	_save_settings()
	_refresh_last_room()

## #907: the relay or host said the room is gone ("bad_room", "host_left"): a
## remembered code for it is stale, so forget it.
func _forget_dead_room(reason: String) -> void:
	if (reason == "bad_room" or reason == "host_left") and not last_room_code.is_empty() and last_room_code == room_code:
		last_room_code = ""
		_save_settings()
		_refresh_last_room()

func _refresh_last_room() -> void:
	if _last_room_button == null:
		return
	_last_room_button.visible = not last_room_code.is_empty()
	_last_room_button.text = tr("JOIN_LAST_ROOM") % last_room_code

func _on_last_room_pressed() -> void:
	if last_room_code.is_empty():
		return
	_room_edit.text = last_room_code
	_room_edit.caret_column = last_room_code.length()
	_code_hint.visible = false
	_set_status("")

func _on_join_pressed() -> void:
	join(_room_edit.text, _name_edit.text)

func _build_hud() -> void:
	# Issue #976: the host's own HUD scene, its kill feed played from the
	# host's recorded events (mirror: it records nothing itself).
	_host_hud = HostHudScene.instantiate() as CanvasLayer
	_host_hud.name = "HostHud"
	var feed: Control = _host_hud.get_node("KillFeed") as Control
	feed.mirror = true
	# The scene's placeholder texts are the host's own start-up lines, in
	# English; every label shows the host's text once its first frame lands.
	for label: Node in _host_hud.find_children("*", "Label", true, false):
		(label as Label).text = ""
	_host_hud.visible = false
	add_child(_host_hud)
	if effects != null:
		effects.kill_feed = feed
	_modifier_label = ModifierBannerScript.build(self)
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_hud)
	_wait_label = _label(tr("JOIN_WAITING"), 28, Color.WHITE, UiThemeScript.HEADING_LABEL)
	_wait_label.set_anchors_preset(Control.PRESET_CENTER)
	_wait_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud.add_child(_wait_label)

## The joiner's copy of the host's HUD scene (#976).
func host_hud() -> CanvasLayer:
	return _host_hud

## The joiner's modifier banner, `ModifierBanner.gd`'s like the host's (#976).
func modifier_label() -> Label:
	return _modifier_label

func _build_lobby_panel() -> void:
	_lobby_panel = Control.new()
	_lobby_panel.name = "LobbyPanel"
	_lobby_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_lobby_panel)
	var box: VBoxContainer = _centered_panel(_lobby_panel, 380, &"")
	_lobby_title = _label(tr("JOIN_LOBBY_TITLE"), 28, Color.WHITE, UiThemeScript.HEADING_LABEL)
	box.add_child(_lobby_title)
	_copy_button = Button.new()
	_copy_button.name = "CopyCode"
	_copy_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_copy_button.visible = false
	_copy_button.pressed.connect(copy_room_code)
	box.add_child(_copy_button)
	_sync_copy_button()
	_career_button = Button.new()
	_career_button.name = "Career"
	_career_button.flat = true
	_career_button.focus_mode = Control.FOCUS_NONE
	_career_button.pressed.connect(func() -> void:
		_career_open = not _career_open
		_refresh_career())
	box.add_child(_career_button)
	_refresh_career()
	_lobby_list = VBoxContainer.new()
	# Issue #441: the cosmetics panel sits beside the player list.
	var beside := HBoxContainer.new()
	beside.add_theme_constant_override("separation", 20)
	box.add_child(beside)
	beside.add_child(_lobby_list)
	_cosmetics_panel = CosmeticsPanelScript.new()
	_cosmetics_panel.picked.connect(_on_cosmetic_picked)
	beside.add_child(_cosmetics_panel)
	_ready_button = Button.new()
	_ready_button.name = "Ready"
	_ready_button.toggle_mode = true
	_ready_button.text = tr("JOIN_READY")
	_ready_button.toggled.connect(func(on: bool) -> void:
		_ready_want = 1 if on else 0
		_ready_want_msec = GameClockScript.now_msec()
		_send_json({"t": "ready", "v": on}))
	box.add_child(_ready_button)
	_host_row = HBoxContainer.new()
	_host_row.name = "HostMenu"
	_host_row.add_theme_constant_override("separation", 8)
	box.add_child(_host_row)
	_mode_button = Button.new()
	_mode_button.name = "Mode"
	_mode_button.pressed.connect(func() -> void:
		_send_json({"t": "mode", "v": "ffa" if lobby.get("mode") == "teams" else "teams"}))
	_host_row.add_child(_mode_button)
	var down := Button.new()
	down.name = "TargetDown"
	down.text = "-"
	down.pressed.connect(func() -> void: _send_json({"t": "target", "n": int(lobby.get("target", 5)) - 1}))
	_host_row.add_child(down)
	_target_label = _label(tr("LOBBY_FIRST_TO") % 5)
	_host_row.add_child(_target_label)
	var up := Button.new()
	up.name = "TargetUp"
	up.text = "+"
	up.pressed.connect(func() -> void: _send_json({"t": "target", "n": int(lobby.get("target", 5)) + 1}))
	_host_row.add_child(up)
	_leave_button = Button.new()
	_leave_button.name = "LeaveLobby"
	_leave_button.text = tr("JOIN_LEAVE_MATCH")
	_leave_button.pressed.connect(leave)
	box.add_child(_leave_button)

func _build_menu_panel() -> void:
	_menu_panel = Control.new()
	_menu_panel.name = "Menu"
	_menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_menu_panel)
	var shade := ColorRect.new()
	shade.color = Color(UiThemeScript.INDIGO, 0.75)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_panel.add_child(shade)
	var box: VBoxContainer = _centered_panel(_menu_panel, 320)
	box.add_child(_label(tr("JOIN_PAUSED"), 28, Color.WHITE, UiThemeScript.INK_HEADING_LABEL))
	var resume_button := Button.new()
	resume_button.name = "Resume"
	resume_button.text = tr("JOIN_RESUME")
	resume_button.pressed.connect(resume)
	box.add_child(resume_button)
	box.add_child(_label(tr("JOIN_MOUSE_SENS"), 20, Color.WHITE, UiThemeScript.INK_LABEL))
	_sens_slider = HSlider.new()
	_sens_slider.name = "Sensitivity"
	_sens_slider.min_value = 0.1
	_sens_slider.max_value = 5.0
	_sens_slider.step = 0.1
	_sens_slider.value = _mouse.sensitivity
	_sens_slider.value_changed.connect(set_sensitivity)
	box.add_child(_sens_slider)
	_pause_button = Button.new()
	_pause_button.name = "HostPause"
	_pause_button.pressed.connect(func() -> void:
		_send_json({"t": "host", "cmd": "resume" if lobby.get("paused", false) else "pause", "match": lobby.get("match", 0)}))
	box.add_child(_pause_button)
	var leave_button := Button.new()
	leave_button.name = "Leave"
	leave_button.text = tr("JOIN_LEAVE_MATCH")
	leave_button.pressed.connect(leave)
	box.add_child(leave_button)

func _set_state(new_state: int) -> void:
	state = new_state
	state_changed.emit(new_state)

func _set_status(text: String) -> void:
	status_text = text
	if _status_label != null:
		_status_label.text = text
	var busy: bool = state == State.CONNECTING
	if _join_button != null:
		_join_button.disabled = busy
		_room_edit.editable = not busy
		_paste_button.disabled = busy
		_last_room_button.disabled = busy
		_name_edit.editable = not busy

func _show_join_screen() -> void:
	_join_panel.visible = true
	_hud.visible = false
	_lobby_panel.visible = false
	_menu_panel.visible = false
	_update_link.visible = false
	_refresh_last_room()
	if _name_edit.text.is_empty():
		_name_edit.text = player_name

func _show_playing() -> void:
	_join_panel.visible = false
	_hud.visible = true
	_menu_panel.visible = false
	_wait_label.visible = true
	_refresh_lobby()

func join_screen_visible() -> bool:
	return _join_panel != null and _join_panel.visible

func lobby_visible() -> bool:
	return _lobby_panel != null and _lobby_panel.visible

func menu_visible() -> bool:
	return _menu_panel != null and _menu_panel.visible

func _is_host() -> bool:
	return slot >= 0 and int(lobby.get("host", -1)) == slot

## The host's deltas for this seat (#503): added to the totals and saved.
## The host says this seat earned an achievement (#689): unlock it on this PC's
## own Steam account. `unlock()` ignores an id it does not know.
func _on_achievement(msg: Dictionary) -> void:
	var achievements: Node = get_node_or_null(^"/root/Achievements")
	if achievements != null:
		achievements.unlock(str(msg.get("id", "")))

func _on_career(msg: Dictionary) -> void:
	career = CareerScript.add(career, msg.get("d"))
	CareerScript.save_totals(career_path, career)
	_refresh_career()

## The compact line under the room title; a tap opens all six stats.
func career_text() -> String:
	if not _career_open:
		return tr("CAREER_LINE") % [int(career.get("matches", 0)), int(career.get("match_wins", 0)), int(career.get("kos", 0))]
	var favourite: String = CareerScript.favourite(career)
	return "\n".join([
		tr("CAREER_MATCHES") % int(career.get("matches", 0)),
		tr("CAREER_MATCH_WINS") % int(career.get("match_wins", 0)),
		tr("CAREER_ROUND_WINS") % int(career.get("round_wins", 0)),
		tr("CAREER_KOS") % int(career.get("kos", 0)),
		tr("CAREER_SELF_KOS") % int(career.get("self_kos", 0)),
		tr("CAREER_FAVOURITE") % (favourite if not favourite.is_empty() else "-"),
	])

## Issue #1033: copies the room code and reads "Copied" for 1.5 s, exactly as
## the host's Copy code does (#863). Client-side only; the host's Hide room
## code setting is its own screen's.
func copy_room_code() -> void:
	if room_code.is_empty():
		return
	_copied_until_msec = CopyCodeScript.press(room_code, clipboard_setter, get_tree(), _sync_copy_button)
	_sync_copy_button()

func _sync_copy_button() -> void:
	if _copy_button == null:
		return
	_copy_button.text = tr(CopyCodeScript.caption_key(_copied_until_msec, false))
	# Only in the plain lobby: not through a countdown, a match or the podium.
	_copy_button.visible = str(lobby.get("phase", "")) == "lobby" and not room_code.is_empty()

func _refresh_career() -> void:
	if _career_button != null:
		_career_button.text = career_text()

func _refresh_lobby() -> void:
	if _lobby_panel == null or state != State.PLAYING:
		return
	var phase: String = str(lobby.get("phase", ""))
	# Issue #976: on victory the host's own victory screen shows instead.
	_lobby_panel.visible = phase == "lobby" or phase == "countdown" or (phase == "victory" and not victory_visible())
	if phase == "countdown":
		_lobby_title.text = tr("JOIN_ROOM_STARTING") % [room_code, int(lobby.get("count", 0))]
	elif phase == "victory":
		_lobby_title.text = tr("JOIN_ROOM_OVER") % room_code
	else:
		_lobby_title.text = tr("JOIN_ROOM_TITLE") % room_code
	for child in _lobby_list.get_children():
		_lobby_list.remove_child(child)
		child.queue_free()
	for entry: Variant in lobby.get("players", []):
		if entry is Dictionary:
			var line: String = str(entry.get("name", "")) if not str(entry.get("name", "")).is_empty() else "P%d" % (int(entry.get("slot", 0)) + 1)
			if entry.get("ready", false):
				line = tr("JOIN_PLAYER_READY") % line
			if entry.has("ping"):
				line += "  " + tr("PING_MS") % int(entry["ping"])
			var color := Color.html(str(entry.get("color", "ffffff")))
			_lobby_list.add_child(_label(line, 20, color))
	var host: bool = _is_host()
	_host_row.visible = host
	_mode_button.text = tr("MODE_TEAMS") if lobby.get("mode") == "teams" else tr("MODE_FFA")
	_target_label.text = tr(_target_label_key(str(lobby.get("target_kind", "first_to")))) % int(lobby.get("target", 5))
	_pause_button.visible = host
	_pause_button.text = tr("JOIN_RESUME_MATCH") if lobby.get("paused", false) else tr("JOIN_PAUSE_MATCH")
	_ready_button.visible = phase != "playing" and phase != "round_end"
	_sync_copy_button()
	_cosmetics_panel.visible = (phase == "lobby" or phase == "countdown") and not _own_ready()
	if _ready_want != -1 and (_own_ready() == (_ready_want == 1) or GameClockScript.now_msec() - _ready_want_msec > 3000):
		_ready_want = -1 # the host's echo arrived (or never will): mirror again (#550)
	if _ready_want == -1:
		_ready_button.set_pressed_no_signal(_own_ready()) # mirror the server: it clears ready at match start and victory (#518)
	_sync_capture()

func _refresh_hud() -> void:
	if _hud == null:
		return
	_wait_label.visible = false
	# The modifier banner shows while the host's does (the snapshot's
	# announcer text), in the same ModifierBanner label.
	var banner: String = str(_world.get("announcer_text", ""))
	_modifier_label.text = banner
	_modifier_label.visible = not banner.is_empty()
	var phase: int = int(_world.get("round_phase", 0))
	if phase != _last_round_phase and effects != null:
		if phase == PHASE_ROUND_ACTIVE:
			effects.round_started()
		elif phase != PHASE_ROUND_END:
			effects.round_left()
	_last_round_phase = phase
	_refresh_extras()

## The parts of the host screen that come from the `hud` frame (issues #436,
## #976): the host's HUD scene and mode HUD in the host's state, and the
## host's victory screen with every award.
func _refresh_extras() -> void:
	if _hud == null or _host_hud == null:
		return
	# Unpacked and applied only when the host's frame changed it.
	var ui_text: String = str(hud.get("ui", ""))
	if ui_text != _ui_text:
		_ui_text = ui_text
		_screens = RemoteHudScript.unpack(ui_text, {})
		UiMirrorScript.apply(_host_hud, _screens.get("main", {}) if _screens.get("main") is Dictionary else {})
	var screens: Dictionary = _screens
	var phase: String = str(lobby.get("phase", ""))
	# The host's lobby screen covers its HUD; the joiner's lobby panel is here.
	_host_hud.visible = phase != "lobby" and phase != "countdown" and state == State.PLAYING
	if effects == null:
		return
	var mode_state: Dictionary = screens.get("mode", {}) if screens.get("mode") is Dictionary else {}
	effects.apply_mode_hud(str(screens.get("mode_script", "")), mode_state)
	effects.set_numbers(screens.get("numbers"))
	if effects.mode_hud != null:
		effects.mode_hud.visible = _host_hud.visible
	var victory_text: String = str(hud.get("victory", "")) if int(hud.get("state", 0)) == RemoteHudScript.STATE_VICTORY else ""
	if victory_text != _victory_text:
		_victory_text = victory_text
		effects.show_victory(RemoteHudScript.unpack(victory_text, {}))
	_refresh_lobby()

## Whether the host's victory screen is up on this joiner (#976).
func victory_visible() -> bool:
	return effects != null and effects.victory_visible()

# --- Cosmetics picker (issue #441) ------------------------------------------------

## The mouse panel in this lobby, shown until the player readies up.
func cosmetics_panel() -> Control:
	return _cosmetics_panel

func _own_ready() -> bool:
	for entry: Variant in lobby.get("players", []):
		if entry is Dictionary and int(entry.get("slot", -1)) == slot:
			return bool(entry.get("ready", false))
	return false

## A `looks` frame: the full one (with the palette) on binding, then updates.
func _on_looks(msg: Dictionary) -> void:
	if msg.has("palette"):
		looks = msg.duplicate(true)
		_cosmetics_panel.set_catalog(msg)
	elif msg.get("looks") is Array:
		looks["looks"] = msg["looks"]
	if msg.get("looks") is Array:
		_cosmetics_panel.set_looks(msg["looks"], slot)

## A click on the panel: tell the host (the phone's own frame) and save it.
func _on_cosmetic_picked(kind: String, value: Variant) -> void:
	saved_pick[kind] = value
	saved_pick = CosmeticsPickerScript.clean_pick(saved_pick)
	_save_settings()
	_send_json({"t": kind, "v": value})
# --- Rejoining a held seat (issue #459) ------------------------------------------

## Whether the client is retrying its way back into the match it dropped from.
func rejoining() -> bool:
	return _rejoin_until_msec > Time.get_ticks_msec()

## After a network failure, keep retrying the same room until `until` (wall
## msec); a refusal (kick, no slot, room gone) goes through `_return_to_join()`
## alone and so ends the retries.
func _keep_rejoining(until: int) -> void:
	if until <= Time.get_ticks_msec() or room_code.is_empty():
		return
	_rejoin_until_msec = until
	_rejoin_next_msec = Time.get_ticks_msec() + REJOIN_RETRY_MSEC
	var lost: String = tr("JOIN_LOST") if status_text.is_empty() else status_text
	_set_status(lost + " " + tr("JOIN_REJOINING"))

func _watch_snapshots() -> void:
	if state != State.PLAYING:
		_last_snapshot_msec = 0
		return
	var now: int = Time.get_ticks_msec()
	if _last_snapshot_msec == 0:
		_last_snapshot_msec = now
	elif now - _last_snapshot_msec > SNAPSHOT_WATCHDOG_MSEC:
		_last_snapshot_msec = 0
		_return_to_join(tr("JOIN_LOST"))
		_keep_rejoining(now + ControllerServerScript.REMOTE_SEAT_HOLD_MSEC)

func _tick_rejoin() -> void:
	if _rejoin_until_msec == 0 or state != State.JOIN:
		return
	var now: int = Time.get_ticks_msec()
	if now >= _rejoin_until_msec:
		_rejoin_until_msec = 0
		_set_status(tr("JOIN_LOST"))
		return
	if now < _rejoin_next_msec:
		return
	var until: int = _rejoin_until_msec
	if not join(room_code, player_name):
		_keep_rejoining(until)

## The host row's target label per `target_kind` (#544), as `GameModes.target_label_key`.
func _target_label_key(kind: String) -> String:
	match kind:
		"lives":
			return "LOBBY_LIVES"
		"goals":
			return "LOBBY_GOALS_TO_WIN"
		"captures":
			return "LOBBY_CAPTURES_TO_WIN"
	return "LOBBY_FIRST_TO"

## #711: Steam's floating gamepad keyboard for a text field, through the autoload
## by path; a build or test tree without it does nothing.
func _attach_pad_keyboard(edit: Control) -> void:
	var steam: Node = get_node_or_null(^"/root/SteamPlatform")
	if steam != null:
		steam.call("attach_text_input", edit)
