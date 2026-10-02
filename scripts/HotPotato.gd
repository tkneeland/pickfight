extends Node

## Hot Potato / Tag (issue #278): one player is "it". "It" passes the tag on by
## landing a damaging hit: the player struck becomes "it". Whoever still holds
## it when the fuse runs out is eliminated, and a new "it" is picked from the
## survivors with a fresh fuse, until one player is left.
##
## The mode never touches `RoundManager._scores`. Draws come from a stream
## seeded from the match seed (#187), so a seeded match picks the same "it".
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

## An announcer line for the mode (#370); the Announcer listens for it.
signal callout(sound: StringName)

## Seconds "it" has before the fuse eliminates them.
var fuse_sec: float = 12.0
## After a tag nobody can be tagged for this long, so the new "it" cannot be
## tagged straight back.
var tag_cooldown_sec: float = 1.0

var round_manager: Node
var it_slot: int = -1
## Seconds left on the fuse; counts down only while someone is "it".
var fuse_left: float = 0.0
## slot -> seconds spent as "it" this round (a float, never truncated).
var it_time: Dictionary = {}
var tag_count: int = 0
## slot -> tags that player passed on this round (issue #355).
var tags_passed: Dictionary = {}
var _cooldown_left: float = 0.0
var _active: bool = false
var _rng: RandomNumberGenerator
var _handlers: Dictionary = {}
var _watched: Dictionary = {}

func setup(manager: Node) -> void:
	round_manager = manager

func start_round(slots: Array[int]) -> void:
	end_round()
	if round_manager == null:
		return
	if round_manager.has_method("rng_for"):
		_rng = round_manager.rng_for("hot_potato")
	else:
		_rng = RandomNumberGenerator.new()
		_rng.seed = 278
	it_time.clear()
	tag_count = 0
	tags_passed.clear()
	_cooldown_left = 0.0
	for slot: int in slots:
		if slot < 0 or slot >= round_manager._players.size():
			continue
		var player: Variant = round_manager._players[slot]
		if player == null or not is_instance_valid(player) or not player.has_signal("strike_landed"):
			continue
		var handler: Callable = _on_strike.bind(slot)
		_watched[slot] = player
		_handlers[slot] = handler
		it_time[slot] = 0.0
		player.strike_landed.connect(handler)
	_active = true
	callout.emit(&"announce_hot_potato")
	_pick_it()

func end_round() -> void:
	_active = false
	for slot: int in _handlers.keys():
		var player: Variant = _watched.get(slot)
		var handler: Callable = _handlers[slot]
		if player != null and is_instance_valid(player) and player.strike_landed.is_connected(handler):
			player.strike_landed.disconnect(handler)
	_handlers.clear()
	_watched.clear()
	it_slot = -1
	fuse_left = 0.0

## Hands this round's tags to the match stats (issue #355).
func report_stats(stats: RefCounted) -> void:
	for slot: int in tags_passed:
		stats.record_tags_passed(slot, int(tags_passed[slot]))

func connected_count() -> int:
	return _handlers.size()

func _is_alive(slot: int) -> bool:
	var player: Variant = _watched.get(slot)
	return player != null and is_instance_valid(player) and bool(player.alive)

func _alive_slots() -> Array[int]:
	var slots: Array[int] = []
	var keys: Array = _watched.keys()
	keys.sort()
	for slot: int in keys:
		if _is_alive(slot):
			slots.append(slot)
	return slots

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if it_slot != -1 and not _is_alive(it_slot):
		_pick_it()
	if it_slot == -1:
		_pick_it()
		return
	it_time[it_slot] = float(it_time.get(it_slot, 0.0)) + delta
	fuse_left -= delta
	if fuse_left <= 0.0:
		var loser: int = it_slot
		it_slot = -1
		_watched[loser].eliminate()
		_pick_it()

## `striker_slot` is bound last: `strike_landed` is emitted by the striker.
func _on_strike(victim: Node, amount: float, _point: Vector2, _lethal: bool, striker_slot: int) -> void:
	if not _active or amount <= 0.0 or _cooldown_left > 0.0:
		return
	if striker_slot != it_slot or victim == null or not is_instance_valid(victim):
		return
	for slot: int in _watched.keys():
		if _watched[slot] == victim and slot != it_slot and _is_alive(slot):
			it_slot = slot
			fuse_left = fuse_sec
			_cooldown_left = tag_cooldown_sec
			tag_count += 1
			tags_passed[striker_slot] = int(tags_passed.get(striker_slot, 0)) + 1
			return

## A random live player becomes "it" with a full fuse; nobody with fewer than
## two alive (the round is about to end, or nobody is playing).
func _pick_it() -> void:
	var alive: Array[int] = _alive_slots()
	if alive.size() < 2:
		it_slot = -1
		return
	it_slot = alive[_rng.randi_range(0, alive.size() - 1)]
	fuse_left = fuse_sec
	_cooldown_left = tag_cooldown_sec
