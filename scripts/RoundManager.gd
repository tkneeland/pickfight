extends Node

## Round/session loop (ADR-0004), built on top of `ControllerServer`'s roster
## (ADR-0007). The session itself is endless -- this node just keeps starting
## a new elimination round each time the current one is down to one player
## standing, for as long as enough of the roster is present to play.
##
## "The roster" means claimed slots (`ControllerServer.claimed_slots()`):
## someone whose controller drops mid-round keeps their slot for the rest of
## that round -- their `Player` just sits wherever the last input left it,
## drifting to rest, exactly as an unplugged controller always has -- and is
## only dropped from the roster between rounds, when
## `expire_disconnected_claims()` runs.

@export var player_paths: Array[NodePath] = []
## Stages to rotate through: `stage_scenes[0]` opens every session, then
## shuffled bags cover the rest with no repeat back-to-back (ADR-0011).
## Swapped once per round, in `_swap_stage()`. Spawn points come from the
## active stage's `get_spawn_points()`, not from an export here.
@export var stage_scenes: Array[PackedScene] = []
## Node the active stage instance is added to and removed from.
@export var arena_container_path: NodePath
@export var controller_server_path: NodePath
@export var score_label_path: NodePath
## Shown while waiting on roster size, since a WAITING round leaves every
## Player invisible (Player._ready()) -- without this the shared screen looks
## broken (blank arena, no players) instead of "needs one more phone".
@export var waiting_label_path: NodePath
## Shown for round_end_pause_sec once a round resolves. Without this, the
## winner is put through leave_round() the same tick the loser is put through
## eliminate() -- both go inert via the same _go_inert(), so every player
## vanishes at once and the shared screen shows nothing happened. Holds one
## icon+score entry per player slot (see scenes/Main.tscn), refreshed from
## each Player's identity_color and this node's own _scores.
@export var scoreboard_path: NodePath
## A round will not start with fewer roster entries than this -- one player
## cannot be "eliminated down to one survivor".
@export var min_players_to_start: int = 2
## Pause after a round resolves, so the shared screen has a moment where a
## win is visible before the next round's players pop back in.
@export var round_end_pause_sec: float = 2.0
## How long a round may run with no player still in it holding a connected
## controller before it ends with no winner (ADR-0007 amendment). Without
## this, a round everyone walked away from can never end -- nobody is left to
## ring anyone out -- so its claims never expire and every new phone is
## refused. Long enough that a Wi-Fi blip hitting the whole room at once
## costs nobody the round.
@export var abandoned_round_grace_sec: float = 10.0
## Determinism seam for stage rotation (ADR-0011): -1 (the default) leaves
## the rotation randomized every run; any other value seeds it so a scenario
## can assert an exact bag order.
@export var rotation_seed: int = -1
## Rising kill zone (issue #22, ADR-0012): how long the active stage's floor
## `KillZone` holds still at round start before it begins to climb.
@export var kill_zone_grace_sec: float = 50.0
## Seconds the rise then takes to reach the stage's highest spawn. A
## deadline, not a speed: stages range from under 500 px to over 900 px
## between floor and top spawn, and a fixed speed would give Cascade's
## holdouts twice as long as Flatlands'. The speed is derived per stage in
## `_start_kill_zone_rise()`, and the zone keeps climbing past that spawn.
@export var kill_zone_rise_sec: float = 80.0

## Sound hooks (issue #75, ADR-0016); nothing in the game reads them.
## `round_started` once every player is spawned, `round_won` where the
## winner scores, `modifier_announced` as a modifier's name goes up.
signal round_started
signal round_won(slot: int)
signal modifier_announced(title: String)

enum State { WAITING, ROUND_ACTIVE, ROUND_END }

var _state: int = State.WAITING
var _pause_until_msec: int = 0
var _players: Array = []
var _scores: PackedInt32Array = PackedInt32Array()
var _controller_server: Node
var _waiting_label: Label
var _scoreboard: Control
## Stage rotation state (ADR-0011): shuffled bags over `stage_scenes` with no
## stage playing twice in a row, opening every session on `stage_scenes[0]`.
## `_stage_index` starts at -1 so the first `_swap_stage()` call is recognized
## as the opener rather than the seam between two bags.
var _stage_index: int = -1
var _current_stage: Node2D
var _stage_spawn_points: Array[Vector2] = []
## Remaining stage indices for the current bag, next-to-play at the front
## (`pop_front()`). Refilled by `_refill_bag()` once emptied.
var _bag: Array[int] = []
## Seeded from `rotation_seed` in `_ready()`; never the global RNG, so two
## RoundManagers can be given the same seed and produce the same sequence
## (ADR-0011) -- `Array.shuffle()` can't do that, since it always draws from
## the global RNG.
var _rng: RandomNumberGenerator
## When the current round was first seen with no connected controller among
## its surviving players, or -1 while at least one is connected.
var _abandoned_since_msec: int = -1
## The previous round's winner slot, or -1 (no winner: a no-survivors round,
## or no round has ended yet). Consumed by the next `_try_start_round()` --
## which clears it back to -1, since it applies to one round only -- and
## dropped early if that slot's claim expires first (issue #6, D3): a claim
## only ever lapses at the round boundary (ADR-0007), and a newcomer who
## later takes the freed slot must not inherit the old winner's weapon.
var _last_winner_slot: int = -1

## Playtest option (issue #29): with `-- --random-weapons` on the host's
## command line, every player who did not win the last round starts the next
## one holding a random weapon from this list rather than the pickaxe, for
## trying weapons without chasing pickups (#14). The winner still keeps what
## they held (ADR-0005), and pickups still spawn. Off by default: a normal
## launch plays exactly as designed.
const PLAYTEST_WEAPON_PATHS: PackedStringArray = [
	"res://resources/pickaxe.tres",
	"res://resources/staff.tres",
	"res://resources/sword.tres",
	"res://resources/axe.tres",
	"res://resources/dagger.tres",
	"res://resources/boomstick.tres",
]
var _random_weapons: bool = false
## `--demo`: a short-slot showcase. Random weapons, a fixed opening run of
## the stages with the most parts on show, and a quicker lava that still
## leaves a real fight before it arrives. Tests never pass it.
var _demo: bool = false
const DEMO_STAGE_ORDER: PackedStringArray = [
	"Springboard", "Rockfall", "Gale", "Bulwark", "Carousel", "Sinkhole",
]
const DEMO_KILL_ZONE_GRACE_SEC: float = 20.0
const DEMO_KILL_ZONE_RISE_SEC: float = 40.0
const DEMO_PHYSICS_TICKS: int = 120

func _ready() -> void:
	# Either list: `-- --demo` from a terminal, or bare `--demo` from the
	# editor's Play button (project.godot `editor/run/main_run_args`).
	_demo = OS.get_cmdline_user_args().has("--demo") or OS.get_cmdline_args().has("--demo")
	_random_weapons = _demo or OS.get_cmdline_user_args().has("--random-weapons")
	if _demo:
		_apply_demo_mode()
	if _random_weapons:
		print("RoundManager: --random-weapons on; non-winners start each round with a random weapon")
	_rng = RandomNumberGenerator.new()
	if rotation_seed == -1:
		_rng.randomize()
	else:
		_rng.seed = rotation_seed
	for path in player_paths:
		_players.append(get_node_or_null(path))
	_watch_for_buzzes()
	_scores.resize(_players.size())
	_controller_server = get_node_or_null(controller_server_path)
	_waiting_label = get_node_or_null(waiting_label_path) as Label
	_scoreboard = get_node_or_null(scoreboard_path) as Control
	if _scoreboard != null:
		_scoreboard.visible = false
	_update_score_label()
	_set_waiting_text(0)

func _process(_delta: float) -> void:
	match _state:
		State.WAITING:
			_try_start_round()
		State.ROUND_ACTIVE:
			_check_round_end()
			if _state == State.ROUND_ACTIVE:
				_tick_pickups()
		State.ROUND_END:
			if Time.get_ticks_msec() >= _pause_until_msec:
				# Expire first, then test: a winner whose claim lapsed must not
				# pass its weapon to whoever claims the freed slot (issue #6 D3).
				# `_try_start_round()` expires again on the way in; it is idempotent,
				# and the check below is only meaningful once expiry has run.
				if _controller_server != null:
					_controller_server.expire_disconnected_claims()
					if _last_winner_slot != -1 and not _controller_server.claimed_slots().has(_last_winner_slot):
						_last_winner_slot = -1
				_state = State.WAITING
				_try_start_round()

## Enough of the roster present and idle: bring every claimed player into
## the arena. Slots nobody has claimed stay exactly as `Player._ready()`
## (or the previous round's `leave_round()`) left them -- inert and hidden.
##
## Disconnected claims are expired first, on every attempt rather than only
## after a round ends: ADR-0007 holds an entry "until the end of the current
## round", and while waiting there is no round to hold it for. Otherwise a
## phone that joined and dropped before any round started keeps its slot
## forever, is counted as present, and gets spawned as a limp body.
func _try_start_round() -> void:
	if _controller_server == null:
		return
	_controller_server.expire_disconnected_claims()
	var roster: Array[int] = _controller_server.claimed_slots()
	if roster.size() < min_players_to_start:
		# Drop the last round's scoreboard too, so it can't sit over the
		# centred waiting text when a player left during the round.
		if _scoreboard != null:
			_scoreboard.visible = false
		_set_waiting_text(roster.size())
		return
	if _waiting_label != null:
		_waiting_label.visible = false
	if _scoreboard != null:
		_scoreboard.visible = false
	_swap_stage()
	for slot in roster:
		if slot < 0 or slot >= _players.size() or _players[slot] == null:
			continue
		var spawn: Vector2 = Vector2.ZERO
		if slot < _stage_spawn_points.size():
			spawn = _stage_spawn_points[slot]
		else:
			push_warning("RoundManager: stage has %d spawn point(s), none for slot %d; spawning at the origin" % [_stage_spawn_points.size(), slot])
		var keeps_weapon: bool = slot == _last_winner_slot
		_players[slot].start_round(spawn, keeps_weapon)
		if _random_weapons and not keeps_weapon:
			_players[slot].set_weapon_stats(load(PLAYTEST_WEAPON_PATHS[randi() % PLAYTEST_WEAPON_PATHS.size()]))
	_abandoned_since_msec = -1
	# One round only: consumed here whether or not the winner is still rostered.
	_last_winner_slot = -1
	_state = State.ROUND_ACTIVE
	_start_round_modifier()
	_start_pickups()
	_start_kill_zone_rise()
	round_started.emit()

## Rotates to the next stage (ADR-0011): frees the outgoing instance, picks
## the next `_stage_index` into `stage_scenes` via `_next_stage_index()`, and
## caches the new stage's spawn points so `_try_start_round()`'s loop above
## can read them per slot. A no-op with an empty `stage_scenes`, leaving
## `_stage_spawn_points` as it was.
func _swap_stage() -> void:
	if stage_scenes.is_empty():
		return
	var container: Node = get_node_or_null(arena_container_path)
	if container == null:
		return
	if _current_stage != null:
		_current_stage.queue_free()
	_stage_index = _next_stage_index()
	_current_stage = stage_scenes[_stage_index].instantiate()
	container.add_child(_current_stage)
	_stage_spawn_points = _current_stage.get_spawn_points()

## Picks the next stage index (ADR-0011): `stage_scenes[0]` opens every
## session (`_stage_index` still at -1), then shuffled bags cover the whole
## roster, refilling once the current bag is empty. `_stage_index` still
## holds the previously-played index at this point, so it doubles as the
## "just played" value the fresh bag must not start with.
func _next_stage_index() -> int:
	if _demo:
		return (_stage_index + 1) % stage_scenes.size()
	if _stage_index == -1:
		return 0
	if _bag.is_empty():
		_refill_bag(_stage_index)
	return _bag.pop_front()

## Builds a fresh shuffled bag (one Fisher-Yates pass over `_rng`, never the
## global RNG or `Array.shuffle()`, which draws from it) covering every index
## into `stage_scenes`, then fixes up a bag that would repeat `avoid` back to
## back by swapping its first entry with another position -- every index
## plays exactly once regardless of where in the bag it lands, so this cannot
## skip or duplicate a stage. Left alone when the roster has only one stage,
## since no swap can avoid a repeat there (the opener's own repeat case).
func _refill_bag(avoid: int) -> void:
	_bag = _shuffled_indices()
	if _bag.size() > 1 and _bag[0] == avoid:
		var swap_with: int = 1 + _rng.randi() % (_bag.size() - 1)
		var tmp: int = _bag[0]
		_bag[0] = _bag[swap_with]
		_bag[swap_with] = tmp

## A Fisher-Yates shuffle of `range(stage_scenes.size())` over `_rng`.
func _shuffled_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in stage_scenes.size():
		indices.append(i)
	for i in range(indices.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: int = indices[i]
		indices[i] = indices[j]
		indices[j] = tmp
	return indices

func _set_waiting_text(connected: int) -> void:
	if _waiting_label == null:
		return
	_waiting_label.visible = true
	# Not "x / 2": two is the minimum to start, not the most who can play (#36).
	_waiting_label.text = "Waiting for players: %d connected (need %d)" % [connected, min_players_to_start]

## A round ends the instant one or zero players are still standing --
## whichever came from a ring-out or the last hit that crossed DEATH_DAMAGE.
## The lone survivor (if any) scores the round and is returned to the same
## inert state a loser ends up in, via `leave_round()` rather than
## `eliminate()`, since finishing a round alive is not a death.
##
## A round nobody can finish -- no survivor has a connected controller -- is
## ended with no winner once `abandoned_round_grace_sec` has passed; every
## survivor leaves the round the same way a winner does.
func _check_round_end() -> void:
	var alive_slots: Array[int] = []
	for slot in _players.size():
		var player: Variant = _players[slot]
		if player != null and player.alive:
			alive_slots.append(slot)
	if alive_slots.size() > 1:
		if not _round_abandoned(alive_slots):
			return
		for slot in alive_slots:
			_players[slot].leave_round()
		alive_slots.clear()
	if alive_slots.size() == 1:
		var winner_slot: int = alive_slots[0]
		_scores[winner_slot] += 1
		_buzz(winner_slot, "win")
		round_won.emit(winner_slot)
		_players[winner_slot].leave_round()
		_update_score_label()
		_last_winner_slot = winner_slot
	else:
		_last_winner_slot = -1
	_clear_pickups()
	_stop_kill_zone_rise()
	_end_round_modifier()
	_show_scoreboard()
	_state = State.ROUND_END
	_pause_until_msec = Time.get_ticks_msec() + int(round_end_pause_sec * 1000.0)

## Phone buzzes (issue #34, ADR-0013): each slot's player is watched here, so
## `Player` never learns about phones and `ControllerServer` never learns
## about rounds. Every buzz goes only to the phone whose player it is about.
## - `eliminated` for the player just eliminated -- not for survivors put
##   through `leave_round()` at round end, which emits nothing.
## - `struck` for the victim of a strike that dealt damage, and `hit` for the
##   attacker who landed it. A 0-damage swing buzzes no one.
## - `win` is sent from `_check_round_end()` where the winner scores.
func _watch_for_buzzes() -> void:
	for slot in _players.size():
		var player: Variant = _players[slot]
		if player == null:
			continue
		if player.has_signal("eliminated"):
			player.connect("eliminated", _buzz.bind(slot, "eliminated"))
		if player.has_signal("strike_landed"):
			player.connect("strike_landed", _on_strike_landed.bind(slot))

## `attacker_slot` comes last because that is where the signal's bind puts it.
func _on_strike_landed(victim: Node, amount: float, _point: Vector2, _lethal: bool, attacker_slot: int) -> void:
	if amount <= 0.0:
		return
	var victim_slot: int = _players.find(victim)
	if victim_slot != -1:
		_buzz(victim_slot, "struck")
	_buzz(attacker_slot, "hit")

## A roster that cannot buzz (a test stub without `send_buzz`) is skipped.
func _buzz(slot: int, kind: String) -> void:
	if _controller_server != null and _controller_server.has_method("send_buzz"):
		_controller_server.send_buzz(slot, kind)

## Whether the round has run for `abandoned_round_grace_sec` with none of
## `alive_slots` holding a connected controller. Any one reconnecting resets
## the countdown. A roster that cannot report liveness (a test stub without
## `slot_has_controller()`) never abandons a round.
func _round_abandoned(alive_slots: Array[int]) -> bool:
	if not _controller_server.has_method("slot_has_controller"):
		return false
	for slot in alive_slots:
		if _controller_server.slot_has_controller(slot):
			_abandoned_since_msec = -1
			return false
	var now: int = Time.get_ticks_msec()
	if _abandoned_since_msec < 0:
		_abandoned_since_msec = now
	return now - _abandoned_since_msec >= int(abandoned_round_grace_sec * 1000.0)

## Refreshes and reveals the round-end scoreboard: one icon+score entry per
## player slot, read from that slot's Scoreboard/SlotN child (Icon then
## Score, per scenes/Main.tscn) and this node's own _players/_scores.
## Only slots in play get an entry (#45): an empty or disconnected slot's
## entry is hidden, so two players see two scores, not four.
func _show_scoreboard() -> void:
	if _scoreboard == null:
		return
	for slot in _players.size():
		if slot >= _scoreboard.get_child_count():
			continue
		var entry: Node = _scoreboard.get_child(slot)
		if entry is CanvasItem:
			entry.visible = _slot_in_play(slot)
		if entry.get_child_count() < 2:
			continue
		var icon: ColorRect = entry.get_child(0) as ColorRect
		var score_label: Label = entry.get_child(1) as Label
		var player: Variant = _players[slot]
		if icon != null and player != null:
			icon.color = player.identity_outline_color()
		if score_label != null:
			score_label.text = str(_scores[slot]) if slot < _scores.size() else "0"
	_scoreboard.visible = true

## Whether `slot` is claimed and, where the roster can say, has a phone
## connected right now (#45). Without a roster every slot counts, so a
## scenario with no ControllerServer still sees its whole scoreboard.
func _slot_in_play(slot: int) -> bool:
	if _controller_server == null:
		return true
	if not _controller_server.claimed_slots().has(slot):
		return false
	if _controller_server.has_method("slot_has_controller"):
		return _controller_server.slot_has_controller(slot)
	return true

func _update_score_label() -> void:
	var label: Label = get_node_or_null(score_label_path) as Label
	if label == null:
		return
	var parts: PackedStringArray = PackedStringArray()
	for slot in _scores.size():
		if _slot_in_play(slot):
			parts.append("P%d: %d" % [slot + 1, _scores[slot]])
	label.text = "  ".join(parts)

# --- Weapon pickups (issue #14, ADR-0009) ------------------------------------
#
# One pickup lies on the stage when a round starts; another arrives every
# `pickup_spawn_interval_sec` while fewer than `max_pickups` are on it; any
# left when the round ends are cleared. Pickups are parented to the active
# stage instance, so a stage swap can never strand one either.

## The pickup scene instanced per spawn (scenes/Pickup.tscn).
@export var pickup_scene: PackedScene = preload("res://scenes/Pickup.tscn")
## Seconds between pickup arrivals once a round is running (user story 20).
@export var pickup_spawn_interval_sec: float = 10.0
## Fewest pickups the stage is allowed to hold at once (user stories 3 and
## 20). The live cap is `_pickup_cap()`: one fewer than the roster, never
## below this (#36, amending ADR-0009).
@export var max_pickups: int = 2
## Weapons a pickup may hold. Empty means the roster's own list
## (`PickupWeapons.available_weapons()`); scenarios fill it with test weapons.
## The pickaxe is filtered out either way.
@export var pickup_weapons: Array[Resource] = []

const PickupWeaponsScript := preload("res://scripts/PickupWeapons.gd")
## Where a pickup lands on a stage that declares no `PickupSpawn*` markers,
## relative to the stage's origin: above its centre (user story 17).
const FALLBACK_PICKUP_OFFSET: Vector2 = Vector2(0.0, -200.0)
## Two pickups within this of each other are on the same spot.
const PICKUP_SPOT_EPSILON: float = 8.0
## A pickup spot this close to a player spawn is skipped (#111, owner
## playtest: players spawned on a drop and took it before moving). About a
## body width plus the largest pickup's trigger, with room to spare, so a
## player standing on their spawn cannot touch a pickup.
const PICKUP_CLEAR_OF_SPAWN_RADIUS: float = 120.0

var _pickups: Array[Node2D] = []
var _next_pickup_msec: int = 0

## Round start: clear anything left over, put the first pickup down, and
## start the interval from now.
func _start_pickups() -> void:
	_clear_pickups()
	_spawn_pickup()
	_next_pickup_msec = Time.get_ticks_msec() + int(pickup_spawn_interval_sec * 1000.0)

## Each tick of an active round: once the interval is up, add one if the
## stage is below the cap, and start the next interval either way.
func _tick_pickups() -> void:
	var now: int = Time.get_ticks_msec()
	if now < _next_pickup_msec:
		return
	_next_pickup_msec = now + int(pickup_spawn_interval_sec * 1000.0)
	if _live_pickups().size() < _pickup_cap():
		_spawn_pickup()

## Most pickups the stage holds at once right now: one fewer than the players
## on the roster, and never under `max_pickups` -- 2 for two or three players,
## 3 for four (#36, amending ADR-0009's "at most two").
func _pickup_cap() -> int:
	var roster: int = _controller_server.claimed_slots().size() if _controller_server != null else 0
	return maxi(max_pickups, roster - 1)

func _clear_pickups() -> void:
	for pickup: Node2D in _live_pickups():
		pickup.queue_free()
	_pickups.clear()

## Pickups still on the stage: collected ones free themselves, so anything
## freed or on its way out is dropped from the list here.
func _live_pickups() -> Array[Node2D]:
	var live: Array[Node2D] = []
	for pickup: Node2D in _pickups:
		if is_instance_valid(pickup) and not pickup.is_queued_for_deletion():
			live.append(pickup)
	_pickups = live
	return live

func _spawn_pickup() -> void:
	if pickup_scene == null or _live_pickups().size() >= _pickup_cap():
		return
	var parent: Node = _current_stage if _current_stage != null else get_node_or_null(arena_container_path)
	if parent == null:
		return
	var spot: Variant = _free_pickup_spot()
	if spot == null:
		return
	var offered: Array[Resource] = pickup_weapons if not pickup_weapons.is_empty() else PickupWeaponsScript.available_weapons()
	var weapon: Resource = PickupWeaponsScript.choose(offered)
	if weapon == null:
		return
	var pickup: Node2D = pickup_scene.instantiate() as Node2D
	pickup.set_weapon(weapon)
	parent.add_child(pickup)
	pickup.global_position = spot
	# Placed after entering the tree: a spawn, not motion (issue #108).
	pickup.reset_physics_interpolation()
	_pickups.append(pickup)

## A random declared spot with no pickup already on it, or the fallback above
## the stage's centre when the stage declares none. Null when every spot is
## taken. Spots within PICKUP_CLEAR_OF_SPAWN_RADIUS of a player spawn are
## skipped while any other free spot remains; if every free spot is near a
## spawn, the one furthest from all spawns is used, so a stage still gets
## its pickups (#111).
func _free_pickup_spot() -> Variant:
	var spots: Array[Vector2] = []
	if _current_stage != null and _current_stage.has_method("get_pickup_spawn_points"):
		spots = _current_stage.get_pickup_spawn_points()
	if spots.is_empty():
		var origin: Vector2 = _current_stage.global_position if _current_stage != null else Vector2.ZERO
		spots = [origin + FALLBACK_PICKUP_OFFSET]
	var free: Array[Vector2] = []
	for spot: Vector2 in spots:
		var taken: bool = false
		for pickup: Node2D in _live_pickups():
			if pickup.global_position.distance_to(spot) < PICKUP_SPOT_EPSILON:
				taken = true
				break
		if not taken:
			free.append(spot)
	if free.is_empty():
		return null
	var clear: Array[Vector2] = []
	for spot: Vector2 in free:
		if _distance_to_nearest_spawn(spot) >= PICKUP_CLEAR_OF_SPAWN_RADIUS:
			clear.append(spot)
	if not clear.is_empty():
		return clear[randi() % clear.size()]
	var best: Vector2 = free[0]
	for spot: Vector2 in free:
		if _distance_to_nearest_spawn(spot) > _distance_to_nearest_spawn(best):
			best = spot
	return best

## How far `spot` is from the nearest player spawn on the current stage; INF
## when the stage declares none.
func _distance_to_nearest_spawn(spot: Vector2) -> float:
	var nearest: float = INF
	for spawn: Vector2 in _stage_spawn_points:
		nearest = minf(nearest, spot.distance_to(spawn))
	return nearest

# --- Rising kill zone (issue #22, ADR-0012) ----------------------------------
#
# Only the node named `KillZone` directly under the stage root rises. Hazard
# parts share KillZone.gd but sit elsewhere in the tree under other names, so
# they are never found here and never rise. Each round instances a fresh
# stage, so the zone resets to its authored height by construction.

## The active stage's floor kill zone, or null on a stage without one.
func _floor_kill_zone() -> Node2D:
	if _current_stage == null:
		return null
	var zone: Node2D = _current_stage.get_node_or_null("KillZone") as Node2D
	if zone == null or not zone.has_method("start_rising"):
		return null
	return zone

## Round start: arm the rise so it reaches the highest spawn
## `kill_zone_rise_sec` after the grace period ends.
func _start_kill_zone_rise() -> void:
	var zone: Node2D = _floor_kill_zone()
	if zone == null or _stage_spawn_points.is_empty():
		return
	var highest_y: float = INF
	for spawn: Vector2 in _stage_spawn_points:
		highest_y = minf(highest_y, spawn.y)
	var distance: float = zone.global_position.y - highest_y
	if distance <= 0.0 or kill_zone_rise_sec <= 0.0:
		push_warning("RoundManager: floor kill zone is not below the highest spawn; not rising")
		return
	zone.start_rising(kill_zone_grace_sec, distance / kill_zone_rise_sec)

func _stop_kill_zone_rise() -> void:
	var zone: Node2D = _floor_kill_zone()
	if zone != null:
		zone.stop_rising()

# --- Round modifiers (issue #50, ADR-0015) -----------------------------------
#
# Some rounds get one random twist from `RoundModifiers.gd`, applied right
# after the round's players spawn and before the kill zone is armed, and
# undone the moment the round ends. Its name is shown big on screen for
# `modifier_announce_sec` by a label this node builds itself, so no scene
# needs editing.

const RoundModifiersScript := preload("res://scripts/RoundModifiers.gd")

## Chance, 0..1, that a round rolls a modifier. 0 switches them off.
@export_range(0.0, 1.0) var modifier_chance: float = 0.35
## How long a rolled modifier's name stays on screen at round start.
@export var modifier_announce_sec: float = 3.0
## A `RoundModifiers` id (e.g. "low_gravity") every round gets, whatever
## `modifier_chance` and `modifier_rolls_enabled` say: the determinism seam a
## scenario or a playtest uses to pick one. Empty (the default) rolls.
@export var forced_modifier: String = ""
## Determinism seam for the roll itself, like `rotation_seed`: -1 leaves it
## random every run. Its own RNG, never `_rng`, so a roll can never shift a
## seeded stage rotation.
@export var modifier_seed: int = -1

## Master switch for random rolls, shared by every RoundManager. The game
## never touches it. The scenario runner turns it off at startup so every
## scenario written before #50 plays exactly as it did; a scenario that wants
## rolls turns it back on, and `forced_modifier` works either way.
static var modifier_rolls_enabled: bool = true

var _modifier: RefCounted = null
var _modifier_rng: RandomNumberGenerator
var _modifier_layer: CanvasLayer
var _modifier_label: Label
## Hides the label `modifier_announce_sec` after an announcement. A child
## node, so it goes when this node does; restarted by every announcement.
var _modifier_timer: Timer

## The id of the modifier on the current round, or "" for none.
func active_modifier_id() -> String:
	return _modifier.id if _modifier != null else ""

## The announcement label, or null before any modifier was ever announced.
func modifier_label() -> Label:
	return _modifier_label

## Round start: roll (or take the forced one), apply it to every player now
## in the round and the stage, and announce it.
func _start_round_modifier() -> void:
	_end_round_modifier()
	var id: String = _roll_modifier()
	if id == "":
		return
	_modifier = RoundModifiersScript.create(id)
	if _modifier == null:
		push_warning("RoundManager: unknown round modifier '%s'" % id)
		return
	var in_round: Array = []
	for player: Variant in _players:
		if player != null and player.alive:
			in_round.append(player)
	_modifier.apply(self, in_round, _current_stage)
	_announce_modifier(_modifier.title)

## Round end: put back everything the modifier changed and drop its name.
func _end_round_modifier() -> void:
	if _modifier != null:
		_modifier.undo()
		_modifier = null
	if _modifier_label != null:
		_modifier_label.visible = false

func _roll_modifier() -> String:
	if forced_modifier != "":
		return forced_modifier
	if not modifier_rolls_enabled or modifier_chance <= 0.0:
		return ""
	if _modifier_rng == null:
		_modifier_rng = RandomNumberGenerator.new()
		if modifier_seed == -1:
			_modifier_rng.randomize()
		else:
			_modifier_rng.seed = modifier_seed
	if _modifier_rng.randf() >= modifier_chance:
		return ""
	var ids: PackedStringArray = RoundModifiersScript.IDS
	return ids[_modifier_rng.randi() % ids.size()]

func _announce_modifier(title: String) -> void:
	if _modifier_label == null:
		_build_modifier_label()
	_modifier_label.text = title
	_modifier_label.visible = true
	_modifier_timer.start(maxf(modifier_announce_sec, 0.01))
	modifier_announced.emit(title)

## Big, outlined, centred across the upper part of the screen, on its own
## canvas layer above the HUD.
func _build_modifier_label() -> void:
	_modifier_layer = CanvasLayer.new()
	_modifier_layer.name = "ModifierLayer"
	_modifier_layer.layer = 10
	add_child(_modifier_layer)
	_modifier_label = Label.new()
	_modifier_label.name = "ModifierLabel"
	_modifier_label.anchor_left = 0.0
	_modifier_label.anchor_right = 1.0
	_modifier_label.anchor_top = 0.12
	_modifier_label.anchor_bottom = 0.32
	_modifier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modifier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_modifier_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modifier_label.add_theme_font_size_override("font_size", 96)
	_modifier_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	_modifier_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0, 1.0))
	_modifier_label.add_theme_constant_override("outline_size", 16)
	_modifier_label.visible = false
	_modifier_layer.add_child(_modifier_label)
	_modifier_timer = Timer.new()
	_modifier_timer.name = "ModifierAnnounceTimer"
	_modifier_timer.one_shot = true
	_modifier_timer.timeout.connect(func() -> void: _modifier_label.visible = false)
	add_child(_modifier_timer)

## A RoundManager leaving the tree mid-round (a scenario tearing down) must
## not leave its modifier on players that outlive it.
func _exit_tree() -> void:
	if _modifier != null:
		_modifier.undo()
		_modifier = null

## Puts DEMO_STAGE_ORDER at the front of the rotation (the rest follow in
## their usual order, played straight through), and shortens the lava.
func _apply_demo_mode() -> void:
	var ordered: Array[PackedScene] = []
	for stage_name: String in DEMO_STAGE_ORDER:
		for scene: PackedScene in stage_scenes:
			if scene.resource_path.get_file().get_basename() == stage_name:
				ordered.append(scene)
	for scene: PackedScene in stage_scenes:
		if not ordered.has(scene):
			ordered.append(scene)
	stage_scenes = ordered
	kill_zone_grace_sec = DEMO_KILL_ZONE_GRACE_SEC
	kill_zone_rise_sec = DEMO_KILL_ZONE_RISE_SEC
	# Twice the physics rate halves how far a fast head or body moves per
	# step, so far less tunnels through platforms. Gameplay is timed in
	# seconds, not ticks; the scenarios never pass --demo, so they keep 60.
	Engine.physics_ticks_per_second = DEMO_PHYSICS_TICKS
	print("RoundManager: --demo on; random weapons, %d Hz physics, lava after %.0f s, stages from %s" % [
		Engine.physics_ticks_per_second, kill_zone_grace_sec, ", ".join(DEMO_STAGE_ORDER)])
