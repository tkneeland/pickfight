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
const RelayLinkScript: GDScript = preload("res://scripts/RelayLink.gd")
const ControllerServerScript: GDScript = preload("res://scripts/ControllerServer.gd")
const PuppetScript: GDScript = preload("res://scripts/RemotePuppet.gd")
const PaletteScript: GDScript = preload("res://scripts/Palette.gd")
const PickupWeaponsScript: GDScript = preload("res://scripts/PickupWeapons.gd")
const TeamsScript: GDScript = preload("res://scripts/Teams.gd")
const StageScript: GDScript = preload("res://scripts/Stage.gd")
const CosmeticsPickerScript: GDScript = preload("res://scripts/CosmeticsPicker.gd")
const CosmeticsPanelScript: GDScript = preload("res://scripts/OnlineCosmeticsPanel.gd")
const DemoBuildScript := preload("res://scripts/DemoBuild.gd")

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
var join_timeout_msec: int = JOIN_TIMEOUT_MSEC
var client_id: String = ""
var player_name: String = ""
## Sent in the hello; a scenario sets another to see a version mismatch refused.
var protocol_version: int = ControllerServerScript.PROTOCOL_VERSION
## Sent in the hello (#447): the host refuses a build that is not its own.
## A scenario sets it to try the other build against the same host.
var demo_build: bool = DemoBuildScript.is_active()
var room_code: String = ""
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
var _hud_signature: String = ""
## Issue #459: after a dropped connection mid-match the client rejoins by
## itself, every REJOIN_RETRY_MSEC, until the host's seat hold would have run
## out (wall clock here; the host counts it in game time). 0 when not rejoining.
const REJOIN_RETRY_MSEC: int = 1500
var _rejoin_until_msec: int = 0
var _rejoin_next_msec: int = 0

var _camera: Camera2D
var _world_root: Node2D
var _stage_holder: Node2D
var _puppet_holder: Node2D
var _ui: CanvasLayer
var _join_panel: Control
var _room_edit: LineEdit
var _name_edit: LineEdit
var _status_label: Label
var _join_button: Button
var _cancel_button: Button
var _update_link: LinkButton
var _hud: Control
var _score_box: VBoxContainer
var _feed_label: Label
var _banner_label: Label
var _mode_label: Label
var _result_label: Label
var _podium_label: Label
var _leave_button: Button
var _wait_label: Label
var _lobby_panel: Control
var _lobby_title: Label
var _lobby_list: VBoxContainer
var _ready_button: Button
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
	if client_id.is_empty():
		client_id = _random_id()
		_save_settings()
	_build_world()
	_build_ui()
	_show_join_screen()
	get_viewport().size_changed.connect(_fit_camera)

func _exit_tree() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	_set_captured(false)

func _process(_delta: float) -> void:
	if _socket != null:
		_poll_socket()
	_tick_rejoin()
	if state == State.PLAYING:
		_render()

func _physics_process(_delta: float) -> void:
	if state == State.PLAYING:
		_pad_input()
		_send_input()

## #435: a gamepad's right stick drives the arm too, as a gamepad seat's does on
## the host (#261). While the stick is out it sets the vector; let go, and the
## arm rests until the stick or the mouse moves again.
var test_pad_stick: Variant = null # a Vector2 here stands in for a real pad (headless has none)
var _pad_driving: bool = false

func _pad_input() -> void:
	var stick := Vector2.ZERO
	if test_pad_stick is Vector2:
		stick = ControllerServerScript.stick_vector(test_pad_stick)
	else:
		for device: int in Input.get_connected_joypads():
			stick = ControllerServerScript.stick_vector(Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)))
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
	var pad_button := event as InputEventJoypadButton
	if pad_button != null and pad_button.pressed and not menu_open and (pad_button.button_index == JOY_BUTTON_A or pad_button.button_index == JOY_BUTTON_START) and _ready_button != null and _ready_button.is_visible_in_tree():
		_ready_button.button_pressed = not _ready_button.button_pressed # A or Start readies in the lobby (#518)
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
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		toggle_menu()
		get_viewport().set_input_as_handled()

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
		"looks":
			_on_looks(msg)
		"ping":
			_send_json({"t": "pong", "n": msg.get("n", 0)})
		"release":
			pass # the host owns the toggle now (#481)
		"closed":
			_return_to_join(reason_text(str(msg.get("reason", "closed"))))
		"error":
			var reason: String = str(msg.get("reason", "unknown"))
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
	body.resize(10)
	body.encode_float(0, v.x)
	body.encode_float(4, v.y)
	body[8] = 1 if released else 0
	body[9] = action_presses | (0x80 if _action_was_hold else 0)
	_send_envelope(RelayLinkScript.KIND_INPUT, body)
	input_frames_sent += 1

## The mouse moved by `relative` pixels while captured (what `_input` calls).
func mouse_motion(relative: Vector2) -> void:
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

func toggle_menu() -> void:
	if state != State.PLAYING:
		return
	if menu_open:
		resume()
		return
	menu_open = true
	_mouse.reset()
	input_vector = Vector2.ZERO
	_set_captured(false)
	_menu_panel.visible = true
	_refresh_lobby()

func resume() -> void:
	if state != State.PLAYING:
		return
	menu_open = false
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

## Applies a decoded snapshot: a full one becomes the new world (and snaps the
## puppets), a delta is merged onto the last full one. A delta with no full
## snapshot before it is dropped.
func apply_snapshot(snap: Dictionary) -> void:
	if snap.get("is_full_snapshot", false):
		_world = snap.duplicate(true)
		_samples.clear()
		full_frames_applied += 1
		_sync_stage()
	else:
		if _world.is_empty():
			return
		_apply_delta(snap.get("delta_entities", []))
	frames_applied += 1
	_push_sample()
	_refresh_hud()

func world() -> Dictionary:
	return _world

static func _find_by(list: Array, key: String, id: int) -> Dictionary:
	for entry: Variant in list:
		if entry is Dictionary and int(entry.get(key, -1)) == id:
			return entry
	return {}

func _apply_delta(entities: Array) -> void:
	for ent: Variant in entities:
		if not ent is Dictionary:
			continue
		var e: Dictionary = ent
		var id: int = int(e.get("id", 0))
		match int(e.get("type", 0)):
			SnapshotScript.TYPE_PLAYER:
				var p: Dictionary = _find_by(_world.get("players", []), "player_id", id)
				if p.is_empty():
					continue
				var body: Dictionary = p.get("body", {})
				body["position"] = e.get("position", body.get("position", Vector2.ZERO))
				body["rotation"] = e.get("rotation", body.get("rotation", 0.0))
				body["linear_velocity"] = e.get("linear_velocity", body.get("linear_velocity", Vector2.ZERO))
				p["body"] = body
				var weapon: Dictionary = p.get("weapon", {})
				weapon["head_position"] = e.get("head_position", weapon.get("head_position", Vector2.ZERO))
				weapon["head_rotation"] = e.get("head_rotation", weapon.get("head_rotation", 0.0))
				weapon["head_shape_index"] = e.get("head_shape_index", weapon.get("head_shape_index", 0))
				p["weapon"] = weapon
				p["damage"] = e.get("damage", p.get("damage", 0))
				p["state"] = e.get("state", p.get("state", 1))
			SnapshotScript.TYPE_PROJECTILE:
				var pr: Dictionary = _find_by(_world.get("projectiles", []), "projectile_id", id)
				if not pr.is_empty():
					pr["position"] = e.get("position", pr.get("position", Vector2.ZERO))
					pr["velocity"] = e.get("velocity", pr.get("velocity", Vector2.ZERO))
			SnapshotScript.TYPE_PICKUP:
				var pk: Dictionary = _find_by(_world.get("pickups", []), "pickup_id", id)
				if not pk.is_empty():
					pk["position"] = e.get("position", pk.get("position", Vector2.ZERO))
			SnapshotScript.TYPE_FLAIL:
				var flail: Dictionary = _world.get("flail", {})
				if not flail.is_empty():
					flail["ball_position"] = e.get("pos1", flail.get("ball_position", Vector2.ZERO))
					flail["ball_velocity"] = e.get("pos2", flail.get("ball_velocity", Vector2.ZERO))
			SnapshotScript.TYPE_GRAPPLE:
				var grapple: Dictionary = _world.get("grapple", {})
				if not grapple.is_empty():
					grapple["hook_position"] = e.get("pos1", grapple.get("hook_position", Vector2.ZERO))
					grapple["rope_end"] = e.get("pos2", grapple.get("rope_end", Vector2.ZERO))
			SnapshotScript.TYPE_TIMER:
				_world["timer_ms"] = e.get("timer_ms", 0)
			SnapshotScript.TYPE_SCORES:
				var scores: Dictionary = _world.get("scores", {})
				scores[id] = e.get("score", 0)
				_world["scores"] = scores
			SnapshotScript.TYPE_KILL_ZONE:
				_world["kill_zone_height"] = e.get("height", 0)

func _push_sample() -> void:
	var sample: Dictionary = {"t": Time.get_ticks_msec(), "players": {}, "things": {}}
	for p: Variant in _world.get("players", []):
		if p is Dictionary:
			var body: Dictionary = p.get("body", {})
			var weapon: Dictionary = p.get("weapon", {})
			sample["players"][int(p.get("player_id", 0))] = [body.get("position", Vector2.ZERO),
				body.get("rotation", 0.0), weapon.get("head_position", Vector2.ZERO)]
	for p: Variant in _world.get("projectiles", []):
		if p is Dictionary:
			sample["things"]["proj%d" % int(p.get("projectile_id", 0))] = p.get("position", Vector2.ZERO)
	for p: Variant in _world.get("pickups", []):
		if p is Dictionary:
			sample["things"]["pick%d" % int(p.get("pickup_id", 0))] = p.get("position", Vector2.ZERO)
	var flail: Dictionary = _world.get("flail", {})
	if not flail.is_empty():
		sample["things"]["flail"] = flail.get("ball_position", Vector2.ZERO)
	var grapple: Dictionary = _world.get("grapple", {})
	if not grapple.is_empty():
		sample["things"]["hook"] = grapple.get("hook_position", Vector2.ZERO)
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

## Loads the host's stage by id when a round is on screen and frees it when not.
func _sync_stage() -> void:
	var want: int = int(_world.get("stage_id", 0)) if _round_shown() else -1
	if want == _stage_id:
		return
	if _stage != null:
		_stage_holder.remove_child(_stage)
		_stage.queue_free()
		_stage = null
	_stage_id = want
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
	_stage_holder.add_child(_stage)
	_fit_camera()

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
	_hud_signature = ""
	hud = {}
	if _puppet_holder != null:
		for child in _puppet_holder.get_children():
			_puppet_holder.remove_child(child)
			child.queue_free()

## The puppet of player `slot_id`, or null.
func player_puppet(slot_id: int) -> Node2D:
	return _puppets.get("player%d" % slot_id) as Node2D

func puppet_count(kind: int) -> int:
	var n: int = 0
	for puppet: Node in _puppets.values():
		if puppet.kind == kind:
			n += 1
	return n

func has_stage() -> bool:
	return _stage != null

func stage_id() -> int:
	return _stage_id

func _puppet(key: String, kind: int) -> Node2D:
	var puppet: Node2D = _puppets.get(key)
	if puppet == null:
		puppet = PuppetScript.new()
		puppet.kind = kind
		_puppet_holder.add_child(puppet)
		_puppets[key] = puppet
	return puppet

## Draws the newest state INTERP_MSEC late, blending the two samples around that
## moment so the 30 Hz stream moves smoothly.
func _render() -> void:
	if _samples.is_empty() or not _round_shown():
		_hide_puppets_except({})
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
		puppet.label = str(p.get("name", ""))
		puppet.damage = int(p.get("damage", 0))
		puppet.phase = int(p.get("state", 1))
		puppet.set_pose((from_pose[0] as Vector2).lerp(to_pose[0], alpha),
			lerp_angle(from_pose[1], to_pose[1], alpha),
			(from_pose[2] as Vector2).lerp(to_pose[2], alpha))
	for p: Variant in _world.get("projectiles", []):
		if p is Dictionary:
			var id: int = int(p.get("projectile_id", 0))
			_place_thing("proj%d" % id, PuppetScript.Kind.PROJECTILE, a, b, alpha, Color(1, 0.9, 0.3), "", live)
	for p: Variant in _world.get("pickups", []):
		if p is Dictionary:
			var id: int = int(p.get("pickup_id", 0))
			_place_thing("pick%d" % id, PuppetScript.Kind.PICKUP, a, b, alpha, Color(0.4, 0.9, 1.0), _weapon_name(int(p.get("weapon_type", 0))), live)
	if not _world.get("flail", {}).is_empty():
		_place_thing("flail", PuppetScript.Kind.PROJECTILE, a, b, alpha, Color(0.8, 0.8, 0.8), "", live)
	if not _world.get("grapple", {}).is_empty():
		_place_thing("hook", PuppetScript.Kind.PROJECTILE, a, b, alpha, Color(0.6, 1.0, 0.6), "", live)
	_hide_puppets_except(live)

func _place_thing(key: String, kind: int, a: Dictionary, b: Dictionary, alpha: float, color: Color, label: String, live: Dictionary) -> void:
	var to_pos: Variant = b["things"].get(key)
	# Issue #429: a thing the newest snapshot no longer holds is gone now, not
	# when the interpolation window moves past its last sample.
	if to_pos == null or not _samples.back()["things"].has(key):
		return
	var from_pos: Variant = a["things"].get(key, to_pos)
	live[key] = true
	var puppet: Node2D = _puppet(key, kind)
	puppet.color = color
	puppet.label = label
	puppet.position = (from_pos as Vector2).lerp(to_pos, alpha)
	puppet.queue_redraw()

func _hide_puppets_except(live: Dictionary) -> void:
	for key: String in _puppets.keys():
		if not live.has(key):
			_puppets[key].queue_free()
			_puppets.erase(key)

static func _weapon_name(index: int) -> String:
	if index <= 0 or index > PickupWeaponsScript.WEAPON_PATHS.size():
		return ""
	return PickupWeaponsScript.WEAPON_PATHS[index - 1].get_file().get_basename()

# --- Settings -----------------------------------------------------------------------------

func _load_settings() -> void:
	if settings_path.is_empty():
		return
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	player_name = str(config.get_value(SECTION, "name", ""))
	saved_pick = CosmeticsPickerScript.read_pick(config, SECTION)
	client_id = str(config.get_value(SECTION, "id", ""))
	var sens: Variant = config.get_value(SECTION, "sensitivity", 1.0)
	if (sens is float or sens is int) and is_finite(float(sens)):
		_mouse.sensitivity = clampf(float(sens), 0.1, 5.0)

func _save_settings() -> void:
	if settings_path.is_empty():
		return
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value(SECTION, "name", player_name)
	config.set_value(SECTION, "id", client_id)
	config.set_value(SECTION, "sensitivity", _mouse.sensitivity)
	CosmeticsPickerScript.write_pick(config, SECTION, saved_pick)
	config.save(settings_path)

static func _random_id() -> String:
	var out: String = ""
	for i in 8:
		out += "%02x" % (randi() % 256)
	return out

# --- UI ---------------------------------------------------------------------------------------

func _build_world() -> void:
	_world_root = Node2D.new()
	_world_root.name = "World"
	add_child(_world_root)
	_stage_holder = Node2D.new()
	_stage_holder.name = "Stage"
	_world_root.add_child(_stage_holder)
	_puppet_holder = Node2D.new()
	_puppet_holder.name = "Puppets"
	_world_root.add_child(_puppet_holder)
	_camera = Camera2D.new()
	_camera.name = "Camera"
	add_child(_camera)
	_camera.make_current()
	_fit_camera()

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	add_child(_ui)
	_build_hud()
	_build_lobby_panel()
	_build_menu_panel()
	_build_join_panel()

func _label(text: String, size: int = 20, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _centered_panel(parent: Control, min_width: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
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
	shade.color = Color(0.08, 0.09, 0.12)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_join_panel.add_child(shade)
	_ui.add_child(_join_panel)
	var box: VBoxContainer = _centered_panel(_join_panel, 360)
	box.add_child(_label(tr("JOIN_TITLE"), 30))
	box.add_child(_label(tr("JOIN_ROOM_CODE_LABEL")))
	_room_edit = LineEdit.new()
	_room_edit.name = "RoomCode"
	_room_edit.placeholder_text = "ABCD"
	_room_edit.max_length = CODE_LENGTH
	_room_edit.text_changed.connect(_on_room_text_changed)
	_room_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	box.add_child(_room_edit)
	box.add_child(_label(tr("JOIN_YOUR_NAME")))
	_name_edit = LineEdit.new()
	_name_edit.name = "PlayerName"
	_name_edit.placeholder_text = tr("JOIN_NAME_PLACEHOLDER")
	_name_edit.max_length = NAME_MAX_LENGTH
	_name_edit.text = player_name
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	box.add_child(_name_edit)
	_status_label = _label("", 18, Color(1.0, 0.7, 0.5))
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
	var cleaned: String = normalize_code(text)
	if cleaned != text:
		_room_edit.text = cleaned
		_room_edit.caret_column = cleaned.length()

func _on_join_pressed() -> void:
	join(_room_edit.text, _name_edit.text)

func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_hud)
	_score_box = VBoxContainer.new()
	_score_box.position = Vector2(16, 12)
	_hud.add_child(_score_box)
	_feed_label = _label("", 18)
	_feed_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed_label.position = Vector2(-16, 12)
	_feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_feed_label)
	_banner_label = _label("", 36, Color(1, 0.9, 0.4))
	_banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner_label.position = Vector2(0, 12)
	_hud.add_child(_banner_label)
	_mode_label = _label("", 22, Color(0.8, 0.95, 1.0))
	_mode_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mode_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mode_label.position = Vector2(0, 58)
	_hud.add_child(_mode_label)
	_result_label = _label("", 40, Color(1, 0.9, 0.4))
	_result_label.set_anchors_preset(Control.PRESET_CENTER)
	_result_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud.add_child(_result_label)
	_wait_label = _label(tr("JOIN_WAITING"), 28)
	_wait_label.set_anchors_preset(Control.PRESET_CENTER)
	_wait_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud.add_child(_wait_label)

func _build_lobby_panel() -> void:
	_lobby_panel = Control.new()
	_lobby_panel.name = "LobbyPanel"
	_lobby_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_lobby_panel)
	var box: VBoxContainer = _centered_panel(_lobby_panel, 380)
	_lobby_title = _label(tr("JOIN_LOBBY_TITLE"), 28)
	box.add_child(_lobby_title)
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
	_ready_button.toggled.connect(func(on: bool) -> void: _send_json({"t": "ready", "v": on}))
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
	_podium_label = _label("", 22)
	_podium_label.name = "Podium"
	box.add_child(_podium_label)
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
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_panel.add_child(shade)
	var box: VBoxContainer = _centered_panel(_menu_panel, 320)
	box.add_child(_label(tr("JOIN_PAUSED"), 28))
	var resume_button := Button.new()
	resume_button.name = "Resume"
	resume_button.text = tr("JOIN_RESUME")
	resume_button.pressed.connect(resume)
	box.add_child(resume_button)
	box.add_child(_label(tr("JOIN_MOUSE_SENS")))
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
		_name_edit.editable = not busy

func _show_join_screen() -> void:
	_join_panel.visible = true
	_hud.visible = false
	_lobby_panel.visible = false
	_menu_panel.visible = false
	_update_link.visible = false
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

func _refresh_lobby() -> void:
	if _lobby_panel == null or state != State.PLAYING:
		return
	var phase: String = str(lobby.get("phase", ""))
	_lobby_panel.visible = phase == "lobby" or phase == "countdown" or phase == "victory"
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
	_target_label.text = tr("LOBBY_FIRST_TO") % int(lobby.get("target", 5))
	_pause_button.visible = host
	_pause_button.text = tr("JOIN_RESUME_MATCH") if lobby.get("paused", false) else tr("JOIN_PAUSE_MATCH")
	_ready_button.visible = phase != "playing" and phase != "round_end"
	_cosmetics_panel.visible = (phase == "lobby" or phase == "countdown") and not _own_ready()
	_ready_button.set_pressed_no_signal(_own_ready()) # mirror the server: it clears ready at match start and victory (#518)
	_sync_capture()

func _refresh_hud() -> void:
	if _hud == null:
		return
	_wait_label.visible = false
	var scores: Dictionary = _world.get("scores", {})
	var names: Dictionary = {}
	var colors: Dictionary = {}
	for p: Variant in _world.get("players", []):
		if p is Dictionary:
			names[int(p.get("player_id", 0))] = str(p.get("name", ""))
			colors[int(p.get("player_id", 0))] = PaletteScript.PLAYERS[int(p.get("color", 0)) % PaletteScript.PLAYERS.size()]
	var signature: String = str(scores) + str(names)
	if signature != _hud_signature:
		_hud_signature = signature
		for child in _score_box.get_children():
			_score_box.remove_child(child)
			child.queue_free()
		for id: int in names:
			var shown: String = names[id] if not (names[id] as String).is_empty() else "P%d" % (id + 1)
			_score_box.add_child(_label("%s  %d" % [shown, int(scores.get(id, 0))], 20, colors[id]))
	var feed: PackedStringArray = PackedStringArray()
	for entry: Variant in _world.get("kill_feed", []):
		if entry is Dictionary:
			feed.append(str(entry.get("text", "")))
	_feed_label.text = "\n".join(feed)
	var banner: String = str(_world.get("announcer_text", ""))
	if banner.is_empty() and int(_world.get("timer_ms", 0)) > 0:
		banner = str(ceili(int(_world["timer_ms"]) / 1000.0))
	_banner_label.text = banner
	_refresh_extras()

## The parts of the host screen that come from the `hud` frame (issue #436).
## Plain text built here with `tr()`, so it follows the player's locale.
func _refresh_extras() -> void:
	if _hud == null:
		return
	var state: int = int(hud.get("state", 0))
	var banner: Array = hud.get("banner", [])
	if not banner.is_empty() and str(_banner_label.text).is_empty():
		_banner_label.text = ("%s %s" % banner).strip_edges()
	_mode_label.text = mode_text()
	_result_label.text = round_result_text() if state == PHASE_ROUND_END else ""
	_podium_label.text = podium_text()
	_podium_label.visible = not _podium_label.text.is_empty()

func _name_of(slot: int) -> String:
	for row: Variant in hud.get("board", []):
		if int(row[0]) == slot:
			return str(row[1]) if not str(row[1]).is_empty() else "P%d" % (slot + 1)
	return "P%d" % (slot + 1)

## The round's result line, or "" (the host's round-end banner).
func round_result_text() -> String:
	var team: int = int(hud.get("round_winner_team", -1))
	if team >= 0:
		return tr("HUD_TEAM_TAKES_ROUND") % TeamsScript.team_name(team)
	var winner: int = int(hud.get("round_winner", -1))
	if winner >= 0:
		return tr("HUD_TAKES_ROUND") % _name_of(winner)
	return tr("HUD_ROUND_DRAWN") if hud.has("round_winner") else ""

## The match podium once the match is over: places, names, scores.
func podium_text() -> String:
	if str(lobby.get("phase", "")) != "victory" or int(hud.get("state", 0)) != 5:
		return ""
	var lines: PackedStringArray = PackedStringArray()
	var team: int = int(lobby.get("winner_team", -1))
	var winner: int = int(lobby.get("winner", -1))
	if team >= 0:
		lines.append(tr("HUD_TEAM_WINS_MATCH") % TeamsScript.team_name(team))
	elif winner >= 0:
		lines.append(tr("HUD_WINS_MATCH") % _name_of(winner))
	var place: int = 0
	for row: Variant in hud.get("board", []):
		place += 1
		lines.append(tr("HUD_PODIUM_ROW") % [place, _name_of(int(row[0])), int(row[2])])
	return "\n".join(lines)

## The game mode's own HUD line, or "" (Classic has none).
func mode_text() -> String:
	var m: Dictionary = hud.get("m", {})
	if m.is_empty():
		return ""
	match str(hud.get("mode", "")):
		"king_of_the_hill":
			var parts: PackedStringArray = PackedStringArray()
			var hold: Dictionary = m.get("hold", {})
			for key: Variant in hold:
				parts.append(tr("HUD_HOLD") % [_name_of(int(key)), int(hold[key]), int(m.get("win", 0))])
			if bool(m.get("moving", false)):
				parts.append(tr("HUD_HILL_MOVING"))
			return "  ".join(parts)
		"capture_the_flag":
			var sc: Array = m.get("score", [0, 0])
			var fl: Array = m.get("flag", [0, 0])
			return tr("HUD_CTF") % [int(sc[0]), int(sc[1]), tr("HUD_FLAG_%d" % int(fl[0])), tr("HUD_FLAG_%d" % int(fl[1]))]
		"soccer":
			var sc2: Array = m.get("score", [0, 0])
			return tr("HUD_SOCCER") % [int(sc2[0]), int(sc2[1]), int(m.get("win", 0))]
		"hot_potato":
			return tr("HUD_POTATO") % [_name_of(int(m.get("it", -1))), int(m.get("fuse", 0))] if int(m.get("it", -1)) >= 0 else ""
		"stock":
			var lives: Dictionary = m.get("lives", {})
			var bits: PackedStringArray = PackedStringArray()
			for key2: Variant in lives:
				bits.append(tr("HUD_LIVES") % [_name_of(int(key2)), int(lives[key2])])
			var clock: String = str(m.get("clock", ""))
			return ("%s  " % clock if not clock.is_empty() else "") + "  ".join(bits)
	return ""

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
