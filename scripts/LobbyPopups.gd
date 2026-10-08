extends RefCounted
## The lobby's two popups (#547), split out of `LobbyScreen.gd`: How to play (the
## four `HowToPlayDemo` lessons as cards, then the current mode's rule) and Your
## look (the `OnlineCosmeticsPanel` in its popup layout, with a live preview).
##
## Each is an overlay over the whole lobby: a dim backdrop (a click on it closes)
## and a cream card popping in. The demos are real players on tiny stages, so
## they are built only while How to play is open and freed the moment it closes
## or the lobby goes (#219): no demo body is simulated behind a round.
##
## `_screen` is the LobbyScreen (read dynamically: this script cannot name it
## without a preload cycle).

const HowToPlayDemoScript := preload("res://scripts/HowToPlayDemo.gd")
const OnlineCosmeticsPanelScript := preload("res://scripts/OnlineCosmeticsPanel.gd")
const GameModesScript := preload("res://scripts/GameModes.gd")
const PadMenuScript := preload("res://scripts/PadMenu.gd")
const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")
const StagesRulesScreenScript := preload("res://scripts/StagesRulesScreen.gd")

const HELP_WIDTH_PX: float = 920.0
const LOOK_WIDTH_PX: float = 980.0
const DIM_COLOR: Color = Color(0.0784, 0.0941, 0.1137, 0.72)

var _screen # the LobbyScreen
var _help: Control
var _look: Control
var _look_panel: Control
var _help_card: Control
var _look_card: Control
var _stages: Control
var _stages_card: Control
var _stages_screen # StagesRulesScreen.gd, built the first time it opens (#647)
var _demo_grid: GridContainer
var _rule_label: Label
var _close_button: Button
var _open: String = ""
var _mode_id: String = ""
var _target_kind: String = "first_to"
var _target: int = 5

func _init(screen) -> void:
	_screen = screen

## Builds both overlays (hidden) into `parent`, above everything the lobby has so far.
func build(parent: Control) -> void:
	_help = _overlay("HowToPlayPopup", parent)
	_help_card = _card(_help, HELP_WIDTH_PX)
	var box := VBoxContainer.new()
	box.name = "HowToPlay"
	box.add_theme_constant_override("separation", 16)
	_help_card.add_child(box)
	var head := HBoxContainer.new()
	head.name = "Head"
	box.add_child(head)
	var title: Label = ScreenKitScript.themed_label(_screen.tr("HOW_TO_PLAY_TITLE"), 46, UiThemeScript.INK_HEADING_LABEL)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_close_button = ScreenKitScript.themed_button("X", UiThemeScript.YELLOW_BUTTON, "Close")
	_close_button.custom_minimum_size = Vector2(56, 56)
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.pressed.connect(open.bind(""))
	head.add_child(_close_button)
	_demo_grid = GridContainer.new()
	_demo_grid.name = "Demos"
	_demo_grid.columns = 2
	_demo_grid.add_theme_constant_override("h_separation", 18)
	_demo_grid.add_theme_constant_override("v_separation", 18)
	box.add_child(_demo_grid)
	var rule_box := PanelContainer.new()
	rule_box.name = "RuleBox"
	rule_box.theme_type_variation = UiThemeScript.RULE_BOX
	box.add_child(rule_box)
	_rule_label = ScreenKitScript.themed_label("", 20, UiThemeScript.INK_BOLD_LABEL)
	_rule_label.name = "Rule"
	_rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule_box.add_child(_rule_label)

	_look = _overlay("YourLookPopup", parent)
	_look_card = _card(_look, LOOK_WIDTH_PX)
	_look_panel = OnlineCosmeticsPanelScript.new()
	_look_panel.name = "HostPicker"
	_look_panel.set_popup_layout(true)
	_look_panel.visible = false
	_look_panel.done_pressed.connect(open.bind(""))
	_look_card.add_child(_look_panel)

	# Stages & Rules (#647): its contents are built the first time it opens.
	_stages = _overlay("StagesRulesPopup", parent)
	_stages_card = _card(_stages, StagesRulesScreenScript.CARD_WIDTH_PX)
	_stages_screen = StagesRulesScreenScript.new(_screen)

## An overlay: a dim backdrop that closes the popup when clicked, and a centre for the card.
func _overlay(overlay_name: String, parent: Control) -> Control:
	var overlay := Control.new()
	overlay.name = overlay_name
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			request_close())
	parent.add_child(overlay)
	return overlay

func _card(overlay: Control, width: float) -> PanelContainer:
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = UiThemeScript.DIALOG_CARD
	card.custom_minimum_size.x = width
	card.mouse_filter = Control.MOUSE_FILTER_STOP # a click on the card is not a click on the backdrop
	center.add_child(card)
	return card

## The How to play overlay (what `how_to_play_panel()` returns), or null before it was built.
func help_panel() -> Control:
	return _help

func look_overlay() -> Control:
	return _look

## The Stages & Rules overlay (#647), or null before the lobby was built.
func stages_overlay() -> Control:
	return _stages

## The Stages & Rules screen's model (tabs, tiles, switches), host only.
func stages_screen():
	return _stages_screen

## The Your look panel, bound to the host PC's seat by HostControls.
func look_panel() -> Control:
	return _look_panel

## "help", "look", "stages" or "" for none.
func current() -> String:
	return _open

## The How to play demos running now (four while that popup is open).
func demos() -> Array[Node]:
	var out: Array[Node] = []
	if _demo_grid != null:
		for card: Node in _demo_grid.get_children():
			for child: Node in card.get_children():
				if child.get_script() == HowToPlayDemoScript:
					out.append(child)
	return out

## A user's way out (backdrop click, Done, Esc, B): closes the open popup unless
## it is Stages & Rules with a mode left on no stage. True when it closed.
func request_close() -> bool:
	if _open == "stages" and not _stages_screen.can_close():
		return false
	open("")
	return true

## Opens popup `which` ("help", "look" or "stages"), closing the other; "" closes
## any. Stages & Rules is the host's: it stays shut until host controls attach.
func open(which: String) -> void:
	if which == _open or _help == null:
		return
	if which == "stages" and _screen._server == null:
		return
	_open = which
	# A popup owns A and B while it is up, so a gamepad cannot ready its seat behind it.
	PadMenuScript.set_open("lobby_popup", which != "")
	_help.visible = which == "help"
	_look.visible = which == "look"
	_stages.visible = which == "stages"
	if which == "stages":
		if not _stages_screen.is_built():
			_stages_screen.build(_stages_card)
		_stages_screen.on_open(_mode_id)
		ScreenKitScript.pop_in(_stages_card)
	if which == "help":
		_start_demos()
		ScreenKitScript.pop_in(_help_card)
	else:
		_stop_demos()
	if which == "look":
		ScreenKitScript.pop_in(_look_card)
	_focus_for_pad(which)

## With the gamepad menu open, focus goes into the popup so A and B work there.
func _focus_for_pad(which: String) -> void:
	if not _screen.pad_menu_open() or which == "":
		return
	var target: Control = _close_button if which == "help" else _look_panel.done_button()
	if which == "stages":
		target = _stages_screen.focus_target()
	if target != null:
		target.grab_focus()

func _start_demos() -> void:
	if not demos().is_empty():
		return
	for i in _screen.HOW_TO_PLAY_LINES.size():
		var card := PanelContainer.new()
		card.name = "DemoCard%d" % i
		card.theme_type_variation = StringName("DemoCard%d" % (i % UiThemeScript.DEMO_CARD_COLORS.size()))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var demo: Node = HowToPlayDemoScript.new(_screen.HOW_TO_PLAY_KINDS[i], _screen.tr("HOW_TO_PLAY_LINE_%d" % (i + 1)), i)
		card.add_child(demo)
		_demo_grid.add_child(card)

func _stop_demos() -> void:
	if _demo_grid == null:
		return
	for card: Node in _demo_grid.get_children():
		# Out of the tree at once, not at the end of the frame: its bodies
		# leave their worlds, and its players the "players" group, now.
		_demo_grid.remove_child(card)
		card.queue_free()

## The rule line under the demos: the picked mode's name and rule, with the
## host's target in it (the same value as the status line and the Host panel).
func set_mode(id: String, target_kind: String = "first_to", target: int = 5) -> void:
	_mode_id = id
	_target_kind = target_kind
	_target = target
	if _rule_label == null:
		return
	var rule: String = GameModesScript.status_line(id)
	if target_kind == "first_to":
		rule += " " + _screen.tr("LOBBY_HELP_FIRST_TO") % target
	_rule_label.text = "%s: %s" % [GameModesScript.display_name(id), rule]
