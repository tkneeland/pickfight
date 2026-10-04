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
const UiThemeScript := preload("res://scripts/UiTheme.gd")

const TITLE_KINDS: Array[String] = ["local", "online", "solo"]
const TITLE_KEYS: Dictionary = {"local": KEY_C, "online": KEY_O, "solo": KEY_S}
const TITLE_BUTTON_FONT_SIZE: int = 40
## The logo as the mockup frames it (#546), and each card's colour variation.
const TITLE_LOGO_SIZE: Vector2 = Vector2(1360, 300)
const TITLE_CARD_VARIATIONS: Dictionary = {"local": &"TitleCardOrange", "online": &"TitleCardSky", "solo": &"TitleCardGreen"}
const TITLE_CARD_HEIGHT: float = 210.0

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
	_title_panel = Control.new()
	_title_panel.name = "TitlePanel"
	_title_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_panel.visible = false
	lobby_panel.add_child(_title_panel)
	# Opaque ground, so the lobby never shows through (#546).
	_title_panel.add_child(ScreenKitScript.striped_background())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 64)
	_title_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	margin.add_child(box)
	var logo: TextureRect = ScreenKitScript.logo_rect("Logo", TITLE_LOGO_SIZE)
	box.add_child(logo)
	var pick := Label.new()
	pick.text = _screen.tr("TITLE_PICK")
	pick.theme_type_variation = UiThemeScript.TITLE_HEADING_LABEL
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(pick)
	var cards := HBoxContainer.new()
	cards.name = "Cards"
	cards.add_theme_constant_override("separation", 40)
	box.add_child(cards)
	var labels: Dictionary = {"local": ["TITLE_COUCH", "TITLE_COUCH_HINT"], "online": ["TITLE_ONLINE", "TITLE_ONLINE_HINT"],
		"solo": ["TITLE_SOLO", "TITLE_SOLO_HINT"]}
	var previous: Button = null
	for kind: String in TITLE_KINDS:
		var button := _build_card(kind, labels[kind][0], labels[kind][1])
		cards.add_child(button)
		_title_buttons[kind] = button
		if previous != null:
			previous.focus_neighbor_bottom = previous.get_path_to(button)
			button.focus_neighbor_top = button.get_path_to(previous)
			previous.focus_neighbor_right = previous.get_path_to(button)
			button.focus_neighbor_left = button.get_path_to(previous)
		previous = button
	var footer := Label.new()
	footer.name = "Footer"
	footer.text = _screen.tr("TITLE_FOOTER")
	footer.theme_type_variation = UiThemeScript.MUTED_HINT_LABEL
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(footer)
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

## One chunky card for `kind`: name, key badge and a wrapped one-line blurb on a
## Button in the kind's accent colour. It pops (a small tilt and scale) on hover
## and focus; nothing waits on the motion.
func _build_card(kind: String, name_key: String, hint_key: String) -> Button:
	var button := Button.new()
	button.name = "Title_" + kind
	button.theme_type_variation = TITLE_CARD_VARIATIONS[kind]
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, TITLE_CARD_HEIGHT)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(press_title.bind(kind))
	button.tooltip_text = _screen.tr(name_key)
	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("margin_left", 32)
	inner.add_theme_constant_override("margin_right", 32)
	inner.add_theme_constant_override("margin_top", 24)
	inner.add_theme_constant_override("margin_bottom", 24)
	button.add_child(inner)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	inner.add_child(column)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	var title := Label.new()
	title.text = _screen.tr(name_key).get_slice(" (", 0) # "Couch (C)" -> "Couch"
	title.theme_type_variation = UiThemeScript.CARD_NAME_LABEL
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var badge := PanelContainer.new()
	badge.theme_type_variation = UiThemeScript.KEY_BADGE
	badge.custom_minimum_size = Vector2(48, 48)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(badge)
	var key := Label.new()
	key.text = OS.get_keycode_string(TITLE_KEYS[kind])
	key.theme_type_variation = UiThemeScript.KEY_BADGE_LABEL
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(key)
	var blurb := Label.new()
	blurb.text = _screen.tr(hint_key)
	blurb.theme_type_variation = UiThemeScript.CARD_DESC_LABEL
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(blurb)
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	for entered: Signal in [button.mouse_entered, button.focus_entered]:
		entered.connect(_pop_card.bind(button, true))
	for exited: Signal in [button.mouse_exited, button.focus_exited]:
		exited.connect(_pop_card.bind(button, false))
	return button

func _pop_card(button: Button, on: bool) -> void:
	if on == false and (button.is_hovered() or button.has_focus()):
		return # still hovered or focused by the other route
	if not button.is_inside_tree():
		return
	var tween: Tween = button.create_tween().set_parallel(true)
	tween.tween_property(button, "rotation_degrees", -1.0 if on else 0.0, 0.12)
	tween.tween_property(button, "scale", Vector2.ONE * (1.03 if on else 1.0), 0.12)
