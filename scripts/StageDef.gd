extends RefCounted

## Stage definition: a versioned JSON description of a stage, validated before
## anything is built from it (#1045, ADR-0026). Never a .tscn, since a scene can
## embed code. Preload by path; there is no class_name.
##
## `validate_text(json)` / `validate(data)` return {"ok": bool, "reason": String,
## "def": Dictionary}. A rejection carries exactly one human-readable reason (the
## first problem found); an accepted definition returns itself normalised in "def".
##
## Shape (schema 1):
##   {"schema": 1, "name": "Ledges",
##    "parts": [{"type": "Platform", "pos": [0, 0], "size": [240, 24], "params": {"one_way": false}},
##              {"type": "KillFloor", "pos": [0, 900]}],
##    "spawns": [[-300, -40], ...],       # at least MIN_SPAWNS points
##    "modes": ["stock"]}                # optional mode tags, from GameModes.IDS

const GameModesScript := preload("res://scripts/GameModes.gd")

const SCHEMA_VERSION: int = 1
const MAX_NAME_LENGTH: int = 40
const MAX_PARTS: int = 64
const MIN_SPAWNS: int = 8
const MAX_SPAWNS: int = 16
## Every position (parts and spawns) must lie inside +/- BOUNDS_X, +/- BOUNDS_Y.
const BOUNDS_X: float = 4000.0
const BOUNDS_Y: float = 3000.0
const MIN_PART_SIDE: float = 8.0
const MAX_PART_WIDTH: float = 2000.0
const MAX_PART_HEIGHT: float = 1000.0

## The whitelist: whether the part is sized, and its allowed params with their
## JSON types. The rest of the catalogue is decided later.
const CATALOGUE: Dictionary = {
	"Platform": {"sized": true, "params": {"one_way": "bool"}},
	"KillFloor": {"sized": false, "params": {}},
}
const KILL_FLOOR: String = "KillFloor"

static func validate_text(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _reject("malformed JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
	return validate(json.data)

static func validate(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return _reject("the definition must be a JSON object")
	var d: Dictionary = data
	if not d.has("schema") or not _is_int(d["schema"]) or int(d["schema"]) != SCHEMA_VERSION:
		return _reject("unsupported schema version (expected %d)" % SCHEMA_VERSION)
	if typeof(d.get("name")) != TYPE_STRING or String(d["name"]).strip_edges() == "":
		return _reject("name must be a non-empty string")
	if String(d["name"]).length() > MAX_NAME_LENGTH:
		return _reject("name is longer than %d characters" % MAX_NAME_LENGTH)
	if typeof(d.get("parts")) != TYPE_ARRAY:
		return _reject("parts must be an array")
	var parts: Array = d["parts"]
	if parts.size() > MAX_PARTS:
		return _reject("too many parts (%d, the cap is %d)" % [parts.size(), MAX_PARTS])
	var kill_floors: int = 0
	var clean_parts: Array = []
	for i in parts.size():
		var res: Dictionary = _check_part(parts[i], i)
		if res.has("reason"):
			return _reject(res["reason"])
		if res["part"]["type"] == KILL_FLOOR:
			kill_floors += 1
		clean_parts.append(res["part"])
	if kill_floors == 0:
		return _reject("no KillFloor part (every stage needs one)")
	if kill_floors > 1:
		return _reject("more than one KillFloor part")
	if typeof(d.get("spawns")) != TYPE_ARRAY:
		return _reject("spawns must be an array")
	var spawns: Array = d["spawns"]
	if spawns.size() < MIN_SPAWNS:
		return _reject("too few spawns (%d, at least %d needed)" % [spawns.size(), MIN_SPAWNS])
	if spawns.size() > MAX_SPAWNS:
		return _reject("too many spawns (%d, the cap is %d)" % [spawns.size(), MAX_SPAWNS])
	var clean_spawns: Array = []
	for i in spawns.size():
		var p: Variant = _vec(spawns[i])
		if p == null:
			return _reject("spawn %d must be [x, y] numbers" % i)
		if not _in_bounds(p):
			return _reject("spawn %d is out of bounds" % i)
		clean_spawns.append(p)
	var modes: Array = []
	if d.has("modes"):
		if typeof(d["modes"]) != TYPE_ARRAY:
			return _reject("modes must be an array of mode ids")
		for m in d["modes"]:
			if typeof(m) != TYPE_STRING or not GameModesScript.IDS.has(m):
				return _reject("unknown mode tag '%s'" % str(m))
			if not modes.has(m):
				modes.append(m)
	return {"ok": true, "reason": "", "def": {
		"schema": SCHEMA_VERSION, "name": String(d["name"]), "parts": clean_parts,
		"spawns": clean_spawns, "modes": modes}}

static func _check_part(raw: Variant, i: int) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {"reason": "part %d must be an object" % i}
	var p: Dictionary = raw
	var type: Variant = p.get("type")
	if typeof(type) != TYPE_STRING or not CATALOGUE.has(type):
		return {"reason": "part %d has unknown type '%s'" % [i, str(type)]}
	var spec: Dictionary = CATALOGUE[type]
	var pos: Variant = _vec(p.get("pos"))
	if pos == null:
		return {"reason": "part %d (%s) needs pos [x, y] numbers" % [i, type]}
	if not _in_bounds(pos):
		return {"reason": "part %d (%s) is out of bounds" % [i, type]}
	var clean: Dictionary = {"type": type, "pos": pos}
	if spec["sized"]:
		var size: Variant = _vec(p.get("size"))
		if size == null:
			return {"reason": "part %d (%s) needs size [w, h] numbers" % [i, type]}
		if size.x < MIN_PART_SIDE or size.y < MIN_PART_SIDE:
			return {"reason": "part %d (%s) is smaller than %d px on a side" % [i, type, int(MIN_PART_SIDE)]}
		if size.x > MAX_PART_WIDTH or size.y > MAX_PART_HEIGHT:
			return {"reason": "part %d (%s) is oversize (max %dx%d)" % [i, type, int(MAX_PART_WIDTH), int(MAX_PART_HEIGHT)]}
		# The whole box, not just its centre, must stay inside the bounds.
		if absf(pos.x) + size.x * 0.5 > BOUNDS_X or absf(pos.y) + size.y * 0.5 > BOUNDS_Y:
			return {"reason": "part %d (%s) reaches out of bounds" % [i, type]}
		clean["size"] = size
	elif p.has("size"):
		return {"reason": "part %d (%s) takes no size" % [i, type]}
	var params: Variant = p.get("params", {})
	if typeof(params) != TYPE_DICTIONARY:
		return {"reason": "part %d (%s) params must be an object" % [i, type]}
	var allowed: Dictionary = spec["params"]
	var clean_params: Dictionary = {}
	for k in params:
		if not allowed.has(k):
			return {"reason": "part %d (%s) has unknown param '%s'" % [i, type, str(k)]}
		if allowed[k] == "bool" and typeof(params[k]) != TYPE_BOOL:
			return {"reason": "part %d (%s) param '%s' must be true or false" % [i, type, str(k)]}
		clean_params[k] = params[k]
	clean["params"] = clean_params
	for k in p:
		if not ["type", "pos", "size", "params"].has(k):
			return {"reason": "part %d (%s) has unknown field '%s'" % [i, type, str(k)]}
	return {"part": clean}

static func _vec(v: Variant) -> Variant:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 2:
		return null
	var a: Array = v
	for n in a:
		if (typeof(n) != TYPE_FLOAT and typeof(n) != TYPE_INT) or is_nan(float(n)) or is_inf(float(n)):
			return null
	return Vector2(float(a[0]), float(a[1]))

static func _in_bounds(p: Vector2) -> bool:
	return absf(p.x) <= BOUNDS_X and absf(p.y) <= BOUNDS_Y

static func _is_int(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT) or (typeof(v) == TYPE_FLOAT and float(v) == floorf(float(v)))

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "def": {}}
