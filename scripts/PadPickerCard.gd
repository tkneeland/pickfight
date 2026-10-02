extends HBoxContainer
## The Local gamepad layout of the cosmetics picker (#441, ADR-0021): a compact
## slot-style picker on a gamepad seat's lobby card on the shared screen. A
## preview, then three slots (hat, colour, eyes); the slot the pad's cursor is on
## is outlined. D-pad up and down move the cursor, the bumpers cycle, A readies
## up (`CosmeticsPicker.pad_button`, reached from ControllerServer's pad input).
##
## Display only, and self-refreshing: it reads the slot's looks and cursor off
## the server every frame, and shows only while a gamepad holds the seat in the
## lobby (`ControllerServer.pad_picker_shown`), so an unplugged pad's card goes
## blank at once and a phone-only room never sees one. LobbyScreen adds it to a
## pad claim's row.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const PickerScript := preload("res://scripts/CosmeticsPicker.gd")
const PreviewScript := preload("res://scripts/CosmeticsPreview.gd")

const FONT_SIZE: int = 18
const SLOT_SIZE: Vector2 = Vector2(92, 40)
const PREVIEW_SIZE: Vector2 = Vector2(40, 40)
const ACCENT: Color = Color(1.0, 0.85, 0.2, 1.0)
const DIM: Color = Color(0.35, 0.37, 0.42, 1.0)
const FILL: Color = Color(0.12, 0.13, 0.17, 1.0)

var slot: int = -1
var _server: Object = null
var _preview: Control
var _slots: Array[PanelContainer] = []
var _hat_label: Label
var _eyes_label: Label
var _swatch: ColorRect
var _signature: String = ""

func _init(server: Object = null, seat_slot: int = -1) -> void:
	name = "PadPicker"
	_server = server
	slot = seat_slot
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	_preview = PreviewScript.new()
	_preview.custom_minimum_size = PREVIEW_SIZE
	add_child(_preview)
	_hat_label = _slot_label()
	_add_slot("Hat", _hat_label)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(SLOT_SIZE.x - 24, SLOT_SIZE.y - 16)
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_slot("Color", _swatch)
	_eyes_label = _slot_label()
	_add_slot("Eyes", _eyes_label)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = tr("PICKER_PAD_HINT")
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(hint)

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

## The text each slot shows now, for scenarios: {"hat", "eyes"} labels and the
## swatch colour.
func shown_look() -> Dictionary:
	return {"hat": _hat_label.text, "eyes": _eyes_label.text, "color": _swatch.color}

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
	_swatch.color = colour
	_preview.set_look(colour, hat, eyes)
	for i in _slots.size():
		_slots[i].add_theme_stylebox_override("panel", _slot_style(i == row))

func _slot_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	return label

func _add_slot(slot_name: String, content: Control) -> void:
	var box := PanelContainer.new()
	box.name = slot_name
	box.custom_minimum_size = SLOT_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", _slot_style(false))
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(center)
	center.add_child(content)
	add_child(box)
	_slots.append(box)

func _slot_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FILL
	style.border_color = ACCENT if selected else DIM
	style.set_border_width_all(3 if selected else 1)
	style.set_corner_radius_all(6)
	return style
