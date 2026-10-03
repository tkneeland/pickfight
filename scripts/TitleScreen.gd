extends RefCounted

## Title screen: Couch, Online or Solo (#435, ADR-0021), split out of
## `LobbyScreen.gd` (#543).
##
## Over the lobby at launch: the host picks the match kind before anyone joins.
## Couch is the Local match (phones, the controller page, gamepads), Online is
## remote seats with the host's own mouse seat, and Solo is Online with the room
## closed and three bots. Click, the keys C, O and S, or the D-pad and A. While it
## shows, PadMenu keeps A from seating a gamepad. A `-s` run (the scenarios) starts
## with it closed, so a scenario that does not pick drives the lobby as before.
##
## Also the "N players were dropped" notice shown after a kind switch.
## `_screen` is the LobbyScreen, which holds the lobby panel this is built
## into and the ControllerServer it commands (read dynamically: this script
## cannot name LobbyScreen without a preload cycle).

const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const PadMenuScript := preload("res://scripts/PadMenu.gd")

const TITLE_KINDS: Array[String] = ["local", "online", "solo"]
const TITLE_KEYS: Dictionary = {"local": KEY_C, "online": KEY_O, "solo": KEY_S}
const TITLE_BUTTON_FONT_SIZE: int = 40

var _screen # the LobbyScreen
var _title_panel: Control
var _title_buttons: Dictionary = {}
var _kind_notice: Label

func _init(screen) -> void:
	_screen = screen

## The title screen's panel, or null before the controls were attached.
func title_panel() -> Control:
	return _title_panel

func title_visible() -> bool:
	return _title_panel != null and _title_panel.visible

## The title button for "local", "online" or "solo", or null.
func title_button(kind: String) -> Button:
	return _title_buttons.get(kind) as Button

## Shows or hides the title screen; showing it puts focus on Couch.
func show_title(on: bool) -> void:
	if _title_panel == null:
		return
	_title_panel.visible = on
	PadMenuScript.set_open("title", on)
	if on:
		(_title_buttons["local"] as Button).grab_focus()
	else:
		var focused: Control = _screen.get_viewport().gui_get_focus_owner() if _screen.is_inside_tree() else null
		if focused != null and _title_panel.is_ancestor_of(focused):
			focused.release_focus()

## What picking `kind` on the title screen does: that match kind, then the lobby.
func press_title(kind: String) -> void:
	var server: Object = _screen._server
	if server == null or not TITLE_KINDS.has(kind):
		return
	server.apply_host_command("kind", kind)
	show_title(false)
	_screen.refresh_controls()

## Whether `source` (the ControllerServer) runs a match with no QR and no LAN
## URL: Online, or Solo, which is offline (#522).
static func online_kind(source: Object) -> bool:
	return source != null and source.has_method("match_kind") and ["online", "solo"].has(source.match_kind())

## The match kind as the player reads it: Couch, Online or Solo.
static func match_kind_text(source: Object) -> String:
	if not online_kind(source):
		return TranslationServer.translate("MATCH_COUCH")
	if source.has_method("room_closed") and source.room_closed():
		return TranslationServer.translate("MATCH_SOLO")
	return TranslationServer.translate("MATCH_ONLINE")

func build() -> void:
	var lobby_panel: Control = _screen._lobby_panel
	var server: Object = _screen._server
	_kind_notice = ScreenKitScript.big_label("", 28, ScreenKitScript.LOBBY_ACCENT)
	_kind_notice.name = "KindNotice"
	_kind_notice.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_kind_notice.offset_top = 12.0
	_kind_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kind_notice.visible = false
	lobby_panel.add_child(_kind_notice)
	_title_panel = ColorRect.new()
	_title_panel.name = "TitlePanel"
	(_title_panel as ColorRect).color = ScreenKitScript.LOBBY_BACKGROUND
	_title_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_panel.visible = false
	lobby_panel.add_child(_title_panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	_title_panel.add_child(box)
	box.add_child(ScreenKitScript.logo_rect("Logo", ScreenKitScript.LOGO_LOBBY_SIZE))
	box.add_child(ScreenKitScript.big_label(_screen.tr("TITLE_PICK"), 36, Color.WHITE))
	var labels: Dictionary = {"local": ["TITLE_COUCH", "TITLE_COUCH_HINT"], "online": ["TITLE_ONLINE", "TITLE_ONLINE_HINT"],
		"solo": ["TITLE_SOLO", "TITLE_SOLO_HINT"]}
	var previous: Button = null
	for kind: String in TITLE_KINDS:
		var button := Button.new()
		button.name = "Title_" + kind
		button.text = _screen.tr(labels[kind][0])
		button.custom_minimum_size = Vector2(420, 0)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.add_theme_font_size_override("font_size", TITLE_BUTTON_FONT_SIZE)
		button.pressed.connect(press_title.bind(kind))
		box.add_child(button)
		box.add_child(ScreenKitScript.big_label(_screen.tr(labels[kind][1]), 22, Color(0.8, 0.82, 0.88)))
		_title_buttons[kind] = button
		if previous != null:
			previous.focus_neighbor_bottom = previous.get_path_to(button)
			button.focus_neighbor_top = button.get_path_to(previous)
		previous = button
	if _screen.is_inside_tree() and _screen.get_tree().get_script() == null and server.has_method("match_kind") and server.match_kind() == "":
		show_title(true) # the game, not a `-s` script (see Sfx.is_script_main_loop)

## The "N players were dropped" line after a kind switch, while the server says so.
func refresh_kind_notice() -> void:
	if _kind_notice == null:
		return
	var server: Object = _screen._server
	var notice: Dictionary = server.kind_drop_notice() if server.has_method("kind_drop_notice") else {}
	_kind_notice.visible = not notice.is_empty()
	if not notice.is_empty():
		var key: String = "LOBBY_KIND_DROPPED_PHONES" if notice["kind"] == "online" else "LOBBY_KIND_DROPPED_REMOTE"
		_kind_notice.text = _screen.tr(key) % int(notice["count"])
