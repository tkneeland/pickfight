extends CanvasLayer

## MATCH POINT on the host screen (issue #825). When a round starts and a
## fighter (or, in Teams, a team) needs exactly one more round win to take the
## match, a "MATCH POINT: <name>" plate shows under the stage title card for
## `LIFETIME_SEC` in that fighter's colour on an ink plate (the #548 HUD look),
## and the leader's name tag keeps a small gold dot until the round ends. Two
## on match point show two plates stacked.
##
## Self-contained: `Announcer.gd`'s round-manager watch calls `show_for()` as
## each round starts; `RoundManager.gd` and `Player.gd` are not touched. It
## reads only `match_target()`, `score_of()`, `team_score()` and friends,
## duck-typed. Host screen only: no remote-client banner path exists for it.
## Preloaded by path (CLAUDE.md), never referenced by a `class_name`.

const UiThemeScript := preload("res://scripts/UiTheme.gd")
const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const TeamsScript := preload("res://scripts/Teams.gd")

const GROUP: StringName = &"match_point_plates"
const DOT_GROUP: StringName = &"match_point_dots"
const LIFETIME_SEC: float = 2.5
const FADE_SEC: float = 0.3
const FONT_SIZE: int = 26 # at least the 16 px Deck floor (D7/D10)
## Above the stage title card's layer (10).
const PLATE_LAYER: int = 11
## Under the title and its rule line (see `RoundCards.show_stage_title`).
const TOP_FRAC: float = 0.36
const FIRST_PLATE_DROP: float = 170.0
const PLATE_STEP: float = 58.0
const MAX_PLATES: int = 4
## Classic (""), King of the Hill, Sudden Death, Soccer and Capture the Flag.
## Stock is one round, so it has no match point.
const MODES: PackedStringArray = ["", "king_of_the_hill", "sudden_death", "soccer", "capture_the_flag"]

## The lines shown, as {"text": String, "color": Color, "slot": int}: what the scenarios read.
var lines: Array[Dictionary] = []

## Who is on match point in `rm`'s round that just started. Empty when nobody
## is, or when the match has no scoring target (endless Solo practice).
static func leaders(rm: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not bool(rm.get("lobby_enabled")) or not MODES.has(str(rm.get("game_mode"))):
		return out
	var want: int = int(rm.match_target()) - 1
	if want < 0:
		return out
	if rm.team_mode():
		for team: int in TeamsScript.COUNT:
			if rm.team_score(team) == want:
				out.append({"text": TeamsScript.team_name(team), "color": TeamsScript.team_color(team), "slot": -1})
		return out
	var in_round: Array = rm.get("_in_round")
	for slot: int in in_round:
		if rm.score_of(slot) == want:
			out.append({"text": str(rm._slot_name(slot)), "color": rm._slot_color(slot), "slot": slot})
	return out

## Shows the plates and dots for the round `rm` has just started. Returns the
## plate layer, or null when nobody is on match point.
static func show_for(rm: Node) -> Node:
	var found: Array[Dictionary] = leaders(rm)
	if found.is_empty() or not rm.is_inside_tree():
		return null
	for old: Node in rm.get_tree().get_nodes_in_group(GROUP):
		old.remove_from_group(GROUP)
		old.queue_free()
	for old_dot: Node in rm.get_tree().get_nodes_in_group(DOT_GROUP):
		old_dot.queue_free()
	var layer: CanvasLayer = (load("res://scripts/MatchPointPlate.gd") as GDScript).new() as CanvasLayer
	for entry: Dictionary in found.slice(0, MAX_PLATES):
		layer.lines.append(entry)
	rm.add_child(layer)
	var round_number: int = int(rm.get("_round_number"))
	for entry: Dictionary in found:
		var tag: Label = rm.name_tag(int(entry["slot"])) if int(entry["slot"]) >= 0 else null
		if tag == null:
			continue
		var dot := Control.new()
		dot.set_script(load("res://scripts/MatchPointDot.gd"))
		dot.set("round_manager", rm)
		dot.set("round_number", round_number)
		tag.add_child(dot)
	return layer

func _ready() -> void:
	add_to_group(GROUP)
	name = "MatchPointPlates"
	layer = PLATE_LAYER
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var root := Control.new()
	root.name = "Plates"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var y: float = screen.y * TOP_FRAC + FIRST_PLATE_DROP
	for entry: Dictionary in lines:
		var label: Label = ScreenKitScript.ink_label(
			TranslationServer.translate("MATCH_POINT") % str(entry["text"]), FONT_SIZE, entry["color"], 0)
		var plate := PanelContainer.new()
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_theme_stylebox_override("panel", UiThemeScript.plate(UiThemeScript.INK, 20, 6, true, 14))
		plate.add_child(label)
		root.add_child(plate)
		var size: Vector2 = plate.get_combined_minimum_size()
		plate.size = size
		plate.position = Vector2((screen.x - size.x) * 0.5, y)
		y += PLATE_STEP
	var tween: Tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(root, "modulate:a", 0.0, FADE_SEC).set_delay(LIFETIME_SEC - FADE_SEC)
	tween.tween_callback(queue_free)
