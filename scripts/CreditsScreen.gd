extends CanvasLayer

## Credits and licences screen (#721, Steam readiness 4.2 and 4.3): who made the game, the
## third-party assets and code it ships, and the full licence texts (`THIRD-PARTY.md`, in
## English). Opened from the title screen's Credits button and from Settings by
## `CreditsScreen.open(tree)`; closed with the X, Esc or the gamepad's B.
##
## One node (`CreditsScreen`) under the root, built on first use and kept. While it is open it
## takes Esc and B before Settings does, scrolls with the D-pad or arrows, and tells `PadMenu` a
## menu is open so A does not seat a gamepad. Preloaded by path, never by `class_name`
## (CLAUDE.md).

const NODE_NAME: String = "CreditsScreen"
const THIRD_PARTY_PATH: String = "res://THIRD-PARTY.md"
const SCREEN_LAYER: int = 30
const SCROLL_STEP_PX: int = 90
const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")
const PadMenuScript := preload("res://scripts/PadMenu.gd")
const LanguagesScript := preload("res://scripts/Languages.gd")

## Music credits, from `CREDITS.md`'s Music table: [track, author].
const MUSIC: Array = [
	["Snowfall (Looped ver.)", "Kistol"],
	["Fast fight / battle music (looped)", "Ville Nousiainen (loop by XCVG)"],
	["Mars (NES Shooter Music)", "SketchyLogic"],
	["Levels 1 to 3 (5 Chiptunes: Action)", "SubspaceAudio"],
	["Boss Battle #2 [8 bit]", "nene"],
	["Battle Theme A", "cynicmusic"],
	["Battle Theme", "Wolfgang_"],
]

var _scroll: ScrollContainer
var _close_button: Button
var _text: PackedStringArray = PackedStringArray()
var _restore_focus: Control

## Opens the credits (building the screen the first time) and returns it.
static func open(tree: SceneTree) -> Node:
	var screen: Node = tree.root.get_node_or_null(NODE_NAME)
	if screen == null:
		screen = (load("res://scripts/CreditsScreen.gd") as GDScript).new()
		tree.root.add_child(screen)
	screen.show_credits()
	return screen

func _ready() -> void:
	name = NODE_NAME
	layer = SCREEN_LAYER
	visible = false
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(ScreenKitScript.striped_background())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 160)
	margin.add_theme_constant_override("margin_right", 160)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var head := HBoxContainer.new()
	head.name = "Head"
	column.add_child(head)
	var title := Label.new()
	title.name = "Title"
	title.text = tr("CREDITS_TITLE")
	title.theme_type_variation = UiThemeScript.TITLE_HEADING_LABEL
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hint := Label.new()
	hint.text = tr("CREDITS_CLOSE_HINT")
	hint.theme_type_variation = UiThemeScript.MUTED_HINT_LABEL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hint)
	_close_button = ScreenKitScript.themed_button("X", UiThemeScript.YELLOW_BUTTON, "Close", true)
	_close_button.custom_minimum_size = Vector2(56, 56)
	_close_button.pressed.connect(close)
	head.add_child(_close_button)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	_scroll.add_child(body)
	_build_body(body)

func _build_body(body: VBoxContainer) -> void:
	_line(body, tr("CREDITS_STUDIO"), 34)
	_heading(body, "CREDITS_MUSIC")
	_line(body, tr("CREDITS_MUSIC_NOTE"))
	for track: Array in MUSIC:
		_line(body, "%s: %s" % [track[0], track[1]])
	_heading(body, "CREDITS_SOUND")
	_line(body, "Kenney (kenney.nl): Impact Sounds, RPG Audio, Sci-fi Sounds and Interface Sounds, CC0 1.0")
	_line(body, "Announcer: synthesised with Piper TTS (voice en_US-john-medium, public-domain LibriVox speech), CC0 1.0")
	_line(body, "Player grunts: synthesised for this game, CC0 1.0")
	_heading(body, "CREDITS_FONTS")
	_line(body, "Lilita One, Nunito and Noto Sans SC, JP and KR, SIL Open Font License 1.1")
	_heading(body, "CREDITS_ENGINE")
	_line(body, "Godot Engine, MIT licence (Copyright (c) 2014-present Godot Engine contributors; Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur)")
	_line(body, "GodotSteam (GP Garcia, Chris Ridenour and contributors), MIT; Steamworks SDK (Valve)")
	_line(body, "Sentry SDK for Godot, MIT; QR encoder after Project Nayuki's QR Code generator library, MIT")
	_heading(body, "CREDITS_TRANSLATIONS")
	_line(body, tr("CREDITS_TRANSLATIONS_NOTE"))
	for option: Dictionary in LanguagesScript.OPTIONS:
		if option["code"] != "en":
			_line(body, "%s: %s" % [option["name"], tr("CREDITS_PROOFREADER_OPEN")])
	_heading(body, "CREDITS_LICENCES")
	_line(body, _third_party_text(), 18)

func _heading(body: VBoxContainer, key: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	body.add_child(spacer)
	var label := ScreenKitScript.themed_label(tr(key), 30, UiThemeScript.TITLE_HEADING_LABEL)
	body.add_child(label)
	_text.append(label.text)

func _line(body: VBoxContainer, text: String, font_size: int = 22) -> void:
	var label := ScreenKitScript.themed_label(text, font_size, UiThemeScript.BOLD_LABEL, HORIZONTAL_ALIGNMENT_LEFT, "", TextServer.AUTOWRAP_WORD_SMART)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(label)
	_text.append(text)

## `THIRD-PARTY.md` (English), or a pointer to it when the export left the file out.
static func _third_party_text() -> String:
	var file := FileAccess.open(THIRD_PARTY_PATH, FileAccess.READ)
	if file == null:
		return "The full licence texts are in THIRD-PARTY.md next to the game."
	return file.get_as_text().replace("\r\n", "\n")

func show_credits() -> void:
	_restore_focus = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	visible = true
	PadMenuScript.set_open("credits", true)
	_scroll.scroll_vertical = 0
	_close_button.grab_focus()

func close() -> void:
	if not visible:
		return
	visible = false
	PadMenuScript.set_open("credits", false)
	if _close_button.has_focus():
		_close_button.release_focus()
	if _restore_focus != null and is_instance_valid(_restore_focus) and _restore_focus.is_visible_in_tree():
		_restore_focus.grab_focus()
	_restore_focus = null

func is_open() -> bool:
	return visible

func close_button() -> Button:
	return _close_button

## Everything the screen says, one entry per line (the licence texts as one entry).
func credits_text() -> String:
	return "\n".join(_text)

## Esc and B close it; the D-pad and arrows scroll. Taken in `_input`, ahead of Settings' own
## Esc and B handling underneath.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	var closing: bool = PadMenuScript.pressed(event, JOY_BUTTON_B) \
		or (key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE)
	if closing:
		close()
		get_viewport().set_input_as_handled()
		return
	# A closes (the X is the only thing focused); left and right do nothing, but are taken so the
	# title screen under this one does not steal focus on them (#676).
	for action: StringName in [&"ui_accept", &"ui_left", &"ui_right"]:
		if event.is_action_pressed(action, false, true):
			if action == &"ui_accept":
				close()
			get_viewport().set_input_as_handled()
			return
	var step: int = 0
	if event.is_action_pressed(&"ui_down", true):
		step = SCROLL_STEP_PX
	elif event.is_action_pressed(&"ui_up", true):
		step = -SCROLL_STEP_PX
	if step != 0:
		_scroll.scroll_vertical += step
		get_viewport().set_input_as_handled()
