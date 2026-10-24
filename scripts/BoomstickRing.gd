extends Node2D

## A ring over a boomstick holder that fills toward its next automatic shot
## (issue #965), so a holder can line up the barrel and a rival can dodge on
## purpose.
##
## Self-contained, in the idle-hint pattern (#826): NameTags.gd builds this as a
## child and calls `tick()` from its own `tick()`. It reads the read-only
## `Player.fire_ready_in()` (#952) and shows only for a living, visible fighter
## whose held weapon fires on its own (`fire_interval > 0`) -- never another
## weapon, a ghost or a KO'd fighter. The ring flashes white for FLASH_SEC as the
## shot fires, skipped with Reduce flashes on (the fill still shows). Host screen
## only; nothing is sent to phones.

const RADIUS: float = 9.0
const WIDTH: float = 4.0
const GAP_ABOVE_TAG: float = 16.0
const FLASH_SEC: float = 0.1
const GameClockScript := preload("res://scripts/GameClock.gd")
const EffectStreamScript := preload("res://scripts/EffectStream.gd")

var _players: Array = []
var _slot_color: Callable
## slot -> fill fraction 0..1 for each ring up this frame.
var _fill: Dictionary = {}
## slot -> centre (world space) of each ring up this frame.
var _centre: Dictionary = {}
## slot -> last `fire_ready_in()` seen, to spot the shot (the clock wrapping).
var _last_ready: Dictionary = {}
## slot -> game msec the white flash ends.
var _flash_until: Dictionary = {}
var _scale: float = 1.0
## Issue #976: the Online joiner's copy, fed by the host's fire-clock events;
## it records nothing.
var mirror: bool = false

func _init(players: Array = [], slot_color: Callable = Callable()) -> void:
	name = "BoomstickRing"
	z_index = 20
	_players = players
	_slot_color = slot_color

## True while a ring is up over `slot`.
func has_ring(slot: int) -> bool:
	return _fill.has(slot)

## The ring's fill over `slot`, 0..1, or -1 with no ring.
func ring_fill(slot: int) -> float:
	return float(_fill.get(slot, -1.0))

## True while `slot`'s ring is in its white shot flash.
func is_flashing(slot: int) -> bool:
	return _flash_until.has(slot) and GameClockScript.now_msec() < int(_flash_until[slot])

## One frame. `anchor` (Callable slot -> Vector2) is the top-centre of that
## slot's name tag in world space; `scale` grows the ring with the tags.
func tick(anchor: Callable, scale_by: float) -> void:
	var had: bool = not _fill.is_empty()
	_fill.clear()
	_centre.clear()
	_scale = scale_by
	var now: int = GameClockScript.now_msec()
	var reduce: bool = _reduce_flash()
	for slot in _players.size():
		var player: Variant = _players[slot]
		if player == null or not is_instance_valid(player) or not player.alive or not player.visible \
				or not player.has_method("fire_ready_in"):
			_last_ready.erase(slot)
			_flash_until.erase(slot)
			continue
		var ready_in: float = player.fire_ready_in()
		if is_inf(ready_in):
			if _last_ready.has(slot) and not mirror:
				EffectStreamScript.record("fire_clock", {"s": slot, "i": 0.0, "r": 0.0}, self) # #976
			_last_ready.erase(slot)
			_flash_until.erase(slot)
			continue
		var stats: Variant = player.get("_stats")
		var interval: float = float(stats.fire_interval) if stats != null else 0.0
		if interval <= 0.0:
			continue
		# The clock wraps back to nearly a full interval as the shot goes off.
		var wrapped: bool = _last_ready.has(slot) and ready_in > float(_last_ready[slot]) + 0.001
		if wrapped and not reduce:
			_flash_until[slot] = now + int(FLASH_SEC * 1000.0)
		# Issue #976: the joiner's clock, set where it starts and at every shot.
		if (wrapped or not _last_ready.has(slot)) and not mirror:
			EffectStreamScript.record("fire_clock", {"s": slot, "i": interval, "r": ready_in}, self)
		_last_ready[slot] = ready_in
		_fill[slot] = clampf(1.0 - ready_in / interval, 0.0, 1.0)
		if anchor.is_valid():
			_centre[slot] = (anchor.call(slot) as Vector2) + Vector2(0.0, -GAP_ABOVE_TAG * scale_by)
	if had or not _fill.is_empty():
		queue_redraw()

func _draw() -> void:
	var now: int = GameClockScript.now_msec()
	for slot: int in _fill.keys():
		if not _centre.has(slot):
			continue
		var c: Vector2 = _centre[slot]
		var r: float = RADIUS * _scale
		var w: float = WIDTH * _scale
		var colour: Color = _slot_color.call(slot) if _slot_color.is_valid() else Color.WHITE
		var flashing: bool = _flash_until.has(slot) and now < int(_flash_until[slot])
		draw_circle(c, r + w * 0.5, Color(0.0784, 0.0941, 0.1137, 0.75))
		draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.25), w * 0.6, true)
		var fill: float = float(_fill[slot])
		if fill > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * fill, 32, Color.WHITE if flashing else colour, w, true)
		if flashing:
			draw_circle(c, r, Color(1, 1, 1, 0.9))

func _reduce_flash() -> bool:
	var sfx: Node = get_node_or_null(^"/root/Sfx")
	return sfx != null and bool(sfx.get("reduce_flash"))
