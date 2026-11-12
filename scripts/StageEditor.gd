extends Node2D

## The stage editor (#1047, ADR-0026): one stage definition at a time, on the
## host PC with mouse and keyboard. Opened from the title screen by
## `StageTestPlay.open_editor()`; its own scene, `scenes/StageEditor.tscn`.
##
## The working definition is kept in its JSON shape (`StageDef.to_json_data()`:
## vectors as [x, y], every number a float), so what is saved, exported or
## test-played is exactly what is edited. A platform's `pos` is its centre.
##
## The canvas is the "World" child, moved and scaled as the view (no Camera2D,
## so the editor never changes the viewport's own transform): a faint 8 px grid,
## the StageDef bounds, and the normal 1600x900 screen centred on the origin.
## Tools: Select/Move (V), Platform (P) and Spawn (S); positions snap to the
## grid unless Shift is held. The side panel holds the name, a live status line
## (StageDef's reason, or "Ready to save") and New / Open / Save / Import /
## Export / Test / Back to title. Modes are not edited here; a loaded
## definition's `modes` are kept as they are.
##
## Every edit goes through the seams below (`world_press()`, `world_drag()`,
## `world_release()`, `delete_selected()`, ...), so a scenario can drive the
## editor without a mouse; the real input handlers are thin wrappers over them.
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const StageDefScript := preload("res://scripts/StageDef.gd")
const CustomStagesScript := preload("res://scripts/CustomStages.gd")
const StageTestPlayScript := preload("res://scripts/StageTestPlay.gd")
const RemoteClientScript := preload("res://scripts/RemoteClient.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")
const StagePreviewsScript := preload("res://scripts/StagePreviews.gd")
const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")

const TOOL_SELECT: String = "select"
const TOOL_PLATFORM: String = "platform"
const TOOL_SPAWN: String = "spawn"
const TOOLS: Array[String] = [TOOL_SELECT, TOOL_PLATFORM, TOOL_SPAWN]

## The snap grid, in world px.
const GRID: float = 8.0
## A plain click with the Platform tool makes one this size.
const CLICK_PLATFORM_SIZE: Vector2 = Vector2(240, 24)
## The normal screen, outlined about the origin for scale.
const SCREEN_SIZE: Vector2 = Vector2(1600, 900)
## A new stage's name. Not translated: a stage's file key keeps only ASCII
## letters and digits (`CustomStages.file_key()`).
const NEW_STAGE_NAME: String = "New stage"
const UNDO_CAP: int = 100
const ZOOM_MIN: float = 0.1
const ZOOM_MAX: float = 4.0
const ZOOM_STEP: float = 1.15
## Keyboard pan speed, in screen px per second.
const PAN_SPEED_PX: float = 900.0
## S is both the Spawn tool and WASD's down: it pans only once held this long.
const S_PAN_DELAY_SEC: float = 0.2
## Screen-px sizes, the same at every zoom.
const SPAWN_RADIUS_PX: float = 14.0
const HANDLE_PX: float = 7.0
const PICK_PX: float = 8.0
## A Platform-tool press and release closer than this (screen px) is a plain click.
const CLICK_PX: float = 4.0
const PANEL_WIDTH_PX: float = 380.0
const TEXT_PX: int = 18

const CANVAS_COLOR: Color = Color("1B2036")
const BOUNDS_COLOR: Color = Color(1.0, 1.0, 1.0, 0.55)
const SELECT_COLOR: Color = UiThemeScript.YELLOW
const HOVER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.7)

## Which edges a resize handle moves; handles run clockwise from the top-left
## corner: 0 TL, 1 T, 2 TR, 3 R, 4 BR, 5 B, 6 BL, 7 L.
const HANDLE_LEFT: Array[int] = [0, 6, 7]
const HANDLE_RIGHT: Array[int] = [2, 3, 4]
const HANDLE_TOP: Array[int] = [0, 1, 2]
const HANDLE_BOTTOM: Array[int] = [4, 5, 6]

var _def: Dictionary = {}
## The saved file's key ("" until saved or opened).
var _key: String = ""
var _dirty: bool = false
var _tool: String = TOOL_SELECT
## The selected item: "" (none), "part" or "spawn", and its index.
var _sel_kind: String = ""
var _sel_index: int = -1
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
## "name" while the last undo step is a run of name typing (one step for it).
var _last_action: String = ""
var _view_center: Vector2 = Vector2.ZERO
var _zoom: float = 0.5
## The drag in progress: {"mode": "move"/"resize"/"draw", ...}; {} when none.
var _drag: Dictionary = {}
var _panning: bool = false
var _hover: Vector2 = Vector2.ZERO
var _hover_valid: bool = false
var _s_held_sec: float = 0.0
var _message: String = ""
var _builtins: PackedStringArray = PackedStringArray()
var _builtins_read: bool = false

var _world: Node2D
var _ui: CanvasLayer
var _ui_root: Control
var _name_edit: LineEdit
var _status_label: Label
var _counts_label: Label
var _message_label: Label
var _tool_buttons: Dictionary = {}
var _overlay: Control
var _confirm_action: Callable = Callable()
var _confirm_cancel: Callable = Callable()
var _file_dialog: FileDialog

func _ready() -> void:
	_world = Node2D.new()
	_world.name = "World"
	_world.draw.connect(_draw_world)
	add_child(_world)
	_build_ui()
	if not StageTestPlayScript.editor_state.is_empty():
		var state: Dictionary = StageTestPlayScript.editor_state.duplicate(true)
		StageTestPlayScript.editor_state = {}
		restore(state)
	else:
		new_stage()

func _process(delta: float) -> void:
	_keyboard_pan(delta)
	_apply_view()

# --- The definition -------------------------------------------------------------

## A new stage that validates at once: one 1200x24 platform at (0, 200), the
## kill floor at y 900 and eight spawns along the platform's top.
static func new_stage_def() -> Dictionary:
	var spawns: Array = []
	for i in StageDefScript.MIN_SPAWNS:
		spawns.append([-525.0 + 150.0 * i, 160.0])
	return {"schema": StageDefScript.SCHEMA_VERSION, "name": NEW_STAGE_NAME, "spawns": spawns, "parts": [
		{"type": "Platform", "pos": [0.0, 200.0], "size": [1200.0, 24.0], "params": {"one_way": false}},
		{"type": StageDefScript.KILL_FLOOR, "pos": [0.0, 900.0]}]}

## The working definition (JSON shape), a copy.
func working_def() -> Dictionary:
	return _def.duplicate(true)

## The built-in stages' names, which a custom stage may not take.
func builtin_names() -> PackedStringArray:
	if not _builtins_read:
		_builtins_read = true
		for path: String in RemoteClientScript.stage_paths():
			_builtins.append(HostSettingsScript.name_of(path))
	return _builtins

## Starts a new stage at once, dropping any unsaved changes (`request_new()`
## asks first).
func new_stage() -> void:
	_load_def(new_stage_def(), "")
	_message = ""
	frame_stage()

## The definition's status: StageDef's reason, the name's problem, or "Ready
## to save"; then the part and spawn counts on a second line.
func status_text() -> String:
	return "%s\n%s" % [_status_line(), _counts_line()]

func _status_line() -> String:
	var checked: Dictionary = StageDefScript.validate(_def)
	if not bool(checked["ok"]):
		return String(checked["reason"])
	var problem: String = CustomStagesScript.name_problem(String(_def.get("name", "")), builtin_names())
	return problem if problem != "" else tr("STAGE_EDITOR_READY")

func _counts_line() -> String:
	return _trf("STAGE_EDITOR_COUNTS", [_parts().size(), StageDefScript.MAX_PARTS, _spawns().size(),
		StageDefScript.MIN_SPAWNS, StageDefScript.MAX_SPAWNS])

## `tr(key) % args`; when the translation row is missing (a fresh CSV row not
## yet imported) the key and its arguments plainly, never a format error.
func _trf(key: String, args: Variant) -> String:
	var text: String = tr(key)
	if text == key or not text.contains("%"):
		return "%s %s" % [text, str(args)]
	return text % args

## The last action's feedback (saved, refused, ...), "" when none.
func message_text() -> String:
	return _message

func is_dirty() -> bool:
	return _dirty

func saved_key() -> String:
	return _key

func current_tool() -> String:
	return _tool

## The selection as {"kind": "part"/"spawn", "index": i}, or {} when none.
func selection() -> Dictionary:
	if _sel_kind == "":
		return {}
	return {"kind": _sel_kind, "index": _sel_index}

## The view: {"center": Vector2, "zoom": float}.
func view() -> Dictionary:
	return {"center": _view_center, "zoom": _zoom}

func set_view(center: Vector2, zoom: float) -> void:
	_view_center = center
	_zoom = clampf(zoom, ZOOM_MIN, ZOOM_MAX)
	_apply_view()

func set_tool(tool_name: String) -> void:
	if not TOOLS.has(tool_name):
		return
	_tool = tool_name
	_drag = {}
	_refresh()

## Renames the stage (the name field's seam); a run of renames is one undo step.
func set_stage_name(stage_name: String) -> void:
	stage_name = stage_name.left(StageDefScript.MAX_NAME_LENGTH)
	if stage_name == String(_def.get("name", "")):
		return
	var before: Dictionary = working_def()
	_def["name"] = stage_name
	if _last_action == "name" and not _undo.is_empty():
		_dirty = true
	else:
		_push_undo(before)
		_last_action = "name"
	if _name_edit != null and _name_edit.text != stage_name:
		_name_edit.text = stage_name
	_refresh()

func _parts() -> Array:
	return _def.get("parts", []) as Array

func _spawns() -> Array:
	return _def.get("spawns", []) as Array

func _kill_floor_index() -> int:
	var parts: Array = _parts()
	for i in parts.size():
		if (parts[i] as Dictionary).get("type") == StageDefScript.KILL_FLOOR:
			return i
	return -1

func _is_platform(i: int) -> bool:
	return i >= 0 and i < _parts().size() and (_parts()[i] as Dictionary).get("type") != StageDefScript.KILL_FLOOR

static func _vec(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

static func _arr(v: Vector2) -> Array:
	return [float(v.x), float(v.y)]

static func _part_rect(part: Dictionary) -> Rect2:
	var size: Vector2 = _vec(part["size"])
	return Rect2(_vec(part["pos"]) - size * 0.5, size)

## Writes `rect` to platform `i`, kept to StageDef's size limits and bounds.
func _set_platform_rect(i: int, rect: Rect2) -> void:
	var size := Vector2(
		clampf(rect.size.x, StageDefScript.MIN_PART_SIDE, StageDefScript.MAX_PART_WIDTH),
		clampf(rect.size.y, StageDefScript.MIN_PART_SIDE, StageDefScript.MAX_PART_HEIGHT))
	var origin := Vector2(
		clampf(rect.position.x, -StageDefScript.BOUNDS_X, StageDefScript.BOUNDS_X - size.x),
		clampf(rect.position.y, -StageDefScript.BOUNDS_Y, StageDefScript.BOUNDS_Y - size.y))
	var part: Dictionary = _parts()[i]
	part["pos"] = _arr(origin + size * 0.5)
	part["size"] = _arr(size)

static func _clamp_point(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, -StageDefScript.BOUNDS_X, StageDefScript.BOUNDS_X),
		clampf(p.y, -StageDefScript.BOUNDS_Y, StageDefScript.BOUNDS_Y))

## `p` on the 8 px grid, or rounded to whole px when `free` (Shift).
static func snap(p: Vector2, free: bool = false) -> Vector2:
	if free:
		return p.round()
	return (p / GRID).round() * GRID

func _load_def(data: Dictionary, key: String) -> void:
	_def = _as_floats(data.duplicate(true))
	for part: Dictionary in _parts():
		if part.get("type") != StageDefScript.KILL_FLOOR and not part.has("params"):
			part["params"] = {"one_way": false}
	_key = key
	_dirty = false
	_undo.clear()
	_redo.clear()
	_last_action = ""
	_drag = {}
	_clear_selection()
	if _name_edit != null:
		_name_edit.text = String(_def.get("name", ""))
	_refresh()

## Every number in `v` as a float, so equal definitions compare equal.
static func _as_floats(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		for k: Variant in d.keys():
			d[k] = _as_floats(d[k])
		return d
	if v is Array:
		var a: Array = v
		for i in a.size():
			a[i] = _as_floats(a[i])
		return a
	if typeof(v) == TYPE_INT:
		return float(v)
	return v

# --- Undo -----------------------------------------------------------------------

## Records `before` as an undo step when the definition has changed since.
func _push_undo(before: Dictionary) -> void:
	_last_action = ""
	if before == _def:
		return
	_undo.append(before)
	while _undo.size() > UNDO_CAP:
		_undo.pop_front()
	_redo.clear()
	_dirty = true

func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(working_def())
	_def = _undo.pop_back()
	_after_history()
	return true

func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(working_def())
	_def = _redo.pop_back()
	_after_history()
	return true

func undo_depth() -> int:
	return _undo.size()

func redo_depth() -> int:
	return _redo.size()

func _after_history() -> void:
	_dirty = true
	_last_action = ""
	_drag = {}
	_fix_selection()
	if _name_edit != null:
		_name_edit.text = String(_def.get("name", ""))
	_refresh()

# --- Selection and hit-testing ----------------------------------------------------

func _clear_selection() -> void:
	_sel_kind = ""
	_sel_index = -1

func _fix_selection() -> void:
	if (_sel_kind == "part" and _sel_index >= _parts().size()) or (_sel_kind == "spawn" and _sel_index >= _spawns().size()):
		_clear_selection()

## The item at world point `p`: {"kind": "part"/"spawn", "index": i}, or {}.
## Spawns are on top, then platforms (the last drawn first), then the kill floor.
func item_at(p: Vector2) -> Dictionary:
	var spawns: Array = _spawns()
	for i in range(spawns.size() - 1, -1, -1):
		if _vec(spawns[i]).distance_to(p) <= SPAWN_RADIUS_PX / _zoom:
			return {"kind": "spawn", "index": i}
	var parts: Array = _parts()
	var tolerance: float = PICK_PX / _zoom
	for i in range(parts.size() - 1, -1, -1):
		if _is_platform(i) and _part_rect(parts[i]).grow(tolerance * 0.5).has_point(p):
			return {"kind": "part", "index": i}
	var kill: int = _kill_floor_index()
	if kill >= 0 and absf(_vec(parts[kill]["pos"]).y - p.y) <= tolerance:
		return {"kind": "part", "index": kill}
	return {}

## Selects the item at `p` (or nothing). True when something was selected.
func select_at(p: Vector2) -> bool:
	var item: Dictionary = item_at(p)
	if item.is_empty():
		_clear_selection()
	else:
		_sel_kind = item["kind"]
		_sel_index = item["index"]
	_refresh()
	return not item.is_empty()

## The selected platform's handles, world points, in HANDLE_* order.
func _handles(rect: Rect2) -> Array[Vector2]:
	var c: Vector2 = rect.get_center()
	return [rect.position, Vector2(c.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, c.y),
		rect.end, Vector2(c.x, rect.end.y), Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x, c.y)]

## The selected platform's handle at `p`, or -1.
func handle_at(p: Vector2) -> int:
	if _sel_kind != "part" or not _is_platform(_sel_index):
		return -1
	var handles: Array[Vector2] = _handles(_part_rect(_parts()[_sel_index]))
	for i in handles.size():
		if handles[i].distance_to(p) <= (HANDLE_PX + 2.0) / _zoom:
			return i
	return -1

## A selected platform's handle point in world px (a scenario's way to grab it).
func handle_point(handle: int) -> Vector2:
	if _sel_kind != "part" or not _is_platform(_sel_index):
		return Vector2.ZERO
	return _handles(_part_rect(_parts()[_sel_index]))[handle]

# --- Editing seams ------------------------------------------------------------------

## A mouse press at world point `p`. Right-click deletes what is under it; the
## left button acts by tool: Select grabs a handle or item to drag (or clears
## the selection), Platform starts drawing one, Spawn adds a spawn.
func world_press(p: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	_hover = p
	_hover_valid = true
	if button == MOUSE_BUTTON_RIGHT:
		delete_at(p)
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	_drag = {}
	match _tool:
		TOOL_SELECT:
			_press_select(p)
		TOOL_PLATFORM:
			_drag = {"mode": "draw", "press": p, "start": snap(p, shift), "end": snap(p, shift), "before": working_def()}
		TOOL_SPAWN:
			add_spawn(p, shift)
	_refresh()

func _press_select(p: Vector2) -> void:
	var handle: int = handle_at(p)
	if handle >= 0:
		_drag = {"mode": "resize", "press": p, "handle": handle, "index": _sel_index,
			"rect": _part_rect(_parts()[_sel_index]), "before": working_def()}
		return
	if not select_at(p):
		return
	var origin: Vector2
	if _sel_kind == "spawn":
		origin = _vec(_spawns()[_sel_index])
	elif _is_platform(_sel_index):
		origin = _part_rect(_parts()[_sel_index]).position
	else:
		origin = _vec(_parts()[_sel_index]["pos"])
	_drag = {"mode": "move", "press": p, "kind": _sel_kind, "index": _sel_index, "origin": origin, "before": working_def()}

## The mouse dragged to world point `p` (with the left button held).
func world_drag(p: Vector2, shift: bool = false) -> void:
	_hover = p
	_hover_valid = true
	if _drag.is_empty():
		return
	match String(_drag["mode"]):
		"draw":
			_drag["end"] = snap(p, shift)
		"move":
			_drag_move(p, shift)
		"resize":
			_drag_resize(p, shift)
	_refresh()

func _drag_move(p: Vector2, shift: bool) -> void:
	var to: Vector2 = snap(_drag["origin"] + (p - _drag["press"]), shift)
	var i: int = _drag["index"]
	if _drag["kind"] == "spawn":
		_spawns()[i] = _arr(_clamp_point(to))
	elif _is_platform(i):
		var size: Vector2 = _vec(_parts()[i]["size"])
		_set_platform_rect(i, Rect2(to, size))
	else: # the kill floor moves only up and down
		var pos: Vector2 = _drag["origin"]
		_parts()[i]["pos"] = _arr(Vector2(pos.x, clampf(to.y, -StageDefScript.BOUNDS_Y, StageDefScript.BOUNDS_Y)))

func _drag_resize(p: Vector2, shift: bool) -> void:
	var m: Vector2 = snap(p, shift)
	var r: Rect2 = _drag["rect"]
	var h: int = _drag["handle"]
	var left: float = r.position.x
	var right: float = r.end.x
	var top: float = r.position.y
	var bottom: float = r.end.y
	if HANDLE_LEFT.has(h):
		left = clampf(m.x, maxf(right - StageDefScript.MAX_PART_WIDTH, -StageDefScript.BOUNDS_X), right - StageDefScript.MIN_PART_SIDE)
	if HANDLE_RIGHT.has(h):
		right = clampf(m.x, left + StageDefScript.MIN_PART_SIDE, minf(left + StageDefScript.MAX_PART_WIDTH, StageDefScript.BOUNDS_X))
	if HANDLE_TOP.has(h):
		top = clampf(m.y, maxf(bottom - StageDefScript.MAX_PART_HEIGHT, -StageDefScript.BOUNDS_Y), bottom - StageDefScript.MIN_PART_SIDE)
	if HANDLE_BOTTOM.has(h):
		bottom = clampf(m.y, top + StageDefScript.MIN_PART_SIDE, minf(top + StageDefScript.MAX_PART_HEIGHT, StageDefScript.BOUNDS_Y))
	_set_platform_rect(_drag["index"], Rect2(left, top, right - left, bottom - top))

## The left button let go at world point `p`: a drawn platform is made (a
## plain click makes a 240x24 one), and a move or resize becomes one undo step.
func world_release(p: Vector2, shift: bool = false) -> void:
	if _drag.is_empty():
		return
	var drag: Dictionary = _drag
	_drag = {}
	if drag["mode"] == "draw":
		var press: Vector2 = drag["press"]
		if press.distance_to(p) * _zoom < CLICK_PX:
			_add_platform(Rect2(snap(p - CLICK_PLATFORM_SIZE * 0.5, shift), CLICK_PLATFORM_SIZE))
		else:
			_add_platform(_drawn_rect(drag["start"], snap(p, shift)))
	else:
		_push_undo(drag["before"])
	_refresh()

## The box drawn from corner `a` to `b`, kept to the size limits from `a`.
static func _drawn_rect(a: Vector2, b: Vector2) -> Rect2:
	var w: float = clampf(absf(b.x - a.x), StageDefScript.MIN_PART_SIDE, StageDefScript.MAX_PART_WIDTH)
	var h: float = clampf(absf(b.y - a.y), StageDefScript.MIN_PART_SIDE, StageDefScript.MAX_PART_HEIGHT)
	return Rect2(a.x if b.x >= a.x else a.x - w, a.y if b.y >= a.y else a.y - h, w, h)

func _add_platform(rect: Rect2) -> bool:
	if _parts().size() >= StageDefScript.MAX_PARTS:
		_message = _trf("STAGE_EDITOR_TOO_MANY_PARTS", StageDefScript.MAX_PARTS)
		_refresh()
		return false
	var before: Dictionary = working_def()
	_parts().append({"type": "Platform", "pos": [0.0, 0.0], "size": [0.0, 0.0], "params": {"one_way": false}})
	var i: int = _parts().size() - 1
	_set_platform_rect(i, rect)
	_push_undo(before)
	_sel_kind = "part"
	_sel_index = i
	_refresh()
	return true

## Adds a spawn at world point `p` (snapped unless `shift`); refused past
## StageDef.MAX_SPAWNS. True when added.
func add_spawn(p: Vector2, shift: bool = false) -> bool:
	if _spawns().size() >= StageDefScript.MAX_SPAWNS:
		_message = _trf("STAGE_EDITOR_TOO_MANY_SPAWNS", StageDefScript.MAX_SPAWNS)
		_refresh()
		return false
	var before: Dictionary = working_def()
	_spawns().append(_arr(_clamp_point(snap(p, shift))))
	_push_undo(before)
	_sel_kind = "spawn"
	_sel_index = _spawns().size() - 1
	_refresh()
	return true

## Deletes the selected item. The kill floor stays: every stage needs exactly
## one. True when something was deleted.
func delete_selected() -> bool:
	if _sel_kind == "":
		return false
	if _sel_kind == "part" and not _is_platform(_sel_index):
		_message = tr("STAGE_EDITOR_KILL_FLOOR_STAYS")
		_refresh()
		return false
	var before: Dictionary = working_def()
	if _sel_kind == "spawn":
		_spawns().remove_at(_sel_index)
	else:
		_parts().remove_at(_sel_index)
	_push_undo(before)
	_clear_selection()
	_refresh()
	return true

## Deletes the item at world point `p` (right-click). True when deleted.
func delete_at(p: Vector2) -> bool:
	if not select_at(p):
		return false
	return delete_selected()

## Toggles one-way on the selected platform. True when there was one.
func toggle_one_way() -> bool:
	if _sel_kind != "part" or not _is_platform(_sel_index):
		return false
	var before: Dictionary = working_def()
	var part: Dictionary = _parts()[_sel_index]
	var params: Dictionary = part.get("params", {})
	params["one_way"] = not bool(params.get("one_way", false))
	part["params"] = params
	_push_undo(before)
	_refresh()
	return true

# --- File actions ---------------------------------------------------------------

## Saves to the store (`CustomStages.save()`), the result as it gives it; on a
## refusal its reason is shown.
func save_stage(overwrite: bool = false) -> Dictionary:
	# Saving the stage that is open over its own file needs no asking (#1047 review).
	var own: bool = _key != "" and CustomStagesScript.file_key(String(_def.get("name", ""))).to_lower() == _key.to_lower()
	var res: Dictionary = CustomStagesScript.save(_def, builtin_names(), overwrite or own)
	if bool(res.get("exists", false)):
		show_confirm(_trf("STAGE_EDITOR_REPLACE_CONFIRM", res["key"]), save_stage.bind(true))
		return res
	if bool(res["ok"]):
		_key = res["key"]
		_dirty = false
		_message = _trf("STAGE_EDITOR_SAVED", _key)
	else:
		_message = _trf("STAGE_EDITOR_NOT_SAVED", res["reason"])
	_refresh()
	return res

## Opens the saved stage `key` at once (`request_open()` asks first when there
## are unsaved changes).
func open_key(key: String) -> Dictionary:
	var res: Dictionary = CustomStagesScript.load_stage(key)
	if bool(res["ok"]):
		close_popup()
		_load_def(res["def"], key)
		frame_stage()
		_message = _trf("STAGE_EDITOR_OPENED", key)
	else:
		_message = _trf("STAGE_EDITOR_NOT_OPENED", res["reason"])
	_refresh()
	return res

## Imports the file at `path` into the store and opens it.
func import_path(path: String, overwrite: bool = false) -> Dictionary:
	var res: Dictionary = CustomStagesScript.import_file(path, builtin_names(), overwrite)
	if bool(res.get("exists", false)):
		show_confirm(_trf("STAGE_EDITOR_REPLACE_CONFIRM", res["key"]), import_path.bind(path, true))
		return res
	if bool(res["ok"]):
		open_key(res["key"])
		_message = _trf("STAGE_EDITOR_IMPORTED", res["key"])
	else:
		_message = _trf("STAGE_EDITOR_NOT_IMPORTED", res["reason"])
	_refresh()
	return res

## Exports the working definition to the file at `path`.
func export_path(path: String) -> Dictionary:
	var res: Dictionary = CustomStagesScript.export_file(_def, path)
	if bool(res["ok"]):
		_message = _trf("STAGE_EDITOR_EXPORTED", path)
	else:
		_message = _trf("STAGE_EDITOR_NOT_EXPORTED", res["reason"])
	_refresh()
	return res

## Test-plays the working definition, saved or not. "" when the game is
## starting, else why not (shown).
func test_play() -> String:
	_drag = {}
	var reason: String = StageTestPlayScript.start(get_tree(), working_def(), editor_state())
	if reason != "":
		_message = _trf("STAGE_EDITOR_CANT_TEST", reason)
		_refresh()
	return reason

## New, asking first when there are unsaved changes.
func request_new() -> void:
	_guard_unsaved(new_stage)

## Opens the saved stage `key`, asking first when there are unsaved changes.
func request_open(key: String) -> void:
	_guard_unsaved(func() -> void: open_key(key))

## Back to the title screen, asking first when there are unsaved changes.
func request_back() -> void:
	_guard_unsaved(func() -> void: StageTestPlayScript.back_to_title(get_tree()))

func _guard_unsaved(action: Callable) -> void:
	if _dirty:
		show_confirm(tr("STAGE_EDITOR_DISCARD"), action)
	else:
		close_popup()
		action.call()

# --- Test-play hand-off -----------------------------------------------------------

## Everything needed to come back exactly as left after a test round.
func editor_state() -> Dictionary:
	return {"def": working_def(), "key": _key, "dirty": _dirty, "tool": _tool,
		"view_center": _view_center, "zoom": _zoom, "selection": selection(),
		"undo": _undo.duplicate(true), "redo": _redo.duplicate(true)}

## Takes back what `editor_state()` gave.
func restore(state: Dictionary) -> void:
	_load_def(state.get("def", new_stage_def()), String(state.get("key", "")))
	_dirty = bool(state.get("dirty", false))
	_tool = String(state.get("tool", TOOL_SELECT)) if TOOLS.has(state.get("tool")) else TOOL_SELECT
	for step: Variant in state.get("undo", []):
		_undo.append(step as Dictionary)
	for step: Variant in state.get("redo", []):
		_redo.append(step as Dictionary)
	var sel: Dictionary = state.get("selection", {})
	if not sel.is_empty():
		_sel_kind = String(sel.get("kind", ""))
		_sel_index = int(sel.get("index", -1))
		_fix_selection()
	set_view(state.get("view_center", Vector2.ZERO), float(state.get("zoom", 0.5)))
	_refresh()

# --- View -----------------------------------------------------------------------

## The part of the screen the canvas shows (left of the side panel).
func _canvas_size() -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	return Vector2(maxf(vp.x - PANEL_WIDTH_PX, 1.0), maxf(vp.y, 1.0))

func _apply_view() -> void:
	if _world == null:
		return
	_world.scale = Vector2(_zoom, _zoom)
	_world.position = _canvas_size() * 0.5 - _view_center * _zoom
	_world.queue_redraw()

## A screen (viewport) point in world px.
func screen_to_world(p: Vector2) -> Vector2:
	return (p - (_canvas_size() * 0.5 - _view_center * _zoom)) / _zoom

## Zooms by `factor` keeping the world point under screen point `at` still.
func zoom_at(at: Vector2, factor: float) -> void:
	var before: Vector2 = screen_to_world(at)
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_view_center += before - screen_to_world(at)
	_apply_view()

## Frames the whole stage (Home): its platforms, spawns and kill floor.
func frame_stage() -> void:
	var box := Rect2()
	var first: bool = true
	var points: Array[Vector2] = []
	for part: Dictionary in _parts():
		if part.get("type") == StageDefScript.KILL_FLOOR:
			points.append(_vec(part["pos"]))
		else:
			var r: Rect2 = _part_rect(part)
			points.append(r.position)
			points.append(r.end)
	for s: Variant in _spawns():
		points.append(_vec(s))
	for p: Vector2 in points:
		if first:
			box = Rect2(p, Vector2.ZERO)
			first = false
		else:
			box = box.expand(p)
	box = box.grow(80.0)
	var area: Vector2 = _canvas_size() * 0.9
	_zoom = clampf(minf(area.x / maxf(box.size.x, 1.0), area.y / maxf(box.size.y, 1.0)), ZOOM_MIN, 1.0)
	_view_center = box.get_center()
	_apply_view()

func _keyboard_pan(delta: float) -> void:
	_s_held_sec = _s_held_sec + delta if Input.is_physical_key_pressed(KEY_S) else 0.0
	if _overlay != null or Input.is_key_pressed(KEY_CTRL) or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN) or _s_held_sec >= S_PAN_DELAY_SEC:
		dir.y += 1.0
	if dir != Vector2.ZERO:
		_view_center += dir.normalized() * PAN_SPEED_PX * delta / _zoom

# --- Input ----------------------------------------------------------------------

## A drag or pan in progress takes the mouse ahead of the GUI, so letting go
## over the side panel still ends it.
func _input(event: InputEvent) -> void:
	if _drag.is_empty() and not _panning:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_mouse_motion(motion)
		get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click != null and not click.pressed:
		if click.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = false
		elif click.button_index == MOUSE_BUTTON_LEFT:
			world_release(screen_to_world(click.position), click.shift_pressed)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null:
		if key.pressed and not key.echo and _key_pressed(key):
			get_viewport().set_input_as_handled()
		return
	if _overlay != null:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_mouse_motion(motion)
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	match click.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			zoom_at(click.position, ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(click.position, 1.0 / ZOOM_STEP)
		MOUSE_BUTTON_MIDDLE:
			_panning = true
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			get_viewport().gui_release_focus()
			world_press(screen_to_world(click.position), click.button_index, click.shift_pressed)
		_:
			return
	get_viewport().set_input_as_handled()

func _mouse_motion(motion: InputEventMouseMotion) -> void:
	if _panning:
		_view_center -= motion.relative / _zoom
		_apply_view()
		return
	var p: Vector2 = screen_to_world(motion.position)
	if not _drag.is_empty():
		world_drag(p, motion.shift_pressed)
	else:
		_hover = p
		_hover_valid = true

## The editor's keys. True when the key was the editor's. Esc closes a popup,
## else does nothing (and never reaches the settings menu: no accidental exit).
func _key_pressed(key: InputEventKey) -> bool:
	if key.keycode == KEY_ESCAPE:
		if _overlay != null:
			close_popup()
		elif _file_dialog != null and _file_dialog.visible:
			_file_dialog.hide()
		return true
	if _overlay != null:
		return false
	if key.ctrl_pressed or key.meta_pressed: # Ctrl everywhere, and Cmd on macOS too (#1047 review)
		match key.keycode:
			KEY_Z:
				if key.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y:
				redo()
			KEY_S:
				save_stage()
			_:
				return false
		return true
	match key.keycode:
		KEY_V:
			set_tool(TOOL_SELECT)
		KEY_P:
			set_tool(TOOL_PLATFORM)
		KEY_S:
			set_tool(TOOL_SPAWN)
		KEY_O:
			toggle_one_way()
		KEY_HOME:
			frame_stage()
		KEY_DELETE, KEY_BACKSPACE:
			# The hovered item only while the mouse is over the canvas, not the side panel.
			var over_canvas: bool = get_viewport().gui_get_hovered_control() == null
			if over_canvas and _hover_valid and not item_at(_hover).is_empty():
				delete_at(_hover)
			else:
				delete_selected()
		_:
			return false
	return true

# --- Drawing --------------------------------------------------------------------

## The world rect the canvas shows.
func _visible_world_rect() -> Rect2:
	var vp: Vector2 = get_viewport_rect().size
	var a: Vector2 = screen_to_world(Vector2.ZERO)
	return Rect2(a, vp / _zoom)

func _draw_world() -> void:
	var view_rect: Rect2 = _visible_world_rect()
	_world.draw_rect(view_rect, CANVAS_COLOR)
	var bounds := Rect2(-StageDefScript.BOUNDS_X, -StageDefScript.BOUNDS_Y, StageDefScript.BOUNDS_X * 2.0, StageDefScript.BOUNDS_Y * 2.0)
	_draw_grid(view_rect.intersection(bounds))
	_world.draw_rect(bounds, BOUNDS_COLOR, false, 2.0 / _zoom)
	var screen := Rect2(-SCREEN_SIZE * 0.5, SCREEN_SIZE)
	_world.draw_rect(screen, Color(UiThemeScript.SKY, 0.8), false, 2.0 / _zoom)
	_draw_text(screen.position + Vector2(6, -8) / _zoom, tr("STAGE_EDITOR_SCREEN_LABEL"), 16, UiThemeScript.SKY)
	var hovered: Dictionary = item_at(_hover) if _hover_valid and _drag.is_empty() else {}
	var parts: Array = _parts()
	for i in parts.size():
		if _is_platform(i):
			_draw_platform(i, hovered)
	var kill: int = _kill_floor_index()
	if kill >= 0:
		_draw_kill_floor(kill, hovered)
	if not _drag.is_empty() and _drag["mode"] == "draw":
		var r: Rect2 = _drawn_rect(_drag["start"], _drag["end"])
		_world.draw_rect(r, Color(SELECT_COLOR, 0.35))
		_world.draw_rect(r, SELECT_COLOR, false, 2.0 / _zoom)
	var spawns: Array = _spawns()
	for i in spawns.size():
		_draw_spawn(i, hovered)

## The grid: 8 px lines when they are far enough apart, else 64 or 256; every
## 64th and 256th px line a little stronger.
func _draw_grid(area: Rect2) -> void:
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var step: float = GRID
	while step * _zoom < 6.0 and step < 256.0:
		step = 64.0 if step < 64.0 else 256.0
	var lines: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	var x: float = ceilf(area.position.x / step) * step
	while x <= area.end.x:
		var level: int = 2 if fmod(absf(x), 256.0) == 0.0 else (1 if fmod(absf(x), 64.0) == 0.0 else 0)
		lines[level].append_array([Vector2(x, area.position.y), Vector2(x, area.end.y)])
		x += step
	var y: float = ceilf(area.position.y / step) * step
	while y <= area.end.y:
		var level: int = 2 if fmod(absf(y), 256.0) == 0.0 else (1 if fmod(absf(y), 64.0) == 0.0 else 0)
		lines[level].append_array([Vector2(area.position.x, y), Vector2(area.end.x, y)])
		y += step
	var alphas: Array[float] = [0.05, 0.1, 0.18]
	for level in 3:
		if lines[level].size() >= 2:
			_world.draw_multiline(lines[level], Color(1.0, 1.0, 1.0, alphas[level]), -1.0)

func _draw_platform(i: int, hovered: Dictionary) -> void:
	var part: Dictionary = _parts()[i]
	var r: Rect2 = _part_rect(part)
	var one_way: bool = bool((part.get("params", {}) as Dictionary).get("one_way", false))
	var selected: bool = _sel_kind == "part" and _sel_index == i
	if one_way:
		_world.draw_rect(r, Color(StagePreviewsScript.ONE_WAY, 0.55))
		_world.draw_dashed_line(r.position, Vector2(r.end.x, r.position.y), StagePreviewsScript.ONE_WAY, 4.0 / _zoom, 12.0 / _zoom)
	else:
		_world.draw_rect(r, StagePreviewsScript.PLATFORM)
	var outline: Color = SELECT_COLOR if selected else (HOVER_COLOR if hovered.get("kind") == "part" and hovered.get("index") == i else UiThemeScript.INK)
	_world.draw_rect(r, outline, false, (3.0 if selected else 1.5) / _zoom)
	if selected:
		for h: Vector2 in _handles(r):
			var half: float = HANDLE_PX / _zoom
			_world.draw_rect(Rect2(h - Vector2(half, half), Vector2(half, half) * 2.0), SELECT_COLOR)
			_world.draw_rect(Rect2(h - Vector2(half, half), Vector2(half, half) * 2.0), UiThemeScript.INK, false, 1.5 / _zoom)

func _draw_kill_floor(i: int, hovered: Dictionary) -> void:
	var pos: Vector2 = _vec(_parts()[i]["pos"])
	var selected: bool = _sel_kind == "part" and _sel_index == i
	var lit: bool = selected or (hovered.get("kind") == "part" and hovered.get("index") == i)
	_world.draw_line(Vector2(-StageDefScript.BOUNDS_X, pos.y), Vector2(StageDefScript.BOUNDS_X, pos.y),
		StagePreviewsScript.KILL, (4.0 if lit else 2.5) / _zoom)
	var half: float = (HANDLE_PX + 2.0) / _zoom
	var handle := Rect2(pos - Vector2(half, half), Vector2(half, half) * 2.0)
	_world.draw_rect(handle, SELECT_COLOR if selected else StagePreviewsScript.KILL)
	_world.draw_rect(handle, UiThemeScript.INK, false, 1.5 / _zoom)
	_draw_text(pos + Vector2(14, -6) / _zoom, tr("STAGE_EDITOR_KILL_FLOOR"), 16, StagePreviewsScript.KILL)

func _draw_spawn(i: int, hovered: Dictionary) -> void:
	var p: Vector2 = _vec(_spawns()[i])
	var selected: bool = _sel_kind == "spawn" and _sel_index == i
	var lit: bool = selected or (hovered.get("kind") == "spawn" and hovered.get("index") == i)
	_world.draw_set_transform(p, 0.0, Vector2.ONE / _zoom)
	_world.draw_circle(Vector2.ZERO, SPAWN_RADIUS_PX, StagePreviewsScript.SPAWN)
	_world.draw_arc(Vector2.ZERO, SPAWN_RADIUS_PX, 0.0, TAU, 24, Color.WHITE if lit else UiThemeScript.INK, 3.0 if lit else 1.5)
	var font: Font = ThemeDB.fallback_font
	var label: String = str(i + 1)
	var size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	_world.draw_string(font, Vector2(-size.x * 0.5, font.get_ascent(16) * 0.5 - 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiThemeScript.INK)
	_world.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Text at world point `at`, `px` screen px tall whatever the zoom.
func _draw_text(at: Vector2, text: String, px: int, color: Color) -> void:
	_world.draw_set_transform(at, 0.0, Vector2.ONE / _zoom)
	_world.draw_string(ThemeDB.fallback_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
	_world.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# --- UI -------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	add_child(_ui)
	_ui_root = Control.new()
	_ui_root.name = "Root"
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_ui_root)
	_build_toolbar()
	_build_panel()

func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.name = "Toolbar"
	bar.theme_type_variation = UiThemeScript.CREAM_PANEL
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.position = Vector2(16, 16)
	_ui_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	var labels: Dictionary = {TOOL_SELECT: "STAGE_EDITOR_TOOL_SELECT", TOOL_PLATFORM: "STAGE_EDITOR_TOOL_PLATFORM", TOOL_SPAWN: "STAGE_EDITOR_TOOL_SPAWN"}
	for tool_name: String in TOOLS:
		var button: Button = ScreenKitScript.themed_button(tr(labels[tool_name]), UiThemeScript.SEG_BUTTON, "Tool_" + tool_name)
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(set_tool.bind(tool_name))
		_tool_buttons[tool_name] = button
		row.add_child(button)

func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = UiThemeScript.CARD_PANEL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_WIDTH_PX + 8.0
	panel.offset_right = -12.0
	panel.offset_top = 12.0
	panel.offset_bottom = -12.0
	_ui_root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(ScreenKitScript.themed_label(tr("STAGE_EDITOR_TITLE"), 34, UiThemeScript.INK_HEADING_LABEL, HORIZONTAL_ALIGNMENT_LEFT, "Title"))
	column.add_child(ScreenKitScript.themed_label(tr("STAGE_EDITOR_NAME"), TEXT_PX, UiThemeScript.INK_BOLD_LABEL))
	_name_edit = LineEdit.new()
	_name_edit.name = "Name"
	_name_edit.max_length = StageDefScript.MAX_NAME_LENGTH
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.text_changed.connect(set_stage_name)
	_name_edit.text_submitted.connect(func(_text: String) -> void: _name_edit.release_focus())
	column.add_child(_name_edit)
	_status_label = ScreenKitScript.themed_label("", 20, UiThemeScript.INK_BOLD_LABEL, HORIZONTAL_ALIGNMENT_LEFT, "Status", TextServer.AUTOWRAP_WORD_SMART)
	column.add_child(_status_label)
	_counts_label = ScreenKitScript.themed_label("", TEXT_PX, UiThemeScript.HINT_LABEL, HORIZONTAL_ALIGNMENT_LEFT, "Counts")
	column.add_child(_counts_label)
	_message_label = ScreenKitScript.themed_label("", TEXT_PX, UiThemeScript.INK_LABEL, HORIZONTAL_ALIGNMENT_LEFT, "Message", TextServer.AUTOWRAP_WORD_SMART)
	column.add_child(_message_label)
	var grid := GridContainer.new()
	grid.name = "Buttons"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	var actions: Array = [
		["New", "STAGE_EDITOR_NEW", UiThemeScript.ACTION_BUTTON, request_new],
		["Open", "STAGE_EDITOR_OPEN", UiThemeScript.ACTION_BUTTON, show_open_list],
		["Save", "STAGE_EDITOR_SAVE", UiThemeScript.ACTION_BUTTON, save_stage.bind(false)],
		["Test", "STAGE_EDITOR_TEST", UiThemeScript.YELLOW_BUTTON, test_play],
		["Import", "STAGE_EDITOR_IMPORT", UiThemeScript.ACTION_BUTTON, func() -> void: _guard_unsaved(_show_file_dialog.bind(true))],
		["Export", "STAGE_EDITOR_EXPORT", UiThemeScript.ACTION_BUTTON, _show_file_dialog.bind(false)],
	]
	for action: Array in actions:
		var button: Button = ScreenKitScript.themed_button(tr(action[1]), action[2], action[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var call: Callable = action[3]
		button.pressed.connect(func() -> void: call.call())
		grid.add_child(button)
	var back: Button = ScreenKitScript.themed_button(tr("STAGE_EDITOR_BACK"), UiThemeScript.PINK_BUTTON, "Back")
	back.pressed.connect(request_back)
	column.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	column.add_child(ScreenKitScript.themed_label(tr("STAGE_EDITOR_HELP"), 16, UiThemeScript.HINT_LABEL, HORIZONTAL_ALIGNMENT_LEFT, "Help", TextServer.AUTOWRAP_WORD_SMART))

func _refresh() -> void:
	if _status_label != null:
		_status_label.text = _status_line()
		_counts_label.text = _counts_line()
		_message_label.text = _message
	for tool_name: String in _tool_buttons:
		(_tool_buttons[tool_name] as Button).theme_type_variation = UiThemeScript.SEG_BUTTON_ON if tool_name == _tool else UiThemeScript.SEG_BUTTON
	if _world != null:
		_world.queue_redraw()

# --- Popups ---------------------------------------------------------------------

## The open popup (the stage list or a confirm), or null.
func popup() -> Control:
	return _overlay

func close_popup() -> void:
	if _overlay != null:
		_overlay.hide()
		_overlay.queue_free()
		_overlay = null
	var cancel: Callable = _confirm_cancel
	_confirm_action = Callable()
	_confirm_cancel = Callable()
	if cancel.is_valid():
		cancel.call()

## A dimmed full-screen overlay with a card, returning the card's column.
func _open_popup(node_name: String, width: float) -> VBoxContainer:
	close_popup()
	_overlay = Control.new()
	_overlay.name = node_name
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_root.add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	var card := PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = UiThemeScript.DIALOG_CARD
	card.custom_minimum_size.x = width
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	return column

## Asks `text`; Yes runs `on_yes`, No or Esc runs `on_no` (when given).
func show_confirm(text: String, on_yes: Callable, on_no: Callable = Callable()) -> void:
	var column: VBoxContainer = _open_popup("Confirm", 560.0)
	var label: Label = ScreenKitScript.themed_label(text, 24, UiThemeScript.INK_HEADING_LABEL, HORIZONTAL_ALIGNMENT_CENTER, "Question", TextServer.AUTOWRAP_WORD_SMART)
	column.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	var yes: Button = ScreenKitScript.themed_button(tr("STAGE_EDITOR_YES"), UiThemeScript.YELLOW_BUTTON, "Yes", true)
	yes.pressed.connect(confirm_yes)
	row.add_child(yes)
	var no: Button = ScreenKitScript.themed_button(tr("STAGE_EDITOR_NO"), UiThemeScript.ACTION_BUTTON, "No", true)
	no.pressed.connect(close_popup)
	row.add_child(no)
	_confirm_action = on_yes
	_confirm_cancel = on_no

func is_confirm_open() -> bool:
	return _overlay != null and _overlay.name == "Confirm"

## Answers the open confirm with Yes.
func confirm_yes() -> void:
	var action: Callable = _confirm_action
	_confirm_cancel = Callable()
	close_popup()
	if action.is_valid():
		action.call()

## The Open popup: every saved stage, an invalid one greyed with its reason;
## a stage's name opens it, Delete removes it (after a confirm).
func show_open_list() -> void:
	var column: VBoxContainer = _open_popup("OpenList", 760.0)
	ScreenKitScript.popup_head(column, tr("STAGE_EDITOR_OPEN_TITLE"), 34, close_popup)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	var entries: Array[Dictionary] = CustomStagesScript.list()
	# #1253, #1255: what recovering an unfinished save did, at the top of the list.
	var notes: PackedStringArray = PackedStringArray()
	if not CustomStagesScript.recovery_problems.is_empty():
		notes.append(_trf("STAGE_EDITOR_RECOVERY_FAILED", ", ".join(CustomStagesScript.recovery_problems)))
	if not CustomStagesScript.recovery_notes.is_empty():
		notes.append(_trf("STAGE_EDITOR_RECOVERED_COPY", ", ".join(CustomStagesScript.recovery_notes)))
	if not notes.is_empty():
		var note: Label = ScreenKitScript.themed_label("\n".join(notes), 18, UiThemeScript.HINT_LABEL, HORIZONTAL_ALIGNMENT_LEFT, "RecoveryNote", TextServer.AUTOWRAP_WORD_SMART)
		rows.add_child(note)
		_message = "\n".join(notes)
		_refresh()
	if entries.is_empty():
		rows.add_child(ScreenKitScript.themed_label(tr("STAGE_EDITOR_OPEN_EMPTY"), 20, UiThemeScript.HINT_LABEL))
	for entry: Dictionary in entries:
		var key: String = entry["key"]
		var row := HBoxContainer.new()
		row.name = "Row_" + key.validate_node_name()
		row.add_theme_constant_override("separation", 10)
		rows.add_child(row)
		var open: Button = ScreenKitScript.themed_button(key, UiThemeScript.ACTION_BUTTON, "Open", true)
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.disabled = not bool(entry["ok"])
		open.pressed.connect(request_open.bind(key))
		row.add_child(open)
		if not bool(entry["ok"]):
			row.modulate = Color(1, 1, 1, 0.55)
			open.tooltip_text = entry["reason"]
			var why: Label = ScreenKitScript.themed_label(entry["reason"], 16, UiThemeScript.HINT_LABEL, HORIZONTAL_ALIGNMENT_LEFT, "Reason", TextServer.AUTOWRAP_WORD_SMART)
			why.custom_minimum_size.x = 260.0
			row.add_child(why)
		var delete: Button = ScreenKitScript.themed_button(tr("STAGE_EDITOR_DELETE"), UiThemeScript.PINK_BUTTON, "Delete", true)
		delete.pressed.connect(request_delete.bind(key))
		row.add_child(delete)

## Asks, then deletes the saved stage `key` and shows the list again.
func request_delete(key: String) -> void:
	show_confirm(_trf("STAGE_EDITOR_DELETE_CONFIRM", key), _delete_and_list.bind(key), show_open_list)

func _delete_and_list(key: String) -> void:
	delete_key(key)
	show_open_list()

## Deletes the saved stage `key` at once. The open stage stays open, unsaved.
func delete_key(key: String) -> bool:
	var gone: bool = CustomStagesScript.delete(key)
	if gone:
		_message = _trf("STAGE_EDITOR_DELETED", key)
		if key == _key:
			_key = ""
			_dirty = true
		_refresh()
	return gone

## Import (`opening` true) or Export: the OS file dialog, for `*.json`.
func _show_file_dialog(opening: bool) -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.name = "FileDialog"
		_file_dialog.use_native_dialog = true
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.json"])
		_file_dialog.file_selected.connect(_on_file_selected)
		_ui_root.add_child(_file_dialog)
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if opening else FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.title = tr("STAGE_EDITOR_IMPORT_TITLE") if opening else tr("STAGE_EDITOR_EXPORT_TITLE")
	_file_dialog.set_meta("opening", opening)
	if not opening:
		var key: String = CustomStagesScript.file_key(String(_def.get("name", "")))
		_file_dialog.current_file = "%s.json" % (key if key != "" else "stage")
	_file_dialog.popup_centered(Vector2i(900, 600))

func _on_file_selected(path: String) -> void:
	if bool(_file_dialog.get_meta("opening", false)):
		import_path(path)
	else:
		export_path(path)
