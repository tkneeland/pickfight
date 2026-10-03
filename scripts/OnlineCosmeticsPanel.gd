extends PanelContainer
## The Online layout of the cosmetics picker (#441, ADR-0021): a large
## mouse-friendly panel in an Online player's own lobby, beside the player list,
## shown until they ready up (its owner decides when). A big preview, then
## clickable grids: hats, colours (a colour another player wears is greyed out
## and cannot be clicked), eyes.
##
## Transport-free: the catalog and everyone's looks come in as the host's
## `looks` frames (`ControllerServer.looks_message()` / `looks_update_message()`),
## and a click emits `picked(kind, value)` with kind "hat", "color" or "eyes", the
## phone's own frame names. Two owners:
##   - the PC client (`RemoteClient.gd`) feeds it the frames it is sent and turns
##     `picked` into frames back to the host, saving the pick in its own copy;
##   - the host's own seat in an Online lobby calls `bind_server(server, slot)`,
##     which reads the server directly and applies picks through its setters.
##     LobbyScreen adds one to its right column in an Online lobby, bound to
##     `server.host_pc_slot()` (see docs/FEATURES.md, #441).
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

signal picked(kind: String, value: Variant)

const PickerScript := preload("res://scripts/CosmeticsPicker.gd")
const PreviewScript := preload("res://scripts/CosmeticsPreview.gd")

const TITLE_SIZE: int = 24
const FONT_SIZE: int = 18
const PREVIEW_SIZE: Vector2 = Vector2(140, 160)
const SWATCH_SIZE: Vector2 = Vector2(48, 48)
const TAKEN_MODULATE: Color = Color(1, 1, 1, 0.25)

var own_slot: int = -1
## The palette as the host sent it: "#rrggbb", "" for a colour nobody can wear.
var palette: Array = []
var _looks: Array = []
var _own: Dictionary = {}
var _server: Object = null

var _preview: Control
var _hat_buttons: Dictionary = {} # id -> Button
var _eyes_buttons: Dictionary = {} # id -> Button
var _color_buttons: Array[Button] = []
var _hat_grid: GridContainer
var _color_grid: GridContainer
var _eyes_grid: GridContainer

func _init() -> void:
	name = "CosmeticsPanel"
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	box.add_child(_label(tr("PICKER_TITLE"), TITLE_SIZE))
	_preview = PreviewScript.new()
	_preview.custom_minimum_size = PREVIEW_SIZE
	box.add_child(_preview)
	box.add_child(_label(tr("PICKER_HAT"), FONT_SIZE))
	_hat_grid = _grid(3)
	box.add_child(_hat_grid)
	for id: String in PickerScript.options("hat"):
		var button: Button = _button(PickerScript.label_of("hat", id))
		button.name = "Hat_" + id
		button.pressed.connect(pick_hat.bind(id))
		_hat_grid.add_child(button)
		_hat_buttons[id] = button
	box.add_child(_label(tr("PICKER_COLOUR"), FONT_SIZE))
	_color_grid = _grid(8)
	box.add_child(_color_grid)
	box.add_child(_label(tr("PICKER_EYES"), FONT_SIZE))
	_eyes_grid = _grid(3)
	box.add_child(_eyes_grid)
	for id: String in PickerScript.options("eyes"):
		var button: Button = _button(PickerScript.label_of("eyes", id))
		button.name = "Eyes_" + id
		button.pressed.connect(pick_eyes.bind(id))
		_eyes_grid.add_child(button)
		_eyes_buttons[id] = button

## A shorter preview, for a lobby with little height to spare (the host's own
## seat shares its column with the host controls).
func set_compact(on: bool) -> void:
	_preview.custom_minimum_size = Vector2(PREVIEW_SIZE.x, 100.0) if on else PREVIEW_SIZE

## The host's full `looks` frame (palette, hats, eyes, everyone's looks).
func set_catalog(looks_frame: Dictionary) -> void:
	var colours: Variant = looks_frame.get("palette", [])
	if colours is Array and colours != palette:
		palette = colours.duplicate()
		_build_colors()
	var looks: Variant = looks_frame.get("looks", null)
	if looks is Array:
		set_looks(looks, own_slot)

## Everyone's looks (a `looks` frame's list) as seen by `slot`.
func set_looks(looks: Array, slot: int) -> void:
	own_slot = slot
	_looks = looks.duplicate(true)
	_own = PickerScript.own_look(_looks, own_slot)
	_refresh()

## Whether colour `index` is greyed out: worn by another player, or not wearable.
func color_taken(index: int) -> bool:
	if index < 0 or index >= palette.size() or str(palette[index]).is_empty():
		return true
	return PickerScript.taken_colors(_looks, own_slot).has(index)

func pick_hat(id: String) -> void:
	_own["hat"] = id
	_refresh()
	picked.emit("hat", id)

func pick_eyes(id: String) -> void:
	_own["eyes"] = id
	_refresh()
	picked.emit("eyes", id)

## A click on colour `index`: nothing for a greyed-out one.
func pick_color(index: int) -> void:
	if color_taken(index):
		return
	_own["color"] = index
	_refresh()
	picked.emit("color", index)

func hat_button(id: String) -> Button:
	return _hat_buttons.get(id) as Button

func eyes_button(id: String) -> Button:
	return _eyes_buttons.get(id) as Button

func color_button(index: int) -> Button:
	return _color_buttons[index] if index >= 0 and index < _color_buttons.size() else null

## What the preview shows now: {"color": Color, "hat", "eyes"}.
func preview_look() -> Dictionary:
	return {"color": _preview.color, "hat": _preview.hat_id, "eyes": _preview.eyes_id}

## Drive the panel straight off `server` for its own seat `slot` (the host's
## own seat in an Online lobby, #435): no frames, no saving here.
func bind_server(server: Object, slot: int) -> void:
	_server = server
	own_slot = slot
	if not picked.is_connected(_apply_to_server):
		picked.connect(_apply_to_server)
	set_catalog(server.looks_message())

func _process(_delta: float) -> void:
	if _server != null and is_visible_in_tree():
		var looks: Array = _server.looks_update_message().get("looks", [])
		if looks != _looks:
			set_looks(looks, own_slot)

func _apply_to_server(kind: String, value: Variant) -> void:
	match kind:
		"hat":
			_server.set_slot_hat(own_slot, str(value))
		"eyes":
			_server.set_slot_eyes(own_slot, str(value))
		"color":
			_server.request_color(own_slot, int(value))
	set_looks(_server.looks_update_message().get("looks", []), own_slot)

func _refresh() -> void:
	var hat: String = str(_own.get("hat", PickerScript.HatScript.NONE))
	var eyes: String = str(_own.get("eyes", PickerScript.PlayerFaceScript.EYE_ROUND))
	var index: int = int(_own.get("color", -1))
	for id: String in _hat_buttons:
		(_hat_buttons[id] as Button).button_pressed = id == hat
	for id: String in _eyes_buttons:
		(_eyes_buttons[id] as Button).button_pressed = id == eyes
	for i in _color_buttons.size():
		var taken: bool = color_taken(i)
		_color_buttons[i].disabled = taken
		_color_buttons[i].modulate = TAKEN_MODULATE if taken else Color.WHITE
		_color_buttons[i].button_pressed = i == index
	var colour: Color = Color.html(str(palette[index])) if index >= 0 and index < palette.size() and not str(palette[index]).is_empty() else Color.WHITE
	_preview.set_look(colour, hat, eyes)

func _build_colors() -> void:
	for button: Button in _color_buttons:
		_color_grid.remove_child(button)
		button.queue_free()
	_color_buttons.clear()
	for i in palette.size():
		var button := Button.new()
		button.name = "Color_%d" % i
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = SWATCH_SIZE
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color.html(str(palette[i])) if not str(palette[i]).is_empty() else Color(0.2, 0.2, 0.2)
		fill.set_corner_radius_all(6)
		var picked_style: StyleBoxFlat = fill.duplicate()
		picked_style.border_color = Color.WHITE
		picked_style.set_border_width_all(4)
		for state: String in ["normal", "hover", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, fill)
		button.add_theme_stylebox_override("pressed", picked_style)
		button.add_theme_stylebox_override("hover_pressed", picked_style)
		button.pressed.connect(pick_color.bind(i))
		_color_grid.add_child(button)
		_color_buttons.append(button)
	_refresh()

func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	return grid

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(110, 36)
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	return button

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label
