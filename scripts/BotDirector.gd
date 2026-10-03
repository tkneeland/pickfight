extends Node

## Owns the bots (issue #152). `ControllerServer` builds one of these as its
## own child, so no scene has to know about it.
##
## A bot is a virtual controller: it holds a roster slot the way a phone does,
## and its `Bot` brain sends input vectors through
## `ControllerServer.push_virtual_input()`, down the same smoothing and
## `Player.set_input_vector()` path a phone's packets take. Nothing else in
## the game can tell a bot from a phone, except the lobby list and the phone
## page, which mark bots.
##
## Two ways in:
##
## - `--bots=N` on the command line (after `--`) adds N bots at start-up, for
##   testing. With no phone joined the bots are all the lobby has and all are
##   ready, so a match starts by itself.
## - The host's bot counter, or the Solo match kind (#445, #522), seats bots
##   (`counter_seated`). Those bots are there for the humans (issue #165): they
##   do not make a ready lobby on their own (RoundManager asks
##   `needs_a_human()`), and once no human seat has been connected for
##   `orphan_grace_sec` they all go, even mid-round (#509). `--bots=N` bots
##   need no human and never go by themselves.
##
## Paused with the rest of the game: `ControllerServer` runs through a pause,
## but it makes this node PAUSABLE, so a bot stops thinking when the host
## phone pauses (issue #165).
##
## Preloaded by path (CLAUDE.md), never referenced by a `class_name`.

const BotScript: GDScript = preload("res://scripts/Bot.gd")
## How many players a solo practice match has, the host included.
const SOLO_PLAYERS: int = 4
const BOTS_FLAG: String = "--bots="

## Extra command-line arguments, read as if they followed `--`. A test seam:
## the scenario runner cannot pass the game its own arguments.
static var extra_args: PackedStringArray = PackedStringArray()

## The `ControllerServer` this director belongs to. Set before `_ready()`.
var server: Node = null
## slot -> the `Bot` driving it.
var bots: Dictionary = {}
## True while the host's bot counter or Solo seated the bots (#505): like Solo
## practice bots they need a human who has readied, not a room of bots alone.
## `--bots=N` bots, the headless playtest, are exempt.
var counter_seated: bool = false
## How long solo bots wait with no phone connected before they all go: long
## enough to ride out a phone that drops and reconnects.
@export var orphan_grace_sec: float = 10.0
var _orphaned_for: float = 0.0
## The match seed the RoundManager last handed over (issue #187), or -1 for
## none yet. Each bot's `rng` is `bot_seed(match_seed, slot)`.
var match_seed: int = -1

## One bot's seed, from the match seed and the slot it drives: two bots in a
## match never share a stream, and the same slot in a replayed match gets the
## same one.
static func bot_seed(seed_value: int, slot: int) -> int:
	return hash([seed_value, "bot", slot])

## A new match on `seed_value` (issue #187): every bot here restarts its
## stream from it, and bots added later in the match are seeded from it too.
func seed_bots(seed_value: int) -> void:
	match_seed = seed_value
	for slot: int in bots:
		(bots[slot] as Node).rng.seed = bot_seed(seed_value, slot)

func _ready() -> void:
	if server == null:
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	args.append_array(extra_args)
	var wanted: int = bots_from_args(args)
	if wanted > 0:
		# Deferred: the players are the server's siblings, and each one has
		# to be ready before a controller binds to it.
		add_bots.call_deferred(wanted)

## Counter bots with no human seat connected for `orphan_grace_sec`: send them
## away, so they do not play match after match to an empty room (issue #165).
func _process(delta: float) -> void:
	if not needs_a_human() or _a_human_is_connected():
		_orphaned_for = 0.0
		return
	_orphaned_for += delta
	if _orphaned_for >= orphan_grace_sec:
		_orphaned_for = 0.0
		remove_bots()

## Whether these bots only play alongside a human: the host's counter or Solo
## seated them, and they are still here.
func needs_a_human() -> bool:
	return counter_seated and not bots.is_empty()

## Whether any human seat (a phone, the host's PC seat, a pad) is connected.
func _a_human_is_connected() -> bool:
	for slot: int in server.claimed_slots():
		if not server.is_virtual(slot) and server.slot_has_controller(slot):
			return true
	return false

## The N in `--bots=N`, or 0 without the flag. Negative or junk reads as 0.
static func bots_from_args(args: PackedStringArray) -> int:
	var wanted: int = 0
	for arg: String in args:
		if arg.begins_with(BOTS_FLAG):
			wanted = maxi(0, arg.trim_prefix(BOTS_FLAG).to_int())
	return wanted

## Add up to `count` bots, as many as there are free slots; returns how many
## were added.
func add_bots(count: int) -> int:
	var added: int = 0
	for i in count:
		var slot: int = server.add_virtual_controller(_free_bot_name())
		if slot == -1:
			break
		var bot: Node = BotScript.new()
		bot.name = "Bot%d" % slot
		bot.player = server.player_in_slot(slot)
		bot.output = func(v: Vector2) -> void: server.push_virtual_input(slot, v)
		if match_seed != -1:
			bot.rng.seed = bot_seed(match_seed, slot)
		add_child(bot)
		bots[slot] = bot
		added += 1
	return added

## "Bot N" with the lowest N no bot here holds, so a name never repeats
## after a bot is kicked (issue #165).
func _free_bot_name() -> String:
	var taken: PackedStringArray = PackedStringArray()
	for slot: int in bots:
		taken.append(server.slot_name(slot))
	var n: int = 1
	while taken.has("Bot %d" % n):
		n += 1
	return "Bot %d" % n

## Send every bot away.
func remove_bots() -> void:
	for slot: int in bots.keys():
		remove_bot(slot)
	counter_seated = false

## Send the bot in `slot` away (the host's kick lands here too). A bot in the
## round leaves it, the way a kicked phone's player does, rather than leaving
## a limp body behind (issue #165).
func remove_bot(slot: int) -> void:
	var bot: Node = bots.get(slot)
	bots.erase(slot)
	if bot != null:
		bot.queue_free()
	var player: Node = server.player_in_slot(slot)
	if player != null and bool(player.get("alive")) and player.has_method("leave_round"):
		player.leave_round()
	server.remove_virtual_controller(slot)
	if bots.is_empty():
		counter_seated = false

func bot_count() -> int:
	return bots.size()
