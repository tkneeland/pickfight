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

const IDS: PackedStringArray = [KING_OF_THE_HILL, SUDDEN_DEATH, HOT_POTATO, STOCK]

const KingOfTheHillScript := preload("res://scripts/KingOfTheHill.gd")
const SuddenDeathScript := preload("res://scripts/SuddenDeath.gd")
const HotPotatoScript := preload("res://scripts/HotPotato.gd")
const StockScript := preload("res://scripts/Stock.gd")

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
	return null
