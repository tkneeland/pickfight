extends Node

## The one place the game talks to Steam (docs/steam-readiness.md item 6.1).
## An autoload beside `Sfx` and `Music`, reached by path, never by
## `class_name`; GodotSteam itself is reached only through the engine's
## singleton registry, so a build without the addon, without the Steam client
## or running headless still starts and plays. Every failure logs one line and
## leaves `available` false.
##
## Later tickets build on this: achievements (#689) call `set_achievement` and
## `store_stats`; persona names (#538) read `persona_name()`.
##
## Dev checkouts test against Spacewar (app ID 480) through a git-ignored
## `steam_appid.txt` at the repo root; see docs/steam-readiness.md.

const APP_ID_SETTING := "pickfight/steam_app_id"
const DEFAULT_APP_ID := 480

## True only once Steam answered the init call.
var available: bool = false
var app_id: int = 0

## Test seam (#538): a non-empty value stands in for the Steam persona name.
var fake_persona_for_test: String = ""

## Test seam (#298): true makes every invite wrapper act as if Steam were
## running, recording the call in `calls_for_test` instead of reaching GodotSteam.
var fake_running_for_test: bool = false
## Test seam (#298): each wrapper call as `[name, args...]`, in order.
var calls_for_test: Array = []

## #298: a Steam friend asked to join `code` (valid Online room code). Fired
## from a runtime Join Game and from `emit_join_for_test`.
signal join_requested(code: String)

## The connect string key in the launch args and the rich presence payload.
const CONNECT_FLAG := "+pickfight_room"
const RemoteClientScript := preload("res://scripts/RemoteClient.gd")
const InviteConfirmScript := preload("res://scripts/InviteConfirm.gd")
const QuitGameScript := preload("res://scripts/QuitGame.gd")
const REMOTE_CLIENT_SCENE := "res://scenes/RemoteClient.tscn"

## A room code from a launch/connect request that arrived with no join screen
## to take it; RemoteClient consumes it with `take_pending_join_code()`.
var pending_join_code: String = ""

var _steam: Object = null

func _ready() -> void:
	app_id = int(ProjectSettings.get_setting(APP_ID_SETTING, DEFAULT_APP_ID))
	if not Engine.has_singleton("Steam"):
		print("SteamPlatform: GodotSteam not present, Steam off")
		return
	var tree := get_tree()
	if (tree != null and tree.get_script() != null) or DisplayServer.get_name() == "headless":
		return
	var steam: Object = Engine.get_singleton("Steam")
	var result: Variant = steam.call("steamInitEx", app_id)
	# steamInitEx returns {"status": int, "verbal": String}; 0 (OK) means ready.
	if typeof(result) != TYPE_DICTIONARY or int(result.get("status", 1)) != 0:
		var why: String = str(result.get("verbal", "unknown")) if typeof(result) == TYPE_DICTIONARY else "unknown"
		print("SteamPlatform: Steam init failed (%s), Steam off" % why)
		return
	_steam = steam
	available = true
	if steam.has_signal("join_game_requested"):
		steam.connect("join_game_requested", _on_join_game_requested)
	pending_join_code = parse_connect(" ".join(OS.get_cmdline_args()) + " " + " ".join(OS.get_cmdline_user_args()))
	print("SteamPlatform: Steam ready (app %d)" % app_id)

func _process(_delta: float) -> void:
	if available:
		_steam.call("run_callbacks")

## The player's Steam name, or "" when Steam is not running.
func persona_name() -> String:
	if not fake_persona_for_test.is_empty():
		return fake_persona_for_test
	if not available:
		return ""
	return str(_steam.call("getPersonaName"))

## The player's 64-bit Steam ID, or 0 when Steam is not running.
func steam_id() -> int:
	if not available:
		return 0
	return int(_steam.call("getSteamID"))

## Unlock an achievement by its Steamworks API name. False when Steam is not
## running or refused it.
func set_achievement(api_name: String) -> bool:
	if not available:
		return false
	return bool(_steam.call("setAchievement", api_name))

## Push pending stat and achievement changes to Steam. False when unavailable.
func store_stats() -> bool:
	if not available:
		return false
	return bool(_steam.call("storeStats"))

# --- Friend invites (#298) -------------------------------------------------------

## Whether invite calls reach Steam: it is running, or the test seam says so.
func running() -> bool:
	return available or fake_running_for_test

## The valid room code in a connect string ("+pickfight_room ABCD", or a whole
## command line containing it), else "". Same rules as a typed code: upper-case,
## the relay's alphabet, full length; anything else is garbage.
static func parse_connect(text: String) -> String:
	var tokens: PackedStringArray = text.split(" ", false)
	var at: int = tokens.find(CONNECT_FLAG)
	if at < 0 or at + 1 >= tokens.size():
		return ""
	var raw: String = tokens[at + 1]
	var code: String = RemoteClientScript.normalize_code(raw)
	if code != raw.to_upper() or not RemoteClientScript.code_is_complete(code):
		return ""
	return code

## The connect string a friend's Join Game hands back for `code`.
static func connect_string(code: String) -> String:
	return "%s %s" % [CONNECT_FLAG, code]

## Show friends a Join Game button for `code` plus a short status line.
func set_rich_presence(code: String, status: String) -> void:
	if not running():
		return
	calls_for_test.append(["set_rich_presence", code, status])
	if available:
		_steam.call("setRichPresence", "connect", connect_string(code))
		_steam.call("setRichPresence", "status", status)

## Take the Join Game button and status away (the room closed).
func clear_rich_presence() -> void:
	if not running():
		return
	calls_for_test.append(["clear_rich_presence"])
	if available:
		_steam.call("clearRichPresence")

## Open Steam's overlay "invite friends" dialog carrying `code`.
func open_invite_dialog(code: String) -> void:
	if not running():
		return
	calls_for_test.append(["open_invite_dialog", code])
	if available:
		_steam.call("activateGameOverlayInviteDialogConnectString", connect_string(code))

## The launch-arg room code, once; "" when there is none.
func take_pending_join_code() -> String:
	var code: String = pending_join_code
	pending_join_code = ""
	return code

## Test seam: act as if a friend accepted an invite with `connect`.
func emit_join_for_test(connect: String) -> void:
	_on_join_game_requested(0, connect)

func _on_join_game_requested(_friend: int, connect: String) -> void:
	var code: String = parse_connect(connect)
	if code.is_empty():
		return # garbage payload: ignored
	if get_signal_connection_list("join_requested").is_empty():
		pending_join_code = code
		_open_join_screen_if_idle()
	join_requested.emit(code)

## Test seams (#1075): `join_screen_for_test`, when valid, stands in for the scene change to the join
## screen; `invite_scene_for_test` stands in for the current scene, which a `-s` run does not have.
var join_screen_for_test: Callable = Callable()
var invite_scene_for_test: Node = null
## The open "Leave your room?" prompt (InviteConfirm.gd), or null.
var invite_confirm: Node = null

## A friend's Join Game from the host's own screen is never ignored (#1075). A host alone or with only
## bots goes to the PC join screen at once. A host with another human seated, in the lobby, a
## countdown or mid-match, is asked first: the match keeps running behind the prompt, a second invite
## replaces the pending code, and Stay drops it. Joining closes the room on the scene change, so the
## others see Host left.
func _open_join_screen_if_idle() -> void:
	var tree := get_tree()
	var scene: Node = invite_scene_for_test if invite_scene_for_test != null else (tree.current_scene if tree != null else null)
	if tree == null or scene == null or (fake_running_for_test and not join_screen_for_test.is_valid()):
		return
	if invite_confirm != null and is_instance_valid(invite_confirm):
		return # already asking: the new code replaced the pending one
	var server: Node = null
	for node: Node in scene.find_children("*", "", true, false):
		if node.has_method("host_pc_slot") and node.has_method("claimed_slots"):
			server = node
			break
	if server == null or not QuitGameScript.others_seated(server):
		_go_to_join_screen()
		return
	invite_confirm = InviteConfirmScript.new(server)
	invite_confirm.decided.connect(_on_invite_decided)
	tree.root.add_child(invite_confirm)

func _on_invite_decided(join: bool) -> void:
	if invite_confirm != null and is_instance_valid(invite_confirm):
		invite_confirm.queue_free()
	invite_confirm = null
	if join:
		_go_to_join_screen()
	else:
		pending_join_code = "" # Stay: the invite is dropped

func _go_to_join_screen() -> void:
	if join_screen_for_test.is_valid():
		join_screen_for_test.call()
		return
	get_tree().change_scene_to_file.call_deferred(REMOTE_CLIENT_SCENE)

# --- Store page (#793) -----------------------------------------------------------

## Test seam (#793): when valid, stands in for `OS.shell_open` and receives the URL.
var shell_open_for_test: Callable = Callable()

## Open the store page for `store_app_id` (the base game's Steam app ID): in the Steam
## overlay when Steam runs, else in the system browser at `url`. Does nothing for an
## unset app ID (0 or less).
func open_store_page(store_app_id: int, url: String) -> void:
	if store_app_id <= 0:
		return
	if running():
		calls_for_test.append(["open_store_page", store_app_id])
		if available:
			_steam.call("activateGameOverlayToStore", store_app_id, 0) # 0: STORE_FLAG_NONE
		return
	if url.is_empty():
		return
	if shell_open_for_test.is_valid():
		shell_open_for_test.call(url)
	else:
		OS.shell_open(url)

# --- Timeline markers (#703) -----------------------------------------------------

## Steam built-in icon and priority (0-1000) per marker kind.
const TIMELINE_KINDS := {
	"ko": {"icon": "steam_combat", "priority": 50},
	"round_win": {"icon": "steam_crown", "priority": 80},
	"match_win": {"icon": "steam_achievement", "priority": 100},
}
## Steam's "featured" clip suggestion (0 none, 1 standard, 2 featured).
const TIMELINE_CLIP_FEATURED := 2

## Drop a marker on the player's Steam Timeline (and clip it). `kind` is "ko",
## "round_win" or "match_win"; anything else is ignored. Does nothing without Steam.
func add_timeline_event(kind: String, title: String) -> void:
	if not running() or not TIMELINE_KINDS.has(kind):
		return
	calls_for_test.append(["add_timeline_event", kind, title])
	if not available:
		return
	var spec: Dictionary = TIMELINE_KINDS[kind]
	if _steam.has_method("addInstantaneousTimelineEvent"):
		_steam.call("addInstantaneousTimelineEvent", title, "", spec["icon"], spec["priority"], 0.0, TIMELINE_CLIP_FEATURED)
	elif _steam.has_method("addTimelineEvent"):
		_steam.call("addTimelineEvent", spec["icon"], title, "", spec["priority"], 0.0, 0.0, TIMELINE_CLIP_FEATURED)

# --- Gamepad text input (#711) ---------------------------------------------------

## True while the last input was a gamepad's (same rule as HostControls.pad_active,
## which decides the captions' glyphs, but fed from the autoload so a screen with
## no host controls, like the PC join screen, can ask too).
var pad_input_active: bool = false

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		pad_input_active = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad_input_active = false

## Open Steam's floating gamepad keyboard over the screen rect (x, y, w, h), single
## line. It types into the focused Godot control as key events, so nothing is
## written back. Falls back to the full-screen keyboard on older GodotSteam, whose
## result is written back to `_text_target` on dismissal. False without Steam.
func show_text_input(x: int, y: int, w: int, h: int) -> bool:
	if not running():
		return false
	calls_for_test.append(["show_text_input", x, y, w, h])
	if not available:
		return true
	if _steam.has_method("showFloatingGamepadTextInput"):
		return bool(_steam.call("showFloatingGamepadTextInput", 0, x, y, w, h))
	if _steam.has_method("showGamepadTextInput"):
		if _steam.has_signal("gamepad_text_input_dismissed") and not _steam.is_connected("gamepad_text_input_dismissed", _on_text_dismissed):
			_steam.connect("gamepad_text_input_dismissed", _on_text_dismissed)
		return bool(_steam.call("showGamepadTextInput", 0, 0, "", 256, ""))
	return false

var _text_target: Control = null

func _on_text_dismissed(submitted: bool, _length: int) -> void:
	if not submitted or _text_target == null or not is_instance_valid(_text_target):
		return
	var text: String = str(_steam.call("getEnteredGamepadTextInput"))
	if _text_target is LineEdit or _text_target is TextEdit:
		_text_target.text = text

## Make `control` (a LineEdit or TextEdit) raise the gamepad keyboard when it gains
## focus while a gamepad is the active input. Mouse and keyboard focus do nothing.
func attach_text_input(control: Control) -> void:
	control.focus_entered.connect(_on_text_focus.bind(control))

func _on_text_focus(control: Control) -> void:
	if not pad_input_active or not running():
		return
	_text_target = control
	var scale: Vector2 = control.get_global_transform_with_canvas().get_scale()
	var at: Vector2 = control.get_screen_position()
	show_text_input(int(at.x), int(at.y), int(control.size.x * scale.x), int(control.size.y * scale.y))
