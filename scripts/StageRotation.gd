extends RefCounted

## Which stage plays next (ADR-0011, issues #144 and #163): pure bookkeeping
## over indices into `scenes`, split out of RoundManager (#175). RoundManager
## instances the stage this picks, frames the camera on it and hands out its
## spawns; this only deals.
##
## `scenes[0]` opens every match (RoundManager puts `stage_index` back to
## -1 for each, #200), then shuffled bags cover the rest with no
## stage playing twice in a row. A large stage (`Stage.view_size` bigger than
## the normal view) is only dealt to a round of `large_stage_min_players` or
## more, and a bag is re-dealt the moment the player count crosses that line.
##
## RoundManager keeps `scenes` and `large_stage_min_players` in step with its
## own exports of the same meaning.

const StageScript := preload("res://scripts/Stage.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")

## Which stages the host switched off (#294); a scenario hands in its own.
var settings: RefCounted = HostSettingsScript.shared()
## The rotation: RoundManager's `stage_scenes` (the same array). Setting it
## tells `settings` which stages exist.
var scenes: Array[PackedScene] = []:
	set(value):
		scenes = value
		var names := PackedStringArray()
		for scene: PackedScene in value:
			names.append(HostSettingsScript.name_of(scene.resource_path))
		settings.known_stages = names
## Fewest players a round needs before a large stage may be dealt to it.
var large_stage_min_players: int = 5
## `--demo`: play the rotation straight through in order, no bags.
var demo: bool = false
## Seeded by RoundManager from `rotation_seed`; never the global RNG, so two
## rotations given the same seed produce the same sequence (ADR-0011) --
## `Array.shuffle()` can't do that, since it always draws from the global RNG.
var rng: RandomNumberGenerator
## The `GameModes` id the round being started plays under ("" for classic);
## a stage's `mode_weights` for it say how often it is dealt (#373).
var mode_id: String = ""
## What `mode_id` was when `bag` was dealt: a mode change re-deals the bag.
var _bag_mode: String = ""
## The index into `scenes` last played. Starts at -1 so the first
## `next_stage_index()` call is recognized as the opener rather than the seam
## between two bags. The caller stores each pick here.
var stage_index: int = -1
## Remaining stage indices for the current bag, next-to-play at the front
## (`pop_front()`). Refilled by `_refill_bag()` once emptied.
var bag: Array[int] = []
## How many players the round being started has; read by `stage_allowed()`.
var round_player_count: int = 0
## What `_large_stages_eligible()` said when `bag` was dealt (#163).
var _bag_large_eligible: bool = false
## `Stage.view_size_of()` per stage scene, so a scene's state is read once.
var _large_stage_cache: Dictionary = {}

## Throws away what is left of the bag, so the next deal starts a fresh one
## for its own player count (a new match, #163).
func new_bag() -> void:
	bag.clear()

## Whether `scenes[index]` is a large stage.
func stage_is_large(index: int) -> bool:
	var scene: PackedScene = scenes[index]
	if not _large_stage_cache.has(scene):
		_large_stage_cache[scene] = StageScript.is_large_view(StageScript.view_size_of(scene))
	return _large_stage_cache[scene]

## Whether the round being started may play `scenes[index]`: any normal
## stage, and a large one only with `large_stage_min_players` or more. A
## rotation with no stage the round may play (say, only large stages and two
## players) ignores the rule rather than play nothing.
func stage_allowed(index: int) -> bool:
	if not _stage_enabled(index):
		return false
	if round_player_count >= large_stage_min_players or not stage_is_large(index):
		return true
	for i in scenes.size():
		if not stage_is_large(i):
			return false
	return true

## Whether the host left `scenes[index]` switched on (#294). A rotation with
## every stage off (the settings refuse that) ignores the switches.
func _stage_enabled(index: int) -> bool:
	if settings.is_stage_enabled(HostSettingsScript.name_of(scenes[index].resource_path)):
		return true
	for scene: PackedScene in scenes:
		if settings.is_stage_enabled(HostSettingsScript.name_of(scene.resource_path)):
			return false
	return true

## Picks the next stage index (ADR-0011): `scenes[0]` opens every match
## (`stage_index` still at -1), then shuffled bags cover the whole roster,
## refilling once the current bag is empty. `stage_index` still holds the
## previously-played index at this point, so it doubles as the "just played"
## value the fresh bag must not start with.
##
## Issue #144: only stages `stage_allowed()` for this round's player count are
## played. A bag is dealt from the stages allowed when it is filled, and
## re-dealt the moment the count crosses `large_stage_min_players` either way
## (#163): a bag dealt for three would otherwise hold no large stage for
## however many rounds of seven it had left. A new match deals afresh too
## (`new_bag()`).
func next_stage_index() -> int:
	if demo:
		var next: int = stage_index
		for _i in scenes.size():
			next = (next + 1) % scenes.size()
			if stage_allowed(next):
				break
		return next
	if stage_index == -1:
		for i in scenes.size():
			if stage_allowed(i):
				return i
		return 0
	if _bag_large_eligible != _large_stages_eligible() and _rotation_has_large_stage():
		bag.clear()
	if _bag_mode != mode_id:
		bag.clear()
	# A fresh bag always holds an allowed stage, so this ends within one bag's
	# worth of skips and one refill.
	var index: int = 0
	for _attempt in 2 * scenes.size() + 1:
		if bag.is_empty():
			_refill_bag(stage_index)
		index = bag.pop_front()
		if stage_allowed(index):
			break
	return index

## Builds a fresh shuffled bag (one Fisher-Yates pass over `rng`, never the
## global RNG or `Array.shuffle()`, which draws from it) covering every index
## into `scenes`, then fixes up a bag that would repeat `avoid` back to
## back by swapping its first entry with another position -- every index
## plays exactly once regardless of where in the bag it lands, so this cannot
## skip or duplicate a stage. Left alone when the roster has only one stage,
## since no swap can avoid a repeat there (the opener's own repeat case).
func _refill_bag(avoid: int) -> void:
	# Shuffled first and filtered after, so a rotation with no large stages
	# draws exactly the order it drew before issue #144.
	bag = []
	_bag_large_eligible = _large_stages_eligible()
	_bag_mode = mode_id
	var rare_dropped: Array[int] = []
	for index: int in _shuffled_indices():
		if not stage_allowed(index):
			continue
		# A stage weighing under 1 is dealt into the bag with that probability
		# (#373); a weight of 1 or more draws nothing.
		var weight: float = StageScript.mode_weight_of(scenes[index], mode_id)
		if weight < 1.0 and rng.randf() >= weight:
			rare_dropped.append(index)
			continue
		bag.append(index)
	if bag.is_empty():
		bag.assign(rare_dropped)
	_add_weighted_copies()
	if bag.size() > 1 and bag[0] == avoid:
		var swap_with: int = 1 + rng.randi() % (bag.size() - 1)
		var tmp: int = bag[0]
		bag[0] = bag[swap_with]
		bag[swap_with] = tmp

## Stages favoured by this mode (#373; a rarer one is thinned in `_refill_bag`): a stage whose `mode_weights` entry for
## `mode_id` rounds to n > 1 is dealt n times per bag instead of once. The
## extras go in at positions drawn from `rng`, never next to the same stage.
## Nothing is drawn when no allowed stage is favoured, so every other mode's
## sequence is exactly what it was.
func _add_weighted_copies() -> void:
	var extras: Array[int] = []
	for index: int in bag.duplicate():
		var copies: int = roundi(StageScript.mode_weight_of(scenes[index], mode_id))
		for _c in range(1, copies):
			extras.append(index)
	for index: int in extras:
		var candidates: Array[int] = []
		for pos in bag.size() + 1:
			var before: int = bag[pos - 1] if pos > 0 else -1
			var after: int = bag[pos] if pos < bag.size() else -1
			if before != index and after != index:
				candidates.append(pos)
		if candidates.is_empty():
			candidates.append(bag.size())
		bag.insert(candidates[rng.randi() % candidates.size()], index)

## Whether this round's player count may play large stages (issue #144).
func _large_stages_eligible() -> bool:
	return round_player_count >= large_stage_min_players

## Whether any stage in the rotation is large. Without one the player count
## never changes a bag, so it is never re-dealt for it.
func _rotation_has_large_stage() -> bool:
	for i in scenes.size():
		if stage_is_large(i):
			return true
	return false

## A Fisher-Yates shuffle of `range(scenes.size())` over `rng`.
func _shuffled_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in scenes.size():
		indices.append(i)
	for i in range(indices.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = indices[i]
		indices[i] = indices[j]
		indices[j] = tmp
	return indices
