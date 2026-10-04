extends VBoxContainer
## The Local gamepad layout of the cosmetics picker (#441, ADR-0021, restyled
## for the lobby cards in #547): three slot-style rows (Hat, Colour, Eyes) inside
## a gamepad seat's own player card, under the avatar. The row the pad's cursor is
## on is yellow and carries a left and a right arrow; the others are plain. The
## D-pad or the left stick moves the cursor up and down and changes the value
## left and right (`CosmeticsPicker.pad_button` / `pad_step`, reached from
## ControllerServer's pad input). A readies. There is no instruction text: the
## arrows on the picked row say it. The avatar above shows the result, so this
## card draws no preview of its own.
##
## Display only, and self-refreshing: it reads the slot's looks and cursor off
## the server every frame, and shows only while a gamepad holds the seat in the
## lobby (`ControllerServer.pad_picker_shown`), so an unplugged pad's card goes
## blank at once and a phone-only room never sees one. The lobby adds it to a
## pad claim's player card.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const PickerScript := preload("res://scripts/CosmeticsPicker.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")

const FONT_SIZE: int = 16
const ROW_HEIGHT: float = 28.0
const SWATCH_SIZE: Vector2 = Vector2(34, 16)
const LEFT_ARROW: String = "◀"
const RIGHT_ARROW: String = "▶"

var slot: int = -1
var _server: Object = null
var _rows: Array[PanelContainer] = []
var _lefts: Array[Label] = []
var _rights: Array[Label] = []
var _hat_label: Label
var _eyes_label: Label
var _swatch: Panel
var _signature: String = ""

func _init(server: Object = null, seat_slot: int = -1) -> void:
	name = "PadPicker"
	_server = server
	slot = seat_slot
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_hat_label = _value_label()
	_add_row("Hat", tr("PICKER_HAT"), _hat_label)
	_swatch = Panel.new()
	_swatch.custom_minimum_size = SWATCH_SIZE
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_row("Color", tr("PICKER_COLOUR"), _swatch)
	_eyes_label = _value_label()
	_add_row("Eyes", tr("PICKER_EYES"), _eyes_label)

func _ready() -> void:
	refresh()

func _process(_delta: float) -> void:
	refresh()

## Whether the card is showing: a gamepad holds the seat and it is the lobby.
func shown() -> bool:
	return _server != null and _server.has_method("pad_picker_shown") and _server.pad_picker_shown(slot)

## The slot the cursor is on: "hat", "color" or "eyes".
func selected_row() -> String:
	return PickerScript.ROWS[_server.cosmetics_picker.row_of(slot)] if _server != null else ""

## The text each row shows now, for scenarios: {"hat", "eyes"} labels and the
## swatch colour.
func shown_look() -> Dictionary:
	return {"hat": _hat_label.text, "eyes": _eyes_label.text, "color": _swatch_color}

var _swatch_color: Color = Color.WHITE

## The arrows the picked row shows now, "" for a row without them.
func arrows_of(row: int) -> String:
	return (_lefts[row].text + _rights[row].text) if row >= 0 and row < _lefts.size() and _lefts[row].modulate.a > 0.5 else ""

func refresh() -> void:
	visible = shown()
	if not visible:
		return
	var hat: String = _server.slot_hat(slot)
	var eyes: String = _server.slot_eyes(slot)
	var colour: Color = _server.palette_color(_server.slot_color(slot))
	var row: int = _server.cosmetics_picker.row_of(slot)
	var signature: String = "%s|%s|%s|%d" % [hat, eyes, colour.to_html(), row]
	if signature == _signature:
		return
	_signature = signature
	_hat_label.text = PickerScript.label_of("hat", hat)
	_eyes_label.text = PickerScript.label_of("eyes", eyes)
	_swatch_color = colour
	var swatch_box := UiThemeScript.box(colour, 5, 2)
	_swatch.add_theme_stylebox_override("panel", swatch_box)
	for i in _rows.size():
		var on: bool = i == row
		_rows[i].theme_type_variation = UiThemeScript.PICK_ROW_ON if on else UiThemeScript.PICK_ROW
		# Hidden, not removed: the rows keep their width as the cursor moves.
		_lefts[i].modulate.a = 1.0 if on else 0.0
		_rights[i].modulate.a = 1.0 if on else 0.0

func _value_label() -> Label:
	var label := Label.new()
	label.theme_type_variation = &"InkBoldLabel"
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _arrow(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"InkHeadingLabel"
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _add_row(row_name: String, caption: String, value: Control) -> void:
	var box := PanelContainer.new()
	box.name = row_name
	box.theme_type_variation = UiThemeScript.PICK_ROW
	box.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	var left: Label = _arrow(LEFT_ARROW)
	line.add_child(left)
	var title := Label.new()
	title.theme_type_variation = &"InkBoldLabel"
	title.add_theme_font_size_override("font_size", FONT_SIZE)
	title.text = caption
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(title)
	if value is Label:
		line.add_child(value)
	else:
		var holder := CenterContainer.new()
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(value)
		line.add_child(holder)
	var right: Label = _arrow(RIGHT_ARROW)
	line.add_child(right)
	add_child(box)
	_rows.append(box)
	_lefts.append(left)
	_rights.append(right)
