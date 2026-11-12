extends RefCounted

## The host's saved custom stages (#1047, ADR-0026): one stage definition per
## `<dir>/<file>.json`, made in the stage editor or imported by hand (the route
## for builds without the Workshop). Every read and write goes through
## `StageDef`, so a file is only ever built when it passes the same limits the
## Online client applies (#1049).
##
## A stage's key, used by the rotation, the host's toggles and the phone, is its
## file's base name (`HostSettings.name_of()`), exactly as for a built-in stage;
## so a name whose file would match a built-in stage is refused.
##
## A `-s` run (the scenarios) never touches the owner's folder: it uses a folder
## in the OS temp dir, per process. Preload by path; there is no class_name.

const StageDefScript := preload("res://scripts/StageDef.gd")
const StageBuilderScript := preload("res://scripts/StageBuilder.gd")
const SfxScript := preload("res://scripts/Sfx.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")
## Characters a file name cannot hold on some OS, dropped from a stage's key.
const UNSAFE_CHARS: String = "<>:\"/\\|?*."

const STAGES_DIR: String = "user://stages"
const EXTENSION: String = "json"
## Most custom stages listed (and so offered to the rotation).
const MAX_STAGES: int = 64

## Overrides the folder (a scenario's own temp folder); "" uses the default.
static var dir_override: String = ""

## The folder stages are kept in: the owner's `user://stages`, or a per-process
## temp folder in a `-s` run.
static func stages_dir() -> String:
	if dir_override != "":
		return dir_override
	var tree := Engine.get_main_loop() as SceneTree
	if SfxScript.is_script_main_loop(tree):
		return OS.get_temp_dir().path_join("pickfight_headless_stages_%d" % OS.get_process_id())
	return STAGES_DIR

## The file base name a stage called `stage_name` is saved under: the name
## with the characters a file name cannot hold (and control characters and
## '.') dropped, trimmed, so a Japanese or Russian name keeps its letters.
## "" when nothing is left.
static func file_key(stage_name: String) -> String:
	var out: String = ""
	for c in stage_name.strip_edges():
		if c.unicode_at(0) >= 32 and not UNSAFE_CHARS.contains(c):
			out += c
	return out.strip_edges()

## Whether a stage is already saved under `key` (case-insensitively, as on
## Windows and macOS file systems).
static func exists(key: String) -> bool:
	return not saved_key_like(key).is_empty()

## The saved key that names the same file as `key` ignoring case, or "".
static func saved_key_like(key: String) -> String:
	for entry: Dictionary in list():
		if String(entry["key"]).to_lower() == key.to_lower():
			return entry["key"]
	return ""

static func path_of(key: String) -> String:
	return stages_dir().path_join("%s.%s" % [key, EXTENSION])

## Why a stage cannot be saved under `stage_name` ("" when it can):
## nothing usable in the name, or it would share a built-in stage's key.
static func name_problem(stage_name: String, builtin_names: PackedStringArray) -> String:
	var key: String = file_key(stage_name)
	var letters := RegEx.create_from_string("[\\p{L}\\p{N}]")
	if key == "" or letters.search(key) == null:
		return "the name needs a letter or digit"
	for builtin: String in builtin_names:
		if builtin.to_lower() == key.to_lower():
			return "a built-in stage is already called %s" % builtin
	return ""

## Every saved stage, sorted by key: `{"key", "path", "ok", "reason", "def"}`,
## where "def" is the accepted definition in its JSON shape ({} when rejected).
## At most `MAX_STAGES`.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(stages_dir())
	if dir == null:
		return out
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for file: String in files:
		if file.get_extension().to_lower() != EXTENSION:
			continue
		var key: String = file.get_basename()
		var path: String = stages_dir().path_join(file)
		var checked: Dictionary = StageDefScript.validate_text(FileAccess.get_file_as_string(path))
		out.append({"key": key, "path": path, "ok": bool(checked["ok"]), "reason": checked["reason"],
			"def": StageDefScript.to_json_data(checked["def"]) if bool(checked["ok"]) else {}})
		if out.size() >= MAX_STAGES:
			break
	return out

## Saves `data` (a definition in JSON shape). `{"ok", "reason", "key", "path",
## "exists"}`: refused, writing nothing, when it fails `StageDef`, its name is
## unusable or a built-in's, the store is full (`MAX_STAGES`), the folder cannot
## be written, or a stage is already saved under its key and `overwrite` is
## false ("exists" is then true, so the caller can ask before replacing it).
static func save(data: Dictionary, builtin_names: PackedStringArray, overwrite: bool = false) -> Dictionary:
	var checked: Dictionary = StageDefScript.validate(data)
	if not bool(checked["ok"]):
		return _fail(checked["reason"])
	var stage_name: String = checked["def"]["name"]
	var problem: String = name_problem(stage_name, builtin_names)
	if problem != "":
		return _fail(problem)
	var existing: String = saved_key_like(file_key(stage_name))
	if existing != "" and not overwrite:
		var refused: Dictionary = _fail("a stage called %s is already saved" % existing)
		refused["exists"] = true
		refused["key"] = existing
		return refused
	if existing == "" and list().size() >= MAX_STAGES:
		return _fail("the store holds %d stages, the most it keeps" % MAX_STAGES)
	if existing != "" and existing != file_key(stage_name):
		delete_file_only(existing) # the same file in another case: replace it cleanly
	var err: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(stages_dir()))
	if err != OK and err != ERR_ALREADY_EXISTS:
		return _fail("cannot create the stages folder (%s)" % error_string(err))
	var key: String = file_key(stage_name)
	var path: String = path_of(key)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
	file.store_string(JSON.stringify(StageDefScript.to_json_data(checked["def"]), "\t"))
	file.close()
	return {"ok": true, "reason": "", "key": key, "path": path, "exists": false}

## Loads the saved stage `key`: `{"ok", "reason", "def"}`, "def" in JSON shape.
static func load_stage(key: String) -> Dictionary:
	var path: String = path_of(key)
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "no saved stage called %s" % key, "def": {}}
	return read_file(path)

## Reads and checks any `.json` file (an import): `{"ok", "reason", "def"}`.
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "the file does not exist", "def": {}}
	var checked: Dictionary = StageDefScript.validate_text(FileAccess.get_file_as_string(path))
	if not bool(checked["ok"]):
		return {"ok": false, "reason": checked["reason"], "def": {}}
	return {"ok": true, "reason": "", "def": StageDefScript.to_json_data(checked["def"])}

## Imports the file at `path` into the store (checked, then saved under its
## own name). Same result as `save()`, `overwrite` included.
static func import_file(path: String, builtin_names: PackedStringArray, overwrite: bool = false) -> Dictionary:
	var read: Dictionary = read_file(path)
	if not bool(read["ok"]):
		return _fail(read["reason"])
	return save(read["def"], builtin_names, overwrite)

## Writes `data` (checked first) to the outside file `path`, for sharing by
## hand. `{"ok", "reason"}`.
static func export_file(data: Dictionary, path: String) -> Dictionary:
	var checked: Dictionary = StageDefScript.validate(data)
	if not bool(checked["ok"]):
		return {"ok": false, "reason": checked["reason"]}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]}
	file.store_string(JSON.stringify(StageDefScript.to_json_data(checked["def"]), "\t"))
	file.close()
	return {"ok": true, "reason": ""}

## Deletes the saved stage `key`, and forgets it in the host's per-mode
## on-lists (so a new stage of the same name starts off). True when a file was removed.
static func delete(key: String) -> bool:
	if not delete_file_only(key):
		return false
	HostSettingsScript.shared().forget_custom_stage(key)
	return true

## Removes the file for `key` alone, leaving the host's settings as they are.
static func delete_file_only(key: String) -> bool:
	var path: String = path_of(key)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK

## The valid saved stages as PackedScenes for the rotation, each with its
## `resource_path` set to its file so `HostSettings.name_of()` gives its key.
## A stage whose key matches a built-in name (a file dropped in by hand) is left out.
static func scenes(builtin_names: PackedStringArray) -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	for entry: Dictionary in list():
		if not bool(entry["ok"]) or name_problem(entry["key"], builtin_names) != "":
			continue
		var built: Dictionary = StageBuilderScript.build(entry["def"])
		if not bool(built["ok"]):
			continue
		var scene: PackedScene = StageBuilderScript.pack(built["stage"])
		built["stage"].free()
		if scene == null:
			continue
		scene.take_over_path(entry["path"])
		out.append(scene)
	return out

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "key": "", "path": "", "exists": false}
