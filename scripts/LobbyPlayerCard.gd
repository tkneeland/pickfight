extends Control
## One player's card in the lobby's 4x2 grid (#547): a cream card with a strip in
## the player's colour along its top, the square avatar (hat, colour, eyes; no
## pickaxe) clear of the strip, the name, the in-card look picker on a gamepad
## seat, and a READY / not ready / BOT pill. Online, the host PC's own card opens
## the Your look popup when clicked, and the host can Kick every other card.
##
## Display only. `apply()` takes everything the card shows as a dictionary, so
## the lobby decides and this draws. A plain Control that sizes its own children
## (a PanelContainer would stretch the strip over the whole card).
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

signal body_clicked(slot: int)
signal badge_pressed(slot: int)
signal kick_pressed(slot: int)

const PreviewScript := preload("res://scripts/CosmeticsPreview.gd")
const PadPickerCardScript := preload("res://scripts/PadPickerCard.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")
const ScreenKitScript := preload("res://scripts/ScreenKit.gd")

const BORDER_PX: float = 5.0
const STRIP_PX: float = 18.0
const CARD_MIN_SIZE: Vector2 = Vector2(150, 0)
const AVATAR_SIZE: Vector2 = Vector2(62, 80)
const NAME_FONT_SIZE: int = 26
const SMALL_FONT_SIZE: int = 16

var slot: int = -1
var clickable: bool = false

var _strip: Panel
var _content: MarginContainer
var _avatar: Control
var _name: Label
var _meta: Label
var _picker: Control = null
var _badge: Button
var _kick: Button
var _pill: StringName = &""
var _strip_color: Color = Color.TRANSPARENT

func _init(seat_slot: int = -1) -> void:
	slot = seat_slot
	name = "Card%d" % seat_slot
	custom_minimum_size = CARD_MIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := PanelContainer.new()
	bg.name = "Bg"
	bg.theme_type_variation = UiThemeScript.CARD_PANEL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_strip = Panel.new()
	_strip.name = "Strip"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_strip.offset_left = BORDER_PX
	_strip.offset_right = -BORDER_PX
	_strip.offset_top = BORDER_PX
	_strip.offset_bottom = BORDER_PX + STRIP_PX
	add_child(_strip)
	_content = MarginContainer.new()
	_content.name = "Content"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("margin_left", int(BORDER_PX) + 6)
	_content.add_theme_constant_override("margin_right", int(BORDER_PX) + 6)
	_content.add_theme_constant_override("margin_top", int(BORDER_PX + STRIP_PX) + 6)
	_content.add_theme_constant_override("margin_bottom", int(BORDER_PX) + 8)
	add_child(_content)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_content.add_child(box)
	var avatar_row := CenterContainer.new()
	avatar_row.name = "AvatarRow"
	avatar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(avatar_row)
	_avatar = PreviewScript.new()
	_avatar.custom_minimum_size = AVATAR_SIZE
	avatar_row.add_child(_avatar)
	_name = ScreenKitScript.themed_label("", NAME_FONT_SIZE, UiThemeScript.INK_HEADING_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_name.name = "Name"
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_name)
	_meta = ScreenKitScript.themed_label("", SMALL_FONT_SIZE, UiThemeScript.INK_BOLD_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_meta.name = "Meta"
	_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta.visible = false
	box.add_child(_meta)
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var badge_row := HBoxContainer.new()
	badge_row.name = "BadgeRow"
	badge_row.alignment = BoxContainer.ALIGNMENT_CENTER
	badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(badge_row)
	_badge = ScreenKitScript.themed_button("", UiThemeScript.PILL_OFF, "Badge")
	_badge.pressed.connect(func() -> void: badge_pressed.emit(slot))
	badge_row.add_child(_badge)
	_kick = ScreenKitScript.themed_button(tr("HOST_KICK"), UiThemeScript.ACTION_BUTTON, "Kick")
	_kick.add_theme_font_size_override("font_size", SMALL_FONT_SIZE + 2)
	_kick.visible = false
	_kick.pressed.connect(func() -> void: kick_pressed.emit(slot))
	box.add_child(_kick)

func _get_minimum_size() -> Vector2:
	return _content.get_combined_minimum_size()

func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if clickable and click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		body_clicked.emit(slot)
		accept_event()

## The Kick button, or null.
func kick_button() -> Button:
	return _kick if _kick.visible else null

## The READY / not ready / BOT pill.
func badge() -> Button:
	return _badge

func name_label() -> Label:
	return _name

## The line under the name (team, ping, the pad tip), or "" while there is none.
func meta_text() -> String:
	return _meta.text if _meta.visible else ""

func avatar() -> Control:
	return _avatar

## The in-card pad picker, or null on a card that has none.
func picker() -> Control:
	return _picker

## Gives the card a gamepad picker (once); it shows itself while a pad holds the seat.
func add_picker(server: Object) -> void:
	if _picker != null:
		return
	_picker = PadPickerCardScript.new(server, slot)
	_picker.name = "PadPicker"
	var box: Node = _content.get_node("Box")
	box.add_child(_picker)
	box.move_child(_picker, _name.get_index() + 2)

func remove_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null

## Redraws the card from `info`: name, color (Color), hat, eyes, ready, bot, host,
## own, team_text, ping (ms or -1), tip (bool), clickable, kickable, dim.
func apply(info: Dictionary) -> void:
	var suffix: String = ""
	if bool(info.get("own", false)):
		suffix = tr("LOBBY_YOU_TAG")
	elif bool(info.get("host", false)):
		suffix = tr("LOBBY_HOST_TAG")
	_name.text = "%s%s" % [info.get("name", ""), suffix]
	var colour: Color = info.get("color", Color.WHITE)
	if colour != _strip_color:
		_strip_color = colour
		var strip_box := StyleBoxFlat.new()
		strip_box.bg_color = colour
		strip_box.corner_radius_top_left = 15
		strip_box.corner_radius_top_right = 15
		_strip.add_theme_stylebox_override("panel", strip_box)
	_avatar.set_look(colour, str(info.get("hat", "none")), str(info.get("eyes", "round")))
	var bot: bool = bool(info.get("bot", false))
	var ready: bool = bool(info.get("ready", false))
	var pill: StringName = UiThemeScript.PILL_BOT if bot else (UiThemeScript.PILL_ON if ready else UiThemeScript.PILL_OFF)
	if pill != _pill:
		_pill = pill
		_badge.theme_type_variation = pill
	_badge.text = tr("LOBBY_BOT") if bot else (tr("LOBBY_READY") if ready else tr("LOBBY_NOT_READY"))
	_badge.disabled = false
	_badge.mouse_filter = Control.MOUSE_FILTER_STOP if bool(info.get("badge_clickable", false)) else Control.MOUSE_FILTER_IGNORE
	var lines: PackedStringArray = PackedStringArray()
	if not str(info.get("team_text", "")).is_empty():
		lines.append(str(info["team_text"]))
	if int(info.get("ping", -1)) >= 0:
		lines.append(TranslationServer.translate("PING_MS") % int(info["ping"]))
	if bool(info.get("tip", false)):
		lines.append(tr("LOBBY_PAD_TIP"))
	_meta.text = "\n".join(lines)
	_meta.visible = not lines.is_empty()
	clickable = bool(info.get("clickable", false))
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
	_kick.visible = bool(info.get("kickable", false))
	modulate.a = 0.82 if bool(info.get("dim", false)) else 1.0
