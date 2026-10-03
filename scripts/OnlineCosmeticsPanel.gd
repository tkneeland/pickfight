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
## Restyled in #547 as the "Your look" popup (`set_popup_layout(true)`): a live
## preview on the left, Colour, Hat and Eyes on the right, Done at the bottom.
## Without that call it is the narrow stack the PC client shows beside its player
## list. Opened from the Host panel's Your look button or by clicking the host's
## own player card (`LobbyPopups.gd`).
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

signal picked(kind: String, value: Variant)
## The popup layout's Done button.
signal done_pressed

const PickerScript := preload("res://scripts/CosmeticsPicker.gd")
const PreviewScript := preload("res://scripts/CosmeticsPreview.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")
const ScreenKitScript := preload("res://scripts/ScreenKit.gd")

const TITLE_SIZE: int = 24
const FONT_SIZE: int = 18
const PREVIEW_SIZE: Vector2 = Vector2(140, 160)
const POPUP_PREVIEW_SIZE: Vector2 = Vector2(260, 260)
const SWATCH_SIZE: Vector2 = Vector2(48, 48)
const POPUP_SWATCH_HEIGHT: float = 52.0
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
var _popup_layout: bool = false
var _root: BoxContainer
var _title: Label
var _headings: Array[Label] = []
var _preview_frame: PanelContainer
var _preview_note: Label
var _taken_note: Label
var _done_row: HBoxContainer

func _init() -> void:
	name = "CosmeticsPanel"
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	_root = BoxContainer.new()
	_root.vertical = true
	_root.add_theme_constant_override("separation", 8)
	margin.add_child(_root)
	var left := VBoxContainer.new()
	left.name = "Left"
	left.add_theme_constant_override("separation", 8)
	_root.add_child(left)
	_title = _label(tr("PICKER_TITLE"), TITLE_SIZE)
	left.add_child(_title)
	_preview_frame = PanelContainer.new()
	_preview_frame.name = "PreviewFrame"
	left.add_child(_preview_frame)
	_preview = PreviewScript.new()
	_preview.custom_minimum_size = PREVIEW_SIZE
	_preview_frame.add_child(_preview)
	_preview_note = ScreenKitScript.themed_label(tr("PICKER_LIVE_NOTE"), 17, UiThemeScript.HINT_LABEL, HORIZONTAL_ALIGNMENT_CENTER)
	_preview_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_note.visible = false
	left.add_child(_preview_note)
	var right := VBoxContainer.new()
	right.name = "Right"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	_root.add_child(right)
	right.add_child(_heading(tr("PICKER_COLOUR")))
	_color_grid = _grid(8)
	right.add_child(_color_grid)
	right.add_child(_heading(tr("PICKER_HAT")))
	_hat_grid = _grid(3)
	right.add_child(_hat_grid)
	for id: String in PickerScript.options("hat"):
		var button: Button = _button(PickerScript.label_of("hat", id))
		button.name = "Hat_" + id
		button.pressed.connect(pick_hat.bind(id))
		_hat_grid.add_child(button)
		_hat_buttons[id] = button
	right.add_child(_heading(tr("PICKER_EYES")))
	_eyes_grid = _grid(3)
	right.add_child(_eyes_grid)
	for id: String in PickerScript.options("eyes"):
		var button: Button = _button(PickerScript.label_of("eyes", id))
		button.name = "Eyes_" + id
		button.pressed.connect(pick_eyes.bind(id))
		_eyes_grid.add_child(button)
		_eyes_buttons[id] = button
	_taken_note = ScreenKitScript.themed_label(tr("PICKER_TAKEN_NOTE"), 16, UiThemeScript.HINT_LABEL)
	_taken_note.visible = false
	right.add_child(_taken_note)
	_done_row = HBoxContainer.new()
	_done_row.name = "DoneRow"
	_done_row.alignment = BoxContainer.ALIGNMENT_END
	_done_row.visible = false
	right.add_child(_done_row)
	var done: Button = ScreenKitScript.themed_button(tr("PICKER_DONE"), UiThemeScript.YELLOW_BUTTON, "Done")
	done.add_theme_font_size_override("font_size", 30)
	done.focus_mode = Control.FOCUS_ALL
	done.pressed.connect(func() -> void: done_pressed.emit())
	_done_row.add_child(done)
	_apply_layout()

## The Your look popup's layout (#547): the preview on the left on its dark
## stage, Colour, Hat and Eyes on the right, a note about greyed colours and a
## Done button, on the popup's own cream card (this panel draws no card then).
func set_popup_layout(on: bool) -> void:
	_popup_layout = on
	_apply_layout()
	if _color_grid != null and not palette.is_empty():
		_build_colors()

func is_popup_layout() -> bool:
	return _popup_layout

## The Done button, or null before it was built.
func done_button() -> Button:
	return _done_row.get_node_or_null("Done") as Button

func _apply_layout() -> void:
	_root.vertical = not _popup_layout
	_root.add_theme_constant_override("separation", 36 if _popup_layout else 8)
	_hat_grid.columns = 5 if _popup_layout else 3
	_eyes_grid.columns = 6 if _popup_layout else 3
	_preview.custom_minimum_size = POPUP_PREVIEW_SIZE if _popup_layout else PREVIEW_SIZE
	_preview_note.visible = _popup_layout
	_taken_note.visible = _popup_layout
	_done_row.visible = _popup_layout
	_title.add_theme_font_size_override("font_size", 44 if _popup_layout else TITLE_SIZE)
	_title.theme_type_variation = UiThemeScript.INK_HEADING_LABEL if _popup_layout else UiThemeScript.HEADING_LABEL
	for heading: Label in _headings:
		heading.add_theme_font_size_override("font_size", 26 if _popup_layout else FONT_SIZE)
		heading.theme_type_variation = UiThemeScript.INK_HEADING_LABEL if _popup_layout else UiThemeScript.HEADING_LABEL
	if _popup_layout:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_preview_frame.theme_type_variation = UiThemeScript.PREVIEW_STAGE
		_preview_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		remove_theme_stylebox_override("panel")
		_preview_frame.theme_type_variation = &""

func _heading(text: String) -> Label:
	var label: Label = _label(text, FONT_SIZE)
	_headings.append(label)
	return label

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
		button.custom_minimum_size = Vector2(0, POPUP_SWATCH_HEIGHT) if _popup_layout else SWATCH_SIZE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _popup_layout else Control.SIZE_FILL
		var colour: Color = Color.html(str(palette[i])) if not str(palette[i]).is_empty() else Color(0.2, 0.2, 0.2)
		var fill := UiThemeScript.box(colour, 12, 4, Vector2(3, 3), Vector4(0, 0, 0, 0))
		var picked_style := UiThemeScript.box(colour, 12, 6, Vector2(0, 0), Vector4(0, 0, 0, 0))
		picked_style.shadow_color = Color.WHITE
		picked_style.shadow_size = 5
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
	button.theme_type_variation = UiThemeScript.PICK_BUTTON
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = UiThemeScript.HEADING_LABEL
	label.add_theme_font_size_override("font_size", font_size)
	return label
