extends RefCounted

## The hand-off between the stage editor and the game (#1047). The editor is its
## own scene (`scenes/StageEditor.tscn`); the game is `scenes/Main.tscn`. Both
## are swapped with `change_scene_to_file`, so what must survive the swap lives
## here, in static vars:
##
## - `def`: the stage being test-played, in JSON shape (saved or not).
## - `editor_state`: whatever the editor wants back on return (its working
##   definition, file key, view, selection, undo history). Opaque here.
## - `active`: true from `start()` until `return_to_editor()`; Main reads it
##   on start-up and plays an offline Solo round on `def` alone.
##
## Preload by path; there is no class_name.

const StageDefScript := preload("res://scripts/StageDef.gd")

const EDITOR_SCENE: String = "res://scenes/StageEditor.tscn"
const MAIN_SCENE: String = "res://scenes/Main.tscn"

static var def: Dictionary = {}
static var editor_state: Dictionary = {}
static var active: bool = false
## The scene swap, a seam so a scenario can record it instead of leaving.
static var change_scene: Callable = Callable()

## Opens the editor from the title screen, fresh.
static func open_editor(tree: SceneTree) -> void:
	active = false
	def = {}
	editor_state = {}
	_go(tree, EDITOR_SCENE)

## Leaves the editor for the title screen.
static func back_to_title(tree: SceneTree) -> void:
	active = false
	def = {}
	editor_state = {}
	_go(tree, MAIN_SCENE)

## Test-plays `stage` (a definition in JSON shape), keeping `state` for the
## editor's return. Returns "" when the game is starting, else why not (the
## definition fails StageDef), changing nothing.
static func start(tree: SceneTree, stage: Dictionary, state: Dictionary) -> String:
	var checked: Dictionary = StageDefScript.validate(stage)
	if not bool(checked["ok"]):
		return checked["reason"]
	def = StageDefScript.to_json_data(checked["def"])
	editor_state = state
	active = true
	_go(tree, MAIN_SCENE)
	return ""

## The test round is over (Esc or the round's end): back to the editor, which
## takes `editor_state` back.
static func return_to_editor(tree: SceneTree) -> void:
	active = false
	def = {}
	_go(tree, EDITOR_SCENE)

static func _go(tree: SceneTree, path: String) -> void:
	if change_scene.is_valid():
		change_scene.call(path)
	elif tree != null:
		tree.change_scene_to_file.call_deferred(path)
