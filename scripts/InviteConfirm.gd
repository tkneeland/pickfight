extends CanvasLayer

## A Steam friend's invite reached a host who has another human seated (#1075, #298):
## "A friend invited you to a room. Leave yours? This ends it for everyone in it."
## with Join and Stay. Enter or Y joins, Esc or N stays, A joins and B stays on a
## gamepad, and the mouse works. There is no timeout and the match keeps running behind
## it. If the room empties while it is open it just joins. Built in code, added over the
## host screen by SteamPlatform, which acts on `decided`.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")
const PadMenuScript := preload("res://scripts/PadMenu.gd")
const QuitGameScript := preload("res://scripts/QuitGame.gd")

## true: leave this room and join the friend's; false: stay and drop the invite.
signal decided(join: bool)

var _server: Object
var _join_button: Button
var _stay_button: Button
var _done: bool = false

func _init(server: Object = null) -> void:
	_server = server
	layer = 120
	name = "InviteConfirm"

func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	margin.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.text = tr("INVITE_CONFIRM_TITLE")
	title.theme_type_variation = UiThemeScript.TITLE_HEADING_LABEL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var text := Label.new()
	text.name = "Text"
	text.text = tr("INVITE_CONFIRM_TEXT")
	text.theme_type_variation = UiThemeScript.MUTED_HINT_LABEL
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 32)
	box.add_child(row)
	_join_button = ScreenKitScript.themed_button(tr("INVITE_JOIN"), UiThemeScript.ACTION_BUTTON, "Invite_join", true)
	_join_button.pressed.connect(_decide.bind(true))
	row.add_child(_join_button)
	_stay_button = ScreenKitScript.themed_button(tr("INVITE_STAY"), UiThemeScript.ACTION_BUTTON, "Invite_stay", true)
	_stay_button.pressed.connect(_decide.bind(false))
	row.add_child(_stay_button)
	_join_button.focus_neighbor_right = _join_button.get_path_to(_stay_button)
	_stay_button.focus_neighbor_left = _stay_button.get_path_to(_join_button)
	PadMenuScript.set_open("invite", true) # A must not seat a gamepad behind it
	_join_button.grab_focus()

func _exit_tree() -> void:
	PadMenuScript.set_open("invite", false)

func join_button() -> Button:
	return _join_button

func stay_button() -> Button:
	return _stay_button

## Joins as soon as nobody but the host and bots is left in the room.
func _process(_delta: float) -> void:
	if not _done and _server != null and is_instance_valid(_server) and not QuitGameScript.others_seated(_server):
		_decide(true)

func _input(event: InputEvent) -> void:
	if _done:
		return
	var join: bool = false
	var stay: bool = false
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		join = key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_Y]
		stay = key.physical_keycode in [KEY_ESCAPE, KEY_N]
	elif PadMenuScript.pressed(event, JOY_BUTTON_A):
		join = true
	elif PadMenuScript.pressed(event, JOY_BUTTON_B):
		stay = true
	if join or stay:
		get_viewport().set_input_as_handled()
		_decide(join)

func _decide(join: bool) -> void:
	if _done:
		return
	_done = true
	decided.emit(join)
