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
## Issue #144: a large stage (`Stage.view_size` bigger than the normal view)
## is only offered to a round with at least this many players; normal stages
## are offered at any count. See `_stage_allowed()`.
@export var large_stage_min_players: int = 5
## Issue #144: the camera `_swap_stage()` zooms and centres on each new
## stage's view (`Stage.get_view_rect()`). Empty leaves every camera alone,
## which is what every scenario's RoundManager does unless it tests this.
@export var camera_path: NodePath
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
## Announcer hooks (#152): each whole second of the lobby countdown (3, 2,
## 1), and the round win that wins the match.
signal countdown_ticked(seconds_left: int)
signal match_won(slot: int)

enum State { WAITING, ROUND_ACTIVE, ROUND_END, LOBBY, COUNTDOWN, VICTORY }

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
	_watch_for_survivor()
	_scores.resize(_players.size())
	_controller_server = get_node_or_null(controller_server_path)
	if _controller_server != null and _controller_server.has_signal("host_command"):
		_controller_server.connect("host_command", _on_host_command)
	_watch_for_lobby_changes()
	if _controller_server != null and _controller_server.has_signal("player_joined"):
		_controller_server.connect("player_joined", _on_slot_claimed_fresh)
	_waiting_label = get_node_or_null(waiting_label_path) as Label
	_scoreboard = get_node_or_null(scoreboard_path) as Control
	if _scoreboard != null:
		_scoreboard.visible = false
	_update_score_label()
	_set_waiting_text(0)
	if lobby_enabled:
		_enter_lobby()

func _process(_delta: float) -> void:
	_tick_spawn_protection()
	_tick_name_tags()
	match _state:
		State.LOBBY, State.COUNTDOWN, State.VICTORY:
			_tick_lobby()
		State.WAITING:
			if lobby_enabled and _roster_size() < min_players_to_start:
				_enter_lobby()
			else:
				_try_start_round()
		State.ROUND_ACTIVE:
			_check_round_end()
			if _state == State.ROUND_ACTIVE:
				_tick_pickups()
				if lobby_enabled and _lobby_publish_due():
					_publish_lobby_state()
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
				if _match_winner_slot != -1:
					_enter_victory()
					return
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
	_round_player_count = roster.size()
	_swap_stage()
	_round_number += 1
	_in_round.clear()
	for slot in roster:
		if slot < 0 or slot >= _players.size() or _players[slot] == null:
			continue
		# By place in the round, not slot number (#163): stages pair their spawns
		# left/right, so slots 0 and 2 alone would both start on the left.
		var spawn: Vector2 = _spawn_point(_in_round.size())
		var keeps_weapon: bool = slot == _last_winner_slot
		_players[slot].start_round(spawn, keeps_weapon)
		_in_round.append(slot)
		if _random_weapons and not keeps_weapon:
			_players[slot].set_weapon_stats(load(PLAYTEST_WEAPON_PATHS[randi() % PLAYTEST_WEAPON_PATHS.size()]))
	_ko_round_started()
	_abandoned_since_msec = -1
	# One round only: consumed here whether or not the winner is still rostered.
	_last_winner_slot = -1
	_survivor_slot = -1
	_state = State.ROUND_ACTIVE
	_start_round_modifier()
	_start_pickups()
	_start_kill_zone_rise()
	_start_spawn_protection()
	_show_stage_title()
	round_started.emit()

## Rotates to the next stage (ADR-0011): frees the outgoing instance, picks
## the next `_stage_index` into `stage_scenes` via `_next_stage_index()`, and
## caches the new stage's spawn points so `_try_start_round()`'s loop above
## can hand them out in roster order. A no-op with an empty `stage_scenes`, leaving
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
	_fit_camera_to_stage()

# --- Large stages (issue #144) ------------------------------------------------
#
# A stage may declare a view bigger than the 1600x900 screen (`Stage.view_size`).
# The Main camera zooms out, uniformly, until that view fits, and centres on it;
# a normal stage puts it back to zoom 1 at the origin, exactly as it always was.
# HUD, title card, lobby and podium live on CanvasLayers, which the camera never
# moves or scales; the name tags are world-space, so they are scaled back up by
# the zoom (see `_tick_name_tags()`).

const StageScript := preload("res://scripts/Stage.gd")

## How many players the round being started has; read by `_stage_allowed()`.
var _round_player_count: int = 0
## `Stage.view_size_of()` per stage scene, so a scene's state is read once.
var _large_stage_cache: Dictionary = {}

func _fit_camera_to_stage() -> void:
	var camera: Camera2D = get_node_or_null(camera_path) as Camera2D if not camera_path.is_empty() else null
	if camera == null or _current_stage == null:
		return
	var view: Rect2
	if _current_stage.has_method("get_view_rect"):
		view = _current_stage.get_view_rect()
	else:
		view = Rect2(_current_stage.global_position - StageScript.DEFAULT_VIEW_SIZE * 0.5, StageScript.DEFAULT_VIEW_SIZE)
	var zoom: float = StageScript.zoom_for_view(view.size)
	camera.zoom = Vector2(zoom, zoom)
	camera.global_position = view.get_center()
	# A cut between rounds, not a pan: no smoothing or interpolation from the
	# last stage's framing.
	camera.reset_smoothing()
	camera.reset_physics_interpolation()
	camera.force_update_scroll()

## Whether `stage_scenes[index]` is a large stage.
func _stage_is_large(index: int) -> bool:
	var scene: PackedScene = stage_scenes[index]
	if not _large_stage_cache.has(scene):
		_large_stage_cache[scene] = StageScript.is_large_view(StageScript.view_size_of(scene))
	return _large_stage_cache[scene]

## Whether the round being started may play `stage_scenes[index]`: any normal
## stage, and a large one only with `large_stage_min_players` or more. A
## rotation with no stage the round may play (say, only large stages and two
## players) ignores the rule rather than play nothing.
func _stage_allowed(index: int) -> bool:
	if _round_player_count >= large_stage_min_players or not _stage_is_large(index):
		return true
	for i in stage_scenes.size():
		if not _stage_is_large(i):
			return false
	return true

## Picks the next stage index (ADR-0011): `stage_scenes[0]` opens every
## session (`_stage_index` still at -1), then shuffled bags cover the whole
## roster, refilling once the current bag is empty. `_stage_index` still
## holds the previously-played index at this point, so it doubles as the
## "just played" value the fresh bag must not start with.
##
## Issue #144: only stages `_stage_allowed()` for this round's player count are
## played. A bag is dealt from the stages allowed when it is filled, and
## re-dealt the moment the count crosses `large_stage_min_players` either way
## (#163): a bag dealt for three would otherwise hold no large stage for
## however many rounds of seven it had left. A new match deals afresh too
## (`_begin_match()`).
func _next_stage_index() -> int:
	if _demo:
		var next: int = _stage_index
		for _i in stage_scenes.size():
			next = (next + 1) % stage_scenes.size()
			if _stage_allowed(next):
				break
		return next
	if _stage_index == -1:
		for i in stage_scenes.size():
			if _stage_allowed(i):
				return i
		return 0
	if _bag_large_eligible != _large_stages_eligible() and _rotation_has_large_stage():
		_bag.clear()
	# A fresh bag always holds an allowed stage, so this ends within one bag's
	# worth of skips and one refill.
	var index: int = 0
	for _attempt in 2 * stage_scenes.size() + 1:
		if _bag.is_empty():
			_refill_bag(_stage_index)
		index = _bag.pop_front()
		if _stage_allowed(index):
			break
	return index

## Builds a fresh shuffled bag (one Fisher-Yates pass over `_rng`, never the
## global RNG or `Array.shuffle()`, which draws from it) covering every index
## into `stage_scenes`, then fixes up a bag that would repeat `avoid` back to
## back by swapping its first entry with another position -- every index
## plays exactly once regardless of where in the bag it lands, so this cannot
## skip or duplicate a stage. Left alone when the roster has only one stage,
## since no swap can avoid a repeat there (the opener's own repeat case).
func _refill_bag(avoid: int) -> void:
	# Shuffled first and filtered after, so a rotation with no large stages
	# draws exactly the order it drew before issue #144.
	_bag = []
	_bag_large_eligible = _large_stages_eligible()
	for index: int in _shuffled_indices():
		if _stage_allowed(index):
			_bag.append(index)
	if _bag.size() > 1 and _bag[0] == avoid:
		var swap_with: int = 1 + _rng.randi() % (_bag.size() - 1)
		var tmp: int = _bag[0]
		_bag[0] = _bag[swap_with]
		_bag[swap_with] = tmp

## Whether this round's player count may play large stages (issue #144).
func _large_stages_eligible() -> bool:
	return _round_player_count >= large_stage_min_players

## What `_large_stages_eligible()` said when `_bag` was dealt (#163).
var _bag_large_eligible: bool = false

## Whether any stage in the rotation is large. Without one the player count
## never changes a bag, so it is never re-dealt for it.
func _rotation_has_large_stage() -> bool:
	for i in stage_scenes.size():
		if _stage_is_large(i):
			return true
	return false

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
	_flush_kos()
	var alive_slots: Array[int] = []
	for slot in _players.size():
		var player: Variant = _players[slot]
		if player != null and player.alive:
			alive_slots.append(slot)
	# Nobody left, but someone was the last one standing on an earlier physics
	# tick of this frame: they won before they fell (#163).
	if alive_slots.is_empty() and _survivor_slot != -1:
		alive_slots.append(_survivor_slot)
	if alive_slots.size() > 1:
		if not _round_abandoned(alive_slots):
			return
		for slot in alive_slots:
			_players[slot].leave_round()
		alive_slots.clear()
	_survivor_slot = -1
	if alive_slots.size() == 1:
		var winner_slot: int = alive_slots[0]
		_scores[winner_slot] += 1
		_buzz(winner_slot, "win")
		round_won.emit(winner_slot)
		_players[winner_slot].leave_round()
		_update_score_label()
		_last_winner_slot = winner_slot
		if lobby_enabled and _scores[winner_slot] >= _match_target:
			_match_winner_slot = winner_slot
			match_won.emit(winner_slot)
	else:
		_last_winner_slot = -1
	_clear_pickups()
	_stop_kill_zone_rise()
	_end_round_modifier()
	_ko_round_ended(_last_winner_slot)
	_show_scoreboard()
	_state = State.ROUND_END
	_pause_until_msec = Time.get_ticks_msec() + int(round_end_pause_sec * 1000.0)
	if lobby_enabled:
		_publish_lobby_state()

## The round's last one standing, recorded the moment an elimination leaves a
## single player alive (#163), or -1. `_check_round_end()` runs once per
## rendered frame, but eliminations land on physics ticks and a slow frame
## can hold two: without this, a survivor who falls on the tick after the
## deciding KO ends the round with nobody standing, and nobody scores.
var _survivor_slot: int = -1
## The physics frame `_survivor_slot` was recorded on. A survivor eliminated
## on that same tick went down together with the last opponent: still a draw.
var _survivor_frame: int = -1

func _watch_for_survivor() -> void:
	for slot in _players.size():
		var player: Variant = _players[slot]
		if player != null and player.has_signal("eliminated"):
			player.connect("eliminated", _on_eliminated_check_survivor.bind(slot))

func _on_eliminated_check_survivor(slot: int) -> void:
	if _state != State.ROUND_ACTIVE:
		return
	var frame: int = Engine.get_physics_frames()
	if slot == _survivor_slot:
		if frame == _survivor_frame:
			_survivor_slot = -1
		return
	var alive: Array[int] = _alive_slots()
	if alive.size() == 1:
		_survivor_slot = alive[0]
		_survivor_frame = frame

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
		if player.has_signal("eliminated"):
			player.connect("eliminated", _on_ko_eliminated.bind(slot))

## `attacker_slot` comes last because that is where the signal's bind puts it.
func _on_strike_landed(victim: Node, amount: float, _point: Vector2, _lethal: bool, attacker_slot: int) -> void:
	_ko_record_hit(victim, amount, attacker_slot)
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

## Where the `place`-th player of a round (0-based, in roster order) starts:
## spawn point `place`, so the first two players of any roster take a stage's
## first left/right pair whatever their slot numbers (#163). On a stage with
## fewer spawns than players (issue #138) a spawn is shared round-robin and
## nudged by `SPAWN_SHARE_OFFSET` per lap -- alternately left and right -- so
## two players never start inside each other.
func _spawn_point(place: int) -> Vector2:
	var count: int = _stage_spawn_points.size()
	if count == 0:
		push_warning("RoundManager: stage has no spawn points; player %d spawns at the origin" % place)
		return Vector2.ZERO
	var lap: int = place / count
	var spawn: Vector2 = _stage_spawn_points[place % count]
	if lap > 0:
		var side: float = 1.0 if place % 2 == 0 else -1.0
		spawn += Vector2(SPAWN_SHARE_OFFSET.x * side * lap, SPAWN_SHARE_OFFSET.y * lap)
	return spawn

## How far a player sharing a spawn point starts from the one it shares with:
## to the side by about a body width and a little higher, so it lands beside
## rather than on top, still on the same platform.
const SPAWN_SHARE_OFFSET: Vector2 = Vector2(48.0, -24.0)

## A podium column's width once more than four are on it (issue #138).
const PODIUM_CROWDED_COLUMN_PX: float = 180.0

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
		var name_label: Label = entry.get_child(2) as Label if entry.get_child_count() > 2 else null
		if name_label != null:
			name_label.text = _slot_name(slot)
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
## 12 since #152 (was 10): a little rarer with few players, and
## `_pickup_interval_sec()` shortens it for a crowd.
@export var pickup_spawn_interval_sec: float = 12.0
## With this many players or more on the roster the stage is crowded (#152):
## pickups come every `crowded_interval_scale` of the interval, and the cap
## rises to one per player.
@export var crowded_roster: int = 5
@export var crowded_interval_scale: float = 0.6
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
	_next_pickup_msec = Time.get_ticks_msec() + int(_pickup_interval_sec() * 1000.0)

## Each tick of an active round: once the interval is up, add one if the
## stage is below the cap, and start the next interval either way.
func _tick_pickups() -> void:
	var now: int = Time.get_ticks_msec()
	if now < _next_pickup_msec:
		return
	_next_pickup_msec = now + int(_pickup_interval_sec() * 1000.0)
	if _live_pickups().size() < _pickup_cap():
		_spawn_pickup()

## Most pickups the stage holds at once right now: one fewer than the players
## on the roster, and never under `max_pickups` -- 2 for two or three players,
## 3 for four (#36, amending ADR-0009's "at most two"); one per player from
## `crowded_roster` up (#152).
func _pickup_cap() -> int:
	var roster: int = _controller_server.claimed_slots().size() if _controller_server != null else 0
	if roster >= crowded_roster:
		return maxi(max_pickups, roster)
	return maxi(max_pickups, roster - 1)

## Seconds until the next pickup: `pickup_spawn_interval_sec`, shortened by
## `crowded_interval_scale` from `crowded_roster` players up (#152).
func _pickup_interval_sec() -> float:
	var roster: int = _controller_server.claimed_slots().size() if _controller_server != null else 0
	if roster >= crowded_roster:
		return pickup_spawn_interval_sec * crowded_interval_scale
	return pickup_spawn_interval_sec

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

# --- Spawn protection (issue #114) -------------------------------------------
#
# For `spawn_protection_sec` after a round places the players, none of them can
# take damage, and each blinks to show it. Knockback still applies (owner's
# call left to us in #114; a shove at spawn is harmless, and blocking it would
# mean reaching into Player's physics). The lava still eliminates. There is no
# mid-round spawn to protect: a phone that joins mid-round waits for the next
# round (ADR-0004), and that round's start protects it with everyone else.

## Seconds of spawn protection at round start (#114). 0 turns it off.
@export var spawn_protection_sec: float = 1.0
## Blink rate and the dimmed alpha a protected player blinks down to.
const SPAWN_BLINK_HZ: float = 8.0
const SPAWN_BLINK_ALPHA: float = 0.35

var _protected: Array[Node2D] = []
var _protected_until_msec: int = 0

func _start_spawn_protection() -> void:
	_end_spawn_protection()
	if spawn_protection_sec <= 0.0:
		return
	for player: Variant in _players:
		if player is Node2D and is_instance_valid(player) and bool(player.get("alive")):
			player.set("spawn_protected", true)
			_protected.append(player)
	_protected_until_msec = Time.get_ticks_msec() + int(spawn_protection_sec * 1000.0)

func _tick_spawn_protection() -> void:
	if _protected.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if now >= _protected_until_msec or _state != State.ROUND_ACTIVE:
		_end_spawn_protection()
		return
	var lit: bool = int(float(now) / 1000.0 * SPAWN_BLINK_HZ * 2.0) % 2 == 0
	for player: Node2D in _protected:
		if is_instance_valid(player):
			player.modulate.a = 1.0 if lit else SPAWN_BLINK_ALPHA

func _end_spawn_protection() -> void:
	for player: Node2D in _protected:
		if is_instance_valid(player):
			player.set("spawn_protected", false)
			player.modulate.a = 1.0
	_protected.clear()

## Whether spawn protection is running, for the scenarios.
func spawn_protection_active() -> bool:
	return not _protected.is_empty()

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
	if _paused:
		_set_tree_paused(false)
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

# --- Lobby, ready-up and matches (issue #120) --------------------------------
#
# With `lobby_enabled` (scenes/Main.tscn turns it on) the session opens on a
# lobby screen: the game name, a big join QR, and each joined phone's colour,
# name and ready state. When every joined phone (2+) is ready a 3-2-1
# countdown runs; a join, a leave or an un-ready during it cancels it. Then a
# match: rounds as before, until someone reaches the host phone's "first to
# N". A victory screen with a podium follows, and every phone pressing
# Rematch (Ready again) takes the room back to the lobby, which counts down
# straight away. Off by default, so every scenario written before #120 keeps
# its endless round loop.
#
# ControllerServer only carries the phones' requests and this node's state
# back to them; everything here reaches it duck-typed, so a stub roster
# without the lobby methods simply never has anyone ready.

## Open on the lobby and play matches ("first to N") instead of an endless
## round loop.
@export var lobby_enabled: bool = false
## Length of the 3-2-1 countdown once everyone is ready.
@export var lobby_countdown_sec: float = 3.0

const LOBBY_BACKGROUND: Color = Color(0.05, 0.06, 0.08, 0.96)
const LOBBY_ACCENT: Color = Color(1.0, 0.85, 0.2, 1.0)
const GAME_TITLE: String = "PICKFIGHT"
## Podium block heights by place, as a fraction of the tallest.
const PODIUM_HEIGHTS: Array[float] = [1.0, 0.72, 0.5, 0.34]
const PODIUM_TALLEST_PX: float = 260.0

var _match_target: int = 5
var _match_winner_slot: int = -1
var _countdown_until_msec: int = 0
var _countdown_roster: Array[int] = []
var _lobby_layer: CanvasLayer
var _lobby_panel: Control
var _victory_panel: Control
var _lobby_rows: VBoxContainer
var _lobby_status: Label
var _lobby_target_label: Label
var _lobby_qr: TextureRect
var _lobby_url: Label
var _victory_title: Label
var _podium: HBoxContainer
var _last_lobby_state: Dictionary = {}

## "lobby", "countdown", "playing", "round_end" (the pause between rounds)
## or "victory": what the phones are told.
func lobby_phase() -> String:
	match _state:
		State.LOBBY:
			return "lobby"
		State.COUNTDOWN:
			return "countdown"
		State.VICTORY:
			return "victory"
		State.ROUND_END:
			return "round_end"
	return "playing"

## The current match's "first to N", fixed when its countdown finished.
func match_target() -> int:
	return _match_target

## The match winner the victory screen is showing, or -1.
func match_winner_slot() -> int:
	return _match_winner_slot

func lobby_panel() -> Control:
	return _lobby_panel

func victory_panel() -> Control:
	return _victory_panel

func score_of(slot: int) -> int:
	return _scores[slot] if slot >= 0 and slot < _scores.size() else 0

func _roster() -> Array[int]:
	if _controller_server == null:
		return []
	# Never mid-round: a claim outlives a disconnect until the round ends
	# (ADR-0007), and the phones' state is published every frame of one.
	if _state != State.ROUND_ACTIVE and _state != State.ROUND_END:
		_controller_server.expire_disconnected_claims()
	return _controller_server.claimed_slots()

func _roster_size() -> int:
	return _roster().size()

func _is_ready(slot: int) -> bool:
	return _controller_server != null and _controller_server.has_method("slot_ready") and _controller_server.slot_ready(slot)

func _everyone_ready(roster: Array[int]) -> bool:
	if roster.size() < min_players_to_start or _bots_waiting_for_a_human(roster):
		return false
	for slot: int in roster:
		if not _is_ready(slot):
			return false
	return true

func _host_slot() -> int:
	if _controller_server != null and _controller_server.has_method("host_slot"):
		return _controller_server.host_slot()
	return -1

## What the host phone has typed, or the current value with no host to ask.
func _requested_target() -> int:
	if _controller_server != null and _controller_server.has_method("match_target"):
		return maxi(1, int(_controller_server.match_target()))
	return _match_target

## A slot's display name: the phone's nickname where the roster has one.
func _slot_name(slot: int) -> String:
	if _controller_server != null and _controller_server.has_method("slot_name"):
		var nickname: String = str(_controller_server.slot_name(slot))
		if not nickname.is_empty():
			return nickname
	return "P%d" % (slot + 1)

func _slot_color(slot: int) -> Color:
	var player: Variant = _players[slot] if slot >= 0 and slot < _players.size() else null
	if player != null and player.has_method("identity_outline_color"):
		return player.identity_outline_color()
	return Color.WHITE

## The chill lobby track, from the Music autoload (#118) by path. Fight music
## is Music's own job: it follows `round_started`.
func _play_lobby_music() -> void:
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("play_lobby"):
		music.play_lobby()

func _enter_lobby() -> void:
	_play_lobby_music()
	_state = State.LOBBY
	_match_winner_slot = -1
	_clear_stage()
	if _waiting_label != null:
		_waiting_label.visible = false
	if _scoreboard != null:
		_scoreboard.visible = false
	_build_lobby_ui()
	_lobby_panel.visible = true
	_victory_panel.visible = false
	_last_lobby_state = {}
	_tick_lobby()

func _enter_victory() -> void:
	_play_lobby_music()
	_state = State.VICTORY
	_clear_stage()
	if _controller_server != null and _controller_server.has_method("clear_ready"):
		_controller_server.clear_ready()
	if _scoreboard != null:
		_scoreboard.visible = false
	_build_lobby_ui()
	_refresh_victory()
	_lobby_panel.visible = false
	_victory_panel.visible = true
	_last_lobby_state = {}
	_tick_lobby()

## Frees the last round's stage on the way into the lobby or the victory
## screen (#163), so its falling rocks and collapsing floors stop running --
## and making sounds -- behind them. The next round instances a fresh stage
## anyway; `_stage_index` is kept, so it still never repeats the last one.
func _clear_stage() -> void:
	if _current_stage != null:
		_current_stage.queue_free()
		_current_stage = null
	_stage_spawn_points = []

## The countdown ran out: fresh scores, everyone back to not-ready (so the
## victory screen's Rematch needs pressing afresh), and the first round.
func _begin_match() -> void:
	_match_target = _requested_target()
	_match_winner_slot = -1
	_last_winner_slot = -1
	for slot in _scores.size():
		_scores[slot] = 0
	# A fresh bag for a fresh match (#163), dealt for its own player count.
	_bag.clear()
	_update_score_label()
	_ko_match_started()
	if _controller_server != null and _controller_server.has_method("clear_ready"):
		_controller_server.clear_ready()
	_lobby_panel.visible = false
	_victory_panel.visible = false
	_state = State.WAITING
	_publish_lobby_state()
	_try_start_round()

func _tick_lobby() -> void:
	var roster: Array[int] = _roster()
	match _state:
		State.LOBBY:
			if _everyone_ready(roster):
				_state = State.COUNTDOWN
				_countdown_roster = roster.duplicate()
				_countdown_until_msec = Time.get_ticks_msec() + int(lobby_countdown_sec * 1000.0)
		State.COUNTDOWN:
			if roster != _countdown_roster or not _everyone_ready(roster):
				_state = State.LOBBY
			elif Time.get_ticks_msec() >= _countdown_until_msec:
				_begin_match()
				return
		State.VICTORY:
			if _everyone_ready(roster) or roster.size() < min_players_to_start:
				_enter_lobby()
				return
	var tick: int = _countdown_left() if _state == State.COUNTDOWN else 0
	if tick != _last_countdown_tick and tick > 0:
		countdown_ticked.emit(tick)
	_last_countdown_tick = tick
	_publish_lobby_state()

## The countdown second last announced by `countdown_ticked` (#152).
var _last_countdown_tick: int = 0

func _countdown_left() -> int:
	return maxi(1, ceili(float(_countdown_until_msec - Time.get_ticks_msec()) / 1000.0))

## Builds the state the phones and the lobby screen show, and pushes it out
## only when something in it changed.
func _publish_lobby_state() -> void:
	_lobby_published_msec = Time.get_ticks_msec()
	lobby_state_builds += 1
	var roster: Array[int] = _roster()
	var players: Array = []
	for slot: int in roster:
		# "color" (issue #151): a phone picking a colour changes the state, so
		# the lobby's swatches are redrawn in it.
		players.append({"slot": slot, "ready": _is_ready(slot), "name": _slot_name(slot),
			"color": _slot_color(slot).to_html(false)})
	var in_lobby: bool = _state == State.LOBBY or _state == State.COUNTDOWN
	var state: Dictionary = {
		"phase": lobby_phase(),
		"host": _host_slot(),
		"target": _requested_target() if in_lobby else _match_target,
		"players": players,
		"count": _countdown_left() if _state == State.COUNTDOWN else 0,
		"winner": _match_winner_slot,
		# Issue #121: what each phone needs to say where its player stands.
		"round": _round_number,
		"in_round": _in_round.duplicate(),
		"alive": _alive_slots(),
		"next": ceili(maxf(0.0, float(_pause_until_msec - Time.get_ticks_msec())) / 1000.0) if _state == State.ROUND_END else 0,
		# Issue #149: the host phone's menu offers Resume instead of Pause.
		"paused": _paused,
	}
	if state == _last_lobby_state:
		return
	_last_lobby_state = state
	if _controller_server != null and _controller_server.has_method("set_lobby_state"):
		_controller_server.set_lobby_state(state)
	if _lobby_panel != null and in_lobby:
		_refresh_lobby(state)
	elif _victory_panel != null and _state == State.VICTORY:
		_refresh_victory()

func _refresh_lobby(state: Dictionary) -> void:
	for child: Node in _lobby_rows.get_children():
		child.queue_free()
	for entry: Dictionary in state["players"]:
		var slot: int = entry["slot"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(40, 40)
		swatch.color = _slot_color(slot)
		row.add_child(swatch)
		var tag: String = "  (host)" if slot == state["host"] else ""
		var label := _big_label("%s%s  -  %s" % [entry["name"], tag, "READY" if entry["ready"] else "not ready"],
			36 if state["players"].size() <= 4 else 28, LOBBY_ACCENT if entry["ready"] else Color(0.8, 0.82, 0.88))
		row.add_child(label)
		_lobby_rows.add_child(row)
	_lobby_target_label.text = "First to %d" % state["target"]
	var joined: int = state["players"].size()
	if _state == State.COUNTDOWN:
		_lobby_status.text = str(state["count"])
	elif joined < min_players_to_start:
		_lobby_status.text = "Scan to join: %d joined (need %d)" % [joined, min_players_to_start]
	else:
		_lobby_status.text = "Press Ready on your phone"
	if _controller_server != null:
		var qr: Variant = _controller_server.get("join_qr_texture")
		_lobby_qr.texture = qr as Texture2D
		_lobby_qr.visible = qr != null
		var url: Variant = _controller_server.get("join_url")
		_lobby_url.text = str(url) if url != null else ""

## The podium: the match winner on the tallest block, then everyone else in
## the roster by final score.
func _refresh_victory() -> void:
	for child: Node in _podium.get_children():
		child.queue_free()
	var roster: Array[int] = _roster()
	var slots: Array[int] = []
	for slot in _players.size():
		if _players[slot] != null and (roster.has(slot) or slot == _match_winner_slot):
			slots.append(slot)
	slots.sort_custom(func(a: int, b: int) -> bool:
		if a == _match_winner_slot or b == _match_winner_slot:
			return a == _match_winner_slot
		return _scores[a] > _scores[b])
	# Five to eight on the podium (issue #138) take narrower columns and smaller
	# names that wrap, so eight columns still fit across the 1600 px screen.
	var crowded: bool = slots.size() > 4
	_podium.add_theme_constant_override("separation", 16 if crowded else 40)
	for place in slots.size():
		var slot: int = slots[place]
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_END
		column.add_theme_constant_override("separation", 8)
		var name_label: Label = _big_label("%s\n%d" % [_slot_name(slot), _scores[slot]], 24 if crowded else 36, Color.WHITE)
		if crowded:
			# A fixed column that a long name wraps inside rather than widens.
			name_label.custom_minimum_size.x = PODIUM_CROWDED_COLUMN_PX
			name_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		column.add_child(name_label)
		var block := ColorRect.new()
		block.color = _slot_color(slot)
		block.custom_minimum_size = Vector2(120 if crowded else 160, PODIUM_TALLEST_PX * PODIUM_HEIGHTS[mini(place, PODIUM_HEIGHTS.size() - 1)])
		column.add_child(block)
		column.add_child(_big_label(str(place + 1), 28, Color.WHITE))
		_podium.add_child(column)
	if _match_winner_slot != -1:
		_victory_title.text = "%s WINS!" % _slot_name(_match_winner_slot)
		_victory_title.add_theme_color_override("font_color", _slot_color(_match_winner_slot))
	else:
		_victory_title.text = "MATCH OVER"
	_refresh_awards(slots)

func _build_lobby_ui() -> void:
	if _lobby_layer != null:
		return
	_lobby_layer = CanvasLayer.new()
	_lobby_layer.name = "LobbyLayer"
	_lobby_layer.layer = 5
	add_child(_lobby_layer)

	_lobby_panel = _full_screen_panel("LobbyPanel")
	var columns := HBoxContainer.new()
	columns.set_anchors_preset(Control.PRESET_FULL_RECT)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 96)
	_lobby_panel.add_child(columns)
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 24)
	columns.add_child(left)
	left.add_child(_big_label(GAME_TITLE, 120, LOBBY_ACCENT))
	_lobby_target_label = _big_label("First to 5", 44, Color.WHITE)
	left.add_child(_lobby_target_label)
	_lobby_rows = VBoxContainer.new()
	_lobby_rows.add_theme_constant_override("separation", 12)
	left.add_child(_lobby_rows)
	_lobby_status = _big_label("", 56, LOBBY_ACCENT)
	left.add_child(_lobby_status)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 16)
	columns.add_child(right)
	_lobby_qr = TextureRect.new()
	_lobby_qr.custom_minimum_size = Vector2(420, 420)
	_lobby_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lobby_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lobby_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(_lobby_qr)
	_lobby_url = _big_label("", 28, Color(0.8, 0.82, 0.88))
	right.add_child(_lobby_url)
	_how_to_play = _build_how_to_play()
	right.add_child(_how_to_play)

	_victory_panel = _full_screen_panel("VictoryPanel")
	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 32)
	_victory_panel.add_child(stack)
	_victory_title = _big_label("", 110, LOBBY_ACCENT)
	stack.add_child(_victory_title)
	_podium = HBoxContainer.new()
	_podium.alignment = BoxContainer.ALIGNMENT_CENTER
	_podium.add_theme_constant_override("separation", 40)
	stack.add_child(_podium)
	stack.add_child(_big_label("Press Rematch on your phone", 40, Color.WHITE))

func _full_screen_panel(node_name: String) -> Control:
	var panel := ColorRect.new()
	panel.name = node_name
	panel.color = LOBBY_BACKGROUND
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	_lobby_layer.add_child(panel)
	return panel

func _big_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	label.add_theme_constant_override("outline_size", maxi(4, font_size / 10))
	return label

# --- Stage title card (issue #120) -------------------------------------------
#
# The stage's name sweeps across the screen for about a second at every round
# start, below the modifier banner so the two never overlap.

## How long the stage name takes to sweep across. 0 turns it off.
@export var stage_title_sec: float = 1.1

var _title_layer: CanvasLayer
var _title_label: Label
var _title_tween: Tween

## The title card label, or null before any round has started.
func stage_title_label() -> Label:
	return _title_label

func _show_stage_title() -> void:
	if _current_stage == null or stage_title_sec <= 0.0:
		return
	if _title_label == null:
		_title_layer = CanvasLayer.new()
		_title_layer.name = "StageTitleLayer"
		_title_layer.layer = 10
		add_child(_title_layer)
		_title_label = Label.new()
		_title_label.name = "StageTitle"
		_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_label.add_theme_font_size_override("font_size", 80)
		_title_label.add_theme_color_override("font_color", Color.WHITE)
		_title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 1.0))
		_title_label.add_theme_constant_override("outline_size", 14)
		_title_layer.add_child(_title_label)
	_title_label.text = str(_current_stage.name).to_upper()
	_title_label.reset_size()
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var width: float = _title_label.get_minimum_size().x
	var middle: float = (screen.x - width) * 0.5
	_title_label.position = Vector2(screen.x, screen.y * 0.36)
	_title_label.visible = true
	if _title_tween != null:
		_title_tween.kill()
	_title_tween = create_tween()
	# Fast in, a slow drift through the middle where it can be read, fast out.
	_title_tween.tween_property(_title_label, "position:x", middle + 40.0, stage_title_sec * 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_title_tween.tween_property(_title_label, "position:x", middle - 40.0, stage_title_sec * 0.4)
	_title_tween.tween_property(_title_label, "position:x", -width - 20.0, stage_title_sec * 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_title_tween.tween_callback(func() -> void: _title_label.visible = false)

# --- Nicknames in play (issue #121, always on since #151) --------------------
#
# Every living player carries its phone's nickname ("P3" without one) above
# its head, in its colour -- whatever the round loop is doing, lobby or not.
# The tag clears the player's hat (issue #151), follows a colour change at
# once, and, when fighters bunch up, a tag that would cover another's is
# lifted clear of it so all eight stay readable.

## How far above the body's centre the name tag's bottom edge sits, at least.
const NAME_TAG_RISE: float = 40.0
## Gap between the top of a player's hat and its name tag's bottom edge.
const NAME_TAG_HAT_GAP: float = 6.0
## Gap kept between two tags stacked to clear each other.
const NAME_TAG_STACK_GAP: float = 2.0

var _round_number: int = 0
## The slots the current (or last) round spawned, in slot order.
var _in_round: Array[int] = []
var _name_tag_root: Node2D
var _name_tags: Array[Label] = []

## A slot's name tag, or null before the first frame has built them.
func name_tag(slot: int) -> Label:
	return _name_tags[slot] if slot >= 0 and slot < _name_tags.size() else null

func _alive_slots() -> Array[int]:
	var alive: Array[int] = []
	for slot in _players.size():
		if _players[slot] != null and _players[slot].alive:
			alive.append(slot)
	return alive

func _tick_name_tags() -> void:
	if _name_tag_root == null:
		_name_tag_root = Node2D.new()
		_name_tag_root.name = "NameTags"
		_name_tag_root.z_index = 50
		add_child(_name_tag_root)
		for slot in _players.size():
			var tag := Label.new()
			tag.name = "NameTag%d" % slot
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tag.add_theme_font_size_override("font_size", 22)
			tag.add_theme_color_override("font_color", _slot_color(slot))
			tag.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
			tag.add_theme_constant_override("outline_size", 6)
			tag.visible = false
			_name_tag_root.add_child(tag)
			_name_tags.append(tag)
	var placed: Array[Rect2] = []
	var shown_slots: Array[int] = []
	# Scaled up by however far the camera is zoomed out (issue #144), so a name
	# reads the same size on a large stage as on a normal one.
	var tag_scale: float = 1.0
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null and camera.zoom.x > 0.0:
		tag_scale = 1.0 / camera.zoom.x
	for slot in _players.size():
		var player: Variant = _players[slot]
		var tag: Label = _name_tags[slot]
		var shown: bool = player != null and player.alive and player.visible
		tag.visible = shown
		if not shown:
			continue
		var text: String = _slot_name(slot)
		if tag.text != text:
			tag.text = text
			tag.reset_size()
		var colour: Color = _slot_color(slot)
		if tag.get_theme_color("font_color") != colour:
			tag.add_theme_color_override("font_color", colour)
		var rise: float = NAME_TAG_RISE
		if player.has_method("hat_top"):
			rise = maxf(rise, player.hat_top() + NAME_TAG_HAT_GAP)
		tag.scale = Vector2(tag_scale, tag_scale)
		var size: Vector2 = tag.get_minimum_size() * tag_scale
		tag.position = player.global_position + Vector2(-size.x * 0.5, -rise - size.y)
		shown_slots.append(slot)
	# Lowest tag first; each one after it moves up past any tag it would cover.
	shown_slots.sort_custom(func(a: int, b: int) -> bool:
		return _name_tags[a].position.y > _name_tags[b].position.y)
	for slot: int in shown_slots:
		var tag: Label = _name_tags[slot]
		var rect := Rect2(tag.position, tag.get_minimum_size() * tag_scale)
		var moved: bool = true
		while moved:
			moved = false
			for other: Rect2 in placed:
				if rect.intersects(other):
					rect.position.y = other.position.y - rect.size.y - NAME_TAG_STACK_GAP * tag_scale
					moved = true
		tag.position = rect.position
		placed.append(rect)

# --- Host phone controls and how to play (issue #149) --------------------------
#
# The host phone's hidden menu (controller/index.html) sends Pause/Resume, End
# match and Kick player; ControllerServer lets only the host's requests through
# as `host_command`, and they are acted on here. Pause freezes the whole scene
# tree except ControllerServer (which must keep hearing the phones) and this
# node's pause banner; every deadline this node keeps in wall-clock msec is
# pushed back by however long the pause lasted, so nothing expires during it.
#
# The lobby screen -- the shared screen, not the phones -- carries a short
# how-to-play panel.

## The lines of the lobby's how-to-play panel.
const HOW_TO_PLAY_LINES: PackedStringArray = [
	"Drag on your phone to swing your pick - flick it fast to hit hard",
	"Hook the pick on a ledge and pull yourself up to climb",
	"Touch a weapon pickup to grab a new weapon",
	"Knock the others off the stage or into the rising lava - last one standing wins the round",
]
const HOW_TO_PLAY_WIDTH_PX: float = 560.0

var _how_to_play: Control
var _paused: bool = false
var _paused_at_msec: int = 0
var _pause_layer: CanvasLayer
var _pause_label: Label

## The lobby's how-to-play panel, or null before the lobby was ever shown.
func how_to_play_panel() -> Control:
	return _how_to_play

## Whether the host phone has the match paused.
func is_paused() -> bool:
	return _paused

## The PAUSED banner, or null before the first pause.
func pause_label() -> Label:
	return _pause_label

func _build_how_to_play() -> Control:
	var box := VBoxContainer.new()
	box.name = "HowToPlay"
	box.add_theme_constant_override("separation", 8)
	box.add_child(_big_label("HOW TO PLAY", 34, LOBBY_ACCENT))
	for line: String in HOW_TO_PLAY_LINES:
		var label: Label = _big_label(line, 24, Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = HOW_TO_PLAY_WIDTH_PX
		box.add_child(label)
	return box

## Whether a match is under way: what Pause and End match act on.
func _in_match() -> bool:
	return lobby_enabled and (_state == State.ROUND_ACTIVE or _state == State.ROUND_END or _state == State.WAITING)

func _on_host_command(cmd: String, slot: int) -> void:
	match cmd:
		"pause":
			if _in_match() and not _paused:
				_pause_match()
		"resume":
			if _paused:
				_resume_match()
		"end":
			if _in_match():
				_end_match()
		"kick":
			# Already out of the roster; out of the round too, without a death.
			if slot >= 0 and slot < _players.size() and _players[slot] != null and _players[slot].alive:
				_players[slot].leave_round()
			if lobby_enabled:
				_publish_lobby_state()

func _pause_match() -> void:
	_paused = true
	_paused_at_msec = Time.get_ticks_msec()
	_set_tree_paused(true)
	_show_pause_banner(true)
	_publish_lobby_state()

func _resume_match() -> void:
	var paused_for: int = Time.get_ticks_msec() - _paused_at_msec
	_pause_until_msec += paused_for
	_next_pickup_msec += paused_for
	_protected_until_msec += paused_for
	if _abandoned_since_msec >= 0:
		_abandoned_since_msec += paused_for
	_stats.shift(paused_for)
	_paused = false
	_set_tree_paused(false)
	_show_pause_banner(false)
	_publish_lobby_state()

## The host phone ended the match early: the round in progress is wound down
## with no winner and the room goes back to the lobby.
func _end_match() -> void:
	if _paused:
		_paused = false
		_set_tree_paused(false)
		_show_pause_banner(false)
	for player: Variant in _players:
		if player != null and player.alive:
			player.leave_round()
	_clear_pickups()
	_stop_kill_zone_rise()
	_end_round_modifier()
	_end_spawn_protection()
	_last_winner_slot = -1
	if _controller_server != null and _controller_server.has_method("clear_ready"):
		_controller_server.clear_ready()
	_enter_lobby()

func _set_tree_paused(on: bool) -> void:
	if is_inside_tree():
		get_tree().paused = on

func _show_pause_banner(on: bool) -> void:
	if _pause_label == null:
		if not on:
			return
		_pause_layer = CanvasLayer.new()
		_pause_layer.name = "PauseLayer"
		_pause_layer.layer = 12
		_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_pause_layer)
		var dim := ColorRect.new()
		dim.color = Color(0.0, 0.0, 0.0, 0.45)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pause_layer.add_child(dim)
		_pause_label = _big_label("PAUSED", 120, LOBBY_ACCENT)
		_pause_label.name = "PauseLabel"
		_pause_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_pause_layer.add_child(_pause_label)
	_pause_layer.visible = on
	_pause_label.visible = on

# --- Host changes, solo bots, lobby publishing (issue #165) --------------------
#
# The host phone dropping hands its menu to the next phone at once, even while
# paused: ControllerServer's `host_changed` republishes the lobby state, which
# otherwise only goes out from `_process` and so stops with the tree. Solo
# practice bots never make a ready room on their own. Mid-round the full lobby
# state is built only when a cheap key of what changes in a round (the roster,
# who is alive, the host, the round) has changed, and otherwise at most every
# LOBBY_REFRESH_MSEC, not every frame.

## Mid-round, the longest the phones wait for a change outside the key (a
## nickname, a colour).
const LOBBY_REFRESH_MSEC: int = 250
var _lobby_published_msec: int = 0
var _lobby_key: Array = []
## How many times the lobby state has been built, for the scenarios.
var lobby_state_builds: int = 0

func _watch_for_lobby_changes() -> void:
	if _controller_server != null and _controller_server.has_signal("host_changed"):
		_controller_server.connect("host_changed", _on_host_changed)

func _lobby_publish_due() -> bool:
	var key: Array = [_roster(), _alive_slots(), _host_slot(), _round_number]
	if key != _lobby_key:
		_lobby_key = key
		return true
	return Time.get_ticks_msec() - _lobby_published_msec >= LOBBY_REFRESH_MSEC

func _on_host_changed(_slot: int) -> void:
	if lobby_enabled:
		_publish_lobby_state()

## Whether `roster` is only Solo practice bots waiting for a human: no phone
## in it is connected, and the bots came from the host's Solo button, not
## from `--bots=N`.
func _bots_waiting_for_a_human(roster: Array[int]) -> bool:
	var director: Variant = _controller_server.get("bot_director") if _controller_server != null else null
	if director == null or not director.has_method("needs_a_human") or not director.needs_a_human():
		return false
	for slot: int in roster:
		if not _controller_server.is_virtual(slot) and _controller_server.slot_has_controller(slot):
			return false
	return true

# --- Kill feed, KO credit and match awards (issue #148) ------------------------
#
# `MatchStats.gd` keeps the match's numbers and decides who gets each KO: the
# last player to hit the victim within 3 s, otherwise a self-KO. `KillFeed.gd`
# (the HUD node at `kill_feed_path`) shows each KO top right and a banner for
# the big moments. The victory screen gets up to three awards under the podium.

const MatchStatsScript := preload("res://scripts/MatchStats.gd")
const KillFeedScript := preload("res://scripts/KillFeed.gd")

## The HUD's KillFeed node (scenes/Main.tscn). Empty: KOs are still counted,
## just not shown.
@export var kill_feed_path: NodePath

var _stats: RefCounted = MatchStatsScript.new()
## Eliminations not yet credited, as [slot, msec]: `Player.eliminate()` emits
## `eliminated` before the lethal strike's `strike_landed`, so crediting waits
## for the end of the frame (or the next round-end check) to see that strike.
var _pending_kos: Array = []

func match_stats() -> RefCounted:
	return _stats

func kill_feed() -> Control:
	return get_node_or_null(kill_feed_path) as Control

## The victory screen's awards row, or null before any.
func awards_row() -> Control:
	return _podium.get_parent().get_node_or_null("Awards") as Control if _podium != null else null

func _ko_record_hit(victim: Node, amount: float, attacker_slot: int) -> void:
	_stats.record_hit(attacker_slot, _players.find(victim), amount, Time.get_ticks_msec())

func _on_ko_eliminated(slot: int) -> void:
	if _pending_kos.is_empty():
		_flush_kos.call_deferred()
	_pending_kos.append([slot, Time.get_ticks_msec()])

func _flush_kos() -> void:
	var pending: Array = _pending_kos
	_pending_kos = []
	var feed: Control = kill_feed()
	for entry: Array in pending:
		var ko: Dictionary = _stats.record_elimination(entry[0], entry[1])
		if feed == null:
			continue
		var victim: int = ko["victim"]
		var killer: int = ko["killer"]
		if killer == -1:
			feed.push_ko("", Color.WHITE, _slot_name(victim), _slot_color(victim))
			continue
		feed.push_ko(_slot_name(killer), _slot_color(killer), _slot_name(victim), _slot_color(victim))
		var streak: int = ko["streak"]
		if streak >= 2:
			feed.show_banner(["DOUBLE KO!", "TRIPLE KO!"][streak - 2] if streak <= 3 else "MULTI KO!", _slot_name(killer), _slot_color(killer))
		elif ko["first_blood"]:
			feed.show_banner("FIRST BLOOD", _slot_name(killer), _slot_color(killer))

func _ko_match_started() -> void:
	_stats.begin_match()
	_pending_kos.clear()
	var feed: Control = kill_feed()
	if feed != null:
		feed.clear()

## A fresh phone (or bot) claimed `slot` (issue #161). The slot may be one a
## drop-out's expired claim or a kick freed mid-match: the newcomer starts on
## no points and none of the old occupant's KOs, deaths or awards.
func _on_slot_claimed_fresh(slot: int) -> void:
	if slot < 0 or slot >= _scores.size():
		return
	_scores[slot] = 0
	_stats.forget_slot(slot)
	_pending_kos = _pending_kos.filter(func(entry: Array) -> bool: return entry[0] != slot)
	_update_score_label()

func _ko_round_started() -> void:
	_pending_kos.clear()
	_stats.begin_round(_in_round, Time.get_ticks_msec())

## A round won by the last of three or more is a big moment; one of two
## winning speaks for itself on the scoreboard.
func _ko_round_ended(winner_slot: int) -> void:
	_stats.end_round(Time.get_ticks_msec())
	var feed: Control = kill_feed()
	if feed != null and winner_slot != -1 and _in_round.size() >= 3:
		feed.show_banner("LAST ONE STANDING", _slot_name(winner_slot), _slot_color(winner_slot))

func _refresh_awards(slots: Array[int]) -> void:
	var stack: Node = _podium.get_parent()
	var old: Node = stack.get_node_or_null("Awards")
	if old != null:
		stack.remove_child(old)
		old.queue_free()
	var awards: Array[Dictionary] = _stats.awards(slots)
	if awards.is_empty():
		return
	var row: HBoxContainer = KillFeedScript.award_cards(awards, _slot_name, _slot_color)
	stack.add_child(row)
	stack.move_child(row, _podium.get_index() + 1)
