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
	"res://resources/boomstick.tres",
	"res://resources/grapple.tres",
	"res://resources/flail.tres",
	"res://resources/boomerang.tres",
]

## The weapons as `available_weapons()` first loaded them, held for the
## session. See there for why.
static var _loaded: Array[Resource] = []
static var _loaded_once: bool = false

## The roster's pickup-eligible weapons, loaded. A path that does not exist
## is skipped rather than failing the round, so a roster edit that removes a
## weapon file costs that weapon and nothing else.
##
## Loaded once and held (issue #108). `load()` only returns a cached resource
## while something still holds it, and between rounds nothing holds a weapon
## nobody picked up -- so every pickup spawn re-read all five files from disk,
## measured at 9-10 ms, a dropped frame at every round start and every pickup
## interval. A copy of the list goes out, so a caller cannot edit the cache.
static func available_weapons() -> Array[Resource]:
	if not _loaded_once:
		_loaded_once = true
		for path: String in WEAPON_PATHS:
			if ResourceLoader.exists(path):
				_loaded.append(load(path))
	return _loaded.duplicate()

## One weapon drawn uniformly at random from `candidates`, never the pickaxe
## however it got into the list. Null when nothing eligible is offered, rather
## than inventing a weapon. Draws from `rng` (issue #187: the match seed's
## pickup stream); the global RNG only when none is given.
static func choose(candidates: Array[Resource], rng: RandomNumberGenerator = null) -> Resource:
	var eligible: Array[Resource] = []
	for stats: Resource in candidates:
		if stats != null and stats.resource_path != PICKAXE_PATH:
			eligible.append(stats)
	if eligible.is_empty():
		return null
	var roll: int = rng.randi() if rng != null else randi()
	return eligible[roll % eligible.size()]
