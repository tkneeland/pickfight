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
## A scenario seam: true makes every write report a failure, as a full disk would.
static var fail_writes_for_test: bool = false
## A scenario seam: true makes recovery's rename back fail, as a locked file would.
static var fail_renames_for_test: bool = false
## What the last recovery could not put back (#1253): one line per stranded
## file kept in place because its rename failed. Empty when all went well.
static var recovery_problems: PackedStringArray = PackedStringArray()
## The stages the last recovery kept as recovered copies (#1255), by key.
static var recovery_notes: PackedStringArray = PackedStringArray()
static var _stray_re: RegEx = null
## A stranded save's file name: `<key>.json.bak` / `.tmp` (numbered `-2`, `-3`
## when taken), or the older `<key>.bak` / `.tmp`. Group 1 is the key, 2 the kind.
const STRAY_PATTERN: String = "(?i)^(.+?)(?:\\.json)?\\.(bak|tmp)(?:-\\d+)?$"

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
	for c in clean_name(stage_name):
		if not UNSAFE_CHARS.contains(c):
			out += c
	return out.strip_edges()

## `stage_name` without invisible characters: control characters, zero-width
## ones (U+200B..U+200F, U+2060..U+206F, U+FEFF) and bidi controls
## (U+202A..U+202E), which could make two names look alike or reorder text.
## Trimmed. Saved stages keep their name in this form.
static func clean_name(stage_name: String) -> String:
	var out: String = ""
	for c in stage_name:
		var u: int = c.unicode_at(0)
		if u < 32 or u == 0x7F or (u >= 0x200B and u <= 0x200F) or (u >= 0x202A and u <= 0x202E) \
				or (u >= 0x2060 and u <= 0x206F) or u == 0xFEFF:
			continue
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
	recovery_problems = PackedStringArray()
	recovery_notes = PackedStringArray()
	var dir := DirAccess.open(stages_dir())
	if dir == null:
		return out
	_recover_stranded()
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

## A save cut short (a crash between `_write_safely()`'s steps) can leave a
## stage as a `.bak` (the old file set aside) or a `.tmp` (the new one not yet
## moved in), named as `STRAY_PATTERN` reads. Strays are taken in sorted order,
## `.bak` before `.tmp` (an old file set aside beats an unfinished new one):
## - a `.tmp` that is not a valid stage is an unfinished write: removed;
## - with no `<key>.json` in place (any letter case), the stray is put back as
##   it. A `.bak` is put back unchecked on purpose: it is the only copy, and an
##   invalid one is then listed with its reason rather than lost;
## - with one in place, a stray holding the same text is a leftover: removed;
## - one holding anything else is never deleted (#1255): it is kept as its own
##   stage, `<name> (recovered)` (numbered when taken), named in `recovery_notes`.
## A stray that cannot be moved is kept where it is and named in
## `recovery_problems` (#1253), so no copy of a stage is ever lost.
static func _recover_stranded() -> void:
	var dir_path: String = stages_dir()
	var files: PackedStringArray = DirAccess.get_files_at(dir_path)
	files.sort()
	var present: Dictionary = {} # lower-case key -> key as saved
	for file: String in files:
		if file.get_extension().to_lower() == EXTENSION:
			present[file.get_basename().to_lower()] = file.get_basename()
	if _stray_re == null:
		_stray_re = RegEx.create_from_string(STRAY_PATTERN)
	for kind: String in ["bak", "tmp"]:
		for file: String in files:
			var m: RegExMatch = _stray_re.search(file)
			if m == null or m.get_string(2).to_lower() != kind:
				continue
			var key: String = m.get_string(1)
			var stray: String = ProjectSettings.globalize_path(dir_path.path_join(file))
			var text: String = FileAccess.get_file_as_string(stray)
			var checked: Dictionary = StageDefScript.validate_text(text)
			if kind == "tmp" and not bool(checked["ok"]):
				DirAccess.remove_absolute(stray) # an unfinished write that is not a stage
				continue
			if not present.has(key.to_lower()):
				var err: Error = _rename(stray, ProjectSettings.globalize_path(path_of(key)))
				if err == OK:
					present[key.to_lower()] = key
				else:
					_keep_problem(file, err)
				continue
			if text == FileAccess.get_file_as_string(path_of(present[key.to_lower()])):
				DirAccess.remove_absolute(stray) # the same stage is in place: a leftover
				continue
			var recovered: String = _recovered_key(key, present)
			var moved: Error
			if bool(checked["ok"]):
				# Renamed inside too, so opening and saving it never lands back on `key`.
				var def: Dictionary = StageDefScript.to_json_data(checked["def"])
				def["name"] = recovered
				moved = OK if _write_safely(path_of(recovered), JSON.stringify(def, "\t"), "") == "" else ERR_CANT_CREATE
				if moved == OK:
					DirAccess.remove_absolute(stray)
			else:
				moved = _rename(stray, ProjectSettings.globalize_path(path_of(recovered)))
			if moved == OK:
				present[recovered.to_lower()] = recovered
				recovery_notes.append(recovered)
			else:
				_keep_problem(file, moved)

static func _rename(from: String, to: String) -> Error:
	return ERR_CANT_CREATE if fail_renames_for_test else DirAccess.rename_absolute(from, to)

static func _keep_problem(file: String, err: Error) -> void:
	recovery_problems.append("%s (%s)" % [file, error_string(err)])
	push_warning("CustomStages: could not restore %s: %s; it is kept" % [file, error_string(err)])

## A free key for a recovered copy of `key`: "<key> (recovered)", then
## "(recovered 2)", ..., the base cut so the name fits `MAX_NAME_LENGTH`.
static func _recovered_key(key: String, present: Dictionary) -> String:
	var n: int = 1
	while true:
		var suffix: String = " (recovered)" if n == 1 else " (recovered %d)" % n
		var base: String = key.left(StageDefScript.MAX_NAME_LENGTH - suffix.length()).strip_edges()
		var candidate: String = base + suffix
		if not present.has(candidate.to_lower()):
			return candidate
		n += 1
	return key

## The name of a file beside `g_path` for `kind` ("tmp" or "bak"):
## `<g_path>.<kind>`, or numbered `-2`, `-3`, ... while that name is taken, so a
## safe write never touches a file it did not create (#1253).
static func _free_sibling(g_path: String, kind: String) -> String:
	var candidate: String = "%s.%s" % [g_path, kind]
	var n: int = 2
	while FileAccess.file_exists(candidate):
		candidate = "%s.%s-%d" % [g_path, kind, n]
		n += 1
	return candidate

## Writes `text` to `path` so that a failure never costs what was there: it goes
## to a free `<path>.tmp` beside it first and is read back after closing (which
## also catches errors that only show at close), then the old file at `old`
## (`path` itself, the same file in another letter case, or "" for none) is set
## aside as a free `<old>.bak`, the temp file is moved in, and only then is the
## `.bak` removed. Both names are new files (`_free_sibling()`), so siblings it did
## not create are never touched, and a target itself named `.bak` or `.tmp` works.
## On any failure the old file is put back and the temp file removed. "" when
## done, else the reason. Paths are `user://` or absolute.
static func _write_safely(path: String, text: String, old: String) -> String:
	var g_path: String = ProjectSettings.globalize_path(path)
	var g_tmp: String = _free_sibling(g_path, "tmp")
	var file := FileAccess.open(g_tmp, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	file.store_string(text)
	file.close()
	if fail_writes_for_test or FileAccess.get_file_as_string(g_tmp) != text:
		DirAccess.remove_absolute(g_tmp)
		return "cannot write %s (%s)" % [path, error_string(ERR_FILE_CANT_WRITE)]
	var aside: String = ""
	if old != "" and FileAccess.file_exists(old):
		var g_old: String = ProjectSettings.globalize_path(old)
		aside = _free_sibling(g_old, "bak")
		if DirAccess.rename_absolute(g_old, aside) != OK:
			DirAccess.remove_absolute(g_tmp)
			return "cannot replace %s" % old
	var err: Error = DirAccess.rename_absolute(g_tmp, g_path)
	if err != OK:
		DirAccess.remove_absolute(g_tmp)
		if aside != "":
			DirAccess.rename_absolute(aside, ProjectSettings.globalize_path(old))
		return "cannot write %s (%s)" % [path, error_string(err)]
	if aside != "":
		DirAccess.remove_absolute(aside)
	return ""

## Saves `data` (a definition in JSON shape). `{"ok", "reason", "key", "path",
## "exists"}`: refused, writing nothing, when it fails `StageDef`, its name is
## unusable or a built-in's, the store is full (`MAX_STAGES`), the folder cannot
## be written, or a stage is already saved under its key and `overwrite` is
## false ("exists" is then true, so the caller can ask before replacing it).
static func save(data: Dictionary, builtin_names: PackedStringArray, overwrite: bool = false) -> Dictionary:
	var checked: Dictionary = StageDefScript.validate(data)
	if not bool(checked["ok"]):
		return _fail(checked["reason"])
	var stage_name: String = clean_name(checked["def"]["name"])
	checked["def"]["name"] = stage_name
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
	var err: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(stages_dir()))
	if err != OK and err != ERR_ALREADY_EXISTS:
		return _fail("cannot create the stages folder (%s)" % error_string(err))
	var key: String = file_key(stage_name)
	var path: String = path_of(key)
	var text: String = JSON.stringify(StageDefScript.to_json_data(checked["def"]), "\t")
	var written: String = _write_safely(path, text, path_of(existing) if existing != "" else "")
	if written != "":
		return _fail(written)
	if existing != "" and existing != key:
		HostSettingsScript.shared().rename_custom_stage(existing, key) # a case-only rename keeps its switches
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
## hand, safely (`_write_safely()`): a failed export keeps any file already
## there. `{"ok", "reason"}`.
static func export_file(data: Dictionary, path: String) -> Dictionary:
	var checked: Dictionary = StageDefScript.validate(data)
	if not bool(checked["ok"]):
		return {"ok": false, "reason": checked["reason"]}
	var text: String = JSON.stringify(StageDefScript.to_json_data(checked["def"]), "\t")
	var written: String = _write_safely(path, text, path)
	return {"ok": written == "", "reason": written}

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
