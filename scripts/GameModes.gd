extends RefCounted

## Game modes (issues #276-#278): rules layered onto the endless round loop.
##
## A mode is a node `RoundManager` adds under itself for one round: it is
## given the manager (`setup`), the slots playing the round (`start_round`),
## and told when the round is over (`end_round`), where it must disconnect
## every signal it connected and stop acting. A mode never touches the match
## tally (`RoundManager._scores`): it decides who is eliminated, and the
## normal last-one-standing rule does the scoring.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const KING_OF_THE_HILL: String = "king_of_the_hill"
const SUDDEN_DEATH: String = "sudden_death"
const HOT_POTATO: String = "hot_potato"
const STOCK: String = "stock"
const SOCCER: String = "soccer"
const CAPTURE_THE_FLAG: String = "capture_the_flag"

const IDS: PackedStringArray = [KING_OF_THE_HILL, SUDDEN_DEATH, HOT_POTATO, STOCK, SOCCER, CAPTURE_THE_FLAG]

## Classic is no mode at all: the endless round loop as it always was.
const CLASSIC: String = ""

## Every mode the host can pick (issue #352), in picker order, with all that
## varies per mode in one place: adding a mode is one entry here (plus its
## script in `create()`).
## - name / rule: the picker label, the title card and the how-to-play card;
##   keep the rule to one short line (the card does not wrap).
## - rise: false switches the rising lava off; `rise_grace_factor` scales the
##   grace period before it starts and `rise_speed_factor` its climb speed.
## - banned: `RoundModifiers` ids never rolled in this mode.
## - no_modifiers: optional; true means no modifier is ever rolled (Stock, #375).
## - ffa_only: not playable in the Teams format.
## - teams_only: optional; true means playable only in the Teams format (Soccer, #402).
## - own_stages: optional; true means the mode is dealt only the stages whose
##   `mode_weights` name it (`StageRotation`): elsewhere there is no goal or
##   base, and nothing could end the round (Soccer, Capture the Flag).
const TABLE: Array[Dictionary] = [
	{
		"id": CLASSIC, "name": "Classic", "rule": "Last one standing wins.",
		"rise": true, "rise_grace_factor": 1.0, "rise_speed_factor": 1.0,
		"banned": [], "ffa_only": false,
	},
	{
		"id": KING_OF_THE_HILL, "name": "King of the Hill",
		"rule": "Hold the hill alone to win.",
		"rise": false, "rise_grace_factor": 1.0, "rise_speed_factor": 1.0,
		"banned": ["meteor_shower"], "ffa_only": false,
	},
	{
		"id": HOT_POTATO, "name": "Hot Potato",
		"rule": "Do not hold the tag when the fuse ends.",
		"rise": false, "rise_grace_factor": 1.0, "rise_speed_factor": 1.0,
		"banned": ["weapon_roulette"], "ffa_only": true,
	},
	{
		"id": SUDDEN_DEATH, "name": "Sudden Death",
		"rule": "One hit and you are out.",
		"rise": true, "rise_grace_factor": 0.5, "rise_speed_factor": 1.5,
		"banned": ["double_damage"], "ffa_only": false,
	},
	{
		"id": STOCK, "name": "Stock",
		"rule": "Lose all your lives and you are out.",
		"rise": false, "rise_grace_factor": 1.0, "rise_speed_factor": 1.0,
		"banned": [], "ffa_only": false, "no_modifiers": true,
	},
	{
		"id": SOCCER, "name": "Soccer",
		"rule": "First team to 3 goals wins.",
		"rise": false, "rise_grace_factor": 1.0, "rise_speed_factor": 1.0,
		"banned": ["meteor_shower"], "ffa_only": false, "teams_only": true, "own_stages": true,
	},
	{
		"id": CAPTURE_THE_FLAG, "name": "Capture the Flag",
		"rule": "First team to 2 captures wins.",
		"rise": false, "rise_grace_factor": 1.0, "rise_speed_factor": 1.0,
		"banned": ["meteor_shower"], "ffa_only": false, "teams_only": true, "own_stages": true,
	},
]

## The table row for `id`, or {} for an unknown id.
static func entry(id: String) -> Dictionary:
	for row: Dictionary in TABLE:
		if row["id"] == id:
			return row
	return {}

## Whether `id` is a pickable mode (Classic included).
static func is_valid(id: String) -> bool:
	return not entry(id).is_empty() and DemoBuildScript.mode_in_slice(id)

static func display_name(id: String) -> String:
	return TranslationServer.translate("MODE_%s_NAME" % (id if id != CLASSIC else "classic").to_upper())

static func rule_line(id: String) -> String:
	if not is_valid(id):
		return ""
	return TranslationServer.translate("MODE_%s_RULE" % (id if id != CLASSIC else "classic").to_upper())

## Whether the rising lava runs in `id`.
static func has_rise(id: String) -> bool:
	return bool(entry(id).get("rise", true))

static func rise_grace_factor(id: String) -> float:
	return float(entry(id).get("rise_grace_factor", 1.0))

static func rise_speed_factor(id: String) -> float:
	return float(entry(id).get("rise_speed_factor", 1.0))

static func is_ffa_only(id: String) -> bool:
	return bool(entry(id).get("ffa_only", false))

static func is_teams_only(id: String) -> bool:
	return bool(entry(id).get("teams_only", false))

## Whether `id` plays only on the stages whose `mode_weights` name it.
static func needs_own_stages(id: String) -> bool:
	return bool(entry(id).get("own_stages", false))

## Whether `id` can be played in the format (`teams` true for Teams).
static func fits_format(id: String, teams: bool) -> bool:
	return not (teams and is_ffa_only(id)) and not (not teams and is_teams_only(id))

## Whether `modifier_id` may never be rolled in `id`.
static func bans_modifier(id: String, modifier_id: String) -> bool:
	var row: Dictionary = entry(id)
	return bool(row.get("no_modifiers", false)) or (row.get("banned", []) as Array).has(modifier_id)

## The picker's rows for the host phone: id, name and whether Teams rules it out.
static func picker_rows() -> Array:
	var rows: Array = []
	for row: Dictionary in TABLE:
		if not DemoBuildScript.mode_in_slice(row["id"]):  # the demo's slice (#361)
			continue
		rows.append({"id": row["id"], "name": row["name"], "ffa_only": row["ffa_only"], "teams_only": bool(row.get("teams_only", false))})
	return rows

const DemoBuildScript := preload("res://scripts/DemoBuild.gd")
const KingOfTheHillScript := preload("res://scripts/KingOfTheHill.gd")
const SuddenDeathScript := preload("res://scripts/SuddenDeath.gd")
const HotPotatoScript := preload("res://scripts/HotPotato.gd")
const StockScript := preload("res://scripts/Stock.gd")
const SoccerScript := preload("res://scripts/Soccer.gd")
const CaptureTheFlagScript := preload("res://scripts/CaptureTheFlag.gd")

## A fresh mode node for `id`, or null for "" or an unknown id.
static func create(id: String) -> Node:
	match id:
		KING_OF_THE_HILL:
			return KingOfTheHillScript.new()
		SUDDEN_DEATH:
			return SuddenDeathScript.new()
		HOT_POTATO:
			return HotPotatoScript.new()
		STOCK:
			return StockScript.new()
		SOCCER:
			return SoccerScript.new()
		CAPTURE_THE_FLAG:
			return CaptureTheFlagScript.new()
	return null
