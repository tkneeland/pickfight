extends RefCounted

## The one list of weapons a pickup may hand out (issue #14, ADR-0009), and
## the draw that picks one. Every weapon in the roster except the pickaxe:
## the pickaxe is what everyone already holds, so a pickup of it would change
## nothing (user story 4). Preloaded by path wherever it is used, never
## referenced by `class_name` (CLAUDE.md).

const PICKAXE_PATH: String = "res://resources/pickaxe.tres"
const WEAPON_PATHS: PackedStringArray = [
	"res://resources/staff.tres",
	"res://resources/sword.tres",
	"res://resources/axe.tres",
	"res://resources/dagger.tres",
]

## The roster's pickup-eligible weapons, loaded. A path that does not exist
## is skipped rather than failing the round, so a roster edit that removes a
## weapon file costs that weapon and nothing else.
static func available_weapons() -> Array[Resource]:
	var weapons: Array[Resource] = []
	for path: String in WEAPON_PATHS:
		if ResourceLoader.exists(path):
			weapons.append(load(path))
	return weapons

## One weapon drawn uniformly at random from `candidates`, never the pickaxe
## however it got into the list. Null when nothing eligible is offered, rather
## than inventing a weapon.
static func choose(candidates: Array[Resource]) -> Resource:
	var eligible: Array[Resource] = []
	for stats: Resource in candidates:
		if stats != null and stats.resource_path != PICKAXE_PATH:
			eligible.append(stats)
	if eligible.is_empty():
		return null
	return eligible[randi() % eligible.size()]
