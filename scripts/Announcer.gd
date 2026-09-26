extends Node

## The announcer (issue #152): a voice calling the match on the shared screen.
##
## - "3", "2", "1" as the lobby countdown ticks, and "FIGHT!" as each round
##   starts.
## - The round modifier's name, straight after "FIGHT!".
## - "KO!" when a player is eliminated; "Double KO!" instead when a second
##   goes within `DOUBLE_KO_WINDOW_SEC` of the first.
## - "Winner!" for the round win that takes the match; in the endless session
##   (lobby off, ADR-0004) for every round win.
##
## Built by the `Sfx` autoload beside `SfxHooks`, and wired the same way:
## it watches the tree for nodes carrying the signals it wants (duck typing,
## never `class_name`), so the game never calls it. Every line is a `Sfx`
## sound (the `announce_*` entries, `"voice": true`), so it rides the SFX bus,
## volume and mute like everything else.
##
## Lines never talk over each other: they queue, and each waits for the one
## before to finish.

## A second elimination this soon after the first makes one "Double KO!".
## It is also how long "KO!" waits before it is said.
const DOUBLE_KO_WINDOW_SEC: float = 0.35
## Silence between two queued lines.
const LINE_GAP_SEC: float = 0.08
## Lines left waiting longer than this are dropped as stale: a queue that
## backs up (a flurry of KOs) must not still be talking a round later.
const STALE_SEC: float = 4.0
const META_WATCHED: StringName = &"_announcer_watched"

var sfx: Node

## Every line said, oldest first: what the scenarios check.
var said: PackedStringArray = PackedStringArray()

## Queued lines, as {"sound": StringName, "at": msec queued}.
var _queue: Array[Dictionary] = []
var _busy_until_msec: int = 0
var _pending_kos: int = 0
var _ko_due_msec: int = 0
var _lengths: Dictionary = {}

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_watch_subtree(get_tree().root)

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if _pending_kos > 0 and now >= _ko_due_msec:
		_flush_ko()
	if _queue.is_empty() or now < _busy_until_msec:
		return
	var line: Dictionary = _queue.pop_front()
	if now - int(line["at"]) > int(STALE_SEC * 1000.0):
		return
	var sound: StringName = line["sound"]
	sfx.play(sound)
	said.append(String(sound))
	_busy_until_msec = now + int((_length(sound) + LINE_GAP_SEC) * 1000.0)

## Queue `sound` (an `announce_*` key of `Sfx.SOUNDS`). A KO still waiting
## on its double-KO window is said first, so lines keep their order.
func say(sound: StringName) -> void:
	if _pending_kos > 0:
		_flush_ko()
	_enqueue(sound)

## Drop anything queued or waiting: the scenarios start from quiet.
func clear() -> void:
	_queue.clear()
	_pending_kos = 0
	_busy_until_msec = 0
	said.clear()

## The line for a modifier's on-screen title, "LOW GRAVITY" ->
## `announce_low_gravity`; empty when there is no clip for it.
func modifier_line(title: String) -> StringName:
	var key: String = "announce_" + title.strip_edges().to_lower().replace(" ", "_")
	return StringName(key) if sfx != null and sfx.has_sound(key) else &""

func _enqueue(sound: StringName) -> void:
	_queue.append({"sound": sound, "at": Time.get_ticks_msec()})

func _flush_ko() -> void:
	var sound: StringName = &"announce_double_ko" if _pending_kos >= 2 else &"announce_ko"
	_pending_kos = 0
	_enqueue(sound)

func _length(sound: StringName) -> float:
	if not _lengths.has(sound):
		_lengths[sound] = float(sfx.sound_length(sound)) if sfx.has_method("sound_length") else 1.0
	return _lengths[sound]

# --- Watching the tree ---------------------------------------------------------

func _watch_subtree(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_watch_subtree(child)

func _on_node_added(node: Node) -> void:
	if node.has_meta(META_WATCHED):
		return
	if node.has_signal("strike_landed") and node.has_signal("eliminated"):
		node.connect("eliminated", _on_eliminated)
	elif node.has_signal("round_started") and node.has_signal("round_won"):
		node.connect("round_started", _on_round_started)
		node.connect("round_won", _on_round_won.bind(node))
		if node.has_signal("modifier_announced"):
			node.connect("modifier_announced", _on_modifier_announced)
		if node.has_signal("countdown_ticked"):
			node.connect("countdown_ticked", _on_countdown_ticked)
		if node.has_signal("match_won"):
			node.connect("match_won", _on_match_won)
	else:
		return
	node.set_meta(META_WATCHED, true)

func _on_countdown_ticked(seconds_left: int) -> void:
	if seconds_left >= 1 and seconds_left <= 3:
		say(StringName("announce_%d" % seconds_left))

## "FIGHT!" goes ahead of the modifier's name, which the round manager
## announces a moment before it says the round has started.
func _on_round_started() -> void:
	var at: int = _queue.size()
	for i in _queue.size():
		if modifier_line_is(_queue[i]["sound"]):
			at = i
			break
	_queue.insert(at, {"sound": &"announce_fight", "at": Time.get_ticks_msec()})

## Whether `sound` is one of the modifier names.
func modifier_line_is(sound: StringName) -> bool:
	var key: String = String(sound)
	return key.begins_with("announce_") and not key in [
		"announce_3", "announce_2", "announce_1", "announce_fight",
		"announce_ko", "announce_double_ko", "announce_winner"]

func _on_modifier_announced(title: String) -> void:
	var line: StringName = modifier_line(title)
	if line != &"":
		say(line)

func _on_eliminated() -> void:
	if _pending_kos == 0:
		_ko_due_msec = Time.get_ticks_msec() + int(DOUBLE_KO_WINDOW_SEC * 1000.0)
	_pending_kos += 1

func _on_round_won(_slot: int, round_manager: Node) -> void:
	if not bool(round_manager.get("lobby_enabled")):
		say(&"announce_winner")

func _on_match_won(_slot: int) -> void:
	say(&"announce_winner")
