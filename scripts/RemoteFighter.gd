extends Node2D

## A stand-in for a host fighter on the Online joiner (issue #976), carrying
## just what the host's per-fighter overlays read from a `Player`:
## `OffscreenIndicators.gd` (where it is, alive and shown, team), `NameTags.gd`
## (`hat_top()`), `IdleHint.gd` (`input_vector`) and `BoomstickRing.gd`
## (`fire_ready_in()`, `_stats.fire_interval`). `RemoteEffects.gd` keeps one per
## slot at that slot's puppet, so the joiner runs the host's own overlay code.
## Preloaded by path, never by `class_name` (CLAUDE.md).

const HatScript: GDScript = preload("res://scripts/Hat.gd")
const PickupWeaponsScript: GDScript = preload("res://scripts/PickupWeapons.gd")
const GameClockScript: GDScript = preload("res://scripts/GameClock.gd")
## Half the body's side: `Player._body_top()` is minus this.
const BODY_HALF: float = 24.0

## What `BoomstickRing` reads off `Player._stats`.
class FireStats extends RefCounted:
	var fire_interval: float = 0.0

var alive: bool = false
var team: int = -1
## The host's `_slot_name` for this slot, from the snapshot.
var display_name: String = ""
var hat_id: String = "none"
## Never read on the joiner (the host decides the idle hint); here because
## `IdleHint.gd` reads it.
var input_vector: Vector2 = Vector2.ZERO
var _stats: FireStats = FireStats.new()
var _weapon_index: int = -1
## Seconds to the next shot as of `_fire_sync_msec` (`GameClock` time).
var _fire_ready: float = 0.0
var _fire_sync_msec: int = 0

## Like `Player.hat_top()`: from the body's centre to the top of its hat.
func hat_top() -> float:
	return BODY_HALF + HatScript.height_of(hat_id)

## Like `Player.fire_ready_in()`: INF for a weapon that never fires.
func fire_ready_in() -> float:
	if _stats.fire_interval <= 0.0:
		return INF
	var since: float = float(GameClockScript.now_msec() - _fire_sync_msec) / 1000.0
	return maxf(_fire_ready - since, 0.0)

## The host's fire clock (its `fire_clock` event): `interval` 0 for none.
func sync_fire(interval: float, ready_in: float) -> void:
	_stats.fire_interval = maxf(interval, 0.0)
	_fire_ready = ready_in
	_fire_sync_msec = GameClockScript.now_msec()

## The snapshot's weapon index. A new weapon starts its clock afresh, as
## `Player._assign_weapon_stats()` does; the host's next event corrects it.
func set_weapon(index: int) -> void:
	if index == _weapon_index:
		return
	_weapon_index = index
	var interval: float = 0.0
	var path: String = PickupWeaponsScript.PICKAXE_PATH
	if index > 0:
		path = PickupWeaponsScript.WEAPON_PATHS[index - 1] if index <= PickupWeaponsScript.WEAPON_PATHS.size() else ""
	var stats: Resource = load(path) if not path.is_empty() else null
	if stats != null and "fire_interval" in stats:
		interval = float(stats.fire_interval)
	sync_fire(interval, interval)
