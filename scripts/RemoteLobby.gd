extends RefCounted

## The Online joiner's lobby (#1127): the host's own `LobbyScreen` (logo, player
## cards, mode cards, room code card, How to play and Your look popups), built by
## the same scripts and fed the `lobby` frame the client already gets, so a joiner
## sees exactly what the host sees. There is no second copy of the drawing.
##
## What is the joiner's own is added to the screen's right column: Your look, How
## to play, the career line, the host seat's mode / target row, Leave
## match and Ready. It also answers the queries the cards make of a "server"
## (the seat's hat and eyes, which seat is this player's own) from the `looks`
## frame, so the joiner's own card reads "(you)" and opens Your look when clicked.
## Preloaded by path, never by `class_name` (CLAUDE.md).

const LobbyScreenScript: GDScript = preload("res://scripts/LobbyScreen.gd")
const ScreenKitScript: GDScript = preload("res://scripts/ScreenKit.gd")
const UiThemeScript: GDScript = preload("res://scripts/UiTheme.gd")

## Above the host's screens the joiner mirrors (HUD 1, victory 5, cards 10-12, flash 50),
## below its own menu and join panels (layer 60).
const SCREEN_LAYER: int = 59

var screen # LobbyScreen.gd
var title: Label
var career_button: Button
var look_button: Button
var help_button: Button
var host_row: HBoxContainer
var mode_button: Button
var target_label: Label
var leave_button: Button
var ready_button: Button

var own_slot: int = -1
var _looks: Array = []

func build(parent: Node, copy_pressed: Callable) -> void:
	screen = LobbyScreenScript.new()
	screen.layer = SCREEN_LAYER
	parent.add_child(screen)
	screen.build_panels()
	screen.attach_joiner(copy_pressed)
	title = ScreenKitScript.themed_label("", 28, UiThemeScript.HEADING_LABEL, HORIZONTAL_ALIGNMENT_LEFT, "RoomTitle")
	screen.top_left().add_child(title)
	var right: VBoxContainer = screen.right_column()
	career_button = Button.new()
	career_button.name = "Career"
	career_button.flat = true
	career_button.focus_mode = Control.FOCUS_NONE
	career_button.add_theme_color_override("font_color", Color("8F96BD"))
	right.add_child(career_button)
	look_button = ScreenKitScript.themed_button(screen.tr("PICKER_TITLE"), UiThemeScript.SKY_BUTTON, "look")
	look_button.pressed.connect(func() -> void: screen.set_popup("look"))
	right.add_child(look_button)
	help_button = ScreenKitScript.themed_button(screen.tr("HOW_TO_PLAY_BUTTON"), UiThemeScript.PINK_BUTTON, "how_to_play")
	help_button.pressed.connect(func() -> void: screen.set_popup("help"))
	right.add_child(help_button)
	host_row = HBoxContainer.new()
	host_row.name = "HostMenu"
	host_row.add_theme_constant_override("separation", 8)
	right.add_child(host_row)
	mode_button = ScreenKitScript.themed_button("", UiThemeScript.SWITCH_BUTTON, "Mode")
	host_row.add_child(mode_button)
	var down: Button = ScreenKitScript.themed_button("-", UiThemeScript.STEP_BUTTON, "TargetDown")
	host_row.add_child(down)
	target_label = ScreenKitScript.themed_label("", 22, UiThemeScript.MUTED_LABEL, HORIZONTAL_ALIGNMENT_CENTER, "TargetLabel")
	target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_row.add_child(target_label)
	var up: Button = ScreenKitScript.themed_button("+", UiThemeScript.STEP_BUTTON, "TargetUp")
	host_row.add_child(up)
	leave_button = ScreenKitScript.themed_button(screen.tr("JOIN_LEAVE_MATCH"), UiThemeScript.ACTION_BUTTON, "LeaveLobby")
	right.add_child(leave_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(spacer)
	ready_button = ScreenKitScript.themed_button("", UiThemeScript.START_BUTTON, "Ready", true)
	ready_button.toggle_mode = true
	right.add_child(ready_button)
	right.move_child(screen._lobby_status, right.get_child_count() - 1)
	# The host's stages button and summary column are the host's; the joiner keeps the summary line.
	down.pressed.connect(func() -> void: step_target.emit(-1))
	up.pressed.connect(func() -> void: step_target.emit(1))
	mode_button.pressed.connect(func() -> void: toggle_mode.emit())

signal step_target(delta: int)
signal toggle_mode

## The look panel in the Your look popup, which the client binds to its seat.
func look_panel() -> Control:
	return screen._popups.look_panel()

func set_looks(list: Array) -> void:
	_looks = list

# --- What the cards ask a server --------------------------------------------------

func is_joiner_view() -> bool:
	return true

func match_kind() -> String:
	return "online"

func room_closed() -> bool:
	return false

func room_code_hidden() -> bool:
	return false

func host_pc_slot() -> int:
	return own_slot

func host_picker_shown() -> bool:
	return true

func is_virtual(_slot: int) -> bool:
	return false

func pc_runs_room() -> bool:
	return false

func slot_hat(slot: int) -> String:
	return str(_look_of(slot).get("hat", "none"))

func slot_eyes(slot: int) -> String:
	return str(_look_of(slot).get("eyes", "round"))

func _look_of(slot: int) -> Dictionary:
	for entry: Variant in _looks:
		if entry is Dictionary and int(entry.get("slot", -1)) == slot:
			return entry
	return {}
