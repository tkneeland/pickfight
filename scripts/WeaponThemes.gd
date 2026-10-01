extends RefCounted

## Per-stage weapon themes for the pickup pool (issue #310). A stage favours
## the weapons that suit it: the umbrella where wind zones blow, the grapple
## (and plunger) on tall stages, the pogo on flat or bouncy ones. Weighted, not
## exclusive -- every offered weapon keeps at least BASE_COPIES, so any of them
## can still turn up anywhere. Weights are derived from the parts on the stage,
## so no stage is hand-edited; a stage may adjust them with the
## `weapon_weight_overrides` export. Preloaded by path, never by class_name.

const PickupWeaponsScript := preload("res://scripts/PickupWeapons.gd")

## Copies in the bag of a weapon the stage has no opinion about.
const BASE_COPIES: int = 2
## Extra copies per matching theme signal.
const THEME_BONUS: int = 4
## Pickup spots spread at least this far vertically make a tall stage; at most
## FLAT_SPREAD make a flat one.
const TALL_SPREAD: float = 400.0
const FLAT_SPREAD: float = 150.0

## Weapon file stems each theme favours.
const WIND_WEAPONS: PackedStringArray = ["umbrella"]
const TALL_WEAPONS: PackedStringArray = ["grapple", "plunger"]
const FLAT_WEAPONS: PackedStringArray = ["pogo"]

## Copies in the bag for each of `offered` on `stage`: weapon -> int >= 1. The
## pickaxe is left out; a null or empty stage gets the base rate for all.
static func copies_for(stage: Node, offered: Array[Resource]) -> Dictionary:
	var boosts: Dictionary = {}
	if stage != null:
		_add_boost(boosts, WIND_WEAPONS, _count_parts(stage, "WindZone.gd") > 0)
		_add_boost(boosts, TALL_WEAPONS, _vertical_spread(stage) >= TALL_SPREAD)
		_add_boost(boosts, FLAT_WEAPONS, _count_parts(stage, "BouncePad.gd") > 0
			or _is_flat(stage))
	var overrides: Dictionary = {}
	if stage != null and "weapon_weight_overrides" in stage:
		overrides = stage.weapon_weight_overrides
	var copies: Dictionary = {}
	for stats: Resource in offered:
		if stats == null or stats.resource_path == PickupWeaponsScript.PICKAXE_PATH:
			continue
		var stem: String = stats.resource_path.get_file().get_basename()
		var count: int = BASE_COPIES + int(boosts.get(stem, 0))
		if overrides.has(stem):
			count = int(overrides[stem])
		copies[stats] = maxi(1, count)
	return copies

static func _add_boost(boosts: Dictionary, stems: PackedStringArray, active: bool) -> void:
	if not active:
		return
	for stem: String in stems:
		boosts[stem] = int(boosts.get(stem, 0)) + THEME_BONUS

static func _count_parts(node: Node, script_file: String) -> int:
	var found: int = 0
	var script: Script = node.get_script() as Script
	if script != null and script.resource_path.get_file() == script_file:
		found += 1
	for child: Node in node.get_children():
		found += _count_parts(child, script_file)
	return found

static func _pickup_ys(stage: Node) -> Array[float]:
	var ys: Array[float] = []
	for child: Node in stage.get_children():
		if child is Marker2D and child.name.begins_with("PickupSpawn"):
			ys.append((child as Marker2D).position.y)
	return ys

static func _vertical_spread(stage: Node) -> float:
	var ys: Array[float] = _pickup_ys(stage)
	if ys.size() < 2:
		return 0.0
	return ys.max() - ys.min()

static func _is_flat(stage: Node) -> bool:
	var ys: Array[float] = _pickup_ys(stage)
	return ys.size() >= 2 and ys.max() - ys.min() <= FLAT_SPREAD
