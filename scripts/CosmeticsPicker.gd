extends RefCounted
## The in-game cosmetics picker's model (#441, ADR-0021): what a player without a
## phone picks hat, colour and eyes from. One model, two layouts: the compact
## slot-style card on a gamepad seat's lobby card (`PadPickerCard.gd`) and the
## large mouse panel in an Online player's own lobby (`OnlineCosmeticsPanel.gd`).
##
## The catalog is the phone picker's (`Hat.gd` IDS, `PlayerFace.gd` EYE_IDS, the
## palette `ControllerServer` hands out), and the rules are the phone's too: a
## pick goes through `ControllerServer.set_slot_hat` / `request_color` /
## `set_slot_eyes`, so a colour another claimed slot holds is refused, first come
## first served, whichever input asked. A pad skips such a colour when it cycles;
## the panel greys it out.
##
## Per-seat state is only which row a pad's cursor is on. A pad's picks live in
## its claim for the session (they survive a replug, #442) and are never saved;
## an Online player's are saved in their own copy (`read_pick` / `write_pick`)
## and sent on join (`pick_messages`).
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const HatScript := preload("res://scripts/Hat.gd")
const PlayerFaceScript := preload("res://scripts/PlayerFace.gd")

## The picker's rows, top to bottom: the D-pad moves between them.
const ROWS: PackedStringArray = ["hat", "color", "eyes"]
## Cosmetics change in the lobby only, never between rounds (ADR-0021).
const PICK_PHASES: PackedStringArray = ["lobby", "countdown"]

# --- Catalog and rules (shared by every layout) ---------------------------------

## The options of `row`, in the order every picker shows them. Colours are
## palette indices, `palette_size` of them.
static func options(row: String, palette_size: int = 0) -> Array:
	match row:
		"hat":
			return Array(HatScript.IDS)
		"eyes":
			return PlayerFaceScript.EYE_IDS.duplicate()
		"color":
			return range(maxi(0, palette_size))
	return []

## The option after `current` in `options` going `dir` (+1 or -1), wrapping, and
## skipping any `allowed` refuses. `current` when nothing else is allowed. An
## unknown `current` (an unpicked colour, -1) starts from the front or the back.
static func step(opts: Array, current: Variant, dir: int, allowed: Callable = Callable()) -> Variant:
	var n: int = opts.size()
	if n == 0 or dir == 0:
		return current
	var at: int = opts.find(current)
	if at == -1:
		at = -1 if dir > 0 else n
	for k in range(1, n + 1):
		var candidate: Variant = opts[posmod(at + dir * k, n)]
		if candidate == current:
			return current
		if not allowed.is_valid() or bool(allowed.call(candidate)):
			return candidate
	return current

## The palette indices other slots wear, from a `looks` list as
## `ControllerServer.looks_update_message()` sends it: taken for `own_slot`.
static func taken_colors(looks: Array, own_slot: int) -> Array[int]:
	var out: Array[int] = []
	for entry: Variant in looks:
		if entry is Dictionary and int(entry.get("slot", -1)) != own_slot and int(entry.get("color", -1)) >= 0:
			out.append(int(entry["color"]))
	return out

## `own_slot`'s entry in a `looks` list, or {}.
static func own_look(looks: Array, own_slot: int) -> Dictionary:
	for entry: Variant in looks:
		if entry is Dictionary and int(entry.get("slot", -1)) == own_slot:
			return entry
	return {}

## What a picker writes for option `value` of `row`: the hat's or eyes' name in
## the current locale (`PICKER_HAT_<ID>` / `PICKER_EYES_<ID>`), falling back to
## the English label (colour options are drawn as swatches, so theirs is "").
static func label_of(row: String, value: Variant) -> String:
	var id: String = str(value)
	var english: String
	var key: String
	match row:
		"hat":
			english = str(HatScript.LABELS.get(id, id))
			key = "PICKER_HAT_" + id.to_upper()
		"eyes":
			english = str(PlayerFaceScript.EYE_LABELS.get(id, id))
			key = "PICKER_EYES_" + id.to_upper()
		_:
			return ""
	var shown: String = TranslationServer.translate(key)
	return english if shown == key else shown

# --- A saved pick (Online players' own copy) -------------------------------------

## A pick as {"hat", "eyes", "color"}: unknown ids fall back to bare and round, a
## colour that is not a whole number to -1 (unpicked, the automatic colour).
static func clean_pick(raw: Variant) -> Dictionary:
	var pick: Dictionary = raw if raw is Dictionary else {}
	var hat: String = str(pick.get("hat", HatScript.NONE))
	var eyes: String = str(pick.get("eyes", PlayerFaceScript.EYE_ROUND))
	var color: Variant = pick.get("color", -1)
	return {
		"hat": hat if HatScript.IDS.has(hat) else HatScript.NONE,
		"eyes": eyes if PlayerFaceScript.EYE_IDS.has(eyes) else PlayerFaceScript.EYE_ROUND,
		"color": int(color) if (color is int or color is float) and int(color) >= 0 else -1,
	}

static func read_pick(config: ConfigFile, section: String) -> Dictionary:
	return clean_pick({
		"hat": config.get_value(section, "hat", HatScript.NONE),
		"eyes": config.get_value(section, "eyes", PlayerFaceScript.EYE_ROUND),
		"color": config.get_value(section, "color", -1),
	})

static func write_pick(config: ConfigFile, section: String, pick: Dictionary) -> void:
	var clean: Dictionary = clean_pick(pick)
	for key: String in clean:
		config.set_value(section, key, clean[key])

## The frames a client sends on join to put its saved pick on: the phone's own
## `hat`, `eyes` and `color` frames, so the host applies the phone's rules (a
## colour already taken is refused and the automatic colour stays).
static func pick_messages(pick: Dictionary) -> Array[Dictionary]:
	var clean: Dictionary = clean_pick(pick)
	var out: Array[Dictionary] = [{"t": "hat", "v": clean["hat"]}, {"t": "eyes", "v": clean["eyes"]}]
	if int(clean["color"]) >= 0:
		out.append({"t": "color", "v": int(clean["color"])})
	return out

# --- Per-seat state: a pad's cursor ------------------------------------------------

var _row: Dictionary = {} # slot -> index into ROWS

## The row `slot`'s cursor is on (0 hat, 1 colour, 2 eyes).
func row_of(slot: int) -> int:
	return int(_row.get(slot, 0))

func row_name(slot: int) -> String:
	return ROWS[row_of(slot)]

func move_row(slot: int, dir: int) -> void:
	_row[slot] = clampi(row_of(slot) + dir, 0, ROWS.size() - 1)

func forget(slot: int) -> void:
	_row.erase(slot)
	_stick_dir.erase(slot)
	_stick_wait.erase(slot)

## A pad button on `slot`'s picker: D-pad up and down pick a row, left and right
## change its option (#547: the bumpers are not the picker's any more, so a bumper
## only ever lets the weapon go). True when the button was the picker's.
func pad_button(server: Object, slot: int, button: int) -> bool:
	match button:
		JOY_BUTTON_DPAD_UP:
			move_row(slot, -1)
		JOY_BUTTON_DPAD_DOWN:
			move_row(slot, 1)
		JOY_BUTTON_DPAD_LEFT:
			cycle(server, slot, -1)
		JOY_BUTTON_DPAD_RIGHT:
			cycle(server, slot, 1)
		_:
			return false
	return true

## The left stick does what the D-pad does (a single right Joy-Con has no D-pad):
## past this deflection it counts as a press, then repeats after a delay.
const STICK_THRESHOLD: float = 0.6
const STICK_FIRST_REPEAT_SEC: float = 0.4
const STICK_REPEAT_SEC: float = 0.18

var _stick_dir: Dictionary = {} # slot -> Vector2i of the way the stick is held
var _stick_wait: Dictionary = {} # slot -> seconds until it repeats

## Feeds `slot`'s left stick `axis` for `delta` seconds: a press on the first
## frame past the threshold, along the stick's stronger axis, and again after
## STICK_FIRST_REPEAT_SEC and every STICK_REPEAT_SEC while it is held. Up and
## down move the row, left and right change the value.
func stick(server: Object, slot: int, axis: Vector2, delta: float) -> void:
	var dir := Vector2i.ZERO
	if axis.length() >= STICK_THRESHOLD:
		dir = Vector2i(int(signf(axis.x)), 0) if absf(axis.x) >= absf(axis.y) else Vector2i(0, int(signf(axis.y)))
	if dir == Vector2i.ZERO:
		_stick_dir.erase(slot)
		_stick_wait.erase(slot)
		return
	if _stick_dir.get(slot, Vector2i.ZERO) != dir:
		_stick_dir[slot] = dir
		_stick_wait[slot] = STICK_FIRST_REPEAT_SEC
		_stick_press(server, slot, dir)
		return
	_stick_wait[slot] = float(_stick_wait.get(slot, STICK_REPEAT_SEC)) - delta
	if float(_stick_wait[slot]) <= 0.0:
		_stick_wait[slot] = float(_stick_wait[slot]) + STICK_REPEAT_SEC
		_stick_press(server, slot, dir)

func _stick_press(server: Object, slot: int, dir: Vector2i) -> void:
	if dir.y != 0:
		move_row(slot, dir.y)
	else:
		cycle(server, slot, dir.x)

## Steps `slot`'s current row one option `dir` through the server's own setters,
## the ones a phone's frames reach. A colour cycle skips colours another slot
## wears. False when nothing changed.
func cycle(server: Object, slot: int, dir: int) -> bool:
	match row_name(slot):
		"hat":
			var hat: Variant = step(options("hat"), server.slot_hat(slot), dir)
			return hat != server.slot_hat(slot) and server.set_slot_hat(slot, hat)
		"eyes":
			var eyes: Variant = step(options("eyes"), server.slot_eyes(slot), dir)
			return eyes != server.slot_eyes(slot) and server.set_slot_eyes(slot, eyes)
		"color":
			var current: int = server.slot_color(slot)
			var free: Callable = func(index: Variant) -> bool: return server.color_free(int(index), slot)
			var next: Variant = step(options("color", server.palette_size()), current, dir, free)
			return int(next) != current and server.request_color(slot, int(next))
	return false
